;;; skill_filter_select_callback.el --- Skill filter select callback -*- lexical-binding: t; -*-
;;
;; Skill filter select callback: provide interactive skill filtering with keyboard navigation.
;; Supports up/down arrow navigation to select different skills.

;;; Commentary:
;;
;; This module provides `aiaos-cli-skill-skill-management/skill-filter-select-callback`
;; which enables interactive skill filtering with keyboard navigation.
;; Supports up/down arrow navigation to select different skills.
;;
;; Usage:
;;   (aiaos-cli-skill-skill-management/skill-filter-select-callback "text")
;;
;; The function:
;; 1. Searches for skills matching QUERY (substring match on name/description)
;; 2. Displays matching skills in a list
;; 3. Allows up/down arrow navigation
;; 4. Returns the selected skill name on RET, or nil on C-g

;;; Code:

(defun aiaos-cli-skill-skill-management/skill-filter-select-callback (query &optional selected-idx)
  "Filter and select skills interactively.

QUERY is the search query string.
SELECTED-IDX is the initial selected skill index (0-based, default 0).

Returns the selected skill name, or nil if cancelled.

Example usage:
  (aiaos-cli-skill-skill-management/skill-filter-select-callback \"text\")
  (aiaos-cli-skill-skill-management/skill-filter-select-callback \"text\" 2)"
  (let* ((skills (aiaos-cli--skill-filter-by-query query))
         (len (length skills)))
    ;; Return nil if no skills found
    (if (zerop len)
        (prog1 nil
          (message "No skills found for query: %s" query))
      ;; Use completing-read for interactive selection
      (completing-read (format "Select skill [%d options]: " len)
                         (mapcar (lambda (skill) (cons skill skill)) skills)
                         nil t
                         (nth (or selected-idx 0) skills)))))

(defun aiaos-cli--skill-filter-by-query (query)
  "Filter skills by QUERY (substring match on name/description).

Returns a list of skill names matching the query.
If QUERY is empty, returns all installed skills."
  ;; Get skill list from skills directory
  (let* ((skills-dir aiaos-cli-skills-dir)
         (all-skills (when (file-directory-p skills-dir)
                       (cl-remove-if 'file-name-nondirectory
                                    (directory-files skills-dir t "^[^.]")))))
    ;; Filter by query
    (if (string-empty-p query)
        all-skills
      (cl-remove-if (lambda (skill)
                      (not (string-match-p query skill)))
                    all-skills))))

(provide 'skill_filter_select_callback)
;;; skill_filter_select_callback.el ends here
