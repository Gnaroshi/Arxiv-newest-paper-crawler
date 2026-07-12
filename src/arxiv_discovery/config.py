from __future__ import annotations

import importlib.util
import os
from dataclasses import dataclass, field, replace
from pathlib import Path
from types import ModuleType
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

ENV_PREFIX = "ARXIV_DISCOVERY_"
LEGACY_ENV_PREFIX = "ARXIV_PAPER_CRAWLER_"

DEFAULT_CATEGORIES = (
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


def _env(name: str) -> str | None:
    return os.getenv(f"{ENV_PREFIX}{name}") or os.getenv(f"{LEGACY_ENV_PREFIX}{name}")


def _env_int(name: str, default: int) -> int:
    raw = _env(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = _env(name)
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = _env(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_list(name: str, default: tuple[str, ...]) -> tuple[str, ...]:
    raw = _env(name)
    if raw is None:
        return default
    values = tuple(item.strip() for item in raw.split(",") if item.strip())
    return values or default


@dataclass(frozen=True, slots=True)
class Settings:
    project_root: Path
    data_dir: Path
    templates_dir: Path
    papers_path: Path
    favorites_path: Path
    pdfs_dir: Path
    timezone: str = "UTC"
    cutoff_time: str = "00:00"
    categories: tuple[str, ...] = DEFAULT_CATEGORIES
    days: int = 1
    max_results: int = 200
    translate: bool = False
    download_mode: str = "none"
    google_api_key: str | None = None
    gemini_model: str = "gemini-1.5-flash-latest"
    translation_delay_seconds: float = 1.0
    flask_host: str = "127.0.0.1"
    flask_port: int = 8080
    flask_debug: bool = False
    subject_map: dict[str, str] = field(default_factory=dict)
    legacy_mode: bool = False

    @property
    def cutoff_hour_minute(self) -> tuple[int, int]:
        hour, minute = self.cutoff_time.split(":", maxsplit=1)
        return int(hour), int(minute)

    @property
    def timezone_info(self) -> ZoneInfo:
        try:
            return ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError(f"Unknown timezone: {self.timezone}") from exc

    def ensure_runtime_directories(self, *, include_pdfs: bool = False) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        if include_pdfs:
            self.pdfs_dir.mkdir(parents=True, exist_ok=True)

    def with_overrides(self, **values: object) -> "Settings":
        return replace(self, **values)


def _legacy_config(project_root: Path) -> ModuleType | None:
    path = project_root / "config.py"
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location("arxiv_discovery_legacy_config", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_settings(
    project_root: Path | None = None,
    *,
    legacy: bool = False,
) -> Settings:
    package_root = Path(__file__).resolve().parent
    root = Path(project_root).resolve() if project_root else package_root.parent.parent
    runtime_root = root if legacy else root / "data"
    legacy_config = _legacy_config(root) if legacy else None

    categories = _env_list("CATEGORIES", DEFAULT_CATEGORIES)
    categories = _env_list("AI_CATEGORIES", categories)
    days = _env_int("DAYS", _env_int("DAYS_TO_SEARCH", 1))
    maximum = _env_int("MAX_RESULTS", 200)
    subject_map = dict(DEFAULT_SUBJECT_MAP)
    if legacy_config is not None:
        categories = tuple(getattr(legacy_config, "AI_CATEGORIES", categories))
        days = int(getattr(legacy_config, "DAYS_TO_SEARCH", days))
        maximum = int(getattr(legacy_config, "MAX_RESULTS", maximum))
        subject_map.update(getattr(legacy_config, "SUBJECT_MAP", {}))

    return Settings(
        project_root=root,
        data_dir=runtime_root,
        templates_dir=package_root / "web" / "templates",
        papers_path=runtime_root / "papers.json",
        favorites_path=runtime_root / "favorites.json",
        pdfs_dir=runtime_root / "pdfs",
        timezone=_env("TIMEZONE") or ("Asia/Seoul" if legacy else "UTC"),
        cutoff_time=_env("CUTOFF_TIME") or ("07:00" if legacy else "00:00"),
        categories=categories,
        days=days,
        max_results=maximum,
        translate=legacy or _env_bool("TRANSLATE", False),
        download_mode="all" if legacy else "none",
        google_api_key=(os.getenv("GOOGLE_API_KEY") or _env("GOOGLE_API_KEY")),
        gemini_model=_env("GEMINI_MODEL") or "gemini-1.5-flash-latest",
        translation_delay_seconds=_env_float("TRANSLATION_DELAY_SECONDS", 1.0),
        flask_host=_env("FLASK_HOST") or ("0.0.0.0" if legacy else "127.0.0.1"),
        flask_port=_env_int("FLASK_PORT", 8080),
        flask_debug=_env_bool("FLASK_DEBUG", legacy),
        subject_map=subject_map,
        legacy_mode=legacy,
    )
