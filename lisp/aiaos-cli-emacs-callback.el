;;; aiaos-cli-emacs-callback.el --- Emacs回调层

;; 版本: 1.0
;; 作者: AIAOS CLI
;; 描述: 处理Emacs到AIAOS CLI的回调和事件

(require 'aiaos-cli-emacs-controller)
(require 'aiaos-cli-core)

(defgroup aiaos-cli-emacs-callback nil
  "AIAOS CLI Emacs回调层"
  :prefix "aiaos-cli-emacs-callback-")

;;; 事件类型定义

(defconst aiaos-cli-emacs-callback-events
  '(buffer-created buffer-switched buffer-modified
                  frame-created frame-selected window-split window-selected
                  mode-changed major-mode-changed after-save-hook
                  post-command-hook before-command-hook))

;;; 回调注册表

(defconst aiaos-cli-emacs-callback-table (make-hash-table :test 'equal))

;;; 回调管理

(defun aiaos-cli-emacs-callback-register (event-type callback)
  "注册事件回调"
  (let ((callbacks (gethash event-type aiaos-cli-emacs-callback-table)))
    (unless callbacks
      (setq callbacks (list callback))
      (puthash event-type callbacks aiaos-cli-emacs-callback-table))
    (push callback callbacks)
    (puthash event-type callbacks aiaos-cli-emacs-callback-table)
    (aiaos-cli-emacs-callback-setup-hook event-type)))

(defun aiaos-cli-emacs-callback-unregister (event-type callback)
  "注销事件回调"
  (let ((callbacks (gethash event-type aiaos-cli-emacs-callback-table)))
    (when callbacks
      (setq callbacks (delete callback callbacks))
      (puthash event-type callbacks aiaos-cli-emacs-callback-table))))

(defun aiaos-cli-emacs-callback-trigger (event-type &rest args)
  "触发事件回调"
  (let ((callbacks (gethash event-type aiaos-cli-emacs-callback-table)))
    (dolist (callback callbacks)
      (condition-case err
          (apply callback args)
        (error (aiaos-log "error" "Callback failed" err))))))

;;; Hook设置

(defun aiaos-cli-emacs-callback-setup-hook (event-type)
  "为事件类型设置Hook"
  (pcase event-type
    ('buffer-created
     (add-hook 'after-save-hook 'aiaos-cli-emacs-callback-buffer-saved))
    ('buffer-switched
     (add-hook 'switch-buffer-hook 'aiaos-cli-emacs-callback-buffer-switched))
    ('buffer-modified
     (add-hook 'after-revert-hook 'aiaos-cli-emacs-callback-buffer-modified))
    ('frame-created
     (add-hook 'after-make-frame-hook 'aiaos-cli-emacs-callback-frame-created))
    ('frame-selected
     (add-hook 'frame-switch-buffer-hook 'aiaos-cli-emacs-callback-frame-selected))
    ('mode-changed
     (add-hook 'major-mode-hook 'aiaos-cli-emacs-callback-mode-changed))
    ('after-save
     (add-hook 'after-save-hook 'aiaos-cli-emacs-callback-buffer-saved))
    ('post-command
     (add-hook 'post-command-hook 'aiaos-cli-emacs-callback-post-command))
    (_ (aiaos-log "warning" "Unknown event type" event-type))))

;;; 具体Hook实现

(defun aiaos-cli-emacs-callback-buffer-saved ()
  "缓冲区保存后回调"
  (aiaos-cli-emacs-callback-trigger 'after-save (current-buffer)))

(defun aiaos-cli-emacs-callback-buffer-switched ()
  "缓冲区切换后回调"
  (aiaos-cli-emacs-callback-trigger 'buffer-switched (current-buffer)))

(defun aiaos-cli-emacs-callback-buffer-modified ()
  "缓冲区修改后回调"
  (aiaos-cli-emacs-callback-trigger 'buffer-modified (current-buffer)))

(defun aiaos-cli-emacs-callback-frame-created ()
  "帧创建后回调"
  (aiaos-cli-emacs-callback-trigger 'frame-created (selected-frame)))

(defun aiaos-cli-emacs-callback-frame-selected ()
  "帧选择后回调"
  (aiaos-cli-emacs-callback-trigger 'frame-selected (selected-frame)))

(defun aiaos-cli-emacs-callback-mode-changed ()
  "模式改变后回调"
  (aiaos-cli-emacs-callback-trigger 'mode-changed major-mode))

(defun aiaos-cli-emacs-callback-post-command ()
  "命令执行后回调"
  (aiaos-cli-emacs-callback-trigger 'post-command this-command))

;;; 同步到AIAOS CLI

(defun aiaos-cli-emacs-callback-sync-to-aiaos (event-type &rest args)
  "同步事件到AIAOS CLI"
  (aiaos-log "info" "Emacs event" (list (cons 'event-type event-type)
                                        (cons 'buffer (current-buffer))
                                        (cons 'frame (selected-frame))
                                        (cons 'mode major-mode))))

(provide 'aiaos-cli-emacs-callback)

;;; aiaos-cli-emacs-callback.el 结束