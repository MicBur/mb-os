#!/usr/bin/env python3
"""MB-OS Clipboard Bridge — Webbasierte Zwischenablage für Host ↔ VM"""

import http.server
import json
import subprocess
import os
import html

PORT = 9876
DISPLAY = os.environ.get("DISPLAY", ":0")

HTML_PAGE = """<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>MB-OS Clipboard Bridge</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'Segoe UI', Inter, system-ui, sans-serif;
    background: linear-gradient(135deg, #0a0e1a 0%, #1a1e2e 50%, #0d1117 100%);
    color: #e6edf3;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 20px;
  }
  .container {
    width: 100%; max-width: 600px;
    background: rgba(22, 27, 34, 0.8);
    border: 1px solid rgba(48, 54, 61, 0.8);
    border-radius: 16px;
    padding: 32px;
    backdrop-filter: blur(20px);
    box-shadow: 0 8px 32px rgba(0,0,0,0.4);
  }
  h1 {
    text-align: center;
    font-size: 1.5rem;
    margin-bottom: 8px;
    background: linear-gradient(90deg, #20c2f8, #f820c2);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .subtitle { text-align: center; color: #8b949e; margin-bottom: 24px; font-size: 0.9rem; }
  .section { margin-bottom: 24px; }
  .section h2 { font-size: 1rem; color: #58a6ff; margin-bottom: 8px; }
  textarea {
    width: 100%; height: 120px;
    background: rgba(13, 17, 23, 0.8);
    border: 1px solid rgba(48, 54, 61, 0.6);
    border-radius: 8px;
    color: #e6edf3;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    font-size: 14px;
    padding: 12px;
    resize: vertical;
    outline: none;
    transition: border-color 0.2s;
  }
  textarea:focus { border-color: #20c2f8; }
  .btn-row { display: flex; gap: 8px; margin-top: 8px; }
  button {
    flex: 1;
    padding: 10px 16px;
    border: none;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }
  .btn-primary {
    background: linear-gradient(135deg, #20c2f8, #1a8cd8);
    color: white;
  }
  .btn-primary:hover { transform: translateY(-1px); box-shadow: 0 4px 12px rgba(32,194,248,0.3); }
  .btn-secondary {
    background: linear-gradient(135deg, #f820c2, #c818a0);
    color: white;
  }
  .btn-secondary:hover { transform: translateY(-1px); box-shadow: 0 4px 12px rgba(248,32,194,0.3); }
  .btn-copy {
    background: rgba(48, 54, 61, 0.8);
    color: #e6edf3;
    border: 1px solid rgba(48, 54, 61, 0.6);
  }
  .btn-copy:hover { background: rgba(58, 64, 71, 0.8); }
  .status {
    text-align: center;
    padding: 8px;
    border-radius: 6px;
    margin-top: 12px;
    font-size: 13px;
    display: none;
  }
  .status.success { display: block; background: rgba(46,160,67,0.2); color: #3fb950; }
  .status.error { display: block; background: rgba(248,81,73,0.2); color: #f85149; }
  .arrow { text-align: center; font-size: 2rem; color: #30363d; margin: 8px 0; }
</style>
</head>
<body>
<div class="container">
  <h1>📋 MB-OS Clipboard Bridge</h1>
  <p class="subtitle">Zwischenablage zwischen Host und VM synchronisieren</p>

  <div class="section">
    <h2>⬇️ Host → VM (Einfügen)</h2>
    <textarea id="pasteArea" placeholder="Text hier einfügen (Ctrl+V), dann 'An VM senden' klicken..."></textarea>
    <div class="btn-row">
      <button class="btn-primary" onclick="sendToVM()">📤 An VM senden</button>
    </div>
  </div>

  <div class="arrow">⇅</div>

  <div class="section">
    <h2>⬆️ VM → Host (Kopieren)</h2>
    <textarea id="copyArea" readonly placeholder="Klick 'Von VM holen' um die VM-Zwischenablage zu lesen..."></textarea>
    <div class="btn-row">
      <button class="btn-secondary" onclick="getFromVM()">📥 Von VM holen</button>
      <button class="btn-copy" onclick="copyToHost()">📋 In Host-Clipboard</button>
    </div>
  </div>

  <div id="status" class="status"></div>
</div>

<script>
function showStatus(msg, type) {
  const s = document.getElementById('status');
  s.textContent = msg;
  s.className = 'status ' + type;
  setTimeout(() => s.className = 'status', 3000);
}

async function sendToVM() {
  const text = document.getElementById('pasteArea').value;
  if (!text) { showStatus('Kein Text zum Senden!', 'error'); return; }
  try {
    const r = await fetch('/api/paste', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({text: text})
    });
    const d = await r.json();
    if (d.ok) showStatus('✅ Text an VM-Clipboard gesendet!', 'success');
    else showStatus('❌ Fehler: ' + d.error, 'error');
  } catch(e) { showStatus('❌ Verbindungsfehler', 'error'); }
}

async function getFromVM() {
  try {
    const r = await fetch('/api/copy');
    const d = await r.json();
    if (d.ok) {
      document.getElementById('copyArea').value = d.text;
      showStatus('✅ VM-Clipboard gelesen!', 'success');
    } else showStatus('❌ Fehler: ' + d.error, 'error');
  } catch(e) { showStatus('❌ Verbindungsfehler', 'error'); }
}

async function copyToHost() {
  const text = document.getElementById('copyArea').value;
  if (!text) { showStatus('Kein Text zum Kopieren!', 'error'); return; }
  try {
    await navigator.clipboard.writeText(text);
    showStatus('✅ In Host-Clipboard kopiert!', 'success');
  } catch(e) {
    // Fallback
    const ta = document.createElement('textarea');
    ta.value = text; document.body.appendChild(ta);
    ta.select(); document.execCommand('copy');
    document.body.removeChild(ta);
    showStatus('✅ In Host-Clipboard kopiert!', 'success');
  }
}
</script>
</body>
</html>"""


class ClipboardHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Quiet

    def do_GET(self):
        if self.path == '/api/copy':
            try:
                env = os.environ.copy()
                env["DISPLAY"] = DISPLAY
                result = subprocess.run(
                    ["xclip", "-selection", "clipboard", "-o"],
                    capture_output=True, text=True, timeout=3, env=env
                )
                text = result.stdout
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"ok": True, "text": text}).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"ok": False, "error": str(e)}).encode())
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode())

    def do_POST(self):
        if self.path == '/api/paste':
            try:
                length = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(length))
                text = data.get('text', '')
                env = os.environ.copy()
                env["DISPLAY"] = DISPLAY
                proc = subprocess.Popen(
                    ["xclip", "-selection", "clipboard"],
                    stdin=subprocess.PIPE, env=env
                )
                proc.communicate(input=text.encode())
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"ok": True}).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"ok": False, "error": str(e)}).encode())

if __name__ == '__main__':
    server = http.server.HTTPServer(('127.0.0.1', PORT), ClipboardHandler)
    print(f"Clipboard Bridge running on http://127.0.0.1:{PORT}")
    server.serve_forever()
