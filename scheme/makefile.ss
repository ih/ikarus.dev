#!../src/ikarus -b ikarus.boot --r6rs-script
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

;;; vim:syntax=scheme
(import (only (ikarus) import))
(import (except (ikarus) 
          current-letrec-pass
          current-core-eval
          assembler-output optimize-cp optimize-level
          cp0-size-limit cp0-effort-limit expand/optimize
          expand/scc-letrec expand
          optimizer-output tag-analysis-output perform-tag-analysis))
(import (ikarus.compiler))
(import (except (psyntax system $bootstrap)
                eval-core 
                current-primitive-locations
                compile-core-expr-to-port))
(import (ikarus.compiler)) ; just for fun
(optimize-level 2)
(perform-tag-analysis #t)
(pretty-width 160)
((pretty-format 'fix) ((pretty-format 'letrec)))
(strip-source-info #t)

(current-letrec-pass 'scc)
(define scheme-library-files
  ;;; Listed in the order in which they're loaded.
  ;;;
  ;;; Loading of the boot file may segfault if a library is
  ;;; loaded before its dependencies are loaded first.
  ;;;
  ;;; reason is that the base libraries are not a hierarchy of
  ;;; dependencies but rather an eco system in which every
  ;;; part depends on the other.
  ;;;
  ;;; For example, the printer may call error if it finds
  ;;;  an error (e.g. "not an output port"), while the error
  ;;;  procedure may call the printer to display the message.
  ;;;  This works fine as long as error does not itself cause
  ;;;  an error (which may lead to the infamous Error: Error: 
  ;;;  Error: Error: Error: Error: Error: Error: Error: ...).
  ;;;
  '(
    
    "ikarus.singular-objects.ss"
    "ikarus.handlers.ss"
    "ikarus.multiple-values.ss"
    "ikarus.control.ss"
    "ikarus.exceptions.ss"
    "ikarus.collect.ss"
    "ikarus.apply.ss"
    "ikarus.predicates.ss"
    "ikarus.equal.ss"
    "ikarus.pairs.ss"
    "ikarus.lists.ss"
    "ikarus.fixnums.ss"
    "ikarus.chars.ss"
    "ikarus.structs.ss"
    "ikarus.records.procedural.ss"
    "ikarus.strings.ss"
    "ikarus.unicode-conversion.ss"
    "ikarus.date-string.ss"
    "ikarus.symbols.ss"
    "ikarus.vectors.ss"
    "ikarus.unicode.ss"
    "ikarus.string-to-number.ss"
    "ikarus.numerics.ss"
    "ikarus.conditions.ss"
    "ikarus.guardians.ss"
    "ikarus.symbol-table.ss"
    "ikarus.codecs.ss"
    "ikarus.bytevectors.ss"
    "ikarus.posix.ss"
    "ikarus.io.ss"
    "ikarus.hash-tables.ss"
    "ikarus.pretty-formats.ss"
    "ikarus.writer.ss"
    "ikarus.reader.ss"
    "ikarus.reader.annotated.ss"
    "ikarus.code-objects.ss"
    "ikarus.intel-assembler.ss"
    "ikarus.fasl.write.ss"
    "ikarus.fasl.ss"
    "ikarus.compiler.ss"
    "psyntax.compat.ss"
    "psyntax.library-manager.ss"
    "psyntax.internal.ss"
    "psyntax.config.ss"
    "psyntax.builders.ss"
    "psyntax.expander.ss"
    "ikarus.apropos.ss"
    "ikarus.load.ss"
    "ikarus.pretty-print.ss"
    "ikarus.cafe.ss"
    "ikarus.timer.ss"
    "ikarus.time-and-date.ss"
    "ikarus.sort.ss"
    "ikarus.promises.ss"
    "ikarus.enumerations.ss"
    "ikarus.command-line.ss"
    "ikarus.pointers.ss"
    "ikarus.not-yet-implemented.ss"
    ;"ikarus.trace.ss"
    "ikarus.debugger.ss"
    "ikarus.main.ss"
    ))

(define ikarus-system-macros
  '([define              (define)]
    [define-syntax       (define-syntax)]
    [define-fluid-syntax (define-fluid-syntax)]
    [module              (module)]
    [library             (library)]
    [begin               (begin)]
    [import              (import)]
    [export              (export)]
    [set!                (set!)]
    [let-syntax          (let-syntax)]
    [letrec-syntax       (letrec-syntax)]
    [stale-when          (stale-when)]
    [foreign-call        (core-macro . foreign-call)]
    [quote               (core-macro . quote)]
    [syntax-case         (core-macro . syntax-case)]
    [syntax              (core-macro . syntax)]
    [lambda              (core-macro . lambda)]
    [case-lambda         (core-macro . case-lambda)]
    [type-descriptor     (core-macro . type-descriptor)]
    [letrec              (core-macro . letrec)]
    [letrec*             (core-macro . letrec*)]
    [if                  (core-macro . if)]
    [fluid-let-syntax    (core-macro . fluid-let-syntax)]
    [record-type-descriptor (core-macro . record-type-descriptor)]
    [record-constructor-descriptor (core-macro . record-constructor-descriptor)]
    [let-values          (macro . let-values)]
    [let*-values         (macro . let*-values)]
    [define-struct       (macro . define-struct)]
    [case                (macro . case)]
    [syntax-rules        (macro . syntax-rules)]
    [quasiquote          (macro . quasiquote)]
    [quasisyntax         (macro . quasisyntax)]
    [with-syntax         (macro . with-syntax)]
    [identifier-syntax   (macro . identifier-syntax)]
    [parameterize        (macro . parameterize)]
    [when                (macro . when)]         
    [unless              (macro . unless)]
    [let                 (macro . let)]
    [let*                (macro . let*)]
    [cond                (macro . cond)]
    [do                  (macro . do)]
    [and                 (macro . and)]
    [or                  (macro . or)]
    [time                (macro . time)]
    [delay               (macro . delay)]
    [endianness          (macro . endianness)]
    [assert              (macro . assert)]
    [...                 (macro . ...)]
    [=>                  (macro . =>)]
    [else                (macro . else)]
    [_                   (macro . _)]
    [unquote             (macro . unquote)]
    [unquote-splicing    (macro . unquote-splicing)]
    [unsyntax            (macro . unsyntax)]
    [unsyntax-splicing   (macro . unsyntax-splicing)]
    [trace-lambda        (macro . trace-lambda)]
    [trace-let           (macro . trace-let)]
    [trace-define        (macro . trace-define)]
    [trace-define-syntax (macro . trace-define-syntax)]
    [trace-let-syntax    (macro . trace-let-syntax)]
    [trace-letrec-syntax (macro . trace-letrec-syntax)]
    [guard               (macro . guard)]
    [eol-style           (macro . eol-style)]
    [buffer-mode         (macro . buffer-mode)]
    [file-options        (macro . file-options)]
    [error-handling-mode (macro . error-handling-mode)]
    [fields              (macro . fields)] 
    [mutable             (macro . mutable)]
    [immutable           (macro . immutable)] 
    [parent              (macro . parent)]
    [protocol            (macro . protocol)]
    [sealed              (macro . sealed)]
    [opaque              (macro . opaque )]
    [nongenerative       (macro . nongenerative)]
    [parent-rtd          (macro . parent-rtd)]
    [define-record-type  (macro . define-record-type)]
    [define-enumeration  (macro . define-enumeration)]
    [define-condition-type  (macro . define-condition-type)]
    [&condition                ($core-rtd . (&condition-rtd &condition-rcd))]
    [&message                  ($core-rtd . (&message-rtd &message-rcd))]
    [&warning                  ($core-rtd . (&warning-rtd &warning-rcd ))]
    [&serious                  ($core-rtd . (&serious-rtd &serious-rcd))]
    [&error                    ($core-rtd . (&error-rtd &error-rcd))]
    [&violation                ($core-rtd . (&violation-rtd &violation-rcd ))]
    [&assertion                ($core-rtd . (&assertion-rtd &assertion-rcd ))]
    [&irritants                ($core-rtd . (&irritants-rtd &irritants-rcd))]
    [&who                      ($core-rtd . (&who-rtd &who-rcd ))]
    [&non-continuable          ($core-rtd . (&non-continuable-rtd &non-continuable-rcd))]
    [&implementation-restriction  ($core-rtd . (&implementation-restriction-rtd &implementation-restriction-rcd))]
    [&lexical                  ($core-rtd . (&lexical-rtd &lexical-rcd ))]
    [&syntax                   ($core-rtd . (&syntax-rtd &syntax-rcd ))]
    [&undefined                ($core-rtd . (&undefined-rtd &undefined-rcd))]
    [&i/o                      ($core-rtd . (&i/o-rtd &i/o-rcd ))]
    [&i/o-read                 ($core-rtd . (&i/o-read-rtd &i/o-read-rcd ))]
    [&i/o-write                ($core-rtd . (&i/o-write-rtd &i/o-write-rcd))]
    [&i/o-invalid-position     ($core-rtd . (&i/o-invalid-position-rtd &i/o-invalid-position-rcd ))]
    [&i/o-filename             ($core-rtd . (&i/o-filename-rtd &i/o-filename-rcd))]
    [&i/o-file-protection      ($core-rtd . (&i/o-file-protection-rtd &i/o-file-protection-rcd))]
    [&i/o-file-is-read-only    ($core-rtd .  (&i/o-file-is-read-only-rtd &i/o-file-is-read-only-rcd ))]
    [&i/o-file-already-exists  ($core-rtd . (&i/o-file-already-exists-rtd &i/o-file-already-exists-rcd))]
    [&i/o-file-does-not-exist  ($core-rtd . (&i/o-file-does-not-exist-rtd &i/o-file-does-not-exist-rcd))]
    [&i/o-port                 ($core-rtd . (&i/o-port-rtd &i/o-port-rcd))]
    [&i/o-decoding             ($core-rtd . (&i/o-decoding-rtd &i/o-decoding-rcd))]
    [&i/o-encoding             ($core-rtd . (&i/o-encoding-rtd &i/o-encoding-rcd))]
    [&no-infinities            ($core-rtd . (&no-infinities-rtd &no-infinities-rcd ))]
    [&no-nans                  ($core-rtd . (&no-nans-rtd &no-nans-rcd))]
    [&interrupted              ($core-rtd . (&interrupted-rtd &interrupted-rcd))]
    [&source                   ($core-rtd . (&source-rtd &source-rcd))]
    ))

(define library-legend
  ;; abbr.       name                             visible? required?
  '([i           (ikarus)                              #t     #t]
    [cm          (chez modules)                        #t     #t]
    [symbols     (ikarus symbols)                      #t     #t]
    [parameters  (ikarus parameters)                   #t     #t]
    [r           (rnrs)                                #t     #t]
    [r5          (rnrs r5rs)                           #t     #t]
    [ct          (rnrs control)                        #t     #t]
    [ev          (rnrs eval)                           #t     #t]
    [mp          (rnrs mutable-pairs)                  #t     #t]
    [ms          (rnrs mutable-strings)                #t     #t]
    [pr          (rnrs programs)                       #t     #t]
    [sc          (rnrs syntax-case)                    #t     #t]
    [fi          (rnrs files)                          #t     #t]
    [sr          (rnrs sorting)                        #t     #t]
    [ba          (rnrs base)                           #t     #t]
    [ls          (rnrs lists)                          #t     #t]
    [is          (rnrs io simple)                      #t     #t]
    [bv          (rnrs bytevectors)                    #t     #t]
    [uc          (rnrs unicode)                        #t     #t]
    [ex          (rnrs exceptions)                     #t     #t]
    [bw          (rnrs arithmetic bitwise)             #t     #t]
    [fx          (rnrs arithmetic fixnums)             #t     #t]
    [fl          (rnrs arithmetic flonums)             #t     #t]
    [ht          (rnrs hashtables)                     #t     #t]
    [ip          (rnrs io ports)                       #t     #t]
    [en          (rnrs enums)                          #t     #t]
    [co          (rnrs conditions)                     #t     #t]
    [ri          (rnrs records inspection)             #t     #t]
    [rp          (rnrs records procedural)             #t     #t]
    [rs          (rnrs records syntactic)              #t     #t]
    [$pairs      (ikarus system $pairs)                #f     #t]
    [$lists      (ikarus system $lists)                #f     #t]
    [$chars      (ikarus system $chars)                #f     #t]
    [$strings    (ikarus system $strings)              #f     #t]
    [$vectors    (ikarus system $vectors)              #f     #t]
    [$flonums    (ikarus system $flonums)              #f     #t]
    [$bignums    (ikarus system $bignums)              #f     #t]
    [$bytes      (ikarus system $bytevectors)          #f     #t]
    [$transc     (ikarus system $transcoders)          #f     #t]
    [$fx         (ikarus system $fx)                   #f     #t]
    [$rat        (ikarus system $ratnums)              #f     #t]
    [$comp       (ikarus system $compnums)             #f     #t]
    [$symbols    (ikarus system $symbols)              #f     #t]
    [$structs    (ikarus system $structs)              #f     #t]
    ;[$ports      (ikarus system $ports)                #f     #t]
    [$codes      (ikarus system $codes)                #f     #t]
    [$tcbuckets  (ikarus system $tcbuckets)            #f     #t]
    [$arg-list   (ikarus system $arg-list)             #f     #t]
    [$stack      (ikarus system $stack)                #f     #t]
    [$interrupts (ikarus system $interrupts)           #f     #t]
    [$io         (ikarus system $io)                   #f     #t]
    [$for        (ikarus system $foreign)              #f     #t]
    [$all        (psyntax system $all)                 #f     #t]
    [$boot       (psyntax system $bootstrap)           #f     #t]
    [ne          (psyntax null-environment-5)          #f     #f]
    [se          (psyntax scheme-report-environment-5) #f     #f]
    ))

(define identifier->library-map
  '(
    [import                                      i]
    [export                                      i]
    [foreign-call                                i]
    [type-descriptor                             i]
    [parameterize                                i parameters]
    [define-struct                               i]
    [stale-when                                  i]
    [time                                        i]
    [trace-lambda                                i]
    [trace-let                                   i]
    [trace-define                                i]
    [trace-define-syntax                         i]
    [trace-let-syntax                            i]
    [trace-letrec-syntax                         i]
    [make-list                                   i]
    [last-pair                                   i]
    [bwp-object?                                 i]
    [weak-cons                                   i]
    [weak-pair?                                  i]
    [uuid                                        i]
    [date-string                                 i]
    [andmap                                      i]
    [ormap                                       i]
    [fx<                                         i]
    [fx<=                                        i]
    [fx>                                         i]
    [fx>=                                        i]
    [fx=                                         i]
    [fxadd1                                      i]
    [fxsub1                                      i]
    [fxquotient                                  i]
    [fxremainder                                 i]
    [fxmodulo                                    i]
    [fxsll                                       i]
    [fxsra                                       i]
    [sra                                         i]
    [sll                                         i]
    [fxlogand                                    i]
    [fxlogxor                                    i]
    [fxlogor                                     i]
    [fxlognot                                    i]
    [fixnum->string                              i]
    [string->flonum                              i]
    [add1                                        i]
    [sub1                                        i]
    [bignum?                                     i]
    [ratnum?                                     i]
    [compnum?                                    i]
    [cflonum?                                    i]
    [flonum-parts                                i]
    [flonum-bytes                                i]
    [quotient+remainder                          i]
    [flonum->string                              i]
    [random                                      i]
    [gensym?                                     i symbols]
    [getprop                                     i symbols]
    [putprop                                     i symbols]
    [remprop                                     i symbols]
    [property-list                               i symbols]
    [gensym->unique-string                       i symbols]
    [symbol-bound?                               i symbols]
    [top-level-value                             i symbols]
    [reset-symbol-proc!                          i symbols]
    [make-guardian                               i]
    [port-mode                                   i]
    [set-port-mode!                              i]
    [with-input-from-string                      i]
    [open-output-string                          i]
    [open-output-bytevector                      i]
    [get-output-string                           i]
    [get-output-bytevector                       i]
    [with-output-to-string                       i]
;    [with-output-to-bytevector                   i]
    [console-input-port                          i]
    [console-error-port                          i]
    [console-output-port                         i]
    [reset-input-port!                           i]
    [reset-output-port!                          i]
    [read-token                                  i]
    [printf                                      i]
    [fprintf                                     i]
    [format                                      i]
    [comment-handler                             i]
    [print-gensym                                i symbols]
    [print-graph                                 i]
    [print-unicode                               i]
    [unicode-printable-char?                     i]
    [gensym-count                                i symbols]
    [gensym-prefix                               i symbols]
    [make-parameter                              i parameters]
    [call/cf                                     i]
    [print-error                                 i]
    [strerror                                    i]
    [interrupt-handler                           i]
    [engine-handler                              i]
    [assembler-output                            i]
    [optimizer-output                            i]
    [new-cafe                                    i]
    [waiter-prompt-string                        i]
    [expand                                      i]
    [core-expand                                 i]
    [expand/optimize                             i]
    [expand/scc-letrec                           i]
    [environment?                                i]
    [environment-symbols                         i]
    [time-it                                     i]
    [verbose-timer                               i]
    [current-time                                i]
    [time?                                       i]
    [time-second                                 i]
    [time-gmt-offset                             i]
    [time-nanosecond                             i]
    [command-line-arguments                      i]
    [set-rtd-printer!                            i]
    [struct?                                     i]
    [make-struct-type                            i]
    [struct-type-name                            i]
    [struct-type-symbol                          i]
    [struct-type-field-names                     i]
    [struct-field-accessor                       i]
    [struct-length                               i]
    [struct-ref                                  i]
    [struct-set!                                 i]
    [struct-printer                              i]
    [struct-name                                 i]
    [struct-type-descriptor                      i]
    [code?                                       i]
    [immediate?                                  i]
    [pointer-value                               i]
    [system                                      i]
    [process                                     i]
    [process*                                    i]
    [process-nonblocking                         i]
    [waitpid                                     i]
    [wstatus-pid                                 i]
    [wstatus-exit-status                         i]
    [wstatus-received-signal                     i]
    [kill                                        i]
    [apropos                                     i]
    [installed-libraries                         i]
    [uninstall-library                           i]
    [library-path                                i]
    [library-extensions                          i]
    [current-primitive-locations                 $boot]
    [boot-library-expand                         $boot]
    [current-library-collection                  $boot]
    [library-name                                $boot]
    [find-library-by-name                        $boot]
    [$car                                        $pairs]
    [$cdr                                        $pairs]
    [$set-car!                                   $pairs]
    [$set-cdr!                                   $pairs]
    [$memq                                       $lists]
    [$memv                                       $lists]
    [$char?                                      $chars]
    [$char=                                      $chars]
    [$char<                                      $chars]
    [$char>                                      $chars]
    [$char<=                                     $chars]
    [$char>=                                     $chars]
    [$char->fixnum                               $chars]
    [$fixnum->char                               $chars]
    [$make-string                                $strings]
    [$string-ref                                 $strings]
    [$string-set!                                $strings]
    [$string-length                              $strings]
    [$make-bytevector                            $bytes]
    [$bytevector-length                          $bytes]
    [$bytevector-s8-ref                          $bytes]
    [$bytevector-u8-ref                          $bytes]
    [$bytevector-set!                            $bytes]
    [$bytevector-ieee-double-native-ref          $bytes]
    [$bytevector-ieee-double-native-set!         $bytes]
    [$bytevector-ieee-double-nonnative-ref       $bytes]
    [$bytevector-ieee-double-nonnative-set!      $bytes]
    [$bytevector-ieee-single-native-ref          $bytes]
    [$bytevector-ieee-single-native-set!         $bytes]
    [$bytevector-ieee-single-nonnative-ref       $bytes]
    [$bytevector-ieee-single-nonnative-set!      $bytes]
    [$flonum-u8-ref                              $flonums]
    [$make-flonum                                $flonums]
    [$flonum-set!                                $flonums]
    [$flonum-signed-biased-exponent              $flonums]
    [$flonum-rational?                           $flonums]
    [$flonum-integer?                            $flonums]
    [$fl+                                        $flonums]
    [$fl-                                        $flonums]
    [$fl*                                        $flonums]
    [$fl/                                        $flonums]
    [$fl=                                        $flonums]
    [$fl<                                        $flonums]
    [$fl<=                                       $flonums]
    [$fl>                                        $flonums]
    [$fl>=                                       $flonums]
    ;[$flround                                    $flonums]
    [$fixnum->flonum                             $flonums]
    [$flonum-sbe                                 $flonums]
    [$make-bignum                                $bignums]
    [$bignum-positive?                           $bignums]
    [$bignum-size                                $bignums]
    [$bignum-byte-ref                            $bignums]
    [$bignum-byte-set!                           $bignums]
    [$make-ratnum                                $rat]
    [$ratnum-n                                   $rat]
    [$ratnum-d                                   $rat]
    [$make-compnum                               $comp]
    [$compnum-real                               $comp]
    [$compnum-imag                               $comp]
    [$make-cflonum                               $comp]
    [$cflonum-real                               $comp]
    [$cflonum-imag                               $comp]
    [$make-vector                                $vectors]
    [$vector-length                              $vectors]
    [$vector-ref                                 $vectors]
    [$vector-set!                                $vectors]
    [$fxzero?                                    $fx]
    [$fxadd1                                     $fx]
    [$fxsub1                                     $fx]
    [$fx>=                                       $fx]
    [$fx<=                                       $fx]
    [$fx>                                        $fx]
    [$fx<                                        $fx]
    [$fx=                                        $fx]
    [$fxsll                                      $fx]
    [$fxsra                                      $fx]
    [$fxquotient                                 $fx]
    [$fxmodulo                                   $fx]
    [$int-quotient                               $fx]
    [$int-remainder                              $fx]
    [$fxlogxor                                   $fx]
    [$fxlogor                                    $fx]
    [$fxlognot                                   $fx]
    [$fxlogand                                   $fx]
    [$fx+                                        $fx]
    [$fx*                                        $fx]
    [$fx-                                        $fx]
    [$fxinthash                                  $fx]
    [$make-symbol                                $symbols]
    [$symbol-unique-string                       $symbols]
    [$symbol-value                               $symbols]
    [$symbol-string                              $symbols]
    [$symbol-plist                               $symbols]
    [$set-symbol-value!                          $symbols]
    [$set-symbol-proc!                           $symbols]
    [$set-symbol-string!                         $symbols]
    [$set-symbol-unique-string!                  $symbols]
    [$set-symbol-plist!                          $symbols]
    [$unintern-gensym                            $symbols]
    [$symbol-table-size                          $symbols]
    [$init-symbol-value!                         ]
    [$unbound-object?                            $symbols]
    ;;;
    [base-rtd                                    $structs]
    [$struct-set!                                $structs]
    [$struct-ref                                 $structs]
    [$struct-rtd                                 $structs]
    [$struct                                     $structs]
    [$make-struct                                $structs]
    [$struct?                                    $structs]
    [$struct/rtd?                                $structs]
    ;;;
    [$closure-code                               $codes]
    [$code->closure                              $codes]
    [$code-reloc-vector                          $codes]
    [$code-freevars                              $codes]
    [$code-size                                  $codes]
    [$code-annotation                            $codes]
    [$code-ref                                   $codes]
    [$code-set!                                  $codes]
    [$set-code-annotation!                       $codes]
    [procedure-annotation                        i]
    [$make-annotated-procedure                   $codes]
    [$annotated-procedure-annotation             $codes]
    [$make-tcbucket                              $tcbuckets]
    [$tcbucket-key                               $tcbuckets]
    [$tcbucket-val                               $tcbuckets]
    [$tcbucket-next                              $tcbuckets]
    [$set-tcbucket-val!                          $tcbuckets]
    [$set-tcbucket-next!                         $tcbuckets]
    [$set-tcbucket-tconc!                        $tcbuckets]
    [$arg-list                                   $arg-list]
    [$collect-key                                $arg-list]
    [$$apply                                     $stack]
    [$fp-at-base                                 $stack]
    [$primitive-call/cc                          $stack]
    [$frame->continuation                        $stack]
    [$current-frame                              $stack]
    [$seal-frame-and-call                        $stack]
    [$make-call-with-values-procedure            $stack]
    [$make-values-procedure                      $stack]
    [$interrupted?                               $interrupts]
    [$unset-interrupted!                         $interrupts]
    [$swap-engine-counter!                       $interrupts]
    [interrupted-condition?                      i]
    [make-interrupted-condition                  i]

    [source-position-condition?                  i]
    [make-source-position-condition              i]
    [source-position-file-name                   i]
    [source-position-character                   i]

    [$apply-nonprocedure-error-handler           ]
    [$incorrect-args-error-handler               ]
    [$multiple-values-error                      ]
    [$debug                                      ]
    [$underflow-misaligned-error                 ]
    [top-level-value-error                       ]
    [car-error                                   ]
    [cdr-error                                   ]
    [fxadd1-error                                ]
    [fxsub1-error                                ]
    [cadr-error                                  ]
    [fx+-type-error                              ]
    [fx+-types-error                             ]
    [fx+-overflow-error                          ]
    [$do-event                                   ]
    [do-overflow                                 ]
    [do-overflow-words                           ]
    [do-vararg-overflow                          ]
    [collect                                     i]
    [collect-key                                 i]
    [post-gc-hooks                               i]
    [do-stack-overflow                           ]
    [make-promise                                ]
    [make-traced-procedure                       i]
    [make-traced-macro                           i]
    [error@fx+                                   ]
    [error@fxarithmetic-shift-left               ]
    [error@fxarithmetic-shift-right              ]
    [error@fx*                                   ]
    [error@fx-                                   ]
    [error@add1                                  ]
    [error@sub1                                  ]
    [error@fxadd1                                ]
    [error@fxsub1                                ]
    [fasl-write                                  i]
    [fasl-read                                   i]
    [fasl-directory                              i]
    [lambda                                      i r ba se ne]
    [and                                         i r ba se ne]
    [begin                                       i r ba se ne]
    [case                                        i r ba se ne]
    [cond                                        i r ba se ne]
    [define                                      i r ba se ne]
    [define-syntax                               i r ba se ne]
    [define-fluid-syntax                         i]
    [identifier-syntax                           i r ba]
    [if                                          i r ba se ne]
    [let                                         i r ba se ne]
    [let*                                        i r ba se ne]
    [let*-values                                 i r ba]
    [let-syntax                                  i r ba se ne]
    [let-values                                  i r ba]
    [fluid-let-syntax                            i]
    [letrec                                      i r ba se ne]
    [letrec*                                     i r ba]
    [letrec-syntax                               i r ba se ne]
    [or                                          i r ba se ne]
    [quasiquote                                  i r ba se ne]
    [quote                                       i r ba se ne]
    [set!                                        i r ba se ne]
    [syntax-rules                                i r ba se ne]
    [unquote                                     i r ba se ne]
    [unquote-splicing                            i r ba se ne]
    [<                                           i r ba se]
    [<=                                          i r ba se]
    [=                                           i r ba se]
    [>                                           i r ba se]
    [>=                                          i r ba se]
    [+                                           i r ba se]
    [-                                           i r ba se]
    [*                                           i r ba se]
    [/                                           i r ba se]
    [abs                                         i r ba se]
    [asin                                        i r ba se]
    [acos                                        i r ba se]
    [atan                                        i r ba se]
    [sinh                                        i]
    [cosh                                        i]
    [tanh                                        i]
    [asinh                                       i]
    [acosh                                       i]
    [atanh                                       i]
    [angle                                       i r ba se]
    [append                                      i r ba se]
    [apply                                       i r ba se]
    [assert                                      i r ba]
    [assertion-error                             ]
    [assertion-violation                         i r ba]
    [boolean=?                                   i r ba]
    [boolean?                                    i r ba se]
    [car                                         i r ba se]
    [cdr                                         i r ba se]
    [caar                                        i r ba se]
    [cadr                                        i r ba se]
    [cdar                                        i r ba se]
    [cddr                                        i r ba se]
    [caaar                                       i r ba se]
    [caadr                                       i r ba se]
    [cadar                                       i r ba se]
    [caddr                                       i r ba se]
    [cdaar                                       i r ba se]
    [cdadr                                       i r ba se]
    [cddar                                       i r ba se]
    [cdddr                                       i r ba se]
    [caaaar                                      i r ba se]
    [caaadr                                      i r ba se]
    [caadar                                      i r ba se]
    [caaddr                                      i r ba se]
    [cadaar                                      i r ba se]
    [cadadr                                      i r ba se]
    [caddar                                      i r ba se]
    [cadddr                                      i r ba se]
    [cdaaar                                      i r ba se]
    [cdaadr                                      i r ba se]
    [cdadar                                      i r ba se]
    [cdaddr                                      i r ba se]
    [cddaar                                      i r ba se]
    [cddadr                                      i r ba se]
    [cdddar                                      i r ba se]
    [cddddr                                      i r ba se]
    [call-with-current-continuation              i r ba se]
    [call/cc                                     i r ba]
    [call-with-values                            i r ba se]
    [ceiling                                     i r ba se]
    [char->integer                               i r ba se]
    [char<=?                                     i r ba se]
    [char<?                                      i r ba se]
    [char=?                                      i r ba se]
    [char>=?                                     i r ba se]
    [char>?                                      i r ba se]
    [char?                                       i r ba se]
    [complex?                                    i r ba se]
    [cons                                        i r ba se]
    [cos                                         i r ba se]
    [denominator                                 i r ba se]
    [div                                         i r ba]
    [mod                                         i r ba]
    [div-and-mod                                 i r ba]
    [div0                                        i r ba]
    [mod0                                        i r ba]
    [div0-and-mod0                               i r ba]
    [dynamic-wind                                i r ba se]
    [eq?                                         i r ba se]
    [equal?                                      i r ba se]
    [eqv?                                        i r ba se]
    [error                                       i r ba]
    [warning                                     i]
    [die                                         i]
    [even?                                       i r ba se]
    [exact                                       i r ba]
    [exact-integer-sqrt                          i r ba]
    [exact?                                      i r ba se]
    [exp                                         i r ba se]
    [expt                                        i r ba se]
    [finite?                                     i r ba]
    [floor                                       i r ba se]
    [for-each                                    i r ba se]
    [gcd                                         i r ba se]
    [imag-part                                   i r ba se]
    [inexact                                     i r ba]
    [inexact?                                    i r ba se]
    [infinite?                                   i r ba]
    [integer->char                               i r ba se]
    [integer-valued?                             i r ba]
    [integer?                                    i r ba se]
    [lcm                                         i r ba se]
    [length                                      i r ba se]
    [list                                        i r ba se]
    [list->string                                i r ba se]
    [list->vector                                i r ba se]
    [list-ref                                    i r ba se]
    [list-tail                                   i r ba se]
    [list?                                       i r ba se]
    [log                                         i r ba se]
    [magnitude                                   i r ba se]
    [make-polar                                  i r ba se]
    [make-rectangular                            i r ba se]
    [$make-rectangular                           $comp]
    [make-string                                 i r ba se]
    [make-vector                                 i r ba se]
    [map                                         i r ba se]
    [max                                         i r ba se]
    [min                                         i r ba se]
    [nan?                                        i r ba]
    [negative?                                   i r ba se]
    [not                                         i r ba se]
    [null?                                       i r ba se]
    [number->string                              i r ba se]
    [number?                                     i r ba se]
    [numerator                                   i r ba se]
    [odd?                                        i r ba se]
    [pair?                                       i r ba se]
    [positive?                                   i r ba se]
    [procedure?                                  i r ba se]
    [rational-valued?                            i r ba]
    [rational?                                   i r ba se]
    [rationalize                                 i r ba se]
    [real-part                                   i r ba se]
    [real-valued?                                i r ba]
    [real?                                       i r ba se]
    [reverse                                     i r ba se]
    [round                                       i r ba se]
    [sin                                         i r ba se]
    [sqrt                                        i r ba se]
    [string                                      i r ba se]
    [string->list                                i r ba se]
    [string->number                              i r ba se]
    [string->symbol                              i symbols r ba se]
    [string-append                               i r ba se]
    [string-copy                                 i r ba se]
    [string-for-each                             i r ba]
    [string-length                               i r ba se]
    [string-ref                                  i r ba se]
    [string<=?                                   i r ba se]
    [string<?                                    i r ba se]
    [string=?                                    i r ba se]
    [string>=?                                   i r ba se]
    [string>?                                    i r ba se]
    [string?                                     i r ba se]
    [substring                                   i r ba se]
    [symbol->string                              i symbols r ba se]
    [symbol=?                                    i symbols r ba]
    [symbol?                                     i symbols r ba se]
    [tan                                         i r ba se]
    [truncate                                    i r ba se]
    [values                                      i r ba se]
    [vector                                      i r ba se]
    [vector->list                                i r ba se]
    [vector-fill!                                i r ba se]
    [vector-for-each                             i r ba]
    [vector-length                               i r ba se]
    [vector-map                                  i r ba]
    [vector-ref                                  i r ba se]
    [vector-set!                                 i r ba se]
    [vector?                                     i r ba se]
    [zero?                                       i r ba se]
    [...                                         i ne r ba sc se]
    [=>                                          i ne r ba ex se]
    [_                                           i ne r ba sc]
    [else                                        i ne r ba ex se]
    [bitwise-arithmetic-shift                    i r bw]
    [bitwise-arithmetic-shift-left               i r bw]
    [bitwise-arithmetic-shift-right              i r bw]
    [bitwise-not                                 i r bw]
    [bitwise-and                                 i r bw]
    [bitwise-ior                                 i r bw]
    [bitwise-xor                                 i r bw]
    [bitwise-bit-count                           i r bw]
    [bitwise-bit-field                           i r bw]
    [bitwise-bit-set?                            i r bw]
    [bitwise-copy-bit                            i r bw]
    [bitwise-copy-bit-field                      i r bw]
    [bitwise-first-bit-set                       i r bw]
    [bitwise-if                                  i r bw]
    [bitwise-length                              i r bw]
    [bitwise-reverse-bit-field                   i r bw]
    [bitwise-rotate-bit-field                    i r bw]
    [fixnum?                                     i r fx]
    [fixnum-width                                i r fx]
    [least-fixnum                                i r fx]
    [greatest-fixnum                             i r fx]
    [fx*                                         i r fx]
    [fx*/carry                                   i r fx]
    [fx+                                         i r fx]
    [fx+/carry                                   i r fx]
    [fx-                                         i r fx]
    [fx-/carry                                   i r fx]
    [fx<=?                                       i r fx]
    [fx<?                                        i r fx]
    [fx=?                                        i r fx]
    [fx>=?                                       i r fx]
    [fx>?                                        i r fx]
    [fxand                                       i r fx]
    [fxarithmetic-shift                          i r fx]
    [fxarithmetic-shift-left                     i r fx]
    [fxarithmetic-shift-right                    i r fx]
    [fxbit-count                                 i r fx]
    [fxbit-field                                 i r fx]
    [fxbit-set?                                  i r fx]
    [fxcopy-bit                                  i r fx]
    [fxcopy-bit-field                            i r fx]
    [fxdiv                                       i r fx]
    [fxdiv-and-mod                               i r fx]
    [fxdiv0                                      i r fx]
    [fxdiv0-and-mod0                             i r fx]
    [fxeven?                                     i r fx]
    [fxfirst-bit-set                             i r fx]
    [fxif                                        i r fx]
    [fxior                                       i r fx]
    [fxlength                                    i r fx]
    [fxmax                                       i r fx]
    [fxmin                                       i r fx]
    [fxmod                                       i r fx]
    [fxmod0                                      i r fx]
    [fxnegative?                                 i r fx]
    [fxnot                                       i r fx]
    [fxodd?                                      i r fx]
    [fxpositive?                                 i r fx]
    [fxreverse-bit-field                         i r fx]
    [fxrotate-bit-field                          i r fx]
    [fxxor                                       i r fx]
    [fxzero?                                     i r fx]
    [fixnum->flonum                              i r fl]
    [fl*                                         i r fl]
    [fl+                                         i r fl]
    [fl-                                         i r fl]
    [fl/                                         i r fl]
    [fl<=?                                       i r fl]
    [fl<?                                        i r fl]
    [fl=?                                        i r fl]
    [fl>=?                                       i r fl]
    [fl>?                                        i r fl]
    [flabs                                       i r fl]
    [flacos                                      i r fl]
    [flasin                                      i r fl]
    [flatan                                      i r fl]
    [flceiling                                   i r fl]
    [flcos                                       i r fl]
    [fldenominator                               i r fl]
    [fldiv                                       i r fl]
    [fldiv-and-mod                               i r fl]
    [fldiv0                                      i r fl]
    [fldiv0-and-mod0                             i r fl]
    [fleven?                                     i r fl]
    [flexp                                       i r fl]
    [flexpt                                      i r fl]
    [flfinite?                                   i r fl]
    [flfloor                                     i r fl]
    [flinfinite?                                 i r fl]
    [flinteger?                                  i r fl]
    [fllog                                       i r fl]
    [flmax                                       i r fl]
    [flmin                                       i r fl]
    [flmod                                       i r fl]
    [flmod0                                      i r fl]
    [flnan?                                      i r fl]
    [flnegative?                                 i r fl]
    [flnumerator                                 i r fl]
    [flodd?                                      i r fl]
    [flonum?                                     i r fl]
    [flpositive?                                 i r fl]
    [flround                                     i r fl]
    [flsin                                       i r fl]
    [flsqrt                                      i r fl]
    [fltan                                       i r fl]
    [fltruncate                                  i r fl]
    [flzero?                                     i r fl]
    [real->flonum                                i r fl]
    [make-no-infinities-violation                i r fl]
    [make-no-nans-violation                      i r fl]
    [&no-infinities                              i r fl]
    [no-infinities-violation?                    i r fl]
    [&no-nans                                    i r fl]
    [no-nans-violation?                          i r fl]
    [bytevector->sint-list                       i r bv]
    [bytevector->u8-list                         i r bv]
    [bytevector->uint-list                       i r bv]
    [bytevector-copy                             i r bv]
    [string-copy!                                i]
    [bytevector-copy!                            i r bv]
    [bytevector-fill!                            i r bv]
    [bytevector-ieee-double-native-ref           i r bv]
    [bytevector-ieee-double-native-set!          i r bv]
    [bytevector-ieee-double-ref                  i r bv]
    [bytevector-ieee-double-set!                 i r bv]
    [bytevector-ieee-single-native-ref           i r bv]
    [bytevector-ieee-single-native-set!          i r bv]
    [bytevector-ieee-single-ref                  i r bv]
    [bytevector-ieee-single-set!                 i r bv]
    [bytevector-length                           i r bv]
    [bytevector-s16-native-ref                   i r bv]
    [bytevector-s16-native-set!                  i r bv]
    [bytevector-s16-ref                          i r bv]
    [bytevector-s16-set!                         i r bv]
    [bytevector-s32-native-ref                   i r bv]
    [bytevector-s32-native-set!                  i r bv]
    [bytevector-s32-ref                          i r bv]
    [bytevector-s32-set!                         i r bv]
    [bytevector-s64-native-ref                   i r bv]
    [bytevector-s64-native-set!                  i r bv]
    [bytevector-s64-ref                          i r bv]
    [bytevector-s64-set!                         i r bv]
    [bytevector-s8-ref                           i r bv]
    [bytevector-s8-set!                          i r bv]
    [bytevector-sint-ref                         i r bv]
    [bytevector-sint-set!                        i r bv]
    [bytevector-u16-native-ref                   i r bv]
    [bytevector-u16-native-set!                  i r bv]
    [bytevector-u16-ref                          i r bv]
    [bytevector-u16-set!                         i r bv]
    [bytevector-u32-native-ref                   i r bv]
    [bytevector-u32-native-set!                  i r bv]
    [bytevector-u32-ref                          i r bv]
    [bytevector-u32-set!                         i r bv]
    [bytevector-u64-native-ref                   i r bv]
    [bytevector-u64-native-set!                  i r bv]
    [bytevector-u64-ref                          i r bv]
    [bytevector-u64-set!                         i r bv]
    [bytevector-u8-ref                           i r bv]
    [bytevector-u8-set!                          i r bv]
    [bytevector-uint-ref                         i r bv]
    [bytevector-uint-set!                        i r bv]
    [bytevector=?                                i r bv]
    [bytevector?                                 i r bv]
    [endianness                                  i r bv]
    [native-endianness                           i r bv]
    [sint-list->bytevector                       i r bv]
    [string->utf16                               i r bv]
    [string->utf32                               i r bv]
    [string->utf8                                i r bv]
    [u8-list->bytevector                         i r bv]
    [uint-list->bytevector                       i r bv]
    [utf8->string                                i r bv]
    [utf16->string                               i r bv]
    [utf32->string                               i r bv]
    [print-condition                             i]
    [condition?                                  i r co]
    [&assertion                                  i r co]
    [assertion-violation?                        i r co]
    [&condition                                  i r co]
    [condition                                   i r co]
    [condition-accessor                          i r co]
    [condition-irritants                         i r co]
    [condition-message                           i r co]
    [condition-predicate                         i r co]
    [condition-who                               i r co]
    [define-condition-type                       i r co]
    [&error                                      i r co]
    [error?                                      i r co]
    [&implementation-restriction                 i r co]
    [implementation-restriction-violation?       i r co]
    [&irritants                                  i r co]
    [irritants-condition?                        i r co]
    [&lexical                                    i r co]
    [lexical-violation?                          i r co]
    [make-assertion-violation                    i r co]
    [make-error                                  i r co]
    [make-implementation-restriction-violation   i r co]
    [make-irritants-condition                    i r co]
    [make-lexical-violation                      i r co]
    [make-message-condition                      i r co]
    [make-non-continuable-violation              i r co]
    [make-serious-condition                      i r co]
    [make-syntax-violation                       i r co]
    [make-undefined-violation                    i r co]
    [make-violation                              i r co]
    [make-warning                                i r co]
    [make-who-condition                          i r co]
    [&message                                    i r co]
    [message-condition?                          i r co]
    [&non-continuable                            i r co]
    [non-continuable-violation?                  i r co]
    [&serious                                    i r co]
    [serious-condition?                          i r co]
    [simple-conditions                           i r co]
    [&syntax                                     i r co]
    [syntax-violation-form                       i r co]
    [syntax-violation-subform                    i r co]
    [syntax-violation?                           i r co]
    [&undefined                                  i r co]
    [undefined-violation?                        i r co]
    [&violation                                  i r co]
    [violation?                                  i r co]
    [&warning                                    i r co]
    [warning?                                    i r co]
    [&who                                        i r co]
    [who-condition?                              i r co]
    [case-lambda                                 i r ct]
    [do                                          i r ct se ne]
    [unless                                      i r ct]
    [when                                        i r ct]
    [define-enumeration                          i r en]
    [enum-set->list                              i r en]
    [enum-set-complement                         i r en]
    [enum-set-constructor                        i r en]
    [enum-set-difference                         i r en]
    [enum-set-indexer                            i r en]
    [enum-set-intersection                       i r en]
    [enum-set-member?                            i r en]
    [enum-set-projection                         i r en]
    [enum-set-subset?                            i r en]
    [enum-set-union                              i r en]
    [enum-set-universe                           i r en]
    [enum-set=?                                  i r en]
    [make-enumeration                            i r en]
    [enum-set?                                   i]
    [environment                                 i ev]
    [eval                                        i ev se]
    [raise                                       i r ex]
    [raise-continuable                           i r ex]
    [with-exception-handler                      i r ex]
    [guard                                       i r ex]
    [binary-port?                                i r ip]
    [buffer-mode                                 i r ip]
    [buffer-mode?                                i r ip]
    [bytevector->string                          i r ip]
    [call-with-bytevector-output-port            i r ip]
    [call-with-port                              i r ip]
    [call-with-string-output-port                i r ip]
    [assoc                                       i r ls se]
    [assp                                        i r ls]
    [assq                                        i r ls se]
    [assv                                        i r ls se]
    [cons*                                       i r ls]
    [filter                                      i r ls]
    [find                                        i r ls]
    [fold-left                                   i r ls]
    [fold-right                                  i r ls]
    [for-all                                     i r ls]
    [exists                                      i r ls]
    [member                                      i r ls se]
    [memp                                        i r ls]
    [memq                                        i r ls se]
    [memv                                        i r ls se]
    [partition                                   i r ls]
    [remq                                        i r ls]
    [remp                                        i r ls]
    [remv                                        i r ls]
    [remove                                      i r ls]
    [set-car!                                    i mp se]
    [set-cdr!                                    i mp se]
    [string-set!                                 i ms se]
    [string-fill!                                i ms se]
    [command-line                                i r pr]
    [exit                                        i r pr]
    [delay                                       i r5 se ne]
    [exact->inexact                              i r5 se]
    [force                                       i r5 se]
    [inexact->exact                              i r5 se]
    [modulo                                      i r5 se]
    [remainder                                   i r5 se]
    [null-environment                            i r5 se]
    [quotient                                    i r5 se]
    [scheme-report-environment                   i r5 se]
    [interaction-environment                     i]
    [new-interaction-environment                 i]
    [close-port                                  i r ip]
    [eol-style                                   i r ip]
    [error-handling-mode                         i r ip]
    [file-options                                i r ip]
    [flush-output-port                           i r ip]
    [get-bytevector-all                          i r ip]
    [get-bytevector-n                            i r ip]
    [get-bytevector-n!                           i r ip]
    [get-bytevector-some                         i r ip]
    [get-char                                    i r ip]
    [get-datum                                   i r ip]
    [get-line                                    i r ip]
    [read-line                                   i]
    [get-string-all                              i r ip]
    [get-string-n                                i r ip]
    [get-string-n!                               i r ip]
    [get-u8                                      i r ip]
    [&i/o                                        i r ip is fi]
    [&i/o-decoding                               i r ip]
    [i/o-decoding-error?                         i r ip]
    [&i/o-encoding                               i r ip]
    [i/o-encoding-error-char                     i r ip]
    [i/o-encoding-error?                         i r ip]
    [i/o-error-filename                          i r ip is fi]
    [i/o-error-port                              i r ip is fi]
    [i/o-error-position                          i r ip is fi]
    [i/o-error?                                  i r ip is fi]
    [&i/o-file-already-exists                    i r ip is fi]
    [i/o-file-already-exists-error?              i r ip is fi]
    [&i/o-file-does-not-exist                    i r ip is fi]
    [i/o-file-does-not-exist-error?              i r ip is fi]
    [&i/o-file-is-read-only                      i r ip is fi]
    [i/o-file-is-read-only-error?                i r ip is fi]
    [&i/o-file-protection                        i r ip is fi]
    [i/o-file-protection-error?                  i r ip is fi]
    [&i/o-filename                               i r ip is fi]
    [i/o-filename-error?                         i r ip is fi]
    [&i/o-invalid-position                       i r ip is fi]
    [i/o-invalid-position-error?                 i r ip is fi]
    [&i/o-port                                   i r ip is fi]
    [i/o-port-error?                             i r ip is fi]
    [&i/o-read                                   i r ip is fi]
    [i/o-read-error?                             i r ip is fi]
    [&i/o-write                                  i r ip is fi]
    [i/o-write-error?                            i r ip is fi]
    [lookahead-char                              i r ip]
    [lookahead-u8                                i r ip]
    [make-bytevector                             i r bv]
    [make-custom-binary-input-port               i r ip]
    [make-custom-binary-output-port              i r ip]
    [make-custom-textual-input-port              i r ip]
    [make-custom-textual-output-port             i r ip]
    [make-custom-binary-input/output-port        i r ip]
    [make-custom-textual-input/output-port       i r ip]
    [make-i/o-decoding-error                     i r ip]
    [make-i/o-encoding-error                     i r ip]
    [make-i/o-error                              i r ip is fi]
    [make-i/o-file-already-exists-error          i r ip is fi]
    [make-i/o-file-does-not-exist-error          i r ip is fi]
    [make-i/o-file-is-read-only-error            i r ip is fi]
    [make-i/o-file-protection-error              i r ip is fi]
    [make-i/o-filename-error                     i r ip is fi]
    [make-i/o-invalid-position-error             i r ip is fi]
    [make-i/o-port-error                         i r ip is fi]
    [make-i/o-read-error                         i r ip is fi]
    [make-i/o-write-error                        i r ip is fi]
    [latin-1-codec                               i r ip]
    [make-transcoder                             i r ip]
    [native-eol-style                            i r ip]
    [native-transcoder                           i r ip]
    [transcoder?                                 i]
    [open-bytevector-input-port                  i r ip]
    [open-bytevector-output-port                 i r ip]
    [open-file-input-port                        i r ip]
    [open-file-input/output-port                 i r ip]
    [open-file-output-port                       i r ip]
    [open-string-input-port                      i r ip]
    [open-string-output-port                     i r ip]
    [output-port-buffer-mode                     i r ip]
    [port-eof?                                   i r ip]
    [port-has-port-position?                     i r ip]
    [port-has-set-port-position!?                i r ip]
    [port-position                               i r ip]
    [input-port-column-number                    i]
    [input-port-row-number                       i]
    [port-transcoder                             i r ip]
    [port?                                       i r ip]
    [put-bytevector                              i r ip]
    [put-char                                    i r ip]
    [put-datum                                   i r ip]
    [put-string                                  i r ip]
    [put-u8                                      i r ip]
    [set-port-position!                          i r ip]
    [standard-error-port                         i r ip]
    [standard-input-port                         i r ip]
    [standard-output-port                        i r ip]
    [string->bytevector                          i r ip]
    [textual-port?                               i r ip]
    [transcoded-port                             i r ip]
    [transcoder-codec                            i r ip]
    [transcoder-eol-style                        i r ip]
    [transcoder-error-handling-mode              i r ip]
    [utf-16-codec                                i r ip]
    [utf-8-codec                                 i r ip]
    [input-port?                                 i r is ip se]
    [output-port?                                i r is ip se]
    [current-input-port                          i r ip is se]
    [current-output-port                         i r ip is se]
    [current-error-port                          i r ip is]
    [eof-object                                  i r ip is]
    [eof-object?                                 i r ip is se]
    [close-input-port                            i r is se]
    [close-output-port                           i r is se]
    [display                                     i r is se]
    [newline                                     i r is se]
    [open-input-file                             i r is se]
    [open-output-file                            i r is se]
    [peek-char                                   i r is se]
    [read                                        i r is se]
    [read-char                                   i r is se]
    [with-input-from-file                        i r is se]
    [with-output-to-file                         i r is se]
    [with-output-to-port                         i]
    [write                                       i r is se]
    [write-char                                  i r is se]
    [call-with-input-file                        i r is se]
    [call-with-output-file                       i r is se]
    [hashtable-clear!                            i r ht]
    [hashtable-contains?                         i r ht]
    [hashtable-copy                              i r ht]
    [hashtable-delete!                           i r ht]
    [hashtable-entries                           i r ht]
    [hashtable-keys                              i r ht]
    [hashtable-mutable?                          i r ht]
    [hashtable-ref                               i r ht]
    [hashtable-set!                              i r ht]
    [hashtable-size                              i r ht]
    [hashtable-update!                           i r ht]
    [hashtable?                                  i r ht]
    [make-eq-hashtable                           i r ht]
    [make-eqv-hashtable                          i r ht]
    [hashtable-hash-function                     i r ht]
    [make-hashtable                              i r ht]
    [hashtable-equivalence-function              i r ht]
    [equal-hash                                  i r ht]
    [string-hash                                 i r ht]
    [string-ci-hash                              i r ht]
    [symbol-hash                                 i r ht]
    [list-sort                                   i r sr]
    [vector-sort                                 i r sr]
    [vector-sort!                                i r sr]
    [file-exists?                                i r fi]
    [delete-file                                 i r fi]
    [rename-file                                 i]
    [file-regular?                               i]
    [file-directory?                             i]
    [file-symbolic-link?                         i]
    [file-readable?                              i]
    [file-writable?                              i]
    [file-executable?                            i]
    [current-directory                           i]
    [directory-list                              i]
    [make-directory                              i]
    [make-directory*                             i]
    [delete-directory                            i]
    [directory-stream?                           i]
    [open-directory-stream                       i]
    [read-directory-stream                       i]
    [close-directory-stream                      i]
    [change-mode                                 i]
    [make-symbolic-link                          i]
    [make-hard-link                              i]
    [file-ctime                                  i]
    [file-mtime                                  i]
    [file-size                                   i]
    [file-real-path                              i]
    [split-file-name                             i]
    [fork                                        i]
    [define-record-type                          i r rs]
    [fields                                      i r rs]
    [immutable                                   i r rs]
    [mutable                                     i r rs]
    [opaque                                      i r rs]
    [parent                                      i r rs]
    [parent-rtd                                  i r rs]
    [protocol                                    i r rs]
    [record-constructor-descriptor               i r rs]
    [record-type-descriptor                      i r rs]
    [sealed                                      i r rs]
    [nongenerative                               i r rs]
    [record-field-mutable?                       i r ri]
    [record-rtd                                  i r ri]
    [record-type-field-names                     i r ri]
    [record-type-generative?                     i r ri]
    [record-type-name                            i r ri]
    [record-type-opaque?                         i r ri]
    [record-type-parent                          i r ri]
    [record-type-sealed?                         i r ri]
    [record-type-uid                             i r ri]
    [record?                                     i r ri]
    [make-record-constructor-descriptor          i r rp]
    [make-record-type-descriptor                 i r rp]
    [record-accessor                             i r rp]
    [record-constructor                          i r rp]
    [record-mutator                              i r rp]
    [record-predicate                            i r rp]
    [record-type-descriptor?                     i r rp]
    [syntax-violation                            i r sc]
    [bound-identifier=?                          i r sc]
    [datum->syntax                               i r sc]
    [syntax                                      i r sc]
    [syntax->datum                               i r sc]
    [syntax-case                                 i r sc]
    [unsyntax                                    i r sc]
    [unsyntax-splicing                           i r sc]
    [quasisyntax                                 i r sc]
    [with-syntax                                 i r sc]
    [free-identifier=?                           i r sc]
    [generate-temporaries                        i r sc]
    [identifier?                                 i r sc]
    [make-variable-transformer                   i r sc]
    [variable-transformer?                       i]
    [variable-transformer-procedure              i]
    [make-compile-time-value                     i]
    [syntax-transpose                            i]
    [char-alphabetic?                            i r uc se]
    [char-ci<=?                                  i r uc se]
    [char-ci<?                                   i r uc se]
    [char-ci=?                                   i r uc se]
    [char-ci>=?                                  i r uc se]
    [char-ci>?                                   i r uc se]
    [char-downcase                               i r uc se]
    [char-foldcase                               i r uc]
    [char-titlecase                              i r uc]
    [char-upcase                                 i r uc se]
    [char-general-category                       i r uc]
    [char-lower-case?                            i r uc se]
    [char-numeric?                               i r uc se]
    [char-title-case?                            i r uc]
    [char-upper-case?                            i r uc se]
    [char-whitespace?                            i r uc se]
    [string-ci<=?                                i r uc se]
    [string-ci<?                                 i r uc se]
    [string-ci=?                                 i r uc se]
    [string-ci>=?                                i r uc se]
    [string-ci>?                                 i r uc se]
    [string-downcase                             i r uc]
    [string-foldcase                             i r uc]
    [string-normalize-nfc                        i r uc]
    [string-normalize-nfd                        i r uc]
    [string-normalize-nfkc                       i r uc]
    [string-normalize-nfkd                       i r uc]
    [string-titlecase                            i r uc]
    [string-upcase                               i r uc]
    [getenv                                      i]
    [setenv                                      i]
    [unsetenv                                    i]
    [environ                                     i]
    [nanosleep                                   i]
    [char-ready?                                 ]
    [load                                        i]
    [load-r6rs-script                            i]
    [void                                        i $boot]
    [gensym                                      i symbols $boot]
    [symbol-value                                i symbols $boot]
    [system-value                                i]
    [set-symbol-value!                           i symbols $boot]
    [eval-core                                   $boot]
    [current-core-eval                           i] ;;; temp
    [pretty-print                                i $boot]
    [pretty-format                               i]
    [pretty-width                                i]
    [module                                      i cm]
    [library                                     i]
    [syntax-dispatch                             ]
    [syntax-error                                i]
    [$transcoder->data                           $transc]
    [$data->transcoder                           $transc]
    [make-file-options                           i]
    ;;;
    [port-id               i]
    [read-annotated        i]
    [read-script-annotated i]
    [annotation?           i]
    [annotation-expression i]
    [annotation-source     i]
    [annotation-stripped   i]
    [port-closed?          i]
    [$make-port           $io]
    [$port-tag            $io]
    [$port-id             $io]
    [$port-cookie         $io]
    [$port-transcoder     $io]
    [$port-index          $io]
    [$port-size           $io]
    [$port-buffer         $io]
    [$port-get-position   $io]
    [$port-set-position!  $io]
    [$port-close          $io]
    [$port-read!          $io]
    [$port-write!         $io]
    [$set-port-index!     $io]
    [$set-port-size!      $io]
    [$port-attrs          $io]
    [$set-port-attrs!     $io]
    ;;;
    [&condition-rtd]
    [&condition-rcd]
    [&message-rtd]
    [&message-rcd]
    [&warning-rtd]
    [&warning-rcd]
    [&serious-rtd]
    [&serious-rcd]
    [&error-rtd]
    [&error-rcd]
    [&violation-rtd]
    [&violation-rcd]
    [&assertion-rtd]
    [&assertion-rcd]
    [&irritants-rtd]
    [&irritants-rcd]
    [&who-rtd]
    [&who-rcd]
    [&non-continuable-rtd]
    [&non-continuable-rcd]
    [&implementation-restriction-rtd]
    [&implementation-restriction-rcd]
    [&lexical-rtd]
    [&lexical-rcd]
    [&syntax-rtd]
    [&syntax-rcd]
    [&undefined-rtd]
    [&undefined-rcd]
    [&i/o-rtd]
    [&i/o-rcd]
    [&i/o-read-rtd]
    [&i/o-read-rcd]
    [&i/o-write-rtd]
    [&i/o-write-rcd]
    [&i/o-invalid-position-rtd]
    [&i/o-invalid-position-rcd]
    [&i/o-filename-rtd]
    [&i/o-filename-rcd]
    [&i/o-file-protection-rtd]
    [&i/o-file-protection-rcd]
    [&i/o-file-is-read-only-rtd]
    [&i/o-file-is-read-only-rcd]
    [&i/o-file-already-exists-rtd]
    [&i/o-file-already-exists-rcd]
    [&i/o-file-does-not-exist-rtd]
    [&i/o-file-does-not-exist-rcd]
    [&i/o-port-rtd]
    [&i/o-port-rcd]
    [&i/o-decoding-rtd]
    [&i/o-decoding-rcd]
    [&i/o-encoding-rtd]
    [&i/o-encoding-rcd]
    [&no-infinities-rtd]
    [&no-infinities-rcd]
    [&no-nans-rtd]
    [&no-nans-rcd]
    [&interrupted-rtd]
    [&interrupted-rcd]
    [&source-rtd]
    [&source-rcd]
    [tcp-connect                      i]
    [udp-connect                      i]
    [tcp-connect-nonblocking          i]
    [udp-connect-nonblocking          i]
    [tcp-server-socket                i]
    [tcp-server-socket-nonblocking    i]
    [accept-connection                i]
    [accept-connection-nonblocking    i]
    [close-tcp-server-socket          i]
    [register-callback                i]
    [input-socket-buffer-size         i]
    [output-socket-buffer-size        i]
    [ellipsis-map ]
    [optimize-cp i]
    [optimize-level i]
    [cp0-size-limit i]
    [cp0-effort-limit i]
    [tag-analysis-output i]
    [perform-tag-analysis i]
    [current-letrec-pass i]
    [pointer?                          $for]
    [pointer->integer                  $for]
    [integer->pointer                  $for]
    [dlopen                            $for]
    [dlerror                           $for]
    [dlclose                           $for]
    [dlsym                             $for]
    [malloc                            $for]
    [free                              $for]
    [memcpy                            $for]
    [errno                             $for]
    [pointer-ref-c-signed-char         $for]
    [pointer-ref-c-signed-short        $for]
    [pointer-ref-c-signed-int          $for]
    [pointer-ref-c-signed-long         $for]
    [pointer-ref-c-signed-long-long    $for]
    [pointer-ref-c-unsigned-char       $for]
    [pointer-ref-c-unsigned-short      $for]
    [pointer-ref-c-unsigned-int        $for]
    [pointer-ref-c-unsigned-long       $for]
    [pointer-ref-c-unsigned-long-long  $for]
    [pointer-ref-c-float               $for]
    [pointer-ref-c-double              $for]
    [pointer-ref-c-pointer             $for]
    [pointer-set-c-char!               $for]
    [pointer-set-c-short!              $for]
    [pointer-set-c-int!                $for]
    [pointer-set-c-long!               $for]
    [pointer-set-c-long-long!          $for]
    [pointer-set-c-pointer!            $for]
    [pointer-set-c-float!              $for]
    [pointer-set-c-double!             $for]
    [make-c-callout                    $for]
    [make-c-callback                   $for]
    [host-info                         i]
    [debug-call                        ]

  ))

(define (macro-identifier? x) 
  (and (assq x ikarus-system-macros) #t))

(define (procedure-identifier? x)
  (not (macro-identifier? x)))

(define bootstrap-collection
  (let ([ls 
         (let f ([ls library-legend])
           (define required? cadddr)
           (define library-name cadr)
           (cond
             [(null? ls) '()]
             [(required? (car ls)) 
              (cons (find-library-by-name (library-name (car ls)))
                    (f (cdr ls)))]
             [else (f (cdr ls))]))])
    (case-lambda
      [() ls]
      [(x) (unless (memq x ls) 
             (set! ls (cons x ls)))])))

(define (verify-map)
  (define (f x)
    (for-each 
      (lambda (x) 
        (unless (assq x library-legend)
          (error 'verify "not in the libraries list" x)))
      (cdr x)))
  (for-each f identifier->library-map))

(library (ikarus makefile collections)
  (export make-collection)
  (import (rnrs))
  (define (make-collection)
    (let ([set '()])
      (case-lambda
        [() set]
        [(x) (set! set (cons x set))]))))

(import (ikarus makefile collections))

(define verbose-output? #f)

(define debugf
  (if verbose-output?
      printf
      (case-lambda
        [(str) (printf str)]
        [(str . args) (printf ".")])))

(define (assq1 x ls)
  (let f ([x x] [ls ls] [p #f])
    (cond
      [(null? ls) p]
      [(eq? x (caar ls)) 
       (if p
           (if (pair? p) 
               (if (eq? (cdr p) (cdar ls))
                   (f x (cdr ls) p)
                   (f x (cdr ls) 2))
               (f x (cdr ls) (+ p 1)))
           (f x (cdr ls) (car ls)))]
      [else (f x (cdr ls) p)])))
      
(define (make-system-data subst env)
  (define who 'make-system-data)
  (let ([export-subst    (make-collection)] 
        [export-env      (make-collection)]
        [export-primlocs (make-collection)])
    (for-each
      (lambda (x)
        (let ([name (car x)] [binding (cadr x)])
          (let ([label (gensym)])
            (export-subst (cons name label))
            (export-env   (cons label binding)))))
      ikarus-system-macros)
    (for-each
      (lambda (x)
        (when (procedure-identifier? x)
          (cond
            [(assq x (export-subst))
             (error who "ambiguous export" x)]
            [(assq1 x subst) =>
             ;;; primitive defined (exported) within the compiled libraries
             (lambda (p)
               (unless (pair? p) 
                 (error who "invalid exports" p x))
               (let ([label (cdr p)])
                 (cond
                   [(assq label env) =>
                    (lambda (p)
                      (let ([binding (cdr p)])
                        (case (car binding)
                          [(global) 
                           (export-subst (cons x label))
                           (export-env   (cons label (cons 'core-prim x)))
                           (export-primlocs (cons x (cdr binding)))]
                          [else 
                           (error #f "invalid binding for identifier" p x)])))]
                   [else (error #f "cannot find binding" x label)])))]
            [else 
             ;;; core primitive with no backing definition, assumed to
             ;;; be defined in other strata of the system
             ;(printf "undefined primitive ~s\n" x)
             (let ([label (gensym)])
               (export-subst (cons x label))
               (export-env (cons label (cons 'core-prim x))))])))
      (map car identifier->library-map))
    (values (export-subst) (export-env) (export-primlocs))))

(define (get-export-subset key subst)
  (let f ([ls subst])
    (cond
      [(null? ls) '()]
      [else
       (let ([x (car ls)])
         (let ([name (car x)])
           (cond
             [(assq name identifier->library-map)
              =>
              (lambda (q)
                (cond
                  [(memq key (cdr q)) 
                   (cons x (f (cdr ls)))]
                  [else (f (cdr ls))]))]
             [else 
              ;;; not going to any library?
              (f (cdr ls))])))])))

(define (build-system-library export-subst export-env primlocs)
  (define (build-library legend-entry)
    (let ([key (car legend-entry)]
          [name (cadr legend-entry)]
          [visible? (caddr legend-entry)]) 
      (let ([id     (gensym)]
            [name       name]
            [version    (if (eq? (car name) 'rnrs) '(6) '())]
            [import-libs '()]
            [visit-libs  '()]
            [invoke-libs '()])
        (let-values ([(subst env)
                      (if (equal? name '(psyntax system $all)) 
                          (values export-subst export-env)
                          (values
                            (get-export-subset key export-subst)
                            '()))])
          `(install-library 
             ',id ',name ',version ',import-libs ',visit-libs ',invoke-libs
             ',subst ',env void void '#f '#f '#f '() ',visible? '#f)))))
  (let ([code `(library (ikarus primlocs)
                  (export) ;;; must be empty
                  (import 
                    (only (ikarus.symbols) system-value-gensym)
                    (only (psyntax library-manager)
                          install-library)
                    (only (ikarus.compiler)
                          current-primitive-locations)
                    (ikarus))
                  (let ([g system-value-gensym])
                    (for-each
                      (lambda (x) (putprop (car x) g (cdr x)))
                      ',primlocs)
                    (let ([proc 
                           (lambda (x) (getprop x g))])
                      (current-primitive-locations proc)))
                  ,@(map build-library library-legend))])
    (let-values ([(name code empty-subst empty-env)
                  (boot-library-expand code)])
       (values name code))))

;;; the first code to run on the system is one that initializes
;;; the value and proc fields of the location of $init-symbol-value!
;;; Otherwise, all subsequent inits to any global variable will
;;; segfault.  

(define (make-init-code)
  (define proc (gensym))
  (define loc (gensym))
  (define label (gensym))
  (define sym (gensym))
  (define val (gensym))
  (define args (gensym))
  (values 
    (list '(ikarus.init))
    (list
      `((case-lambda 
          [(,proc) (,proc ',loc ,proc)])
        (case-lambda
          [(,sym ,val)
           (begin
             ((primitive $set-symbol-value!) ,sym ,val)
             (if ((primitive procedure?) ,val) 
                 ((primitive $set-symbol-proc!) ,sym ,val)
                 ((primitive $set-symbol-proc!) ,sym
                    (case-lambda 
                      [,args
                       ((primitive error)
                         'apply 
                         '"not a procedure"
                         ((primitive $symbol-value) ,sym))]))))])))
    `([$init-symbol-value! . ,label])
    `([,label . (global . ,loc)])))

(define src-dir (or (getenv "IKARUS_SRC_DIR") "."))

(define (expand-all files)
  ;;; remove all re-exported identifiers (those with labels in
  ;;; subst but not binding in env).
  (define (prune-subst subst env)
    (cond 
      ((null? subst) '()) 
      ((not (assq (cdar subst) env)) (prune-subst (cdr subst) env)) 
      (else (cons (car subst) (prune-subst (cdr subst) env)))))
  (let-values (((name* code* subst env) (make-init-code)))
    (debugf "Expanding ")
    (for-each
      (lambda (file)
        (debugf " ~s" file)
        (load (string-append src-dir "/" file)
          (lambda (x) 
            (let-values ([(name code export-subst export-env)
                          (boot-library-expand x)])
               (set! name* (cons name name*))
               (set! code* (cons code code*))
               (set! subst (append export-subst subst))
               (set! env (append export-env env))))))
      files)
    (debugf "\n")
    (let-values ([(export-subst export-env export-locs)
                  (make-system-data (prune-subst subst env) env)])
      (let-values ([(name code)
                    (build-system-library export-subst export-env export-locs)])
        (values 
          (reverse (cons* (car name*) name (cdr name*)))
          (reverse (cons* (car code*) code (cdr code*)))
          export-locs)))))

(verify-map)

(time-it "the entire bootstrap process"
  (lambda ()
    (let-values ([(name* core* locs)
                  (time-it "macro expansion"
                    (lambda () 
                      (parameterize ([current-library-collection
                                       bootstrap-collection])
                        (expand-all scheme-library-files))))])
        (current-primitive-locations
          (lambda (x)
            (cond
              [(assq x locs) => cdr]
              [else 
               (error 'bootstrap "no location for primitive" x)])))
        (let ([p (open-file-output-port "ikarus.boot" 
                    (file-options no-fail))])
          (time-it "code generation and serialization"
            (lambda ()
              (debugf "Compiling ")
              (for-each 
                (lambda (name core) 
                  (debugf " ~s" name)
                  (compile-core-expr-to-port core p))
                name*
                core*) 
              (debugf "\n")))
          (close-output-port p)))))

;(print-missing-prims)

(printf "Happy Happy Joy Joy\n")


;;; vim:syntax=scheme


#!eof


