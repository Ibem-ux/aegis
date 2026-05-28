# ibemCom — Private Communication Platform

A self-hosted, encrypted private messenger for 2–10 users. Signal-grade privacy with full infrastructure ownership.

## Architecture

| Layer | Technology |
|-------|-----------|
| **Backend** | Fastify + TypeScript |
| **Frontend** | Flutter (Android) — codename *Aegis* |
| **Database** | PostgreSQL 16 |
| **Real-time** | Socket.IO |
| **Cache/Queue** | Redis 7 |
| **Media Storage** | MinIO (S3-compatible) |

## Project Structure

```
ibemCom/
├── backend/           # Fastify API server + Socket.IO
│   ├── src/
│   │   ├── config/    # Environment & connection configs
│   │   ├── modules/   # Auth, Users, Chats, Messages, Media, Devices, Invites
│   │   ├── plugins/   # Fastify plugins (DB, Redis, MinIO, Auth, Socket)
│   │   ├── services/  # Encryption, Token, OTP, Backup services
│   │   ├── socket/    # Real-time messaging handlers
│   │   └── utils/     # Logger, errors, helpers
│   └── docker-compose.yml
├── frontend/          # Flutter app (Aegis)
│   └── lib/
│       ├── core/      # Network, Database, Security, Storage
│       └── features/  # Auth, Chats, Messages
├── nginx/             # Reverse proxy config
├── scripts/           # Setup, backup, restore scripts
└── docker-compose.prod.yml
```

## Security Features

- **AES-256-GCM** server-side message encryption at rest
- **Client-side media encryption** — server cannot decrypt media files
- **TOTP 2FA** for account protection
- **Device verification** — new devices must be approved by trusted devices
- **Invite-only registration** via QR codes
- **JWT authentication** with RS256 signing and refresh token rotation
- **Rate limiting** and brute-force protection
- **Encrypted local database** on mobile (SQLite3MC via Drift)

## Getting Started

### Prerequisites

- Node.js 18+
- Docker & Docker Compose
- Flutter 3.22+ (stable channel)

### Backend

```bash
cd backend
cp .env.example .env
# Edit .env with your configuration
docker-compose up -d        # Start PostgreSQL, Redis, MinIO
npm install
npm run dev
```

### Frontend (Flutter)

```bash
cd frontend
flutter pub get
flutter run
```

## License

Private — All rights reserved.
