from collections import Counter
import csv
import io
import json
import os
import re
import zipfile
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import PlainTextResponse
from pymysql.connections import Connection

from app.database import get_db
from app.schemas import (
    AdminDashboardOut,
    AdminUserCreate,
    AdminUserOut,
    AdminUserStatusUpdate,
    BackgroundDigestOut,
    ClassOut,
    ProgressionCreate,
    ProgressionOut,
    ProgressionUploadResult,
    QuestionnaireSubmit,
    StudentHomeOut,
    StudentProfileOut,
    SubsystemOut,
    TopicProgressUpdateRequest,
    UserOut,
)
from app.services.auth_service import get_current_user, require_admin

router = APIRouter(prefix="/curriculum", tags=["curriculum"])


def _loads_list(raw: str | None) -> list[str]:
    if not raw:
        return []
    try:
        val = json.loads(raw)
        return [str(x) for x in val] if isinstance(val, list) else []
    except Exception:
        return []


def _parse_date_flexible(raw: str) -> date:
    text = str(raw or "").strip()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%Y/%m/%d"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"Unrecognized date format '{text}' (use YYYY-MM-DD)")


def _fetch_profile(db: Connection, user_id: int) -> StudentProfileOut:
    with db.cursor() as cursor:
        cursor.execute(
            """
            SELECT sp.*,
                   s.name AS subsystem_name,
                   c.name AS class_name
            FROM student_profiles sp
            LEFT JOIN subsystems s ON s.id = sp.subsystem_id
            LEFT JOIN classes c ON c.id = sp.class_id
            WHERE sp.user_id = %s
            """,
            (user_id,),
        )
        row = cursor.fetchone()
    if not row:
        return StudentProfileOut(user_id=user_id)
    return StudentProfileOut(
        user_id=int(row["user_id"]),
        subsystem_id=row["subsystem_id"],
        subsystem_name=row["subsystem_name"],
        class_id=row["class_id"],
        class_name=row["class_name"],
        age=row.get("age"),
        questionnaire_completed=bool(row["questionnaire_completed"]),
        favourite_subject=row.get("favourite_subject"),
        difficult_subjects=_loads_list(row["difficult_subjects_json"]),
        difficulty_reason=row.get("difficulty_reason"),
        hobbies=_loads_list(row["hobbies_json"]),
        activity_style=row.get("activity_style") or "both",
        learning_style=row["learning_style"] or "practical_examples",
        fallback_preference=row.get("fallback_preference") or "another_example",
        exercise_preference=row["exercise_preference"] or "short_quizzes",
        preferred_study_period=row.get("preferred_study_period") or "evening",
        academic_goal=row["academic_goal"],
        daily_goal_minutes=int(row["daily_goal_minutes"] or 60),
        reminder_hour=int(row["reminder_hour"] or 18),
        reminder_minute=int(row["reminder_minute"] or 0),
    )


def _fetch_student_topics(
    db: Connection,
    user_id: int,
    subsystem_id: Optional[int],
    class_id: Optional[int],
) -> list[ProgressionOut]:
    if not subsystem_id or not class_id:
        return []
    with db.cursor() as cursor:
        cursor.execute(
            """
            SELECT op.*,
                   s.name AS subsystem_name,
                   c.name AS class_name,
                   COALESCE(stp.status, 'not_started') AS student_status,
                   COALESCE(stp.understanding_level, 'none') AS understanding_level
            FROM official_progressions op
            INNER JOIN subsystems s ON s.id = op.subsystem_id
            INNER JOIN classes c ON c.id = op.class_id
            LEFT JOIN student_topic_progress stp
              ON stp.progression_id = op.id AND stp.user_id = %s
            WHERE op.subsystem_id = %s AND op.class_id = %s
            ORDER BY op.week_number ASC, op.start_date ASC, op.id ASC
            """,
            (user_id, subsystem_id, class_id),
        )
        rows = cursor.fetchall()
    class_subjs = {s.lower() for s in _fetch_class_subjects(db, subsystem_id, class_id)}
    clean_rows: list[dict] = []
    seen: set[str] = set()
    per_subj: dict[str, int] = {}
    for r in rows:
        cleaned_subj = _clean_subject_name(r.get("subject_name") or "")
        r["subject_name"] = cleaned_subj
        low_subj = cleaned_subj.lower()
        if class_subjs and low_subj not in class_subjs:
            continue
        tt = (r.get("topic_title") or "").strip().lower()
        key = f"{low_subj}::{tt}"
        if key in seen:
            continue
        seen.add(key)
        c = per_subj.get(low_subj, 0)
        if c >= 12:
            continue
        per_subj[low_subj] = c + 1
        clean_rows.append(r)
    return [ProgressionOut(**r) for r in clean_rows]


def _build_digest_for_user(db: Connection, user_id: int) -> BackgroundDigestOut:
    profile = _fetch_profile(db, user_id)
    all_topics = _fetch_student_topics(
        db, user_id, profile.subsystem_id, profile.class_id
    )
    today = date.today()
    weekday = today.weekday()  # 0=Mon, 1=Tue, 2=Wed, 3=Thu, 4=Fri, 5=Sat, 6=Sun
    is_sunday = weekday == 6
    is_saturday = weekday == 5

    # On Sunday, preview the coming week (Mon..Sun); otherwise the current week.
    ref_day = today + timedelta(days=1) if is_sunday else today
    weekly_topics = _select_this_week_topics(all_topics, ref_day, max_items=25)
    today_topics = _select_today_topics(weekly_topics, today, max_items=4)

    week_num = weekly_topics[0].week_number if weekly_topics else 1
    class_label = profile.class_name or "Your Class"

    # 1. Sunday notification: Weekly roadmap preview + consolidation of past week
    if weekly_topics:
        weekly_summary = "; ".join(
            f"{t.subject_name}: {t.topic_title}"
            for t in weekly_topics[:8]
        )
        sunday_title = f"Sunday Roadmap & Review • Week {week_num} ({class_label})"
        sunday_body = (
            f"Here is what we will study this week (Week {week_num}): {weekly_summary}. "
            f"Review what we covered during the past week and prepare for Monday!"
        )
    else:
        sunday_title = f"Sunday Weekly Briefing • ({class_label})"
        sunday_body = (
            "Review your programme files from the uploaded container and revise any difficult topics with Kivora AI."
        )

    # 2. Daily notification (Monday - Friday study plan, Saturday/Sunday weekend revision)
    day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    day_name = day_names[weekday]

    if is_saturday:
        rev_topics = "; ".join(f"{t.subject_name}: {t.topic_title}" for t in today_topics[:5])
        daily_title = f"Saturday Weekly Revision • Week {week_num} ({class_label})"
        daily_body = (
            f"Saturday Revision Day: Consolidate everything studied Monday through Friday ({rev_topics}). "
            f"Test yourself with an AI Quiz to lock in your understanding!"
        )
    elif is_sunday:
        daily_title = f"Sunday Review & Preparation • Week {week_num} ({class_label})"
        daily_body = (
            f"Finish your weekly revision and check your Week {week_num} syllabus to start Monday strong!"
        )
    elif today_topics:
        daily_summary = ", ".join(f"{t.subject_name}: {t.topic_title}" for t in today_topics)
        daily_title = f"{day_name} Study Plan • Week {week_num} ({class_label})"
        daily_body = f"Today ({day_name}) you will study: {daily_summary} according to your official syllabus. Tap to begin!"
    else:
        daily_title = f"{day_name} Study Reminder • ({class_label})"
        daily_body = f"Open Kivora to study your scheduled topics for {day_name} with your AI tutor."

    return BackgroundDigestOut(
        user_id=user_id,
        is_sunday=is_sunday,
        sunday_title=sunday_title,
        sunday_body=sunday_body,
        daily_title=daily_title,
        daily_body=daily_body,
        today_topics=today_topics,
        weekly_topics=weekly_topics,
    )


@router.get("/subsystems", response_model=list[SubsystemOut])
def list_subsystems(db: Connection = Depends(get_db)) -> list[SubsystemOut]:
    """List Cameroon's two subsystems and all their classes."""
    with db.cursor() as cursor:
        cursor.execute("SELECT * FROM subsystems ORDER BY id ASC")
        subsystems = cursor.fetchall()
        cursor.execute("SELECT * FROM classes ORDER BY subsystem_id ASC, level_order ASC")
        classes = cursor.fetchall()

    by_sub: dict[int, list[ClassOut]] = {}
    for c in classes:
        by_sub.setdefault(int(c["subsystem_id"]), []).append(
            ClassOut(
                id=int(c["id"]),
                subsystem_id=int(c["subsystem_id"]),
                name=c["name"],
                level_order=int(c["level_order"]),
            )
        )

    return [
        SubsystemOut(
            id=int(s["id"]),
            code=s["code"],
            name=s["name"],
            description=s["description"],
            classes=by_sub.get(int(s["id"]), []),
        )
        for s in subsystems
    ]


@router.get("/classes/{class_id}/subjects", response_model=list[str])
def get_class_subjects(class_id: int, db: Connection = Depends(get_db)) -> list[str]:
    """Return distinct subjects offered in this class."""
    with db.cursor() as cursor:
        cursor.execute("SELECT subsystem_id FROM classes WHERE id = %s", (class_id,))
        row = cursor.fetchone()
    subsystem_id = int(row["subsystem_id"]) if row and row.get("subsystem_id") else None
    subjects = _fetch_class_subjects(db, subsystem_id, class_id)
    
    # Filter out vocational trade noise from bulk-imported files
    trade_keywords = [
        "boucherie", "charcuterie", "boulangerie", "pâtisserie", "cuisine", "restaurant",
        "taille", "marqueterie", "patronnage", "puericulture", "usinage", "assainissement",
        "grume", "froid", "climatisation", "installation", "outillage", "techniques inustrielles",
        "sciences et technologies du tertaire", "travaux pratiques de", "travaux de taille"
    ]
    raw_cleaned = [
        s for s in subjects 
        if len(s) > 2 
        and s.lower() not in ("classe de", "section")
        and not any(tk in s.lower() for tk in trade_keywords)
    ]
    
    if subsystem_id == 2:
        core_fr = [
            "Mathématiques", "Physique", "Chimie", "SVTEEHB", "Philosophie", 
            "Français", "Histoire", "Géographie", "Anglais", "Informatique", 
            "Économie", "Comptabilité", "Littérature", "ECM", "Allemand", "Espagnol"
        ]
        # Only include subjects that are actually taught in this class
        res = []
        if raw_cleaned:
            for c in core_fr:
                match = next((s for s in raw_cleaned if c.lower() in s.lower() or s.lower() in c.lower()), None)
                if match and match not in res:
                    res.append(match)
            for s in raw_cleaned:
                if s not in res and not any(c.lower() == s.lower() for c in res):
                    res.append(s)
        if not res:
            res = list(core_fr)
        return res[:22]
    else:
        core_en = [
            "Mathematics", "Physics", "Chemistry", "Biology", "Computer Science", 
            "English Language", "Literature in English", "French", "History", 
            "Geography", "Economics", "Accounting", "Citizenship"
        ]
        res = []
        if raw_cleaned:
            for c in core_en:
                match = next((s for s in raw_cleaned if c.lower() in s.lower() or s.lower() in c.lower()), None)
                if match and match not in res:
                    res.append(match)
            for s in raw_cleaned:
                if s not in res and not any(c.lower() == s.lower() for c in res):
                    res.append(s)
        if not res:
            res = list(core_en)
        return res[:22]


@router.get("/student/profile", response_model=StudentProfileOut)
def get_student_profile(
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> StudentProfileOut:
    """Get the logged-in student's profile & questionnaire answers."""
    return _fetch_profile(db, int(current_user["id"]))


@router.put("/student/questionnaire", response_model=StudentProfileOut)
def save_questionnaire(
    payload: QuestionnaireSubmit,
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> StudentProfileOut:
    """Save or update the student's onboarding questionnaire."""
    user_id = int(current_user["id"])
    with db.cursor() as cursor:
        cursor.execute(
            "SELECT id FROM classes WHERE id = %s AND subsystem_id = %s",
            (payload.class_id, payload.subsystem_id),
        )
        if not cursor.fetchone():
            raise HTTPException(
                status_code=400,
                detail="Selected class does not belong to the selected subsystem",
            )

        if payload.full_name and payload.full_name.strip():
            cursor.execute(
                "UPDATE users SET full_name = %s WHERE id = %s",
                (payload.full_name.strip(), user_id),
            )

        cursor.execute(
            """
            INSERT INTO student_profiles (
              user_id, subsystem_id, class_id, age, questionnaire_completed,
              favourite_subject, difficult_subjects_json, difficulty_reason,
              hobbies_json, activity_style, learning_style, fallback_preference,
              exercise_preference, preferred_study_period, academic_goal,
              daily_goal_minutes, reminder_hour, reminder_minute
            )
            VALUES (%s, %s, %s, %s, 1, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
              subsystem_id = VALUES(subsystem_id),
              class_id = VALUES(class_id),
              age = VALUES(age),
              questionnaire_completed = 1,
              favourite_subject = VALUES(favourite_subject),
              difficult_subjects_json = VALUES(difficult_subjects_json),
              difficulty_reason = VALUES(difficulty_reason),
              hobbies_json = VALUES(hobbies_json),
              activity_style = VALUES(activity_style),
              learning_style = VALUES(learning_style),
              fallback_preference = VALUES(fallback_preference),
              exercise_preference = VALUES(exercise_preference),
              preferred_study_period = VALUES(preferred_study_period),
              academic_goal = VALUES(academic_goal),
              daily_goal_minutes = VALUES(daily_goal_minutes),
              reminder_hour = VALUES(reminder_hour),
              reminder_minute = VALUES(reminder_minute)
            """,
            (
                user_id,
                payload.subsystem_id,
                payload.class_id,
                payload.age,
                payload.favourite_subject,
                json.dumps(payload.difficult_subjects),
                payload.difficulty_reason,
                json.dumps(payload.hobbies),
                payload.activity_style,
                payload.learning_style,
                payload.fallback_preference,
                payload.exercise_preference,
                payload.preferred_study_period,
                payload.academic_goal,
                payload.daily_goal_minutes,
                payload.reminder_hour,
                payload.reminder_minute,
            ),
        )
    return _fetch_profile(db, user_id)


def _clean_subject_name(raw: str) -> str:
    s = re.sub(r"\s+", " ", (raw or "").strip())
    # Strip series / class prefix: 'A - ', 'C - ', 'D - ', 'Classe de - ', 'Classe de 6ème - '
    s = re.sub(r"^(?:[A-Z]{1,4}|classe(?:\s+de(?:\s+[^\-]+)?)?|form\s+\d+|lower\s+sixth|upper\s+sixth)\s*[-–:]\s*", "", s, flags=re.IGNORECASE)
    s = re.sub(r"^(?:all|tous|tout)\s*[-–:]\s*", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\bAdditionnal\b", "Additional", s, flags=re.IGNORECASE)
    s = re.sub(r"\s*\(ID-\d+\)", "", s, flags=re.IGNORECASE)
    s = s.replace("\ufffd", "e")
    s = re.sub(r"math[\w\ufffd]*matiques", "Mathématiques", s, flags=re.IGNORECASE)
    s = re.sub(r"fran[\w\ufffd]*ais", "Français", s, flags=re.IGNORECASE)
    s = re.sub(r"g[\w\ufffd]*ographie", "Géographie", s, flags=re.IGNORECASE)
    s = re.sub(r"[\w\ufffd]*conomie", "Économie", s, flags=re.IGNORECASE)
    s = re.sub(r"electricit[\w\ufffd]*", "Électricité", s, flags=re.IGNORECASE)
    s = re.sub(r"electronique", "Électronique", s, flags=re.IGNORECASE)
    s = re.sub(r"num[\w\ufffd]*rique", "Numérique", s, flags=re.IGNORECASE)
    s = re.sub(r"comptabilit[\w\ufffd]*", "Comptabilité", s, flags=re.IGNORECASE)
    s = re.sub(r"s[\w\ufffd]*courisme", "Secourisme", s, flags=re.IGNORECASE)
    s = re.sub(r"r[\w\ufffd]*frig[\w\ufffd]*ration", "Réfrigération", s, flags=re.IGNORECASE)
    s = re.sub(r"r[\w\ufffd]*daction", "Rédaction", s, flags=re.IGNORECASE)
    s = re.sub(r"proc[\w\ufffd]*d[\w\ufffd]*s", "Procédés", s, flags=re.IGNORECASE)
    s = re.sub(r"l[\ufffd']", "l'", s)
    s = re.sub(r"d[\ufffd']", "d'", s)
    s = s.replace("\ufffd", "e")
    if " - " in s:
        parts = [p.strip() for p in s.split(" - ")]
        if 1 <= len(parts[0].split()) <= 4 and len(parts[0]) <= 32:
            s = parts[0]
    s = re.sub(r"\s+ok\b", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\s*-\s*-\s*", " - ", s)
    s = re.sub(r"\s*[-–:]\s*$", "", s)
    return s.strip()[:95]


def record_student_topic_progress(
    db: Connection,
    user_id: int,
    progression_id: Optional[int],
    status: str,
    understanding_level: str,
    quiz_score: Optional[int] = None,
    weakness_notes: Optional[str] = None,
    preserve_understood: bool = True,
) -> bool:
    """Create or evolve the student's topic mastery state in student_topic_progress."""
    if not progression_id:
        return False
    try:
        with db.cursor() as cursor:
            if preserve_understood:
                cursor.execute(
                    "SELECT status, understanding_level, quiz_score FROM student_topic_progress WHERE user_id = %s AND progression_id = %s",
                    (user_id, progression_id),
                )
                existing = cursor.fetchone()
                if existing and existing.get("status") == "understood" and quiz_score is None:
                    cursor.execute(
                        "UPDATE student_topic_progress SET last_studied_at = NOW() WHERE user_id = %s AND progression_id = %s",
                        (user_id, progression_id),
                    )
                    return True
            cursor.execute(
                """
                INSERT INTO student_topic_progress (
                    user_id, progression_id, status, understanding_level,
                    quiz_score, weakness_notes, last_studied_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, NOW())
                ON DUPLICATE KEY UPDATE
                    status = VALUES(status),
                    understanding_level = VALUES(understanding_level),
                    quiz_score = COALESCE(VALUES(quiz_score), quiz_score),
                    weakness_notes = COALESCE(VALUES(weakness_notes), weakness_notes),
                    last_studied_at = NOW()
                """,
                (
                    user_id,
                    progression_id,
                    status,
                    understanding_level,
                    quiz_score,
                    (weakness_notes or None),
                ),
            )
        return True
    except Exception:
        return False


def _fetch_class_program_topics(
    db: Connection,
    subsystem_id: Optional[int],
    class_id: Optional[int],
    limit: int = 200,
) -> list[ProgressionOut]:
    if not subsystem_id or not class_id:
        return []
    with db.cursor() as cursor:
        cursor.execute(
            """
            SELECT pt.id, pt.subsystem_id, s.name AS subsystem_name,
                   pt.class_id, c.name AS class_name,
                   pt.subject_name, pt.topic_title, pt.subtopics,
                   1 AS week_number, CURDATE() AS start_date, CURDATE() AS end_date,
                   NULL AS study_days,
                   'not_started' AS student_status,
                   'none' AS understanding_level
            FROM program_topics pt
            INNER JOIN subsystems s ON s.id = pt.subsystem_id
            INNER JOIN classes c ON c.id = pt.class_id
            WHERE pt.subsystem_id = %s AND pt.class_id = %s
            ORDER BY pt.subject_name ASC, pt.id ASC
            LIMIT %s
            """,
            (subsystem_id, class_id, limit),
        )
        rows = cursor.fetchall()
    return [ProgressionOut(**r) for r in rows]


def _fetch_class_subjects(
    db: Connection,
    subsystem_id: Optional[int],
    class_id: Optional[int],
) -> list[str]:
    if not subsystem_id or not class_id:
        return []
    with db.cursor() as cursor:
        cursor.execute(
            """
            SELECT DISTINCT subject_name FROM official_progressions
            WHERE subsystem_id = %s AND class_id = %s
            UNION
            SELECT DISTINCT subject_name FROM program_topics
            WHERE subsystem_id = %s AND class_id = %s
            ORDER BY subject_name ASC
            """,
            (subsystem_id, class_id, subsystem_id, class_id),
        )
        rows = cursor.fetchall()
    
    trade_keywords = (
        "boucherie", "charcuterie", "boulangerie", "pâtisserie", "cuisine", "restaurant",
        "taille", "marqueterie", "patronnage", "puericulture", "usinage", "assainissement",
        "grume", "froid", "climatisation", "installation", "outillage", "techniques inustrielles",
        "sciences et technologies du tertaire", "travaux pratiques de", "travaux de taille",
        "classe de", "section"
    )
    raw_subjects: list[str] = []
    seen: set[str] = set()
    for r in rows:
        clean = _clean_subject_name(r.get("subject_name") or "")
        low = clean.lower()
        if len(clean) > 2 and low not in seen and not any(tk in low for tk in trade_keywords):
            seen.add(low)
            raw_subjects.append(clean)
            
    if subsystem_id == 2:
        core_fr = [
            "Mathématiques", "Physique", "Chimie", "SVTEEHB", "Philosophie", 
            "Français", "Histoire", "Géographie", "Anglais", "Informatique", 
            "Économie", "Comptabilité", "Littérature", "ECM", "Allemand", "Espagnol"
        ]
        res = []
        if raw_subjects:
            for c in core_fr:
                match = next((s for s in raw_subjects if c.lower() in s.lower() or s.lower() in c.lower()), None)
                if match and match not in res:
                    res.append(match)
            for s in raw_subjects:
                if s not in res and not any(c.lower() == s.lower() for c in res):
                    res.append(s)
        if not res:
            res = list(core_fr)
        return res[:22]
    else:
        core_en = [
            "Mathematics", "Physics", "Chemistry", "Biology", "Computer Science", 
            "English Language", "Literature in English", "French", "History", 
            "Geography", "Economics", "Accounting", "Citizenship"
        ]
        res = []
        if raw_subjects:
            for c in core_en:
                match = next((s for s in raw_subjects if c.lower() in s.lower() or s.lower() in c.lower()), None)
                if match and match not in res:
                    res.append(match)
            for s in raw_subjects:
                if s not in res and not any(c.lower() == s.lower() for c in res):
                    res.append(s)
        if not res:
            res = list(core_en)
        return res[:22]


def _select_this_week_topics(
    all_topics: list[ProgressionOut],
    today: date,
    max_items: int = 60,
) -> list[ProgressionOut]:
    """Return the complete curriculum progression covering all class subjects across Monday-Friday."""
    if not all_topics:
        return []

    # 1. Determine active school week number
    tight_matches = [
        t for t in all_topics
        if t.start_date <= today and t.end_date >= today
        and (t.end_date - t.start_date).days <= 28
        and t.week_number and t.week_number > 0
    ]
    if tight_matches:
        counts = Counter(t.week_number for t in tight_matches)
        target_week = counts.most_common(1)[0][0]
    else:
        pending = [t for t in all_topics if t.student_status != "understood" and t.week_number and t.week_number > 0]
        target_week = min(t.week_number for t in pending) if pending else 10

    # 2. Group all topics by subject
    by_subject: dict[str, list[ProgressionOut]] = {}
    for t in all_topics:
        s_key = _clean_subject_name(t.subject_name).lower()
        by_subject.setdefault(s_key, []).append(t)

    # 3. For every subject, pick the best matching topic for this week:
    picked: list[ProgressionOut] = []
    for s_key, sub_topics in by_subject.items():
        exact = [t for t in sub_topics if t.week_number == target_week]
        if exact:
            chosen = sorted(exact, key=lambda t: t.id)[0]
        else:
            chosen = min(sub_topics, key=lambda t: (abs((t.week_number or 1) - target_week), t.id))
        picked.append(chosen)

    # 4. Standard secondary school timetable distribution (Monday to Friday, 3-4 subjects per day)
    WEEKDAY_LABELS = [
        "Lundi · Monday",
        "Mardi · Tuesday",
        "Mercredi · Wednesday",
        "Jeudi · Thursday",
        "Vendredi · Friday",
    ]

    status_rank = {"needs_revision": 0, "in_progress": 1, "not_started": 2, "understood": 3}
    picked.sort(key=lambda t: (status_rank.get(t.student_status, 2), _clean_subject_name(t.subject_name)))

    assigned_weekly: list[ProgressionOut] = []
    for idx, t in enumerate(picked[:max_items]):
        day_idx = idx % 5
        assigned_weekly.append(
            t.model_copy(update={
                "study_days": WEEKDAY_LABELS[day_idx],
                "week_number": target_week,
            })
        )
    return assigned_weekly


def _select_today_topics(
    weekly_topics: list[ProgressionOut],
    today: date,
    max_items: int = 4,
) -> list[ProgressionOut]:
    """Select focused topics for today from this week's progression.
    On weekdays (Mon-Fri), selects the exact topics assigned to that specific weekday.
    On weekends (Sat-Sun), focuses on weekly revision of what was studied during Monday-Friday.
    """
    if not weekly_topics:
        return []

    weekday = today.weekday()  # 0=Mon, 1=Tue, 2=Wed, 3=Thu, 4=Fri, 5=Sat, 6=Sun
    # Weekend revision mode (Saturday=5, Sunday=6)
    if weekday in (5, 6):
        # Dedicated revision of everything studied during Monday-Friday
        rev_pool = [
            t.model_copy(update={"study_days": "Samedi & Dimanche (Révision) · Sat & Sun (Revision)"})
            for t in weekly_topics
        ]
        return rev_pool

    # Weekday study mode (Mon=0, Tue=1, Wed=2, Thu=3, Fri=4)
    weekday_keys = ["lundi", "mardi", "mercredi", "jeudi", "vendredi"]
    current_key = weekday_keys[weekday]

    day_topics = [
        t for t in weekly_topics
        if t.study_days and current_key in t.study_days.lower()
    ]
    if not day_topics:
        day_topics = [t for idx, t in enumerate(weekly_topics) if (idx % 5) == weekday]

    return day_topics or weekly_topics[:max_items]


@router.get("/student/home", response_model=StudentHomeOut)
def get_student_home(
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> StudentHomeOut:
    """Return the Student Home dashboard: official today/weekly/full progression + class subjects & topics."""
    user_id = int(current_user["id"])
    profile = _fetch_profile(db, user_id)
    all_topics = _fetch_student_topics(
        db, user_id, profile.subsystem_id, profile.class_id
    )
    class_subjects = _fetch_class_subjects(db, profile.subsystem_id, profile.class_id)
    program_topics = _fetch_class_program_topics(
        db, profile.subsystem_id, profile.class_id, limit=60
    )

    today = date.today()
    weekly_topics = _select_this_week_topics(all_topics, today, max_items=60)
    today_topics = _select_today_topics(weekly_topics, today, max_items=3)
    understood = sum(1 for t in all_topics if t.student_status == "understood")
    needs_rev = sum(1 for t in all_topics if t.student_status == "needs_revision")

    return StudentHomeOut(
        user=UserOut(
            id=user_id,
            full_name=current_user["full_name"],
            email=current_user["email"],
            role=current_user["role"],
            questionnaire_completed=profile.questionnaire_completed,
        ),
        profile=profile,
        today_topics=today_topics,
        weekly_topics=weekly_topics,
        all_topics=all_topics,
        class_subjects=class_subjects,
        program_topics=program_topics,
        understood_count=understood,
        needs_revision_count=needs_rev,
        total_topics_count=len(all_topics),
    )


@router.post("/student/progress", response_model=StudentHomeOut)
def update_student_progress(
    payload: TopicProgressUpdateRequest,
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> StudentHomeOut:
    """Update a student's mastery status on a curriculum topic and return updated home metrics."""
    user_id = int(current_user["id"])
    record_student_topic_progress(
        db=db,
        user_id=user_id,
        progression_id=payload.progression_id,
        status=payload.status,
        understanding_level=payload.understanding_level,
        quiz_score=payload.quiz_score,
        weakness_notes=payload.weakness_notes,
        preserve_understood=False,
    )
    return get_student_home(current_user=current_user, db=db)


@router.get("/student/background-digest", response_model=BackgroundDigestOut)
def get_student_background_digest(
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> BackgroundDigestOut:
    """Authenticated endpoint returning Sunday weekly & daily programme notifications."""
    return _build_digest_for_user(db, int(current_user["id"]))


@router.get("/background-digest/{user_id}", response_model=BackgroundDigestOut)
def get_public_background_digest(
    user_id: int,
    db: Connection = Depends(get_db),
) -> BackgroundDigestOut:
    """Background worker endpoint polled by Workmanager for Sunday & daily notifications."""
    return _build_digest_for_user(db, user_id)


@router.get("/explore/topics")
def explore_topics(
    subject: Optional[str] = Query(default=None),
    q: Optional[str] = Query(default=None),
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> list[ProgressionOut]:
    """List official progression + uploaded program topics for Explore & Learn."""
    profile = _fetch_profile(db, int(current_user["id"]))

    def _query_table(table: str, has_dates: bool) -> list[ProgressionOut]:
        clauses = []
        params: list = []
        if profile.subsystem_id:
            clauses.append("t.subsystem_id = %s")
            params.append(profile.subsystem_id)
        if profile.class_id:
            clauses.append("t.class_id = %s")
            params.append(profile.class_id)
        if subject:
            like_sub = f"%{subject.strip()}%"
            clauses.append("(LOWER(t.subject_name) = LOWER(%s) OR LOWER(t.subject_name) LIKE LOWER(%s))")
            params.extend([subject.strip(), like_sub])
        if q:
            like = f"%{q.strip()}%"
            clauses.append(
                "(t.subject_name LIKE %s OR t.topic_title LIKE %s OR t.subtopics LIKE %s)"
            )
            params.extend([like, like, like])
        where_sql = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        date_cols = (
            "t.week_number, t.start_date, t.end_date, t.study_days"
            if has_dates
            else "1 AS week_number, CURDATE() AS start_date, CURDATE() AS end_date, NULL AS study_days"
        )
        order_sql = "ORDER BY t.subject_name ASC, t.id ASC"
        query_params = list(params)
        if subject:
            order_sql = "ORDER BY CASE WHEN LOWER(t.subject_name) = LOWER(%s) THEN 0 ELSE 1 END, t.subject_name ASC, t.id ASC"
            query_params.append(subject.strip())
        with db.cursor() as cursor:
            cursor.execute(
                f"""
                SELECT t.id, t.subsystem_id, s.name AS subsystem_name,
                       t.class_id, c.name AS class_name,
                       t.subject_name, t.topic_title, t.subtopics,
                       {date_cols}
                FROM {table} t
                INNER JOIN subsystems s ON s.id = t.subsystem_id
                INNER JOIN classes c ON c.id = t.class_id
                WHERE t.subsystem_id = s.id AND t.class_id = c.id
                {where_sql.replace('WHERE ', 'AND ') if where_sql else ''}
                {order_sql}
                LIMIT 500
                """,
                query_params,
            )
            return [ProgressionOut(**r) for r in cursor.fetchall()]

    progs = _query_table("official_progressions", True)
    prog_topics = _query_table("program_topics", False)
    seen = {(p.subject_name.lower(), p.topic_title.lower(), p.class_id) for p in progs}
    combined = list(progs)
    for pt in prog_topics:
        key = (pt.subject_name.lower(), pt.topic_title.lower(), pt.class_id)
        if key not in seen:
            seen.add(key)
            combined.append(pt)
    return combined


def _ensure_folder_logs_table(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS uploaded_folder_logs (
          id INT UNSIGNED NOT NULL AUTO_INCREMENT,
          folder_name VARCHAR(200) NOT NULL,
          files_count INT UNSIGNED NOT NULL DEFAULT 0,
          topics_added INT UNSIGNED NOT NULL DEFAULT 0,
          uploaded_by INT UNSIGNED DEFAULT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        """
    )


@router.get("/admin/dashboard", response_model=AdminDashboardOut)
def get_admin_dashboard(
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> AdminDashboardOut:
    """Return the mobile Admin Dashboard overview and official date-range progressions."""
    with db.cursor() as cursor:
        cursor.execute("SELECT COUNT(*) AS cnt FROM subsystems")
        subsystems_cnt = int(cursor.fetchone()["cnt"])
        cursor.execute("SELECT COUNT(*) AS cnt FROM classes")
        classes_cnt = int(cursor.fetchone()["cnt"])
        cursor.execute("SELECT COUNT(*) AS cnt FROM users WHERE role = 'student'")
        students_cnt = int(cursor.fetchone()["cnt"])
        cursor.execute("SELECT COUNT(*) AS cnt FROM official_progressions")
        prog_cnt = int(cursor.fetchone()["cnt"])
        cursor.execute("SELECT COUNT(*) AS cnt FROM program_topics")
        pt_cnt = int(cursor.fetchone()["cnt"])

        cursor.execute(
            """
            SELECT u.id, u.full_name, u.email, u.role, COALESCE(u.is_active, 1) AS is_active,
                   s.name AS subsystem_name,
                   c.name AS class_name,
                   COALESCE(sp.questionnaire_completed, 0) AS questionnaire_completed
            FROM users u
            LEFT JOIN student_profiles sp ON sp.user_id = u.id
            LEFT JOIN subsystems s ON s.id = sp.subsystem_id
            LEFT JOIN classes c ON c.id = sp.class_id
            WHERE u.role = 'student'
            ORDER BY u.created_at DESC
            LIMIT 60
            """
        )
        recent_students = cursor.fetchall()

        cursor.execute(
            """
            SELECT op.*,
                   s.name AS subsystem_name,
                   c.name AS class_name
            FROM official_progressions op
            INNER JOIN subsystems s ON s.id = op.subsystem_id
            INNER JOIN classes c ON c.id = op.class_id
            ORDER BY op.subsystem_id ASC, op.class_id ASC, op.week_number ASC, op.start_date ASC
            LIMIT 150
            """
        )
        progs = [ProgressionOut(**r) for r in cursor.fetchall()]

        _ensure_folder_logs_table(cursor)
        cursor.execute(
            """
            SELECT folder_name,
                   SUM(files_count) AS files_count,
                   SUM(topics_added) AS topics_added,
                   MAX(created_at) AS last_uploaded_at
            FROM uploaded_folder_logs
            GROUP BY folder_name
            ORDER BY MAX(id) DESC
            LIMIT 25
            """
        )
        raw_folders = cursor.fetchall()
        uploaded_folders = [
            {
                "folder_name": f["folder_name"],
                "files_count": int(f["files_count"] or 0),
                "topics_added": int(f["topics_added"] or 0),
                "last_uploaded_at": (
                    f["last_uploaded_at"].isoformat()
                    if f.get("last_uploaded_at") is not None
                    and hasattr(f["last_uploaded_at"], "isoformat")
                    else str(f.get("last_uploaded_at") or "")
                ),
            }
            for f in raw_folders
        ]

    for st in recent_students:
        st["questionnaire_completed"] = bool(st["questionnaire_completed"])
        st["is_active"] = bool(st.get("is_active", 1))

    return AdminDashboardOut(
        admin=UserOut(
            id=int(admin_user["id"]),
            full_name=admin_user["full_name"],
            email=admin_user["email"],
            role="admin",
            questionnaire_completed=True,
        ),
        subsystems_count=subsystems_cnt,
        classes_count=classes_cnt,
        students_count=students_cnt,
        progressions_count=prog_cnt,
        program_topics_count=pt_cnt,
        recent_students=recent_students,
        progressions=progs,
        uploaded_folders=uploaded_folders,
    )


_CURRICULUM_EXTS = (".csv", ".xlsx", ".xlsm", ".xls", ".json", ".txt")
_STORED_DOC_EXTS = (".pdf", ".doc", ".docx", ".ods")
_UPLOADS_DIR = Path(__file__).resolve().parents[2] / "uploads" / "curriculum"


def _save_uploaded_raw(rel_path: str, raw_bytes: bytes) -> None:
    safe_rel = "/".join(
        re.sub(r"[^a-zA-Z0-9._ -]", "_", seg)
        for seg in rel_path.replace("\\", "/").split("/")
        if seg and seg not in (".", "..")
    )
    if not safe_rel:
        safe_rel = f"upload_{int(datetime.now().timestamp())}"
    dest = _UPLOADS_DIR / safe_rel
    os.makedirs(dest.parent, exist_ok=True)
    dest.write_bytes(raw_bytes)


async def _expand_uploaded_files(
    files: list[UploadFile],
) -> tuple[list[tuple[str, bytes]], list[str]]:
    """Expand uploaded files and .zip archives into a flat list of (path, bytes)."""
    expanded: list[tuple[str, bytes]] = []
    errors: list[str] = []
    for file in files:
        raw_bytes = await file.read()
        fname = file.filename or "curriculum.csv"
        lower = fname.lower()
        base = fname.replace("\\", "/").split("/")[-1]
        if base.startswith((".", "~$")):
            continue
        if lower.endswith(".zip"):
            try:
                with zipfile.ZipFile(io.BytesIO(raw_bytes)) as zf:
                    for info in zf.infolist():
                        if info.is_dir():
                            continue
                        entry_name = info.filename
                        entry_base = entry_name.replace("\\", "/").split("/")[-1]
                        if (
                            "__MACOSX" in entry_name
                            or entry_base.startswith((".", "~$"))
                            or not entry_name.lower().endswith(_CURRICULUM_EXTS)
                        ):
                            continue
                        data = zf.read(info)
                        if data:
                            expanded.append((entry_name, data))
            except Exception as exc:
                errors.append(f"{fname}: invalid zip archive ({exc})")
        else:
            expanded.append((fname, raw_bytes))
    return expanded, errors


def _norm_text(s: str) -> str:
    return (
        s.strip()
        .lower()
        .replace("_", " ")
        .replace("-", " ")
        .replace("è", "e")
        .replace("é", "e")
        .replace("ê", "e")
        .replace("à", "a")
    )


_CLASS_ALIASES = {
    "6e": "6eme",
    "6 eme": "6eme",
    "5e": "5eme",
    "5 eme": "5eme",
    "4e": "4eme",
    "4 eme": "4eme",
    "3e": "3eme",
    "3 eme": "3eme",
    "2nde": "seconde",
    "2nd": "seconde",
    "1ere": "premiere",
    "1 ere": "premiere",
    "tle": "terminale",
    "term": "terminale",
}


def _infer_context_from_path(
    filepath: str,
    sub_lookup: dict[str, int],
    class_lookup: dict[tuple[int, str], int],
) -> tuple[Optional[int], Optional[int], str]:
    clean_fp = filepath.replace("\\", "/")
    raw_parts = [p.strip() for p in clean_fp.split("/") if p.strip()]
    base_no_ext = os.path.splitext(raw_parts[-1])[0] if raw_parts else ""

    norm_all = " ".join(_norm_text(p) for p in raw_parts)
    sub_id: Optional[int] = None
    if any(k in norm_all for k in ("english sub", "anglophone", "english")):
        sub_id = sub_lookup.get("en", 1)
    elif any(k in norm_all for k in ("french sub", "francophone", "french", "francais")):
        sub_id = sub_lookup.get("fr", 2)

    cls_id: Optional[int] = None
    matched_cls_label = ""
    candidates = [*raw_parts[:-1], base_no_ext]
    for raw_c in candidates:
        nc = _norm_text(raw_c)
        nc = _CLASS_ALIASES.get(nc, nc)
        # Check exact or prefix/contained class match against all known classes
        for (sid, cname), cid in class_lookup.items():
            if sub_id is not None and sid != sub_id:
                continue
            if nc == cname or re.search(rf"\b{re.escape(cname)}\b", nc):
                cls_id = cid
                sub_id = sid
                matched_cls_label = cname
                break
        if cls_id is not None:
            break

    # Derive subject name from filename (e.g. "Form 1 - Biology" -> "Biology")
    subject_from_name = base_no_ext.strip()
    if matched_cls_label:
        subject_from_name = re.sub(
            rf"(?i)\b{re.escape(matched_cls_label)}\b", "", subject_from_name
        )
    subject_from_name = re.sub(r"^[\s\-_:–—]+|[\s\-_:–—]+$", "", subject_from_name)
    return sub_id, cls_id, subject_from_name[:95]


def _extract_topic_and_subtopics(norm_row: dict[str, str]) -> tuple[str, Optional[str]]:
    topic_keys = (
        "topic",
        "topic_title",
        "topics",
        "chapitre",
        "chapitres",
        "chapter",
        "chapters",
        "lecon",
        "lecons",
        "lesson",
        "lessons",
        "module",
        "modules",
        "title",
        "titre",
        "theme",
        "themes",
        "unite",
        "unit",
        "notions",
        "notion",
        "content",
        "contenu",
        "intitule",
        "competence",
        "competences",
        "objectif",
        "objectifs",
    )
    topic = ""
    used_key = ""
    for k in topic_keys:
        v = norm_row.get(k, "").strip()
        if v:
            topic = v
            used_key = k
            break

    if not topic:
        for k, v in norm_row.items():
            clean_v = v.strip()
            if not clean_v:
                continue
            if any(
                hint in k
                for hint in (
                    "topic",
                    "lesson",
                    "lecon",
                    "chapit",
                    "module",
                    "title",
                    "titre",
                    "theme",
                    "conten",
                    "unit",
                    "notion",
                    "savoir",
                    "activit",
                    "competenc",
                    "objecti",
                )
            ):
                topic = clean_v
                used_key = k
                break

    subtopics = (
        norm_row.get("subtopics")
        or norm_row.get("description")
        or norm_row.get("contenu")
        or norm_row.get("objectifs")
        or norm_row.get("competences")
        or ""
    ).strip()

    skip_meta = {
        "subsystem",
        "subsystem_name",
        "subsystem_code",
        "sous-systeme",
        "sous_systeme",
        "class",
        "class_name",
        "classe",
        "niveau",
        "subject",
        "subject_name",
        "matiere",
        "discipline",
        "week",
        "week_number",
        "semaine",
        "start_date",
        "end_date",
        "date_debut",
        "date_fin",
        "study_days",
        "days",
    }
    if not topic:
        extra_parts: list[str] = []
        for k, v in norm_row.items():
            clean_v = v.strip()
            if not clean_v or k in skip_meta:
                continue
            if _DATE_TOKEN_RE.search(clean_v):
                continue
            if re.fullmatch(r"[\d\s./:-]+", clean_v) or len(clean_v) < 3:
                continue
            if not topic:
                topic = clean_v
                used_key = k
            else:
                extra_parts.append(clean_v)
        if not subtopics and extra_parts:
            subtopics = " · ".join(extra_parts[:3])
    elif not subtopics:
        extra_parts = [
            v.strip()
            for k, v in norm_row.items()
            if k != used_key
            and k not in skip_meta
            and len(v.strip()) >= 3
            and not _DATE_TOKEN_RE.search(v.strip())
            and not re.fullmatch(r"[\d\s./:-]+", v.strip())
        ]
        if extra_parts:
            subtopics = " · ".join(extra_parts[:3])

    # If Chapter + Title/Lesson both exist, combine them cleanly when distinct
    chap = (
        norm_row.get("chapter")
        or norm_row.get("chapitre")
        or norm_row.get("chapter_chapitre")
        or ""
    ).strip()
    if chap and topic and chap.lower() not in topic.lower() and not _DATE_TOKEN_RE.search(chap):
        topic = f"{chap} — {topic}"

    return topic[:195], (subtopics[:1000] if subtopics else None)


_DATE_TOKEN_RE = re.compile(r"\b(\d{1,2}[/-]\d{1,2}[/-]\d{4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})\b")
_BANNER_SUBSTRINGS = (
    "term / trimestre",
    "1er trimestre",
    "2e trimestre",
    "2eme trimestre",
    "3e trimestre",
    "3eme trimestre",
    "period / week",
    "effective date",
    "all terms (full year)",
)


def _is_banner_row(topic: str, raw_row: dict) -> bool:
    low = (topic or "").strip().lower()
    if any(b in low for b in _BANNER_SUBSTRINGS):
        return True
    first_vals = " ".join(str(v or "").lower() for v in list(raw_row.values())[:2])
    return any(b in first_vals for b in ("term / trimestre", "period / week"))


def _compute_academic_week(start_d: date) -> int:
    # Academic year starts around September 1 of the school year
    acad_year_start = date(
        start_d.year if start_d.month >= 8 else start_d.year - 1, 9, 1
    )
    wk = ((start_d - acad_year_start).days // 7) + 1
    return max(1, min(wk, 52))


def _extract_date_range(norm_row: dict[str, str]) -> tuple[Optional[date], Optional[date], int]:
    raw_start = (
        norm_row.get("start_date")
        or norm_row.get("from_date")
        or norm_row.get("date_debut")
        or norm_row.get("debut")
        or ""
    )
    raw_end = (
        norm_row.get("end_date")
        or norm_row.get("to_date")
        or norm_row.get("date_fin")
        or norm_row.get("fin")
        or ""
    )
    if raw_start and raw_end:
        start_d = _parse_date_flexible(raw_start)
        end_d = _parse_date_flexible(raw_end)
        if end_d < start_d:
            raise ValueError("end_date before start_date")
        week_raw = (
            norm_row.get("week_number")
            or norm_row.get("week")
            or norm_row.get("semaine")
            or ""
        )
        m = re.search(r"\d+", str(week_raw))
        wk = max(1, min(int(m.group(0)), 52)) if m else _compute_academic_week(start_d)
        return start_d, end_d, wk

    # Check combined period columns such as "07/09/2026\nau 11/09/2026"
    for k, v in norm_row.items():
        if not v:
            continue
        if any(h in k for h in ("period", "periode", "week", "semaine", "date", "col_0")):
            tokens = _DATE_TOKEN_RE.findall(v)
            if len(tokens) >= 2:
                try:
                    d1 = _parse_date_flexible(tokens[0])
                    d2 = _parse_date_flexible(tokens[1])
                    if d2 >= d1:
                        return d1, d2, _compute_academic_week(d1)
                except ValueError:
                    pass
    return None, None, 1


def _extract_pdf_syllabus_topics(
    filepath: str,
    raw_bytes: bytes,
    sub_lookup: dict[str, int],
    class_lookup: dict[tuple[int, str], int],
    admin_id: int,
) -> list[tuple]:
    """Parse Cameroon MINESEC syllabus PDFs (filename class range + subject + optional text outline)."""
    clean_fp = filepath.replace("\\", "/")
    base_name = os.path.splitext(clean_fp.split("/")[-1])[0]
    norm_all = _norm_text(clean_fp)

    sub_id = sub_lookup.get("fr", 2) if ("french" in norm_all or "francophone" in norm_all or "francais" in norm_all) else sub_lookup.get("en", 1)

    # Detect class ranges in filename e.g. "Form 1 to 5", "Form I to V", "F 3 4 _ 5", "Form IV _ V"
    norm_base = _norm_text(base_name)
    norm_base_nums = norm_base
    for rom, dig in (("iv", "4"), ("iii", "3"), ("ii", "2"), ("v", "5"), ("i", "1")):
        norm_base_nums = re.sub(rf"\b{rom}\b", dig, norm_base_nums)

    target_cids: list[int] = []
    m_range = re.search(r"(?:form|f)\s*(\d)\s*(?:to|a|-)\s*(\d)", norm_base_nums)
    if m_range:
        lo, hi = int(m_range.group(1)), int(m_range.group(2))
        for n in range(min(lo, hi), max(lo, hi) + 1):
            cid = class_lookup.get((sub_id, f"form {n}"))
            if cid and cid not in target_cids:
                target_cids.append(cid)
    else:
        for n_str in re.findall(r"\b([1-5])\b", norm_base_nums):
            cid = class_lookup.get((sub_id, f"form {n_str}"))
            if cid and cid not in target_cids:
                target_cids.append(cid)

    if not target_cids:
        inferred_sub, inferred_cls, _ = _infer_context_from_path(
            filepath, sub_lookup, class_lookup
        )
        if inferred_sub:
            sub_id = inferred_sub
        if inferred_cls:
            target_cids.append(inferred_cls)
    if not target_cids:
        # Apply to Form 1..Form 5 by default for 1st cycle syllabuses
        for n in range(1, 6):
            cid = class_lookup.get((sub_id, f"form {n}"))
            if cid:
                target_cids.append(cid)

    # Clean subject name from syllabus filename (e.g. "ESG Biology Form 1 to 5" -> "Biology")
    subj = re.sub(r"(?i)^(esg|gse|syllabus|programme)\s+", "", base_name)
    subj = re.sub(r"(?i)\b(?:form|f)\s*(?:[iv]+|\d).*$", "", subj)
    subj = subj.replace("_", "&").strip(" -_")
    subj = re.sub(r"\s+", " ", subj)[:95] or "Curriculum Syllabus"

    extracted_headings: list[str] = []
    try:
        import pypdf

        reader = pypdf.PdfReader(io.BytesIO(raw_bytes))
        for pg in reader.pages[:12]:
            txt = (pg.extract_text() or "").strip()
            for line in txt.splitlines():
                clean_line = re.sub(r"\s+", " ", line).strip()
                if (
                    len(clean_line) >= 8
                    and len(clean_line) <= 120
                    and any(
                        kw in clean_line.lower()
                        for kw in ("module", "topic", "unit", "chapter", "chapitre", "competenc")
                    )
                ):
                    extracted_headings.append(clean_line[:190])
                if len(extracted_headings) >= 12:
                    break
            if len(extracted_headings) >= 12:
                break
    except Exception:
        pass

    rows: list[tuple] = []
    for cid in target_cids:
        if extracted_headings:
            for h in extracted_headings:
                rows.append((sub_id, cid, subj, h, f"Official syllabus: {base_name}", admin_id))
        else:
            rows.append(
                (
                    sub_id,
                    cid,
                    subj,
                    f"{subj} — Official Class Syllabus",
                    f"Source document: {base_name}.pdf",
                    admin_id,
                )
            )
    return rows


@router.post("/admin/upload-curriculum", response_model=ProgressionUploadResult)
async def upload_curriculum_auto(
    files: list[UploadFile] = File(...),
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> ProgressionUploadResult:
    """Smart upload for Program and/or Progression files (or zipped folders) from the admin's device."""
    sub_lookup, class_lookup = _build_lookup_maps(db)
    programs_inserted = 0
    progressions_inserted = 0
    skipped = 0
    expanded_files, errors = await _expand_uploaded_files(files)
    skipped += len(errors)

    with db.cursor() as cursor:
        _ensure_folder_logs_table(cursor)
        folder_stats: dict[str, list[int]] = {}
        prog_rows: list[tuple] = []
        topic_rows: list[tuple] = []
        admin_id = int(admin_user["id"])

        for fname, raw_bytes in expanded_files:
            clean_path = fname.replace("\\", "/")
            root_folder = (
                clean_path.split("/")[0] if "/" in clean_path else "Uploaded Files"
            )
            stats = folder_stats.setdefault(root_folder, [0, 0])
            stats[0] += 1
            if fname.lower().endswith(_STORED_DOC_EXTS):
                _save_uploaded_raw(clean_path, raw_bytes)
                if fname.lower().endswith(".pdf"):
                    pdf_topics = _extract_pdf_syllabus_topics(
                        clean_path, raw_bytes, sub_lookup, class_lookup, admin_id
                    )
                    topic_rows.extend(pdf_topics)
                    programs_inserted += len(pdf_topics)
                    stats[1] += len(pdf_topics)
                continue
            try:
                rows_to_import = _parse_uploaded_rows(raw_bytes, fname)
            except Exception as exc:
                skipped += 1
                if len(errors) < 15:
                    errors.append(f"{fname}: {exc}")
                continue

            path_sub_id, path_cls_id, path_subject = _infer_context_from_path(
                fname, sub_lookup, class_lookup
            )
            file_added = 0
            for idx, raw_row in enumerate(rows_to_import, start=1):
                norm_row = {
                    _norm_text(str(k)).replace(" ", "_"): (
                        str(v).strip() if v is not None else ""
                    )
                    for k, v in raw_row.items()
                    if k is not None
                }
                sub_val = (
                    norm_row.get("subsystem")
                    or norm_row.get("subsystem_name")
                    or norm_row.get("subsystem_code")
                    or norm_row.get("sous_systeme")
                    or norm_row.get("section")
                    or ""
                ).lower()
                cls_val = _norm_text(
                    norm_row.get("class_name")
                    or norm_row.get("class")
                    or norm_row.get("classe")
                    or norm_row.get("niveau")
                    or ""
                )
                cls_val = _CLASS_ALIASES.get(cls_val, cls_val)
                subject = _clean_subject_name(
                    norm_row.get("subject")
                    or norm_row.get("subject_name")
                    or norm_row.get("matiere")
                    or norm_row.get("discipline")
                    or path_subject
                    or ""
                )
                topic, subtopics = _extract_topic_and_subtopics(norm_row)
                if _is_banner_row(topic, raw_row):
                    continue

                sub_id = sub_lookup.get(sub_val) or path_sub_id
                cls_id = (
                    class_lookup.get((sub_id, cls_val)) if sub_id and cls_val else None
                ) or path_cls_id
                if not sub_id or not cls_id or not subject or not topic:
                    skipped += 1
                    if len(errors) < 15:
                        errors.append(
                            f"{fname} row {idx}: missing subsystem/class/subject/topic"
                        )
                    continue

                try:
                    start_d, end_d, week_num = _extract_date_range(norm_row)
                except Exception as exc:
                    skipped += 1
                    if len(errors) < 15:
                        errors.append(f"{fname} row {idx}: {exc}")
                    continue

                if start_d and end_d:
                    study_days = (
                        norm_row.get("study_days")
                        or norm_row.get("days")
                        or norm_row.get("jours")
                        or "Mon - Fri"
                    )[:58]
                    prog_rows.append(
                        (
                            sub_id,
                            cls_id,
                            subject,
                            topic,
                            subtopics,
                            week_num,
                            start_d,
                            end_d,
                            study_days,
                            admin_id,
                        )
                    )
                    progressions_inserted += 1
                    file_added += 1
                else:
                    topic_rows.append(
                        (sub_id, cls_id, subject, topic, subtopics, admin_id)
                    )
                    programs_inserted += 1
                    file_added += 1

            stats[1] += file_added

        if prog_rows:
            cursor.executemany(
                """
                INSERT INTO official_progressions
                  (subsystem_id, class_id, subject_name, topic_title, subtopics,
                   week_number, start_date, end_date, study_days, created_by)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                prog_rows,
            )
        if topic_rows:
            cursor.executemany(
                """
                INSERT INTO program_topics
                  (subsystem_id, class_id, subject_name, topic_title, subtopics, created_by)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                topic_rows,
            )

        for folder_name, (f_count, t_count) in folder_stats.items():
            cursor.execute(
                """
                INSERT INTO uploaded_folder_logs
                  (folder_name, files_count, topics_added, uploaded_by)
                VALUES (%s, %s, %s, %s)
                """,
                (folder_name, f_count, t_count, admin_id),
            )

    return ProgressionUploadResult(
        inserted_count=programs_inserted + progressions_inserted,
        skipped_count=skipped,
        programs_inserted=programs_inserted,
        progressions_inserted=progressions_inserted,
        errors=errors[:15],
    )


@router.get("/admin/programs/template", response_class=PlainTextResponse)
def download_program_template() -> str:
    """Return a sample CSV template for uploading the official Program (subjects & topics per class)."""
    return (
        "subsystem,class_name,subject,topic,subtopics\n"
        "English Subsystem,Form 5,Mathematics,Matrices & Operations,Order addition subtraction and multiplication\n"
        "English Subsystem,Form 5,Physics,Linear Motion,Speed velocity acceleration graphs\n"
        "French Subsystem,3eme,Mathematiques,Equations du 1er degre,Developpement et factorisation\n"
    )


_HEADER_HINTS = {
    "subsystem",
    "sous-systeme",
    "sous_systeme",
    "class",
    "class_name",
    "classe",
    "niveau",
    "subject",
    "subject_name",
    "matiere",
    "discipline",
    "topic",
    "topic_title",
    "chapitre",
    "lecon",
    "module",
}


def _rows_from_grid(grid: list[tuple]) -> list[dict]:
    non_empty = [
        [str(v).strip() if v is not None else "" for v in row]
        for row in grid
        if any(v is not None and str(v).strip() != "" for v in row)
    ]
    if not non_empty:
        return []
    header_idx = 0
    for idx, row in enumerate(non_empty[:15]):
        joined = " ".join(
            _norm_text(cell) for cell in row if cell
        )
        if any(h in joined for h in ("topic", "lesson", "lecon", "chapit", "module", "subject", "matiere", "week", "semaine")):
            header_idx = idx
            break
    headers = non_empty[header_idx]
    result = []
    for vals in non_empty[header_idx + 1 :]:
        row_dict = {}
        for i, h in enumerate(headers):
            key = h if h else f"col_{i}"
            row_dict[key] = vals[i] if i < len(vals) else ""
        if any(str(v).strip() for v in row_dict.values()):
            result.append(row_dict)
    return result


def _parse_uploaded_rows(raw_bytes: bytes, filename: str) -> list[dict]:
    lower = filename.lower()
    if lower.endswith((".xlsx", ".xlsm")):
        import openpyxl

        wb = openpyxl.load_workbook(io.BytesIO(raw_bytes), read_only=True, data_only=True)
        try:
            ws = wb.active
            grid = list(ws.iter_rows(values_only=True))
        finally:
            wb.close()
        return _rows_from_grid(grid)

    if lower.endswith(".xls"):
        import xlrd

        wb = xlrd.open_workbook(file_contents=raw_bytes)
        sheet = wb.sheet_by_index(0)
        grid = [tuple(sheet.row_values(r)) for r in range(sheet.nrows)]
        return _rows_from_grid(grid)

    text = raw_bytes.decode("utf-8-sig", errors="replace").strip()
    if not text:
        return []
    if lower.endswith(".json") or text.startswith("["):
        parsed = json.loads(text)
        if not isinstance(parsed, list):
            raise ValueError("JSON root must be an array")
        return [dict(r) for r in parsed]
    sample = text.splitlines()[0] if text.splitlines() else ""
    delimiter = ";" if sample.count(";") > sample.count(",") else ","
    reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
    return [dict(r) for r in reader]


def _build_lookup_maps(db: Connection) -> tuple[dict[str, int], dict[tuple[int, str], int]]:
    with db.cursor() as cursor:
        cursor.execute("SELECT id, code, name FROM subsystems")
        subsystems = cursor.fetchall()
        cursor.execute("SELECT id, subsystem_id, name FROM classes")
        classes = cursor.fetchall()

    sub_lookup: dict[str, int] = {}
    for s in subsystems:
        sub_lookup[s["code"].strip().lower()] = int(s["id"])
        sub_lookup[s["name"].strip().lower()] = int(s["id"])
    sub_lookup["english"] = sub_lookup.get("en", 1)
    sub_lookup["french"] = sub_lookup.get("fr", 2)
    sub_lookup["anglophone"] = sub_lookup.get("en", 1)
    sub_lookup["francophone"] = sub_lookup.get("fr", 2)

    class_lookup: dict[tuple[int, str], int] = {}
    for c in classes:
        norm = c["name"].strip().lower().replace("è", "e").replace("é", "e")
        class_lookup[(int(c["subsystem_id"]), norm)] = int(c["id"])
    return sub_lookup, class_lookup


@router.post("/admin/programs/upload", response_model=ProgressionUploadResult)
async def upload_programs_files(
    files: list[UploadFile] = File(...),
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> ProgressionUploadResult:
    """Upload one or more CSV/JSON/XLSX/XLS/ZIP Program files containing subjects & topics per class."""
    sub_lookup, class_lookup = _build_lookup_maps(db)
    inserted = 0
    expanded_files, errors = await _expand_uploaded_files(files)
    skipped = len(errors)

    with db.cursor() as cursor:
        for fname, raw_bytes in expanded_files:
            if fname.lower().endswith(_STORED_DOC_EXTS):
                _save_uploaded_raw(fname.replace("\\", "/"), raw_bytes)
                continue
            try:
                rows_to_import = _parse_uploaded_rows(raw_bytes, fname)
            except Exception as exc:
                skipped += 1
                errors.append(f"{fname}: {exc}")
                continue

            path_sub_id, path_cls_id, path_subject = _infer_context_from_path(
                fname, sub_lookup, class_lookup
            )
            for idx, raw_row in enumerate(rows_to_import, start=1):
                norm_row = {
                    _norm_text(str(k)).replace(" ", "_"): (
                        str(v).strip() if v is not None else ""
                    )
                    for k, v in raw_row.items()
                    if k is not None
                }
                sub_val = (
                    norm_row.get("subsystem")
                    or norm_row.get("subsystem_name")
                    or norm_row.get("subsystem_code")
                    or norm_row.get("sous_systeme")
                    or ""
                ).lower()
                cls_val = _norm_text(
                    norm_row.get("class_name")
                    or norm_row.get("class")
                    or norm_row.get("classe")
                    or ""
                )
                cls_val = _CLASS_ALIASES.get(cls_val, cls_val)
                subject = (
                    norm_row.get("subject")
                    or norm_row.get("subject_name")
                    or norm_row.get("matiere")
                    or path_subject
                    or ""
                )[:95]
                topic, subtopics = _extract_topic_and_subtopics(norm_row)

                sub_id = sub_lookup.get(sub_val) or path_sub_id
                cls_id = (
                    class_lookup.get((sub_id, cls_val)) if sub_id and cls_val else None
                ) or path_cls_id
                if not sub_id or not cls_id or not subject or not topic:
                    skipped += 1
                    errors.append(f"{fname} row {idx}: invalid subsystem/class/subject/topic")
                    continue

                cursor.execute(
                    """
                    INSERT INTO program_topics
                      (subsystem_id, class_id, subject_name, topic_title, subtopics, created_by)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    (sub_id, cls_id, subject, topic, subtopics, int(admin_user["id"])),
                )
                inserted += 1

    return ProgressionUploadResult(
        inserted_count=inserted,
        skipped_count=skipped,
        errors=errors[:15],
    )


@router.get("/admin/progressions/template", response_class=PlainTextResponse)
def download_progression_template() -> str:
    """Return a sample CSV template for uploading official programmes & progressions."""
    today = date.today()
    end = today + timedelta(days=3)
    return (
        "subsystem,class_name,subject,topic,subtopics,week_number,start_date,end_date,study_days\n"
        f"English Subsystem,Form 5,Mathematics,Matrices & Operations,Addition and matrix multiplication,1,{today},{end},Mon - Wed\n"
        f"English Subsystem,Form 5,Physics,Linear Motion,Speed velocity and acceleration,1,{today + timedelta(days=1)},{end + timedelta(days=2)},Thu - Sat\n"
        f"French Subsystem,3eme,Mathematiques,Equations du 1er degre,Developpement et factorisation,1,{today},{end},Lun - Mer\n"
    )


@router.post("/admin/progressions/upload", response_model=ProgressionUploadResult)
async def upload_progressions_file(
    files: list[UploadFile] = File(...),
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> ProgressionUploadResult:
    """Upload one or more CSV/JSON/XLSX/XLS/ZIP progression files to populate official_progressions."""
    sub_lookup, class_lookup = _build_lookup_maps(db)
    inserted = 0
    expanded_files, errors = await _expand_uploaded_files(files)
    skipped = len(errors)

    with db.cursor() as cursor:
        for fname, raw_bytes in expanded_files:
            if fname.lower().endswith(_STORED_DOC_EXTS):
                _save_uploaded_raw(fname.replace("\\", "/"), raw_bytes)
                continue
            try:
                rows_to_import = _parse_uploaded_rows(raw_bytes, fname)
            except Exception as exc:
                skipped += 1
                errors.append(f"{fname}: {exc}")
                continue

            path_sub_id, path_cls_id, path_subject = _infer_context_from_path(
                fname, sub_lookup, class_lookup
            )
            for idx, raw_row in enumerate(rows_to_import, start=1):
                norm_row = {
                    _norm_text(str(k)).replace(" ", "_"): (
                        str(v).strip() if v is not None else ""
                    )
                    for k, v in raw_row.items()
                    if k is not None
                }
                sub_val = (
                    norm_row.get("subsystem")
                    or norm_row.get("subsystem_name")
                    or norm_row.get("subsystem_code")
                    or norm_row.get("sous_systeme")
                    or ""
                ).lower()
                cls_val = _norm_text(
                    norm_row.get("class_name")
                    or norm_row.get("class")
                    or norm_row.get("classe")
                    or ""
                )
                cls_val = _CLASS_ALIASES.get(cls_val, cls_val)
                subject = (
                    norm_row.get("subject")
                    or norm_row.get("subject_name")
                    or norm_row.get("matiere")
                    or path_subject
                    or ""
                )[:95]
                topic, subtopics = _extract_topic_and_subtopics(norm_row)
                study_days = (
                    norm_row.get("study_days") or norm_row.get("days") or "Mon - Wed"
                )[:58]

                sub_id = sub_lookup.get(sub_val) or path_sub_id
                if not sub_id:
                    skipped += 1
                    errors.append(f"{fname} row {idx}: unknown subsystem '{sub_val}'")
                    continue

                cls_id = (
                    class_lookup.get((sub_id, cls_val)) if cls_val else None
                ) or path_cls_id
                if not cls_id:
                    skipped += 1
                    errors.append(f"{fname} row {idx}: unknown class '{cls_val}'")
                    continue

                if not subject or not topic:
                    skipped += 1
                    errors.append(f"{fname} row {idx}: missing subject or topic")
                    continue

                try:
                    week_num = int(norm_row.get("week_number") or norm_row.get("week") or 1)
                    start_d = _parse_date_flexible(
                        norm_row.get("start_date") or norm_row.get("from_date") or ""
                    )
                    end_d = _parse_date_flexible(
                        norm_row.get("end_date") or norm_row.get("to_date") or ""
                    )
                    if end_d < start_d:
                        raise ValueError("end_date before start_date")
                except Exception as exc:
                    skipped += 1
                    errors.append(f"{fname} row {idx}: {exc}")
                    continue

                cursor.execute(
                    """
                    INSERT INTO official_progressions
                      (subsystem_id, class_id, subject_name, topic_title, subtopics,
                       week_number, start_date, end_date, study_days, created_by)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        sub_id,
                        cls_id,
                        subject,
                        topic,
                        subtopics,
                        week_num,
                        start_d,
                        end_d,
                        study_days,
                        int(admin_user["id"]),
                    ),
                )
                inserted += 1

    return ProgressionUploadResult(
        inserted_count=inserted,
        skipped_count=skipped,
        errors=errors[:15],
    )


@router.post("/admin/progressions", response_model=ProgressionOut, status_code=201)
def create_official_progression(
    payload: ProgressionCreate,
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> ProgressionOut:
    """Create a new official date-range study progression slot for a Cameroon subsystem & class."""
    if payload.end_date < payload.start_date:
        raise HTTPException(
            status_code=400, detail="end_date must be on or after start_date"
        )
    with db.cursor() as cursor:
        cursor.execute(
            "SELECT id FROM classes WHERE id = %s AND subsystem_id = %s",
            (payload.class_id, payload.subsystem_id),
        )
        if not cursor.fetchone():
            raise HTTPException(
                status_code=400,
                detail="Class does not belong to the chosen subsystem",
            )
        cursor.execute(
            """
            INSERT INTO official_progressions
              (subsystem_id, class_id, subject_name, topic_title, subtopics,
               week_number, start_date, end_date, study_days, created_by)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                payload.subsystem_id,
                payload.class_id,
                payload.subject_name.strip(),
                payload.topic_title.strip(),
                payload.subtopics,
                payload.week_number,
                payload.start_date,
                payload.end_date,
                payload.study_days,
                int(admin_user["id"]),
            ),
        )
        prog_id = cursor.lastrowid
        cursor.execute(
            """
            SELECT op.*,
                   s.name AS subsystem_name,
                   c.name AS class_name
            FROM official_progressions op
            INNER JOIN subsystems s ON s.id = op.subsystem_id
            INNER JOIN classes c ON c.id = op.class_id
            WHERE op.id = %s
            """,
            (prog_id,),
        )
        row = cursor.fetchone()
    return ProgressionOut(**row)


@router.delete("/admin/progressions/{progression_id}", status_code=204)
def delete_official_progression(
    progression_id: int,
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> None:
    """Delete an official progression slot."""
    with db.cursor() as cursor:
        cursor.execute(
            "DELETE FROM official_progressions WHERE id = %s", (progression_id,)
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Progression not found")


@router.delete("/admin/uploaded-folders/{folder_name:path}", status_code=200)
def delete_uploaded_folder(
    folder_name: str,
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> dict:
    """Remove an uploaded folder's logs and stored files on disk so it can be re-imported."""
    folder_clean = folder_name.strip().replace("\\", "/").strip("/")
    if not folder_clean or folder_clean in (".", ".."):
        raise HTTPException(status_code=400, detail="Invalid folder name")

    with db.cursor() as cursor:
        _ensure_folder_logs_table(cursor)
        cursor.execute(
            "DELETE FROM uploaded_folder_logs WHERE folder_name = %s",
            (folder_clean,),
        )
        deleted_count = cursor.rowcount

    # Also delete files from disk if stored under _UPLOADS_DIR
    target_disk_dir = _UPLOADS_DIR / folder_clean
    try:
        if target_disk_dir.exists() and target_disk_dir.is_dir():
            import shutil

            shutil.rmtree(target_disk_dir, ignore_errors=True)
    except Exception:
        pass

    return {"ok": True, "deleted": folder_clean, "removed_records": deleted_count}


@router.get("/admin/users", response_model=list[AdminUserOut])
def list_admin_users(
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> list[AdminUserOut]:
    """List all registered users (students and admins) with status and profile info."""
    with db.cursor() as cursor:
        cursor.execute(
            """
            SELECT u.id,
                   u.full_name,
                   u.email,
                   u.role,
                   COALESCE(u.is_active, 1) AS is_active,
                   u.created_at,
                   sp.subsystem_id,
                   s.name AS subsystem_name,
                   sp.class_id,
                   c.name AS class_name,
                   COALESCE(sp.questionnaire_completed, 0) AS questionnaire_completed
            FROM users u
            LEFT JOIN student_profiles sp ON sp.user_id = u.id
            LEFT JOIN subsystems s ON s.id = sp.subsystem_id
            LEFT JOIN classes c ON c.id = sp.class_id
            ORDER BY u.created_at DESC
            """
        )
        rows = cursor.fetchall()
        result = []
        for r in rows:
            result.append(
                AdminUserOut(
                    id=int(r["id"]),
                    full_name=r["full_name"],
                    email=r["email"],
                    role=r["role"],
                    is_active=bool(r.get("is_active", 1)),
                    subsystem_id=r.get("subsystem_id"),
                    subsystem_name=r.get("subsystem_name"),
                    class_id=r.get("class_id"),
                    class_name=r.get("class_name"),
                    questionnaire_completed=bool(r.get("questionnaire_completed", 0)),
                    created_at=(
                        r.get("created_at").isoformat()
                        if r.get("created_at")
                        and hasattr(r["created_at"], "isoformat")
                        else str(r.get("created_at") or "")
                    ),
                )
            )
        return result


@router.post("/admin/users", response_model=AdminUserOut, status_code=201)
def create_admin_user(
    payload: AdminUserCreate,
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> AdminUserOut:
    """Create a new user (student or admin) directly from the Admin console."""
    from app.services.auth_service import hash_password

    email = payload.email.strip().lower()
    full_name = payload.full_name.strip()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="Invalid email address")
    if not full_name:
        raise HTTPException(status_code=400, detail="Name cannot be empty")

    with db.cursor() as cursor:
        cursor.execute("SELECT id FROM users WHERE email = %s", (email,))
        if cursor.fetchone():
            raise HTTPException(
                status_code=409, detail="A user with this email already exists"
            )

        pw_hash = hash_password(payload.password)
        cursor.execute(
            """
            INSERT INTO users (full_name, email, password_hash, role, is_active)
            VALUES (%s, %s, %s, %s, 1)
            """,
            (full_name, email, pw_hash, payload.role),
        )
        user_id = cursor.lastrowid

        sub_name = None
        cls_name = None
        if payload.role == "student":
            cursor.execute(
                """
                INSERT INTO student_profiles (user_id, subsystem_id, class_id, questionnaire_completed)
                VALUES (%s, %s, %s, 0)
                ON DUPLICATE KEY UPDATE subsystem_id = VALUES(subsystem_id), class_id = VALUES(class_id)
                """,
                (user_id, payload.subsystem_id, payload.class_id),
            )
            if payload.subsystem_id:
                cursor.execute(
                    "SELECT name FROM subsystems WHERE id = %s",
                    (payload.subsystem_id,),
                )
                sub_r = cursor.fetchone()
                if sub_r:
                    sub_name = sub_r["name"]
            if payload.class_id:
                cursor.execute(
                    "SELECT name FROM classes WHERE id = %s", (payload.class_id,)
                )
                cls_r = cursor.fetchone()
                if cls_r:
                    cls_name = cls_r["name"]

        return AdminUserOut(
            id=user_id,
            full_name=full_name,
            email=email,
            role=payload.role,
            is_active=True,
            subsystem_id=payload.subsystem_id,
            subsystem_name=sub_name,
            class_id=payload.class_id,
            class_name=cls_name,
            questionnaire_completed=False,
            created_at=datetime.utcnow().isoformat(),
        )


@router.put("/admin/users/{user_id}/status", response_model=AdminUserOut)
def update_user_status(
    user_id: int,
    payload: AdminUserStatusUpdate,
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> AdminUserOut:
    """Block or unblock a user. Blocked users cannot log in or make API calls."""
    if int(admin_user["id"]) == user_id and not payload.is_active:
        raise HTTPException(
            status_code=400, detail="Cannot deactivate your own admin account"
        )

    with db.cursor() as cursor:
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user = cursor.fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        cursor.execute(
            "UPDATE users SET is_active = %s WHERE id = %s",
            (1 if payload.is_active else 0, user_id),
        )

        cursor.execute(
            """
            SELECT u.id, u.full_name, u.email, u.role, COALESCE(u.is_active, 1) AS is_active,
                   u.created_at, sp.subsystem_id, s.name AS subsystem_name,
                   sp.class_id, c.name AS class_name,
                   COALESCE(sp.questionnaire_completed, 0) AS questionnaire_completed
            FROM users u
            LEFT JOIN student_profiles sp ON sp.user_id = u.id
            LEFT JOIN subsystems s ON s.id = sp.subsystem_id
            LEFT JOIN classes c ON c.id = sp.class_id
            WHERE u.id = %s
            """,
            (user_id,),
        )
        r = cursor.fetchone()
        return AdminUserOut(
            id=int(r["id"]),
            full_name=r["full_name"],
            email=r["email"],
            role=r["role"],
            is_active=bool(r.get("is_active", 1)),
            subsystem_id=r.get("subsystem_id"),
            subsystem_name=r.get("subsystem_name"),
            class_id=r.get("class_id"),
            class_name=r.get("class_name"),
            questionnaire_completed=bool(r.get("questionnaire_completed", 0)),
            created_at=(
                r.get("created_at").isoformat()
                if r.get("created_at") and hasattr(r["created_at"], "isoformat")
                else str(r.get("created_at") or "")
            ),
        )


@router.delete("/admin/users/{user_id}", status_code=204)
def delete_user(
    user_id: int,
    admin_user: dict = Depends(require_admin),
    db: Connection = Depends(get_db),
) -> None:
    """Delete a user account and associated student profile data."""
    if int(admin_user["id"]) == user_id:
        raise HTTPException(
            status_code=400, detail="Cannot delete your own admin account"
        )
    with db.cursor() as cursor:
        cursor.execute(
            "DELETE FROM student_topic_progress WHERE user_id = %s", (user_id,)
        )
        cursor.execute(
            "DELETE FROM student_profiles WHERE user_id = %s", (user_id,)
        )
        cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="User not found")
