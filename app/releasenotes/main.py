from __future__ import annotations

import json
import logging
import secrets
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import urlparse

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse, JSONResponse

from . import __version__
from .auth import (
    LoginGuard,
    create_session,
    verify_password,
    verify_session,
)
from .config import Settings
from .db import (
    ConflictError,
    NotFoundError,
    connect,
    count_releases,
    create_release,
    delete_release,
    export_releases,
    get_release,
    init_db,
    latest_release,
    list_releases,
    seed_if_empty,
    update_release,
)
from .models import LoginIn, ReleaseIn

logger = logging.getLogger("releasenotes")
COOKIE_NAME = "rn_session"


def get_db(request: Request):
    conn = connect(request.app.state.settings.db_path)
    try:
        yield conn
    finally:
        conn.close()


def require_admin(request: Request) -> str:
    settings = request.app.state.settings
    token = request.cookies.get(COOKIE_NAME)
    user = verify_session(request.app.state.secret, token)
    if user is None or user != settings.admin_user:
        raise HTTPException(status_code=401, detail="Nicht angemeldet")
    return user


def _static_root(request: Request) -> Path:
    return request.app.state.settings.static_dir.resolve()


def _safe_file(root: Path, relative: str) -> Path | None:
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    return candidate if candidate.is_file() else None


def _serve_index(request: Request) -> Response:
    index = _static_root(request) / "index.html"
    if not index.is_file():
        return JSONResponse(
            {
                "detail": "Web-Build fehlt. Bitte 'npm run build' im Verzeichnis web ausfuehren."
            },
            status_code=404,
        )
    return FileResponse(
        index,
        media_type="text/html",
        headers={"Cache-Control": "no-cache"},
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    secret = settings.secret or secrets.token_hex(32)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        settings.db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = connect(settings.db_path)
        try:
            init_db(conn)
            inserted = seed_if_empty(conn, settings.seed_path)
            if inserted:
                logger.info("Seeded %s releases", inserted)
            logger.info("Database ready (%s releases)", count_releases(conn))
        finally:
            conn.close()
        if not settings.secret:
            logger.warning(
                "RELEASENOTES_SECRET is not set; sessions are invalid after restart"
            )
        yield

    app = FastAPI(
        title="ReleaseNotes Portal",
        version=__version__,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.secret = secret
    app.state.login_guard = LoginGuard()

    @app.middleware("http")
    async def security_middleware(request: Request, call_next):
        if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
            origin = request.headers.get("origin")
            if origin:
                parsed = urlparse(origin)
                if not parsed.netloc or parsed.netloc != request.headers.get("host", ""):
                    return JSONResponse(
                        {"detail": "Origin nicht erlaubt"}, status_code=403
                    )
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "same-origin")
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:; font-src 'self'; connect-src 'self'; "
            "base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
        )
        return response

    @app.get("/healthz")
    def healthz(request: Request):
        try:
            conn = connect(request.app.state.settings.db_path)
            try:
                conn.execute("SELECT 1").fetchone()
            finally:
                conn.close()
            db_state = "ok"
        except Exception:
            logger.exception("Healthcheck database failure")
            db_state = "error"
        status_code = 200 if db_state == "ok" else 503
        return JSONResponse(
            {
                "status": "ok" if db_state == "ok" else "error",
                "db": db_state,
                "version": __version__,
            },
            status_code=status_code,
        )

    @app.get("/api/releases")
    def api_public_releases(db=Depends(get_db)):
        return list_releases(db, published_only=True)

    @app.get("/api/latest")
    def api_latest(db=Depends(get_db)):
        item = latest_release(db)
        if item is None:
            return Response(status_code=204)
        return item

    @app.get("/api/releases/{slug}")
    def api_release(slug: str, db=Depends(get_db)):
        item = get_release(db, slug=slug, published_only=True)
        if item is None:
            raise HTTPException(status_code=404, detail="Release nicht gefunden")
        return item

    @app.get("/api/session")
    def api_session(request: Request):
        settings = request.app.state.settings
        token = request.cookies.get(COOKIE_NAME)
        user = verify_session(request.app.state.secret, token)
        authenticated = user is not None and user == settings.admin_user
        return {
            "authenticated": authenticated,
            "username": settings.admin_user if authenticated else None,
        }

    @app.post("/api/login")
    def api_login(payload: LoginIn, request: Request, response: Response):
        settings = request.app.state.settings
        client = request.client.host if request.client else "unknown"
        guard: LoginGuard = request.app.state.login_guard
        if guard.blocked(client):
            raise HTTPException(
                status_code=429,
                detail="Zu viele Fehlversuche. Bitte spaeter erneut versuchen.",
            )
        if not settings.admin_hash:
            raise HTTPException(
                status_code=503, detail="Admin-Zugang ist nicht konfiguriert"
            )
        valid_user = payload.username == settings.admin_user
        valid_password = verify_password(payload.password, settings.admin_hash)
        if not (valid_user and valid_password):
            guard.fail(client)
            raise HTTPException(
                status_code=401, detail="Benutzername oder Passwort falsch"
            )
        guard.reset(client)
        token = create_session(
            request.app.state.secret, settings.admin_user, settings.session_ttl
        )
        response.set_cookie(
            COOKIE_NAME,
            token,
            max_age=settings.session_ttl,
            httponly=True,
            samesite="lax",
            secure=settings.cookie_secure,
            path="/",
        )
        return {"authenticated": True, "username": settings.admin_user}

    @app.post("/api/logout")
    def api_logout(response: Response):
        response.delete_cookie(COOKIE_NAME, path="/")
        return {"authenticated": False}

    @app.get("/api/admin/releases")
    def api_admin_releases(_: str = Depends(require_admin), db=Depends(get_db)):
        return list_releases(db, published_only=False)

    @app.get("/api/admin/export")
    def api_admin_export(_: str = Depends(require_admin), db=Depends(get_db)):
        body = json.dumps(export_releases(db), ensure_ascii=False, indent=2)
        return Response(
            content=body,
            media_type="application/json",
            headers={
                "Content-Disposition": 'attachment; filename="releasenotes-export.json"'
            },
        )

    @app.post("/api/admin/releases", status_code=201)
    def api_admin_create(
        payload: ReleaseIn, _: str = Depends(require_admin), db=Depends(get_db)
    ):
        try:
            return create_release(db, payload.model_dump())
        except ConflictError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

    @app.put("/api/admin/releases/{release_id}")
    def api_admin_update(
        release_id: int,
        payload: ReleaseIn,
        _: str = Depends(require_admin),
        db=Depends(get_db),
    ):
        try:
            return update_release(db, release_id, payload.model_dump())
        except NotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ConflictError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

    @app.delete("/api/admin/releases/{release_id}", status_code=204)
    def api_admin_delete(
        release_id: int, _: str = Depends(require_admin), db=Depends(get_db)
    ):
        try:
            delete_release(db, release_id)
        except NotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return Response(status_code=204)

    @app.get("/")
    def index(request: Request):
        return _serve_index(request)

    @app.get("/{full_path:path}")
    def spa(full_path: str, request: Request):
        if full_path.startswith(("api/", "healthz")):
            raise HTTPException(status_code=404, detail="Not found")
        root = _static_root(request)
        file = _safe_file(root, full_path)
        if file is not None:
            headers = (
                {"Cache-Control": "public, max-age=31536000, immutable"}
                if full_path.startswith("assets/")
                else {}
            )
            return FileResponse(file, headers=headers)
        return _serve_index(request)

    return app


app = create_app()
