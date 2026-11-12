#!/usr/bin/env bash
#
# releasenotes-inner.sh - laeuft INNERHALB des LXC.
# Installiert das ReleaseNotes-Portal, richtet systemd ein und startet den Dienst.
#
set -euo pipefail
umask 077

APP_ID="releasenotes"
APP_DIR="/opt/releasenotes"
DATA_DIR="/var/lib/releasenotes"
CONF_DIR="/etc/releasenotes"
CONF_FILE="${CONF_DIR}/config.env"
VENV="${APP_DIR}/venv"
PORT="8080"
REPO_URL="https://github.com/HatchetMan111/FireNexWall-Proxmox"
REPO_REF="main"
SOURCE_DIR=""
ADMIN_PASSWORD_FILE=""
DEBUG=0
LOG_FILE="/var/log/releasenotes-install.log"

msg_info()  { echo -e "\e[34m[INFO]\e[0m  $*"; }
msg_ok()    { echo -e "\e[32m[OK]\e[0m    $*"; }
msg_warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
msg_error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }
die()       { msg_error "$*"; exit 1; }

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then
    rm -rf "$TMP_DIR"
  fi
  if [[ "${ADMIN_PASSWORD_FILE:-}" == "/root/.releasenotes-admin" && -f "$ADMIN_PASSWORD_FILE" ]]; then
    rm -f "$ADMIN_PASSWORD_FILE"
  fi
}
trap cleanup EXIT

on_error() {
  local code=$1 line=$2 cmd=$3
  trap - ERR
  {
    echo
    msg_error "Abbruch (Exit ${code}) in Zeile ${line}: ${cmd}"
    echo "--- Install-Log (letzte 80 Zeilen) ---"
    tail -n 80 "$LOG_FILE" 2>/dev/null || true
    echo "--- systemctl status ${APP_ID} ---"
    systemctl status "$APP_ID" --no-pager -l 2>&1 | tail -n 60 || true
    echo "--- journalctl -u ${APP_ID} ---"
    journalctl -u "$APP_ID" -n 80 --no-pager 2>&1 || true
    echo "--- Offene Ports ---"
    ss -tlnp 2>&1 | head -30 || true
    echo "--- Python-Version ---"
    python3 --version 2>&1 || true
    echo "--- DNS ---"
    cat /etc/resolv.conf 2>&1 || true
    ip route 2>&1 || true
    getent hosts deb.debian.org 2>&1 || true
    echo
    echo "Naechster Schritt:"
    echo "  pct enter <CT-ID>"
    echo "  bash /root/releasenotes-inner.sh --debug --port ${PORT} --source-dir ${SOURCE_DIR:-<repo>}"
  } >&2
  exit "$code"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

usage() {
  cat <<EOF
ReleaseNotes Container-Installer

Usage: bash releasenotes-inner.sh [OPTIONEN]

  --port N                  Web-Port (Default: ${PORT})
  --repo URL                Git-Repo (Default: ${REPO_URL})
  --ref REF                 Branch/Tag (Default: ${REPO_REF})
  --source-dir PATH         Lokales Quellverzeichnis statt git clone (Entwicklung)
  --admin-password-file P   Datei mit dem neuen Admin-Passwort
  --debug                   bash -x und erweiterte Diagnose
  -h, --help                Hilfe
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --repo) REPO_URL="$2"; shift 2;;
    --ref) REPO_REF="$2"; shift 2;;
    --source-dir) SOURCE_DIR="$2"; shift 2;;
    --admin-password-file) ADMIN_PASSWORD_FILE="$2"; shift 2;;
    --debug) DEBUG=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unbekannte Option: $1";;
  esac
done

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || ! (( PORT >= 1 && PORT <= 65535 )); then
  die "Ungueltiger Port: ${PORT}"
fi

touch "$LOG_FILE" 2>/dev/null || true
chmod 600 "$LOG_FILE" 2>/dev/null || true
if [[ "$DEBUG" == "1" ]]; then
  export PS4='+ $(date +%H:%M:%S) ${BASH_SOURCE##*/}:${LINENO}: '
  exec > >(tee -a "$LOG_FILE") 2>&1
  set -x
else
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

msg_info "ReleaseNotes Installation startet (Port ${PORT})"

[[ "$(id -u)" == "0" ]] || die "Bitte als root im Container ausfuehren"
[[ -f /etc/debian_version ]] || die "Debian wird erwartet"
rm -f /root/.releasenotes-generated-password

APT_OPTS=(
  -o Acquire::Retries=5
  -o Acquire::http::Timeout=30
  -o Acquire::https::Timeout=30
  -o Acquire::ForceIPv4=true
)
PACKAGES=(
  ca-certificates curl git openssl python3 python3-venv sqlite3 ufw
)

ensure_dns() {
  getent hosts deb.debian.org >/dev/null 2>&1 && return 0
  local gateway=""
  gateway="$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')" || true
  {
    if [[ -n "$gateway" ]]; then
      printf 'nameserver %s\n' "$gateway"
    fi
    printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n'
    printf 'options timeout:2 attempts:3\n'
  } > /etc/resolv.conf
  for _ in $(seq 1 10); do
    getent hosts deb.debian.org >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

apt_update() {
  apt-get update -qq "${APT_OPTS[@]}"
}

install_packages() {
  local attempt
  for attempt in 1 2 3; do
    if apt-get install -y -qq --no-install-recommends \
      "${APT_OPTS[@]}" "${PACKAGES[@]}"; then
      return 0
    fi
    msg_warn "apt-Versuch ${attempt}/3 fehlgeschlagen - DNS/Netz pruefen"
    ensure_dns || true
    sleep 5
    apt_update || true
  done
  return 1
}

msg_info "DNS pruefen"
ensure_dns || die "DNS im Container funktioniert nicht (deb.debian.org nicht aufloesbar)"
msg_ok "DNS funktioniert"

msg_info "Pakete installieren"
export DEBIAN_FRONTEND=noninteractive
update_ok=0
for attempt in 1 2 3; do
  if apt_update; then
    update_ok=1
    break
  fi
  msg_warn "apt-get update Versuch ${attempt}/3 fehlgeschlagen"
  ensure_dns || true
  sleep 3
done
[[ "$update_ok" == "1" ]] || die "apt-get update fehlgeschlagen - DNS/Netz im Container pruefen"
install_packages || die "Pakete konnten nicht installiert werden - DNS/Netz im Container pruefen"
msg_ok "Pakete installiert"

if ! id "$APP_ID" >/dev/null 2>&1; then
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_ID"
  msg_ok "Benutzer ${APP_ID} angelegt"
fi

mkdir -p "$APP_DIR" "$DATA_DIR" "$CONF_DIR"

if [[ -n "$SOURCE_DIR" ]]; then
  SRC="$SOURCE_DIR"
  [[ -d "$SRC/app" && -d "$SRC/web" ]] || die "Quellverzeichnis unvollstaendig: ${SRC}"
  msg_info "Lokale Quellen: ${SRC}"
else
  TMP_DIR="$(mktemp -d)"
  msg_info "Code laden von ${REPO_URL} (${REPO_REF})"
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "${TMP_DIR}/src" \
    || die "git clone fehlgeschlagen: ${REPO_URL} (${REPO_REF})"
  SRC="${TMP_DIR}/src"
fi

msg_info "Dateien nach ${APP_DIR} kopieren"
rm -rf "$APP_DIR/app" "$APP_DIR/web" "$APP_DIR/systemd" "$APP_DIR/data"
tar -C "$SRC" \
  --exclude='web/node_modules' \
  --exclude='app/.venv' \
  --exclude='app/__pycache__' \
  --exclude='app/.pytest_cache' \
  -cf - app web systemd data | tar -C "$APP_DIR" -xf -
[[ -f "$APP_DIR/app/releasenotes/main.py" ]] || die "App-Code fehlt nach dem Kopieren"
[[ -f "$APP_DIR/web/dist/index.html" ]] \
  || die "Frontend-Artefakt fehlt (web/dist/index.html) - lokal 'npm run build' ausfuehren und dist committen"
msg_ok "Code und Frontend-Artefakt kopiert"

msg_info "Python-Umgebung"
if [[ ! -x "${VENV}/bin/python" ]]; then
  python3 -m venv "$VENV"
fi
"${VENV}/bin/pip" install --quiet --upgrade pip wheel
"${VENV}/bin/pip" install --quiet -r "$APP_DIR/app/requirements.txt"
"${VENV}/bin/python" -c "import fastapi, uvicorn" \
  || die "Python-Abhaengigkeiten konnten nicht geladen werden"
msg_ok "Python-Abhaengigkeiten installiert"

OLD_SECRET=""
OLD_HASH_B64=""
if [[ -f "$CONF_FILE" ]]; then
  OLD_SECRET="$(awk '/^RELEASENOTES_SECRET=/{sub(/^RELEASENOTES_SECRET=/,""); print; exit}' "$CONF_FILE")"
  OLD_HASH_B64="$(awk '/^RELEASENOTES_ADMIN_HASH=/{sub(/^RELEASENOTES_ADMIN_HASH=/,""); print; exit}' "$CONF_FILE")"
fi

SECRET="${OLD_SECRET:-$(openssl rand -hex 32)}"
ADMIN_HASH_B64="$OLD_HASH_B64"

if [[ -n "$ADMIN_PASSWORD_FILE" ]]; then
  [[ -f "$ADMIN_PASSWORD_FILE" ]] || die "Admin-Passwort-Datei fehlt: ${ADMIN_PASSWORD_FILE}"
  ADMIN_HASH_RAW="$(PYTHONPATH="$APP_DIR/app" "${VENV}/bin/python" -c \
    'import sys; from releasenotes.auth import hash_password; print(hash_password(sys.stdin.read().rstrip("\n")))' \
    < "$ADMIN_PASSWORD_FILE")"
  [[ -n "$ADMIN_HASH_RAW" ]] || die "Admin-Passwort ist leer"
  ADMIN_HASH_B64="b64:$(printf '%s' "$ADMIN_HASH_RAW" | base64 -w0 | tr '+/' '-_' | tr -d '=')"
  unset ADMIN_HASH_RAW
  msg_ok "Admin-Passwort aktualisiert"
fi

if [[ -z "$ADMIN_HASH_B64" ]]; then
  { set +x; } 2>/dev/null
  GENERATED_PASSWORD="$(openssl rand -hex 12)"
  ADMIN_HASH_RAW="$(printf '%s' "$GENERATED_PASSWORD" | PYTHONPATH="$APP_DIR/app" "${VENV}/bin/python" -c \
    'import sys; from releasenotes.auth import hash_password; print(hash_password(sys.stdin.read()))')"
  ADMIN_HASH_B64="b64:$(printf '%s' "$ADMIN_HASH_RAW" | base64 -w0 | tr '+/' '-_' | tr -d '=')"
  printf '%s\n' "$GENERATED_PASSWORD" > /root/.releasenotes-generated-password
  chmod 600 /root/.releasenotes-generated-password
  msg_warn "Kein Admin-Passwort uebergeben. Generiert: /root/.releasenotes-generated-password"
  unset GENERATED_PASSWORD ADMIN_HASH_RAW
  if [[ "$DEBUG" == "1" ]]; then
    set -x
  fi
fi

msg_info "Konfiguration schreiben"
umask 077
cat > "$CONF_FILE" <<EOF
RELEASENOTES_PORT=${PORT}
RELEASENOTES_DB=${DATA_DIR}/releasenotes.db
RELEASENOTES_STATIC=${APP_DIR}/web/dist
RELEASENOTES_SEED=${APP_DIR}/data/seed.json
RELEASENOTES_SECRET=${SECRET}
RELEASENOTES_ADMIN_USER=admin
RELEASENOTES_ADMIN_HASH=${ADMIN_HASH_B64}
RELEASENOTES_COOKIE_SECURE=0
EOF
chmod 600 "$CONF_FILE"
chown root:root "$CONF_FILE"
unset SECRET ADMIN_HASH_B64
msg_ok "Konfiguration in ${CONF_FILE}"

install -d -m 0750 -o "$APP_ID" -g "$APP_ID" "$DATA_DIR"
chown -R "$APP_ID:$APP_ID" "$APP_DIR"

msg_info "Datenbank initialisieren"
runuser -u "$APP_ID" -- env \
  PYTHONPATH="$APP_DIR/app" \
  RELEASENOTES_DB="${DATA_DIR}/releasenotes.db" \
  RELEASENOTES_SEED="${APP_DIR}/data/seed.json" \
  "${VENV}/bin/python" -m releasenotes.seed
msg_ok "Datenbank bereit"

msg_info "systemd-Unit installieren"
sed -e "s|@APP_DIR@|${APP_DIR}|g" \
    -e "s|@APP_PORT@|${PORT}|g" \
    -e "s|@APP_USER@|${APP_ID}|g" \
    "$APP_DIR/systemd/releasenotes.service" > "/etc/systemd/system/${APP_ID}.service"
chmod 644 "/etc/systemd/system/${APP_ID}.service"
systemctl daemon-reload
systemctl enable "$APP_ID" >/dev/null 2>&1
systemctl restart "$APP_ID"
msg_ok "Dienst ${APP_ID}.service aktiviert"

msg_info "Firewall (LAN)"
if command -v ufw >/dev/null 2>&1; then
  ufw default deny incoming >/dev/null 2>&1 || true
  ufw default allow outgoing >/dev/null 2>&1 || true
  for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    ufw allow from "$net" to any port "$PORT" proto tcp >/dev/null 2>&1 || true
    ufw allow from "$net" to any port 22 proto tcp >/dev/null 2>&1 || true
  done
  if ufw --force enable >/dev/null 2>&1; then
    msg_ok "ufw: Port ${PORT} und SSH nur aus RFC1918"
  else
    msg_warn "ufw konnte nicht aktiviert werden (LXC ohne CAP_NET_ADMIN) - LAN-Grenze schuetzt"
  fi
else
  msg_warn "ufw nicht verfuegbar - LAN-Grenze schuetzt"
fi

msg_info "Healthcheck"
ok=0
for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 2
done
if [[ "$ok" != "1" ]]; then
  msg_error "Web-UI antwortet nicht auf http://127.0.0.1:${PORT}/healthz"
  systemctl status "$APP_ID" --no-pager -l 2>&1 | tail -n 60 || true
  journalctl -u "$APP_ID" -n 80 --no-pager 2>&1 || true
  die "Healthcheck fehlgeschlagen"
fi
systemctl is-active --quiet "$APP_ID" || die "Dienst ${APP_ID} laeuft nicht"
msg_ok "Dienst laeuft, /healthz antwortet"

echo
msg_ok "ReleaseNotes ist im Container bereit."
