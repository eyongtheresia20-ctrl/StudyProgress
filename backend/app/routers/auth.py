from fastapi import APIRouter, Depends, HTTPException
from pymysql.connections import Connection

from app.database import get_db
from app.schemas import (
    AuthResponse,
    LoginRequest,
    ProfileUpdateRequest,
    RegisterRequest,
    UserOut,
)
from app.services.auth_service import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _build_user_out(db: Connection, user_row: dict) -> UserOut:
    questionnaire_done = True
    if user_row["role"] == "student":
        with db.cursor() as cursor:
            cursor.execute(
                "SELECT questionnaire_completed FROM student_profiles WHERE user_id = %s",
                (user_row["id"],),
            )
            prof = cursor.fetchone()
        questionnaire_done = bool(prof and prof["questionnaire_completed"])
    return UserOut(
        id=int(user_row["id"]),
        full_name=user_row["full_name"],
        email=user_row["email"],
        role=user_row["role"],
        questionnaire_completed=questionnaire_done,
    )


@router.post("/register", response_model=AuthResponse, status_code=201)
def register(payload: RegisterRequest, db: Connection = Depends(get_db)) -> AuthResponse:
    """Register a new student or administrator account."""
    email = payload.email.strip().lower()
    with db.cursor() as cursor:
        cursor.execute("SELECT id FROM users WHERE email = %s", (email,))
        if cursor.fetchone():
            raise HTTPException(status_code=409, detail="Email is already registered")

        pw_hash = hash_password(payload.password)
        cursor.execute(
            """
            INSERT INTO users (full_name, email, password_hash, role)
            VALUES (%s, %s, %s, %s)
            """,
            (payload.full_name.strip(), email, pw_hash, payload.role),
        )
        user_id = cursor.lastrowid

        if payload.role == "student":
            cursor.execute(
                """
                INSERT INTO student_profiles (user_id, questionnaire_completed)
                VALUES (%s, 0)
                """,
                (user_id,),
            )

        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user_row = cursor.fetchone()

    token = create_access_token(int(user_row["id"]), user_row["role"])
    return AuthResponse(access_token=token, user=_build_user_out(db, user_row))


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, db: Connection = Depends(get_db)) -> AuthResponse:
    """Authenticate an existing student or administrator."""
    email = payload.email.strip().lower()
    with db.cursor() as cursor:
        cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
        user_row = cursor.fetchone()

    if not user_row or not verify_password(payload.password, user_row["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    if not user_row["is_active"]:
        raise HTTPException(status_code=403, detail="Account is disabled")

    token = create_access_token(int(user_row["id"]), user_row["role"])
    return AuthResponse(access_token=token, user=_build_user_out(db, user_row))


@router.get("/me", response_model=UserOut)
def get_me(
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> UserOut:
    """Return the authenticated user and questionnaire status (used on splash screen)."""
    return _build_user_out(db, current_user)


@router.patch("/profile", response_model=UserOut)
def update_my_profile(
    payload: ProfileUpdateRequest,
    current_user: dict = Depends(get_current_user),
    db: Connection = Depends(get_db),
) -> UserOut:
    """Update the authenticated user's name, email, and/or password."""
    user_id = int(current_user["id"])
    with db.cursor() as cursor:
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user_row = cursor.fetchone()
        if not user_row:
            raise HTTPException(status_code=404, detail="User not found")

        new_name = (
            payload.full_name.strip()
            if payload.full_name is not None
            else user_row["full_name"]
        )
        new_email = (
            payload.email.strip().lower()
            if payload.email is not None
            else user_row["email"]
        )
        if new_email != user_row["email"]:
            cursor.execute(
                "SELECT id FROM users WHERE email = %s AND id != %s",
                (new_email, user_id),
            )
            if cursor.fetchone():
                raise HTTPException(
                    status_code=409, detail="Email is already in use"
                )

        new_pw_hash = user_row["password_hash"]
        if payload.new_password:
            if not payload.current_password or not verify_password(
                payload.current_password, user_row["password_hash"]
            ):
                raise HTTPException(
                    status_code=400, detail="Current password is incorrect"
                )
            new_pw_hash = hash_password(payload.new_password)

        cursor.execute(
            """
            UPDATE users
            SET full_name = %s, email = %s, password_hash = %s
            WHERE id = %s
            """,
            (new_name, new_email, new_pw_hash, user_id),
        )
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        updated = cursor.fetchone()

    return _build_user_out(db, updated)

