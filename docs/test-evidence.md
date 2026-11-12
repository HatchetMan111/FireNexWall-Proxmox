# Testevidenz

Stand: 2026-11-12
Umgebung: Linux (Ubuntu-Kernel 6.8), Python 3.12.3, Node.js 22.23.2, npm 10.9.8

## Ergebnisuebersicht

| Pruefung | Ergebnis | Nachweis |
| --- | --- | --- |
| Bash-Syntax (`bash -n`) | bestanden | `tests/static-checks.sh` |
| Shellcheck (Installer + Tests) | bestanden | `tests/static-checks.sh` |
| Struct-Audit (systemd, Installer, README) | bestanden | `tests/static-checks.sh` |
| Backend-Tests (pytest) | 21 bestanden | `tests/api.sh` |
| Frontend-Tests (vitest) | 3 bestanden | `cd web && npm test` |
| Frontend-Build (tsc + vite) | bestanden | `cd web && npm run build` |
| Container-Pakete (Debian 12) | bestanden | `docker run --rm debian:12 ...`; venv-pip ohne `python3-pip`, kein Node |
| Lokaler End-to-End-Smoke-Test | bestanden | `tests/local-smoke.sh` |
| Browser-/Visual-Pruefung | bestanden, keine Konsolenfehler | Playwright-Screenshots |
| Proxmox-Installation | **nicht ausgefuehrt** | kein `pct`/`pvesh` in dieser Umgebung |
| Proxmox-Reboot-Test | **nicht ausgefuehrt** | Testskript liegt bereit |

## Statische Pruefungen

Befehl:

```bash
bash tests/static-checks.sh
```

Ergebnis: Exit-Code 0.

Geprueft wurden unter anderem:

- `bash -n` fuer alle Skripte in `install/` und `tests/`
- `shellcheck -x` fuer Host-Installer, Container-Installer und Tests
- systemd: `Restart=always`, `After/Wants=network-online.target`,
  Bindung an `0.0.0.0`, `ReadWritePaths`, `NoNewPrivileges`
- Host-Installer: `pvesh get /cluster/nextid`, `--onboot 1`,
  `--unprivileged 1`, `set -euo pipefail`
- Container-Installer: `systemctl enable`, `web/dist/index.html`,
  `ensure_dns`, `Acquire::Retries=5`, `python3 -m venv`, `/healthz`
- README enthaelt den Installations-Einzeiler

## Backend-Tests

Befehl:

```bash
bash tests/api.sh
```

Ergebnis:

```text
platform linux -- Python 3.12.3, pytest-8.3.4
collected 21 items

tests/test_api.py ..............                                         [ 66%]
tests/test_db.py .......                                                 [100%]

21 passed, 1 warning in 4.65s
```

Abgedeckt: Healthcheck, oeffentliche Liste/Detail, Login-Erfolg und -Fehler,
Login-Rate-Limit, Origin-Pruefung, Session/Logout, CRUD, doppelte Slugs,
Entwuerfe, ungueltige Download-URLs, JSON-Export, SPA-Fallback, Asset-Caching,
Path-Traversal-Schutz, `b64:`-Konfigurationshash.

## Frontend

Befehl:

```bash
cd web
npm test
npm run build
```

Ergebnis:

```text
Test Files  1 passed (1)
     Tests  3 passed (3)

dist/index.html                   0.65 kB │ gzip:   0.38 kB
dist/assets/index-D2h6T5Ea.css   18.97 kB │ gzip:   4.65 kB
dist/assets/index-DHL-dU1H.js    355.87 kB │ gzip: 111.74 kB
✓ built in 5.35s
```

## Container-Paketprobe (Debian 12)

Befehl:

```bash
docker run --rm debian:12 bash -lc '
  apt-get update -qq -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::ForceIPv4=true
  apt-get install -y -qq --no-install-recommends -o Acquire::Retries=5 \
    ca-certificates curl git openssl python3 python3-venv sqlite3 ufw
  python3 -m venv /tmp/v
  /tmp/v/bin/pip --version
  test ! -e /usr/bin/node'
```

Ergebnis: `pip 23.0.1 ...` und `PACKAGES-OK`. Damit ist bestaetigt, dass
`python3-venv` pip mitbringt und weder `python3-pip` noch Node.js im Container
noetig sind.

## Lokaler End-to-End-Smoke-Test

Befehl:

```bash
bash tests/local-smoke.sh
```

Ergebnis: Exit-Code 0.

```text
[OK]    Health: {"status":"ok","db":"ok","version":"1.0.0"}
[OK]    SPA-Startseite: HTTP 200
[OK]    SPA-Fallback /admin: HTTP 200
[OK]    Oeffentliche Releases: 3
[OK]    Admin ohne Login: HTTP 401
[OK]    Falsches Login: HTTP 401
[OK]    Login korrekt
[OK]    Release erstellt (ID 4)
[OK]    Doppelter Slug: HTTP 409
[OK]    Nach Logout: HTTP 401
[OK]    Release geloescht: HTTP 204
[OK]    Oeffentliche Releases nach Cleanup: 3

[OK]    Lokaler Smoke-Test bestanden.
```

Der Test verwendet eine temporaere SQLite-Datenbank und einen freien Port; die
Produktionsdaten werden nicht beruehrt.

## Browser-/Visual-Pruefung

Durchgefuehrt mit Playwright gegen den lokal gebauten Stand:

| Ansicht | Datei |
| --- | --- |
| Startseite (hell) | `docs/screenshots/home.png` |
| Release-Detail | `docs/screenshots/detail.png` |
| Admin-Login | `docs/screenshots/login.png` |
| Admin-Bereich | `docs/screenshots/admin.png` |
| Startseite (dunkel) | `docs/screenshots/dark.png` |
| Mobilansicht | `docs/screenshots/mobile.png` |

Beobachtungen:

- Keine Fehler in der Browser-Konsole.
- Light- und Dark-Theme funktionieren.
- Mobilansicht: Suchfeld nimmt die volle Breite ein, Markenname bleibt einzeilig.
- SPA-Routen `/release/:slug` und `/admin` laden direkt (Fallback greift).

## Deployment-Verifikation

Das Repository wurde nach
`https://github.com/HatchetMan111/FireNexWall-Proxmox` gepusht (Branch `main`,
Commit `c126eb0`).

Geprueft am 2026-11-12:

```text
raw .../install/releasenotes.sh        -> HTTP 200
raw .../install/releasenotes-inner.sh  -> HTTP 200
raw .../README.md                      -> HTTP 200
Repository-Webseite                    -> HTTP 200
```

Der veroeffentlichte Einzeiler wurde bis zur Hilfe-Ausgabe ausgefuehrt:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/FireNexWall-Proxmox/main/install/releasenotes.sh)" -- --help
```

Ergebnis: Hilfe wird ausgegeben, Exit-Code 0. Damit sind Download, Bash-Aufruf
und Argumentweitergabe ueber den Raw-Link verifiziert.

## Proxmox-Installation und Reboot

Diese Umgebung ist kein Proxmox-VE-Host:

```text
pct: nicht vorhanden
pvesh: nicht vorhanden
qm: nicht vorhanden
pveam: nicht vorhanden
```

Daher konnten der echte LXC-Installationslauf und der Reboot-Test hier nicht
ausgefuehrt werden. Beides ist vor der Veroeffentlichung auf einem Host
nachzuholen.

### Installation

Voraussetzung: Das Repository ist unter
`https://github.com/HatchetMan111/FireNexWall-Proxmox` erreichbar und der
Branch `main` enthaelt `install/releasenotes.sh`.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/FireNexWall-Proxmox/main/install/releasenotes.sh)" -- --ctid 120 --yes
```

Erwartet:

- Exit-Code 0
- `pct status 120` zeigt `running`
- `pct config 120` zeigt `onboot: 1`
- `pct exec 120 -- systemctl is-active releasenotes` zeigt `active`
- `pct exec 120 -- curl -fsS http://127.0.0.1:8080/healthz` liefert
  `{"status":"ok","db":"ok",...}`

### Reboot-Test

```bash
bash tests/reboot-test.sh --ctid 120 --port 8080
```

Das Skript prueft Dienst und Web-UI vor dem Reboot, rebootet den Container,
wartet auf eine neue `boot_id`, prueft Dienst und `/healthz` erneut und
schreibt die Ausgabe an `docs/test-evidence.md` an.

Erwartetes Ergebnis:

```text
[OK] Dienst aktiv, boot_id <vorher>
[OK] Web-UI antwortet vor dem Reboot
[OK] Reboot ausgeloest
[OK] Neue boot_id <nachher>
[OK] Dienst aktiv, /healthz antwortet nach dem Reboot
[OK] Reboot-Test bestanden.
```

## Bekannte Einschraenkungen

- Der Installer laedt den Code per `git clone` von GitHub. Das Repository muss
  oeffentlich erreichbar bleiben; bei einem anderen Owner/Namen muessen
  `REPO_URL` und die Raw-Links angepasst werden.
- ufw kann in unprivilegierten LXC ohne `CAP_NET_ADMIN` nicht aktiviert werden;
  der Installer warnt dann und faehrt fort. Die LAN-Grenze des Hosts schuetzt.
- Der Login verwendet ein signiertes Cookie ohne serverseitige
  Sitzungsregistrierung. Logout loescht das Cookie im Browser; ein zuvor
  kopiertes Cookie bleibt bis zum Ablauf (12 Stunden) gueltig.
- Fuer TLS/Reverse-Proxy-Betrieb muss `RELEASENOTES_COOKIE_SECURE=1` gesetzt
  werden.
