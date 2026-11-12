from __future__ import annotations

from .config import Settings
from .db import connect, init_db, seed_if_empty


def main() -> None:
    settings = Settings.from_env()
    settings.db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = connect(settings.db_path)
    try:
        init_db(conn)
        inserted = seed_if_empty(conn, settings.seed_path)
    finally:
        conn.close()
    print(f"seed: {inserted} releases inserted")


if __name__ == "__main__":
    main()
