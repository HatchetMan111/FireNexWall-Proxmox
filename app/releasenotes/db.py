from __future__ import annotations

import json
import re
import sqlite3
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
STATUSES = ("stable", "rc", "beta", "alpha", "security")

SCHEMA = """
CREATE TABLE IF NOT EXISTS releases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'stable',
    release_date TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    body_md TEXT NOT NULL DEFAULT '',
    known_issues_md TEXT NOT NULL DEFAULT '',
    downloads TEXT NOT NULL DEFAULT '[]',
    published INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_releases_date ON releases(release_date DESC, id DESC);
"""


class ConflictError(Exception):
    """Raised when a slug is already in use."""


class NotFoundError(Exception):
    """Raised when a release does not exist."""


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def connect(path: Path | str) -> sqlite3.Connection:
    conn = sqlite3.connect(str(path), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=5000")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


def slugify(value: str) -> str:
    slug = value.strip().lower()
    slug = re.sub(r"\s+", "-", slug)
    slug = "".join(ch for ch in slug if ch.isalnum() or ch in "._-")
    slug = slug.strip("-._")
    return slug or "release"


def _iso_date(value: Any) -> str:
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    text = str(value).strip()
    date.fromisoformat(text)
    return text


def _normalize(data: dict[str, Any]) -> dict[str, Any]:
    version = str(data.get("version", "")).strip()
    if not version:
        raise ValueError("version is required")
    slug = str(data.get("slug") or slugify(version)).strip().lower()
    if not SLUG_RE.match(slug):
        raise ValueError(
            "slug must match ^[a-z0-9][a-z0-9._-]*$"
        )
    status = str(data.get("status") or "stable").strip().lower()
    if status not in STATUSES:
        raise ValueError(f"status must be one of {', '.join(STATUSES)}")
    downloads = data.get("downloads") or []
    if not isinstance(downloads, list):
        raise ValueError("downloads must be a list")
    return {
        "version": version,
        "slug": slug,
        "title": str(data.get("title") or "").strip(),
        "status": status,
        "release_date": _iso_date(data.get("release_date")),
        "summary": str(data.get("summary") or "").strip(),
        "body_md": str(data.get("body_md") or ""),
        "known_issues_md": str(data.get("known_issues_md") or ""),
        "downloads": json.dumps(downloads, ensure_ascii=False),
        "published": 1 if data.get("published", True) else 0,
    }


def _row_to_release(row: sqlite3.Row) -> dict[str, Any]:
    item = dict(row)
    try:
        item["downloads"] = json.loads(item.get("downloads") or "[]")
    except json.JSONDecodeError:
        item["downloads"] = []
    item["published"] = bool(item.get("published"))
    return item


def list_releases(
    conn: sqlite3.Connection, published_only: bool = True
) -> list[dict[str, Any]]:
    query = "SELECT * FROM releases"
    params: tuple[Any, ...] = ()
    if published_only:
        query += " WHERE published = 1"
    query += " ORDER BY release_date DESC, id DESC"
    return [_row_to_release(row) for row in conn.execute(query, params)]


def get_release(
    conn: sqlite3.Connection,
    *,
    slug: str | None = None,
    release_id: int | None = None,
    published_only: bool = False,
) -> dict[str, Any] | None:
    if release_id is not None:
        row = conn.execute(
            "SELECT * FROM releases WHERE id = ?", (release_id,)
        ).fetchone()
    elif slug is not None:
        row = conn.execute(
            "SELECT * FROM releases WHERE slug = ?", (slug,)
        ).fetchone()
    else:
        raise ValueError("slug or release_id is required")
    if row is None:
        return None
    item = _row_to_release(row)
    if published_only and not item["published"]:
        return None
    return item


def create_release(conn: sqlite3.Connection, data: dict[str, Any]) -> dict[str, Any]:
    values = _normalize(data)
    now = utc_now()
    try:
        cur = conn.execute(
            """
            INSERT INTO releases
                (version, slug, title, status, release_date, summary, body_md,
                 known_issues_md, downloads, published, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                values["version"],
                values["slug"],
                values["title"],
                values["status"],
                values["release_date"],
                values["summary"],
                values["body_md"],
                values["known_issues_md"],
                values["downloads"],
                values["published"],
                now,
                now,
            ),
        )
        conn.commit()
    except sqlite3.IntegrityError as exc:
        conn.rollback()
        raise ConflictError(f"slug '{values['slug']}' already exists") from exc
    item = get_release(conn, release_id=int(cur.lastrowid))
    assert item is not None
    return item


def update_release(
    conn: sqlite3.Connection, release_id: int, data: dict[str, Any]
) -> dict[str, Any]:
    existing = get_release(conn, release_id=release_id)
    if existing is None:
        raise NotFoundError(f"release {release_id} not found")
    merged = dict(existing)
    merged.update(data)
    values = _normalize(merged)
    try:
        conn.execute(
            """
            UPDATE releases
               SET version = ?, slug = ?, title = ?, status = ?, release_date = ?,
                   summary = ?, body_md = ?, known_issues_md = ?, downloads = ?,
                   published = ?, updated_at = ?
             WHERE id = ?
            """,
            (
                values["version"],
                values["slug"],
                values["title"],
                values["status"],
                values["release_date"],
                values["summary"],
                values["body_md"],
                values["known_issues_md"],
                values["downloads"],
                values["published"],
                utc_now(),
                release_id,
            ),
        )
        conn.commit()
    except sqlite3.IntegrityError as exc:
        conn.rollback()
        raise ConflictError(f"slug '{values['slug']}' already exists") from exc
    item = get_release(conn, release_id=release_id)
    assert item is not None
    return item


def delete_release(conn: sqlite3.Connection, release_id: int) -> None:
    cur = conn.execute("DELETE FROM releases WHERE id = ?", (release_id,))
    conn.commit()
    if cur.rowcount == 0:
        raise NotFoundError(f"release {release_id} not found")


def latest_release(conn: sqlite3.Connection) -> dict[str, Any] | None:
    releases = list_releases(conn, published_only=True)
    return releases[0] if releases else None


def export_releases(conn: sqlite3.Connection) -> list[dict[str, Any]]:
    return list_releases(conn, published_only=False)


def count_releases(conn: sqlite3.Connection) -> int:
    row = conn.execute("SELECT COUNT(*) AS n FROM releases").fetchone()
    return int(row["n"])


def seed_if_empty(conn: sqlite3.Connection, seed_path: Path | str | None) -> int:
    if count_releases(conn) > 0 or not seed_path:
        return 0
    path = Path(seed_path)
    if not path.is_file():
        return 0
    items = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(items, list):
        raise ValueError("seed file must contain a list")
    inserted = 0
    for item in items:
        try:
            create_release(conn, item)
            inserted += 1
        except ConflictError:
            continue
    return inserted
