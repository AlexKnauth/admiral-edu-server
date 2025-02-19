#lang typed/racket/base

;; why not just use YAML or a plain s-expression for this?

;; FIXME just use an s-expression...

(require racket/file
         racket/string)
;; Given a Path-String and optionally a delimiter, parses the file line by line
;; Each line that contains the delimeter is parsed as a key (delim) value pair and
;; included in the returned HashTable. The first instance of the delimiter is used as a separator
(provide read-conf)
(: read-conf (->* (Path-String) (String) (HashTable String String)))
(define (read-conf file-path [delim "="])
  (let*: ([contents : String  (file->string file-path)]
          [lines : (Listof String) (filter (compose not comment?) (string-split contents "\n"))]
          [splits : (Listof (Listof String)) (map (lambda: ([s : String]) (string-split s delim)) lines)]
          [len-2 : (Listof (Listof String)) (filter (lambda: ([s : (Listof String)]) (> (length s) 1)) splits)]
          [result : (Listof (Pairof String String)) (map (lambda: ([x : (Listof String)]) (cons (car x) (string-join (cdr x) delim))) len-2)])
    (make-immutable-hash result)))

(: comment? (String -> Boolean))
(define (comment? line)
  (let ((trimmed (string-trim line)))
    (cond [(= (string-length trimmed) 0) #f]
          [(eq? (string-ref trimmed 0) #\#) #t]
          [else #f])))

;; what the heck is this for?
(: valid-config? (String -> Boolean))
(define (valid-config? path)
  #f)