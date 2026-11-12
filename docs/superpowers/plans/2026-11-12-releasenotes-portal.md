# ReleaseNotes Portal – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein lokal installierbares Release-Notes-Portal (FastAPI + SQLite + React/Vite) mit Community-Scripts-konformem Proxmox-LXC-Installer.

**Architecture:** FastAPI liefert JSON-API und das gebaute React-SPA aus; SQLite speichert Releases. Der Host-Installer erzeugt einen Debian-12-LXC und ruft den Inner-Installer auf, der Code, Build, venv, systemd-Unit und Firewall einrichtet.

**Tech Stack:** Python 3.11+/FastAPI/Uvicorn/sqlite3, React 18/Vite 6/TypeScript, Bash, systemd, Proxmox `pct`/`pveam`.

**Spec:** `docs/superpowers/specs/2026-11-12-releasenotes-portal-design.md`

## Global Constraints

- App-ID `releasenotes`, Port `8080`, CT-Hostname `releasenotes`.
- Repo `https://github.com/HatchetMan111/FireNexWall-Proxmox`, Branch `main`.
- Beide Installer: `set -euo pipefail`, ERR-Trap mit vollständiger Fehlerkette,
  Log unter `/var/log/releasenotes-install.log`.
- Container: Debian 12, unprivileged, `onboot 1`, 2 vCPU, 2048 MB RAM, 8 GB Disk.
- Keine externen Cloud-Dienste, keine CDNs, keine Telemetrie.
- UI-Texte Deutsch; Code/Kommentare Englisch; keine Kommentare in generiertem Code,
  außer sicherheitsrelevanten Begründungen.
- Admin-Daten in `/etc/releasenotes/config.env` (0600), DB in
  `/var/lib/releasenotes/releasenotes.db`, Code in `/opt/releasenotes`.

## Review Focus

- Leere Datenbank / fehlende Seed-Datei darf den Start nicht verhindern.
- Umlaute und Markdown-Sonderzeichen in Version/Titel/Text müssen korrekt
  gespeichert, sortiert und gerendert werden.
- Doppelte Version/Slug darf bestehende Releases nicht überschreiben (409).
- Abgelaufene/manipulierte Session-Cookies dürfen keinen Schreibzugriff erlauben.
- Installer-Wiederholung darf DB und Admin-Passwort nicht löschen.

---

### Task 1: Projekt-Scaffold, Konfiguration und Datenbank

**Files:**
- Create: `app/requirements.txt`, `app/requirements-dev.txt`, `app/pyproject.toml`
- Create: `app/releasenotes/__init__.py`, `config.py`, `db.py`
- Create: `data/seed.json`
- Test: `app/tests/test_db.py`

**Interfaces:**
- Produces: `Settings(db_path, static_dir, seed_path, secret, admin_user, admin_hash)`,
  `Settings.from_env()`, `connect(path)`, `init_db(path)`, `seed_if_empty(conn, path)`,
  `list_releases(conn, published_only)`, `get_release(conn, slug|id)`,
  `create_release(conn, data)`, `update_release(conn, id, data)`, `delete_release(conn, id)`,
  `latest_release(conn)`.

- [ ] **Step 1:** `requirements.txt` mit `fastapi==0.115.6`, `uvicorn[standard]==0.32.1`.
  `requirements-dev.txt` mit `pytest==8.3.4`, `httpx==0.28.1`.
- [ ] **Step 2:** Failing test: DB anlegen, Seed importieren, Liste sortiert prüfen,
  doppelten Slug ablehnen.
- [ ] **Step 3:** `pytest app/tests/test_db.py -v` → FAIL (Module fehlen).
- [ ] **Step 4:** `config.py` (Env-basierte Settings), `db.py` (Schema, CRUD,
  JSON-Downloads, Seed) implementieren; `data/seed.json` mit drei deutschen
  Beispiel-Releases.
- [ ] **Step 5:** `pytest app/tests/test_db.py -v` → PASS.

### Task 2: Auth, Modelle und API

**Files:**
- Create: `app/releasenotes/models.py`, `auth.py`, `main.py`, `seed.py`
- Test: `app/tests/test_api.py`

**Interfaces:**
- Consumes: DB-Funktionen aus Task 1.
- Produces: `create_app(settings=None)`, `app`; Endpunkte gemäß Spec §6;
  `hash_password(pw)`, `verify_password(pw, hash)`, `create_session(secret, user)`,
  `verify_session(secret, token)`.

- [ ] **Step 1:** Failing API-Tests: `/healthz`, öffentliche Liste ohne Entwürfe,
  Login falsch/richtig, CRUD nur mit Cookie, Slug-Konflikt 409, SPA-Fallback.
- [ ] **Step 2:** `pytest app/tests/test_api.py -v` → FAIL.
- [ ] **Step 3:** `auth.py` (scrypt, HMAC-Cookie, Login-Bremse), `models.py`
  (Pydantic-Validierung), `main.py` (Routen, Origin-Check, statische Auslieferung,
  Lifespan-Init/Seed), `seed.py` (CLI) implementieren.
- [ ] **Step 4:** `pytest app/tests -v` → PASS.

### Task 3: React/Vite-Frontend

**Files:**
- Create: `web/package.json`, `package-lock.json`, `tsconfig.json`,
  `tsconfig.node.json`, `vite.config.ts`, `index.html`
- Create: `web/src/main.tsx`, `App.tsx`, `styles.css`, `lib/api.ts`, `lib/types.ts`
- Create: `web/src/components/{Header,StatusBadge,Markdown,ThemeToggle}.tsx`
- Create: `web/src/pages/{HomePage,ReleasePage,AdminPage,NotFound}.tsx`
- Test: `web/src/lib/format.test.ts` (Vitest) optional; Build ist Pflicht.

**Interfaces:**
- Consumes: API aus Task 2.
- Produces: gebautes `web/dist` mit `index.html` und `assets/*`.

- [ ] **Step 1:** Vite/React/TS-Konfiguration und `npm install` (Lockfile erzeugen).
- [ ] **Step 2:** API-Client/Typen, Routing, Theme, Layout implementieren.
- [ ] **Step 3:** Öffentliche Liste mit Suche/Statusfilter, Detailseite mit
  Markdown/Known Issues/Downloads, 404.
- [ ] **Step 4:** Admin-Login, Release-Tabelle, Editor mit Download-Zeilen,
  Live-Vorschau, Speichern/Löschen, Logout.
- [ ] **Step 5:** `npm run build` → PASS (keine TS-Fehler); `npm run test` falls Tests vorhanden.
- [ ] **Step 6:** Visueller Smoke per `npm run dev` + curl auf den Dev-Server.

### Task 4: systemd-Unit und Container-Installer

**Files:**
- Create: `systemd/releasenotes.service`
- Create: `install/releasenotes-inner.sh`
- Test: `tests/static-checks.sh`

**Interfaces:**
- Consumes: Repo-Struktur, `app/requirements.txt`, `web/package.json`.
- Produces: `/etc/systemd/system/releasenotes.service`, laufender Dienst auf `:8080`.

- [ ] **Step 1:** Unit-Template mit `@APP_DIR@`, `@APP_USER@`, `@APP_PORT@`;
  `Restart=always`, `After=network-online.target`, `Wants=network-online.target`,
  `ProtectSystem=strict`, `ReadWritePaths=/var/lib/releasenotes`.
- [ ] **Step 2:** Inner-Installer: Argumente, Logging/ERR-Trap, apt, User,
  Clone, Web-Build, venv, Config (Secret/Hash erzeugen bzw. erhalten), DB/Seed,
  Unit rendern, enable/restart, ufw, Healthcheck.
- [ ] **Step 3:** `bash -n install/releasenotes-inner.sh` und `shellcheck` → PASS
  (oder dokumentierte Ausnahmen).
- [ ] **Step 4:** Lokaler Trockentest der Konfigurations-/Hash-Erzeugung mit
  temporärem Verzeichnis (ohne apt/systemd).

### Task 5: Host-Installer

**Files:**
- Create: `install/releasenotes.sh`
- Modify: `tests/static-checks.sh`

- [ ] **Step 1:** Argumentparser, Root-/Proxmox-Prüfung, Logging/ERR-Trap.
- [ ] **Step 2:** Nächste freie ID, Update-/Fremd-CT-Erkennung, Template/Storage,
  CT-Erstellung mit `onboot 1` und Ressourcen.
- [ ] **Step 3:** Netz warten, Inner-Script lokal/remote beziehen, `pct push`,
  Ausführung, Host-Verifikation, Abschlussausgabe.
- [ ] **Step 4:** `bash -n` + `shellcheck` → PASS; `--help` und Argumentfehler testen.

### Task 6: Tests, README und Nachweise

**Files:**
- Create: `tests/api.sh`, `tests/local-smoke.sh`, `tests/reboot-test.sh`
- Create: `README.md`, `docs/test-evidence.md`, `.gitignore`
- Test: alle Skripte

- [ ] **Step 1:** `api.sh` führt pytest in einer temporären venv aus.
- [ ] **Step 2:** `local-smoke.sh` startet Uvicorn mit Temp-DB, prüft Health,
  Login und CRUD per curl, beendet sauber.
- [ ] **Step 3:** `reboot-test.sh` (Host) prüft Installation, rebootet CT,
  wartet auf Service/HTTP, schreibt Logauszug nach `docs/test-evidence.md`.
- [ ] **Step 4:** README mit Einzeiler, Optionen, Update, Deinstallation,
  Passwort-Reset, Logs, Troubleshooting, Sicherheitshinweis, Entwicklung.
- [ ] **Step 5:** Alle lokalen Verifikationen ausführen und Ergebnisse in
  `docs/test-evidence.md` festhalten.

## Execution

Native Ausführung in dieser Session (kein separater Subagent), da die Tasks
stark über gemeinsame Interfaces verzahnt sind. Nach jedem Task: Tests/Lint.
