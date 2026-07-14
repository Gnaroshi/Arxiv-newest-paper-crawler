from __future__ import annotations

from typing import NotRequired, TypedDict


class StoredPaper(TypedDict):
    entry_id: str
    short_id: str
    title: str
    authors: list[str]
    subjects: list[str]
    abstract: str
    pdf_url: str
    published_time_utc: str
    updated_time_utc: NotRequired[str]
    crawled_at: NotRequired[str]
    abstract_ko: NotRequired[str]
    local_pdf_path: NotRequired[str]


class TranslationResult(TypedDict):
    status: str
    text: NotRequired[str]
    error: NotRequired[str]
