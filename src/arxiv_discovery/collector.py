from __future__ import annotations

import datetime as dt
import re
from collections.abc import Iterable
from pathlib import Path
from typing import Any

import arxiv

from .config import Settings
from .models import StoredPaper


def sanitize_filename(name: str) -> str:
    return re.sub(r'[\\/*?:"<>|]', "_", name)


def collection_window(
    settings: Settings,
    *,
    now: dt.datetime | None = None,
) -> tuple[dt.datetime, dt.datetime]:
    local_now = now or dt.datetime.now(settings.timezone_info)
    if local_now.tzinfo is None:
        local_now = local_now.replace(tzinfo=settings.timezone_info)
    else:
        local_now = local_now.astimezone(settings.timezone_info)
    hour, minute = settings.cutoff_hour_minute
    end = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if local_now < end:
        end -= dt.timedelta(days=1)
    start = end - dt.timedelta(days=settings.days)
    return start.astimezone(dt.timezone.utc), end.astimezone(dt.timezone.utc)


def _paper_from_result(result: Any, crawled_at: str) -> StoredPaper:
    return {
        "entry_id": result.entry_id,
        "short_id": result.get_short_id(),
        "title": result.title,
        "authors": [author.name for author in result.authors],
        "subjects": list(result.categories),
        "abstract": result.summary.replace("\n", " ").strip(),
        "pdf_url": result.pdf_url,
        "published_time_utc": result.published.isoformat(),
        "updated_time_utc": result.updated.isoformat(),
        "crawled_at": crawled_at,
    }


def _download_pdf(
    result: Any,
    settings: Settings,
    paper: StoredPaper,
    diagnostic,
) -> None:
    primary_subject = result.categories[0] if result.categories else "Uncategorized"
    subject_dir = settings.pdfs_dir / primary_subject
    subject_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{sanitize_filename(result.title)}.pdf"
    result.download_pdf(dirpath=str(subject_dir), filename=filename)
    paper["local_pdf_path"] = str(Path(primary_subject) / filename)
    diagnostic(f"Downloaded PDF: {subject_dir / filename}")


def collect_papers(
    settings: Settings,
    *,
    download_mode: str,
    selected_ids: set[str] | None = None,
    results: Iterable[Any] | None = None,
    now: dt.datetime | None = None,
    diagnostic=print,
) -> list[StoredPaper]:
    if download_mode not in {"none", "selected", "all"}:
        raise ValueError("Unsupported download mode")
    selected_ids = selected_ids or set()
    if download_mode == "selected" and not selected_ids:
        raise ValueError("Selected download mode requires candidate IDs")
    if download_mode != "none":
        settings.ensure_runtime_directories(include_pdfs=True)
    start, end = collection_window(settings, now=now)
    diagnostic(
        f"Collecting up to {settings.max_results} papers in "
        f"{','.join(settings.categories)} from {start.isoformat()} to {end.isoformat()}"
    )
    query = " OR ".join(f"cat:{category}" for category in settings.categories)
    if results is None:
        client = arxiv.Client()
        search = arxiv.Search(
            query=query,
            max_results=settings.max_results,
            sort_by=arxiv.SortCriterion.SubmittedDate,
        )
        results = client.results(search)

    crawled_at = dt.datetime.now(dt.timezone.utc).isoformat()
    papers: list[StoredPaper] = []
    try:
        for result in results:
            submitted = result.published
            if submitted.tzinfo is None:
                submitted = submitted.replace(tzinfo=dt.timezone.utc)
            submitted = submitted.astimezone(dt.timezone.utc)
            if not start <= submitted < end:
                continue
            paper = _paper_from_result(result, crawled_at)
            papers.append(paper)
            short_id = paper["short_id"]
            base_id = re.sub(r"v\d+$", "", short_id, flags=re.I)
            should_download = download_mode == "all" or (
                download_mode == "selected"
                and bool(
                    {short_id, base_id, f"arxiv:{base_id.lower()}"} & selected_ids
                )
            )
            if should_download:
                try:
                    _download_pdf(result, settings, paper, diagnostic)
                except Exception:  # provider failure is per-paper
                    diagnostic(f"Failed to download PDF: {result.title[:30]}...")
    except arxiv.UnexpectedEmptyPageError:
        diagnostic("Reached the end of arXiv search results.")
    diagnostic(f"Found {len(papers)} paper(s)")
    return papers


def collect_new_papers() -> list[StoredPaper]:
    """Compatibility function matching the legacy top-level module."""

    from .config import load_settings

    return collect_papers(load_settings(legacy=True), download_mode="all")
