# StudyProgress

AI-powered student study & progression tracker built with **Flutter**, **Python FastAPI**, **MySQL (phpMyAdmin)**, and **Google Gemini**.

## Project Structure

- `database/schema.sql` — MySQL schema ready to import into **phpMyAdmin**
- `database/seed.sql` — Optional sample student, study program, and modules
- `backend/` — Python **FastAPI** REST API connecting to MySQL and Google Gemini
- `mobile/` — **Flutter** mobile app (Programs & Progression, Pomodoro Focus Timer, Background Reminders, AI Study Tutor)

---

## 1. Setup MySQL in phpMyAdmin

1. Start MySQL and phpMyAdmin (e.g., via XAMPP, Laragon, WAMP, or Docker).
2. Open **phpMyAdmin** (`http://localhost/phpmyadmin`).
3. Go to the **Import** tab and import `database/schema.sql`.
4. (Optional) Import `database/seed.sql` to populate sample student #1 (`Alex Student`) and sample study modules.

---

## 2. Setup & Run FastAPI Backend

1. Open `backend/.env` and update your MySQL credentials and Gemini API key:
   ```env
   MYSQL_HOST=127.0.0.1
   MYSQL_PORT=3306
   MYSQL_USER=root
   MYSQL_PASSWORD=
   MYSQL_DATABASE=study_progress_db
   GEMINI_API_KEY=your_google_gemini_api_key
   GEMINI_MODEL=gemini-2.5-flash
   ```
2. Start the FastAPI server from `d:\StudyProgress\backend`:
   ```powershell
   .\.venv\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```
3. Verify it works by opening `http://127.0.0.1:8000/docs` or `http://127.0.0.1:8000/health`.

---

## 3. Run the Flutter Mobile App

1. From `d:\StudyProgress\mobile`:
   ```powershell
   flutter pub get
   flutter run
   ```
2. In the app's **Settings** (gear icon):
   - **Android Emulator**: use `http://10.0.2.2:8000` (default on Android)
   - **Physical Phone (same Wi-Fi)**: use `http://<YOUR_PC_LAN_IP>:8000`
   - **Windows / Chrome**: use `http://127.0.0.1:8000`
   - Tap **Save & Test MySQL + API** to confirm connectivity.

## Background Features

- **Daily Study Reminders**: Uses `flutter_local_notifications` + `timezone` to notify the student at their chosen time every day.
- **Background Progress Digest**: Uses `workmanager` on Android/iOS to periodically call `GET /students/{id}/background-digest` and show a reminder notification if the daily study goal isn't met or a module is overdue.
- **Pomodoro Focus Timer**: Tracks focus/break sessions across tabs, logs completed minutes to MySQL, and fires a local notification when each block finishes.

