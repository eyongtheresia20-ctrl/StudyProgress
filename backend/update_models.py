with open('backend/app/services/ai_service.py', 'r', encoding='utf-8') as f:
    text = f.read().replace('\r\n', '\n')

old_models = """_FALLBACK_MODELS = (
    "gemini-3.1-flash-lite",
    "gemini-3.5-flash-lite",
    "gemini-3.6-flash",
    "gemini-3.8-flash",
    "gemini-3.7-flash",
)"""

new_models = """_FALLBACK_MODELS = (
    "gemini-3.5-flash",
    "gemini-3.5-flash-lite",
    "gemini-3.8-flash",
    "gemini-3.1-flash-lite",
    "gemini-3.7-flash",
    "gemini-3.6-flash",
)"""

assert old_models in text, "old_models not found"
text = text.replace(old_models, new_models)
with open('backend/app/services/ai_service.py', 'w', encoding='utf-8') as f:
    f.write(text)
print("Updated _FALLBACK_MODELS successfully!")

