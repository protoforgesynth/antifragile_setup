#!/bin/bash
# init-dotfiles.sh — Initialize bare git repo for dotfiles management
# Run once on a fresh system to set up dotfiles tracking

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[dotfiles]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[dotfiles]${NC} $1"; }
log_error() { echo -e "${RED}[dotfiles]${NC} $1" >&2; }

DOTFILES_DIR="$HOME/.dotfiles"
DOTFILES_ALIAS='dotfiles'

# ============================================================
# Check if already initialized
# ============================================================

if [ -d "$DOTFILES_DIR" ]; then
    log_warning "Dotfiles repo already exists at $DOTFILES_DIR"
    read -rp "Reinitialize? This will NOT delete existing data. [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Aborted"
        exit 0
    fi
fi

# ============================================================
# Initialize bare repo
# ============================================================

log "Initializing bare git repository..."

git init --bare "$DOTFILES_DIR"

# Configure to hide untracked files (very important!)
git --git-dir="$DOTFILES_DIR" --work-tree="$HOME" config --local status.showUntrackedFiles no

log "Bare repo created at $DOTFILES_DIR"

# ============================================================
# Add shell alias
# ============================================================

ALIAS_CMD="alias $DOTFILES_ALIAS='git --git-dir=\$HOME/.dotfiles --work-tree=\$HOME'"

add_to_shell_config() {
    local config_file="$1"
    local shell_name="$2"

    if [ -f "$config_file" ]; then
        if ! grep -q "alias $DOTFILES_ALIAS=" "$config_file" 2>/dev/null; then
            echo "" >> "$config_file"
            echo "# Dotfiles management" >> "$config_file"
            echo "$ALIAS_CMD" >> "$config_file"
            log "Added alias to $config_file"
        else
            log "$shell_name already has dotfiles alias"
        fi
    fi
}

# Fish shell (different syntax)
if [ -d "$HOME/.config/fish" ]; then
    FISH_CONF="$HOME/.config/fish/config.fish"
    if ! grep -q "alias $DOTFILES_ALIAS" "$FISH_CONF" 2>/dev/null; then
        mkdir -p "$HOME/.config/fish"
        echo "" >> "$FISH_CONF"
        echo "# Dotfiles management" >> "$FISH_CONF"
        echo "alias $DOTFILES_ALIAS 'git --git-dir=\$HOME/.dotfiles --work-tree=\$HOME'" >> "$FISH_CONF"
        log "Added alias to fish config"
    fi
fi

# Bash
add_to_shell_config "$HOME/.bashrc" "Bash"
add_to_shell_config "$HOME/.bash_profile" "Bash profile"

# Zsh
add_to_shell_config "$HOME/.zshrc" "Zsh"

# ============================================================
# Create .gitignore for dotfiles
# ============================================================

DOTFILES_IGNORE="$HOME/.dotfiles-ignore"

cat > "$DOTFILES_IGNORE" << 'EOF'
# Dotfiles gitignore - files to NOT track
# Add paths here to ignore them from dotfiles tracking

# This file itself
.dotfiles-ignore

# Large directories
.cache
.local/share/Trash
.Trash
node_modules
.npm
.nvm
.cargo/registry
.rustup
.pyenv/versions

# Sensitive
.ssh/id_*
.gnupg/private-keys*
.netrc
*credentials*
*secret*
*.pem
*.key

# macOS
.DS_Store
.Spotlight-V100
.Trashes
.fseventsd

# Application data (too large/volatile)
Library/
.local/share/
.config/google-chrome
.config/chromium
.mozilla

# Editor state
.vscode/workspaceStorage
.idea
*.swp
*.swo
EOF

log "Created $DOTFILES_IGNORE"

# ============================================================
# Initial commit
# ============================================================

# For immediate use in this session
dotfiles() {
    git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"
}

log "Creating initial commit..."

# Add some safe default files
SAFE_FILES=(
    ".gitconfig"
    ".gitignore_global"
)

for file in "${SAFE_FILES[@]}"; do
    if [ -f "$HOME/$file" ]; then
        dotfiles add "$HOME/$file" 2>/dev/null || true
    fi
done

dotfiles commit -m "Initial dotfiles commit" --allow-empty

# ============================================================
# Instructions
# ============================================================

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Dotfiles Repo Initialized!                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Usage:"
echo ""
echo "  # Restart shell or run:"
echo "  source ~/.bashrc  # or ~/.zshrc"
echo ""
echo "  # Add a config file:"
echo "  $DOTFILES_ALIAS add ~/.config/fish/config.fish"
echo ""
echo "  # Commit changes:"
echo "  $DOTFILES_ALIAS commit -m 'add fish config'"
echo ""
echo "  # Check status:"
echo "  $DOTFILES_ALIAS status"
echo ""
echo "  # Add remote (GitHub):"
echo "  $DOTFILES_ALIAS remote add origin git@github.com:USER/dotfiles.git"
echo "  $DOTFILES_ALIAS push -u origin main"
echo ""
echo "Recommended files to track:"
echo "  ~/.config/fish/           - Fish shell"
echo "  ~/.config/kitty/          - Kitty terminal"
echo "  ~/.gitconfig              - Git config"
echo "  ~/.config/starship.toml   - Starship prompt"
echo "  ~/.vimrc or ~/.config/nvim/ - Vim/Neovim"
echo ""
echo -e "${YELLOW}Tip:${NC} Run 'discover-dotfiles.sh' to see all your configs"
