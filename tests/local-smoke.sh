#!/usr/bin/env bash
#
# local-smoke.sh - startet das Portal lokal und prueft Health, Login und CRUD.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${VENV:-$ROOT/app/.venv}"
PORT="${PORT:-8091}"
TMP="$(mktemp -d)"
PID=""

msg() { printf '\033[34m[SMOKE]\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m[OK]\033[0m    %s\n' "$*"; }
die() { printf '\033[31m[FAIL]\033[0m  %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

[[ -x "$VENV/bin/python" ]] || die "venv fehlt: $VENV (zuerst tests/api.sh ausfuehren)"
[[ -f "$ROOT/web/dist/index.html" ]] || die "web/dist fehlt (cd web && npm ci && npm run build)"

HASH="$(PYTHONPATH="$ROOT/app" "$VENV/bin/python" -c \
  'from releasenotes.auth import hash_password; print(hash_password("smoke-pass"))')"

if ! "$VENV/bin/python" - "$PORT" <<'PY'
import socket
import sys

sock = socket.socket()
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
then
  OLD_PORT="$PORT"
  PORT="$("$VENV/bin/python" -c \
    'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
  msg "Port ${OLD_PORT} belegt, nutze freien Port ${PORT}"
fi

msg "Starte Uvicorn auf Port ${PORT}"
(
  cd "$ROOT/app"
  exec env \
    RELEASENOTES_DB="$TMP/smoke.db" \
    RELEASENOTES_STATIC="$ROOT/web/dist" \
    RELEASENOTES_SEED="$ROOT/data/seed.json" \
    RELEASENOTES_SECRET="smoke-secret" \
    RELEASENOTES_ADMIN_HASH="$HASH" \
    "$VENV/bin/uvicorn" releasenotes.main:app --host 127.0.0.1 --port "$PORT"
) > "$TMP/server.log" 2>&1 &
PID=$!

ready=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.5
done
[[ "$ready" == "1" ]] || { tail -n 40 "$TMP/server.log"; die "Server startet nicht"; }
ok "Health: $(curl -fsS "http://127.0.0.1:${PORT}/healthz")"

code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/")"
[[ "$code" == "200" ]] || die "Startseite liefert HTTP ${code}"
ok "SPA-Startseite: HTTP ${code}"

code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/admin")"
[[ "$code" == "200" ]] || die "Admin-Fallback liefert HTTP ${code}"
ok "SPA-Fallback /admin: HTTP ${code}"

before="$(curl -fsS "http://127.0.0.1:${PORT}/api/releases" | "$VENV/bin/python" -c 'import json,sys; print(len(json.load(sys.stdin)))')"
[[ "$before" == "3" ]] || die "Seed-Releases erwartet: 3, gefunden: ${before}"
ok "Oeffentliche Releases: ${before}"

code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/api/admin/releases")"
[[ "$code" == "401" ]] || die "Admin ohne Login liefert HTTP ${code} statt 401"
ok "Admin ohne Login: HTTP 401"

code="$(curl -s -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"falsch"}' \
  "http://127.0.0.1:${PORT}/api/login")"
[[ "$code" == "401" ]] || die "Falsches Login liefert HTTP ${code} statt 401"
ok "Falsches Login: HTTP 401"

curl -fsS -c "$TMP/cookies" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"smoke-pass"}' \
  "http://127.0.0.1:${PORT}/api/login" >/dev/null
ok "Login korrekt"

created="$(curl -fsS -b "$TMP/cookies" \
  -H 'Content-Type: application/json' \
  -d '{"version":"9.9.9","title":"Smoke Release","status":"beta","release_date":"2026-11-12","summary":"Test","body_md":"# Test","known_issues_md":"","downloads":[],"published":true}' \
  "http://127.0.0.1:${PORT}/api/admin/releases")"
NEW_ID="$(printf '%s' "$created" | "$VENV/bin/python" -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
ok "Release erstellt (ID ${NEW_ID})"

code="$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/cookies" \
  -H 'Content-Type: application/json' \
  -d '{"version":"9.9.9","release_date":"2026-11-12"}' \
  "http://127.0.0.1:${PORT}/api/admin/releases")"
[[ "$code" == "409" ]] || die "Doppelter Slug liefert HTTP ${code} statt 409"
ok "Doppelter Slug: HTTP 409"

curl -fsS -b "$TMP/cookies" -c "$TMP/cookies" -X POST "http://127.0.0.1:${PORT}/api/logout" >/dev/null
code="$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/cookies" "http://127.0.0.1:${PORT}/api/admin/releases")"
[[ "$code" == "401" ]] || die "Nach Logout liefert Admin HTTP ${code} statt 401"
ok "Nach Logout: HTTP 401"

curl -fsS -c "$TMP/cookies" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"smoke-pass"}' \
  "http://127.0.0.1:${PORT}/api/login" >/dev/null
code="$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/cookies" \
  -X DELETE "http://127.0.0.1:${PORT}/api/admin/releases/${NEW_ID}")"
[[ "$code" == "204" ]] || die "Loeschen liefert HTTP ${code} statt 204"
ok "Release geloescht: HTTP 204"

after="$(curl -fsS "http://127.0.0.1:${PORT}/api/releases" | "$VENV/bin/python" -c 'import json,sys; print(len(json.load(sys.stdin)))')"
[[ "$after" == "3" ]] || die "Release-Liste nach Loeschen: ${after} statt 3"
ok "Oeffentliche Releases nach Cleanup: ${after}"

echo
ok "Lokaler Smoke-Test bestanden."
