;; Inter-Agency Communication Contract
;; Facilitates coordination between different emergency response organizations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u104))

;; Message Types
(define-constant MESSAGE-ALERT u1)
(define-constant MESSAGE-REQUEST u2)
(define-constant MESSAGE-UPDATE u3)
(define-constant MESSAGE-COORDINATION u4)

;; Data Variables
(define-data-var next-message-id uint u1)
(define-data-var next-incident-id uint u1)

;; Data Maps
(define-map agencies
  { agency-id: (string-ascii 20) }
  {
    name: (string-ascii 100),
    agency-type: (string-ascii 30),
    zone-coverage: (list 10 uint),
    contact-info: (string-ascii 100),
    status: (string-ascii 20),
    last-active: uint
  }
)

(define-map messages
  { message-id: uint }
  {
    sender-agency: (string-ascii 20),
    recipient-agencies: (list 10 (string-ascii 20)),
    message-type: uint,
    priority-level: uint,
    subject: (string-ascii 100),
    content: (string-ascii 500),
    incident-reference: (optional uint),
    timestamp: uint,
    read-by: (list 10 (string-ascii 20))
  }
)

(define-map incident-coordination
  { incident-id: uint }
  {
    lead-agency: (string-ascii 20),
    participating-agencies: (list 10 (string-ascii 20)),
    incident-type: (string-ascii 50),
    severity-level: uint,
    zone: uint,
    status: (string-ascii 20),
    created-at: uint,
    last-updated: uint,
    resource-requests: (list 20 uint)
  }
)

(define-map agency-resources
  { agency-id: (string-ascii 20) }
  {
    personnel-available: uint,
    equipment-available: (list 10 { equipment-type: (string-ascii 30), quantity: uint }),
    specialized-capabilities: (list 5 (string-ascii 50)),
    current-deployments: uint,
    max-capacity: uint
  }
)

(define-map authorized-operators principal bool)

;; Authorization Functions
(define-private (is-authorized (caller principal))
  (or
    (is-eq caller CONTRACT-OWNER)
    (default-to false (map-get? authorized-operators caller))
  )
)

;; Public Functions
(define-public (add-authorized-operator (operator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-operators operator true))
  )
)

(define-public (register-agency (agency-id (string-ascii 20)) (name (string-ascii 100)) (agency-type (string-ascii 30)) (zone-coverage (list 10 uint)))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? agencies { agency-id: agency-id })) ERR-ALREADY-EXISTS)

    (map-set agencies
      { agency-id: agency-id }
      {
        name: name,
        agency-type: agency-type,
        zone-coverage: zone-coverage,
        contact-info: "",
        status: "ACTIVE",
        last-active: block-height
      }
    )
    (ok true)
  )
)

(define-public (send-message (sender-agency (string-ascii 20)) (recipient-agencies (list 10 (string-ascii 20))) (message-type uint) (priority-level uint) (subject (string-ascii 100)) (content (string-ascii 500)) (incident-reference (optional uint)))
  (let
    (
      (message-id (var-get next-message-id))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= message-type u1) (<= message-type u4)) ERR-INVALID-INPUT)
    (asserts! (and (>= priority-level u1) (<= priority-level u5)) ERR-INVALID-INPUT)
    (asserts! (is-some (map-get? agencies { agency-id: sender-agency })) ERR-NOT-FOUND)

    (map-set messages
      { message-id: message-id }
      {
        sender-agency: sender-agency,
        recipient-agencies: recipient-agencies,
        message-type: message-type,
        priority-level: priority-level,
        subject: subject,
        content: content,
        incident-reference: incident-reference,
        timestamp: block-height,
        read-by: (list)
      }
    )
    (var-set next-message-id (+ message-id u1))
    (ok message-id)
  )
)

(define-public (mark-message-read (message-id uint) (agency-id (string-ascii 20)))
  (let
    (
      (message (unwrap! (map-get? messages { message-id: message-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? agencies { agency-id: agency-id })) ERR-NOT-FOUND)

    (map-set messages
      { message-id: message-id }
      (merge message {
        read-by: (unwrap! (as-max-len? (append (get read-by message) agency-id) u10) ERR-INVALID-INPUT)
      })
    )
    (ok true)
  )
)

(define-public (create-incident-coordination (lead-agency (string-ascii 20)) (incident-type (string-ascii 50)) (severity-level uint) (zone uint))
  (let
    (
      (incident-id (var-get next-incident-id))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= severity-level u1) (<= severity-level u5)) ERR-INVALID-INPUT)
    (asserts! (and (>= zone u1) (<= zone u10)) ERR-INVALID-INPUT)
    (asserts! (is-some (map-get? agencies { agency-id: lead-agency })) ERR-NOT-FOUND)

    (map-set incident-coordination
      { incident-id: incident-id }
      {
        lead-agency: lead-agency,
        participating-agencies: (list lead-agency),
        incident-type: incident-type,
        severity-level: severity-level,
        zone: zone,
        status: "ACTIVE",
        created-at: block-height,
        last-updated: block-height,
        resource-requests: (list)
      }
    )
    (var-set next-incident-id (+ incident-id u1))
    (ok incident-id)
  )
)

(define-public (join-incident-coordination (incident-id uint) (agency-id (string-ascii 20)))
  (let
    (
      (incident (unwrap! (map-get? incident-coordination { incident-id: incident-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? agencies { agency-id: agency-id })) ERR-NOT-FOUND)
    (asserts! (is-eq (get status incident) "ACTIVE") ERR-INVALID-INPUT)

    (map-set incident-coordination
      { incident-id: incident-id }
      (merge incident {
        participating-agencies: (unwrap! (as-max-len? (append (get participating-agencies incident) agency-id) u10) ERR-INVALID-INPUT),
        last-updated: block-height
      })
    )
    (ok true)
  )
)

(define-public (update-agency-resources (agency-id (string-ascii 20)) (personnel-available uint) (current-deployments uint) (max-capacity uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? agencies { agency-id: agency-id })) ERR-NOT-FOUND)
    (asserts! (<= current-deployments max-capacity) ERR-INVALID-INPUT)

    (map-set agency-resources
      { agency-id: agency-id }
      {
        personnel-available: personnel-available,
        equipment-available: (list),
        specialized-capabilities: (list),
        current-deployments: current-deployments,
        max-capacity: max-capacity
      }
    )
    (ok true)
  )
)

(define-public (request-inter-agency-support (requesting-agency (string-ascii 20)) (target-agency (string-ascii 20)) (incident-id uint) (resource-type (string-ascii 50)) (quantity uint))
  (let
    (
      (message-id (var-get next-message-id))
      (incident (unwrap! (map-get? incident-coordination { incident-id: incident-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? agencies { agency-id: requesting-agency })) ERR-NOT-FOUND)
    (asserts! (is-some (map-get? agencies { agency-id: target-agency })) ERR-NOT-FOUND)
    (asserts! (> quantity u0) ERR-INVALID-INPUT)

    ;; Send support request message
    (map-set messages
      { message-id: message-id }
      {
        sender-agency: requesting-agency,
        recipient-agencies: (list target-agency),
        message-type: MESSAGE-REQUEST,
        priority-level: (get severity-level incident),
        subject: "Inter-Agency Support Request",
        content: resource-type,
        incident-reference: (some incident-id),
        timestamp: block-height,
        read-by: (list)
      }
    )

    ;; Update incident with resource request
    (map-set incident-coordination
      { incident-id: incident-id }
      (merge incident {
        resource-requests: (unwrap! (as-max-len? (append (get resource-requests incident) message-id) u20) ERR-INVALID-INPUT),
        last-updated: block-height
      })
    )

    (var-set next-message-id (+ message-id u1))
    (ok message-id)
  )
)

(define-public (update-agency-status (agency-id (string-ascii 20)) (new-status (string-ascii 20)))
  (let
    (
      (agency (unwrap! (map-get? agencies { agency-id: agency-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    (map-set agencies
      { agency-id: agency-id }
      (merge agency {
        status: new-status,
        last-active: block-height
      })
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-agency (agency-id (string-ascii 20)))
  (map-get? agencies { agency-id: agency-id })
)

(define-read-only (get-message (message-id uint))
  (map-get? messages { message-id: message-id })
)

(define-read-only (get-incident-coordination (incident-id uint))
  (map-get? incident-coordination { incident-id: incident-id })
)

(define-read-only (get-agency-resources (agency-id (string-ascii 20)))
  (map-get? agency-resources { agency-id: agency-id })
)

(define-read-only (get-messages-for-agency (agency-id (string-ascii 20)))
  (ok agency-id) ;; Simplified for this implementation
)

(define-read-only (get-active-incidents-for-zone (zone uint))
  (ok zone) ;; Simplified for this implementation
)
