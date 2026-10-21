import arxiv
import pytest
import requests
from requests.adapters import HTTPAdapter

from arxiv_discovery.network import (
    BoundedAdapter,
    configure_arxiv_client,
    download_pdf,
    gemini_http_options,
)
from arxiv_discovery.storage import DataCorruptionError, save_json
from arxiv_paper_crawler.storage import load_papers


def test_arxiv_sdk_has_timeouts_and_no_automatic_retries(monkeypatch):
    captured = {}

    def send(_adapter, _request, **kwargs):
        captured.update(kwargs)
        return requests.Response()

    monkeypatch.setattr(HTTPAdapter, "send", send)
    client = configure_arxiv_client(arxiv.Client())
    try:
        adapter = client._session.get_adapter("https://export.arxiv.org")
        assert isinstance(adapter, BoundedAdapter)
        adapter.send(requests.Request("GET", "https://example.invalid").prepare())
        assert captured["timeout"] == (5, 10)
        assert client.num_retries == 0
        assert client.delay_seconds >= 3
    finally:
        client._session.close()


def test_gemini_sdk_has_timeout_and_single_attempt():
    options = gemini_http_options()
    assert options.timeout == 30_000
    assert options.retry_options.attempts == 1


def test_corrupt_legacy_data_is_not_treated_as_an_empty_library(tmp_path):
    path = tmp_path / "papers.json"
    path.write_text("{corrupt reading state", encoding="utf-8")
    with pytest.raises(DataCorruptionError):
        load_papers(path)
    assert path.read_text(encoding="utf-8") == "{corrupt reading state"


def test_invalid_legacy_shape_is_not_treated_as_an_empty_library(tmp_path):
    path = tmp_path / "papers.json"
    path.write_text("{}", encoding="utf-8")
    with pytest.raises(DataCorruptionError):
        load_papers(path)


def test_failed_atomic_save_preserves_previous_library(monkeypatch, tmp_path):
    path = tmp_path / "papers.json"
    save_json(path, [{"title": "My reading work"}])
    previous = path.read_bytes()

    def fail_replace(*_args):
        raise OSError("fixture disk failure")

    monkeypatch.setattr("arxiv_discovery.storage.os.replace", fail_replace)
    with pytest.raises(OSError):
        save_json(path, [])
    assert path.read_bytes() == previous
    assert not list(tmp_path.glob("*.tmp"))


class PDFResponse:
    def __init__(self, chunks):
        self.chunks = chunks

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        pass

    def raise_for_status(self):
        pass

    def iter_content(self, **_kwargs):
        yield from self.chunks


def test_pdf_download_is_streamed_bounded_and_does_not_overwrite(monkeypatch, tmp_path):
    options = {}

    def get(url, **kwargs):
        options.update(kwargs, url=url)
        return PDFResponse([b"%PDF-1.7\n", b"reading copy"])

    monkeypatch.setattr("arxiv_discovery.network.requests.get", get)
    path = tmp_path / "paper.pdf"
    download_pdf("http://arxiv.org/pdf/2610.00001", path)
    assert options == {
        "url": "https://arxiv.org/pdf/2610.00001",
        "stream": True,
        "timeout": (5, 10),
    }
    before = path.read_bytes()
    monkeypatch.setattr(
        "arxiv_discovery.network.requests.get",
        lambda *_a, **_k: pytest.fail("Must keep existing reading copy"),
    )
    download_pdf("https://arxiv.org/pdf/2610.00001", path)
    assert path.read_bytes() == before


def test_non_pdf_download_is_rejected_and_temporary_file_removed(monkeypatch, tmp_path):
    monkeypatch.setattr(
        "arxiv_discovery.network.requests.get",
        lambda *_a, **_k: PDFResponse([b"<html>Server error</html>"]),
    )
    with pytest.raises(ValueError, match="did not return a PDF"):
        download_pdf("https://arxiv.org/pdf/2610.00001", tmp_path / "paper.pdf")
    assert list(tmp_path.iterdir()) == []


def test_pdf_stream_has_elapsed_time_limit(monkeypatch, tmp_path):
    times = iter([0, 46])
    monkeypatch.setattr("arxiv_discovery.network.time.monotonic", lambda: next(times))
    monkeypatch.setattr(
        "arxiv_discovery.network.requests.get",
        lambda *_a, **_k: PDFResponse([b"%PDF-1.7"]),
    )
    with pytest.raises(TimeoutError):
        download_pdf("https://arxiv.org/pdf/2610.00001", tmp_path / "paper.pdf")
    assert list(tmp_path.iterdir()) == []
