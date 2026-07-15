from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

ENV_PREFIX = "ARXIV_PAPER_CRAWLER_"

DEFAULT_AI_CATEGORIES = (
    "cs.AI",
    "cs.LG",
    "cs.CV",
    "cs.CL",
    "cs.NE",
    "stat.ML",
)

DEFAULT_SUBJECT_MAP = {
    "cs.AI": "Artificial Intelligence",
    "cs.LG": "Machine Learning",
    "cs.CV": "Computer Vision",
    "cs.CL": "Computation and Language",
    "cs.NE": "Neural and Evolutionary Computing",
    "stat.ML": "Machine Learning (Statistics)",
    "cs.RO": "Robotics",
    "cs.IR": "Information Retrieval",
    "cs.GR": "Graphics",
    "cs.CE": "Computational Engineering",
    "math.AG": "Algebraic Geometry",
    "quant-ph": "Quantum Physics",
}


def _env_int(name: str, default: int) -> int:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    try:
        return int(raw_value)
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    try:
        return float(raw_value)
    except ValueError:
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


def _env_list(name: str, default: tuple[str, ...]) -> tuple[str, ...]:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    items = [item.strip() for item in raw_value.split(",") if item.strip()]
    return tuple(items) if items else default


@dataclass(frozen=True, slots=True)
class Settings:
    project_root: Path
    package_root: Path
    data_dir: Path
    papers_path: Path
    favorites_path: Path
    pdfs_dir: Path
    days_to_search: int
    max_results: int
    download_pdfs: bool = False
    ai_categories: tuple[str, ...] = DEFAULT_AI_CATEGORIES
    subject_map: dict[str, str] = field(default_factory=dict)
    google_api_key: str | None = None
    gemini_model: str = "gemini-3.5-flash"
    translation_delay_seconds: float = 1.0
    data_refresh_hour: int = 7

    def ensure_runtime_directories(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        if self.download_pdfs:
            self.pdfs_dir.mkdir(parents=True, exist_ok=True)

    def pdf_dir_for_subject(self, subject: str | None) -> Path:
        subject_name = subject or "Uncategorized"
        path = self.pdfs_dir / subject_name
        path.mkdir(parents=True, exist_ok=True)
        return path


def load_settings(project_root: Path | None = None) -> Settings:
    package_root = Path(__file__).resolve().parent
    resolved_project_root = (
        Path(project_root).resolve() if project_root else package_root.parent.parent
    )
    resolved_package_root = package_root
    data_dir = resolved_project_root / "data"

    return Settings(
        project_root=resolved_project_root,
        package_root=resolved_package_root,
        data_dir=data_dir,
        papers_path=data_dir / "papers.json",
        favorites_path=data_dir / "favorites.json",
        pdfs_dir=data_dir / "pdfs",
        days_to_search=_env_int(f"{ENV_PREFIX}DAYS_TO_SEARCH", 1),
        max_results=_env_int(f"{ENV_PREFIX}MAX_RESULTS", 200),
        download_pdfs=_env_bool(f"{ENV_PREFIX}DOWNLOAD_PDFS", False),
        ai_categories=_env_list(
            f"{ENV_PREFIX}AI_CATEGORIES", DEFAULT_AI_CATEGORIES
        ),
        subject_map=dict(DEFAULT_SUBJECT_MAP),
        google_api_key=(
            os.getenv("GEMINI_API_KEY")
            or os.getenv("GOOGLE_API_KEY")
            or os.getenv(f"{ENV_PREFIX}GOOGLE_API_KEY")
        ),
        gemini_model=os.getenv(
            f"{ENV_PREFIX}GEMINI_MODEL", "gemini-3.5-flash"
        ),
        translation_delay_seconds=_env_float(
            f"{ENV_PREFIX}TRANSLATION_DELAY_SECONDS", 1.0
        ),
        data_refresh_hour=_env_int(f"{ENV_PREFIX}DATA_REFRESH_HOUR", 7),
    )
