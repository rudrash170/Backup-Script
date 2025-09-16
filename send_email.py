#!/usr/bin/env python3
"""Send backup log via email using SMTP (LOGIN/STARTTLS)."""
import argparse, sys, smtplib, ssl, yaml, os
from email.message import EmailMessage

def parse_args():
    p = argparse.ArgumentParser(description="Send log file via email")
    p.add_argument('--config', help='Path to config.yaml (preferred)')
    p.add_argument('--to')
    p.add_argument('--from', dest='from_addr')
    p.add_argument('--smtp-server')
    p.add_argument('--smtp-port', type=int)
    p.add_argument('--user')
    p.add_argument('--pass', dest='password')
    p.add_argument('--log', required=True, help='Path to log file to send')
    return p.parse_args()

def load_config(path):
    if not path:
        return {}
    try:
        with open(path, 'r') as fh:
            return yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return {}
    except Exception as e:
        print(f"WARN: Failed to load config {path}: {e}", file=sys.stderr)
        return {}

def extract_email(cfg):
    email = cfg.get('EMAIL') or {k[len('EMAIL_'):]: v for k,v in cfg.items() if k.startswith('EMAIL_')}
    # Normalize keys to upper
    norm = {str(k).upper(): v for k,v in email.items()} if isinstance(email, dict) else {}
    return norm

def main():
    args = parse_args()
    cfg = load_config(args.config)
    email_cfg = extract_email(cfg)

    enabled = str(email_cfg.get('ENABLED', 'false')).lower() == 'true'
    # CLI overrides
    to = args.to or email_cfg.get('TO')
    from_addr = args.from_addr or email_cfg.get('FROM')
    server = args.smtp_server or email_cfg.get('SMTP_SERVER')
    port = args.smtp_port or int(email_cfg.get('SMTP_PORT') or 0)
    user = args.user or email_cfg.get('USER')
    password = args.password or email_cfg.get('PASS')

    if not enabled:
        # Silently exit if not enabled
        return
    missing = [n for n,v in [('TO',to),('FROM',from_addr),('SMTP_SERVER',server),('SMTP_PORT',port),('USER',user),('PASS',password)] if not v]
    if missing:
        print(f"Email not sent; missing fields: {', '.join(missing)}", file=sys.stderr)
        return

    try:
        with open(args.log, 'r', errors='replace') as fh:
            body = fh.read()[-100000:]
    except Exception as e:
        print(f"Could not read log file: {e}", file=sys.stderr)
        return

    msg = EmailMessage()
    hostname = os.uname().nodename if hasattr(os, 'uname') else os.environ.get('COMPUTERNAME','host')
    msg['Subject'] = f'Backup Report - {hostname}'
    msg['From'] = from_addr
    msg['To'] = to
    msg.set_content(body or 'Log file empty')

    try:
        context = ssl.create_default_context()
        with smtplib.SMTP(server, port, timeout=30) as s:
            s.starttls(context=context)
            s.login(user, password)
            s.send_message(msg)
    except Exception as e:
        print(f"Email send failed: {e}", file=sys.stderr)
        return

if __name__ == '__main__':
    main()
