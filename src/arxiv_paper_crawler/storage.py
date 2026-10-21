from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

from arxiv_discovery.storage import load_favorites as checked_load_favorites
from arxiv_discovery.storage import load_json as checked_load_json
from arxiv_discovery.storage import load_papers as checked_load_papers
from arxiv_discovery.storage import save_json as atomic_save_json


def load_json(path: Path, default: Any) -> Any:
    return checked_load_json(path, deepcopy(default))


def save_json(path: Path, payload: Any) -> None:
    atomic_save_json(path, payload)


def load_papers(path: Path) -> list[dict[str, Any]]:
    return checked_load_papers(path)


def save_papers(path: Path, papers: list[dict[str, Any]]) -> None:
    save_json(path, papers)


def load_favorite_ids(path: Path) -> list[str]:
    return checked_load_favorites(path)


def save_favorite_ids(path: Path, favorite_ids: list[str]) -> None:
    save_json(path, favorite_ids)
