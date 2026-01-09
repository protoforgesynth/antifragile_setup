#!/bin/bash
# backup-to-usb-auto.sh — Auto-triggered backup when USB is inserted
# Called by launchd when /Volumes/ANTIFRAGILE appears

set -euo pipefail

USB_MOUNT="/Volumes/ANTIFRAGILE"
LOCK_FILE="/tmp/antifragile-usb-backup.lock"
LOG_FILE="$HOME/.local/log/antifragile/usb-auto.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ============================================================
# Guards
# ============================================================

# Wait a moment for volume to fully mount
sleep 3

# Check if volume actually exists
if [ ! -d "$USB_MOUNT" ]; then
    log "Volume $USB_MOUNT not found, exiting"
    exit 0
fi

# Prevent multiple simultaneous runs
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        log "Backup already running (PID $LOCK_PID), exiting"
        exit 0
    fi
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ============================================================
# Notify user
# ============================================================

# macOS notification
osascript -e 'display notification "Starting automatic backup..." with title "Antifragile Backup" sound name "Submarine"' 2>/dev/null || true

log "=== USB backup triggered ==="
log "Volume: $USB_MOUNT"

# ============================================================
# Run backup
# ============================================================

if "$SCRIPT_DIR/backup-to-usb.sh" >> "$LOG_FILE" 2>&1; then
    log "Backup completed successfully"

    # Success notification
    osascript -e 'display notification "USB backup complete!" with title "Antifragile Backup" sound name "Glass"' 2>/dev/null || true
else
    log "Backup failed!"

    # Error notification
    osascript -e 'display notification "USB backup FAILED! Check logs." with title "Antifragile Backup" sound name "Basso"' 2>/dev/null || true
    exit 1
fi

log "=== USB backup finished ==="
