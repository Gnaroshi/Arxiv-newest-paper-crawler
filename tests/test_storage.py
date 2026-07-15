from arxiv_paper_crawler.storage import (
    load_favorite_ids,
    load_papers,
    save_favorite_ids,
    save_papers,
)


def test_save_and_load_papers_round_trip(tmp_path):
    papers_path = tmp_path / "nested" / "papers.json"
    papers = [
        {
            "short_id": "1234.5678",
            "title": "Example Paper",
            "abstract": "Example abstract",
            "published_time_utc": "2026-03-20T00:00:00",
        }
    ]

    save_papers(papers_path, papers)

    assert papers_path.exists()
    assert load_papers(papers_path) == papers


def test_favorites_default_and_round_trip(tmp_path):
    favorites_path = tmp_path / "favorites.json"

    assert load_favorite_ids(favorites_path) == []

    save_favorite_ids(favorites_path, ["a", "b"])
    assert load_favorite_ids(favorites_path) == ["a", "b"]
