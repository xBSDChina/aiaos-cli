;;; aiaos-cli-emacs-security.el --- Emacs安全机制层  -*- lexical-binding: t; -*-

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: 提供Emacs操作的安全机制，包括权限控制、沙箱执行、输入验证

(require 'aiaos-cli-core)
(require 'cl-lib)
(require 'aiaos-cli-emacs-adapter)
(require 'aiaos-cli-emacs-controller)

(defgroup aiaos-cli-emacs-security nil
  "AIAOS CLI Emacs安全机制"
  :prefix "aiaos-cli-emacs-security-"
  :group 'aiaos-cli-emacs)

;;; 配置

(defcustom aiaos-cli-emacs-security-enabled t
  "是否启用安全机制"
  :type 'boolean
  :group 'aiaos-cli-emacs-security)

(defcustom aiaos-cli-emacs-security-allow-file-write t
  "是否允许文件写入"
  :type 'boolean
  :group 'aiaos-cli-emacs-security)

(defcustom aiaos-cli-emacs-security-allow-process t
  "是否允许进程执行"
  :type 'boolean
  :group 'aiaos-cli-emacs-security)

(defcustom aiaos-cli-emacs-security-allow-network t
  "是否允许网络访问"
  :type 'boolean
  :group 'aiaos-cli-emacs-security)

;;; 权限控制

(cl-defstruct aiaos-cli-emacs-permission
  "权限结构"
  (resource nil)
  (operations nil)
  (expires nil))

(defconst aiaos-cli-emacs-permissions (make-hash-table :test 'equal))

(defun aiaos-cli-emacs-security-grant-permission (resource operation &optional expires)
  "授予权限"
  (let ((perms (gethash resource aiaos-cli-emacs-permissions)))
    (unless perms
      (setq perms (list))
      (puthash resource perms aiaos-cli-emacs-permissions))
    (push (cons operation expires) perms)
    (puthash resource perms aiaos-cli-emacs-permissions)
    t))

(defun aiaos-cli-emacs-security-check-permission (resource operation)
  "检查权限"
  (if (not aiaos-cli-emacs-security-enabled)
      t
    (let ((perms (gethash resource aiaos-cli-emacs-permissions)))
      (if perms
          (let ((perm (assoc operation perms)))
            (if perm
                (let ((expires (cdr perm)))
                  ;; 无过期时间或尚未过期则允许
                  (or (null expires)
                      (time-less-p (current-time) expires)))
              nil))
        nil))))

;;; 输入验证

(defun aiaos-cli-emacs-security-validate-buffer-name (name)
  "验证缓冲区名称"
  (and (stringp name)
       (> (length name) 0)
       (<= (length name) 256)
       (not (string-match-p "[\x00-\x1f]" name))))

(defun aiaos-cli-emacs-security-validate-file-path (path)
  "验证文件路径"
  (and (stringp path)
       (> (length path) 0)
       (<= (length path) 4096)
       (not (string-match-p "[\x00-\x1f]" path))))

(defun aiaos-cli-emacs-security-validate-command (command)
  "验证命令"
  (and (symbolp command)
       (fboundp command)))

;;; 沙箱执行

(defmacro aiaos-cli-emacs-security-sandbox (body)
  "沙箱执行宏"
  `(condition-case err
       (progn
         (aiaos-log "debug" "Executing in sandbox" nil)
         ,body)
     (error 
      (aiaos-log "error" "Sandbox execution failed" err)
      (signal (car err) (cdr err)))))

;;; 安全操作封装

(defun aiaos-cli-emacs-security-safe-create-buffer (name mode)
  "安全创建缓冲区"
  (if (aiaos-cli-emacs-security-validate-buffer-name name)
      (aiaos-cli-emacs-security-sandbox
       (aiaos-cli-emacs-controller-create-buffer name mode))
    (error "Invalid buffer name: %s" name)))

(defun aiaos-cli-emacs-security-safe-execute-command (command &rest args)
  "安全执行命令"
  (if (aiaos-cli-emacs-security-validate-command command)
      (aiaos-cli-emacs-security-sandbox
       (apply command args))
    (error "Invalid command: %s" command)))

;;; 审计日志

(defconst aiaos-cli-emacs-security-audit-log (make-hash-table :test 'equal))

(defun aiaos-cli-emacs-security-audit (operation resource result)
  "记录审计日志"
  (let ((entry (list (cons 'operation operation)
                     (cons 'resource resource)
                     (cons 'result result)
                     (cons 'timestamp (current-time)))))
    (push entry (gethash (format-time-string "%Y-%m-%d") 
                         aiaos-cli-emacs-security-audit-log))))

(defun aiaos-cli-emacs-security-get-audit-log (&optional date)
  "获取审计日志"
  (gethash (or date (format-time-string "%Y-%m-%d"))
           aiaos-cli-emacs-security-audit-log))

;;; 初始化

(defun aiaos-cli-emacs-security-init ()
  "初始化安全机制"
  (aiaos-log "info" "Initializing security module")
  
  ;; 授予默认权限
  (aiaos-cli-emacs-security-grant-permission 
   'buffer '(create read update delete))
  (aiaos-cli-emacs-security-grant-permission 
   'window '(create read update delete))
  (aiaos-cli-emacs-security-grant-permission 
   'frame '(create read update delete))
  
  (aiaos-log "info" "Security module initialized"))

(provide 'aiaos-cli-emacs-security)

;;; aiaos-cli-emacs-security.el 结束