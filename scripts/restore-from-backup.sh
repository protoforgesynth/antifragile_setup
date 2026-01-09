#!/bin/bash
# restore-from-backup.sh — Restore data from restic backup (B2 or USB)
# Run on a fresh macOS installation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
log_error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1" >&2; }
log_section() { echo ""; echo -e "${BLUE}=== $1 ===${NC}"; }

# ============================================================
# Menu
# ============================================================

show_menu() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Antifragile Restore Utility        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Select backup source:"
    echo ""
    echo "  1) Backblaze B2 (cloud)"
    echo "  2) USB Drive (local)"
    echo "  3) Exit"
    echo ""
    read -rp "Choice [1-3]: " choice
}

# ============================================================
# Setup B2 connection
# ============================================================

setup_b2() {
    log_section "Backblaze B2 Setup"

    if [ -z "${B2_ACCOUNT_ID:-}" ]; then
        echo "Enter B2 Account ID:"
        read -r B2_ACCOUNT_ID
        export B2_ACCOUNT_ID
    fi

    if [ -z "${B2_ACCOUNT_KEY:-}" ]; then
        echo "Enter B2 Application Key:"
        read -rs B2_ACCOUNT_KEY
        export B2_ACCOUNT_KEY
        echo ""
    fi

    echo "Enter repository (e.g., b2:bucket-name:restic-backup):"
    read -r REPO
    export RESTIC_REPOSITORY="$REPO"

    echo "Enter restic password:"
    read -rs RESTIC_PASSWORD
    export RESTIC_PASSWORD
    echo ""
}

# ============================================================
# Setup USB connection
# ============================================================

setup_usb() {
    log_section "USB Drive Setup"

    echo "Available volumes:"
    ls /Volumes/ 2>/dev/null || echo "Cannot list /Volumes/"
    echo ""

    read -rp "Enter USB mount point [/Volumes/ANTIFRAGILE]: " USB_MOUNT
    USB_MOUNT="${USB_MOUNT:-/Volumes/ANTIFRAGILE}"

    if [ ! -d "$USB_MOUNT/restic-repo" ]; then
        log_error "Restic repo not found at $USB_MOUNT/restic-repo"
        exit 1
    fi

    REPO="$USB_MOUNT/restic-repo"
    export RESTIC_REPOSITORY="$REPO"

    echo "Enter restic password:"
    read -rs RESTIC_PASSWORD
    export RESTIC_PASSWORD
    echo ""
}

# ============================================================
# List snapshots
# ============================================================

list_snapshots() {
    log_section "Available Snapshots"
    restic snapshots
}

# ============================================================
# Restore menu
# ============================================================

restore_menu() {
    echo ""
    echo "What would you like to restore?"
    echo ""
    echo "  1) SSH keys only (~/.ssh)"
    echo "  2) SSH + GPG keys"
    echo "  3) Projects (~/dev/projects)"
    echo "  4) Everything (full restore)"
    echo "  5) Custom path"
    echo "  6) Browse snapshot contents"
    echo "  7) Back to main menu"
    echo ""
    read -rp "Choice [1-7]: " restore_choice
}

# ============================================================
# Restore functions
# ============================================================

restore_ssh() {
    log "Restoring SSH keys..."

    # Backup existing if present
    if [ -d "$HOME/.ssh" ]; then
        log_warning "Existing ~/.ssh found, backing up to ~/.ssh.bak"
        mv "$HOME/.ssh" "$HOME/.ssh.bak.$(date +%s)"
    fi

    restic restore latest --target "$HOME" --include "/.ssh"

    # Fix permissions
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
    chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null || true

    log "SSH keys restored and permissions fixed"
}

restore_gpg() {
    log "Restoring GPG keys..."

    if [ -d "$HOME/.gnupg" ]; then
        log_warning "Existing ~/.gnupg found, backing up"
        mv "$HOME/.gnupg" "$HOME/.gnupg.bak.$(date +%s)"
    fi

    restic restore latest --target "$HOME" --include "/.gnupg"

    chmod 700 "$HOME/.gnupg"
    log "GPG keys restored"
}

restore_projects() {
    log "Restoring projects..."

    mkdir -p "$HOME/dev"

    restic restore latest --target "$HOME" --include "/dev/projects"

    log "Projects restored to ~/dev/projects"
}

restore_full() {
    log_warning "Full restore will overwrite existing files!"
    read -rp "Continue? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Cancelled"
        return
    fi

    log "Performing full restore..."

    # Create restore directory to avoid overwriting
    RESTORE_DIR="$HOME/restore_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$RESTORE_DIR"

    restic restore latest --target "$RESTORE_DIR"

    log "Restored to: $RESTORE_DIR"
    log "Review contents and move to appropriate locations"
}

restore_custom() {
    echo "Enter path to restore (e.g., /dev/projects/myproject):"
    read -r custom_path

    echo "Restore to [home directory]: "
    read -r target_dir
    target_dir="${target_dir:-$HOME}"

    restic restore latest --target "$target_dir" --include "$custom_path"

    log "Restored $custom_path to $target_dir"
}

browse_snapshot() {
    echo "Enter snapshot ID (or 'latest'):"
    read -r snapshot_id
    snapshot_id="${snapshot_id:-latest}"

    log "Contents of snapshot $snapshot_id:"
    restic ls "$snapshot_id" | head -100

    echo ""
    echo "(Showing first 100 entries. Use 'restic ls $snapshot_id | less' for full list)"
}

# ============================================================
# Main
# ============================================================

main() {
    # Check for restic
    if ! command -v restic &> /dev/null; then
        log_error "restic not found"
        echo ""
        echo "Install restic first:"
        echo "  brew install restic"
        exit 1
    fi

    while true; do
        show_menu

        case $choice in
            1)
                setup_b2
                list_snapshots

                while true; do
                    restore_menu
                    case $restore_choice in
                        1) restore_ssh ;;
                        2) restore_ssh; restore_gpg ;;
                        3) restore_projects ;;
                        4) restore_full ;;
                        5) restore_custom ;;
                        6) browse_snapshot ;;
                        7) break ;;
                        *) echo "Invalid choice" ;;
                    esac
                done
                ;;
            2)
                setup_usb
                list_snapshots

                while true; do
                    restore_menu
                    case $restore_choice in
                        1) restore_ssh ;;
                        2) restore_ssh; restore_gpg ;;
                        3) restore_projects ;;
                        4) restore_full ;;
                        5) restore_custom ;;
                        6) browse_snapshot ;;
                        7) break ;;
                        *) echo "Invalid choice" ;;
                    esac
                done
                ;;
            3)
                log "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid choice"
                ;;
        esac
    done
}

main "$@"
