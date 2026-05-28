#!/bin/bash

# Setup script for ibemCom Private Messenger Server Environment
set -e

echo "===================================================="
echo "      ibemCom Private Messenger Setup Script        "
echo "===================================================="

# 1. Generate directories
echo "Creating necessary directories..."
mkdir -p nginx/ssl/live
mkdir -p backend/keys
mkdir -p backups

# 2. Check for openssl dependency
if ! command -v openssl &> /dev/null; then
    echo "Error: openssl command not found. Please install openssl first."
    exit 1
fi

# 3. Generate RSA keys for JWT token signing if not exist
if [ ! -f backend/keys/private.pem ]; then
    echo "Generating JWT token RSA private and public key pair..."
    openssl genpkey -algorithm RSA -out backend/keys/private.pem -pkeyopt rsa_keygen_bits:2048
    openssl rsa -pubout -in backend/keys/private.pem -out backend/keys/public.pem
    echo "RSA keys generated successfully."
fi

# 4. Generate self-signed certificate for Nginx start if not exist
if [ ! -f nginx/ssl/live/ibemcom.crt ]; then
    echo "Generating self-signed SSL certificate for local/initial Nginx configurations..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout nginx/ssl/live/ibemcom.key \
        -out nginx/ssl/live/ibemcom.crt \
        -subj "/C=US/ST=State/L=City/O=ibemCom/CN=localhost"
    echo "Self-signed certificate generated successfully."
fi

# 5. Build environment variables file (.env) if not exists
if [ ! -f .env ]; then
    echo "Generating production keys and .env file..."
    
    # Generate secure random strings
    MASTER_KEY=$(openssl rand -hex 32)
    BACKUP_KEY=$(openssl rand -hex 32)
    DB_PASSWORD=$(openssl rand -hex 16)
    REDIS_PASSWORD=$(openssl rand -hex 16)
    MINIO_PASSWORD=$(openssl rand -hex 16)

    cat <<EOT > .env
# Production Config Env
NODE_ENV=production
PORT=3000
HOST=0.0.0.0

# Database Credentials
DB_USER=ibemuser
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=ibemdb

# Redis Password
REDIS_PASSWORD=${REDIS_PASSWORD}

# MinIO storage
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}
MINIO_BUCKET_NAME=ibemcom-media

# RSA JWT keys paths (relative to container app root)
JWT_PRIVATE_KEY_PATH=keys/private.pem
JWT_PUBLIC_KEY_PATH=keys/public.pem

# Core AES Encryption keys (32 bytes hex)
MASTER_ENCRYPTION_KEY=${MASTER_KEY}
BACKUP_ENCRYPTION_KEY=${BACKUP_KEY}
EOT
    echo ".env file generated successfully with secure credentials."
else
    echo ".env file already exists. Skipping variable generation to protect existing credentials."
fi

echo "===================================================="
echo "Setup complete! To run the production environment, execute:"
echo "  docker-compose -f docker-compose.prod.yml up -d --build"
echo "===================================================="
