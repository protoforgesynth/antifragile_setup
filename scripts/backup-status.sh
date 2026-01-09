#!/bin/bash
# backup-status.sh — Live backup progress viewer
# Shows real-time progress with fancy progress bar

set -euo pipefail

PROGRESS_FILE="/tmp/antifragile-progress.json"
STATUS_FILE="/tmp/antifragile-status"
LOG_DIR="$HOME/.local/log/antifragile"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================
# Helpers
# ============================================================

progress_bar() {
    local percent="$1"
    local width=40

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    echo -n "["
    for ((i=0; i<filled; i++)); do echo -n "█"; done
    for ((i=0; i<empty; i++)); do echo -n "░"; done
    echo -n "]"
}

human_size() {
    local bytes="$1"
    if [ -z "$bytes" ] || [ "$bytes" = "null" ]; then
        echo "0B"
        return
    fi

    if [ "$bytes" -ge 1073741824 ]; then
        awk "BEGIN {printf \"%.1fGB\", $bytes / 1073741824}"
    elif [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.1fMB\", $bytes / 1048576}"
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1fKB\", $bytes / 1024}"
    else
        echo "${bytes}B"
    fi
}

clear_line() {
    echo -ne "\r\033[K"
}

# ============================================================
# Check if backup is running
# ============================================================

if [ ! -f "$STATUS_FILE" ]; then
    echo -e "${DIM}No backup in progress${NC}"
    echo ""
    echo "Recent backups:"
    ls -lt "$LOG_DIR"/backup_*.log 2>/dev/null | head -5 | while read line; do
        echo "  $line"
    done
    echo ""
    echo "To start a backup:"
    echo "  backup-to-b2   — Cloud backup"
    echo "  backup-to-usb  — USB backup"
    exit 0
fi

STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "unknown")

case "$STATUS" in
    "completed")
        echo -e "${GREEN}✓ Last backup completed successfully${NC}"
        if [ -f "$PROGRESS_FILE" ]; then
            RESULT=$(cat "$PROGRESS_FILE")
            TYPE=$(echo "$RESULT" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
            DURATION=$(echo "$RESULT" | grep -o '"duration":"[^"]*"' | cut -d'"' -f4)
            SIZE=$(echo "$RESULT" | grep -o '"size":"[^"]*"' | cut -d'"' -f4)
            echo -e "  Type: ${CYAN}$TYPE${NC}"
            [ -n "$DURATION" ] && echo -e "  Duration: ${CYAN}$DURATION${NC}"
            [ -n "$SIZE" ] && echo -e "  Size: ${CYAN}$SIZE${NC}"
        fi
        exit 0
        ;;
    "failed")
        echo -e "${RED}✗ Last backup failed${NC}"
        if [ -f "$PROGRESS_FILE" ]; then
            ERROR=$(cat "$PROGRESS_FILE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
            echo -e "  Error: $ERROR"
        fi
        echo ""
        echo "Check logs:"
        echo "  tail -100 $LOG_DIR/backup_b2_*.log | less"
        exit 1
        ;;
    "running")
        # Continue to live view
        ;;
    *)
        echo -e "${DIM}Status unknown${NC}"
        exit 0
        ;;
esac

# ============================================================
# Live progress view
# ============================================================

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           ${BOLD}Antifragile Backup Progress${NC}${BLUE}                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${DIM}Press Ctrl+C to exit (backup continues in background)${NC}"
echo ""

# Find the most recent log file
CURRENT_LOG=$(ls -t "$LOG_DIR"/backup_*.log 2>/dev/null | head -1)

if [ -z "$CURRENT_LOG" ]; then
    echo "Waiting for backup to start..."
fi

# Function to parse restic JSON progress
parse_progress() {
    local line="$1"

    # Check if it's a status line
    if echo "$line" | grep -q '"message_type":"status"'; then
        local percent=$(echo "$line" | grep -o '"percent_done":[0-9.]*' | cut -d':' -f2)
        local files_done=$(echo "$line" | grep -o '"files_done":[0-9]*' | cut -d':' -f2)
        local files_total=$(echo "$line" | grep -o '"total_files":[0-9]*' | cut -d':' -f2)
        local bytes_done=$(echo "$line" | grep -o '"bytes_done":[0-9]*' | cut -d':' -f2)
        local bytes_total=$(echo "$line" | grep -o '"total_bytes":[0-9]*' | cut -d':' -f2)
        local current=$(echo "$line" | grep -o '"current_files":\[[^]]*\]' | sed 's/.*\["\([^"]*\)".*/\1/' | head -1)

        if [ -n "$percent" ]; then
            local pct=$(awk "BEGIN {printf \"%.0f\", $percent * 100}")
            local bar=$(progress_bar "$pct")

            clear_line
            echo -ne "${BOLD}Progress:${NC} $bar ${GREEN}${pct}%${NC}"

            if [ -n "$files_done" ] && [ -n "$files_total" ]; then
                echo -ne "  ${DIM}Files: $files_done/$files_total${NC}"
            fi

            if [ -n "$bytes_done" ] && [ -n "$bytes_total" ]; then
                local done_h=$(human_size "$bytes_done")
                local total_h=$(human_size "$bytes_total")
                echo -ne "  ${DIM}($done_h / $total_h)${NC}"
            fi
        fi
    elif echo "$line" | grep -q '"message_type":"summary"'; then
        echo ""
        echo ""
        local files=$(echo "$line" | grep -o '"files_new":[0-9]*' | cut -d':' -f2)
        local size=$(echo "$line" | grep -o '"data_added":[0-9]*' | cut -d':' -f2)
        local duration=$(echo "$line" | grep -o '"total_duration":[0-9.]*' | cut -d':' -f2)

        echo -e "${GREEN}✓ Backup Complete!${NC}"
        [ -n "$files" ] && echo -e "  New files: ${CYAN}$files${NC}"
        [ -n "$size" ] && echo -e "  Data added: ${CYAN}$(human_size "$size")${NC}"
        [ -n "$duration" ] && echo -e "  Duration: ${CYAN}${duration}s${NC}"
    fi
}

# Monitor log file
LAST_SIZE=0
while true; do
    # Check if still running
    if [ -f "$STATUS_FILE" ]; then
        STATUS=$(cat "$STATUS_FILE" 2>/dev/null)
        if [ "$STATUS" != "running" ]; then
            echo ""
            echo ""
            if [ "$STATUS" = "completed" ]; then
                echo -e "${GREEN}✓ Backup completed!${NC}"
            else
                echo -e "${RED}✗ Backup failed${NC}"
            fi
            break
        fi
    fi

    # Find current log
    CURRENT_LOG=$(ls -t "$LOG_DIR"/backup_*.log 2>/dev/null | head -1)

    if [ -n "$CURRENT_LOG" ] && [ -f "$CURRENT_LOG" ]; then
        # Read new lines
        CURRENT_SIZE=$(wc -c < "$CURRENT_LOG")
        if [ "$CURRENT_SIZE" -gt "$LAST_SIZE" ]; then
            tail -c +$((LAST_SIZE + 1)) "$CURRENT_LOG" | while IFS= read -r line; do
                # Try to parse JSON progress
                if echo "$line" | grep -q '"message_type"'; then
                    parse_progress "$line"
                fi
            done
            LAST_SIZE=$CURRENT_SIZE
        fi
    fi

    sleep 0.5
done
