;;; time.el --- hello-world skill: time command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-hello-world/time (_args &rest options)
  "Return current timestamp.

ARGS is ignored (empty plist).
OPTIONS is a plist with :format (iso|epoch).

Per ~/aiaos-cli_skills.md §3.3, every command MUST return a plist
containing at least :status, :skill, :command, and :timestamp."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (fmt (or (plist-get opts :format) "iso"))
         (epoch (float-time (current-time)))
         (ts (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
    (if (string= fmt "epoch")
        (list :status "ok"
              :epoch epoch
              :skill "hello-world"
              :command "time"
              :timestamp ts)
      (list :status "ok"
            :iso ts
            :epoch epoch
            :skill "hello-world"
            :command "time"
            :timestamp ts))))

(provide 'aiaos-cli-skill-hello-world/time)
