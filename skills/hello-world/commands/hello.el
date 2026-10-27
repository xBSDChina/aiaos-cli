;;; hello.el --- hello-world skill: hello command -*- lexical-binding: t; -*-

;;;###autoload
(defun aiaos-cli-skill-hello-world/hello (args &rest options)
  "Greet a name.

ARGS is a plist with :name.
OPTIONS is a plist with :greeting."
  (let* ((opts (if (and (listp options)
                        (= (length options) 1)
                        (listp (car options)))
                   (car options)
                 options))
         (name (plist-get args :name))
         (greeting (or (plist-get opts :greeting) "Hello")))
    (unless (stringp name)
      (error "aiaos-cli-skill-hello-world/hello: missing :name"))
    (list :status "ok"
          :message (format "%s, %s!" greeting name)
          :skill "hello-world"
          :command "hello"
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))

(provide 'aiaos-cli-skill-hello-world/hello)
