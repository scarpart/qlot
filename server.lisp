(defpackage #:qlot/server
  (:use #:cl)
  (:import-from #:qlot/source
                #:*dist-base-url*
                #:prepare
                #:source-prepared
                #:url-path-for
                #:project.txt
                #:distinfo.txt
                #:releases.txt
                #:systems.txt
                #:archive)
  (:import-from #:qlot/parser
                #:prepare-qlfile)
  (:import-from #:qlot/tmp
                #:*tmp-directory*)
  (:import-from #:qlot/util
                #:*system-quicklisp-home*
                #:with-quicklisp-home)
  (:import-from #:alexandria
                #:when-let)
  (:export #:localhost
           #:start-server
           #:stop-server))
(in-package #:qlot/server)

(defvar *handler* nil)

(defun localhost (&optional (path ""))
  ;; Use PATH If PATH is an URL, not an URL path.
  (when (and (< 0 (length path))
             (not (char= (aref path 0) #\/)))
    (return-from localhost path))
  (format nil "qlot://localhost~A" path))

#+quicklisp
(defun qlot-fetch (url file &key (follow-redirects t) quietly (maximum-redirects 10))
  "Request URL and write the body of the response to FILE."
  (declare (ignorable follow-redirects quietly maximum-redirects))
  (let ((result (funcall *handler* `(:path-info ,url))))
    (when (= (first result) 200)
      (typecase (third result)
        (list
         (with-open-file (o file :direction :output :if-exists :supersede)
           (format o "~A" (car (third result)))))
        (pathname
         (uiop:copy-file (third result) file)))))
  (values (make-instance 'ql-http::header :status 200)
          (probe-file file)))

(defun make-app (sources)
  (flet ((make-route (source action)
           (let ((action-name (symbol-name action)))
             (lambda ()
               (let* ((*dist-base-url* (localhost))
                      (res (funcall (symbol-function action) source)))
                 (list 200
                       (if (string-equal (subseq action-name (- (length action-name) 4))
                                         ".txt")
                           (list :content-type "text/plain")
                           '())
                       (if (stringp res)
                           (list res)
                           res)))))))
    (let ((route (make-hash-table :test 'equal))
          (tmp-directory *tmp-directory*))
      (dolist (source sources)
        (setf (gethash (localhost (url-path-for source 'project.txt)) route)
              (lambda ()
                (let ((*tmp-directory* tmp-directory))
                  (prepare source))
                (dolist (action '(project.txt distinfo.txt releases.txt systems.txt archive))
                  (when-let (path (url-path-for source action))
                    (setf (gethash (localhost path) route)
                          (make-route source action))))
                (funcall (make-route source 'project.txt)))))
      (lambda (env)
        (with-quicklisp-home *system-quicklisp-home*
          (let ((fn (gethash (getf env :path-info) route))
                (*tmp-directory* tmp-directory))
            (if fn
                (funcall fn)
                '(404 (:content-type "text/plain") ("Not Found")))))))))

(defgeneric start-server (sources)
  (:method ((sources list))
    #+quicklisp
    (let ((x "qlot"))
      (setf ql-http:*fetch-scheme-functions*
            (acons x 'qlot-fetch
                   (remove x ql-http:*fetch-scheme-functions* :key 'first :test 'equal))))
    (setf *handler* (make-app sources)))
  (:method ((qlfile pathname))
    (start-server (prepare-qlfile qlfile))))

(defun stop-server ()
  (setf *handler* nil))
