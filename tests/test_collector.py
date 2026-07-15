from datetime import datetime
from types import SimpleNamespace

from arxiv_paper_crawler.collector import collect_new_papers
from arxiv_paper_crawler.config import load_settings


class FakeResult:
    def __init__(self, *, published: datetime):
        self.entry_id = "entry-1"
        self.title = "Test Paper"
        self.authors = [SimpleNamespace(name="Alice")]
        self.categories = ["cs.AI"]
        self.summary = "Abstract"
        self.pdf_url = "https://example.com/paper.pdf"
        self.published = published
        self.download_called = False

    def get_short_id(self) -> str:
        return "1234.5678"

    def download_pdf(self, *, dirpath: str, filename: str) -> None:
        self.download_called = True


class FakeClient:
    def __init__(self, result: FakeResult):
        self._result = result

    def results(self, search):
        return [self._result]


class FrozenDateTime(datetime):
    @classmethod
    def now(cls, tz=None):
        current = cls(2026, 3, 20, 12, 0, 0)
        if tz is None:
            return current
        return current.astimezone(tz)


def test_collect_new_papers_skips_pdf_download_by_default(monkeypatch, tmp_path):
    settings = load_settings(project_root=tmp_path)
    result = FakeResult(published=FrozenDateTime(2026, 3, 19, 21, 0, 0))

    monkeypatch.setattr(
        "arxiv_paper_crawler.collector.arxiv.Client",
        lambda: FakeClient(result),
    )
    monkeypatch.setattr(
        "arxiv_paper_crawler.collector.arxiv.Search",
        lambda **kwargs: kwargs,
    )
    monkeypatch.setattr(
        "arxiv_paper_crawler.collector.datetime.datetime",
        FrozenDateTime,
    )

    papers = collect_new_papers(settings)

    assert len(papers) == 1
    assert papers[0]["entry_id"] == "entry-1"
    assert result.download_called is False
    assert settings.pdfs_dir.exists() is False
