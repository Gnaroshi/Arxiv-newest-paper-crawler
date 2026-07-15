from dataclasses import replace
from types import SimpleNamespace

from arxiv_paper_crawler.config import load_settings
from arxiv_paper_crawler.translator import process_papers_with_gemini


class FakeModels:
    def __init__(self):
        self.calls = []

    def generate_content(self, *, model, contents):
        self.calls.append({"model": model, "contents": contents})
        return SimpleNamespace(text="번역된 초록")


def test_translation_uses_current_client_shape_and_preserves_source(
    monkeypatch, tmp_path
):
    models = FakeModels()
    client = SimpleNamespace(models=models)
    settings = replace(
        load_settings(project_root=tmp_path),
        google_api_key="test-only-key",
        translation_delay_seconds=0,
    )
    paper = {"title": "Example", "abstract": "English abstract"}
    monkeypatch.setattr(
        "arxiv_paper_crawler.translator._build_model",
        lambda _: client,
    )

    translated = process_papers_with_gemini([paper], settings)

    assert paper == {"title": "Example", "abstract": "English abstract"}
    assert translated[0]["abstract_ko"] == "번역된 초록"
    assert models.calls[0]["model"] == "gemini-3.5-flash"
    assert "English abstract" in models.calls[0]["contents"]
