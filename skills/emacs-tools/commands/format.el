;;; format.el --- emacs-tools skill: format command -*- lexical-binding: t; -*-
;;;
;;; 文本折行工具，符合 §3.3 返回规范。

(eval-when-compile (require 'cl-lib))

;;;###autoload
(defun aiaos-cli-skill-emacs-tools/format (args &rest options)
  "Wrap TEXT to WIDTH columns with optional INDENT.

ARGS is a plist with :text and :width.
OPTIONS is a plist with :indent (integer, default 0).

Returns plist with :status :skill :command :timestamp as required.
R9001: 参数类型转换契约修复，接受 string/number，自动转换。"
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (raw (plist-get args :text))
         (text (cond ((stringp raw) raw)
                     ((numberp raw) (format "%s" raw))
                     (t nil)))
         (raw-width (plist-get args :width))
         (width (cond ((stringp raw-width) (string-to-number raw-width))
                      ((numberp raw-width) raw-width)
                      (t nil)))
         (raw-indent (plist-get opts :indent))
         (indent (cond ((stringp raw-indent) (string-to-number raw-indent))
                       ((numberp raw-indent) raw-indent)
                       (t 0))))
    (unless text
      (error "aiaos-cli-skill-emacs-tools/format: missing :text"))
    (unless (and width (numberp width) (> width 0))
      (error "aiaos-cli-skill-emacs-tools/format: invalid :width"))
    (unless (and (numberp indent) (>= indent 0))
      (error "aiaos-cli-skill-emacs-tools/format: invalid :indent"))
    (let ((lines (split-string text "\n" nil))
          (all-chunks '()))
      (dolist (line lines)
        (let ((col 0)
              (chunks '()))
          (while (< col (length line))
            (push (substring line col (min (+ col width) (length line))) chunks)
            (setq col (+ col width)))
          (setq chunks (nreverse chunks))
          (setq all-chunks (append all-chunks chunks))))
      (list :status "ok"
            :width width
            :indent indent
            :line-count (length all-chunks)
            :output (mapconcat 'identity all-chunks "\n")
            :skill "emacs-tools"
            :command "format"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))

(provide 'aiaos-cli-skill-emacs-tools/format)
