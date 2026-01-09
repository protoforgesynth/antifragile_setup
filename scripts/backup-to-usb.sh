#!/bin/bash
# backup-to-usb.sh — Backup critical data to encrypted USB drive
# Run manually or auto-triggered when USB is inserted

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${ANTIFRAGILE_CONFIG:-$HOME/.config/antifragile}"
LOG_DIR="$HOME/.local/log/antifragile"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.env"
EXCLUDE_CONF="$CONFIG_DIR/exclude.conf"

# Default USB mount point - can be overridden
USB_MOUNT="${USB_MOUNT:-/Volumes/ANTIFRAGILE}"
USB_REPO="$USB_MOUNT/restic-repo"
EMERGENCY_DIR="$USB_MOUNT/emergency"

# Source notification helpers
if [ -f "$SCRIPT_DIR/lib/notify.sh" ]; then
    source "$SCRIPT_DIR/lib/notify.sh"
else
    notify_start() { :; }
    notify_success() { :; }
    notify_error() { :; }
fi

mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/backup_usb_$TIMESTAMP.log"
START_TIME=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Functions
# ============================================================

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1" >&2
}

log_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

# ============================================================
# Pre-flight checks
# ============================================================

log_section "Pre-flight Checks"

# Check if USB is mounted
if [ ! -d "$USB_MOUNT" ]; then
    log_error "USB drive not mounted at $USB_MOUNT"
    notify_error "USB" "Drive not mounted"
    echo ""
    echo "Available volumes:"
    ls /Volumes/ 2>/dev/null || echo "Cannot list /Volumes/"
    echo ""
    echo "To use a different mount point:"
    echo "  USB_MOUNT=/Volumes/YourDrive $0"
    exit 1
fi

log "USB drive found at $USB_MOUNT"

# Check for restic
if ! command -v restic &> /dev/null; then
    log_error "restic not found. Install with: brew install restic"
    exit 1
fi

# Load credentials for restic password
if [ -f "$CREDENTIALS_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CREDENTIALS_FILE"
fi

# Check for USB-specific password or use main password
if [ -z "${RESTIC_PASSWORD_USB:-}" ]; then
    if [ -z "${RESTIC_PASSWORD:-}" ]; then
        log_warning "No RESTIC_PASSWORD_USB or RESTIC_PASSWORD found"
        echo "Enter restic password for USB repository:"
        read -rs RESTIC_PASSWORD
        export RESTIC_PASSWORD
    fi
    export RESTIC_PASSWORD_USB="${RESTIC_PASSWORD}"
fi

# Use USB password for this session
export RESTIC_PASSWORD="$RESTIC_PASSWORD_USB"

# ============================================================
# Initialize USB repo if needed
# ============================================================

if [ ! -d "$USB_REPO" ]; then
    log_section "Initializing USB Repository"
    log "Creating new restic repository at $USB_REPO"

    mkdir -p "$USB_REPO"
    restic -r "$USB_REPO" init

    log "Repository initialized"
fi

# Create emergency directory
mkdir -p "$EMERGENCY_DIR"

# ============================================================
# Critical data backup
# ============================================================

log_section "Backing up Critical Data"
notify_start "USB Drive"

CRITICAL_PATHS=()

# SSH keys - CRITICAL
if [ -d "$HOME/.ssh" ]; then
    CRITICAL_PATHS+=("$HOME/.ssh")
    log "Adding: ~/.ssh/"
fi

# GPG keys - CRITICAL
if [ -d "$HOME/.gnupg" ]; then
    CRITICAL_PATHS+=("$HOME/.gnupg")
    log "Adding: ~/.gnupg/"
fi

# Projects
if [ -d "$HOME/dev/projects" ]; then
    CRITICAL_PATHS+=("$HOME/dev/projects")
    log "Adding: ~/dev/projects/"
fi

# Obsidian vaults
if [ -d "$HOME/obsidian_vaults" ]; then
    CRITICAL_PATHS+=("$HOME/obsidian_vaults")
    log "Adding: ~/obsidian_vaults/"
fi

# Main dev directory
if [ -d "$HOME/dev" ]; then
    CRITICAL_PATHS+=("$HOME/dev")
    log "Adding: ~/dev/"
fi

# Config directory
if [ -d "$HOME/.config" ]; then
    CRITICAL_PATHS+=("$HOME/.config")
    log "Adding: ~/.config/"
fi

if [ ${#CRITICAL_PATHS[@]} -eq 0 ]; then
    log_error "No critical paths found to backup!"
    notify_error "USB" "No paths to backup"
    exit 1
fi

# Build exclude args
EXCLUDE_ARGS=()
if [ -f "$EXCLUDE_CONF" ]; then
    EXCLUDE_ARGS+=("--exclude-file=$EXCLUDE_CONF")
fi

# Run backup with JSON progress
log "Starting restic backup..."

{
    restic -r "$USB_REPO" backup \
        "${CRITICAL_PATHS[@]}" \
        "${EXCLUDE_ARGS[@]}" \
        --json \
        2>&1
} | tee -a "$LOG_FILE" | while IFS= read -r line; do
    if echo "$line" | grep -q '"message_type":"status"'; then
        percent=$(echo "$line" | grep -o '"percent_done":[0-9.]*' | cut -d':' -f2 || echo "0")
        if [ -n "$percent" ]; then
            pct=$(awk "BEGIN {printf \"%.0f\", $percent * 100}")
            files_done=$(echo "$line" | grep -o '"files_done":[0-9]*' | cut -d':' -f2 || echo "0")
            bytes_done=$(echo "$line" | grep -o '"bytes_done":[0-9]*' | cut -d':' -f2 || echo "0")
            cat > /tmp/antifragile-progress.json << EOF
{"status":"running","type":"USB","percent":$pct,"files_done":$files_done,"bytes_done":$bytes_done,"updated":"$(date -Iseconds)"}
EOF
            # Show progress in terminal too
            printf "\r  Progress: %3d%% (%d files)" "$pct" "$files_done"
        fi
    fi
done
echo ""  # newline after progress

BACKUP_EXIT=${PIPESTATUS[0]}
if [ "$BACKUP_EXIT" -ne 0 ]; then
    log_error "Backup failed!"
    notify_error "USB" "Backup failed"
    exit 1
fi

log "Restic backup completed"

# ============================================================
# Emergency exports (double protection)
# ============================================================

log_section "Creating Emergency Exports"

# Check for GPG
if command -v gpg &> /dev/null; then
    # Export SSH keys with GPG encryption
    if [ -d "$HOME/.ssh" ]; then
        log "Encrypting SSH keys with GPG..."
        tar cf - "$HOME/.ssh" 2>/dev/null | gpg --symmetric --cipher-algo AES256 -o "$EMERGENCY_DIR/ssh-keys.tar.gpg" 2>/dev/null || {
            log_warning "GPG encryption of SSH keys failed (need passphrase)"
        }
    fi

    # Export GPG keys
    if [ -d "$HOME/.gnupg" ]; then
        log "Exporting GPG keys..."
        gpg --export-secret-keys --armor > "$EMERGENCY_DIR/gpg-secret-keys.asc" 2>/dev/null || {
            log_warning "GPG secret key export failed"
        }
        gpg --export --armor > "$EMERGENCY_DIR/gpg-public-keys.asc" 2>/dev/null || true
    fi
else
    log_warning "GPG not installed, skipping emergency exports"
fi

# ============================================================
# Cleanup old snapshots
# ============================================================

log_section "Cleaning Up Old Snapshots"

restic -r "$USB_REPO" forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --prune

# ============================================================
# Create recovery instructions
# ============================================================

cat > "$USB_MOUNT/RECOVERY.md" << 'EOF'
# Emergency Recovery Instructions

## Quick Recovery

1. Install restic:
   ```bash
   brew install restic
   ```

2. List snapshots:
   ```bash
   restic -r /Volumes/ANTIFRAGILE/restic-repo snapshots
   ```

3. Restore everything:
   ```bash
   restic -r /Volumes/ANTIFRAGILE/restic-repo restore latest --target ~/restore
   ```

4. Restore specific path:
   ```bash
   restic -r /Volumes/ANTIFRAGILE/restic-repo restore latest --target ~/ --include "/.ssh"
   ```

## Emergency Files (if restic unavailable)

- `emergency/ssh-keys.tar.gpg` - SSH keys (GPG encrypted)
- `emergency/gpg-secret-keys.asc` - GPG secret keys
- `emergency/gpg-public-keys.asc` - GPG public keys

Decrypt SSH keys:
```bash
gpg -d emergency/ssh-keys.tar.gpg | tar xf -
```

## Important Notes

- Restic password is required to access backups
- GPG passphrase is required for emergency files
- Keep both passwords in a secure location (password manager + printed copy)
EOF

log "Recovery instructions written to $USB_MOUNT/RECOVERY.md"

# ============================================================
# Summary
# ============================================================

log_section "Backup Summary"

echo ""
restic -r "$USB_REPO" stats
echo ""

log "Recent snapshots:"
restic -r "$USB_REPO" snapshots --last 3

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
if [ "$DURATION" -ge 60 ]; then
    DURATION_STR="$(($DURATION/60))m $(($DURATION%60))s"
else
    DURATION_STR="${DURATION}s"
fi

# Get backup size
BACKUP_SIZE=$(restic -r "$USB_REPO" stats --json 2>/dev/null | grep -o '"total_size":[0-9]*' | cut -d':' -f2 || echo "")
if [ -n "$BACKUP_SIZE" ] && [ "$BACKUP_SIZE" -ge 1073741824 ]; then
    SIZE_STR="$(awk "BEGIN {printf \"%.1f\", $BACKUP_SIZE / 1073741824}")GB"
elif [ -n "$BACKUP_SIZE" ] && [ "$BACKUP_SIZE" -ge 1048576 ]; then
    SIZE_STR="$(awk "BEGIN {printf \"%.1f\", $BACKUP_SIZE / 1048576}")MB"
else
    SIZE_STR=""
fi

notify_success "USB Drive" "$DURATION_STR" "$SIZE_STR"

echo ""
log "USB backup complete! Duration: $DURATION_STR"
log "Remember to safely eject the drive before removing."
