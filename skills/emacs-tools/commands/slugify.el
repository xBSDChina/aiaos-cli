;;; slugify.el --- emacs-tools skill: slugify command -*- lexical-binding: t; -*-
;;;
;;; 将文本转换为 URL-safe slug，符合 §3.3 返回规范。
;;;
;;; R2220 增强：
;;;   - 新增 :unicode 选项，保留非 ASCII 字母/数字（中文、日文、韩文、希腊字母等）
;;;   - 新增 :preserve 选项，允许保留指定字符集
;;;   - 新增返回字段：removed-char-count、kept-char-count、has-unicode
;;;
;;; 处理管线：
;;;   1. 下划线统一替换为分隔符（preserve 中的下划线除外）
;;;   2. 转小写
;;;   3. 逐字符分类：保留字符原样保留；非法字符替换为分隔符
;;;   4. 折叠连续分隔符为单个
;;;   5. 去除首尾分隔符
;;;   6. 可选截断

(defun aiaos-cli--slugify-trim-separator (str sep)
  "Remove leading/trailing SEP from STR."
  (let ((re (format "^%s\\|%s$" (regexp-quote sep) (regexp-quote sep))))
    (replace-regexp-in-string re "" str)))

(defun aiaos-cli--slugify-collapse-sep (str sep)
  "Collapse consecutive SEPs in STR to single SEP."
  (replace-regexp-in-string (format "%s+" (regexp-quote sep)) sep str))

(defun aiaos-cli--slugify-char-keep-p (ch unicode preserve)
  "Return non-nil if CHAR CH should be kept in slug.

UNICODE non-nil means allow non-ASCII letters/digits via Unicode regexp classes.
PRESERVE is a string of extra chars to always keep."
  (cond
   ((member ch (string-to-list preserve)) t)
   ((and (integerp ch) (< ch 128))
    (member ch (string-to-list "abcdefghijklmnopqrstuvwxyz0123456789")))
   (unicode
    (let ((s (string ch)))
      (or (string-match-p "[[:alpha:]]" s)
          (string-match-p "[[:digit:]]" s))))
   (t nil)))

(defun aiaos-cli--slugify-translate (str sep unicode preserve)
  "Return STR with illegal chars replaced by SEP.

Kept chars are preserved; illegal chars become SEP.
Returns a list (STR RESULT, KEPT-COUNT, REMOVED-COUNT)."
  (let ((kept nil)
        (removed 0)
        (total 0))
    (dolist (ch (string-to-list str))
      (cl-incf total)
      (if (aiaos-cli--slugify-char-keep-p ch unicode preserve)
          (push (string ch) kept)
        (push sep kept)
        (cl-incf removed)))
    (list (concat (apply #'concat (nreverse kept)))
          (- total removed)
          removed)))

(defun aiaos-cli--slugify-has-unicode-p (str)
  "Return non-nil if STR contains any non-ASCII char."
  (catch 'found
    (dolist (ch (string-to-list str))
      (when (> ch 127)
        (throw 'found t)))))

(defun aiaos-cli--slugify-replace-underscore (str sep preserve)
  "Replace '_' in STR with SEP, except chars in PRESERVE."
  (let ((result "")
        (sep-char (string-to-char sep)))
    (dolist (ch (string-to-list str))
      (if (and (= ch ?_) (not (member ch (string-to-list preserve))))
          (setq result (concat result sep))
        (setq result (concat result (string ch)))))
    result))

;;;###autoload
(defun aiaos-cli-skill-emacs-tools/slugify (args &rest options)
  "Generate a URL-safe slug from ARGS[:text].

OPTS has :separator, :truncate, :unicode, :preserve.

ARGS is a plist with :text.
OPTIONS is a plist with:
  :separator  (default \"-\")
  :truncate   (integer, default nil)
  :unicode    (boolean, default nil) - preserve non-ASCII letters/digits
  :preserve   (string, default \"\") - extra chars to always keep

Returns plist with :status :skill :command :timestamp as required."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (text (plist-get args :text))
         (sep (or (plist-get opts :separator) "-"))
         (truncate (plist-get opts :truncate))
         (unicode (plist-get opts :unicode))
         (preserve (or (plist-get opts :preserve) "")))
    (unless (stringp text)
      (error "aiaos-cli-skill-emacs-tools/slugify: missing :text"))
    (unless (stringp sep)
      (error "aiaos-cli-skill-emacs-tools/slugify: :separator must be a string"))
    (unless (> (length sep) 0)
      (error "aiaos-cli-skill-emacs-tools/slugify: :separator cannot be empty"))
    (unless (or (null truncate)
                (and (integerp truncate) (> truncate 0)))
      (error "aiaos-cli-skill-emacs-tools/slugify: :truncate must be a positive integer or nil"))
    (unless (stringp preserve)
      (error "aiaos-cli-skill-emacs-tools/slugify: :preserve must be a string"))
    (let* ((step1 (aiaos-cli--slugify-replace-underscore text sep preserve))
           (step2 (downcase step1))
           (translated (aiaos-cli--slugify-translate step2 sep unicode preserve))
           (step3 (nth 0 translated))
           (kept-count (nth 1 translated))
           (removed-count (nth 2 translated))
           (step4 (aiaos-cli--slugify-collapse-sep step3 sep))
           (step5 (aiaos-cli--slugify-trim-separator step4 sep))
           (final (if (and truncate (integerp truncate) (> truncate 0)
                           (< truncate (length step5)))
                      (substring step5 0 truncate)
                    step5))
           (truncated (and truncate (integerp truncate) (> truncate 0)
                           (< truncate (length step5))))
           (input-has-unicode (aiaos-cli--slugify-has-unicode-p text)))
      (list :status "ok"
            :input text
            :input-length (length text)
            :separator sep
            :unicode unicode
            :preserve preserve
            :output final
            :output-length (length final)
            :truncated truncated
            :removed-char-count removed-count
            :kept-char-count (length final)
            :has-unicode input-has-unicode
            :skill "emacs-tools"
            :command "slugify"
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z")))))

(provide 'aiaos-cli-skill-emacs-tools/slugify)
