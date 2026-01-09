# Emergency Recovery Guide

This guide helps you restore your data after a complete system loss.

## Scenario: Lost/Stolen Laptop

### Step 1: Get New Hardware

1. Acquire new Mac
2. Complete initial macOS setup
3. Skip iCloud restore (we'll do manual restore)

### Step 2: Install Prerequisites

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to PATH (Apple Silicon)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Install restic
brew install restic
```

### Step 3: Restore SSH Keys (Priority!)

```bash
# Set B2 credentials
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-app-key"
export RESTIC_REPOSITORY="b2:your-bucket:restic-backup"
export RESTIC_PASSWORD="your-restic-password"

# List available snapshots
restic snapshots

# Restore SSH keys
restic restore latest --target ~/ --include "/.ssh"

# Fix permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub
chmod 644 ~/.ssh/config
chmod 644 ~/.ssh/known_hosts
```

### Step 4: Restore GPG Keys

```bash
restic restore latest --target ~/ --include "/.gnupg"
chmod 700 ~/.gnupg
```

### Step 5: Clone This Repo

```bash
mkdir -p ~/dev/projects
cd ~/dev/projects
git clone git@github.com:YOUR_USER/antifragile_setup.git
cd antifragile_setup
```

### Step 6: Restore Dotfiles

```bash
# Clone dotfiles bare repo
git clone --bare git@github.com:YOUR_USER/dotfiles.git ~/.dotfiles

# Define alias
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'

# Checkout files
dotfiles checkout

# If conflicts, backup existing files first:
mkdir -p ~/.dotfiles-backup
dotfiles checkout 2>&1 | grep -E "^\s+" | awk '{print $1}' | xargs -I{} mv {} ~/.dotfiles-backup/{}
dotfiles checkout
```

### Step 7: Restore Homebrew Packages

```bash
# Restore Brewfile from backup
restic restore latest --target ~/ --include "/Brewfile"

# Or if in dotfiles:
dotfiles checkout ~/Brewfile

# Install all packages
brew bundle --file=~/Brewfile
```

### Step 8: Restore Projects

```bash
restic restore latest --target ~/ --include "/dev"
```

### Step 9: Restore Remaining Data

```bash
# Full restore to temp directory
restic restore latest --target ~/restore_temp

# Review and move what you need
ls ~/restore_temp
```

### Step 10: Setup Automatic Backups

```bash
cd ~/dev/projects/antifragile_setup
./scripts/setup.sh
```

---

## Scenario: USB Only Recovery

If B2 is unavailable but you have USB:

```bash
# Mount USB drive (should be named ANTIFRAGILE)

# Set password
export RESTIC_PASSWORD="your-usb-password"

# List snapshots
restic -r /Volumes/ANTIFRAGILE/restic-repo snapshots

# Restore
restic -r /Volumes/ANTIFRAGILE/restic-repo restore latest --target ~/
```

### Emergency Files on USB

If restic itself is unavailable:

```bash
# Decrypt SSH keys
gpg -d /Volumes/ANTIFRAGILE/emergency/ssh-keys.tar.gpg | tar xf -

# Import GPG keys
gpg --import /Volumes/ANTIFRAGILE/emergency/gpg-secret-keys.asc
```

---

## Scenario: Fresh macOS Install (Same Mac)

### Before Wiping

1. Run `pre-wipe-checklist.sh`
2. Ensure B2 backup is fresh
3. Ensure USB backup is connected and fresh
4. Note your restic password!

### Create Bootable Installer

```bash
# Download latest macOS from App Store, then:
sudo /Applications/Install\ macOS\ Sequoia.app/Contents/Resources/createinstallmedia \
    --volume /Volumes/USB_INSTALLER
```

### Wipe and Install

1. Restart, hold Power button (Apple Silicon)
2. Select Options → Disk Utility
3. Erase internal drive (APFS encrypted)
4. Install macOS
5. Follow recovery steps above

---

## Important Passwords/Credentials

Store these in multiple locations:

| Item | Primary Storage | Backup Storage |
|------|----------------|----------------|
| Restic password | Password manager | Printed in safe |
| B2 Account ID | Password manager | Printed in safe |
| B2 Application Key | Password manager | — |
| USB restic password | Password manager | Memorized |
| GPG passphrase | Memorized | Printed in safe |
| Apple ID | Password manager | Memorized |

---

## Useful Restic Commands

```bash
# List snapshots
restic snapshots

# List files in snapshot
restic ls latest
restic ls latest /dev/projects

# Find specific file
restic find "*.fish"

# Restore specific path
restic restore latest --target ~/restore --include "/path/to/file"

# Mount as filesystem (explore interactively)
mkdir /tmp/restic-mount
restic mount /tmp/restic-mount
# Browse in Finder, then:
umount /tmp/restic-mount

# Check backup integrity
restic check

# Show stats
restic stats
```

---

## Troubleshooting

### "Repository not found"

```bash
# Check credentials
echo $RESTIC_REPOSITORY
echo $B2_ACCOUNT_ID

# Try initializing (will fail safely if exists)
restic init
```

### "Wrong password"

- Triple-check the password
- Check for copy-paste issues (hidden characters)
- Try typing manually

### "Permission denied" on SSH

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
```

### Slow restore

```bash
# Limit bandwidth if needed
restic restore latest --target ~/ --limit-download 5000
```
