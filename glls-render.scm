(module glls-render (c-prefix
                     define-pipeline
                     export-pipeline)

(import scheme
(chicken base) (chicken keyword) (chicken module) (chicken syntax)

(prefix glls glls:) glls-renderable (prefix gl-utils gl:))

(import-for-syntax (chicken keyword) (chicken platform) srfi-1 (prefix glls glls:) (prefix glls-compiler glls:)
                   glls-renderable matchable miscmacros)

(reexport (except glls define-pipeline)
          (only glls-renderable
                renderable-size
                unique-textures?
                set-renderable-vao!
                set-renderable-n-elements!
                set-renderable-element-type!
                set-renderable-mode!
                set-renderable-offset!))

(begin-for-syntax
 (define c-prefix (make-parameter '||))
 (define header-included? (make-parameter #f)))

(define c-prefix (make-parameter '||)) ; Needs to be defined twice so it can be manipulated upon export (for some reason)

(define-syntax renderable-setters
  (ir-macro-transformer
   (lambda (exp i compare)
     (match exp
      ((_ name uniforms)
       (let ((base-name (symbol-append 'set- name '-renderable-)))
         `(begin
            ,@(let loop ((uniforms uniforms) (i 0))
                (if (null? uniforms)
                    '()
                    (cons `(define (,(symbol-append base-name (caar uniforms) '!)
                                    renderable value)
                             (set-renderable-uniform-value! renderable ,i value
                                                            ',(caar uniforms)))
                          (loop (cdr uniforms) (add1 i))))))))
       (exp (syntax-error 'renderable-setters "Bad arguments" exp))))))

(define-for-syntax (get-uniforms s)
  (cond
   ((and (list? s)
       (list? (car s))
       (member (caar s) glls:shader-types))
    (get-keyword uniform: (cdar s) (lambda () '())))
   ((and (list? s) (>= (length s) 2) (member #:uniform s))
    (cdr (member #:uniform s)))
   (else (syntax-error 'define-pipeline "Only shaders that include uniform definitions may be used with glls-render" s))))

(define-syntax define-renderable-functions
  (ir-macro-transformer
   (lambda (exp i compare)
     (match exp
       ((_ name . shaders)
        (let* ((name (strip-syntax name))
               (uniforms (delete-duplicates
                          (concatenate (map get-uniforms (strip-syntax shaders)))
                          (lambda (a b) (eq? (car a) (car b))))))
          (let-values (((render-funs render-fun-name
                                     render-arrays-fun-name
                                     fast-fun-begin-name
                                     fast-fun-name fast-fun-end-name
                                     fast-fun-arrays-name)
                        (if (feature? compiling:)
                            (render-functions (c-prefix) name uniforms)
                            (values #f #f #f #f #f #f #f))))
            `(begin
               ,(if (feature? compiling:)
                    `(begin
                       ,(if (not (header-included?))
                            (begin 
                              (header-included? #t)
                              `(begin
                                 (import (chicken foreign))
                                 (foreign-declare ,gllsRender.h)))
                            #f)
                       (foreign-declare ,render-funs)
                       (define ,(symbol-append 'render- name)
                         (foreign-lambda void ,render-fun-name c-pointer))
                       (define ,(symbol-append 'render-arrays- name)
                         (foreign-lambda void ,render-arrays-fun-name c-pointer))
                       (define (,(symbol-append name '-fast-render-functions))
                         (values
                          (foreign-lambda void ,(symbol->string fast-fun-begin-name)
                                          c-pointer)
                          (foreign-lambda void ,(symbol->string fast-fun-name)
                                          c-pointer)
                          (foreign-lambda void ,(symbol->string fast-fun-end-name))
                          (foreign-lambda void ,(symbol->string fast-fun-arrays-name)
                                          c-pointer)
                          (foreign-value ,(string-append
                                           "&" (symbol->string fast-fun-begin-name))
                                         c-pointer)
                          (foreign-value ,(string-append
                                           "&" (symbol->string fast-fun-name))
                                         c-pointer)
                          (foreign-value ,(string-append
                                           "&" (symbol->string fast-fun-end-name))
                                         c-pointer)
                          (foreign-value ,(string-append
                                           "&" (symbol->string fast-fun-arrays-name))
                                         c-pointer))))
                    `(begin
                       (define (,(symbol-append 'render- name) renderable)
                         (render-renderable ',uniforms renderable #f))
                       (define (,(symbol-append 'render-arrays- name) renderable)
                         (render-renderable ',uniforms renderable #t))))
               (define (,(symbol-append 'make- name '-renderable) . args)
                 (apply make-renderable ,name args))
               (renderable-setters ,name ,uniforms)))))
       (expr (syntax-error 'define-pipeline "Invalid pipeline definition" expr))))))

(define-syntax define-pipeline
  (syntax-rules ()
    ((_ name  shaders ...)
     (begin (glls:define-pipeline name shaders ...)
            (define-renderable-functions name shaders ...)))
    ((_ . expr) (syntax-error 'define-pipeline "Invalide pipeline definition" expr))))

(define-syntax export-pipeline
  (ir-macro-transformer
   (lambda (expr i c)
     (cons 'export
           (flatten
            (let loop ((pipelines (cdr expr)))
              (if (null? pipelines)
                  '()
                  (if (not (symbol? (car pipelines)))
                      (syntax-error 'export-shader "Expected a pipeline name" expr)
                      (cons (let* ((name (strip-syntax (car pipelines)))
                                   (render (symbol-append 'render- name))
                                   (make-renderable (symbol-append 'make- name
                                                                   '-renderable))
                                   (fast-funs (symbol-append name
                                                             '-fast-render-functions)))
                              (list name render make-renderable fast-funs))
                            (loop (cdr pipelines)))))))))))


) ; glls-render
