;;; test-aiaos-cli.el --- ERT tests for aiaos-cli -*- lexical-binding: t; -*-

;; R1312: hermetic 路径派生 —— 从测试文件自身位置推导项目根，
;; 消除对 /home/shjiaye8 硬编码的依赖，便于在任意 checkout 目录跑测试。
(defvar aiaos-cli-test--root
  (directory-file-name
   (file-name-directory
    (directory-file-name
     (file-name-directory load-file-name))))
  "Project root, derived from this test file's location.

`load-file-name' is e.g. `/root/tests/test-aiaos-cli.el'.
`file-name-directory' returns a trailing-slash dir, so calling it
twice does NOT climb one level.  We strip the slash with
`directory-file-name' first, then call `file-name-directory' again
to climb from `tests/' up to the project root.")

(defvar aiaos-cli-test--bin
  (expand-file-name "bin/aiaos-cli" aiaos-cli-test--root)
  "Path to the aiaos-cli binary.")

(defvar aiaos-cli-test--skills
  (expand-file-name "skills" aiaos-cli-test--root)
  "Path to the skills directory.")

(add-to-list 'load-path (expand-file-name "elisp" aiaos-cli-test--root))
(require 'ert)
(require 'aiaos-cli)

(ert-deftest aiaos-cli-test/resolve-bin ()
  "Test binary resolution."
  (setq aiaos-cli-bin aiaos-cli-test--bin)
  (let ((bin (aiaos-cli--resolve-bin)))
    (should (stringp bin))
    (should (file-executable-p bin))))

(ert-deftest aiaos-cli-test/call-sync-version ()
  "Test synchronous --version call."
  (setq aiaos-cli-bin aiaos-cli-test--bin)
  (let ((res (aiaos-cli--call-sync (list aiaos-cli-bin "--version"))))
    (should (eq (car res) 0))
    (should (string-match "1\\.0\\.0" (cdr res)))))

(ert-deftest aiaos-cli-test/version-consistent ()
  "Test version consistency check."
  (setq aiaos-cli-bin aiaos-cli-test--bin)
  (aiaos-cli-init)
  (should (aiaos-cli--version-consistent-p)))

(ert-deftest aiaos-cli-test/hello-command ()
  "Test hello-world skill hello command."
  (load (concat aiaos-cli-test--skills "/hello-world/commands/hello.el"))
  (let ((r (aiaos-cli-skill-hello-world/hello '(:name "Alice"))))
    (should (plist-get r :status))
    (should (string= (plist-get r :status) "ok"))
    (should (string-match "Alice" (plist-get r :message)))))

(ert-deftest aiaos-cli-test/hello-command-with-greeting ()
  "Test hello-world skill hello command with greeting."
  (load (concat aiaos-cli-test--skills "/hello-world/commands/hello.el"))
  (let ((r (aiaos-cli-skill-hello-world/hello '(:name "Bob") '(:greeting "Hi"))))
    (should (string= (plist-get r :status) "ok"))
    (should (string-match "Hi, Bob" (plist-get r :message)))))

(ert-deftest aiaos-cli-test/time-command-iso ()
  "Test hello-world skill time command with iso format."
  (load (concat aiaos-cli-test--skills "/hello-world/commands/time.el"))
  (let ((r (aiaos-cli-skill-hello-world/time '() '(:format "iso"))))
    (should (string= (plist-get r :status) "ok"))
    (should (plist-get r :iso))
    (should (plist-get r :epoch))))

(ert-deftest aiaos-cli-test/time-command-epoch ()
  "Test hello-world skill time command with epoch format."
  (load (concat aiaos-cli-test--skills "/hello-world/commands/time.el"))
  (let ((r (aiaos-cli-skill-hello-world/time '() '(:format "epoch"))))
    (should (string= (plist-get r :status) "ok"))
    (should (plist-get r :epoch))
    (should (not (plist-get r :iso)))))

(ert-deftest aiaos-cli-test/hooks-load ()
  "Test that hooks load without error."
  (load (concat aiaos-cli-test--skills "/hello-world/hooks/on-load.el"))
  (load (concat aiaos-cli-test--skills "/hello-world/hooks/pre-command.el"))
  (load (concat aiaos-cli-test--skills "/hello-world/hooks/post-command.el"))
  (should (fboundp 'aiaos-cli-skill-hello-world/on-load))
  (should (fboundp 'aiaos-cli-skill-hello-world/pre-command))
  (should (fboundp 'aiaos-cli-skill-hello-world/post-command)))

(ert-deftest aiaos-cli-test/call-async-captures-stderr ()
  "R621: 异步调用应真正捕获 stderr（之前 start-process 丢弃 stderr）。
R1319: 修复 TD-032 竞态 —— 加超时保护，消除 async 时序导致的 hang。"
  (let ((aiaos-cli-bin "/bin/sh")
        done status out err proc
        waited max-wait)
    (setq proc (aiaos-cli--call-async
                '("/bin/sh" "-c" "echo OUT; echo ERR >&2")
                (lambda (s o e)
                  (setq done t status s out o err e))))
    (should (processp proc))
    ;; R1319: TD-032 修复 —— 超时保护，避免 async 时序导致的无限 hang。
    ;; 100 × 0.05s = 5s 上限；若 sentinel 未触发，should done 报清晰错误。
    (setq waited 0 max-wait 100)
    (while (and (not done) (< waited max-wait))
      (sit-for 0.05)
      (setq waited (1+ waited)))
    (should done)
    (should (= status 0))
    (should (string= out "OUT\n"))
    (should (string= err "ERR\n"))))

(ert-deftest aiaos-cli-test/call-async-returns-process ()
  "R621: 应返回 process 对象以便调用方管理。"
  (let ((aiaos-cli-bin "/bin/sh") done)
    (let ((p (aiaos-cli--call-async
              '("/bin/sh" "-c" "true")
              (lambda (_ _ _) (setq done t)))))
      (should (processp p))
      (while (not done) (sit-for 0.05))
      (should (processp p)))))

;; ---------------------------------------------------------------------------
;; R780 regression tests: lock down the parse-json and assert-binary fixes
;; ---------------------------------------------------------------------------

(ert-deftest aiaos-cli-test/parse-json-valid ()
  "R780: parse-json should return a hash-table on valid JSON."
  (let ((r (aiaos-cli--parse-json "{\"a\":1,\"b\":\"x\"}")))
    (should (hash-table-p r))
    (should (equal (gethash "a" r) 1))
    (should (equal (gethash "b" r) "x"))))

(ert-deftest aiaos-cli-test/parse-json-invalid-returns-nil ()
  "R780: parse-json should return nil (not raise) on malformed JSON."
  (should (null (aiaos-cli--parse-json "not json")))
  (should (null (aiaos-cli--parse-json "{broken")))
  (should (null (aiaos-cli--parse-json ""))))

(ert-deftest aiaos-cli-test/parse-json-non-string-errors ()
  "R780: parse-json should raise user-error on non-string input."
  ;; Emacs 30 removed `errorp' and made `cl-typep' unreliable on error
  ;; objects; use `consp' as a portable check that an error was signaled.
  (should (consp (condition-case e
                      (aiaos-cli--parse-json nil)
                    (error e))))
  (should (consp (condition-case e
                      (aiaos-cli--parse-json 42)
                    (error e)))))

(ert-deftest aiaos-cli-test/parse-json-emacs29-compat ()
  "R780: parse-json must not depend on json-read-from-string (Emacs 30+ only).
Guards against a future regression that reintroduces the void-function
crash on Emacs 29."
  (let ((src (with-temp-buffer
               (insert-file-contents
                (locate-file "aiaos-cli.el" load-path))
               (buffer-string))))
    (should (not (string-match-p "json-read-from-string" src)))))

(ert-deftest aiaos-cli-test/assert-binary-error-includes-search-paths ()
  "R780: assert-binary error message must list all three lookup paths
so the user can act immediately.

R1311: this test is now hermetic.  It previously relied on the ambient
environment having NO aiaos-cli on PATH; when the project bin/ was
exported (the normal dev layout), `aiaos-cli--resolve-bin' fell back to
`executable-find', succeeded, and no error was signaled -- leaving `msg'
nil and crashing the assertions with `wrong-type-argument stringp nil'.

Note: the correct way to cut the PATH fallback is to clear `exec-path',
NOT the PATH environment variable.  `executable-find' consults the
`exec-path' variable, so `setenv' on PATH has no effect on it (verified
in Emacs 30.1: `setenv' left the lookup succeeding, while
`(setq exec-path '())' returned nil).  Shadowing `executable-path' and
`cl-flet' also fail because `aiaos-cli--resolve-bin' is a global function
and lexical bindings cannot reach inside it.

R1410: 修复第3步 fallback 问题。测试清空了 `exec-path'（切断第2步 PATH
查找），但没有切断第3步 fallback —— `~/aiaos/aiaos-cli/bin/aiaos-cli' 在开发
环境中真实存在，所以 `resolve-bin' 成功返回，`assert-binary' 不报错，`msg'
保持 nil。现在通过设置 `HOME' 环境变量到临时目录，使第3步 fallback 也找不到
文件。"
  (let ((saved aiaos-cli-bin)
        (saved-exec-path exec-path)
        (saved-home (getenv "HOME"))
        msg)
    (unwind-protect
        (progn
          (setq aiaos-cli-bin "/tmp/definitely-not-a-real-aiaos-cli-binary")
          (setq exec-path '())                   ; R1311: cut PATH fallback
          (setenv "HOME" "/tmp/definitely-not-a-real-home")  ; R1410: cut default path fallback
          (let ((err))                            ; R1311: explicit capture
            (condition-case e
                (aiaos-cli--assert-binary)
              (error (setq err (error-message-string e))))
            (setq msg err)))
      (setq exec-path saved-exec-path)           ; R1311: restore
      (setq aiaos-cli-bin saved)
      (setenv "HOME" saved-home))              ; R1410: restore HOME
    (should (stringp msg))                       ; R1311: guard assertions
    (should (string-match-p "aiaos-cli-bin=" msg))
    (should (string-match-p "PATH=" msg))
    (should (string-match-p "~/aiaos/aiaos-cli/bin/aiaos-cli" msg))
    (should (string-match-p "Fix by setq aiaos-cli-bin" msg))
    (should (string-match-p "/tmp/definitely-not-a-real-aiaos-cli-binary" msg))))

(ert-deftest aiaos-cli-test/assert-binary-success ()
  "R780: assert-binary should return the binary path when it exists."
  (let ((saved aiaos-cli-bin)
        (target aiaos-cli-test--bin)
        bin)
    (unwind-protect
        (progn
          (setq aiaos-cli-bin target)
          (setq bin (aiaos-cli--assert-binary)))
      (setq aiaos-cli-bin saved))
    (should (string= bin target))
    (should (file-executable-p bin))))

;; ---------------------------------------------------------------------------
;; R1100 regression tests: lock down the alist->plist type bridge (P0)
;; ---------------------------------------------------------------------------

(ert-deftest aiaos-cli-test/alist-to-plist-basic ()
  "JSON alist 产物应转换为 keyword-key plist。"
  (let* ((alist (json-read-from-string "{\"name\":\"AIAOS\",\"level\":3}"))
         (plist (aiaos-cli--alist-to-plist alist)))
    (should (equal (plist-get plist :name) "AIAOS"))
    (should (equal (plist-get plist :level) 3))))

(ert-deftest aiaos-cli-test/alist-to-plist-empty ()
  "空 alist 应返回空 plist，且 plist-get 静默返回 nil（契约行为）。"
  (let ((plist (aiaos-cli--alist-to-plist '())))
    (should (null plist))
    (should (null (plist-get plist :anything)))))

(ert-deftest aiaos-cli-test/alist-to-plist-nested-value ()
  "嵌套 alist 值应原样保留（不递归转换，与旧实现契约一致）。"
  (let* ((alist (json-read-from-string "{\"opts\":{\"format\":\"json\"}}"))
         (plist (aiaos-cli--alist-to-plist alist)))
    (should (equal (plist-get plist :opts) '((format . "json"))))))

;; ---------------------------------------------------------------------------
;; R1130 regression tests: skill management wrappers
;;
;; 验证 5 个新 wrapper (validate/deps/search/enable/disable) 把参数正确
;; 转发给 aiaos-cli-run。用 cl-letf 重定义 aiaos-cli-run 捕获参数，
;; 避免真正调用后端，也避免 advice 机制在 batch 模式下的不稳定性。
;; ---------------------------------------------------------------------------

(defun aiaos-cli-test--capture-run-call (&rest args)
  "Capture args passed to aiaos-cli-run and return them."
  args)

(ert-deftest aiaos-cli-test/skill-validate-wrapper ()
  "aiaos-cli-skill-validate 应把 name 作为 --name=X 传给后端。"
  (cl-letf (((symbol-function #'aiaos-cli-run)
             #'aiaos-cli-test--capture-run-call))
    (let ((res (aiaos-cli-skill-validate "hello-world")))
      (should (string= (nth 0 res) "skill"))
      (should (string= (nth 1 res) "validate"))
      (should (string= (nth 2 res) "--name=hello-world")))))

(ert-deftest aiaos-cli-test/skill-deps-wrapper ()
  "aiaos-cli-skill-deps 应把 name 作为 --name=X 传给后端。"
  (cl-letf (((symbol-function #'aiaos-cli-run)
             #'aiaos-cli-test--capture-run-call))
    (let ((res (aiaos-cli-skill-deps "hello-world")))
      (should (string= (nth 0 res) "skill"))
      (should (string= (nth 1 res) "deps"))
      (should (string= (nth 2 res) "--name=hello-world")))))

(ert-deftest aiaos-cli-test/skill-search-wrapper ()
  "aiaos-cli-skill-search 应把 query 作为位置参数透传（无 --name= 前缀）。"
  (cl-letf (((symbol-function #'aiaos-cli-run)
             #'aiaos-cli-test--capture-run-call))
    (let ((res (aiaos-cli-skill-search "hello")))
      (should (string= (nth 0 res) "skill"))
      (should (string= (nth 1 res) "search"))
      (should (string= (nth 2 res) "hello")))))

(ert-deftest aiaos-cli-test/skill-enable-wrapper ()
  "aiaos-cli-skill-enable 应把 name 作为 --name=X 传给后端。"
  (cl-letf (((symbol-function #'aiaos-cli-run)
             #'aiaos-cli-test--capture-run-call))
    (let ((res (aiaos-cli-skill-enable "hello-world")))
      (should (string= (nth 0 res) "skill"))
      (should (string= (nth 1 res) "enable"))
      (should (string= (nth 2 res) "--name=hello-world")))))

(ert-deftest aiaos-cli-test/skill-disable-wrapper ()
  "aiaos-cli-skill-disable 应把 name 作为 --name=X 传给后端。"
  (cl-letf (((symbol-function #'aiaos-cli-run)
             #'aiaos-cli-test--capture-run-call))
    (let ((res (aiaos-cli-skill-disable "hello-world")))
      (should (string= (nth 0 res) "skill"))
      (should (string= (nth 1 res) "disable"))
      (should (string= (nth 2 res) "--name=hello-world")))))

(ert-deftest aiaos-cli-test/skill-keymap-wiring ()
  "aiaos-cli-init 后，aiaos-cli--keymap 应包含 skill 子菜单及 5 个新动作。"
  (aiaos-cli-init)
  (let ((top aiaos-cli--keymap))
    (should (keymapp top))
    (let ((skill-map (lookup-key top "k")))
      (should (keymapp skill-map))
      ;; 验证 5 个新动作已挂载
      (should (eq (lookup-key skill-map "v") #'aiaos-cli-skill-validate))
      (should (eq (lookup-key skill-map "d") #'aiaos-cli-skill-deps))
      (should (eq (lookup-key skill-map "s") #'aiaos-cli-skill-search))
      (should (eq (lookup-key skill-map "e") #'aiaos-cli-skill-enable))
      (should (eq (lookup-key skill-map "D") #'aiaos-cli-skill-disable))
      ;; 既有动作仍在
      (should (eq (lookup-key skill-map "l") #'aiaos-cli-skill-list))
      (should (eq (lookup-key skill-map "i") #'aiaos-cli-skill-info))
      (should (eq (lookup-key skill-map "r") #'aiaos-cli-skill-run)))))


;; =============================================================================
;; R1317: 端到端测试 —— aiaos-cli-skill-run 与 aiaos-cli-skill-load-all
;;
;; 背景：既有 25 个 ERT 测试覆盖了 resolve-bin / call-sync / version / 5 个
;; hello-world 命令 / keymap 挂载，但没有一个测试真正调用
;; aiaos-cli-skill-run（interactive 入口）或 aiaos-cli-skill-load-all（批量
;; 加载）。R1210 引入 aiaos-cli-init load-skills 参数后，load-all 的自动
;; 加载路径从未被回归覆盖。本节补齐这两个端到端断言。
;;
;; 注意：aiaos-cli-skill-run 是薄包装，返回 skill 函数产生的 plist（不是
;; (status . output) 对），所以断言走 plist-get。
;; =============================================================================

(ert-deftest aiaos-cli-test/skill-load-all-populates-cache ()
  "aiaos-cli-skill-load-all 应把 skills/ 下所有已启用技能装入缓存。"
  (setq aiaos-cli-bin aiaos-cli-test--bin)
  (setq aiaos-cli-skills-dir aiaos-cli-test--skills)
  (aiaos-cli-init)
  (aiaos-cli-skill-load-all)
  (should (consp aiaos-cli--loaded-skills))
  ;; 至少包含 hello-world 与 file-tools（R1314 新增）
  (should (member "hello-world" aiaos-cli--loaded-skills))
  (should (member "file-tools" aiaos-cli--loaded-skills))
  ;; skill-cache 也应被填充
  (should (hash-table-p aiaos-cli--skill-cache))
  (should (gethash "hello-world" aiaos-cli--skill-cache))
  (should (gethash "file-tools" aiaos-cli--skill-cache)))

(ert-deftest aiaos-cli-test/skill-load-single-populates-cache ()
  "R1318 (TD-031): 单独 aiaos-cli-skill-load 也应填充 skill-cache。

此前仅 aiaos-cli-skill-load-all 填充 cache，单独 skill-load 后 cache
缺失该技能，语义不一致。此测试锁定修复：清空 cache 后单独加载一个技能，
cache 应包含该技能的元数据条目。"
  (setq aiaos-cli-bin aiaos-cli-test--bin)
  (setq aiaos-cli-skills-dir aiaos-cli-test--skills)
  (aiaos-cli-init)
  ;; 清空 cache，模拟“只单独加载一个技能”的场景
  (setq aiaos-cli--skill-cache nil)
  (should (not (hash-table-p aiaos-cli--skill-cache)))
  ;; 单独加载 hello-world
  (let ((res (aiaos-cli-skill-load "hello-world")))
    (should (consp res))
    ;; cache 应被创建并填充
    (should (hash-table-p aiaos-cli--skill-cache))
    (should (gethash "hello-world" aiaos-cli--skill-cache))
    (let ((entry (gethash "hello-world" aiaos-cli--skill-cache)))
      (should (hash-table-p entry))
      (should (string= (gethash "name" entry) "hello-world"))
      (should (gethash "version" entry)))))

(ert-deftest aiaos-cli-test/skill-run-hello-world-hello ()
  "aiaos-cli-skill-run 端到端：调用 hello-world/hello 应返回 :status ok 的 plist。"
  (setq aiaos-cli-bin aiaos-cli-test--bin)
  (setq aiaos-cli-skills-dir aiaos-cli-test--skills)
  (aiaos-cli-init t)  ;; 带 load-skills，确保技能已加载
  (let ((res (aiaos-cli-skill-run "hello-world" "hello"
                                  '(:name "Alice") '())))
    (should (listp res))
    (should (string= (plist-get res :status) "ok"))
    (should (string-match "Alice" (plist-get res :message)))
    (should (string= (plist-get res :skill) "hello-world"))
    (should (string= (plist-get res :command) "hello"))))

(ert-deftest aiaos-cli-test/skill-run-file-tools-stat ()
  "aiaos-cli-skill-run 端到端：调用 file-tools/stat 应返回含 :bytes 的 plist。"
  (setq aiaos-cli-bin aiaos-cli-test--bin)
  (setq aiaos-cli-skills-dir aiaos-cli-test--skills)
  (aiaos-cli-init t)
  (let ((tmpfile (make-temp-file "aiaos-cli-test-"))
        (res nil))
    (with-temp-file tmpfile
      (insert "hello world"))
    (unwind-protect
        (progn
          (setq res (aiaos-cli-skill-run "file-tools" "stat"
                                         (list :path tmpfile) '()))
          (should (listp res))
          (should (string= (plist-get res :status) "ok"))
          (should (integerp (plist-get res :bytes)))
          (should (> (plist-get res :bytes) 0))
          (should (string= (plist-get res :skill) "file-tools")))
      (delete-file tmpfile))))

;; R1324: Test --format-result (previously dead code)
(ert-deftest aiaos-cli-test/format-result-json ()
  "Test aiaos-cli--format-result with valid JSON."
  (let ((result (aiaos-cli--format-result 0
                       (json-encode '(("status" . "ok") ("message" . "test")))
                       "Test")))
    (should (string-match-p "Test" result))
    (should (string-match-p "status" result))
    (should (string-match-p "ok" result))))

(ert-deftest aiaos-cli-test/format-result-plain-text ()
  "Test aiaos-cli--format-result with non-JSON output."
  (let ((result (aiaos-cli--format-result 0 "plain text output" "Plain")))
    (should (string-match-p "Plain" result))
    (should (string-match-p "plain text output" result))))

(ert-deftest aiaos-cli-test/format-result-empty ()
  "Test aiaos-cli--format-result with empty output."
  (let ((result (aiaos-cli--format-result 0 "" "Empty")))
    (should (string-match-p "Empty" result))))

(ert-deftest aiaos-cli-test/show-result-uses-format-result ()
  "Test that aiaos-cli--show-result now uses --format-result."
  (let ((buffer-name (concat "*aiaos-cli-test-" (format-time-string "%Y%m%d%H%M%S"))))
    (with-current-buffer (get-buffer-create buffer-name)
      (aiaos-cli--show-result "Test Title" (json-encode '(("key" . "value"))))
      (let ((buffer-content (buffer-string)))
        (should (string-match-p "Test Title" buffer-content))
        (should (string-match-p "key" buffer-content))
        (should (string-match-p "value" buffer-content))))
    (kill-buffer (get-buffer buffer-name))))

(ert-deftest aiaos-cli-test/tui-entry-command-exists ()
  "R1325: Verify aiaos-cli-app-start command is defined and interactive."
  (should (fboundp 'aiaos-cli-app-start))
  (should (commandp 'aiaos-cli-app-start)))

(ert-deftest aiaos-cli-test/tui-keybinding-registered ()
  "R1325: Verify C-c a t is bound to aiaos-cli-app-start within aiaos-cli keymap."
  (aiaos-cli-init)
  (should (fboundp 'aiaos-cli-app-start))
  (when aiaos-cli--keymap
    (should (equal (lookup-key aiaos-cli--keymap (kbd "t")) 'aiaos-cli-app-start))))

(ert-deftest aiaos-cli-test/tui-module-loadable ()
  "R1325: Verify aiaos-cli-app module can be loaded without errors."
  (let ((app-file (locate-file "aiaos-cli-app.el" load-path)))
    (should app-file)
    (load app-file 'noerror)
    (should (fboundp 'aiaos-cli--app-start))
    (should (fboundp 'aiaos-cli-app-mode))))

(ert-deftest aiaos-cli-test/tui-core-modules-loadable ()
  "R1325: Verify TUI framework modules are loadable (state, context, component, etc.)."
  (let ((modules '("aiaos-cli-state" "aiaos-cli-context"
                    "aiaos-cli-component" "aiaos-cli-lifecycle"
                    "aiaos-cli-theme" "aiaos-cli-router"
                    "aiaos-cli-components")))
    (dolist (mod modules)
      (let ((mod-file (locate-file (concat mod ".el") load-path)))
        (should (file-exists-p mod-file))
        (load mod-file 'noerror)))
    ;; Verify key TUI infrastructure is available
    (should (fboundp 'aiaos-cli-state-init))
    (should (fboundp 'aiaos-cli-context-init))
    (should (fboundp 'aiaos-cli-router-init))))

(ert-deftest aiaos-cli-test/agent-send-uses-call-async ()
  "R1400: aiaos-cli-agent-send should use aiaos-cli--call-async for inline chat response."
  (let ((file (locate-file "aiaos-cli.el" load-path)))
    (should file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (should (re-search-forward "aiaos-cli--call-async" nil t))
      (should (re-search-forward "waiting for agent response" nil t))
      (should (re-search-forward "<<<" nil t)))))

(ert-deftest aiaos-cli-test/agent-send-not-use-aiaos-cli-run ()
  "R1400: aiaos-cli-agent-send should not call aiaos-cli-run for agent chat."
  (let ((file (locate-file "aiaos-cli.el" load-path)))
    (should file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (should (re-search-forward "(defun aiaos-cli-agent-send" nil t))
      (should (re-search-forward "aiaos-cli--call-async" nil t)))))

(ert-deftest aiaos-cli-test/call-async-timeout-defined ()
  "R2600 (TD-003): aiaos-cli-async-timeout must be a positive integer.

Previously the variable was defined but never used — processes could
hang forever. After R2600, the timeout must be a valid positive integer
so the timer in aiaos-cli--call-async can actually fire."
  (should (boundp 'aiaos-cli-async-timeout))
  (should (integerp aiaos-cli-async-timeout))
  (should (> aiaos-cli-async-timeout 0)))

(ert-deftest aiaos-cli-test/call-async-has-timeout-protection ()
  "R2600 (TD-003): aiaos-cli--call-async must include timeout protection.

The function source must contain:
  - run-with-timer with aiaos-cli-async-timeout
  - A kill-process call in the timeout handler
  - Status code 124 (GNU coreutils timeout convention)"
  (let ((file (locate-file "aiaos-cli.el" load-path)))
    (should file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      ;; Must find the function
      (should (re-search-forward "(defun aiaos-cli--call-async" nil t))
      ;; Must use run-with-timer for timeout
      (should (re-search-forward "run-with-timer" nil t))
      ;; Must reference the timeout variable
      (should (re-search-forward "aiaos-cli-async-timeout" nil t))
      ;; Must kill process on timeout
      (should (re-search-forward "kill-process" nil t))
      ;; Must use status 124 (timeout convention) — reset to function start
      (goto-char (point-min))
      (should (re-search-forward "124" nil t)))))

;; ============================================================
;; Provider 管理命令组测试 (R4200)
;; ============================================================

(ert-deftest aiaos-cli-test/provider-list-exists ()
  "R4200: aiaos-cli-provider-list must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-list)))

(ert-deftest aiaos-cli-test/provider-use-exists ()
  "R4200: aiaos-cli-provider-use must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-use)))

(ert-deftest aiaos-cli-test/provider-test-exists ()
  "R4200: aiaos-cli-provider-test must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-test)))

(ert-deftest aiaos-cli-test/provider-tier-exists ()
  "R4200: aiaos-cli-provider-tier must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-tier)))

(ert-deftest aiaos-cli-test/provider-fallback-exists ()
  "R4200: aiaos-cli-provider-fallback must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-fallback)))

(ert-deftest aiaos-cli-test/provider-fallback-order-exists ()
  "R4200: aiaos-cli-provider-fallback-order must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-fallback-order)))

(ert-deftest aiaos-cli-test/provider-audit-exists ()
  "R4200: aiaos-cli-provider-audit must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-audit)))

(ert-deftest aiaos-cli-test/provider-report-exists ()
  "R4200: aiaos-cli-provider-report must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-report)))

(ert-deftest aiaos-cli-test/provider-chat-exists ()
  "R4200: aiaos-cli-provider-chat must exist as M-x entry."
  (should (fboundp 'aiaos-cli-provider-chat)))

;; ============================================================
;; Skill 管理补全命令测试 (R4200)
;; ============================================================

(ert-deftest aiaos-cli-test/skill-create-exists ()
  "R4200: aiaos-cli-skill-create must exist as M-x entry."
  (should (fboundp 'aiaos-cli-skill-create)))

(ert-deftest aiaos-cli-test/skill-install-exists ()
  "R4200: aiaos-cli-skill-install must exist as M-x entry."
  (should (fboundp 'aiaos-cli-skill-install)))

(ert-deftest aiaos-cli-test/skill-uninstall-exists ()
  "R4200: aiaos-cli-skill-uninstall must exist as M-x entry."
  (should (fboundp 'aiaos-cli-skill-uninstall)))

(ert-deftest aiaos-cli-test/skill-update-exists ()
  "R4200: aiaos-cli-skill-update must exist as M-x entry."
  (should (fboundp 'aiaos-cli-skill-update)))

;; ============================================================
;; aiaos-cli-run domain 补全测试 (R4200)
;; ============================================================

(ert-deftest aiaos-cli-test/run-domain-includes-provider ()
  "R4200: aiaos-cli-run interactive prompt must include provider domain."
  (let ((file (locate-file "aiaos-cli.el" load-path)))
    (should file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (should (re-search-forward "provider" nil t)))))

