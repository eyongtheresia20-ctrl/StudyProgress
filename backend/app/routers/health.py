from fastapi import APIRouter, Depends
from pymysql.connections import Connection

from app.config import get_settings
from app.database import get_db

router = APIRouter(tags=["health"])


@router.get("/health")
def health_check(db: Connection = Depends(get_db)) -> dict:
    """Verify API, MySQL connection, and Gemini API configuration."""
    with db.cursor() as cursor:
        cursor.execute("SELECT 1 AS ok")
        row = cursor.fetchone()
    settings = get_settings()
    return {
        "status": "ok",
        "database": "connected" if row and row.get("ok") == 1 else "error",
        "mysql_database": settings.mysql_database,
        "gemini_configured": bool(settings.gemini_api_key.strip()),
    }

