#lang racket/base

(require racket/string
         "../paths.rkt"
         "../base.rkt")

; String -> (Listof (Either Success Failure))
; Takes a String such that each line is a uid to be added to the system
; Returns a list of Success/Failure where each success was added to the system
; and each Failure was not added. Each Failure provides a message as to why the uid
; could not be added.
(provide register-roster)
(define (register-roster data)
  (let* ((uids (map string-trim (string-split data "\n")))
         (report (map register-uid uids)))
    report))

; String -> Either Success Failure
; Takes a String uid and registers it as a student for the class.
(provide register-uid)
(define (register-uid uid)
  (let ((has-spaces (regexp-match? #px" " uid)))
    (cond [has-spaces
           (Failure
            (format
             "Received '~a' but User IDs may not contain spaces."
             uid))]
          [(not (ct-id? uid))
           (Failure
            (format
             "Received '~a' which is not a legal Captain Teach ID"
             uid))]
          [else
           (begin
             (when (not (user:exists? uid)) (user:create uid))
             (let ((registered (role:exists? (class-name) uid)))
               (cond [registered
                      (Failure
                       (format
                        "Received '~a' but User ID is already registered in the class."
                        uid))]
                     [else (begin
                             (role:associate (class-name) uid student-role)
                             (Success uid))])))])))

; String -> Either Success Failure
; Takes a String uid and removes the user from the class.
(provide drop-uid)
(define (drop-uid uid)
  (let ((do-action (lambda (clean-uid)
                     (role:delete (class-name) uid)
                     (Success uid))))
    (is-registered->run uid do-action)))

; String -> OneOf 'instructor-role, 'student-role, 'ta-role -> Either Success Failure
(provide change-role)
(define (change-role uid new-role)
  (let ((do-action (lambda (clean-uid)
                     (let ((action (cond [(eq? new-role 'instructor-role) (role:set-role (class-name) uid instructor-role)]
                                         [(eq? new-role 'student-role) (role:set-role (class-name) uid student-role)]
                                         [(eq? new-role 'ta-role) (role:set-role (class-name) uid ta-role)]
                                         [else #f])))
                       (if (not action) (Failure (format "Could not change role of '~a' to '~a': No such role" uid new-role))
                           (Success uid))))))
    (is-registered->run uid do-action)))
                           
                   

; UserId -> (Function: (UserId . Rest) -> Either Success Failure) -> Rest -> Either Success Failure
(define (is-registered->run uid f . args)
  (let* ((clean (string-trim uid))
         (exists? (role:exists? (class-name) clean)))
    (cond [(not exists?) (Failure (format "The User ID '~a' is not registered in the class." uid))]
          [else (apply f (cons clean args))])))