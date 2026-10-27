;;; wordcount.el --- text-tools skill: wordcount command -*- lexical-binding: t; -*-

;;;###autoload
(require 'cl-lib)

(defun aiaos-cli-skill-text-tools/wordcount (args &rest options)
  "Count words/chars/lines in text.

ARGS is a plist with :text.
OPTIONS is a plist with :split (delimiter string, default whitespace)."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (text (plist-get args :text))
         (split (or (plist-get opts :split) " ")))
    (unless (stringp text)
      (error "aiaos-cli-skill-text-tools/wordcount: missing :text"))
    (let* (words words-nonempty n-words n-chars n-lines unique)
      (setf words (if (string= split " ")
                      (split-string text "[[:space:]]+" t)
                    (split-string text split t)))
      (setf words-nonempty (cl-remove "" words :test #'string=))
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
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))

(provide 'aiaos-cli-skill-text-tools/wordcount)