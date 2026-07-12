from __future__ import annotations

import json
from pathlib import Path

from arxiv_discovery.cli import build_parser, main
from arxiv_discovery.config import load_settings
from arxiv_discovery.contracts import candidate_from_paper, candidate_id, envelope
from arxiv_discovery.provider import discover, doctor, export_candidates
from arxiv_discovery.storage import save_papers

ROOT = Path(__file__).resolve().parents[1]


def stored_paper(*, short_id: str = "2401.00001v1", translated: bool = False):
    paper = {
        "entry_id": f"https://arxiv.org/abs/{short_id}",
        "short_id": short_id,
        "title": "A Typed Discovery Fixture",
        "authors": ["Ada Example", "Grace Example"],
        "subjects": ["cs.AI", "cs.LG"],
        "abstract": "An abstract that remains local to the provider response.",
        "pdf_url": f"https://arxiv.org/pdf/{short_id}",
        "published_time_utc": "2026-07-11T01:00:00+00:00",
        "updated_time_utc": "2026-07-11T02:00:00+00:00",
        "crawled_at": "2026-07-12T00:00:00+00:00",
    }
    if translated:
        paper["abstract_ko"] = "번역된 초록"
    return paper


def test_manifest_declares_real_fixed_provider_entrypoints() -> None:
    manifest = json.loads((ROOT / "gnaroshi.app.json").read_text(encoding="utf-8"))
    assert manifest["id"] == "arxiv-crawler"
    assert manifest["entrypoints"]["cli"]["executable"] == "arxiv-discovery"
    assert manifest["entrypoints"]["localHttp"] == {}
    assert manifest["entrypoints"]["deepLinks"] == []
    assert manifest["privacy"]["credentials"] == "provider-owned"
    assert "open-arxiv-paper" in manifest["capabilities"]


def test_candidate_schema_is_stable_across_arxiv_versions() -> None:
    first = candidate_from_paper(stored_paper(short_id="2401.00001v1"))
    updated = candidate_from_paper(stored_paper(short_id="2401.00001v3"))
    assert first["candidateId"] == updated["candidateId"] == "arxiv:2401.00001"
    assert first["arxivId"] == "2401.00001v1"
    assert first["duplicateHint"] == {"kind": "arxiv-id", "value": "2401.00001"}
    assert first["sourceProvider"] == "arxiv-crawler"
    assert first["translationStatus"] == "not-requested"
    assert "downloadedLocalPath" not in first


def test_discovery_defaults_to_no_download_and_does_not_translate(
    tmp_path: Path,
) -> None:
    settings = load_settings(tmp_path)
    calls = []

    def collector(_settings, *, download_pdfs, diagnostic):
        calls.append(download_pdfs)
        diagnostic("fixture diagnostic")
        return [stored_paper()]

    diagnostics = []
    result = discover(settings, collector=collector, diagnostic=diagnostics.append)
    assert result["status"] == "ok"
    assert result["data"]["downloadMode"] == "none"
    assert result["data"]["candidateCount"] == 1
    assert calls == [False]
    assert diagnostics == ["fixture diagnostic"]
    assert not settings.papers_path.exists()
    assert not settings.pdfs_dir.exists()


def test_cli_json_is_one_stdout_value_and_configuration_is_typed(
    monkeypatch, capsys
) -> None:
    monkeypatch.setattr(
        "arxiv_discovery.cli.discover",
        lambda settings, download: envelope(
            "discover-papers",
            data={
                "candidateCount": 0,
                "candidates": [],
                "configuration": {
                    "timezone": settings.timezone,
                    "cutoffTime": settings.cutoff_time,
                    "categories": list(settings.categories),
                    "days": settings.days,
                    "maxResults": settings.max_results,
                },
                "downloadMode": download,
            },
        ),
    )
    exit_code = main([
        "discover",
        "--json",
        "--download=none",
        "--timezone=UTC",
        "--cutoff-time=06:30",
        "--category=cs.CL",
        "--days=2",
        "--max-results=25",
    ])
    captured = capsys.readouterr()
    value = json.loads(captured.out)
    assert exit_code == 0
    assert captured.out.count("\n") == 1
    assert value["data"]["configuration"] == {
        "timezone": "UTC",
        "cutoffTime": "06:30",
        "categories": ["cs.CL"],
        "days": 2,
        "maxResults": 25,
    }


def test_export_filters_cached_candidates_without_destination_write(
    tmp_path: Path,
) -> None:
    settings = load_settings(tmp_path)
    save_papers(
        settings.papers_path,
        [stored_paper(short_id="2401.00001v1"), stored_paper(short_id="2401.00002v1")],
    )
    result = export_candidates(settings, selected_ids=[candidate_id("2401.00002v1")])
    assert result["data"]["candidateCount"] == 1
    assert result["data"]["candidates"][0]["candidateId"] == "arxiv:2401.00002"
    output = tmp_path / "selected" / "candidates.json"
    export_candidates(settings, selected_ids=["arxiv:2401.00002"], output=output)
    export_candidates(settings, selected_ids=["arxiv:2401.00002"], output=output)
    assert output.exists()
    assert output.with_suffix(".json.bak").exists()


def test_doctor_reports_missing_data_and_optional_translation_without_paths(
    tmp_path: Path,
) -> None:
    result = doctor(load_settings(tmp_path))
    serialized = json.dumps(result)
    assert result["status"] == "ok"
    assert result["data"]["candidateData"] == "missing"
    assert result["data"]["translation"] == "not-configured"
    assert str(tmp_path) not in serialized
    assert "GOOGLE_API_KEY" not in serialized


def test_required_new_subcommands_are_present() -> None:
    help_text = build_parser().format_help()
    for command in ("discover", "translate", "serve", "export", "doctor"):
        assert command in help_text
