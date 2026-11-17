from datetime import date, datetime
import io
import zipfile
from fastapi.testclient import TestClient

from app.database import get_db
from app.main import app


class FakeCursor:
    def __init__(self, state: dict):
        self.state = state
        self._result = []
        self.rowcount = 0
        self.lastrowid = 1

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, query: str, params=None):
        q = " ".join(query.lower().split())
        if q.startswith("select 1 as ok"):
            self._result = [{"ok": 1}]
        elif q.startswith("select id from users where email = %s"):
            email = params[0]
            self._result = [u for u in self.state["users"] if u["email"] == email]
        elif q.startswith("insert into users"):
            uid = len(self.state["users"]) + 1
            self.lastrowid = uid
            self.state["users"].append(
                {
                    "id": uid,
                    "full_name": params[0],
                    "email": params[1],
                    "password_hash": params[2],
                    "role": params[3],
                    "is_active": 1,
                }
            )
            self.rowcount = 1
        elif q.startswith("insert into student_profiles"):
            uid = params[0]
            existing = next((p for p in self.state["profiles"] if p["user_id"] == uid), None)
            if existing:
                existing.update(
                    {
                        "subsystem_id": params[1],
                        "class_id": params[2],
                        "age": params[3],
                        "questionnaire_completed": 1,
                        "favourite_subject": params[4],
                        "difficult_subjects_json": params[5],
                        "difficulty_reason": params[6],
                        "hobbies_json": params[7],
                        "activity_style": params[8],
                        "learning_style": params[9],
                        "fallback_preference": params[10],
                        "exercise_preference": params[11],
                        "preferred_study_period": params[12],
                        "academic_goal": params[13],
                        "daily_goal_minutes": params[14],
                        "reminder_hour": params[15],
                        "reminder_minute": params[16],
                    }
                )
            else:
                self.state["profiles"].append(
                    {
                        "user_id": uid,
                        "subsystem_id": None,
                        "class_id": None,
                        "age": None,
                        "questionnaire_completed": 0,
                        "favourite_subject": None,
                        "difficult_subjects_json": "[]",
                        "difficulty_reason": None,
                        "hobbies_json": "[]",
                        "activity_style": "both",
                        "learning_style": "practical_examples",
                        "fallback_preference": "another_example",
                        "exercise_preference": "short_quizzes",
                        "preferred_study_period": "evening",
                        "academic_goal": None,
                        "daily_goal_minutes": 60,
                        "reminder_hour": 18,
                        "reminder_minute": 0,
                    }
                )
            self.rowcount = 1
        elif "from users where id = %s" in q:
            uid = params[0]
            self._result = [u for u in self.state["users"] if u["id"] == uid]
        elif "select questionnaire_completed from student_profiles" in q:
            uid = params[0]
            self._result = [p for p in self.state["profiles"] if p["user_id"] == uid]
        elif "from subsystems order by id" in q:
            self._result = list(self.state["subsystems"])
        elif "from classes order by" in q:
            self._result = list(self.state["classes"])
        elif "select id from classes where id = %s and subsystem_id = %s" in q:
            cid, sid = params
            self._result = [
                c for c in self.state["classes"] if c["id"] == cid and c["subsystem_id"] == sid
            ]
        elif "from student_profiles sp" in q:
            uid = params[0]
            rows = []
            for p in self.state["profiles"]:
                if p["user_id"] == uid:
                    sub = next(
                        (s["name"] for s in self.state["subsystems"] if s["id"] == p["subsystem_id"]),
                        None,
                    )
                    cls = next(
                        (c["name"] for c in self.state["classes"] if c["id"] == p["class_id"]),
                        None,
                    )
                    rows.append({**p, "subsystem_name": sub, "class_name": cls})
            self._result = rows
        elif "from official_progressions" in q:
            if "where id = %s" in q and params:
                pid = int(params[0])
                self._result = [p for p in self.state["progressions"] if p["id"] == pid]
            else:
                self._result = list(self.state["progressions"])
        elif q.startswith("insert into ai_interactions"):
            aid = len(self.state["ai_interactions"]) + 1
            self.lastrowid = aid
            self.state["ai_interactions"].append(
                {
                    "id": aid,
                    "user_id": params[0],
                    "progression_id": params[1],
                    "interaction_type": params[2],
                    "prompt": params[3],
                    "response": params[4],
                    "created_at": datetime.now(),
                }
            )
            self.rowcount = 1
        elif "from ai_interactions ai" in q:
            uid = params[0]
            items = [x for x in self.state["ai_interactions"] if x["user_id"] == uid]
            self._result = [
                {
                    **x,
                    "subject_name": None,
                    "topic_title": None,
                }
                for x in reversed(items)
            ]
        elif q.startswith("select id, code, name from subsystems"):
            self._result = list(self.state["subsystems"])
        elif q.startswith("select id, subsystem_id, name from classes"):
            self._result = list(self.state["classes"])
        elif q.startswith("insert into program_topics"):
            self.state["program_topics"].append(
                {
                    "subsystem_id": params[0],
                    "class_id": params[1],
                    "subject_name": params[2],
                    "topic_title": params[3],
                }
            )
            self.rowcount = 1
        elif q.startswith("create table if not exists uploaded_folder_logs"):
            self._result = []
        elif q.startswith("insert into uploaded_folder_logs"):
            self._result = []
        elif "from uploaded_folder_logs" in q:
            self._result = []
        elif q.startswith("insert into official_progressions"):
            pid = len(self.state["progressions"]) + 1
            self.state["progressions"].append(
                {
                    "id": pid,
                    "subsystem_id": params[0],
                    "class_id": params[1],
                    "subject_name": params[2],
                    "topic_title": params[3],
                }
            )
            self.rowcount = 1
        else:
            self._result = []

    def fetchone(self):
        return self._result[0] if self._result else None

    def fetchall(self):
        return list(self._result)

    def executemany(self, query: str, seq_params):
        total = 0
        for p in seq_params:
            self.execute(query, p)
            total += self.rowcount
        self.rowcount = total


class FakeConnection:
    def __init__(self, state: dict):
        self.state = state

    def cursor(self):
        return FakeCursor(self.state)


def _make_state():
    return {
        "users": [],
        "profiles": [],
        "ai_interactions": [],
        "program_topics": [],
        "subsystems": [
            {"id": 1, "code": "en", "name": "English Subsystem", "description": "Anglophone"},
            {"id": 2, "code": "fr", "name": "French Subsystem", "description": "Francophone"},
        ],
        "classes": [
            {"id": 1, "subsystem_id": 1, "name": "Form 1", "level_order": 1},
            {"id": 4, "subsystem_id": 1, "name": "Form 4", "level_order": 4},
            {"id": 5, "subsystem_id": 1, "name": "Form 5", "level_order": 5},
            {"id": 11, "subsystem_id": 2, "name": "3eme", "level_order": 4},
        ],
        "progressions": [
            {
                "id": 1,
                "subsystem_id": 1,
                "subsystem_name": "English Subsystem",
                "class_id": 5,
                "class_name": "Form 5",
                "subject_name": "Mathematics",
                "topic_title": "Matrices & Operations",
                "subtopics": "Addition and multiplication",
                "week_number": 1,
                "start_date": date.today(),
                "end_date": date.today(),
                "study_days": "Mon - Wed",
                "student_status": "not_started",
                "understanding_level": "none",
            }
        ],
    }


def test_register_questionnaire_and_student_home():
    state = _make_state()
    app.dependency_overrides[get_db] = lambda: FakeConnection(state)
    client = TestClient(app)

    res_sub = client.get("/curriculum/subsystems")
    assert res_sub.status_code == 200
    assert len(res_sub.json()) == 2

    res_reg = client.post(
        "/auth/register",
        json={
            "full_name": "Benoit Kamga",
            "email": "benoit@example.cm",
            "password": "password123",
            "role": "student",
        },
    )
    assert res_reg.status_code == 201
    data = res_reg.json()
    assert data["user"]["questionnaire_completed"] is False
    token = data["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    res_q = client.put(
        "/curriculum/student/questionnaire",
        headers=headers,
        json={
            "subsystem_id": 1,
            "class_id": 5,
            "age": 15,
            "favourite_subject": "Mathematics",
            "difficult_subjects": ["Physics"],
            "difficulty_reason": "Understanding formulas",
            "hobbies": ["Football", "Music"],
            "activity_style": "both",
            "learning_style": "visual_simulations",
            "fallback_preference": "visual_demonstration",
            "exercise_preference": "short_quizzes",
            "preferred_study_period": "evening",
            "academic_goal": "Pass GCE O-Level with Distinction",
            "daily_goal_minutes": 60,
            "reminder_hour": 18,
            "reminder_minute": 30,
        },
    )
    assert res_q.status_code == 200
    assert res_q.json()["questionnaire_completed"] is True
    assert res_q.json()["class_name"] == "Form 5"

    res_home = client.get("/curriculum/student/home", headers=headers)
    assert res_home.status_code == 200
    home = res_home.json()
    assert len(home["today_topics"]) == 1
    assert home["today_topics"][0]["topic_title"] == "Matrices & Operations"

    res_digest = client.get("/curriculum/background-digest/1")
    assert res_digest.status_code == 200
    assert "Matrices & Operations" in res_digest.json()["daily_body"]

    app.dependency_overrides.clear()


def test_ai_multimodal_and_history():
    from app.routers.ai import get_ai_assistant
    from app.services.ai_service import GeminiStudyAssistant

    state = _make_state()
    app.dependency_overrides[get_db] = lambda: FakeConnection(state)
    offline_assistant = GeminiStudyAssistant()
    offline_assistant._client = None
    app.dependency_overrides[get_ai_assistant] = lambda: offline_assistant
    client = TestClient(app)

    res_reg = client.post(
        "/auth/register",
        json={
            "full_name": "Student Multimodal",
            "email": "multi@example.cm",
            "password": "password123",
            "role": "student",
        },
    )
    assert res_reg.status_code == 201
    headers = {"Authorization": f"Bearer {res_reg.json()['access_token']}"}

    res_multi = client.post(
        "/ai/ask-multimodal",
        headers=headers,
        data={"question": "Solve problem 1"},
        files=[
            ("files", ("homework.png", b"\x89PNG\r\n\x1a\nfake", "image/png")),
            ("files", ("voice.webm", b"OggSfakeaudio", "audio/webm")),
        ],
    )
    assert res_multi.status_code == 200
    body = res_multi.json()
    assert "homework.png" in body["content"]
    assert "voice.webm" in body["content"]

    res_hist = client.get("/ai/history", headers=headers)
    assert res_hist.status_code == 200
    hist = res_hist.json()
    assert len(hist) == 1
    assert "[Image: homework.png]" in hist[0]["prompt"]
    assert "[Audio: voice.webm]" in hist[0]["prompt"]
    assert "Solve problem 1" in hist[0]["prompt"]

    res_trans = client.post(
        "/ai/transcribe",
        headers=headers,
        data={"language": "fr"},
        files=[("file", ("voice.webm", b"OggSfakeaudio", "audio/webm"))],
    )
    assert res_trans.status_code == 200
    assert res_trans.json()["model_used"] == "offline-fallback"

    res_sum = client.post(
        "/ai/summary",
        headers=headers,
        json={"progression_id": 1},
    )
    assert res_sum.status_code == 200
    sum_body = res_sum.json()
    assert sum_body["interaction_type"] == "summary"
    assert sum_body["video_suggestions"] == []
    assert isinstance(sum_body["diagrams"], list)
    assert len(sum_body["diagrams"]) >= 2
    assert any(d["diagram_type"] == "comparison" for d in sum_body["diagrams"])
    assert sum_body["simulation"] is not None
    assert len(sum_body["simulation"]["steps"]) >= 3
    assert sum_body["progress_updated"] is True

    from app.services.web_research import _relevance_score
    assert _relevance_score("Allotropes of sulfur", "Sulfur forms yellow crystals.", {"sulfur", "allotropes"}, "Chemistry") > 0
    assert _relevance_score("Boron", "Boron is a chemical element with atomic number 5.", {"sulfur", "allotropes"}, "Chemistry") == 0

    res_quiz = client.post(
        "/ai/quiz",
        headers=headers,
        json={"progression_id": 1, "num_questions": 5},
    )
    assert res_quiz.status_code == 200
    quiz_list = res_quiz.json()["quiz"]
    assert any(q["question_type"] == "essay" for q in quiz_list)

    import json as _json
    res_grade = client.post(
        "/ai/quiz/grade",
        headers=headers,
        data={
            "progression_id": "1",
            "quiz_json": _json.dumps(quiz_list),
            "answers_json": _json.dumps({"Q2": "Matrices store numbers in rows and columns."}),
            "note": "Check Q2 paper working",
        },
        files=[("files", ("paper_page1.png", b"\x89PNG\r\n\x1a\npaper", "image/png"))],
    )
    assert res_grade.status_code == 200
    graded = res_grade.json()
    assert "paper_page1.png" in graded["content"]
    assert graded["simulation"] is not None
    assert len(graded["simulation"]["steps"]) >= 1
    assert graded["video_suggestions"] == []
    assert graded["progress_updated"] is True

    res_prog = client.post(
        "/curriculum/student/progress",
        headers=headers,
        json={
            "progression_id": 1,
            "status": "understood",
            "understanding_level": "full",
            "quiz_score": 85,
        },
    )
    assert res_prog.status_code == 200
    prog_home = res_prog.json()
    assert "understood_count" in prog_home
    assert "needs_revision_count" in prog_home
    assert "total_topics_count" in prog_home

    app.dependency_overrides.clear()


def test_admin_zip_folder_curriculum_upload():
    state = _make_state()
    app.dependency_overrides[get_db] = lambda: FakeConnection(state)
    client = TestClient(app)

    res_reg = client.post(
        "/auth/register",
        json={
            "full_name": "Admin User",
            "email": "admin@example.cm",
            "password": "password123",
            "role": "admin",
        },
    )
    assert res_reg.status_code == 201
    headers = {"Authorization": f"Bearer {res_reg.json()['access_token']}"}

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr(
            "English Subsystem/Form 5/program.csv",
            "subject,topic,subtopics\nMathematics,Trigonometry,Sine and Cosine\n",
        )
        zf.writestr(
            "English Subsystem/Form 5/progression.csv",
            f"subject,topic,week_number,start_date,end_date\nPhysics,Optics,2,{date.today()},{date.today()}\n",
        )
        zf.writestr(
            "EXCEL/English Sub System/General Education/Form 1/Form 1 - Biology.xlsx.csv",
            "Module,Content,Hours\nCell Structure,Prokaryotic vs Eukaryotic Cells,2h\n",
        )
        zf.writestr(
            "EXCEL/English Sub System/General Education/Form 4/Form 4 - All - Additional mathematics.xlsx.csv",
            "Period / Week;Chapter;Title\n09/11/2026 au 13/11/2026;Chap 1. Group Theory;Lesson 1. Binary Operations\n",
        )
    buf.seek(0)

    res_up = client.post(
        "/curriculum/admin/upload-curriculum",
        headers=headers,
        files=[("files", ("folder_bundle.zip", buf.read(), "application/zip"))],
    )
    assert res_up.status_code == 200
    data = res_up.json()
    assert data["programs_inserted"] == 2
    assert data["progressions_inserted"] == 2
    assert data["skipped_count"] == 0

    app.dependency_overrides.clear()


def test_multi_subject_simulation_adaptation():
    from app.services.ai_service import _build_fallback_simulation

    subjects = [
        ("Mathematics", "Quadratic Equations", "math"),
        ("Chemistry", "Sulfur Allotropes", "chemistry"),
        ("Computer Science", "CPU & Algorithms", "cs"),
        ("Geography", "Water Cycle", "geography"),
        ("Economics", "Sole Proprietorship", "commerce"),
        ("History", "Constitutional Rights", "humanities"),
        ("Biology", "Xylem Water Transport", "nature"),
    ]
    for subj, topic, expected_env in subjects:
        sim = _build_fallback_simulation(subj, topic, hobbies="football")
        assert len(sim.steps) >= 2
        first_scene = sim.steps[0].scene
        assert first_scene is not None
        assert first_scene.environment == expected_env
        assert len(first_scene.objects) >= 2
        assert len(first_scene.motions) >= 1


def test_weekly_plan_cap_and_rich_history_pack_unpack():
    from app.routers.ai import _pack_rich_response, _unpack_rich_response
    from app.routers.curriculum import _select_this_week_topics
    from app.schemas import ProgressionOut
    from app.services.ai_service import _build_fallback_simulation

    today = date.today()
    bulk = [
        ProgressionOut(
            id=i,
            subsystem_id=1,
            subsystem_name="English Subsystem",
            class_id=4,
            class_name="Form 4",
            subject_name=f"Subject {i % 10}",
            topic_title=f"Lesson {i}",
            week_number=1,
            start_date=today,
            end_date=today,
            student_status="not_started",
            understanding_level="none",
        )
        for i in range(1, 51)
    ]
    weekly = _select_this_week_topics(bulk, today, max_items=8)
    assert len(weekly) == 8

    sim = _build_fallback_simulation("Biology", "Xylem Transport")
    packed = _pack_rich_response(
        "# Full Lesson Notes",
        sources=[{"title": "Xylem", "url": "https://en.wikipedia.org/wiki/Xylem", "image_url": "https://example.com/xylem.jpg"}],
        simulation=sim,
        score_summary="8/10",
    )
    clean_text, meta = _unpack_rich_response(packed)
    assert clean_text == "# Full Lesson Notes"
    assert meta["score_summary"] == "8/10"
    assert len(meta["sources"]) == 1
    assert meta["simulation"]["title"] == sim.title


def test_notes_sanitization_and_language_sources():
    from app.services.ai_service import (
        _extract_notes_from_malformed_json,
        _sanitize_notes,
    )
    from app.services.web_research import fetch_verified_topic_notes

    # Leaked json fragments must be stripped
    leaked = (
        'Some valid intro notes\n"scale": 1.0}, {"sprite": "triangle",'
        ' "label": "Team B"}'
    )
    cleaned = _sanitize_notes(leaked)
    assert '"scale": 1.0' not in cleaned
    assert '"sprite":' not in cleaned
    assert cleaned == "Some valid intro notes"

    # Raw json starting string must return empty (preventing leak)
    raw_json_start = '"scale": 1.0}, {"sprite": "triangle"}'
    assert _sanitize_notes(raw_json_start) == ""

    # Standalone dollars around numbers must be cleaned ($10$ -> 10)
    formula_note = "Numbers multiply to $10$ and add to $7$."
    assert (
        _sanitize_notes(formula_note)
        == "Numbers multiply to 10 and add to 7."
    )

    # French sources
    dossier_fr, sources_fr = fetch_verified_topic_notes(
        "Mathematiques", "Equations", language="fr"
    )
    assert len(sources_fr) >= 3
    assert any(
        "wikipedia" in s["url"] or "vikidia" in s["url"]
        for s in sources_fr
    )
    assert "Articles et liens de référence" in dossier_fr
