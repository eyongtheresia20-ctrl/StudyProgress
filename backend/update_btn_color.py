with open('mobile/lib/screens/student_home_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''        FilledButton.icon(
          onPressed: () => onEditQuestionnaire(0),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF13346B),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.edit_outlined),
          label: Text(s.updateQuestionnaire),
        ),'''

repl = '''        FilledButton.icon(
          onPressed: () => onEditQuestionnaire(0),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF13346B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
          label: Text(
            s.updateQuestionnaire,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),'''

assert target in text, "Target not found in student_home_screen.dart"
text = text.replace(target, repl, 1)

with open('mobile/lib/screens/student_home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated updateQuestionnaire button styling with pure white text!')
