# Antifragile Setup

> *"Antifragile gains from disorder"* — Nassim Taleb

A complete backup system for macOS that makes losing your laptop a minor inconvenience, not a catastrophe.

## Philosophy

- **Redundancy**: 2+ copies of everything (cloud + local USB)
- **Encryption**: All backups encrypted at rest (AES-256)
- **Automation**: Daily cloud backups + auto USB backup on insert
- **Fast Recovery**: Back to productive in hours, not days

## Features

- Encrypted incremental backups to Backblaze B2 (~$3/month for 500GB)
- Auto-backup to USB when drive is inserted
- Bare git repo for dotfiles management
- Pre-wipe checklist before clean macOS installs
- Interactive restore utility

## Quick Start

### 1. Clone and Setup

```bash
git clone git@github.com:protoforgesynth/antifragile_setup.git ~/dev/projects/antifragile_setup
cd ~/dev/projects/antifragile_setup
./scripts/setup.sh
```

Setup will guide you through:
- Installing restic via Homebrew
- Configuring Backblaze B2 credentials
- Initializing restic repository
- Setting up automatic backups
- Initializing dotfiles repo

### 2. Create Backblaze B2 Account

1. Sign up at [backblaze.com/b2](https://www.backblaze.com/b2/cloud-storage.html)
2. Create a bucket (private, default encryption)
3. Create Application Key with access to your bucket
4. Note down: Account ID, Application Key, Bucket Name

### 3. Prepare USB Drive

Format your USB/external drive:

```
Disk Utility → Select Drive → Erase
  Name: ANTIFRAGILE
  Format: APFS (Encrypted)  ← adds password protection
  Scheme: GUID Partition Map
```

First backup (creates restic repo):
```bash
backup-to-usb
```

After this, backups run automatically when you insert the drive.

### 4. Discover Your Dotfiles

```bash
discover-dotfiles
# Creates inventory at ~/dotfiles-inventory/
```

### 5. Setup Dotfiles Tracking

```bash
# Add configs you want to track
dotfiles add ~/.config/fish/config.fish
dotfiles add ~/.config/kitty/kitty.conf
dotfiles add ~/.gitconfig

# Commit
dotfiles commit -m "initial dotfiles"

# Push to GitHub (create repo first)
dotfiles remote add origin git@github.com:YOUR_USER/dotfiles.git
dotfiles push -u origin main
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        MacBook                              │
│  ~/dev/projects/     — code                                 │
│  ~/obsidian_vaults/  — knowledge base                       │
│  ~/.config/          — app configs                          │
│  ~/.ssh/, ~/.gnupg/  — keys (critical!)                     │
└─────────────────────────────────────────────────────────────┘
           │                                    │
           │ Daily 12:00 (automatic)            │ On USB insert
           ▼                                    ▼
┌─────────────────────┐            ┌─────────────────────┐
│   Backblaze B2      │            │   USB ANTIFRAGILE   │
│   restic encrypted  │            │   restic encrypted  │
│   full backup       │            │   critical data     │
└─────────────────────┘            └─────────────────────┘
```

## Commands

After setup, these commands are available:

| Command | Description |
|---------|-------------|
| `backup-to-b2` | Manual backup to Backblaze B2 |
| `backup-to-usb` | Manual backup to USB |
| `restore-from-backup` | Interactive restore utility |
| `pre-wipe-checklist` | Verify backups before wiping Mac |
| `discover-dotfiles` | Scan for all dotfiles/configs |
| `dotfiles` | Git alias for dotfiles repo |

## Daily Workflow

**Automatic (no action needed):**
- 12:00 daily → `backup-to-b2` runs via launchd
- USB inserted → backup starts automatically

**Manual (recommended weekly):**
- Insert USB drive, wait for notification
- `dotfiles status` → commit new configs

## Before Wiping macOS

```bash
# 1. Run checklist
pre-wipe-checklist

# 2. Fix any failed checks

# 3. Final backup
backup-to-b2
backup-to-usb  # with USB connected

# 4. Verify you can access B2 from another device

# 5. Create bootable installer
sudo /Applications/Install\ macOS\ Sequoia.app/Contents/Resources/createinstallmedia \
    --volume /Volumes/USB_INSTALLER

# 6. Wipe and reinstall
```

## Recovery

### Quick Recovery (SSH keys first!)

```bash
# Install prerequisites
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install restic

# Set credentials
export B2_ACCOUNT_ID="..."
export B2_ACCOUNT_KEY="..."
export RESTIC_REPOSITORY="b2:bucket:repo"
export RESTIC_PASSWORD="..."

# Restore SSH keys
restic restore latest --target ~/ --include "/.ssh"
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*

# Clone this repo
git clone git@github.com:protoforgesynth/antifragile_setup.git ~/dev/projects/antifragile_setup

# Restore dotfiles
git clone --bare git@github.com:YOUR_USER/dotfiles.git ~/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
dotfiles checkout

# Restore Homebrew
brew bundle --file=~/Brewfile

# Restore everything else
restic restore latest --target ~/
```

See [docs/RECOVERY.md](docs/RECOVERY.md) for detailed instructions.

## File Structure

```
~/.config/antifragile/
├── credentials.env    # B2 credentials (never commit!)
├── backup.conf        # Paths to backup
└── exclude.conf       # Patterns to exclude

~/.local/log/antifragile/
├── backup_b2_*.log    # B2 backup logs
└── usb-auto.log       # USB auto-backup log

~/Library/LaunchAgents/
├── com.antifragile.backup.plist       # Daily B2 backup
└── com.antifragile.usb-watcher.plist  # USB auto-trigger
```

## Costs

| Storage | Monthly Cost |
|---------|--------------|
| 50 GB   | ~$0.30 |
| 100 GB  | ~$0.60 |
| 500 GB  | ~$3.00 |

Backblaze B2: $0.006/GB/month storage + $0.01/GB egress (first 3x free)

## Security

- **Encryption**: AES-256 via restic (Backblaze never sees your data)
- **USB**: APFS Encrypted adds another layer
- **Credentials**: Stored with 600 permissions, never committed
- **Keys**: SSH/GPG backed up encrypted, also separately in USB emergency/

## Critical: Password Safety

**Store your restic password in 3 places:**
1. Password manager (1Password, Bitwarden, etc.)
2. Printed copy in a safe/secure location
3. With a trusted person in sealed envelope

If you lose this password, your backups are **UNRECOVERABLE**.

## Troubleshooting

**Backup not running automatically?**
```bash
# Check if launchd job is loaded
launchctl list | grep antifragile

# Reload if needed
launchctl unload ~/Library/LaunchAgents/com.antifragile.backup.plist
launchctl load ~/Library/LaunchAgents/com.antifragile.backup.plist
```

**USB backup not triggering?**
```bash
# Check USB watcher
launchctl list | grep usb-watcher

# Check logs
tail -50 ~/.local/log/antifragile/usb-auto.log
```

**Can't connect to B2?**
```bash
# Verify credentials
source ~/.config/antifragile/credentials.env
restic snapshots
```

## License

MIT
