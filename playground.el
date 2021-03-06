;;; playground.el --- Manage sandboxes for alternative configurations -*- lexical-binding: t -*-

;; Copyright (C) 2018 by Akira Komamura

;; Author: Akira Komamura <akira.komamura@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.4"))
;; Keywords: maint
;; URL: https://github.com/akirak/emacs-playground

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Playground is a playground for Emacs. Its basic idea is to create
;; an isolated directory called a sandbox and make it $HOME of Emacs.
;; Playground allows you to easily experiment with various Emacs configuration
;; repositories available on GitHub, while keeping your current configuration
;; untouched (almost, except for a stuff for Playground). It can also simplify
;; your workflow in Emacs by hiding irrelevant files and directories
;; existing in your home directory.

;;; Code:

(require 'cl-lib)

(defconst playground-original-home-directory (concat "~" user-login-name)
  "The original home directory of the user.")

(defcustom playground-script-directory
  (expand-file-name ".local/bin" playground-original-home-directory)
  "The directory where the wrapper script is saved."
  :group 'playground)

(defcustom playground-directory
  (expand-file-name ".emacs-play" playground-original-home-directory)
  "The directory where home directories of playground are stored."
  :group 'playground)

(defcustom playground-inherited-contents '(".gnupg")
  "Files and directories in the home directory that should be added to virtual home directories."
  :group 'playground)

(defcustom playground-dotemacs-list
      '(
        (:repo "https://github.com/bbatsov/prelude.git" :name "prelude")
        (:repo "https://github.com/seagle0128/.emacs.d.git")
        (:repo "https://github.com/purcell/emacs.d.git")
        (:repo "https://github.com/syl20bnr/spacemacs.git" :name "spacemacs")
        (:repo "https://github.com/eschulte/emacs24-starter-kit.git" :name "emacs24-starter-kit")
        (:repo "https://github.com/akirak/emacs.d.git")
        )
      "List of configuration repositories suggested in ‘playground-checkout’."
      :group 'playground)

(defun playground--emacs-executable ()
  "Get the executable file of Emacs."
  (executable-find (car command-line-args)))

(defun playground--script-paths ()
  "A list of script files generated by `playground-persist' command."
  (let ((dir playground-script-directory)
        (original-name (file-name-nondirectory (playground--emacs-executable))))
    (mapcar (lambda (filename) (expand-file-name filename dir))
            (list original-name (concat original-name "-noplay")))))

(defun playground--read-url (prompt)
  "Read a repository URL from the minibuffer, prompting with a string PROMPT."
  (read-from-minibuffer prompt))

(defun playground--update-symlinks (dest)
  "Produce missing symbolic links in the sandbox directory DEST."
  (let ((origin playground-original-home-directory))
    (cl-loop for relpath in playground-inherited-contents
             do (let ((src (expand-file-name relpath origin))
                      (new (expand-file-name relpath dest)))
                  (when (and (not (file-exists-p new))
                             (file-exists-p src))
                    (make-directory (file-name-directory new) t)
                    (make-symbolic-link src new))
                  ))))

(defconst playground--github-repo-path-pattern
  "\\(?:[0-9a-z][-0-9a-z]+/[-a-z0-9_.]+?[0-9a-z]\\)"
  "A regular expression for a repository path (user/repo) on GitHub.")

(defconst playground--github-repo-url-patterns
  (list (concat "^git@github\.com:\\("
                playground--github-repo-path-pattern
                "\\)\\(?:\.git\\)$")
        (concat "^https://github\.com/\\("
                playground--github-repo-path-pattern
                "\\)\\(\.git\\)?$"))
  "A list of regular expressions that match a repository URL on GitHub.")

(defun playground--github-repo-path-p (path)
  "Check if PATH is a repository path (user/repo) on GitHub."
  (let ((case-fold-search t))
    (string-match-p (concat "^" playground--github-repo-path-pattern "$") path)))

(defun playground--parse-github-url (url)
  "Return a repository path (user/repo) if URL is a repository URL on GitHub."
  (cl-loop for pattern in playground--github-repo-url-patterns
           when (string-match pattern url)
           return (match-string 1 url)))

(defun playground--github-repo-path-to-https-url (path)
  "Convert a GitHub repository PATH into a HTTPS url."
  (concat "https://github.com/" path ".git"))

(defun playground--build-name-from-url (url)
  "Produce a sandbox name from a repository URL."
  (pcase (playground--parse-github-url url)
    (`nil "")
    (rpath (car (split-string rpath "/")))))

(defun playground--directory (name)
  "Get the path of a sandbox named NAME."
  (expand-file-name name playground-directory))

;;;###autoload
(defun playground-update-symlinks ()
  "Update missing symbolic links in existing local sandboxes."
  (interactive)
  (mapc #'playground--update-symlinks
        (directory-files playground-directory t "^\[^.\]")))

(defvar playground-last-config-home nil
  "Path to the sandbox last run.")

(defun playground--process-buffer-name (name)
  "Generate the name of a buffer for a sandbox named NAME."
  (format "*play %s*" name))

(defun playground--start (name home)
  "Start a sandbox named NAME at HOME."
  ;; Fail if Emacs is not run inside a window system
  (unless window-system
    (error "Can't start another Emacs as you are not using a window system"))

  (let ((process-environment (cons (concat "HOME=" home)
                                   process-environment))
        ;; Convert default-directory to full-path so Playground can be run on cask
        (default-directory (expand-file-name default-directory)))
    (start-process "playground"
                   (playground--process-buffer-name name)
                   (playground--emacs-executable))
    (setq playground-last-config-home home)))

;; TODO: Add support for Helm
(defun playground--config-selector (prompt installed available-alist)
  "Run ‘completing-read’ to select a sandbox to check out.

- PROMPT is a prompt displayed in the minibuffer.
- INSTALLED is a list of sandbox named which are already available locally.
- AVAILABLE-ALIST is an alist of sandboxes, which is usually taken from
  `playground-dotemacs-alist'."
  (completing-read prompt
                   (cl-remove-duplicates (append installed
                                              (mapcar 'car available-alist))
                                      :test 'equal)))

(defun playground--select-config (available-alist)
  "Select a sandbox to check out from either pre-configurations or a URL.

AVAILABLE-ALIST is an alist of dotemacs configurations, which is usually
taken from playground-dotemacs-alist."
  (let* ((installed-list (directory-files playground-directory nil "^\[^.\]"))
         (inp (playground--config-selector "Choose a configuration or enter a repository URL: "
                                     installed-list available-alist))
         (installed (member inp installed-list))
         (available (assoc inp available-alist)))
    (cond
     (installed (let ((name inp))
                  (playground--start name (playground--directory name))))
     (available (apply 'playground--start-with-dotemacs available))
     ((playground--git-url-p inp) (let ((name (read-from-minibuffer "Name for the config: "
                                                              (playground--build-name-from-url inp))))
                              (playground--start-with-dotemacs name :repo inp)))
     (t (error (format "Doesn't look like a repository URL: %s" inp))))))

(defun playground--git-url-p (s)
  "Test if S is a URL to a Git repository."
  (or (string-match-p "^\\(?:ssh|rsync|git|https?|file\\)://.+\.git/?$" s)
      (string-match-p "^\\(?:[-.a-zA-Z1-9]+@\\)?[-./a-zA-Z1-9]+:[-./a-zA-Z1-9]+\.git/?$" s)
      (string-match-p (concat "^https://github.com/"
                              playground--github-repo-path-pattern) s)
      (and (string-suffix-p ".git" s) (file-directory-p s)) ; local bare repository
      (and (file-directory-p s) (file-directory-p (expand-file-name ".git" s))) ; local working tree
      ))

(cl-defun playground--initialize-sandbox (name url
                                         &key
                                         (recursive t)
                                         (depth 1))
  "Initialize a sandbox with a configuration repository."
  (let ((dpath (playground--directory name)))
    (condition-case err
        (progn
          (make-directory dpath t)
          (apply 'process-lines
                 (remove nil (list "git" "clone"
                                   (when recursive "--recursive")
                                   (when depth
                                     (concat "--depth="
                                             (cond ((stringp depth) depth)
                                                   ((numberp depth) (int-to-string depth)))))
                                   url
                                   (expand-file-name ".emacs.d" dpath)))
                 )
          (playground--update-symlinks dpath)
          dpath)
      (error (progn (message (format "Cleaning up %s..." dpath))
                    (delete-directory dpath t)
                    (error (error-message-string err)))))))

(cl-defun playground--start-with-dotemacs (name
                                     &rest other-props
                                     &key repo &allow-other-keys)
  "Start Emacs on a sandbox named NAME."
  (when (null repo)
    (error "You must pass :repo to playground--start-with-dotemacs function"))
  (let ((url (if (playground--github-repo-path-p repo)
                 (playground--github-repo-path-to-https-url repo)
               repo)))
    (playground--start name
                 (apply 'playground--initialize-sandbox
                        name url
                        (cl-remprop 'repo other-props)))))

;;;###autoload
(defun playground-checkout (&optional name)
  "Start Emacs on a sandbox.

If NAME is given, check out the sandbox from playground-dotemacs-alist."
  (interactive)

  (make-directory playground-directory t)

  (pcase (and name (playground--directory name))

    ;; NAME refers to an existing sandbox
    (`(and (pred file-directory-p)
           ,dpath)
     (playground--start name dpath))

    ;; Otherwise
    (`nil
     ;; Build an alist from playground-dotemacs-list
     (let ((alist (cl-loop for plist in playground-dotemacs-list
                           collect (cons (or (plist-get plist :name)
                                             (playground--build-name-from-url (plist-get plist :repo)))
                                         plist))))
       (if (null name)
           (playground--select-config alist)
         (pcase (assoc name alist)
           (`nil (error (format "Config named %s does not exist in playground-dotemacs-list"
                                name)))
           (pair (apply 'playground--start-with-dotemacs pair))))))))

;;;###autoload
(defun playground-start-last ()
  "Start Emacs on the last sandbox run by Playground."
  (interactive)
  (pcase (and (boundp 'playground-last-config-home)
              playground-last-config-home)
    (`nil (error "Play has not been run yet. Run 'playground-checkout'"))
    (home (let* ((name (file-name-nondirectory home))
                 (proc (get-buffer-process (playground--process-buffer-name name))))
            (if (and proc (process-live-p proc))
                (when (yes-or-no-p (format "%s is still running. Kill it? " name))
                  (lexical-let ((sentinel (lambda (_ event)
                                            (cond
                                             ((string-prefix-p "killed" event) (playground--start name home))))))
                    (set-process-sentinel proc sentinel)
                    (kill-process proc)))
              (playground--start name home))))))

;;;###autoload
(defun playground-persist ()
  "Generate wrapper scripts to make the last sandbox environment the default."
  (interactive)

  (unless (boundp 'playground-last-config-home)
    (error "No play instance has been run yet"))

  (let ((home playground-last-config-home))
    (when (yes-or-no-p (format "Set $HOME of Emacs to %s? " home))
      (destructuring-bind
          (wrapper unwrapper) (playground--script-paths)
        (playground--generate-runner wrapper home)
        (playground--generate-runner unwrapper playground-original-home-directory)
        (message (format "%s now starts with %s as $HOME. Use %s to start normally"
                         (file-name-nondirectory wrapper)
                         home
                         (file-name-nondirectory unwrapper)))))))

(defun playground--generate-runner (fpath home)
  "Generate an executable script at FPATH for running Emacs on HOME."
  (with-temp-file fpath
    (insert (concat "#!/bin/sh\n"
                    (format "HOME=%s exec %s \"$@\""
                            home
                            (playground--emacs-executable)))))
  (set-file-modes fpath #o744))

;;;###autoload
(defun playground-return ()
  "Delete wrapper scripts generated by Playground."
  (interactive)
  (when (yes-or-no-p "Delete the scripts created by play? ")
    (mapc 'delete-file (cl-remove-if-not 'file-exists-p (playground--script-paths)))))

(provide 'playground)

;;; playground.el ends here
