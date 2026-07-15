from __future__ import annotations

import argparse
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import replace

from .collector import collect_new_papers
from .config import Settings, load_settings
from .runtime import merge_papers, should_recrawl_today
from .storage import load_papers, save_papers
from .translator import process_papers_with_gemini

NATIVE_BUNDLE_ID = "dev.gnaroshi.ArxivDiscovery"


def run_processing_workflow(
    settings: Settings,
    *,
    force_recrawl: bool = False,
    no_prompt: bool = False,
) -> None:
    settings.ensure_runtime_directories()
    existing_papers = load_papers(settings.papers_path)

    should_crawl = should_recrawl_today(
        existing_papers,
        force_recrawl=force_recrawl,
        no_prompt=no_prompt,
    )
    if not should_crawl:
        print("Skipping crawl step for today.")
        return

    print("Starting the ArXiv paper processing workflow")
    new_papers = collect_new_papers(settings)
    processed_papers = process_papers_with_gemini(new_papers, settings)
    merged_papers = merge_papers(existing_papers, processed_papers)
    print(f"Saving processed paper data to '{settings.papers_path}'")
    save_papers(settings.papers_path, merged_papers)
    print("Save complete")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="A workflow manager for ArXiv papers."
    )
    parser.add_argument(
        "action",
        nargs="?",
        default="process",
        choices=["process", "serve", "all"],
        help=(
            "The action to perform: 'process' (collect & translate), "
            "'serve' or 'all' (compatibility aliases that open the native app)."
        ),
    )
    parser.add_argument(
        "--download-pdfs",
        action=argparse.BooleanOptionalAction,
        default=None,
        help=(
            "Download original PDFs during crawling. "
            "Defaults to config and is disabled by default."
        ),
    )
    parser.add_argument(
        "--force-recrawl",
        action="store_true",
        help="Crawl again immediately even if today's crawl already exists.",
    )
    parser.add_argument(
        "--no-prompt",
        action="store_true",
        help=(
            "Do not prompt if today's crawl already exists; "
            "keep the safe default skip behavior."
        ),
    )
    return parser


def open_native_app() -> bool:
    if sys.platform != "darwin":
        print("Arxiv Discovery is a macOS application.")
        return False

    completed = subprocess.run(
        ["open", "-b", NATIVE_BUNDLE_ID],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode == 0:
        return True

    print(
        "Arxiv Discovery.app is not installed. "
        "Run ./ArxivDiscoveryApp/install_app.sh first."
    )
    return False


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    settings = load_settings()

    if args.download_pdfs is not None:
        settings = replace(settings, download_pdfs=args.download_pdfs)

    if args.action == "process":
        run_processing_workflow(
            settings,
            force_recrawl=args.force_recrawl,
            no_prompt=args.no_prompt,
        )

    if args.action in {"all", "serve"}:
        if args.action == "serve":
            print(
                "The Flask interface has been replaced by Arxiv Discovery.app. "
                "Opening the native application."
            )
        open_native_app()

    return 0
