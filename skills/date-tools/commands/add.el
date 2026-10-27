;;; add.el --- date-tools skill: add command -*- lexical-binding: t; -*-

(defun aiaos-cli-skill-date-tools--dim (year month)
  "Days in month."
  (cond
   ((memq month '(1 3 5 7 8 10 12)) 31)
   ((memq month '(4 6 9 11)) 30)
   ((= month 2) (if (or (zerop (% year 4))
                        (and (zerop (% year 100)) (zerop (% year 400))))
                    29 28))
   (t 30)))

;;;###autoload
(defun aiaos-cli-skill-date-tools/add (args &rest _options)
  "Add or subtract days/months from a base date."
  (let* ((date (plist-get args :date))
         (days (plist-get args :days))
         (months (or (plist-get args :months) 0)))
    (unless date (error "missing :date"))
    (let* ((parts (split-string date "-"))
           (year (string-to-number (nth 0 parts)))
           (month (string-to-number (nth 1 parts)))
           (day (string-to-number (nth 2 parts)))
           (new-month (+ month months))
           (new-year year))
      (while (> new-month 12)
        (setq new-month (- new-month 12))
        (setq new-year (1+ new-year)))
      (while (< new-month 1)
        (setq new-month (+ new-month 11))
        (setq new-year (1- new-year)))
      (setq day (min day (aiaos-cli-skill-date-tools--dim new-year new-month)))
      (let* ((base-time (encode-time 0 0 0 day new-month new-year))
             (result-time (time-add base-time (seconds-to-time (* (or days 0) 86400)))))
        (list :status "ok"
              :input date
              :days (or days 0)
              :months months
              :result (format-time-string "%Y-%m-%d" result-time)
              :skill "date-tools"
              :command "add"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))))

(provide 'aiaos-cli-skill-date-tools/add)
