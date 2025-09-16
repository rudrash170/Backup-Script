---

## 🏷️ Script Flags

`nas_backup.sh` supports the following flags:

- `--run-backup` : Runs the main backup process (file archiving, transfer, cleanup, email alert)
- `--setup-cron` : Adds a daily cron job at 2am to run the backup script on Linux
- `--setup-task` : Adds a daily Windows Task Scheduler job at 2am to run the backup script

**Usage Examples:**

Run the backup manually:
```bash
./nas_backup.sh --run-backup
```

Set up a daily cron job (Linux):
```bash
./nas_backup.sh --setup-cron
```

Set up a daily Task Scheduler job (Windows):
```bash
./nas_backup.sh --setup-task
```

# 🚀 Automated File Backup to NAS

>This project provides a robust, easy-to-use solution for daily automated backups of a file directory to a NAS (Network Attached Storage) share, with logging, integrity checks, incremental backups, and optional email alerts.

---

## 🌟 Features
- Incremental backups (tar snapshot)
- Multiple source directories in one archive
- Exclude patterns (passed to tar)
- NAS copy + SHA256 integrity verification
- Central config (`config.yaml`)
- Email alerts (all logic in Python helper)
- Idempotent cron / Task Scheduler setup
- Concurrency guard (lock file if `flock` available)
- Automatic cleanup of local temp archives
- Absolute path fallback when sources differ in parents

---

## 📦 Files
- `nas_backup.sh` — Main Bash script orchestrating the backup process
- `backup.py` — Python script to create a compressed archive of one or more source directories
- `config.yaml` — Configuration file for paths, retention, email, etc.
- `send_email.py` — Helper script to send the log via SMTP when email alerts are enabled

---

## 🔄 Backup Flow

```mermaid
graph TD
    A[Start: Scheduled or Manual Run] --> B[Load config.yaml]
    B --> C[Create Incremental Archive (backup.py)]
    C --> D[Copy Archive to NAS]
    D --> E[Verify SHA256 Checksum]
    E --> F[Log Actions]
    F --> G[Cleanup Old Local Backups]
    G --> H{Email Alerts?}
    H -- Yes --> I[Send Email]
    H -- No --> J[Finish]
    I --> J[Finish]
```

---

## 🚦 Usage
1. **Edit `config.yaml`**
    - Set `SOURCE_DIR` as a YAML list of directories you want to back up, e.g.:
       ```yaml
       SOURCE_DIR:
          - /var/www/site
          - /etc/nginx
       ```
   - Set `NAS_PATH` to your mounted NAS backup location
   - Adjust other settings as needed

2. **Make the script executable**
   ```bash
   chmod +x nas_backup.sh
   ```

3. **Test the backup manually**
   ```bash
   ./nas_backup.sh --run-backup
   ```

4. **Schedule with cron (Linux) or Task Scheduler (Windows)**
   - **Linux:** Add a line to your crontab (e.g., to run daily at 2am):
     ```bash
     0 2 * * * /path/to/nas_backup.sh
     ```
   - **Windows:** Use Task Scheduler to run the script at your chosen time

---

## 📧 Email Alerts
- Configure the `EMAIL` section in `config.yaml`.
- Bash only invokes `send_email.py`; all SMTP/auth logic lives in Python now.
- The log file content becomes the email body.
- Example config section:
   ```yaml
   EMAIL:
      ENABLED: true
      TO: you@example.com
      FROM: backup@example.com
      SMTP_SERVER: smtp.example.com
      SMTP_PORT: 587
      USER: smtpuser
      PASS: smtppassword
   ```

---

## 🛠️ Requirements
- Python 3
- Bash (Linux) or PowerShell (Windows)
- `tar`, `gzip`, `sha256sum` utilities
- NAS share must be mounted and writable
 - (Optional) `flock` for concurrency guard on Linux

---

## 📝 Notes
- The script only backs up files, not databases
- Old backup files in the local temp directory are deleted after the specified retention period
- For restoring, simply extract the `.tar.gz` file from your NAS backup location
 - If multiple source directories don't share the same parent, the archive will store absolute paths
 - Exclude patterns are passed directly to `tar --exclude` (globs supported)

---

## 📄 License
MIT
