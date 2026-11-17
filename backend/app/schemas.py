from datetime import date, datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


UserRole = Literal["student", "admin"]
UnderstandingLevel = Literal["none", "partial", "full"]
TopicStatus = Literal["not_started", "in_progress", "needs_revision", "understood"]
AiInteractionType = Literal["chat", "quiz", "summary", "simulation", "check"]


class RegisterRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=140)
    email: str = Field(..., min_length=4, max_length=190)
    password: str = Field(..., min_length=6, max_length=128)
    role: UserRole = "student"


class LoginRequest(BaseModel):
    email: str = Field(..., min_length=4, max_length=190)
    password: str = Field(..., min_length=1, max_length=128)


class UserOut(BaseModel):
    id: int
    full_name: str
    email: str
    role: UserRole
    questionnaire_completed: bool = False


class ProfileUpdateRequest(BaseModel):
    full_name: Optional[str] = Field(default=None, min_length=2, max_length=140)
    email: Optional[str] = Field(default=None, min_length=4, max_length=190)
    current_password: Optional[str] = None
    new_password: Optional[str] = Field(default=None, min_length=6, max_length=128)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class ClassOut(BaseModel):
    id: int
    subsystem_id: int
    name: str
    level_order: int


class SubsystemOut(BaseModel):
    id: int
    code: str
    name: str
    description: Optional[str] = None
    classes: list[ClassOut] = Field(default_factory=list)


class QuestionnaireSubmit(BaseModel):
    full_name: Optional[str] = Field(default=None, min_length=2, max_length=120)
    subsystem_id: int
    class_id: int
    age: Optional[int] = Field(default=None, ge=6, le=30)
    favourite_subject: Optional[str] = Field(default=None, max_length=100)
    difficult_subjects: list[str] = Field(default_factory=list)
    difficulty_reason: Optional[str] = Field(default=None, max_length=160)
    hobbies: list[str] = Field(default_factory=list)
    activity_style: str = "both"
    learning_style: str = "practical_examples"
    fallback_preference: str = "another_example"
    exercise_preference: str = "short_quizzes"
    preferred_study_period: str = "evening"
    academic_goal: Optional[str] = Field(default=None, max_length=255)
    daily_goal_minutes: int = Field(default=60, ge=15, le=480)
    reminder_hour: int = Field(default=18, ge=0, le=23)
    reminder_minute: int = Field(default=0, ge=0, le=59)


class StudentProfileOut(BaseModel):
    user_id: int
    subsystem_id: Optional[int] = None
    subsystem_name: Optional[str] = None
    class_id: Optional[int] = None
    class_name: Optional[str] = None
    age: Optional[int] = None
    questionnaire_completed: bool = False
    favourite_subject: Optional[str] = None
    difficult_subjects: list[str] = Field(default_factory=list)
    difficulty_reason: Optional[str] = None
    hobbies: list[str] = Field(default_factory=list)
    activity_style: str = "both"
    learning_style: str = "practical_examples"
    fallback_preference: str = "another_example"
    exercise_preference: str = "short_quizzes"
    preferred_study_period: str = "evening"
    academic_goal: Optional[str] = None
    daily_goal_minutes: int = 60
    reminder_hour: int = 18
    reminder_minute: int = 0


class ProgressionCreate(BaseModel):
    subsystem_id: int
    class_id: int
    subject_name: str = Field(..., min_length=1, max_length=100)
    topic_title: str = Field(..., min_length=1, max_length=200)
    subtopics: Optional[str] = None
    week_number: int = Field(default=1, ge=1, le=52)
    start_date: date
    end_date: date
    study_days: Optional[str] = Field(default="Mon - Wed", max_length=60)


class ProgressionOut(BaseModel):
    id: int
    subsystem_id: int
    subsystem_name: Optional[str] = None
    class_id: int
    class_name: Optional[str] = None
    subject_name: str
    topic_title: str
    subtopics: Optional[str] = None
    week_number: int
    start_date: date
    end_date: date
    study_days: Optional[str] = None
    student_status: TopicStatus = "not_started"
    understanding_level: UnderstandingLevel = "none"


class StudentHomeOut(BaseModel):
    user: UserOut
    profile: StudentProfileOut
    today_topics: list[ProgressionOut] = Field(default_factory=list)
    weekly_topics: list[ProgressionOut] = Field(default_factory=list)
    all_topics: list[ProgressionOut] = Field(default_factory=list)
    class_subjects: list[str] = Field(default_factory=list)
    program_topics: list[ProgressionOut] = Field(default_factory=list)
    understood_count: int = 0
    needs_revision_count: int = 0
    total_topics_count: int = 0


class AdminDashboardOut(BaseModel):
    admin: UserOut
    subsystems_count: int
    classes_count: int
    students_count: int
    progressions_count: int
    program_topics_count: int = 0
    recent_students: list[dict] = Field(default_factory=list)
    progressions: list[ProgressionOut] = Field(default_factory=list)
    uploaded_folders: list[dict] = Field(default_factory=list)


class AdminUserCreate(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=120)
    email: str = Field(..., max_length=150)
    password: str = Field(..., min_length=6, max_length=100)
    role: str = Field(default="student", pattern="^(student|admin)$")
    subsystem_id: Optional[int] = None
    class_id: Optional[int] = None


class AdminUserStatusUpdate(BaseModel):
    is_active: bool


class AdminUserOut(BaseModel):
    id: int
    full_name: str
    email: str
    role: str
    is_active: bool = True
    subsystem_id: Optional[int] = None
    subsystem_name: Optional[str] = None
    class_id: Optional[int] = None
    class_name: Optional[str] = None
    questionnaire_completed: bool = False
    created_at: Optional[Any] = None


class ProgressionUploadResult(BaseModel):
    inserted_count: int
    skipped_count: int
    programs_inserted: int = 0
    progressions_inserted: int = 0
    errors: list[str] = Field(default_factory=list)


class BackgroundDigestOut(BaseModel):
    user_id: int
    is_sunday: bool
    sunday_title: str
    sunday_body: str
    daily_title: str
    daily_body: str
    today_topics: list[ProgressionOut] = Field(default_factory=list)
    weekly_topics: list[ProgressionOut] = Field(default_factory=list)


class AiAskRequest(BaseModel):
    progression_id: Optional[int] = None
    subject_name: Optional[str] = Field(default=None, max_length=100)
    topic_title: Optional[str] = Field(default=None, max_length=200)
    question: str = Field(default="", max_length=4000)


class AiTopicActionRequest(BaseModel):
    progression_id: Optional[int] = None
    subject_name: Optional[str] = Field(default=None, max_length=100)
    topic_title: Optional[str] = Field(default=None, max_length=200)
    num_questions: int = Field(default=4, ge=1, le=10)


class QuizQuestion(BaseModel):
    question: str
    question_type: Literal["mcq", "short_answer", "essay"] = "mcq"
    options: list[str] = Field(default_factory=list)
    correct_index: int = 0
    marks: int = 1
    expected_points: list[str] = Field(default_factory=list)
    explanation: str = ""


class SceneObject(BaseModel):
    sprite: str = "cell"
    label: str = ""
    x: float = 0.5
    y: float = 0.5
    color: str = "blue"
    scale: float = 1.0


class SceneMotion(BaseModel):
    from_x: float = 0.2
    from_y: float = 0.5
    to_x: float = 0.8
    to_y: float = 0.5
    particle: str = "drop"
    color: str = "cyan"
    label: str = ""


class SimulationScene(BaseModel):
    environment: str = "biology"
    objects: list[SceneObject] = Field(default_factory=list)
    motions: list[SceneMotion] = Field(default_factory=list)


class SimulationStep(BaseModel):
    step_number: int = 1
    title: str
    action: str
    visual_model: str = ""
    outcome: str = ""
    scene: Optional[SimulationScene] = None


class SimulationData(BaseModel):
    title: str
    hobby_connection: str = ""
    learning_style_focus: str = ""
    scenario: str = ""
    steps: list[SimulationStep] = Field(default_factory=list)
    key_takeaway: str = ""


class AiTranslateRequest(BaseModel):
    text: str
    target_language: str = "en"


class AiTranslateOut(BaseModel):
    translated_text: str
    target_language: str
    model_used: str = "gemini"


class DiagramComparisonRow(BaseModel):
    criterion: str
    left_value: str
    right_value: str


class DiagramNode(BaseModel):
    id: str
    label: str
    detail: str = ""
    role: str = "step"


class DiagramEdge(BaseModel):
    from_id: str
    to_id: str
    label: str = ""


class NoteDiagram(BaseModel):
    diagram_type: Literal["comparison", "flow", "cycle", "concept_map"] = "flow"
    title: str
    subtitle: str = ""
    left_label: str = ""
    right_label: str = ""
    comparison_rows: list[DiagramComparisonRow] = Field(default_factory=list)
    nodes: list[DiagramNode] = Field(default_factory=list)
    edges: list[DiagramEdge] = Field(default_factory=list)
    takeaway: str = ""


class AiResponseOut(BaseModel):
    interaction_type: AiInteractionType
    content: str
    model_used: str
    quiz: Optional[list[QuizQuestion]] = None
    sources: list[dict[str, str]] = Field(default_factory=list)
    video_suggestions: list[dict[str, str]] = Field(default_factory=list)
    diagrams: list[NoteDiagram] = Field(default_factory=list)
    simulation: Optional[SimulationData] = None
    score_summary: Optional[str] = None
    progress_updated: bool = False


class TopicProgressUpdateRequest(BaseModel):
    progression_id: int
    status: TopicStatus = "in_progress"
    understanding_level: UnderstandingLevel = "partial"
    quiz_score: Optional[int] = Field(default=None, ge=0, le=100)
    weakness_notes: Optional[str] = Field(default=None, max_length=1000)


class AiHistoryItemOut(BaseModel):
    id: int
    progression_id: Optional[int] = None
    subject_name: Optional[str] = None
    topic_title: Optional[str] = None
    interaction_type: AiInteractionType
    prompt: str
    response: str
    sources: list[dict[str, str]] = Field(default_factory=list)
    diagrams: list[NoteDiagram] = Field(default_factory=list)
    simulation: Optional[SimulationData] = None
    quiz: Optional[list[QuizQuestion]] = None
    score_summary: Optional[str] = None
    created_at: datetime


class AiTranscribeOut(BaseModel):
    text: str
    model_used: str
