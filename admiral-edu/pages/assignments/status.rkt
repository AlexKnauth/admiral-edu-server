#lang typed/racket/base

(require racket/match
         racket/list
         racket/string
         "../../database/mysql/typed-db.rkt"
         "../../base.rkt"
         "../../paths.rkt"
         "../path-xexprs.rkt"
         "../../authoring/assignment.rkt"
         "../typed-xml.rkt"
         "../responses.rkt"
         (prefix-in error: "../errors.rkt")
         (prefix-in action: "action.rkt"))

(provide load)
(: load (->* (ct-session (Listof String) (U XExpr #f)) (Boolean)
             Response))
;; FIXME flatten into top-level dispatch
(define (load session url message [post #f])
  (match url
    [(list assignment-id) (display-assignment session assignment-id message)]
    [(list assignment-id step-id) (display-step session assignment-id step-id message post)]
    [(list assignment-id step-id review-id) (display-review session assignment-id step-id review-id message post)]
    [_ (error:four-oh-four-response)]))


(: display-assignment (ct-session String (U XExpr #f) -> Response))
(define (display-assignment session assignment-id message)
  (let*: ((assignment (assignment-id->assignment assignment-id))
          [steps : (Listof XExpr) (list (cons 'ol (apply append (map (step->statistic session assignment-id) (Assignment-steps assignment)))))])
    ;; FIXME replace all xexprs->response with plain-page
    (xexprs->response
     (append (header session assignment-id message)
             steps))))


(: header (ct-session String (U XExpr #f) -> (Listof XExpr)))
(define (header session assignment-id message)
  (let* ((assignment (assignment-id->assignment assignment-id))
         (record (assignment:select (class-name) assignment-id))
         (open (assignment:Record-open record))
         (ready (assignment:Record-ready record))
         (status (if ready (if open "Open" "Closed") "Missing Dependencies")))
  `((h1 () ,(action:assignments session "Assignments"))
    (h2 () ,(action:dashboard session assignment-id assignment-id))
    (h3 () ,(action:status session assignment-id "Status") " : " ,status)
    ,(if message message ""))))

(: display-step (ct-session String String (U XExpr #f) Boolean ->
                            Response))
(define (display-step session assignment-id step-id message post)
  (let* ((message (if post (check-for-action assignment-id step-id session) #f))
         (order (get-order session))
         (sort-by (submission:get-sort-by session))
         (next-order (opposite-order order))
         (count (number->string (submission:count-step assignment-id (class-name) step-id)))
         (submission-records (submission:select-all assignment-id (class-name) step-id sort-by order)))
  (xexprs->response
   (append (header session assignment-id message)
           `((h4 (),step-id)
             (p () "Submissions : " ,count)
             (p () "Select a User ID to view their submission.")
             (h3 () "Student Submissions:")
             (h4 () "Global Actions")
             ,(publish-all-action)
             ,(unpublish-all-action))
           `(,(append-xexpr
               `(table ()
                       (tr ()
                           (th () ,(sort-by-action "user_id" next-order "Student ID"))
                           (th () ,(sort-by-action "last_modified" next-order "Last Modified"))
                           (th () ,(sort-by-action "published" next-order "Published"))
                           (th () "Actions")))
               (map (submission-record->xexpr session) submission-records)))
           `((h3 () "Students Pending Submission"))
           (list-no-submissions assignment-id step-id)))))

(: list-no-submissions (String String -> (Listof XExpr)))
(define (list-no-submissions assignment-id step-id)
  (let ((no-submission (submission:select-no-submissions assignment-id (class-name) step-id)))
    (cond [(empty? no-submission) '((p "No pending submissions."))]
          [else (let: ([f : (String -> XExpr) (lambda (uid) `(li () ,uid))])
                  (map f no-submission))])))


; (String Order String -> Xexpr)
(: sort-by-action (String Order String -> XExpr))
(define (sort-by-action field order context)
  (unless (basic-ct-id? field)
    (raise-argument-error
     'sort-by-action
     "basic-ct-id"
     0 field))
  (define order-str (symbol->string order))
  (unless (basic-ct-id? order-str)
    (raise-argument-error
     'sort-by-action
     "basic-ct-id"
     0 order))
  `(a ((href ,(string-append "?sort-by=" field "&order=" order-str)))
      ,context))

(: submission-record->xexpr (ct-session -> (submission:Record -> XExpr)))
(define ((submission-record->xexpr session) record)
  (let ((user-id (submission:Record-user record))
        (last_modified (format-time-stamp (submission:Record-last-modified record)))
        (published (if (submission:Record-published record) "Yes" "No"))
        (actions (if (submission:Record-published record) (unpublish-action record) (publish-action record))))
                     
    `(tr () 
         (td () ,(view-submission-action session record user-id))
         (td () ,last_modified)
         (td () ,published)
         (td () ,actions))))

(: unpublish-all-action ( -> XExpr))
(define (unpublish-all-action)
    `(form ((method "post"))
           (input ((type "hidden") (name "action") (value "unpublish-all")))           
           (p (input ((type "submit") (value "Unpublish All"))) " - All submissions for this step will be marked Unpublished. This will not modify timestamps. If a student chooses to update their submission, their timestamp will be updated.")))

(: publish-all-action ( -> XExpr))
(define (publish-all-action)
    `(form ((method "post"))
           (input ((type "hidden") (name "action") (value "publish-all")))
           (p (input ((type "submit") (value "Publish All"))) " - All submissions for this step will be marked Published. This will not modify timestamps.")))

(: unpublish-action (submission:Record -> XExpr))
(define (unpublish-action record)
  (let ((user-id (submission:Record-user record)))
    `(form ((method "post"))
           (input ((type "hidden") (name "action") (value "unpublish")))
           (input ((type "hidden") (name "user-id") (value ,user-id)))
           (input ((type "submit") (value "Unpublish"))))))

(: publish-action (submission:Record -> XExpr))
(define (publish-action record)
  (let ((user-id (submission:Record-user record)))
    `(form ((method "post"))
           (input ((type "hidden") (name "action") (value "publish")))
           (input ((type "hidden") (name "user-id") (value ,user-id)))
           (input ((type "submit") (value "Publish"))))))

(: view-submission-action (ct-session submission:Record String -> XExpr))
(define (view-submission-action session record user-id)
  (let ((user (submission:Record-user record))
        (assignment (submission:Record-assignment record))
        (step (submission:Record-step record)))
    (cta `((href ,(ct-url-path session "su" user "browse" assignment step)))
         user-id)))



(: format-time-stamp (TimeStamp -> XExpr))
(define (format-time-stamp time-stamp)
  (let ((year (number->string (TimeStamp-year time-stamp)))
        (month (number->string (- (TimeStamp-month time-stamp) 1)))
        (day (number->string (TimeStamp-day time-stamp)))
        (hour (number->string (TimeStamp-hour time-stamp)))
        (minute (ensure-leading-zero (number->string (TimeStamp-minute time-stamp))))
        (second (ensure-leading-zero (number->string (TimeStamp-second time-stamp)))))
    ;; is this even legal? yikes.
    `(script
      ,(string-join
        `(,(string-append "var d = new Date(Date.UTC("year "," month "," day "," hour "," minute "," second ", 0));")
          "document.write(d.toLocaleDateString() + \" \" + d.toLocaleTimeString());")
        "\n"))))
;    (string-append month " " day " " year " " hour ":" minute ":" second)))


(: ensure-leading-zero (String -> String))
(define (ensure-leading-zero str)
  (let ((len (string-length str)))
  (cond [(= len 1) (string-append "0" str)]
        [else str])))


(: month->string (Exact-Nonnegative-Integer -> String))
(define (month->string month)
  (match month
    [1 "January"]
    [2 "February"]
    [3 "March"]
    [4 "April"]
    [5 "May"]
    [6 "June"]
    [7 "July"]
    [8 "August"]
    [9 "September"]
    [10 "October"]
    [11 "November"]
    [12 "December"]
    [_ (raise-argument-error 'month->string "number in [0..11]" 0 month)]))


    


(: display-review (ct-session String String String (U XExpr #f) Boolean
                              -> Response))
(define (display-review session assignment-id step-id review-id message post)
  (let* ((message (if post (check-for-action assignment-id step-id session) #f))
         (assigned (number->string (review:count-all-assigned-reviews assignment-id (class-name) step-id review-id)))
         (completed (number->string (review:count-completed-reviews assignment-id (class-name) step-id review-id)))
         (sort-by (review:get-sort-by session))
         (order (get-order session))
         (next-order (opposite-order order))
         (review-records (review:select-all assignment-id (class-name) step-id review-id sort-by order))
         (reviews (apply append (map (review-record->xexpr session) review-records))))
    (xexprs->response
     (append (header session assignment-id message)
             `((h4 () ,step-id " > " ,review-id)
               (p () "Assigned : " ,assigned)
               (p () "Completed : " ,completed)
               (p () "Selecting a students ID will bring you to the students view of a review."))
             `(,(append-xexpr `(table ()
                                      (th () ,(sort-by-action review:reviewer-id next-order "Reviewer ID"))
                                      (th () ,(sort-by-action review:reviewee-id next-order "Reviewee ID"))
                                      (th () ,(sort-by-action review:completed next-order "Completed"))
                                      (th () ,(sort-by-action review:flagged next-order "Flagged"))
                                      (th () ,(sort-by-action review:feedback-viewed-time-stamp next-order "Feedback Viewed"))
                                      (th () "Actions"))
                              reviews))))))



(: review-record->xexpr (ct-session -> (review:Record -> (Listof XExpr))))
(define ((review-record->xexpr session) record)
  (let* ((reviewee (review:Record-reviewee-id record))
         (reviewer (review:Record-reviewer-id record))
         (feedback (review:Record-feedback-viewed-time-stamp record))
         (feedback-viewed (if (Null? feedback) "Never" (format-time-stamp feedback)))
         (completed (if (review:Record-completed record) "Yes" ""))
         (actions (if (review:Record-completed record) 
                      (mark-incomplete-action record "Mark Incomplete") 
                      (mark-complete-action record "Mark Complete")))
         (flagged (review:Record-flagged record)))
  `((tr ()
     (td () ,(view-review-action session record reviewer))
     (td () ,(view-feedback-action session record reviewee))
     (td () ,completed)
     (td () ,(if flagged '(b "FLAGGED") ""))
     (td () ,feedback-viewed)
     (td () ,actions)))))


(: mark-incomplete-action (review:Record XExpr -> XExpr))
(define (mark-incomplete-action record context)
  (let ((hash (review:Record-hash record)))
    `(form ((method "post"))
           (input ((type "hidden") (name "action") (value "mark-incomplete")))
           (input ((type "hidden") (name "review-hash") (value ,hash)))
           (input ((type "submit") (value "Mark Incomplete"))))))


(: mark-complete-action (review:Record XExpr -> XExpr))
(define (mark-complete-action record context)
  (let ((hash (review:Record-hash record)))
    `(form ((method "post"))
           (input ((type "hidden") (name "action") (value "mark-complete")))
           (input ((type "hidden") (name "review-hash") (value ,hash)))
           (input ((type "submit") (value "Mark Complete"))))))



(: check-for-action (String String ct-session -> XExpr))
(define (check-for-action assignment-id step-id session)
  (let ((action (get-binding 'action session)))
    (printf "Checking for action: ~a\n" action)
    (cond [(Failure? action) `(p () (b () ,(Failure-message action)))]
          [else (do-action assignment-id step-id (Success-result action) session)])))


(: do-action (String String String ct-session -> XExpr))
(define (do-action assignment-id step-id action session)
  (printf "performing action: ~a\n" action)
  (cond [(string=? action "mark-incomplete") (do-mark-incomplete session)]
        [(string=? action "mark-complete") (do-mark-complete session)]
        [(string=? action "publish") (do-publish assignment-id step-id session)]
        [(string=? action "unpublish") (do-unpublish assignment-id step-id session)]
        [(string=? action "unpublish-all") (do-unpublish-all assignment-id step-id)]
        [(string=? action "publish-all") (do-publish-all assignment-id step-id)]
        [else `(p () (b () "No such action: " ,action))]))

(: do-publish-all (String String -> XExpr))
(define (do-publish-all assignment-id step-id)
  (let* ((unpublished (submission:select-all-unpublished assignment-id (class-name) step-id))
         (do-submit (lambda: ([user-id : String]) (submit-step assignment-id step-id user-id)))
         (assignment-record (assignment:select (class-name) assignment-id))
         ;; Ensure the assignment is open so submissions can be processed
         (dont-care (when (not (assignment:Record-open assignment-record)) (assignment:open assignment-id (class-name))))
         (results (filter Failure? (map do-submit unpublished)))
         ;; Close the assignment if it was open
         (dont-care (when (not (assignment:Record-open assignment-record)) (assignment:close assignment-id (class-name)))))
    (cond [(empty? results) '(p (b "All Submissions Published."))]
          [else '(p (b ((style "color:red;")) "Some submissions could not be published."))])))

(: do-unpublish-all (String String -> XExpr))
(define (do-unpublish-all assignment-id step-id)
  (submission:unpublish-all assignment-id (class-name) step-id)
  '(p (b "All Submissions Unpublished.")))

(: do-publish (String String ct-session -> XExpr))
(define (do-publish assignment-id step-id session)
  (let ((user-id (get-binding 'user-id session))
        (assignment-record (assignment:select (class-name) assignment-id)))
    (cond [(Failure? user-id) `(p () (b () ,(Failure-message user-id)))]
          [else (begin
                  (when (not (assignment:Record-open assignment-record)) (assignment:open assignment-id (class-name)))
                  (submit-step assignment-id step-id (Success-result user-id))
                  (when (not (assignment:Record-open assignment-record)) (assignment:close assignment-id (class-name)))
                  '(p (b "Submission published.")))])))

(: do-unpublish (String String ct-session -> XExpr))
(define (do-unpublish assignment-id step-id session)
  (let ((user-id (get-binding 'user-id session)))
    (cond [(Failure? user-id) `(p () (b () ,(Failure-message user-id)))]
          [else (begin
                  (submission:unpublish assignment-id (class-name) step-id (Success-result user-id))
                  '(p (b "Submission unpublished.")))])))



(: do-mark-incomplete (ct-session -> XExpr))
(define (do-mark-incomplete session)
  (let ((hash (get-binding 'review-hash session)))
    (cond [(Failure? hash) `(p () (b () ,(Failure-message hash)))]
          [else (begin
                  (review:mark-incomplete (Success-result hash))
                  '(p (b "Review marked incomplete.")))])))


(: do-mark-complete (ct-session -> XExpr))
(define (do-mark-complete session)
  (let ((hash (get-binding 'review-hash session)))
    (cond [(Failure? hash) `(p () (b () ,(Failure-message hash)))]
          [else (begin
                  (review:mark-complete (Success-result hash))
                  '(p (b "Review marked complete.")))])))

(: view-review-action (ct-session review:Record XExpr -> XExpr))
(define (view-review-action session record context)
  (let ((hash (review:Record-hash record))
        (reviewer (review:Record-reviewer-id record)))
    (cond [(role:exists? (class-name) reviewer)
           (cta `((href ,(ct-url-path session "su" reviewer "review" hash)))
                context)]
          [else `(p () ,context)])))

(: view-feedback-action (ct-session review:Record XExpr -> XExpr))
(define (view-feedback-action session record context)
  (let ((hash (review:Record-hash record))
        (reviewee (review:Record-reviewee-id record)))
    (cond [(role:exists? (class-name) reviewee)
           (cta `((href ,(ct-url-path session "su" reviewee "feedback" "view" hash)))
                context)]
          [else `(p () ,context)])))


(: step->statistic (ct-session String -> (Step -> (Listof XExpr))))
(define (step->statistic session assignment-id)
  (lambda (step)
    (let*: ((step-id (Step-id step))
            (submissions (number->string (submission:count-step assignment-id (class-name) step-id)))
            [reviews : (Listof XExpr) (apply append (map (review->statistic session assignment-id step-id) (Step-reviews step)))])
      `((li () "Step : " ,(action:step-status session assignment-id step-id step-id))
        ,(append-xexpr `(ul () 
                           (li () "Submissions: " ,submissions))
                      reviews)))))


(: review->statistic (ct-session String String -> (Review -> (Listof XExpr))))
(define (review->statistic session assignment-id step-id)
  (lambda (review)
    (let* ((review-id (Review-id review))
           (completed (number->string (review:count-completed-reviews assignment-id (class-name) step-id review-id)))
           (assigned (number->string (review:count-all-assigned-reviews assignment-id (class-name) step-id review-id))))
      `((li () "Reviews : " ,(action:review-status session assignment-id step-id review-id review-id))
        (ul () 
         (li () "Completed: " ,completed)
         (li () "Assigned: " ,assigned))))))

(module+ test
  (require typed/rackunit)

  (check-equal? (month->string 7) "July")
  (check-exn #px"number in \\[0..11\\]" (λ () (month->string 1234))))