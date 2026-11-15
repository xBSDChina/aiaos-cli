;;; stats.el --- emacs-tools skill: stats command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-emacs-tools/stats (args &rest _options)
  "Return character/word/line/byte statistics of TEXT.
ARGS is a plist with :text.
Returns plist with :status :skill :command :timestamp as required."
  (let* ((text (plist-get args :text)))
    (unless (stringp text)
      (error "aiaos-cli-skill-emacs-tools/stats: missing :text"))
    (let* ((chars (length text))
           (bytes (length (encode-coding-string text 'utf-8)))
           (lines (split-string text "\n" nil))
           (line-count (length lines))
           (words (split-string text "[ \t\n]+" nil))
           (word-count (length words)))
      (list :status "ok"
            :chars chars
            :bytes bytes
            :lines line-count
            :words word-count
            :avg-line-length (if (= line-count 0) 0 (/ (float chars) line-count))
            :skill "emacs-tools"
            :command "stats"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))

(provide 'aiaos-cli-skill-emacs-tools/stats)
