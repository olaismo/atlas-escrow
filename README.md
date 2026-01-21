# atlas-escrow-v1 README

## Overview

**atlas-escrow-v1** is a Stacks smart contract that implements a bilateral escrow system for STX transfers. It enables secure peer-to-peer transactions where funds are locked in the contract and require mutual approval before release, with built-in expiration and admin controls.

## Features

- **Bilateral Approval**: Both sender and recipient must approve before funds are released
- **Flexible Pre-Approval Modifications**: Sender can change recipient or extend expiration before recipient approves
- **Expiration-Based Refunds**: Automatically refundable after expiration date passes
- **Admin Emergency Controls**: Contract admin can cancel escrows and refund senders
- **Approval Revocation**: Either party can revoke their approval while escrow remains open
- **Memo Support**: Document transactions with up to 64 ASCII characters
- **Granular Status Tracking**: Track escrows through Open, Released, Refunded, or Cancelled states

## Core Functions

### Admin Functions

- **`init-admin`** - One-time initialization; sets caller as contract admin
- **`admin-cancel`** - Emergency function: admin cancels an open escrow and refunds sender

### Escrow Management

- **`create-escrow`** - Create and fund a new escrow
- **`approve-release`** - Approve escrow release (sender or recipient)
- **`revoke-approval`** - Revoke your own approval
- **`execute-release`** - Execute release when both parties approve
- **`cancel-escrow`** - Sender cancels before recipient approves
- **`refund-after-expiration`** - Refund sender after escrow expires

### Modifications (Before Recipient Approval)

- **`change-recipient`** - Sender updates recipient address
- **`extend-expiration`** - Sender extends expiration date
- **`update-memo`** - Sender updates transaction memo

### Read-Only Functions

- **`get-escrow`** - Retrieve full escrow details
- **`get-next-escrow-id`** - Get next available escrow ID
- **`get-admin`** - Get current admin principal
- **`get-contract-balance`** - Get total STX held in contract
- **`can-release`** - Check if escrow can be released

## Escrow States

| Status | Value | Description |
|--------|-------|-------------|
| OPEN | 0 | Escrow is active and awaiting approval |
| RELEASED | 1 | Funds transferred to recipient |
| REFUNDED | 2 | Funds refunded to sender after expiration |
| CANCELLED | 3 | Escrow cancelled (sender or admin action) |

## Error Codes

| Error | Code | Meaning |
|-------|------|---------|
| ERR-NOT-AUTHORIZED | 100 | Caller lacks permission |
| ERR-ESCROW-NOT-FOUND | 101 | Escrow ID doesn't exist |
| ERR-NOT-OPEN | 102 | Escrow is not in OPEN status |
| ERR-INVALID-AMOUNT | 103 | Amount is zero or invalid |
| ERR-INVALID-EXPIRATION | 104 | Expiration is invalid |
| ERR-NOT-READY | 105 | Not all required approvals received |
| ERR-NOT-EXPIRED | 106 | Escrow has not expired yet |
| ERR-RECIPIENT-LOCKED | 107 | Recipient has already approved |
| ERR-ADMIN-NOT-SET | 108 | No admin initialized |
| ERR-ADMIN-ALREADY-SET | 109 | Admin already initialized |

## Usage Example

```
1. Alice calls create-escrow(bob, 1000, 1000, "payment for services")
   → Escrow ID 0 created, 1000 STX locked

2. Alice calls approve-release(0)
   → Alice's approval set

3. Bob calls approve-release(0)
   → Bob's approval set

4. Alice or Bob calls execute-release(0)
   → 1000 STX transferred to Bob
```

## Security Considerations

- Funds are locked in contract until conditions are met
- Bilateral approval prevents one-party fraud
- Expiration mechanism prevents indefinite lockups
- Admin can only cancel (not steal); emergency use only
- Pre-approval modifications only allowed before recipient locks in

## Contract Constants

- **MAX MEMO LENGTH**: 64 ASCII characters
- **MINIMUM AMOUNT**: Greater than 0 STX
- **MINIMUM EXPIRATION**: Greater than 0
