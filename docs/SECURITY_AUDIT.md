# Tisaal (Maan Connect) — Comprehensive Security Audit
**Date:** October 14, 2026  
**Target:** Backend (Node.js/TypeScript), Database (SQLite), Protocol (WebSocket/WebRTC), Mobile Client (Flutter/Android)  
**Status:** Audit Completed & Stabilized

---

## 1. Executive Summary

This security audit assesses the **Tisaal / Maan Connect** phone-number-free global communication system against modern threat models for decentralized and identity-based communication platforms.

### Key Audit Conclusions:
1. **Zero-PII Compliance (VERIFIED):**
   - The application does not collect, request, or store mobile phone numbers, email addresses, IMEI, IMSI, or SIM card identifiers.
   - User identity is rooted entirely in cryptographic key pairs (Ed25519) and BIP-39 recovery mnemonics.
2. **Authentication & Nonce Security (VERIFIED & HARDENED):**
   - Challenge-response authentication requires signing a random 32-byte cryptographic nonce using the client's Ed25519 private key.
   - Nonces are now strictly **single-use** (deleted immediately upon consumption), eliminating replay attacks.
   - Nonce expiration is strictly enforced at 5 minutes.
3. **Username Collision & Case Sensitivity (VERIFIED & FIXED):**
   - Fixed SQLite case-sensitivity issue by applying `COLLATE NOCASE` and case-insensitive uniqueness checks to prevent username spoofing (e.g. `Usman` vs `usman`).
4. **Transport vs End-to-End Encryption (VERIFIED & IMPLEMENTED FOR 1-TO-1 CHAT):**
   - **Current State:** 1-to-1 direct messaging payloads are end-to-end encrypted on the client using X25519 Diffie-Hellman, HKDF-SHA256, and ChaCha20-Poly1305 AEAD with Authenticated Associated Data (AAD).
   - **Database State:** The backend stores only ciphertext envelopes (`ephemeral_public_key`, `nonce`, `ciphertext`, `auth_tag`) in SQLite. Plaintext is never stored, logged, or visible on the server.
   - **Explicit Scope Boundary:** Group messaging, multi-device sync, and binary attachment encryption remain future roadmap milestones.
5. **WebRTC Background Limitations (TRANSPARENT DISCLOSURE):**
   - WebSocket connections only stay active while the Android app is foregrounded.
   - Without Google Firebase Cloud Messaging (FCM) high-priority data pushes and Android `ConnectionService` (Telecom API), incoming calls cannot wake up a terminated or deeply sleeping Android device.

---

## 2. Threat Analysis & Vulnerability Findings

### Finding SEC-01: Nonce Replay & Brute Force Vulnerability
- **Severity:** High (Fixed)
- **Component:** `backend/src/routes/auth.routes.ts`
- **Pre-Fix Behavior:** Nonces were deleted only after a successful signature check. If an attacker provided an invalid signature, the nonce remained in the database until expiration, permitting repeated offline/online signature attack attempts on the same challenge.
- **Remediation:** Nonces are now deleted **immediately upon first validation attempt** regardless of outcome, ensuring 100% single-use challenge guarantees.

### Finding SEC-02: Username Collision & Homograph Spoofing
- **Severity:** Medium (Fixed)
- **Component:** `backend/src/db/database.ts` & `auth.routes.ts`
- **Pre-Fix Behavior:** SQLite's default `TEXT UNIQUE` constraint is case-sensitive, allowing `Alice` and `alice` to register as distinct accounts.
- **Remediation:** Added `COLLATE NOCASE` to `users.username` and enforced strict regex validation (`^[a-zA-Z0-9_-]{3,30}$`) prohibiting whitespace, control characters, or Unicode confusable characters.

### Finding SEC-03: Missing Rate Limiting on Auth & Challenge Endpoints
- **Severity:** Medium (Fixed)
- **Component:** `backend/src/routes/auth.routes.ts`
- **Pre-Fix Behavior:** Endpoints `/api/auth/challenge`, `/api/auth/register`, and `/api/auth/login` lacked rate limits, leaving the service open to denial-of-service and database exhaustion.
- **Remediation:** Added an in-memory sliding-window IP rate limiter limiting requests to 60/minute per IP address with automated HTTP 429 throttling.

### Finding SEC-04: Android Missing Hardware & Network Permissions
- **Severity:** High (Fixed)
- **Component:** `mobile/android/app/src/main/AndroidManifest.xml`
- **Pre-Fix Behavior:** The manifest lacked `INTERNET`, `RECORD_AUDIO`, `CAMERA`, `MODIFY_AUDIO_SETTINGS`, and `ACCESS_NETWORK_STATE`. On actual Android hardware, WebRTC calls crashed immediately due to security exceptions.
- **Remediation:** Added all required permissions, camera/microphone hardware feature declarations (`android:required="false"` for tablet/emulator compatibility), and cleartext traffic support for local debugging.

### Finding SEC-05: Missing JWT Secret Guard in Production
- **Severity:** Medium (Fixed)
- **Component:** `backend/src/crypto/auth.ts`
- **Pre-Fix Behavior:** Default fallback secret `'tisaal-secure-dev-secret-key-32chars!'` was active without enforcing an environment variable in production mode.
- **Remediation:** Added strict check throwing a fatal error on startup if `NODE_ENV === 'production'` and the default development secret is in use.

### Finding SEC-06: WebSocket Message Length & Block List Enforcement
- **Severity:** Low (Fixed)
- **Component:** `backend/src/ws/signaling.ts`
- **Pre-Fix Behavior:** WebSocket chat messages had no size caps and did not check if the recipient had blocked the sender.
- **Remediation:** Enforced a 5,000-character cap per text payload and added an automated database check rejecting messages and call signaling if the target user has blocked the sender.

### Finding SEC-07: Plaintext Message Exposure in Server Storage
- **Severity:** High (Fixed via E2EE)
- **Component:** `backend/src/db/database.ts`, `backend/src/ws/signaling.ts`, `mobile/lib/core/crypto/crypto_service.dart`
- **Pre-Fix Behavior:** Messages passing through WebSockets and stored in the backend SQLite database were plain UTF-8 text strings, exposing sensitive user communication to database leaks or server compromises.
- **Remediation:** Implemented RFC 7748 X25519 Diffie-Hellman key agreement, RFC 5869 HKDF-SHA256, and RFC 8439 ChaCha20-Poly1305 AEAD authenticated encryption on the client. The server now exclusively receives and persists ciphertext envelopes (`ephemeral_public_key`, `nonce`, `ciphertext`, `auth_tag`) with zero plaintext storage.

### Finding SEC-08: Cryptographic Boundary: Recipient Forward Secrecy & Post-Compromise Security Limitation
- **Severity:** Medium (Documented Protocol Limitation)
- **Component:** `mobile/lib/core/crypto/crypto_service.dart`
- **Audit Analysis:** The 1-pass envelope scheme provides **Sender Forward Secrecy** because the sender's ephemeral private key is deleted immediately. However, it computes $\text{X25519}(b, E)$ where $b$ is the recipient's static private encryption key. If $b$ is compromised at any future time $T$, an adversary with recorded historical envelopes can retroactively decrypt all past messages sent to that recipient.
- **Remediation / Roadmap:** The system must not claim full bi-directional forward secrecy or post-compromise break-in recovery. The roadmap designates Phase 2 for integrating an audited Double Ratchet implementation (`vodozemac` or `libsignal-client`).

### Finding SEC-09: Server Key-Substitution Man-in-the-Middle (MitM) Risk
- **Severity:** Medium (Mitigated via TOFU)
- **Component:** `mobile/lib/providers/chat_provider.dart`
- **Audit Analysis:** Because peer public encryption keys are queried from the server directory, a compromised server could theoretically attempt to substitute Bob's public encryption key with an attacker-controlled key.
- **Remediation:** Implemented Trust-On-First-Use (TOFU) key pinning in `ChatProvider`. If a peer's public encryption key changes after the initial conversation, an in-chat security alert is immediately presented to the user (`⚠️ Security Notice: The recipient identity encryption key has changed since your last conversation. Verify their identity out-of-band.`).

---

## 3. Cryptographic Verification Matrix

| Component | Standard / Algorithm | Verified Status |
| :--- | :--- | :--- |
| **Mnemonic Phrase** | BIP-39 (12-word, 128-bit entropy) | **PASS** (Deterministic Dart implementation) |
| **Key Derivation** | Seed (512-bit) -> 32-byte Ed25519 Seed + 32-byte X25519 Seed | **PASS** (Domain separation verified) |
| **Identity Signing** | Ed25519 (RFC 8032 / Pure JS & Dart) | **PASS** (Cross-verified in test suite) |
| **Key Agreement** | X25519 ECDH (RFC 7748) | **PASS** (Ephemeral-static 1-DH key exchange) |
| **Key Derivation (KDF)** | HKDF-SHA256 (RFC 5869) | **PASS** (32-byte symmetric key derivation) |
| **Authenticated Cipher** | ChaCha20-Poly1305 AEAD (RFC 8439) | **PASS** (12-byte nonce, 16-byte MAC, AAD bound) |
| **Sender Forward Secrecy** | Ephemeral X25519 key destroyed post-encryption | **PASS** (Sender past messages secure) |
| **Recipient Forward Secrecy** | Requires asymmetric DH ratchet step | **KNOWN LIMITATION** (Phase 2 Double Ratchet roadmap) |
| **MitM Protection** | TOFU key pinning + In-chat alert on key change | **PASS** (Key substitution detected) |
| **Account ID** | SHA-256 (`acc_` + first 16 hex chars) | **PASS** (Deterministic & unique) |
| **Session Tokens** | HMAC-SHA256 (JWT, 30-day expiry) | **PASS** (Tampering rejected) |
| **Call Media** | WebRTC DTLS 1.2 / SRTP | **PASS** (Standard WebRTC peer protocol) |
| **Scope Coverage** | 1-to-1 Direct Messaging | **PASS** (Group chat & attachments are future roadmap items) |

---

## 4. Zero-Logging & Privacy Verification
- Verified that private keys, BIP-39 mnemonics, seed bytes, and raw JWT secrets are **never** logged to stdout, stderr, or logfiles.
- The backend SQLite database stores only public keys (`public_key TEXT`, `public_encryption_key TEXT`), deterministic account IDs, usernames, and ciphertext envelopes.
- Message plaintext is never logged in server debug statements or persisted to disk.
