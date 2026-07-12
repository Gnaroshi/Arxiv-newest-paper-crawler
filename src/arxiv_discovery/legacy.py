from __future__ import annotations

import argparse
import datetime as dt
from collections.abc import Sequence

from .collector import collect_papers
from .config import Settings, load_settings
from .storage import save_papers
from .translator import translate_papers
from .web.app import run_web_app


def _already_processed_today(settings: Settings) -> bool:
    if not settings.papers_path.exists():
        return False
    modified = dt.datetime.fromtimestamp(
        settings.papers_path.stat().st_mtime,
        tz=settings.timezone_info,
    )
    hour, minute = settings.cutoff_hour_minute
    cutoff = dt.datetime.now(settings.timezone_info).replace(
        hour=hour, minute=minute, second=0, microsecond=0
    )
    return modified > cutoff


def run_processing_workflow(settings: Settings | None = None) -> None:
    resolved = settings or load_settings(legacy=True)
    if _already_processed_today(resolved):
        print(f"Today's paper data ('{resolved.papers_path.name}') already exists.")
        print("Skipping data processing.")
        return
    print(
        "Legacy process mode: downloading every matching PDF and attempting "
        "translation before writing papers.json."
    )
    papers = collect_papers(resolved, download_mode="all")
    translated = translate_papers(papers, resolved)
    save_papers(resolved.papers_path, translated)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="A workflow manager for arXiv papers.")
    parser.add_argument(
        "action",
        nargs="?",
        default="all",
        choices=["process", "serve", "all"],
        help="process, serve, or all (default)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    settings = load_settings(legacy=True)
    if args.action in {"all", "process"}:
        run_processing_workflow(settings)
    if args.action in {"all", "serve"}:
        run_web_app(settings)
    return 0
