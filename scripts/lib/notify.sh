#!/bin/bash
# notify.sh — Notification helpers for Antifragile backup system
# Source this file in other scripts

# ============================================================
# Configuration
# ============================================================

NOTIFY_APP_NAME="Antifragile Backup"
NOTIFY_SOUND_START="Submarine"
NOTIFY_SOUND_SUCCESS="Glass"
NOTIFY_SOUND_ERROR="Basso"
NOTIFY_ICON=""  # Can set to app icon path

# Progress file for inter-process communication
PROGRESS_FILE="/tmp/antifragile-progress.json"
STATUS_FILE="/tmp/antifragile-status"

# ============================================================
# Check for terminal-notifier
# ============================================================

has_terminal_notifier() {
    command -v terminal-notifier &> /dev/null
}

# ============================================================
# Basic notifications
# ============================================================

notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-}"
    local action_url="${4:-}"

    if has_terminal_notifier; then
        local args=(
            -title "$NOTIFY_APP_NAME"
            -subtitle "$title"
            -message "$message"
            -group "antifragile"
        )

        [ -n "$sound" ] && args+=(-sound "$sound")
        [ -n "$action_url" ] && args+=(-open "$action_url")

        terminal-notifier "${args[@]}" 2>/dev/null
    else
        # Fallback to osascript
        osascript -e "display notification \"$message\" with title \"$NOTIFY_APP_NAME\" subtitle \"$title\"${sound:+ sound name \"$sound\"}" 2>/dev/null || true
    fi
}

notify_start() {
    local backup_type="$1"  # "B2" or "USB"

    # Write status
    echo "running" > "$STATUS_FILE"
    echo "{\"status\":\"running\",\"type\":\"$backup_type\",\"started\":\"$(date -Iseconds)\",\"percent\":0}" > "$PROGRESS_FILE"

    if has_terminal_notifier; then
        terminal-notifier \
            -title "$NOTIFY_APP_NAME" \
            -subtitle "Backup Started" \
            -message "Starting $backup_type backup..." \
            -sound "$NOTIFY_SOUND_START" \
            -group "antifragile" \
            -execute "open -a Terminal '$HOME/.local/bin/backup-status'" \
            2>/dev/null
    else
        notify "Backup Started" "Starting $backup_type backup..." "$NOTIFY_SOUND_START"
    fi
}

notify_progress() {
    local percent="$1"
    local files_done="$2"
    local files_total="$3"
    local current_file="$4"
    local bytes_done="$5"
    local bytes_total="$6"

    # Update progress file
    cat > "$PROGRESS_FILE" << EOF
{
    "status": "running",
    "percent": $percent,
    "files_done": $files_done,
    "files_total": $files_total,
    "bytes_done": $bytes_done,
    "bytes_total": $bytes_total,
    "current_file": "$current_file",
    "updated": "$(date -Iseconds)"
}
EOF
}

notify_success() {
    local backup_type="$1"
    local duration="$2"
    local size="$3"

    echo "completed" > "$STATUS_FILE"
    echo "{\"status\":\"completed\",\"type\":\"$backup_type\",\"duration\":\"$duration\",\"size\":\"$size\"}" > "$PROGRESS_FILE"

    local message="$backup_type backup complete"
    [ -n "$duration" ] && message="$message in $duration"
    [ -n "$size" ] && message="$message ($size)"

    if has_terminal_notifier; then
        terminal-notifier \
            -title "$NOTIFY_APP_NAME" \
            -subtitle "Backup Complete" \
            -message "$message" \
            -sound "$NOTIFY_SOUND_SUCCESS" \
            -group "antifragile" \
            2>/dev/null
    else
        notify "Backup Complete" "$message" "$NOTIFY_SOUND_SUCCESS"
    fi
}

notify_error() {
    local backup_type="$1"
    local error_msg="$2"

    echo "failed" > "$STATUS_FILE"
    echo "{\"status\":\"failed\",\"type\":\"$backup_type\",\"error\":\"$error_msg\"}" > "$PROGRESS_FILE"

    local log_path="$HOME/.local/log/antifragile"

    if has_terminal_notifier; then
        terminal-notifier \
            -title "$NOTIFY_APP_NAME" \
            -subtitle "Backup Failed!" \
            -message "$backup_type: $error_msg" \
            -sound "$NOTIFY_SOUND_ERROR" \
            -group "antifragile" \
            -open "file://$log_path" \
            2>/dev/null
    else
        notify "Backup Failed!" "$backup_type: $error_msg" "$NOTIFY_SOUND_ERROR"
    fi
}

# ============================================================
# Progress bar helper
# ============================================================

progress_bar() {
    local percent="$1"
    local width="${2:-30}"

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"
}

# ============================================================
# Human readable sizes
# ============================================================

human_size() {
    local bytes="$1"

    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc)GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc)MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=1; $bytes / 1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

human_duration() {
    local seconds="$1"

    if [ "$seconds" -ge 3600 ]; then
        printf "%dh %dm %ds" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
    elif [ "$seconds" -ge 60 ]; then
        printf "%dm %ds" $((seconds/60)) $((seconds%60))
    else
        printf "%ds" "$seconds"
    fi
}
