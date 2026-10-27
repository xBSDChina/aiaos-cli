;;; format.el --- emacs-tools skill: format command -*- lexical-binding: t; -*-
;;;
;;; 文本折行工具，符合 §3.3 返回规范。

(eval-when-compile (require 'cl-lib))

;;;###autoload
(defun aiaos-cli-skill-emacs-tools/format (args &rest options)
  "Wrap TEXT to WIDTH columns with optional INDENT.

ARGS is a plist with :text and :width.
OPTIONS is a plist with :indent (integer, default 0).

Returns plist with :status :skill :command :timestamp as required."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (text (plist-get args :text))
         (width (plist-get args :width))
         (indent (or (plist-get opts :indent) 0)))
    (unless (stringp text)
      (error "aiaos-cli-skill-emacs-tools/format: missing :text"))
    (unless (and (integerp width) (> width 0))
      (error "aiaos-cli-skill-emacs-tools/format: invalid :width"))
    (unless (and (integerp indent) (>= indent 0))
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