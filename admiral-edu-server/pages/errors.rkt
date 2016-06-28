#lang racket/base

(require web-server/servlet
         racket/date
         racket/list
         racket/string)
(require "../logging.rkt"
         "../ct-session.rkt")
(require web-server/http/bindings
         web-server/templates
         web-server/http/response-structs
         xml
         json)

(provide not-authorized)
(define (not-authorized)
  (let ([display-message 
         (string-append 
          "You are not authorized to access this page. "
          "You may need to <a href='/authentication/redirect?logout=/logout.html'>logout</a> "
          "and log back in with a different account name.")])
(include-template "html/error.html")))

(provide assignment-closed)
(define (assignment-closed)
  "<p>The assignment you were attempting to access is currently closed.</p>")

(provide exception-occurred)
(define (exception-occurred exn)
  (if (exn? exn) (log-exception exn) (begin (printf "Caught: ~a\n" exn) (flush-output)))
  ;; TODO Recursively print out exception information
  ;; TODO Send email with exception output to self.
  (response/full
   200 #"Okay"
   (current-seconds) TEXT/HTML-MIME-TYPE
   empty
   (list (string->bytes/utf-8 "An error occurred while processing your request. This has been reported. Please try again later."))))

(define (log-exception exn)
  (let* ((message (exn-message exn))
         (marks (exn-continuation-marks exn))
         (stack (if (continuation-mark-set? marks) (continuation-mark-set->context marks) #f)))
    (printf "Caught Exception: ~a\n" exn)
    (printf "Message: ~a\n" message)
    (when stack (map print-stack-elem stack))
    (flush-output)))
                 
(define (print-stack-elem elem) 
  (let ((label (if (null? elem) "function-name???" (car elem)))
        (srcloc (if (and (not (null? elem)) (srcloc? (cdr elem))) (srcloc->string (cdr elem)) "No Source Location")))
  (printf "~a - ~a\n" label srcloc)))
                

(provide response-error)
(define (response-error message code status)
  (log-ct-error-info
   "[~a] ERROR: ~a"
   (date->string (current-date) #t)
   message)
  (response/full
   code status
   (current-seconds) TEXT/HTML-MIME-TYPE
   empty
   (list (string->bytes/utf-8 (error message)))))

(provide response-error/xexpr)
(define (response-error/xexpr xexpr code status)
  (response/xexpr
   #:code code
   #:message status
   xexpr))

(provide error)
(define (error message)
  (let ([display-message message])
    (include-template "html/error.html")))

(provide error-not-registered)
(define (error-not-registered session)
  `(html 
    (body 
     (h1 "Error") 
     (p "You are not registered for this class.")
     (p " You may need to "
        (a ((href "/authentication/redirect?logout=/logout.html")) " logout")
        " and reauthenticate with the correct account. You are currently"
        " logged in with the information below. If this information is correct"
        " you should contact your instructor.")
     (p , (string-append "User ID: " (ct-session-uid session)))
     (p , (string-append "Class ID: " (ct-session-class session))))))

(provide error-invalid-session)
(define error-invalid-session
  '(html
    (body
     (h1 "An Error Occurred")
     (p "This session is not valid. Try to log out and then log in again."))))

(provide four-oh-four)
(define (four-oh-four)
  (log-ct-error-info
   "[~a] ERROR: ~a"
   (date->string (current-date) #t)
   "404 not found")
  (response-error/xexpr four-oh-four-xexpr 404 "Not Found"))

(provide four-oh-four-xexpr)
(define four-oh-four-xexpr
  '((h2 "404 - The resource does not exist")))

(provide xexpr->error-page)
; (: xexpr->error-page ((Listof XExpr) -> String))
(define (xexpr->error-page xexpr)
  (let ([display-message (string-join (map xexpr->string xexpr) "\n")])
    (include-template "html/error.html")))

(provide error-page)
(define (error-page . message)
  (let ([display-message (apply string-append message)])
    (include-template "html/error.html")))
    