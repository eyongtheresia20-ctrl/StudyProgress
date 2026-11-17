from datetime import date
from app.database import get_db
from app.routers.curriculum import _fetch_student_topics, _fetch_profile, _select_this_week_topics, _select_today_topics

gen = get_db()
db = next(gen)
try:
    profile = _fetch_profile(db, 2)
    all_topics = _fetch_student_topics(db, 2, profile.subsystem_id, profile.class_id)
    today = date(2026, 11, 16) # Monday
    weekly = _select_this_week_topics(all_topics, today, max_items=60)
    today_topics = _select_today_topics(weekly, today, max_items=4)

    print(f"Weekly topics count: {len(weekly)}")
    print("First 10 weekly topics with study_days:")
    for t in weekly[:10]:
        print(f"  [{t.study_days}] {t.subject_name} (Wk {t.week_number}): {t.topic_title[:45]}")

    print("\nToday topics (Monday):")
    for t in today_topics:
        print(f"  [{t.study_days}] {t.subject_name}: {t.topic_title[:45]}")
finally:
    gen.close()
