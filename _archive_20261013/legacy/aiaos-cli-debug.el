;;; aiaos-cli-debug.el --- Comprehensive debugging interface for AIAOS CLI
;; -*- lexical-binding: t -*-

(require 'aiaos-cli)

;; ============================================================================
;; Interactive commands for emacsclient debugging
;; ============================================================================

(defun aiaos-cli-debug-test ()
  "Run comprehensive diagnostic tests. Returns results as string."
  (interactive)
  (let ((out "[AIAOS] Diagnostic Tests\n==========\n")
        (fail 0))
    ;; Test 1: providers loaded
    (if aiaos-cli--providers
        (setq out (concat out "  [PASS] Providers loaded\n"))
      (setq out (concat out "  [FAIL] Providers NOT loaded\n"))
      (setq fail (1+ fail)))
    ;; Test 2: provider order
    (if aiaos-cli--provider-order
        (setq out (concat out (format "  [PASS] Provider order: %s\n"
                                     (mapconcat #'identity aiaos-cli--provider-order ", "))))
      (setq out (concat out "  [FAIL] No provider order\n"))
      (setq fail (1+ fail)))
    ;; Test 3: default provider configured
    (let ((def-prov (aiaos-cli--get-provider-config aiaos-cli-default-provider)))
      (if def-prov
          (setq out (concat out (format "  [PASS] Default provider '%s' configured\n" aiaos-cli-default-provider)))
        (setq out (concat out (format "  [FAIL] Default provider '%s' NOT configured\n" aiaos-cli-default-provider)))
        (setq fail (1+ fail))))
    ;; Test 4: mode function exists
    (if (fboundp 'aiaos-cli-mode)
        (setq out (concat out "  [PASS] aiaos-cli-mode exists\n"))
      (setq out (concat out "  [FAIL] aiaos-cli-mode MISSING\n"))
      (setq fail (1+ fail)))
    ;; Test 5: entry points
    (if (fboundp 'aiaos-cli-open)
        (setq out (concat out "  [PASS] aiaos-cli-open exists\n"))
      (setq out (concat out "  [FAIL] aiaos-cli-open MISSING\n"))
      (setq fail (1+ fail)))
    (if (fboundp 'aiaos-cli)
        (setq out (concat out "  [PASS] aiaos-cli exists\n"))
      (setq out (concat out "  [FAIL] aiaos-cli MISSING\n"))
      (setq fail (1+ fail)))
    ;; Test 6: key functions
    (dolist (fn '(aiaos-cli--handle-return aiaos-cli--llm-chat aiaos-cli--try-provider
                  aiaos-cli--debug-probe aiaos-cli--switch-provider-direct
                  aiaos-cli--show-stats aiaos-cli--reset-conversation
                  aiaos-cli--build-request-body aiaos-cli--http-post
                  aiaos-cli--http-post-stream aiaos-cli--switch-provider))
      (if (fboundp fn)
          (setq out (concat out (format "  [PASS] %S exists\n" fn)))
        (setq out (concat out (format "  [FAIL] %S MISSING\n" fn)))
        (setq fail (1+ fail))))
    ;; Test 7: trim
    (if (string= (aiaos-cli--trim "  hello  ") "hello")
        (setq out (concat out "  [PASS] aiaos-cli--trim\n"))
      (setq out (concat out "  [FAIL] aiaos-cli--trim\n"))
      (setq fail (1+ fail)))
    ;; Test 8: json parsing
    (condition-case e
        (let ((parsed (aiaos-cli--json-string-to-elisp "{\"a\":1,\"b\":\"x\"}")))
          (if (and (hash-table-p parsed)
                   (eq (gethash 'a parsed) 1)
                   (string= (gethash 'b parsed) "x"))
              (setq out (concat out "  [PASS] json-string-to-elisp\n"))
            (setq out (concat out "  [FAIL] json-string-to-elisp\n"))
            (setq fail (1+ fail))))
      (error
       (setq out (concat out (format "  [FAIL] json-string-to-elisp: %s\n" (error-message-string e))))
       (setq fail (1+ fail))))
    ;; Test 9: curl availability
    (if (executable-find "curl")
        (setq out (concat out "  [PASS] curl available\n"))
      (setq out (concat out "  [FAIL] curl NOT found\n"))
      (setq fail (1+ fail)))
    ;; Test 10: build request body
    (condition-case e
        (let ((body (aiaos-cli--build-request-body (nth 0 aiaos-cli--provider-order))))
          (if (and body (assoc 'model body) (assoc 'messages body))
              (setq out (concat out "  [PASS] Request body build\n"))
            (setq out (concat out "  [FAIL] Request body build incomplete\n"))
            (setq fail (1+ fail))))
      (error
       (setq out (concat out (format "  [FAIL] Request body build: %s\n" (error-message-string e))))
       (setq fail (1+ fail))))
    ;; Test 11: no duplicate providers
    (let ((unique (length (delete-dups aiaos-cli--provider-order))))
      (if (= unique (length aiaos-cli--provider-order))
          (setq out (concat out (format "  [PASS] No duplicate providers (%d)\n" unique)))
        (setq out (concat out (format "  [FAIL] Duplicates: %d unique out of %d\n"
                                      unique (length aiaos-cli--provider-order))))
        (setq fail (1+ fail))))
    ;; Summary
    (setq out (concat out (format "\nResult: %d failures\n" fail)))
    (message "%s" out)
    out))

(defun aiaos-cli-debug-probe-all ()
  "Probe ALL providers with a short test request. Shows results in *AIAOS Debug* buffer."
  (interactive)
  (let ((buf (get-buffer-create "*AIAOS Debug*")))
    (with-current-buffer buf
      (erase-buffer)
      (aiaos-cli--clear-debug-output)
      (insert "=== AIAOS Provider Diagnostic ===\n\n")
      (let ((results '())
            (i 0))
        (while (< i (length aiaos-cli--provider-order))
          (let* ((prov-name (nth i aiaos-cli--provider-order))
                 (target (aiaos-cli--resolve-provider-target prov-name))
                 (api-url (nth 1 target))
                 (model (nth 2 target))
                 (cfg (aiaos-cli--get-provider-config prov-name))
                 (api-key (gethash 'api-key cfg))
                 (status ""))
            (insert (format "--- %s ---\n" prov-name))
            (insert (format "  URL:    %s\n" (or api-url "N/A")))
            (insert (format "  Model:  %s\n" (or model "N/A")))
            (insert (format "  Key:    %s\n"
                            (if api-key
                                (format "%s...%s (len=%d)"
                                        (substring api-key 0 (min 4 (length api-key)))
                                        (substring api-key (- (length api-key) 4))
                                        (length api-key))
                              "NONE")))
            (if (null api-key)
                (progn
                  (insert "  Status: NO_API_KEY\n")
                  (push (list prov-name "NO_API_KEY" nil) results))
              (if (null api-url)
                  (progn
                    (insert "  Status: NO_URL\n")
                    (push (list prov-name "NO_URL" nil) results))
                (condition-case err
                    (let ((aiaos-cli-enable-streaming nil))
                      (let ((body-json (json-encode (aiaos-cli--build-request-body prov-name))))
                        (let ((raw (aiaos-cli--http-post api-url api-key body-json 8)))
                          (if raw
                              (let ((parsed (aiaos-cli--json-string-to-elisp raw)))
                                (let ((content (gethash :content
                                                       (gethash :message
                                                                (first (gethash :choices parsed))))))
                                  (if content
                                      (progn
                                        (insert (format "  Status: OK\n  Response: %s\n"
                                                        (substring content 0 80)))
                                        (push (list prov-name "OK" t) results))
                                    (progn
                                      (insert "  Status: NO_CONTENT_IN_RESPONSE\n")
                                      (insert (format "  Raw: %s\n" (substring raw 0 200)))
                                      (push (list prov-name "NO_CONTENT" nil) results)))))
                            (progn
                              (insert "  Status: EMPTY_RESPONSE\n")
                              (push (list prov-name "NO_BODY" nil) results))))))
                  (aiaos-cli-llm-auth
                   (insert (format "  Status: AUTH_FAILED (%s)\n" (error-message-string err)))
                   (push (list prov-name "AUTH_FAILED" nil) results))
                  (aiaos-cli-llm-timeout
                   (insert (format "  Status: TIMEOUT (%ds)\n" 8))
                   (push (list prov-name "TIMEOUT" nil) results))
                  (aiaos-cli-llm-error
                   (insert (format "  Status: ERROR (%s)\n" (error-message-string err)))
                   (push (list prov-name "ERROR" nil) results))
                  (error
                   (insert (format "  Status: ERROR (%s)\n" (error-message-string err)))
                   (push (list prov-name "ERROR" nil) results))))
            (insert "\n"))
          (setq i (1+ i)))
        (insert "=== Summary ===\n")
        (let ((ok-count 0) (fail-count 0))
          (dolist (r results)
            (if (nth 2 r)
                (setq ok-count (1+ ok-count))
              (setq fail-count (1+ fail-count))))
          (insert (format "OK: %d / Failed: %d / Total: %d\n" ok-count fail-count (length results)))
          (when (> ok-count 0)
            (insert "\nWorking providers:\n")
            (dolist (r results)
              (when (nth 2 r)
                (insert (format "  * %s\n" (nth 0 r)))))))))
    (switch-to-buffer buf)))

(defun aiaos-cli-debug-show-state ()
  "Show current AIAOS CLI state in *AIAOS State* buffer."
  (interactive)
  (let ((buf (get-buffer-create "*AIAOS State*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "=== AIAOS CLI State ===\n\n")
      (insert (format "Providers hash: %s\n"
                      (if aiaos-cli--providers
                          (format "hash-table (%d entries)" (hash-table-count aiaos-cli--providers))
                        "nil")))
      (insert (format "Provider order: %s\n"
                      (mapconcat #'identity (or aiaos-cli--provider-order '("empty")) ", ")))
      (insert (format "Current index:  %d\n" aiaos-cli--current-provider-index))
      (insert (format "Current provider: %s\n" (or (aiaos-cli--get-current-provider) "none")))
      (insert (format "Mode active:    %s\n" aiaos-cli--mode-active))
      (insert (format "Busy:           %s\n" aiaos-cli--busy))
      (insert (format "Last error:     %s\n" (or aiaos-cli--last-error "none")))
      (insert (format "Conversation:   %d messages\n" (length aiaos-cli--conversation)))
      (insert (format "Error log:      %d entries\n" (length aiaos-cli--error-log)))
      (insert (format "Provider stats: %d entries\n" (length aiaos-cli--provider-stats)))
      (when aiaos-cli--debug-output
        (insert "\n=== Debug Output ===\n")
        (dolist (line (nreverse aiaos-cli--debug-output))
          (insert line "\n")))
      (switch-to-buffer buf))))

(provide 'aiaos-cli-debug)
;;; aiaos-cli-debug.el ends here
