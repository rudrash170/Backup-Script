
#!/bin/bash

set -euo pipefail

# =========================
# Load Config from YAML (supports nested dicts & lists)
# =========================
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"

parse_yaml() {
    python3 - "$1" <<'PY'
import sys, yaml, shlex
cfg = yaml.safe_load(open(sys.argv[1])) or {}

def emit(k, v):
    if isinstance(v, bool):
        print(f"{k}={'true' if v else 'false'}")
    elif isinstance(v, (int, float)):
        print(f"{k}={v}")
    elif v is None:
        print(f"{k}=''")
    elif isinstance(v, str):
        print(f"{k}={shlex.quote(v)}")
    elif isinstance(v, list):
        items = ' '.join(shlex.quote(str(i)) for i in v)
        print(f"{k}=({items})")
    elif isinstance(v, dict):
        for sk, sv in v.items():
            emit(f"{k}_{sk}".upper(), sv)
    else:
        print(f"{k}={shlex.quote(str(v))}")

for key, val in cfg.items():
    emit(key.upper(), val)
PY
}

eval "$(parse_yaml "$CONFIG_FILE")"

# Backward compatibility variable mapping for EMAIL section (if present)
EMAIL_ENABLED=${EMAIL_ENABLED:-${EMAIL_ENABLED_TRUE:-false}}

PYTHON_BIN=${PYTHON:-python3}

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

# Prevent concurrent runs (best-effort, Linux only if flock present)
LOCK_FILE="/tmp/nas_backup.lock"
if command -v flock >/dev/null 2>&1; then
    exec 200>"$LOCK_FILE"
    flock -n 200 || { echo "Another backup process is running. Exiting."; exit 0; }
fi

if [ "$1" = "--run-backup" ]; then
    DATE=$(date +"%Y-%m-%d")
    mkdir -p "$LOCAL_TMP"
    log "INFO: Starting backup process."

    # --- File System Backup via Python (Incremental) ---
    SNAPSHOT_FILE="$LOCAL_TMP/backup.snar"
    FS_BACKUP_FILE="${LOCAL_TMP}/${SOURCE_DIR_NAME}-${DATE}.tar.gz"

    # Validate sources
    if [ -z "${SOURCE_DIR[*]:-}" ]; then
        log "ERROR: SOURCE_DIR not defined in config.yaml"; exit 1
    fi

    # Build arguments safely
    BACKUP_ARGS=("$PYTHON_BIN" "$SCRIPT_DIR/backup.py" --output "$FS_BACKUP_FILE" --snapshot "$SNAPSHOT_FILE")
    for s in "${SOURCE_DIR[@]}"; do
        BACKUP_ARGS+=(--source "$s")
    done
    for e in "${EXCLUDE[@]:-}"; do
        BACKUP_ARGS+=(--exclude "$e")
    done

    # Run backup
    if ! "${BACKUP_ARGS[@]}"; then
        log "ERROR: File system backup failed."; exit 1
    fi
    if [ $? -eq 0 ]; then
        log "SUCCESS: File system backup created: $FS_BACKUP_FILE (incremental)"
    else
        log "ERROR: File system backup failed."
        exit 1
    fi

    # --- Data Transfer ---
    mkdir -p "$NAS_PATH/fs"
    log INFO "Copying file system backup to NAS."

    cp "$FS_BACKUP_FILE" "$NAS_PATH/fs/"
    if [ $? -eq 0 ]; then
        log "SUCCESS: File system backup copied to $NAS_PATH/fs/$(basename "$FS_BACKUP_FILE")"
        # SHA256 checksum
        FS_SUM_LOCAL=$(sha256sum "$FS_BACKUP_FILE" | awk '{print $1}')
        FS_SUM_NAS=$(sha256sum "$NAS_PATH/fs/$(basename "$FS_BACKUP_FILE")" | awk '{print $1}')
        if [ "$FS_SUM_LOCAL" = "$FS_SUM_NAS" ]; then
            log "INFO: File system backup checksum verified."
        else
            log "ERROR: File system backup checksum mismatch!"
        fi
    else
        log "ERROR: Failed to copy file system backup to NAS."
        exit 1
    fi

    # --- Local Cleanup ---
    find "$LOCAL_TMP" -type f -name "*.gz" -delete
    OLD_FILES=$(find "$LOCAL_TMP" -type f -mtime +$RETENTION_DAYS)
    if [ -z "$OLD_FILES" ]; then
        log "INFO: No local files older than $RETENTION_DAYS days to clean up."
    else
        find "$LOCAL_TMP" -type f -mtime +$RETENTION_DAYS -exec rm {} \;
        log "INFO: Cleaned up local files older than $RETENTION_DAYS days."
    fi

    log "INFO: Backup process finished."

    # --- Email Alert (delegated entirely to Python script) ---
    if [ -f "$SCRIPT_DIR/send_email.py" ]; then
        if ! "$PYTHON_BIN" "$SCRIPT_DIR/send_email.py" --config "$CONFIG_FILE" --log "$LOG_FILE"; then
            log "WARN: Email script reported an error"
        fi
    else
        log "INFO: Email script not present; skipping notification"
    fi
    exit 0
fi

if [ "$1" = "--setup-cron" ]; then
    CRON_TIME="$SCHEDULE"
    SCRIPT_PATH="$(realpath "$0")"
    TMP_CRON=$(mktemp)
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH --run-backup" > "$TMP_CRON" || true
    echo "$CRON_TIME $SCRIPT_PATH --run-backup" >> "$TMP_CRON"
    crontab "$TMP_CRON" && rm -f "$TMP_CRON"
    log "INFO: Cron job ensured: $CRON_TIME $SCRIPT_PATH --run-backup"
    exit 0
fi

if [ "$1" = "--setup-task" ]; then
    # Parse hour and minute from SCHEDULE (assumes format "m h * * *")
        CRON_MIN=$(echo "$SCHEDULE" | awk '{print $1}')
        CRON_HOUR=$(echo "$SCHEDULE" | awk '{print $2}')
        ST_TIME=$(printf '%02d:%02d' "$CRON_HOUR" "$CRON_MIN")
        # Remove existing task if present
        schtasks /Query /TN BackupScript > /dev/null 2>&1 && schtasks /Delete /F /TN BackupScript >/dev/null 2>&1 || true
        schtasks /Create /SC DAILY /TN BackupScript /TR "pwsh -File '$(realpath "$0")' --run-backup" /ST "$ST_TIME" >/dev/null 2>&1 && \
            log "INFO: Windows Task Scheduler job ensured at $ST_TIME" || \
            log "ERROR: Failed to create scheduled task"
    exit 0
fi