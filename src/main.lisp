;(ql:quickload "bifrost-yggdrasill")
;(ql:quickload "lparallel")
;(ql:quickload "filesystem-hash-table")
;(ql:quickload "log4cl")
(ql:quickload :log4cl.log4sly)
;(log4cl.log4sly:install)

(declaim (optimize (speed 0) (space 0) (debug 3)))
(defvar debug-mode t)

(in-package :xtce-engine)
(defparameter *TEST* (make-enumerated-parameter-type
 '|STC:CCSDS:Sequence-Flags-Type|
 :enumeration-list (list
					(make-enumeration #b00 'Continuation :short-description "Space Packet contains a continuation segment of User Data.")
					(make-enumeration #b01 'First-Segment :short-description "Space Packet contains the first segment of User Data.")
					(make-enumeration #b10 'Last-Segment :short-description "Space Packet contains the last segment of User Data.")
					(make-enumeration #b11 'Unsegmented :short-description "Space Packet is unsegmented."))))

; Generate and store speculative container match
; When container is called again, check for speculative match, then check against restriction criteria.
; When the full container match occurs, you win

;Fixed frames do not span, immediately move to next level
;Variable sized frames may span, need to move to accumulator (e.g. simulators)

(defun find-sync-pattern (frame sync-pattern &key (max-bit-errors 0) (aperture 0))
  ; Need to double check if aperture does what we think it does
  "Use to check for a synchronized frame.

   Args:
     frame (hex): the frame to check for synchronization pattern.
     sync-pattern (sync-pattern): sync-pattern type.
     max-errors (positive-integer): Maximum number of bit errors (inclusive) for a match to occur.
     
  Returns:
    hex: Frame truncated from the left up to the start of the container (i.e. truncate synchronization marker + start of container)
    nil: No synchronization marker was found. "

  (with-slots (pattern pattern-length-in-bits bit-location-from-start mask mask-length-bits) sync-pattern
	(let* ((truncated-mask (if (and mask mask-length-bits)
							   (truncate-from-left-to-size mask mask-length-bits)
							   pattern))
		   
		   (truncated-pattern (if pattern-length-in-bits
								  (truncate-from-left-to-size pattern pattern-length-in-bits)
								  pattern))
		   (speculative-match (ldb-left pattern-length-in-bits aperture frame))
		   
		   (match? (logand speculative-match truncated-mask))
		   (error-count (hamming-distance truncated-pattern match?))
		   (frame-truncation (+ 1 bit-location-from-start pattern-length-in-bits aperture)))
	  (when (<= error-count max-bit-errors)
		(truncate-from-left frame frame-truncation)))))

;(find-sync-pattern  #x1acffc1dFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF (make-sync-pattern))

(defun process-fixed-frame (state-check-counter verify-counter state-symbol sync-strategy frame &key (aperture 0))
  (with-slots (xtce::sync-pattern verify-to-lock-good-frames check-to-lock-good-frames max-bit-errors-in-sync-pattern) sync-strategy
	(let ((sync-result (find-sync-pattern frame sync-pattern :aperture aperture))
		  (state-result nil))
	  
	  (labels ((reset-verify-counter () (setf verify-counter 0))
			   (reset-state-check-counter () (setf state-check-counter 0)))
		
		(case state-symbol
		  (LOCK
		   (reset-state-check-counter)
		   (when sync-result
			 (incf verify-counter)
			 (setf state-result 'LOCK)))
		  (unless sync-result
			(incf state-check-counter)
			(setf state-result 'CHECK))

		  (CHECK
		   (when sync-result
			 (reset-state-check-counter)
			 (incf verify-counter)
			 (setf state-result 'LOCK))
		   (unless sync-result
			 (if (> state-check-counter check-to-lock-good-frames)
				 (progn
				   (reset-state-check-counter)
				   (reset-verify-counter)
				   (setf state-result 'SEARCH))
				 (progn
				   (incf state-check-counter)
				   (setf state-result 'CHECK)))))

		  (VERIFY
		   (reset-state-check-counter)
		   (when sync-result
			 (incf verify-counter)
			 (if (> verify-counter verify-to-lock-good-frames)
				 (progn
				   (setf state-result 'LOCK))
				 (setf state-result 'VERIFY)))
		   (unless sync-result
			 (reset-verify-counter)
			 (setf state-result 'SEARCH)))

		  (SEARCH
		   (reset-state-check-counter)
		   (when sync-result
			 (incf verify-counter)
			 (setf state-result 'VERIFY))
		   (unless sync-result
			 (reset-verify-counter)
			 (setf state-result 'SEARCH))))

		;; (print state-result)
		;; (print state-check-counter)
		;; (print verify-counter)
		
		(values state-result sync-result (lambda (frame aperture)
										   (process-fixed-frame
											state-check-counter
											verify-counter
											state-result
											sync-strategy
											frame
											:aperture aperture)))))))

;TODO: Check counters
(process-fixed-frame 0 0 'VERIFY (make-sync-strategy (make-sync-pattern)) #x1acffc1dFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)

(defun emit! (message)
  (format t "~A" message))

(defgeneric get-frame-processor-initial-state (frame-type))

(defmethod get-frame-processor-initial-state ((frame-type fixed-frame-stream))
  (with-slots (sync-strategy) frame-type
	(lambda (frame aperture) (process-fixed-frame 0 0 'SEARCH sync-strategy frame :aperture aperture))))

(defmethod get-frame-processor-initial-state ((frame-type variable-frame-stream)))

;(defmethod get-frame-processor-initial-state ((frame-type custom-frame-stream)))

(defun get-fixed-frame-stream-initial-state (fixed-frame-stream-type)
  (let ((fixed-frame-processor-continuation (get-frame-processor-initial-state fixed-frame-stream-type)))
	(lambda (frame) (process-fixed-frame-stream fixed-frame-stream-type fixed-frame-processor-continuation frame))))

(defun process-fixed-frame-stream
	(fixed-frame-stream-type
	 fixed-frame-processor-continuation
	 frame)

  (labels ((aperture-values (n)
			 (append '(0)
					 (alexandria:iota n :start 1)
					 (alexandria:iota n :start -1 :step -1)))

		   (find-marker-with-aperture (aperture)
			 (loop for aperture in (aperture-values aperture)
				   for res = (multiple-value-list (funcall fixed-frame-processor-continuation frame aperture))
				   when (second res)
					 return (cons aperture res) ; Exit early
				   finally (return (cons aperture res))))) ; Giving up

	(with-slots (sync-aperture-in-bits frame-length-in-bits sync-strategy) fixed-frame-stream-type
	  (destructuring-bind (aperture state frame next-continuation) (find-marker-with-aperture sync-aperture-in-bits)
		;;(print state)
		;; (print aperture)
		;; (print (print-hex frame))
		(unless aperture
		  (emit! (list "Aperture greater than zero:" aperture)))		
		(return-from process-fixed-frame-stream (values frame state (lambda (frame) (process-fixed-frame-stream fixed-frame-stream-type next-continuation frame))))))))

(defun get-frame-processor (stream-type)
  (typecase stream-type
	(fixed-frame-stream
	 'process-fixed-frame-stream)
	(variable-frame-stream)
	(custom-stream)))

(defparameter qq #x1acffc1eFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)

(setf qq #x1acffc1dFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)

(defun process-frame-result (frame state next-ref symbol-table)
  (declare (ignore frame)
		   (ignore next-ref)
		   (ignore symbol-table)
		   )
  (case state
	(LOCK
										;(accept-frame frame)
	 (emit! state))
	
	(VERIFY
	 (emit! state)
	 )
	
	(SEARCH
	 (emit! (list "Could not find synchronization marker!")))
	
	(CHECK))
  )

;; (defun monad (space-system frame-queue)
;;   (with-state
;; 	(loop
;; 	  for frame = (lparallel.queue:pop-queue frame-queue)
;; 	  when (null frame)
;; 		return :exit
;; 	  do
;; 		 (print "Got Frame")
;; 		 (multiple-value-bind (frame state next-continuation) (funcall frame-stream-processor-continuation frame)
;; 		   (incf frame-counter)
;; 		   (setf frame-stream-processor-continuation next-continuation)
;; 		   (print frame-counter)
;; 		   (print frame)
;; 		   (print state)
;; 		   (print (slot-value stream-type 'next-ref))
;; 		   )
;; 	)))

(defmacro with-state (space-system &body body)
  `(let* ((telemetry-metadata (slot-value ,space-system 'telemetry-metadata))
		  (stream-type (when telemetry-metadata (first (slot-value telemetry-metadata 'stream-set))))
		  (frame-stream-processor-continuation (get-fixed-frame-stream-initial-state stream-type))
		  (symbol-table (slot-value space-system 'symbol-table))
		  (next-ref (slot-value stream-type 'next-ref))
		  (next (dereference next-ref symbol-table))
		  (frame-counter 0))
	 ,@body
	 ))


(define-condition fragmented-packet-error (SB-KERNEL:BOUNDING-INDICES-BAD-ERROR)
  ((start :initarg :start :reader start)
   (end :initarg :end :reader end))
  (:report (lambda (condition stream) (format stream "Attempted to index outside of frame data while reading packet -> start: ~A, end:~A" (start condition) (end condition)))))


(defun packet-subseq (sequence start &optional end)
  (handler-case (subseq sequence start end)
	(SB-KERNEL:BOUNDING-INDICES-BAD-ERROR ()
	  (signal 'fragmented-packet-error :start start
									   :end end))))


;;;Decode returns from encodings should not modify the alist, this may change in the future when we also want to record precalibrated values
;; Parameters must call decode on the encoding, calibrate the value, place it into the alist, and multiple value return

(defgeneric decode (data decodable-object symbol-table alist bit-offset))

;Dispatch on container-ref
(defmethod decode (data (container-ref-entry xtce::container-ref-entry) symbol-table alist bit-offset)
  (log:debug "Dispatching on: " container-ref-entry)
  (let* ((dereferenced-container (xtce:dereference container-ref-entry symbol-table)))
	(multiple-value-bind (res next-bit-offset) (decode data dereferenced-container symbol-table alist bit-offset)
	  (log:debug bit-offset next-bit-offset res)
	  (values res next-bit-offset))))

(defmethod decode (data (parameter-ref-entry xtce::parameter-ref-entry) symbol-table alist bit-offset)
  (log:debug "Dispatching on:" parameter-ref-entry)
  (let* ((dereferenced-container (xtce:dereference parameter-ref-entry symbol-table)))
	(multiple-value-bind (res next-bit-offset) (decode data dereferenced-container symbol-table alist bit-offset)
	  (log:debug bit-offset next-bit-offset res)
	  (values res next-bit-offset))))

;; Dispatch on container
(defmethod decode (data (container xtce::sequence-container) symbol-table alist bit-offset)
  (with-slots (name) container
	(log:debug "Dispatch on: " name)
	(let ((res-list '()))
	  (dolist (ref (entry-list container))
		(multiple-value-bind (res next-bit-offset) (decode data ref symbol-table (append alist res-list) bit-offset)
		  ;(print bit-offset)
		  (log:debug "Got Result: ~A, ~A" next-bit-offset res)
		  (setf bit-offset next-bit-offset)
		  (typecase ref
			(xtce::container-ref-entry
			 (log:debug "Appending container result.")
			 (setf res-list (append res-list res)))
			(xtce::parameter-ref-entry
			 (log:debug "Pushing parameter result.")
			 (push res res-list)))))
	  (log:debug "Finished container processing: ~A, ~A" bit-offset res-list)
	  (values res-list bit-offset))))

;; Dispatch on Parameter
(defmethod decode (data (parameter xtce::parameter) symbol-table alist bit-offset)
  (log:debug "Dispatch on: " parameter)
  (with-slots (name) parameter
	(let ((parameter-type (xtce::dereference parameter symbol-table)))
	  (assert parameter-type () "No dereference for parameter ~A" parameter)
	  (multiple-value-bind (res next-bit-offset) (decode data parameter-type symbol-table alist bit-offset)
		(log:debug bit-offset next-bit-offset res)
		(values (cons name res) next-bit-offset)))))

;; Dispatch on binary-parameter-type
(defmethod decode (data (parameter-type xtce::binary-parameter-type) symbol-table alist bit-offset)
  (log:debug "Dispatch on: " parameter-type)
  (with-slots (name) parameter-type
	(let ((data-encoding (xtce:data-encoding parameter-type)))
	  (unless data-encoding 
		(error "Can not decode data from stream without a data-encoding for ~A" parameter-type))
	  (multiple-value-bind (res next-bit-offset) (decode data data-encoding symbol-table alist bit-offset)
		;(setf res (bit-vector->hex res))
		(log:debug bit-offset next-bit-offset res)
		(values res next-bit-offset)))))

;; Dispatch on string-parameter-type
(defmethod decode (data (parameter-type xtce::string-parameter-type) symbol-table alist bit-offset)
  (with-slots (name) parameter-type
	(let ((data-encoding (xtce:data-encoding parameter-type)))
	  (unless data-encoding 
		(error "Can not decode data from stream without a data-encoding for ~A" parameter-type))
	  (multiple-value-bind (res next-bit-offset) (decode data data-encoding symbol-table alist bit-offset)
										;(setf res (bit-vector->hex res))
		(log:debug bit-offset next-bit-offset res)
		(values res next-bit-offset)))))

;;Decode binary-data encoding
(defmethod decode (data (encoding xtce::binary-data-encoding) symbol-table alist bit-offset)
  (with-slots (xtce::size-in-bits) encoding
	(let* ((size-in-bits (xtce::resolve-get-size xtce::size-in-bits :alist alist :db-connection nil))
		   (data-segment (packet-subseq data bit-offset (+ bit-offset size-in-bits)))
		   (next-offset (+ bit-offset size-in-bits)))
	  (log:debug "Extracting: " size-in-bits)
	  (log:debug bit-offset next-offset data-segment)
	  (values data-segment next-offset))))

;; Dispatch on enumerated-parameter-type
(defmethod decode (data (parameter-type xtce::enumerated-parameter-type) symbol-table alist bit-offset)
  (log:debug parameter-type)
  (with-slots (name) parameter-type
	(let ((data-encoding (xtce:data-encoding parameter-type)))
	  (unless data-encoding 
		(error "Can not decode data from stream without a data-encoding for ~A" parameter-type))
	  (multiple-value-bind (res next-bit-offset) (decode data data-encoding symbol-table alist bit-offset)
		(log:debug bit-offset next-bit-offset res)
		(values res next-bit-offset)))))

;;Decode boolean parameter 
(defmethod decode (data (parameter-type xtce::boolean-parameter-type) symbol-table alist bit-offset)
  (log:debug parameter-type)
  (with-slots (name) parameter-type
	(let* ((data-encoding (xtce:data-encoding parameter-type))
		   (res nil))
	  (unless data-encoding ;Empty data-encoding is only valid for ground derrived telemetry 			
		(error "Can not decode data from stream without a data-encoding for ~A" parameter-type))
	  (multiple-value-bind (decoded-flag next-bit-offset) (decode data data-encoding symbol-table alist bit-offset)
		(with-slots (xtce::zero-string-value xtce::one-string-value xtce::name) parameter-type
		  (setf res (typecase decoded-flag
					  (bit-vector
					   (if (equal decoded-flag #*0)
						   xtce::zero-string-value
						   xtce::one-string-value))
					  (number
					   (if (equalp decoded-flag 0)
						   xtce::zero-string-value
						   xtce::one-string-value))
					  (string
					   (if (member decoded-flag '("F" "False" "Null" "No" "None" "Nil" "0" "") :test 'equalp)
						   xtce::zero-string-value
						   xtce::one-string-value)))))
		(log:debug next-bit-offset bit-offset res)
		(values res next-bit-offset)))))

;;Decode Integer Parameter
(defmethod decode (data (parameter-type xtce::integer-parameter-type) symbol-table alist bit-offset)
  (log:debug parameter-type)
  (let ((data-encoding (xtce:data-encoding parameter-type)))
	(unless data-encoding ;Empty data-encoding is only valid for ground derrived telemetry 			
	  (error "Can not decode data from stream without a data-encoding for ~A" parameter-type))
	(multiple-value-bind (res next-bit-offset) (decode data data-encoding symbol-table alist bit-offset)
	  (with-slots (xtce::name) parameter-type
		(log:debug bit-offset res)
		(values res next-bit-offset)))))

;;Decode Integer Encoding
(defmethod decode (data (integer-data-encoding xtce::integer-data-encoding) symbol-table alist bit-offset)
  (log:debug integer-data-encoding)
  (with-slots (xtce::integer-encoding xtce::size-in-bits) integer-data-encoding
	(let ((res nil)
		  (next-bit-offset (+ bit-offset xtce::size-in-bits)))
	  (case xtce::integer-encoding
		(xtce::'unsigned
		 (let* ((data-segment (subseq data bit-offset next-bit-offset)))
		   ;;(print (format nil "~A ~A" bit-offset next-bit-offset))
		   ;;(print data-segment)
		   (setf res (bit-vector->uint data-segment))
		   (log:debug bit-offset next-bit-offset res)
		   (log:debug "Extracted: " data-segment)
		   )))
	  (values res next-bit-offset))))

;; (defun a (space-system frame)
;;   (with-state space-system
;; 	(multiple-value-bind (frame state next-continuation) (funcall frame-stream-processor-continuation frame)
;; 	  (incf frame-counter)
;; 	  (setf frame-stream-processor-continuation next-continuation)
;; 	  ;; (print frame-counter)
;; 	  ;; (print frame)
;; 	  ;; (print state)
;; 	  ;; (print next-ref)
;; 										;(print next)
;; 										;(print (type-of next))
;; 	  (decode frame next symbol-table '() 0)
;; 	  )
;; 	))

										;TODO: Typecheck when dereferencing


;; I think you only need 2 threads: 1 for uplink and 1 for downlink, I think the overhead from multiple threads would exceed just finishing off the computation

;; (defparameter frame-queue (lparallel.queue:make-queue))
;; (defparameter test (bt:make-thread (lambda () (monad nasa-cfs::NASA-cFS frame-queue)) :name "monad"))

;; (lparallel.queue:push-queue qq frame-queue)
;; (lparallel.queue:push-queue nil frame-queue)



;; (print-hex (second (process-fixed-frame 0 1 'SEARCH (make-sync-strategy) (make-sync-pattern) #x1acffc1dFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))

;; (lambda (frame aperture) (process-fixed-frame 0 0 'SEARCH (make-sync-strategy) (make-sync-pattern) frame :aperture aperture))


;; (time (process-fixed-frame-stream (make-fixed-frame-stream (make-sync-strategy) 1024) qq))


(defun bit-array-list->concat-bit-vector (l)
  (apply #'concatenate-bit-arrays l))

(defun alist->bit-vector (l)
  (bit-array-list->concat-bit-vector (mapcar #'cdr l)))

(defun new-bit-vector () (make-array 1 :element-type 'bit :adjustable t :fill-pointer 0))

(defun concatenate-bit-arrays (&rest rest)
  (apply #'concatenate 'bit-vector rest))

(defun invert (bit)
  (declare (type bit bit))
  (logxor bit 1))

(defun bit-vector->twos-complement->integer (v)
  ;;(declare (optimize (speed 3) (safety 0)))
  (let ((neg (equal 1 (bit v 0)))
		(res nil))
	(if neg
		(setf res (map 'string #'digit-char (bit-not v)))
		(setf res (map 'string #'(lambda (bit) (digit-char bit)) v)))

	(setf res (parse-integer res :radix 2))
	;;(setf res (format nil "~b" res))
	(when neg
	  (setf res (- (+ res #b1))))
	res
	))

(defun uint->bit-vector (n &optional (pad (integer-length n))) 
  "~43 HAYAI!"
  ;;(declare (optimize (speed 3) (safety 0)))
  (let ((pos (- pad 1))
		(res (make-sequence 'bit-vector pad :initial-element 0)))
	(loop while (> n 0)
		  do
			 (setf (aref res pos) (logand n 1))
			 (setf n (ash n -1))
			 (setf pos (- pos 1)))
	res))

(defun bit-vector->twos-complement->dec (v)
  ;;(declare (optimize (speed 3) (safety 0)))
  (let ((neg (equal 1 (bit v 0)))
		(res nil))
	(if neg
		(setf res (map 'string #'digit-char (bit-not v)))
		(setf res (map 'string #'(lambda (bit) (digit-char bit)) v)))
	(setf res (parse-integer res :radix 2))
	(when neg
	  (setf res (- (+ res #b1))))
	res))

(defun bit-vector->ones-complement->dec (v)
  ;;(declare (optimize (speed 3) (safety 0)))
  (let ((neg (equal 1 (bit v 0)))
		(res nil))
	(if neg
		(setf res (map 'string #'digit-char (bit-not v)))
		(setf res (map 'string #'(lambda (bit) (digit-char bit)) v)))
	(setf res (parse-integer res :radix 2))
	(when neg
	  (setf res (- res)))
	res))

(defun bit-vector->uint (v)
  (parse-integer (map 'string #'digit-char v) :radix 2))

(defun bit-vector->hex (v)
  (let* ((uint (bit-vector->uint v))
		 (hex (format nil "0x~X" uint)))
	hex))

(defun twos-complement-representable-p (n bits)
  (let ((max (expt 2 (- bits 1))))
	(and (< n max) (>= n (- max)))))

(defun dec->twos-complement (integer pad)
  ;;(declare (optimize (speed 3) (safety 0)))
  (assert (twos-complement-representable-p integer pad) (integer pad) "Insufficient bits to represent this integer.")
  (if (< integer 0)
	  (uint->bit-vector (+ #b1 (bit-vector->uint (bit-not (uint->bit-vector (abs integer) pad)))) pad)
	  (pad-bit-vector (uint->bit-vector integer) pad)))

(defun dec->ones-complement (integer pad)
  (if (< integer 0)
	  (bit-not (uint->bit-vector (abs integer) pad)
			   (uint->bit-vector integer pad))))

(defun pad-bit-vector (v pad &key (pad-element 0) (position :left))
  (assert (or (equal position :left) (equal position :right)) (position) "~A is an invalid value: Position must be one of: :right :left" position)
  (if (< (length v) pad)
		(case position
		  (:left
		   (concatenate-bit-arrays (make-sequence 'bit-vector (- pad (length v)) :initial-element pad-element) v))
		  (:right
		   (concatenate-bit-arrays v (make-sequence 'bit-vector (- pad (length v)) :initial-element pad-element))))
		v))

(defun bit-vector->sign-mag->dec (v)
  (let* ((sign (bit v 0))
		 (neg (equal 1 sign))
		 (res nil))
	(setf (bit v 0) 0)
	(setf res (bit-vector->uint v))
	(if neg
		(- res)
		res)))

(defun dec->sign-mag (n pad)
  (let ((res (uint->bit-vector (abs n) pad)))
	(when (< n 0)
	  (setf (bit res 0) 1))
	res
	))

(defvar packedBCD-Table
  '((1 . #*0000)
	(2 . #*0001)
	(3 . #*0010)
	(4 . #*0100)
	(5 . #*0101)
	(6 . #*0110)
	(7 . #*0111)
	(8 . #*1000)
	(9 . #*1001)))

(defun bcd->dec (v byte-size)
  (loop for i from 0 to (length v) by byte-size
		while (< i (- (length v) (- byte-size 1)))
		collect (first(rassoc (subseq v i (+ i byte-size)) packedBCD-Table :test 'equal)) into res
		finally (return (mapcar #'identity res))))

(defun digit-list->integer (l)
  (reduce #'(lambda (acc digit) (+ (* acc 10) digit)) l))

(defun dec->bcd (n &optional (pad 4))
  (let ((digit-list (integer->digit-list n)) )
	(apply 'concatenate-bit-arrays (mapcar #'(lambda (digit) (pad-bit-vector (cdr (assoc digit packedBCD-Table :test 'equal)) pad)) digit-list))))

(defun integer->digit-list (n)
  (loop while (> n 1)
		collect (rem n 10 )
		do
		   (setf n (floor (/ n 10)))))


(defun monad (frame symbol-table &key (packet-extractor (lambda (data first-header-pointer symbol-table alist)
						   (extract-space-packets data first-header-pointer symbol-table alist #*))))
  (log:info "STARTING CYCLE")
  (let* ((frame-alist (decode frame (gethash "STC.CCSDS.AOS.Container.Frame" symbol-table) symbol-table '() 0))
		 (frame-data-field (cdr (assoc stc::'|STC.CCSDS.AOS.Transfer-Frame-Data-Field| frame-alist)))
		 (container (gethash "STC.CCSDS.MPDU.Container.MPDU" symbol-table))
		 (mpdu (decode frame-data-field container symbol-table '() 0))
		 (packet-zone (cdr (assoc stc::'|STC.CCSDS.MPDU.Packet-Zone| mpdu)))
		 (first-header-pointer (cdr (assoc stc::'|STC.CCSDS.MPDU.Header.First-Header-Pointer| mpdu))))

	(log:info first-header-pointer)
	(multiple-value-bind (alist next-extractor)
		(funcall packet-extractor packet-zone first-header-pointer symbol-table mpdu)
	  (values alist (lambda (frame symbol-table) (monad frame symbol-table :packet-extractor next-extractor))))))




(defun extract-space-packets (data first-header-pointer symbol-table alist previous-packet-segment)
  (log:info "Attempting to extract space packets...")
  
  (when (stc::stc.ccsds.mpdu.is-idle-pattern first-header-pointer)
	(log:info "Found idle pattern.")
	(return-from extract-space-packets nil))
  
  (let ((container stc::CCSDS.Space-Packet.Container.Space-Packet)
		(packet-list nil)
		(data-length (length data)))

	(when (stc::stc.ccsds.mpdu.is-spanning-pattern first-header-pointer)
	  (log:info "Attempting to reconstruct spanning packet.")
	  (if (eq previous-packet-segment #*)
		  (progn
			(log:info "Found spanning packet but we do not have a previous fragmented packet.")
			(return-from extract-space-packets
			  (values nil
					  (lambda (next-data first-header-pointer symbol-table alist)
						(extract-space-packets next-data first-header-pointer symbol-table alist nil)))))		  
		  (progn
			(log:info "Packet still fragmented.")
			(return-from extract-space-packets
			  (values packet-list
					  (lambda (next-data first-header-pointer symbol-table alist)
						(extract-space-packets next-data first-header-pointer symbol-table alist (concatenate-bit-arrays previous-packet-segment data))))))))
	
	(let* ((rear-fragment (subseq data 0 (* 8 first-header-pointer)))
		   (lead-fragment nil))
	  (unless (equal first-header-pointer 0)
		(log:info "Attempting to reconstruct fragmented packet.")
		(log:info previous-packet-segment)
		(if (equal previous-packet-segment #*)
		  (log:info "Found fragmented packet at the front of the MPDU but we did not see it's lead fragment in the last MPDU.")
		  (progn
			(let* ((reconstructed-packet (concatenate-bit-arrays previous-packet-segment rear-fragment))
				   (decoded-packet (decode reconstructed-packet container symbol-table alist 0)))
			  (log:info reconstructed-packet)
			  (if (stc::stc.ccsds.space-packet.is-idle-pattern
				   (cdr (assoc stc::'|STC.CCSDS.Space-Packet.Header.Application-Process-Identifier| decoded-packet)))
				  (log:info "Idle packet restored; Discarding.")
				  (progn 
					(log:info "Restored packet!")
					(push decoded-packet packet-list)))))))
	  
	  (let ((next-pointer (* 8 first-header-pointer)))
		(log:debug "Attempting to extract packets starting from zero pointer.")
		(loop while (< next-pointer data-length)
			  do
				 (handler-case 
					 (multiple-value-bind (res-list bits-consumed) (decode data container symbol-table alist next-pointer)					   
					   (setf next-pointer bits-consumed)
					   (log:debug "Extracted ~A of ~A bytes" bits-consumed data-length)
					   (if (stc::stc.ccsds.space-packet.is-idle-pattern
							(cdr (assoc stc::'|STC.CCSDS.Space-Packet.Header.Application-Process-Identifier| res-list)))
						   (log:debug "Found idle Packet!")
						   (push res-list packet-list)))
				   (fragmented-packet-error ()
					 ;; We hit this whenever the packet length tells us to subseq beyond the data frame
					 ;; This is fine, we just take the rest of the frame as a leading fragment
					 (log:info "Fragmented Packet!")
					 (setf lead-fragment (subseq data next-pointer))
					 (return))))
		(log:info "Extracted ~A packets." (length packet-list))
		(log:info (- data-length next-pointer))
		(log:info (length (subseq data next-pointer) ))
		(values packet-list (lambda (next-data first-header-pointer symbol-table alist)
							  (extract-space-packets next-data first-header-pointer symbol-table alist lead-fragment)))))))

(defun pack-arrays-with-padding (padding-vector max-size &rest arrays)
  (declare (optimize (speed 3) (safety 0)))
  (let* ((v (apply #'concatenate-bit-arrays arrays))
		 (size-to-go (- max-size (length v)))
		 (pack-quantity (floor (/ size-to-go (length padding-vector))))
		 (padding-items ())
		 (padded-array #*))
	(declare (bit-vector padding-vector v)
			 (integer max-size pack-quantity))
	(dotimes (i pack-quantity)
	  (push padding-vector padding-items))
	(setf padded-array (apply #'concatenate-bit-arrays v padding-items))
	(values padded-array (- max-size (length padded-array)))))

										;Might be nicer to build an alist we can concatenate at the end
(defun make-mpdu-header (packet-header-in-bits maxmimum-packet-size)
  (let ((first-header-pointer-in-bytes
		  (if (<= packet-header-in-bits maxmimum-packet-size)
			  (uint->bit-vector (/ packet-header-in-bits 8) 11)
			  #*11111111111)))
	;(log:info packet-header-in-bits)
	(alist->bit-vector
	 (list (cons 'spare #*00000)
		   (cons 'first-header-pointer first-header-pointer-in-bytes)))))

(defun fragment-packet (packet-to-frag lead-fragment-size-bits maxmimum-packet-size)
  (assert (equal 0 (mod lead-fragment-size-bits 8))(lead-fragment-size-bits) "number of bits must be equivalent to an integral number of bytes")
  (when (equal 0 lead-fragment-size-bits)
	(return-from fragment-packet (values (make-mpdu-header 0 0) packet-to-frag #*)))

  (when (< (length packet-to-frag) lead-fragment-size-bits)
	(return-from fragment-packet (values
								  (make-mpdu-header (length packet-to-frag) maxmimum-packet-size)
								  packet-to-frag
								  #*)))
  
  (let* ((lead-fragment (subseq packet-to-frag 0 lead-fragment-size-bits))
		 (rear-fragment (subseq packet-to-frag lead-fragment-size-bits))
		 (mpdu-header (make-mpdu-header (length rear-fragment) maxmimum-packet-size)))
	(values mpdu-header lead-fragment rear-fragment)))



(defun monad (frame symbol-table &key (packet-extractor (lambda (data first-header-pointer symbol-table alist)
						   (extract-space-packets data first-header-pointer symbol-table alist #*))))
  (log:info "STARTING CYCLE")
  (let* ((frame-alist (decode frame (gethash "STC.CCSDS.AOS.Container.Frame" symbol-table) symbol-table '() 0))
		 (frame-data-field (cdr (assoc stc::'|STC.CCSDS.AOS.Transfer-Frame-Data-Field| frame-alist)))
		 (container (gethash "STC.CCSDS.MPDU.Container.MPDU" symbol-table))
		 (mpdu (decode frame-data-field container symbol-table '() 0))
		 (packet-zone (cdr (assoc stc::'|STC.CCSDS.MPDU.Packet-Zone| mpdu)))
		 (first-header-pointer (cdr (assoc stc::'|STC.CCSDS.MPDU.Header.First-Header-Pointer| mpdu))))

	(log:info first-header-pointer)
	(multiple-value-bind (alist next-extractor)
		(funcall packet-extractor packet-zone first-header-pointer symbol-table mpdu)
	  (values alist (lambda (frame symbol-table) (monad frame symbol-table :packet-extractor next-extractor))))))

(defclass service ()
  ((name :initarg :name :type symbol)
   (short-description :initarg :short-description :type string)
   (long-description :initarg :long-description :type long-description)
   (alias-set :initarg :alias-set :type alias-set)
   (ancillary-data-set :initarg :ancillary-data-set :type ancillary-data-set)
   (reference-set :initarg :reference-set)))


(defun make-service (name reference-set &key short-description long-description alias-set ancillary-data-set)
  (make-instance 'service :name name
						  :reference-set reference-set
						  :short-description short-description
						  :long-description long-description
						  :ancillary-data-set ancillary-data-set
						  :alias-set alias-set))

(deftype service-set ()
  `(satisfies service-set-p))

(defun service-set-p (l)
  (and (listp l)
	   (every #'(lambda (i) (typep i 'service)) l)))

(deftype container-ref-set ()
  `(satisfies container-set-p))

(defun container-ref-set-p (l)
  (and (listp l)
	   (every #'(lambda (i) (typep i 'container-ref)) l)))


										;container+reference combinations

(defun mpdu-monad (frame-alist symbol-table &key (packet-extractor (lambda (data first-header-pointer symbol-table alist)
																	(extract-space-packets data first-header-pointer symbol-table alist #*))))
  (let* ((frame-data-field (cdr (assoc stc::'|STC.CCSDS.AOS.Transfer-Frame-Data-Field| frame-alist)))
		 (container (gethash "STC.CCSDS.MPDU.Container.MPDU" symbol-table))
		 (mpdu (decode frame-data-field container symbol-table '() 0))
		 (packet-zone (cdr (assoc stc::'|STC.CCSDS.MPDU.Packet-Zone| mpdu)))
		 (first-header-pointer (cdr (assoc stc::'|STC.CCSDS.MPDU.Header.First-Header-Pointer| mpdu))))

	(log:info first-header-pointer)
	(multiple-value-bind (alist next-extractor)
		(funcall packet-extractor packet-zone first-header-pointer symbol-table mpdu)
	  (values alist (lambda (frame-alist symbol-table) (mpdu-monad frame-alist symbol-table :packet-extractor next-extractor))
			  )
	  )))

(defmacro with-test-table (&body body)
  `(let ((test-table (xtce::register-keys-in-sequence
					  (stc::with-ccsds.space-packet.parameters
						  (stc::with-ccsds.space-packet.types
							  (stc::with-ccsds.space-packet.containers
								  (stc::with-ccsds.mpdu.containers
									  (stc::with-ccsds.mpdu.types
										  (stc::with-ccsds.mpdu.parameters
											  (stc::with-ccsds.aos.containers
												  (stc::with-ccsds.aos.header.parameters
													  (stc::with-ccsds.aos.header.types '())))))))))
					  (filesystem-hash-table:make-filesystem-hash-table) 'Test)))
	 ,@body))


(defun generate-service (service symbol-table &optional (service-table (make-hash-table)))
  ;; VCID -> Service
  (with-slots (name reference-set short-description ancillary-data-set) service
	(let* ((reference-container (first  reference-set))
		   (reference (dereference reference-container symbol-table))
		   (vcid (xtce::value (gethash 'VCID (xtce::items ancillary-data-set)))))
	  (assert reference-container)
	  (assert vcid)
	  (case (name reference)
		(stc::'|STC.CCSDS.MPDU.Container.MPDU|
		 (log:info "Generated MPDU Service for VCID ~A!" vcid)
		 (setf (gethash vcid service-table) (list #'mpdu-monad service)))
		(t
		 (log:warn "Could not find a service for reference ~A" reference))))
  service-table
  ))

(defun generate-services (service-list symbol-table &optional (service-table (make-hash-table)))
  (dolist (service service-list)
	(generate-service service symbol-table service-table))
  service-table)

;; (with-test-table
;;   (generate-services (list (make-service "STC.CCSDS.MPDU.Container.MPDU"
;; 										 (list (make-container-ref '|STC.CCSDS.MPDU.Container.MPDU|))
;; 										 :short-description "Test MPDU Service"
;; 										 :ancillary-data-set (xtce::make-ancillary-data-set (make-ancillary-data 'VCID 0))))
;; 					 test-table
;; 					 ))

(defparameter q
  (with-test-table
	(list (make-service "STC.CCSDS.MPDU.Container.MPDU"
						(list (make-container-ref '|STC.CCSDS.MPDU.Container.MPDU|))
						:short-description "Test MPDU Service"
						:ancillary-data-set (xtce::make-ancillary-data-set (xtce::make-ancillary-data 'VCID 43))))
	))

;; (log:info
;;  (dump-xml
;;   (xtce::make-ancillary-data-set (make-ancillary-data 'VCID 4))))


;(setf lparallel:*kernel* (lparallel:make-kernel 10))

(defun vcid-dispatch-service (service-list symbol-table service-queue output-queue)
  (log:info "UP")
  (let ((services (generate-services service-list symbol-table)))
	(loop
	  (let* ((frame-alist (pop-queue service-queue))
			 (vcid (cdr (assoc stc::'|STC.CCSDS.AOS.Header.Virtual-Channel-ID| frame-alist)))
			 (monad-pair (gethash vcid services))
			 (monad (first monad-pair))
			 (service (second monad-pair)))
		(multiple-value-bind (packet-list next-monad) (funcall monad frame-alist symbol-table)
		  (log:info packet-list)
		  (setf (gethash vcid services) (list next-monad service))
		  (push-queue packet-list output-queue)
		  (log:info vcid)
		  )))))

(defparameter service-queue (make-queue))
(defparameter output-queue (make-queue))

(with-test-table
  (log:info "Going up!")
  (bt:make-thread (vcid-dispatch-service q test-table service-queue output-queue) :name "Test1")
										;(log:info "Down")
  )

(with-test-table
  (with-aos-header
	(with-space-packet
	  (with-idle-packet
		(with-pack-fragment-idle-frame
		  (let ((frame-1 (decode frame-1 (gethash "STC.CCSDS.AOS.Container.Frame" test-table) test-table '() 0)))
										;(log:info frame-1)
			(push-queue frame-1 service-queue)
			;(push-queue frame-2 service-queue)
			(log:info (pop-queue output-queue))
			)
		  
		  )))))

(push-queue nil service-queue)

;; (push-queue   service-queue )
(defmacro with-aos-header (&body body)
  `(let* ((header-result (list (cons STC::'|STC.CCSDS.Space-Packet.Header.Packet-Data-Length| 3)
							   (cons STC::'|STC.CCSDS.Space-Packet.Header.Packet-Version-Number| 0)
							   (cons STC::'|STC.CCSDS.Space-Packet.Header.Application-Process-Identifier| #*00000000001)
							   (cons STC::'|STC.CCSDS.Space-Packet.Header.Secondary-Header-Flag| 0)
							   (cons STC::'|STC.CCSDS.Space-Packet.Header.Packet-Type| 0)
							   (cons STC::'|STC.CCSDS.Space-Packet.Header.Packet-Sequence-Count| 666)
							   (cons STC::'|STC.CCSDS.Space-Packet.Header.Sequence-Flags| #*11)
							   (cons STC::'|STC.CCSDS.Space-Packet.Packet-Data-Field.User-Data-Field| #*10111010110111000000110111101101)))
		  
		  (aos-header (alist->bit-vector
					   (list (cons 'transfer-frame-version-number #*01)
							 (cons 'spacecraft-id #*01100011) ;0x63
							 (cons 'virtual-channel-id #*101011) ;43
							 (cons 'virtual-channel-frame-count #*100101110000100010101011); 9898155
							 (cons 'replay-flag #*0)
							 (cons 'virtual-channel-frame-count-usage-flag #*1)
							 (cons 'reserved-space #*00)
							 (cons 'vc-frame-count-cycle #*1010)))))
	 ,@body))

(defmacro with-space-packet (&body body)
  `(let ((space-packet (alist->bit-vector
						(list (cons 'packet-version-number  #*000)
							  (cons 'packet-type #*0)
							  (cons 'sec-hdr-flag #*0)
							  (cons 'apid #*00000000001)
							  (cons 'sequence-flags #*11)
							  (cons 'sequence-count #*00001010011010)
							  (cons 'data-len (uint->bit-vector (- (/ (length (uint->bit-vector #xBADC0DED)) 8) 1) 16))
							  (cons 'data (uint->bit-vector #xBADC0DED))))))
	 ,@body))



(defmacro with-idle-packet (&body body)
  `(let ((idle-packet (alist->bit-vector
					   (list (cons 'packet-version-number  #*000)
							 (cons 'packet-type #*0)
							 (cons 'sec-hdr-flag #*0)
							 (cons 'appid #*11111111111)
							 (cons 'sequence-flags #*11)
							 (cons 'sequence-count #*00001010011010)
							 (cons 'data-len (uint->bit-vector (- (/ (length (uint->bit-vector #xFFFFFFFF)) 8) 1) 16))
							 (cons 'data (uint->bit-vector #xFFFFFFFF))))))
	 ,@body))

(defmacro with-test-table (&body body)
  `(let ((test-table (xtce::register-keys-in-sequence
					  (stc::with-ccsds.space-packet.parameters
						  (stc::with-ccsds.space-packet.types
							  (stc::with-ccsds.space-packet.containers
								  (stc::with-ccsds.mpdu.containers
									  (stc::with-ccsds.mpdu.types
										  (stc::with-ccsds.mpdu.parameters
											  (stc::with-ccsds.aos.containers
												  (stc::with-ccsds.aos.header.parameters
													  (stc::with-ccsds.aos.header.types '())))))))))
					  (filesystem-hash-table:make-filesystem-hash-table) 'Test)))
	 ,@body))

(defmacro with-pack-fragment-idle-frame (&body body)
  `(let* ((payload-1 (nconc (make-list 30 :initial-element space-packet) (make-list 2 :initial-element idle-packet)))
		  (payload-2 nil)
		  (mpdu-1 (make-mpdu-header 0 4096))
		  (mpdu-2 nil)
		  (frame-1 nil)
		  (frame-2 nil)
		  (lead-frag nil)
		  (rear-frag nil))
	 (multiple-value-bind (frame padding-required) (apply #'pack-arrays-with-padding idle-packet 8192 AOS-HEADER mpdu-1 payload-1)
	   (multiple-value-bind (next-mpdu-header lead-frag_ rear-frag_) 
		   (fragment-packet idle-packet padding-required 1024)
		 (setf lead-frag lead-frag_)
		 (setf rear-frag rear-frag_)
		 (setf frame-1 (concatenate-bit-arrays frame lead-frag))
		 (setf mpdu-2 next-mpdu-header)
		 (setf frame-2 (pad-bit-vector (pack-arrays-with-padding idle-packet 8192 AOS-HEADER next-mpdu-header rear-frag) 8192 :position :right))
		 ))
	 ,@body))
