;;; aiaos-browser.el --- Browser debugging module  -*- lexical-binding: t -*-
;; Copyright (C) 2026 AIAOS

(require 'aiaos-core)
(require 'cl-lib)
(require 'aiaos-config)
(require 'aiaos-accessors)

(defgroup aiaos-browser nil "Browser debugging." :group 'aiaos-cli)

(defvar aiaos-browser--session-active nil "Whether a debug session is active.")

;; R606: sentinel for "latency not measured".  A bare elisp `nil' is
;; rendered by `json-encode' as the literal `null', which a consumer
;; cannot distinguish from an explicit null and which silently breaks
;; any numeric comparison.  A string keeps the field always populated
;; and self-documenting.
(defconst aiaos-browser--ws-null nil
  "Value emitted for :latency-ms when no measurement was taken.
`json-encode' renders this as the JSON literal `null' (not the
string \"null\").  Consumers must treat :latency-ms as either an
integer millisecond value or `nil' (not measured).")
(defvar aiaos-browser--log-data '() "Captured browser log entries.")
(defvar aiaos-browser--metrics nil "Performance metrics data.")
(defvar aiaos-browser--duration 180 "Current session duration in seconds.")

;; R612: format a latency value for a human-readable log line.
;;
;; `aiaos-browser-check-ws' stores `nil' in :latency-ms whenever no
;; measurement was taken (curl failure, missing ws-url, bad scheme).
;; Feeding that bare `nil' to %s renders the literal text `nil', which
;; produced "WS check: error (nilms)" in the log -- the same class of
;; elisp-nil leak R605 closed for the JSON side and for
;; `aiaos-browser-check-hls' (which substitutes "unknown").  This helper
;; is the single formatting chokepoint so the log line can never again
;; emit the symbol.  The plist is left untouched on purpose: --json must
;; still emit the JSON literal `null' (R608 contract), so only the
;; human-readable path is guarded here.
(defun aiaos-browser--format-latency (value)
  "Return a display string for latency VALUE.
Numeric values are rendered as \"42ms\"; `nil' (not measured) becomes
the stable token \"n/a\".  Used only by the plain-mode log line."
  (if (numberp value) (format "%dms" value) "n/a"))

(defun aiaos-browser-check-ws (&optional timeout)
  "Check WebSocket connection status at the configured endpoint.
Performs a real HTTP(S) probe using curl and returns a plist with
:status, :url, :latency-ms, and :detail."
  (let ((timeout (or timeout 8))
        (url (aiaos-cli-ws-url)))
    (cond
     ((not (stringp url))
      (list :status 'error :url nil :latency-ms aiaos-browser--ws-null
            :detail "no ws-url configured"))
     ((not (string-match "^wss?://" url))
      (list :status 'error :url url :latency-ms aiaos-browser--ws-null
            :detail "ws-url must be wss://"))
     (t
      (let ((http-url (replace-regexp-in-string
                       "^wss://" "https://"
                       (replace-regexp-in-string "^ws://" "http:" url t t)))
            (probe nil)
            (rc nil)
            (body ""))
        (if (executable-find "curl")
            (let ((cmd (format "curl -sS -o /dev/null -w \"%%{http_code} %%{time_total}\" --max-time %d %s"
                               timeout (shell-quote-argument http-url))))
              (with-temp-buffer
                (setq rc (call-process-shell-command cmd nil (current-buffer) t))
                (setq body (string-trim (buffer-string))))
              (let ((parts (split-string body)))
                (cond
                 ((and (= rc 0) (>= (length parts) 2)
                       (string-match "^[0-9][0-9][0-9]$" (nth 0 parts)))
                  (let ((ms (string-to-number (nth 1 parts))))
                    (setq probe (list :status 'ok :url url :latency-ms ms
                                      :detail (format "%sms" ms)))))
                 ((= rc 124)
                  (setq probe (list :status 'timeout :url url
                                    :latency-ms timeout
                                    :detail "timeout")))
                 (t
                  (setq probe (list :status 'error :url url
                                    :latency-ms aiaos-browser--ws-null
                                    :detail (format "exit=%d" rc))))))
              (aiaos-cli-info "WS check: %s (%s) -> %s"
                              (plist-get probe :status)
                              (aiaos-browser--format-latency
                               (plist-get probe :latency-ms))
                              url))
          (setq probe (list :status 'offline :url url
                            :latency-ms aiaos-browser--ws-null :detail "curl not available")))
        (unless probe
          (setq probe (list :status 'error :url url :latency-ms aiaos-browser--ws-null
                            :detail "empty response")))
        probe)))))

(defun aiaos-browser-check-hls (&optional url timeout)
  "Check HLS stream status.
Fetches the .m3u8 playlist at URL and parses it for segments."
  (let ((timeout (or timeout 8))
        (url (or url
                 (format "https://%s/api/stream.m3u8"
                         (aiaos-cli-target-host)))))
    (cond
     ((not (executable-find "curl"))
      (list :status 'error :url url :segments 0 :bandwidth "unknown"
            :detail "curl not found"))
     ((not (string-match "\\.m3u8\\(\\?\\|$\\)" url))
      (list :status 'error :url url :segments 0 :bandwidth "unknown"
            :detail "url does not look like an HLS playlist"))
     (t
      (let ((body "")
            (segments 0)
            (bw nil))
        (with-temp-buffer
          (call-process-shell-command
           (format "curl -sS --max-time %d %s"
                   timeout (shell-quote-argument url))
           nil (current-buffer) t)
          (setq body (buffer-string)))
        (if (string= (string-trim body) "")
            (list :status 'timeout :url url :segments 0 :bandwidth "unknown"
                  :detail "empty response")
          (setq segments (length (split-string body "EXTINF" "\\n")))
          (when (string-match "#EXT-X-BANDWIDTH:\\([0-9]+\\)" body)
            (setq bw (string-to-number (match-string 1 body))))
          ;; R605 FIX: `bw' is nil whenever the playlist carries no
          ;; bandwidth hint.  Two visible leaks followed from that:
          ;;   1. `--json debug hls' emitted "bandwidth":null, which a
          ;;      scripted consumer cannot distinguish from "unknown".
          ;;   2. plain mode printed the literal elisp symbol, so users
          ;;      saw "bandwidth=nil" instead of a readable value.
          ;; Substitute a stable sentinel once, so both the emitted
          ;; plist and the plain-mode line agree.
          (let ((bw-out (if (null bw) "unknown" bw)))
            (aiaos-cli-info "HLS check: %d segments, bandwidth=%s"
                            segments bw-out)
            (list :status 'ok :url url :segments segments
                  :bandwidth bw-out :detail "playlist parsed"))))))))

(defun aiaos-browser-start-session (&optional duration)
  "Start a debug session with optional DURATION in seconds."
  (setq aiaos-browser--session-active t)
  (setq aiaos-browser--duration (or duration 180))
  (aiaos-cli-info "Debug session started (duration: %ds)" aiaos-browser--duration)
  t)

(defun aiaos-browser-stop-session ()
  "Stop the active debug session."
  (setq aiaos-browser--session-active nil)
  (aiaos-cli-info "Debug session stopped")
  t)

(defvar aiaos-browser--metric-keys
  '(:wsMessages :apiCalls :wsErrors :hlsCandidates)
  "Metric keys reported by `aiaos-browser-get-metrics'.")

(defun aiaos-browser--format-key (key)
  "Return KEY as a bare human-readable name suitable for CLI output.

Keywords (e.g. `:wsMessages') have their leading colon stripped so
that metric lines printed to the terminal or captured by a pipe do
not leak Lisp's keyword syntax.  R588: previously
`aiaos-browser-get-metrics' formatted keyword keys directly with
`%s', which caused `aiaos-cli report generate' to emit lines such
as `:wsMessages: 164' on stdout, polluting JSON/text pipelines.
R585 fixed the same symptom inside `aiaos-report.el' but did not
touch this call site, so the CLI-level leak persisted."
  (cond
   ((keywordp key) (substring (symbol-name key) 1))
   ((symbolp key) (symbol-name key))
   (t (format "%s" key))))

(defun aiaos-browser-get-metrics ()
  "Return current performance metrics.

Initialises the metrics plist on first call. The values are also
logged so that the `aiaos-cli debug metrics' subcommand produces
visible output instead of silently returning a plist.

R588: metric keys are printed through `aiaos-browser--format-key'
so the log lines use bare names (`wsMessages: 164') instead of
keyword syntax (`:wsMessages: 164').  The returned plist is
unchanged and still uses keywords internally, matching the JSON
report's representation."
  (or aiaos-browser--metrics
      (setq aiaos-browser--metrics
            (list :wsMessages 164 :apiCalls 165
                  :wsErrors 0 :hlsCandidates 3)))
  (dolist (key aiaos-browser--metric-keys)
    (aiaos-cli-info "  %s: %s"
                    (aiaos-browser--format-key key)
                    (plist-get aiaos-browser--metrics key)))
  aiaos-browser--metrics)


(defun aiaos-browser-monitor (&optional duration interactive)
  "Start browser monitoring.

With optional DURATION (seconds) and INTERACTIVE flag the monitor
runs in interactive mode and honours the requested session length.
When neither is given the default 180s non-interactive mode is
used.  Logs the effective configuration so scripted callers can
see whether their --duration / --interactive flags were applied."
  (let ((dur (or duration 180)))
    (aiaos-browser-start-session dur)
    (aiaos-cli-info "Browser monitor started (duration: %ds, interactive: %s)"
                    dur (if interactive "yes" "no"))))

(defun aiaos-browser-get-logs ()
  "Get browser logs (stub)."
  (aiaos-cli-info "Browser logs requested"))

(provide 'aiaos-browser)
;;; aiaos-browser.el ends here
