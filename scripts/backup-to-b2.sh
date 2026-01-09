#!/bin/bash
# backup-to-b2.sh — Incremental encrypted backup to Backblaze B2 using restic
# Runs daily via launchd

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${ANTIFRAGILE_CONFIG:-$HOME/.config/antifragile}"
LOG_DIR="$HOME/.local/log/antifragile"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.env"
BACKUP_CONF="$CONFIG_DIR/backup.conf"
EXCLUDE_CONF="$CONFIG_DIR/exclude.conf"

# Create log directory
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/backup_b2_$TIMESTAMP.log"

# ============================================================
# Logging
# ============================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# ============================================================
# Pre-flight checks
# ============================================================

if [ ! -f "$CREDENTIALS_FILE" ]; then
    log_error "Credentials file not found: $CREDENTIALS_FILE"
    log_error "Create it from credentials.env.template"
    exit 1
fi

if [ ! -f "$BACKUP_CONF" ]; then
    log_error "Backup config not found: $BACKUP_CONF"
    exit 1
fi

# Load credentials
# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"

if [ -z "${B2_ACCOUNT_ID:-}" ] || [ -z "${B2_ACCOUNT_KEY:-}" ]; then
    log_error "B2_ACCOUNT_ID or B2_ACCOUNT_KEY not set in credentials file"
    exit 1
fi

if [ -z "${RESTIC_REPOSITORY:-}" ]; then
    log_error "RESTIC_REPOSITORY not set in credentials file"
    exit 1
fi

if [ -z "${RESTIC_PASSWORD:-}" ]; then
    log_error "RESTIC_PASSWORD not set in credentials file"
    exit 1
fi

# Check if restic is installed
if ! command -v restic &> /dev/null; then
    log_error "restic not found. Install with: brew install restic"
    exit 1
fi

# Check network connectivity
if ! ping -c 1 api.backblazeb2.com &> /dev/null; then
    log_error "Cannot reach Backblaze B2. Check network connection."
    exit 1
fi

# ============================================================
# Main backup
# ============================================================

log "Starting backup to Backblaze B2"
log "Repository: $RESTIC_REPOSITORY"

# Build backup command
BACKUP_CMD="restic backup"

# Add paths from config file
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    # Expand ~ to $HOME
    expanded_path="${line/#\~/$HOME}"

    if [ -e "$expanded_path" ]; then
        BACKUP_CMD="$BACKUP_CMD \"$expanded_path\""
    else
        log "Skipping non-existent path: $expanded_path"
    fi
done < "$BACKUP_CONF"

# Add exclude file if exists
if [ -f "$EXCLUDE_CONF" ]; then
    BACKUP_CMD="$BACKUP_CMD --exclude-file=\"$EXCLUDE_CONF\""
fi

# Add common options
BACKUP_CMD="$BACKUP_CMD --verbose --one-file-system"

log "Running: $BACKUP_CMD"

# Execute backup
if eval "$BACKUP_CMD" >> "$LOG_FILE" 2>&1; then
    log "Backup completed successfully"
else
    log_error "Backup failed!"
    exit 1
fi

# ============================================================
# Cleanup old snapshots
# ============================================================

log "Cleaning up old snapshots..."

restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune \
    >> "$LOG_FILE" 2>&1

log "Cleanup completed"

# ============================================================
# Verify backup integrity (weekly)
# ============================================================

DAY_OF_WEEK=$(date +%u)
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    log "Running weekly integrity check..."
    if restic check >> "$LOG_FILE" 2>&1; then
        log "Integrity check passed"
    else
        log_error "Integrity check failed!"
    fi
fi

# ============================================================
# Summary
# ============================================================

log "Backup statistics:"
restic stats >> "$LOG_FILE" 2>&1

# Show recent snapshots
log "Recent snapshots:"
restic snapshots --last 5 >> "$LOG_FILE" 2>&1

log "Full log: $LOG_FILE"
log "Backup to B2 complete!"

# Cleanup old logs (keep last 30)
find "$LOG_DIR" -name "backup_b2_*.log" -mtime +30 -delete 2>/dev/null || true
