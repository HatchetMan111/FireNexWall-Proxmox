from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import threading
import time

SCRYPT_N = 2**14
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_DKLEN = 64


def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64d(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + padding)


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    derived = hashlib.scrypt(
        password.encode("utf-8"),
        salt=salt,
        n=SCRYPT_N,
        r=SCRYPT_R,
        p=SCRYPT_P,
        dklen=SCRYPT_DKLEN,
    )
    return f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}${_b64e(salt)}${_b64e(derived)}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, n_raw, r_raw, p_raw, salt_raw, hash_raw = encoded.split("$")
        if algorithm != "scrypt":
            return False
        derived = hashlib.scrypt(
            password.encode("utf-8"),
            salt=_b64d(salt_raw),
            n=int(n_raw),
            r=int(r_raw),
            p=int(p_raw),
            dklen=len(_b64d(hash_raw)),
        )
        return hmac.compare_digest(derived, _b64d(hash_raw))
    except (ValueError, TypeError):
        return False


def create_session(secret: str, username: str, ttl: int = 43200) -> str:
    payload = {
        "u": username,
        "exp": int(time.time()) + ttl,
        "n": secrets.token_hex(8),
    }
    raw = _b64e(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signature = hmac.new(
        secret.encode("utf-8"), raw.encode("ascii"), hashlib.sha256
    ).digest()
    return f"{raw}.{_b64e(signature)}"


def verify_session(secret: str, token: str | None) -> str | None:
    if not secret or not token or "." not in token:
        return None
    raw, signature = token.rsplit(".", 1)
    expected = hmac.new(
        secret.encode("utf-8"), raw.encode("ascii"), hashlib.sha256
    ).digest()
    try:
        if not hmac.compare_digest(expected, _b64d(signature)):
            return None
        payload = json.loads(_b64d(raw))
        if int(payload.get("exp", 0)) < int(time.time()):
            return None
        username = payload.get("u")
        return str(username) if username else None
    except (ValueError, TypeError, json.JSONDecodeError):
        return None


class LoginGuard:
    def __init__(self, limit: int = 5, window: int = 300) -> None:
        self.limit = limit
        self.window = window
        self._hits: dict[str, list[float]] = {}
        self._lock = threading.Lock()

    def _active(self, key: str) -> list[float]:
        cutoff = time.time() - self.window
        hits = [ts for ts in self._hits.get(key, []) if ts >= cutoff]
        if hits:
            self._hits[key] = hits
        else:
            self._hits.pop(key, None)
        return hits

    def blocked(self, key: str) -> bool:
        with self._lock:
            return len(self._active(key)) >= self.limit

    def fail(self, key: str) -> None:
        with self._lock:
            self._active(key)
            self._hits.setdefault(key, []).append(time.time())

    def reset(self, key: str) -> None:
        with self._lock:
            self._hits.pop(key, None)
