#!/bin/bash

# Restore script for ibemCom Production Stack
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_encrypted_db_backup.enc>"
    exit 1
fi

BACKUP_FILE=$1
TEMP_DECRYPTED="/tmp/restored-db-temp.sql"

# Load .env variables
export $(grep -v '^#' .env | xargs)

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: Backup file '${BACKUP_FILE}' not found."
    exit 1
fi

echo "===================================================="
echo "          ibemCom Restore Procedure                 "
echo "===================================================="

# 1. Decrypt dump
echo "Decrypting database backup archive..."
openssl enc -d -aes-256-cbc -pbkdf2 \
  -pass pass:${BACKUP_ENCRYPTION_KEY} \
  -in ${BACKUP_FILE} \
  -out ${TEMP_DECRYPTED}

# 2. Reset database and restore
echo "Restoring database tables..."
# Drop and recreate schema inside container
docker exec -i ibemcom-prod-db psql -U ${DB_USER} -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME};"
docker exec -i ibemcom-prod-db psql -U ${DB_USER} -d postgres -c "CREATE DATABASE ${DB_NAME};"

# Feed the decrypted SQL into the container db
docker exec -i ibemcom-prod-db psql -U ${DB_USER} -d ${DB_NAME} < ${TEMP_DECRYPTED}

# Cleanup temp
rm -f ${TEMP_DECRYPTED}

echo "===================================================="
echo "Database successfully restored from backup!"
echo "===================================================="
