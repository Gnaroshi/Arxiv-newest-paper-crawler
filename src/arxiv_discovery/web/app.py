from __future__ import annotations

import os
from collections import defaultdict
from collections.abc import Mapping
from datetime import datetime

from flask import Flask, abort, redirect, render_template, request, url_for

from ..config import Settings, load_settings
from ..models import StoredPaper
from ..storage import load_favorites, load_papers, save_favorites

SHOWCASE_PAPERS: list[StoredPaper] = [
    {
        "entry_id": "showcase:example-vla-01",
        "short_id": "example-vla-01",
        "title": "Example: Grounded action planning with compact visual tokens",
        "authors": ["Example Author A", "Example Author B"],
        "subjects": ["cs.RO", "cs.CV"],
        "abstract": (
            "A deterministic example record used to review a no-download "
            "discovery and handoff workflow."
        ),
        "abstract_ko": (
            "다운로드 없이 탐색과 인계 흐름을 검토하기 위한 "
            "결정적 예시 레코드입니다."
        ),
        "pdf_url": "",
        "published_time_utc": "2026-07-10T09:00:00Z",
    },
    {
        "entry_id": "showcase:example-vla-02",
        "short_id": "example-vla-02",
        "title": "Example: Evaluating instruction following under distribution shift",
        "authors": ["Example Author C"],
        "subjects": ["cs.AI", "cs.RO"],
        "abstract": "An explicit synthetic candidate. No PDF is downloaded or opened.",
        "abstract_ko": "명시적 합성 후보이며 PDF를 다운로드하거나 열지 않습니다.",
        "pdf_url": "",
        "published_time_utc": "2026-07-09T09:00:00Z",
    },
]


def showcase_enabled(environment: Mapping[str, str] | None = None) -> bool:
    values = environment if environment is not None else os.environ
    return values.get("GNAROSHI_SHOWCASE") == "1"


def group_papers_by_date(
    papers: list[StoredPaper],
) -> dict[str, list[StoredPaper]]:
    grouped: defaultdict[str, list[StoredPaper]] = defaultdict(list)
    for paper in papers:
        date = datetime.fromisoformat(
            paper["published_time_utc"].replace("Z", "+00:00")
        ).strftime("%Y-%m-%d")
        grouped[date].append(paper)
    return dict(sorted(grouped.items(), reverse=True))


def create_app(settings: Settings | None = None) -> Flask:
    resolved = settings or load_settings()
    resolved.ensure_runtime_directories()
    app = Flask(__name__, template_folder=str(resolved.templates_dir))

    def current_papers() -> list[StoredPaper]:
        if showcase_enabled():
            return SHOWCASE_PAPERS
        return load_papers(resolved.papers_path)

    def current_favorites() -> list[str]:
        if showcase_enabled():
            return []
        return load_favorites(resolved.favorites_path)

    @app.route("/")
    def index():
        papers = current_papers()
        favorite_ids = current_favorites()
        favorites = [paper for paper in papers if paper.get("short_id") in favorite_ids]
        return render_template(
            "index.html",
            grouped_papers=group_papers_by_date(favorites),
            favorite_ids=favorite_ids,
            subject_map=resolved.subject_map,
            showcase=showcase_enabled(),
        )

    @app.route("/all")
    def all_papers():
        papers = current_papers()
        favorite_ids = current_favorites()
        return render_template(
            "all_papers.html",
            grouped_papers=group_papers_by_date(papers),
            favorite_ids=favorite_ids,
            subject_map=resolved.subject_map,
            showcase=showcase_enabled(),
        )

    @app.route("/paper/<short_id>")
    def paper_detail(short_id: str):
        paper = next(
            (item for item in current_papers() if item.get("short_id") == short_id),
            None,
        )
        if paper is None:
            abort(404)
        return render_template(
            "paper_detail.html", paper=paper, showcase=showcase_enabled()
        )

    @app.route("/handoff/<short_id>")
    def handoff_preview(short_id: str):
        paper = next(
            (item for item in current_papers() if item.get("short_id") == short_id),
            None,
        )
        if paper is None:
            abort(404)
        return render_template(
            "handoff_preview.html", paper=paper, showcase=showcase_enabled()
        )

    @app.route("/favorite/<short_id>", methods=["POST"])
    def toggle_favorite(short_id: str):
        if showcase_enabled():
            abort(403, description="Showcase mode is read-only")
        favorite_ids = current_favorites()
        if short_id in favorite_ids:
            favorite_ids.remove(short_id)
        else:
            favorite_ids.append(short_id)
        save_favorites(resolved.favorites_path, favorite_ids)
        return redirect(request.referrer or url_for("index"))

    return app


def run_web_app(settings: Settings | None = None) -> None:
    resolved = settings or load_settings()
    app = create_app(resolved)
    print(
        f"Starting the web application at http://{resolved.flask_host}:{resolved.flask_port}"
    )
    app.run(
        debug=resolved.flask_debug,
        use_reloader=False,
        host=resolved.flask_host,
        port=resolved.flask_port,
    )
