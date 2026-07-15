from __future__ import annotations

import datetime
import re
from typing import Any

import arxiv

from .config import Settings


def sanitize_filename(name: str) -> str:
    return re.sub(r'[\/*?:"<>|]', "_", name)


def collect_new_papers(settings: Settings) -> list[dict[str, Any]]:
    settings.ensure_runtime_directories()

    print(f"Collecting papers from the last {settings.days_to_search} day(s)")
    query = " OR ".join(
        f"cat:{category}" for category in settings.ai_categories
    )
    crawl_timestamp = (
        datetime.datetime.now(datetime.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z")
    )

    today_cutoff = datetime.datetime.now().replace(
        hour=settings.data_refresh_hour,
        minute=0,
        second=0,
        microsecond=0,
    )
    start_day = today_cutoff - datetime.timedelta(days=settings.days_to_search)
    end_time_utc = today_cutoff - datetime.timedelta(hours=9)
    start_time_utc = start_day - datetime.timedelta(hours=9)

    client = arxiv.Client()
    search = arxiv.Search(
        query=query,
        max_results=settings.max_results,
        sort_by=arxiv.SortCriterion.SubmittedDate,
    )
    results = client.results(search)

    new_papers: list[dict[str, Any]] = []
    try:
        for result in results:
            published_time_utc = result.published.replace(tzinfo=None)
            if not start_time_utc <= published_time_utc < end_time_utc:
                continue

            paper_info = {
                "entry_id": result.entry_id,
                "short_id": result.get_short_id(),
                "title": result.title,
                "authors": [author.name for author in result.authors],
                "subjects": result.categories,
                "abstract": result.summary.replace("\n", " ").strip(),
                "pdf_url": result.pdf_url,
                "published_time_utc": result.published.isoformat(),
                "crawled_at": crawl_timestamp,
            }
            new_papers.append(paper_info)

            if not settings.download_pdfs:
                continue

            try:
                primary_subject = (
                    result.categories[0] if result.categories else None
                )
                subject_dir = settings.pdf_dir_for_subject(primary_subject)
                pdf_filename = f"{sanitize_filename(result.title)}.pdf"
                result.download_pdf(
                    dirpath=str(subject_dir),
                    filename=pdf_filename,
                )
                print(f"Downloaded PDF: {subject_dir / pdf_filename}")
            except Exception as exc:
                print(f"Failed to download PDF: {result.title[:30]}... - {exc}")
    except arxiv.UnexpectedEmptyPageError:
        print("Reached the end of arXiv search results.")

    print("-" * 50)
    print(f"Found {len(new_papers)} paper(s)")
    return new_papers
