;;; timestamp.el --- date-tools skill: timestamp command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-date-tools/timestamp (args &rest _options)
  "Convert between Unix timestamp and date string.

ARGS is a plist with:
  :value    - the input value (timestamp string or date string)
  :direction - to-unix | to-date | auto (default: auto)"
  (let* ((value (plist-get args :value))
         (direction (plist-get args :direction))
         (result))
    (unless value
      (error "aiaos-cli-skill-date-tools/timestamp: missing :value"))
    (cond
     ;; Timestamp -> date
     ((or (not direction) (string= direction "auto") (string= direction "to-date"))
      (if (string-match-p "^[0-9]+$" value)
          (setf result (format-time-string "%Y-%m-%dT%H:%M:%S%z"
                                           (string-to-number value)))
        (setf result value)))
     ;; Date -> timestamp
     ((string= direction "to-unix")
      (let* ((parts (split-string value "-"))
             (year (string-to-number (nth 0 parts)))
             (month (string-to-number (nth 1 parts)))
             (day (string-to-number (nth 2 parts)))
             (hour (string-to-number (or (nth 3 parts) "0")))
             (min (string-to-number (or (nth 4 parts) "0")))
             (sec (string-to-number (or (nth 5 parts) "0")))
             (encoded (encode-time sec min hour day month year)))
        ;; encode-time returns (sec-high sec-low), full seconds = high * 65536 + low
        (setf result (format "%d" (+ (* (car encoded) 65536) (cadr encoded))))))
     (t (error "aiaos-cli-skill-date-tools/timestamp: unknown direction %S" direction)))
    (list :status "ok"
          :input value
          :direction (or direction "auto")
          :result result
          :skill "date-tools"
          :command "timestamp"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-date-tools/timestamp)
