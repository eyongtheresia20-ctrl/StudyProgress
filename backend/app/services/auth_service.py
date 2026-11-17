import base64
import hashlib
import hmac
import json
import os
import time
from typing import Optional

from fastapi import Depends, Header, HTTPException
from pymysql.connections import Connection

from app.config import get_settings
from app.database import get_db


def hash_password(password: str) -> str:
    """Hash a password using PBKDF2-HMAC-SHA256 with a random 16-byte salt."""
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 120_000)
    return f"{base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def verify_password(password: str, stored_hash: str) -> bool:
    """Verify a plaintext password against a stored PBKDF2 hash."""
    try:
        salt_b64, digest_b64 = stored_hash.split("$", 1)
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(digest_b64)
        actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 120_000)
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def create_access_token(user_id: int, role: str) -> str:
    """Create a signed HMAC-SHA256 bearer token."""
    settings = get_settings()
    payload = {
        "sub": user_id,
        "role": role,
        "exp": int(time.time()) + settings.token_ttl_hours * 3600,
    }
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    payload_b64 = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
    sig = hmac.new(
        settings.auth_secret.encode("utf-8"),
        payload_b64.encode("ascii"),
        hashlib.sha256,
    ).digest()
    sig_b64 = base64.urlsafe_b64encode(sig).decode("ascii").rstrip("=")
    return f"{payload_b64}.{sig_b64}"


def decode_access_token(token: str) -> dict:
    """Validate and decode a signed bearer token."""
    settings = get_settings()
    try:
        payload_b64, sig_b64 = token.split(".", 1)
        expected_sig = hmac.new(
            settings.auth_secret.encode("utf-8"),
            payload_b64.encode("ascii"),
            hashlib.sha256,
        ).digest()
        expected_b64 = base64.urlsafe_b64encode(expected_sig).decode("ascii").rstrip("=")
        if not hmac.compare_digest(sig_b64, expected_b64):
            raise ValueError("Invalid token signature")
        padded = payload_b64 + "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))
        if int(payload.get("exp", 0)) < int(time.time()):
            raise ValueError("Token expired")
        return payload
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired session token") from exc


def get_current_user(
    authorization: Optional[str] = Header(default=None),
    db: Connection = Depends(get_db),
) -> dict:
    """FastAPI dependency returning the authenticated user row."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    payload = decode_access_token(token)
    user_id = int(payload["sub"])

    with db.cursor() as cursor:
        cursor.execute(
            "SELECT id, full_name, email, role, is_active, created_at FROM users WHERE id = %s",
            (user_id,),
        )
        user = cursor.fetchone()
    if not user or not user["is_active"]:
        raise HTTPException(status_code=401, detail="User account not active")
    return user


def require_admin(current_user: dict = Depends(get_current_user)) -> dict:
    """FastAPI dependency ensuring the current user is an administrator."""
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Administrator access required")
    return current_user

