from __future__ import annotations

import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Any

from .models import StoredPaper


class DataCorruptionError(RuntimeError):
    """Raised when local runtime JSON exists but is not readable."""


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        raise DataCorruptionError(
            f"Local data is unreadable: {path.name}. "
            "Restore its .bak file or repair it."
        ) from exc


def save_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
    handle, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            json.dump(payload, file, ensure_ascii=False, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary_name, path)
    finally:
        temporary_path = Path(temporary_name)
        if temporary_path.exists():
            temporary_path.unlink()


def load_papers(path: Path) -> list[StoredPaper]:
    value = load_json(path, [])
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise DataCorruptionError(f"Local data has an invalid shape: {path.name}.")
    return value


def save_papers(path: Path, papers: list[StoredPaper]) -> None:
    save_json(path, papers)


def load_favorites(path: Path) -> list[str]:
    value = load_json(path, [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise DataCorruptionError(f"Local data has an invalid shape: {path.name}.")
    return value


def save_favorites(path: Path, favorite_ids: list[str]) -> None:
    save_json(path, favorite_ids)
