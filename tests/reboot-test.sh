#!/usr/bin/env bash
#
# reboot-test.sh - prueft die Installation auf einem Proxmox-Host und rebootet den CT.
# Muss als root auf dem Proxmox-Host ausgefuehrt werden.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTID=""
PORT=8080
OUT="$ROOT/docs/test-evidence.md"

msg() { printf '\033[34m[TEST]\033[0m  %s\n' "$*"; }
ok()  { printf '\033[32m[OK]\033[0m    %s\n' "$*"; }
die() { printf '\033[31m[FAIL]\033[0m  %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Reboot-Test fuer ReleaseNotes

Usage: bash tests/reboot-test.sh --ctid ID [--port N] [--out FILE]

  --ctid ID    Container-ID (Pflicht)
  --port N     Web-Port (Default: ${PORT})
  --out FILE   Evidenzdatei (Default: docs/test-evidence.md)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ctid) CTID="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unbekannte Option: $1";;
  esac
done

[[ "$(id -u)" == "0" ]] || die "Bitte als root auf dem Proxmox-Host ausfuehren"
command -v pct >/dev/null || die "pct nicht gefunden - kein Proxmox-VE-Host?"
[[ -n "$CTID" ]] || die "--ctid ist erforderlich"
pct config "$CTID" >/dev/null 2>&1 || die "CT ${CTID} existiert nicht"

HOSTNAME_CT="$(pct config "$CTID" | awk -F': ' '/^hostname:/{print $2}')"
case "${HOSTNAME_CT,,}" in
  nexfirewall|releasenotes) ;;
  *) die "CT ${CTID} hat Hostname '${HOSTNAME_CT}', erwartet 'NexFireWall'" ;;
esac

mkdir -p "$(dirname "$OUT")"
exec > >(tee -a "$OUT") 2>&1

echo
echo "## Proxmox-Reboot-Test $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo
echo "- Host: $(hostname)"
echo "- CT: ${CTID} (${HOSTNAME_CT})"
echo "- Port: ${PORT}"
echo

msg "Status vor dem Reboot"
[[ "$(pct status "$CTID" | awk '{print $2}')" == "running" ]] \
  || die "CT ${CTID} laeuft nicht"
pct exec "$CTID" -- systemctl is-active --quiet releasenotes \
  || die "Dienst releasenotes ist vor dem Reboot nicht aktiv"
BOOT_BEFORE="$(pct exec "$CTID" -- cat /proc/sys/kernel/random/boot_id)"
ok "Dienst aktiv, boot_id ${BOOT_BEFORE}"

msg "Healthcheck vor dem Reboot"
pct exec "$CTID" -- curl -fsS "http://127.0.0.1:${PORT}/healthz" \
  || die "Healthcheck vor dem Reboot fehlgeschlagen"
echo
ok "Web-UI antwortet vor dem Reboot"

msg "Container rebooten"
pct reboot "$CTID"
ok "Reboot ausgeloest"

BOOT_AFTER="$BOOT_BEFORE"
for _ in $(seq 1 90); do
  CURRENT="$(pct exec "$CTID" -- cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  if [[ -n "$CURRENT" && "$CURRENT" != "$BOOT_BEFORE" ]]; then
    BOOT_AFTER="$CURRENT"
    break
  fi
  sleep 2
done
[[ "$BOOT_AFTER" != "$BOOT_BEFORE" ]] || die "Container hat nicht neu gebootet"
ok "Neue boot_id ${BOOT_AFTER}"

msg "Auf Dienst und Web-UI warten"
ready=0
for _ in $(seq 1 90); do
  if pct exec "$CTID" -- curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "$ready" != "1" ]]; then
  echo "--- CT-Status ---"
  pct status "$CTID" || true
  echo "--- journalctl -u releasenotes ---"
  pct exec "$CTID" -- journalctl -u releasenotes -n 100 --no-pager || true
  echo "--- Install-Log ---"
  pct exec "$CTID" -- tail -n 100 /var/log/releasenotes-install.log || true
  die "Web-UI antwortet nach dem Reboot nicht"
fi
pct exec "$CTID" -- systemctl is-active --quiet releasenotes \
  || die "Dienst releasenotes ist nach dem Reboot nicht aktiv"
ok "Dienst aktiv, /healthz antwortet nach dem Reboot"

msg "Healthcheck-Antwort"
pct exec "$CTID" -- curl -fsS "http://127.0.0.1:${PORT}/healthz"
echo

msg "Letzte Journalzeilen"
pct exec "$CTID" -- journalctl -u releasenotes -n 20 --no-pager

echo
ok "Reboot-Test bestanden."
