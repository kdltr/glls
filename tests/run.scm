(use test glls-compiler)

(test-group "renaming"
  (test 'gl_Position (symbol->glsl 'gl:position))
  (test 'floatBitsToUint (symbol->glsl 'float-bits-to-uint)))

(test-group "expressions"
  (test "vec4(position, 0.0, 1.0);\n" (compile-expr '(vec4 position 0.0 1.0)))
  (test "1 + 2;\n" (compile-expr '(+ 1 2)))
  (test "vec4(position, 0.0, (0.5 + x + y));\n"
        (compile-expr '(vec4 position 0.0 (+ 0.5 x y))))
  (test "position.xyz;\n"
        (compile-expr '(swizzle position x y z)))
  (test "array.length();\n"
        (compile-expr '(length array)))
  (test "if (i == 0) {\n    foo = 4;\n    bar = 5;\n} else {\n    foo = 4.0;\n}\n"
        (compile-expr '(if (= i 0) 
                           (begin (set! foo 4) (set! bar 5))
                           (set! foo 4.0))))
  (test "int foo;\nint bar = 4;\nvec4 quox[];\nvec4 baz[4];\nvec4 box[4] = 1(3, 3, 4);\nif (foo == 1) {\n    foo = 4;\n}\n"
        (compile-expr '(let ((foo #:int)
                             (bar #:int 4)
                             (quox (#:array #:vec4))
                             (baz (#:array #:vec4 4))
                             (box (#:array #:vec4 4) (1 3 3 4)))
                         (cond ((= foo 1) (set! foo 4))))))
  (test "if (x < 0) {\n    y = 1;\n} else if (x < 5) {\n    y = 2;\n} else {\n    y = 3;\n}\n"
        (compile-expr '(cond
                        ((< x 0) (set! y 1))
                        ((< x 5) (set! y 2))
                        (else (set! y 3)))))
  (test "vec3 foo (int x[], int y) {\n    x = y;\n    return bar;\n}\n"
        (compile-expr '(define (foo (x (in: #:int)) (y #:int)) #:vec3
                  (set! x y)
                  bar)))
  (test "for (i = 0; (< i 5); ++i) {\n    foo(i);\n}\n"
        (compile-expr '(dotimes (i 5)
                                (foo i))))
  (test "while ((< i 4)) {\n    if (thing) {\n        break;\n    }\n    foo(i);\n}\n"
        (compile-expr '(while (< i 4)
                         (if thing (break))
                         (foo i))))
  (test  "#version 330\n\nin vec2 vertex;\nin vec3 color;\nout vec3 c;\nuniform mat4 viewMatrix;\nvoid main () {\n    gl_Position = viewMatrix * vec4(vertex, 0.0, 1.0);\n    c = color;\n}\n"
        (compile-glls
         '(#:vertex ((vertex #:vec2) (color #:vec3) #:uniform (view-matrix #:mat4))
                    (define (main) #:void
                      (set! gl:position (* view-matrix (vec4 vertex 0.0 1.0)))
                      (set! c color))
                    -> ((c #:vec3)))))
  (test-error (compile-expr '(let ((foo (#:array #:int 4) (1 2))))))

  (test "vec4(position, 0.0, 1.0);\n"
        (compile-expr '(vec4 position 0.0 1.0)))
  (test "for (i = 2; (< i 4); ++i) {\n    break;\n}\n"
        (compile-expr '(dotimes (i 2 4) (break))))
  (test "for (i = 0; (< i 4); ++i) {\n    break;\n}\n"
        (compile-expr '(for (set! i 0) (< i 4) (++ i) (break))))
  (test "struct name {\n    int x;\n    int y[];\n};\n"
        (compile-expr '(record foo (x int) (y (array: int)))))
  (test "int x = 4;\nint y;\ny = 1;\nx + y;\n"
        (compile-expr '(let ((x int 4) (y int)) (set! y 1) (+ x y))))
  (test "int x = 4;\nx + 1;\n"
        (compile-expr '(let ((x int 4)) (+ x 1))))
  (test "int x;\nint y[];\nx + y;\n"
        (compile-expr '(let ((x int) (y (array: int))) (+ x y))))
  (test "int foo (int x, int y) {\n    return x + y;\n}\n"
        (compile-expr '(define (foo (x int) (y int)) int (+ x y))))
  (test "int foo () {\n    return 5;\n}\n"
        (compile-expr '(define (foo) int 5)))
  (test "int foo[5] = {1, 2, 3, 4, 5};\n"
        (compile-expr '(define foo (array: int 5) #(1 2 3 4 5)))))

(test-exit)
