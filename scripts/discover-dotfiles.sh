#!/bin/bash
# discover-dotfiles.sh — Scan macOS for all dotfiles and configs worth backing up
# Run this BEFORE setting up backups to understand what you have

set -euo pipefail

OUTPUT_DIR="${1:-$HOME/dotfiles-inventory}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$OUTPUT_DIR/inventory_$TIMESTAMP.md"

mkdir -p "$OUTPUT_DIR"

echo "# Dotfiles Inventory Report" > "$REPORT"
echo "Generated: $(date)" >> "$REPORT"
echo "" >> "$REPORT"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
    echo "" >> "$REPORT"
    echo "## $1" >> "$REPORT"
    echo "" >> "$REPORT"
}

log_item() {
    echo -e "  ${GREEN}✓${NC} $1"
    echo "- $1" >> "$REPORT"
}

log_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    echo "- ⚠️ $1" >> "$REPORT"
}

log_size() {
    local path="$1"
    if [ -e "$path" ]; then
        local size=$(du -sh "$path" 2>/dev/null | cut -f1)
        echo "$size"
    else
        echo "N/A"
    fi
}

echo -e "${BLUE}Scanning your macOS for dotfiles and configs...${NC}"
echo ""

# ============================================================
log_section "1. Shell Configurations"
# ============================================================

# Fish
if [ -d "$HOME/.config/fish" ]; then
    log_item "Fish shell: ~/.config/fish/ ($(log_size "$HOME/.config/fish"))"
    echo "  - config.fish" >> "$REPORT"
    ls "$HOME/.config/fish/functions/" 2>/dev/null | head -10 | while read f; do
        echo "  - functions/$f" >> "$REPORT"
    done
fi

# Zsh
[ -f "$HOME/.zshrc" ] && log_item "Zsh: ~/.zshrc"
[ -f "$HOME/.zprofile" ] && log_item "Zsh: ~/.zprofile"
[ -f "$HOME/.zshenv" ] && log_item "Zsh: ~/.zshenv"
[ -d "$HOME/.oh-my-zsh" ] && log_item "Oh My Zsh: ~/.oh-my-zsh/ ($(log_size "$HOME/.oh-my-zsh"))"

# Bash
[ -f "$HOME/.bashrc" ] && log_item "Bash: ~/.bashrc"
[ -f "$HOME/.bash_profile" ] && log_item "Bash: ~/.bash_profile"
[ -f "$HOME/.bash_aliases" ] && log_item "Bash: ~/.bash_aliases"

# Starship prompt
[ -f "$HOME/.config/starship.toml" ] && log_item "Starship: ~/.config/starship.toml"

# ============================================================
log_section "2. SSH & Security"
# ============================================================

if [ -d "$HOME/.ssh" ]; then
    log_warning "SSH directory: ~/.ssh/ ($(log_size "$HOME/.ssh")) - CRITICAL!"
    echo "  Contents:" >> "$REPORT"
    ls -la "$HOME/.ssh/" 2>/dev/null | grep -v '^total' | while read line; do
        echo "    $line" >> "$REPORT"
    done
fi

[ -d "$HOME/.gnupg" ] && log_warning "GPG keys: ~/.gnupg/ ($(log_size "$HOME/.gnupg")) - CRITICAL!"
[ -f "$HOME/.netrc" ] && log_warning "Netrc: ~/.netrc - contains credentials!"

# ============================================================
log_section "3. Development Tools"
# ============================================================

# Git
[ -f "$HOME/.gitconfig" ] && log_item "Git: ~/.gitconfig"
[ -f "$HOME/.gitignore_global" ] && log_item "Git: ~/.gitignore_global"

# Node.js
[ -f "$HOME/.npmrc" ] && log_item "npm: ~/.npmrc"
[ -f "$HOME/.yarnrc" ] && log_item "Yarn: ~/.yarnrc"
[ -d "$HOME/.nvm" ] && log_item "NVM: ~/.nvm/ ($(log_size "$HOME/.nvm"))"
[ -d "$HOME/.volta" ] && log_item "Volta: ~/.volta/ ($(log_size "$HOME/.volta"))"

# Python
[ -f "$HOME/.pypirc" ] && log_item "PyPI: ~/.pypirc"
[ -d "$HOME/.pyenv" ] && log_item "pyenv: ~/.pyenv/ ($(log_size "$HOME/.pyenv"))"
[ -f "$HOME/.python-version" ] && log_item "Python version: ~/.python-version"

# Ruby
[ -f "$HOME/.gemrc" ] && log_item "Ruby gems: ~/.gemrc"
[ -d "$HOME/.rbenv" ] && log_item "rbenv: ~/.rbenv/ ($(log_size "$HOME/.rbenv"))"

# Rust
[ -d "$HOME/.cargo" ] && log_item "Cargo: ~/.cargo/ ($(log_size "$HOME/.cargo"))"
[ -d "$HOME/.rustup" ] && log_item "Rustup: ~/.rustup/ ($(log_size "$HOME/.rustup"))"

# Go
[ -d "$HOME/.go" ] && log_item "Go: ~/.go/ ($(log_size "$HOME/.go"))"
[ -d "$HOME/go" ] && log_item "Go workspace: ~/go/ ($(log_size "$HOME/go"))"

# Docker
[ -f "$HOME/.docker/config.json" ] && log_item "Docker: ~/.docker/config.json"

# Kubernetes
[ -d "$HOME/.kube" ] && log_item "Kubernetes: ~/.kube/ ($(log_size "$HOME/.kube"))"

# ============================================================
log_section "4. Terminal Emulators"
# ============================================================

[ -d "$HOME/.config/kitty" ] && log_item "Kitty: ~/.config/kitty/ ($(log_size "$HOME/.config/kitty"))"
[ -d "$HOME/.config/alacritty" ] && log_item "Alacritty: ~/.config/alacritty/"
[ -f "$HOME/.tmux.conf" ] && log_item "Tmux: ~/.tmux.conf"
[ -d "$HOME/.tmux" ] && log_item "Tmux plugins: ~/.tmux/"

# iTerm2 (macOS specific)
ITERM_PREFS="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
[ -f "$ITERM_PREFS" ] && log_item "iTerm2: ~/Library/Preferences/com.googlecode.iterm2.plist"

# ============================================================
log_section "5. Editors & IDEs"
# ============================================================

# Vim/Neovim
[ -f "$HOME/.vimrc" ] && log_item "Vim: ~/.vimrc"
[ -d "$HOME/.vim" ] && log_item "Vim: ~/.vim/ ($(log_size "$HOME/.vim"))"
[ -d "$HOME/.config/nvim" ] && log_item "Neovim: ~/.config/nvim/ ($(log_size "$HOME/.config/nvim"))"

# VSCode
VSCODE_USER="$HOME/Library/Application Support/Code/User"
if [ -d "$VSCODE_USER" ]; then
    log_item "VSCode settings: ($(log_size "$VSCODE_USER"))"
    echo "  - settings.json" >> "$REPORT"
    echo "  - keybindings.json" >> "$REPORT"
    echo "  - snippets/" >> "$REPORT"
fi

# Cursor (VSCode fork)
CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
[ -d "$CURSOR_USER" ] && log_item "Cursor settings: ($(log_size "$CURSOR_USER"))"

# JetBrains
JETBRAINS_DIR="$HOME/Library/Application Support/JetBrains"
if [ -d "$JETBRAINS_DIR" ]; then
    log_item "JetBrains IDEs:"
    ls "$JETBRAINS_DIR" 2>/dev/null | while read ide; do
        echo "  - $ide" >> "$REPORT"
    done
fi

# Sublime Text
[ -d "$HOME/Library/Application Support/Sublime Text" ] && log_item "Sublime Text settings"

# ============================================================
log_section "6. Package Managers"
# ============================================================

# Homebrew
if command -v brew &> /dev/null; then
    BREW_COUNT=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    CASK_COUNT=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
    log_item "Homebrew: $BREW_COUNT formulae, $CASK_COUNT casks"

    # Save Brewfile
    echo "  Saving Brewfile..."
    brew bundle dump --file="$OUTPUT_DIR/Brewfile" --force 2>/dev/null || true
    echo "  - Brewfile saved to $OUTPUT_DIR/Brewfile" >> "$REPORT"
fi

# ============================================================
log_section "7. macOS Application Configs"
# ============================================================

APP_SUPPORT="$HOME/Library/Application Support"
if [ -d "$APP_SUPPORT" ]; then
    echo "Notable Application Support directories:" >> "$REPORT"

    # Check common important apps
    [ -d "$APP_SUPPORT/obsidian" ] && log_item "Obsidian config"
    [ -d "$APP_SUPPORT/Claude" ] && log_item "Claude app config"
    [ -d "$APP_SUPPORT/Raycast" ] && log_item "Raycast config"
    [ -d "$APP_SUPPORT/Alfred" ] && log_item "Alfred config"
    [ -d "$APP_SUPPORT/1Password" ] && log_item "1Password config"
    [ -d "$APP_SUPPORT/Spotify" ] && log_item "Spotify config"
    [ -d "$APP_SUPPORT/Slack" ] && log_item "Slack config"
    [ -d "$APP_SUPPORT/Discord" ] && log_item "Discord config"
fi

# ============================================================
log_section "8. XDG Config Directory (~/.config)"
# ============================================================

if [ -d "$HOME/.config" ]; then
    echo "Contents of ~/.config/:" >> "$REPORT"
    ls -1 "$HOME/.config/" 2>/dev/null | while read item; do
        size=$(log_size "$HOME/.config/$item")
        log_item "$item ($size)"
    done
fi

# ============================================================
log_section "9. Data Directories to Backup"
# ============================================================

[ -d "$HOME/dev" ] && log_item "Dev directory: ~/dev/ ($(log_size "$HOME/dev"))"
[ -d "$HOME/dev/projects" ] && log_item "Projects: ~/dev/projects/ ($(log_size "$HOME/dev/projects"))"
[ -d "$HOME/obsidian_vaults" ] && log_item "Obsidian vaults: ~/obsidian_vaults/ ($(log_size "$HOME/obsidian_vaults"))"
[ -d "$HOME/Documents" ] && log_item "Documents: ~/Documents/ ($(log_size "$HOME/Documents"))"

# ============================================================
log_section "10. All Dotfiles in Home Directory"
# ============================================================

echo "All dotfiles/dotdirs in ~/:" >> "$REPORT"
echo '```' >> "$REPORT"
ls -la "$HOME" 2>/dev/null | grep '^\.' | grep -v '^\.\.$' | grep -v '^\.DS_Store' >> "$REPORT" || true
echo '```' >> "$REPORT"

# ============================================================
# Summary
# ============================================================

echo ""
echo -e "${GREEN}=== SCAN COMPLETE ===${NC}"
echo ""
echo "Report saved to: $REPORT"
echo "Brewfile saved to: $OUTPUT_DIR/Brewfile (if Homebrew installed)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the report: cat $REPORT"
echo "2. Decide what to include in your dotfiles repo"
echo "3. Run the backup setup script"
