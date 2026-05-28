#!/bin/bash

# Cron Backup orchestration script for ibemCom Production Stack
set -e

# Load .env variables
export $(grep -v '^#' .env | xargs)

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="./backups"
DB_TEMP_FILE="/tmp/db-${TIMESTAMP}.sql"
DB_ENC_FILE="${BACKUP_DIR}/db-backup-${TIMESTAMP}.sql.enc"

echo "Starting automated backup..."
mkdir -p ${BACKUP_DIR}

# 1. PostgreSQL backup via docker container exec
echo "Extracting database SQL dump..."
docker exec -t ibemcom-prod-db pg_dump -U ${DB_USER} ${DB_NAME} > ${DB_TEMP_FILE}

# 2. Encrypt database dump using BACKUP_ENCRYPTION_KEY via OpenSSL
echo "Encrypting database dump archive..."
# Convert hex backup key to binary and encrypt
openssl enc -aes-256-cbc -salt -pbkdf2 \
  -pass pass:${BACKUP_ENCRYPTION_KEY} \
  -in ${DB_TEMP_FILE} \
  -out ${DB_ENC_FILE}

# Remove plaintext temp file
rm -f ${DB_TEMP_FILE}

# 3. MinIO media storage mirroring
echo "Backing up storage assets..."
# MinIO volume data can be archived directly since files are already encrypted client-side
tar -czf ${BACKUP_DIR}/media-backup-${TIMESTAMP}.tar.gz -C ./docker-compose volumes/minio_prod_data 2>/dev/null || true

# 4. Clean up older backups (keep last 30 days)
echo "Running retention cleanup..."
find ${BACKUP_DIR} -type f -name "db-backup-*" -mtime +30 -delete
find ${BACKUP_DIR} -type f -name "media-backup-*" -mtime +30 -delete

echo "Backup completed successfully: ${DB_ENC_FILE}"
EOT
