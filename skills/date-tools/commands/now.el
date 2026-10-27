;;; now.el --- date-tools skill: now command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-date-tools/now (args &rest _options)
  "Return current date/time in the specified format.

ARGS is a plist with optional :format (string).
Default format is ISO 8601 (YYYY-MM-DDTHH:MM:SS+TZ).

Supported format tokens (passed to format-time-string):
  %Y - Year, %m - Month, %d - Day, %H - Hour,
  %M - Minute, %S - Second, %z - TZ offset, %A - Weekday, %B - Month name"
  (let ((fmt (or (plist-get args :format) "%Y-%m-%dT%H:%M:%S%z")))
    (list :status "ok"
          :format fmt
          :result (format-time-string fmt)
          :skill "date-tools"
          :command "now"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-date-tools/now)
