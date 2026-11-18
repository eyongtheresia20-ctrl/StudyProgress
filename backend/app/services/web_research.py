from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from html import unescape
import re
from typing import Optional
from urllib.parse import quote

import httpx

_NOTES_CACHE: dict[str, tuple[str, list[dict[str, str]]]] = {}

_API_HEADERS = {
    "User-Agent": "KivoraStudyApp/1.0 (Educational Study Verification; mailto:support@kivora.edu)",
    "Accept": "application/json",
}

_NOISE_WORDS = {
    "the",
    "and",
    "for",
    "with",
    "from",
    "into",
    "that",
    "this",
    "lesson",
    "lecon",
    "chapter",
    "chapitre",
    "unit",
    "module",
    "part",
    "topic",
    "notion",
    "notions",
    "fundamental",
    "fundamentals",
    "basic",
    "basics",
    "introduction",
    "overview",
    "general",
    "study",
    "form",
    "class",
    "week",
    "term",
    "all",
    "les",
    "des",
    "une",
    "dans",
    "pour",
    "sur",
}


def _strip_tags(raw: str) -> str:
    return re.sub(r"\s+", " ", unescape(re.sub(r"<[^>]+>", " ", raw))).strip()


def _clean_phrase(text: str) -> str:
    cleaned = re.sub(
        r"\b(?:TU|WK|Module|Unit|Chap(?:ter|itre)?|Lesson|Le[çc]on|Notion|Form|Lower\s*Sixth|Upper\s*Sixth)\s*\d*\s*[:.-]?\s*",
        "",
        text,
        flags=re.I,
    )
    cleaned = re.sub(r"\([^)]*\b(?:TU|Lesson|Wk)\b[^)]*\)", "", cleaned, flags=re.I)
    return cleaned.strip(" :-.|")


def _extract_search_terms(
    subject_name: str, topic_title: str, subtopics: Optional[str]
) -> tuple[str, list[str], set[str]]:
    """Derive clean academic concepts and core relevance keywords from progression titles."""
    raw = (topic_title or "").strip()
    parts = [p.strip() for p in re.split(r"[—–|]+|(?:\s+-\s+)", raw) if p.strip()]
    cleaned_parts: list[str] = []
    for part in parts:
        # If there is a colon after a prefix like "Lesson 1: Sole Proprietorship", take the meaningful side.
        sub_chunks = [c.strip() for c in part.split(":") if c.strip()]
        for chunk in sub_chunks:
            cleaned = _clean_phrase(chunk)
            if cleaned and len(cleaned) >= 3:
                cleaned_parts.append(cleaned)

    candidates: list[str] = []
    for item in reversed(cleaned_parts):
        if item.lower() not in {c.lower() for c in candidates}:
            candidates.append(item)

    if subtopics:
        for seg in re.split(r"[;,]+", subtopics):
            sub_clean = _clean_phrase(seg)
            if sub_clean and len(sub_clean) >= 4 and "curriculum" not in sub_clean.lower():
                if sub_clean.lower() not in {c.lower() for c in candidates}:
                    candidates.append(sub_clean)
                break

    primary = candidates[0] if candidates else (_clean_phrase(raw) or subject_name or "Study Topic")

    keyword_pool = set()
    for text in (primary, *candidates[:2]):
        for tok in re.findall(r"[a-zA-ZÀ-ÿ0-9]+", text.lower()):
            if len(tok) >= 3 and tok not in _NOISE_WORDS:
                keyword_pool.add(tok)
    if not keyword_pool and subject_name:
        for tok in re.findall(r"[a-zA-ZÀ-ÿ0-9]+", subject_name.lower()):
            if len(tok) >= 3 and tok not in _NOISE_WORDS:
                keyword_pool.add(tok)

    return primary, candidates[:3], keyword_pool


def _relevance_score(title: str, extract: str, keywords: set[str], subject_name: str) -> int:
    low_title = title.lower()
    low_extract = extract[:450].lower()
    if "(disambiguation)" in low_title or "may refer to:" in low_extract:
        return 0
    if not keywords:
        return 1

    title_hits = sum(1 for kw in keywords if re.search(rf"\b{re.escape(kw)}", low_title))
    extract_hits = sum(1 for kw in keywords if re.search(rf"\b{re.escape(kw)}", low_extract))

    # Reject articles where NONE of the core topic words appear in the title AND extract matches fewer than 2.
    if title_hits == 0 and extract_hits < 2:
        return 0

    subj_words = {
        tok for tok in re.findall(r"[a-zA-ZÀ-ÿ0-9]+", (subject_name or "").lower())
        if len(tok) >= 4 and tok not in _NOISE_WORDS
    }
    subj_bonus = 2 if any(w in low_extract or w in low_title for w in subj_words) else 0
    return title_hits * 5 + extract_hits * 2 + subj_bonus


def _fetch_mediawiki_sources(
    base_url: str,
    source_label: str,
    domain_root: str,
    query: str,
    keywords: set[str],
    subject_name: str,
    limit: int = 3,
) -> list[dict[str, str]]:
    """Search a Wikimedia educational wiki and keep only high-relevance verified articles."""
    results: list[tuple[int, dict[str, str]]] = []
    try:
        resp = httpx.get(
            base_url,
            params={
                "action": "query",
                "generator": "search",
                "gsrsearch": query,
                "gsrlimit": str(limit),
                "prop": "extracts|info|pageimages",
                "exintro": "1",
                "explaintext": "1",
                "exsentences": "7",
                "inprop": "url",
                "pithumbsize": "900",
                "format": "json",
            },
            timeout=1.0,
            follow_redirects=True,
            headers=_API_HEADERS,
        )
        if resp.status_code != 200:
            return []
        pages = (resp.json().get("query") or {}).get("pages") or {}
        for page in pages.values():
            title = (page.get("title") or "").strip()
            extract = _strip_tags(page.get("extract") or "")
            if not title or not extract:
                continue
            score = _relevance_score(title, extract, keywords, subject_name)
            if score <= 0:
                continue
            url = (
                page.get("fullurl")
                or f"https://{domain_root}/wiki/{quote(title.replace(' ', '_'))}"
            )
            thumb = str((page.get("thumbnail") or {}).get("source") or "").strip()
            if any(
                bad in thumb.lower()
                for bad in ("commons-logo", "wikimedia", "flag_of_", "ambox", "question_book")
            ):
                thumb = ""
            entry = {
                "title": title[:140],
                "source": source_label,
                "url": url,
                "snippet": extract[:950],
            }
            if thumb.startswith("http"):
                entry["image_url"] = thumb
            results.append((score, entry))
    except Exception:
        return []
    results.sort(key=lambda pair: pair[0], reverse=True)
    return [item for _, item in results]


def _fetch_ddg_instant(
    query: str, keywords: set[str], subject_name: str
) -> list[dict[str, str]]:
    """Fetch reference encyclopedia summary via DuckDuckGo Instant Answer API."""
    sources: list[dict[str, str]] = []
    try:
        resp = httpx.get(
            "https://api.duckduckgo.com/",
            params={
                "q": query,
                "format": "json",
                "no_html": "1",
                "skip_disambig": "1",
            },
            timeout=1.0,
            follow_redirects=True,
            headers=_API_HEADERS,
        )
        if resp.status_code not in (200, 202):
            return sources
        data = resp.json()
        abstract = _strip_tags(data.get("AbstractText") or "")
        url = (data.get("AbstractURL") or "").strip()
        heading = (data.get("Heading") or query).strip()
        if abstract and url.startswith("http") and _relevance_score(heading, abstract, keywords, subject_name) > 0:
            sources.append(
                {
                    "title": heading[:140],
                    "source": (data.get("AbstractSource") or "Reference Encyclopedia").strip(),
                    "url": url,
                    "snippet": abstract[:950],
                }
            )
    except Exception:
        return sources
    return sources


def fetch_verified_topic_notes(
    subject_name: str,
    topic_title: str,
    subtopics: Optional[str] = None,
    class_name: Optional[str] = None,
    language: str = "en",
) -> tuple[str, list[dict[str, str]]]:
    """Gather high-relevance overlapping notes from multiple online sources so AI can verify truth."""
    cache_key = f"{str(subject_name).strip().lower()}|{str(topic_title).strip().lower()}|{str(language).strip().lower()}"
    if cache_key in _NOTES_CACHE:
        return _NOTES_CACHE[cache_key]
    is_fr = str(language or "").strip().lower() == "fr"
    primary, candidates, keywords = _extract_search_terms(
        subject_name, topic_title, subtopics
    )
    clean_subject = (subject_name or "").strip()
    scoped_query = (
        f"{primary} {clean_subject}".strip() if clean_subject else primary
    )
    wiki_query = primary if len(primary.split()) >= 2 else scoped_query

    results: list[dict[str, str]] = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        if is_fr:
            futures = [
                pool.submit(
                    _fetch_mediawiki_sources,
                    "https://fr.wikipedia.org/w/api.php",
                    "Wikipédia",
                    "fr.wikipedia.org",
                    wiki_query,
                    keywords,
                    clean_subject,
                    3,
                ),
                pool.submit(
                    _fetch_mediawiki_sources,
                    "https://fr.vikidia.org/w/api.php",
                    "Vikidia (Encyclopédie scolaire)",
                    "fr.vikidia.org",
                    primary,
                    keywords,
                    clean_subject,
                    3,
                ),
                pool.submit(
                    _fetch_mediawiki_sources,
                    "https://fr.wikibooks.org/w/api.php",
                    "Wikilivres Pédagogiques",
                    "fr.wikibooks.org",
                    scoped_query,
                    keywords,
                    clean_subject,
                    2,
                ),
                pool.submit(
                    _fetch_ddg_instant, primary, keywords, clean_subject
                ),
            ]
        else:
            futures = [
                pool.submit(
                    _fetch_mediawiki_sources,
                    "https://en.wikipedia.org/w/api.php",
                    "Wikipedia",
                    "en.wikipedia.org",
                    wiki_query,
                    keywords,
                    clean_subject,
                    3,
                ),
                pool.submit(
                    _fetch_mediawiki_sources,
                    "https://simple.wikipedia.org/w/api.php",
                    "Simple Wikipedia (School Reference)",
                    "simple.wikipedia.org",
                    primary,
                    keywords,
                    clean_subject,
                    3,
                ),
                pool.submit(
                    _fetch_mediawiki_sources,
                    "https://en.wikibooks.org/w/api.php",
                    "Wikibooks Textbook",
                    "en.wikibooks.org",
                    scoped_query,
                    keywords,
                    clean_subject,
                    2,
                ),
                pool.submit(
                    _fetch_ddg_instant, primary, keywords, clean_subject
                ),
            ]
        if len(candidates) > 1 and candidates[1].lower() != primary.lower():
            if is_fr:
                futures.append(
                    pool.submit(
                        _fetch_mediawiki_sources,
                        "https://fr.wikipedia.org/w/api.php",
                        "Wikipédia",
                        "fr.wikipedia.org",
                        candidates[1],
                        keywords,
                        clean_subject,
                        2,
                    )
                )
            else:
                futures.append(
                    pool.submit(
                        _fetch_mediawiki_sources,
                        "https://en.wikipedia.org/w/api.php",
                        "Wikipedia",
                        "en.wikipedia.org",
                        candidates[1],
                        keywords,
                        clean_subject,
                        2,
                    )
                )

        for fut in futures:
            try:
                results.extend(fut.result(timeout=0.6))
            except Exception:
                continue

    deduped: list[dict[str, str]] = []
    seen_urls: set[str] = set()
    seen_titles: set[str] = set()
    for item in results:
        norm_url = item.get("url", "").strip().rstrip("/").lower()
        norm_title = f"{item.get('source', '').lower()}|{item.get('title', '').lower()[:45]}"
        if not norm_url or norm_url in seen_urls or norm_title in seen_titles:
            continue
        seen_urls.add(norm_url)
        seen_titles.add(norm_title)
        deduped.append(item)
        if len(deduped) >= 5:
            break

    if len(deduped) < 3:
        from urllib.parse import quote_plus

        q_text = f"{clean_subject} {primary}".strip() or primary or topic_title
        q_enc = quote_plus(q_text)
        if is_fr:
            extra_links = [
                {
                    "title": f"{primary or topic_title} — Wikipédia",
                    "source": "Wikipédia",
                    "url": f"https://fr.wikipedia.org/w/index.php?search={q_enc}",
                    "snippet": f"Consultez les articles encyclopédiques complets et fiches de cours détaillées sur {q_text}.",
                    "image_url": "",
                },
                {
                    "title": f"{primary or topic_title} — Vikidia",
                    "source": "Vikidia",
                    "url": f"https://fr.vikidia.org/w/index.php?search={q_enc}",
                    "snippet": f"Explications simples, claires et adaptées aux collégiens et lycéens sur {q_text}.",
                    "image_url": "",
                },
                {
                    "title": f"{primary or topic_title} — Wikilivres",
                    "source": "Wikilivres",
                    "url": f"https://fr.wikibooks.org/w/index.php?search={q_enc}",
                    "snippet": f"Manuels pédagogiques libres, définitions et exercices résolus sur {q_text}.",
                    "image_url": "",
                },
            ]
        else:
            extra_links = [
                {
                    "title": f"{primary or topic_title} — Wikipedia Search",
                    "source": "Wikipedia",
                    "url": f"https://en.wikipedia.org/w/index.php?search={q_enc}",
                    "snippet": f"Explore full encyclopedia articles and background notes on {q_text}.",
                    "image_url": "",
                },
                {
                    "title": f"{primary or topic_title} — Khan Academy",
                    "source": "Khan Academy",
                    "url": f"https://www.khanacademy.org/search?page_search_query={q_enc}",
                    "snippet": f"Interactive practice exercises and step-by-step lessons on {q_text}.",
                    "image_url": "",
                },
                {
                    "title": f"{primary or topic_title} — Wikibooks",
                    "source": "Wikibooks",
                    "url": f"https://en.wikibooks.org/w/index.php?search={q_enc}",
                    "snippet": f"Open textbook chapters and worked examples for {q_text}.",
                    "image_url": "",
                },
            ]
        for item in extra_links:
            norm_url = item["url"].lower()
            if norm_url not in seen_urls:
                seen_urls.add(norm_url)
                deduped.append(item)
            if len(deduped) >= 4:
                break

    header_text = (
        "Articles et liens de référence vérifiés (citer [Source 1], [Source 2], ... pour sourcer les explications) :"
        if is_fr
        else "Verified Online Reference Articles (cite as [Source 1], [Source 2], ... when summarizing facts):"
    )
    dossier_lines = [header_text]
    for i, src in enumerate(deduped, 1):
        dossier_lines.append(
            f"[Source {i} — {src['title']} | {src['source']} | {src['url']}]\n{src['snippet']}"
        )
    result = ("\n".join(dossier_lines), deduped)
    _NOTES_CACHE[cache_key] = result
    return result


def build_video_and_simulation_links(
    subject_name: str,
    topic_title: str,
    learning_style: Optional[str] = None,
    subtopics: Optional[str] = None,
) -> list[dict[str, str]]:
    """Retained for signature compatibility; videos/simulations are generated directly by Kivora AI."""
    return []
