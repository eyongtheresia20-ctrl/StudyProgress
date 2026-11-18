import json

import logging

import re

from typing import Any, Optional

logger = logging.getLogger(__name__)

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, UploadFile

from pymysql.connections import Connection

from app.database import get_db

from app.routers.curriculum import record_student_topic_progress

from app.schemas import (

    AiAskRequest,

    AiTranslateRequest,

    AiTranslateOut,

    AiHistoryItemOut,

    AiResponseOut,

    AiTopicActionRequest,

    AiTranscribeOut,

    NoteDiagram,

    QuizQuestion,

    SimulationData,

)

from app.services.ai_service import (

    GeminiStudyAssistant,

    _build_fallback_simulation,

    _enforce_personalized_greeting,

    _is_visual_learner,

    extract_optional_simulation,

)

from app.services.auth_service import get_current_user

router = APIRouter(prefix="/ai", tags=["ai_tutor"])

_SUMMARY_CACHE: dict[str, Any] = {}

_QUIZ_CACHE: dict[str, Any] = {}

_TRANSLATE_CACHE: dict[str, str] = {}

_MIME_BY_EXT: dict[str, str] = {

    ".png": "image/png",

    ".jpg": "image/jpeg",

    ".jpeg": "image/jpeg",

    ".webp": "image/webp",

    ".gif": "image/gif",

    ".mp3": "audio/mp3",

    ".wav": "audio/wav",

    ".m4a": "audio/mp4",

    ".aac": "audio/aac",

    ".ogg": "audio/ogg",

    ".webm": "audio/webm",

}

def _resolve_mime_type(upload: UploadFile) -> str:

    content_type = (upload.content_type or "").strip().lower()

    if content_type.startswith(("image/", "audio/")):

        return content_type.split(";")[0].strip()

    fname = (upload.filename or "").lower()

    for ext, mime in _MIME_BY_EXT.items():

        if fname.endswith(ext):

            return mime

    return "application/octet-stream"

def get_ai_assistant() -> GeminiStudyAssistant:

    return GeminiStudyAssistant()

def _resolve_topic_context(

    db: Connection,

    progression_id: Optional[int],

    subject_name: Optional[str],

    topic_title: Optional[str],

) -> Optional[dict]:

    if progression_id:

        with db.cursor() as cursor:

            cursor.execute(

                "SELECT * FROM official_progressions WHERE id = %s",

                (progression_id,),

            )

            row = cursor.fetchone()

        if not row:

            raise HTTPException(status_code=404, detail="Topic progression not found")

        return row

    if subject_name or topic_title:

        return {

            "subject_name": subject_name or "General Study",

            "topic_title": topic_title or subject_name or "Topic Study",

            "subtopics": "Student-selected independent study topic",

            "start_date": "",

            "end_date": "",

        }

    return None

def _fetch_student_ctx(db: Connection, user_id: int) -> Optional[dict]:

    with db.cursor() as cursor:

        cursor.execute(

            """

            SELECT u.full_name, sp.hobbies_json, sp.learning_style,

                   s.name AS subsystem_name, c.name AS class_name

            FROM users u

            LEFT JOIN student_profiles sp ON sp.user_id = u.id

            LEFT JOIN subsystems s ON s.id = sp.subsystem_id

            LEFT JOIN classes c ON c.id = sp.class_id

            WHERE u.id = %s

            """,

            (user_id,),

        )

        row = cursor.fetchone()

    if not row:

        return None

    try:

        hobbies = ", ".join(json.loads(row.get("hobbies_json") or "[]"))

    except Exception:

        hobbies = ""

    full_name = (row.get("full_name") or "Student").strip()

    first_name = full_name.split()[0] if full_name else "Student"

    return {

        "student_name": full_name,

        "first_name": first_name,

        "subsystem_name": row.get("subsystem_name"),

        "class_name": row.get("class_name"),

        "hobbies": hobbies,

        "learning_style": row.get("learning_style"),

    }

_RICH_MARKER = "\n\n<!--KIVORA_RICH_V1:"

_RICH_END = "-->"

def _pack_rich_response(

    content: str,

    sources: Optional[list[dict[str, str]]] = None,

    diagrams: Optional[list[NoteDiagram]] = None,

    simulation: Optional[SimulationData] = None,

    quiz: Optional[list[QuizQuestion]] = None,

    score_summary: Optional[str] = None,

    subject_name: Optional[str] = None,

    topic_title: Optional[str] = None,

) -> str:

    meta: dict = {}

    if subject_name:

        meta["subject_name"] = subject_name

    if topic_title:

        meta["topic_title"] = topic_title

    if sources:

        meta["sources"] = sources

    if diagrams:

        meta["diagrams"] = [d.model_dump() for d in diagrams]

    if simulation is not None:

        meta["simulation"] = simulation.model_dump()

    if quiz:

        meta["quiz"] = [q.model_dump() for q in quiz]

    if score_summary:

        meta["score_summary"] = score_summary

    if not meta:

        return content

    return f"{content}{_RICH_MARKER}{json.dumps(meta, ensure_ascii=False)}{_RICH_END}"

def _unpack_rich_response(raw_response: str) -> tuple[str, dict]:

    text = (raw_response or "").strip()

    idx = text.rfind(_RICH_MARKER)

    if idx == -1:

        return text, {}

    marker_len = len(_RICH_MARKER)

    end_idx = text.rfind(_RICH_END)

    clean_text = text[:idx].rstrip()

    if end_idx == -1 or end_idx <= idx:

        return clean_text, {}

    json_str = text[idx + marker_len : end_idx]

    try:

        meta = json.loads(json_str)

        return clean_text, meta if isinstance(meta, dict) else {}

    except Exception:

        return clean_text, {}

def _save_interaction(

    db: Connection,

    user_id: int,

    progression_id: Optional[int],

    interaction_type: str,

    prompt: str,

    response: str,

) -> None:

    try:

        with db.cursor() as cursor:

            cursor.execute(

                """

                INSERT INTO ai_interactions (user_id, progression_id, interaction_type, prompt, response)

                VALUES (%s, %s, %s, %s, %s)

                """,

                (user_id, progression_id, interaction_type, prompt, response),

            )

        db.commit()

    except Exception as exc:

        logger.warning(f"Failed to save AI interaction: {exc}")

def _fetch_recent_conversation(

    db: Connection,

    user_id: int,

    progression_id: Optional[int] = None,

    limit: int = 4,

) -> list[dict[str, str]]:

    history: list[dict[str, str]] = []

    try:

        with db.cursor() as cursor:

            if progression_id:

                cursor.execute(

                    """

                    SELECT prompt, response FROM ai_interactions

                    WHERE user_id = %s AND progression_id = %s

                    ORDER BY id DESC LIMIT %s

                    """,

                    (user_id, progression_id, limit),

                )

            else:

                cursor.execute(

                    """

                    SELECT prompt, response FROM ai_interactions

                    WHERE user_id = %s AND progression_id IS NULL

                    ORDER BY id DESC LIMIT %s

                    """,

                    (user_id, limit),

                )

            rows = cursor.fetchall()

        for r in reversed(rows):

            p = (r.get("prompt") or "").strip()

            resp_text, _ = _unpack_rich_response(r.get("response") or "")

            if p:

                history.append({"role": "user", "text": p[:300]})

            if resp_text:

                history.append({"role": "assistant", "text": resp_text[:400]})

    except Exception:

        history = []

    return history

def _maybe_build_ask_simulation(

    question_text: str,

    topic_ctx: Optional[dict],

    student_ctx: Optional[dict],

):

    q = (question_text or "").strip().lower()

    wants_sim = any(

        k in q

        for k in (

            "explain",

            "how",

            "why",

            "simulat",

            "video",

            "diagram",

            "draw",

            "visual",

            "solve",

            "calculate",

            "what is",

            "comment",

            "pourquoi",

            "explique",

        )

    )

    if not (wants_sim or (_is_visual_learner(student_ctx) and len(q) >= 12)):

        return None

    subj = str((topic_ctx or {}).get("subject_name") or "")

    topic = str((topic_ctx or {}).get("topic_title") or question_text or "Topic")

    hobbies = str((student_ctx or {}).get("hobbies") or "everyday life")

    style = str((student_ctx or {}).get("learning_style") or "visual_simulations")

    return _build_fallback_simulation(subj, topic, hobbies, style)

def _apply_lang(student_ctx: Optional[dict], x_app_language: Optional[str]) -> dict:

    ctx = dict(student_ctx or {})

    if x_app_language and x_app_language.strip().lower() in ("en", "fr"):

        ctx["preferred_language"] = x_app_language.strip().lower()

    elif "french" in str(ctx.get("subsystem_name") or "").lower():

        ctx["preferred_language"] = "fr"

    else:

        ctx.setdefault("preferred_language", "en")

    return ctx

@router.post("/ask", response_model=AiResponseOut)

def ask_ai_tutor(

    payload: AiAskRequest,

    x_app_language: Optional[str] = Header(default=None, alias="X-App-Language"),

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

    assistant: GeminiStudyAssistant = Depends(get_ai_assistant),

) -> AiResponseOut:

    """Ask the AI tutor a question personalized to the student's profile and chosen topic."""

    user_id = int(current_user["id"])

    topic_ctx = _resolve_topic_context(

        db, payload.progression_id, payload.subject_name, payload.topic_title

    )

    student_ctx = _apply_lang(_fetch_student_ctx(db, user_id), x_app_language)

    history = _fetch_recent_conversation(db, user_id, progression_id=payload.progression_id, limit=4) if payload.progression_id else []

    effective_q = payload.question.strip() or ("Bonjour !" if (x_app_language or "").startswith("fr") else "Hello!")

    answer, model_used = assistant.ask_tutor(

        effective_q, topic_ctx, student_ctx, conversation_history=history

    )

    answer, simulation=None(answer)

    simulation=None

    _save_interaction(

        db,

        user_id,

        payload.progression_id,

        "chat",

        effective_q,

        _pack_rich_response(answer, simulation=None),

    )

    prog_updated = record_student_topic_progress(

        db=db,

        user_id=user_id,

        progression_id=payload.progression_id,

        status="in_progress",

        understanding_level="partial",

    )

    return AiResponseOut(

        interaction_type="chat",

        content=answer,

        model_used=model_used,

        simulation=None,

        progress_updated=prog_updated,

    )

@router.post("/summary", response_model=AiResponseOut)

def summarize_topic(

    payload: AiTopicActionRequest,

    x_app_language: Optional[str] = Header(default=None, alias="X-App-Language"),

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

    assistant: GeminiStudyAssistant = Depends(get_ai_assistant),

) -> AiResponseOut:

    """Generate teacher-style verified notes, diagrams, AI animated video explainer, and clickable sources."""

    user_id = int(current_user["id"])

    topic_ctx = _resolve_topic_context(

        db, payload.progression_id, payload.subject_name, payload.topic_title

    )

    if not topic_ctx:

        raise HTTPException(

            status_code=400, detail="Provide progression_id or topic_title"

        )

    student_ctx = _apply_lang(_fetch_student_ctx(db, user_id), x_app_language)

    req_lang = (student_ctx or {}).get("preferred_language") or (x_app_language or "en").strip().lower()

    cache_key = f"{user_id}|{payload.progression_id}|{str(topic_ctx.get('topic_title','')).strip().lower()}|{req_lang}"

    if cache_key in _SUMMARY_CACHE:

        return _SUMMARY_CACHE[cache_key]

    summary, model_used, sources, diagrams, _ = assistant.summarize_topic(

        topic_ctx, student_ctx

    )

    simulation=None

    _save_interaction(

        db,

        user_id,

        payload.progression_id,

        "summary",

        topic_ctx["topic_title"],

        _pack_rich_response(

            summary,

            sources=sources,

            diagrams=diagrams,

            simulation=None,

        ),

    )

    prog_updated = record_student_topic_progress(

        db=db,

        user_id=user_id,

        progression_id=payload.progression_id,

        status="in_progress",

        understanding_level="partial",

    )

    result = AiResponseOut(

        interaction_type="summary",

        content=summary,

        model_used=model_used,

        sources=sources,

        diagrams=diagrams,

        simulation=None,

        progress_updated=prog_updated,

    )

    _SUMMARY_CACHE[cache_key] = result

    return result

@router.post("/quiz", response_model=AiResponseOut)

def generate_quiz(

    payload: AiTopicActionRequest,

    x_app_language: Optional[str] = Header(default=None, alias="X-App-Language"),

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

    assistant: GeminiStudyAssistant = Depends(get_ai_assistant),

) -> AiResponseOut:

    """Generate a mixed MCQ, short-answer, and essay quiz tailored to the student."""

    user_id = int(current_user["id"])

    topic_ctx = _resolve_topic_context(

        db, payload.progression_id, payload.subject_name, payload.topic_title

    )

    if not topic_ctx:

        raise HTTPException(

            status_code=400, detail="Provide progression_id or topic_title"

        )

    student_ctx = _apply_lang(_fetch_student_ctx(db, user_id), x_app_language)

    effective_lang = str((student_ctx or {}).get("preferred_language") or "en").strip().lower()

    cache_key = f"{user_id}|{payload.progression_id}|{str(topic_ctx.get('topic_title','')).strip().lower()}|{effective_lang}"

    if cache_key in _QUIZ_CACHE:

        return _QUIZ_CACHE[cache_key]

    summary_text, questions, model_used = assistant.generate_quiz(

        topic_ctx, student_ctx, num_questions=payload.num_questions

    )

    _save_interaction(

        db,

        user_id,

        payload.progression_id,

        "quiz",

        f"Quiz ({len(questions)}Q): {topic_ctx['topic_title']}",

        json.dumps([q.model_dump() for q in questions]),

    )

    prog_updated = record_student_topic_progress(

        db=db,

        user_id=user_id,

        progression_id=payload.progression_id,

        status="in_progress",

        understanding_level="partial",

    )

    result = AiResponseOut(

        interaction_type="quiz",

        content=summary_text,

        model_used=model_used,

        quiz=questions,

        progress_updated=prog_updated,

    )

    _QUIZ_CACHE[cache_key] = result

    return result

@router.post("/quiz/grade", response_model=AiResponseOut)

async def grade_quiz_submission(

    progression_id: Optional[int] = Form(None),

    subject_name: Optional[str] = Form(None),

    topic_title: Optional[str] = Form(None),

    quiz_json: str = Form("[]"),

    answers_json: str = Form("{}"),

    note: str = Form(""),

    files: list[UploadFile] = File(default=[]),

    x_app_language: Optional[str] = Header(default=None, alias="X-App-Language"),

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

    assistant: GeminiStudyAssistant = Depends(get_ai_assistant),

) -> AiResponseOut:

    """Inspect handwritten paper photos and/or typed quiz answers, explain why right/wrong, propose simulations/videos, and evolve mastery progress."""

    user_id = int(current_user["id"])

    topic_ctx = _resolve_topic_context(db, progression_id, subject_name, topic_title)

    student_ctx = _apply_lang(_fetch_student_ctx(db, user_id), x_app_language)

    try:

        raw_quiz = json.loads(quiz_json or "[]")

        quiz_items = [QuizQuestion(**item) for item in raw_quiz if isinstance(item, dict)]

    except Exception:

        quiz_items = []

    try:

        typed_answers = json.loads(answers_json or "{}")

        if not isinstance(typed_answers, dict):

            typed_answers = {}

    except Exception:

        typed_answers = {}

    attachments: list[tuple[bytes, str, str]] = []

    img_tags: list[str] = []

    for upload in files:

        raw = await upload.read()

        if not raw:

            continue

        mime = _resolve_mime_type(upload)

        if not mime.startswith(("image/", "audio/")):

            raise HTTPException(

                status_code=400,

                detail=f"Unsupported file '{upload.filename}'. Upload photos of your paper or audio.",

            )

        fname = upload.filename or "paper_page.png"

        attachments.append((raw, mime, fname))

        img_tags.append(f"[Paper: {fname}]")

    if not attachments and not typed_answers and not note.strip():

        raise HTTPException(

            status_code=400,

            detail="Answer at least one question or upload a photo of your handwritten paper.",

        )

    (

        feedback,

        score_summary,

        simulation,

        video_suggestions,

        score_percent,

        weak_concepts,

        model_used,

    ) = assistant.grade_quiz_submission(

        topic_context=topic_ctx,

        student_context=student_ctx,

        quiz_items=quiz_items,

        typed_answers=typed_answers,

        student_note=note.strip(),

        paper_attachments=attachments,

    )

    if score_percent >= 70:

        next_status, next_level = "understood", "full"

    elif score_percent >= 40:

        next_status, next_level = "in_progress", "partial"

    else:

        next_status, next_level = "needs_revision", "none"

    prog_updated = record_student_topic_progress(

        db=db,

        user_id=user_id,

        progression_id=progression_id,

        status=next_status,

        understanding_level=next_level,

        quiz_score=score_percent,

        weakness_notes=weak_concepts or None,

        preserve_understood=False,

    )

    topic_label = (topic_ctx or {}).get("topic_title") or topic_title or "Quiz Check"

    prompt_tag = " ".join([f"Quiz Grade ({score_summary}): {topic_label}", *img_tags]).strip()

    _save_interaction(

        db,

        user_id,

        progression_id,

        "simulation",

        prompt_tag,

        _pack_rich_response(

            feedback,

            simulation=None,

            quiz=quiz_items or None,

            score_summary=score_summary,

        ),

    )

    return AiResponseOut(

        interaction_type="simulation",

        content=feedback,

        model_used=model_used,

        quiz=quiz_items or None,

        video_suggestions=video_suggestions,

        simulation=None,

        score_summary=score_summary,

        progress_updated=prog_updated,

    )

@router.post("/ask-multimodal", response_model=AiResponseOut)

async def ask_ai_tutor_multimodal(

    question: str = Form(""),

    progression_id: Optional[int] = Form(None),

    subject_name: Optional[str] = Form(None),

    topic_title: Optional[str] = Form(None),

    files: list[UploadFile] = File(default=[]),

    x_app_language: Optional[str] = Header(default=None, alias="X-App-Language"),

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

    assistant: GeminiStudyAssistant = Depends(get_ai_assistant),

) -> AiResponseOut:

    """Ask the AI tutor with optional picture(s) and/or audio recording attached."""

    user_id = int(current_user["id"])

    topic_ctx = _resolve_topic_context(db, progression_id, subject_name, topic_title)

    student_ctx = _apply_lang(_fetch_student_ctx(db, user_id), x_app_language)

    attachments: list[tuple[bytes, str, str]] = []

    tags: list[str] = []

    for upload in files:

        raw = await upload.read()

        if not raw:

            continue

        mime = _resolve_mime_type(upload)

        if not mime.startswith(("image/", "audio/")):

            raise HTTPException(

                status_code=400,

                detail=f"Unsupported media file '{upload.filename}'. Upload images or audio.",

            )

        fname = upload.filename or ("photo.png" if mime.startswith("image/") else "audio.webm")

        attachments.append((raw, mime, fname))

        tags.append(f"[{'Image' if mime.startswith('image/') else 'Audio'}: {fname}]")

    clean_q = question.strip()

    if not clean_q and not attachments:

        raise HTTPException(

            status_code=400,

            detail="Please enter a question or attach an image or audio clip.",

        )

    history = _fetch_recent_conversation(db, user_id, progression_id=progression_id, limit=4) if progression_id else []

    answer, model_used = assistant.ask_tutor_multimodal(

        question=clean_q,

        topic_context=topic_ctx,

        student_context=student_ctx,

        attachments=attachments,

        conversation_history=history,

    )

    answer, simulation=None(answer)

    # Only build simulation if user explicitly asked for one

    q_lower = clean_q.lower()

    if simulation is None and any(w in q_lower for w in ("simul", "animat", "video")):

        simulation=None(clean_q or "visual work analysis", topic_ctx, student_ctx)

    saved_prompt = " ".join([*tags, clean_q]).strip() or "[Media question]"

    _save_interaction(

        db,

        user_id,

        progression_id,

        "chat",

        saved_prompt,

        _pack_rich_response(answer, simulation=None),

    )

    prog_updated = record_student_topic_progress(

        db=db,

        user_id=user_id,

        progression_id=progression_id,

        status="in_progress",

        understanding_level="partial",

    )

    return AiResponseOut(

        interaction_type="chat",

        content=answer,

        model_used=model_used,

        simulation=None,

        progress_updated=prog_updated,

    )

@router.get("/history", response_model=list[AiHistoryItemOut])

def get_ai_history(

    limit: int = 60,

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

) -> list[AiHistoryItemOut]:

    """Return the authenticated student's AI search & chat history, newest first."""

    safe_limit = max(1, min(limit, 200))

    user_id = int(current_user["id"])

    user_full_name = str(current_user.get("full_name") or "Student").strip()

    s_first = user_full_name.split()[0] if user_full_name else "Student"

    with db.cursor() as cursor:

        cursor.execute(

            """

            SELECT ai.id,

                   ai.progression_id,

                   op.subject_name,

                   op.topic_title,

                   ai.interaction_type,

                   ai.prompt,

                   ai.response,

                   ai.created_at

            FROM ai_interactions ai

            LEFT JOIN official_progressions op ON op.id = ai.progression_id

            WHERE ai.user_id = %s

            ORDER BY ai.created_at DESC, ai.id DESC

            LIMIT %s

            """,

            (user_id, safe_limit),

        )

        rows = cursor.fetchall()

    items: list[AiHistoryItemOut] = []

    for r in rows:

        clean_resp, meta = _unpack_rich_response(str(r.get("response") or ""))

        diagrams_raw = meta.get("diagrams") or []

        sim_raw = None

        quiz_raw = meta.get("quiz")

        items.append(

            AiHistoryItemOut(

                id=r["id"],

                progression_id=r.get("progression_id"),

                subject_name=r.get("subject_name") or meta.get("subject_name"),

                topic_title=r.get("topic_title") or meta.get("topic_title"),

                interaction_type=r["interaction_type"],

                prompt=r["prompt"],

                response=clean_resp,

                sources=meta.get("sources") or [],

                diagrams=[

                    NoteDiagram(**d) for d in diagrams_raw if isinstance(d, dict)

                ],

                simulation=(

                    SimulationData(**sim_raw) if isinstance(sim_raw, dict) else None

                ),

                quiz=(

                    [QuizQuestion(**q) for q in quiz_raw if isinstance(q, dict)]

                    if isinstance(quiz_raw, list)

                    else None

                ),

                score_summary=meta.get("score_summary"),

                created_at=r["created_at"],

            )

        )

    return items

@router.post("/transcribe", response_model=AiTranscribeOut)

async def transcribe_student_audio(

    file: UploadFile = File(...),

    language: str = Form("en"),

    current_user: dict = Depends(get_current_user),

    assistant: GeminiStudyAssistant = Depends(get_ai_assistant),

) -> AiTranscribeOut:

    """Transcribe a student's voice recording or audio clip into accurate text."""

    raw = await file.read()

    if not raw:

        raise HTTPException(status_code=400, detail="Audio file is empty.")

    mime = _resolve_mime_type(file)

    if not mime.startswith("audio/") and mime != "application/octet-stream":

        raise HTTPException(

            status_code=400,

            detail=f"Unsupported audio format '{file.filename}'.",

        )

    if mime == "application/octet-stream":

        mime = "audio/webm"

    text, model_used = assistant.transcribe_audio(raw, mime, language=language)

    return AiTranscribeOut(text=text, model_used=model_used)

@router.post("/translate", response_model=AiTranslateOut)

def translate_text(

    payload: AiTranslateRequest,

    current_user: dict = Depends(get_current_user),

    assistant: GeminiStudyAssistant = Depends(get_ai_assistant),

) -> AiTranslateOut:

    """Rapidly translates educational content between French and English with instant caching."""

    clean_text = (payload.text or "").strip()

    key = f"{hash(clean_text)}_{payload.target_language.strip().lower()}"

    if key in _TRANSLATE_CACHE:

        return AiTranslateOut(

            translated_text=_TRANSLATE_CACHE[key],

            target_language=payload.target_language,

            model_used="cache",

        )

    translated, model = assistant.translate_text(payload.text, payload.target_language)

    _TRANSLATE_CACHE[key] = translated

    return AiTranslateOut(

        translated_text=translated,

        target_language=payload.target_language,

        model_used=model,

    )

@router.delete("/history/{interaction_id}")

def delete_ai_history_item(

    interaction_id: int,

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

):

    """Delete a single AI interaction from history."""

    user_id = int(current_user["id"])

    with db.cursor() as cursor:

        cursor.execute(

            "DELETE FROM ai_interactions WHERE id = %s AND user_id = %s",

            (interaction_id, user_id),

        )

        db.commit()

    return {"status": "ok", "deleted_id": interaction_id}

@router.delete("/history")

def clear_all_ai_history(

    current_user: dict = Depends(get_current_user),

    db: Connection = Depends(get_db),

):

    """Clear all AI search and chat history for the authenticated student."""

    user_id = int(current_user["id"])

    with db.cursor() as cursor:

        cursor.execute(

            "DELETE FROM ai_interactions WHERE user_id = %s",

            (user_id,),

        )

        db.commit()

    return {"status": "ok", "cleared": True}

