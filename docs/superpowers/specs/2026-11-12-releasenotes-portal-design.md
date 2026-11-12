# ReleaseNotes Portal – Design Spec

**Datum:** 2026-11-12
**Status:** Approved (Design), bereit für Implementierungsplan
**Repo:** https://github.com/HatchetMan111/FireNexWall-Proxmox
**App-ID:** `releasenotes` · **Port:** `8080` · **CT-Hostname:** `releasenotes`

## 1. Ziel

Ein vollständig lokales, selbst gehostetes Release-Notes-Portal. Öffentliche
Besucher lesen Releases; ein einzelner Administrator pflegt sie über eine
Weboberfläche mit Login. Keine Cloud-Dienste, keine Telemetrie, keine
externen CDNs. Installation als Proxmox-LXC über einen Community-Scripts-
konformen Einzeiler.

## 2. Scope Version 1

Enthalten:

- Release-Liste mit Suche und Statusfilter
- Detailseite mit Markdown-Body, Known Issues und Download-Links
- Status-Badges (`stable`, `rc`, `beta`, `alpha`, `security`)
- Hervorhebung des neuesten Releases
- Admin-Login (Single-Admin) und CRUD für Releases inkl. Entwürfen
- Markdown-Editor mit Live-Vorschau
- Dark/Light-Theme, responsive UI, lokale Assets
- Beispiel-Seed-Daten (keine Nexwall-Inhalte)

Nicht enthalten (bewusst YAGNI):

- Mehrbenutzer/Rollen, OAuth, Audit-Log
- RSS/Atom, öffentliche JSON-API-Dokumentation, Versionvergleich
- Analytics, Kommentare, Übersetzungen
- Objektspeicher oder externe Datenbank

## 3. Architektur

```
Browser ──HTTP──> FastAPI (uvicorn) ──sqlite3──> /var/lib/releasenotes/releasenotes.db
                        │
                        └── statische Dateien: /opt/releasenotes/web/dist
```

- **Backend:** Python 3.11+, FastAPI, Uvicorn, SQLite (stdlib `sqlite3`),
  Pydantic (über FastAPI). Auth mit stdlib `hashlib.scrypt` und HMAC-signierten
  Cookies. Keine ORM-, Auth- oder Session-Bibliothek.
- **Frontend:** React 18 + Vite 6 + TypeScript, React Router, `react-markdown`
  mit `remark-gfm`. Kein CSS-Framework; eigenes Designsystem über CSS-Variablen.
- **Betrieb:** eine systemd-Unit `releasenotes.service`, `Restart=always`,
  `After=network-online.target`, `onboot=1` im Container.

## 4. Repository-Struktur

```
releasenotes-proxmox/
├── install/releasenotes.sh           # Host-Installer (Proxmox)
├── install/releasenotes-inner.sh     # Container-Installer
├── systemd/releasenotes.service      # Unit-Template (@APP_DIR@/@APP_PORT@)
├── app/
│   ├── requirements.txt
│   ├── requirements-dev.txt
│   ├── pyproject.toml
│   ├── releasenotes/{__init__,config,db,models,auth,seed,main}.py
│   └── tests/test_api.py
├── web/                              # React/Vite/TS
├── data/seed.json
├── tests/{static-checks,api,local-smoke,reboot-test}.sh
├── docs/superpowers/specs|plans/
└── README.md
```

## 5. Datenmodell

Tabelle `releases`:

| Feld | Typ | Regeln |
|---|---|---|
| `id` | INTEGER PK | autoincrement |
| `version` | TEXT | erforderlich, 1–64 Zeichen |
| `slug` | TEXT UNIQUE | erforderlich, `^[a-z0-9][a-z0-9._-]*$`, Default aus Version |
| `title` | TEXT | optional |
| `status` | TEXT | `stable|rc|beta|alpha|security`, Default `stable` |
| `release_date` | TEXT | ISO-Datum `YYYY-MM-DD` |
| `summary` | TEXT | Kurztext, max. 500 Zeichen |
| `body_md` | TEXT | Markdown |
| `known_issues_md` | TEXT | Markdown |
| `downloads` | TEXT/JSON | Array aus `{label,url,platform?,sha256?}` |
| `published` | INTEGER | 0/1, Default 1 |
| `created_at`/`updated_at` | TEXT | UTC ISO-8601 |

Indizes: `release_date DESC`, `slug` unique. Sortierung: Datum absteigend,
bei Gleichstand `id` absteigend.

## 6. HTTP-API

Öffentlich:

- `GET /healthz` → `{status, db, version}`; 503 bei DB-Fehler
- `GET /api/releases` → nur `published`, ohne Entwürfe
- `GET /api/releases/{slug}` → 404 wenn nicht vorhanden/Entwurf
- `GET /api/latest` → neuestes veröffentlichtes Release oder 204
- `GET /api/session` → `{authenticated, username}`

Auth:

- `POST /api/login` `{username,password}` → setzt HttpOnly-Cookie
- `POST /api/logout` → löscht Cookie

Admin (Cookie erforderlich):

- `GET /api/admin/releases` → inkl. Entwürfe
- `POST /api/admin/releases` → 201, 409 bei Slug-Konflikt
- `PUT /api/admin/releases/{id}` → 200, 404/409
- `DELETE /api/admin/releases/{id}` → 204
- `GET /api/admin/export` → JSON-Dump aller Releases

SPA: `/` und alle Nicht-API-Pfade liefern `index.html`; vorhandene Dateien
werden direkt ausgeliefert. `/assets/*` mit langem Cache, `index.html` ohne Cache.

## 7. Auth & Sicherheit

- Admin-Passwort wird beim Install erzeugt (alternativ `--admin-password`),
  als `scrypt$N$r$p$salt$hash` in `/etc/releasenotes/config.env` (0600, root).
- Login-Bremse: max. 5 Fehlversuche pro IP in 5 Minuten, dann 429.
- Session-Cookie: `rn_session`, HttpOnly, SameSite=Lax, 12 h, HMAC-SHA256.
- Schreibende Anfragen mit fremdem `Origin`-Header werden mit 403 abgewiesen.
- Kein Raw-HTML im Frontend; `react-markdown` rendert Markdown ohne `rehype-raw`.
- Admin-Passwort und Secret werden nie geloggt; bei `--debug` wird das
  Passwort nicht in den Logstream geschrieben.
- Empfehlung im README: Bei Zugriff über unsichere Netze Reverse Proxy mit TLS.

## 8. Installer-Verhalten

### Host (`install/releasenotes.sh`)

1. Root-, Proxmox- (`pct`, `pveam`, `pvesh`, `/etc/pve`) Prüfung.
2. CT-ID: `pvesh get /cluster/nextid`, sofern nicht `--ctid`.
3. Existiert die ID:
   - gleicher Hostname `releasenotes` → Update-Modus (Code/Unit aktualisieren,
     DB und Admin-Passwort behalten),
   - fremder Hostname → Abbruch, außer `--force` (dann `pct destroy --purge`).
4. Debian-12-Template sicherstellen, Storage automatisch ermitteln.
5. Container erstellen: `--unprivileged 1 --onboot 1`, DHCP, 2 vCPU,
   2048 MB RAM, 8 GB Disk, Beschreibung „ReleaseNotes Portal“.
6. Netz/DNS abwarten (max. 120 s), Inner-Script per `pct push` übertragen,
   im Container ausführen.
7. Verifikation vom Host: `systemctl is-active`, HTTP-Check auf `/healthz`.
8. Ausgabe: URL, CT-ID, Hostname, Admin-Passwort (nur bei Erstinstallation),
   Update-/Log-/Entfern-Kommandos.

Optionen: `--ctid --hostname --cores --ram --disk --storage --template-storage
--bridge --port --admin-password --repo --ref --nameserver --force --yes --debug -h`.

Fehlerbehandlung: `set -euo pipefail`, ERR-Trap mit Exit-Code, Zeile, Kommando,
Container-Status, letzte Logzeilen, `journalctl`, offene Ports; vollständiges
Log unter `/var/log/releasenotes-install.log`; `--debug` aktiviert `bash -x`.

### Container (`install/releasenotes-inner.sh`)

1. DNS prüfen (Gateway/Host-DNS/Public-Fallback), `apt-get update` mit Retries;
   Installation von `ca-certificates curl git openssl python3 python3-venv
   sqlite3 ufw`.
2. Systembenutzer `releasenotes`, Verzeichnisse `/opt/releasenotes`,
   `/var/lib/releasenotes`, `/etc/releasenotes`.
3. Repo klonen, App/Web/Unit inklusive mitgeliefertem `web/dist` kopieren
   (Update überschreibt Code, nicht Daten).
4. venv anlegen, `pip install -r requirements.txt`.
5. Konfiguration schreiben; bei Update Secret/Hash erhalten.
6. DB initialisieren; Seed nur bei leerer Tabelle.
7. Unit aus Template rendern, `daemon-reload`, `enable`, `restart`.
8. ufw: Port nur aus RFC1918; bei fehlenden Rechten Warnung statt Abbruch.
9. Healthcheck mit Retry; bei Fehler vollständige Diagnose.

## 9. UI

- **Look:** dunkles, redaktionelles Interface mit hellem Modus; tiefes Navy,
  Elektroblau als Akzent, Monospace für Versionsnummern, großzügiger
  Weißraum, klare Karten, keine externen Fonts.
- **Startseite:** Hero mit neuestem Release, Suchfeld, Statusfilter,
  Release-Karten (Version, Datum, Status, Zusammenfassung).
- **Detailseite:** Titel, Metadaten, Markdown, Known Issues, Downloads,
  Zurück-Link, Anker für Überschriften.
- **Admin:** Login-Karte; danach Liste (inkl. Entwürfe) und Editor mit
  Feldern, Download-Zeilen, Live-Vorschau, Speichern/Löschen, Logout.
- **Zustände:** Lade-Skeleton, leere Liste, Fehlerbanner, 404-Seite.
- **A11y:** Labels, sichtbarer Fokus, ausreichende Kontraste, Tastaturbedienung.

## 10. Verifikation

- `bash -n` und `shellcheck` für beide Installer und Testskripte.
- `pytest app/tests` gegen temporäre SQLite-DB (Health, Public-API, Auth,
  CRUD, Konflikte, SPA-Fallback).
- `npm run build` (TypeScript + Vite) und `npm run lint` falls konfiguriert.
- `tests/local-smoke.sh`: App lokal mit Temp-DB starten, Login/CRUD/Health
  per curl prüfen.
- `tests/reboot-test.sh`: auf dem Proxmox-Host Installation prüfen, CT
  rebooten, auf Service und HTTP warten, Ergebnis nach
  `docs/test-evidence.md` schreiben.
- Ein echter Proxmox-Reboot-Test ist in der Entwicklungsumgebung nicht möglich;
  das Skript und die lokalen Tests werden ausgeführt, der Host-Test wird
  dokumentiert und kann vom Betreiber reproduziert werden.

## 11. Betrieb

- Update: Installer erneut mit `--ctid <ID>` ausführen.
- Deinstallation: `pct stop <ID> && pct destroy <ID> --purge`.
- Admin-Passwort zurücksetzen: Installer mit `--ctid <ID> --admin-password 'neu'`.
- Logs: `journalctl -u releasenotes -f`.
- Backup: `/var/lib/releasenotes/releasenotes.db` und `/etc/releasenotes/config.env`.
