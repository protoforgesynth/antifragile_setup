#!/bin/bash
# pre-wipe-checklist.sh — Verify everything is backed up before wiping macOS
# RUN THIS BEFORE ERASING YOUR MAC!

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++))
}

section() {
    echo ""
    echo -e "${BLUE}━━━ $1 ━━━${NC}"
}

# ============================================================
# Header
# ============================================================

echo ""
echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                  PRE-WIPE CHECKLIST                        ║${NC}"
echo -e "${RED}║          Run this BEFORE erasing your Mac!                 ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# Load credentials
# ============================================================

CONFIG_DIR="${ANTIFRAGILE_CONFIG:-$HOME/.config/antifragile}"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.env"

if [ -f "$CREDENTIALS_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CREDENTIALS_FILE"
fi

# ============================================================
# 1. Check B2 Backup
# ============================================================

section "1. Backblaze B2 Backup"

if [ -z "${RESTIC_REPOSITORY:-}" ] || [ -z "${RESTIC_PASSWORD:-}" ]; then
    check_fail "B2 credentials not configured"
else
    if command -v restic &> /dev/null; then
        # Check if we can connect
        if restic snapshots --last 1 &> /dev/null; then
            LAST_B2=$(restic snapshots --last 1 --json 2>/dev/null | grep -o '"time":"[^"]*"' | head -1 | cut -d'"' -f4)
            check_pass "B2 backup accessible, last snapshot: $LAST_B2"

            # Check age of backup
            if [ -n "$LAST_B2" ]; then
                LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_B2:0:19}" "+%s" 2>/dev/null || echo 0)
                NOW_EPOCH=$(date "+%s")
                AGE_HOURS=$(( (NOW_EPOCH - LAST_EPOCH) / 3600 ))

                if [ "$AGE_HOURS" -gt 48 ]; then
                    check_warn "Last backup is $AGE_HOURS hours old (>48h)"
                else
                    check_pass "Backup is recent ($AGE_HOURS hours old)"
                fi
            fi
        else
            check_fail "Cannot connect to B2 repository"
        fi
    else
        check_fail "restic not installed"
    fi
fi

# ============================================================
# 2. Check USB Backup
# ============================================================

section "2. USB Backup"

USB_PATHS=("/Volumes/ANTIFRAGILE" "/Volumes/Backup" "/Volumes/USB")
USB_FOUND=""

for usb in "${USB_PATHS[@]}"; do
    if [ -d "$usb/restic-repo" ]; then
        USB_FOUND="$usb"
        break
    fi
done

if [ -n "$USB_FOUND" ]; then
    check_pass "USB backup found at $USB_FOUND"

    # Check USB backup age
    if command -v restic &> /dev/null; then
        export RESTIC_REPOSITORY="$USB_FOUND/restic-repo"
        if LAST_USB=$(restic snapshots --last 1 --json 2>/dev/null | grep -o '"time":"[^"]*"' | head -1 | cut -d'"' -f4); then
            check_pass "USB last snapshot: $LAST_USB"
        fi
    fi
else
    check_warn "USB backup drive not connected"
fi

# ============================================================
# 3. Check SSH Keys
# ============================================================

section "3. SSH Keys"

if [ -d "$HOME/.ssh" ]; then
    KEY_COUNT=$(ls "$HOME/.ssh"/*.pub 2>/dev/null | wc -l | tr -d ' ')
    check_pass "Found $KEY_COUNT SSH public keys"

    # Verify keys are in backup
    if [ -n "${RESTIC_REPOSITORY:-}" ]; then
        if restic ls latest 2>/dev/null | grep -q ".ssh"; then
            check_pass "SSH keys found in B2 backup"
        else
            check_fail "SSH keys NOT found in B2 backup!"
        fi
    fi
else
    check_warn "No ~/.ssh directory found"
fi

# ============================================================
# 4. Check GPG Keys
# ============================================================

section "4. GPG Keys"

if command -v gpg &> /dev/null; then
    SECRET_KEYS=$(gpg --list-secret-keys 2>/dev/null | grep -c "^sec" || echo 0)
    if [ "$SECRET_KEYS" -gt 0 ]; then
        check_pass "Found $SECRET_KEYS GPG secret keys"

        # Verify in backup
        if [ -n "${RESTIC_REPOSITORY:-}" ]; then
            if restic ls latest 2>/dev/null | grep -q ".gnupg"; then
                check_pass "GPG keys found in B2 backup"
            else
                check_warn "GPG keys may not be in backup"
            fi
        fi
    else
        check_warn "No GPG secret keys found"
    fi
else
    check_warn "GPG not installed"
fi

# ============================================================
# 5. Check Dotfiles Repo
# ============================================================

section "5. Dotfiles Repository"

if [ -d "$HOME/.dotfiles" ]; then
    # Check if pushed to remote
    cd "$HOME"
    DOTFILES_CMD="git --git-dir=$HOME/.dotfiles --work-tree=$HOME"

    if $DOTFILES_CMD remote -v 2>/dev/null | grep -q "origin"; then
        REMOTE_URL=$($DOTFILES_CMD remote get-url origin 2>/dev/null)
        check_pass "Dotfiles repo has remote: $REMOTE_URL"

        # Check if up to date
        if $DOTFILES_CMD status --porcelain 2>/dev/null | grep -q .; then
            check_warn "Dotfiles has uncommitted changes!"
        else
            check_pass "Dotfiles is clean"
        fi
    else
        check_warn "Dotfiles repo has no remote configured"
    fi
else
    check_warn "No dotfiles repo found at ~/.dotfiles"
fi

# ============================================================
# 6. Check Homebrew
# ============================================================

section "6. Homebrew Packages"

if command -v brew &> /dev/null; then
    FORMULA_COUNT=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    CASK_COUNT=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
    check_pass "Homebrew: $FORMULA_COUNT formulae, $CASK_COUNT casks"

    # Check for Brewfile
    if [ -f "$HOME/Brewfile" ]; then
        check_pass "Brewfile exists at ~/Brewfile"
    else
        check_warn "No Brewfile found - creating one now..."
        brew bundle dump --file="$HOME/Brewfile" --force 2>/dev/null && \
            check_pass "Brewfile created at ~/Brewfile" || \
            check_fail "Failed to create Brewfile"
    fi
else
    check_warn "Homebrew not installed"
fi

# ============================================================
# 7. Check Important Directories
# ============================================================

section "7. Important Directories"

check_dir() {
    local dir="$1"
    local name="$2"

    if [ -d "$dir" ]; then
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        check_pass "$name exists ($size)"

        # Verify in backup
        if [ -n "${RESTIC_REPOSITORY:-}" ]; then
            local search_path="${dir#$HOME}"
            if restic ls latest 2>/dev/null | grep -q "$search_path"; then
                check_pass "$name found in backup"
            else
                check_warn "$name may not be in backup"
            fi
        fi
    else
        check_warn "$name not found"
    fi
}

check_dir "$HOME/dev/projects" "Projects"
check_dir "$HOME/dev" "Dev directory"
check_dir "$HOME/obsidian_vaults" "Obsidian vaults"

# ============================================================
# 8. Password Check (Manual)
# ============================================================

section "8. Password & Credential Check"

echo -e "  ${YELLOW}Manual verification required:${NC}"
echo "  [ ] Restic password saved in password manager?"
echo "  [ ] Restic password printed and stored safely?"
echo "  [ ] Backblaze B2 credentials saved?"
echo "  [ ] 2FA recovery codes backed up?"
echo "  [ ] Apple ID password remembered?"
echo "  [ ] FileVault recovery key saved?"

# ============================================================
# 9. iCloud Check (Manual)
# ============================================================

section "9. iCloud Sync"

echo -e "  ${YELLOW}Manual verification required:${NC}"
echo "  [ ] iCloud Drive fully synced? (check for cloud icons)"
echo "  [ ] iCloud Photos synced?"
echo "  [ ] iCloud Keychain synced?"
echo "  [ ] Notes synced?"

# ============================================================
# Summary
# ============================================================

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "SUMMARY:"
echo -e "  ${GREEN}✓ Passed:${NC}  $CHECKS_PASSED"
echo -e "  ${YELLOW}⚠ Warning:${NC} $CHECKS_WARNING"
echo -e "  ${RED}✗ Failed:${NC}  $CHECKS_FAILED"
echo ""

if [ "$CHECKS_FAILED" -gt 0 ]; then
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⛔ DO NOT WIPE - Fix failed checks first!                 ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 1
elif [ "$CHECKS_WARNING" -gt 3 ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  Many warnings - review before proceeding              ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Looking good! Complete manual checks above.            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo "Next steps:"
echo "  1. Complete manual verification items above"
echo "  2. Run one final backup: backup-to-b2.sh && backup-to-usb.sh"
echo "  3. Verify you can access B2 from another device"
echo "  4. Create bootable macOS installer USB"
echo "  5. Proceed with wipe"
