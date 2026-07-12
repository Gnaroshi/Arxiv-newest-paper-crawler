from __future__ import annotations

import sys
from collections.abc import Callable, Sequence
from pathlib import Path

from .collector import collect_papers
from .config import Settings
from .contracts import (
    Candidate,
    IntegrationEnvelope,
    candidate_from_paper,
    candidate_id,
    emit_json,
    envelope,
    write_export,
)
from .models import StoredPaper
from .storage import DataCorruptionError, load_papers, save_papers
from .translator import translate_papers

Diagnostic = Callable[[str], None]


def stderr(message: str) -> None:
    print(message, file=sys.stderr)


def configuration_data(settings: Settings) -> dict[str, object]:
    return {
        "timezone": settings.timezone,
        "cutoffTime": settings.cutoff_time,
        "categories": list(settings.categories),
        "days": settings.days,
        "maxResults": settings.max_results,
    }


def discover(
    settings: Settings,
    *,
    download: str = "none",
    collector=collect_papers,
    diagnostic: Diagnostic = stderr,
) -> IntegrationEnvelope:
    if download != "none":
        return envelope(
            "discover-papers",
            status="blocked",
            data={"downloadMode": download, "candidates": []},
            errors=[{
                "code": "download-mode-not-yet-enabled",
                "message": (
                    "This provider version supports discovery with "
                    "download=none only."
                ),
            }],
        )
    papers = collector(
        settings,
        download_pdfs=False,
        diagnostic=diagnostic,
    )
    candidates = [candidate_from_paper(paper) for paper in papers]
    return envelope(
        "discover-papers",
        data={
            "downloadMode": "none",
            "configuration": configuration_data(settings),
            "candidateCount": len(candidates),
            "candidates": candidates,
        },
    )


def _select_candidates(
    papers: list[StoredPaper],
    selected_ids: Sequence[str] | None,
) -> tuple[list[StoredPaper], list[Candidate]]:
    candidates = [candidate_from_paper(paper) for paper in papers]
    if not selected_ids:
        return papers, candidates
    selected = set(selected_ids)
    pairs = [
        (paper, candidate)
        for paper, candidate in zip(papers, candidates, strict=True)
        if candidate["candidateId"] in selected
        or candidate["arxivId"] in selected
        or candidate_id(candidate["arxivId"]) in selected
    ]
    return [paper for paper, _ in pairs], [candidate for _, candidate in pairs]


def export_candidates(
    settings: Settings,
    *,
    selected_ids: Sequence[str] | None = None,
    output: Path | None = None,
) -> IntegrationEnvelope:
    papers = load_papers(settings.papers_path)
    _selected_papers, candidates = _select_candidates(papers, selected_ids)
    result = envelope(
        "export-candidates",
        data={
            "candidateCount": len(candidates),
            "candidates": candidates,
            "sourceProvider": "arxiv-crawler",
        },
    )
    if output is not None:
        digest = write_export(output, result)
        result["data"]["export"] = {"written": True, "sha256": digest}
    return result


def translate_selected(
    settings: Settings,
    *,
    selected_ids: Sequence[str],
    diagnostic: Diagnostic = stderr,
) -> IntegrationEnvelope:
    if not settings.google_api_key:
        return envelope(
            "export-candidates",
            status="blocked",
            data={"candidateCount": 0, "candidates": []},
            errors=[{
                "code": "translation-credential-unavailable",
                "message": "Configure the translation provider before translating.",
            }],
        )
    papers = load_papers(settings.papers_path)
    selected_papers, _candidates = _select_candidates(papers, selected_ids)
    translated = translate_papers(selected_papers, settings, diagnostic=diagnostic)
    translated_by_id = {
        candidate_id(paper["short_id"]): paper for paper in translated
    }
    merged = [
        translated_by_id.get(candidate_id(paper["short_id"]), paper)
        for paper in papers
    ]
    save_papers(settings.papers_path, merged)
    candidates = [candidate_from_paper(paper) for paper in translated]
    return envelope(
        "export-candidates",
        data={
            "candidateCount": len(candidates),
            "candidates": candidates,
            "translationRequested": True,
        },
    )


def doctor(settings: Settings) -> IntegrationEnvelope:
    warnings: list[str] = []
    status = "ok"
    candidate_count = 0
    data_state = "missing"
    errors = []
    if settings.papers_path.exists():
        try:
            candidate_count = len(load_papers(settings.papers_path))
            data_state = "ready"
        except DataCorruptionError:
            status = "blocked"
            data_state = "corrupt"
            errors.append({
                "code": "local-data-corrupt",
                "message": (
                    "Local paper data is unreadable; restore its backup before export."
                ),
            })
    if not settings.google_api_key:
        warnings.append(
            "Translation is unavailable until its optional credential is configured."
        )
    return envelope(
        "health",
        status=status,
        data={
            "candidateData": data_state,
            "candidateCount": candidate_count,
            "translation": "available" if settings.google_api_key else "not-configured",
            "defaultDownloadMode": "none",
            "configuration": configuration_data(settings),
        },
        warnings=warnings,
        errors=errors,
    )


def emit_result(value: IntegrationEnvelope, *, json_mode: bool) -> int:
    if json_mode:
        emit_json(value)
    else:
        print(
            f"{value['capability']}: {value['status']} "
            f"({value['data'].get('candidateCount', 0)} candidate(s))"
        )
    return 0 if value["status"] in {"ok", "partial"} else 2
