# Aegis Secure Messenger (ibemCom) — Comprehensive Architecture & Handoff Guide

This document provides a detailed overview of the **Aegis Secure Messenger** (also known as `ibemCom`) application, covering the architecture, security protocols, database schemas, local setup, completed achievements, and next steps. It is designed to get any developer or AI up to speed on the codebase immediately.

---

## 🗺️ System Architecture

Aegis is a secure, private communication suite designed for 2–10 users. It operates on a self-hosted client-server architecture with strict End-to-End Encryption (E2EE).

```mermaid
flowchart TD
    subgraph Client ["Aegis Flutter Client"]
        UI["Flutter Presentation Layer"]
        Repo["Messages & Chats Repositories"]
        Drift["Local SQLite (Drift)"]
        Crypto["CryptoService (AES-256-GCM / X25519)"]
    end

    subgraph Backend ["Aegis Fastify Server"]
        Router["Fastify Routing & Middleware"]
        AuthM["Auth Plugin (JWT / ROTP)"]
        MediaM["Media Handler (Sharp / File-Type)"]
        SocketM["Socket.IO Real-time Handler"]
        DB["PostgreSQL / SQLite Database"]
    end

    subgraph Storage ["Storage Layer"]
        LocalU["Local uploads/ directory (MinIO Stub)"]
        MinIO["MinIO S3 Bucket (Future Production)"]
    end

    UI <--> Repo
    Repo <--> Drift
    Repo <--> Crypto
    
    Repo <-->|Socket.IO (Events)| SocketM
    Repo <-->|REST API (Dio)| Router
    Router <--> DB
    Router <--> MediaM
    
    MediaM <-->|Save raw/processed files| LocalU
    MediaM <-->|Pre-signed URLs| MinIO
```

---

## 📂 Codebase File Map

The workspace is organized into two primary sub-projects: `frontend` (Flutter client) and `backend` (Fastify API server).

### 1. Frontend: Flutter Client ([c:\aegis\frontend](file:///c:/aegis/frontend))
* **`lib/main.dart`**: Application entry point initializing Drift DB, Riverpod providers, and Router.
* **`lib/app/`**
  * **`router.dart`**: Navigation routing with `GoRouter` (e.g., Auth paths, Chat Room, Profile Dashboard).
  * **`theme.dart`**: Unified typography (`Outfit` / `Inter`), harmonized colors, and custom glassmorphism style rules.
* **`lib/core/`**
  * **`database/local_database.dart`**: Local Drift/SQLite schema defining tables `local_chats`, `local_messages`, and `sync_queue`.
  * **`network/`**:
    * `api_client.dart`: Network interface with JWT token validation and dynamic headers.
    * `socket_client.dart`: Socket.IO client wrapping message queues and ack handlers.
  * **`secure_storage/`**: Secure keys, user IDs, device fingerprints, and local secrets stored via `flutter_secure_storage`.
  * **`security/crypto_service.dart`**: Core cryptographic engine performing AES-256-GCM encryption/decryption and X25519 key agreements.
* **`lib/features/`**
  * **`auth/`**: Sign-in/Sign-up logic, device fingerprinting, and OTP verification widgets.
  * **`chats/`**: Active conversation directories and home page list displaying recipient avatars and previews.
  * **`messages/`**: Chat room viewport, voice note recorder, attachment selection tray, and decrypted image/video widgets.
  * **`profile/`**: User settings screen containing the avatar cropper, password updater, session manager, and recovery key generation.

### 2. Backend: Fastify Server ([c:\aegis\backend](file:///c:/aegis/backend))
* **`src/server.ts`**: Bootstrap script reading `.env` and launching the server on port `3000`.
* **`src/app.ts`**: Fastify builder declaring global plugins (CORS, Helmet, Static directories) and error handlers.
* **`src/plugins/`**
  * `database.plugin.ts`: DB Connection client supporting PostgreSQL (production) or SQLite (local development).
  * `minio.plugin.ts`: Upload client wrapper (currently stubbed to write directly to `/uploads`).
  * `auth.plugin.ts`: JWT verification hook injecting user details into Fastify request contexts.
  * `rate-limit.plugin.ts`: Limits `/api/media` uploads to a maximum of 5 requests per minute per IP.
  * `socket.plugin.ts`: Instantiates real-time message routing.
* **`src/modules/`**
  * **`auth/`**: Passwordless OTP generation, validation, and registration routes.
  * **`users/`**: Password updating, active sessions list, remote session revocation, and master recovery key matching.
  * **`chats/`**: Group creation, participant joins, and key distribution endpoints.
  * **`devices/`**: Trust states, public key declarations, and device fingerprint validations.
  * **`messages/`**: REST fallbacks for chat room synchronization and delivery logging.
  * **`media/`**: Endpoint for requesting upload/download signed URLs and executing file type/format inspections.

---

## 🔒 Cryptographic & Security Protocols

Aegis relies on a hybrid encryption model ensuring zero-knowledge storage for message bodies and files.

### 1. Hybrid E2EE Messaging Protocol
When a client sends a message in a chat room:
1. **Message Key Generation**: The client generates a cryptographically secure, random 256-bit message key ($K_{msg}$) and a 96-bit (12-byte) initialization vector ($IV$).
2. **Payload Encryption**: The message content is encrypted using $K_{msg}$ and $IV$ under the **AES-256-GCM** algorithm.
3. **Key Agreement (X25519)**:
   * The client fetches the X25519 public keys for all recipient devices belonging to the chat participants.
   * For each recipient device, the sender calculates a shared secret using their own private key and the recipient's public key (ECDH).
   * A unique symmetric AES key is derived from the shared secret using **HKDF SHA-256** with the info string `"Aegis-E2EE-Key-Exchange"`.
   * $K_{msg}$ is encrypted under the derived key.
4. **Envelope Packaging**: An E2EE envelope JSON payload is sent over Socket.IO:
   ```json
   {
     "sender_device_id": "UUID",
     "ciphertext": "base64(ciphertext + MAC)",
     "iv": "base64(bodyIv)",
     "keys": {
       "recipient_device_id_1": {
         "key": "base64(encrypted K_msg + MAC)",
         "iv": "base64(keyIv)"
       }
     }
   }
   ```
5. **Decryption**: The recipient device uses its local private key and the sender's public key to derive the shared secret, decrypts $K_{msg}$ using the corresponding entry in the `"keys"` map, and uses $K_{msg}$ to decrypt the message ciphertext.

### 2. Client-Side Media File Encryption
1. **File Encryption**: The client generates a random AES key and IV, encrypts the file bytes via AES-256-GCM, and appends the auth tag to the ciphertext.
2. **REST Request**: The client requests a signed upload URL from the backend with the query flag `encrypted=true`.
3. **Octet-Stream Bypass**: The backend detects `encrypted=true`, skips magic-number checks and Sharp WebP conversions, and writes the raw binary stream to storage under the path `/uploads/{uploaderId}/{mediaId}.bin`.
4. **Keys Distribution**: The client packs the AES key and IV inside a metadata JSON block:
   ```json
   {
     "file_key": "base64url(aesKey)",
     "file_iv": "base64url(iv)",
     "filename": "original_filename.jpg"
   }
   ```
   This JSON metadata block is E2EE-encrypted as the message content (with type set to `IMAGE`, `VIDEO`, `AUDIO`, or `RECORDING`) and sent to recipients.
5. **In-Memory Playback**: The receiver decrypts the metadata block, requests the encrypted file stream using the `mediaId`, and decrypts the stream in memory for immediate playback or display.

---

## 🗄️ Database Schemas

### 1. Backend PostgreSQL/SQLite Schema ([c:\aegis\backend\src\db\schema.sqlite.sql](file:///c:/aegis/backend/src/db/schema.sqlite.sql))
* **`users`**: User records, password hashes, display details, role labels (`user` vs `admin`), and recovery key hashes.
* **`password_history`**: Maintains the hashes of the current and last 3 passwords to prevent reuse.
* **`devices`**: Tracks trusted public keys, fingerprints, push tokens, and validation status per platform (`ANDROID`, `IOS`, `DESKTOP`, `WEB`).
* **`sessions`**: Web/App refresh tokens, client user agents, IP addresses, and expiration markers.
* **`chats` & `chat_participants`**: Many-to-many link between users and chat rooms, supporting muted/archived flags.
* **`messages` & `message_statuses`**: Captures encrypted message envelopes, media relations, and delivery checkmarks (`SENT`, `DELIVERED`, `READ`).
* **`media`**: Tracks original file names, uploader IDs, MIME types, and size specifications.

### 2. Client Local SQLite Schema via Drift ([c:\aegis\frontend\lib\core\database\local_database.dart](file:///c:/aegis/frontend/lib/core/database/local_database.dart))
* **`local_chats`**: Local cache of chats including the last message preview, timestamp, and archived status.
* **`local_messages`**: Local decrypted messages history storing content in plaintext for local search and display.
* **`sync_queue`**: Offline synchronization queues saving actions like `SEND_MESSAGE` and `MARK_READ` to replay upon connection recovery.

---

## 🚀 Environment Setup & Testing

### 1. Prerequisites
- **Node.js**: v18+
- **Flutter**: v3.22+ (stable channel)
- **C++ Build Tools / OpenSSL**: Required on Windows for dependency compiling.

### 2. Running the Backend
Navigate to the `backend/` directory, copy `.env.example` to `.env`, and launch development:
```bash
cd c:\aegis\backend
npm install
npm run dev
```
* The backend will start on **`http://localhost:3000`**.
* If you run into `EADDRINUSE: address already in use 0.0.0.0:3000`, run this in Windows PowerShell to free the port:
  ```powershell
  Stop-Process -Id (Get-NetTCPConnection -LocalPort 3000).OwningProcess -Force
  ```

### 3. Running the Frontend
Navigate to the `frontend/` directory and launch the Flutter Web client on a static port (so you don't need to re-authorize or re-open custom URLs):
```bash
cd c:\aegis\frontend
flutter pub get
flutter run -d chrome --web-port=5000
```
* The app will serve at **`http://localhost:5000`**.
* Local configuration redirects all requests to `localhost:3000` automatically.

### 4. Running Verification Tests
Ensure all changes compile and pass static analysis:
```bash
# Analyze Flutter codebase and run tests
cd c:\aegis\frontend
flutter analyze
flutter test

# Check TypeScript compiler outputs on Backend
cd c:\aegis\backend
npx tsc --noEmit
```

---

## 🛠️ Phase Progress & Achievements

* **Phase 1: Dependencies Resolution**: Swapped `bcrypt` to `bcryptjs` and handled SQLite native bindings for full Windows compiler compatibility. Fixed Dart analysis issues.
* **Phase 2: Platform Integration**: Extended user registration and device trust engines to natively recognize `WEB` clients (instead of masquerading as desktop).
* **Phase 3: Auth Normalization**: Added identifier trimming/case-normalization on inputs to ensure reliable caching and OTP authentication.
* **Phase 4: Static Dev Ports**: Fixed local workspace port conflict resolutions and locked testing clients to static ports.
* **Phase 5: E2EE Refinements**: Introduced boundary validations on X25519 key generations, integrated decryptions on background REST synchronizations, and exposed debug dashboards for key states.
* **Phase 6: Admin and RBAC**: Added password history checks, master recovery keys, session revoking panels, and field access privacy guards.

---

## 🔴 Future Roadmap / Pending Focus Areas

1. **AWS S3 / MinIO Integration**:
   * Currently, the MinIO plugin ([minio.plugin.ts](file:///c:/aegis/backend/src/plugins/minio.plugin.ts)) acts as a local file writer stub. 
   * When credentials are ready, replace it with the standard `@aws-sdk/client-s3` or `minio` SDK client to store E2EE binary files in the cloud.
2. **TOTP Setup UI Flow**:
   * Complete the frontend settings dialog in the Secure Profile Dashboard to toggle 2FA directly and display the OTP QR Code.
3. **Production Deployment Orchestration**:
   * Assemble a `docker-compose.prod.yml` that configures PostgreSQL 16, Redis 7, MinIO, and Nginx with SSL termination.
