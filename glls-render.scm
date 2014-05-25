(module glls-render (c-prefi
                     define-pipeline)

(import chicken scheme)
(use (prefix glls glls:) glls-renderable)
(import-for-syntax (prefix glls glls:) glls-renderable matchable)

(reexport (except glls define-pipeline))

(begin-for-syntax
 (require-library glls-renderable)
 (define c-prefix (make-parameter '||))
 (define header-included? (make-parameter #f)))

(define c-prefix (make-parameter '||)) ; Needs to be defined twice so it can be manipulated upon export (for some reason)

(define-syntax renderable-setters
  (ir-macro-transformer
   (lambda (exp i compare)
     (match exp
      [(_ name uniforms)
       (let ([base-name (symbol-append 'set- name '-renderable-)])
         `(begin
            (define (,(symbol-append base-name 'vao!) renderable vao)
              (set-renderable-vao! renderable vao))
            (define (,(symbol-append base-name 'n-elements!) renderable n)
              (set-renderable-n-elements! renderable n))
            (define (,(symbol-append base-name 'element-type!) renderable type)
              (set-renderable-element-type! renderable type))
            (define (,(symbol-append base-name 'mode!) renderable mode)
              (set-renderable-mode! renderable mode))
            (define (,(symbol-append base-name 'offset!) renderable offset)
              (set-renderable-offset! renderable offset))
            ,@(let loop ([uniforms uniforms] [i 0])
                (if (null? uniforms)
                    '()
                    (cons `(define (,(symbol-append base-name (caar uniforms) '!)
                                    renderable value)
                             (set-renderable-uniform-value! renderable ,i value))
                          (loop (cdr uniforms) [add1 i]))))))]
       [exp (syntax-error 'renderable-setters "Bad arguments" exp)]))))

(define-syntax define-renderable-functions
   (ir-macro-transformer
    (lambda (exp i compare)
      (if (not (and (= (length exp) 2)
                (symbol? (cadr exp))
                (glls:pipeline? (eval (cadr exp)))))
          (syntax-error 'define-renderable-functions "Expected the name of a pipeline"
                        exp))
      (let* ([name (strip-syntax [cadr exp])]
             [uniforms (glls:pipeline-uniforms (eval name))])
        (let-values ([(render-funs render-fun-name)
                      (if (feature? compiling:)
                          (render-functions (c-prefix) name uniforms)
                          (values #f #f))])
          `(begin
             ,(if (feature? compiling:)
                  `(begin
                     ,(if (not (header-included?))
                          (begin 
                            (header-included? #t)
                            `(foreign-declare ,gllsRender.h))
                          #f)
                     (foreign-declare ,render-funs)
                     (define ,(symbol-append 'render- name)
                       (foreign-lambda void ,render-fun-name c-pointer)))
                  `(define (,(symbol-append 'render- name) renderable)
                     (render-renderable ',uniforms renderable)))
             (define (,(symbol-append 'make- name '-renderable) . args)
               (apply make-renderable ,name args))
             (renderable-setters ,name ,uniforms)
             (print ,render-funs)))))))

 (define-syntax define-pipeline
   (syntax-rules ()
     [(_ name  shaders ...)
      (begin (use glls)
             (glls:define-pipeline name shaders ...)
             (define-renderable-functions name))]
     [(_ . expr) (syntax-error 'define-pipeline "Invalide pipeline definition" expr)]))

) ; glls-render