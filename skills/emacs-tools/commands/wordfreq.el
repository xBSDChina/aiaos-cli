;;; wordfreq.el --- emacs-tools skill: word frequency command -*- lexical-binding: t; -*-
;;;
;;; 统计文本中词频（返回 top-N），符合 §3.3 返回规范。

(eval-when-compile (require 'cl-lib))

(defun aiaos-cli--hash-table-to-list (ht)
  "Convert hash table HT to alist."
  (let ((result '()))
    (maphash (lambda (k v) (push (cons k v) result)) ht)
    result))

(defun aiaos-cli--make-freq-entry (word count)
  "Create a freq entry plist for WORD and COUNT."
  (list :word word :count count))

;;;###autoload
(defun aiaos-cli-skill-emacs-tools/wordfreq (args &rest options)
  "Return top-N word frequencies of TEXT.

ARGS is a plist with :text.
OPTIONS is a plist with :top (integer, default 10).

Returns plist with :status :skill :command :timestamp as required."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (text (plist-get args :text))
         (top (or (plist-get opts :top) 10)))
    (unless (stringp text)
      (error "aiaos-cli-skill-emacs-tools/wordfreq: missing :text"))
    (unless (and (integerp top) (> top 0))
      (error "aiaos-cli-skill-emacs-tools/wordfreq: invalid :top"))
    (let* ((words (split-string text "[^[:alpha:]]+" t))
           (freqs (make-hash-table :test 'equal))
           (total 0))
      (dolist (w words)
        (when (string-match "[[:alpha:]]" w)
          (let ((lw (downcase w)))
            (puthash lw (1+ (or (gethash lw freqs 0) 0)) freqs)
            (setq total (1+ total)))))
      (let* ((pairs (aiaos-cli--hash-table-to-list freqs))
             (sorted (seq-take (sort pairs (lambda (a b) (> (cdr a) (cdr b)))) top))
             (freq-list (mapcar (lambda (p)
                                  (aiaos-cli--make-freq-entry (car p) (cdr p)))
                                sorted)))
        (list :status "ok"
              :input text
              :input-length (length text)
              :top top
              :total-words total
              :unique-words (hash-table-count freqs)
              :frequencies freq-list
              :skill "emacs-tools"
              :command "wordfreq"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))))

(provide 'aiaos-cli-skill-emacs-tools/wordfreq)