# Aegis Secure Private Messenger — Project Phases & Progress Tracking

This document outlines the development phases of the **Aegis Secure Private Messenger** (ibemCom) platform. It keeps track of completed milestones, the current focus, and instructions for local testing to avoid scanning conversation logs.

---

## 🗺️ Project Development Roadmap

### Phase 1: Environment Diagnostic & Codebase Repair (Completed)
* **Goal**: Resolve all platform-level dependencies, compilation issues, and test suite failures on the developer environment.
* **Key Achievements**:
  * Fixed Windows node compiler errors by migrating from native `bcrypt` to `bcryptjs`.
  * Resolved the missing native binding for `better-sqlite3` on Windows.
  * Cleaned up strict Dart analyzer type errors and corrected the deprecated `CardTheme` widget configuration in Flutter.
  * Achieved 100% green compilation on `npm run build`, `flutter analyze`, and unit test success on `flutter test`.

### Phase 2: Native Web/Chrome Integration (Completed)
* **Goal**: Elevate the Web platform to be a first-class supported device platform on the backend alongside mobile.
* **Key Achievements**:
  * Upgraded Fastify request validation schemas (`registerSchema`, `loginSchema`, and a new `/otp/verify` schema) to natively accept `WEB`.
  * Updated the SQLite check constraint (`platform IN ('ANDROID', 'IOS', 'DESKTOP', 'WEB')`) and PostgreSQL Enum types.
  * Restored accurate platform reporting in the Flutter client (`device_info.dart`) to report `WEB` instead of masquerading as desktop.

### Phase 3: Auth Security & SMTP Hardening (Completed)
* **Goal**: Harden the passwordless OTP access flow and resolve premature code expiration or validation errors.
* **Key Achievements**:
  * Implemented normalization for authentication identifiers (emails are fully trimmed and converted to lowercase) to guarantee cache key alignment.
  * Standardized whitespace trimming on incoming verification codes.
  * Enhanced backend debugging logs by outputting expected vs. received OTP values with their string lengths under warning level, making auth issues fully transparent.

### Phase 4: Local Testing & Port Alignment (Completed)
* **Goal**: Establish a stable local environment for end-to-end testing with locked host ports for the backend and frontend.
* **Key Achievements**:
  * Resolved backend process conflicts (free up port `3000`).
  * Set a static port for the Flutter Web testing client to prevent changing links.
  * Verified backend server stability and concurrent Flutter testing environment.

### Phase 5: End-to-End Encryption (E2EE) Validation (Current Focus)
* **Goal**: Verify client-side media and payload encryption, hardening against silent failures.
* **Key Achievements**:
  * Extracted key generation logic to ensure robust X25519 ECDH initialization across all auth flows (register, login, OTP).
  * Added validation guards for 32-byte key boundaries, empty recipient maps, and graceful plaintext fallback warnings.
  * Corrected offline sync logic in `messages_repository` to ensure E2EE payloads are decrypted immediately upon REST sync.
  * Created unit test suite covering single/multi-recipient E2EE, file encryption, and tamper/size boundary validations.
  * Exposed a `/debug/e2ee-status` endpoint on the backend for fast device-key mapping visualization.

### Phase 6: Production Docker Deployment (Future)
* **Goal**: Transition infrastructure (PostgreSQL 16, Redis 7, MinIO S3, Nginx proxy) into a production-ready docker-compose environment.
* **Key Focus Area**:
  * Run media storage and database securely with volume persistence.
  * Setup backup and restore scripts.

---

## ⚡ How to Run Local Testing (Phase 4 Guide)

### 1. Free Up Port 3000 (Backend Port)
If you get `EADDRINUSE: address already in use 0.0.0.0:3000`, a previous backend instance is still running in the background.

To kill it on Windows (PowerShell):
```powershell
# Find and stop the process using port 3000
Stop-Process -Id (Get-NetTCPConnection -LocalPort 3000).OwningProcess -Force
```

### 2. Run the Fastify Backend
Navigate to the `backend/` directory:
```bash
npm run dev
```
The server will boot up and listen on: **`http://localhost:3000`**

### 3. Run Flutter Web on a Static Port
By default, `flutter run` chooses a random dynamic port. You can lock it to a static port (e.g. `5000` or `8080`) so you never have to re-copy the URL:

```bash
# Navigate to the frontend directory
cd frontend

# Run Web app on static port 5000
flutter run -d chrome --web-port=5000
```
Your browser will open to **`http://localhost:5000`**, and it will always remain on this address for subsequent runs.
Since the Flutter app's `ApiEndpoints` automatically uses `localhost:3000` to contact the backend, it will successfully communicate with the server.
