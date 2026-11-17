from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import get_settings
from app.routers import ai, auth, curriculum, health

settings = get_settings()
origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()] or ["*"]
use_wildcard = "*" in origins

app = FastAPI(
    title="StudyProgress Cameroon API",
    description="FastAPI + MySQL (phpMyAdmin) + Gemini AI backend for Cameroon English & French Subsystems.",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[] if use_wildcard else origins,
    allow_origin_regex=".*" if use_wildcard else None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def _unhandled_exception_handler(_request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=500, content={"detail": str(exc)})

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(curriculum.router)
app.include_router(ai.router)
