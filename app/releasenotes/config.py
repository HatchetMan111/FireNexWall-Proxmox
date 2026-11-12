from __future__ import annotations

import base64
import os
from dataclasses import dataclass
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _decode_hash(value: str) -> str:
    if not value.startswith("b64:"):
        return value
    raw = value[4:]
    padding = "=" * (-len(raw) % 4)
    return base64.urlsafe_b64decode(raw + padding).decode("utf-8")


@dataclass(frozen=True)
class Settings:
    db_path: Path
    static_dir: Path
    seed_path: Path | None
    secret: str
    admin_user: str
    admin_hash: str
    session_ttl: int = 43200
    cookie_secure: bool = False

    @classmethod
    def from_env(cls) -> "Settings":
        seed_raw = os.environ.get("RELEASENOTES_SEED", str(PACKAGE_ROOT / "data" / "seed.json"))
        seed_path = Path(seed_raw) if seed_raw else None
        return cls(
            db_path=Path(
                os.environ.get(
                    "RELEASENOTES_DB", "/var/lib/releasenotes/releasenotes.db"
                )
            ),
            static_dir=Path(
                os.environ.get(
                    "RELEASENOTES_STATIC", str(PACKAGE_ROOT / "web" / "dist")
                )
            ),
            seed_path=seed_path,
            secret=os.environ.get("RELEASENOTES_SECRET", ""),
            admin_user=os.environ.get("RELEASENOTES_ADMIN_USER", "admin"),
            admin_hash=_decode_hash(os.environ.get("RELEASENOTES_ADMIN_HASH", "")),
            session_ttl=int(os.environ.get("RELEASENOTES_SESSION_TTL", "43200")),
            cookie_secure=os.environ.get("RELEASENOTES_COOKIE_SECURE", "0") == "1",
        )
