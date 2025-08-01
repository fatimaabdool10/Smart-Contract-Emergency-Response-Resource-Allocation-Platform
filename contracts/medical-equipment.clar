;; Medical Equipment Distribution Contract
;; Allocates ventilators, PPE, and other critical supplies during health crises

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INSUFFICIENT-INVENTORY (err u103))
(define-constant ERR-ALREADY-EXISTS (err u104))

;; Equipment Types
(define-constant EQUIPMENT-VENTILATOR u1)
(define-constant EQUIPMENT-PPE u2)
(define-constant EQUIPMENT-OXYGEN u3)
(define-constant EQUIPMENT-MEDICATION u4)
(define-constant EQUIPMENT-TESTING-KITS u5)

;; Data Variables
(define-data-var next-request-id uint u1)
(define-data-var emergency-mode bool false)

;; Data Maps
(define-map equipment-inventory
  { equipment-type: uint, facility-id: (string-ascii 20) }
  {
    current-stock: uint,
    reserved-stock: uint,
    minimum-threshold: uint,
    last-updated: uint
  }
)

(define-map facilities
  { facility-id: (string-ascii 20) }
  {
    name: (string-ascii 100),
    facility-type: (string-ascii 20),
    zone: uint,
    priority-level: uint,
    contact-info: (string-ascii 100)
  }
)

(define-map equipment-requests
  { request-id: uint }
  {
    facility-id: (string-ascii 20),
    equipment-type: uint,
    quantity-requested: uint,
    quantity-approved: uint,
    priority-level: uint,
    status: (string-ascii 20),
    requested-at: uint,
    approved-at: (optional uint)
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

(define-public (register-facility (facility-id (string-ascii 20)) (name (string-ascii 100)) (facility-type (string-ascii 20)) (zone uint) (priority-level uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= zone u1) (<= zone u10)) ERR-INVALID-INPUT)
    (asserts! (and (>= priority-level u1) (<= priority-level u5)) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? facilities { facility-id: facility-id })) ERR-ALREADY-EXISTS)

    (map-set facilities
      { facility-id: facility-id }
      {
        name: name,
        facility-type: facility-type,
        zone: zone,
        priority-level: priority-level,
        contact-info: ""
      }
    )
    (ok true)
  )
)

(define-public (update-inventory (equipment-type uint) (facility-id (string-ascii 20)) (stock-amount uint) (minimum-threshold uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= equipment-type u1) (<= equipment-type u5)) ERR-INVALID-INPUT)
    (asserts! (is-some (map-get? facilities { facility-id: facility-id })) ERR-NOT-FOUND)

    (map-set equipment-inventory
      { equipment-type: equipment-type, facility-id: facility-id }
      {
        current-stock: stock-amount,
        reserved-stock: u0,
        minimum-threshold: minimum-threshold,
        last-updated: block-height
      }
    )
    (ok true)
  )
)

(define-public (request-equipment (facility-id (string-ascii 20)) (equipment-type uint) (quantity uint) (priority-level uint))
  (let
    (
      (request-id (var-get next-request-id))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= equipment-type u1) (<= equipment-type u5)) ERR-INVALID-INPUT)
    (asserts! (and (>= priority-level u1) (<= priority-level u5)) ERR-INVALID-INPUT)
    (asserts! (> quantity u0) ERR-INVALID-INPUT)
    (asserts! (is-some (map-get? facilities { facility-id: facility-id })) ERR-NOT-FOUND)

    (map-set equipment-requests
      { request-id: request-id }
      {
        facility-id: facility-id,
        equipment-type: equipment-type,
        quantity-requested: quantity,
        quantity-approved: u0,
        priority-level: priority-level,
        status: "PENDING",
        requested-at: block-height,
        approved-at: none
      }
    )
    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

(define-public (approve-equipment-request (request-id uint) (approved-quantity uint) (source-facility-id (string-ascii 20)))
  (let
    (
      (request (unwrap! (map-get? equipment-requests { request-id: request-id }) ERR-NOT-FOUND))
      (inventory-key { equipment-type: (get equipment-type request), facility-id: source-facility-id })
      (source-inventory (unwrap! (map-get? equipment-inventory inventory-key) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "PENDING") ERR-INVALID-INPUT)
    (asserts! (<= approved-quantity (get quantity-requested request)) ERR-INVALID-INPUT)
    (asserts! (>= (get current-stock source-inventory) approved-quantity) ERR-INSUFFICIENT-INVENTORY)

    ;; Update source inventory
    (map-set equipment-inventory
      inventory-key
      (merge source-inventory {
        current-stock: (- (get current-stock source-inventory) approved-quantity),
        last-updated: block-height
      })
    )

    ;; Update request status
    (map-set equipment-requests
      { request-id: request-id }
      (merge request {
        quantity-approved: approved-quantity,
        status: "APPROVED",
        approved-at: (some block-height)
      })
    )

    ;; Update destination inventory
    (let
      (
        (dest-inventory-key { equipment-type: (get equipment-type request), facility-id: (get facility-id request) })
        (dest-inventory (default-to
          { current-stock: u0, reserved-stock: u0, minimum-threshold: u0, last-updated: block-height }
          (map-get? equipment-inventory dest-inventory-key)
        ))
      )
      (map-set equipment-inventory
        dest-inventory-key
        (merge dest-inventory {
          current-stock: (+ (get current-stock dest-inventory) approved-quantity),
          last-updated: block-height
        })
      )
    )
    (ok true)
  )
)

(define-public (set-emergency-mode (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set emergency-mode enabled)
    (ok true)
  )
)

(define-public (emergency-redistribute (equipment-type uint) (from-facility (string-ascii 20)) (to-facility (string-ascii 20)) (quantity uint))
  (let
    (
      (source-key { equipment-type: equipment-type, facility-id: from-facility })
      (dest-key { equipment-type: equipment-type, facility-id: to-facility })
      (source-inventory (unwrap! (map-get? equipment-inventory source-key) ERR-NOT-FOUND))
      (dest-inventory (default-to
        { current-stock: u0, reserved-stock: u0, minimum-threshold: u0, last-updated: block-height }
        (map-get? equipment-inventory dest-key)
      ))
    )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (var-get emergency-mode) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get current-stock source-inventory) quantity) ERR-INSUFFICIENT-INVENTORY)

    ;; Update source inventory
    (map-set equipment-inventory
      source-key
      (merge source-inventory {
        current-stock: (- (get current-stock source-inventory) quantity),
        last-updated: block-height
      })
    )

    ;; Update destination inventory
    (map-set equipment-inventory
      dest-key
      (merge dest-inventory {
        current-stock: (+ (get current-stock dest-inventory) quantity),
        last-updated: block-height
      })
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-facility (facility-id (string-ascii 20)))
  (map-get? facilities { facility-id: facility-id })
)

(define-read-only (get-inventory (equipment-type uint) (facility-id (string-ascii 20)))
  (map-get? equipment-inventory { equipment-type: equipment-type, facility-id: facility-id })
)

(define-read-only (get-equipment-request (request-id uint))
  (map-get? equipment-requests { request-id: request-id })
)

(define-read-only (is-emergency-mode)
  (ok (var-get emergency-mode))
)

(define-read-only (check-critical-shortages (equipment-type uint) (facility-id (string-ascii 20)))
  (match (map-get? equipment-inventory { equipment-type: equipment-type, facility-id: facility-id })
    inventory (ok {
      is-critical: (< (get current-stock inventory) (get minimum-threshold inventory)),
      current-stock: (get current-stock inventory),
      minimum-threshold: (get minimum-threshold inventory)
    })
    ERR-NOT-FOUND
  )
)
