;; -*- Gerbil -*-
;;; © ober

(import
  :gerbil/gambit
  :std/crypto/cipher
  :std/crypto/etc
  :std/crypto/libcrypto
  :std/format
  :std/generic
  :std/generic/dispatch
  :std/iter
  :std/misc/list
  :std/misc/channel
  :std/misc/ports
  :std/net/address
  :std/net/request
  :std/pregexp
  :std/srfi/13
  :std/srfi/19
  :std/srfi/95
  :std/sugar
  :std/text/base64
  :std/text/json
  :std/text/utf8
  :ober/oberlib
  :std/text/yaml)

(export #t)

(def config-file "~/.confluence.yaml")
(declare (not optimize-dead-definitions))
(import (rename-in :gerbil/gambit/os (current-time builtin-current-time)))

(def program-name "confluence")

(def (convert markdown)
  (let-hash (load-config)
    (let* ((url (format "~a/rest/api/contentbody/convert/storage" .url))
	   (data (hash
		  ("value" markdown)
		  ("representation" "wiki")))
	   (results (do-post-generic
		     url
		     (default-headers .basic-auth)
		     (json-object->string data)))
	   (myjson (with-input-from-string results read-json)))
      (let-hash myjson
	(displayln .value)))))

(def (longtask last)
  (let-hash (load-config)
    (let* ((results (do-get-generic (format "~a/longtask" .url) default-headers)))
	   ;;(myjson (with-input-from-string results read-json)))
      (displayln (hash->list results)))))

(def (search query)
  (let-hash (load-config)
    (let* ((query (make-web-safe query))
	   (url (if (string-contains query "~")
		  (format "~a/rest/api/content/search?cql=~a" .url query)
		  (format "~a/rest/api/content/search?cql=text~~~a" .url query)))
	   (results (do-get-generic url (default-headers .basic-auth)))
	   (myjson (from-json results)))
      (let-hash myjson
	(displayln "| Title | id | Type |url|tinyurl| ")
	(displayln "|-|")
	(for (p .results)
	     (let-hash p
	       (let-hash ._links
		 (displayln
		  "|" ..title
		  "|" ..id
		  "|" ..type
		  "|" ....url .?webui
		  "|" ....url .?tinyui
		  "|"))))))))

(def (get id)
  (let-hash (load-config)
    (let* ((url (format "~a/rest/api/content/~a" .url id))
	   (results (do-get-generic url (default-headers .basic-auth)))
	   (myjson (with-input-from-string results read-json)))
      (displayln results))))
;; (let-hash myjson
;;   (displayln "| Title | id | Type |url|tinyurl| ")
;;   (displayln "|-|")
;;   (for-each
;; 	(lambda (p)
;; 	  (let-hash p
;; 	    (let-hash ._links
;; 	      (displayln "|"
;; 			 ..title "|"
;; 			 ..id "|"
;; 			 ..type "|"
;; 			 server .?webui "|"
;; 			 server .?tinyui "|"
;; 			 "|"))))
;; 	.results))))


(def (default-headers basic)
  [
   ["Accept" :: "*/*"]
   ["Content-type" :: "application/json"]
   ["Authorization" :: basic ]
   ])

(def (load-config)
  (let ((config (hash))
        (config-data (yaml-load config-file)))
    (unless (and (list? config-data)
                 (length>n? config-data 0)
                 (table? (car config-data)))
      (displayln (format "Could not parse your config ~a" config-file))
      (exit 2))
    (hash-for-each
     (lambda (k v)
       (hash-put! config (string->symbol k) v))
     (car config-data))
    (let-hash config
      (hash-put! config 'style (or .?style "org-mode"))
      (when .?secrets
	(let-hash (u8vector->object (base64-decode .secrets))
	  (let ((password (get-password-from-config .key .iv .password)))
	    (hash-put! config 'basic-auth (make-basic-auth ..?user password))
	    config))))))

(def (body id)
  (let-hash (load-config)
    (let* ((url (format "~a/rest/api/content/~a?expand=body.view&depth=all" .url id))
	   (results (do-get-generic url (default-headers .basic-auth)))
	   (myjson (with-input-from-string results read-json)))
      (let-hash myjson
	(let-hash .body
	  (let-hash .view
	    (displayln .value)))))))

(def (make-web-safe string)
  (let* ((output (pregexp-replace* " " string "%20")))
    output))

(def (config)
  (let-hash (load-config)
    (displayln "What is your password?: ")
    (let* ((password (read-password ##console-port)))
	   (cipher (make-aes-256-ctr-cipher))
	   (iv (random-bytes (cipher-iv-length cipher)))
	   (key (random-bytes (cipher-key-length cipher)))
	   (encrypted-password (encrypt cipher key iv password))
	   (enc-pass-store (u8vector->base64-string encrypted-password))
	   (iv-store (u8vector->base64-string iv))
	   (key-store (u8vector->base64-string key))
	   (secrets (base64-encode (object->u8vector
				    (hash
				     (password enc-pass-store)
				     (iv iv-store)
				     (key key-store))))))

      (displayln "Add the following lines to your " config-file)
      (displayln "secrets: " secrets)))

(def (get-password-from-config key iv password)
  (bytes->string
   (decrypt
    (make-aes-256-ctr-cipher)
    (base64-string->u8vector key)
    (base64-string->u8vector iv)
    (base64-string->u8vector password))))


;; old utils