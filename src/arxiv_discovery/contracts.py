from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal, NotRequired, TypedDict
from urllib.parse import urlparse

from . import __version__
from .models import StoredPaper
from .storage import save_json

PROVIDER_ID = "arxiv-crawler"
SCHEMA_VERSION = 1
CONTRACT_VERSION = 1
ARXIV_ID = re.compile(r"^(?:\d{4}\.\d{4,5}|[a-z-]+/\d{7})(?:v\d+)?$", re.I)


class DuplicateHint(TypedDict):
    kind: Literal["arxiv-id"]
    value: str


class Candidate(TypedDict):
    candidateId: str
    arxivId: str
    title: str
    authors: list[str]
    abstract: str
    categories: list[str]
    submittedAt: str
    updatedAt: str | None
    paperUrl: str
    pdfUrl: str
    translationStatus: Literal[
        "not-requested", "available", "unavailable", "failed"
    ]
    duplicateHint: DuplicateHint
    sourceProvider: Literal["arxiv-crawler"]
    downloadedLocalPath: NotRequired[str]


class IntegrationError(TypedDict):
    code: str
    message: str


class ProviderInfo(TypedDict):
    id: Literal["arxiv-crawler"]
    version: str
    contractVersion: Literal[1]


class IntegrationEnvelope(TypedDict):
    schemaVersion: Literal[1]
    provider: ProviderInfo
    capability: str
    generatedAt: str
    status: str
    data: dict[str, Any]
    warnings: list[str]
    errors: list[IntegrationError]


def arxiv_id(value: str) -> str:
    normalized = value.strip().removeprefix("http://arxiv.org/abs/").removeprefix(
        "https://arxiv.org/abs/"
    )
    if not ARXIV_ID.fullmatch(normalized):
        raise ValueError("Invalid arXiv identifier")
    return normalized


def base_arxiv_id(value: str) -> str:
    return re.sub(r"v\d+$", "", arxiv_id(value), flags=re.I)


def candidate_id(value: str) -> str:
    return f"arxiv:{base_arxiv_id(value).lower()}"


def _translation_status(paper: StoredPaper) -> str:
    value = paper.get("abstract_ko")
    if not value:
        return "not-requested"
    if value.strip().lower() == "failed to translate":
        return "failed"
    return "available"


def _https_url(value: str, *, fallback: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme == "https" and parsed.netloc:
        return value
    return fallback


def candidate_from_paper(paper: StoredPaper) -> Candidate:
    identifier = arxiv_id(paper["short_id"])
    base = base_arxiv_id(identifier)
    paper_url = _https_url(
        paper.get("entry_id", ""),
        fallback=f"https://arxiv.org/abs/{identifier}",
    )
    pdf_url = _https_url(
        paper["pdf_url"],
        fallback=f"https://arxiv.org/pdf/{identifier}",
    )
    candidate: Candidate = {
        "candidateId": candidate_id(identifier),
        "arxivId": identifier,
        "title": paper["title"].strip(),
        "authors": list(paper["authors"]),
        "abstract": paper["abstract"].strip(),
        "categories": list(paper["subjects"]),
        "submittedAt": paper["published_time_utc"],
        "updatedAt": paper.get("updated_time_utc"),
        "paperUrl": paper_url,
        "pdfUrl": pdf_url,
        "translationStatus": _translation_status(paper),
        "duplicateHint": {"kind": "arxiv-id", "value": base},
        "sourceProvider": PROVIDER_ID,
    }
    local_path = paper.get("local_pdf_path")
    if local_path:
        candidate["downloadedLocalPath"] = local_path
    return candidate


def envelope(
    capability: str,
    *,
    status: str = "ok",
    data: dict[str, Any] | None = None,
    warnings: list[str] | None = None,
    errors: list[IntegrationError] | None = None,
) -> IntegrationEnvelope:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "provider": {
            "id": PROVIDER_ID,
            "version": __version__,
            "contractVersion": CONTRACT_VERSION,
        },
        "capability": capability,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "data": data or {},
        "warnings": warnings or [],
        "errors": errors or [],
    }


def emit_json(value: IntegrationEnvelope) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def write_export(path: Path, value: IntegrationEnvelope) -> str:
    payload = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    save_json(path, value)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
