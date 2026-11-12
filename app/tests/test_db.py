from __future__ import annotations

from pathlib import Path

import pytest

from conftest import SEED_PATH
from releasenotes.db import (
    ConflictError,
    NotFoundError,
    connect,
    count_releases,
    create_release,
    delete_release,
    get_release,
    init_db,
    latest_release,
    list_releases,
    seed_if_empty,
    update_release,
)


@pytest.fixture()
def conn(tmp_path: Path):
    connection = connect(tmp_path / "test.db")
    init_db(connection)
    yield connection
    connection.close()


def test_seed_and_order(conn):
    assert seed_if_empty(conn, SEED_PATH) == 3
    assert count_releases(conn) == 3
    releases = list_releases(conn)
    assert [item["version"] for item in releases] == ["1.3.0", "1.2.0", "1.1.0-rc1"]
    assert latest_release(conn)["slug"] == "1.3.0"
    assert seed_if_empty(conn, SEED_PATH) == 0


def test_missing_seed_is_noop(conn, tmp_path):
    assert seed_if_empty(conn, tmp_path / "missing.json") == 0
    assert seed_if_empty(conn, None) == 0


def test_slug_default_and_lookup(conn):
    item = create_release(
        conn,
        {
            "version": "2.0.0",
            "release_date": "2026-11-01",
            "title": "Zwei",
        },
    )
    assert item["slug"] == "2.0.0"
    assert get_release(conn, slug="2.0.0")["id"] == item["id"]


def test_duplicate_slug_conflicts(conn):
    payload = {"version": "2.0.0", "release_date": "2026-11-01"}
    create_release(conn, payload)
    with pytest.raises(ConflictError):
        create_release(conn, {**payload, "title": "Duplikat"})


def test_drafts_hidden_from_public_list(conn):
    create_release(
        conn,
        {
            "version": "2.0.0",
            "release_date": "2026-11-01",
            "published": False,
        },
    )
    assert list_releases(conn, published_only=True) == []
    assert len(list_releases(conn, published_only=False)) == 1
    assert get_release(conn, slug="2.0.0", published_only=True) is None


def test_update_and_delete(conn):
    item = create_release(
        conn,
        {"version": "2.0.0", "release_date": "2026-11-01", "title": "Alt"},
    )
    updated = update_release(conn, item["id"], {"title": "Neu", "status": "beta"})
    assert updated["title"] == "Neu"
    assert updated["status"] == "beta"

    delete_release(conn, item["id"])
    assert get_release(conn, release_id=item["id"]) is None
    with pytest.raises(NotFoundError):
        delete_release(conn, item["id"])
    with pytest.raises(NotFoundError):
        update_release(conn, 9999, {"title": "x"})


def test_invalid_date_rejected(conn):
    with pytest.raises(ValueError):
        create_release(
            conn, {"version": "2.0.0", "release_date": "01.11.2026"}
        )


def test_slugify_folds_unicode(conn):
    item = create_release(
        conn,
        {"version": "1.4.0-Überarbeitung", "release_date": "2026-11-01"},
    )
    assert item["slug"] == "1.4.0-uberarbeitung"


def test_slugify_strips_non_ascii(conn):
    item = create_release(
        conn,
        {"version": "Версия 1.0", "release_date": "2026-11-01"},
    )
    assert item["slug"] == "1.0"


def test_download_entries_validated(conn):
    with pytest.raises(ValueError):
        create_release(
            conn,
            {
                "version": "2.0.0",
                "release_date": "2026-11-01",
                "downloads": [{"label": "", "url": "https://example.com"}],
            },
        )
    with pytest.raises(ValueError):
        create_release(
            conn,
            {
                "version": "2.0.0",
                "release_date": "2026-11-01",
                "downloads": [{"label": "Paket", "url": "ftp://example.com/x"}],
            },
        )
    with pytest.raises(ValueError):
        create_release(
            conn,
            {
                "version": "2.0.0",
                "release_date": "2026-11-01",
                "downloads": ["kein-objekt"],
            },
        )
    item = create_release(
        conn,
        {
            "version": "2.0.0",
            "release_date": "2026-11-01",
            "downloads": [
                {
                    "label": "Paket",
                    "url": "https://example.com/paket.tar.gz",
                    "sha256": "abc",
                }
            ],
        },
    )
    assert item["downloads"] == [
        {"label": "Paket", "url": "https://example.com/paket.tar.gz", "sha256": "abc"}
    ]
