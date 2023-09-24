(in-package :standard-template-constructs)
(use-package :xtce)

;TODO: Pull these out as ancillary data

(defparameter AOS.Transfer-Frame-Length 1024)

(defparameter use-AOS.Operational-Control-Field nil)

(defparameter AOS.Insert-Zone-Length nil)

(defparameter use-AOS.Frame-Error-Control-Field nil)

(defparameter use-AOS.Header.Frame-Header-Error-Control-Field nil)

(defparameter AOS.Transfer-Frame-Trailer-Length nil)

(defun set-CCSDS.AOS.Transfer-Frame-Length (n)
  (setf AOS.Transfer-Frame-Length n))

(defun get-transfer-frame-data-field-length ()
  (- AOS.Transfer-Frame-Length
	 (+ AOS.Insert-Zone-Length AOS.Transfer-Frame-Trailer-Length)))

(defun set-CCSDS.AOS.Set-Insert-Zone-Length (n)
  (setf AOS.Insert-Zone-Length n))

(defun set-CCSDS.AOS.Frame-Error-Control-Field ())

(defun set-CCSDS.AOS.Operational-Control-Field ())

(defvar CCSDS.AOS.Header.Master-Channel-ID-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Master-Channel-ID-Type|
   :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value 16)))))

(defvar CCSDS.AOS.Header.Signaling-Field-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Signaling-Field-Type|
   :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value 8)))))

(defvar CCSDS.AOS.Header.Version-Number-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Frame-Version-Number-Type|
   :short-description "2 bits fixed to 01"
   :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value 2)))))

(defvar CCSDS.AOS.Header.Spacecraft-Identifier-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Spacecraft-Identifier-Type|
   :short-description "8 bit SCID"
   :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value 8)))))

(defvar CCSDS.AOS.Header.Virtual-Channel-ID-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Virtual-Channel-ID-Type|
   :short-description "6 channel ID "
   :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value 6)))))

(defvar CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Type
  (make-integer-parameter-type
   '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Type|
   :short-description "24 bit positive integer counter"
   :data-encoding (make-integer-data-encoding :size-in-bits 24)))

(defvar CCSDS.AOS.Header.Replay-Flag-Type
  (make-enumerated-parameter-type
   '|STC.CCSDS.AOS.Header.Replay-Flag-Type|
   :short-description "boolean flag"
   :enumeration-list (list (make-enumeration #b0 '|Realtime-Transfer-Frame|)
						   (make-enumeration #b1 '|Replay-Transfer-Frame|))
   :data-encoding (boolean-flag)))

(defvar CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag-Type
  (make-enumerated-parameter-type
   '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag-Type|
   :short-description "boolean flag"
   :enumeration-list (list (make-enumeration #b0 '|Ignored|)
						   (make-enumeration #b1 '|Interpreted|))
   :data-encoding (boolean-flag)))

(defvar CCSDS.AOS.Header.Reserved-Spare-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Reserved-Spare-Type|
   :short-description "CCSDS Reserved 2 bits, always 00"
   :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value 2)))))

(defvar CCSDS.AOS.Header.Frame-Count-Cycle-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Cycle-Type|
   :short-description "Set to all zeros if not used. Otherwise, increments whenever the Frame Count rolls over, effectively extending it to 28 bits."
   :data-encoding (make-integer-data-encoding :size-in-bits 4)))

;TODO: Figure out how to describe that it should be reed solomon checked
(defvar CCSDS.AOS.Header.Frame-Header-Error-Control-Type
  (make-binary-parameter-type
   '|STC.CCSDS.AOS.Header.Frame-Header-Error-Control-Type|
   :short-description "Optional. Reed-Solomon Protecting Mater Channel Identifier and Virtual Channel Identifier. 16 bits."
   :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value 16)))))

(defvar CCSDS.AOS.Insert-Zone-Type
  (make-binary-parameter-type '|STC.CCSDS.AOS.Insert-Zone-Type|
  :short-description "Optional."
  :data-encoding (make-binary-data-encoding (make-size-in-bits (make-fixed-value AOS.Insert-Zone-Length)))))

(defvar CCSDS.AOS.Transfer-Frame-Data-Field-Type
  (make-binary-parameter-type '|STC.CCSDS.AOS.Transfer-Frame-Data-Field-Type|
  :short-description "M_PDU or B_PDU or VCA_SDU or Idle Data"
  :long-description (make-long-description "4.1.4.1.3 The Transfer Frame Data Field shall contain one Multiplexing Protocol Data Unit
(M_PDU), one Bitstream Protocol Data Unit (B_PDU), one Virtual Channel Access Service
Data Unit (VCA_SDU), or Idle Data. \n M_PDUs, B_PDUs, VCA_SDUs, and Idle Data shall not be mixed in a Virtual
Channel (i.e., if a Virtual Channel transfers M_PDUs, every Transfer Frame of that Virtual
Channel shall contain an M_PDU). Management shall decide whether M_PDUs, B_PDUs or
VCA_SDUs are transferred on a particular Virtual Channel, and this decision shall remain
static throughout a Mission Phase.")))

(defun with-ccsds.aos.header.types (type-list)
  (append type-list
		  (list
		   CCSDS.AOS.Transfer-Frame-Data-Field-Type
		   CCSDS.AOS.Header.Frame-Count-Cycle-Type
		   CCSDS.AOS.Header.Frame-Header-Error-Control-Type
		   CCSDS.AOS.Insert-Zone-Type
		   CCSDS.AOS.Header.Master-Channel-ID-Type
		   CCSDS.AOS.Header.Replay-Flag-Type
		   CCSDS.AOS.Header.Reserved-Spare-Type
		   CCSDS.AOS.Header.Signaling-Field-Type
		   CCSDS.AOS.Header.Spacecraft-Identifier-Type
		   CCSDS.AOS.Header.Version-Number-Type
		   CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Type
		   CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag-Type
		   CCSDS.AOS.Header.Virtual-Channel-ID-Type
		   )))

(defvar CCSDS.AOS.Header.Master-Channel-ID
  (make-parameter '|STC.CCSDS.AOS.Header.Master-Channel-ID| '|STC.CCSDS.AOS.Header.Master-Channel-ID-Type|))

(defvar CCSDS.AOS.Header.Signaling-Field
  (make-parameter '|STC.CCSDS.AOS.Header.Signaling-Field| '|STC.CCSDS.AOS.Header.Signaling-Field-Type|))

(defvar CCSDS.AOS.Header.Virtual-Channel-ID
  (make-parameter '|STC.CCSDS.AOS.Header.Virtual-Channel-ID| '|STC.CCSDS.AOS.Header.Virtual-Channel-ID-Type|))

(defvar CCSDS.AOS.Header.Virtual-Channel-Frame-Count
  (make-parameter '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count| '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Type|))

(defvar CCSDS.AOS.Header.Replay-Flag
  (make-parameter '|STC.CCSDS.AOS.Header.Replay-Flag| '|STC.CCSDS.AOS.Header.Replay-Flag-Type|))

(defvar CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag
  (make-parameter '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag| '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag-Type|))

(defvar CCSDS.AOS.Header.Reserved-Spare
  (make-parameter '|STC.CCSDS.AOS.Header.Reserved-Spare| '|STC.CCSDS.AOS.Header.Reserved-Spare-Type|))

(defvar CCSDS.AOS.Header.Frame-Count-Cycle
  (make-parameter '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Cycle| '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Cycle-Type|))

(defvar CCSDS.AOS.Header.Frame-Header-Error-Control
  (make-parameter '|STC.CCSDS.AOS.Header.Frame-Header-Error-Control| '|STC.CCSDS.AOS.Header.Frame-Header-Error-Control-Type|))

(defvar CCSDS.AOS.Insert-Zone
  (make-parameter '|STC.CCSDS.AOS.Insert-Zone| '|STC.CCSDS.AOS.Insert-Zone-Type|))

(defvar CCSDS.AOS.Header.Frame-Version-Number 
  (make-parameter '|STC.CCSDS.AOS.Header.Frame-Version-Number| '|STC.CCSDS.AOS.Header.Frame-Version-Number-Type|))

(defvar CCSDS.AOS.Transfer-Frame-Data-Field
  (make-parameter '|STC.CCSDS.AOS.Transfer-Frame-Data-Field| '|STC.CCSDS.AOS.Transfer-Frame-Data-Field-Type|))

(defvar CCSDS.AOS.Header.Spacecraft-Identifier
  (make-parameter '|STC.CCSDS.AOS.Header.Spacecraft-Identifier| '|STC.CCSDS.AOS.Header.Spacecraft-Identifier-Type|))

(defun with-ccsds.aos.header.parameters (parameter-list)
  (append
   parameter-list
   (list
	CCSDS.AOS.Header.Master-Channel-ID
	CCSDS.AOS.Header.Signaling-Field
	CCSDS.AOS.Header.Virtual-Channel-ID
	CCSDS.AOS.Header.Virtual-Channel-Frame-Count
	CCSDS.AOS.Header.Replay-Flag
	CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag
	CCSDS.AOS.Header.Reserved-Spare
	CCSDS.AOS.Header.Frame-Count-Cycle
	CCSDS.AOS.Header.Frame-Header-Error-Control
	CCSDS.AOS.Header.Frame-Version-Number
	CCSDS.AOS.Transfer-Frame-Data-Field
	CCSDS.AOS.Header.Spacecraft-Identifier)
   (when AOS.Insert-Zone-Length
	 (list CCSDS.AOS.Insert-Zone))))

(defvar CCSDS.AOS.Container.Transfer-Frame-Primary-Header
  (make-sequence-container
   '|STC.CCSDS.AOS.Container.Transfer-Frame-Primary-Header|
   (append
	(list
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Frame-Version-Number|)
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Spacecraft-Identifier|)
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Virtual-Channel-ID|)
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count|)
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Replay-Flag|)
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag|)
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Reserved-Spare|)
	 (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Cycle|))
	(when use-AOS.Header.Frame-Header-Error-Control-Field
	  (make-parameter-ref-entry '|STC.CCSDS.AOS.Header.Frame-Header-Error-Control|)))))

(defvar CCSDS.AOS.Container.Transfer-Frame-Insert-Zone
  (make-sequence-container
   '|STC.CCSDS.AOS.Container.Transfer-Frame.Insert-Zone|
   (list (make-parameter-ref-entry '|STC.CCSDS.AOS.Transfer-Frame.Insert-Zone|))))

(defvar CCSDS.AOS.Container.Transfer-Frame-Data-Field
  (make-sequence-container
   '|STC.CCSDS.AOS.Container.Transfer-Frame-Data-Field|
   (list (make-parameter-ref-entry '|STC.CCSDS.AOS.Transfer-Frame-Data-Field|))))

(defvar CCSDS.AOS.Container.Transfer-Frame-Trailer
  (make-sequence-container
   '|STC.CCSDS.AOS.Container.Transfer-Frame-Trailer|
   (append
	'()
	(when use-AOS.Operational-Control-Field
	  (list (make-parameter-ref-entry '|STC.CCSDS.AOS.Operational-Control-Field|)))
	(when use-AOS.Frame-Error-Control-Field
	  (list (make-parameter-ref-entry '|STC.CCSDS.AOS.Frame-Error-Control-Field|))))))


(defvar CCSDS.AOS.Container.Frame
  (make-sequence-container
   '|STC.CCSDS.AOS.Container.Frame|
   (append 
	(list
	 (make-container-ref-entry '|STC.CCSDS.AOS.Container.Transfer-Frame-Primary-Header|)
	 (make-container-ref-entry  '|STC.CCSDS.AOS.Container.Transfer-Frame-Data-Field|))
	
	(when AOS.Insert-Zone-Length
	  (make-container-ref-entry '|STC.CCSDS.AOS.Container.Transfer-Frame-Insert-Zone|))
	
	(when (or use-AOS.Frame-Error-Control-Field use-AOS.Operational-Control-Field) 
	  (make-container-ref-entry '|STC.CCSDS.AOS.Container.Transfer-Frame-Trailer|)))))

(defun with-ccsds-aos-containers (container-list)
  (append
   container-list
   (list
	CCSDS.AOS.Container.Frame
	CCSDS.AOS.Container.Transfer-Frame-Primary-Header
	CCSDS.AOS.Container.Transfer-Frame-Data-Field)
	(when (or use-AOS.Frame-Error-Control-Field use-AOS.Operational-Control-Field) 
	  (list CCSDS.AOS.Container.Transfer-Frame-Trailer))))

(defun with-ccsds.aos.stream (frame-length-in-bits stream-list)
  (append
   stream-list
   (list
	(make-fixed-frame-stream
	 '|STC.CCSDS.AOS.Stream|
	 frame-length-in-bits
	 (make-container-ref '|STC.CCSDS.AOS.Container.Frame|)
	 (make-sync-strategy (make-sync-pattern))
	 :short-description "CCSDS AOS Stream"))))


;; ;Good pathatlogical cycle:
;; (defvar CCSDS.AOS.Header.Replay-Flag
;;   (make-parameter '|STC.CCSDS.AOS.Header.Replay-Flag| '|STC.CCSDS.AOS.Header.Replay-Flag|))
