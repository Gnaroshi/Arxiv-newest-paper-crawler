from __future__ import annotations

from collections import defaultdict
from datetime import datetime

from flask import Flask, redirect, render_template, request, url_for

from ..config import Settings, load_settings
from ..models import StoredPaper
from ..storage import load_favorites, load_papers, save_favorites


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

    @app.route("/")
    def index():
        papers = load_papers(resolved.papers_path)
        favorite_ids = load_favorites(resolved.favorites_path)
        favorites = [paper for paper in papers if paper.get("short_id") in favorite_ids]
        return render_template(
            "index.html",
            grouped_papers=group_papers_by_date(favorites),
            favorite_ids=favorite_ids,
            subject_map=resolved.subject_map,
        )

    @app.route("/all")
    def all_papers():
        papers = load_papers(resolved.papers_path)
        favorite_ids = load_favorites(resolved.favorites_path)
        return render_template(
            "all_papers.html",
            grouped_papers=group_papers_by_date(papers),
            favorite_ids=favorite_ids,
            subject_map=resolved.subject_map,
        )

    @app.route("/favorite/<short_id>", methods=["POST"])
    def toggle_favorite(short_id: str):
        favorite_ids = load_favorites(resolved.favorites_path)
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
    print(f"Starting the web application at http://{resolved.flask_host}:{resolved.flask_port}")
    app.run(
        debug=resolved.flask_debug,
        use_reloader=False,
        host=resolved.flask_host,
        port=resolved.flask_port,
    )
