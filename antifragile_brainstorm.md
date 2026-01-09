# Antifragile Setup — Полный план

> *"Antifragile gains from disorder"* — Nassim Taleb

## Философия

**Цель**: Потеря/кража ноутбука = лёгкое неудобство, не катастрофа.

**Принципы**:
1. **Redundancy** — минимум 2 копии всего важного (облако + флешка)
2. **Encryption** — всё зашифровано, даже если украдут — бесполезно
3. **Automation** — бэкапы происходят автоматически, без участия человека
4. **Fast Recovery** — восстановление рабочего окружения за часы, не дни

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS Laptop                              │
├─────────────────────────────────────────────────────────────────┤
│  ~/dev/projects/     — код и проекты                            │
│  ~/dev/              — прочие dev-файлы                         │
│  ~/obsidian_vaults/  — база знаний                              │
│  ~/.dotfiles/        — симлинки на конфиги                      │
│  ~/.ssh/             — ключи (отдельно шифруем!)                │
└─────────────────────────────────────────────────────────────────┘
           │                                    │
           ▼                                    ▼
┌─────────────────────┐            ┌─────────────────────┐
│   Backblaze B2      │            │   USB Flash/SSD     │
│   (облако)          │            │   (локально)        │
│                     │            │                     │
│   restic repo       │            │   restic repo       │
│   encrypted         │            │   encrypted         │
│   incremental       │            │   critical only     │
└─────────────────────┘            └─────────────────────┘
```

---

## Компоненты системы

### 1. Restic + Backblaze B2 (основной бэкап)

**Почему restic:**
- Дедупликация — бэкапит только изменения
- Шифрование AES-256 — даже Backblaze не видит данные
- Быстрый — написан на Go
- Простой — одна команда для бэкапа

**Почему Backblaze B2:**
- $6/TB/месяц (дешевле S3 в 4 раза)
- 10GB бесплатно для старта
- Нет egress fees для первых 3x от stored data

### 2. USB Flash/SSD (критичные данные)

**Что хранить:**
- SSH ключи (зашифрованные отдельно)
- GPG ключи
- 2FA recovery codes
- Критичные пароли (если не в менеджере)
- Самые важные проекты

**Формат:** Зашифрованный APFS или LUKS-раздел

### 3. Dotfiles Manager

**Подход: Bare Git Repo**

```bash
# Инициализация
git init --bare $HOME/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
dotfiles config --local status.showUntrackedFiles no

# Использование
dotfiles add ~/.config/fish/config.fish
dotfiles commit -m "add fish config"
dotfiles push origin main
```

**Преимущества:**
- Нет симлинков
- Версионирование
- Легко восстановить на новой машине

---

## Что бэкапить — Полный список

### Tier 1: Критичное (облако + флешка)

| Путь | Описание |
|------|----------|
| `~/.ssh/` | SSH ключи (ВАЖНО: шифровать отдельно!) |
| `~/.gnupg/` | GPG ключи |
| `~/dev/projects/` | Код и проекты |
| `~/obsidian_vaults/` | База знаний |

### Tier 2: Важное (только облако)

| Путь | Описание |
|------|----------|
| `~/dev/` | Остальные dev-файлы |
| `~/.config/` | Конфиги XDG-compliant приложений |
| `~/.local/share/` | Данные приложений |
| `~/Documents/` | Документы |

### Tier 3: Конфиги (dotfiles repo + облако)

| Путь | Описание |
|------|----------|
| `~/.config/fish/` | Fish shell + алиасы |
| `~/.config/kitty/` | Kitty terminal |
| `~/.gitconfig` | Git настройки |
| `~/.npmrc` | npm config |
| `~/.cargo/` | Rust config |
| `~/Library/Application Support/Code/User/` | VSCode settings |
| `~/Library/Application Support/JetBrains/` | IDE настройки |

---

## Скрипт: Сбор всех конфигов

```bash
#!/bin/bash
# collect-dotfiles.sh — найти все конфиги которые стоит бэкапить

echo "=== DOTFILES DISCOVERY SCRIPT ==="
echo ""

# Стандартные dotfiles в home
echo "### Dotfiles в ~/ ###"
ls -la ~/ | grep '^\.' | grep -v '^\.\.$' | awk '{print $NF}'

echo ""
echo "### ~/.config/ содержимое ###"
ls -la ~/.config/ 2>/dev/null

echo ""
echo "### ~/.local/share/ содержимое ###"
ls -la ~/.local/share/ 2>/dev/null

echo ""
echo "### Homebrew packages ###"
brew list --formula
echo ""
echo "### Homebrew casks ###"
brew list --cask

echo ""
echo "### Fish functions ###"
ls ~/.config/fish/functions/ 2>/dev/null

echo ""
echo "### SSH keys ###"
ls -la ~/.ssh/

echo ""
echo "### Application Support (важное) ###"
ls ~/Library/Application\ Support/ | grep -iE 'code|jetbrains|obsidian|iterm|kitty'

echo ""
echo "### Размеры директорий для бэкапа ###"
du -sh ~/dev/ 2>/dev/null
du -sh ~/dev/projects/ 2>/dev/null
du -sh ~/obsidian_vaults/ 2>/dev/null
du -sh ~/.config/ 2>/dev/null
du -sh ~/.local/share/ 2>/dev/null
```

---

## Настройка Restic + Backblaze B2

### Шаг 1: Создать Backblaze B2 bucket

1. Зарегистрироваться на backblaze.com
2. Создать B2 Bucket (private, encryption enabled)
3. Создать Application Key с доступом к bucket

### Шаг 2: Установить restic

```bash
brew install restic
```

### Шаг 3: Инициализировать репозиторий

```bash
# Экспортировать креды
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-application-key"

# Инициализировать репо (запомни пароль!)
restic -r b2:bucket-name:restic-repo init
```

### Шаг 4: Создать конфиг бэкапа

```bash
# ~/.config/restic/backup.conf

# Что бэкапить
~/dev
~/obsidian_vaults
~/.config
~/.local/share
~/.ssh
~/.gnupg
~/.gitconfig
~/Documents
```

```bash
# ~/.config/restic/exclude.conf

# Исключения
*.log
*.tmp
node_modules
.git
__pycache__
.venv
venv
.cache
Cache
Caches
*.pyc
.DS_Store
Thumbs.db
```

### Шаг 5: Скрипт бэкапа

```bash
#!/bin/bash
# ~/scripts/backup-to-b2.sh

set -e

# Загрузить креды
source ~/.config/restic/credentials.env

REPO="b2:your-bucket:restic-repo"

echo "Starting backup to Backblaze B2..."

restic -r "$REPO" backup \
    --files-from ~/.config/restic/backup.conf \
    --exclude-file ~/.config/restic/exclude.conf \
    --verbose

echo "Cleaning old snapshots (keep 7 daily, 4 weekly, 12 monthly)..."
restic -r "$REPO" forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune

echo "Backup complete!"
```

### Шаг 6: Автоматизация (launchd)

```xml
<!-- ~/Library/LaunchAgents/com.antifragile.backup.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.antifragile.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>$HOME/scripts/backup-to-b2.sh >> $HOME/.local/log/backup.log 2>&amp;1</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>12</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

```bash
# Активировать
launchctl load ~/Library/LaunchAgents/com.antifragile.backup.plist
```

---

## Бэкап на USB Flash

### Структура флешки

```
/Volumes/ANTIFRAGILE/
├── restic-repo/           # Зашифрованный restic репо
├── RECOVERY.md            # Инструкции по восстановлению
└── emergency/             # Аварийные файлы (если restic недоступен)
    ├── ssh-keys.tar.gpg   # SSH ключи зашифрованные GPG
    └── 2fa-codes.gpg      # Recovery коды
```

### Скрипт бэкапа на флешку

```bash
#!/bin/bash
# ~/scripts/backup-to-usb.sh

USB_PATH="/Volumes/ANTIFRAGILE"
REPO="$USB_PATH/restic-repo"

if [ ! -d "$USB_PATH" ]; then
    echo "USB drive not mounted at $USB_PATH"
    exit 1
fi

# Критичные данные через restic
restic -r "$REPO" backup \
    ~/dev/projects \
    ~/obsidian_vaults \
    ~/.ssh \
    ~/.gnupg \
    --exclude-file ~/.config/restic/exclude.conf

# Отдельно SSH ключи (двойная защита)
tar cf - ~/.ssh | gpg --symmetric --cipher-algo AES256 > "$USB_PATH/emergency/ssh-keys.tar.gpg"

echo "USB backup complete!"
```

---

## Разовый полный бэкап перед чистой установкой

### Чек-лист перед стиранием

```bash
#!/bin/bash
# ~/scripts/pre-wipe-checklist.sh

echo "=== PRE-WIPE VERIFICATION ==="

# 1. Проверить restic бэкапы
echo "Checking B2 backup..."
restic -r b2:bucket:repo snapshots

echo ""
echo "Checking USB backup..."
restic -r /Volumes/ANTIFRAGILE/restic-repo snapshots

# 2. Проверить dotfiles repo
echo ""
echo "Checking dotfiles repo..."
dotfiles status
dotfiles log --oneline -5

# 3. Проверить что SSH ключи забэкаплены
echo ""
echo "SSH keys in backup:"
restic -r b2:bucket:repo ls latest | grep '.ssh'

# 4. Список установленных приложений
echo ""
echo "Saving installed apps list..."
brew bundle dump --file=~/Brewfile
ls /Applications > ~/apps-list.txt

# 5. Размер бэкапа
echo ""
echo "Backup stats:"
restic -r b2:bucket:repo stats

echo ""
echo "=== MANUAL CHECKS ==="
echo "[ ] iCloud данные синхронизированы?"
echo "[ ] Пароль от restic записан в надёжном месте?"
echo "[ ] Backblaze креды сохранены?"
echo "[ ] 2FA recovery codes забэкаплены?"
echo "[ ] Keychain экспортирован?"
```

### Экспорт Homebrew пакетов

```bash
# Экспорт
brew bundle dump --file=~/Brewfile --force

# Восстановление на новой машине
brew bundle --file=~/Brewfile
```

### Экспорт macOS Keychain

```bash
# GUI: Keychain Access → File → Export Items
# Или через security CLI:
security export -k ~/Library/Keychains/login.keychain-db -o ~/keychain-backup.p12 -f pkcs12
```

---

## Чистая установка macOS

### Шаг 1: Создать загрузочную флешку

```bash
# Скачать macOS из App Store
# Затем:
sudo /Applications/Install\ macOS\ Sequoia.app/Contents/Resources/createinstallmedia \
    --volume /Volumes/USB_INSTALLER
```

### Шаг 2: Стереть Mac

1. Перезагрузить, держать Power (Apple Silicon) или Cmd+R (Intel)
2. Disk Utility → Стереть внутренний диск
3. Установить macOS

### Шаг 3: Первичная настройка

```bash
# 1. Установить Xcode Command Line Tools
xcode-select --install

# 2. Установить Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Установить restic
brew install restic

# 4. Восстановить из бэкапа
export B2_ACCOUNT_ID="..."
export B2_ACCOUNT_KEY="..."

# Восстановить SSH ключи первым делом
restic -r b2:bucket:repo restore latest --target ~/restore --include "/.ssh"
cp -r ~/restore/.ssh ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/*

# 5. Восстановить dotfiles
git clone --bare git@github.com:user/dotfiles.git ~/.dotfiles
alias dotfiles='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
dotfiles checkout

# 6. Восстановить Homebrew пакеты
brew bundle --file=~/Brewfile

# 7. Восстановить остальное
restic -r b2:bucket:repo restore latest --target ~/ --include "/dev" --include "/obsidian_vaults"
```

---

## Структура файлов проекта

```
~/dev/projects/antifragile_setup/
├── README.md
├── scripts/
│   ├── backup-to-b2.sh
│   ├── backup-to-usb.sh
│   ├── collect-dotfiles.sh
│   ├── pre-wipe-checklist.sh
│   └── restore-from-backup.sh
├── config/
│   ├── backup.conf
│   ├── exclude.conf
│   └── credentials.env.template
├── launchd/
│   └── com.antifragile.backup.plist
└── docs/
    ├── RECOVERY.md
    └── SETUP.md
```

---

## Ежедневный workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                     Automatic (launchd)                         │
│  12:00 → backup-to-b2.sh запускается автоматически             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Manual (раз в неделю)                       │
│  Подключить флешку → backup-to-usb.sh                          │
│  dotfiles add/commit/push для новых конфигов                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Безопасность

### Шифрование

| Компонент | Шифрование |
|-----------|------------|
| Restic repo | AES-256 (встроен) |
| Backblaze B2 | Server-side + restic |
| USB Flash | APFS encrypted |
| SSH ключи на флешке | GPG symmetric |

### Доступы

```
Restic пароль → Password manager + напечатан в сейфе
Backblaze креды → Password manager only
USB Flash пароль → Запомнен + напечатан в сейфе
GPG passphrase → Запомнен
```

### Правило 3-2-1

- **3** копии данных (laptop + B2 + USB)
- **2** разных типа носителей (SSD + облако)
- **1** копия offsite (Backblaze)

---

## Следующие шаги

1. [ ] Запустить `collect-dotfiles.sh` для инвентаризации
2. [ ] Создать Backblaze B2 аккаунт и bucket
3. [ ] Инициализировать restic репозитории
4. [ ] Настроить dotfiles bare git repo
5. [ ] Сделать первый полный бэкап
6. [ ] Настроить launchd для автоматизации
7. [ ] Протестировать восстановление на тестовой машине/VM
8. [ ] Подготовить загрузочную флешку с macOS
9. [ ] Выполнить pre-wipe-checklist
10. [ ] Чистая установка + восстановление

---

## FAQ

**Q: Что если забуду пароль от restic?**
A: Данные потеряны. Храни пароль в 3 местах: password manager, напечатанный в сейфе, у доверенного человека.

**Q: Сколько будет стоить Backblaze?**
A: При 50GB данных ≈ $0.30/месяц. При 500GB ≈ $3/месяц.

**Q: Как часто бэкапить?**
A: B2 — ежедневно автоматически. USB — еженедельно вручную.

**Q: Что если Backblaze закроется?**
A: Restic поддерживает много backends. Миграция: `restic copy` на новый backend.
