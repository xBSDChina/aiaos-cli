;; test-client-verify.el -- emacsclient 端到端验证（不 kill daemon，结果写文件）  -*- lexical-binding: t; -*-
;; 用法: emacsclient --eval '(load-file ".../test-client-verify.el")'
;; 结果写入 /tmp/aiaos-client-verify.log

(defvar aiv--log "/tmp/aiaos-client-verify.log")

(defun aiv--out (fmt &rest args)
  (with-temp-buffer
    (insert (apply #'format fmt args) "\n")
    (append-to-file (point-min) (point-max) aiv--log)))

(defun aiv--check (name thunk)
  (let ((res (condition-case err
                 (let ((v (funcall thunk)))
                   (cons 'ok v))
               (error (cons 'err (format "%S" err))))))
    (if (eq (car res) 'ok)
        (aiv--out "PASS  %-42s => %S" name (cdr res))
      (aiv--out "FAIL  %-42s => %s" name (cdr res)))))

(defun aiv--run ()
  (with-temp-file aiv--log
    (insert (format "=== aiaos emacsclient verify @ %s ===\n" (current-time-string))))
  (aiv--out "server-version: %s" emacs-version)
  (aiv--out "daemonp: %S" (daemonp))

  ;; --- 加载 ---
  (aiv--check "load aiaos-cli.el"
              (lambda () (progn (add-to-list 'load-path (expand-file-name "~/aiaos/aiaos-cli/elisp"))
                                 (load (expand-file-name "~/aiaos/aiaos-cli/elisp/aiaos-cli.el") nil t)
                                 (featurep 'aiaos-cli))))

  ;; --- 入口 ---
  (aiv--check "fboundp aiaos" (lambda () (fboundp 'aiaos)))
  (aiv--check "commandp aiaos" (lambda () (commandp 'aiaos)))
  (aiv--check "alias aiaos-cli -> aiaos" (lambda () (eq (indirect-function 'aiaos-cli)
                                                        (indirect-function 'aiaos))))

  ;; --- 核心基础设施 ---
  (aiv--check "aiaos-cli--assert-binary" (lambda () (aiaos-cli--assert-binary)))
  (aiv--check "aiaos-cli--parse-json" (lambda () (gethash "k" (aiaos-cli--parse-json "{\"k\":\"v\"}"))))
  (aiv--check "aiaos-cli--build-cmd session/list"
              (lambda () (aiaos-cli--build-cmd "session" "list" nil)))

  ;; --- 关键变量定义 ---
  (aiv--check "boundp chat-buffer-name" (lambda () (boundp 'aiaos-cli-chat-buffer-name)))
  (aiv--check "chat-buffer-name value" (lambda () aiaos-cli-chat-buffer-name))
  (aiv--check "fboundp agent-mode" (lambda () (fboundp 'aiaos-cli-agent-mode)))

  ;; --- 真正调用 M-x aiaos（关键：验证不改 buffer 名字/模式臆测） ---
  (aiv--check "call (aiaos) and inspect buffer"
              (lambda ()
                (save-window-excursion
                  (aiaos)
                  (list :buf (buffer-name)
                        :mode (symbol-name major-mode)
                        :readonly (if buffer-read-only t nil)))))

  ;; --- 菜单/交互函数存在性 ---
  (aiv--check "fboundp aiaos-cli-menu" (lambda () (fboundp 'aiaos-cli-menu)))
  (aiv--check "fboundp aiaos-cli-agent-send" (lambda () (fboundp 'aiaos-cli-agent-send)))
  (aiv--check "fboundp aiaos-cli-agent-history" (lambda () (fboundp 'aiaos-cli-agent-history)))

  ;; --- LLM 后端（可选能力） ---
  (aiv--check "fboundp aiaos-llm-chat (or similar)"
              (lambda () (list (fboundp 'aiaos-llm-chat)
                               (fboundp 'aiaos-cli-llm-chat)
                               (fboundp 'aiaos-cli-llm-request))))

  (aiv--out "=== DONE ==="))

(aiv--run)
(provide 'test-client-verify)
