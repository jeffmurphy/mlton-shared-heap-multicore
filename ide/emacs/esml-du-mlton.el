;; Copyright (C) 2007 Vesa Karvonen
;;
;; MLton is released under a BSD-style license.
;; See the file MLton-LICENSE for details.

(require 'def-use-mode)
(require 'bg-job)
(require 'esml-util)

;; XXX Fix race condition when (re)loading def-use file that is being written.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Customization

(defgroup esml-du nil
  "MLton def-use info plugin for `def-use-mode'."
  :group 'sml)

(defcustom esml-du-background-parsing 'disabled
  "Method of performing background parsing of def-use data.

Background parsing is disabled by default, but this may downgrade some
functionality, increase overall memory consumption, and real-time lookup
will be slower.

Eager parsing means that background parsing is started immediately when a
def-use file is first loaded or modified.

Lazy parsing means that background parsing starts when the first real-time
query of def-use data finds useful data.

The disabled and lazy options are perhaps better than eager if you wish to
register def-use files at Emacs load time."
  :type '(choice (const :tag "Disabled" disabled)
                 (const :tag "Eager" eager)
                 (const :tag "Lazy" lazy))
  :group 'esml-du)

(defcustom esml-du-change-poll-period nil
  "Delay in seconds between file change polls.  This is basically only
useful with eager background parsing (see `esml-du-background-parsing') to
ensure that background parsing will occur even when Emacs remains
otherwise idle as reloading is also triggered implicitly when def-use data
is needed."
  :type '(choice (number :tag "Period in seconds")
                 (const :tag "Disable polling" nil))
  :group 'esml-du)

(defcustom esml-du-notify 'never
  "Notify certain events."
  :type '(choice (const :tag "Never" never)
                 (const :tag "Always" always))
  :group 'esml-du)

(defcustom esml-du-dufs-auto-load nil
  "Automatic loading of `esml-du-dufs-recent' at startup."
  :type '(choice
          (const :tag "Disabled" nil)
          (const :tag "Enabled" t))
  :group 'esml-du)

(defcustom esml-du-dufs-recent '()
  "Automatically updated list of def-use -files currently or previously
loaded.  This customization variable is not usually manipulated directly
by the user."
  :type '(repeat
          (file :tag "Def-Use file" :must-match t))
  :group 'esml-du)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interface

(defvar esml-du-mlton-history nil)

(defun esml-du-mlton (&optional duf dont-save)
  "Gets def-use information from a def-use file produced by MLton."
  (interactive)
  (cond
   ((not duf)
    (esml-du-mlton
     (compat-read-file-name
      "Specify def-use -file: " nil nil t nil 'esml-du-mlton-history)
     dont-save))
   ((not (and (file-readable-p duf)
              (file-regular-p duf)))
    (compat-error "Specified file is not a regular readable file"))
   ((run-with-idle-timer
     0.5 nil
     (function
      (lambda (duf dont-save)
        (let ((duf (def-use-file-truename duf)))
          (unless (member duf esml-du-live-dufs)
            (let ((ctx (esml-du-ctx duf)))
              (esml-du-load ctx)
              (esml-du-set-live-dufs (cons duf esml-du-live-dufs) dont-save)
              (def-use-add-dus
                (function esml-du-title)
                (function esml-du-sym-at-ref)
                (function esml-du-sym-to-uses)
                (function esml-du-finalize)
                (function esml-du-ctx-attr)
                ctx))))))
     duf dont-save))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Move to symbol

(defun esml-du-character-class (c)
  (cond
   ((find c esml-sml-symbolic-chars)
    'symbolic)
   ((find c esml-sml-alphanumeric-chars)
    'alphanumeric)))

(defun esml-du-extract-following-symbol (chars)
  (save-excursion
    (let ((start (point)))
      (skip-chars-forward chars)
      (buffer-substring start (point)))))

(defun esml-du-move-to-symbol-start ()
  "Moves to the start of the SML symbol at point.  If the point is between
two symbols, one symbolic and other alphanumeric (e.g. !x) the symbol
following the point is preferred.  This ensures that the symbol does not
change surprisingly after a jump."
  (let ((bef (esml-du-character-class (char-before)))
        (aft (esml-du-character-class (char-after))))
    (cond
     ((and (eq bef 'alphanumeric) (eq aft 'symbolic)
           (find (esml-du-extract-following-symbol esml-sml-symbolic-chars)
                 esml-sml-symbolic-keywords
                 :test 'equal))
      (skip-chars-backward esml-sml-alphanumeric-chars))
     ((and (eq bef 'symbolic) (eq aft 'alphanumeric)
           (find (esml-du-extract-following-symbol esml-sml-alphanumeric-chars)
                 esml-sml-alphanumeric-keywords
                 :test 'equal))
      (skip-chars-backward esml-sml-symbolic-chars))
     ((and (eq bef 'symbolic) (not (eq aft 'alphanumeric)))
      (skip-chars-backward esml-sml-symbolic-chars))
     ((and (eq bef 'alphanumeric) (not (eq aft 'symbolic)))
      (skip-chars-backward esml-sml-alphanumeric-chars)))))

(add-to-list 'def-use-mode-to-move-to-symbol-start-alist
             (cons 'sml-mode (function esml-du-move-to-symbol-start)))

(defun esml-du-move-to-symbol-end ()
  "Moves to the end of the SML symbol at point assuming that we are at the
beginning of the symbol."
  (let ((limit (def-use-point-at-next-line)))
    (when (zerop (skip-chars-forward esml-sml-alphanumeric-chars limit))
      (skip-chars-forward esml-sml-symbolic-chars limit))))

(add-to-list 'def-use-mode-to-move-to-symbol-end-alist
             (cons 'sml-mode (function esml-du-move-to-symbol-end)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Methods

(defun esml-du-title (ctx)
  (concat
   (esml-du-ctx-duf ctx)
   " ["
   (if (esml-du-ctx-buf ctx)
       (concat "parsing: "
               (int-to-string
                (truncate
                 (/ (buffer-size (esml-du-ctx-buf ctx))
                    0.01
                    (nth 7 (esml-du-ctx-attr ctx)))))
               "% left")
     "complete")
   ", parsed "
   (int-to-string (esml-du-ctx-parse-cnt ctx))
   " times]"))

(defun esml-du-sym-at-ref (ref ctx)
  (esml-du-reload ctx)
  (unless (or (let ((buffer (def-use-find-buffer-visiting-file
                              (def-use-ref-src ref))))
                (and buffer (buffer-modified-p buffer)))
              (def-use-attr-newer?
                (file-attributes (def-use-ref-src ref))
                (esml-du-ctx-attr ctx)))
    (or (gethash ref (esml-du-ctx-ref-to-sym-table ctx))
        (and (esml-du-try-to-read-symbol-at-ref ref ctx)
             (gethash ref (esml-du-ctx-ref-to-sym-table ctx))))))

(defun esml-du-sym-to-uses (sym ctx)
  (esml-du-reload ctx)
  (let ((file-to-poss (def-use-make-hash-table)))
    ;; Process by buffer/file as it avoids repeated work
    (mapc (function
           (lambda (ref)
             (puthash (def-use-ref-src ref)
                      (cons ref
                            (gethash (def-use-ref-src ref) file-to-poss))
                      file-to-poss)))
          (gethash sym (esml-du-ctx-sym-to-uses-table ctx)))
    ;; Remove references to modified buffers
    (mapc (function
           (lambda (buffer)
             (when (buffer-modified-p buffer)
               (remhash (def-use-buffer-file-truename buffer)
                        file-to-poss))))
          (buffer-list))
    ;; Remove references to modified files
    (mapc (function
           (lambda (file)
             (when (def-use-attr-newer?
                     (file-attributes file)
                     (esml-du-ctx-attr ctx))
               (remhash file file-to-poss))))
          (def-use-hash-table-to-key-list file-to-poss))
    (apply (function nconc)
           (def-use-hash-table-to-value-list file-to-poss))))

(defun esml-du-stop-parsing (ctx)
  (let ((buffer (esml-du-ctx-buf ctx)))
    (when buffer
      (kill-buffer buffer))))

(defvar esml-du-live-dufs nil)

(defun esml-du-set-live-dufs (dufs &optional dont-save)
  (setq esml-du-live-dufs dufs)
  (when (and (not dont-save)
             esml-du-dufs-auto-load)
    (customize-save-variable
     'esml-du-dufs-recent
     (copy-list dufs))))

(defun esml-du-finalize (ctx)
  (esml-du-stop-parsing ctx)
  (let ((timer (esml-du-ctx-poll-timer ctx)))
    (when timer
      (compat-delete-timer timer)
      (esml-du-ctx-set-poll-timer nil ctx)))
  (esml-du-set-live-dufs
   (remove* (esml-du-ctx-duf ctx)
            esml-du-live-dufs
            :test (function equal))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Context

(defun esml-du-ctx (duf)
  (let ((ctx (vector (def-use-make-hash-table) (def-use-make-hash-table)
                     duf nil nil nil 0 nil)))
    (when esml-du-change-poll-period
      (esml-du-ctx-set-poll-timer
       (run-with-timer esml-du-change-poll-period esml-du-change-poll-period
                       (function esml-du-reload) ctx)
       ctx))
    ctx))

(defun esml-du-ctx-parsing?          (ctx) (aref ctx 7))
(defun esml-du-ctx-parse-cnt         (ctx) (aref ctx 6))
(defun esml-du-ctx-poll-timer        (ctx) (aref ctx 5))
(defun esml-du-ctx-buf               (ctx) (aref ctx 4))
(defun esml-du-ctx-attr              (ctx) (aref ctx 3))
(defun esml-du-ctx-duf               (ctx) (aref ctx 2))
(defun esml-du-ctx-ref-to-sym-table  (ctx) (aref ctx 1))
(defun esml-du-ctx-sym-to-uses-table (ctx) (aref ctx 0))

(defun esml-du-ctx-inc-parse-cnt  (ctx)
  (aset ctx 6 (1+ (aref ctx 6))))

(defun esml-du-ctx-set-parsing?   (bool  ctx) (aset ctx 7 bool))
(defun esml-du-ctx-set-poll-timer (timer ctx) (aset ctx 5 timer))
(defun esml-du-ctx-set-buf        (buf   ctx) (aset ctx 4 buf))
(defun esml-du-ctx-set-attr       (attr  ctx) (aset ctx 3 attr))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Parsing

(defun esml-du-read (taking skipping)
  (let ((start (point)))
    (skip-chars-forward taking)
    (let ((result (buffer-substring start (point))))
      (skip-chars-forward skipping)
      result)))

(defconst esml-du-classes ;; XXX Needs customization
  `((,(def-use-intern "variable")    . ,font-lock-variable-name-face)
    (,(def-use-intern "type")        . ,font-lock-variable-name-face)
    (,(def-use-intern "constructor") . ,font-lock-variable-name-face)
    (,(def-use-intern "structure")   . ,font-lock-variable-name-face)
    (,(def-use-intern "signature")   . ,font-lock-variable-name-face)
    (,(def-use-intern "functor")     . ,font-lock-variable-name-face)
    (,(def-use-intern "exception")   . ,font-lock-variable-name-face)))

(defun esml-du-reload (ctx)
  "Reloads the def-use file if it has been modified."
  (when (def-use-attr-newer?
          (file-attributes (esml-du-ctx-duf ctx))
          (esml-du-ctx-attr ctx))
    (esml-du-load ctx)))

(defun esml-du-try-to-read-symbol-at-ref-once (ref ctx)
  (when (search-forward (esml-du-ref-to-appx-syntax ref) nil t)
    (when (eq 'lazy esml-du-background-parsing)
      (esml-du-parse ctx))
    (beginning-of-line)
    (while (= ?\  (char-after))
      (forward-line -1))
    (esml-du-read-one-symbol ctx)))

(defun esml-du-try-to-read-all-symbols-at-ref (ref ctx)
  (let ((syms nil))
    (goto-char 1)
    (while (let ((sym (esml-du-try-to-read-symbol-at-ref-once ref ctx)))
             (when sym
               (push sym syms))))
    syms))

(defun esml-du-try-to-read-symbol-at-ref (ref ctx)
  "Tries to read the symbol at the specified ref from the duf.  Returns
non-nil if something was actually read."
  (let ((buffer (esml-du-ctx-buf ctx)))
    (when buffer
      (bury-buffer buffer)
      (with-current-buffer buffer
        (let ((syms (esml-du-try-to-read-all-symbols-at-ref ref ctx)))
          (when syms
            (while syms
              (let* ((sym (pop syms))
                     (more-syms
                      (esml-du-try-to-read-all-symbols-at-ref
                       (def-use-sym-ref sym) ctx)))
                (when more-syms
                  (setq syms (nconc more-syms syms)))))
            t))))))

(defun esml-du-ref-to-appx-syntax (ref)
  (let ((pos (def-use-ref-pos ref)))
    (concat
     (file-name-nondirectory (def-use-ref-src ref)) " "
     (int-to-string (def-use-pos-line pos)) "."
     (int-to-string (1+ (def-use-pos-col pos))))))

(defun esml-du-read-one-symbol (ctx)
  "Reads one symbol from the current buffer starting at the current point.
Returns the symbol read and deletes the read symbol from the buffer."
  (let* ((start (point))
         (ref-to-sym (esml-du-ctx-ref-to-sym-table ctx))
         (sym-to-uses (esml-du-ctx-sym-to-uses-table ctx))
         (class (def-use-intern (esml-du-read "^ " " ")))
         (name (def-use-intern (esml-du-read "^ " " ")))
         (src (def-use-file-truename (esml-du-read "^ " " ")))
         (line (string-to-int (esml-du-read "^." ".")))
         (col (1- (string-to-int (esml-du-read "^\n" "\n"))))
         (pos (def-use-pos line col))
         (ref (def-use-ref src pos))
         (sym (def-use-sym class name ref
                (cdr (assoc class esml-du-classes))))
         (uses nil))
    (let ((old-sym (gethash ref ref-to-sym)))
      (when old-sym
        (setq sym old-sym))
      (puthash ref sym ref-to-sym))
    (while (< 0 (skip-chars-forward " "))
      (let* ((src (def-use-file-truename (esml-du-read "^ " " ")))
             (line (string-to-int (esml-du-read "^." ".")))
             (col (1- (string-to-int (esml-du-read "^\n" "\n"))))
             (pos (def-use-pos line col))
             (ref (def-use-ref src pos)))
        (let ((old-sym (gethash ref ref-to-sym)))
          (when old-sym
            (let ((old-uses (gethash old-sym sym-to-uses)))
              (remhash old-sym sym-to-uses)
              (mapc
               (function
                (lambda (ref)
                  (puthash ref sym ref-to-sym)))
               old-uses)
              (setq uses (nconc uses old-uses)))))
        (puthash ref sym ref-to-sym)
        (push ref uses)))
    (puthash sym uses sym-to-uses)
    (setq buffer-read-only nil)
    (delete-backward-char (- (point) start))
    (setq buffer-read-only t)
    sym))

(defun esml-du-load (ctx)
  "Loads the def-use file to a buffer for parsing and performing queries."
  (esml-du-ctx-set-attr (file-attributes (esml-du-ctx-duf ctx)) ctx)
  (if (esml-du-ctx-buf ctx)
      (with-current-buffer (esml-du-ctx-buf ctx)
        (goto-char 1)
        (setq buffer-read-only nil)
        (delete-char (1- (point-max))))
    (esml-du-ctx-set-buf
     (generate-new-buffer (concat "** " (esml-du-ctx-duf ctx) " **")) ctx)
    (with-current-buffer (esml-du-ctx-buf ctx)
      (buffer-disable-undo)
      (compat-add-local-hook
       'kill-buffer-hook
       (lexical-let ((ctx ctx))
         (function
          (lambda ()
            (esml-du-ctx-set-buf nil ctx)))))))
  (bury-buffer (esml-du-ctx-buf ctx))
  (with-current-buffer (esml-du-ctx-buf ctx)
    (insert-file (esml-du-ctx-duf ctx))
    (setq buffer-read-only t)
    (goto-char 1))
  (clrhash (esml-du-ctx-ref-to-sym-table ctx))
  (clrhash (esml-du-ctx-sym-to-uses-table ctx))
  (garbage-collect)
  (when (memq esml-du-notify '(always))
    (message "Loaded %s" (esml-du-ctx-duf ctx)))
  (when (eq 'eager esml-du-background-parsing)
    (esml-du-parse ctx)))

(defun esml-du-parse (ctx)
  "Parses the def-use -file.  Because parsing may take a while, it is
done as a background process.  This allows you to continue working
altough the editor may feel a bit sluggish."
  (unless (esml-du-ctx-parsing? ctx)
    (esml-du-ctx-set-parsing? t ctx)
    (bg-job-start
     (function
      (lambda (ctx)
        (let ((buffer (esml-du-ctx-buf ctx)))
          (or (not buffer)
              (with-current-buffer buffer
                (goto-char 1)
                (eobp))))))
     (function
      (lambda (ctx)
        (with-current-buffer (esml-du-ctx-buf ctx)
          (goto-char 1)
          (esml-du-read-one-symbol ctx))))
     (function
      (lambda (ctx)
        (esml-du-stop-parsing ctx)
        (esml-du-ctx-set-parsing? nil ctx)
        (esml-du-ctx-inc-parse-cnt ctx)
        (when (memq esml-du-notify '(always))
          (message "Finished parsing %s." (esml-du-ctx-duf ctx)))))
     ctx)
    (when (memq esml-du-notify '(always))
      (message "Parsing %s in the background..." (esml-du-ctx-duf ctx)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(run-with-idle-timer
 1.0 nil
 (function
  (lambda ()
    (when esml-du-dufs-auto-load
      (mapc (function
             (lambda (file)
               (when (and (file-readable-p file)
                          (file-regular-p file))
                 (esml-du-mlton file t))))
            esml-du-dufs-recent)))))

(provide 'esml-du-mlton)
