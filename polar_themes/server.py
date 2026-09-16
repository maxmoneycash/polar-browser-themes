"""Loopback-only studio. Applying themes requires a per-process capability token.

The hosted studio has no write API. No browser automation, telemetry, or remote
assets are involved in editing a theme.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import secrets
from urllib.parse import urlsplit
from .theme import ASSETS, MAX_BYTES, ThemeError, apply_theme, decode_theme, config_dir, load_theme


def make_handler(token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def valid_host(self):
            return self.headers.get("Host") == "127.0.0.1:{}".format(self.server.server_port)

        def send(self, status, body, content_type="application/json; charset=utf-8"):
            if isinstance(body, dict):
                body = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if not self.valid_host():
                return self.send(403, {"error": "Invalid host"})
            path = urlsplit(self.path).path
            if path == "/api/status":
                from .native import doctor
                report = doctor()
                current = config_dir() / "current.json"
                try:
                    theme = load_theme(str(current)) if current.exists() else load_theme("midnight")
                    return self.send(200, {"local": True, "native": report["adapter_installed"], "theme": theme})
                except ThemeError as error:
                    return self.send(400, {"error": str(error)})
            relative = path.lstrip("/")
            if path in ("/", "/index.html"):
                file = ASSETS / "studio/index.html"
            elif relative in ("app.js", "style.css"):
                file = ASSETS / "studio" / relative
            elif relative.startswith(("themes/", "schema/")):
                file = (ASSETS / relative).resolve()
                if ASSETS.resolve() not in file.parents or file.suffix != ".json":
                    return self.send(404, {"error": "Not found"})
            else:
                return self.send(404, {"error": "Not found"})
            try:
                self.send(200, file.read_bytes(), mimetypes.guess_type(file.name)[0] or "application/octet-stream")
            except OSError:
                self.send(404, {"error": "Not found"})

        def do_POST(self):
            expected_origin = "http://127.0.0.1:{}".format(self.server.server_port)
            if not self.valid_host() or self.headers.get("Origin") != expected_origin:
                return self.send(403, {"error": "Invalid origin"})
            if not secrets.compare_digest(self.headers.get("X-Polar-Themes-Token", ""), token):
                return self.send(403, {"error": "Open the full local studio URL printed by the CLI"})
            if urlsplit(self.path).path != "/api/apply":
                return self.send(404, {"error": "Not found"})
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if size <= 0 or size > MAX_BYTES or self.headers.get("Transfer-Encoding"):
                    return self.send(413, {"error": "Theme must be between 1 byte and 32 KiB"})
                if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                    return self.send(415, {"error": "Expected application/json"})
                theme = decode_theme(self.rfile.read(size))
                apply_theme(theme)
                self.send(200, {"ok": True, "name": theme["name"]})
            except (ValueError, OSError) as error:
                self.send(400, {"error": str(error)})
    return Handler


def serve(port=0):
    token = secrets.token_urlsafe(32)
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(token))
    print("Polar Theme Studio", flush=True)
    print("http://127.0.0.1:{}/#token={}".format(server.server_port, token), flush=True)
    print("Open this URL in Polar. Ctrl+C stops the studio. No browser is launched automatically.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
