#!/usr/bin/env bash
set -euo pipefail

# Config you’ll likely keep constant on your local machine
REMOTE_USER="backupuser"
REMOTE_HOST="your-backup-server"
REMOTE_DIR="/backups/postgres"
REMOTE_PORT="22"
SSH_KEY="$HOME/.ssh/backup_rsync"

LOCAL_RESTORE_ROOT="${HOME}/.local/postgres-restore"

PGHOST="${PGHOST:-localhost}"
PGUSER="${PGUSER:-postgres}"
PGPORT="${PGPORT:-5432}"

usage() {
  cat <<EOF
Usage:
  $0 -b <BACKUP_DATE> -d <DB_NAME> -n <LOCAL_DB_NAME>

Examples:
  # Restore 'main_db' from a backup into 'main_db_test' locally
  $0 -b 2025-11-24_12-00-00 -d main_db -n main_db_test
EOF
}

BACKUP_DATE=""
DB_NAME=""
LOCAL_DB_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b) BACKUP_DATE="$2"; shift 2 ;;
    -d) DB_NAME="$2"; shift 2 ;;
    -n) LOCAL_DB_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$BACKUP_DATE" || -z "$DB_NAME" || -z "$LOCAL_DB_NAME" ]]; then
  echo "ERROR: -b, -d and -n are required."
  usage
  exit 1
fi

if [[ -z "${ENCRYPT_PASSPHRASE:-}" ]]; then
  read -r -s -p "Enter backup GPG passphrase: " ENCRYPT_PASSPHRASE
  echo
fi

LOCAL_DIR="${LOCAL_RESTORE_ROOT}/${BACKUP_DATE}"
mkdir -p "$LOCAL_DIR"

echo "[*] Fetching backup ${BACKUP_DATE} from remote..."
rsync -az -e "ssh -i ${SSH_KEY} -p ${REMOTE_PORT} -o StrictHostKeyChecking=no" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${BACKUP_DATE}/" \
  "${LOCAL_DIR}/"

cd "$LOCAL_DIR"

ENC_FILE="${DB_NAME}.dump.gpg"
PLAIN_FILE="${DB_NAME}.dump"

if [[ ! -f "$ENC_FILE" ]]; then
  echo "ERROR: ${ENC_FILE} not found in ${LOCAL_DIR}"
  exit 1
fi

echo "[*] Decrypting ${ENC_FILE} -> ${PLAIN_FILE}"
printf '%s' "$ENCRYPT_PASSPHRASE" | gpg \
  --batch --yes \
  --passphrase-fd 0 \
  -o "$PLAIN_FILE" \
  -d "$ENC_FILE"

echo "[*] Dropping local DB ${LOCAL_DB_NAME} if it exists..."
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -c "DROP DATABASE IF EXISTS \"$LOCAL_DB_NAME\";"

echo "[*] Creating local DB ${LOCAL_DB_NAME}..."
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -c "CREATE DATABASE \"$LOCAL_DB_NAME\";"

echo "[*] Restoring into ${LOCAL_DB_NAME}..."
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$LOCAL_DB_NAME" -j 4 "$PLAIN_FILE"

echo "[*] Done. Local DB '$LOCAL_DB_NAME' restored from backup '$BACKUP_DATE' (source DB '$DB_NAME')."
