#!/usr/bin/env python3
"""
Local stand-in for Garmin's Connect Developer "Training API" OAuth 2.0 PKCE
flow and workout push endpoint, per the Phase 2 plan: the real Training API
payload schema is gated behind developer approval, so the app is built and
tested against this mock while that application is pending.

Endpoints (mirroring Garmin's real shape as closely as public docs allow):
  GET  /oauth2Confirm           -> consent page (Allow / Don't Allow)
  GET  /oauth2Confirm/approve   -> redirects to redirect_uri with ?code=&state=
  POST /di-oauth2-service/oauth/token -> exchanges code or refresh_token for tokens
  POST /workout                 -> pushes a workout payload (needs Bearer token)
  GET  /workouts                -> lists everything pushed so far (debug helper)

Run: python3 garmin_mock_server.py [port]  (defaults to 8899)
"""
import json
import secrets
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlencode, urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899

# In-memory "database" -- resets whenever the mock server restarts.
auth_codes = {}      # code -> {client_id, redirect_uri, code_challenge, state}
access_tokens = {}   # access_token -> {client_id, issued_at}
refresh_tokens = {}  # refresh_token -> {client_id}
pushed_workouts = [] # list of received workout payloads


def html_page(body: str) -> bytes:
    return f"""<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{{font-family:-apple-system,sans-serif;max-width:480px;margin:48px auto;padding:0 20px}}
button{{font-size:17px;padding:12px 20px;border-radius:10px;border:none;margin-right:8px}}
.allow{{background:#007aff;color:#fff}} .deny{{background:#eee}}</style>
</head><body>{body}</body></html>""".encode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[mock-garmin] {self.address_string()} - {fmt % args}")

    def _send_json(self, status: int, payload: dict):
        body = json.dumps(payload, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, status: int, body: bytes):
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _bearer_token(self):
        auth = self.headers.get("Authorization", "")
        return auth[7:] if auth.startswith("Bearer ") else None

    def do_GET(self):
        parsed = urlparse(self.path)
        qs = parse_qs(parsed.query)

        if parsed.path == "/oauth2Confirm":
            client_id = qs.get("client_id", [""])[0]
            redirect_uri = qs.get("redirect_uri", [""])[0]
            state = qs.get("state", [""])[0]
            code_challenge = qs.get("code_challenge", [""])[0]
            approve_qs = urlencode({
                "redirect_uri": redirect_uri, "state": state,
                "client_id": client_id, "code_challenge": code_challenge,
            })
            deny_qs = urlencode({"redirect_uri": redirect_uri, "state": state})
            body = html_page(f"""
                <h2>Connect to Garmin (mock)</h2>
                <p><b>{client_id or 'WorkoutImporter'}</b> would like to push structured
                workouts to your Garmin Connect account.</p>
                <a href="/oauth2Confirm/approve?{approve_qs}"><button class="allow">Allow</button></a>
                <a href="/oauth2Confirm/deny?{deny_qs}"><button class="deny">Don't Allow</button></a>
            """)
            self._send_html(200, body)
            return

        if parsed.path == "/oauth2Confirm/approve":
            redirect_uri = qs.get("redirect_uri", [""])[0]
            state = qs.get("state", [""])[0]
            client_id = qs.get("client_id", [""])[0]
            code_challenge = qs.get("code_challenge", [""])[0]
            code = secrets.token_urlsafe(16)
            auth_codes[code] = {
                "client_id": client_id, "redirect_uri": redirect_uri,
                "code_challenge": code_challenge, "state": state,
            }
            location = f"{redirect_uri}?{urlencode({'code': code, 'state': state})}"
            self.send_response(302)
            self.send_header("Location", location)
            self.end_headers()
            return

        if parsed.path == "/oauth2Confirm/deny":
            redirect_uri = qs.get("redirect_uri", [""])[0]
            state = qs.get("state", [""])[0]
            location = f"{redirect_uri}?{urlencode({'error': 'access_denied', 'state': state})}"
            self.send_response(302)
            self.send_header("Location", location)
            self.end_headers()
            return

        if parsed.path == "/workouts":
            self._send_json(200, {"count": len(pushed_workouts), "workouts": pushed_workouts})
            return

        self._send_json(404, {"error": "not_found", "path": parsed.path})

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""

        if parsed.path == "/di-oauth2-service/oauth/token":
            form = parse_qs(raw.decode())
            grant_type = form.get("grant_type", [""])[0]

            if grant_type == "authorization_code":
                code = form.get("code", [""])[0]
                entry = auth_codes.pop(code, None)
                if entry is None:
                    self._send_json(400, {"error": "invalid_grant", "error_description": "unknown or reused code"})
                    return
                # NOTE: a real PKCE server verifies code_verifier against
                # entry["code_challenge"] here (SHA256 + base64url). Skipped
                # in this mock for brevity -- the point is exercising the
                # client's request shape, not re-implementing PKCE crypto.
                access_token = secrets.token_urlsafe(24)
                refresh_token = secrets.token_urlsafe(24)
                access_tokens[access_token] = {"client_id": entry["client_id"], "issued_at": time.time()}
                refresh_tokens[refresh_token] = {"client_id": entry["client_id"]}
                self._send_json(200, {
                    "access_token": access_token, "refresh_token": refresh_token,
                    "token_type": "Bearer", "expires_in": 3600,
                })
                return

            if grant_type == "refresh_token":
                refresh_token = form.get("refresh_token", [""])[0]
                entry = refresh_tokens.get(refresh_token)
                if entry is None:
                    self._send_json(400, {"error": "invalid_grant", "error_description": "unknown refresh token"})
                    return
                access_token = secrets.token_urlsafe(24)
                access_tokens[access_token] = {"client_id": entry["client_id"], "issued_at": time.time()}
                self._send_json(200, {
                    "access_token": access_token, "refresh_token": refresh_token,
                    "token_type": "Bearer", "expires_in": 3600,
                })
                return

            self._send_json(400, {"error": "unsupported_grant_type"})
            return

        if parsed.path == "/workout":
            token = self._bearer_token()
            if token is None or token not in access_tokens:
                self._send_json(401, {"error": "unauthorized", "error_description": "missing or invalid access token"})
                return
            try:
                payload = json.loads(raw.decode())
            except json.JSONDecodeError:
                self._send_json(400, {"error": "invalid_json"})
                return
            if not payload.get("workoutName"):
                self._send_json(422, {"error": "validation_error", "message": "workoutName is required"})
                return
            workout_id = secrets.randbelow(10**9)
            record = {"workoutId": workout_id, **payload}
            pushed_workouts.append(record)
            self._send_json(201, {"workoutId": workout_id, "workoutName": payload.get("workoutName")})
            return

        self._send_json(404, {"error": "not_found", "path": parsed.path})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Mock Garmin Training API running on http://127.0.0.1:{PORT}")
    print(f"  Authorize: http://127.0.0.1:{PORT}/oauth2Confirm")
    print(f"  Token:     http://127.0.0.1:{PORT}/di-oauth2-service/oauth/token")
    print(f"  Push:      http://127.0.0.1:{PORT}/workout")
    print(f"  Debug:     http://127.0.0.1:{PORT}/workouts")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
