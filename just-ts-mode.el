;;; just-ts-mode.el --- Major mode for editing Just files  -*- lexical-binding: t -*-

;; Copyright (C) 2024 Mario Rodas <marsam@users.noreply.github.com>

;; Author: Mario Rodas <marsam@users.noreply.github.com>
;; URL: https://github.com/emacs-pe/just-ts-mode
;; Keywords: just languages tree-sitter
;; Version: 0.1
;; Package-Requires: ((emacs "29.1"))

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Support for Just <https://just.systems/> files.

;; This package is compatible with and tested against the grammar for
;; Just found at <https://github.com/IndianBoy42/tree-sitter-just>

;; -------------------------------------------------------------------
;; Israel is committing genocide of the Palestinian people.
;;
;; The population in Gaza is facing starvation, displacement and
;; annihilation amid relentless bombardment and suffocating
;; restrictions on life-saving humanitarian aid.
;;
;; As of March 2025, Israel has killed over 50,000 Palestinians in the
;; Gaza Strip – including 15,600 children – targeting homes,
;; hospitals, schools, and refugee camps.  However, the true death
;; toll in Gaza may be at least around 41% higher than official
;; records suggest.
;;
;; The website <https://databasesforpalestine.org/> records extensive
;; digital evidence of Israel's genocidal acts against Palestinians.
;; Save it to your bookmarks and let more people know about it.
;;
;; Silence is complicity.
;; Protest and boycott the genocidal apartheid state of Israel.
;;
;;
;;                  From the river to the sea, Palestine will be free.
;; -------------------------------------------------------------------

;;; Code:
(require 'treesit)
(require 'pcomplete)

(defgroup just-ts nil
  "Major mode for editing Just files."
  :prefix "just-ts-"
  :group 'languages)

(defcustom just-ts-flymake-command '("just" "--dump" "--color=never" "--justfile=/dev/stdin")
  "External tool used to check Just source code.
This is a non-empty list of strings: the checker tool possibly
followed by required arguments.  Once launched it will receive
the Justfile source to be checked as its standard input."
  :type '(repeat string))

(defvar-local just-ts--flymake-proc nil)

;;;###autoload
(defun just-ts-flymake (report-fn &rest _args)
  "Just backend for Flymake.
Launch `just-ts-flymake-command' (which see) and pass to its
standard input the contents of the current buffer.  The output of
this command is analyzed for error messages."
  (unless (executable-find (car just-ts-flymake-command))
    (error "Cannot find the Just flymake program: %s" (car just-ts-flymake-command)))

  (when (process-live-p just-ts--flymake-proc)
    (kill-process just-ts--flymake-proc))

  (let ((source (current-buffer)))
    (save-restriction
      (widen)
      (setq
       just-ts--flymake-proc
       (make-process
        :name "just-flymake" :noquery t :connection-type 'pipe
        :buffer (generate-new-buffer " *just-ts-flymake*")
        :command just-ts-flymake-command
        :sentinel
        (lambda (proc _event)
          (when (eq 'exit (process-status proc))
            (unwind-protect
                (if (with-current-buffer source (eq proc just-ts--flymake-proc))
                    (with-current-buffer (process-buffer proc)
                      (goto-char (point-min))
                      (cl-loop
                       while (search-forward-regexp
                              "^error: \\(.+\\):?[[:space:]]+——▶ stdin:\\([[:digit:]]+\\):\\([[:digit:]]+\\)$"
                              nil t)
                       for msg = (match-string 1)
                       for (beg . end) = (flymake-diag-region
                                          source
                                          (string-to-number (match-string 2))
                                          (string-to-number (match-string 3)))
                       collect (flymake-make-diagnostic source beg end :error msg)
                       into diags
                       finally (funcall report-fn diags)))
                  (flymake-log :debug "Canceling obsolete check %s" proc))
              (kill-buffer (process-buffer proc)))))))
      (process-send-region just-ts--flymake-proc (point-min) (point-max))
      (process-send-eof just-ts--flymake-proc))))

(defvar just-ts--builtins
  '(;; https://github.com/casey/just/blob/master/GRAMMAR.md#grammar
    "allow-duplicate-recipes" "allow-duplicate-variables"
    "dotenv-filename" "dotenv-load" "dotenv-path" "dotenv-required"
    "export" "fallback" "ignore-comments" "positional-arguments"
    "script-interpreter" "quiet" "shell" "tempdir" "unstable"
    "windows-powershell" "windows-shell" "working-directory")
  "Just built-ins for tree-sitter font-locking.")

(defvar just-ts--builtin-functions
  (let ((functions
         '(;; https://just.systems/man/en/functions.html
           "absolute_path" "append" "arch" "blake3" "blake3_file"
           "cache_directory" "canonicalize" "capitalize" "choose"
           "clean" "config_directory" "config_local_directory"
           "data_directory" "data_local_directory" "datetime"
           "datetime_utc" "encode_uri_component" "env" "env_var"
           "env_var_or_default" "error" "executable_directory"
           "extension" "file_name" "file_stem" "home_directory"
           "invocation_directory" "invocation_dir_native"
           "invocation_directory_native" "is_dependency" "join"
           "just_executable" "just_pid" "justfile"
           "justfile_directory" "kebabcase" "lowercamelcase"
           "lowercase" "module_directory" "module_file" "num_cpus"
           "os" "os_family" "parent_directory" "path_exists" "prepend"
           "quote" "read" "replace" "replace_regex" "require"
           "semver_matches" "sha256" "sha256_file" "shell"
           "shoutykebabcase" "shoutysnakecase" "snakecase"
           "source_directory" "source_file" "style" "titlecase" "trim"
           "trim_end" "trim_end_match" "trim_end_matches" "trim_start"
           "trim_start_match" "trim_start_matches" "uppercamelcase"
           "uppercase" "uuid" "which" "without_extension")))
    ;; "All functions ending in _directory can be abbreviated to _dir."
    ;; https://just.systems/man/en/functions.html#functions
    (dolist (fun functions functions)
      (when (string-suffix-p "_directory" fun)
        (push (substring fun 0 -6) functions))))
  "Just built-in functions for tree-sitter font-locking.")

(defvar just-ts--keywords
  '("export" "import" "mod"
    "alias" "set" "shell"
    "if" "else")
  "Just keywords for tree-sitter font-locking.")

(defvar just-ts--operators
  '(":=" "?"  "==" "!=" "=~" "@" "=" "$" "*" "+" "&&" "@-" "-@" "-"
    "/" ":")
  "Just operators for tree-sitter font-locking.")

(defvar just-ts--attributes
  '(;; https://just.systems/man/en/attributes.html#attributes
    "confirm" "doc" "extension" "group" "linux" "macos" "no-cd"
    "no-exit-message" "no-quiet" "openbsd" "positional-arguments"
    "private" "script" "unix" "windows" "working-directory"))

(defconst just-ts--font-lock-settings
  (treesit-font-lock-rules
   :language 'just
   :feature 'comment
   '((comment) @font-lock-comment-face
     (shebang) @font-lock-comment-face)

   :language 'just
   :feature 'attribute
   `((recipe
      (attribute
       (identifier) @font-lock-preprocessor-face
       (:match ,(regexp-opt just-ts--attributes 'symbols) @font-lock-preprocessor-face))))

   :language 'just
   :feature 'keyword
   `([,@just-ts--keywords] @font-lock-keyword-face)

   :language 'just
   :feature 'operator
   `([,@just-ts--operators] @font-lock-operator-face)

   :language 'just
   :feature 'builtin
   `((setting
      (identifier) @font-lock-builtin-face
      (:match ,(regexp-opt just-ts--builtins 'symbols) @font-lock-builtin-face)))

   :language 'just
   :feature 'constant
   '(["true" "false"] @font-lock-constant-face)

   :language 'just
   :feature 'string
   '([(string) (external_command)] @font-lock-string-face)

   :language 'just
   :feature 'bracket
   '((["(" ")" "[" "]" "{" "}"]) @font-lock-bracket-face)

   :language 'just
   :feature 'delimiter
   '(([","]) @font-lock-delimiter-face)

   :language 'just
   :feature 'interpolation
   '((interpolation "{{" @font-lock-misc-punctuation-face)
     (interpolation "}}" @font-lock-misc-punctuation-face))

   :language 'just
   :feature 'function
   `((function_call
      (identifier) @font-lock-function-call-face
      (:match ,(regexp-opt just-ts--builtin-functions 'symbols) @font-lock-function-call-face)))

   :language 'just
   :feature 'definition
   '((module name: (identifier) @font-lock-function-name-face)
     (recipe_header (identifier) @font-lock-function-name-face)
     (dependency (identifier) @font-lock-function-call-face)
     (dependency_expression (identifier) @font-lock-function-call-face))

   :language 'just
   :feature 'variable
   '((assignment left: (identifier) @font-lock-variable-name-face)
     (alias (identifier) @font-lock-variable-name-face)
     (value (identifier) @font-lock-variable-name-face))

   :language 'just
   :feature 'parameter
   '((parameter (identifier) @font-lock-property-name-face)
     (dependency_expression
      (expression (value (identifier) @font-lock-property-name-face))))

   :language 'just
   :feature 'error
   :override t
   '([(ERROR) (numeric_error)] @font-lock-warning-face))
  "Tree-sitter font-lock settings for `just-ts-mode'.")

(defconst just-ts--indent-rules
  `((just
     ((parent-is "source_file") column-0 0))))

(defun just-ts--treesit-defun-name (node)
  "Return the defun name of NODE.
Return nil if there is no name or if NODE is not a defun node."
  (pcase (treesit-node-type node)
    ("recipe_header"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name")))
    ((or "alias" "assignment")
     (treesit-node-text
      (treesit-node-child-by-field-name node "left")))))

(defun just-ts--alias-node-p (node)
  "Return t if NODE is a type alias."
  (and
   (string-equal "alias" (treesit-node-type node))
   (treesit-node-named node)))

;;;###autoload
(defun pcomplete/just ()
  "Completion for `just'."
  (pcomplete-opt "bmC/def(just-ts--justfile-names)hiI/j?kl?no.pqrsStvwW.")
  (while (pcomplete-here (just-ts--recipe-names))))

(defun just-ts--recipe-names ()
  "Return a list of available Just recipes."
  (with-temp-buffer
    (when (zerop (call-process "just" nil t nil "--list" "--color=never"))
      (goto-char (point-min))
      (let (cmds)
        (while (re-search-forward "^[[:space:]]+\\([^[:space:]]+\\)" nil t)
          (setq cmds (cons (match-string 1) cmds)))
        cmds))))

(defun just-ts--justfile-names ()
  "Return a list of possible Justfile names."
  (pcomplete-entries "\\`\\.?[Jj]ustfile"))

;;;###autoload
(define-derived-mode just-ts-mode prog-mode "Just"
  "Major mode for editing standard Justfiles using treesitter."
  (when (treesit-ready-p 'just)
    (treesit-parser-create 'just)

    ;; Comments.
    (setq-local comment-start "# ")
    (setq-local comment-end "")
    (setq-local comment-start-skip "#\\s-*")

    ;; Indent.
    (setq-local indent-tabs-mode nil)
    (setq-local treesit-simple-indent-rules just-ts--indent-rules)

    ;; Font-lock.
    (setq-local treesit-font-lock-settings just-ts--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment keyword string attribute)
                  (definition constant builtin variable parameter delimiter interpolation)
                  (bracket error function operator)))

    ;; Imenu.
    (setq-local treesit-simple-imenu-settings
                `(("Recipe" "\\`recipe_header\\'" nil nil)
                  ("Variable" "\\`assignment\\'" nil nil)
                  ("Alias" "\\`alias\\'" just-ts--alias-node-p nil)))

    ;; Navigation.
    (setq-local treesit-defun-type-regexp
                (regexp-opt '("recipe_header" "assignment" "alias")))
    (setq-local treesit-defun-name-function #'just-ts--treesit-defun-name)

    ;; Flymake.
    (add-hook 'flymake-diagnostic-functions #'just-ts-flymake nil 'local)

    (treesit-major-mode-setup)))

;;;###autoload
(when (treesit-ready-p 'just)
  (add-to-list 'auto-mode-alist '("/\\.?[Jj]ustfile\\'" . just-ts-mode))
  (add-to-list 'interpreter-mode-alist '("just" . just-ts-mode)))

(provide 'just-ts-mode)
;;; just-ts-mode.el ends here
