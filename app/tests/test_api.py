from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from conftest import SEED_PATH
from releasenotes.auth import hash_password
from releasenotes.config import Settings
from releasenotes.main import create_app


@pytest.fixture()
def client(tmp_path: Path):
    static = tmp_path / "dist"
    (static / "assets").mkdir(parents=True)
    (static / "index.html").write_text(
        "<!doctype html><html><body><div id=root>index</div></body></html>",
        encoding="utf-8",
    )
    (static / "assets" / "app.js").write_text("console.log('ok')", encoding="utf-8")
    settings = Settings(
        db_path=tmp_path / "test.db",
        static_dir=static,
        seed_path=SEED_PATH,
        secret="test-secret",
        admin_user="admin",
        admin_hash=hash_password("geheim"),
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def login(client: TestClient) -> None:
    response = client.post(
        "/api/login", json={"username": "admin", "password": "geheim"}
    )
    assert response.status_code == 200
    assert response.json()["authenticated"] is True


def new_release(**overrides):
    payload = {
        "version": "2.0.0",
        "title": "Version Zwei",
        "status": "beta",
        "release_date": "2026-11-01",
        "summary": "Zweite Version",
        "body_md": "# Neu\n\nInhalt",
        "known_issues_md": "- Nichts",
        "downloads": [
            {"label": "Download", "url": "https://example.com/file.zip"}
        ],
        "published": True,
    }
    payload.update(overrides)
    return payload


def test_healthz(client: TestClient):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["db"] == "ok"


def test_public_list_and_detail(client: TestClient):
    response = client.get("/api/releases")
    assert response.status_code == 200
    items = response.json()
    assert len(items) == 3
    assert items[0]["version"] == "1.3.0"
    assert all(item["published"] for item in items)

    detail = client.get("/api/releases/1.3.0")
    assert detail.status_code == 200
    assert detail.json()["status"] == "stable"

    latest = client.get("/api/latest")
    assert latest.status_code == 200
    assert latest.json()["slug"] == "1.3.0"


def test_admin_requires_login(client: TestClient):
    assert client.get("/api/admin/releases").status_code == 401
    assert client.get("/api/session").json()["authenticated"] is False


def test_login_rejects_wrong_password(client: TestClient):
    response = client.post(
        "/api/login", json={"username": "admin", "password": "falsch"}
    )
    assert response.status_code == 401
    assert client.get("/api/admin/releases").status_code == 401


def test_login_rejects_foreign_origin(client: TestClient):
    response = client.post(
        "/api/login",
        json={"username": "admin", "password": "geheim"},
        headers={"Origin": "http://evil.example"},
    )
    assert response.status_code == 403


def test_crud_flow(client: TestClient):
    login(client)
    session = client.get("/api/session").json()
    assert session == {"authenticated": True, "username": "admin"}

    created = client.post("/api/admin/releases", json=new_release())
    assert created.status_code == 201
    release_id = created.json()["id"]
    assert created.json()["slug"] == "2.0.0"

    duplicate = client.post("/api/admin/releases", json=new_release())
    assert duplicate.status_code == 409

    public = client.get("/api/releases").json()
    assert any(item["id"] == release_id for item in public)

    draft = client.post(
        "/api/admin/releases", json=new_release(version="3.0.0", published=False)
    )
    assert draft.status_code == 201
    assert not any(item["version"] == "3.0.0" for item in client.get("/api/releases").json())
    admin_items = client.get("/api/admin/releases").json()
    assert any(item["version"] == "3.0.0" for item in admin_items)

    updated = client.put(
        f"/api/admin/releases/{release_id}",
        json=new_release(title="Geaendert", status="stable"),
    )
    assert updated.status_code == 200
    assert updated.json()["title"] == "Geaendert"
    assert updated.json()["status"] == "stable"

    deleted = client.delete(f"/api/admin/releases/{release_id}")
    assert deleted.status_code == 204
    assert client.delete(f"/api/admin/releases/{release_id}").status_code == 404


def test_logout_ends_session(client: TestClient):
    login(client)
    assert client.post("/api/logout").status_code == 200
    assert client.get("/api/admin/releases").status_code == 401


def test_spa_fallback_and_assets(client: TestClient):
    home = client.get("/")
    assert home.status_code == 200
    assert "index" in home.text

    admin = client.get("/admin")
    assert admin.status_code == 200
    assert "index" in admin.text

    asset = client.get("/assets/app.js")
    assert asset.status_code == 200
    assert asset.headers["cache-control"].startswith("public, max-age=31536000")


def test_export(client: TestClient):
    login(client)
    response = client.get("/api/admin/export")
    assert response.status_code == 200
    assert "attachment" in response.headers["content-disposition"]
    assert len(response.json()) == 3


def test_unpublished_detail_is_hidden(client: TestClient):
    login(client)
    created = client.post(
        "/api/admin/releases", json=new_release(published=False)
    )
    assert created.status_code == 201
    assert client.get("/api/releases/2.0.0").status_code == 404


def test_rejects_invalid_download_url(client: TestClient):
    login(client)
    payload = new_release()
    payload["downloads"] = [{"label": "Boese", "url": "javascript:alert(1)"}]
    assert client.post("/api/admin/releases", json=payload).status_code == 422


def test_login_rate_limit(client: TestClient):
    for _ in range(5):
        response = client.post(
            "/api/login", json={"username": "admin", "password": "falsch"}
        )
        assert response.status_code == 401
    blocked = client.post(
        "/api/login", json={"username": "admin", "password": "geheim"}
    )
    assert blocked.status_code == 429


def test_static_path_traversal_is_blocked(client: TestClient):
    response = client.get("/%2e%2e/%2e%2e/etc/passwd")
    assert response.status_code == 200
    assert "root:" not in response.text


def test_config_decodes_base64_hash(monkeypatch, tmp_path: Path):
    from base64 import urlsafe_b64encode

    from releasenotes.auth import verify_password

    encoded = hash_password("geheim")
    packed = "b64:" + urlsafe_b64encode(encoded.encode()).decode().rstrip("=")
    monkeypatch.setenv("RELEASENOTES_ADMIN_HASH", packed)
    monkeypatch.setenv("RELEASENOTES_DB", str(tmp_path / "x.db"))
    settings = Settings.from_env()
    assert settings.admin_hash == encoded
    assert verify_password("geheim", settings.admin_hash)
