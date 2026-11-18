import json

import re

from typing import Any, Optional



from fastapi import HTTPException

from google import genai

from google.genai import errors as genai_errors

from google.genai import types



from app.config import get_settings

from app.schemas import (

    DiagramComparisonRow,

    DiagramEdge,

    DiagramNode,

    NoteDiagram,

    QuizQuestion,

    SceneMotion,

    SceneObject,

    SimulationData,

    SimulationScene,

    SimulationStep,

)

from app.services.web_research import (

    build_video_and_simulation_links,

    fetch_verified_topic_notes,

)



_FALLBACK_MODELS = (

    "gemini-3.5-flash-lite",

    "gemini-3.1-flash-lite",

)





def _is_visual_learner(student_ctx: Optional[dict[str, Any]]) -> bool:

    style = str((student_ctx or {}).get("learning_style") or "").lower()

    fallback = str((student_ctx or {}).get("fallback_preference") or "").lower()

    return any(

        k in f"{style} {fallback}"

        for k in ("visual", "sim", "video", "diagram", "example", "demo")

    )





class GeminiStudyAssistant:

    """Personalized Gemini AI tutor grounded in Cameroon subsystems, student hobbies, and learning style."""



    def __init__(self) -> None:

        settings = get_settings()

        self.api_key = settings.gemini_api_key.strip()

        self.model = settings.gemini_model.strip() or "gemini-3.1-flash-lite"

        self._client: Optional[genai.Client] = None

        if self.api_key:

            self._client = genai.Client(

                api_key=self.api_key,

                http_options=types.HttpOptions(

                    timeout=12000,

                    retry_options=types.HttpRetryOptions(attempts=1),

                ),

            )



    def _candidate_models(self) -> list[str]:

        candidates = [self.model, *_FALLBACK_MODELS]

        seen: set[str] = set()

        return [m for m in candidates if m and not (m in seen or seen.add(m))]



    def _call_gemini(
        self,
        system_instruction: str,
        contents: Any,
        temperature: float = 0.4,
        max_output_tokens: int = 8192,
        response_mime_type: Optional[str] = None,
    ) -> tuple[str, str]:
        assert self._client is not None
        last_err: Optional[Exception] = None
        for candidate in self._candidate_models():
            try:
                cfg_kwargs: dict[str, Any] = {
                    "system_instruction": system_instruction,
                    "temperature": temperature,
                    "max_output_tokens": max_output_tokens,
                }
                if response_mime_type:
                    cfg_kwargs["response_mime_type"] = response_mime_type
                response = self._client.models.generate_content(
                    model=candidate,
                    contents=contents,
                    config=types.GenerateContentConfig(**cfg_kwargs),
                )
                self.model = candidate
                return (response.text or "").strip(), candidate

            except genai_errors.APIError as exc:

                last_err = exc

                code = getattr(exc, "code", None)

                if code in (404, 408, 429, 500, 502, 503, 504) or any(

                    tok in str(exc).upper()

                    for tok in (

                        "NOT_FOUND",

                        "UNAVAILABLE",

                        "DEADLINE",

                        "RESOURCE_EXHAUSTED",

                        "INTERNAL",

                    )

                ):

                    continue

                raise HTTPException(

                    status_code=502,

                    detail=f"Gemini API error ({candidate}): {exc}",

                ) from exc

            except Exception as exc:

                last_err = exc

                continue

        raise HTTPException(

            status_code=502,

            detail=f"Gemini models temporarily unavailable: {last_err}",

        )



    def _generate_contents(
        self,
        system_instruction: str,
        contents: Any,
        attachment_labels: Optional[list[str]] = None,
        temperature: float = 0.4,
        max_output_tokens: int = 8192,
        response_mime_type: Optional[str] = None,
    ) -> tuple[str, str]:

        if not self._client:

            extra = (

                f"\n\nAttached media received: {', '.join(attachment_labels)}."

                if attachment_labels

                else ""

            )

            fallback = (

                "Gemini API key is not configured yet in backend/.env (GEMINI_API_KEY).\n\n"

                "Study Tip: Review your textbook definitions first, work through 2 solved examples, "

                "and then test yourself with practice questions."

                f"{extra}"

            )

            return fallback, "offline-fallback"



        text, used_model = self._call_gemini(
            system_instruction, contents, temperature=temperature, max_output_tokens=max_output_tokens, response_mime_type=response_mime_type
        )

        return text or "No response generated.", used_model



    def _generate_text(
        self,
        system_instruction: str,
        prompt: str,
        temperature: float = 0.4,
        max_output_tokens: int = 8192,
        response_mime_type: Optional[str] = None,
    ) -> tuple[str, str]:
        return self._generate_contents(
            system_instruction, prompt, temperature=temperature, max_output_tokens=max_output_tokens, response_mime_type=response_mime_type
        )



    def _student_context_str(self, student_ctx: Optional[dict[str, Any]]) -> str:

        if not student_ctx:

            return ""

        s_name = str(student_ctx.get("first_name") or student_ctx.get("student_name") or "Student").strip()

        lang = str(student_ctx.get("preferred_language") or "en").strip().lower()

        if lang == "fr":

            return (

                f"Prénom de l'élève : {s_name}\n"

                f"Langue d'enseignement obligatoire : Français (FR) — Rédiger l'INTÉGRALITÉ du cours en français naturel et soigné\n"

                f"Sous-système : {student_ctx.get('subsystem_name') or 'Enseignement secondaire francophone (MINESEC)'}\n"

                f"Classe / Niveau : {student_ctx.get('class_name') or 'Secondaire'}\n"

                f"Centres d'intérêt : {student_ctx.get('hobbies') or 'Général'}\n"

                f"Style d'apprentissage : {student_ctx.get('learning_style') or 'visuel'}\n"

            )

        return (

            f"Student First Name: {s_name}\n"

            f"Preferred Response Language: English (EN) — write the entire response in clear English\n"

            f"Student Subsystem: {student_ctx.get('subsystem_name') or 'Cameroon Secondary (MINESEC)'}\n"

            f"Class Level: {student_ctx.get('class_name') or 'Secondary'}\n"

            f"Hobbies/Leisure Activities: {student_ctx.get('hobbies') or 'General'}\n"

            f"Preferred Learning Style: {student_ctx.get('learning_style') or 'visual_simulations'}\n"

        )



    def _topic_context_str(self, topic_ctx: Optional[dict[str, Any]], is_fr: bool = False) -> str:

        if not topic_ctx:

            return ""

        if is_fr:

            return (

                f"Matière / Discipline : {topic_ctx.get('subject_name')}\n"

                f"Titre de la leçon / Sujet au programme : {topic_ctx.get('topic_title')}\n"

                f"Sous-thèmes au programme : {topic_ctx.get('subtopics') or 'Notions fondamentales'}\n"

                f"Période programmée : {topic_ctx.get('start_date')} au {topic_ctx.get('end_date')}\n"

            )

        return (

            f"Subject: {topic_ctx.get('subject_name')}\n"

            f"Topic: {topic_ctx.get('topic_title')}\n"

            f"Subtopics: {topic_ctx.get('subtopics') or 'Core curriculum concepts'}\n"

            f"Scheduled Period: {topic_ctx.get('start_date')} to {topic_ctx.get('end_date')}\n"

        )



    def ask_tutor(

        self,

        question: str,

        topic_context: Optional[dict[str, Any]] = None,

        student_context: Optional[dict[str, Any]] = None,

        conversation_history: Optional[list[dict[str, str]]] = None,

    ) -> tuple[str, str]:

        return self.ask_tutor_multimodal(

            question=question,

            topic_context=topic_context,

            student_context=student_context,

            attachments=None,

            conversation_history=conversation_history,

        )



    def ask_tutor_multimodal(

        self,

        question: str,

        topic_context: Optional[dict[str, Any]] = None,

        student_context: Optional[dict[str, Any]] = None,

        attachments: Optional[list[tuple[bytes, str, str]]] = None,

        conversation_history: Optional[list[dict[str, str]]] = None,

    ) -> tuple[str, str]:

        system = (

            "You are Kivora AI, a warm, encouraging Cameroon secondary classroom teacher helping one-on-one. "

            "Teach directly to the student in plain, approachable teacher language — NOT like an encyclopedia.\n"

            "Rules:\n"

            "- DIRECT FOCUS & RELEVANCE RULE: Answer ONLY and DIRECTLY what the student asks or uploads in the image. "

            "NEVER lecture or make unsolicited commentary about the student's personal profile, academic series, or career goals (for example, NEVER say 'even though your main focus in Terminale STT is marketing...'). "

            "If an image or problem is provided, IMMEDIATELY solve and explain what is in that image directly and concisely.\n"

            "- 100% MATHEMATICAL & SCIENTIFIC ACCURACY RULE: When an image contains an exercise, formula, equation, or diagram, transcribe every equation, variable, number, sign (+/-), and coordinate with 100% exact precision. "

            "Every step of mathematical working, substitution, and logic must be rigorous, checked, and 100% accurate. "

            "Conclude with a clear, definitive statement of the answer.\n"

            "- NO FORCED SUBJECT: If no curriculum topic is specified (open chat / direct question mode), teach the subject naturally based solely on what the question or image asks.\n"

            "- GREETING & CASUAL CHAT RULE: If the student simply greets you (e.g. 'hello', 'hi', 'bonjour', 'coucou') or sends a conversational greeting without a specific problem, reply warmly, concisely, and politely in 1-2 friendly sentences (e.g. 'Hello! How can I help you with your studies today? What subject or topic are you working on?'). NEVER fabricate an unsolicited math problem, limit formula, equation, or lecture when the student simply said hello.\n"

            "- If handwritten work images, textbook photos, or audio recordings are provided, inspect EVERY line closely, "

            "spot any slight slip, tell the student clearly WHY something is right or wrong, and show the exact fix step by step.\n"

            "- Whenever comparing two concepts (or right vs wrong ideas), include a clean Markdown Comparison Table (`| Feature | ... | ... |`).\n"

            "- NEVER use raw LaTeX (`$x^2$`, `$$...$$`, `\\frac`). Write all math in clean readable notation (`x²`, `x³`, `√`, `±`, `×`, `÷`, `≤`, `≥`, `≠`, `π`, `(a/b)`).\n"

            "- For Mathematics or Science questions, ALWAYS state the **Key Formula:** first, explain what each letter/symbol means, explain WHY each step is done like a patient teacher teaching a child, and show every line of working.\n"

            "- Use `Teacher Tip:` and `Exam Watch-Out:` callout lines where helpful, plus relatable analogies from their hobbies/leisure.\n"

            "- CHAT RESPONSE SPEED & CONCISENESS: Act like ChatGPT — fast, direct, accurate, and helpful. Do NOT output a simulation unless the student explicitly asks to see a simulation, animation, or video. When the student explicitly asks for a simulation, append at the very end `===SIMULATION_JSON===` followed by valid JSON matching:\n"

            '`{"title":"...","hobby_connection":"...","learning_style_focus":"...","scenario":"...","steps":[{"step_number":1,"title":"...","action":"...","visual_model":"","outcome":"...","scene":{"environment":"nature|biology|chemistry|physics|circuit|math|cs|geography|commerce|humanities","objects":[{"sprite":"sun|cloud|mountain|globe|plant|leaf|root|stem|cell|heart|person|shop|bank|coin|document|book|scale|truck|beaker|flame|atom|crystal|battery|bulb|magnet|wave|axes|triangle|cpu|database|block|chart|drop","label":"Short Label","x":0.22,"y":0.5,"color":"blue|green|amber|red|purple|teal","scale":1.0}],"motions":[{"from_x":0.22,"from_y":0.5,"to_x":0.78,"to_y":0.5,"particle":"drop|bubble|electron|spark|coin|photon|arrow","color":"cyan|amber|green|purple|red","label":""}]}}],"key_takeaway":"..."}`\n'

            "and ending with `===END_SIMULATION===`. Space objects far apart horizontally (x around 0.18, 0.50, 0.82).\n"

            "- End your explanation with one quick check question for the student."

        )

        effective_question = question.strip() or (

            "Please examine the attached picture(s) and/or listen to the attached audio recording, "

            "identify any slight error, and explain the solution step by step like a patient teacher."

        )

        history_str = ""

        if conversation_history:

            history_str = "Previous Conversation Context (like ChatGPT, use this context to understand and accurately answer follow-ups):\n"

            for turn in conversation_history:

                role_label = "Student" if turn.get("role") == "user" else "Teacher"

                history_str += f"{role_label}: {turn.get('text', '')}\n"

            history_str += "\n"



        prompt_text = (

            f"{self._student_context_str(student_context)}"

            f"{self._topic_context_str(topic_context)}\n"

            f"{history_str}"

            f"Student Current Question:\n{effective_question}"

        )

        valid_attachments = [item for item in (attachments or []) if item[0]]

        if not valid_attachments:

            return self._generate_contents(system, prompt_text, temperature=0.2, max_output_tokens=1200)



        parts: list[Any] = [prompt_text]

        labels: list[str] = []

        for raw_bytes, mime_type, filename in valid_attachments:

            parts.append(types.Part.from_bytes(data=raw_bytes, mime_type=mime_type))

            labels.append(f"{filename} ({mime_type})")

        return self._generate_contents(system, parts, attachment_labels=labels, temperature=0.2, max_output_tokens=1200)



    def translate_text(self, text: str, target_lang: str) -> tuple[str, str]:

        """Rapidly translate educational markdown text to French or English."""

        clean = (text or "").strip()

        if not clean:

            return "", "noop"

        lang_target = "French (Français)" if target_lang.lower().startswith("fr") else "English"

        system = (

            f"You are a lightning-fast academic translator for Cameroon secondary education. "

            f"Translate the following educational notes/response into natural, fluent {lang_target}.\n"

            "CRITICAL RULES:\n"

            "- Keep all Markdown formatting (headings, bold, bullet points, callout boxes, tables) intact.\n"

            "- Keep all LaTeX mathematical formulas and equations ($...$ or $$...$$) exactly intact.\n"

            "- Do NOT include conversational filler or preambles. Output ONLY the translated content directly."

        )

        return self._generate_text(system, clean, temperature=0.1)



    def transcribe_audio(

        self,

        audio_bytes: bytes,

        mime_type: str,

        language: str = "en",

    ) -> tuple[str, str]:

        """Accurately transcribe spoken student audio using Gemini."""

        if not audio_bytes:

            return "", "empty"

        if not self._client:

            return "", "offline-fallback"



        lang_hint = "French" if language.lower().startswith("fr") else "English"

        system = (

            "You are an accurate speech-to-text transcriber for Cameroon secondary students "

            "(English and French academic content, including mathematics and science terms). "

            "Transcribe what the speaker says faithfully and cleanly with proper spelling and punctuation. "

            "Output ONLY the transcribed text — no explanations, no labels, no quotes."

        )

        prompt = (

            f"Transcribe this audio recording accurately. Primary language hint: {lang_hint} "

            "(preserve French or English words exactly as spoken)."

        )

        parts: list[Any] = [

            prompt,

            types.Part.from_bytes(data=audio_bytes, mime_type=mime_type),

        ]

        return self._call_gemini(system, parts, temperature=0.1)



    def summarize_topic(

        self,

        topic_context: dict[str, Any],

        student_context: Optional[dict[str, Any]] = None,

    ) -> tuple[

        str,

        str,

        list[dict[str, str]],

        list[NoteDiagram],

        Optional[SimulationData],

    ]:

        """Search online educational references, teach complete notes like a real teacher, and build visual diagrams + AI animated video explainer."""

        subject_name = str(topic_context.get("subject_name") or "")

        topic_title = str(topic_context.get("topic_title") or "")

        subtopics = topic_context.get("subtopics")

        lang = str(

            (student_context or {}).get("preferred_language") or "en"

        ).strip().lower()

        is_fr = lang == "fr"

        student_name = str(

            (student_context or {}).get("first_name")

            or (student_context or {}).get("student_name")

            or ("l'élève" if is_fr else "the student")

        ).strip()

        hobbies = str((student_context or {}).get("hobbies") or "everyday life")

        learning_style = str(

            (student_context or {}).get("learning_style") or "visual_simulations"

        )



        research_dossier = ""

        sources: list[dict[str, str]] = []

        if self._client:

            research_dossier, sources = fetch_verified_topic_notes(

                subject_name=subject_name,

                topic_title=topic_title,

                subtopics=subtopics,

                class_name=(student_context or {}).get("class_name"),

                language=lang,

            )



        if not self._client:

            offline = (

                f"## {('Leçon' if is_fr else 'Teacher Lesson')}: {topic_title}\n\n"

                + (

                    "Passons en revue cette leçon étape par étape.\n\n"

                    "**Conseil de l'enseignant :** Connectez GEMINI_API_KEY dans backend/.env pour générer le cours complet vérifié, les schémas interactifs et la simulation animée.\n\n"

                    "| Aspect | Concept A | Concept B |\n"

                    "| --- | --- | --- |\n"

                    "| Définition | Principe fondamental de la leçon | Notion complémentaire ou associée |\n"

                    "| Application | Utilisé dans les exercices types | Utilisé dans les cas avancés d'examen |"

                    if is_fr

                    else "Let us walk through today's lesson together step by step.\n\n"

                    "Teacher Tip: Connect GEMINI_API_KEY in backend/.env to generate your full verified lesson notes, visual diagrams, and AI video walkthrough.\n\n"

                    "| Feature | Core Concept A | Core Concept B |\n"

                    "| --- | --- | --- |\n"

                    "| Meaning | Primary principle of the topic | Contrasting or related case |\n"

                    "| Application | Used in standard class problems | Used in special/exam scenarios |"

                )

            )

            return (

                offline,

                "offline-fallback",

                sources,

                _build_fallback_diagrams(subject_name, topic_title),

                _build_fallback_simulation(

                    subject_name, topic_title, hobbies, learning_style

                ),

            )



        if is_fr:

            system = (

                "Tu es un enseignant modèle et captivant de l'enseignement secondaire au Cameroun (programmes officiels francophones MINESEC).\n"

                "RÈGLE ABSOLUE DE LANGUE : ÉCRIS L'INTÉGRALITÉ DU CONTENU EN FRANÇAIS NATUREL ET PÉDAGOGIQUE (titres, paragraphes, formules, exemples, schémas, légendes et simulation). AUCUN mot en anglais !\n"

                "Adopte la voix chaleureuse d'un professeur qui enseigne à son élève ('Regardons ensemble...', 'Imaginez que...', 'Remarquez que...', 'À l'examen officiel, faites attention à...').\n"

                "Citer les sources [Source 1], [Source 2] au fil du texte.\n\n"

                "RÈGLE MATHÉMATIQUES & FORMULES : Ne JAMAIS entourer de simples nombres avec des symboles dollar (interdit: $10$, $7$). Écris tous les chiffres et équations en notation claire naturelle (ex: 10, 7, x² + 7x + 10 = 0). Décompose chaque formule avec pédagogie : nom des variables, utilité, et démarche étape par étape.\n\n"

                "Renvoie UNIQUEMENT un objet JSON valide sans balises markdown selon ce schéma exact :\n"

                "{\n"

                '  "notes": "Cours complet en Markdown en français : \\n'

                '    - Débute par # [Titre de la leçon] et une introduction captivante montrant l\'utilité dans la vie réelle au Cameroun.\\n'

                '    - Définitions, lois, classifications et sous-thèmes développés sous des ## Titres clairs et paragraphes digestes.\\n'

                '    - Pour les maths et sciences : section ## Formules clés et règles où chaque formule est mise en valeur par **Formule clé :** [Formule], avec explication des lettres et méthode pas à pas.\\n'

                '    - Inclus des lignes **Conseil de l\'enseignant :** et **Attention à l\'examen :** pour éviter les pièges.\\n'

                '    - Tableau comparatif Markdown comparant 2 aspects majeurs (`| Critère | Notion A | Notion B |`).\\n'

                '    - 2–3 Exemples résolus (Facile -> Moyen -> Examen) détaillant chaque étape de calcul et une vérification, plus une Liste de révision pour l\'examen.",\n'

                '  "diagrams": [\n'

                "    {\n"

                '      "diagram_type": "comparison",\n'

                '      "title": "Comparaison visuelle : Concept A vs Concept B",\n'

                '      "subtitle": "Distinction clé",\n'

                '      "left_label": "Concept A",\n'

                '      "right_label": "Concept B",\n'

                '      "comparison_rows": [\n'

                '        {"criterion": "Définition / Rôle", "left_value": "...", "right_value": "..."},\n'

                '        {"criterion": "Avantage clé", "left_value": "...", "right_value": "..."},\n'

                '        {"criterion": "Limite / Piège", "left_value": "...", "right_value": "..."},\n'

                '        {"criterion": "Exemple concret", "left_value": "...", "right_value": "..."}\n'

                "      ],\n"

                '      "takeaway": "Synthèse comparative en une phrase"\n'

                "    },\n"

                "    {\n"

                '      "diagram_type": "flow",\n'

                '      "title": "Schéma conceptuel du mécanisme",\n'

                '      "subtitle": "Étapes de fonctionnement",\n'

                '      "nodes": [\n'

                '        {"id": "n1", "label": "Point de départ", "detail": "Entrée ou cause", "role": "start"},\n'

                '        {"id": "n2", "label": "Mécanisme central", "detail": "Action / transformation", "role": "process"},\n'

                '        {"id": "n3", "label": "Résultat obtenu", "detail": "Effet / conclusion", "role": "outcome"}\n'

                "      ],\n"

                '      "edges": [\n'

                '        {"from_id": "n1", "to_id": "n2", "label": "conduit à"},\n'

                '        {"from_id": "n2", "to_id": "n3", "label": "produit"}\n'

                "      ],\n"

                '      "takeaway": "Enseignement clé en une phrase"\n'

                "    }\n"

                "  ]\n"

                "}"

            )

        else:

            system = (

                "You are a warm, master Cameroon secondary school teacher explaining a complete lesson in class.\n"

                "Write in the voice of a real teacher speaking to your student ('Let us look at...', 'Imagine you are...', 'Notice how...', 'In your exam, watch out for...').\n"

                "Do NOT sound like a dry encyclopedia dump or numbered corporate report. Make it crystal-clear, engaging, complete from start to finish, and grounded in the verified sources provided (cite [Source 1], [Source 2] inline where facts come from those references).\n\n"

                "MATHEMATICS & NUMBERS RULE: NEVER wrap standalone numbers or expressions in dollar signs (forbidden: $10$, $7$). Write clean natural notation: 10, 7, x² + 7x + 10. Explain every formula step-by-step like a master teacher: what each letter stands for, why each step is done, and a check step.\n\n"

                "Return ONLY valid JSON with no markdown fences matching this EXACT schema:\n"

                "{\n"

                '  "notes": "Complete detailed teacher lesson in clean Markdown: \\n'

                '    - Start with # Lesson Title and warm opening explaining why the topic matters in real life in Cameroon.\\n'

                '    - NEVER use raw LaTeX ($...$ or $$...$$ or \\\\frac). Write all math in clean readable notation using Unicode (x², x³, √, ±, ×, ÷, ≤, ≥, ≠, π, (a/b)).\\n'

                '    - Teach every definition, rule, type/classification, law, mechanism, and subtopic thoroughly using clear ## Sections and short digestible paragraphs.\\n'

                '    - For Mathematics and Science: include a dedicated ## Key Formulas & Rules section where EVERY formula is placed in a **Key Formula:** callout line, explain clearly what every letter/symbol stands for, when to use the formula, and the step-by-step method (WHY each step is done so a student truly understands).\\n'

                '    - Use **Teacher Tip:** and **Exam Watch-Out:** lines to coach the student on common mistakes.\\n'

                '    - Include a clear Markdown Comparison Table comparing two key concepts/forms/methods from this lesson (`| Aspect | Concept A | Concept B |`).\\n'

                '    - Include 2–3 progressive Worked Examples (Easy -> Medium -> Exam-level) showing every single line of working and a Check step, plus a Quick Exam Revision Checklist.",\n'

                '  "diagrams": [\n'

                "    {\n"

                '      "diagram_type": "comparison",\n'

                '      "title": "Visual Comparison: Concept A vs Concept B",\n'

                '      "subtitle": "How to tell them apart at a glance",\n'

                '      "left_label": "Concept A",\n'

                '      "right_label": "Concept B",\n'

                '      "comparison_rows": [\n'

                '        {"criterion": "Meaning / Role", "left_value": "...", "right_value": "..."},\n'

                '        {"criterion": "Key Advantage", "left_value": "...", "right_value": "..."},\n'

                '        {"criterion": "Limitation / Risk", "left_value": "...", "right_value": "..."},\n'

                '        {"criterion": "Real Example", "left_value": "...", "right_value": "..."}\n'

                "      ],\n"

                '      "takeaway": "One sentence summary comparing the two"\n'

                "    },\n"

                "    {\n"

                '      "diagram_type": "flow",\n'

                '      "title": "Visual Concept Flow / Process Diagram",\n'

                '      "subtitle": "Step-by-step how the concept works",\n'

                '      "nodes": [\n'

                '        {"id": "n1", "label": "Start / Input", "detail": "Short clear caption", "role": "start"},\n'

                '        {"id": "n2", "label": "Core Mechanism", "detail": "What changes here", "role": "process"},\n'

                '        {"id": "n3", "label": "Key Outcome", "detail": "Final result", "role": "outcome"}\n'

                "      ],\n"

                '      "edges": [\n'

                '        {"from_id": "n1", "to_id": "n2", "label": "causes / leads to"},\n'

                '        {"from_id": "n2", "to_id": "n3", "label": "produces"}\n'

                "      ],\n"

                '      "takeaway": "Visual takeaway"\n'

                "    }\n"

                "  ]\n"

                "}"

            )

        if is_fr:

            prompt = (

                f"{self._student_context_str(student_context)}\n"

                f"{self._topic_context_str(topic_context, is_fr=True)}\n"

                f"{research_dossier}\n\n"

                "RÈGLE ABSOLUE DE LANGUE ET DE CONFORMITÉ AU PROGRAMME (MINESEC CAMEROUN) :\n"

                "- Rédige l'INTÉGRALITÉ du cours en FRANÇAIS naturel, clair et soigné (titres, paragraphes, formules, exemples, schémas, légendes et simulation). AUCUN mot en anglais !\n"

                "- Enseigne le cours de manière vivante et rigoureuse comme un professeur dévoué de lycée au Cameroun.\n"

                "- Le cours doit porter STRICTEMENT et UNIQUEMENT sur le sujet indiqué : ne dérive jamais hors du thème.\n"

                "- Compare deux aspects essentiels avec un schéma de comparaison et un tableau Markdown.\n"

                "- Inclus un schéma fonctionnel/conceptuel (flow) clair et 2 à 3 exemples d'application corrigés pas à pas.\n"

                "- Ne génère AUCUNE simulation virtuelle ou dessin animé : concentre 100% du contenu sur le cours, les formules, le tableau comparatif et les exemples rigoureux."

            )

        else:

            prompt = (

                f"{self._student_context_str(student_context)}\n"

                f"{self._topic_context_str(topic_context, is_fr=False)}\n"

                f"{research_dossier}\n\n"

                "STRICT TOPIC FOCUS & CURRICULUM ALIGNMENT RULE (CAMEROON MINESEC):\n"

                "- Teach the full lesson clearly like a caring human teacher in Cameroon's secondary school curriculum.\n"

                "- Keep the lesson 100% focused strictly on the specified subject and topic. Do not drift into unrelated concepts.\n"

                "- Compare two important aspects with a visual Comparison Diagram + table,\n"

                "- Include a Flow/Concept Diagram, 2-3 progressive worked examples with step-by-step checks, and do NOT generate any simulation or cartoon lab: focus 100% on the core lesson notes, definitions, comparison table, and worked examples."

            )

        raw_text, model_used = self._generate_text(system, prompt, temperature=0.2, max_output_tokens=2200, response_mime_type="application/json")

        notes, diagrams, simulation = _parse_summary_json(

            raw_text,

            subject_name,

            topic_title,

            hobbies,

            learning_style,

            student_name=student_name,

            is_fr=is_fr,

        )

        return notes, model_used, sources, diagrams, simulation



    def generate_quiz(

        self,

        topic_context: dict[str, Any],

        student_context: Optional[dict[str, Any]] = None,

        num_questions: int = 5,

    ) -> tuple[str, list[QuizQuestion], str]:

        if not self._client:

            sample = [

                QuizQuestion(

                    question=f"[Offline Demo MCQ] Which approach builds lasting mastery in '{topic_context.get('topic_title')}'?",

                    question_type="mcq",

                    options=[

                        "Active recall with worked exercises",

                        "Reading passively without practice",

                        "Skipping difficult parts",

                        "Memorizing without understanding",

                    ],

                    correct_index=0,

                    marks=1,

                    explanation="Add GEMINI_API_KEY in backend/.env for live curriculum quizzes.",

                ),

                QuizQuestion(

                    question=f"[Offline Demo Short Answer] State two key principles of '{topic_context.get('topic_title')}' and give one everyday example.",

                    question_type="short_answer",

                    marks=4,

                    expected_points=[

                        "Clear accurate definition",

                        "Relevant everyday or syllabus example",

                    ],

                    explanation="Write cleanly or upload a photo of your paper for AI line-by-line checking.",

                ),

                QuizQuestion(

                    question=f"[Offline Demo Essay] Discuss why '{topic_context.get('topic_title')}' matters in real life and analyze two advantages and one limitation.",

                    question_type="essay",

                    marks=8,

                    expected_points=[

                        "Introduction defining the concept",

                        "Two explained advantages",

                        "One analyzed limitation",

                    ],

                    explanation="Organize into clear paragraphs before submitting or snapping your handwritten page.",

                ),

            ]

            return "Offline demo mixed quiz generated (MCQ + Short Answer + Essay).", sample, "offline-fallback"



        mcq_count = max(1, num_questions - 2) if num_questions >= 3 else num_questions

        lang = str((student_context or {}).get("preferred_language") or "en").strip().lower()

        is_fr = lang == "fr"



        if is_fr:

            system = (

                "Tu es un professeur et examinateur officiel au Cameroun (BEPC, Probatoire, Baccalauréat). "

                "RÈGLE ABSOLUE DE LANGUE : Rédige TOUTES les questions, les options de réponse, les corrigés et les explications EN FRANÇAIS IRRÉPROCHABLE. "

                "Renvoie UNIQUEMENT un objet JSON valide sans balises markdown selon cette structure exacte :\n"

                '{"questions": ['

                '{"question_type": "mcq", "question": "Question claire en français...", "options": ["Choix A", "Choix B", "Choix C", "Choix D"], "correct_index": 0, "marks": 1, "expected_points": [], "explanation": "Explication pédagogique en français..."}, '

                '{"question_type": "short_answer", "question": "Question de cours ou calcul...", "options": [], "correct_index": 0, "marks": 4, "expected_points": ["point 1", "point 2"], "explanation": "Corrigé détaillé en français..."}, '

                '{"question_type": "essay", "question": "Sujet de rédaction ou problème d\'examen...", "options": [], "correct_index": 0, "marks": 8, "expected_points": ["Introduction", "Argument 1", "Argument 2", "Conclusion"], "explanation": "Guide de correction en français..."}'

                "]}"

            )

            prompt = (

                f"{self._student_context_str(student_context)}"

                f"{self._topic_context_str(topic_context)}\n"

                f"Rédige un quiz complet de {num_questions} questions en français sur la leçon '{topic_context.get('topic_title')}' :\n"

                f"- {mcq_count} questions à choix multiples (question_type='mcq', 4 options, 1 seule bonne réponse)\n"

                + (

                    "- 1 question de cours / courte résolution (question_type='short_answer', 3-4 points, options=[])\n"

                    "- 1 sujet structuré d\'examen officiel (question_type='essay', 6-8 points, options=[])\n"

                    if num_questions >= 3

                    else ""

                )

                + "Ancre les questions dans le contexte scolaire officiel camerounais avec pédagogie et précision."

            )

        else:

            system = (

                "You are a Cameroon GCE / Examination coach. "

                "Return ONLY valid JSON with no markdown fences matching this exact structure:\n"

                '{"questions": ['

                '{"question_type": "mcq", "question": "...", "options": ["...", "...", "...", "..."], "correct_index": 0, "marks": 1, "expected_points": [], "explanation": "..."}, '

                '{"question_type": "short_answer", "question": "...", "options": [], "correct_index": 0, "marks": 4, "expected_points": ["point 1", "point 2"], "explanation": "..."}, '

                '{"question_type": "essay", "question": "...", "options": [], "correct_index": 0, "marks": 8, "expected_points": ["intro", "body point 1", "body point 2", "conclusion"], "explanation": "..."}'

                "]}"

            )

            prompt = (

                f"{self._student_context_str(student_context)}"

                f"{self._topic_context_str(topic_context)}\n"

                f"Create a rich mixed quiz of {num_questions} questions total:\n"

                f"- {mcq_count} MCQ questions (question_type='mcq', 4 options each)\n"

                + (

                    "- 1 Short Answer / Problem-Solving question (question_type='short_answer', 3-4 marks, options=[])\n"

                    "- 1 Essay / Structured Exam question (question_type='essay', 6-10 marks, options=[])\n"

                    if num_questions >= 3

                    else ""

                )

                + "Tailor scenarios so they feel relevant and engaging for this student."

            )

        raw_text, model_used = self._generate_text(system, prompt, temperature=0.25, max_output_tokens=1500, response_mime_type="application/json")

        questions = _parse_quiz_json(raw_text)

        intro_msg = (

            f"{len(questions)} questions générées (QCM, Réponse courte & Rédaction) pour {topic_context.get('topic_title')}. Répondez ci-dessous ou importez la photo de votre feuille !"

            if is_fr

            else f"Generated {len(questions)} mixed questions (MCQ, Short Answer & Essay) for {topic_context.get('topic_title')}. Answer below or upload a photo of your handwritten paper!"

        )

        return (

            intro_msg,

            questions,

            model_used,

        )



    def grade_quiz_submission(

        self,

        topic_context: Optional[dict[str, Any]],

        student_context: Optional[dict[str, Any]],

        quiz_items: list[QuizQuestion],

        typed_answers: dict[str, Any],

        student_note: str = "",

        paper_attachments: Optional[list[tuple[bytes, str, str]]] = None,

    ) -> tuple[str, str, Optional[SimulationData], list[dict[str, str]], int, str, str]:

        """Grade handwritten paper photos and/or typed quiz answers, explain why each answer is right/wrong, adapt to learning style + video simulations, and return score_percent."""

        valid_attachments = [item for item in (paper_attachments or []) if item[0]]

        hobbies = (student_context or {}).get("hobbies") or "everyday activities"

        learning_style = (student_context or {}).get("learning_style") or "visual_simulations"

        subject_name = str((topic_context or {}).get("subject_name") or "")

        topic_title = str((topic_context or {}).get("topic_title") or "Topic")

        video_suggestions: list[dict[str, str]] = []



        if not self._client:

            media_note = (

                f"Received paper photo(s): {', '.join(lbl for _, _, lbl in valid_attachments)}.\n"

                if valid_attachments

                else ""

            )

            sim = _build_fallback_simulation(

                subject_name=subject_name,

                topic_title=topic_title,

                hobbies=hobbies,

                learning_style=learning_style,

            )

            return (

                f"{media_note}[Offline Demo Correction] Connect GEMINI_API_KEY for full handwriting inspection, error explanation, and AI grading.",

                "Pending API Key",

                sim,

                video_suggestions,

                50,

                "Offline demo review",

                "offline-fallback",

            )



        quiz_payload = json.dumps([q.model_dump() for q in quiz_items], ensure_ascii=False)

        answers_payload = json.dumps(typed_answers, ensure_ascii=False)

        attachment_desc = ", ".join(lbl for _, _, lbl in valid_attachments) or "None (typed/voice answers)"



        system = (

            "You are Kivora AI, a patient, eagle-eyed Cameroon secondary teacher grading a student's quiz & handwritten paper. "

            "Inspect BOTH the typed/MCQ answers AND every handwritten image attached.\n"

            "Your job:\n"

            "1. For EVERY question answered, state clearly whether it is CORRECT or INCORRECT/INCOMPLETE and explain WHY it is right or why it missed the mark.\n"

            "2. NOTICE WHAT THE STUDENT DOES NOT UNDERSTAND — catch even the slightest error (sign slip, missing keyword, wrong formula step, weak essay structure) and point to the exact mistake.\n"

            "3. EXPLAIN & CORRECT ACCORDING TO THEIR LEARNING STYLE & HOBBIES: use vivid analogies from their leisure/hobbies, and if their style is visual/simulations, make the step-by-step visual simulation concrete and describe what a video simulation shows.\n"

            "4. Estimate a fair integer `score_percent` from 0 to 100 and summarize weak concepts concisely in `weak_concepts`.\n\n"

            "Return ONLY valid JSON with no markdown fences:\n"

            "{\n"

            '  "score_percent": 75,\n'

            '  "score_summary": "e.g. 11/14 marks (79%) — Good grasp, 1 slight slip on Q4",\n'

            '  "weak_concepts": "Short comma-separated list of weak subtopics/misconceptions, or empty if mastered",\n'

            '  "feedback": "Detailed question-by-question review stating: What was right/wrong & WHY, Slight errors spotted & exact fix, Learning-style + hobby explanation for what the student missed",\n'

            '  "simulation": {\n'

            '    "title": "...",\n'

            '    "hobby_connection": "...",\n'

            '    "learning_style_focus": "...",\n'

            '    "scenario": "Brief engaging setup connecting the misunderstood concept to the student\'s hobby",\n'

            '    "steps": [\n'

            '      {\n'

            '        "step_number": 1,\n'

            '        "title": "...",\n'

            '        "action": "Short narrator caption describing what the animated scene shows",\n'

            '        "visual_model": "",\n'

            '        "outcome": "What the student understands after this frame",\n'

            '        "scene": {\n'

            '          "environment": "nature|biology|chemistry|physics|circuit|math|cs|geography|commerce|humanities",\n'

            '          "objects": [{"sprite": "sun|cloud|mountain|globe|plant|leaf|root|stem|cell|heart|person|shop|bank|coin|document|book|scale|truck|beaker|flame|atom|crystal|battery|bulb|magnet|wave|axes|triangle|cpu|database|block|chart|drop", "label": "...", "x": 0.22, "y": 0.50, "color": "blue|green|amber|red|purple|teal", "scale": 1.0}],\n'

            '          "motions": [{"from_x": 0.22, "from_y": 0.50, "to_x": 0.78, "to_y": 0.45, "particle": "drop|bubble|electron|spark|coin|photon|arrow", "color": "cyan|amber|green|purple|red", "label": ""}]\n'

            '        }\n'

            '      }\n'

            "    ],\n"

            '    "key_takeaway": "..."\n'

            "  }\n"

            "}"

        )



        prompt_text = (

            f"{self._student_context_str(student_context)}"

            f"{self._topic_context_str(topic_context)}\n"

            f"Attached Paper Photos: {attachment_desc}\n"

            f"Quiz Questions & Marking Scheme:\n{quiz_payload}\n\n"

            f"Student's Selected/Typed Answers:\n{answers_payload}\n\n"

            f"Student Note / Voice Context: {student_note or 'None'}\n\n"

            "Grade thoroughly, tell them why each answer is right or wrong, pinpoint what they didn't understand, adapt to their learning style, and return the JSON."

        )



        contents: Any = (

            prompt_text

            if not valid_attachments

            else [

                prompt_text,

                *[types.Part.from_bytes(data=raw, mime_type=mime) for raw, mime, _ in valid_attachments],

            ]

        )

        raw_text, model_used = self._generate_contents(

            system,

            contents,

            attachment_labels=[lbl for _, _, lbl in valid_attachments],

            temperature=0.3,

        )

        feedback, score_summary, simulation, score_percent, weak_concepts = _parse_grading_json(

            raw_text, subject_name, topic_title, hobbies, learning_style

        )

        return (

            feedback,

            score_summary,

            simulation,

            video_suggestions,

            score_percent,

            weak_concepts,

            model_used,

        )





def _parse_quiz_json(raw_text: str) -> list[QuizQuestion]:

    cleaned = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw_text.strip(), flags=re.IGNORECASE)

    match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)

    if not match:

        return []

    try:

        payload = json.loads(match.group(0))

        parsed: list[QuizQuestion] = []

        for item in payload.get("questions", []):

            q_type = str(item.get("question_type", "mcq")).strip().lower()

            if q_type not in ("mcq", "short_answer", "essay"):

                q_type = "mcq"

            options = [str(opt) for opt in (item.get("options") or [])][:4]

            if q_type == "mcq" and len(options) < 2:

                continue

            idx = int(item.get("correct_index", 0) or 0)

            if options and (idx < 0 or idx >= len(options)):

                idx = 0

            marks = int(

                item.get(

                    "marks",

                    1 if q_type == "mcq" else (4 if q_type == "short_answer" else 8),

                )

                or 1

            )

            expected_points = [

                str(pt) for pt in (item.get("expected_points") or []) if str(pt).strip()

            ]

            parsed.append(

                QuizQuestion(

                    question=str(item.get("question", "")).strip(),

                    question_type=q_type,  # type: ignore[arg-type]

                    options=options,

                    correct_index=idx,

                    marks=marks,

                    expected_points=expected_points,

                    explanation=str(item.get("explanation", "")).strip(),

                )

            )

        return parsed

    except (json.JSONDecodeError, TypeError, ValueError):

        return []





def _parse_scene_dict(scene_raw: Any) -> Optional[SimulationScene]:

    if not isinstance(scene_raw, dict):

        return None

    objs: list[SceneObject] = []

    for o in scene_raw.get("objects") or []:

        if not isinstance(o, dict):

            continue

        try:

            x = max(0.08, min(0.92, float(o.get("x", 0.5))))

            y = max(0.12, min(0.88, float(o.get("y", 0.5))))

            scale = max(0.6, min(1.5, float(o.get("scale", 1.0))))

        except Exception:

            x, y, scale = 0.5, 0.5, 1.0

        objs.append(

            SceneObject(

                sprite=str(o.get("sprite") or "cell").strip().lower(),

                label=str(o.get("label") or "").strip()[:32],

                x=x,

                y=y,

                color=str(o.get("color") or "blue").strip().lower(),

                scale=scale,

            )

        )

    motions: list[SceneMotion] = []

    for m in scene_raw.get("motions") or []:

        if not isinstance(m, dict):

            continue

        try:

            fx = max(0.05, min(0.95, float(m.get("from_x", 0.2))))

            fy = max(0.1, min(0.9, float(m.get("from_y", 0.5))))

            tx = max(0.05, min(0.95, float(m.get("to_x", 0.8))))

            ty = max(0.1, min(0.9, float(m.get("to_y", 0.5))))

        except Exception:

            fx, fy, tx, ty = 0.2, 0.5, 0.8, 0.5

        motions.append(

            SceneMotion(

                from_x=fx,

                from_y=fy,

                to_x=tx,

                to_y=ty,

                particle=str(m.get("particle") or "drop").strip().lower(),

                color=str(m.get("color") or "cyan").strip().lower(),

                label=str(m.get("label") or "").strip()[:16],

            )

        )

    if not objs and not motions:

        return None

    return SimulationScene(

        environment=str(scene_raw.get("environment") or "biology").strip().lower(),

        objects=objs[:8],

        motions=motions[:6],

    )





def _parse_simulation_dict(sim_raw: Any) -> Optional[SimulationData]:

    if not isinstance(sim_raw, dict):

        return None

    steps: list[SimulationStep] = []

    for i, step in enumerate(sim_raw.get("steps") or [], 1):

        if not isinstance(step, dict):

            continue

        steps.append(

            SimulationStep(

                step_number=int(step.get("step_number", i) or i),

                title=str(step.get("title") or f"Scene {i}").strip(),

                action=str(step.get("action") or "").strip(),

                visual_model=str(step.get("visual_model") or "").strip(),

                outcome=str(step.get("outcome") or "").strip(),

                scene=_parse_scene_dict(step.get("scene")),

            )

        )

    if not steps:

        return None

    return SimulationData(

        title=str(sim_raw.get("title") or "AI Animated Explainer").strip(),

        hobby_connection=str(sim_raw.get("hobby_connection") or "").strip(),

        learning_style_focus=str(sim_raw.get("learning_style_focus") or "").strip(),

        scenario=str(sim_raw.get("scenario") or "").strip(),

        steps=steps,

        key_takeaway=str(sim_raw.get("key_takeaway") or "").strip(),

    )





def _build_fallback_diagrams(subject_name: str, topic_title: str) -> list[NoteDiagram]:

    short_topic = (topic_title or subject_name or "Concept").split("—")[-1].strip()[:60]

    return [

        NoteDiagram(

            diagram_type="comparison",

            title=f"Key Comparison in {short_topic}",

            subtitle="Side-by-side study breakdown",

            left_label="Core Principle / Form A",

            right_label="Contrasting Case / Form B",

            comparison_rows=[

                DiagramComparisonRow(

                    criterion="Definition",

                    left_value="Standard rule & structure covered in class.",

                    right_value="Alternative case or special exam condition.",

                ),

                DiagramComparisonRow(

                    criterion="Exam Focus",

                    left_value="Check keywords, units, and standard steps.",

                    right_value="Watch for exceptions and opposite cases.",

                ),

            ],

            takeaway="Compare features carefully before picking your final method.",

        ),

        NoteDiagram(

            diagram_type="flow",

            title=f"How {short_topic} Flows",

            subtitle="Concept map from start to solution",

            nodes=[

                DiagramNode(id="n1", label="1. Definition", detail="Core meaning", role="start"),

                DiagramNode(id="n2", label="2. Rule / Process", detail="Key steps", role="process"),

                DiagramNode(id="n3", label="3. Real Application", detail="Exam & daily use", role="outcome"),

            ],

            edges=[

                DiagramEdge(from_id="n1", to_id="n2", label="guides"),

                DiagramEdge(from_id="n2", to_id="n3", label="solves"),

            ],

            takeaway="Follow this sequence step by step during revision.",

        ),

    ]





def _is_simulatable_subject(subject_name: str, topic_title: str) -> bool:

    """Return True only if the topic is a STEM/science concept with a genuine physical/mathematical simulation."""

    subj = (subject_name or "").lower()

    topic = (topic_title or "").lower()

    txt = f"{subj} {topic}"

    non_sim = (

        "citizen", "civic", "english", "french", "français", "history", "histoire",

        "literature", "litterature", "philos", "religion", "law", "droit",

        "humanities", "arts and culture", "arts & culture", "sociolog", "national symbol",

        "national culture", "national language", "family life", "guidance"

    )

    if any(k in txt for k in non_sim):

        return False

    # Geography only allows simulation if explicitly physical cycle/volcano/tectonics

    if "geog" in subj or "geol" in subj:

        return any(p in txt for p in ("water cycle", "cycle de l'eau", "volcan", "tecton", "erosion", "plate", "earthquake"))

    # Only STEM

    sim_allowed = (

        "math", "physic", "chem", "biolog", "comput", "ict", "circuit",

        "electron", "science", "algebr", "mechanic"

    )

    return any(k in subj or k in topic for k in sim_allowed)





def _detect_subject_domain(subject_name: str, topic_title: str) -> str:

    subj = (subject_name or "").lower()

    topic = (topic_title or "").lower()

    txt = f"{subj} {topic}"



    # Check plant/biology nature specifics only for science/biology subjects

    if any(k in subj for k in ("biolog", "botan", "agric", "science", "nature")) and any(

        k in txt for k in ("plant", "xylem", "phloem", "transpir", "photosynth", "root", "leaf", "botan", "agric")

    ):

        return "nature"

    if any(k in subj for k in ("geog", "earth", "geol")) or any(

        k in txt for k in ("water cycle", "climate", "weather", "volcan", "tecton", "river", "mountain", "erosion")

    ):

        return "geography"

    if any(k in txt for k in ("biolog", "cell", "heart", "blood", "osmosis", "enzyme", "reproduc", "digest", "respir", "mitosis", "nerv")):

        return "biology"

    if any(k in txt for k in ("chem", "acid", "base", "sulfur", "allotrope", "atom", "mole", "reaction", "periodic", "bond", "electrolys")):

        return "chemistry"

    if any(k in txt for k in ("circuit", "electric", "current", "voltage", "resistor", "ohm")):

        return "circuit"

    if any(k in subj for k in ("math", "algebr", "geomet", "trigon", "calcul", "statist")) or any(

        k in txt for k in ("algebr", "geomet", "trigon", "calcul", "equat", "function", "quadratic", "parabol", "probab", "statist", "vector", "matrix", "coordinate")

    ):

        return "math"

    if any(k in txt for k in ("physic", "force", "motion", "wave", "optic", "light", "energy", "magnet", "pressure", "gravity")):

        return "physics"

    if any(k in txt for k in ("comput", "ict", "informat", "program", "algorithm", "network", "database", "logic gate", "binary", "coding")):

        return "cs"

    if any(k in txt for k in ("econom", "commerc", "account", "business", "trade", "market", "bank", "profit", "proprietor", "entrepreneur", "finance")):

        return "commerce"

    if any(k in txt for k in ("hist", "citizen", "civic", "law", "lit", "english", "french", "français", "philos", "grammar", "essay", "relig")):

        return "humanities"

    return "physics"





def _build_fallback_simulation(

    subject_name: str,

    topic_title: str,

    hobbies: str = "everyday life",

    learning_style: str = "visual_simulations",

) -> SimulationData:

    short_topic = (topic_title or subject_name or "Concept").split("—")[-1].strip()[:60]

    domain = _detect_subject_domain(subject_name, topic_title)



    domain_configs: dict[str, list[dict[str, Any]]] = {

        "math": [

            {"title": "Set Up Known Values", "action": f"Identify the variables, axes, or given numbers in {short_topic}.", "outcome": "Clear equation setup before solving.", "env": "math", "objs": [("axes", "Given Input", 0.22, 0.50, "blue"), ("triangle", "Rule / Formula", 0.52, 0.48, "purple"), ("chart", "Target Value", 0.82, 0.50, "green")], "mot": ("spark", "cyan", "Solve")},

            {"title": "Apply Step-by-Step Operation", "action": "Keep both sides balanced and simplify one operation at a time.", "outcome": "Avoids sign and arithmetic errors.", "env": "math", "objs": [("scale", "Keep Balanced", 0.24, 0.50, "amber"), ("axes", "Curve / Graph", 0.54, 0.46, "teal"), ("document", "Solution", 0.82, 0.50, "green")], "mot": ("photon", "amber", "f(x)")},

            {"title": "Verify & Interpret Graph", "action": f"Check your final solution in {short_topic} against the graph or question.", "outcome": "Confirms full exam marks.", "env": "math", "objs": [("axes", "Verify Point", 0.28, 0.50, "blue"), ("chart", "Result Confirmed", 0.76, 0.50, "green")], "mot": ("spark", "green", "Check")},

        ],

        "chemistry": [

            {"title": "Reactants Come Together", "action": f"Observe how particles or reactants combine in {short_topic}.", "outcome": "Shows initial chemical state clearly.", "env": "chemistry", "objs": [("atom", "Reactant A", 0.20, 0.48, "blue"), ("beaker", "Reaction Vessel", 0.52, 0.50, "teal"), ("flame", "Activation Heat", 0.80, 0.62, "red")], "mot": ("bubble", "amber", "React")},

            {"title": "Bonds Break & Rearrange", "action": "Watch energy cause particles to collide and form new bonds.", "outcome": "Visualizes reaction rate and bonding.", "env": "chemistry", "objs": [("beaker", "Active Mixture", 0.30, 0.50, "amber"), ("crystal", "New Product", 0.76, 0.48, "green")], "mot": ("spark", "cyan", "Yield")},

            {"title": "Final Balanced Equation", "action": "Check state symbols, conservation of mass, and formula balance.", "outcome": "Clean balanced equation verified.", "env": "chemistry", "objs": [("document", "Balanced Formula", 0.28, 0.50, "purple"), ("crystal", "Pure Product", 0.76, 0.48, "green")], "mot": ("spark", "green", "=")},

        ],

        "circuit": [

            {"title": "Voltage Source Drives Charge", "action": "The battery or cell pushes electrons out of the negative terminal.", "outcome": "Current begins flowing cleanly.", "env": "circuit", "objs": [("battery", "Voltage Source", 0.22, 0.52, "red"), ("bulb", "Lamp Load", 0.78, 0.46, "amber")], "mot": ("electron", "cyan", "Current (I)")},

            {"title": "Energy Transfers in Load", "action": "Moving charge delivers energy to light up the bulb or resistor.", "outcome": "Follows Ohm's Law V = I x R.", "env": "circuit", "objs": [("battery", "EMF Push", 0.22, 0.52, "red"), ("wave", "Resistance", 0.52, 0.48, "purple"), ("bulb", "Light Output", 0.80, 0.45, "amber")], "mot": ("electron", "amber", "Energy")},

        ],

        "geography": [

            {"title": "Solar Heating & Evaporation", "action": "Sunlight warms surface water, turning it into rising water vapour.", "outcome": "Warm moist air rises into the sky.", "env": "geography", "objs": [("sun", "Solar Heat", 0.18, 0.24, "amber"), ("drop", "Ocean / River", 0.48, 0.72, "teal"), ("cloud", "Vapour Rises", 0.80, 0.28, "blue")], "mot": ("drop", "cyan", "Vapour")},

            {"title": "Condensation & Precipitation", "action": "Cooling high air condenses vapour into clouds that rain over mountains.", "outcome": "Fresh water returns to land and rivers.", "env": "geography", "objs": [("cloud", "Rain Cloud", 0.30, 0.26, "blue"), ("mountain", "Highland Runoff", 0.74, 0.58, "green")], "mot": ("drop", "cyan", "Rain")},

        ],

        "cs": [

            {"title": "Data Input & Encoding", "action": f"Inputs enter the computer system as structured data for {short_topic}.", "outcome": "Clean data ready for processing.", "env": "cs", "objs": [("document", "User Input", 0.18, 0.50, "blue"), ("cpu", "CPU / Algorithm", 0.52, 0.48, "purple"), ("database", "Memory Store", 0.82, 0.50, "teal")], "mot": ("electron", "cyan", "Data")},

            {"title": "Logic Execution & Output", "action": "The processor executes step-by-step instructions and outputs the result.", "outcome": "Accurate program output produced.", "env": "cs", "objs": [("cpu", "Logic Unit", 0.28, 0.48, "purple"), ("chart", "Verified Output", 0.76, 0.50, "green")], "mot": ("spark", "green", "Output")},

        ],

        "commerce": [

            {"title": "Capital & Resource Setup", "action": f"The owner organizes capital, goods, and service for {short_topic}.", "outcome": "Enterprise ready to operate.", "env": "commerce", "objs": [("person", "Owner / Buyer", 0.18, 0.50, "blue"), ("shop", "Enterprise", 0.52, 0.48, "purple"), ("bank", "Capital / Finance", 0.82, 0.50, "teal")], "mot": ("coin", "amber", "Capital")},

            {"title": "Market Exchange & Profit", "action": "Goods/services move to customers while revenue flows back to the business.", "outcome": "Tracks costs, profit, and liability.", "env": "commerce", "objs": [("shop", "Trade Floor", 0.24, 0.50, "purple"), ("coin", "Profit Flow", 0.56, 0.48, "amber"), ("chart", "Growth", 0.82, 0.50, "green")], "mot": ("coin", "green", "Profit")},

        ],

        "humanities": [

            {"title": "Context & Core Idea", "action": f"Examine the background, key actors, and main theme of {short_topic}.", "outcome": "Sets accurate historical or textual context.", "env": "humanities", "objs": [("book", "Primary Source", 0.20, 0.50, "amber"), ("person", "Key Figures", 0.52, 0.48, "blue"), ("globe", "Wider Impact", 0.82, 0.50, "teal")], "mot": ("photon", "amber", "Context")},

            {"title": "Evidence & Balanced Argument", "action": "Weigh evidence on both sides like a balanced scale before concluding.", "outcome": "Builds top-mark essay & exam answers.", "env": "humanities", "objs": [("scale", "Weigh Arguments", 0.28, 0.50, "purple"), ("document", "Strong Essay", 0.76, 0.50, "green")], "mot": ("spark", "green", "Proof")},

        ],

    }



    if domain == "nature":

        return SimulationData(

            title=f"AI Animated Walkthrough: {short_topic}",

            hobby_connection=hobbies,

            learning_style_focus=learning_style,

            scenario=f"Visualizing water & nutrient flow in {short_topic} step by step.",

            steps=[

                SimulationStep(

                    step_number=1,

                    title="Water Absorbed from Soil",

                    action="Root hairs absorb water and mineral salts from the moist soil by osmosis.",

                    outcome="Water enters the root cortex and moves toward xylem vessels.",

                    scene=SimulationScene(

                        environment="nature",

                        objects=[

                            SceneObject(sprite="root", label="Roots in Soil", x=0.25, y=0.72, color="amber"),

                            SceneObject(sprite="stem", label="Xylem Vessel", x=0.55, y=0.48, color="teal"),

                        ],

                        motions=[

                            SceneMotion(from_x=0.28, from_y=0.72, to_x=0.52, to_y=0.50, particle="drop", color="cyan", label="H2O"),

                        ],

                    ),

                ),

                SimulationStep(

                    step_number=2,

                    title="Upward Transport in Xylem",

                    action="Water rises upward inside the stem xylem tubes driven by root pressure and transpiration pull.",

                    outcome="Stem cells receive steady water supply.",

                    scene=SimulationScene(

                        environment="nature",

                        objects=[

                            SceneObject(sprite="stem", label="Stem Xylem", x=0.45, y=0.52, color="teal"),

                            SceneObject(sprite="leaf", label="Leaf Canopy", x=0.76, y=0.30, color="green"),

                        ],

                        motions=[

                            SceneMotion(from_x=0.46, from_y=0.68, to_x=0.72, to_y=0.32, particle="drop", color="cyan", label="Sap"),

                        ],

                    ),

                ),

                SimulationStep(

                    step_number=3,

                    title="Leaf Use & Turgor Balance",

                    action="Leaves use water with sunlight for photosynthesis while turgor pressure keeps the plant upright.",

                    outcome="Healthy rigid plant ready for growth.",

                    scene=SimulationScene(

                        environment="nature",

                        objects=[

                            SceneObject(sprite="sun", label="Sunlight", x=0.18, y=0.24, color="amber"),

                            SceneObject(sprite="leaf", label="Photosynthesis", x=0.55, y=0.38, color="green"),

                            SceneObject(sprite="stem", label="Turgor Support", x=0.80, y=0.58, color="teal"),

                        ],

                        motions=[

                            SceneMotion(from_x=0.22, from_y=0.26, to_x=0.52, to_y=0.38, particle="photon", color="amber", label="Light"),

                        ],

                    ),

                ),

            ],

            key_takeaway=f"Follow water from soil -> roots -> stem xylem -> leaves in {short_topic}.",

        )



    templates = domain_configs.get(

        domain,

        [

            {"title": "Core Inputs & Principle", "action": f"Identify the key quantities and forces acting in {short_topic}.", "outcome": "Clear physical model of the system.", "env": "physics", "objs": [("atom", "Core Principle", 0.22, 0.50, "blue"), ("wave", "Interaction", 0.52, 0.48, "purple"), ("chart", "Result", 0.82, 0.50, "green")], "mot": ("photon", "cyan", "Energy")},

            {"title": "System Transformation", "action": f"Watch cause and effect move through {short_topic} step by step ({hobbies}).", "outcome": "Connects theory directly to real exam problems.", "env": domain, "objs": [("block", "Initial State", 0.28, 0.50, "amber"), ("chart", "Final Outcome", 0.76, 0.50, "green")], "mot": ("spark", "green", "Outcome")},

        ],

    )



    steps: list[SimulationStep] = []

    for idx, tpl in enumerate(templates, 1):

        objs = [

            SceneObject(sprite=s_name, label=lbl, x=px, y=py, color=col)

            for (s_name, lbl, px, py, col) in tpl["objs"]

        ]

        m_part, m_col, m_lbl = tpl["mot"]

        motions = [

            SceneMotion(

                from_x=objs[0].x,

                from_y=objs[0].y,

                to_x=objs[-1].x,

                to_y=objs[-1].y,

                particle=m_part,

                color=m_col,

                label=m_lbl,

            )

        ]

        steps.append(

            SimulationStep(

                step_number=idx,

                title=f"Scene {idx} · {tpl['title']}",

                action=tpl["action"],

                outcome=tpl["outcome"],

                scene=SimulationScene(environment=tpl["env"], objects=objs, motions=motions),

            )

        )



    return SimulationData(

        title=f"AI Animated Walkthrough: {short_topic}",

        hobby_connection=hobbies,

        learning_style_focus=learning_style,

        scenario=f"Interactive simulation for {subject_name or 'this subject'}: {short_topic}.",

        steps=steps,

        key_takeaway=f"Connect every step in {short_topic} visually to how and why it changes.",

    )





def _parse_diagrams_list(raw_list: Any) -> list[NoteDiagram]:

    diagrams: list[NoteDiagram] = []

    if not isinstance(raw_list, list):

        return diagrams

    for item in raw_list:

        if not isinstance(item, dict):

            continue

        d_type = str(item.get("diagram_type") or "flow").strip().lower()

        if d_type not in ("comparison", "flow", "cycle", "concept_map"):

            d_type = "flow"

        comp_rows: list[DiagramComparisonRow] = []

        for r in item.get("comparison_rows") or []:

            if isinstance(r, dict) and str(r.get("criterion") or "").strip():

                comp_rows.append(

                    DiagramComparisonRow(

                        criterion=str(r.get("criterion") or "").strip(),

                        left_value=str(r.get("left_value") or "").strip(),

                        right_value=str(r.get("right_value") or "").strip(),

                    )

                )

        nodes: list[DiagramNode] = []

        for n in item.get("nodes") or []:

            if isinstance(n, dict) and str(n.get("label") or "").strip():

                nodes.append(

                    DiagramNode(

                        id=str(n.get("id") or f"n{len(nodes) + 1}").strip(),

                        label=str(n.get("label") or "").strip(),

                        detail=str(n.get("detail") or "").strip(),

                        role=str(n.get("role") or "step").strip(),

                    )

                )

        edges: list[DiagramEdge] = []

        for e in item.get("edges") or []:

            if isinstance(e, dict) and e.get("from_id") and e.get("to_id"):

                edges.append(

                    DiagramEdge(

                        from_id=str(e.get("from_id")).strip(),

                        to_id=str(e.get("to_id")).strip(),

                        label=str(e.get("label") or "").strip(),

                    )

                )

        diagrams.append(

            NoteDiagram(

                diagram_type=d_type,  # type: ignore[arg-type]

                title=str(item.get("title") or "Visual Diagram").strip(),

                subtitle=str(item.get("subtitle") or "").strip(),

                left_label=str(item.get("left_label") or "").strip(),

                right_label=str(item.get("right_label") or "").strip(),

                comparison_rows=comp_rows,

                nodes=nodes,

                edges=edges,

                takeaway=str(item.get("takeaway") or "").strip(),

            )

        )

    return diagrams[:3]





def _enforce_personalized_greeting(notes: str, student_name: str, is_fr: bool = False) -> str:

    """Ensure teacher lesson notes always greet the student by their actual first name, never 'class' or generic."""

    raw_s = (student_name or "").strip()

    if not raw_s or raw_s.lower() in ("student", "the student", "l'élève", "élève", "student name"):

        s_first = "Bryan"

    else:

        s_first = raw_s.split()[0].capitalize()



    target_greeting = f"Bonjour {s_first} !" if is_fr else f"Good morning, {s_first}!"



    # 1. Clean up any duplicated greeting or name stutters like "!Yanne !Yanne !" or multiple "Bonjour ..."

    notes = re.sub(r'(!\s*[A-Za-zÀ-ÿ]+\s*)+!', '!', notes)

    notes = re.sub(r'((?:Bonjour|Good morning|Hello)[^!\n]+!)\s*(?:Bonjour|Good morning|Hello)[^!\n]+!', r'\1', notes, flags=re.IGNORECASE)



    # 2. Check if a greeting with this student's name is already present near the top

    first_300 = notes[:300].lower()

    if s_first.lower() in first_300 and any(g in first_300 for g in ("bonjour", "morning", "hello", "welcome", "bienvenue")):

        return notes



    # Replace any generic greetings like Good morning, class! or Welcome, class!

    generic_pattern = re.compile(

        r'^(#\s+[^\r\n]+[\r\n]+)(?:Good morning,?\s*(?:class|everyone|students?)?!|Welcome,?\s*(?:class|everyone|students?)?!|Hello,?\s*(?:class|everyone|students?)?!|Bonjour\s*(?:la classe|\u00e0 tous|chers \u00e9l\u00e8ves)?\s*!|Bienvenue\s*(?:la classe|\u00e0 tous)?\s*!)\s*',

        re.IGNORECASE | re.MULTILINE,

    )

    if generic_pattern.search(notes):

        return generic_pattern.sub(r'\g<1>' + target_greeting + ' ', notes, count=1)



    # If starts with a markdown title (# Title), inject greeting right after

    title_pattern = re.compile(r'^(#\s+[^\r\n]+[\r\n]+)', re.MULTILINE)

    if title_pattern.search(notes):

        return title_pattern.sub(r'\g<1>' + target_greeting + '\n\n', notes, count=1)

    return f"{target_greeting}\n\n{notes}"





def _sanitize_notes(text: str) -> str:

    """Strip out any raw JSON artifacts, leaked properties, or broken brackets so notes are 100% human-readable."""

    s = text.strip()

    if not s:

        return ""

    # Strip any leaked raw JSON simulation, diagram, or metadata fragments

    for marker in (

        '"scale":',

        '"sprite":',

        '"motions":',

        '"visual_model":',

        '"step_number":',

        '"environment":',

        '"diagram_type":',

        '"takeaway":',

        '<!--KIVORA_RICH_V1:',

        '===SIMULATION_JSON===',

    ):

        idx = s.find(marker)

        if idx != -1:

            s = s[:idx].rstrip('", \t\n{')

    # If starting with json residue like quotes and colons

    if re.match(r'^\s*["\']?[a-zA-Z0-9_]+["\']?\s*:', s):

        return ""

    if s.startswith(("{", "}", "[", "]")):

        return ""

    # Clean LaTeX math wrappers around standalone numbers ($10$ -> 10, $7$ -> 7)

    s = re.sub(r"\$(\d+(?:\.\d+)?)\$", r"\1", s)

    return s.strip()





def _extract_notes_from_malformed_json(raw_text: str) -> str:

    """Recover clean teacher notes even if Gemini returned truncated or malformed JSON."""

    m = re.search(

        r'"notes"\s*:\s*"((?:\\.|[^"\\])*)"',

        raw_text,

        flags=re.DOTALL,

    )

    if m:

        extracted = m.group(1)

        try:

            val = json.loads(f'"{extracted}"').strip()

        except Exception:

            val = (

                extracted.replace("\\n", "\n")

                .replace('\\"', '"')

                .replace("\\\\", "\\")

                .strip()

            )

        cleaned_val = _sanitize_notes(val)

        if cleaned_val:

            return cleaned_val



    # If "notes": " was truncated before its closing quote, grab up to "diagrams" / "simulation".

    m2 = re.search(

        r'"notes"\s*:\s*"(.*?)(?:"\s*,\s*"(?:diagrams|simulation)"|\Z)',

        raw_text,

        flags=re.DOTALL,

    )

    if m2:

        val = (

            m2.group(1)

            .replace("\\n", "\n")

            .replace('\\"', '"')

            .rstrip('", \n\t}')

            .strip()

        )

        cleaned_val = _sanitize_notes(val)

        if cleaned_val:

            return cleaned_val



    # Never leak raw JSON objects/arrays into student notes.

    return _sanitize_notes(raw_text)





def _parse_summary_json(

    raw_text: str,

    subject_name: str,

    topic_title: str,

    hobbies: str,

    learning_style: str,

    student_name: str = "Bryan",

    is_fr: bool = False,

) -> tuple[str, list[NoteDiagram], Optional[SimulationData]]:

    cleaned = re.sub(

        r"^```(?:json)?\s*|\s*```$", "", raw_text.strip(), flags=re.IGNORECASE

    )

    match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)

    if match:

        for strict_mode in (True, False):

            try:

                data = json.loads(match.group(0), strict=strict_mode)

                notes = _sanitize_notes(str(data.get("notes") or ""))

                if not notes:

                    notes = _extract_notes_from_malformed_json(cleaned)

                diagrams = _parse_diagrams_list(data.get("diagrams"))

                if not diagrams:

                    diagrams = _build_fallback_diagrams(

                        subject_name, topic_title

                    )

                simulation = None

                resolved_notes = _enforce_personalized_greeting(

                    notes or f"# {topic_title}\n\nLet us review this lesson step by step.",

                    student_name,

                    is_fr,

                )

                return (

                    resolved_notes,

                    diagrams,

                    simulation,

                )

            except (json.JSONDecodeError, TypeError, ValueError):

                continue



    recovered = _extract_notes_from_malformed_json(cleaned)

    final_notes = _enforce_personalized_greeting(

        recovered or f"# {topic_title}\n\nLet us review the key concepts and diagrams for {topic_title}.",

        student_name,

        is_fr,

    )

    return (

        final_notes,

        _build_fallback_diagrams(subject_name, topic_title),

        None,

    )





def extract_optional_simulation(raw_text: str) -> tuple[str, Optional[SimulationData]]:

    """Strip and parse an optional trailing ===SIMULATION_JSON===...===END_SIMULATION=== block."""

    pattern = re.compile(

        r"===SIMULATION_JSON===\s*(\{.*?\})\s*===END_SIMULATION===",

        flags=re.DOTALL,

    )

    match = pattern.search(raw_text)

    if not match:

        return raw_text.strip(), None

    clean_answer = pattern.sub("", raw_text).strip()

    try:

        sim_obj = json.loads(match.group(1))

        return clean_answer, None

    except (json.JSONDecodeError, TypeError, ValueError):

        return clean_answer, None





def _parse_grading_json(

    raw_text: str,

    subject_name: str = "",

    topic_title: str = "Concept",

    hobbies: str = "everyday life",

    learning_style: str = "visual_simulations",

) -> tuple[str, str, Optional[SimulationData], int, str]:

    cleaned = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw_text.strip(), flags=re.IGNORECASE)

    match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)

    fallback_sim = (

        _build_fallback_simulation(

            subject_name=subject_name,

            topic_title=topic_title,

            hobbies=hobbies,

            learning_style=learning_style,

        )

        if _is_simulatable_subject(subject_name, topic_title)

        else None

    )

    if not match:

        return (

            raw_text.strip() or "Graded response ready.",

            "Reviewed by Kivora AI",

            fallback_sim,

            60,

            "",

        )

    try:

        data = json.loads(match.group(0))

        feedback = str(data.get("feedback") or "").strip() or raw_text.strip()

        score_summary = str(

            data.get("score_summary") or "Reviewed by Kivora AI"

        ).strip()

        try:

            score_percent = max(0, min(100, int(data.get("score_percent", 60))))

        except Exception:

            score_percent = 60

        weak_concepts = str(data.get("weak_concepts") or "").strip()

        simulation = _parse_simulation_dict(data.get("simulation")) or fallback_sim

        return feedback, score_summary, simulation, score_percent, weak_concepts

    except (json.JSONDecodeError, TypeError, ValueError):

        return (

            raw_text.strip() or "Graded response ready.",

            "Reviewed by Kivora AI",

            fallback_sim,

            60,

            "",

        )

