#!/usr/bin/env python3

import socket
import threading
import argparse
import os
import sqlite3
import datetime
import binascii
import uuid
import ssl
import requests

DB_FILE = "connections.db"
CAP_DIR = "captures"
MAX_READ = 10 * 1024 * 1024  # 10 MB max read per connection
SEND_FILE_LIMIT = 512 * 1024  # 512 KiB -> max size to try attach file to telegram

os.makedirs(CAP_DIR, exist_ok=True)

def init_db():
    conn = sqlite3.connect(DB_FILE, check_same_thread=False)
    c = conn.cursor()
    c.execute('''
      CREATE TABLE IF NOT EXISTS connections (
        id TEXT PRIMARY KEY,
        timestamp TEXT,
        src_ip TEXT,
        src_port INTEGER,
        dst_port INTEGER,
        bytes_received INTEGER,
        filename TEXT,
        summary TEXT
      )
    ''')
    conn.commit()
    return conn

db_conn = init_db()
db_lock = threading.Lock()

def save_record(record):
    with db_lock:
        c = db_conn.cursor()
        c.execute('''
          INSERT INTO connections (id, timestamp, src_ip, src_port, dst_port, bytes_received, filename, summary)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            record['id'],
            record['timestamp'],
            record['src_ip'],
            record['src_port'],
            record['dst_port'],
            record['bytes_received'],
            record['filename'],
            record['summary']
        ))
        db_conn.commit()

def hexdump(data, maxlen=512):
    if not data:
        return ''
    sample = data[:maxlen]
    return binascii.hexlify(sample).decode('ascii')

def send_telegram_message(token, chat_id, text):
    if not token or not chat_id:
        return False
    try:
        url = f"https://api.telegram.org/bot{token}/sendMessage"
        payload = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
        r = requests.post(url, data=payload, timeout=10)
        return r.ok
    except Exception as e:
        print("Telegram send message failed:", e)
        return False

def send_telegram_file(token, chat_id, filepath, caption=None):
    if not token or not chat_id:
        return False
    try:
        url = f"https://api.telegram.org/bot{token}/sendDocument"
        with open(filepath, "rb") as f:
            files = {"document": f}
            data = {"chat_id": chat_id}
            if caption:
                data["caption"] = caption
            r = requests.post(url, files=files, data=data, timeout=30)
        return r.ok
    except Exception as e:
        print("Telegram send file failed:", e)
        return False

def handle_client(conn, addr, dst_port, conn_id, tg_token=None, tg_chat=None):
    src_ip, src_port = addr
    ts = datetime.datetime.utcnow().isoformat() + "Z"
    print(f"[{ts}] new connection {conn_id} from {src_ip}:{src_port} -> port {dst_port}")
    chunks = []
    total = 0
    conn.settimeout(10.0)
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            chunks.append(data)
            total += len(data)
            if total >= MAX_READ:
                print(f"[{conn_id}] reached MAX_READ ({MAX_READ}), closing")
                break
    except socket.timeout:
        pass
    except Exception as e:
        print(f"[{conn_id}] error: {e}")
    finally:
        conn.close()

    payload = b"".join(chunks)
    filename = f"{conn_id}.bin"
    filepath = os.path.join(CAP_DIR, filename)
    try:
        with open(filepath, "wb") as f:
            f.write(payload)
    except Exception as e:
        print(f"[{conn_id}] failed to save payload: {e}")
        filename = None

    summary = hexdump(payload, maxlen=256)
    record = {
        "id": conn_id,
        "timestamp": ts,
        "src_ip": src_ip,
        "src_port": src_port,
        "dst_port": dst_port,
        "bytes_received": total,
        "filename": filename,
        "summary": summary
    }
    save_record(record)
    print(f"[{conn_id}] saved {total} bytes -> {filename}")

    # Telegram notification
    if tg_token and tg_chat:
        text = (
            f"📡 <b>Nouvelle connexion</b>\n"
            f"ID: <code>{conn_id}</code>\n"
            f"Source: <b>{src_ip}:{src_port}</b>\n"
            f"Port: {dst_port}\n"
            f"Bytes: {total}\n"
            f"Time (UTC): {ts}\n\n"
            f"Hex (preview): <code>{summary[:400]}</code>"
        )
        sent_msg = send_telegram_message(tg_token, tg_chat, text)
        # If small payload, try send as document
        if filename and total > 0 and total <= SEND_FILE_LIMIT:
            try:
                send_telegram_file(tg_token, tg_chat, filepath, caption=f"Payload {conn_id} ({total} bytes)")
            except Exception:
                pass

def start_listener(listen_host, listen_port, use_ssl=False, certfile=None, keyfile=None, tg_token=None, tg_chat=None):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((listen_host, listen_port))
    s.listen(50)
    print(f"[+] Listening on {listen_host}:{listen_port} (SSL={'yes' if use_ssl else 'no'})")

    while True:
        try:
            conn, addr = s.accept()
            if use_ssl:
                try:
                    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                    context.load_cert_chain(certfile=certfile, keyfile=keyfile)
                    conn = context.wrap_socket(conn, server_side=True)
                except Exception as e:
                    print(f"SSL handshake failed: {e}")
                    conn.close()
                    continue
            conn_id = uuid.uuid4().hex
            t = threading.Thread(target=handle_client, args=(conn, addr, listen_port, conn_id, tg_token, tg_chat), daemon=True)
            t.start()
        except KeyboardInterrupt:
            print("Shutting down listener.")
            s.close()
            break
        except Exception as e:
            print(f"Listener error: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Advanced TCP listener and logger with Telegram alerts")
    parser.add_argument("--host", default="0.0.0.0", help="Interface to bind (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=4545, help="Port to listen on")
    parser.add_argument("--ssl", action="store_true", help="Enable TLS (requires --cert and --key)")
    parser.add_argument("--cert", help="TLS cert file (PEM)")
    parser.add_argument("--key", help="TLS key file (PEM)")
    parser.add_argument("--tg-token", help="Telegram bot token (or set TELEGRAM_TOKEN env)")
    parser.add_argument("--tg-chat", help="Telegram chat_id (or set TELEGRAM_CHAT_ID env)")
    args = parser.parse_args()

    tg_token = args.tg_token or os.environ.get("TELEGRAM_TOKEN")
    tg_chat  = args.tg_chat  or os.environ.get("TELEGRAM_CHAT_ID")

    if args.ssl and (not args.cert or not args.key):
        parser.error("--ssl requires --cert and --key")

    start_listener(args.host, args.port, use_ssl=args.ssl, certfile=args.cert, keyfile=args.key, tg_token=tg_token, tg_chat=tg_chat)
