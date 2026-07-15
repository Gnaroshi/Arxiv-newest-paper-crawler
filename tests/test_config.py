from arxiv_paper_crawler.config import load_settings


def test_load_settings_builds_runtime_paths(tmp_path):
    settings = load_settings(project_root=tmp_path)

    assert settings.data_dir == tmp_path / "data"
    assert settings.papers_path == tmp_path / "data" / "papers.json"
    assert settings.favorites_path == tmp_path / "data" / "favorites.json"
    assert settings.pdfs_dir == tmp_path / "data" / "pdfs"
    assert settings.download_pdfs is False

    settings.ensure_runtime_directories()
    assert settings.data_dir.is_dir()
    assert not settings.pdfs_dir.exists()


def test_load_settings_applies_env_overrides(monkeypatch, tmp_path):
    monkeypatch.setenv("ARXIV_PAPER_CRAWLER_DAYS_TO_SEARCH", "3")
    monkeypatch.setenv("ARXIV_PAPER_CRAWLER_MAX_RESULTS", "25")
    monkeypatch.setenv("ARXIV_PAPER_CRAWLER_DOWNLOAD_PDFS", "true")
    monkeypatch.setenv("ARXIV_PAPER_CRAWLER_AI_CATEGORIES", "cs.AI,cs.CL")

    settings = load_settings(project_root=tmp_path)

    assert settings.days_to_search == 3
    assert settings.max_results == 25
    assert settings.download_pdfs is True
    assert settings.ai_categories == ("cs.AI", "cs.CL")
