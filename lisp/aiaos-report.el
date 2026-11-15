;;; aiaos-report.el --- Report generation module  -*- lexical-binding: t -*-
;; Copyright (C) 2026 AIAOS

(require 'cl-lib)
(require 'json)
(require 'aiaos-core)
(require 'aiaos-config)
(require 'aiaos-browser)

(defgroup aiaos-report nil "Report generation." :group 'aiaos-cli)

(defcustom aiaos-report-output-dir "~/.aiaos/reports" "Report output dir."
  :type 'string :group 'aiaos-report)

(defun aiaos-report--plistp (val)
  "Return non-nil if VAL looks like a property list.
A plist is an even-length list whose keys are keywords or symbols."
  (and (listp val)
       (zerop (mod (length val) 2))
       (let ((rest val) ok)
         (setq ok t)
         (while (and rest ok)
           (setq ok (and (listp (cdr rest))
                         (or (keywordp (car rest)) (symbolp (car rest)))))
           (setq rest (cddr rest)))
         ok)))

(defun aiaos-report--normalise-chart-data (data)
  "Return DATA as an alist of (SYMBOL . NUMBER) suitable for charts.
Accepts plists, alists, or lists of (SYMBOL . VALUE) pairs.
Non-numeric values are coerced to 0."
  (cond
   ((aiaos-report--plistp data)
    (let ((pl data) out)
      (while pl
        (push (cons (car pl)
                    (if (numberp (cadr pl)) (cadr pl) 0))
              out)
        (setq pl (cddr pl)))
      (nreverse out)))
   ((and (listp data) (consp (car data)) (consp (car (car data))))
    ;; already an alist
    (mapcar (lambda (kv)
              (cons (car kv)
                    (if (numberp (cdr kv)) (cdr kv) 0)))
            data))
   (t '())))

(defun aiaos-report--format-value (val)
  "Format VAL as a human-readable string for HTML/text reports.

Booleans become `true'/'false'; keywords and symbols become their bare
names (leading `:' stripped from keywords), so HTML/text output matches
the JSON report's representation instead of leaking Lisp's `t' or the
keyword colon prefix.  R585: previously keyword keys such as
`:wsMessages' were printed with the colon, contradicting the R583
contract that HTML/text reports use bare metric names."
  (cond
   ((eq val t) "true")
   ((eq val nil) "false")
   ((keywordp val)
    ;; `symbol-name' preserves the leading colon on keywords, so strip
    ;; it explicitly.  This is the R585 fix: without this branch the
    ;; colon leaked into HTML/text reports even though R583 claimed
    ;; the bug was fixed.
    (let ((name (symbol-name val)))
      (substring name 1)))
   ((symbolp val) (symbol-name val))
   (t (format "%s" val))))

(defun aiaos-report--json-value (val)
  "Convert Lisp value VAL into a JSON-compatible value.
Keywords and symbols become strings; property lists become JSON objects;
the boolean t becomes JSON true and nil stays JSON null."
  (cond
   ((null val) nil)
   ((eq val t) t)
   ((stringp val) val)
   ((numberp val) val)
   ((keywordp val) (symbol-name val))
   ((symbolp val) (symbol-name val))
   ((aiaos-report--plistp val)
    (let ((out))
      (while val
        (push (cons (symbol-name (car val))
                    (aiaos-report--json-value (cadr val)))
              out)
        (setq val (cddr val)))
      out))
   ((and (consp val) (listp (cdr val)))
    (cons (aiaos-report--json-value (car val))
          (aiaos-report--json-value (cdr val))))
   ((listp val) (mapcar #'aiaos-report--json-value val))
   (t (format "%s" val))))

(defun aiaos-report--json-pretty (data)
  "Return DATA as JSON text.
Values are normalised by aiaos-report--json-value so that the result is
always valid JSON (keywords and symbols become strings, property lists
become objects, t becomes true, nil becomes null)."
  (json-encode data))


(defun aiaos-report-generate (&optional output-dir)
  "Generate a complete report with both HTML and JSON outputs.
OUTPUT-DIR overrides the default report directory."
  (let* ((dir (expand-file-name (or output-dir aiaos-report-output-dir)))
        (timestamp (format-time-string "%Y%m%d-%H%M%S"))
        ;; O fix: call aiaos-browser-get-metrics exactly once and
        ;; derive both the plist and the alist from it, so metric
        ;; lines are logged only once per report run.
        (metrics-plist (aiaos-browser-get-metrics))
        (metrics (let ((pl metrics-plist) out)
                   (while pl
                     (push (cons (car pl) (cadr pl)) out)
                     (setq pl (cddr pl)))
                   out))
        (config (aiaos-config--to-alist)))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (let ((json-file (expand-file-name (format "report-%s.json" timestamp) dir))
          (html-file (expand-file-name (format "report-%s.html" timestamp) dir)))
      ;; Generate JSON report
      (with-temp-file json-file
        (let ((data (list (cons "timestamp" timestamp)
                          (cons "config"
                                (mapcar (lambda (pair)
                                          (cons (if (symbolp (car pair))
                                                    (symbol-name (car pair))
                                                  (car pair))
                                                (aiaos-report--json-value (cdr pair))))
                                        config))
                          (cons "metrics"
                                (aiaos-report--json-value metrics-plist)))))
          (insert (aiaos-report--json-pretty data))))
      ;; Generate HTML report
      (with-temp-file html-file
        (insert "<!DOCTYPE html><html><head>")
        (insert "<meta charset=\"utf-8\"><title>AIAOS Report</title>")
        (insert "</head><body><h1>AIAOS Debug Report</h1>")
        (insert (format "<p>Generated: %s</p>" timestamp))
        (insert "<h2>Configuration</h2><pre>\n")
        (dolist (pair config)
          (insert (format "%s: %s\n" (aiaos-report--format-value (car pair))
                      (aiaos-report--format-value (cdr pair)))))
        (insert "</pre>\n")
        (insert "<h2>Metrics</h2><pre>\n")
        (dolist (pair metrics)
          (insert (format "%s: %s\n" (aiaos-report--format-value (car pair))
                      (aiaos-report--format-value (cdr pair)))))
        (insert "</pre></body></html>"))
      (aiaos-cli-info "Report generated: %s, %s" json-file html-file)
      ;; R585: return a structured plist so callers can address each
      ;; artifact by name.  `:files' keeps the historical 2-element
      ;; list shape for backward compatibility.
      `(:status :ok
        :json ,json-file
        :html ,html-file
        :timestamp ,timestamp
        :files (,json-file ,html-file)))))

(defun aiaos-report-generate-json (&optional output-dir)
  "Generate JSON report only; returns the JSON file path."
  (let ((results (aiaos-report-generate output-dir)))
    (plist-get results :json)))

(defun aiaos-report-generate-html (&optional output-dir)
  "Generate HTML report only; returns the HTML file path."
  (let ((results (aiaos-report-generate output-dir)))
    (plist-get results :html)))

(defun aiaos-report--ascii-chart (data width)
  "Render DATA (an alist or plist of KEY . VALUE) as an ASCII bar chart.
WIDTH bounds the longest bar in characters."
  (setq data (aiaos-report--normalise-chart-data data))
  (let* ((width (or width 40))
         (max-val (apply 'max (cons 1 (mapcar 'cdr data))))
         (scale (max 1 (/ (float max-val) (float width))))
         (lines '()))
    (dolist (pair data)
      (let* ((label (symbol-name (car pair)))
             (val (or (cdr pair) 0))
             (barlen (max 0 (floor (/ (float val) scale))))
             (bar (make-string barlen ?█)))
        (push (format "%-16s |%s %d"
                      (if (> (length label) 16) (substring label 0 16) label)
                      bar barlen)
              lines)))
    (mapconcat 'identity (nreverse lines) "\n")))

(defcustom aiaos-report-chart-file-name "chart"
  "Base name for generated chart files."
  :type 'string
  :group 'aiaos-report)

(defun aiaos-report-generate-ascii-chart (&optional data)
  "Generate an ASCII bar chart from DATA, defaulting to live metrics.
Writes the chart to a .txt file in the report output directory, prints it,
and returns the file path."
  (let* ((data (or data aiaos-browser--metrics))
         (dir (expand-file-name aiaos-report-output-dir))
         (ts (format-time-string "%Y%m%d-%H%M%S")))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (let ((file (expand-file-name (format "%s-%s.txt" aiaos-report-chart-file-name ts) dir)))
      (with-temp-file file
        (insert "AIAOS Performance Metrics\n")
        (insert (make-string 40 ?-) "\n")
        (insert (aiaos-report--ascii-chart data 40))
        (insert "\n"))
      (aiaos-cli-info "ASCII chart saved: %s" file)
      (princ (aiaos-report--ascii-chart data 40))
      (princ "\n")
      file)))

(defun aiaos-report--html-bar-chart (data)
  "Render DATA (an alist or plist of KEY . VALUE) as inline HTML/CSS bars."
  (setq data (aiaos-report--normalise-chart-data data))
  (let* ((max-val (apply 'max (cons 1
                                    (mapcar (lambda (x)
                                              (if (numberp x) x 0))
                                            (mapcar 'cdr data)))))
         (rows '()))
    (dolist (pair data)
      (let* ((label (symbol-name (car pair)))
             (val (if (numberp (cdr pair)) (cdr pair) 0))
             (pct (if (> max-val 0) (round (* 100.0 (/ (float val) (float max-val)))) 0)))
        (push (format "<div style=\"display:flex;align-items:center;margin:4px 0\">
<span style=\"width:140px\">%s</span>
<span style=\"flex:1;background:#eee;height:16px;border-radius:3px\">
<span style=\"display:block;height:100%%;width:%d%%;background:#4a90d9\"></span>
</span>
<span style=\"width:60px;text-align:right\">%d</span>
</div>"
                      label pct val)
              rows)))
    (mapconcat 'identity (nreverse rows) "\n")))

(defun aiaos-report-generate-text (&optional output-dir)
  "Generate a plain-text report from live metrics and config.

Writes a .txt file under OUTPUT-DIR (or `aiaos-report-output-dir' by
default), prints the report to stdout, and returns the file path.

R575: previously `aiaos-cli report text' was routed to
`aiaos-report-generate-ascii-chart', which produced an ASCII bar
chart instead of a real text report.  This function is the correct
target for the `text' subcommand."
  (let* ((dir (expand-file-name (or output-dir aiaos-report-output-dir)))
         (ts (format-time-string "%Y%m%d-%H%M%S"))
         (file (expand-file-name (format "report-%s.txt" ts) dir))
         (metrics-plist (aiaos-browser-get-metrics))
         (config (aiaos-config--to-alist)))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (with-temp-file file
      (insert "AIAOS Text Report\n")
      (insert (make-string 40 ?-) "\n")
      (insert (format "Generated: %s\n" ts))
      (insert "\nConfiguration:\n")
      (dolist (pair config)
        (insert (format "  %s: %s\n"
                        (aiaos-report--format-value (car pair))
                        (aiaos-report--format-value (cdr pair)))))
      (insert "\nMetrics:\n")
      (let ((pl metrics-plist))
        (while pl
          (insert (format "  %s: %s\n"
                          (aiaos-report--format-value (car pl))
                          (aiaos-report--format-value (cadr pl))))
          (setq pl (cddr pl)))))
    (aiaos-cli-info "Text report saved: %s" file)
    (princ (with-temp-buffer (insert-file-contents file) (buffer-string)))
    file))

(defun aiaos-report-generate-html-chart (&optional data output-dir)
  "Generate a standalone HTML chart file from DATA, defaulting to live metrics.
Returns the path of the written .html file."
  (let* ((data (or data aiaos-browser--metrics))
         (dir (expand-file-name (or output-dir aiaos-report-output-dir)))
         (ts (format-time-string "%Y%m%d-%H%M%S")))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (let ((file (expand-file-name (format "%s-%s.html" aiaos-report-chart-file-name ts) dir)))
      (with-temp-file file
        (insert "<!DOCTYPE html><html><head><meta charset=\"utf-8\">")
        (insert "<title>AIAOS Metrics Chart</title><style>")
        (insert "body{font-family:sans-serif;margin:24px;background:#1e1e2e;color:#cdd6f4}")
        (insert ".bar-row{display:flex;align-items:center;margin:4px 0}")
        (insert ".bar-label{width:140px;font-size:13px}")
        (insert ".bar-track{flex:1;background:#313244;height:16px;border-radius:3px}")
        (insert ".bar-fill{display:block;height:100%;background:#89b4fa}")
        (insert ".bar-value{width:60px;font-size:13px}")
        (insert "</style></head><body>")
        (insert "<h1>AIAOS Performance Metrics</h1>")
        (insert (aiaos-report--html-bar-chart data))
        (insert "</body></html>"))
      (aiaos-cli-info "HTML chart saved: %s" file)
      file)))

(provide 'aiaos-report)
;;; aiaos-report.el ends here
