#!/usr/bin/env python3

from flask import Flask, g, render_template_string, send_from_directory, abort, request, redirect, url_for, session
import sqlite3
import os
from functools import wraps

DB_FILE = "connections.db"
CAP_DIR = "captures"
APP_SECRET = os.environ.get("DASH_SECRET") or "change-this-secret"  # change if exposé
PASSWORD = "Trh@ckn0n"  # mot de passe demandé (exact)
app = Flask(__name__)
app.secret_key = APP_SECRET

# ---- Templates ----
TEMPLATE_LOGIN = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Admin - Login</title>
  <style>
    body{background:#050607;color:#b6ffea;font-family: "Courier New", monospace;}
    .card{max-width:420px;margin:6% auto;padding:20px;border-radius:12px;
          background:linear-gradient(180deg, rgba(0,0,0,0.6), rgba(10,10,10,0.8));
          box-shadow:0 8px 30px rgba(0,0,0,0.6);border:1px solid rgba(0,255,170,0.08);}
    h1{color:#7ef0c2;text-align:center;letter-spacing:2px}
    input[type=password]{width:100%;padding:10px;margin-top:12px;border-radius:6px;border:1px solid #0fffc0;background:#0b0b0b;color:#b6ffea}
    button{width:100%;padding:10px;margin-top:12px;border-radius:6px;border:none;background:#00ff9b;color:#001;background:#00ffa0;cursor:pointer;font-weight:bold}
    .hint{font-size:12px;color:#9fffd8;margin-top:8px;text-align:center}
    .brand{font-size:12px;color:#00ffd1;text-align:center;margin-top:6px}
  </style>
</head>
<body>
  <div class="card">
    <h1>anonymous | dashboard</h1>
    <form method="post" action="{{ url_for('login') }}">
      <input name="password" type="password" placeholder="Mot de passe" autofocus required>
      <button type="submit">Connexion</button>
    </form>
    <div class="hint">Entrez le mot de passe pour accéder au dashboard.</div>
    <div class="brand">trhacknon • demo pédagogique</div>
    {% if error %}<p style="color:#ff7b7b;text-align:center">{{error}}</p>{% endif %}
  </div>
</body>
</html>
"""

TEMPLATE_INDEX = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>anonymous | connections</title>
  <style>
    body{background:#050607;color:#b6ffea;font-family: "Courier New", monospace;padding:18px}
    header{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}
    h1{color:#7ef0c2;margin:0}
    .logout{background:#ff4f7a;color:#050607;padding:8px 12px;border-radius:8px;text-decoration:none}
    table{width:100%;border-collapse:collapse;background:rgba(0,0,0,0.45);backdrop-filter:blur(4px)}
    th,td{padding:10px;border-bottom:1px solid rgba(0,255,170,0.06);font-size:14px}
    th{color:#00ffd1;text-align:left}
    tr:hover td{background:linear-gradient(90deg, rgba(0,255,170,0.03), rgba(0,255,170,0.01))}
    a{color:#9dfdd0;text-decoration:none}
    .id{font-size:12px;color:#9fffd8}
    .hex{font-family:monospace;font-size:12px;background:#081616;padding:8px;border-radius:6px;display:block;overflow:auto}
    .meta{font-size:13px;color:#bdfbe6}
    .footer{margin-top:12px;font-size:12px;color:#7ef0c2}
  </style>
</head>
<body>
  <header>
    <h1>anonymous | connections</h1>
    <div>
      <a class="logout" href="/logout">Logout</a>
    </div>
  </header>

  <table>
    <thead>
      <tr><th>ID</th><th>Time (UTC)</th><th>Source</th><th>Port</th><th>Bytes</th><th>Payload</th></tr>
    </thead>
    <tbody>
    {% for r in rows %}
      <tr>
        <td><div class="id">{{ r['id'] }}</div></td>
        <td>{{ r['timestamp'] }}</td>
        <td>{{ r['src_ip'] }}:{{ r['src_port'] }}</td>
        <td>{{ r['dst_port'] }}</td>
        <td>{{ r['bytes_received'] }}</td>
        <td>
          {% if r['filename'] %}
            <a href="/payload/{{ r['id'] }}">download</a> |
            <a href="/detail/{{ r['id'] }}">detail</a>
          {% else %}
            -
          {% endif %}
        </td>
      </tr>
    {% endfor %}
    </tbody>
  </table>

  <div class="footer">trhacknon • demo pédagogique — interface hacker style</div>
</body>
</html>
"""

TEMPLATE_DETAIL = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Detail {{row['id']}}</title>
  <style>
    body{background:#050607;color:#b6ffea;font-family: "Courier New", monospace;padding:18px}
    a{color:#9dfdd0}
    .hex{font-family:monospace;background:#081616;padding:12px;border-radius:8px;display:block;white-space:pre-wrap;word-break:break-all}
    .meta{margin-bottom:12px}
    .back{display:inline-block;padding:8px 12px;background:#00ffa0;color:#001;border-radius:8px;text-decoration:none}
  </style>
</head>
<body>
  <h2>Detail</h2>
  <div class="meta">
    <b>ID:</b> {{row['id']}}<br>
    <b>Timestamp:</b> {{row['timestamp']}}<br>
    <b>Source:</b> {{row['src_ip']}}:{{row['src_port']}}<br>
    <b>Dst port:</b> {{row['dst_port']}}<br>
    <b>Bytes:</b> {{row['bytes_received']}}<br>
    <b>File:</b> {% if row['filename'] %} <a href="/payload/{{row['id']}}">{{row['filename']}}</a> {% else %} - {% endif %}
  </div>

  <h3>Hex preview (first 1024 bytes)</h3>
  <div class="hex">{{ hex }}</div>

  <p><a class="back" href="/">Retour</a></p>
</body>
</html>
"""

# ---- Helpers ----
def get_db():
    db = getattr(g, "_db", None)
    if db is None:
        db = sqlite3.connect(DB_FILE)
        db.row_factory = sqlite3.Row
        g._db = db
    return db

@app.teardown_appcontext
def close_db(exc):
    db = getattr(g, "_db", None)
    if db is not None:
        db.close()

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        pw = request.form.get("password", "")
        if pw == PASSWORD:
            session["logged"] = True
            return redirect(url_for("index"))
        else:
            error = "Mot de passe incorrect."
    return render_template_string(TEMPLATE_LOGIN, error=error)

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/")
@login_required
def index():
    db = get_db()
    cur = db.execute("SELECT id, timestamp, src_ip, src_port, dst_port, bytes_received, filename FROM connections ORDER BY timestamp DESC LIMIT 200")
    rows = [dict(r) for r in cur.fetchall()]
    return render_template_string(TEMPLATE_INDEX, rows=rows)

@app.route("/detail/<id>")
@login_required
def detail(id):
    db = get_db()
    cur = db.execute("SELECT * FROM connections WHERE id = ?", (id,))
    row = cur.fetchone()
    if not row:
        abort(404)
    row = dict(row)
    hex_sample = ""
    if row.get("filename"):
        path = os.path.join(CAP_DIR, row["filename"])
        if os.path.exists(path):
            data = open(path, "rb").read(1024)
            hex_sample = data.hex()
    return render_template_string(TEMPLATE_DETAIL, row=row, hex=hex_sample)

@app.route("/payload/<id>")
@login_required
def payload(id):
    db = get_db()
    cur = db.execute("SELECT filename FROM connections WHERE id = ?", (id,))
    row = cur.fetchone()
    if not row or not row[0]:
        abort(404)
    fname = row[0]
    return send_from_directory(CAP_DIR, fname, as_attachment=True)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
