with open('backend/app/services/ai_service.py', 'r', encoding='utf-8') as f:
    content = f.read()

old_func = """def _enforce_personalized_greeting(notes: str, student_name: str, is_fr: bool = False) -> str:
    \"\"\"Ensure teacher lesson notes always greet the student by their actual first name, never 'class' or generic.\"\"\"
    raw_s = (student_name or "").strip()
    if not raw_s or raw_s.lower() in ("student", "the student", "l'élève", "élève", "student name"):
        s_first = "Bryan"
    else:
        s_first = raw_s.split()[0].capitalize()

    target_greeting = f"Bonjour {s_first} !" if is_fr else f"Good morning, {s_first}!"
    if target_greeting.lower() in notes[:300].lower():
        return notes

    # Replace any generic greetings like Good morning, class! or Welcome, class!
    generic_pattern = re.compile(
        r'^(#\\s+[^\\r\\n]+[\\r\\n]+)(?:Good morning,?\\s*(?:class|everyone|students?)?!|Welcome,?\\s*(?:class|everyone|students?)?!|Hello,?\\s*(?:class|everyone|students?)?!|Bonjour\\s*(?:la classe|\\u00e0 tous|chers \\u00e9l\\u00e8ves)?\\s*!|Bienvenue\\s*(?:la classe|\\u00e0 tous)?\\s*!)\\s*',
        re.IGNORECASE | re.MULTILINE,
    )
    if generic_pattern.search(notes):
        return generic_pattern.sub(r'\\g<1>' + target_greeting + ' ', notes, count=1)

    # If starts with a markdown title (# Title), inject greeting right after
    title_pattern = re.compile(r'^(#\\s+[^\\r\\n]+[\\r\\n]+)', re.MULTILINE)
    if title_pattern.search(notes):
        return title_pattern.sub(r'\\g<1>' + target_greeting + '\\n\\n', notes, count=1)
    return f"{target_greeting}\\n\\n{notes}\""""

new_func = """def _enforce_personalized_greeting(notes: str, student_name: str, is_fr: bool = False) -> str:
    \"\"\"Ensure teacher lesson notes always greet the student by their actual first name, never 'class' or generic.\"\"\"
    raw_s = (student_name or "").strip()
    if not raw_s or raw_s.lower() in ("student", "the student", "l'élève", "élève", "student name"):
        s_first = "Bryan"
    else:
        s_first = raw_s.split()[0].capitalize()

    target_greeting = f"Bonjour {s_first} !" if is_fr else f"Good morning, {s_first}!"

    # 1. Clean up any duplicated greeting or name stutters like "!Yanne !Yanne !" or multiple "Bonjour ..."
    notes = re.sub(r'(!\\s*[A-Za-zÀ-ÿ]+\\s*)+!', '!', notes)
    notes = re.sub(r'((?:Bonjour|Good morning|Hello)[^!\\n]+!)\\s*(?:Bonjour|Good morning|Hello)[^!\\n]+!', r'\\1', notes, flags=re.IGNORECASE)

    # 2. Check if a greeting with this student's name is already present near the top
    first_300 = notes[:300].lower()
    if s_first.lower() in first_300 and any(g in first_300 for g in ("bonjour", "morning", "hello", "welcome", "bienvenue")):
        return notes

    # Replace any generic greetings like Good morning, class! or Welcome, class!
    generic_pattern = re.compile(
        r'^(#\\s+[^\\r\\n]+[\\r\\n]+)(?:Good morning,?\\s*(?:class|everyone|students?)?!|Welcome,?\\s*(?:class|everyone|students?)?!|Hello,?\\s*(?:class|everyone|students?)?!|Bonjour\\s*(?:la classe|\\u00e0 tous|chers \\u00e9l\\u00e8ves)?\\s*!|Bienvenue\\s*(?:la classe|\\u00e0 tous)?\\s*!)\\s*',
        re.IGNORECASE | re.MULTILINE,
    )
    if generic_pattern.search(notes):
        return generic_pattern.sub(r'\\g<1>' + target_greeting + ' ', notes, count=1)

    # If starts with a markdown title (# Title), inject greeting right after
    title_pattern = re.compile(r'^(#\\s+[^\\r\\n]+[\\r\\n]+)', re.MULTILINE)
    if title_pattern.search(notes):
        return title_pattern.sub(r'\\g<1>' + target_greeting + '\\n\\n', notes, count=1)
    return f"{target_greeting}\\n\\n{notes}\""""

content_norm = content.replace('\r\n', '\n')
old_norm = old_func.replace('\r\n', '\n')
assert old_norm in content_norm, "old_func not found"

content_norm = content_norm.replace(old_norm, new_func)
with open('backend/app/services/ai_service.py', 'w', encoding='utf-8') as f:
    f.write(content_norm)
print("Updated ai_service.py successfully")

