from datetime import date
from collections import Counter
import pymysql

conn = pymysql.connect(host='127.0.0.1', port=3306, user='root', password='', database='study_progress_db', cursorclass=pymysql.cursors.DictCursor)
with conn.cursor() as cur:
    cur.execute("SELECT u.id, sp.subsystem_id, sp.class_id FROM users u JOIN student_profiles sp ON sp.user_id = u.id WHERE u.email = 'brice@yanne.com'")
    user = cur.fetchone()
    print("User:", user)

    cur.execute("SELECT op.*, COALESCE(sp.status, 'not_started') AS student_status FROM official_progressions op LEFT JOIN student_progressions sp ON sp.progression_id = op.id AND sp.user_id = %s WHERE op.subsystem_id = %s AND op.class_id = %s ORDER BY op.start_date, op.id", (user['id'], user['subsystem_id'], user['class_id']))
    all_topics = cur.fetchall()
    print("Total topics for user:", len(all_topics))

    today = date(2026, 11, 16)
    target_week = 10
    week_topics = [t for t in all_topics if t['week_number'] == target_week]
    print(f"Week {target_week} topics: {len(week_topics)}")
    subjects = sorted(list(set(t['subject_name'] for t in week_topics)))
    print("Subjects in Week 10:", subjects)
    for t in week_topics:
        print(f"  {t['subject_name']}: {t['topic_title']} ({t['start_date']} -> {t['end_date']})")
