#!/bin/bash
# Aurora Database Backup Script
# Backs up the PostgreSQL database to the backups/ folder

set -e

# Configuration
DB_NAME="${AURORA_DB_NAME:-aurora_dev}"
DB_USER="${AURORA_DB_USER:-$(whoami)}"
BACKUP_DIR="$(dirname "$0")/../backups"
CLOUD_BACKUP_DIR="${AURORA_CLOUD_BACKUP_DIR:-}"  # Optional: path to cloud-synced folder

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/aurora_backup_$TIMESTAMP.sql"

echo "Backing up database '$DB_NAME' to $BACKUP_FILE..."

# Create backup
pg_dump -U "$DB_USER" -h localhost "$DB_NAME" > "$BACKUP_FILE"

# Compress the backup
gzip "$BACKUP_FILE"
BACKUP_FILE="$BACKUP_FILE.gz"

echo "Backup created: $BACKUP_FILE"

# Copy to cloud backup directory if configured
if [ -n "$CLOUD_BACKUP_DIR" ] && [ -d "$CLOUD_BACKUP_DIR" ]; then
    cp "$BACKUP_FILE" "$CLOUD_BACKUP_DIR/"
    echo "Backup copied to cloud folder: $CLOUD_BACKUP_DIR"
fi

# Keep only last 10 local backups
cd "$BACKUP_DIR"
ls -t aurora_backup_*.sql.gz 2>/dev/null | tail -n +11 | xargs -r rm --

echo "Done! Backup completed successfully."
