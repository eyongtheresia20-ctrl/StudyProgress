from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables or .env."""

    mysql_host: str = "127.0.0.1"
    mysql_port: int = 3306
    mysql_user: str = "root"
    mysql_password: str = ""
    mysql_database: str = "study_progress_db"

    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.1-flash-lite"

    auth_secret: str = "studyprogress-cameroon-dev-secret-change-in-env"
    token_ttl_hours: int = 168

    api_host: str = "0.0.0.0"
    api_port: int = 8000
    cors_origins: str = "*"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()
