;; Install straight.el
;; Just pasted from https://github.com/raxod502/straight.el#getting-started
(let ((bootstrap-file (concat user-emacs-directory "straight/repos/straight.el/bootstrap.el"))
      (bootstrap-version 3))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; You have to install use-package in order to use use-package with straight
(straight-use-package 'use-package)

(use-package emacs-pg
 :straight (emacs-pg :type git :host github :repo "akirak/emacs-pg")
 :defer t
 :commands (emacs-pg-try
            emacs-pg-add
            emacs-pg-adopt
            emacs-pg-dismiss
            emacs-pg-update-symlinks)
 )