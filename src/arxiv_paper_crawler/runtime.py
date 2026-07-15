from __future__ import annotations

from collections.abc import Callable
from datetime import date, datetime
from typing import Any

RECRAWL_PROMPT = (
    "A crawl for today already exists. "
    "Do you want to check for newly posted papers and crawl again? [y/N]: "
)

Paper = dict[str, Any]


def _parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None

    normalized = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def _local_date(value: datetime) -> date:
    if value.tzinfo is None:
        return value.date()
    return value.astimezone().date()


def _paper_crawl_date(paper: Paper) -> date | None:
    crawled_at = _parse_datetime(paper.get("crawled_at"))
    if crawled_at is None:
        return None
    return _local_date(crawled_at)


def has_crawl_for_date(
    papers: list[Paper],
    *,
    target_date: date | None = None,
    now: datetime | None = None,
) -> bool:
    expected_date = target_date or _local_date(now or datetime.now().astimezone())
    return any(_paper_crawl_date(paper) == expected_date for paper in papers)


def should_recrawl_today(
    papers: list[Paper],
    *,
    force_recrawl: bool = False,
    no_prompt: bool = False,
    target_date: date | None = None,
    now: datetime | None = None,
    input_func: Callable[[str], str] = input,
) -> bool:
    if force_recrawl:
        return True

    if not has_crawl_for_date(papers, target_date=target_date, now=now):
        return True

    if no_prompt:
        return False

    answer = input_func(RECRAWL_PROMPT)
    return answer.strip().lower() in {"y", "yes"}


def paper_identity(paper: Paper) -> str:
    for key in ("entry_id", "short_id", "pdf_url"):
        value = paper.get(key)
        if value:
            return f"{key}:{value}"

    title = (paper.get("title") or "").strip().lower()
    published = paper.get("published_time_utc") or ""
    return f"fallback:{title}|{published}"


def merge_papers(
    existing_papers: list[Paper],
    new_papers: list[Paper],
) -> list[Paper]:
    merged_by_id: dict[str, Paper] = {}

    for paper in existing_papers:
        merged_by_id[paper_identity(paper)] = dict(paper)

    for paper in new_papers:
        identity = paper_identity(paper)
        if identity in merged_by_id:
            merged_by_id[identity] = {**merged_by_id[identity], **paper}
        else:
            merged_by_id[identity] = dict(paper)

    return sorted(
        merged_by_id.values(),
        key=lambda paper: (
            paper.get("published_time_utc", ""),
            paper_identity(paper),
        ),
        reverse=True,
    )
