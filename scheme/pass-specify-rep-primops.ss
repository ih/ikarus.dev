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


(define-syntax section
  (syntax-rules (/section)
    [(section e* ... /section) (begin e* ...)]))

(section ;;; helpers

(define (prm op . arg*)
  (make-primcall op arg*))

(define (nop) (make-primcall 'nop '()))

(define (K x) (make-constant x))


(define (tag-test x mask tag)
  (if mask
      (prm '= (prm 'logand x (K mask)) (K tag))
      (prm '= x (K tag))))

(define (sec-tag-test x pmask ptag smask stag)
  (make-conditional 
    (tag-test x pmask ptag)
    (tag-test (prm 'mref x (K (- ptag))) smask stag)
    (make-constant #f)))

(define (dirty-vector-set address)
  (define shift-bits 2)
  (prm 'mset32 
     (prm 'mref pcr (K pcb-dirty-vector))
     (prm 'sll (prm 'srl address (K pageshift)) (K shift-bits))
     (K dirty-word)))

(define (smart-dirty-vector-set addr what)
  (struct-case what
    [(constant t) 
     (if (or (fx? t) (immediate? t))
         (prm 'nop)
         (dirty-vector-set addr))]
    [(known x t)
     (cond
       [(eq? (T:immediate? t) 'yes)
        (record-optimization 'smart-dirty-vec t)
        (nop)]
       [else (smart-dirty-vector-set addr x)])]
    [else (dirty-vector-set addr)]))

(define (slow-mem-assign v x i)
  (with-tmp ([t (prm 'int+ x (K i))])
    (make-seq 
      (prm 'mset t (K 0) (T v))
      (dirty-vector-set t))))

(define (mem-assign v x i)
  (struct-case v
    [(constant t) 
     (if (or (fx? t) (immediate? t))
         (prm 'mset x (K i) (T v))
         (slow-mem-assign v x i))]
    [(known expr t)
     (cond
       [(eq? (T:immediate? t) 'yes)
        (record-optimization 'mem-assign v)
        (prm 'mset x (K i) (T expr))]
       [else (slow-mem-assign expr x i)])]
    [else (slow-mem-assign v x i)]))

(define (align-code unknown-amt known-amt)
  (prm 'sll 
     (prm 'sra
          (prm 'int+ unknown-amt
               (K (+ known-amt (sub1 object-alignment))))
          (K align-shift))
     (K align-shift)))
/section)

(section ;;; simple objects section

(define-primop base-rtd safe
  [(V) (prm 'mref pcr (K pcb-base-rtd))]
  [(P) (K #t)]
  [(E) (prm 'nop)])

(define-primop void safe
  [(V) (K void-object)]
  [(P) (K #t)]
  [(E) (prm 'nop)])

(define-primop nop unsafe
  [(E) (prm 'nop)])

(define-primop neq? unsafe
  [(P x y) (prm '!= (T x) (T y))]
  [(E x y) (nop)])

(define-primop eq? safe
  [(P x y) (prm '= (T x) (T y))]
  [(E x y) (nop)])

(define (equable-constant? x)
  (struct-case x 
    [(constant xv) (equable? xv)]
    [(known x t) (equable-constant? x)]
    [else #f]))

(define-primop eqv? safe
  [(P x y) 
   (if (or (equable-constant? x)
           (equable-constant? y))
       (prm '= (T x) (T y))
       (interrupt))]
  [(E x y) (nop)])

(define-primop null? safe
  [(P x) (prm '= (T x) (K nil))]
  [(E x) (nop)])

(define-primop not safe
  [(P x) (prm '= (T x) (K bool-f))]
  [(E x) (nop)])

(define-primop eof-object safe
  [(V) (K eof)]
  [(P) (K #t)]
  [(E) (nop)])

(define-primop eof-object? safe
  [(P x) (prm '= (T x) (K eof))]
  [(E x) (nop)])

(define-primop $unbound-object? unsafe
  [(P x) (prm '= (T x) (K unbound))]
  [(E x) (nop)])

(define-primop immediate? safe
  [(P x)
   (make-conditional
     (tag-test (T x) fx-mask fx-tag)
     (make-constant #t)
     (tag-test (T x) 7 7))]
  [(E x) (nop)])

(define-primop boolean? safe
  [(P x) 
   (tag-test (T x) bool-mask bool-tag)]
  [(E x) (nop)])

(define-primop bwp-object? safe
  [(P x) (prm '= (T x) (K bwp-object))]
  [(E x) (nop)])

(define-primop $forward-ptr? unsafe
  [(P x) (prm '= (T x) (K -1))]
  [(E x) (nop)])

(define-primop pointer-value unsafe
  [(V x) (prm 'logand 
           (prm 'srl (T x) (K 1))
           (K (* -1 fx-scale)))]
  [(P x) (K #t)]
  [(E x) (nop)])

(define-primop $arg-list unsafe
  [(V) (prm 'mref pcr (K pcb-arg-list))]
  [(P) (K #t)]
  [(E) (nop)])

(define-primop $collect-key unsafe
  [(V) (prm 'mref pcr (K pcb-collect-key))]
  [(E x) (prm 'mset pcr (K pcb-collect-key) (T x))])

(define-primop $memq safe
  [(P x ls)
   (struct-case ls
     [(constant ls)
      (cond
        [(not (list? ls)) (interrupt)]
        [else
         (with-tmp ([x (T x)])
           (let f ([ls ls])
             (cond
               [(null? ls) (K #f)]
               [(null? (cdr ls)) (prm '= x (T (K (car ls))))]
               [else
                (make-conditional 
                  (prm '= x (T (K (car ls))))
                  (K #t)
                  (f (cdr ls)))])))])]
     [(known expr t) 
      (cogen-pred-$memq x expr)]
     [else (interrupt)])]
  [(V x ls)
   (struct-case ls
     [(constant ls)
      (cond
        [(not (list? ls)) (interrupt)]
        [else
         (with-tmp ([x (T x)])
           (let f ([ls ls])
             (cond
               [(null? ls) (K bool-f)]
               [else
                (make-conditional 
                  (prm '= x (T (K (car ls))))
                  (T (K ls))
                  (f (cdr ls)))])))])]
     [(known expr t) 
      (cogen-value-$memq x expr)]
     [else (interrupt)])]
  [(E x ls) (nop)])

(define-primop memq safe
  [(P x ls) (cogen-pred-$memq x ls)]
  [(V x ls) (cogen-value-$memq x ls)]
  [(E x ls) 
   (struct-case ls
     [(constant ls)
      (cond
        [(list? ls) (nop)]
        [else (interrupt)])]
     [(known expr t)
      (cogen-effect-memq x expr)]
     [else (interrupt)])])

(define (equable? x)
  (or (fx? x) (not (number? x))))

(define-primop memv safe
  [(V x ls) 
   (struct-case ls
     [(constant lsv)
      (cond
        [(and (list? lsv) (andmap equable? lsv))
         (cogen-value-$memq x ls)]
        [else (interrupt)])]
     [(known expr t)
      (cogen-value-memv x expr)]
     [else (interrupt)])]
  [(P x ls) 
   (struct-case ls
     [(constant lsv)
      (cond
        [(and (list? lsv) (andmap equable? lsv))
         (cogen-pred-$memq x ls)]
        [else (interrupt)])]
     [(known expr t)
      (cogen-pred-memv x expr)]
     [else (interrupt)])]
  [(E x ls)
   (struct-case ls
     [(constant lsv)
      (cond
        [(list? lsv) (nop)]
        [else (interrupt)])]
     [(known expr t)
      (cogen-effect-memv x expr)]
     [else (interrupt)])])

/section)

(section ;;; pairs 

(define-primop pair? safe
  [(P x)
   (tag-test (T x) pair-mask pair-tag)]
  [(E x) (nop)])

(define-primop cons safe
  [(V a d)
   (with-tmp ([t (prm 'alloc (K pair-size) (K pair-tag))])
     (prm 'mset t (K (- disp-car pair-tag)) (T a))
     (prm 'mset t (K (- disp-cdr pair-tag)) (T d))
     t)]
  [(P a d) (K #t)]
  [(E a d) (prm 'nop)])

(define-primop $car unsafe
  [(V x) (prm 'mref  (T x) (K (- disp-car pair-tag)))]
  [(E x) (nop)])

(define-primop $cdr unsafe
  [(V x) (prm 'mref  (T x) (K (- disp-cdr pair-tag)))]
  [(E x) (nop)])

(define-primop $set-car! unsafe
  [(E x v)
   (with-tmp ([x (T x)])
     (prm 'mset x (K (- disp-car pair-tag)) (T v))
     (smart-dirty-vector-set x v))])

(define-primop $set-cdr! unsafe
  [(E x v)
   (with-tmp ([x (T x)])
     (prm 'mset x (K (- disp-cdr pair-tag)) (T v))
     (smart-dirty-vector-set x v))])

(define (assert-pair x)
  (struct-case x
    [(known x t)
     (case (T:pair? t)
       [(yes) (record-optimization 'assert-pair x) (nop)]
       [(no)  (interrupt)]
       [else  (assert-pair x)])]
    [else
     (interrupt-unless (tag-test x pair-mask pair-tag))]))

(define-primop car safe
  [(V x)
   (with-tmp ([x (T x)])
     (assert-pair x)
     (prm 'mref x (K (- disp-car pair-tag))))]
  [(E x) (assert-pair (T x))])

(define-primop cdr safe
  [(V x)
   (with-tmp ([x (T x)])
     (assert-pair x)
     (prm 'mref x (K (- disp-cdr pair-tag))))]
  [(E x) (assert-pair (T x))])

(define-primop set-car! safe
  [(E x v)
   (with-tmp ([x (T x)])
     (assert-pair x)
     (prm 'mset x (K (- disp-car pair-tag)) (T v))
     (smart-dirty-vector-set x v))])

(define-primop set-cdr! safe
  [(E x v)
   (with-tmp ([x (T x)])
     (assert-pair x)
     (prm 'mset x (K (- disp-cdr pair-tag)) (T v))
     (smart-dirty-vector-set x v))])


(define (expand-cxr val ls) 
  (cond
    [(null? ls) (T val)]
    [else 
     (with-tmp ([x (expand-cxr val (cdr ls))]) 
       (assert-pair x)
       (prm 'mref x 
          (case (car ls) 
            [(a)  (K (- disp-car pair-tag))]
            [else (K (- disp-cdr pair-tag))])))]))

(define-primop caar   safe [(V x) (expand-cxr x '(a a))])
(define-primop cadr   safe [(V x) (expand-cxr x '(a d))])
(define-primop cdar   safe [(V x) (expand-cxr x '(d a))])
(define-primop cddr   safe [(V x) (expand-cxr x '(d d))])
(define-primop caaar  safe [(V x) (expand-cxr x '(a a a))])
(define-primop caadr  safe [(V x) (expand-cxr x '(a a d))])
(define-primop cadar  safe [(V x) (expand-cxr x '(a d a))])
(define-primop caddr  safe [(V x) (expand-cxr x '(a d d))])
(define-primop cdaar  safe [(V x) (expand-cxr x '(d a a))])
(define-primop cdadr  safe [(V x) (expand-cxr x '(d a d))])
(define-primop cddar  safe [(V x) (expand-cxr x '(d d a))])
(define-primop cdddr  safe [(V x) (expand-cxr x '(d d d))])
;(define-primop caaaar safe [(V x) (expand-cxr x '(a a a a))])
;(define-primop caaadr safe [(V x) (expand-cxr x '(a a a d))])
;(define-primop caadar safe [(V x) (expand-cxr x '(a a d a))])
;(define-primop caaddr safe [(V x) (expand-cxr x '(a a d d))])
;(define-primop cadaar safe [(V x) (expand-cxr x '(a d a a))])
;(define-primop cadadr safe [(V x) (expand-cxr x '(a d a d))])
;(define-primop caddar safe [(V x) (expand-cxr x '(a d d a))])
(define-primop cadddr safe [(V x) (expand-cxr x '(a d d d))])
;(define-primop cdaaar safe [(V x) (expand-cxr x '(d a a a))])
;(define-primop cdaadr safe [(V x) (expand-cxr x '(d a a d))])
;(define-primop cdadar safe [(V x) (expand-cxr x '(d a d a))])
;(define-primop cdaddr safe [(V x) (expand-cxr x '(d a d d))])
;(define-primop cddaar safe [(V x) (expand-cxr x '(d d a a))])
;(define-primop cddadr safe [(V x) (expand-cxr x '(d d a d))])
;(define-primop cdddar safe [(V x) (expand-cxr x '(d d d a))])
;(define-primop cddddr safe [(V x) (expand-cxr x '(d d d d))])


(define-primop list safe
  [(V) (K nil)]
  [(V . arg*)
   (let ([n (length arg*)] [t* (map T arg*)])
     (with-tmp ([v (prm 'alloc (K (align (* n pair-size))) (K pair-tag))])
       (prm 'mset v (K (- disp-car pair-tag)) (car t*))
       (prm 'mset v
            (K (- (+ disp-cdr (* (sub1 n) pair-size)) pair-tag))
            (K nil))
       (let f ([t* (cdr t*)] [i pair-size])
         (cond
           [(null? t*) v]
           [else
            (with-tmp ([tmp (prm 'int+ v (K i))])
              (prm 'mset tmp (K (- disp-car pair-tag)) (car t*))
              (prm 'mset tmp (K (+ disp-cdr (- pair-size) (- pair-tag))) tmp)
              (f (cdr t*) (+ i pair-size)))]))))]
  [(P . arg*) (K #t)]
  [(E . arg*) (nop)])

(define-primop cons* safe
  [(V) (interrupt)]
  [(V x) (T x)]
  [(V a . a*)
   (let ([t* (map T a*)] [n (length a*)])
     (with-tmp ([v (prm 'alloc (K (* n pair-size)) (K pair-tag))])
       (prm 'mset v (K (- disp-car pair-tag)) (T a))
       (let f ([t* t*] [i pair-size])
         (cond
           [(null? (cdr t*)) 
            (seq* (prm 'mset v (K (- i disp-cdr pair-tag)) (car t*)) v)]
           [else
            (with-tmp ([tmp (prm 'int+ v (K i))])
              (prm 'mset tmp (K (- disp-car pair-tag)) (car t*))
              (prm 'mset tmp (K (- (- disp-cdr pair-tag) pair-size)) tmp)
              (f (cdr t*) (+ i pair-size)))]))))]
  [(P) (interrupt)]
  [(P x) (P x)]
  [(P a . a*) (K #t)]
  [(E) (interrupt)]
  [(E . a*) (nop)])




/section)

(section ;;; vectors
  (section ;;; helpers
    (define (vector-range-check x idx)
      (define (check-non-vector x idx)
        (define (check-fx idx)
          (seq*
             (interrupt-unless (tag-test (T x) vector-mask vector-tag))
             (with-tmp ([len (cogen-value-$vector-length x)])
               (interrupt-unless (prm 'u< (T idx) len))
               (interrupt-unless-fixnum len))))
        (define (check-? idx)
          (seq*
            (interrupt-unless (tag-test (T x) vector-mask vector-tag))
            (with-tmp ([len (cogen-value-$vector-length x)])
              (interrupt-unless (prm 'u< (T idx) len))
              (with-tmp ([t (prm 'logor len (T idx))])
                (interrupt-unless-fixnum t)))))
        (struct-case idx
          [(constant i)
           (if (and (fx? i) (>= i 0)) 
               (check-fx idx)
               (check-? idx))]
          [(known idx idx-t)
           (case (T:fixnum? idx-t)
             [(yes) (check-fx idx)]
             [(maybe) (vector-range-check x idx)]
             [else
              (printf "vector check with mismatch index tag ~s" idx-t)
              (vector-range-check x idx)])]
          [else (check-? idx)]))
      (define (check-vector x idx)
        (define (check-fx idx)
          (with-tmp ([len (cogen-value-$vector-length x)])
            (interrupt-unless (prm 'u< (T idx) len))))
        (define (check-? idx)
          (seq*
            (interrupt-unless-fixnum (T idx)) 
            (with-tmp ([len (cogen-value-$vector-length x)])
              (interrupt-unless (prm 'u< (T idx) len)))))
        (struct-case idx
          [(constant i)
           (if (and (fx? i) (>= i 0)) 
               (check-fx idx)
               (interrupt))]
          [(known idx idx-t)
           (case (T:fixnum? idx-t)
             [(yes) (check-fx idx)]
             [(no)  (interrupt)]
             [else  (check-vector x idx)])]
          [else (check-? idx)])) 
      (struct-case x
        [(known x t)
         (case (T:vector? t)
           [(yes) (record-optimization 'check-vector x) (check-vector x idx)]
           [(no) (interrupt)]
           [else (check-non-vector x idx)])]
        [else (check-non-vector x idx)]))
    /section)

(define-primop vector? safe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag fx-mask fx-tag)]
  [(E x) (nop)])

(define-primop $make-vector unsafe
  [(V len)
   (struct-case len
     [(constant i)
      (if (and (fx? i) #f)
          (interrupt)
          (with-tmp ([v (prm 'alloc
                            (K (align (+ (* i wordsize) disp-vector-data)))
                            (K vector-tag))])
              (prm 'mset v 
                   (K (- disp-vector-length vector-tag))
                   (K (* i fx-scale)))
              v))]
     [(known expr t)
      (cogen-value-$make-vector expr)]
     [else
      (with-tmp ([alen (align-code (T len) disp-vector-data)])
        (with-tmp ([v (prm 'alloc alen (K vector-tag))])
          (prm 'mset v (K (- disp-vector-length vector-tag)) (T len))
          v))])]
  [(P len) (K #t)]
  [(E len) (nop)])

(define-primop make-vector safe
  [(V len) 
   (with-tmp ([x (make-forcall "ikrt_make_vector1" (list (T len)))])
      (interrupt-when (prm '= x (K 0)))
      x)])

(define-primop $vector-ref unsafe
  [(V x i)
   (or 
     (struct-case i
       [(constant i) 
        (and (fx? i) 
             (fx>= i 0)
             (prm 'mref (T x) 
                  (K (+ (* i wordsize) (- disp-vector-data vector-tag)))))]
       [(known i t)
        (cogen-value-$vector-ref x i)]
       [else #f])
     (prm 'mref (T x) 
        (prm 'int+ (T i) (K (- disp-vector-data vector-tag)))))]
  [(E x i) (nop)])

(define-primop $vector-length unsafe
  [(V x) (prm 'mref (T x) (K (- disp-vector-length vector-tag)))]
  [(E x) (prm 'nop)]
  [(P x) (K #t)])

(define-primop vector-length safe
  [(V x)
   (struct-case x
     [(known x t)
      (case (T:vector? t)
        [(yes) (record-optimization 'vector-length x) (cogen-value-$vector-length x)]
        [(no)  (interrupt)]
        [else  (cogen-value-vector-length x)])]
     [else
      (seq*
        (interrupt-unless (tag-test (T x) vector-mask vector-tag))
        (with-tmp ([t (cogen-value-$vector-length x)])
          (interrupt-unless-fixnum t)
          t))])]
  [(E x)
   (struct-case x
     [(known x t)
      (case (T:vector? t)
        [(yes) (record-optimization 'vector-length x) (nop)]
        [(no)  (interrupt)]
        [else  (cogen-effect-vector-length x)])]
     [else
      (seq*
        (interrupt-unless (tag-test (T x) vector-mask vector-tag))
        (with-tmp ([t (cogen-value-$vector-length x)])
          (interrupt-unless-fixnum t)))])]
  [(P x) 
   (seq* (cogen-effect-vector-length x) (K #t))])

(define-primop vector-ref safe
  [(V x i)
   (seq*
     (vector-range-check x i)
     (cogen-value-$vector-ref x i))]
  [(E x i)
   (vector-range-check x i)])


(define-primop $vector-set! unsafe
  [(E x i v)
   (struct-case i
     [(constant i) 
      (if (not (fx? i))
          (interrupt)
          (mem-assign v (T x) 
             (+ (* i wordsize)
                (- disp-vector-data vector-tag))))]
     [(known i t)
      (cogen-effect-$vector-set! x i v)]
     [else
      (mem-assign v 
         (prm 'int+ (T x) (T i))
         (- disp-vector-data vector-tag))])])

(define-primop vector-set! safe
  [(E x i v)
   (seq*
     (vector-range-check x i)
     (cogen-effect-$vector-set! x i v))])

(define-primop vector safe
  [(V . arg*)
   (with-tmp ([v (prm 'alloc
                   (K (align (+ disp-vector-data
                                (* (length arg*) wordsize))))
                   (K vector-tag))])
     (seq*
       (prm 'mset v (K (- disp-vector-length vector-tag))
            (K (* (length arg*) wordsize)))
       (let f ([t* (map T arg*)]
               [i (- disp-vector-data vector-tag)])
         (cond
           [(null? t*) v]
           [else
            (make-seq
              (prm 'mset v (K i) (car t*))
              (f (cdr t*) (+ i wordsize)))]))))]
  [(E . arg*) (prm 'nop)]
  [(P . arg*) (K #t)])

/section)

(section ;;; closures

(define-primop procedure? safe
  [(P x) (tag-test (T x) closure-mask closure-tag)])

(define-primop $cpref unsafe
  [(V x i) 
   (struct-case i
     [(constant i) 
      (unless (fx? i) (interrupt))
      (prm 'mref (T x)
         (K (+ (- disp-closure-data closure-tag)
               (* i wordsize))))]
     [(known expr t)
      (cogen-value-$cpref x expr)]
     [else (interrupt)])])

/section)

(section ;;; symbols

(define-primop symbol? safe
  [(P x) 
   (sec-tag-test (T x) vector-mask vector-tag #f symbol-record-tag)]
  [(E x) (nop)])

(define-primop $make-symbol unsafe
  [(V str)
   (with-tmp ([x (prm 'alloc (K (align symbol-record-size)) (K symbol-ptag))])
     (prm 'mset x (K (- symbol-ptag)) (K symbol-record-tag))
     (prm 'mset x (K (- disp-symbol-record-string symbol-ptag))  (T str))
     (prm 'mset x (K (- disp-symbol-record-ustring symbol-ptag)) (K 0))
     (prm 'mset x (K (- disp-symbol-record-value symbol-ptag))   (K unbound))
     (prm 'mset x (K (- disp-symbol-record-proc symbol-ptag))    (K unbound))
     (prm 'mset x (K (- disp-symbol-record-plist symbol-ptag))   (K nil))
     x)]
  [(P str) (K #t)]
  [(E str) (nop)])

(define-primop $symbol-string unsafe
  [(V x) (prm 'mref (T x) (K (- disp-symbol-record-string symbol-ptag)))]
  [(E x) (nop)])

(define-primop $set-symbol-string! unsafe
  [(E x v) (mem-assign v (T x) (- disp-symbol-record-string symbol-ptag))])

(define-primop $symbol-unique-string unsafe
  [(V x) (prm 'mref (T x) (K (- disp-symbol-record-ustring symbol-ptag)))]
  [(E x) (nop)])

(define-primop $set-symbol-unique-string! unsafe
  [(E x v) (mem-assign v (T x) (- disp-symbol-record-ustring symbol-ptag))])

(define-primop $symbol-plist unsafe
  [(V x) (prm 'mref (T x) (K (- disp-symbol-record-plist symbol-ptag)))]
  [(E x) (nop)])

(define-primop $set-symbol-plist! unsafe
  [(E x v) (mem-assign v (T x) (- disp-symbol-record-plist symbol-ptag))])

(define-primop $symbol-value unsafe
  [(V x) (prm 'mref (T x) (K (- disp-symbol-record-value symbol-ptag)))]
  [(E x) (nop)])

(define-primop $set-symbol-value! unsafe
  [(E x v)
   (with-tmp ([x (T x)])
     (prm 'mset x (K (- disp-symbol-record-value symbol-ptag)) (T v))
     (dirty-vector-set x))])

(define-primop $set-symbol-proc! unsafe
  [(E x v)
   (with-tmp ([x (T x)])
     (prm 'mset x (K (- disp-symbol-record-proc symbol-ptag)) (T v))
     (dirty-vector-set x))])

(define-primop $set-symbol-value/proc! unsafe
  [(E x v)
   (with-tmp ([x (T x)] [v (T v)])
     (prm 'mset x (K (- disp-symbol-record-value symbol-ptag)) v)
     (prm 'mset x (K (- disp-symbol-record-proc symbol-ptag)) v)
     (dirty-vector-set x))])

(define-primop top-level-value safe
  [(V x)
   (struct-case x
     [(constant s)
      (if (symbol? s)
          (with-tmp ([v (cogen-value-$symbol-value x)])
            (interrupt-when (cogen-pred-$unbound-object? v))
            v)
          (interrupt))]
     [(known expr t)
      (cogen-value-top-level-value expr)]
     [else
      (with-tmp ([x (T x)])
        (interrupt-unless (cogen-pred-symbol? x))
        (with-tmp ([v (cogen-value-$symbol-value x)])
          (interrupt-when (cogen-pred-$unbound-object? v))
          v))])]
  [(E x)
   (struct-case x
     [(constant s)
      (if (symbol? s)
          (with-tmp ([v (cogen-value-$symbol-value x)])
            (interrupt-when (cogen-pred-$unbound-object? v)))
          (interrupt))]
     [(known expr t)
      (cogen-effect-top-level-value expr)]
     [else
      (with-tmp ([x (T x)])
        (interrupt-unless (cogen-pred-symbol? x))
        (with-tmp ([v (cogen-value-$symbol-value x)])
          (interrupt-when (cogen-pred-$unbound-object? v))))])])


(define-primop $init-symbol-function! unsafe
  [(E x v)
   (with-tmp ([x (T x)] [v (T v)])
     (prm 'mset x (K (- disp-symbol-record-proc symbol-ptag)) v)
     (dirty-vector-set x))])


/section)

(section ;;; fixnums

(define-primop fixnum? safe
  [(P x) (tag-test (T x) fx-mask fx-tag)]
  [(E x) (nop)])


(define-primop fixnum-width safe
  [(V) (K (fxsll (- (* wordsize 8) fx-shift) fx-shift))]
  [(E) (nop)]
  [(P) (K #t)])

(define-primop least-fixnum safe
  [(V) (K (sll (- (expt 2 (- (- (* wordsize 8) fx-shift) 1)))
               fx-shift))]
  [(E) (nop)]
  [(P) (K #t)])

(define-primop greatest-fixnum safe
  [(V) (K (sll (- (expt 2 (- (- (* wordsize 8) fx-shift) 1)) 1)
               fx-shift))]
  [(E) (nop)]
  [(P) (K #t)])




(define-primop $fxzero? unsafe
  [(P x) (prm '= (T x) (K 0))]
  [(E x) (nop)])

(define-primop $fx= unsafe
  [(P x y) (prm '= (T x) (T y))]
  [(E x y) (nop)])

(define-primop $fx< unsafe
  [(P x y) (prm '< (T x) (T y))]
  [(E x y) (nop)])

(define-primop $fx<= unsafe
  [(P x y) (prm '<= (T x) (T y))]
  [(E x y) (nop)])

(define-primop $fx> unsafe
  [(P x y) (prm '> (T x) (T y))]
  [(E x y) (nop)])

(define-primop $fx>= unsafe
  [(P x y) (prm '>= (T x) (T y))]
  [(E x y) (nop)])

(define-primop $fxadd1 unsafe
  [(V x) (cogen-value-$fx+ x (K 1))]
  [(P x) (K #t)]
  [(E x) (nop)])

(define-primop $fxsub1 unsafe
  [(V x) (cogen-value-$fx+ x (K -1))]
  [(P x) (K #t)]
  [(E x) (nop)])

(define-primop $fx+ unsafe
  [(V x y) (prm 'int+ (T x) (T y))]
  [(P x y) (K #t)]
  [(E x y) (nop)])

(define-primop $fx* unsafe
  [(V a b) 
   (struct-case a
    [(constant a)
     (unless (fx? a) (interrupt))
     (prm 'int* (T b) (K a))]
    [(known a t) (cogen-value-$fx* a b)]
    [else
     (struct-case b
       [(constant b)
        (unless (fx? b) (interrupt))
        (prm 'int* (T a) (K b))]
       [(known b t) (cogen-value-$fx* a b)]
       [else
        (prm 'int* (T a) (prm 'sra (T b) (K fx-shift)))])])]
  [(P x y) (K #t)]
  [(E x y) (nop)])

(define-primop $fxlognot unsafe
  [(V x) (cogen-value-$fxlogxor x (K -1))]
  [(P x) (K #t)]
  [(E x) (nop)])

(define-primop $fxlogand unsafe
  [(V x y) (prm 'logand (T x) (T y))]
  [(P x y) (K #t)]
  [(E x y) (nop)])

(define-primop $fxlogor unsafe
  [(V x y) (prm 'logor (T x) (T y))]
  [(P x y) (K #t)]
  [(E x y) (nop)])

(define-primop $fxlogxor unsafe
  [(V x y) (prm 'logxor (T x) (T y))]
  [(P x y) (K #t)]
  [(E x y) (nop)])

(define-primop $fx- unsafe
  [(V x y) (prm 'int- (T x) (T y))]
  [(P x y) (K #t)]
  [(E x y) (nop)])

(define-primop $fxsll unsafe
  [(V x i)
   (struct-case i
     [(constant i) 
      (unless (fx? i) (interrupt))
      (prm 'sll (T x) (K i))]
     [(known i t) (cogen-value-$fxsll x i)]
     [else 
      (prm 'sll (T x) (prm 'sra (T i) (K fx-shift)))])]
  [(P x i) (K #t)]
  [(E x i) (nop)])

(define-primop $fxsra unsafe
  [(V x i)
   (struct-case i
     [(constant i) 
      (unless (fx? i) (interrupt))
      (prm 'logand 
           (prm 'sra (T x) 
                (K (if (< i (* wordsize 8))
                       i
                       (- (* wordsize 8) 1))))
           (K (* -1 fx-scale)))]
     [(known i t) (cogen-value-$fxsra x i)]
     [else 
      (with-tmp ([i (prm 'sra (T i) (K fx-shift))])
        (with-tmp ([i (make-conditional
                        (prm '< i (K (* 8 wordsize)))
                        i
                        (K (- (* 8 wordsize) 1)))])
           (prm 'logand
                (prm 'sra (T x) i)
                (K (* -1 fx-scale)))))])]
  [(P x i) (K #t)]
  [(E x i) (nop)])

(define-primop $fxquotient unsafe
  [(V a b) 
   (with-tmp ([b (T b)]) ;;; FIXME: why is quotient called remainder?
    (prm 'sll (prm 'int-quotient (T a) b) (K fx-shift)))]
  [(P a b) (K #t)]
  [(E a b) (nop)])

(define-primop $int-quotient unsafe
  [(V a b)
   (prm 'sll (prm 'int-quotient (T a) (T b)) (K fx-shift))])

(define-primop $int-remainder unsafe
  [(V a b) (prm 'int-remainder (T a))])

(define-primop $fxmodulo unsafe
  [(V a b)
   (with-tmp ([b (T b)]) 
     (with-tmp ([c (prm 'logand b 
                      (prm 'sra (prm 'logxor b (T a))
                         (K (sub1 (* 8 wordsize)))))])
       (prm 'int+ c (prm 'int-remainder (T a) b))))]
  [(P a b) (K #t)]
  [(E a b) (nop)])

(define-primop $fxinthash unsafe
  [(V key)
   (with-tmp ([k (T key)])
     (with-tmp ([k (prm 'int+ k (prm 'logxor (prm 'sll k (K 15)) (K -1)))])
       (with-tmp ([k (prm 'logxor k (prm 'sra k (K 10)))])
         (with-tmp ([k (prm 'int+ k (prm 'sll k (K 3)))])
           (with-tmp ([k (prm 'logxor k (prm 'sra k (K 6)))])
             (with-tmp ([k (prm 'int+ k (prm 'logxor (prm 'sll k (K 11)) (K -1)))])
               (with-tmp ([k (prm 'logxor k (prm 'sra k (K 16)))])
                 (prm 'sll k (K fx-shift)))))))))])
           

;(define inthash
;    (lambda (key)
;      ;static int inthash(int key) { /* from Bob Jenkin's */
;      ;  key += ~(key << 15);
;      ;  key ^=  (key >> 10);
;      ;  key +=  (key << 3);
;      ;  key ^=  (key >> 6);
;      ;  key += ~(key << 11);
;      ;  key ^=  (key >> 16);
;      ;  return key;
;      ;}
;      (let* ([key ($fx+ key ($fxlognot ($fxsll key 15)))]
;             [key ($fxlogxor key ($fxsra key 10))]
;             [key ($fx+ key ($fxsll key 3))]
;             [key ($fxlogxor key ($fxsra key 6))]
;             [key ($fx+ key ($fxlognot ($fxsll key 11)))]
;             [key ($fxlogxor key ($fxsra key 16))])
;        key)))


/section)

(section ;;; bignums

(define-primop bignum? safe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag bignum-mask bignum-tag)]
  [(E x) (nop)])

(define-primop $bignum-positive? unsafe
  [(P x) 
   (prm '= (prm 'logand
                (prm 'mref (T x) (K (- vector-tag))) 
                (K bignum-sign-mask))
        (K 0))]
  [(E x) (nop)])

(define-primop $bignum-byte-ref unsafe
  [(V s i)
   (struct-case i
     [(constant i)
      (unless (fx? i) (interrupt))
      (prm 'sll
        (prm 'logand 
           (prm 'mref (T s)
             (K (+ i (- disp-bignum-data record-tag))))
           (K 255))
        (K fx-shift))]
     [(known i t) (cogen-value-$bignum-byte-ref s i)]
     [else
      (prm 'sll
        (prm 'srl ;;; FIXME: bref
           (prm 'mref (T s)
                (prm 'int+
                   (prm 'sra (T i) (K fx-shift))
                   ;;; ENDIANNESS DEPENDENCY
                   (K (- disp-bignum-data 
                         (- wordsize 1) 
                         record-tag))))
           (K (* (- wordsize 1) 8)))
        (K fx-shift))])]
  [(P s i) (K #t)]
  [(E s i) (nop)])

(define-primop $bignum-size unsafe
  [(V x) 
   (prm 'sll
     (prm 'sra
       (prm 'mref (T x) (K (- record-tag))) 
       (K bignum-length-shift))
     (K (* 2 fx-shift)))])

/section)

(section ;;; flonums

(define ($flop-aux op fl0 fl1)
  (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K flonum-tag))
     (prm 'fl:load (T fl0) (K (- disp-flonum-data vector-tag)))
     (prm op (T fl1) (K (- disp-flonum-data vector-tag)))
     (prm 'fl:store x (K (- disp-flonum-data vector-tag)))
     x))

(define ($flop-aux* op fl fl*)
  (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K flonum-tag))
     (prm 'fl:load (T fl) (K (- disp-flonum-data vector-tag)))
     (let f ([fl* fl*])
       (cond
         [(null? fl*) (prm 'nop)]
         [else
          (make-seq 
            (prm op (T (car fl*)) (K (- disp-flonum-data vector-tag)))
            (f (cdr fl*)))]))
     (prm 'fl:store x (K (- disp-flonum-data vector-tag)))
     x))

(define ($flcmp-aux op fl0 fl1)
  (make-seq 
    (prm 'fl:load (T fl0) (K (- disp-flonum-data vector-tag)))
    (prm op (T fl1) (K (- disp-flonum-data vector-tag)))))

(define-primop flonum? safe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag #f flonum-tag)]
  [(E x) (nop)])

(define-primop $flonum-u8-ref unsafe
  [(V s i)
   (struct-case i
     [(constant i)
      (unless (and (fx? i) (fx<= 0 i) (fx<= i 7))
        (interrupt))
      (prm 'sll
        (prm 'logand 
           (prm 'bref (T s)
             (K (+ (- 7 i) (- disp-flonum-data record-tag))))
           (K 255))
        (K fx-shift))]
     [(known expr t) 
      (cogen-value-$flonum-u8-ref s expr)]
     [else (interrupt)])]
  [(P s i) (K #t)]
  [(E s i) (nop)])

(define-primop $make-flonum unsafe
  [(V)
   (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K flonum-tag))
     x)]
  [(P str) (K #t)]
  [(E str) (nop)])

(define-primop $flonum-set! unsafe
  [(E x i v)
   (struct-case i
     [(constant i)
      (unless (and (fx? i) (fx<= 0 i) (fx<= i 7))
        (interrupt))
      (prm 'bset
         (T x)
         (K (+ (- 7 i) (- disp-flonum-data vector-tag)))
         (prm 'sra (T v) (K fx-shift)))]
     [(known expr t) 
      (cogen-effect-$flonum-set! x expr v)]
     [else (interrupt)])])

(define-primop $fixnum->flonum unsafe
  [(V fx) 
   (case wordsize
     [(4)
      (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
        (prm 'mset x (K (- vector-tag)) (K flonum-tag))
        (prm 'fl:from-int
             (K 0) ; dummy
             (prm 'sra (T fx) (K fx-shift)))
        (prm 'fl:store x (K (- disp-flonum-data vector-tag)))
        x)]
     [else 
      (with-tmp ([f (cogen-value-$make-flonum)])
        (make-forcall "ikrt_fixnum_to_flonum" (list (T fx) f)))])])


(define (check-flonums ls code)
  (cond
    [(null? ls) code]
    [else
     (struct-case (car ls) 
       [(constant v) 
        (if (flonum? v) 
            (check-flonums (cdr ls) code)
            (interrupt))]
       [(known x t)
        (case (T:flonum? t)
          [(yes)
           (record-optimization 'check-flonum x)
           (check-flonums (cdr ls) code)]
          [(no) (interrupt)]
          [else (check-flonums (cons x (cdr ls)) code)])]
       [else
        (check-flonums (cdr ls) 
          (with-tmp ([x (T (car ls))])
            (interrupt-unless 
              (tag-test x vector-mask vector-tag))
            (interrupt-unless
              (prm '= (prm 'mref x (K (- vector-tag)))
                   (K flonum-tag)))
            code))])]))

;  (define (primary-tag-tests ls)
;    (cond
;      [(null? ls) (prm 'nop)]
;      [else 
;       (seq* 
;         (interrupt-unless 
;           (tag-test (car ls) vector-mask vector-tag))
;         (primary-tag-tests (cdr ls)))]))
;  (define (secondary-tag-tests ls)
;    (define (or* a*)
;      (cond
;        [(null? (cdr a*)) (car a*)]
;        [else (prm 'logor (car a*) (or* (cdr a*)))]))
;    (interrupt-unless
;      (prm '= (or* (map (lambda (x) 
;                          (prm 'mref x (K (- vector-tag))))
;                        ls))
;           (K flonum-tag))))
;  (let ([check
;         (let f ([ls ls] [ac '()])
;           (cond
;             [(null? ls) ac]
;             [else
;              (struct-case (car ls)
;                [(constant v) 
;                 (if (flonum? v) 
;                     (f (cdr ls) ac)
;                     #f)]
;                [else (f (cdr ls) (cons (T (car ls)) ac))])]))])
;    (cond
;      [(not check) (interrupt)]
;      [(null? check) code]
;      [else
;       (seq* 
;         (primary-tag-tests check)
;         (secondary-tag-tests check)
;         code)])))

(define-primop $fl+ unsafe
  [(V x y) ($flop-aux 'fl:add! x y)])
(define-primop $fl- unsafe
  [(V x y) ($flop-aux 'fl:sub! x y)])
(define-primop $fl* unsafe
  [(V x y) ($flop-aux 'fl:mul! x y)])
(define-primop $fl/ unsafe
  [(V x y) ($flop-aux 'fl:div! x y)])

(define-primop fl+ safe
  [(V) (K (make-object 0.0))]
  [(V x) (check-flonums (list x) (T x))]
  [(V x . x*) (check-flonums (cons x x*) ($flop-aux* 'fl:add! x x*))]
  [(P . x*) (check-flonums x* (K #t))]
  [(E . x*) (check-flonums x* (nop))])
(define-primop fl* safe
  [(V) (K (make-object 1.0))]
  [(V x) (check-flonums (list x) (T x))]
  [(V x . x*) (check-flonums (cons x x*) ($flop-aux* 'fl:mul! x x*))]
  [(P . x*) (check-flonums x* (K #t))]
  [(E . x*) (check-flonums x* (nop))])
(define-primop fl- safe
  [(V x) (check-flonums (list x) ($flop-aux 'fl:sub! (K 0.0) x))]
  [(V x . x*) (check-flonums (cons x x*) ($flop-aux* 'fl:sub! x x*))]
  [(P x . x*) (check-flonums (cons x x*) (K #t))]
  [(E x . x*) (check-flonums (cons x x*) (nop))])
(define-primop fl/ safe
  [(V x) (check-flonums (list x) ($flop-aux 'fl:div! (K 1.0) x))]
  [(V x . x*) (check-flonums (cons x x*) ($flop-aux* 'fl:div! x x*))]
  [(P x . x*) (check-flonums (cons x x*) (K #t))]
  [(E x . x*) (check-flonums (cons x x*) (nop))])

(define-primop $fl= unsafe
  [(P x y) ($flcmp-aux 'fl:= x y)])
(define-primop $fl< unsafe
  [(P x y) ($flcmp-aux 'fl:< x y)])
(define-primop $fl<= unsafe
  [(P x y) ($flcmp-aux 'fl:<= x y)])
(define-primop $fl> unsafe
  [(P x y) ($flcmp-aux 'fl:> x y)])
(define-primop $fl>= unsafe
  [(P x y) ($flcmp-aux 'fl:>= x y)])

(define-primop fl=? safe
  [(P x y) (check-flonums (list x y) ($flcmp-aux 'fl:= x y))]
  [(E x y) (check-flonums (list x y) (nop))])
(define-primop fl<? safe
  [(P x y) (check-flonums (list x y) ($flcmp-aux 'fl:< x y))]
  [(E x y) (check-flonums (list x y) (nop))])
(define-primop fl<=? safe
  [(P x y) (check-flonums (list x y) ($flcmp-aux 'fl:<= x y))]
  [(E x y) (check-flonums (list x y) (nop))])
(define-primop fl>? safe
  [(P x y) (check-flonums (list x y) ($flcmp-aux 'fl:> x y))]
  [(E x y) (check-flonums (list x y) (nop))])
(define-primop fl>=? safe
  [(P x y) (check-flonums (list x y) ($flcmp-aux 'fl:>= x y))]
  [(E x y) (check-flonums (list x y) (nop))])

(define-primop $flonum-sbe unsafe
  [(V x) 
   (prm 'sll 
     (prm 'srl 
       (prm 'mref32 (T x)
          (K (- (+ disp-flonum-data 4) vector-tag)))
       (K 20))
     (K fx-shift))])

/section)

(section ;;; ratnums

(define-primop ratnum? safe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag #f ratnum-tag)]
  [(E x) (nop)])

(define-primop $make-ratnum unsafe
  [(V num den)
   (with-tmp ([x (prm 'alloc (K (align ratnum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K ratnum-tag))
     (prm 'mset x (K (- disp-ratnum-num vector-tag)) (T num))
     (prm 'mset x (K (- disp-ratnum-den vector-tag)) (T den))
     x)]
  [(P str) (K #t)]
  [(E str) (nop)])


(define-primop $ratnum-n unsafe
  [(V x) (prm 'mref (T x) (K (- disp-ratnum-num vector-tag)))])

(define-primop $ratnum-d unsafe
  [(V x) (prm 'mref (T x) (K (- disp-ratnum-den vector-tag)))])

/section)

(section ;;; complnums

(define-primop compnum? safe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag #f compnum-tag)]
  [(E x) (nop)])

(define-primop $make-compnum unsafe
  [(V real imag)
   (with-tmp ([x (prm 'alloc (K (align compnum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K compnum-tag))
     (prm 'mset x (K (- disp-compnum-real vector-tag)) (T real))
     (prm 'mset x (K (- disp-compnum-imag vector-tag)) (T imag))
     x)]
  [(P str) (K #t)]
  [(E str) (nop)])


(define-primop $compnum-real unsafe
  [(V x) (prm 'mref (T x) (K (- disp-compnum-real vector-tag)))])

(define-primop $compnum-imag unsafe
  [(V x) (prm 'mref (T x) (K (- disp-compnum-imag vector-tag)))])

/section)


(section ;;; cflonums

(define-primop cflonum? safe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag #f cflonum-tag)]
  [(E x) (nop)])

(define-primop $make-cflonum unsafe
  [(V real imag)
   (with-tmp ([x (prm 'alloc (K (align cflonum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K cflonum-tag))
     (prm 'mset x (K (- disp-cflonum-real vector-tag)) (T real))
     (prm 'mset x (K (- disp-cflonum-imag vector-tag)) (T imag))
     x)]
  [(P str) (K #t)]
  [(E str) (nop)])


(define-primop $cflonum-real unsafe
  [(V x) (prm 'mref (T x) (K (- disp-cflonum-real vector-tag)))])

(define-primop $cflonum-imag unsafe
  [(V x) (prm 'mref (T x) (K (- disp-cflonum-imag vector-tag)))])

/section)

(section ;;; generic arithmetic



(define (assert-fixnums a a*)
  (define (or* a a*)
    (cond
      [(null? a*) a]
      [else (or* (prm 'logor a (T (car a*))) (cdr a*))]))
  (define (known-fixnum? x)
    (struct-case x
      [(constant i) (fx? i)]
      [(known x t) 
       (case (T:fixnum? t)
         [(yes) (record-optimization 'assert-fixnum x) #t]
         [else  #f])]
      [else #f]))
  (define (known-non-fixnum? x)
    (struct-case x
      [(constant i) (not (fx? i))]
      [(known x t) (eq? (T:fixnum? t) 'no)]
      [else #f]))
  (let-values ([(fx* others) (partition known-fixnum? (cons a a*))])
    (let-values ([(nfx* others) (partition known-non-fixnum?  others)])
      (cond
        [(not (null? nfx*)) (interrupt)]
        [(null? others)     (nop)]
        [else
         (interrupt-unless 
           (tag-test (or* (T (car others)) (cdr others)) fx-mask fx-tag))]))))

(define (fixnum-fold-p op a a*)
  (seq*
    (assert-fixnums a a*)
    (let f ([a a] [a* a*])
      (cond
        [(null? a*) (K #t)]
        [else
         (let ([b (car a*)])
           (make-conditional
             (prm op (T a) (T b))
             (f b (cdr a*))
             (K #f)))]))))

(define-primop = safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop < safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '< a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop <= safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '<= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop > safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '> a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop >= safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '>= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx= safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx< safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '< a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx<= safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '<= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx> safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '> a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx>= safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '>= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx=? safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx<? safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '< a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx<=? safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '<= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx>? safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '> a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx>=? safe
  [(P) (interrupt)]
  [(P a . a*) (fixnum-fold-p '>= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop - safe
  [(V a) 
   (interrupt)
   (seq*
     (assert-fixnums a '())
     (prm 'int-/overflow (K 0) (T a)))]
  [(V a . a*)
   (interrupt)
   (seq*
     (assert-fixnums a a*)
     (let f ([a (T a)] [a* a*])
       (cond
         [(null? a*) a]
         [else
          (f (prm 'int-/overflow a (T (car a*))) (cdr a*))])))]
  [(P a . a*) (seq* (assert-fixnums a a*) (K #t))]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop + safe
  [(V) (K 0)]
  [(V a . a*)
   (interrupt)
   (seq*
     (assert-fixnums a a*)
     (let f ([a (T a)] [a* a*])
       (cond
         [(null? a*) a]
         [else
          (f (prm 'int+/overflow a (T (car a*))) (cdr a*))])))]
  [(P) (K #t)]
  [(P a . a*) (seq* (assert-fixnums a a*) (K #t))]
  [(E) (nop)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop add1 safe
  [(V x) (cogen-value-+ x (K 1))])
(define-primop sub1 safe
  [(V x) (cogen-value-+ x (K -1))])

(define-primop fxadd1 safe
  [(V x) (cogen-value-+ x (K 1))])
(define-primop fxsub1 safe
  [(V x) (cogen-value-+ x (K -1))])


(define (cogen-binary-* a b)
  (define (cogen-*-non-constants a b)
    (interrupt)
    (with-tmp ([a (T a)] [b (T b)])
      (assert-fixnum a)
      (assert-fixnum b)
      (prm 'int*/overflow a 
        (prm 'sra b (K fx-shift)))))
  (define (cogen-*-constant a b)
    (struct-case a
      [(constant ak)
       (if (fx? ak)
           (begin
             (interrupt)
             (with-tmp ([b (T b)])
                (assert-fixnum b)
                (prm 'int*/overflow a b)))
           (interrupt))]
      [(known x t) (cogen-*-constant x b)]
      [else #f]))
  (or (cogen-*-constant a b)
      (cogen-*-constant b a)
      (cogen-*-non-constants a b)))


(define-primop * safe
  [(V) (K (fxsll 1 fx-shift))]
  [(V a b) (cogen-binary-* a b)]
  [(P) (K #t)]
  [(P a . a*) (seq* (assert-fixnums a a*) (K #t))]
  [(E) (nop)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop bitwise-and safe
  [(V) (K (fxsll -1 fx-shift))]
  [(V a . a*)
   (interrupt)
   (seq*
     (assert-fixnums a a*)
     (let f ([a (T a)] [a* a*])
       (cond
         [(null? a*) a]
         [else
          (f (prm 'logand a (T (car a*))) (cdr a*))])))]
  [(P) (K #t)]
  [(P a . a*) (seq* (assert-fixnums a a*) (K #t))]
  [(E) (nop)]
  [(E a . a*) (assert-fixnums a a*)])

(define-primop fx+ safe
  [(V x y) (cogen-value-+ x y)])

(define-primop fx- safe
  [(V x)   (cogen-value-- (K 0) x)]
  [(V x y) (cogen-value-- x y)])

(define-primop fx* safe
  [(V a b) (cogen-binary-* a b)])

(define-primop zero? safe
  [(P x)
   (seq*
     (assert-fixnum x)
     (cogen-pred-$fxzero? x))]
  [(E x) (assert-fixnum x)])


(define-primop fxarithmetic-shift-left safe
  [(V x n) 
   (struct-case n 
     [(constant i) 
      (cond
        [(and (fx? i)
              (>= i 0)
              (< i (- (* wordsize 8) fx-shift)))
         (with-tmp ([x (T x)])
           (assert-fixnum x)
           (cond
             [(< i 6) 
              (let f ([i i]) 
                (cond
                  [(zero? i) x]
                  [else
                   (interrupt)
                   (prm 'sll/overflow (f (- i 1)) (K 1))]))]
             [else 
              (with-tmp ([x2 (prm 'sll x (K i))])
                (interrupt-unless (prm '= (prm 'sra x2 (K i)) x))
                x2)]))]
        [else
         (interrupt)])]
     [else 
      (with-tmp ([x (T x)] [n (T n)])
        (assert-fixnums x (list n))
        (with-tmp ([n (prm 'sra n (K fx-shift))])
          (interrupt-when 
            (prm '< n (K 0)))
          (interrupt-when 
            (prm '>= n (K (- (* wordsize 8) fx-shift))))
          (with-tmp ([x2 (prm 'sll x n)])
            (interrupt-unless (prm '= (prm 'sra x2 n) x))
            x2)))])])



(define-primop fxarithmetic-shift-right safe
  [(V x n) 
   (struct-case n 
     ;;; FIXME: check for known types
     [(constant i)
      (cond
        [(and (fx? i)
              (>= i 0)
              (< i (- (* wordsize 8) fx-shift)))
         (prm 'sll
              (prm 'sra (T x) (K (+ i fx-shift)))
              (K fx-shift))]
        [else
         (interrupt)])]
     [else 
      (with-tmp ([x (T x)] [n (T n)])
        (assert-fixnums x (list n))
        (with-tmp ([n (prm 'sra n (K fx-shift))])
          (interrupt-when 
            (prm '< n (K 0)))
          (interrupt-when 
            (prm '>= n (K (- (* wordsize 8) fx-shift))))
          (prm 'sll 
               (prm 'sra (prm 'sra x n) (K fx-shift))
               (K fx-shift))))])])


(define (log2 n) 
  (let f ([n n] [i 0])
    (cond
      [(zero? (fxand n 1))
       (f (fxsra n 1) (+ i 1))]
      [(= n 1) i]
      [else #f])))


(define-primop div safe
  [(V x n) 
   (struct-case n 
     [(constant i) 
      (cond
        [(and (fx? i) (> i 0) (log2 i)) =>
         (lambda (bits) 
           (seq* 
             (interrupt-unless (cogen-pred-fixnum? x))
             (prm 'sll 
               (prm 'sra (T x) (K (+ bits fx-shift)))
               (K fx-shift))))]
        [else
         (interrupt)])]
     [(known expr t)
      (cogen-value-div x expr)]
     [else (interrupt)])])

(define-primop quotient safe
  [(V x n) 
   (struct-case n
    [(constant i) 
     (if (eqv? i 2) 
         (seq* 
           (interrupt-unless (cogen-pred-fixnum? x)) 
           (make-conditional
             (prm '< (T x) (K 0))
             (prm 'logand
               (prm 'int+ 
                 (prm 'sra (T x) (K 1))
                 (K (fxsll 1 (sub1 fx-shift))))
               (K (fxsll -1 fx-shift)))
             (prm 'logand
               (prm 'sra (T x) (K 1))
               (K (fxsll -1 fx-shift)))))
         (interrupt))]
    [(known expr t) (cogen-value-quotient x expr)]
    [else (interrupt)])])

/section)

(section ;;; structs

(define-primop $struct? unsafe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag vector-mask vector-tag)]
  [(E x) (nop)])

(define-primop $struct/rtd? unsafe
  [(P x rtd)
   (make-conditional
     (tag-test (T x) vector-mask vector-tag)
     (prm '= (prm 'mref (T x) (K (- vector-tag))) (T rtd))
     (make-constant #f))]
  [(E x rtd) (nop)])

(define-primop $make-struct unsafe
  [(V rtd len)
   (struct-case len
     [(constant i) 
      (unless (fx? i) (interrupt))
      (with-tmp ([t (prm 'alloc
                         (K (align (+ (* i wordsize) disp-struct-data)))
                         (K vector-tag))])
        (prm 'mset t (K (- disp-struct-rtd vector-tag)) (T rtd))
        t)]
     [(known expr t)
      (cogen-value-$make-struct rtd expr)]
     [else
      (with-tmp ([ln (align-code len disp-struct-data)])
        (with-tmp ([t (prm 'alloc ln (K vector-tag))])
          (prm 'mset t (K (- disp-struct-rtd vector-tag)) (T rtd))
           t))])]
  [(P rtd len) (K #t)]
  [(E rtd len) (nop)])

(define-primop $struct-rtd unsafe
  [(V x) 
   (prm 'mref (T x) (K (- disp-struct-rtd vector-tag)))]
  [(E x) (nop)]
  [(P x) #t])

(define-primop $struct-ref unsafe
  [(V x i) (cogen-value-$vector-ref x i)]
  [(E x i) (nop)])

(define-primop $struct-set! unsafe
  [(V x i v) 
   (seq* (cogen-effect-$vector-set! x i v) 
         (K void-object))]
  [(E x i v) (cogen-effect-$vector-set! x i v)]
  [(P x i v) 
   (seq* (cogen-effect-$vector-set! x i v)
         (K #t))])

(define-primop $struct unsafe
  [(V rtd . v*)
   (with-tmp ([t (prm 'alloc 
                     (K (align
                          (+ disp-struct-data
                            (* (length v*) wordsize))))
                     (K vector-tag))])
     (prm 'mset t (K (- disp-struct-rtd vector-tag)) (T rtd))
     (let f ([v* v*] 
             [i (- disp-struct-data vector-tag)])
       (cond
         [(null? v*) t]
         [else
          (make-seq 
            (prm 'mset t (K i) (T (car v*)))
            (f (cdr v*) (+ i wordsize)))])))]
  [(P rtd . v*) (K #t)]
  [(E rtd . v*) (nop)])

/section)

(section ;;; characters

(define-primop char? safe
  [(P x) (tag-test (T x) char-mask char-tag)]
  [(E x) (nop)])

(define-primop $char= unsafe
  [(P x y) (prm '= (T x) (T y))]
  [(E x y) (nop)])

(define-primop $char< unsafe
  [(P x y) (prm '< (T x) (T y))]
  [(E x y) (nop)])

(define-primop $char<= unsafe
  [(P x y) (prm '<= (T x) (T y))]
  [(E x y) (nop)])

(define-primop $char> unsafe
  [(P x y) (prm '> (T x) (T y))]
  [(E x y) (nop)])

(define-primop $char>= unsafe
  [(P x y) (prm '>= (T x) (T y))]
  [(E x y) (nop)])

(define-primop $fixnum->char unsafe
  [(V x) 
   (prm 'logor
        (prm 'sll (T x) (K (- char-shift fx-shift)))
        (K char-tag))]
  [(P x) (K #t)]
  [(E x) (nop)])

(define-primop $char->fixnum unsafe
  [(V x) (prm 'sra (T x) (K (- char-shift fx-shift)))]
  [(P x) (K #t)]
  [(E x) (nop)])


(define (assert-chars a a*)
  (define (or* a a*)
    (cond
      [(null? a*) a]
      [else (or* (prm 'logor a (T (car a*))) (cdr a*))]))
  (define (known-char? x)
    (struct-case x
      [(constant i) (char? i)]
      [(known x t) (eq? (T:char? t) 'yes)]
      [else #f]))
  (define (known-non-char? x)
    (struct-case x
      [(constant i) (not (char? i))]
      [(known x t) (eq? (T:char? t) 'no)]
      [else #f]))
  (let-values ([(fx* others) (partition known-char? (cons a a*))])
    (let-values ([(nfx* others) (partition known-non-char?  others)])
      (cond
        [(not (null? nfx*)) (interrupt)]
        [(null? others)     (nop)]
        [else
         (interrupt-unless 
           (tag-test (or* (T (car others)) (cdr others)) char-mask char-tag))]))))

(define (char-fold-p op a a*)
  (seq*
    (assert-chars a a*)
    (let f ([a a] [a* a*])
      (cond
        [(null? a*) (K #t)]
        [else
         (let ([b (car a*)])
           (make-conditional
             (prm op (T a) (T b))
             (f b (cdr a*))
             (K #f)))]))))


(define-primop char=? safe
  [(P) (interrupt)]
  [(P a . a*) (char-fold-p '= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-chars a a*)])

(define-primop char<? safe
  [(P) (interrupt)]
  [(P a . a*) (char-fold-p '< a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-chars a a*)])

(define-primop char<=? safe
  [(P) (interrupt)]
  [(P a . a*) (char-fold-p '<= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-chars a a*)])

(define-primop char>? safe
  [(P) (interrupt)]
  [(P a . a*) (char-fold-p '> a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-chars a a*)])

(define-primop char>=? safe
  [(P) (interrupt)]
  [(P a . a*) (char-fold-p '>= a a*)]
  [(E) (interrupt)]
  [(E a . a*) (assert-chars a a*)])

/section)

(section ;;; bytevectors
         
(define-primop bytevector? safe
  [(P x) (tag-test (T x) bytevector-mask bytevector-tag)]
  [(E x) (nop)])

(define-primop $make-bytevector unsafe
  [(V n)
   (struct-case n
     [(constant n)
      (unless (fx? n) (interrupt))
      (with-tmp ([s (prm 'alloc 
                      (K (align (+ n 1 disp-bytevector-data)))
                      (K bytevector-tag))])
         (prm 'mset s
             (K (- disp-bytevector-length bytevector-tag))
             (K (* n fx-scale)))
         (prm 'bset s
             (K (+ n (- disp-bytevector-data bytevector-tag)))
             (K 0))
         s)]
     [(known expr t)
      (cogen-value-$make-bytevector expr)]
     [else
      (with-tmp ([s (prm 'alloc 
                      (align-code 
                        (prm 'sra (T n) (K fx-shift))
                        (+ disp-bytevector-data 1))
                      (K bytevector-tag))])
          (prm 'mset s
            (K (- disp-bytevector-length bytevector-tag))
            (T n))
          (prm 'bset s
               (prm 'int+ 
                    (prm 'sra (T n) (K fx-shift))
                    (K (- disp-bytevector-data bytevector-tag)))
               (K 0))
          s)])]
  [(P n) (K #t)]
  [(E n) (nop)])

(define-primop $bytevector-length unsafe
  [(V x) (prm 'mref (T x) (K (- disp-bytevector-length bytevector-tag)))]
  [(P x) (K #t)]
  [(E x) (nop)])

(define-primop $bytevector-u8-ref unsafe
  [(V s i)
   (struct-case i
     [(constant i)
      (unless (fx? i) (interrupt))
      (prm 'sll
        (prm 'logand 
           (prm 'bref (T s)
             (K (+ i (- disp-bytevector-data bytevector-tag))))
           (K 255))
        (K fx-shift))]
     [else
      (prm 'sll
        (prm 'logand
           (prm 'bref (T s)
                (prm 'int+
                   (prm 'sra (T i) (K fx-shift))
                   (K (- disp-bytevector-data bytevector-tag))))
           (K 255))
        (K fx-shift))])]
  [(P s i) (K #t)]
  [(E s i) (nop)])

(define-primop $bytevector-s8-ref unsafe
  [(V s i)
   (struct-case i
     [(constant i)
      (unless (fx? i) (interrupt))
      (prm 'sra
        (prm 'sll
          (prm 'logand 
             (prm 'bref (T s)
               (K (+ i (- disp-bytevector-data bytevector-tag))))
             (K 255))
          (K (- (* wordsize 8) 8)))
        (K (- (* wordsize 8) (+ 8 fx-shift))))]
     [else
      (prm 'sra
        (prm 'sll
           (prm 'bref (T s)
                (prm 'int+
                   (prm 'sra (T i) (K fx-shift))
                   (K (- disp-bytevector-data bytevector-tag))))
           (K (- (* wordsize 8) 8)))
        (K (- (* wordsize 8) (+ 8 fx-shift))))])]
  [(P s i) (K #t)]
  [(E s i) (nop)])


(define-primop $bytevector-set! unsafe
  [(E x i c)
   (struct-case i
     [(constant i) 
      (unless (fx? i) (interrupt))
      (struct-case c
        [(constant c)
         (unless (fx? c) (interrupt))
         (prm 'bset (T x)
              (K (+ i (- disp-bytevector-data bytevector-tag)))
              (K (cond
                   [(<= -128 c 127) c]
                   [(<= 128 c 255) (- c 256)]
                   [else (interrupt)])))]
        [else
         (prm 'bset (T x)
               (K (+ i (- disp-bytevector-data bytevector-tag)))
               (prm 'sra (T c) (K fx-shift)))])]
     [else
      (struct-case c
        [(constant c)
         (unless (fx? c) (interrupt))
         (prm 'bset (T x) 
              (prm 'int+ 
                   (prm 'sra (T i) (K fx-shift))
                   (K (- disp-bytevector-data bytevector-tag)))
              (K (cond
                   [(<= -128 c 127) c]
                   [(<= 128 c 255) (- c 256)]
                   [else (interrupt)])))]
        [else
         (prm 'bset (T x)
              (prm 'int+ 
                   (prm 'sra (T i) (K fx-shift))
                   (K (- disp-bytevector-data bytevector-tag)))
              (prm 'sra (T c) (K fx-shift)))])])])

(define-primop $bytevector-ieee-double-native-ref unsafe
  [(V bv i)
   (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K flonum-tag))
     (prm 'fl:load 
       (prm 'int+ (T bv) (prm 'sra (T i) (K fx-shift)))
       (K (- disp-bytevector-data bytevector-tag)))
     (prm 'fl:store x (K (- disp-flonum-data vector-tag)))
     x)])


;;; the following uses unsupported sse3 instructions
;(define-primop $bytevector-ieee-double-nonnative-ref unsafe
;  [(V bv i)
;   (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
;     (prm 'mset x (K (- vector-tag)) (K flonum-tag))
;     (prm 'fl:load 
;       (prm 'int+ (T bv) (prm 'sra (T i) (K fx-shift)))
;       (K (- disp-bytevector-data bytevector-tag)))
;     (prm 'fl:shuffle
;       (K (make-object '#vu8(7 6 2 3 4 5 1 0)))
;       (K (- disp-bytevector-data bytevector-tag)))
;     (prm 'fl:store x (K (- disp-flonum-data vector-tag)))
;     x)])

(define-primop $bytevector-ieee-double-nonnative-ref unsafe
  [(V bv i)
   (case wordsize
     [(4)
      (let ([bvoff (- disp-bytevector-data bytevector-tag)]
            [floff (- disp-flonum-data vector-tag)])
        (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
          (prm 'mset x (K (- vector-tag)) (K flonum-tag))
          (with-tmp ([t (prm 'int+ (T bv) 
                           (prm 'sra (T i) (K fx-shift)))])
            (with-tmp ([x0 (prm 'mref t (K bvoff))])
              (prm 'bswap! x0 x0)
              (prm 'mset x (K (+ floff wordsize)) x0))
            (with-tmp ([x0 (prm 'mref t (K (+ bvoff wordsize)))])
              (prm 'bswap! x0 x0)
              (prm 'mset x (K floff) x0)))
          x))]
     [else
      (let ([bvoff (- disp-bytevector-data bytevector-tag)]
            [floff (- disp-flonum-data vector-tag)])
        (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
          (prm 'mset x (K (- vector-tag)) (K flonum-tag))
          (with-tmp ([t (prm 'int+ (T bv) 
                           (prm 'sra (T i) (K fx-shift)))])
            (with-tmp ([x0 (prm 'mref t (K bvoff))])
              (prm 'bswap! x0 x0)
              (prm 'mset x (K floff) x0)))
          x))])])


(define-primop $bytevector-ieee-double-native-set! unsafe
  [(E bv i x)
   (seq*
     (prm 'fl:load (T x) (K (- disp-flonum-data vector-tag)))
     (prm 'fl:store
       (prm 'int+ (T bv) (prm 'sra (T i) (K fx-shift)))
       (K (- disp-bytevector-data bytevector-tag))))])


(define-primop $bytevector-ieee-single-native-ref unsafe
  [(V bv i)
   (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
     (prm 'mset x (K (- vector-tag)) (K flonum-tag))
     (prm 'fl:load-single
       (prm 'int+ (T bv) (prm 'sra (T i) (K fx-shift)))
       (K (- disp-bytevector-data bytevector-tag)))
     (prm 'fl:single->double)
     (prm 'fl:store x (K (- disp-flonum-data vector-tag)))
     x)])

(define-primop $bytevector-ieee-single-native-set! unsafe
  [(E bv i x)
   (seq*
     (prm 'fl:load (T x) (K (- disp-flonum-data vector-tag)))
     (prm 'fl:double->single)
     (prm 'fl:store-single
       (prm 'int+ (T bv) (prm 'sra (T i) (K fx-shift)))
       (K (- disp-bytevector-data bytevector-tag))))])

(define-primop $bytevector-ieee-single-nonnative-ref unsafe
  [(V bv i)
   (let ([bvoff (- disp-bytevector-data bytevector-tag)]
         [floff (- disp-flonum-data vector-tag)])
     (with-tmp ([x (prm 'alloc (K (align flonum-size)) (K vector-tag))])
       (prm 'mset x (K (- vector-tag)) (K flonum-tag))
       (with-tmp ([t (prm 'int+ (T bv) (prm 'sra (T i) (K fx-shift)))])
         (with-tmp ([x0 (prm 'mref t (K bvoff))])
           (prm 'bswap! x0 x0)
           (prm 'mset x (K floff) x0)))
       (prm 'fl:load-single x (K (+ floff (- wordsize 4))))
       (prm 'fl:single->double)
       (prm 'fl:store x (K floff))
       x))])


;;; the following uses unsupported sse3 instructions
;(define-primop $bytevector-ieee-double-nonnative-set! unsafe
;  [(E bv i x)
;   (seq*
;     (prm 'fl:load (T x) (K (- disp-flonum-data vector-tag)))
;     (prm 'fl:shuffle
;       (K (make-object '#vu8(7 6 2 3 4 5 1 0)))
;       (K (- disp-bytevector-data bytevector-tag)))
;     (prm 'fl:store
;       (prm 'int+ (T bv) (prm 'sra (T i) (K fx-shift)))
;       (K (- disp-bytevector-data bytevector-tag))))])

(define-primop $bytevector-ieee-double-nonnative-set! unsafe
  [(E bv i x)
   (case wordsize
     [(4)
      (let ([bvoff (- disp-bytevector-data bytevector-tag)]
            [floff (- disp-flonum-data vector-tag)])
        (with-tmp ([t (prm 'int+ (T bv)
                         (prm 'sra (T i) (K fx-shift)))])
          (with-tmp ([x0 (prm 'mref (T x) (K floff))])
            (prm 'bswap! x0 x0)
            (prm 'mset t (K (+ bvoff wordsize)) x0))
          (with-tmp ([x0 (prm 'mref (T x) (K (+ floff wordsize)))])
            (prm 'bswap! x0 x0)
            (prm 'mset t (K bvoff) x0))))]
     [else
      (let ([bvoff (- disp-bytevector-data bytevector-tag)]
            [floff (- disp-flonum-data vector-tag)])
        (with-tmp ([t (prm 'int+ (T bv)
                         (prm 'sra (T i) (K fx-shift)))])
          (with-tmp ([x0 (prm 'mref (T x) (K floff))])
            (prm 'bswap! x0 x0)
            (prm 'mset t (K bvoff) x0))))])])

(define-primop $bytevector-ieee-single-nonnative-set! unsafe
  [(E bv i x)
   (let ([bvoff (- disp-bytevector-data bytevector-tag)]
         [floff (- disp-flonum-data vector-tag)])
     (seq*
       (prm 'fl:load (T x) (K floff))
       (prm 'fl:double->single)
       (with-tmp ([t (prm 'int+ (T bv)
                        (prm 'sra (T i) (K fx-shift)))])
         (prm 'fl:store-single t (K bvoff))
         (case wordsize
           [(4)
            (with-tmp ([x0 (prm 'mref t (K bvoff))])
              (prm 'bswap! x0 x0)
              (prm 'mset t (K bvoff) x0))]
           [else
            (with-tmp ([x0 (prm 'mref32 t (K bvoff))])
              (prm 'bswap! x0 x0)
              (prm 'mset32 t (K bvoff) (prm 'sra x0 (K 32))))]))))])
/section)

(section ;;; strings
         
(define-primop string? safe
  [(P x) (tag-test (T x) string-mask string-tag)]
  [(E x) (nop)])

(define-primop $make-string unsafe
  [(V n)
   (struct-case n
     [(constant n)
      (unless (fx? n) (interrupt))
      (with-tmp ([s (prm 'alloc 
                      (K (align (+ (* n wordsize) disp-string-data)))
                      (K string-tag))])
         (prm 'mset s
             (K (- disp-string-length string-tag))
             (K (* n fx-scale)))
         s)]
     [(known expr) 
      (cogen-value-$make-string expr)]
     [else
      (with-tmp ([s (prm 'alloc 
                      (align-code (T n) disp-string-data)
                      (K string-tag))])
          (prm 'mset s
            (K (- disp-string-length string-tag))
            (T n))
          s)])]
  [(P n) (K #t)]
  [(E n) (nop)])

(define-primop $string-length unsafe
  [(V x) (prm 'mref (T x) (K (- disp-string-length string-tag)))]
  [(P x) (K #t)]
  [(E x) (nop)])


(define-primop $string-ref unsafe
  [(V s i)
   (struct-case i
     [(constant i)
      (unless (fx? i) (interrupt))
      (prm 'mref32 (T s)
        (K (+ (* i char-size) 
              (- disp-string-data string-tag))))]
     [else
      (prm 'mref32 (T s)
        (prm 'int+ 
          (cond 
            [(= wordsize char-size) (T i)]
            [(= wordsize 8) (prm 'sra (T i) (K 1))]
            [else (error '$string-ref "invalid operand")])
          (K (- disp-string-data string-tag))))])]
  [(P s i) (K #t)]
  [(E s i) (nop)])

(define assert-fixnum 
  (case-lambda 
    [(x)
     (struct-case x
       [(constant i) 
        (if (fx? i) (nop) (interrupt))]
       [(known expr t)
        (case (T:fixnum? t)
          [(yes) (nop)]
          [(no)  (interrupt)]
          [else  (assert-fixnum expr)])]
       [else (interrupt-unless (cogen-pred-fixnum? x))])]))

(define (assert-string x)
  (struct-case x
    [(constant s) (if (string? s) (nop) (interrupt))]
    [(known expr t)
     (case (T:string? t)
       [(yes) (record-optimization 'assert-string x) (nop)]
       [(no)  (interrupt)]
       [else  (assert-string expr)])]
    [else (interrupt-unless (cogen-pred-string? x))]))

(define-primop string-ref safe
  [(V s i)
   (seq*
     (assert-fixnum i)
     (assert-string s)
     (interrupt-unless (prm 'u< (T i) (cogen-value-$string-length s)))
     (cogen-value-$string-ref s i))]
  [(P s i)
   (seq*
     (assert-fixnum i)
     (assert-string s)
     (interrupt-unless (prm 'u< (T i) (cogen-value-$string-length s)))
     (K #t))]
  [(E s i)
   (seq*
     (assert-fixnum i)
     (assert-string s)
     (interrupt-unless (prm 'u< (T i) (cogen-value-$string-length s))))])

(define-primop $string-set! unsafe
  [(E x i c)
   (struct-case i
     [(constant i) 
      (unless (fx? i) (interrupt))
      (prm 'mset32 (T x) 
         (K (+ (* i char-size) 
               (- disp-string-data string-tag)))
         (T c))]
     [else
      (prm 'mset32 (T x) 
         (prm 'int+ 
              (cond
                [(= wordsize char-size) (T i)]
                [(= wordsize 8) (prm 'sra (T i) (K 1))]
                [else (error '$string-set! "invalid operand")])
              (K (- disp-string-data string-tag)))
         (T c))])])

/section)

(section ;;; ports

(define-primop port? safe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag port-mask port-tag)]
  [(E x) (nop)])

;(define-primop input-port? safe
;  [(P x) (sec-tag-test (T x) vector-mask vector-tag #f input-port-tag)]
;  [(E x) (nop)])
;
;(define-primop output-port? safe
;  [(P x) (sec-tag-test (T x) vector-mask vector-tag #f output-port-tag)]
;  [(E x) (nop)])
(define port-attrs-shift 6)

(define-primop $make-port unsafe
  [(V attrs idx sz buf tr id read write getp setp cl cookie)
   (with-tmp ([p (prm 'alloc (K (align port-size)) (K vector-tag))])
     (prm 'mset p (K (- vector-tag))
          (prm 'logor (prm 'sll (T attrs) (K port-attrs-shift)) (K port-tag)))
     (prm 'mset p (K (- disp-port-index vector-tag)) (T idx))
     (prm 'mset p (K (- disp-port-size vector-tag)) (T sz))
     (prm 'mset p (K (- disp-port-buffer vector-tag)) (T buf))
     (prm 'mset p (K (- disp-port-transcoder vector-tag)) (T tr))
     (prm 'mset p (K (- disp-port-id vector-tag)) (T id))
     (prm 'mset p (K (- disp-port-read! vector-tag)) (T read))
     (prm 'mset p (K (- disp-port-write! vector-tag)) (T write))
     (prm 'mset p (K (- disp-port-get-position vector-tag)) (T getp))
     (prm 'mset p (K (- disp-port-set-position! vector-tag)) (T setp))
     (prm 'mset p (K (- disp-port-close vector-tag)) (T cl))
     (prm 'mset p (K (- disp-port-cookie vector-tag)) (T cookie))
     (prm 'mset p (K (- disp-port-unused1 vector-tag)) (K 0))
     (prm 'mset p (K (- disp-port-unused2 vector-tag)) (K 0))
     p)])

(define-primop $port-index unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-index vector-tag)))])
(define-primop $port-size unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-size vector-tag)))])
(define-primop $port-buffer unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-buffer vector-tag)))])
(define-primop $port-transcoder unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-transcoder vector-tag)))])
(define-primop $port-id unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-id vector-tag)))])
(define-primop $port-read! unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-read! vector-tag)))])
(define-primop $port-write! unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-write! vector-tag)))])
(define-primop $port-get-position unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-get-position vector-tag)))])
(define-primop $port-set-position! unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-set-position! vector-tag)))])
(define-primop $port-close unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-close vector-tag)))])
(define-primop $port-cookie unsafe
  [(V x) (prm 'mref (T x) (K (- disp-port-cookie vector-tag)))])
(define-primop $port-attrs unsafe
  [(V x) 
   (prm 'sra
     (prm 'mref (T x) (K (- disp-port-attrs vector-tag)))
     (K port-attrs-shift))])
(define-primop $port-tag unsafe
  [(V x)
   (make-conditional 
     (tag-test (T x) vector-mask vector-tag)
     (with-tmp ([tag 
                 (prm 'mref (T x) (K (- disp-port-attrs vector-tag)))])
       (make-conditional 
         (tag-test tag port-mask port-tag)
         (prm 'sra tag (K port-attrs-shift))
         (K 0)))
     (K 0))])

(define-primop $set-port-index! unsafe
  [(E x i) (prm 'mset (T x) (K (- disp-port-index vector-tag)) (T i))])
(define-primop $set-port-size! unsafe
  [(E x i) (prm 'mset (T x) (K (- disp-port-size vector-tag)) (T i))])
(define-primop $set-port-attrs! unsafe
  [(E x i) 
   (prm 'mset (T x)
     (K (- disp-port-attrs vector-tag)) 
     (prm 'logor (prm 'sll (T i) (K port-attrs-shift)) (K port-tag)))])


/section)

(section ;;; interrupts-and-engines

(define-primop $interrupted? unsafe
  [(P) (prm '!= (prm 'mref pcr (K pcb-interrupted)) (K 0))])

(define-primop $unset-interrupted! unsafe
  [(E) (prm 'mset pcr (K pcb-interrupted) (K 0))])

(define-primop $do-event safe
  [(E) 
   (begin
     (interrupt)
     (prm 'incr/zero? pcr (K pcb-engine-counter) 
          (K (fxsll 1 fx-shift))))])

(define-primop $swap-engine-counter! unsafe
  [(V x) 
   ;;; FIXME: should be atomic swap instead of load and set!
   (with-tmp ([x0 (T x)])
     (with-tmp ([t (prm 'mref pcr (K pcb-engine-counter))])
       (prm 'mset pcr (K pcb-engine-counter) x0)
       t))])

(define-primop $stack-overflow-check unsafe
  [(E) 
   (make-shortcut 
     (make-conditional 
       (make-primcall 'u< 
         (list esp (make-primcall 'mref
                     (list pcr (make-constant pcb-frame-redline)))))
       (make-primcall 'interrupt '())
       (make-primcall 'nop '()))
     (make-forcall "ik_stack_overflow" '()))])

/section)

(section ;;; control operations

(define-primop $fp-at-base unsafe
  [(P)
   (prm '= (prm 'int+
                (prm 'mref pcr (K pcb-frame-base)) 
                (K (- wordsize))) 
        fpr)])

(define-primop $current-frame unsafe
  [(V) (prm 'mref pcr (K pcb-next-continuation))])


(define-primop $seal-frame-and-call unsafe
  [(V x) ;;; PCB NEXT CONT;;; PCB BASE
   (with-tmp ([k (prm 'alloc (K continuation-size) (K vector-tag))])
     (with-tmp ([base (prm 'int+
                           (prm 'mref pcr (K pcb-frame-base)) 
                           (K (- wordsize)))])
       (with-tmp ([underflow-handler (prm 'mref base (K 0))])
         (prm 'mset k (K (- vector-tag)) (K continuation-tag))
         (prm 'mset k (K (- disp-continuation-top vector-tag)) fpr)
         (prm 'mset k (K (- disp-continuation-next vector-tag)) 
              (prm 'mref pcr (K pcb-next-continuation))) 
         (prm 'mset k (K (- disp-continuation-size vector-tag)) (prm 'int- base fpr))
         (prm 'mset pcr (K pcb-next-continuation) k)
         (prm 'mset pcr (K pcb-frame-base) fpr)
         (prm '$call-with-underflow-handler underflow-handler (T x) k))))]
  [(E . args) (interrupt)]
  [(P . args) (interrupt)])

(define-primop $frame->continuation unsafe
  [(V x)
   (with-tmp ([t (prm 'alloc
                    (K (align (+ disp-closure-data wordsize)))
                    (K closure-tag))])
     (prm 'mset t (K (- disp-closure-code closure-tag))
          (K (make-code-loc (sl-continuation-code-label))))
     (prm 'mset t (K (- disp-closure-data closure-tag))
          (T x))
     t)]
  [(P x) (K #t)]
  [(E x) (nop)])

(define-primop $make-call-with-values-procedure unsafe
  [(V) (K (make-closure 
            (make-code-loc (sl-cwv-label))
            '() #f))]
  [(P) (interrupt)]
  [(E) (interrupt)])

(define-primop $make-values-procedure unsafe
  [(V) (K (make-closure 
            (make-code-loc (sl-values-label)) 
            '() #f))]
  [(P) (interrupt)]
  [(E) (interrupt)])

(define-primop $make-annotated-procedure unsafe
  [(V annotation proc) 
   (let ([off (- disp-closure-code closure-tag)])
     (with-tmp ([t (prm 'alloc 
                      (K (align (+ disp-closure-data (* 2 wordsize))))
                      (K closure-tag))])
       (prm 'mset t (K (- disp-closure-code closure-tag))
            (K (make-code-loc (sl-annotated-procedure-label))))
       (prm 'mset t (K (- disp-closure-data closure-tag))
            (T annotation))
       (prm 'mset t (K (- (+ disp-closure-data wordsize) closure-tag))
            (T proc))
       t))]
  [(P) (interrupt)]
  [(E) (interrupt)])
  
(define-primop $annotated-procedure-annotation unsafe
  [(V proc) 
   (prm 'mref (T proc) 
     (K (- disp-closure-data closure-tag)))])


/section)

(section ;;; hash table tcbuckets

(define-primop $make-tcbucket unsafe
  [(V tconc key val next)
   (with-tmp ([x (prm 'alloc (K (align tcbucket-size)) (K vector-tag))])
     (prm 'mset x (K (- disp-tcbucket-tconc vector-tag)) (T tconc))
     (prm 'mset x (K (- disp-tcbucket-key vector-tag)) (T key))
     (prm 'mset x (K (- disp-tcbucket-val vector-tag)) (T val))
     (prm 'mset x (K (- disp-tcbucket-next vector-tag)) (T next))
     x)])

(define-primop $tcbucket-key unsafe
  [(V x) (prm 'mref (T x) (K (- disp-tcbucket-key vector-tag)))])
(define-primop $tcbucket-val unsafe
  [(V x) (prm 'mref (T x) (K (- disp-tcbucket-val vector-tag)))])
(define-primop $tcbucket-next unsafe
  [(V x) (prm 'mref (T x) (K (- disp-tcbucket-next vector-tag)))])

(define-primop $set-tcbucket-key! unsafe
  [(E x v) (mem-assign v (T x) (- disp-tcbucket-key vector-tag))])
(define-primop $set-tcbucket-val! unsafe
  [(E x v) (mem-assign v (T x) (- disp-tcbucket-val vector-tag))])
(define-primop $set-tcbucket-next! unsafe
  [(E x v) (mem-assign v (T x) (- disp-tcbucket-next vector-tag))])
(define-primop $set-tcbucket-tconc! unsafe
  [(E x v) (mem-assign v (T x) (- disp-tcbucket-tconc vector-tag))])


/section)

(section ;;; codes

(define-primop code? unsafe
  [(P x) (sec-tag-test (T x) vector-mask vector-tag #f code-tag)])

(define-primop $closure-code unsafe
  [(V x) 
   (prm 'int+ 
        (prm 'mref (T x) (K (- disp-closure-code closure-tag)))
        (K (- vector-tag disp-code-data)))])

(define-primop $code-freevars unsafe
  [(V x) (prm 'mref (T x) (K (- disp-code-freevars vector-tag)))])

(define-primop $code-reloc-vector unsafe
  [(V x) (prm 'mref (T x) (K (- disp-code-relocsize vector-tag)))])

(define-primop $code-size unsafe
  [(V x) (prm 'mref (T x) (K (- disp-code-instrsize vector-tag)))])

(define-primop $code-annotation unsafe
  [(V x) (prm 'mref (T x) (K (- disp-code-annotation vector-tag)))])

(define-primop $code->closure unsafe
  [(V x) 
   (with-tmp ([v (prm 'alloc
                    (K (align (+ 0 disp-closure-data)))
                    (K closure-tag))])
     (prm 'mset v 
          (K (- disp-closure-code closure-tag))
          (prm 'int+ (T x) 
            (K (- disp-code-data vector-tag))))
     v)])

(define-primop $code-ref unsafe
  [(V x i) 
   (prm 'sll
     (prm 'logand
          (prm 'bref (T x)
               (prm 'int+
                    (prm 'sra (T i) (K fx-shift))
                    (K (- disp-code-data vector-tag))))
          (K 255))
     (K fx-shift))])

(define-primop $code-set! unsafe
  [(E x i v)
   (prm 'bset (T x)
        (prm 'int+ 
             (prm 'sra (T i) (K fx-shift))
             (K (- disp-code-data vector-tag)))
        (prm 'sra (T v) (K fx-shift)))])

(define-primop $set-code-annotation! unsafe
  [(E x v) (mem-assign v (T x) (- disp-code-annotation vector-tag))])

/section)

(section ; transcoders

(define-primop transcoder? unsafe
  [(P x) (tag-test (T x) transcoder-mask transcoder-tag)])

(define-primop $data->transcoder unsafe
  [(V x) (prm 'logor
              (prm 'sll (T x) (K (- transcoder-payload-shift
                                    fx-shift)))
              (K transcoder-tag))])
(define-primop $transcoder->data unsafe
  [(V x) (prm 'sra (T x) (K (- transcoder-payload-shift fx-shift)))])
/section)

