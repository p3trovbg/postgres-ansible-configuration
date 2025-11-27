#!/usr/bin/env bash
set -euo pipefail

# This script runs on DEVELOPER's local machine
# Requires: SSH access to backup server, local Postgres instance

BACKUP_SERVER_USER="backupuser"
BACKUP_SERVER_HOST="127.0.0.1" # point remote storage server
BACKUP_SERVER_PORT="2223"
SSH_KEY="~/.ssh/backup_server_key" 
REMOTE_DIR="/backups/postgres"
LOCAL_BACKUP_DIR="../postgres_backups" # point location when you want save backup on your machine

# Prompt for backup date and database
echo "Available backups on server:"
ssh -i "$SSH_KEY" -p "$BACKUP_SERVER_PORT" \
  "${BACKUP_SERVER_USER}@${BACKUP_SERVER_HOST}" \
  "ls -1 ${REMOTE_DIR} | tail -10"

read -p "Enter backup date (YYYY-MM-DD_HH-MM-SS): " BACKUP_DATE
read -p "Enter database name: " DATABASE
read -sp "Enter decryption passphrase: " PASSPHRASE
echo

mkdir -p "$LOCAL_BACKUP_DIR"

# Download encrypted backup
echo "Downloading backup..."
rsync -az --partial \
  -e "ssh -i ${SSH_KEY} -p ${BACKUP_SERVER_PORT}" \
  "${BACKUP_SERVER_USER}@${BACKUP_SERVER_HOST}:${REMOTE_DIR}/${BACKUP_DATE}/${DATABASE}.dump.gpg" \
  "${LOCAL_BACKUP_DIR}/"

# Decrypt
echo "Decrypting..."
printf '%s' "$PASSPHRASE" | gpg \
  --batch --yes --passphrase-fd 0 --decrypt \
  "${LOCAL_BACKUP_DIR}/${DATABASE}.dump.gpg" \
  > "${LOCAL_BACKUP_DIR}/${DATABASE}.dump"

# Restore to local Postgres
echo "Restoring to local database..."
LOCAL_DB_NAME="${DATABASE}_local"

# # Assuming local Postgres (not Docker, adjust if needed)
# dropdb --if-exists "$LOCAL_DB_NAME"
# createdb "$LOCAL_DB_NAME"
# pg_restore -d "$LOCAL_DB_NAME" --no-owner --no-acl "${LOCAL_BACKUP_DIR}/${DATABASE}.dump"

# # Cleanup
# rm -f "${LOCAL_BACKUP_DIR}/${DATABASE}.dump"

echo "Database restored to: $LOCAL_DB_NAME"