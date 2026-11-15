;;; wordcount.el --- text-tools skill: wordcount command -*- lexical-binding: t; -*-

;;;###autoload
(require 'cl-lib)

(defun aiaos-cli-skill-text-tools/wordcount (args &rest options)
  "Count words/chars/lines in text.

ARGS is a plist with :text.
OPTIONS is a plist with :split (delimiter string, default whitespace).
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
         (split (or (plist-get opts :split) "[ \t\n]+"))
         words words-nonempty n-words n-chars n-lines unique)
    (unless text
      (error "aiaos-cli-skill-text-tools/wordcount: missing :text"))
    (setf words (split-string text split))
    (setf words-nonempty (cl-remove-if (lambda (w) (string= w "")) words))
    (setf n-words (length words-nonempty))
    (setf n-chars (length text))
    (setf n-lines (length (split-string text "\n")))
    (setf unique (length (cl-delete-duplicates words-nonempty :test #'string=)))
    (list :status "ok"
          :words n-words
          :chars n-chars
          :lines n-lines
          :unique unique
          :skill "text-tools"
          :command "wordcount"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-text-tools/wordcount)
