;;;
;;; Copyright (c) 1992, 1993, 1994 Carnegie Mellon University
;;; All Rights Reserved.
;;;
;;; See COPYRIGHT file for further information.
;;;

(in-package :nesl-lisp)

(defparameter *max-print-length* 10)
(defparameter *max-streams* 20)
(defparameter *sleep-factor* 5)
(defparameter *stream-array* (make-array *max-streams*))
(defparameter *free-streams* 
  (do ((l nil (cons i l))
       (i 3 (+ i 1)))
      ((= i *max-streams*) (reverse l))))
(setf (svref *stream-array* 0) *standard-input*)
(setf (svref *stream-array* 2) *standard-output*)


(defconstant *min_int* most-negative-fixnum)
(defconstant *max_int* most-positive-fixnum)
(defconstant *min_float* most-negative-double-float)
(defconstant *max_float* most-positive-double-float)




(defmacro add-primitive (name value type other)
  `(let ((vname (setq-var ,name ,value *defs* ,type)))
     (setq *defs* (cons (make-binding :name ,name :value vname
				    :type ,type
				    :original-code ,other) *defs*))))


(defmacro add-primitive-fn (fn defs)
 `(let 
      ((name (func-name ,fn))
       (value (func-body ,fn))
       (type (func-type ,fn)))
    (cons (make-binding :name name :value (compile nil value)
			:type type :original-code ,fn) ,defs)))



(defun add-prim-functions (defs filename)
  (let ((func-list (lisp-file filename t)))
    (do ((list func-list (cdr list)))
	((null list) defs)
	(let* ((curr-fn (car list)))
	  (setq defs (add-primitive-fn curr-fn defs))))
    defs))


(defun add-other-functions (defs filename)
  (declare (special *load-error* *curr-lisp-code* *curr-checklist*))
  (let ((obj-file (concatenate 'string filename *obj-tailer*))
	(src-file (concatenate 'string filename ".lnesl"))
	(lsp-file (concatenate 'string filename ".nlsp")))
    (setq *load-error* nil)
    (if (and (probe-file obj-file)
	     (> (file-write-date obj-file)
		(file-write-date src-file)))
	(progn
	  (format t "Fast loading ~a~%" obj-file)
	  (catch 'nload-error 
	    (load obj-file))
	  (if *load-error* 
	      (progn 
		(delete-file obj-file)
		(add-other-functions defs filename))
	    *defs*))
      (progn
	(format t "loading ~a~%" src-file)
	(setq *curr-lisp-code* nil)
	(setq *curr-checklist* nil)
	(let* ((instr-list (lisp-file src-file nil))
	       (old-defs defs)
	       (new-defs 
		(dolist (curr-instr instr-list defs)      
			(multiple-value-bind (new-defs value type var) 
					 (eval-toplevel curr-instr defs t 
							old-defs)
					 (setq defs new-defs)))))
	  (with-open-file (outstr lsp-file :direction :output
				  :if-exists :supersede 
				  :if-does-not-exist :create)
			  (write-to-str `(in-package :nesl-lisp) outstr)
			  (write-to-str `(check-types 
			    ',(extract-types-values *curr-checklist* old-defs)
			    *defs*) outstr)
			  (dolist (code *curr-lisp-code*)
				  (write-to-str code outstr)))
	  (compile-file lsp-file :output-file obj-file)
	  new-defs)))))


(defun nesl-or (a b) (or a b))
(defun nesl-and (a b) (and a b))
(defun nesl-xor (a b) (not (eql a b)))
(defun max-char (a b) (if (char> a b) a b))
(defun min-char (a b) (if (char< a b) a b))

(defun get-nesl-type (a) 
  (typecase a
	    (integer  'int)
	    (float 'float)
	    (character  'char)
	    (cons (list 'pair (get-nesl-type (first a)) 
			(get-nesl-type (second a))))
	    (nesl-seq (nesl-seq-type a))
	    (datatype (datatype-name a))
	    (t 'bool)))


(defun get-nesl-type2 (a) 
  (typecase a
	    (integer  'int)
	    (float 'float)
	    (character  'char)
	    (cons (list 'pair (get-nesl-type2 (first a)) 
			(get-nesl-type2 (second a))))
	    (nesl-seq (nesl-seq-type a))
	    (datatype (datatype-type a))
	    (t 'bool)))


(defun unify-func (type arg-type) 
  (let* ((match-type (list 'function (make-variable 'any) 
			(make-variable 'any) arg-type))
	(func-type (instantiate-type type)))
    (unify match-type func-type nil)
    (clean-type func-type nil)))
    
	

(defun datatype-var (name type value others)
  (let* ((value (if others (list value others) value))
	(arg-type (get-nesl-type2 value))
	(func-type (first (unify-func type arg-type)))
	(res-type (third func-type))
	(arg-type (fourth func-type)))
    (make-datatype :name name :value value :type res-type 
		   :arg-type (list arg-type))))

(defun char-vect (str)
  (make-nesl-seq :len (length str) :value (coerce str 'simple-vector)
		 :type '(vector char)))

(defun char-list (vect)
  (coerce (nesl-seq-value vect) 'list))


(defun read-delim (len str delim &optional no-hang)
  (if (zerop len) (list (char-vect nil) (list 0 (list #\  t)))
    (do* ((next-char t (if no-hang (read-char-no-hang str nil nil)
			 (read-char str nil nil)))
	  (ret-val nil (cons next-char ret-val))
	  (l len (- l 1)))
	(nil)
	(cond 
	 ((eq l 0) (return (list (char-vect (reverse ret-val)) 
				 (list 0 (list #\  t)))))
	 ((not next-char) 
	  (return (list (char-vect (reverse (cdr ret-val))) 
			(list (+ l 1) (list #\  t)))))
	 ((member next-char delim) 
	  (return (list (char-vect (reverse (cdr ret-val)))
			(list (+ l 1) (list next-char nil)))))
	 (t nil)))))
      
    

(defun nullstream ()
  (make-datatype :name 'stream :value -1 :type '(stream) :arg-type '(int)))

(defun assign-new-stream (str flag)
  (if (not flag) (list (nullstream) (list (char-vect "") flag))
    (if (null  *free-streams*) 
	(let ((temp (close str))) 
	  (declare (ignore temp))
	  (list (nullstream) 
		(list (char-vect ": Too many streams open.") nil)))
      (let ((str-index (first *free-streams*)))
	(setq *free-streams* (cdr *free-streams*))
	(setf (svref *stream-array* str-index) str)
	(list str-index (list (char-vect "") flag))))))
		
(defun new-stream-check ()
  (not (null *free-streams*)))

(defun flush-str (str)
   (let ((stream (svref *stream-array* (datatype-value str))))
     (if (output-stream-p stream) (finish-output stream))))

(defun create-str (index)
  (if (null index) nil
  (make-datatype :name 'stream :value index)))
 
(defun lookup-stream (str-index)
  (let* ((str-index (datatype-value str-index))
	 (str (if (array-in-bounds-p *stream-array* str-index) 
	       (svref *stream-array* str-index) nil)))
    str))


(defun is-nullstr (stream)
  (let ((str-index (datatype-value stream)))
    (eql str-index -1)))


(defun free-stream (str-index)
  (let* ((str-index (datatype-value str-index))
	 (file-stream (if (and (array-in-bounds-p *stream-array* str-index)
			       (> str-index 2))
			  (svref *stream-array* str-index) nil)))
    (if file-stream 
	(progn 
	  (setq *free-streams* (cons str-index *free-streams*))
	  (setf (svref *stream-array* str-index) nil)
	  file-stream)
      nil)))


(defun prim-read-object (str)
  (multiple-value-bind (obj err) 
		       (nesl-ignore-errors (read str nil nil))
		       (list obj (not err))))



