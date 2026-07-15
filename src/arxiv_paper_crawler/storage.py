from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return deepcopy(default)

    try:
        with path.open("r", encoding="utf-8") as file:
            return json.load(file)
    except (json.JSONDecodeError, OSError):
        return deepcopy(default)


def save_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=4)


def load_papers(path: Path) -> list[dict[str, Any]]:
    papers = load_json(path, [])
    return papers if isinstance(papers, list) else []


def save_papers(path: Path, papers: list[dict[str, Any]]) -> None:
    save_json(path, papers)


def load_favorite_ids(path: Path) -> list[str]:
    favorite_ids = load_json(path, [])
    return favorite_ids if isinstance(favorite_ids, list) else []


def save_favorite_ids(path: Path, favorite_ids: list[str]) -> None:
    save_json(path, favorite_ids)
