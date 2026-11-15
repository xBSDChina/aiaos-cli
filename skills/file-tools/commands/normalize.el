;;; normalize.el --- file-tools skill: normalize command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-file-tools/normalize (args &rest _options)
  "Normalize a path and return abs/dir/name/ext components.

ARGS is a plist with :path.
OPTIONS is an unused plist for this command."
  (let ((path (plist-get args :path)))
    (if (or (null path) (not (stringp path)) (string= path ""))
        (list :status "error" :code "INVALID_ARGS"
              :message "path 不能为空"
              :skill "file-tools" :command "normalize"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
      (let* ((abs (expand-file-name path))
             (dir (file-name-directory abs))
             (base (file-name-nondirectory abs))
             (ext (file-name-extension abs))
             (noext (file-name-sans-extension base)))
        (list :status "ok"
              :input path
              :absolute abs
              :directory dir
              :name base
              :stem noext
              :extension ext
              :exists (file-exists-p abs)
              :skill "file-tools" :command "normalize"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))))

(provide 'aiaos-cli-skill-file-tools/normalize)
