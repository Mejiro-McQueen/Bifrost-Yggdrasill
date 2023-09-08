(defpackage :xtce
  (:use :cl
		:cxml
		:filesystem-hash-table)
  (:documentation "XTCE")
  (:export
   #:format-bool
   #:format-number
   #:format-symbol
   #:hamming-distance
   #:hex-length-in-bits
   #:ldb-left
   #:make-absolute-time-parameter
   #:make-argument-instance-ref
   #:make-array-parameter-ref-entry
   #:make-array-parameter-type
   #:make-base-container
   #:make-binary-data-encoding
   #:make-binary-parameter-type
   #:make-comparison
   #:make-container-ref-entry
   #:make-container-segment-ref-entry
   #:make-count
   #:make-default-rate-in-stream
   #:make-dynamic-value
   #:make-encoding
   #:make-ending-index
   #:make-enumerated-parameter-type
   #:make-enumeration
   #:make-enumeration-alarm
   #:make-epoch
   #:make-fixed-frame-stream
   #:make-fixed-value
   #:make-float-data-encoding
   #:make-float-parameter-type
   #:make-include-condition
   #:make-indirect-parameter-ref-entry
   #:make-integer-data-encoding
   #:make-integer-parameter-type
   #:make-leading-size
   #:make-linear-adjustment
   #:make-location-in-container-in-bits
   #:make-long-description
   #:make-next-container
   #:make-offset-from
   #:make-offset
   #:make-parameter
   #:make-parameter-instance-ref
   #:make-parameter-ref-entry
   #:make-parameter-segment-ref-entry
   #:make-polynomial-calibrator
   #:make-rate-in-stream
   #:make-reference-time
   #:make-repeat-entry
   #:make-restriction-criteria
   #:make-sequence-container
   #:make-size-in-bits
   #:make-size-range-in-characters
   #:make-spline-point
   #:make-starting-index
   #:make-stream-segment-entry
   #:make-string-data-encoding
   #:make-string-parameter-type
   #:make-sync-pattern
   #:make-sync-strategy
   #:make-term
   #:make-termination-char
   #:make-container-ref
   #:make-stream-ref
   #:make-service-ref
   #:make-unit
   #:print-bin
   #:print-hex
   #:prompt-new-value
   #:truncate-from-left
   #:truncate-from-left-to-size
   #:make-telemetry-metadata
   #:make-space-system
   #:make-dimension
   #:dump-xml
   #:instantiate-parameter
   #:mask
   #:pattern
   #:pattern-length-in-bits
   #:bit-location-from-start
   #:short-description
   #:long-description
   #:alias-set
   #:ancillary-data-set
   #:bit-rate-in-bips
   #:pcm-type
   #:inverted
   #:sync-aperture-in-bits
   #:frame-length-in-bits
   #:next-ref
   #:sync-strategy
   ))

(defpackage :xtce-engine
  (:use :cl
		:xtce)
  (:documentation "XTCE-Engine")
  (:export #:STC.CCSDS.Space-Packet-Types))


(defpackage :standard-template-constructs
  (:use :cl
		:xtce)
  (:documentation "Standard Template Constructs")
  (:nicknames :stc)
  (:export
   #:CCSDS.AOS.Data-Field
   #:CCSDS.AOS.Data-Field-Type
   #:CCSDS.AOS.Header.Frame-Count-Cycle
   #:CCSDS.AOS.Header.Frame-Count-Cycle-Type
   #:CCSDS.AOS.Header.Frame-Header-Error-Control
   #:CCSDS.AOS.Header.Frame-Header-Error-Control-Type
   #:CCSDS.AOS.Header.Master-Channel-ID
   #:CCSDS.AOS.Header.Master-Channel-ID-Type
   #:CCSDS.AOS.Header.Replay-Flag
   #:CCSDS.AOS.Header.Replay-Flag-Type
   #:CCSDS.AOS.Header.Reserved-Spare
   #:CCSDS.AOS.Header.Reserved-Spare-Type
   #:CCSDS.AOS.Header.Signaling-Field
   #:CCSDS.AOS.Header.Signaling-Field-Type
   #:CCSDS.AOS.Header.Spacecraft-Identifier
   #:CCSDS.AOS.Header.Spacecraft-Identifier-Type
   #:CCSDS.AOS.Header.Version-Number
   #:CCSDS.AOS.Header.Version-Number-Type
   #:CCSDS.AOS.Header.Virtual-Channel-Frame-Count
   #:CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Type
   #:CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag
   #:CCSDS.AOS.Header.Virtual-Channel-Frame-Count-Usage-Flag-Type
   #:CCSDS.AOS.Header.Virtual-Channel-ID
   #:CCSDS.AOS.Header.Virtual-Channel-ID-Type
   #:CCSDS.AOS.Insert-Zone
   #:CCSDS.AOS.Insert-Zone-Type
   #:CCSDS.MPDU.Header.First-Header-Pointer
   #:CCSDS.MPDU.Header.Reserved-Spare
   #:CCSDS.MPDU.Header.Reserved-Spare-Type
   #:CCSDS.MPDU.Packet-Zone
   #:CCSDS.Space-Packet.Header.Application-Process-Identifier
   #:CCSDS.Space-Packet.Header.Application-Process-Identifier-Type
   #:CCSDS.Space-Packet.Header.Packet-Data-Length
   #:CCSDS.Space-Packet.Header.Packet-Data-Length-Type
   #:CCSDS.Space-Packet.Header.Packet-Identification
   #:CCSDS.Space-Packet.Header.Packet-Identification-Type
   #:CCSDS.Space-Packet.Header.Packet-Name
   #:CCSDS.Space-Packet.Header.Packet-Name-Type
   #:CCSDS.Space-Packet.Header.Packet-Sequence-Control-Type
   #:CCSDS.Space-Packet.Header.Packet-Sequence-Count
   #:CCSDS.Space-Packet.Header.Packet-Sequence-Count-Type
   #:CCSDS.Space-Packet.Header.Packet-Transfer-Frame-Version-Number
   #:CCSDS.Space-Packet.Header.Packet-Type
   #:CCSDS.Space-Packet.Header.Packet-Type-Type
   #:CCSDS.Space-Packet.Header.Packet-Version-Number-Type
   #:CCSDS.Space-Packet.Header.Secondary-Header-Flag
   #:CCSDS.Space-Packet.Header.Secondaty-Header-Flag-Type
   #:CCSDS.Space-Packet.Header.Sequence-Control
   #:CCSDS.Space-Packet.Header.Sequence-Flags
   #:CCSDS.Space-Packet.Header.Types
   #:with-ccsds.aos.header.parameters
   #:with-ccsds.aos.header.types
   #:with-ccsds.space-packet.header.parameters
   #:with-ccsds.space-packet.header.types
   #:CCSDS.MPDU.Packet-Type
   #:CCSDS.MPDU.Packet
   #:with-ccsds.aos.stream
   ))

(defpackage :nasa-cfs
  (:use :cl
		:xtce)
  (:nicknames :cfs)
  (:documentation "NASA-cFS")
  (:export))
