from datetime import datetime, timezone

from arxiv_paper_crawler.runtime import (
    RECRAWL_PROMPT,
    has_crawl_for_date,
    merge_papers,
    should_recrawl_today,
)


def test_has_crawl_for_date_is_false_when_no_entry_for_today():
    papers = [{"entry_id": "old", "crawled_at": "2026-03-19T08:00:00Z"}]
    now = datetime(2026, 3, 20, 9, 0, tzinfo=timezone.utc)

    assert has_crawl_for_date(papers, now=now) is False


def test_has_crawl_for_date_is_true_when_today_entry_exists():
    papers = [{"entry_id": "today", "crawled_at": "2026-03-20T08:00:00Z"}]
    now = datetime(2026, 3, 20, 9, 0, tzinfo=timezone.utc)

    assert has_crawl_for_date(papers, now=now) is True


def test_should_recrawl_today_accepts_yes_answer():
    prompts: list[str] = []
    papers = [{"entry_id": "today", "crawled_at": "2026-03-20T08:00:00Z"}]
    now = datetime(2026, 3, 20, 9, 0, tzinfo=timezone.utc)

    should_crawl = should_recrawl_today(
        papers,
        now=now,
        input_func=lambda prompt: prompts.append(prompt) or "y",
    )

    assert prompts == [RECRAWL_PROMPT]
    assert should_crawl is True


def test_should_recrawl_today_defaults_to_skip_on_enter():
    papers = [{"entry_id": "today", "crawled_at": "2026-03-20T08:00:00Z"}]
    now = datetime(2026, 3, 20, 9, 0, tzinfo=timezone.utc)

    assert (
        should_recrawl_today(papers, now=now, input_func=lambda _: "") is False
    )


def test_should_recrawl_today_respects_no_prompt_safe_skip():
    papers = [{"entry_id": "today", "crawled_at": "2026-03-20T08:00:00Z"}]
    now = datetime(2026, 3, 20, 9, 0, tzinfo=timezone.utc)

    assert should_recrawl_today(papers, now=now, no_prompt=True) is False
    assert should_recrawl_today(papers, now=now, force_recrawl=True) is True


def test_merge_papers_deduplicates_and_updates_safely():
    existing_papers = [
        {
            "entry_id": "paper-1",
            "title": "Existing Paper",
            "abstract": "old abstract",
            "abstract_ko": "existing translation",
            "published_time_utc": "2026-03-20T00:00:00Z",
            "crawled_at": "2026-03-20T08:00:00Z",
        }
    ]
    new_papers = [
        {
            "entry_id": "paper-1",
            "title": "Existing Paper",
            "abstract": "updated abstract",
            "published_time_utc": "2026-03-20T00:00:00Z",
            "crawled_at": "2026-03-20T09:00:00Z",
        },
        {
            "entry_id": "paper-2",
            "title": "New Paper",
            "abstract": "new abstract",
            "published_time_utc": "2026-03-20T01:00:00Z",
            "crawled_at": "2026-03-20T09:00:00Z",
        },
    ]

    merged = merge_papers(existing_papers, new_papers)
    merged_by_id = {paper["entry_id"]: paper for paper in merged}

    assert len(merged) == 2
    assert merged_by_id["paper-1"]["abstract"] == "updated abstract"
    assert merged_by_id["paper-1"]["abstract_ko"] == "existing translation"
    assert merged_by_id["paper-1"]["crawled_at"] == "2026-03-20T09:00:00Z"
