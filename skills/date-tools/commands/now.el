;;; now.el --- date-tools skill: now command -*- lexical-binding: t; -*-

(eval-when-compile (require 'cl-lib))

;;;###autoload
(defun aiaos-cli-skill-date-tools--format-alias (name)
  "Resolve format NAME alias to strftime format string.

Supported aliases:
  iso      -> %Y-%m-%dT%H:%M:%S%z  (ISO 8601)
  iso-utc  -> %Y-%m-%dT%H:%M:%S+0000
  rfc      -> %a, %d %b %Y %H:%M:%S %z  (RFC 822)
  short    -> %Y-%m-%d
  short-utc -> same as short (no TZ component)
  time     -> %H:%M:%S
  date     -> %Y-%m-%d
  unix     -> %s  (seconds since epoch)
  compact  -> %Y%m%dT%H%M%S

If NAME is not a known alias, it is returned unchanged (strftime passthrough)."
  (let ((aliases (list (cons "iso"       "%Y-%m-%dT%H:%M:%S%z")
                       (cons "iso-utc"   "%Y-%m-%dT%H:%M:%S+0000")
                       (cons "rfc"       "%a, %d %b %Y %H:%M:%S %z")
                       (cons "short"     "%Y-%m-%d")
                       (cons "short-utc" "%Y-%m-%d")
                       (cons "time"      "%H:%M:%S")
                       (cons "date"      "%Y-%m-%d")
                       (cons "unix"      "%s")
                       (cons "compact"   "%Y%m%dT%H%M%S"))))
    (or (cdr (assoc (downcase name) aliases))
        name)))

;;;###autoload
(defun aiaos-cli-skill-date-tools/now (args &rest _options)
  "Return current date/time in the specified format.

ARGS is a plist with optional :format (string).
Default format is ISO 8601 (YYYY-MM-DDTHH:MM:SS+TZ).

Format name aliases (pass the alias name instead of a full strftime string):
  iso, iso-utc, rfc, short, short-utc, time, date, unix, compact

Or pass any strftime format string directly (e.g., \"%Y-%m-%d\")."
  (let* ((raw-fmt (or (plist-get args :format) "iso"))
         (fmt (aiaos-cli-skill-date-tools--format-alias raw-fmt)))
    (list :status "ok"
          :format fmt
          :result (format-time-string fmt)
          :skill "date-tools"
          :command "now"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-date-tools/now)
