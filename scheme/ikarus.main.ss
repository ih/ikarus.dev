;;; Ikarus Scheme -- A compiler for R6RS Scheme.
;;; Copyright (C) 2006,2007,2008  Abdulaziz Ghuloum
;;; 
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License version 3 as
;;; published by the Free Software Foundation.
;;; 
;;; This program is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; General Public License for more details.
;;; 
;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.



;;; this is here to test that we can import things from other
;;; libraries within the compiler itself.

(library (ikarus startup)
  (export print-greeting init-library-path host-info split-path)
  (import (except (ikarus) host-info) (ikarus include))
  (include "ikarus.config.ss")

  (define (host-info) target)
  
  (define (split-path s)
    (define (nodata i s ls)
      (cond
        [(= i (string-length s)) ls]
        [(char=? (string-ref s i) #\:) (nodata (+ i 1) s ls)]
        [else (data (+ i 1) s ls (list (string-ref s i)))]))
    (define (data i s ls ac)
      (cond
        [(= i (string-length s)) 
         (cons (list->string (reverse ac)) ls)]
        [(char=? (string-ref s i) #\:) 
         (nodata (+ i 1) s
           (cons (list->string (reverse ac)) ls))]
        [else (data (+ i 1) s ls (cons (string-ref s i) ac))]))
    (reverse (nodata 0 s '())))


  (define (print-greeting)
    (printf "Ikarus Scheme version ~a~a~a~a\n" 
      ikarus-version
      (if (zero? (string-length ikarus-revision)) "" "+")
      (if (= (fixnum-width) 30)
          ""
          ", 64-bit")
      (if (zero? (string-length ikarus-revision)) 
          ""
          (format " (revision ~a, build ~a)"
            (+ 1 (string->number ikarus-revision))
            (let-syntax ([ds (lambda (x) (date-string))])
              ds))))
    (display "Copyright (c) 2006-2009 Abdulaziz Ghuloum\n\n"))

  (define (init-library-path) 
    (library-path
      (append
        (cond
          [(getenv "IKARUS_LIBRARY_PATH") => split-path]
          [else '(".")])
        (list ikarus-lib-dir)))
    (let ([prefix
           (lambda (ext ls)
             (append (map (lambda (x) (string-append ext x)) ls) ls))])
      (library-extensions 
        (prefix "/main" 
          (prefix ".ikarus"
            (library-extensions)))))))


;;; Finally, we're ready to evaluate the files and enter the cafe.

(library (ikarus main)
  (export)
  (import (except (ikarus) load-r6rs-script)
          (except (ikarus startup) host-info)
          (only (ikarus.compiler) generate-debug-calls)
          (only (ikarus.debugger) guarded-start)
          (only (psyntax library-manager) current-library-expander)
          (only (ikarus.reader.annotated) read-source-file)
          (only (ikarus.symbol-table) initialize-symbol-table!)
          (only (ikarus load) load-r6rs-script))

  (define rcfiles #t) ;; #f for no rcfile, list for specific list

  (define (parse-command-line-arguments)
    (let f ([args (command-line-arguments)] [k void])
      (define (invalid-rc-error)
        (die 'ikarus "--no-rcfile is invalid with --rcfile"))
      (cond
        [(null? args) (values '() #f #f '() k)]
        [(member (car args) '("-d" "--debug"))
         (f (cdr args) (lambda () (k) (generate-debug-calls #t)))]
        [(member (car args) '("-nd" "--no-debug"))
         (f (cdr args) (lambda () (k) (generate-debug-calls #f)))]
        [(string=? (car args) "-O2")
         (f (cdr args) (lambda () (k) (optimize-level 2)))]
        [(string=? (car args) "-O1")
         (f (cdr args) (lambda () (k) (optimize-level 1)))] 
        [(string=? (car args) "-O0")
         (f (cdr args) (lambda () (k) (optimize-level 0)))]
        [(string=? (car args) "--no-rcfile")
         (unless (boolean? rcfiles) (invalid-rc-error))
         (set! rcfiles #f)
         (f (cdr args) k)]
        [(string=? (car args) "--rcfile")
         (let ([d (cdr args)])
           (when (null? d) (die 'ikarus "--rcfile requires a script name"))
           (set! rcfiles 
             (cons (car d) 
               (case rcfiles
                 [(#t) '()]
                 [(#f) (invalid-rc-error)]
                 [else rcfiles])))
           (f (cdr d) k))]
        [(string=? (car args) "--")
         (values '() #f #f (cdr args) k)]
        [(string=? (car args) "--script")
         (let ([d (cdr args)])
           (cond
             [(null? d) (die 'ikarus "--script requires a script name")]
             [else (values '() (car d) 'script (cdr d) k)]))]
        [(string=? (car args) "--r6rs-script")
         (let ([d (cdr args)])
           (cond
             [(null? d) (die 'ikarus "--r6rs-script requires a script name")]
             [else (values '() (car d) 'r6rs-script (cdr d) k)]))]
        [(string=? (car args) "--r6rs-repl")
         (let ([d (cdr args)])
           (cond
             [(null? d) (die 'ikarus "--r6rs-repl requires a script name")]
             [else (values '() (car d) 'r6rs-repl (cdr d) k)]))]
        [(string=? (car args) "--compile-dependencies")
         (let ([d (cdr args)])
           (cond
             [(null? d)
              (die 'ikarus "--compile-dependencies requires a script name")]
             [else
              (values '() (car d) 'compile (cdr d) k)]))]
        [else
         (let-values ([(f* script script-type a* k) (f (cdr args) k)])
           (values (cons (car args) f*) script script-type a* k))])))

  (initialize-symbol-table!)
  (init-library-path)
  (let-values ([(files script script-type args init-command-line-args)
                (parse-command-line-arguments)])

    (define (assert-null files who)
      (unless (null? files)
        (apply die 'ikarus
          (format "load files not allowed for ~a" who)
          files)))

    (define (start proc)
      (if (generate-debug-calls)
          (guarded-start proc)
          (proc)))

    (define-syntax doit
      (syntax-rules ()
        [(_ e e* ...)
         (start (lambda () e e* ...))]))

    (define (default-rc-files)
      (cond
        [(getenv "IKARUS_RC_FILES") => split-path]
        [(getenv "HOME") =>
         (lambda (home)
           (let ([f (string-append home "/.ikarusrc")])
             (if (file-exists? f) 
                 (list f)
                 '())))]
        [else '()]))

    (for-each
      (lambda (filename)
        (with-exception-handler
          (lambda (con)
            (raise-continuable 
              (condition 
                (make-who-condition 'ikarus)
                (make-message-condition 
                  (format "loading rc file ~a failed" filename))
                con)))
          (lambda ()
            (load-r6rs-script filename #f #t))))
      (case rcfiles
        [(#t) (default-rc-files)]
        [(#f) '()]
        [else (reverse rcfiles)]))

    (init-command-line-args)

    (cond
      [(memq script-type '(r6rs-script r6rs-repl))
       (let ([f (lambda ()
                  (doit
                    (command-line-arguments (cons script args))
                    (for-each
                      (lambda (filename)
                        (for-each
                          (lambda (src)
                            ((current-library-expander) src))
                          (read-source-file filename)))
                      files)
                    (load-r6rs-script script #f #t)))])
         (cond
           [(eq? script-type 'r6rs-script) (f)]
           [else
            (print-greeting)
            (let ([env (f)])
              (interaction-environment env)
              (new-cafe
                (lambda (x)
                  (doit (eval x env)))))]))]
      [(eq? script-type 'compile)
       (assert-null files "--compile-dependencies")
       (doit
         (command-line-arguments (cons script args))
         (load-r6rs-script script #t #f))]
      [(eq? script-type 'script) ; no greeting, no cafe
       (command-line-arguments (cons script args))
       (doit
         (for-each load files)
         (load script))]
      [else
       (print-greeting)
       (command-line-arguments (cons "*interactive*" args))
       (doit (for-each load files))
       (new-cafe
         (lambda (x)
           (doit (eval x (interaction-environment)))))])

    (exit 0)))
