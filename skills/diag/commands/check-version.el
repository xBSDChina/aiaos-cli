;;; check-version.el --- 扫描源码检查版本号一致性 -*- lexical-binding: t; -*-

;; Copyright (C) 2024 AIAOS Project
;; Version: 1.0.0

(require 'cl-lib)
(require 'find-func)
(require 'aiaos-cli-version)
(require 'aiaos-cli-core)
(require 'aiaos-cli-router)

(defun aiaos-cli--scan-version-drift (file expected)
  "Scan FILE for version strings that differ from EXPECTED.
Return a list of drift plists (:file :line :version :content)."
  (if (not (file-readable-p file))
      nil
    (let ((matches nil)
          (line-no 0))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring (point) (line-end-position))))
            (setq line-no (1+ line-no))
            (when (and (string-match "1\\.0\\.[0-9]+" line)
                       (not (string-match expected line)))
              (push (list :file (file-relative-name file)
                          :line line-no
                          :version (match-string 0 line)
                          :content line)
                    matches))
            (forward-line 1))))
      (nreverse matches))))

(defun aiaos-cli-skill-diag/check-version (args &optional opts)
  "Scan the repository for hardcoded version strings and compare
with the VERSION file.

Returns a plist with:
  :status      \"ok\" | \"drift\" | \"error\"
  :expected    the version from VERSION file
  :drift       list of (:file :line :version :content) mismatches
  :files-scanned  number of files scanned
  :strict      t if strict mode was requested and drift was found
"
  (let* ((opts (or opts '()))
         (strict (plist-get opts :strict))
         (verbose (plist-get opts :verbose))
         (scan-path (plist-get opts :path))
         (scan-dir (if (or (null scan-path) (string-empty-p scan-path))
                       (expand-file-name
                        ".." (file-name-directory load-file-name))
                     scan-path))
         (expected (replace-regexp-in-string "[\r\n]" "" aiaos-cli-version))
         (all-drift nil)
         (files-scanned 0))
    (if (not (and (file-exists-p scan-dir) (file-directory-p scan-dir)))
        (list :status "error"
              :message (format "Directory not found: %s" scan-dir))
      (dolist (file (find-file-names-recursively-in-directory scan-dir))
        (let ((base (file-name-nondirectory file)))
          (when (and (string-match "\\.el$" base)
                     (not (string-match "^\\.\\." base)))
            (let ((fdrift (aiaos-cli--scan-version-drift file expected)))
              (when fdrift
                (setq all-drift (append all-drift fdrift))
                (setq files-scanned (1+ files-scanned))))))
      (let ((drift-count (length all-drift)))
        (if (> drift-count 0)
            (list :status "drift"
                  :expected expected
                  :drift all-drift
                  :files-scanned files-scanned
                  :verbose verbose
                  :strict (if (and strict (> drift-count 0)) t nil)
                  :message (format "Found %d version drift(s) (expected %s)"
                                   drift-count expected))
          (list :status "ok"
                :expected expected
                :drift nil
                :files-scanned files-scanned
                :verbose verbose
                :strict nil
                :message (format "All %d files consistent with %s"
                                 files-scanned expected))))))))

(aiaos-cli-register-command
 "diag" "check-version"
 #'aiaos-cli-skill-diag/check-version
 :description "扫描源码检查版本号一致性"
 :args '()
 :options '((:verbose "verbose" "v" boolean nil "详细模式")
            (:strict "strict" "s" boolean nil "严格模式：任何漂移都视为失败")
            (:path "path" "p" string nil "扫描目录"))
 :skill "diag")

(provide 'aiaos-cli-skill-diag/commands/check-version)
;;; check-version.el ends here