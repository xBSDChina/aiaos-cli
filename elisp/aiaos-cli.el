;;; aiaos-cli.el --- AIAOS-CLI Emacs Frontend -*- lexical-binding: t; -*-

;; Copyright (C) 2026 SenseTime / AIAOS Project
;; Author: AIAOS Project
;; Version: 1.0.0
;; Keywords: tools, process, aiaos
;; Package-Requires: ((emacs "29.0"))

;; This file is the Emacs frontend for aiaos-cli.
;; It follows the AIAOS-CLI paradigm defined in ~/aiaos-cli_design.md:
;;   - Elisp as primary, external process as auxiliary
;;   - Async non-blocking IO
;;   - Buffer as interface (not popup)
;;   - C-c a key prefix
;;
;; Load path:
;;   (add-to-list 'load-path "/path/to/aiaos-cli/elisp")
;;   (require 'aiaos-cli)
;;   (aiaos-cli-init)

;;; Commentary:

;; The frontend exposes:
;;   * aiaos-cli-run             - run an arbitrary aiaos-cli subcommand
;;   * aiaos-cli-session-*       - session commands
;;   * aiaos-cli-context-*       - context commands
;;   * aiaos-cli-skill-*         - skill commands
;;   * aiaos-cli-agent-chat      - agent chat (interactive)
;;   * aiaos-cli-doctor          - environment doctor
;;   * aiaos-cli-log-tail        - tail logs in a dedicated buffer
;;   * aiaos-cli-mode            - major mode for result buffers
;;   * aiaos-cli-agent-mode      - major mode for chat buffer

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'url)

;; TUI 模块集成
(require 'aiaos-cli-core)
(require 'aiaos-cli-state)
(require 'aiaos-cli-context)
(require 'aiaos-cli-lifecycle)
(require 'aiaos-cli-component)
(require 'aiaos-cli-theme)
(require 'aiaos-cli-components)
(require 'aiaos-cli-router)
(require 'aiaos-cli-app)

(defgroup aiaos-cli nil
  "AIAOS-CLI Emacs frontend."
  :group 'tools
  :prefix "aiaos-cli-")

(defcustom aiaos-cli-bin "aiaos-cli"
  "Path to the aiaos-cli executable."
  :type 'file
  :group 'aiaos-cli)

(defcustom aiaos-cli-default-format "json"
  "Default output format for aiaos-cli invocations."
  :type '(choice (const json) (const table) (const raw))
  :group 'aiaos-cli)

(defcustom aiaos-cli-async-timeout 30
  "Timeout (seconds) for async aiaos-cli invocations."
  :type 'integer
  :group 'aiaos-cli)

(defcustom aiaos-cli-key-prefix "C-c a"
  "Key prefix for aiaos-cli commands."
  :type 'string
  :group 'aiaos-cli)

(defcustom aiaos-cli-result-buffer-name "*aiaos-cli*"
  "Name of the result buffer."
  :type 'string
  :group 'aiaos-cli)

(defcustom aiaos-cli-chat-buffer-name "*aiaos-cli-agent*"
  "Name of the agent chat buffer."
  :type 'string
  :group 'aiaos-cli)

(defcustom aiaos-cli-skills-dir
  (expand-file-name "~/aiaos/aiaos-cli/skills")
  "Directory containing aiaos-cli skills (each skill is a subdirectory).

Override if you install skills elsewhere.  Used by
`aiaos-cli-skill-load' to locate `skill.yaml', `commands/*.el' and
`hooks/*.el'."
  :type 'directory
  :group 'aiaos-cli)

(defvar aiaos-cli--version nil "Cached aiaos-cli version.")
(defvar aiaos-cli--expected-version "1.0.0" "Version this frontend expects from the binary.")
(defvar aiaos-cli--inited nil "Non-nil after aiaos-cli-init.")
(defvar aiaos-cli--loaded-skills nil
  "R1210: list of skill names loaded via aiaos-cli-skill-load-all.")
(defvar aiaos-cli--skill-cache nil "Cache of installed skills.")
(defvar aiaos-cli--keymap nil "R1320: keymap bound in aiaos-cli-init.")

(defun aiaos-cli--expand-env (path)
  "Expand leading ~ in PATH."
  (if (string-prefix-p "~/" path)
      (expand-file-name path)
    path))

(defun aiaos-cli--resolve-bin ()
  "Return absolute path to aiaos-cli binary, or nil if not found.

R1404: 修复声称搜索 3 个路径但实际只查 2 个的问题。
现在真正按顺序检查：1) aiaos-cli-bin 变量  2) PATH 中 aiaos-cli
3) 默认安装路径 ~/aiaos/aiaos-cli/bin/aiaos-cli。

R2401: 修复 return-from 缺少 cl-block 导致 void-variable 错误。
使用 cond 替代 return-from，避免块标签冲突。"
  (let ((bin (aiaos-cli--expand-env aiaos-cli-bin)))
    (cond ((file-executable-p bin)
           bin)
          ((executable-find "aiaos-cli")
           (let ((found (executable-find "aiaos-cli")))
             (setq aiaos-cli-bin found)
             found))
          ((file-executable-p (expand-file-name "~/aiaos/aiaos-cli/bin/aiaos-cli"))
           (let ((default-bin (expand-file-name "~/aiaos/aiaos-cli/bin/aiaos-cli")))
             (setq aiaos-cli-bin default-bin)
             default-bin))
          (t nil))))

(defun aiaos-cli--assert-binary ()
  "Return the aiaos-cli binary path or signal an error.

R780: original error only said set aiaos-cli-bin or install aiaos-cli,
giving the user no clue what was actually searched. Now report all
three lookup paths plus the PATH value, so the user can act
immediately. (Message avoids paren characters inside the string
literal to sidestep any reader ambiguity.)"
  (let ((bin (aiaos-cli--resolve-bin)))
    (unless bin
      (user-error
       (concat "aiaos-cli binary not found. Searched: "
               "1 aiaos-cli-bin=" (or aiaos-cli-bin "<nil>")
               " 2 PATH=" (or (executable-find "aiaos-cli") "<nil>")
               " 3 ~/aiaos/aiaos-cli/bin/aiaos-cli. "
               "Fix by setq aiaos-cli-bin or export PATH.")))
    bin))

(defun aiaos-cli--coerce-string (arg)
  "Coerce ARG to a string. Handles both strings and symbols.

R2401: Emacs 的 string 函数对符号的处理在不同版本行为不一致，
使用 symbol-name 显式处理符号类型，保证跨版本兼容。"
  (cond ((stringp arg) arg)
        ((symbolp arg) (symbol-name arg))
        (t (format "%s" arg))))

(defun aiaos-cli--build-cmd (domain action &rest args)
  "Build the aiaos-cli command vector.

DOMAIN and ACTION are the CLI domain and action (e.g. \"session\" \"new\").
They can be strings or symbols; symbols are coerced to strings.
ARGS is a flat list of additional CLI args/options."
  (let ((bin (aiaos-cli--assert-binary)))
    (append (list bin (aiaos-cli--coerce-string domain) (aiaos-cli--coerce-string action)
                  (format "--format=%s" aiaos-cli-default-format))
            args)))

(defun aiaos-cli--call-sync (cmd)
  "Invoke CMD synchronously, return (status . stdout-string).

CMD is a list of strings.  Errors are signaled with `user-error'."
  (let ((buf (get-buffer-create (format "*aiaos-cli-tmp-%s*" (random 1000000))))
        status)
    (unwind-protect
        (progn
          (setq status (apply #'call-process (car cmd) nil buf nil (cdr cmd)))
          (cons status (with-current-buffer buf (buffer-string))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(defun aiaos-cli--call-async (cmd callback)
  "Invoke CMD asynchronously; call CALLBACK with (status stdout stderr).

CMD is a list of strings.  CALLBACK receives three args.
R621 修复: 之前用 start-process 时 stderr 被丢弃，err-buf 永远为空。
现在用 make-process + connection-type t + connection-function 真正分离
stdout/stderr，让调用方（如 aiaos-cli-run）的失败分支能拿到 stderr。
R2600 修复 (TD-003): 此前 aiaos-cli-async-timeout 变量已定义但从未使用，
进程可能永远挂起。现在增加超时保护：超时后 kill 进程，
以 status=124（类似 GNU coreutils timeout 的约定）调用 callback。"
  (let ((process-connection-type nil)
        out-buf err-buf proc timer killed)
    (setq out-buf (get-buffer-create (format "*aiaos-cli-out-%s*" (random 1000000)))
          err-buf (get-buffer-create (format "*aiaos-cli-err-%s*" (random 1000000))))
    (setq proc (make-process
                :name "aiaos-cli"
                :buffer out-buf
                :noquery t
                :stderr err-buf
                :command cmd
                :sentinel
                (lambda (p _event)
                  (when (memq (process-status p) '(signal exit))
                    (cancel-timer timer)
                    (let ((status (process-exit-status p))
                          (out (with-current-buffer out-buf (buffer-string)))
                          (err (with-current-buffer err-buf (buffer-string))))
                      (kill-buffer out-buf)
                      ;; R621: unwind-protect 兜底，确保 callback 抛异常时 err-buf 不泄漏。
                      (unwind-protect
                          (funcall callback status out err)
                        (when (buffer-live-p err-buf)
                        (kill-buffer err-buf))))))))
    ;; R2600: 超时保护 — 启动一个计时器，超时后 kill 进程并回调 status=124。
    (when (and (natnump aiaos-cli-async-timeout) (> aiaos-cli-async-timeout 0))
      (setq timer
            (run-with-timer aiaos-cli-async-timeout nil
              (lambda ()
                (when (and (process-live-p proc) (not killed))
                  (setq killed t)
                  (let ((status 124)
                        (out (with-current-buffer out-buf (buffer-string)))
                        (err (format "Timeout: process killed after %d seconds"
                                     aiaos-cli-async-timeout)))
                    (kill-buffer out-buf)
                    (kill-process proc)
                    (unwind-protect
                        (funcall callback status out err)
                      (when (buffer-live-p err-buf)
                        (kill-buffer err-buf)))))))))
    proc))

(defun aiaos-cli--parse-json (str)
  "Parse JSON string STR, returning nil on failure.

JSON objects are parsed as hash tables so callers can use
json-object-keys and gethash.

R780: original used an Emacs 30+ only JSON reader, conflicting
with the file header Package-Requires emacs 29 declaration. Under
Emacs 29 it raised void-function. Switched to json-read + temp
buffer, which works on both 29 and 30. Also the original error
handler silently swallowed ALL exceptions; now we catch json-error
(the parent of json-scanner-error and json-syntax-error) so any
JSON parse failure returns nil, while genuinely unexpected errors
(e.g. buffer creation failure) still propagate. The non-string
input guard is also explicit now."
  (unless (stringp str)
    (user-error "aiaos-cli--parse-json: expected string, got %s" (type-of str)))
  (let ((json-false :json-false)
        (json-object-type 'hash-table))
    (condition-case nil
        (with-temp-buffer
          (insert str)
          (goto-char (point-min))
          (json-read))
      (json-error nil)
      (end-of-buffer nil))))

(defun aiaos-cli--format-result (status output &optional title)
  "Format STATUS and OUTPUT into a human-readable string.

If OUTPUT is valid JSON, pretty-print key fields; otherwise echo raw."
  (let ((json (aiaos-cli--parse-json output)))
    (if json
        (let ((lines (list (format "── %s [exit=%d] ──" (or title "aiaos-cli") status) "")))
          (dolist (kv (hash-table-keys json))
            (let ((v (gethash kv json)))
              (push (format "%-14s %s" kv (aiaos-cli--stringify v)) lines)))
          (string-join (nreverse lines) "\n"))
      (format "── %s [exit=%d] ──\n%s" (or title "aiaos-cli") status output))))

(defun aiaos-cli--stringify (v)
  "Stringify V for display, truncating long strings."
  (cond
   ((null v) "null")
   ((listp v) (format "[%d items]" (length v)))
   ((hash-table-p v) (format "{%d keys}" (hash-table-count v)))
   ((stringp v) (if (> (length v) 200)
                    (concat (substring v 0 200) "…")
                  v))
   (t (format "%s" v))))

(define-derived-mode aiaos-cli-mode special-mode "aiaos-cli"
  "Major mode for aiaos-cli result buffers."
  (setq-local read-only t)
  (setq-local truncate-lines t))

(defun aiaos-cli--show-result (title output &optional status)
  "Show TITLE and OUTPUT in the aiaos-cli result buffer.

STATUS optional exit code for display. R2201: 之前硬编码 status=0，
导致 help/version 等命令即使失败也显示 exit=0。现在使用真实 status。
R1324: Use aiaos-cli--format-result to render structured output
instead of dumping raw text, making previously dead code live."
  (let* ((exit-code (or status 0))
         (formatted (aiaos-cli--format-result exit-code output title)))
    (with-current-buffer (get-buffer-create aiaos-cli-result-buffer-name)
      (erase-buffer)
      (insert formatted "\n")
      (aiaos-cli-mode)
      (goto-char (point-min)))
    (switch-to-buffer aiaos-cli-result-buffer-name)))

(defun aiaos-cli-init (&optional load-skills)
  "Initialize the aiaos-cli frontend: bind keys, cache version.

R1210: 新增可选 LOAD-SKILLS 参数。为真时自动发现并加载所有未 disabled
的技能（调用 aiaos-cli-skill-load-all），修复 TD-001：此前 init 后
直接调用技能函数会得到 void-function，必须显式 (aiaos-cli-skill-run ...)
才能间接触发加载。默认 nil 保持向后兼容。"
  (interactive "P")
  (let ((load-skills-flag (if load-skills t nil))
        (bin (aiaos-cli--resolve-bin))
        (map (make-sparse-keymap)))
    ;; Bind C-c a prefix
      (define-key map "h" #'aiaos-cli-help)
      (define-key map "v" #'aiaos-cli-version)
      ;; R2026: Session submenu
      (let ((session-map (make-sparse-keymap)))
        (define-key session-map "l" #'aiaos-cli-session-list)
        (define-key session-map "n" #'aiaos-cli-session-new)
        (define-key session-map "s" #'aiaos-cli-session-show)
        (define-key session-map "w" #'aiaos-cli-session-switch)
        (define-key session-map "a" #'aiaos-cli-session-archive)
        (define-key session-map "d" #'aiaos-cli-session-delete)
        (define-key session-map "c" #'aiaos-cli-session-current)
        (define-key map "s" session-map))
      ;; R2026: Context submenu
      (let ((context-map (make-sparse-keymap)))
        (define-key context-map "s" #'aiaos-cli-context-show)
        (define-key context-map "v" #'aiaos-cli-context-save)
        (define-key context-map "l" #'aiaos-cli-context-load)
        (define-key context-map "c" #'aiaos-cli-context-clear)
        (define-key context-map "e" #'aiaos-cli-context-export)
        (define-key map "c" context-map))
      ;; R1130: skill 子菜单。此前 k 直连 skill-list，但 validate/deps/
      ;; search/enable/disable 无入口。改为 k 进入 skill 子 keymap，
      ;; 各动作以单字符选择，避免与 d/s/v 等已有绑定冲突。
      (let ((skill-map (make-sparse-keymap)))
        (define-key skill-map "l" #'aiaos-cli-skill-list)
        (define-key skill-map "i" #'aiaos-cli-skill-info)
        (define-key skill-map "v" #'aiaos-cli-skill-validate)
        (define-key skill-map "d" #'aiaos-cli-skill-deps)
        (define-key skill-map "s" #'aiaos-cli-skill-search)
        (define-key skill-map "e" #'aiaos-cli-skill-enable)
        (define-key skill-map "D" #'aiaos-cli-skill-disable)
        (define-key skill-map "L" #'aiaos-cli-skill-load)
        (define-key skill-map "r" #'aiaos-cli-skill-run)
        (define-key map "k" skill-map))
      ;; R2026: Config submenu
      (let ((config-map (make-sparse-keymap)))
        (define-key config-map "l" #'aiaos-cli-config-list)
        (define-key config-map "g" #'aiaos-cli-config-get)
        (define-key config-map "s" #'aiaos-cli-config-set)
        (define-key config-map "e" #'aiaos-cli-config-edit)
        (define-key config-map "v" #'aiaos-cli-config-validate)
        (define-key config-map "m" #'aiaos-cli-config-migrate)
        (define-key config-map "r" #'aiaos-cli-config-reset)
        (define-key map "g" config-map))
      ;; R2026: Project submenu
      (let ((project-map (make-sparse-keymap)))
        (define-key project-map "i" #'aiaos-cli-project-init)
        (define-key project-map "s" #'aiaos-cli-project-sync)
        (define-key project-map "b" #'aiaos-cli-project-build)
        (define-key project-map "d" #'aiaos-cli-project-deploy)
        (define-key project-map "t" #'aiaos-cli-project-status)
        (define-key map "p" project-map))
      ;; R2026: Agent submenu
      (let ((agent-map (make-sparse-keymap)))
        (define-key agent-map "c" #'aiaos-cli-agent-chat)
        (define-key agent-map "d" #'aiaos-cli-agent-delegate)
        (define-key agent-map "t" #'aiaos-cli-agent-tool)
        (define-key agent-map "h" #'aiaos-cli-agent-history)
        (define-key map "a" agent-map))
      ;; R2026: Log submenu
      (let ((log-map (make-sparse-keymap)))
        (define-key log-map "t" #'aiaos-cli-log-tail)
        (define-key log-map "s" #'aiaos-cli-log-search)
        (define-key log-map "e" #'aiaos-cli-log-export)
        (define-key log-map "a" #'aiaos-cli-log-analyze)
        (define-key log-map "l" #'aiaos-cli-log-list)
        (define-key map "l" log-map))
      ;; R2026: Doctor submenu
      (let ((doctor-map (make-sparse-keymap)))
        (define-key doctor-map "c" #'aiaos-cli-doctor)
        (define-key doctor-map "f" #'aiaos-cli-doctor-fix)
        (define-key doctor-map "r" #'aiaos-cli-doctor-report)
        (define-key map "d" doctor-map))
      (define-key map "l" #'aiaos-cli-log-tail)
      (define-key map "r" #'aiaos-cli-run)
      ;; R1325: TUI application entry (C-c a t)
      (define-key map "t" #'aiaos-cli-app-start)
      (define-key (current-global-map) (read-kbd-macro aiaos-cli-key-prefix) map)
    ;; R1130: 保存 keymap 供测试/调试使用
    (setq aiaos-cli--keymap map)
    ;; Cache version (if binary found)
    (when bin
      (condition-case _
          (let ((res (aiaos-cli--call-sync (list bin "--version"))))
            (setq aiaos-cli--version (string-trim (cdr res))))
        (error nil)))
    (setq aiaos-cli--inited t)
    ;; TUI Module Integration (R1330)
    ;; Load TUI modules if available (optional, for enhanced TUI features)
    (when (file-exists-p (expand-file-name "aiaos-cli-app.el" load-path))
      (condition-case err
          (load "aiaos-cli-state")
        (message "aiaos-cli: warning - state module not available: %s" err))
      (condition-case err
          (load "aiaos-cli-context")
        (message "aiaos-cli: warning - context module not available: %s" err))
      (condition-case err
          (load "aiaos-cli-lifecycle")
        (message "aiaos-cli: warning - lifecycle module not available: %s" err))
      (condition-case err
          (load "aiaos-cli-component")
        (message "aiaos-cli: warning - component module not available: %s" err))
      (condition-case err
          (load "aiaos-cli-theme")
        (message "aiaos-cli: warning - theme module not available: %s" err))
      (condition-case err
          (load "aiaos-cli-router")
        (message "aiaos-cli: warning - router module not available: %s" err))
      (condition-case err
          (load "aiaos-cli-components")
        (message "aiaos-cli: warning - components module not available: %s" err))
      (condition-case err
          (load "aiaos-cli-app")
        (message "aiaos-cli: warning - app module not available: %s" err))
      (message "aiaos-cli: TUI modules loaded successfully"))
  ;; R1210: 可选自动加载已启用技能
  (when load-skills-flag
    (condition-case err
        (aiaos-cli-skill-load-all)
      (error (message "aiaos-cli: skill-load-all failed: %s" err)))
    (message "aiaos-cli initialized (version %s%s)"
             (or aiaos-cli--version "?")
             (if load-skills-flag
                 (format ", skills=%s" aiaos-cli--loaded-skills)
               "")))))

;;;###autoload
(defun aiaos-cli-help ()
  "Show aiaos-cli help."
  (interactive)
  (let ((cmd (list (aiaos-cli--assert-binary) "--help")))
    (aiaos-cli--call-async cmd
      (lambda (status out _err)
        (aiaos-cli--show-result "help" out status)))))

;;;###autoload
(defun aiaos-cli-version ()
  "Show aiaos-cli version."
  (interactive)
  (let ((cmd (list (aiaos-cli--assert-binary) "--version")))
    (aiaos-cli--call-async cmd
      (lambda (_status out _err)
        (message "aiaos-cli %s" (string-trim out))))))

;;;###autoload
(defun aiaos-cli-doctor ()
  "Run environment doctor."
  (interactive)
  (aiaos-cli-run "doctor" "check"))

(defun aiaos-cli-run (domain action &rest args)
  "Run aiaos-cli DOMAIN ACTION with ARGS and show result.

R780: 原实现失败分支只 message，用户必须盯 echo area 看错误，结果 buffer
完全没显示。改为失败时也切到结果 buffer，把 status 和 stderr 都展示。
另外 --build-cmd 已注入 --format，如果调用方再传 --format 会重复，去重。"
  (interactive (list
                (completing-read "Domain: "
                  '("session" "context" "skill" "agent" "project" "config" "doctor" "log"))
                (read-string "Action (empty for help): ")))
  (let ((cmd (apply (quote aiaos-cli--build-cmd) (cons domain (cons action args))))
        seen-format)
    (setq cmd (cl-remove-if
                (lambda (x)
                  (and (string-prefix-p "--format=" x)
                       (if seen-format t (progn (setq seen-format t) nil))))
                cmd))
    (message "Running: %s" (mapconcat #'identity cmd " "))
    (aiaos-cli--call-async cmd
      (lambda (status out err)
        (if (= status 0)
            (aiaos-cli--show-result (format "%s %s" domain action) out status)
          (with-current-buffer (get-buffer-create aiaos-cli-result-buffer-name)
            (erase-buffer)
            (insert (propertize "=== AIAOS Error ===\n\n"
                                'face 'font-lock-warning-face))
            (insert (format "Command: %s %s\nExit status: %d\n\n"
                            domain action status))
            (insert err)
            (insert "\n")
            (aiaos-cli-mode)
            (goto-char (point-min)))
          (switch-to-buffer aiaos-cli-result-buffer-name))))))

;;;###autoload
(defun aiaos-cli-session-new (name)
  "Create a new aiaos session with NAME."
  (interactive "sSession name: ")
  (aiaos-cli-run "session" "new" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-session-list ()
  "List aiaos sessions."
  (interactive)
  (aiaos-cli-run "session" "list"))

;;;###autoload
(defun aiaos-cli-session-current ()
  "Show current aiaos session."
  (interactive)
  (aiaos-cli-run "session" "current"))

;;;###autoload
(defun aiaos-cli-context-show ()
  "Show current aiaos context."
  (interactive)
  (aiaos-cli-run "context" "show"))

;;;###autoload
(defun aiaos-cli-context-save ()
  "Save current context."
  (interactive)
  (aiaos-cli-run "context" "save"))

;;;###autoload
(defun aiaos-cli-skill-list ()
  "List installed aiaos skills."
  (interactive)
  (aiaos-cli-run "skill" "list"))

;;;###autoload
(defun aiaos-cli-skill-info (name)
  "Show info for skill NAME."
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "info" (format "--name=%s" name)))

;;
;; 补齐 Shell 端已实现但 Elisp 端缺失的入口：validate / deps / search /
;; enable / disable。此前用户必须敲 `aiaos-cli-run' 或命令行才能触达这些
;; 子命令，违反设计文档 §2.1 "Elisp as primary" 范式。
;; 命名沿用 aiaos-cli-skill-<verb> 惯例，与 skill-list/skill-info 并列。
;;;###autoload
(defun aiaos-cli-skill-validate (name)
  "Validate skill NAME's skill.yaml metadata and command entries."
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "validate" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-skill-deps (name)
  "Show dependency graph of skill NAME (recursively resolved).

R1130: Shell 端 skill_deps 已支持 --format json 与循环检测，前端仅做
薄封装。返回结果 buffer 展示 JSON 依赖树。"
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "deps" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-skill-search (query)
  "Search installed skills by QUERY (substring match on name/description).

R1130: 后端 skill_search 当前为 substring 过滤；若 QUERY 为空则等价于
`aiaos-cli-skill-list'."
  (interactive "sSearch query: ")
  (aiaos-cli-run "skill" "search" query))

;;;###autoload
(defun aiaos-cli-skill-enable (name)
  "Enable skill NAME by clearing its `disabled' flag in skill.yaml."
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "enable" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-skill-disable (name)
  "Disable skill NAME by setting `disabled: true' in skill.yaml."
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "disable" (format "--name=%s" name)))

;; R1318 (TD-031): 轻量 skill.yaml 顶层标量解析。
;; 仅提取顶层 `key: value' 形式的标量字段（name/version/description/author/
;; license），跳过嵌套结构（commands/hooks/dependencies 等带子键的块）。
;; 不引入外部 YAML 依赖，满足前端离线加载场景。
(defun aiaos-cli--parse-skill-yaml-scalar (yaml-path)
  "Parse top-level scalar fields of YAML file YAML-PATH into a hash-table.

Returns a hash-table mapping field names to string values.
Only top-level key:value scalars are captured; nested blocks (commands,
hooks, dependencies ...) are ignored.  Used by aiaos-cli-skill-load to
populate aiaos-cli--skill-cache so single-skill loading matches
aiaos-cli-skill-load-all (TD-031).

R1318: implemented with pure string ops (string-match on a colon,
split-string, substring) instead of complex regex character classes,
to avoid Elisp read-syntax pitfalls with quoted regexes."
  (let ((table (make-hash-table :test 'equal))
        line colon key value)
    (with-temp-buffer
      (insert-file-contents yaml-path)
      (goto-char (point-min))
      (while (not (eolp))
        (setq line (buffer-substring (point) (line-end-position)))
        ;; 跳过空行、注释行、缩进（嵌套）行
        (when (and (not (string-prefix-p " " line))
                   (not (string-prefix-p "\t" line))
                   (not (string-prefix-p "#" line))
                   (not (string= line "")))
          (setq colon (string-match ":" line))
          (when colon
            (setq key (substring line 0 colon)
                  value (substring line (1+ colon)))
            (setq value (replace-regexp-in-string "^ +" "" value))
            (setq value (replace-regexp-in-string " +$" "" value))
            ;; 去首尾引号
            (when (and (> (length value) 1)
                       (member (substring value 0 1) '("\"" "'")))
              (setq value (substring value 1)))
            (when (and (> (length value) 0)
                       (member (substring value (- (length value) 1))
                               '("\"" "'")))
              (setq value (substring value 0 (- (length value) 1))))
            (puthash key value table)))
        (forward-line 1)))
    table))

(defun aiaos-cli-skill-load (name)
  "Load skill NAME's commands and hooks so their functions become available.

This is the fix for the long-standing gap noted in the design doc: after
`(aiaos-cli-init)`, calling `aiaos-cli-skill-<name>/<cmd>` raised
`void-function` because the skill's `.el` files were never loaded.

Reads `skills/<name>/skill.yaml`, loads each `commands/*.el` and each
`hooks/*.el`, and returns the list of loaded file paths.  Errors are
signaled with `user-error`."
  (interactive "sSkill name: ")
  (unless (stringp name)
    (user-error "aiaos-cli-skill-load: NAME must be a string"))
  (unless aiaos-cli--inited
    (aiaos-cli-init))
  (let ((skill-yaml (expand-file-name (concat name "/skill.yaml")
                                       aiaos-cli-skills-dir)))
    (unless (file-exists-p skill-yaml)
      (user-error "aiaos-cli-skill-load: skill not found: %s (%s)"
                  name skill-yaml))
    (let ((loaded '()))
      (mapc (lambda (sub)
              (let ((dir (expand-file-name (concat name "/" sub)
                                            aiaos-cli-skills-dir)))
                (when (file-directory-p dir)
                  (mapc (lambda (f)
                          (load f 'noerror)
                          (push f loaded))
                        (directory-files dir t "\.el$")))))
            '("commands" "hooks"))
      ;; R1318 (TD-031): 单独调用 skill-load 时也同步更新 skill-cache，
      ;; 与 skill-load-all 行为一致。此前仅 load-all 填充 cache，单独
      ;; skill-load 后 cache 缺失该技能，语义不一致。
      (unless aiaos-cli--skill-cache
        (setq aiaos-cli--skill-cache (make-hash-table :test 'equal)))
      (puthash name (aiaos-cli--parse-skill-yaml-scalar skill-yaml)
               aiaos-cli--skill-cache)
      (message "aiaos-cli: loaded %d file(s) for skill %s"
               (length loaded) name)
      loaded)))

;; R1100: alist->plist 桥接（JSON 解析产物 -> plist）。
;; 此前内嵌于 core/skill.sh 的 Python 生成脚本中，无法单元测试；现迁移至前端，
;; 生成脚本依赖 `-l aiaos-cli` 已加载本定义，不再重复 defun。
(defun aiaos-cli--alist-to-plist (alist)
  "Convert ALIST (the product of JSON object parsing) to a plist with keyword keys."
  (mapcan (lambda (x) (list (intern (format ":%s" (car x))) (cdr x)))
          alist))

(defun aiaos-cli-skill-run (name command args opts)
  "Run skill command COMMAND of skill NAME with ARGS/OPTS plists.

Thin frontend wrapper around aiaos-cli-skill-load plus the generated
skill function.  Returns the plist result."
  (interactive "sSkill name: sCommand name: ")
  (aiaos-cli-skill-load name)
  (let ((fn (intern (format "aiaos-cli-skill-%s/%s"
                            name command))))
    (unless (fboundp fn)
      (user-error "aiaos-cli-skill-run: function %s not defined after load" fn))
    (funcall fn (or args '()) (or opts '()))))

(defun aiaos-cli-skill-load-all (&optional verbose)
  "R1210: 加载所有未 disabled 的技能（TD-001 修复）。

调用 `aiaos-cli skill list --format json' 获取技能清单，过滤掉
`disabled: true' 的条目，逐个调用 `aiaos-cli-skill-load'。返回本次新
加载的技能名列表，并把累计已加载名写入 `aiaos-cli--loaded-skills'。

VERBOSE 为真时逐个 message 提示。已加载过的技能跳过（幂等）。"
  (interactive "P")
  (require 'json)
  ;; R1317: 修复 TD-025 —— 原 let 里 res/skills 的初始化分别引用了 bin/res，
  ;; 但 let 绑定是同时初始化的，被引用的变量此时还未定义，触发 void-variable。
  ;; 改为嵌套 let：先解析 bin，再调用 call-sync，再解析 JSON，最后再进入
  ;; 业务逻辑 let。
  (let ((bin (aiaos-cli--assert-binary)))
    (let ((res (aiaos-cli--call-sync
                (list bin "skill" "list" "--format" "json"))))
      (let ((skills (aiaos-cli--parse-json (cdr res)))
            (loaded aiaos-cli--loaded-skills)
            (newly-loaded nil))
        ;; R1317: aiaos-cli--parse-json 返回 vector（Emacs JSON 解析器行为），
        ;; 用 cl-loop 遍历 vector 元素（hash-table）。
        (unless aiaos-cli--skill-cache
          (setq aiaos-cli--skill-cache (make-hash-table :test 'equal)))
        (cl-loop for skill across skills do
          (let ((name (gethash "name" skill))
                (disabled (gethash "disabled" skill)))
            (when (and name
                      (not (eq disabled t))
                      (not (member name loaded))
                      ;; R1401: Only load skills that exist in aiaos-cli-skills-dir.
                      (file-exists-p (expand-file-name
                                           (format "%s/skill.yaml" name)
                                           aiaos-cli-skills-dir)))
              (aiaos-cli-skill-load name)
              (puthash name skill aiaos-cli--skill-cache)
              (push name loaded)
              (push name newly-loaded)
              (when verbose
                (message "aiaos-cli: loaded skill %s" name)))))
        (setq aiaos-cli--loaded-skills loaded)
        (nreverse newly-loaded)))))

(defvar aiaos-cli--agent-history '() "History of agent chat messages.")

(define-derived-mode aiaos-cli-agent-mode fundamental-mode "aiaos-cli-agent"
  "Major mode for aiaos agent chat."
  (setq-local truncate-lines t)
  (setq-local read-only t))

;;;###autoload
(defun aiaos-cli-agent-chat ()
  "Open the aiaos agent chat buffer."
  (interactive)
  (with-current-buffer (get-buffer-create aiaos-cli-chat-buffer-name)
    (aiaos-cli-agent-mode)
    (unless (buffer-modified-p)
      (erase-buffer)
      (insert "=== AIAOS Agent Chat ===\n\n"
              "Type a message and press C-c a to send, or C-c q to quit.\n\n"))
    (goto-char (point-max)))
  (switch-to-buffer aiaos-cli-chat-buffer-name))

(defun aiaos-cli-agent-send (message)
  "Send MESSAGE to the aiaos agent and display response in the chat buffer.

R1400: Previously called aiaos-cli-run which opens a separate result
buffer, so the agent reply never appeared in the chat buffer. Now
uses aiaos-cli--call-async directly to inline the response.

Returns the process object."
  (interactive "sMessage: ")
  (unless (string-trim message) (user-error "Empty message"))
  (with-current-buffer (get-buffer-create aiaos-cli-chat-buffer-name)
    (setq buffer-read-only nil)
    (goto-char (point-max))
    (insert (format "\n>>> %s\n" message))
    (setq buffer-read-only t))
  (push (list :role "user" :message message) aiaos-cli--agent-history)
  (with-current-buffer (get-buffer-create aiaos-cli-chat-buffer-name)
    (setq buffer-read-only nil)
    (goto-char (point-max))
    (insert (propertize "\n...waiting for agent response..." 'face 'font-lock-comment-face))
    (setq buffer-read-only t))
  (let ((cmd (aiaos-cli--build-cmd "agent" "chat" (format "--message=%s" message))))
    (aiaos-cli--call-async cmd
      (lambda (status out err)
        (with-current-buffer (get-buffer-create aiaos-cli-chat-buffer-name)
          (setq buffer-read-only nil)
          (goto-char (point-max))
          (when (re-search-backward "\.\.\.waiting for agent response\.\.\." (point-min))
            (delete-region (match-beginning 0) (match-end 0)))
          (if (= status 0)
              (insert (format "\n<<< %s\n" (string-trim out)))
            (insert (format "\n<<< [error] %s\n" (or (string-trim err) "unknown error"))))
          (setq buffer-read-only t)
          (goto-char (point-max)))))))

(defvar aiaos-cli--log-tail-timer nil "Timer for log tail updates.")

(defun aiaos-cli--log-tail-stop ()
  "Cancel the log-tail timer and clear state."
  (when aiaos-cli--log-tail-timer
    (cancel-timer aiaos-cli--log-tail-timer)
    (setq aiaos-cli--log-tail-timer nil)))

;;;###autoload
(defun aiaos-cli-log-tail ()
  "Tail aiaos-cli logs in a dedicated buffer."
  (interactive)
  (if aiaos-cli--log-tail-timer
      (progn
        (aiaos-cli--log-tail-stop)
        (message "Log tail stopped"))
    (with-current-buffer (get-buffer-create "*aiaos-cli-log*")
      (aiaos-cli-mode)
      (erase-buffer)
      (insert "=== AIAOS Log Tail ===\n\n"))
    (switch-to-buffer "*aiaos-cli-log*")
    (setq aiaos-cli--log-tail-timer
          (run-at-time 1 3 #'aiaos-cli--log-tail-tick))
    (aiaos-cli--log-tail-tick)))

(defun aiaos-cli--log-tail-tick ()
  "Tick function for log tail.

R780: 原实现无 error handler，子进程崩溃或 callback 抛异常时 timer 静默
失败且继续按 3s 间隔重复触发，用户看不到任何反馈。现在用 condition-case
包裹，捕获异常后停止 timer 并 message；失败时把 stderr 写入 log buffer。"
  (condition-case err
      (aiaos-cli--call-async
       (list (aiaos-cli--assert-binary) "log" "tail" "--limit=20" "--format=raw")
       (lambda (status out err-stream)
         (with-current-buffer (get-buffer-create "*aiaos-cli-log*")
           (setq buffer-read-only nil)
           (goto-char (point-max))
           (cond
            ((= status 0)
             (insert (current-time-string) " | " out "\n"))
            (t (insert (format "%s | [log tail failed: status=%d]\n%s\n"
                               (current-time-string) status err-stream)))))
           (setq buffer-read-only t)
           (goto-char (point-max))))
    (error
     (aiaos-cli--log-tail-stop)
     (message "aiaos-cli log tail stopped: %s" (error-message-string err)))))

;;;###autoload
(defun aiaos-cli-log-tail-stop ()
  "Stop log tail."
  (interactive)
  (aiaos-cli--log-tail-stop)
  (message "Log tail stopped"))

;; ---------------------------------------------------------------------------
;; TUI Framework Entry (R1325)
;; ---------------------------------------------------------------------------

(defvar aiaos-cli--app-loaded nil
  "R1325: Cache whether aiaos-cli-app is loaded.")

(defun aiaos-cli-app-start ()
  "Start aiaos-cli TUI application.

R1325: Activates the TUI framework modules (aiaos-cli-app + 7 support
modules, 138 functions) that were previously dead code. The TUI provides
an interactive interface with navigation, status bar, and theme support."
  (interactive)
  (unless (aiaos-cli--assert-binary)
    (user-error "aiaos-cli 未安装或不可执行"))
  (unless (aiaos-cli--version-consistent-p)
    (user-error "版本不匹配，请更新 aiaos-cli"))
  (unless aiaos-cli--app-loaded
    (let ((app-file (locate-file "aiaos-cli-app.el" load-path)))
      (if app-file
          (load app-file)
        (user-error "TUI 模块未找到，请检查安装路径")))
    (setq aiaos-cli--app-loaded t))
  (aiaos-cli--app-start))


;; ---------------------------------------------------------------------------
;; Version gate
(defun aiaos-cli--version-consistent-p ()
  "Return t if aiaos-cli binary version matches aiaos-cli--expected-version.

R780: 原实现用 string-match ... $，但 --version 输出形如 aiaos-cli v1.0.0，
$ 只锚定末尾，expected-version 是裸 1.0.0。原实现碰巧能匹配，但语义
不清晰且对带后缀的版本号（如 1.0.0-rc1）会误判。改为先提取语义化
版本再精确比较。"
  (unless aiaos-cli--inited
    (aiaos-cli-init))
  (unless aiaos-cli--version
    (let ((bin (condition-case _ (aiaos-cli--assert-binary) (user-error nil))))
      (when bin
        (condition-case _
            (let ((res (aiaos-cli--call-sync (list bin "--version"))))
              (setq aiaos-cli--version (string-trim (cdr res))))
          (error nil)))))
  (let ((want aiaos-cli--expected-version)
        (got (and aiaos-cli--version
                  (let ((m (string-match
                             (concat "v?\\([0-9]+\\.[0-9]+\\.[0-9]+\\)")
                             aiaos-cli--version)))
                    (when m (match-string 1 aiaos-cli--version))))))
    (and got (string= want got))))


;;;-----------------------------------------------------------------------------
;; R2026: 补齐缺失的命令组 (session/context/config/project/log/doctor/agent)
;;;-----------------------------------------------------------------------------

;; ============================================================
;; Session 完整命令组 (补全 show/switch/archive/delete)
;; ============================================================

;;;###autoload
(defun aiaos-cli-session-show (name)
  "Show aiaos session NAME details."
  (interactive "sSession name: ")
  (aiaos-cli-run "session" "show" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-session-switch (name)
  "Switch to aiaos session NAME."
  (interactive "sSession name: ")
  (aiaos-cli-run "session" "switch" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-session-archive (name)
  "Archive aiaos session NAME."
  (interactive "sSession name: ")
  (aiaos-cli-run "session" "archive" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-session-delete (name)
  "Delete aiaos session NAME."
  (interactive "sSession name: ")
  (aiaos-cli-run "session" "delete" (format "--name=%s" name)))

;; ============================================================
;; Context 完整命令组 (补全 load/clear/export)
;; ============================================================

;;;###autoload
(defun aiaos-cli-context-load (name)
  "Load aiaos context NAME."
  (interactive "sContext name: ")
  (aiaos-cli-run "context" "load" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-context-clear ()
  "Clear current aiaos context."
  (interactive)
  (aiaos-cli-run "context" "clear"))

;;;###autoload
(defun aiaos-cli-context-export (format)
  "Export aiaos context in specified FORMAT (json|yaml|table)."
  (interactive "sExport format (json/yaml/table): ")
  (aiaos-cli-run "context" "export" (format "--format=%s" format)))

;; ============================================================
;; Config 命令组 (全新)
;; ============================================================

;;;###autoload
(defun aiaos-cli-config-get (key)
  "Get aiaos config KEY value."
  (interactive "sConfig key: ")
  (aiaos-cli-run "config" "get" (format "--key=%s" key)))

;;;###autoload
(defun aiaos-cli-config-set (key value)
  "Set aiaos config KEY to VALUE."
  (interactive "sConfig key: sConfig value: ")
  (aiaos-cli-run "config" "set" (format "--key=%s" key) (format "--value=%s" value)))

;;;###autoload
(defun aiaos-cli-config-list ()
  "List all aiaos config values."
  (interactive)
  (aiaos-cli-run "config" "list"))

;;;###autoload
(defun aiaos-cli-config-edit ()
  "Edit aiaos config file."
  (interactive)
  (aiaos-cli-run "config" "edit"))

;;;###autoload
(defun aiaos-cli-config-validate ()
  "Validate aiaos config."
  (interactive)
  (aiaos-cli-run "config" "validate"))

;;;###autoload
(defun aiaos-cli-config-migrate ()
  "Migrate aiaos config to new version."
  (interactive)
  (aiaos-cli-run "config" "migrate"))

;;;###autoload
(defun aiaos-cli-config-reset ()
  "Reset aiaos config to defaults."
  (interactive)
  (aiaos-cli-run "config" "reset"))

;; ============================================================
;; Project 命令组 (全新)
;; ============================================================

;;;###autoload
(defun aiaos-cli-project-init (name)
  "Initialize aiaos project with NAME."
  (interactive "sProject name: ")
  (aiaos-cli-run "project" "init" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-project-sync ()
  "Sync aiaos project."
  (interactive)
  (aiaos-cli-run "project" "sync"))

;;;###autoload
(defun aiaos-cli-project-build ()
  "Build aiaos project."
  (interactive)
  (aiaos-cli-run "project" "build"))

;;;###autoload
(defun aiaos-cli-project-deploy ()
  "Deploy aiaos project."
  (interactive)
  (aiaos-cli-run "project" "deploy"))

;;;###autoload
(defun aiaos-cli-project-status ()
  "Show aiaos project status."
  (interactive)
  (aiaos-cli-run "project" "status"))

;; ============================================================
;; Log 命令组 (补全 show/clear/level)
;; ============================================================

;;;###autoload
(defun aiaos-cli-log-search (keyword)
  "Search aiaos log for KEYWORD."
  (interactive "sSearch keyword: ")
  (aiaos-cli-run "log" "search" (format "--pattern=%s" keyword)))

;;;###autoload
(defun aiaos-cli-log-export (output-file)
  "Export aiaos log to OUTPUT-FILE."
  (interactive "sOutput file: ")
  (aiaos-cli-run "log" "export" (format "--output=%s" output-file)))

;;;###autoload
(defun aiaos-cli-log-analyze ()
  "Analyze aiaos log."
  (interactive)
  (aiaos-cli-run "log" "analyze"))

;;;###autoload
(defun aiaos-cli-log-list ()
  "List aiaos log files."
  (interactive)
  (aiaos-cli-run "log" "list"))

;; ============================================================
;; Doctor 命令组 (补全 fix/report)
;; ============================================================

;;;###autoload
(defun aiaos-cli-doctor-fix ()
  "Fix aiaos environment issues."
  (interactive)
  (aiaos-cli-run "doctor" "fix"))

;;;###autoload
(defun aiaos-cli-doctor-report ()
  "Generate aiaos environment report."
  (interactive)
  (aiaos-cli-run "doctor" "report"))

;; ============================================================
;; Agent 命令组 (补全 delegate/tool/history)
;; ============================================================

;;;###autoload
(defun aiaos-cli-agent-delegate (task)
  "Delegate TASK to aiaos agent."
  (interactive "sTask to delegate: ")
  (aiaos-cli-run "agent" "delegate" (format "--task=%s" task)))

;;;###autoload
(defun aiaos-cli-agent-tool (name)
  "Invoke agent TOOL NAME."
  (interactive "sTool name: ")
  (aiaos-cli-run "agent" "tool" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-agent-history ()
  "Show aiaos agent history."
  (interactive)
  (aiaos-cli-run "agent" "history"))

;;; aiaos-cli-new-commands.el ends here

(provide 'aiaos-cli)

;;; aiaos-cli.el ends here
