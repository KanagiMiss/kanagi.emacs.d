(require-package 'flymake-cursor)

;;basic configuration
(autoload 'flymake-find-file-hook "flymake" "" t)
(add-hook 'find-file-hook 'flymake-find-file-hook)
(setq flymake-gui-warnings-enabled nil)
(setq flymake-log-level 0)

;;syntax-check for c/c++
(setq flymake-allowed-file-name-masks '())
;;(when (executable-find "texify")
;;  (add-to-list 'flymake-allowed-file-name-masks
;;               '("\\.tex\\'" flymake-simple-tex-init))
;;  (add-to-list 'flymake-allowed-file-name-masks
;;               '("[0-9]+\\.tex\\'"
;;                 flymake-master-tex-init flymake-master-cleanup)))
(when (executable-find "xml")
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.xml\\'" flymake-xml-init))
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.html?\\'" flymake-xml-init)))
(when (executable-find "perl")
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.p[ml]\\'" flymake-perl-init)))
(when (executable-find "php")
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.php[1]?\\'" flymake-php-init)))
(when (executable-find "make")
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.idl\\'" flymake-simple-make-init))
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.java\\'"
                 flymake-simple-make-java-init flymake-simple-java-cleanup))
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.cs\\'" flymake-simple-make-init)))
(when (or (executable-find "make")
          (executable-find "gcc")
          (executable-find "g++"))
  (defvar flymake-makefile-filenames '("Makefile" "makefile" "GNUmakefile")
    "File names for make.")
  (defun flymake-get-gcc-cmdline (source base-dir)
    (let ((cc (if (string= (file-name-extension source) "c") "gcc" "g++")))
      (list cc
            (list "-Wall"
                  "-Wextra"
                  "-pedantic"
                  "-fsyntax-only"
                  "-I.."
                  "-I../include"
                  "-I../inc"
                  "-I../common"
                  "-I../public"
                  "-I../.."
                  "-I../../include"
                  "-I../../inc"
                  "-I../../common"
                  "-I../../public"
                  source))))
  (defun flymake-init-find-makfile-dir (source-file-name)
    "Find Makefile, store its dir in buffer data and return its dir, if found."
    (let* ((source-dir (file-name-directory source-file-name))
           (buildfile-dir nil))
      (catch 'found
        (dolist (makefile flymake-makefile-filenames)
          (let ((found-dir (flymake-find-buildfile makefile source-dir)))
            (when found-dir
              (setq buildfile-dir found-dir)
              (setq flymake-base-dir buildfile-dir)
              (throw 'found t)))))
      buildfile-dir))
  (defun flymake-simple-make-gcc-init-impl (create-temp-f
                                            use-relative-base-dir
                                            use-relative-source)
    "Create syntax check command line for a directly checked source file.
Use CREATE-TEMP-F for creating temp copy."
    (let* ((args nil)
           (source-file-name buffer-file-name)
           (source-dir (file-name-directory source-file-name))
           (buildfile-dir
            (and (executable-find "make")
                 (flymake-init-find-makfile-dir source-file-name)))
           (cc (if (string= (file-name-extension source-file-name) "c")
                   "gcc"
                 "g++")))
      (if (or buildfile-dir (executable-find cc))
          (let* ((temp-source-file-name
                  (ignore-errors
                    (flymake-init-create-temp-buffer-copy create-temp-f))))
            (if temp-source-file-name
                (setq args
                      (flymake-get-syntax-check-program-args
                       temp-source-file-name
                       (if buildfile-dir buildfile-dir source-dir)
                       use-relative-base-dir
                       use-relative-source
                       (if buildfile-dir
                           'flymake-get-make-cmdline
                         'flymake-get-gcc-cmdline)))
              (flymake-report-fatal-status
               "TMPERR"
               (format "Can't create temp file for %s" source-file-name))))
        (flymake-report-fatal-status
         "NOMK" (format "No buildfile (%s) found for %s, or can't found %s"
                        "Makefile" source-file-name cc)))
      args))
  (defun flymake-simple-make-gcc-init ()
    (flymake-simple-make-gcc-init-impl 'flymake-create-temp-inplace t t))
  (defun flymake-master-make-gcc-init (get-incl-dirs-f
                                       master-file-masks
                                       include-regexp)
    "Create make command line for a source file
 checked via master file compilation."
    (let* ((args nil)
           (temp-master-file-name
            (ignore-errors
              (flymake-init-create-temp-source-and-master-buffer-copy
               get-incl-dirs-f
               'flymake-create-temp-inplace
               master-file-masks
               include-regexp)))
           (cc (if (string= (file-name-extension buffer-file-name) "c")
                   "gcc"
                 "g++")))
      (if temp-master-file-name
          (let* ((source-file-name buffer-file-name)
                 (source-dir (file-name-directory source-file-name))
                 (buildfile-dir
                  (and (executable-find "make")
                       (flymake-init-find-makfile-dir source-file-name))))
            (if (or buildfile-dir (executable-find cc))
                (setq args (flymake-get-syntax-check-program-args
                            temp-master-file-name
                            (if buildfile-dir buildfile-dir source-dir)
                            nil
                            nil
                            (if buildfile-dir
                                'flymake-get-make-cmdline
                              'flymake-get-gcc-cmdline)))
              (flymake-report-fatal-status
               "NOMK"
               (format "No buildfile (%s) found for %s, or can't found %s"
                       "Makefile" source-file-name cc))))
        (flymake-report-fatal-status
         "TMPERR" (format "Can't create temp file for %s" source-file-name)))
      args))
  (defun flymake-master-make-gcc-header-init ()
    (flymake-master-make-gcc-init
     'flymake-get-include-dirs
     '("\\.cpp\\'" "\\.c\\'")
     "[ \t]*#[ \t]*include[ \t]*\"\\([[:word:]0-9/\\_.]*%s\\)\""))
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.\\(?:h\\(?:pp\\)?\\)\\'"
                 flymake-master-make-gcc-header-init flymake-master-cleanup))
  (add-to-list 'flymake-allowed-file-name-masks
               '("\\.\\(?:c\\(?:pp\\|xx\\|\\+\\+\\)?\\|CC\\)\\'"
                 flymake-simple-make-gcc-init)))







;;set the custom face of flymake
(custom-set-faces
 '(flymake-errline ((((class color)) (:underline "red"))))
 '(flymake-warnline ((((class color)) (:underline "blue")))))

;; Stop flymake from breaking when ruby-mode is invoked by mmm-mode,
;; at which point buffer-file-name is nil
(eval-after-load 'flymake
  '(progn
     (defun flymake-can-syntax-check-file (file-name)
       "Determine whether we can syntax check FILE-NAME.
Return nil if we cannot, non-nil if we can."
       (if (and file-name (flymake-get-init-function file-name)) t nil))))

(provide 'init-flymake)
