from __future__ import annotations

import argparse
from collections.abc import Sequence

from .config import load_settings
from .web.app import run_web_app


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="arxiv-discovery",
        description="Safe local arXiv paper discovery provider.",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)
    serve = subcommands.add_parser("serve", help="Run the existing local Flask UI")
    serve.add_argument("--host")
    serve.add_argument("--port", type=int)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "serve":
        settings = load_settings()
        if args.host:
            settings = settings.with_overrides(flask_host=args.host)
        if args.port:
            settings = settings.with_overrides(flask_port=args.port)
        run_web_app(settings)
    return 0
