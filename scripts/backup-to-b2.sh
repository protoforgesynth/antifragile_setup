#!/bin/bash
# backup-to-b2.sh — Incremental encrypted backup to Backblaze B2 using restic
# Runs daily via launchd, shows progress notifications

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

# Source notification helpers
if [ -f "$SCRIPT_DIR/lib/notify.sh" ]; then
    source "$SCRIPT_DIR/lib/notify.sh"
else
    # Fallback if lib not found
    notify_start() { :; }
    notify_progress() { :; }
    notify_success() { :; }
    notify_error() { :; }
fi

# Create log directory
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/backup_b2_$TIMESTAMP.log"
START_TIME=$(date +%s)

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
    notify_error "B2" "Credentials file not found"
    exit 1
fi

if [ ! -f "$BACKUP_CONF" ]; then
    log_error "Backup config not found: $BACKUP_CONF"
    notify_error "B2" "Backup config not found"
    exit 1
fi

# Load credentials
# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"

if [ -z "${B2_ACCOUNT_ID:-}" ] || [ -z "${B2_ACCOUNT_KEY:-}" ]; then
    log_error "B2_ACCOUNT_ID or B2_ACCOUNT_KEY not set"
    notify_error "B2" "Missing B2 credentials"
    exit 1
fi

if [ -z "${RESTIC_REPOSITORY:-}" ] || [ -z "${RESTIC_PASSWORD:-}" ]; then
    log_error "RESTIC_REPOSITORY or RESTIC_PASSWORD not set"
    notify_error "B2" "Missing restic config"
    exit 1
fi

# Check if restic is installed
if ! command -v restic &> /dev/null; then
    log_error "restic not found. Install with: brew install restic"
    notify_error "B2" "restic not installed"
    exit 1
fi

# Check network connectivity
if ! ping -c 1 -W 5 api.backblazeb2.com &> /dev/null; then
    log_error "Cannot reach Backblaze B2. Check network."
    notify_error "B2" "No network connection"
    exit 1
fi

# ============================================================
# Start backup
# ============================================================

log "Starting backup to Backblaze B2"
log "Repository: $RESTIC_REPOSITORY"

notify_start "B2 Cloud"

# Build list of paths to backup
BACKUP_PATHS=()
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    # Expand ~ to $HOME
    expanded_path="${line/#\~/$HOME}"

    if [ -e "$expanded_path" ]; then
        BACKUP_PATHS+=("$expanded_path")
        log "Including: $expanded_path"
    else
        log "Skipping (not found): $expanded_path"
    fi
done < "$BACKUP_CONF"

if [ ${#BACKUP_PATHS[@]} -eq 0 ]; then
    log_error "No valid paths to backup!"
    notify_error "B2" "No paths to backup"
    exit 1
fi

# Build exclude args
EXCLUDE_ARGS=()
if [ -f "$EXCLUDE_CONF" ]; then
    EXCLUDE_ARGS+=("--exclude-file=$EXCLUDE_CONF")
fi

# ============================================================
# Run backup with JSON progress output
# ============================================================

log "Starting restic backup..."

# Run backup with JSON output for progress parsing
# Tee to both log file and parse for progress
{
    restic backup \
        "${BACKUP_PATHS[@]}" \
        "${EXCLUDE_ARGS[@]}" \
        --json \
        --one-file-system \
        2>&1
} | tee -a "$LOG_FILE" | while IFS= read -r line; do
    # Parse JSON progress and update status
    if echo "$line" | grep -q '"message_type":"status"'; then
        percent=$(echo "$line" | grep -o '"percent_done":[0-9.]*' | cut -d':' -f2 || echo "0")
        if [ -n "$percent" ]; then
            pct=$(awk "BEGIN {printf \"%.0f\", $percent * 100}")
            files_done=$(echo "$line" | grep -o '"files_done":[0-9]*' | cut -d':' -f2 || echo "0")
            files_total=$(echo "$line" | grep -o '"total_files":[0-9]*' | cut -d':' -f2 || echo "0")
            bytes_done=$(echo "$line" | grep -o '"bytes_done":[0-9]*' | cut -d':' -f2 || echo "0")
            bytes_total=$(echo "$line" | grep -o '"total_bytes":[0-9]*' | cut -d':' -f2 || echo "0")

            # Update progress file
            cat > /tmp/antifragile-progress.json << EOF
{"status":"running","type":"B2","percent":$pct,"files_done":$files_done,"files_total":$files_total,"bytes_done":$bytes_done,"bytes_total":$bytes_total,"updated":"$(date -Iseconds)"}
EOF
        fi
    fi
done

BACKUP_EXIT_CODE=${PIPESTATUS[0]}

if [ "$BACKUP_EXIT_CODE" -ne 0 ]; then
    log_error "Backup failed with exit code $BACKUP_EXIT_CODE"
    notify_error "B2" "Backup failed (exit code $BACKUP_EXIT_CODE)"
    exit 1
fi

log "Backup completed successfully"

# ============================================================
# Cleanup old snapshots
# ============================================================

log "Cleaning up old snapshots..."

restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune \
    >> "$LOG_FILE" 2>&1 || {
        log_error "Cleanup failed, but backup succeeded"
    }

log "Cleanup completed"

# ============================================================
# Weekly integrity check
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
# Calculate stats and notify
# ============================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Get human readable duration
if [ "$DURATION" -ge 3600 ]; then
    DURATION_STR="$(($DURATION/3600))h $((($DURATION%3600)/60))m"
elif [ "$DURATION" -ge 60 ]; then
    DURATION_STR="$(($DURATION/60))m $(($DURATION%60))s"
else
    DURATION_STR="${DURATION}s"
fi

# Get backup size from last snapshot
BACKUP_SIZE=$(restic stats --json 2>/dev/null | grep -o '"total_size":[0-9]*' | cut -d':' -f2 || echo "")
if [ -n "$BACKUP_SIZE" ]; then
    if [ "$BACKUP_SIZE" -ge 1073741824 ]; then
        SIZE_STR="$(awk "BEGIN {printf \"%.1f\", $BACKUP_SIZE / 1073741824}")GB"
    elif [ "$BACKUP_SIZE" -ge 1048576 ]; then
        SIZE_STR="$(awk "BEGIN {printf \"%.1f\", $BACKUP_SIZE / 1048576}")MB"
    else
        SIZE_STR="${BACKUP_SIZE}B"
    fi
else
    SIZE_STR=""
fi

notify_success "B2 Cloud" "$DURATION_STR" "$SIZE_STR"

log "Backup complete! Duration: $DURATION_STR"

# ============================================================
# Show recent snapshots
# ============================================================

log "Recent snapshots:"
restic snapshots --last 3 >> "$LOG_FILE" 2>&1

log "Full log: $LOG_FILE"

# Cleanup old logs (keep last 30 days)
find "$LOG_DIR" -name "backup_b2_*.log" -mtime +30 -delete 2>/dev/null || true
