from contextlib import contextmanager
from typing import Generator

import pymysql
from fastapi import HTTPException
from pymysql.cursors import DictCursor

from app.config import get_settings


@contextmanager
def get_db_connection() -> Generator[pymysql.connections.Connection, None, None]:
    """Yield a MySQL connection configured with DictCursor and auto-commit/rollback."""
    settings = get_settings()
    conn = None
    try:
        conn = pymysql.connect(
            host=settings.mysql_host,
            port=settings.mysql_port,
            user=settings.mysql_user,
            password=settings.mysql_password,
            database=settings.mysql_database,
            charset="utf8mb4",
            cursorclass=DictCursor,
            autocommit=False,
            connect_timeout=5,
        )
        yield conn
        conn.commit()
    except pymysql.MySQLError as exc:
        if conn is not None:
            conn.rollback()
        raise HTTPException(
            status_code=503,
            detail=f"Database error (check MySQL/phpMyAdmin connection): {exc}",
        ) from exc
    finally:
        if conn is not None:
            conn.close()


def get_db() -> Generator[pymysql.connections.Connection, None, None]:
    """FastAPI dependency yielding a MySQL connection."""
    with get_db_connection() as conn:
        yield conn

