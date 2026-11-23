"""
=============================================================================
FILE: main.py
PURPOSE: FastAPI Main Entry Point & Route Orchestrator for Kivora
=============================================================================
Features:
- CORS middleware with wildcard fallback for multi-device network testing.
- Static download endpoint for over-the-air APK distribution.
- Modular router registration:
    * /auth       - Student & Admin registration, JWT authentication.
    * /curriculum - Official Cameroon syllabus progressions & class library.
    * /ai         - AI Tutor endpoints with Gemini LLM integration.
    * /health     - Health checks and system connectivity diagnostics.
=============================================================================
"""

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse, HTMLResponse
import os

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


@app.get("/apk")
@app.get("/download/app.apk")
def download_app_apk():
    apk_path = os.path.abspath(r"d:\StudyProgress\mobile\build\app\outputs\flutter-apk\app-debug.apk")
    if os.path.exists(apk_path):
        return FileResponse(apk_path, media_type="application/vnd.android.package-archive", filename="kivora-study.apk")
    return JSONResponse(status_code=404, content={"detail": "APK not built yet"})


@app.get("/download", response_class=HTMLResponse)
def download_page():
    return """<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kivora - Téléchargement APK</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #FAF9FE 0%, #EDE7F8 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            color: #0F172A;
        }
        .card {
            background: white;
            max-width: 440px;
            width: 100%;
            border-radius: 24px;
            padding: 32px 24px;
            box-shadow: 0 20px 40px rgba(38, 20, 94, 0.08);
            text-align: center;
            border: 1px solid #E2E8F0;
        }
        .badge {
            display: inline-block;
            background: #DCFCE7;
            color: #15803D;
            padding: 6px 14px;
            border-radius: 99px;
            font-size: 13px;
            font-weight: 700;
            margin-bottom: 16px;
        }
        h1 {
            font-size: 26px;
            font-weight: 800;
            color: #26145E;
            margin-bottom: 6px;
        }
        p.sub {
            font-size: 14px;
            color: #64748B;
            margin-bottom: 24px;
        }
        .btn {
            display: block;
            background: #26145E;
            color: white;
            text-decoration: none;
            padding: 16px 20px;
            border-radius: 14px;
            font-size: 16px;
            font-weight: 700;
            box-shadow: 0 10px 20px rgba(38, 20, 94, 0.25);
            transition: transform 0.15s ease;
        }
        .btn:hover {
            transform: translateY(-2px);
        }
        .instructions {
            margin-top: 24px;
            text-align: left;
            background: #F8FAFC;
            padding: 16px;
            border-radius: 14px;
            border: 1px solid #E2E8F0;
        }
        .instructions h3 {
            font-size: 13px;
            color: #334155;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .instructions ol {
            padding-left: 20px;
            font-size: 13.5px;
            color: #475569;
            line-height: 1.6;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="badge">● Serveur Backend en ligne</div>
        <h1>Kivora Mobile</h1>
        <p class="sub">Mise à jour avec résilience réseau & sélection de serveur</p>
        <a class="btn" href="/download/app.apk">📥 Télécharger Kivora APK</a>
        <div class="instructions">
            <h3>Instructions rapides :</h3>
            <ol>
                <li>Appuyez sur le bouton <b>Télécharger</b> ci-dessus.</li>
                <li>Une fois le téléchargement terminé, ouvrez le fichier <code>kivora-study.apk</code>.</li>
                <li>Appuyez sur <b>Installer</b> (ou <i>Mettre à jour</i>).</li>
                <li>Ouvrez l'application : elle se connectera automatiquement !</li>
            </ol>
        </div>
    </div>
</body>
</html>
"""


@app.exception_handler(Exception)
async def _unhandled_exception_handler(_request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=500, content={"detail": str(exc)})

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(curriculum.router)
app.include_router(ai.router)
