#!/bin/bash
# Aurora Database Restore Script
# Restores the PostgreSQL database from a backup file

set -e

# Configuration
DB_NAME="${AURORA_DB_NAME:-aurora_dev}"
DB_USER="${AURORA_DB_USER:-$(whoami)}"
BACKUP_DIR="$(dirname "$0")/../backups"

# Check if backup file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_file.sql.gz>"
    echo ""
    echo "Available backups:"
    ls -lt "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -10 || echo "  No backups found in $BACKUP_DIR"
    exit 1
fi

BACKUP_FILE="$1"

# Check if file exists
if [ ! -f "$BACKUP_FILE" ]; then
    # Try looking in backup directory
    if [ -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    else
        echo "Error: Backup file not found: $BACKUP_FILE"
        exit 1
    fi
fi

echo "WARNING: This will replace all data in database '$DB_NAME'!"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

echo "Restoring database from $BACKUP_FILE..."

# Drop and recreate database
dropdb -U "$DB_USER" -h localhost --if-exists "$DB_NAME"
createdb -U "$DB_USER" -h localhost "$DB_NAME"

# Restore from backup
gunzip -c "$BACKUP_FILE" | psql -U "$DB_USER" -h localhost "$DB_NAME"

echo "Done! Database restored successfully."
