from __future__ import annotations

import time
from typing import Any

from .config import Settings


def _build_model(settings: Settings):
    if not settings.google_api_key:
        print(
            "GOOGLE_API_KEY is not set. Skipping translation "
            "and keeping only the English abstract."
        )
        return None

    try:
        from google import genai
    except ImportError as exc:
        print(f"Gemini client is unavailable: {exc}")
        return None

    try:
        return genai.Client(api_key=settings.google_api_key)
    except Exception as exc:
        print(f"Failed to configure Gemini: {exc}")
        return None


def process_papers_with_gemini(
    papers_to_process: list[dict[str, Any]], settings: Settings
) -> list[dict[str, Any]]:
    if not papers_to_process:
        print("Nothing to translate.")
        return []

    model = _build_model(settings)
    if model is None:
        return papers_to_process

    print(f"Translating {len(papers_to_process)} paper abstract(s)")

    processed_papers: list[dict[str, Any]] = []
    for paper in papers_to_process:
        translated_paper = dict(paper)
        try:
            prompt = f"""
            You are an expert technical translator.
            Translate the following English abstract into Korean.
            Return only the translated Korean text.

            English Abstract:
            ---
            {paper['abstract']}
            ---
            """
            response = model.models.generate_content(
                model=settings.gemini_model,
                contents=prompt,
            )
            translated_text = getattr(response, "text", "").strip()
            if translated_text:
                translated_paper["abstract_ko"] = translated_text
        except Exception as exc:
            print(f"Failed to translate: {paper['title'][:30]}... - {exc}")

        processed_papers.append(translated_paper)
        time.sleep(settings.translation_delay_seconds)

    print("Translation complete")
    return processed_papers
