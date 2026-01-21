;; ============================
;; Contract: atlas-escrow-v1
;; ============================

;; ----------------------------
;; Errors
;; ----------------------------
(define-constant ERR-NOT-AUTHORIZED        u100)
(define-constant ERR-ESCROW-NOT-FOUND      u101)
(define-constant ERR-NOT-OPEN              u102)
(define-constant ERR-INVALID-AMOUNT        u103)
(define-constant ERR-INVALID-EXPIRATION    u104)
(define-constant ERR-NOT-READY             u105)
(define-constant ERR-NOT-EXPIRED           u106)
(define-constant ERR-RECIPIENT-LOCKED      u107)
(define-constant ERR-ADMIN-NOT-SET         u108)
(define-constant ERR-ADMIN-ALREADY-SET     u109)

;; ----------------------------
;; Status codes
;; ----------------------------
(define-constant STATUS-OPEN      u0)
(define-constant STATUS-RELEASED  u1)
(define-constant STATUS-REFUNDED  u2)
(define-constant STATUS-CANCELLED u3)

;; ----------------------------
;; State
;; ----------------------------
(define-data-var escrow-nonce uint u0)
(define-data-var admin (optional principal) none)

(define-map escrows
  uint
  {
    sender: principal,
    recipient: principal,
    amount: uint,
    created-at: uint,
    expiration: uint,
    status: uint,
    sender-approve: bool,
    recipient-approve: bool,
    memo: (string-ascii 64)
  }
)

;; ----------------------------
;; Private helpers
;; ----------------------------
(define-private (contract-principal)
  ;; Evaluate `tx-sender` in the contract context to obtain the contract principal
  (as-contract tx-sender)
)

(define-private (is-open (status uint))
  (is-eq status STATUS-OPEN)
)

(define-private (assert-open (e
  {
    sender: principal,
    recipient: principal,
    amount: uint,
    created-at: uint,
    expiration: uint,
    status: uint,
    sender-approve: bool,
    recipient-approve: bool,
    memo: (string-ascii 64)
  }))
  (if (is-open (get status e))
    (ok true)
    (err ERR-NOT-OPEN)
  )
)

(define-private (require-admin)
  (let ((a (var-get admin)))
    (asserts! (is-some a) (err ERR-ADMIN-NOT-SET))
    (asserts! (is-eq tx-sender (unwrap-panic a)) (err ERR-NOT-AUTHORIZED))
    (ok true)
  )
)

;; ----------------------------
;; Admin
;; ----------------------------

;; One-time initialization: first time only, and must set yourself as admin
(define-public (init-admin)
  (begin
    (asserts! (is-none (var-get admin)) (err ERR-ADMIN-ALREADY-SET))
    (var-set admin (some tx-sender))
    (print { event: "admin-initialized", admin: tx-sender })
    (ok true)
  )
)

;; Emergency: admin cancels an OPEN escrow and refunds sender
(define-public (admin-cancel (escrow-id uint))
  (begin
    (try! (require-admin))

    (let ((escrow-opt (map-get? escrows escrow-id)))
      (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

      (let ((e (unwrap-panic escrow-opt)))
        (try! (assert-open e))

        (try!
          (stx-transfer?
            (get amount e)
            (contract-principal)
            (get sender e)
          )
        )

        (map-set escrows escrow-id (merge e { status: STATUS-CANCELLED }))
        (print { event: "admin-cancelled", escrow-id: escrow-id })
        (ok true)
      )
    )
  )
)

;; ----------------------------
;; Core escrow actions
;; ----------------------------

;; Create an escrow and lock STX in this contract
(define-public (create-escrow
  (recipient principal)
  (amount uint)
  (expiration uint)
  (memo (string-ascii 64))
)
  (begin
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (> expiration u0) (err ERR-INVALID-EXPIRATION))
    (asserts! (is-some (some recipient)) (err ERR-NOT-AUTHORIZED))
    (asserts! (> (len memo) u0) (err ERR-INVALID-AMOUNT))

    (let ((id (var-get escrow-nonce)))
      ;; Lock STX in contract
      (try! (stx-transfer? amount tx-sender (contract-principal)))

      (map-set escrows id
        {
          sender: tx-sender,
          recipient: recipient,
          amount: amount,
          created-at: u0,
          expiration: expiration,
          status: STATUS-OPEN,
          sender-approve: false,
          recipient-approve: false,
          memo: memo
        }
      )

      (var-set escrow-nonce (+ id u1))
      (print { event: "escrow-created", escrow-id: id, sender: tx-sender, recipient: recipient, amount: amount })
      (ok id)
    )
  )
)

;; Approve release (either sender or recipient can approve)
(define-public (approve-release (escrow-id uint))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))

      (if (is-eq tx-sender (get sender e))
          (begin
            (map-set escrows escrow-id (merge e { sender-approve: true }))
            (print { event: "approved", escrow-id: escrow-id, by: tx-sender, role: "sender" })
            (ok true)
          )
          (if (is-eq tx-sender (get recipient e))
              (begin
                (map-set escrows escrow-id (merge e { recipient-approve: true }))
                (print { event: "approved", escrow-id: escrow-id, by: tx-sender, role: "recipient" })
                (ok true)
              )
              (err ERR-NOT-AUTHORIZED)
          )
      )
    )
  )
)

;; Revoke approval (either sender or recipient can revoke their own approval)
(define-public (revoke-approval (escrow-id uint))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))

      (if (is-eq tx-sender (get sender e))
          (begin
            (map-set escrows escrow-id (merge e { sender-approve: false }))
            (print { event: "revoked", escrow-id: escrow-id, by: tx-sender, role: "sender" })
            (ok true)
          )
          (if (is-eq tx-sender (get recipient e))
              (begin
                (map-set escrows escrow-id (merge e { recipient-approve: false }))
                (print { event: "revoked", escrow-id: escrow-id, by: tx-sender, role: "recipient" })
                (ok true)
              )
              (err ERR-NOT-AUTHORIZED)
          )
      )
    )
  )
)

;; Execute release: requires BOTH approvals; sender or recipient can trigger execution
(define-public (execute-release (escrow-id uint))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))

      (asserts!
        (or (is-eq tx-sender (get sender e)) (is-eq tx-sender (get recipient e)))
        (err ERR-NOT-AUTHORIZED)
      )

      (asserts!
        (and (get sender-approve e) (get recipient-approve e))
        (err ERR-NOT-READY)
      )

      (try!
        (stx-transfer?
          (get amount e)
          (contract-principal)
          (get recipient e)
        )
      )

      (map-set escrows escrow-id (merge e { status: STATUS-RELEASED }))
      (print { event: "escrow-released", escrow-id: escrow-id })
      (ok true)
    )
  )
)

;; Sender cancel: only allowed while OPEN and before recipient approves
(define-public (cancel-escrow (escrow-id uint))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))

      (asserts! (is-eq tx-sender (get sender e)) (err ERR-NOT-AUTHORIZED))
      (asserts! (not (get recipient-approve e)) (err ERR-RECIPIENT-LOCKED))

      (try!
        (stx-transfer?
          (get amount e)
          (contract-principal)
          (get sender e)
        )
      )

      (map-set escrows escrow-id (merge e { status: STATUS-CANCELLED }))
      (print { event: "escrow-cancelled", escrow-id: escrow-id })
      (ok true)
    )
  )
)

;; Refund after expiration: sender or recipient can trigger, funds go back to sender
(define-public (refund-after-expiration (escrow-id uint))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))

      (asserts!
        (or (is-eq tx-sender (get sender e)) (is-eq tx-sender (get recipient e)))
        (err ERR-NOT-AUTHORIZED)
      )

      (asserts! (>= u0 (get expiration e)) (err ERR-NOT-EXPIRED))

      (try!
        (stx-transfer?
          (get amount e)
          (contract-principal)
          (get sender e)
        )
      )

      (map-set escrows escrow-id (merge e { status: STATUS-REFUNDED }))
      (print { event: "escrow-refunded", escrow-id: escrow-id })
      (ok true)
    )
  )
)

;; Extend expiration: sender only, must increase and remain in the future
(define-public (extend-expiration (escrow-id uint) (new-expiration uint))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))
      (asserts! (is-eq tx-sender (get sender e)) (err ERR-NOT-AUTHORIZED))
      (asserts! (> new-expiration u0) (err ERR-INVALID-EXPIRATION))
      (asserts! (> new-expiration (get expiration e)) (err ERR-INVALID-EXPIRATION))

      (map-set escrows escrow-id (merge e { expiration: new-expiration }))
      (print { event: "expiration-extended", escrow-id: escrow-id, expiration: new-expiration })
      (ok true)
    )
  )
)

;; Change recipient: sender only, only before recipient approval
(define-public (change-recipient (escrow-id uint) (new-recipient principal))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))
      (asserts! (is-eq tx-sender (get sender e)) (err ERR-NOT-AUTHORIZED))
      (asserts! (not (get recipient-approve e)) (err ERR-RECIPIENT-LOCKED))

      (map-set escrows escrow-id (merge e { recipient: new-recipient }))
      (print { event: "recipient-changed", escrow-id: escrow-id, recipient: new-recipient })
      (ok true)
    )
  )
)

;; Update memo: sender only, while OPEN
(define-public (update-memo (escrow-id uint) (new-memo (string-ascii 64)))
  (let ((escrow-opt (map-get? escrows escrow-id)))
    (asserts! (is-some escrow-opt) (err ERR-ESCROW-NOT-FOUND))

    (let ((e (unwrap-panic escrow-opt)))
      (try! (assert-open e))
      (asserts! (is-eq tx-sender (get sender e)) (err ERR-NOT-AUTHORIZED))

      (map-set escrows escrow-id (merge e { memo: new-memo }))
      (print { event: "memo-updated", escrow-id: escrow-id })
      (ok true)
    )
  )
)

;; ----------------------------
;; Read-only helpers
;; ----------------------------

(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows escrow-id)
)

(define-read-only (get-next-escrow-id)
  (var-get escrow-nonce)
)

(define-read-only (get-admin)
  (var-get admin)
)

(define-read-only (get-contract-balance)
  (stx-get-balance (contract-principal))
)

(define-read-only (can-release (escrow-id uint))
  (match (map-get? escrows escrow-id)
    e (and (is-open (get status e)) (get sender-approve e) (get recipient-approve e))
    false
  )
)
