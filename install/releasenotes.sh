#!/usr/bin/env bash
#
# releasenotes.sh - Proxmox VE Installer fuer das ReleaseNotes-Portal
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/FireNexWall-Proxmox/main/install/releasenotes.sh)"
#
set -euo pipefail
umask 077

APP="ReleaseNotes"
APP_ID="releasenotes"
APP_PORT=8080
CTID=""
CT_HOSTNAME="releasenotes"
CORES=2
RAM_MB=2048
SWAP_MB=512
DISK_GB=8
STORAGE=""
TEMPLATE_STORAGE="local"
BRIDGE="vmbr0"
REPO_URL="https://github.com/HatchetMan111/FireNexWall-Proxmox"
REPO_REF="main"
DNS_SERVERS=""
FORCE=0
ASSUME_YES=0
DEBUG=0
PASSWORD=""
ADMIN_PASSWORD=""
ADMIN_TMP=""
LOG_FILE="/var/log/releasenotes-install.log"
INNER_TMP=""
HOSTS_TMP=""
UPDATE_ONLY=0

msg_info()  { echo -e "\e[34m[INFO]\e[0m  $*"; }
msg_ok()    { echo -e "\e[32m[OK]\e[0m    $*"; }
msg_warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
msg_error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }
die()       { msg_error "$*"; exit 1; }

cleanup() {
  if [[ -n "${ADMIN_TMP:-}" && -f "${ADMIN_TMP:-}" ]]; then
    rm -f "$ADMIN_TMP"
  fi
  if [[ -n "${HOSTS_TMP:-}" && -f "${HOSTS_TMP:-}" ]]; then
    rm -f "$HOSTS_TMP"
  fi
}
trap cleanup EXIT

print_admin_password() {
  local tracing=0 pw=""
  [[ "$-" == *x* ]] && tracing=1
  set +x
  pw="$(cat "$ADMIN_TMP")"
  if { : > /dev/tty; } 2>/dev/null; then
    printf '  Admin-Passwort: %s\n' "$pw" > /dev/tty
  else
    (
      umask 077
      printf '%s\n' "$pw" > /root/releasenotes-admin-password
    )
    printf '  Admin-Passwort: siehe /root/releasenotes-admin-password\n'
  fi
  unset pw
  [[ "$tracing" == "1" ]] && set -x
  return 0
}

configure_ct_dns() {
  local gateway="" host_ns="" ns="" ns_list=""
  for _ in $(seq 1 30); do
    pct exec "$CTID" -- true >/dev/null 2>&1 && break
    sleep 1
  done
  gateway="$(pct exec "$CTID" -- ip route 2>/dev/null | awk '/^default/{print $3; exit}')" || true
  host_ns="$(awk '/^nameserver/ && $2 !~ /^(127\.|::1)$/ && !seen[$2]++ { print $2; n++; if (n==3) exit }' /etc/resolv.conf 2>/dev/null)" || true
  # shellcheck disable=SC2086
  for ns in ${DNS_SERVERS:-} ${gateway:-} ${host_ns:-} 1.1.1.1 9.9.9.9; do
    [[ -n "$ns" ]] || continue
    case " ${ns_list} " in *" ${ns} "*) continue;; esac
    ns_list="${ns_list:+${ns_list} }${ns}"
  done
  [[ -n "$ns_list" ]] || return 0
  if ! pct set "$CTID" --nameserver "$ns_list" >/dev/null 2>&1; then
    msg_warn "DNS konnte nicht in der CT-Konfiguration gespeichert werden"
  fi
  {
    for ns in $ns_list; do
      printf 'nameserver %s\n' "$ns"
    done
    printf 'options timeout:2 attempts:3\n'
  } | pct exec "$CTID" -- tee /etc/resolv.conf >/dev/null 2>&1 \
    || msg_warn "Konnte /etc/resolv.conf im Container nicht schreiben"
}

pin_install_hosts() {
  local host="" ips="" ip=""
  local pin_hosts=(
    deb.debian.org security.debian.org
    github.com pypi.org files.pythonhosted.org
  )
  HOSTS_TMP="$(mktemp)"
  {
    printf '# releasenotes installer: host pinning\n'
    for host in "${pin_hosts[@]}"; do
      ips="$(getent ahostsv4 "$host" 2>/dev/null \
        | awk '!seen[$1]++ { print $1; n++; if (n==4) exit }')" || true
      if [[ -z "$ips" ]]; then
        ips="$(pct exec "$CTID" -- getent ahostsv4 "$host" 2>/dev/null \
          | awk '!seen[$1]++ { print $1; n++; if (n==4) exit }')" || true
      fi
      while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        case "$ip" in 127.*) continue;; esac
        printf '%s %s\n' "$ip" "$host"
      done <<< "$ips"
    done
    printf '# end releasenotes installer: host pinning\n'
  } > "$HOSTS_TMP"
  if ! grep -Eq '^[0-9]' "$HOSTS_TMP"; then
    msg_warn "Keine A-Eintraege fuer Install-Hosts ermittelbar - nutze DNS"
    rm -f "$HOSTS_TMP"
    HOSTS_TMP=""
    return 0
  fi
  if ! pct push "$CTID" "$HOSTS_TMP" /tmp/releasenotes-hosts --perms 644 >/dev/null 2>&1; then
    msg_warn "Host-Pinning konnte nicht in den Container kopiert werden"
    rm -f "$HOSTS_TMP"
    HOSTS_TMP=""
    return 0
  fi
  pct exec "$CTID" -- sh -c '
    if grep -q "^# releasenotes installer: host pinning" /etc/hosts; then
      sed -i "/^# releasenotes installer: host pinning/,/^# end releasenotes installer: host pinning/d" /etc/hosts
    fi
    cat /tmp/releasenotes-hosts >> /etc/hosts
    rm -f /tmp/releasenotes-hosts
  ' || msg_warn "Host-Pinning konnte /etc/hosts nicht aktualisieren"
  rm -f "$HOSTS_TMP"
  HOSTS_TMP=""
}

on_error() {
  local code=$1 line=$2 cmd=$3
  trap - ERR
  {
    echo
    msg_error "Abbruch (Exit ${code}) in Zeile ${line}: ${cmd}"
    if [[ -n "${CTID:-}" ]] && pct status "$CTID" >/dev/null 2>&1; then
      echo "--- Container-Status ---"
      pct status "$CTID" 2>&1 || true
      echo "--- CT-Konfiguration ---"
      pct config "$CTID" 2>&1 | head -n 40 || true
      echo "--- Container-Install-Log (letzte 80 Zeilen) ---"
      pct exec "$CTID" -- tail -n 80 /var/log/releasenotes-install.log 2>&1 || true
      echo "--- journalctl -u ${APP_ID} ---"
      pct exec "$CTID" -- journalctl -u "$APP_ID" -n 80 --no-pager 2>&1 || true
      echo "--- Ports im Container ---"
      pct exec "$CTID" -- ss -tlnp 2>&1 | head -30 || true
      echo "--- DNS im Container ---"
      pct exec "$CTID" -- cat /etc/resolv.conf 2>&1 || true
      pct exec "$CTID" -- ip route 2>&1 || true
      pct exec "$CTID" -- getent hosts deb.debian.org 2>&1 || true
    fi
    echo "--- Host-Log: ${LOG_FILE} ---"
    tail -n 80 "$LOG_FILE" 2>/dev/null || true
    echo
    echo "Naechster Schritt:"
    echo "  pct enter ${CTID:-<ID>}"
    echo "  bash /root/releasenotes-inner.sh --debug --port ${APP_PORT}"
    echo "oder Installer erneut mit --debug starten."
  } >&2
  exit "$code"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

usage() {
  cat <<EOF
${APP} - Proxmox VE Installer

Usage: bash releasenotes.sh [OPTIONEN]

  --ctid ID                CT-ID (Default: naechste freie)
  --hostname NAME          Container-Hostname (Default: ${CT_HOSTNAME})
  --cores N                vCPUs (Default: ${CORES})
  --ram MB                 RAM in MiB (Default: ${RAM_MB})
  --disk GB                Disk in GiB (Default: ${DISK_GB})
  --storage NAME           Storage fuer die Disk (Default: automatisch)
  --template-storage NAME  Storage fuer das Template (Default: ${TEMPLATE_STORAGE})
  --bridge NAME            Linux-Bridge (Default: ${BRIDGE})
  --port N                 Web-Port (Default: ${APP_PORT})
  --admin-password PW      Admin-Passwort setzen (Default: zufaellig bei Erstinstallation)
  --repo URL               Git-Repo (Default: ${REPO_URL})
  --ref REF                Branch/Tag (Default: ${REPO_REF})
  --nameserver "NS ..."    DNS-Server im Container (Default: Gateway + Host-DNS + 1.1.1.1/9.9.9.9)
  --force                  Fremden Container mit dieser ID entfernen
  --yes                    nicht-interaktiv, Defaults verwenden
  --debug                  bash -x + erweiterte Diagnose
  -h, --help               Hilfe
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ctid) CTID="$2"; shift 2;;
    --hostname) CT_HOSTNAME="$2"; shift 2;;
    --cores) CORES="$2"; shift 2;;
    --ram) RAM_MB="$2"; shift 2;;
    --disk) DISK_GB="$2"; shift 2;;
    --storage) STORAGE="$2"; shift 2;;
    --template-storage) TEMPLATE_STORAGE="$2"; shift 2;;
    --bridge) BRIDGE="$2"; shift 2;;
    --port) APP_PORT="$2"; shift 2;;
    --admin-password) ADMIN_PASSWORD="$2"; shift 2;;
    --repo) REPO_URL="$2"; shift 2;;
    --ref) REPO_REF="$2"; shift 2;;
    --nameserver) DNS_SERVERS="$2"; shift 2;;
    --force) FORCE=1; shift;;
    --yes) ASSUME_YES=1; shift;;
    --debug) DEBUG=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unbekannte Option: $1";;
  esac
done

if [[ -n "$CTID" ]] && ! [[ "$CTID" =~ ^[0-9]+$ ]]; then
  die "Ungueltige CT-ID: ${CTID}"
fi
if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || ! (( APP_PORT >= 1 && APP_PORT <= 65535 )); then
  die "Ungueltiger Port: ${APP_PORT}"
fi
if ! [[ "$CORES" =~ ^[0-9]+$ ]] || ! (( CORES >= 1 )); then
  die "Ungueltige vCPU-Anzahl: ${CORES}"
fi
if ! [[ "$RAM_MB" =~ ^[0-9]+$ ]] || ! (( RAM_MB >= 512 )); then
  die "Ungueltiger RAM: ${RAM_MB}"
fi
if ! [[ "$DISK_GB" =~ ^[0-9]+$ ]] || ! (( DISK_GB >= 4 )); then
  die "Ungueltige Disk: ${DISK_GB}"
fi
if ! [[ "$CT_HOSTNAME" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
  die "Ungueltiger Hostname: ${CT_HOSTNAME}"
fi
if [[ -n "$ADMIN_PASSWORD" && "$ADMIN_PASSWORD" == *$'\n'* ]]; then
  die "Admin-Passwort darf keinen Zeilenumbruch enthalten"
fi

touch "$LOG_FILE" 2>/dev/null || true
chmod 600 "$LOG_FILE" 2>/dev/null || true
if [[ "$DEBUG" == "1" ]]; then
  export PS4='+ $(date +%H:%M:%S) ${0##*/}:${LINENO}: '
  exec > >(tee -a "$LOG_FILE") 2>&1
  set -x
else
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

msg_info "${APP} Installer"

[[ "$(id -u)" == "0" ]] || die "Bitte als root auf dem Proxmox-Host ausfuehren."
command -v pct >/dev/null || die "pct nicht gefunden - kein Proxmox-VE-Host?"
command -v pveam >/dev/null || die "pveam nicht gefunden"
command -v pvesh >/dev/null || die "pvesh nicht gefunden"
command -v pvesm >/dev/null || die "pvesm nicht gefunden"
command -v openssl >/dev/null || die "openssl nicht gefunden"
[[ -d /etc/pve ]] || die "/etc/pve fehlt - kein Proxmox-VE-Host?"

msg_info "Internet pruefen"
curl -fsS --max-time 10 -o /dev/null https://raw.githubusercontent.com \
  || msg_warn "raw.githubusercontent.com nicht erreichbar - Repo-Download koennte scheitern"

if [[ -z "$CTID" ]]; then
  CTID="$(pct list 2>/dev/null | awk 'NR>1 {print $1}' | while read -r id; do
    existing="$(pct config "$id" 2>/dev/null | awk -F': ' '/^hostname:/{print $2}')"
    if [[ "$existing" == "$CT_HOSTNAME" ]]; then
      printf '%s\n' "$id"
      break
    fi
  done)"
  if [[ -n "$CTID" ]]; then
    msg_info "Bestehender CT ${CTID} (${CT_HOSTNAME}) wird aktualisiert"
  else
    CTID="$(pvesh get /cluster/nextid 2>/dev/null | tr -d '"' | tr -d '[:space:]')"
    [[ "$CTID" =~ ^[0-9]+$ ]] || die "Konnte keine freie CT-ID ermitteln"
  fi
fi
msg_ok "CT-ID: ${CTID}"

EXISTING_HOST=""
if pct config "$CTID" >/dev/null 2>&1; then
  EXISTING_HOST="$(pct config "$CTID" | awk -F': ' '/^hostname:/{print $2}')"
  if [[ "$EXISTING_HOST" == "$CT_HOSTNAME" ]]; then
    msg_warn "CT ${CTID} (${CT_HOSTNAME}) existiert - Update-Modus"
    UPDATE_ONLY=1
    if [[ "$(pct status "$CTID" | awk '{print $2}')" != "running" ]]; then
      msg_info "Container starten"
      pct start "$CTID"
      for _ in $(seq 1 30); do
        [[ "$(pct status "$CTID" | awk '{print $2}')" == "running" ]] && break
        sleep 1
      done
    fi
  else
    if [[ "$FORCE" == "1" ]]; then
      msg_warn "CT ${CTID} (${EXISTING_HOST}) wird auf Wunsch (--force) entfernt"
      pct stop "$CTID" 2>/dev/null || true
      pct destroy "$CTID" --purge
      UPDATE_ONLY=0
    else
      die "CT ${CTID} existiert bereits mit Hostname '${EXISTING_HOST}'. Andere ID waehlen oder --force."
    fi
  fi
fi

if [[ -n "$ADMIN_PASSWORD" ]]; then
  ADMIN_TMP="$(mktemp)"
  chmod 600 "$ADMIN_TMP"
  { set +x; } 2>/dev/null
  printf '%s' "$ADMIN_PASSWORD" > "$ADMIN_TMP"
  unset ADMIN_PASSWORD
elif [[ "$UPDATE_ONLY" == "0" ]]; then
  ADMIN_TMP="$(mktemp)"
  chmod 600 "$ADMIN_TMP"
  openssl rand -hex 16 > "$ADMIN_TMP"
fi

if [[ "$ASSUME_YES" != "1" && -t 0 ]] && command -v whiptail >/dev/null 2>&1; then
  if ! whiptail --title "Ressourcen" --yesno \
    "CT ${CTID}: ${CORES} vCPU, ${RAM_MB} MB RAM, ${DISK_GB} GB Disk, Port ${APP_PORT}.\n\nFortfahren?" \
    12 70; then
    die "Vom Benutzer abgebrochen"
  fi
fi

if [[ "$UPDATE_ONLY" == "0" ]]; then
  msg_info "Template suchen"
  pveam update >/dev/null 2>&1 || true
  AVAILABLE_TEMPLATES="$(pveam available --section system)"
  TEMPLATE="$(awk '/debian-12-standard/{print $2; exit}' <<<"$AVAILABLE_TEMPLATES")"
  [[ -n "$TEMPLATE" ]] || die "Kein debian-12-standard Template verfuegbar"
  TEMPLATE_LIST="$(pveam list "$TEMPLATE_STORAGE")"
  if ! grep -Fq "$TEMPLATE" <<<"$TEMPLATE_LIST"; then
    msg_info "Template herunterladen: ${TEMPLATE}"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
    TEMPLATE_LIST="$(pveam list "$TEMPLATE_STORAGE")"
  fi
  TEMPLATE_PATH="$(awk -v t="$TEMPLATE" 'index($0,t){print $1; exit}' <<<"$TEMPLATE_LIST")"
  if [[ -z "$TEMPLATE_PATH" ]]; then
    TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
  fi
  msg_ok "Template: ${TEMPLATE_PATH}"

  if [[ -z "$STORAGE" ]]; then
    STORAGE="$(pvesm status --content rootdir | awk 'NR>1 && $3=="active"{print $1; exit}')"
  fi
  [[ -n "$STORAGE" ]] || die "Kein Storage mit content rootdir gefunden"
  msg_ok "Storage: ${STORAGE}"

  [[ -n "$PASSWORD" ]] || PASSWORD="$(openssl rand -hex 12)"

  msg_info "Container ${CTID} erstellen"
  if [[ "$DEBUG" == "1" ]]; then
    set +x
  fi
  pct create "$CTID" "$TEMPLATE_PATH" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CORES" \
    --memory "$RAM_MB" \
    --swap "$SWAP_MB" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    --unprivileged 1 \
    --onboot 1 \
    --ostype debian \
    --password "$PASSWORD" \
    --description "${APP} - lokales Release-Notes-Portal"
  if [[ "$DEBUG" == "1" ]]; then
    set -x
  fi
  pct start "$CTID"
  msg_ok "Container erstellt und gestartet"
else
  CT_STATUS="$(pct status "$CTID" | awk '{print $2}')"
  [[ "$CT_STATUS" == "running" ]] || pct start "$CTID"
  pct set "$CTID" --onboot 1 >/dev/null 2>&1 || true
fi

CT_CONFIG="$(pct config "$CTID")"
if ! grep -q '^onboot: 1' <<<"$CT_CONFIG"; then
  pct set "$CTID" --onboot 1 >/dev/null
fi

msg_info "DNS im Container konfigurieren"
configure_ct_dns

msg_info "Install-Hosts im Container pinnen"
pin_install_hosts

msg_info "Auf Netzwerk und DNS im Container warten"
ready=0
for _ in $(seq 1 120); do
  if pct exec "$CTID" -- getent hosts deb.debian.org >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != "1" ]]; then
  msg_error "DNS-Diagnose:"
  pct exec "$CTID" -- cat /etc/resolv.conf 2>&1 || true
  pct exec "$CTID" -- ip route 2>&1 || true
  die "Container hat nach 120s kein DNS/Netz. Ggf. --nameserver '1.1.1.1 9.9.9.9' setzen."
fi

msg_info "Inner-Installer uebertragen"
LOCAL_INNER="$(dirname -- "${BASH_SOURCE[0]:-}")/releasenotes-inner.sh"
if [[ -f "$LOCAL_INNER" ]]; then
  INNER_TMP="$LOCAL_INNER"
else
  INNER_TMP="$(mktemp)"
  RAW_BASE="${REPO_URL/github.com/raw.githubusercontent.com}"
  curl -fsSL "${RAW_BASE}/${REPO_REF}/install/releasenotes-inner.sh" -o "$INNER_TMP" \
    || die "Inner-Installer konnte nicht geladen werden"
fi
pct push "$CTID" "$INNER_TMP" /root/releasenotes-inner.sh --perms 700
if [[ "$INNER_TMP" != "$LOCAL_INNER" ]]; then
  rm -f "$INNER_TMP"
fi

INNER_ARGS=()
if [[ -n "$ADMIN_TMP" && -f "$ADMIN_TMP" ]]; then
  pct push "$CTID" "$ADMIN_TMP" /root/.releasenotes-admin --perms 600
  INNER_ARGS+=(--admin-password-file /root/.releasenotes-admin)
fi
if [[ "$DEBUG" == "1" ]]; then
  INNER_ARGS+=(--debug)
fi

msg_info "Installation im Container (kann einige Minuten dauern)"
pct exec "$CTID" -- bash /root/releasenotes-inner.sh \
  --port "$APP_PORT" --repo "$REPO_URL" --ref "$REPO_REF" \
  ${INNER_ARGS[@]+"${INNER_ARGS[@]}"}

msg_info "Verifikation vom Host"
ok=0
for _ in $(seq 1 60); do
  if pct exec "$CTID" -- curl -fsS "http://127.0.0.1:${APP_PORT}/healthz" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || die "Healthcheck im Container fehlgeschlagen"
pct exec "$CTID" -- systemctl is-active --quiet "$APP_ID" || die "Dienst nicht aktiv"
msg_ok "Dienst aktiv, /healthz antwortet"

CT_IP="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$CT_IP" ]] || CT_IP="<IP ermitteln mit: pct exec ${CTID} -- hostname -I>"

cat <<EOF

  ${APP} ist installiert.

  Web-UI:      http://${CT_IP}:${APP_PORT}
  Admin:       http://${CT_IP}:${APP_PORT}/admin
  Benutzer:    admin
EOF

if [[ -n "$ADMIN_TMP" && -f "$ADMIN_TMP" ]]; then
  print_admin_password
elif pct exec "$CTID" -- test -f /root/.releasenotes-generated-password; then
  printf '  Admin-Passwort: neu erzeugt, siehe /root/.releasenotes-generated-password im CT\n'
else
  printf '  Admin-Passwort: unveraendert\n'
fi

cat <<EOF

  CT-ID:       ${CTID}
  Hostname:    ${CT_HOSTNAME}
  root-PW:     ${PASSWORD:-unveraendert (Update)}

  Update:      bash -c "\$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/FireNexWall-Proxmox/main/install/releasenotes.sh)" -- --ctid ${CTID}
  Logs:        pct exec ${CTID} -- journalctl -u ${APP_ID} -f
  Shell:       pct enter ${CTID}
  Entfernen:   pct stop ${CTID} && pct destroy ${CTID} --purge

EOF
