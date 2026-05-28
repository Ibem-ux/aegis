# Aegis — Secure Private Communication Suite Backend

Self-hosted, secure communication backend built with Fastify, TypeScript, PostgreSQL, Redis, and MinIO.

## Getting Started

### Prerequisites

- Node.js (v20+)
- Docker and Docker Compose

### Development Setup

1. **Clone the repository and go to the backend folder**:
   ```bash
   cd c/ibemCom/backend
   ```

2. **Copy the environment configuration**:
   ```bash
   cp .env.example .env
   ```

3. **Start the infrastructure stack (Postgres, Redis, MinIO)**:
   ```bash
   docker-compose up -d
   ```

4. **Install backend dependencies**:
   ```bash
   npm install
   ```

5. **Run the development server (with hot reload)**:
   ```bash
   npm run dev
   ```

---

## API Documentation

All API endpoints are prefixed with `/api`.

### 1. Authentication (`/auth`)
- `POST /auth/register` — Onboard a new user with a valid QR invite token.
- `POST /auth/login` — Sign in to retrieve access/refresh tokens. Sets up new untrusted devices.
- `POST /auth/refresh` — Refresh the access token using refresh token rotation.
- `POST /auth/logout` (Auth required) — Revoke the current session immediately.
- `POST /auth/2fa/setup` (Auth required) — Generate a TOTP secret and QR code.
- `POST /auth/2fa/verify` (Auth/Pre-2FA required) — Complete verification and enable 2FA.

### 2. User Profiles (`/users`)
- `GET /users/me` — Retrieve own user profile details.
- `PUT /users/me` — Update display name and avatar URL.
- `GET /users/search?search=xyz` — Search active contacts.

### 3. Devices (`/devices`)
- `GET /devices` — List all user's registered devices.
- `POST /devices/approve` — Approve (trust) a new device using an already trusted device.
- `DELETE /devices/:id` — Revoke trust and remove a device connection.

### 5. Chats (`/chats`)
- `GET /chats` — List all active chats (contains recipient status and encrypted last message).
- `POST /chats` — Create or retrieve a 1:1 chat room.

### 6. Messages (`/messages`)
- `GET /messages/:chatId` — Fetch chat messages with infinite scroll pagination.
- `POST /messages` — Send a message (rest endpoint fallback).

### 7. Media (`/media`)
- `GET /media/upload?filename=x&mime_type=y&file_size=z` — Request a pre-signed MinIO PUT upload URL.
- `GET /media/download/:id` — Request a pre-signed MinIO GET download URL.

---

## Socket.IO Events (`/chat` Namespace)

WebSocket secure authentication is verified using the access JWT token passed in the handshake auth payload: `{ token: "ACCESS_TOKEN" }`.

### Outbound Events (Client to Server)
- `message:send` — Send encrypted message.
  - Payload: `{ chat_id, content, message_type, reply_to_id, media_id }`
- `message:read` — Acknowledge message read.
  - Payload: `{ message_id, chat_id, sender_id }`
- `typing:start` / `typing:stop` — Broadcast typing indicators.
  - Payload: `{ chat_id }`
- `presence:get_online` — Fetch currently online user list.
- `sync:request` — Request missed messages since reconnect.
  - Payload: `{ last_sync_timestamp }`

### Inbound Events (Server to Client)
- `message:receive` — Relays a new incoming message.
- `message:read_ack` — Relays read receipt to sender.
- `typing:indicator` — Relays typing indicator status.
- `presence:update` — Relays online/offline updates of contacts.
