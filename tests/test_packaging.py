from __future__ import annotations

import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

import pytest

from arxiv_discovery.collector import collect_papers, collection_window
from arxiv_discovery.config import load_settings
from arxiv_discovery.storage import (
    DataCorruptionError,
    load_papers,
    save_papers,
)

ROOT = Path(__file__).resolve().parents[1]


def paper() -> dict:
    return {
        "entry_id": "https://arxiv.org/abs/2401.00001v1",
        "short_id": "2401.00001v1",
        "title": "Fixture Paper",
        "authors": ["Ada Example"],
        "subjects": ["cs.AI"],
        "abstract": "Fixture abstract",
        "pdf_url": "https://arxiv.org/pdf/2401.00001v1",
        "published_time_utc": "2026-07-11T01:00:00+00:00",
        "updated_time_utc": "2026-07-11T01:00:00+00:00",
    }


def test_new_and_legacy_runtime_locations_are_distinct(tmp_path: Path) -> None:
    modern = load_settings(tmp_path)
    legacy = load_settings(tmp_path, legacy=True)
    assert modern.papers_path == tmp_path / "data" / "papers.json"
    assert modern.download_mode == "none"
    assert modern.timezone == "UTC"
    assert modern.cutoff_time == "00:00"
    assert legacy.papers_path == tmp_path / "papers.json"
    assert legacy.download_mode == "all"
    assert legacy.translate is True
    assert legacy.timezone == "Asia/Seoul"
    assert legacy.cutoff_time == "07:00"


def test_provider_legacy_keeps_process_serve_and_all(
    monkeypatch, tmp_path: Path
) -> None:
    import arxiv_discovery.legacy as legacy

    settings = load_settings(tmp_path, legacy=True)
    events: list[str] = []
    monkeypatch.setattr(legacy, "load_settings", lambda legacy=True: settings)
    monkeypatch.setattr(
        legacy,
        "run_processing_workflow",
        lambda _settings: events.append("process"),
    )
    monkeypatch.setattr(legacy, "open_native_app", lambda: events.append("serve"))
    assert legacy.main(["process"]) == 0
    assert legacy.main(["serve"]) == 0
    assert legacy.main(["all"]) == 0
    assert events == ["process", "serve", "process", "serve"]


def test_main_py_remains_a_compatibility_wrapper() -> None:
    result = subprocess.run(
        [sys.executable, "main.py", "--help"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "process" in result.stdout
    assert "serve" in result.stdout
    assert "all" in result.stdout


def test_collection_window_uses_configured_timezone_and_cutoff(tmp_path: Path) -> None:
    settings = load_settings(tmp_path).with_overrides(
        timezone="UTC",
        cutoff_time="06:30",
        days=2,
    )
    start, end = collection_window(
        settings,
        now=datetime(2026, 7, 12, 8, 0, tzinfo=timezone.utc),
    )
    assert start.isoformat() == "2026-07-10T06:30:00+00:00"
    assert end.isoformat() == "2026-07-12T06:30:00+00:00"


def test_collector_does_not_download_when_disabled(tmp_path: Path) -> None:
    settings = load_settings(tmp_path).with_overrides(
        timezone="UTC", cutoff_time="07:00", days=1
    )
    result = SimpleNamespace(
        entry_id="https://arxiv.org/abs/2401.00001v1",
        get_short_id=lambda: "2401.00001v1",
        title="Fixture Paper",
        authors=[SimpleNamespace(name="Ada Example")],
        categories=["cs.AI"],
        summary="Fixture abstract",
        pdf_url="https://arxiv.org/pdf/2401.00001v1",
        published=datetime(2026, 7, 11, 12, 0, tzinfo=timezone.utc),
        updated=datetime(2026, 7, 11, 12, 0, tzinfo=timezone.utc),
        download_pdf=lambda **_kwargs: pytest.fail("download must not run"),
    )
    papers = collect_papers(
        settings,
        download_mode="none",
        results=[result],
        now=datetime(2026, 7, 12, 12, 0, tzinfo=timezone.utc),
    )
    assert len(papers) == 1
    assert "local_pdf_path" not in papers[0]


def test_storage_is_atomic_and_corruption_is_visible(tmp_path: Path) -> None:
    path = tmp_path / "data" / "papers.json"
    save_papers(path, [paper()])
    save_papers(path, [paper()])
    assert path.with_suffix(".json.bak").exists()
    path.write_text("{broken", encoding="utf-8")
    with pytest.raises(DataCorruptionError, match="papers.json"):
        load_papers(path)
