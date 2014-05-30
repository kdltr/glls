;;;; glls.scm
;;;;
;;;; Methods and macros for defining, compiling, and deleting shaders and pipelines.
;;;; Pipelines are the name that we are using to refer to OpenGL "programs"
;;;; which is an unfortunately vague term.

(module glls
  (make-pipeline
   pipeline-shaders
   pipeline-attributes
   pipeline-uniforms
   pipeline-program
   pipeline?
   create-pipeline
   define-pipeline
   define-shader
   create-shader
   compile-shader
   compile-pipeline
   compile-pipelines
   pipeline-uniform
   pipeline-attribute
   %delete-shader
   %delete-pipeline)

(import chicken scheme srfi-69 srfi-1 miscmacros)
(use glls-compiler (prefix opengl-glew gl:) matchable)
(import-for-syntax glls-compiler)

(reexport glls-compiler)

(begin-for-syntax
 (require-library glls-compiler))

(define-record pipeline
  shaders (setter attributes) (setter uniforms) (setter program))

(define-record-printer (pipeline p out)
  (fprintf out "#(pipeline ~S shaders:~S attributes:~S uniforms:~S)"
           (pipeline-program p) (map shader-type (pipeline-shaders p))
           (pipeline-attributes p) (pipeline-uniforms p)))

(define (%delete-shader shader)
  (gl:delete-shader (shader-program shader)))

(define (%delete-pipeline pipeline)
  (gl:delete-program (pipeline-program pipeline)))

(define-syntax define-shader
  (ir-macro-transformer
   (lambda (exp rename compare)
     (let* ([name (cadr exp)]
           [shader (%create-shader (strip-syntax (cddr exp)))]
           [shader-maker `(make-shader
                           ,(shader-type shader)
                           ,(shader-source shader) ',(shader-inputs shader)
                           ',(shader-outputs shader) ',(shader-uniforms shader)
                           0)])
       `(define ,name (set-finalizer! ,shader-maker %delete-shader))))))

(define (create-shader form)
  (set-finalizer! (%create-shader form) %delete-shader))

(define *pipelines* '())

(define (create-pipeline . shaders)
  (if (< (length shaders) 2)
      (syntax-error "Invalid pipeline definition:" shaders))
  (let* ([shaders (map (lambda (s)
                         (if (shader? s)
                             s
                             (create-shader s)))
                       shaders)]
         [attributes (apply append
                            (map shader-inputs
                                 (filter (lambda (s)
                                           (equal? (shader-type s) #:vertex))
                                         shaders)))]
         [uniforms (apply append (map shader-uniforms shaders))]
         [pipeline (make-pipeline shaders attributes uniforms 0)])
    (set! *pipelines* (cons pipeline *pipelines*))
    (set-finalizer! pipeline %delete-pipeline)
    pipeline))

(define-syntax define-pipeline
  (ir-macro-transformer
   (lambda (exp i compare)
     (if (< (length exp) 3)
         (syntax-error "Invalid pipeline definition:" exp))
     (let* ([new-shader? (lambda (s) (and (list? s)
                                   (= (length s) 5)
                                   (compare (cadddr s) '->)))]
            [shader-with-uniforms? (lambda (s) (and (list? s)
                                             (>= (length s) 2)
                                             (equal? (second s) uniform:)))]
            [name (cadr exp)]
            [shaders (map (lambda (s)
                            (cond
                             [(new-shader? s) (%create-shader s)]
                             [(shader-with-uniforms? s) (car s)]
                             [else s]))
                          (strip-syntax (cddr exp)))]
            [shader-makers (map (lambda (s)
                                  (if (shader? s)
                                      `(set-finalizer!
                                        (make-shader
                                         ,(shader-type s)
                                         ,(shader-source s) ',(shader-inputs s)
                                         ',(shader-outputs s) ',(shader-uniforms s)
                                         0)
                                        %delete-shader)
                                      s))
                                shaders)])
       (if (and (feature? csi:)
              (handle-exceptions e (begin #f) (eval name)))
           `(begin
              (define old-program (pipeline-program ,name))
              (define ,name
                (create-pipeline ,@shader-makers))
              (set! (pipeline-program ,name) old-program)
              (compile-pipelines))
           `(define ,name
              (create-pipeline ,@shader-makers)))))))


;;; GL compiling
(define (compile-shader shader)
  (define (shader-int-type shader)
    (ecase (shader-type shader)
           [(vertex:) gl:+vertex-shader+]
           [(tess-control:) gl:+tess-control-shader+]
           [(tess-evaluation:) gl:+tess-evaluation-shader+]
           [(geometry:) gl:+geometry-shader+]
           [(fragment:) gl:+fragment-shader+]
           [(compute:) gl:+compute-shader+]))
  (when (zero? (shader-program shader))
    (set! (shader-program shader) (gl:make-shader (shader-int-type shader) (shader-source shader)))))

(define (compile-pipeline pipeline)
  (for-each compile-shader (pipeline-shaders pipeline))
  (let* ([program (gl:make-program (map shader-program (pipeline-shaders pipeline))
                                   (if (> (pipeline-program pipeline) 0)
                                       (pipeline-program pipeline)
                                       (gl:create-program)))]
         [attribute-location
          (lambda (a)
            (match-let* ([(name . type) a]
                         [location (gl:get-attrib-location
                                    program
                                    (symbol->string (symbol->glsl name)))])
              (list name location type)))]
         [uniform-location
          (lambda (u)
            (match-let* ([(name . type) u]
                         [location (gl:get-uniform-location
                                    program
                                    (symbol->string (symbol->glsl name)))])
              (list name location type)))])
    (for-each (lambda (s)
                (gl:detach-shader program (shader-program s)))
              (pipeline-shaders pipeline))
    (set! (pipeline-program pipeline) program)
    (set! (pipeline-attributes pipeline)
      (map attribute-location (pipeline-attributes pipeline)))
    (set! (pipeline-uniforms pipeline)
      (map uniform-location (pipeline-uniforms pipeline)))))

(define (compile-pipelines)
  (for-each compile-pipeline *pipelines*)
  (set! *pipelines* '()))

;; Accessors
(define (pipeline-uniform uniform pipeline)
  (let ([u (assoc uniform (pipeline-uniforms pipeline))])
    (unless u
      (error 'pipeline-uniform "No such uniform" uniform))
    (when (< (length u) 3)
      (error 'pipeline-uniform "Pipeline has not been compiled" pipeline))
    (cadr u)))

(define (pipeline-attribute attr pipeline)
  (let ([a (assoc attr (pipeline-attributes pipeline))])
    (unless a
      (error 'pipeline-attribute "No such attribute" attr))
    (when (< (length a) 3)
      (error 'pipeline-attribute "Pipeline has not been compiled" pipeline))
    (cadr a)))

) ; module end
