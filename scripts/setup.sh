#!/bin/bash
# setup.sh — Full setup of Antifragile backup system
# Run this after installing the project

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[setup]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[setup]${NC} $1"; }
log_error() { echo -e "${RED}[setup]${NC} $1" >&2; }
section() { echo ""; echo -e "${BLUE}=== $1 ===${NC}"; }

# ============================================================
# Header
# ============================================================

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Antifragile Setup Installation                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# 1. Check prerequisites
# ============================================================

section "Checking Prerequisites"

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    log_warning "Homebrew not installed"
    read -rp "Install Homebrew? [Y/n]: " install_brew
    if [[ ! "$install_brew" =~ ^[Nn]$ ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        log_error "Homebrew required for restic installation"
        exit 1
    fi
fi
log "Homebrew: OK"

# Check/install restic
if ! command -v restic &> /dev/null; then
    log "Installing restic..."
    brew install restic
fi
log "Restic: OK ($(restic version | head -1))"

# Check for git
if ! command -v git &> /dev/null; then
    log_error "Git not installed"
    exit 1
fi
log "Git: OK"

# ============================================================
# 2. Create config directory
# ============================================================

section "Setting Up Config Directory"

CONFIG_DIR="$HOME/.config/antifragile"
mkdir -p "$CONFIG_DIR"
mkdir -p "$HOME/.local/log/antifragile"

log "Created $CONFIG_DIR"

# Copy config files
cp "$PROJECT_DIR/config/backup.conf" "$CONFIG_DIR/"
cp "$PROJECT_DIR/config/exclude.conf" "$CONFIG_DIR/"

if [ ! -f "$CONFIG_DIR/credentials.env" ]; then
    cp "$PROJECT_DIR/config/credentials.env.template" "$CONFIG_DIR/credentials.env"
    chmod 600 "$CONFIG_DIR/credentials.env"
    log_warning "Created credentials.env - EDIT THIS FILE!"
else
    log "credentials.env already exists"
fi

log "Config files installed"

# ============================================================
# 3. Backblaze B2 setup
# ============================================================

section "Backblaze B2 Configuration"

echo ""
echo "Do you have a Backblaze B2 account?"
echo "  1) Yes, configure now"
echo "  2) No, I'll set it up later"
echo ""
read -rp "Choice [1-2]: " b2_choice

if [ "$b2_choice" = "1" ]; then
    echo ""
    echo "Enter B2 Account ID (from Backblaze dashboard):"
    read -r B2_ACCOUNT_ID

    echo "Enter B2 Application Key:"
    read -rs B2_ACCOUNT_KEY
    echo ""

    echo "Enter bucket name (e.g., my-backup-bucket):"
    read -r B2_BUCKET

    echo "Enter restic repository path in bucket (e.g., restic-backup):"
    read -r REPO_PATH

    echo ""
    echo "Enter a STRONG password for restic encryption:"
    echo "(Store this safely - if lost, backups are UNRECOVERABLE!)"
    read -rs RESTIC_PASSWORD
    echo ""

    # Update credentials file
    cat > "$CONFIG_DIR/credentials.env" << EOF
# Antifragile Backup Credentials
# Generated: $(date)
# WARNING: Keep this file secure!

export B2_ACCOUNT_ID="$B2_ACCOUNT_ID"
export B2_ACCOUNT_KEY="$B2_ACCOUNT_KEY"
export RESTIC_REPOSITORY="b2:$B2_BUCKET:$REPO_PATH"
export RESTIC_PASSWORD="$RESTIC_PASSWORD"
EOF

    chmod 600 "$CONFIG_DIR/credentials.env"
    log "Credentials saved to $CONFIG_DIR/credentials.env"

    # Initialize restic repository
    log "Initializing restic repository on B2..."
    source "$CONFIG_DIR/credentials.env"

    if restic init 2>/dev/null; then
        log "Restic repository initialized!"
    else
        log_warning "Repository may already exist or there was an error"
    fi
else
    log "Skipping B2 setup. Edit $CONFIG_DIR/credentials.env later"
fi

# ============================================================
# 4. Install launchd job
# ============================================================

section "Setting Up Automatic Backups"

LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="com.antifragile.backup.plist"
PLIST_SRC="$PROJECT_DIR/launchd/$PLIST_FILE"
PLIST_DST="$LAUNCHD_DIR/$PLIST_FILE"

if [ -d "$HOME/Library" ]; then
    # We're on macOS
    mkdir -p "$LAUNCHD_DIR"

    # Update plist with correct paths
    sed "s|\$HOME|$HOME|g" "$PLIST_SRC" > "$PLIST_DST"

    # Update script path
    sed -i '' "s|antifragile_setup|$(basename "$PROJECT_DIR")|g" "$PLIST_DST" 2>/dev/null || true

    log "Installed launchd plist to $PLIST_DST"

    echo ""
    read -rp "Enable automatic daily backups at 12:00? [Y/n]: " enable_launchd
    if [[ ! "$enable_launchd" =~ ^[Nn]$ ]]; then
        launchctl load "$PLIST_DST" 2>/dev/null || true
        log "Automatic B2 backups enabled"
    else
        log "Skipped. Enable later with: launchctl load $PLIST_DST"
    fi

    # USB auto-backup watcher
    USB_PLIST="com.antifragile.usb-watcher.plist"
    USB_PLIST_SRC="$PROJECT_DIR/launchd/$USB_PLIST"
    USB_PLIST_DST="$LAUNCHD_DIR/$USB_PLIST"

    sed "s|\$HOME|$HOME|g" "$USB_PLIST_SRC" > "$USB_PLIST_DST"
    sed -i '' "s|antifragile_setup|$(basename "$PROJECT_DIR")|g" "$USB_PLIST_DST" 2>/dev/null || true

    echo ""
    read -rp "Enable auto-backup when USB 'ANTIFRAGILE' is inserted? [Y/n]: " enable_usb
    if [[ ! "$enable_usb" =~ ^[Nn]$ ]]; then
        launchctl load "$USB_PLIST_DST" 2>/dev/null || true
        log "USB auto-backup enabled"
    else
        log "Skipped. Enable later with: launchctl load $USB_PLIST_DST"
    fi
else
    log_warning "Not on macOS, skipping launchd setup"
    log "For Linux, create a systemd timer or cron job"
fi

# ============================================================
# 5. Dotfiles setup
# ============================================================

section "Dotfiles Repository"

if [ ! -d "$HOME/.dotfiles" ]; then
    echo ""
    read -rp "Initialize dotfiles bare repo? [Y/n]: " init_dotfiles
    if [[ ! "$init_dotfiles" =~ ^[Nn]$ ]]; then
        "$SCRIPT_DIR/init-dotfiles.sh"
    fi
else
    log "Dotfiles repo already exists"
fi

# ============================================================
# 6. Make scripts accessible
# ============================================================

section "Installing Scripts"

# Create symlinks in ~/.local/bin
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

SCRIPTS=(
    "backup-to-b2.sh"
    "backup-to-usb.sh"
    "discover-dotfiles.sh"
    "pre-wipe-checklist.sh"
    "restore-from-backup.sh"
)

for script in "${SCRIPTS[@]}"; do
    chmod +x "$SCRIPT_DIR/$script"
    ln -sf "$SCRIPT_DIR/$script" "$BIN_DIR/${script%.sh}"
done

log "Scripts linked to $BIN_DIR"

# Add to PATH if needed
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    log_warning "Add to your shell config:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Setup Complete!                               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Installed components:"
echo "  ✓ Config files in ~/.config/antifragile/"
echo "  ✓ Scripts in ~/.local/bin/"
if [ -d "$HOME/Library" ]; then
    echo "  ✓ Launchd job for automatic backups"
fi
echo ""
echo "Next steps:"
echo ""
echo "  1. Edit credentials (if not done):"
echo "     nano ~/.config/antifragile/credentials.env"
echo ""
echo "  2. Run first backup:"
echo "     backup-to-b2"
echo ""
echo "  3. Scan for dotfiles to track:"
echo "     discover-dotfiles"
echo ""
echo "  4. Add important configs to dotfiles repo:"
echo "     dotfiles add ~/.config/fish/config.fish"
echo "     dotfiles commit -m 'add fish config'"
echo ""
echo "  5. (Optional) Setup USB backup:"
echo "     Format USB as APFS encrypted, name it ANTIFRAGILE"
echo "     backup-to-usb"
echo ""
echo -e "${YELLOW}Important:${NC} Store your restic password in a safe place!"
