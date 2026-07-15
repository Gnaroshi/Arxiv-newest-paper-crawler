from __future__ import annotations

import time
from collections.abc import Callable

from .config import Settings, load_settings
from .models import StoredPaper


def translate_papers(
    papers: list[StoredPaper],
    settings: Settings,
    *,
    diagnostic: Callable[[str], None] = print,
) -> list[StoredPaper]:
    if not papers:
        diagnostic("Nothing to translate.")
        return []
    if not settings.google_api_key:
        diagnostic("GOOGLE_API_KEY is not set; keeping English abstracts only.")
        return [dict(paper) for paper in papers]
    try:
        from google import genai

        client = genai.Client(api_key=settings.google_api_key)
    except Exception:
        diagnostic("Translation provider is unavailable.")
        return [dict(paper) for paper in papers]

    translated: list[StoredPaper] = []
    for paper in papers:
        updated = dict(paper)
        try:
            response = client.models.generate_content(
                model=settings.gemini_model,
                contents=(
                    "Translate this academic abstract into Korean. Return only the "
                    f"translation.\n\n{paper['abstract']}"
                ),
            )
            text = getattr(response, "text", "").strip()
            if text:
                updated["abstract_ko"] = text
        except Exception:
            diagnostic(f"Failed to translate: {paper['title'][:30]}...")
        translated.append(updated)
        time.sleep(settings.translation_delay_seconds)
    return translated


def process_papers_with_gemini(
    papers_to_process: list[StoredPaper],
) -> list[StoredPaper]:
    """Compatibility function matching the legacy top-level module."""

    return translate_papers(papers_to_process, load_settings(legacy=True))


def save_papers_to_json(
    papers_data: list[StoredPaper],
    filename: str = "papers.json",
) -> None:
    from pathlib import Path

    from .storage import save_papers

    save_papers(Path(filename), papers_data)
