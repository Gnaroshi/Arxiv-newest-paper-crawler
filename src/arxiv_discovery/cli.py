from __future__ import annotations

import argparse
from collections.abc import Sequence
from pathlib import Path

from arxiv_paper_crawler.cli import open_native_app

from .config import load_settings
from .provider import (
    discover,
    doctor,
    emit_result,
    export_candidates,
    recent_activity,
    status,
    translate_selected,
    version,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="arxiv-discovery",
        description="Safe local arXiv paper discovery provider.",
    )
    parser.add_argument("--version", action="version", version="%(prog)s 0.3.0")
    subcommands = parser.add_subparsers(dest="command", required=True)
    discover_command = subcommands.add_parser(
        "discover", help="Discover candidates without writing local data"
    )
    _add_discovery_options(discover_command)
    discover_command.add_argument(
        "--download", choices=["none", "selected", "all"], default="none"
    )
    discover_command.add_argument(
        "--select",
        action="append",
        help="Candidate or arXiv ID to download when --download=selected",
    )
    discover_command.add_argument("--json", action="store_true")

    translate = subcommands.add_parser(
        "translate", help="Explicitly translate selected cached candidates"
    )
    translate.add_argument("--candidate", action="append", required=True)
    translate.add_argument("--json", action="store_true")

    subcommands.add_parser("serve", help="Open the native macOS application")

    export = subcommands.add_parser(
        "export", help="Export cached candidates through the versioned schema"
    )
    export.add_argument("--candidate", action="append")
    export.add_argument("--output", type=Path)
    export.add_argument("--json", action="store_true")

    doctor_command = subcommands.add_parser(
        "doctor", help="Check provider configuration and local data safely"
    )
    _add_discovery_options(doctor_command)
    doctor_command.add_argument("--json", action="store_true")

    version_command = subcommands.add_parser(
        "version", help="Show provider and build versions"
    )
    version_command.add_argument("--json", action="store_true")

    status_command = subcommands.add_parser(
        "status", help="Show provider availability safely"
    )
    _add_discovery_options(status_command)
    status_command.add_argument("--json", action="store_true")

    recent_command = subcommands.add_parser(
        "recent", help="Show bounded cached discovery activity"
    )
    recent_command.add_argument("--limit", type=int, default=5)
    recent_command.add_argument("--json", action="store_true")
    return parser


def _add_discovery_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--timezone")
    parser.add_argument("--cutoff-time")
    parser.add_argument("--category", action="append")
    parser.add_argument("--days", type=int)
    parser.add_argument("--max-results", type=int)


def _configured_settings(args: argparse.Namespace):
    settings = load_settings()
    overrides = {}
    if getattr(args, "timezone", None):
        overrides["timezone"] = args.timezone
    if getattr(args, "cutoff_time", None):
        overrides["cutoff_time"] = args.cutoff_time
    if getattr(args, "category", None):
        overrides["categories"] = tuple(args.category)
    if getattr(args, "days", None) is not None:
        if args.days < 1 or args.days > 31:
            raise ValueError("days must be between 1 and 31")
        overrides["days"] = args.days
    if getattr(args, "max_results", None) is not None:
        if args.max_results < 1 or args.max_results > 2000:
            raise ValueError("max-results must be between 1 and 2000")
        overrides["max_results"] = args.max_results
    configured = settings.with_overrides(**overrides)
    configured.timezone_info
    configured.cutoff_hour_minute
    return configured


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        settings = _configured_settings(args)
    except (TypeError, ValueError):
        parser = build_parser()
        parser.error("Invalid discovery configuration")
        return 2
    if args.command == "discover":
        try:
            return emit_result(
                discover(
                    settings,
                    download=args.download,
                    selected_ids=args.select,
                ),
                json_mode=args.json,
            )
        except Exception:
            from .contracts import envelope

            return emit_result(
                envelope(
                    "discover-papers",
                    status="failed",
                    errors=[
                        {
                            "code": "discovery-failed",
                            "message": "arXiv discovery failed safely.",
                        }
                    ],
                ),
                json_mode=args.json,
            )
    if args.command == "translate":
        return emit_result(
            translate_selected(settings, selected_ids=args.candidate),
            json_mode=args.json,
        )
    if args.command == "serve":
        print(
            "The Flask interface has been replaced by Arxiv Discovery.app. "
            "Opening the native application."
        )
        return 0 if open_native_app() else 2
    if args.command == "export":
        try:
            return emit_result(
                export_candidates(
                    settings,
                    selected_ids=args.candidate,
                    output=args.output,
                ),
                json_mode=args.json,
            )
        except Exception:
            from .contracts import envelope

            return emit_result(
                envelope(
                    "export-candidates",
                    status="failed",
                    errors=[
                        {
                            "code": "candidate-export-failed",
                            "message": "Candidate export failed safely.",
                        }
                    ],
                ),
                json_mode=args.json,
            )
    if args.command == "doctor":
        return emit_result(doctor(settings), json_mode=args.json)
    if args.command == "version":
        return emit_result(version(), json_mode=args.json)
    if args.command == "status":
        return emit_result(status(settings), json_mode=args.json)
    if args.command == "recent":
        return emit_result(
            recent_activity(settings, limit=args.limit), json_mode=args.json
        )
    return 0
