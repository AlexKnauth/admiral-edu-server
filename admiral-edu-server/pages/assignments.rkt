#lang typed/racket/base

(require "../base.rkt"
         "typed-xml.rkt"
         "responses.rkt"
         (prefix-in error: "errors.rkt")
         (prefix-in dashboard: "assignments/dashboard.rkt")
         (prefix-in list: "assignments/list.rkt")
         (prefix-in action: "assignments/action.rkt")
         (prefix-in student-view: "assignments/student-view.rkt")
         (prefix-in status: "assignments/status.rkt"))

(provide load)
(: load (->* (ct-session (Listof String) Boolean) ((U XExpr #f))
             Response))
(define (load session url post [message #f])
    (cond [(can-edit? session) (show-instructor-view session url post message)]
          [else (student-view:load session url message post)]))

(: can-edit? (ct-session -> Boolean))
(define (can-edit? session)
  (let ((session-role (role session)))
    (roles:Record-can-edit session-role)))

(: role (ct-session -> roles:Record))
(define (role session)
  (let* ((class (ct-session-class session))
         (uid (ct-session-uid session))
         (result (role:select class uid)))
    result))

(: show-instructor-view
   (ct-session (Listof String) Boolean (U XExpr #f) -> Response))
(define (show-instructor-view session url post message)
  (let ((action (if (null? url) action:LIST (car url)))
        (rest-url (if (null? url) url (cdr url))))
    ((lookup-action-function action) session rest-url message post)))

(: no-such-action
   (Any -> (->* (ct-session (Listof String) (U XExpr #f)) (Boolean) Response)))
(define (no-such-action action)
  (lambda (_ __ ___ [____ #f])
    (error:error-xexprs->response
     `((p ,(format "The requested action ~a is not valid here." action)))
     400 #"Bad Request")))

(: action-functions
   (HashTable String (->* (ct-session (Listof String) (U XExpr #f)) (Boolean)
                          Response)))
(define action-functions
  (make-immutable-hash
   (list
    (cons action:LIST list:load)
    (cons action:DASHBOARD dashboard:load)
    (cons action:OPEN dashboard:open)
    (cons action:CLOSE dashboard:close)
    (cons action:DELETE dashboard:delete)
    (cons "status" status:load))))

(: lookup-action-function
   (String -> (->* (ct-session (Listof String) (U XExpr #f)) (Boolean)
                   Response)))
(define (lookup-action-function action)
  (cond [(hash-has-key? action-functions action) (hash-ref action-functions action)]
        [else (no-such-action action)]))

