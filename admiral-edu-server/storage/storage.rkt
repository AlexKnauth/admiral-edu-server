#lang typed/racket/base

(require racket/file
         racket/string
         racket/list
         racket/match
         "../configuration.rkt"
         "../util/basic-types.rkt"
         "../database/mysql.rkt"
         (prefix-in local: "local-storage.rkt")
         "../paths.rkt")

;; These are our file-system-sig types
;; FIXME converting path inputs from String to Path-String
;; as needed. The work is generally in cloud-storage,
;; where they're assumed to be strings.
(require/typed "storage-basic.rkt"
               [retrieve-file (Path-String -> String)]
               [retrieve-file-bytes (Path-String -> Bytes)]
               ; TODO: Revise from Any to some safe data type
               [write-file (String Any -> Void)]
               [delete-path (String -> Void)]
               [path-info (Path-String -> (U 'file 'directory 'does-not-exist))]
               [list-files (Path-String -> (Listof String))]
               [list-dirs (String -> (Listof String))]
               [list-sub-files (String -> (Listof String))])

;; FIXME: pass Ct-Paths to these

(provide retrieve-file 
         retrieve-file-bytes
         write-file 
         delete-path
         path-info
         list-files
         list-dirs
         list-sub-files)

(define success (Success (void)))

;; Start function definitions

;; Returns #t if the specified path is a file and #f otherwise.
(provide is-file?)
(: is-file? (String -> Boolean))
(define (is-file? path)
  (eq? 'file (path-info path)))


;; Returns #t if the specified path is a directory and #f otherwise.
(provide is-directory?)
(: is-directory? (Path-String -> Boolean))
(define (is-directory? path)
  (eq? 'directory (path-info path)))


;; class-id -> assignment-id -> step-id -> review-id -> string
;; The path to the default-rubric for the class, assignment, step-id, and review-id
(: default-rubric-path (String String String String -> String))
(define (default-rubric-path class assignment step-id review-id)
  (string-append class "/" assignment "/reviews/" step-id "/" review-id "/rubric.json"))


;; class-id -> assignment-id -> step-id -> review-id -> string
;; Given the class, assignment, step-id, review-id, returns a string of the default rubric.
(provide retrieve-default-rubric)
(: retrieve-default-rubric (String String String String -> String))
(define (retrieve-default-rubric class assignment step-id review-id)
  (retrieve-file (default-rubric-path class assignment step-id review-id)))

;; class-id -> assignment-id -> step-id -> string -> review-id -> void
;; Given the class, assignment, step, rubric, and review-id, saves the default rubric.
(provide create-default-rubric)
(: create-default-rubric (String String String String String -> Void))
(define (create-default-rubric class assignment step-id rubric review-id)
  (let ((path (default-rubric-path class assignment step-id review-id)))
    (write-file path rubric)))


(: assignment-description-path (String String -> String))
(define (assignment-description-path class-id assignment-id)
  (string-append class-id "/" assignment-id "/description.yaml"))


;; class-id -> assignment-id -> string -> void
;; Given the class, assignment, and description, writes the description for the assignment.
(provide save-assignment-description)
(: save-assignment-description (String String String -> Void))
(define (save-assignment-description class assignment description)
  (let ((path (assignment-description-path class assignment)))
    (write-file path description)))


;; class-id -> assignment-id -> string
;; Given the class and assignment, retrieves the stored assignment description
(provide retrieve-assignment-description)
(: retrieve-assignment-description (String String -> String))
(define (retrieve-assignment-description class assignment)
    (retrieve-file (assignment-description-path class assignment)))


;; class-id -> assignment-id -> step-id -> review-id -> reviewer-id -> reviewee-id -> string
;; Returns the path to the specified rubric
(: rubric-path (String String String String String String -> String))
(define (rubric-path class-id assignment-id step-id review-id reviewer reviewee)
  (string-append class-id "/" assignment-id "/reviews/" step-id "/" review-id "/" reviewer "/" reviewee "/rubric.json"))


;; class-id -> assignment-id -> step-id -> review-id -> reviewer -> reviewee -> string -> void
(provide save-rubric)
(: save-rubric (String String String String String String String -> Void))
(define (save-rubric class assignment step-id review-id reviewer reviewee data)
  (let ((path (rubric-path class assignment step-id review-id reviewer reviewee)))
    (write-file path data)))


(provide retrieve-rubric)
(: retrieve-rubric (String String String String String String -> String))
(define (retrieve-rubric class-id assignment-id step-id review-id reviewer-id reviewee-id)
  (let ((path (rubric-path class-id assignment-id step-id review-id reviewer-id reviewee-id)))
    ; If no rubric is found, copy the default-rubric
    (when (not (eq? 'file (path-info path))) 
      (begin
        (let ((default-rubric (retrieve-default-rubric class-id assignment-id step-id review-id)))
          (write-file path default-rubric))))
    
    (retrieve-file (rubric-path class-id assignment-id step-id review-id reviewer-id reviewee-id))))


;; class-id -> assignment-id -> step-id -> review-id -> reviewer-id -> reviewee-id -> file-path -> string
(: review-comments-path (String String String String String String String -> String))
(define (review-comments-path class-id assignment-id step-id review-id reviewer-id reviewee-id file-path)
  ;; FIXME icky path hacking
  (string-append class-id "/" assignment-id "/reviews/" step-id "/" review-id "/" reviewer-id "/" reviewee-id "/" (remove-leading-slash file-path) ".comments.json"))


;; class-id -> assignment-id -> step-id -> review-id -> reviewer-id -> reviewee-id -> file-path -> string -> void
(provide save-review-comments)
(: save-review-comments (String String String String String String String String -> Void))
(define (save-review-comments class assignment step-id review-id reviewer reviewee file-path data)
  ;; FIXME no validation of json shape
  (let ((path (review-comments-path class assignment step-id review-id reviewer reviewee file-path)))
    (write-file path data)))


(provide load-review-comments)
(: load-review-comments (String String String String String String String -> String))
(define (load-review-comments class-id assignment-id step-id review-id reviewer-id reviewee-id file-path)
  (let ((path (review-comments-path class-id assignment-id step-id review-id reviewer-id reviewee-id file-path)))
    (cond [(is-file? path) (retrieve-file path)]
          [else "{\"comments\" : {}}"])))

;; Returns the bytes of the file associated with the class, assignment, 
;; step, user, and path, or #f if the path doesn't refer to a file.
(provide maybe-get-file-bytes)
(: maybe-get-file-bytes (String String String String (U String
                                                        Ct-Path)
                                -> (U False Bytes)))
(define (maybe-get-file-bytes class assignment step uid path)
  ;; FIXME remove first cond clause and change to paths everywhere.
  (cond [(string? path)
         (define file-path (string-append
                            (submission-path/string class assignment uid step)
                            "/"
                            path))
         (match (path-info file-path)
           ['file
            (printf "Attempting to retrieve: ~a\n" file-path)
            (retrieve-file-bytes file-path)]
           [other
            #f])]
        [else
         (define file-path
           (ct-path->path
            (ct-path-join
             (submission-path class assignment uid step)
             path)))
         (match (path-info file-path)
           ['file
            (printf "Attempting to retrieve: ~a\n" file-path)
            (retrieve-file-bytes file-path)]
           [other
            #f])]))

;; class-id -> assignment-id user-id step-id
(provide submission-path)
(: submission-path (String String String String -> Ct-Path))
(define (submission-path class-id assignment-id user-id step-id)
  (rel-ct-path class-id assignment-id user-id step-id))

;; FIXME eliminate uses of this, replacing with submission-path
(: submission-path/string (String String String String -> String))
(define (submission-path/string class-id assignment-id user-id step-id)
  (path->string
   (ct-path->path (submission-path class-id assignment-id user-id step-id))))


;; given class, assignment, etc., construct the path at which the files live
(provide submission-file-path)
(: submission-file-path (String String String String (U String Ct-Path) -> Ct-Path))
(define (submission-file-path class-id assignment-id user-id step-id file-name)
  (ct-path-join (submission-path class-id assignment-id user-id step-id)
                ;; FIXME eliminate first branch when unneeded
                (cond [(string? file-name) (rel-ct-path file-name)]
                      [else file-name])))


; Uploads a dependency solution. If necessary, deletes the previous dependency that was uploaded 
(provide upload-dependency-solution)
(: upload-dependency-solution (String String String String String (U String Bytes) -> (Result Void)))
(define (upload-dependency-solution class-id user-id assignment-id step-id file-name file-content)
  (cond [(not (check-file-name file-name)) (Failure (format "Invalid filename ~a" file-name))]
        [else
         (let ((path (submission-path/string class-id assignment-id user-id step-id)))
           ;; Delete previously uploaded files
           (delete-path path)
           
           ;; Write to storage
           (let ((result (cond [(or (local:is-zip? file-name)
                                    (local:is-tar? file-name)) (do-unarchive-solution class-id user-id assignment-id step-id file-name file-content)]
                               [else (do-single-file-solution class-id user-id assignment-id step-id file-name file-content)])))
             ;; If necessary, create database entry
             (when (not (submission:exists? assignment-id class-id step-id user-id)) (submission:create-instructor-solution assignment-id class-id step-id user-id))
             result))]))

; Uploads a student submission.
(provide upload-submission)
(: upload-submission (String String String String String (U String Bytes) -> (Result Void)))
(define (upload-submission class-id user-id assignment-id step-id file-name file-content)
  (sdo
   (if (string=? file-name "") (Failure "expected nonempty filename") success)
   (let* ((exists (submission:exists? assignment-id class-id step-id user-id))
          (record (if exists (submission:select assignment-id class-id step-id user-id) #f))
          (published (if record (submission:Record-published record) #f)))
     (cond [(not (check-file-name file-name)) (Failure (format "Invalid filename ~a" file-name))]
           ;; Ensure the students has not finalized their submission
           [published (Failure "Submission already exists.")]
           [else (let ((path (submission-path/string class-id assignment-id user-id step-id)))
                   
                   ;; Delete previously uploaded files
                   (delete-path path)
                   
                   ;; Write to storage
                   (cond [(or (local:is-zip? file-name)
                              (local:is-tar? file-name)) (do-unarchive-solution class-id user-id assignment-id step-id file-name file-content)]
                         [else (do-single-file-solution class-id user-id assignment-id step-id file-name file-content)])
                   
                   ;; Create / update record
                   (when (not exists) (submission:create assignment-id class-id step-id user-id))
                   (submission:unpublish assignment-id class-id step-id user-id)
                   (submission:update-timestamp assignment-id class-id step-id user-id)
                   (Success (void)))]))))


(: do-unarchive-solution (String String String String String (U String Bytes) -> (Result Void)))
(define (do-unarchive-solution class-id user-id assignment-id step-id file-name file-content)
  (let* ((temp-dir (get-local-temp-directory))
         (file-path (build-path temp-dir file-name))
         (path (submission-path/string class-id assignment-id user-id step-id)))
    
    ;; Write the file out
    (local:write-file file-path file-content)
    
    ;; Unzip it
    (local:unarchive temp-dir file-path)
    
    ;; Remove the archive file
    (local:delete-path file-path)
    
    ;; Copy files to storage
    (let* ((file-names (local:list-sub-files temp-dir))
           ;; FIXME terrible way to do a "split-path"
           (len (string-length (path->string temp-dir)))
           (submission-file-name (lambda: ([file-name : String]) (string-append path (substring file-name len))))
           (handle-file (lambda: ([file-name : String]) 
                          (let* ((s-name (submission-file-name file-name))
                                 (data (file->bytes file-name)))
                            (write-file s-name data)))))
      ;; TODO: Potentially change write-file to return success / failure
      (map handle-file file-names))
    
    ;; Remove the temp directory
    (local:delete-path temp-dir)
    (Success (void))))

      
(: do-single-file-solution (String String String String String (U String Bytes) -> (Result Void)))
(define (do-single-file-solution class-id user-id assignment-id step-id file-name file-content)
  (let ((s-path (path->string
                 (ct-path->path
                  (submission-file-path class-id assignment-id user-id step-id file-name)))))
    (write-file s-path file-content)
    (Success (void))))

;; class-id -> assignment-id -> bytes?
;; Zips an assignment directory and returns the bytes
(provide export-assignment)
(: export-assignment (String String -> Bytes))
(define (export-assignment class-id assignment-id)
  (let* ((path (build-path class-id assignment-id))
         (temp-dir (get-local-temp-directory))
         (archive-name (string-append assignment-id ".zip"))
         (files (list-sub-files (path->string path)))
         (store-temp-file (lambda: ([file-name : String])
                            (let ((data (retrieve-file-bytes file-name)))
                              (local:write-file (build-path temp-dir file-name) data)))))
    ;; Store all files locally
    (map store-temp-file files)
    (local:rearrange-and-archive temp-dir class-id assignment-id archive-name)
    ;; Convert archive to bytes, delete temporary directory, and return archive's bytes
    (define data (local:retrieve-file-bytes (build-path temp-dir archive-name)))
    (delete-path (path->string temp-dir))
    data))


(: get-review-path (review:Record -> String))
(define (get-review-path review)
  (let* ((class (review:Record-class-id review))
         (assignment (review:Record-assignment-id review))
         (step (review:Record-step-id review))
         (review-id (review:Record-review-id review))
         (reviewer (review:Record-reviewer-id review))
         (reviewee (review:Record-reviewee-id review)))
    (string-append class "/" assignment "/reviews/" step "/" review-id "/" reviewer "/" reviewee "/")))


(: review-feedback-path (review:Record -> String))
(define (review-feedback-path review)
  (string-append (get-review-path review) "feedback.txt"))


;; review -> feedback-string -> void
;; Saves the feedback for the specified review
(provide save-review-feedback)
(: save-review-feedback (review:Record String -> Void))
(define (save-review-feedback review feedback)
  (let* ((path (review-feedback-path review)))
    (write-file path feedback)))


;; review -> string
;; Loads the feedback for the specified review
(provide load-review-feedback)
(: load-review-feedback (review:Record -> String))
(define (load-review-feedback review)
  (let* ((path (review-feedback-path review)))
    (cond [(is-file? path) (retrieve-file path)]
          [else ""])))

;; Utility functions
(: remove-leading-slash (String -> String))
(define (remove-leading-slash p)
  (cond [(string=? "" p) ""]
        [else (begin
                (let* ((fc (string-ref p 0))
                       (pp (if (eq? #\/ fc) (substring p 1) p)))
                  pp))]))



;; Creates a directory tmp/some-hash
(: get-local-temp-directory (-> Path))
(define (get-local-temp-directory)
  (build-path "tmp" (random-hash)))


;; Creates a random 32 hash
(: random-hash (-> String))
(define (random-hash)
  (for/fold ([s ""])
      ([x (in-range 32)])
    (string-append s
                   (number->string (truncate (random 15)) 16))))


;; Checks if a file-name is acceptable
;; Acceptable filenames include alphanumeric characters, underscore, dash, and period
;; that is, they must meet the regular expression #rx[a-zA-Z0-9_.-]*
;; Returns #t if the file-name is acceptable and #f otherwise.
(provide check-file-name)
(: check-file-name (String -> Boolean))
(define (check-file-name file-name)
  (let* ((okay-chars #rx"[a-zA-Z0-9_.\\ ()-]*"))
    (regexp-match-exact? okay-chars file-name)))


