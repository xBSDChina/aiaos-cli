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

;; R-COMPILE-DECLARE: 声明 aiaos-cli-llm.el 中定义的函数，消除 byte-compile
;; "not known to be defined" 警告（aiaos-cli-llm 仅在 batch 运行时 require）。
(declare-function aiaos-llm-build-tools-schema "aiaos-cli-llm.el" ())

;; TUI 模块集成
(require 'aiaos-cli-core)
(require 'cl-lib)
(require 'aiaos-cli-state)
(require 'aiaos-cli-context)
(require 'aiaos-cli-lifecycle)
(require 'aiaos-cli-component)
(require 'aiaos-cli-theme)
(require 'aiaos-cli-components)
(require 'aiaos-cli-router)
(require 'aiaos-cli-app)
(require 'aiaos-cli-command)
(require 'aiaos-cli-registry)
(require 'aiaos-cli-elisp)
(require 'aiaos-cli-sim)

(defgroup aiaos-cli nil
  "AIAOS-CLI Emacs frontend."
  :group 'tools
  :prefix "aiaos-cli-")

(defcustom aiaos-cli-bin "aiaos"
  "Path to the aiaos executable.
Searches aiaos-bin, then PATH, then ~/aiaos/bin/aiaos."
  :type 'file
  :group 'aiaos-cli)

(defcustom aiaos-cli-default-format "json"
  "Default output format for aiaos-cli invocations."
  :type '(choice (const json) (const table) (const raw))
  :group 'aiaos-cli)

(defcustom aiaos-cli-async-timeout 5400
  "Timeout (seconds) for async aiaos-cli invocations.

R2902: LLM provider 交互通常耗时较长（模型推理、工具调用、流式
输出），默认 30 秒过短，导致 process killed after 30 seconds。
提升到 120 秒以容纳完整的多轮 agent 交互。"
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
  (expand-file-name "~/.emacs.d/aiaos-cli/skills")
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

(defun aiaos-cli--expand-arg (arg)
  "Expand ~ in ARG so it works as a process argument.

call-process/make-process run the program directly WITHOUT a shell, so a
literal \"~/foo\" is passed through untouched and the binary cannot find
the file.  This expands a leading ~ (\"~\", \"~/foo\", \"~user/foo\") and
also handles \"--key=~/foo\" style option values.  Non-string args and
strings with no ~ are returned unchanged."
  (cond
   ((not (stringp arg)) arg)
   ;; Leading tilde: ~, ~/foo, ~user/foo
   ((string-prefix-p "~" arg)
    (condition-case nil (expand-file-name arg) (error arg)))
   ;; --key=~/foo style: expand the value after '='
   ((string-match-p "=~" arg)
    (let ((eq-pos (string-match "=~" arg)))
      (concat (substring arg 0 (1+ eq-pos))
              (condition-case nil
                  (expand-file-name (substring arg (1+ eq-pos)))
                (error (substring arg (1+ eq-pos)))))))
   (t arg)))

(defun aiaos-cli--resolve-bin ()
  "Return absolute path to aiaos binary, or nil if not found.

R1404: 修复声称搜索 3 个路径但实际只查 2 个的问题。
现在真正按顺序检查：1) aiaos-cli-bin 变量（仅当为绝对路径时）
2) PATH 中 aiaos/aiaos-cli  3) 默认安装路径 ~/aiaos/bin/aiaos
和 ~/aiaos/aiaos-cli/bin/aiaos-cli。

R2900: 修复 file-executable-p 对裸名 \"aiaos\" 返回 t 的 bug——
当 default-directory 为 ~ 时，~/aiaos 是目录，file-executable-p
错误地返回 t，导致返回裸名而非绝对路径，make-process 随后无法
找到程序。现在仅接受绝对路径的 file-executable-p 检查。"
  (let ((bin (aiaos-cli--expand-env aiaos-cli-bin)))
    (cond
     ;; 1) aiaos-cli-bin 为绝对路径且可执行
     ((and (stringp bin)
           (file-name-absolute-p bin)
           (file-executable-p bin))
      bin)
     ;; R2904: 优先使用新版 aiaos-cli binary（含 Python bridge + 17 provider fallback）
     ;; 必须先于 PATH 检查，避免命中 ~/aiaos/bin/aiaos 旧版（走旧 agent 循环 → minimax 402）
     ((file-executable-p (expand-file-name "~/aiaos/aiaos-cli/bin/aiaos-cli"))
      (let ((default-bin (expand-file-name "~/aiaos/aiaos-cli/bin/aiaos-cli")))
        (setq aiaos-cli-bin default-bin)
        default-bin))
     ;; 2) PATH 中的 aiaos / aiaos-cli（executable-find 返回绝对路径）
     ((or (executable-find "aiaos")
          (executable-find "aiaos-cli"))
      (let ((found (or (executable-find "aiaos")
                       (executable-find "aiaos-cli"))))
        (setq aiaos-cli-bin found)
        found))
     ;; 3) 显式绝对路径候选（旧版兜底）
     ((file-executable-p (expand-file-name "~/aiaos/bin/aiaos"))
      (let ((default-bin (expand-file-name "~/aiaos/bin/aiaos")))
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
       (concat "aiaos binary not found. Searched: "
               "1 aiaos-cli-bin=" (or aiaos-cli-bin "<nil>")
               " 2 PATH=" (or (executable-find "aiaos") (executable-find "aiaos-cli") "<nil>")
               " 3 ~/aiaos/bin/aiaos and ~/aiaos/aiaos-cli/bin/aiaos-cli. "
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

CMD is a list of strings.  Errors are signaled with `user-error'.
Each argument has ~ expanded via `aiaos-cli--expand-arg'."
  (let ((cmd (mapcar #'aiaos-cli--expand-arg cmd))
        (buf (get-buffer-create (format "*aiaos-cli-tmp-%s*" (random 1000000))))
        status)
    (unwind-protect
        (progn
          (setq status (apply #'call-process (car cmd) nil buf nil (cdr cmd)))
          (cons status (with-current-buffer buf (buffer-string))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(defun aiaos-cli--call-async (cmd callback &optional stream-callback)
  "Invoke CMD asynchronously; call CALLBACK with (status stdout stderr).

CMD is a list of strings.  CALLBACK receives three args.
STREAM-CALLBACK, if non-nil, is a function of one string argument called
with each chunk of stdout as it arrives (SSE/JSONL incremental streaming).
When STREAM-CALLBACK is given a :filter is installed that both appends the
chunk to the internal buffer (so CALLBACK still sees the full stdout) and
forwards it to STREAM-CALLBACK for live display.
R621 修复: 之前用 start-process 时 stderr 被丢弃，err-buf 永远为空。
现在用 make-process + connection-type t + connection-function 真正分离
stdout/stderr，让调用方（如 aiaos-cli-run）的失败分支能拿到 stderr。
R2600 修复 (TD-003): 此前 aiaos-cli-async-timeout 变量已定义但从未使用，
进程可能永远挂起。现在增加超时保护：超时后 kill 进程，
以 status=124（类似 GNU coreutils timeout 的约定）调用 callback。"
  (let ((cmd (mapcar #'aiaos-cli--expand-arg cmd))
        (process-connection-type nil)
        out-buf err-buf proc timer killed
        stream-filter)
    (setq out-buf (get-buffer-create (format "*aiaos-cli-out-%s*" (random 1000000)))
          err-buf (get-buffer-create (format "*aiaos-cli-err-%s*" (random 1000000))))
    ;; 流式过滤：把每个 stdout 块同时写入 out-buf（供 CALLBACK 汇总）并转发给
    ;; STREAM-CALLBACK（供实时显示）。仅当 STREAM-CALLBACK 非空时安装 :filter，
    ;; 否则保持原有 make-process 默认行为（输出直接进 buffer），避免回归。
    (when stream-callback
      (setq stream-filter
            (lambda (_p chunk)
              (with-current-buffer out-buf
                (goto-char (point-max))
                (insert chunk))
              (condition-case nil
                  (funcall stream-callback chunk)
                (error nil)))))
    (let ((plist (list :name "aiaos-cli"
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
                                 (kill-buffer err-buf)))))))))
      (when stream-filter
        (setq plist (plist-put plist :filter stream-filter)))
      (setq proc (apply #'make-process plist)))
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
      (define-key map "t" #'aiaos)
      (define-key (current-global-map) (read-kbd-macro aiaos-cli-key-prefix) map)
    ;; R1130: 保存 keymap 供测试/调试使用
    (setq aiaos-cli--keymap map)
    ;; Cache version (if binary found)
    (when bin
      (condition-case _
          (let ((res (aiaos-cli--call-sync (list bin "--version"))))
            (when (= (car res) 0)
              (setq aiaos-cli--version (string-trim (cdr res)))))
        (error nil)))
    (setq aiaos-cli--inited t)
    ;; TUI Module Integration (R1330)
    ;; Load TUI modules if available (optional, for enhanced TUI features)
    (when (locate-file "aiaos-cli-app.el" load-path)
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
          (progn
            (load "aiaos-cli-app")
            (condition-case _
                (aiaos-cli--app-init)
              (error nil)))
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


;; ============================================================
;; 命令树：结构化功能查阅（R4100+2）
;; ============================================================
;; 该数据结构定义 aiaos-cli 全部顶层命令及子命令，
;; 供 aiaos-cli--register-command-tree 注册到 command 模块，
;; 并由 aiaos-cli-command-tree 渲染为人工审核界面。

(defvar aiaos-cli--command-tree
  '((session . (("new" . "创建新会话")
                 ("list" . "列出所有会话")
                 ("show" . "显示会话详情")
                 ("switch" . "切换当前会话")
                 ("archive" . "归档会话")
                 ("delete" . "删除会话")
                 ("current" . "显示当前会话")))
    (context . (("show" . "显示当前上下文")
                 ("save" . "保存上下文")
                 ("load" . "加载上下文")
                 ("clear" . "清空上下文")
                 ("export" . "导出上下文")
                 ("list" . "列出所有上下文")
                 ("import" . "导入上下文")))
    (skill . (("install" . "安装技能")
              ("uninstall" . "卸载技能")
              ("list" . "列出所有技能")
              ("update" . "更新技能")
              ("info" . "显示技能详情")
              ("search" . "搜索技能")
              ("validate" . "验证技能元数据")
              ("run" . "运行技能命令")
              ("deps" . "依赖解析/拓扑排序")
              ("create" . "创建技能骨架")
              ("enable" . "启用技能")
              ("disable" . "禁用技能")))
    (agent . (("chat" . "与Agent对话")
              ("delegate" . "委托任务给Agent")
              ("tool" . "调用Agent工具")
              ("history" . "查看对话历史")
              ("status" . "查看Agent状态")))
    (project . (("init" . "初始化项目")
                ("sync" . "同步项目")
                ("build" . "构建项目")
                ("deploy" . "部署项目")
                ("status" . "查看项目状态")
                ("info" . "查看项目详情")))
    (config . (("get" . "获取配置项")
               ("set" . "设置配置项")
               ("list" . "列出所有配置")
               ("edit" . "编辑配置文件")
               ("validate" . "验证配置")
               ("migrate" . "迁移配置")
               ("reset" . "重置配置")))
    (log . (("tail" . "查看日志尾部")
            ("search" . "搜索日志")
            ("export" . "导出日志")
            ("analyze" . "分析日志")
            ("list" . "列出日志文件")))
    (provider . (("list" . "列出Providers")
                 ("use" . "使用Provider")
                 ("test" . "测试Provider")
                 ("tier" . "设置Provider层级")
                 ("fallback" . "设置Fallback策略")
                 ("fallback-order" . "设置Fallback顺序")
                 ("chat" . "与Provider对话")
                 ("audit" . "审计Provider")
                 ("report" . "生成Provider报告"))))
  "嵌套列表结构：(顶层命令 . ((子命令 . 描述) ...))。R4100+2 补全全部8域。")

(defvar aiaos-cli--extra-top-commands
  '(("doctor" . "环境诊断 (check, fix, report)")
    ("help" . "显示帮助")
    ("version" . "显示版本"))
  "无子命令的顶层命令（直接映射到 aiaos-cli-doctor 等）。")

;;;###autoload
(defun aiaos-cli--register-command-tree ()
  "将 aiaos-cli--command-tree 注册到 command 模块的注册表。

R4100+2: 集成 aiaos-cli-command 模块，修复孤儿模块问题。
此前 command.el 定义了注册/查询系统但从未被集成，
现在通过该函数初始化并注册全部命令，供
aiaos-cli-command-tree 查阅。"
  (aiaos-cli--command-init)
  ;; 注册顶层命令及其子命令
  (dolist (entry aiaos-cli--command-tree)
    (let* ((domain (car entry))
           (subs (cdr entry)))
      ;; 顶层命令：handler 为 nil，仅作为容器
      (aiaos-cli--command-register
       (format "%s" domain)
       (aiaos-cli--command-make
        (format "%s" domain)
        (format "%s 域命令" domain)
        nil))
      ;; 注册子命令
      (dolist (sub subs)
        (let* ((name (car sub))
               (desc (cdr sub))
               (cmd-name (format "%s %s" domain name)))
          (aiaos-cli--command-register
           cmd-name
           (aiaos-cli--command-make
            name desc nil))))))
  ;; 注册无子命令的顶层命令
  (dolist (entry aiaos-cli--extra-top-commands)
    (aiaos-cli--command-register
     (format "%s" (car entry))
     (aiaos-cli--command-make
      (car entry) (cdr entry) nil)))
  aiaos-cli--command-registry)

;;;###autoload
(defun aiaos-cli-command-tree (&optional buffer)
  "在 BUFFER（默认 \*aiaos-cli-commands\*）中渲染 aiaos-cli 全部命令。

R4100+2: 供人工审核查阅全部功能的结构化界面。
命令来源于 aiaos-cli--command-tree 静态数据 + CLI --help 动态输出。

交互命令：
  \[aiaos-cli-command-tree-expand]  展开/折叠子命令
  \[aiaos-cli-command-run-current]  执行当前行命令
  \[aiaos-cli-command-refresh]     刷新命令树"
  (interactive)
  (aiaos-cli--register-command-tree)
  (let ((buf (or buffer (get-buffer "*aiaos-cli-commands*"))))
    (if (null buf)
        (setq buf (get-buffer-create "*aiaos-cli-commands*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (aiaos-cli--render-command-tree (current-buffer)))
      (aiaos-cli-command-tree-mode))
    (pop-to-buffer buf)))


(defvar aiaos-cli-command-tree-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "e" #'aiaos-cli-command-tree-expand)
    (define-key map "r" #'aiaos-cli-command-tree-refresh)
    (define-key map [return] #'aiaos-cli-command-run-current)
    map)
  "命令树模式 keymap。")

(defvar aiaos-cli--command-tree-collapsed nil
  "已折叠的顶层命令列表（非空表示该顶层命令的子命令不显示）。")

(defun aiaos-cli--render-command-tree (_buf)
  "在 BUF 中渲染命令树。"
  (let ((inhibit-read-only t))
    (goto-char (point-min))
    (insert "# aiaos-cli 命令树\n")
    (insert "# 供人工审核查阅全部功能\n\n")
    (dolist (entry aiaos-cli--command-tree)
      (let* ((domain (car entry))
             (subs (cdr entry))
             (collapsed (memq domain aiaos-cli--command-tree-collapsed)))
        (insert (format "## %s\n\n" domain))
        (unless collapsed
          (dolist (sub subs)
            (let* ((name (car sub))
                   (desc (cdr sub)))
              (insert (format "  - %-15s %s\n" name desc))))
          (insert "\n")))))
    ;; 渲染无子命令的顶层命令
    (dolist (entry aiaos-cli--extra-top-commands)
      (insert (format "## %s\n  - %s\n\n"
                      (car entry) (cdr entry))))
    (insert "---\n")
    (insert (format "命令总数: %d（含子命令）\n"
                    (aiaos-cli--command-count-tree aiaos-cli--command-tree)))
    (insert "提示: 按 e 折叠/展开, r 刷新, RET 执行当前行命令\n\n"))

(defun aiaos-cli--command-count-tree (tree)
  "递归统计命令树中的命令总数（含顶层和子命令）。"
  (let ((count 0))
    (dolist (entry tree)
      (setq count (+ count 1))
      (setq count (+ count (length (cdr entry)))))
    count))

(defun aiaos-cli-command-tree-refresh ()
  "刷新命令树显示。"
  (interactive)
  (aiaos-cli--render-command-tree (current-buffer)))

(defun aiaos-cli-command-tree-expand ()
  "展开/折叠当前顶层命令的子命令。"
  (interactive)
  (let ((match (re-search-backward "^## (\\S+)" nil 'boundary)))
    (when match
      (let ((domain (match-string 1)))
        (if (memq domain aiaos-cli--command-tree-collapsed)
            (setq aiaos-cli--command-tree-collapsed
                  (remq domain aiaos-cli--command-tree-collapsed))
          (setq aiaos-cli--command-tree-collapsed
                (cons domain aiaos-cli--command-tree-collapsed)))
        (aiaos-cli-command-tree-refresh)))))

(defun aiaos-cli-command-run-current ()
  "执行当前行的命令。

若当前行是子命令，执行对应 aiaos-cli-<domain>-<subcommand>；
若是顶层命令，执行 aiaos-cli-<domain>。"
  (interactive)
  (let ((line (thing-at-point 'line)))
    (when (string-match "\`\s*-\s+\(\\S+\)" line)
      (let* ((sub (match-string 1 line))
             (match (re-search-backward "^## \(\\S+\)" nil 'boundary)))
        (if match
            (let ((domain (match-string 1)))
              (let ((fn (intern (format "aiaos-cli-%s-%s" domain sub))))
                (if (fboundp fn)
                    (call-interactively fn)
                  (message "未找到命令函数: %s" fn))))
          (message "无法确定所属域"))))))

(defun aiaos-cli-command-tree-mode ()
  "命令树浏览模式。"
  (interactive)
  (make-local-variable 'aiaos-cli--command-tree-collapsed)
  (make-local-variable 'mode-line-format)
  (setq mode-line-format '(:eval (format " aiaos-commands ")))
  (setq major-mode 'aiaos-cli-command-tree-mode))


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
                  '("session" "context" "skill" "agent" "project" "config" "doctor" "log" "provider"))
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
      ;; R1320: 同步记录到 aiaos-cli--loaded-skills（skill-info/skill-list 依赖）。
      (when (boundp 'aiaos-cli--loaded-skills)
        (setq aiaos-cli--loaded-skills
              (cons (list :name name :path (expand-file-name name aiaos-cli-skills-dir)
                          :version "1.0.36" :enabled t)
                    (cl-remove name aiaos-cli--loaded-skills
                               :key (lambda (s) (plist-get s :name)) :test 'string=))))
      (message "aiaos-cli: loaded %d file(s) for skill %s"
               (length loaded) name)
      loaded)))

;; R1100: alist->plist 桥接（JSON 解析产物 -> plist）。
;; 此前内嵌于 core/skill.sh 的 Python 生成脚本中，无法单元测试；现迁移至前端，
;; 生成脚本依赖 `-l aiaos-cli` 已加载本定义，不再重复 defun。
(defun aiaos-cli--alist-to-plist (data)
  "Convert DATA to a plist with keyword keys.

Handles both string-keyed alists (the product of JSON object parsing,
e.g. ((\"key\" . val) ...)) and keyword plists (e.g. (:key val ...)).
Also handles wrapped/nested alist shapes and mixed plist-with-alist-values."
  (cond
   ((null data) nil)
   ;; Already a keyword plist.
   ((and (consp data) (keywordp (car data))) data)
   ;; Wrapped alist: ((((\"k\" . v) ...)) ...)
   ((and (consp data) (consp (car data)) (listp (caar data))
         (not (symbolp (caar data))))
    (aiaos-cli--alist-to-plist (car data)))
   ;; Mixed plist with alist values: (:key ((sub . val) ...) :k2 v2)
   ((and (consp data) (consp (car data)) (listp (caar data)))
    (mapcan (lambda (x)
              (if (consp (car x))
                  (list (intern (format ":%s" (car x)))
                        (aiaos-cli--alist-to-plist (cdr x)))
                (list (car x) (cdr x))))
            data))
   ;; Alist of (key . val) with string or symbol keys.
   ((and (consp data) (consp (car data)))
    (mapcan (lambda (x)
              (list (intern (format ":%s" (car x))) (cdr x)))
            data))
   (t data)))

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

(defvar aiaos-cli-agent-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") 'aiaos-cli-agent-send)
    (define-key map (kbd "RET") 'aiaos-cli-agent-send)
    (define-key map (kbd "C-j") 'aiaos-cli-agent-send)
    (define-key map (kbd "C-c q")   'aiaos-cli--app-quit)
    map)
  "Keymap for aiaos-cli agent chat mode.")

(define-derived-mode aiaos-cli-agent-mode fundamental-mode "aiaos-cli-agent"
  "Major mode for aiaos agent chat."
  (use-local-map aiaos-cli-agent-mode-map)
  (setq-local truncate-lines t)
  (setq-local read-only nil))

;;;###autoload
(defun aiaos-cli-agent-chat ()
  "Open the aiaos agent chat buffer."
  (interactive)
  (with-current-buffer (get-buffer-create aiaos-cli-chat-buffer-name)
    (aiaos-cli-agent-mode)
    (setq buffer-read-only nil)
    (unless (buffer-modified-p)
      (erase-buffer)
      (insert "=== AIAOS Agent Chat ===\n\n"
              "Type your message below and press C-c C-c to send.\n"
              "Press C-c q to quit.\n\n"))
    (goto-char (point-max))
    (insert "> "))
  (switch-to-buffer aiaos-cli-chat-buffer-name))

(defun aiaos-cli--json-to-string (obj)
  "Convert JSON OBJ (hash-table) to a readable string."
  (cond
   ((null obj) "")
   ((hash-table-p obj)
    (let (pairs)
      (maphash (lambda (k v) (push (format "%s=%s" k (aiaos-cli--json-to-string v)) pairs)) obj)
      (concat "{" (mapconcat #'identity (nreverse pairs) " ") "}")))
   ((vectorp obj) (concat "[" (mapconcat #'aiaos-cli--json-to-string (append obj nil) " ") "]"))
   ((listp obj) (concat "(" (mapconcat #'aiaos-cli--json-to-string obj " ") ")"))
   (t (format "%s" obj))))

(defun aiaos-cli--dialog-status-relevant-p (s)
  "Return non-nil if status message S contains provider/fallback/heal info."
  (string-match-p
   (regexp-opt '("provider" "限流" "429" "503" "508" "504" "切换" "fallback"
                 "自愈" "恢复" "降级" "断路器" "空响应" "重试" "错误" "健康"))
   s))

(defun aiaos-cli--format-tool-result (name result)
  "Format a tool result for display."
  (cond
   ((hash-table-p result)
    (let ((out (gethash "stdout" result))
          (err (gethash "stderr" result))
          (code (gethash "returncode" result)))
      (format "🔧 [%s] 返回码=%s\n%s%s"
              (or name "tool") (or code "?")
              (if (and out (not (string-empty-p out))) (string-trim out) "")
              (if (and err (not (string-empty-p err))) (format "\n[stderr] %s" (string-trim err)) ""))))
   ((stringp result) (format "🔧 [%s] %s" (or name "tool") (string-trim result)))
   (t (format "🔧 [%s] %s" (or name "tool") (aiaos-cli--json-to-string result)))))

(defun aiaos-cli--dialog-format-event (obj)
  "Format a single dialog event OBJ (hash-table) for display.

Returns a string to insert into the agent buffer, or nil to skip.
Supports all provider event types: start / status / thinking / answer /
tool_call / tool_result / error / done / interrupted / end / result.
Used by both the batch `aiaos-cli--dialog-format' and the streaming
agent-buffer path, so single-source formatting is shared."
  (let ((type (gethash "type" obj))
        (content (gethash "content" obj)))
    (cond
     ;; LLM 答案（流式时按 chunk 追加）
     ((string= type "answer")
      (when (and content (not (string-empty-p (string-trim content))))
        (string-trim content)))
     ;; 思考过程
     ((string= type "thinking")
      (when (and content (not (string-empty-p (string-trim content))))
        (propertize (format "💭 %s" (string-trim content))
                    'face 'font-lock-doc-face)))
     ;; 状态/广播消息（provider切换、限流、自愈等）
     ((string= type "status")
      (let ((s (or content "")))
        (when (and (not (string-empty-p (string-trim s)))
                   (aiaos-cli--dialog-status-relevant-p s))
          (propertize (format "ℹ️ %s" (string-trim s))
                      'face 'font-lock-comment-face))))
     ;; 工具调用
     ((string= type "tool_call")
      (propertize (format "🔧 调用工具 %s %s"
                          (gethash "name" obj)
                          (aiaos-cli--json-to-string (gethash "args" obj)))
                  'face 'font-lock-function-name-face))
     ;; 工具结果
     ((string= type "tool_result")
      (aiaos-cli--format-tool-result
       (gethash "name" obj) (gethash "result" obj)))
     ;; 轮次开始：显示轮次进度
     ((string= type "round")
      (propertize (format "▶ 第 %s 轮开始" (or (gethash "round" obj) "?"))
                  'face 'font-lock-keyword-face))
     ;; 每轮任务摘要：显示本轮工具调用与回复情况
     ((string= type "round_summary")
      (let ((rn (gethash "round" obj))
            (tools (gethash "tools" obj))
            (tc (gethash "tool-count" obj))
            (replied (gethash "replied" obj)))
        (propertize
         (format "📋 第 %s 轮完成：%s%s"
                 (or rn "?")
                 (if (and tc (numberp tc) (> tc 0))
                     (format "调用工具 %d 次%s" tc
                             (if (and tools (not (string-empty-p tools)))
                                 (format "（%s）" tools)
                               ""))
                   "未调用工具")
                 (if replied "｜已生成回复" ""))
         'face 'font-lock-doc-face)))
     ;; 持续执行协议：续跑提示
     ((string= type "continuation")
      (propertize (format "🔄 继续执行任务（第 %s 轮）" (or (gethash "round" obj) "?"))
                  'face 'font-lock-comment-face))
     ;; 错误（含 provider 503/508/429）
     ((string= type "error")
      (propertize (format "⛔ %s" (or content "未知错误"))
                  'face '(:foreground "red" :weight bold)))
     ;; 完成
     ((string= type "done")
      (let ((complete (gethash "complete" obj))
            (iters (gethash "iterations" obj))
            (tools (gethash "tool_count" obj)))
        (propertize (format "✅ 任务完成（%d 轮%s%s）"
                            (or iters 0)
                            (if complete "，已完整" "，可能未完成")
                            (if tools (format "，%d 次工具调用" tools) ""))
                    'face 'font-lock-keyword-face)))
     ;; 中断
     ((string= type "interrupted")
      (propertize (format "⏹️ %s" (or content "已中断"))
                  'face '(:foreground "orange" :weight bold)))
     ;; 会话开始
     ((string= type "start")
      (let ((session (gethash "session" obj)))
        (when session
          (propertize (format "🔄 会话（恢复 %s / 共 %s）"
                              (gethash "restored" session)
                              (gethash "total" session))
                      'face 'font-lock-doc-face))))
     ;; bash agent.sh JSON 模式的 result 事件
     ((string= type "result")
      (let ((reply (gethash "reply" obj)))
        (when (and reply (not (string-empty-p reply)))
          (string-trim reply))))
     (t nil))))

(defun aiaos-cli--dialog-format (output)
  "Format streaming JSONL dialog OUTPUT for display.

支持 LLM provider 的所有消息格式（约13种）：
  start / status / thinking / answer / tool_call / tool_result /
  error / done / interrupted / end / 广播消息 / 连续消息 / SSE

同时解析 SSE 格式（data: {...}）与纯 JSONL。answer 事件按连续 chunk
拼接（不插入换行），其余事件各占一行。"
  (let ((lines (split-string output "\n"))
        (parts nil)
        (last-was-answer nil))
    (dolist (line lines)
      (let ((line (string-trim line)))
        ;; 支持 SSE: 去掉 "data: " 前缀
        (when (string-match-p "^data:" line)
          (setq line (string-trim (substring line 5))))
        (when (and (> (length line) 0) (string= (substring line 0 1) "{"))
          (let ((obj (aiaos-cli--parse-json line)))
            (when obj
              (let ((formatted (aiaos-cli--dialog-format-event obj)))
                (when formatted
                  (let ((is-answer (string= (gethash "type" obj) "answer")))
                    (if (and is-answer last-was-answer)
                        ;; 连续 answer chunk 直接拼接
                        (setq parts (cons (concat (car parts) formatted) (cdr parts)))
                      (push formatted parts))
                    (setq last-was-answer is-answer)))))))))
    (if parts
        (string-join (nreverse parts) "\n")
      (string-trim output))))

;;; === 任务完成度双重检测机制 ===
;; 在连续交互结束、即将回到提示符时：
;;   1) 先根据记录检测任务是否完成；
;;   2) 若记录显示可能完成，则让 LLM 生成任务简报（必须含「任务摘要」项）；
;;   3) 再检测简报的「任务摘要」项，判断任务是否真正完成；
;;   4) 若未完成，不回到提示符，自动继续执行任务。
(defvar aiaos-cli--task-continue-count 0
  "当前任务自动续行次数（防止无限循环）。")
(defvar aiaos-cli--task-continue-max 9999
  "任务自动续行的最大次数，超过后强制回到提示符。")
(defvar aiaos-cli--last-agent-reply nil
  "最近一次 agent 回复内容（用于任务完成度记录检测）。")

(defun aiaos-cli--task-record-text ()
  "Build a text summary of the agent conversation records for task detection."
  (aiaos-cli--task-record-text-from aiaos-cli--agent-history))

(defun aiaos-cli--task-briefing-prompt (records)
  "Build the briefing-generation prompt from RECORDS.
The briefing MUST contain a 「任务摘要」item."
  (format
   "你是一个任务完成度评估助手。请根据以下对话记录，生成一份任务简报。\n\
简报必须且仅包含一个「任务摘要」项，并明确评估任务是否已经完成。\n\
请严格以 JSON 格式输出（不要任何多余文字或代码块标记）：\n\
{\"task_summary\": \"<任务摘要内容>\", \"complete\": <true|false>, \"briefing\": \"<完整简报内容>\"}\n\n\
对话记录：\n%s"
   records))

(defun aiaos-cli--task-complete-from-briefing (briefing-text)
  "Check 2: 检测任务简报的「任务摘要」项，判断任务是否完成.

BRIEFING-TEXT is the LLM briefing output (JSON with task_summary/complete, or
plain text).  Returns t if the summary indicates the task is complete, nil
otherwise."
  (let* ((cleaned (string-trim (or briefing-text "")))
         (obj (condition-case nil (aiaos-cli--parse-json cleaned) (error nil)))
         (complete (and obj (gethash "complete" obj)))
         (summary (or (and obj (gethash "task_summary" obj))
                      cleaned)))
    (cond
     ;; JSON 显式 complete 字段
     ((eq complete t) t)
     ((eq complete :json-false) nil)
     ;; 从「任务摘要」项文本分析
     ((and summary (string-match-p
                    "任务完成\\|已完成\\|全部完成\\|✅\\|completed\\|finished\\|task done\\|已解决\\|已实现"
                    (format "%s" summary)))
      t)
     (t nil))))

(defun aiaos-cli--task-continuation-message ()
  "Build the continuation message to keep executing an unfinished task."
  "任务尚未完成，请根据以上对话记录继续执行剩余任务。若任务确已完成，请在回复中明确说明「任务已完成」。")

(defvar aiaos-cli--retry-count 0
  "R2903: 当前重试次数（自愈机制）。")
(defvar aiaos-cli--retry-max 2
  "R2903: 最大重试次数（自愈机制），应对 transient provider 错误。")
(defvar aiaos-cli--retry-delay 3
  "R2903: 重试间隔秒数。")

(defun aiaos-cli--dialog-transient-error-p (out err status)
  "Return non-nil if the dialog response indicates a transient provider error.
R2903: 检测 402/429/5xx 等可自愈错误；但若 bridge 明确返回 permanent=true
（所有 provider 已耗尽），则视为永久错误不再重试。"
  ;; 检查 bridge 是否明确标记为永久失败
  (when (and (stringp out) (> (length (string-trim out)) 0))
    (let ((trimmed (string-trim out)))
      (when (or (string-match-p "fallback_exhausted" trimmed)
                (string-match-p "permanent.*true\\|\"permanent\":\\s-*true" trimmed))
        (aiaos-llm-log "info" "Bridge reports permanent failure, not retrying")
        (cl-return-from aiaos-cli--dialog-transient-error-p nil))))
  ;; 任何非零退出状态 + 错误输出均视为可自愈（bridge 内部已完成 fallback）
  (or (and (numberp status) (> status 0))
      (and (stringp err) (> (length (string-trim err)) 0))
      (and (stringp out) (> (length (string-trim out)) 0)
           (string-match-p "error\\|Error\\|fail\\|timeout\\| refused\\|402\\|429\\|50[0-9]\\|insufficient" out))))

(defvar aiaos-cli--last-agent-message nil
  "R2903: 最近一次发送的消息。自愈重试时复用（提示行已被删除）。")

(defun aiaos-cli--record-to-llm-message (r)
  "Convert conversation RECORD (:role . :message) plist to an LLM message alist."
  (let ((role (or (plist-get r :role) "user"))
        (msg (or (plist-get r :message) "")))
    (cond ((equal role "assistant") (aiaos-llm-message-assistant msg))
          ((equal role "system") (aiaos-llm-message-system msg))
          ((equal role "tool") (aiaos-llm-message-user msg))
          (t (aiaos-llm-message-user msg)))))

(defun aiaos-cli--records-to-messages (records)
  "Convert RECORDS (conversation history plists) to LLM message alists."
  (mapcar #'aiaos-cli--record-to-llm-message (or records nil)))

(defun aiaos-cli--agent-dialog-pure (message &optional stream-cb done-cb records)
  "Pure elisp agent dialog using MESSAGE.

RECORDS, when non-nil, is the conversation history (list of (:role . :message)
plists) from previous turns.  It is prepended as context so the agent's task
chain keeps remembering prior work instead of forgetting the chain records.

Replaces the external `aiaos agent dialog' binary.  Uses the full-capability
pure-elisp LLM engine (`aiaos-llm-chat-stream' -> `aiaos-llm-full-chat'), which
sends tool schemas to the model, executes tool calls in a loop, and streams SSE
deltas in real time.  Emits answer/tool_call/tool_result/status/error events
through STREAM-CB in the same JSONL format the existing renderer expects, then
calls DONE-CB with (status out err).

STREAM-CB and DONE-CB may be nil (batch mode)."
  (let ((status 0) (out "") (err ""))
    (condition-case caught
        (progn
          (when stream-cb
            (funcall stream-cb (concat (json-encode (list (cons "type" "status")
                                                            (cons "content" "正在请求 LLM...")))
                                        "\n")))
          ;; 全能力引擎：真实 SSE 流式 + 工具调用循环
          ;; R-CONTEXT-MEMORY: 将对话历史（records）前置为上下文消息，
          ;; 让 agent 的任务链路在多次 aiaos-cli-agent-send 之间记住记录。
          ;; R-ELISP-CAPABILITY: 在消息列表最前面插入 system message，
          ;; 告知 LLM 当前运行在 Emacs 环境中，可使用 elisp-exec 工具。
          (let* ((history-msgs (aiaos-cli--records-to-messages records))
                 (system-msg (aiaos-llm-message-system aiaos-cli-elisp-system-prompt))
                 (all-msgs (append (list system-msg)
                                   history-msgs
                                   (list (aiaos-llm-message-user message))))
                 (reply
                  (aiaos-llm-full-chat
                   all-msgs
                   (aiaos-llm-build-tools-schema)
                   10
                   ;; 流式事件回调：转发 answer delta 给渲染器
                   (when stream-cb
                      (lambda (obj)
                        (let ((type (cdr (assq 'type obj))))
                          (cond
                           ((equal type "tool_call")
                            (funcall stream-cb (concat (json-encode
                                                        (list (cons "type" "tool_call")
                                                              (cons "name" (cdr (assq 'name obj)))
                                                              (cons "args" (cdr (assq 'args obj)))))
                                                       "\n")))
                           ((equal type "tool_result")
                            (funcall stream-cb (concat (json-encode
                                                        (list (cons "type" "tool_result")
                                                              (cons "name" (cdr (assq 'name obj)))
                                                              (cons "result" (cdr (assq 'result obj)))))
                                                       "\n")))
                           ;; 轮次开始：转发轮号（agent buffer 显示轮次进度）
                           ((equal type "round")
                            (funcall stream-cb (concat (json-encode
                                                        (list (cons "type" "round")
                                                              (cons "round" (cdr (assq 'round obj)))))
                                                       "\n")))
                           ;; 每轮任务摘要：转发轮次小结（工具调用情况）
                           ((equal type "round_summary")
                            (funcall stream-cb (concat (json-encode
                                                        (list (cons "type" "round_summary")
                                                              (cons "round" (cdr (assq 'round obj)))
                                                              (cons "tools" (cdr (assq 'tools obj)))
                                                              (cons "tool-count" (cdr (assq 'tool-count obj)))
                                                              (cons "replied" (cdr (assq 'replied obj)))))
                                                       "\n")))
                           ;; 持续执行协议：转发续跑事件
                           ((equal type "continuation")
                            (funcall stream-cb (concat (json-encode
                                                        (list (cons "type" "continuation")
                                                              (cons "round" (cdr (assq 'round obj)))))
                                                       "\n")))
                           ;; ;;elisp-exec 持续执行协议：转发程序执行事件
                           ((equal type "elisp_exec")
                            (funcall stream-cb (concat (json-encode
                                                        (list (cons "type" "elisp_exec")
                                                              (cons "code" (cdr (assq 'code obj)))
                                                              (cons "result" (cdr (assq 'result obj)))
                                                              (cons "round" (cdr (assq 'round obj)))))
"\n"))))))) t)))
            (setq out (format "%s" reply))
            ;; 若流式事件已渲染了部分内容，此处只发送剩余增量；
            ;; 简化：直接把完整 reply 作为 answer 事件发送（渲染器按内容去重）。
            (when (and stream-cb (> (length out) 0))
              (funcall stream-cb (concat (json-encode (list (cons "type" "answer")
                                                             (cons "content" out)))
                                          "\n"))))
          (when done-cb (funcall done-cb status out err)))
      (error
       (setq status 1)
       (setq err (error-message-string caught))
       (when stream-cb
         (funcall stream-cb (concat (json-encode (list (cons "type" "error")
                                                         (cons "content" err)))
                                    "\n")))
       (when done-cb (funcall done-cb status out err))))))

(defun aiaos-cli--agent-dialog-batch-file (file)
  "Batch entrypoint reading message+records from FILE (elisp `prin1' pair).
File contains `(message records)' written by the parent.  Avoiding passing the
conversation history through the command line: the `--eval' argv would exceed
ARG_MAX (E2BIG \"参数列表过长\") once a session grows long, which is exactly the
\"Error running timer\" seen in `run-at-time' auto-continuation callbacks."
  (let* ((data (with-temp-buffer
                 (insert-file-contents file)
                 (goto-char (point-min))
                 (read (buffer-string))))
         (msg (car data))
         (records (cadr data)))
    (ignore-errors (delete-file file))
    (aiaos-cli--agent-dialog-batch msg records)))

(defun aiaos-cli--agent-dialog-batch (message &optional records)
  "Batch entrypoint: run pure agent dialog for MESSAGE, print JSONL to stdout.

Used as the target of a background `emacs --batch' subprocess so the main
Emacs stays responsive while the LLM streams.  Each event (status/answer/error)
is printed as a single JSON line.  Prints a final done event with the full
reply so the parent can render the fallback batch text if needed.

When RECORDS (conversation history alist) is provided, runs the dual-check task
completion detection after the dialog and emits a `task_check' event:
  CHECK 1 from RECORDS -> if likely complete, generate a task briefing (must
  contain a 「任务摘要」item) -> CHECK 2 from the summary item.  Emits
  {\"type\":\"task_check\",\"complete\":bool,\"briefing\":...} so the parent can
  decide whether to return to the prompt or continue the task."
  (require 'aiaos-cli-llm)
  (require 'aiaos-cli-version)
  (let ((buf (generate-new-buffer " *aiaos-batch-out*")))
    (unwind-protect
        (progn
          (set-buffer-multibyte nil)
          ;; 让 stdout 每行刷新（batch 管道默认块缓冲，filter 需及时收到）
          (let ((events '()))
            (aiaos-cli--agent-dialog-pure
             message
             (lambda (chunk)
               (princ chunk)
               (setq events (cons chunk events)))
(lambda (status out err)
                   ;; 双重检测：根据记录判断任务是否完成，再经任务简报的「任务摘要」项确认
                   (let* ((complete
                           (and records (= status 0)
                                (let* ((rec-text (concat (aiaos-cli--task-record-text-from records)
                                                         "\n"
                                                         (and out (format "[assistant] %s" out))))
                                       (complete-from-records (aiaos-cli--task-complete-from-records-from rec-text nil)))
                                  ;; CHECK 1 明确未完成则不生成简报
                                  (and complete-from-records
                                       ;; CHECK 2: 生成任务简报（含任务摘要项）后二次确认
                                       (let ((briefing (condition-case e
                                                            ;; R-CONSISTENT-SESSION: briefing 在任务历史 + 当前对话的
                                                            ;; 同一会话上下文中生成（而非新会话），保持任务检查连续一致。
                                                            (let* ((sys-msg (aiaos-llm-message-system aiaos-cli-elisp-system-prompt))
                                                                   (base-msgs (append (aiaos-cli--records-to-messages records)
                                                                                      (list (aiaos-llm-message-assistant (or out "")))
                                                                                      (list (aiaos-llm-message-user
                                                                                             (aiaos-cli--task-briefing-prompt rec-text)))))
                                                              (all-msgs (cons sys-msg base-msgs)))
                                                              (aiaos-llm-full-chat (append all-msgs nil)
                                                                                   (aiaos-llm-build-tools-schema) 1))
                                                          (error (format "ERROR: %s" e)))))
                                          (aiaos-cli--task-complete-from-briefing briefing)))))))
                    (when (and records (= status 0))
                      (princ (json-encode (list (cons "type" "task_check")
                                                (cons "complete" (if complete t :json-false)))))
                      (princ "\n"))
                    (princ (json-encode (list (cons "type" "done")
                                              (cons "status" status)
                                              (cons "out" out)
                                              (cons "err" err)
                                              (cons "complete" (if complete t :json-false))
                                              (cons "iterations" (or (cdr (assoc "iterations" aiaos-llm--last-run-stats)) 0))
                                              (cons "tool_count" (or (cdr (assoc "tool_count" aiaos-llm--last-run-stats)) 0)))))
                     (princ "\n")
(setq events (cons (list status out err) events))))
              records)
            (kill-buffer buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(defun aiaos-cli--task-record-text-from (records)
  "Build record text from RECORDS (list of (:role . :message) plists)."
  (mapconcat
   (lambda (m)
     (format "[%s] %s" (or (plist-get m :role) "?") (or (plist-get m :message) "")))
   records "\n"))

(defun aiaos-cli--task-complete-from-records-from (records last-answer)
  "CHECK 1 (batch): detect task completion from RECORDS text and LAST-ANSWER."
  (let ((records (concat (or records "") "\n" (or last-answer ""))))
    (cond
     ((string-match-p "请提供\\|请确认\\|请补充\\|请说明\\|请告诉\\|请给出\\|需要更多信息\\|请问您\\|请先提供\\|请明确"
                      records)
      nil)
     ((string-match-p "任务完成\\|已完成\\|全部完成\\|✅\\|任务简报\\|任务摘要\\|briefing\\|summary\\|completed\\|finished\\|task done"
                      records)
      t)
     (t t))))

(defun aiaos-cli-agent-send (&optional retry)
  "Send the current line's text as a message to the aiaos agent.

Reads the text after the \"> \" prompt at point, sends it via the
CLI backend, and appends the response back into this buffer.
RETRY 为真时表示这是自愈重试调用（不重复读取提示行）。
R2903: 流式输出 —— stdout 每到达一块即增量渲染到 buffer，
无需等待进程结束，LLM answer 逐 token 显示。"
  (interactive)
  (save-excursion
    (let ((msg nil)
          (stream-pending "")
          (stream-started nil)
          (last-was-answer nil)
          (content-inserted nil)
          (task-check-complete t))
      ;; Determine the message: the current line, or the last "> " prompt.
      (if retry
          ;; R2903 修复: 重试时不重新读提示行（已被删除），复用上次消息。
          (setq msg aiaos-cli--last-agent-message)
        (let ((line-start (line-beginning-position)))
          (goto-char line-start)
          ;; If the current line starts with "> ", use its content.
          (if (looking-at "^> \\(.*\\)$")
              (setq msg (string-trim (match-string 1)))
            ;; Otherwise, search backward for the last "> " prompt line.
            (when (re-search-backward "^> \\(.*\\)$" nil t)
              (setq msg (string-trim (match-string 1)))))))
      ;; R2901: 显式处理 nil —— string-empty-p 对 nil 返回 nil（非错误），
      ;; 若 msg 为 nil 会继续执行并导致 "Wrong type argument: stringp, nil"。
      (if (not (and msg (not (string-empty-p msg))))
          (message "aiaos-cli: 没有可发送的消息（请在 \"> \" 提示后输入内容）")
        (setq aiaos-cli--last-agent-message msg)
        ;; Find the prompt line to delete/replace
        (goto-char (point-max))
        (let ((inhibit-read-only t))
          (when (search-backward "> " nil t)
            (delete-region (match-beginning 0) (point-max))
            (goto-char (point-max))))
        (insert "\n")
        (push (list :role "user" :message msg) aiaos-cli--agent-history)
        (unless retry
          (setq aiaos-cli--task-continue-count 0)
          (insert (propertize (format ">>> %s\n" msg) 'face 'font-lock-keyword-face)))
        (insert (propertize "...waiting for response...\n" 'face 'font-lock-comment-face))
        (let ((chat-buf (get-buffer-create aiaos-cli-chat-buffer-name)))
          ;; R-CLOSURE-FIX: 用 let 绑定 lambda + funcall（而非 cl-labels）保证
          ;; 逃逸闭包（完成回调）能正确词法捕获 emit-line/flush-pending。
          (let ((emit-line
                 (lambda (line)
                  (let ((line (string-trim line)))
                    ;; 支持 SSE: 去掉 "data: " 前缀
                    (when (string-match-p "^data:" line)
                      (setq line (string-trim (substring line 5))))
                    (when (and (> (length line) 0)
                               (string= (substring line 0 1) "{"))
                      (let ((obj (aiaos-cli--parse-json line)))
                        (when obj
                          ;; task_check 事件：记录双重检测结果（不渲染）
                          (when (string= (gethash "type" obj) "task_check")
                            (setq task-check-complete (eq (gethash "complete" obj) t)))
                          (let ((formatted (aiaos-cli--dialog-format-event obj)))
                            (when formatted
                              (let ((is-answer (string= (gethash "type" obj) "answer")))
                                (with-current-buffer chat-buf
                                  (let ((inhibit-read-only t))
                                    (goto-char (point-max))
                                    ;; 首个事件: 移除 "...waiting..." 占位符
                                    (unless stream-started
                                      (when (search-backward "...waiting for response..." nil t)
                                        (delete-region (match-beginning 0) (match-end 0)))
                                      (setq stream-started t))
                                    ;; answer 续行直接拼接（不插换行），其余事件分隔一行
                                    (unless (and is-answer last-was-answer)
                                      (insert "\n"))
                                    (insert formatted)))
                                (setq last-was-answer is-answer)
                                (setq content-inserted t)))))))))))
            (let ((flush-pending
                   (lambda ()
                     (when (and (not (string-empty-p stream-pending))
                                (not (string-empty-p (string-trim stream-pending))))
                       (funcall emit-line stream-pending)
                       (setq stream-pending "")))))
              ;; 流式回调: 每块 stdout 增量解析 JSONL 并渲染
              (let ((stream-cb
                     (lambda (chunk)
                       (setq stream-pending (concat stream-pending chunk))
                       (let ((pos 0))
                         (while (string-match "\n" stream-pending pos)
                           ;; R-MATCHDATA-FIX: emit-line 内部会调用 string-match
                           ;; （string-trim/parse-json/format-event），覆盖全局 match-data，
                           ;; 因此必须在调用前捕获 match-end，否则 pos 会倒退导致死循环。
                           (let ((next (match-end 0)))
                             (funcall emit-line (substring stream-pending pos (match-beginning 0)))
                             (setq pos next)))
                         (setq stream-pending (substring stream-pending pos))))))
                 ;; R-SYNC-FIX: 改用后台 emacs --batch 子进程运行 LLM 对话，
                 ;; 避免同步 LLM 调用阻塞主 Emacs（旋转动画卡死）。
                 ;; R-ARGMAX-FIX: 对话历史通过临时文件传给子进程（而非 --eval），
                 ;; 避免长会话时 argv 超 ARG_MAX 报 "参数列表过长" (E2BIG)。
                 (let* ((proj-dir (or (and (symbol-file 'aiaos-cli--agent-dialog-pure)
                                           (file-name-directory (symbol-file 'aiaos-cli--agent-dialog-pure)))
                                      (file-name-directory (or load-file-name ""))
                                      "~/.emacs.d/aiaos-cli/"))
                        (input-file (make-temp-file "aiaos-agent-input-" nil ".el")))
                   (with-temp-file input-file
                     (prin1 (list msg aiaos-cli--agent-history) (current-buffer)))
                   (let ((cmd (list (expand-file-name invocation-name invocation-directory)
                                    "--batch"
                                    "-L" (expand-file-name proj-dir)
                                    "-l" (expand-file-name "aiaos-cli.el" proj-dir)
                                    "--eval" (format "(aiaos-cli--agent-dialog-batch-file %S)"
                                                     input-file))))
                     (aiaos-cli--call-async cmd
                    (lambda (status out err)
                     ;; 完成回调: 冲刷剩余行，然后处理成功/重试/失败。
                     ;; R-FIX-READONLY: 回调在进程 sentinel 上下文中执行，
                     ;; current-buffer 不确定。显式切回聊天 buffer 并用
                     ;; inhibit-read-only 保护写入。
                     (let ((chat-buf (get-buffer aiaos-cli-chat-buffer-name)))
                       (when (buffer-live-p chat-buf)
                          (with-current-buffer chat-buf
                            (let ((inhibit-read-only t))
                              (progn
                               (goto-char (point-max))
                               (funcall flush-pending)
                              (when (search-backward "...waiting for response..." nil t)
                                (delete-region (match-beginning 0) (match-end 0)))
                              ;; R2903 自愈机制: 检测到 transient 错误且未达重试上限时，
                              ;; 自动重试（provider fallback/切换由 binary 内部完成）。
                              (if (and (not (= status 0))
                                      (aiaos-cli--dialog-transient-error-p out err status)
                                      (< aiaos-cli--retry-count aiaos-cli--retry-max))
                                 (progn
                                   (setq aiaos-cli--retry-count (1+ aiaos-cli--retry-count))
                                   (insert (propertize (format "⏳ 检测到 provider 错误（%s），自愈重试 %d/%d..."
                                                               (or (string-trim err) "timeout")
                                                               aiaos-cli--retry-count aiaos-cli--retry-max)
                                                       'face 'font-lock-comment-face))
                                   (insert "\n")
                                   (run-at-time aiaos-cli--retry-delay nil
                                     (lambda ()
                                       (when (buffer-live-p chat-buf)
                                         (with-current-buffer chat-buf
                                           (aiaos-cli-agent-send t))))))
                                (if (= status 0)
                                    (progn
                                      (unless content-inserted
                                        ;; 无流式内容（如进程瞬时退出），用批量格式化兜底
                                        (insert (propertize (format "<<< %s\n"
                                                                    (aiaos-cli--dialog-format out))
                                                            'face 'font-lock-string-face)))
                                      ;; 记录 assistant 回复，供后续任务完成度检测
                                      (when (and out (not (string-empty-p (string-trim out))))
                                        (push (list :role "assistant" :message (string-trim out))
                                              aiaos-cli--agent-history))
                                      (setq aiaos-cli--retry-count 0)
                                      (setq aiaos-cli--last-agent-reply out))
                                  (progn
                                    (setq aiaos-cli--retry-count 0)
                                    (insert (propertize (format "<<< [error] %s\n"
                                                                (or (string-trim err) "unknown error"))
                                                        'face '(:foreground "red" :weight bold))))))
                               ;; 双重任务完成检测：任务完成后才回到提示符，否则自动续行
                               (if (and (= status 0)
                                        (not task-check-complete)
                                        (< aiaos-cli--task-continue-count aiaos-cli--task-continue-max))
                                   (progn
                                     (setq aiaos-cli--task-continue-count
                                           (1+ aiaos-cli--task-continue-count))
                                     (insert (propertize
                                              (format "⏳ 任务未完成，自动继续执行（%d/%d）…\n"
                                                      aiaos-cli--task-continue-count
                                                      aiaos-cli--task-continue-max)
                                              'face 'font-lock-comment-face))
                                     (run-at-time 0.5 nil
                                       (lambda ()
                                         (when (buffer-live-p chat-buf)
                                           (with-current-buffer chat-buf
                                             (let ((aiaos-cli--last-agent-message
                                                    (aiaos-cli--task-continuation-message)))
                                                (aiaos-cli-agent-send t)))))))
                                     (setq aiaos-cli--task-continue-count 0)
                                    ;; R-PROMPT-LINE: 任务完成后回到提示符时，另起一行
                                    ;; 并把光标置于提示符后，准备好接收新消息。
                                    (goto-char (point-max))
                                    (unless (and (> (point) (point-min))
                                                 (eq (char-before) ?\n))
                                      (insert "\n"))
                                      (insert "> "))
                             (condition-case _
                                 (recenter -1)
                                (error nil))))))
                     stream-cb)))))))))))))



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
      (erase-buffer)
      (insert "=== AIAOS Log Tail ===\n\n")
      (aiaos-cli-mode))
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

;; ============================================================
;; Provider 管理命令组
;; ============================================================

;;;###autoload
(defun aiaos-cli-provider-list ()
  "List all providers and their tier levels."
  (interactive)
  (aiaos-cli-run "provider" "list"))

;;;###autoload
(defun aiaos-cli-provider-use (name)
  "Switch current provider to NAME."
  (interactive "sProvider name: ")
  (aiaos-cli-run "provider" "use" name))

;;;###autoload
(defun aiaos-cli-provider-test (name)
  "Health check provider NAME and update tier."
  (interactive "sProvider name: ")
  (aiaos-cli-run "provider" "test" name))

;;;###autoload
(defun aiaos-cli-provider-tier (name tier)
  "Set provider NAME's tier to TIER (full|active|block)."
  (interactive "sProvider name: 
sTier (full/active/block): ")
  (aiaos-cli-run "provider" "tier" name tier))

;;;###autoload
(defun aiaos-cli-provider-fallback (strategy)
  "Set fallback strategy to STRATEGY (sequential|round_robin|priority)."
  (interactive "sFallback strategy: ")
  (aiaos-cli-run "provider" "fallback" (format "--strategy=%s" strategy)))

;;;###autoload
(defun aiaos-cli-provider-fallback-order (order)
  "Set fallback order. ORDER is comma-separated provider names."
  (interactive "sFallback order (comma-separated): ")
  (aiaos-cli-run "provider" "fallback-order" order))

;;;###autoload
(defun aiaos-cli-provider-audit (name)
  "Show audit log for provider NAME."
  (interactive "sProvider name: ")
  (aiaos-cli-run "provider" "audit" name))

;;;###autoload
(defun aiaos-cli-provider-report ()
  "Generate full provider report (strategy, current, fallback order)."
  (interactive)
  (aiaos-cli-run "provider" "report"))

;;;###autoload
(defun aiaos-cli-provider-chat (message)
  "Send MESSAGE to current provider via provider chat."
  (interactive "sMessage: ")
  (aiaos-cli-run "provider" "chat" (format "--message=%s" message)))

;; ============================================================
;; Skill 管理命令组 (补全 create/install/uninstall/update)
;; ============================================================

;;;###autoload
(defun aiaos-cli-skill-create (name)
  "Create skill skeleton for NAME."
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "create" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-skill-install (source)
  "Install skill from SOURCE (local path or git URL).

SOURCE can be a local directory path or a git repository URL.
Examples:
  (aiaos-cli-skill-install \"./skills/my-skill\")
  (aiaos-cli-skill-install \"https://github.com/user/my-skill\")"
  (interactive "sSource (path or URL): ")
  (aiaos-cli-run "skill" "install" source))

;;;###autoload
(defun aiaos-cli-skill-uninstall (name)
  "Uninstall skill NAME."
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "uninstall" (format "--name=%s" name)))

;;;###autoload
(defun aiaos-cli-skill-update (name)
  "Update skill NAME to latest version."
  (interactive "sSkill name: ")
  (aiaos-cli-run "skill" "update" (format "--name=%s" name)))


;; ============================================================
;; R702: 通用领域菜单 (M-x aiaos 全功能覆盖)
;; ============================================================

(defun aiaos-cli-domain-commands (domain)
  "返回 DOMAIN 下所有命令的 (action . 描述) 列表，按 action 排序。

R702: 通用领域菜单的数据源。基于 aiaos-cli--command-tree 枚举，
自动覆盖未来新增命令。DOMAIN 可以是 symbol 或 string。"
  (let ((result nil)
        (domain-sym (if (stringp domain) (intern domain) domain)))
    (dolist (entry aiaos-cli--command-tree)
      (when (equal domain-sym (car entry))
        (setq result (cdr entry))
        (cl-return)))
    (when result
      (sort result (lambda (a b) (string< (car a) (car b)))))))

(defun aiaos-cli-domain-menu (domain)
  "交互式菜单：执行 DOMAIN 领域下任意命令。

R702: 全功能覆盖修复。枚举 DOMAIN 下所有命令，显示编号菜单，
无参命令直接执行，有参命令动态收集参数。"
  (interactive "s领域 (如 skill, diag, provider): ")
  (let ((commands (aiaos-cli-domain-commands domain)))
    (if (null commands)
        (message "领域 '%s' 无可用命令" domain)
      (let ((keys (mapcar #'car commands)))
        (let ((choice
               (completing-read
                (format "选择 %s 命令 (共 %d 个): " domain (length commands))
                keys
                nil t
                nil
                'aiaos-cli-domain-choice-history)))
          (if (null choice)
              (message "已取消")
            (let ((idx (cl-position choice keys :test #'equal)))
              (if idx
                  (let ((action (nth idx keys)))
                    (let ((args (aiaos-cli--collect-args domain action)))
                      (aiaos-cli-run domain action args)))
                  (message "无效选择: %S" choice)))))))))

(defvar aiaos-cli-domain-choice-history nil
  "领域菜单选择历史。")

(defun aiaos-cli--collect-args (domain action)
  "收集 DOMAIN ACTION 的参数，返回字符串列表。

R702: 简化版参数收集。对于 skill 领域，检查常见参数模式。"
  (cond
   ;; skill/run 需要 skill 名和命令名
   ((and (equal domain "skill") (equal action "run"))
    (list (read-string "技能名: ")
          (read-string "命令名: ")))
   ;; skill/install 需要源
   ((and (equal domain "skill") (equal action "install"))
    (list (read-string "源 (路径或URL): ")))
   ;; skill/update 需要名称
   ((and (equal domain "skill") (equal action "update"))
    (list (format "--name=%s" (read-string "技能名: "))))
   ;; skill/uninstall 需要名称
   ((and (equal domain "skill") (equal action "uninstall"))
    (list (format "--name=%s" (read-string "技能名: "))))
   ;; skill/enable/disable 需要名称
   ((and (equal domain "skill")
         (or (equal action "enable") (equal action "disable")))
    (list (format "--name=%s" (read-string "技能名: "))))
   ;; session/delete 需要名称
   ((and (equal domain "session") (equal action "delete"))
    (list (format "--name=%s" (read-string "会话名: "))))
   ;; session/archive 需要名称
   ((and (equal domain "session") (equal action "archive"))
    (list (format "--name=%s" (read-string "会话名: "))))
   ;; session/switch 需要名称
   ((and (equal domain "session") (equal action "switch"))
    (list (format "--name=%s" (read-string "会话名: "))))
   ;; session/show 需要名称
   ((and (equal domain "session") (equal action "show"))
    (list (format "--name=%s" (read-string "会话名: "))))
   ;; config/get 需要键
   ((and (equal domain "config") (equal action "get"))
    (list (read-string "配置键: ")))
   ;; config/set 需要键和值
   ((and (equal domain "config") (equal action "set"))
    (list (read-string "配置键: ") (read-string "配置值: ")))
   ;; 默认：无参数
   (t nil)))

(defun aiaos-cli-menu-read (&optional domain)
  "显示 AIAOS-CLI 全功能主菜单。

R702: 全功能覆盖修复。枚举所有 9 个后端领域，动态生成编号菜单。
支持两种模式：
  - 交互模式（默认）：显示菜单，用户选择领域
  - 编程模式：传入 DOMAIN 直接进入领域菜单

领域列表（9个，对齐后端）：
  session, context, skill, agent, project, config,
  log, provider, doctor
  （skills: 另通过 text-tools, file-tools 等技能包提供）"
  (interactive)
  (let ((domains '("skill" "session" "context" "agent"
                   "project" "config" "log" "provider"
                   "doctor")))
    (if domain
        ;; 编程模式：直接进入指定领域
        (aiaos-cli-domain-menu domain)
      ;; 交互模式：显示主菜单
      (let ((keys (mapcar #'car domains)))
        (let ((choice
               (completing-read
                "选择领域 (共 9 个，对齐后端): "
                keys
                nil t
                nil
                'aiaos-cli-domain-history)))
          (if (null choice)
              (message "已取消")
            (let ((idx (cl-position choice keys :test #'equal)))
              (if idx
                  (aiaos-cli-domain-menu (nth idx domains))
                (message "无效选择: %S" choice)))))))))

(defvar aiaos-cli-domain-history nil
  "领域选择历史。")

;; ============================================================
;; M-x aiaos 主入口
;; ============================================================

(defun aiaos-cli--app-available-p ()
  "检查 TUI 应用模块是否可用。

R702: 用于决定 aiaos 入口走 TUI 还是菜单模式。"
  (and (fboundp 'aiaos-cli--app-run)
       (fboundp 'aiaos-cli--app-init)))

;;;###autoload
;;;###autoload
(defun aiaos (&optional arg)
  "Launch AIAOS-CLI application.

With optional ARG (non-nil), run in interactive setup menu mode.

R-FIX-READONLY: 修复 M-x aiaos 后 buffer is read-only 的问题。
旧实现默认进入 TUI 展示 buffer（aiaos-cli-app-mode 曾错误设置
`read-only' 而非 `buffer-read-only'，只读状态未被解除），用户
一输入即报 Buffer is read-only，且 TUI 无法与 LLM 交互。
现在默认直接进入可交互的 aiaos-cli-agent 聊天 buffer，可与
LLM provider 对话（C-c C-c 发送）。ARG 非空时仍进入全功能菜单。"
  (interactive "P")
  (aiaos-cli-init t)
  (if arg
      (aiaos-cli-menu-read)
    (aiaos-cli-agent-chat)))

;;;###autoload
(defun aiaos-cli-menu ()
  "Launch AIAOS-CLI full-feature menu (R702)."
  (interactive)
  (aiaos-cli-init t)
  (aiaos-cli-menu-read))

;; 兼容别名：M-x aiaos-cli 也指向同一入口
(defalias 'aiaos-cli 'aiaos)

;;; aiaos-cli-new-commands.el ends here

(provide 'aiaos-cli)

;;; aiaos-cli.el ends here
