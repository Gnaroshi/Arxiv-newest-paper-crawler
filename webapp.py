# import json
#
# from flask import Flask, render_template
#
# app = Flask(__name__)
#
#
# def load_papers_from_json(filename="papers.json"):
#     try:
#         with open(filename, "r", encoding="utf-8") as f:
#             return json.load(f)
#     except FileNotFoundError:
#         return []
#
#
# @app.route("/")
# def index():
#     papers = load_papers_from_json()
#     return render_template("index.html", papers=papers)
#
#
# def run_web_app():
#     print("starting web application")
#     app.run(debug=True, use_reloader=False, host="0.0.0.0", port=8080)

# webapp.py

# webapp.py

# webapp.py

import json
import os
from collections import defaultdict
from datetime import datetime

from flask import Flask, redirect, render_template, request, url_for

try:
    import config
except ModuleNotFoundError:
    class config:  # The legacy checkout did not commit its local config module.
        SUBJECT_MAP = {"cs.AI": "Artificial Intelligence", "cs.RO": "Robotics", "cs.CV": "Computer Vision"}

app = Flask(__name__)
PAPERS_FILE = "papers.json"
FAVORITES_FILE = "favorites.json"

SHOWCASE_PAPERS = [
    {
        "short_id": "example-vla-01",
        "title": "Example: Grounded action planning with compact visual tokens",
        "authors": ["Example Author A", "Example Author B"],
        "subjects": ["cs.RO", "cs.CV"],
        "abstract": "A deterministic example record used to review a no-download discovery and handoff workflow.",
        "abstract_ko": "다운로드 없이 탐색과 인계 흐름을 검토하기 위한 결정적 예시 레코드입니다.",
        "pdf_url": "",
        "published_time_utc": "2026-07-10T09:00:00Z",
    },
    {
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


def showcase_enabled(environ=None):
    values = environ if environ is not None else os.environ
    return values.get("GNAROSHI_SHOWCASE") == "1"


def load_papers_from_json():
    """Loads all paper data from the main JSON file."""
    if showcase_enabled():
        return SHOWCASE_PAPERS
    try:
        with open(PAPERS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return []


def load_favorite_ids():
    """Loads the list of favorite paper short_ids from the favorites JSON file."""
    if showcase_enabled():
        return []
    if not os.path.exists(FAVORITES_FILE):
        return []
    try:
        with open(FAVORITES_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        return []


def save_favorite_ids(ids):
    """Saves the list of favorite paper short_ids to the favorites JSON file."""
    if showcase_enabled():
        raise RuntimeError("Showcase mode is read-only")
    with open(FAVORITES_FILE, "w", encoding="utf-8") as f:
        json.dump(ids, f, indent=2)


def group_papers_by_date(papers):
    """Groups a list of papers into a dictionary keyed by publication date."""
    grouped = defaultdict(list)
    for paper in papers:
        date_str = datetime.fromisoformat(
            paper["published_time_utc"].replace("Z", "+00:00")
        ).strftime("%Y-%m-%d")
        grouped[date_str].append(paper)
    return dict(sorted(grouped.items(), reverse=True))


@app.route("/")
def index():
    """Handler for the main page, showing ONLY FAVORITE papers."""
    all_papers = load_papers_from_json()
    favorite_ids = load_favorite_ids()

    favorite_papers = [p for p in all_papers if p.get("short_id") in favorite_ids]
    grouped_favorites = group_papers_by_date(favorite_papers)

    return render_template(
        "index.html",
        grouped_papers=grouped_favorites,
        favorite_ids=favorite_ids,
        subject_map=config.SUBJECT_MAP,
    )


@app.route("/all")
def all_papers():
    """Handler for the page showing ALL papers."""
    papers = load_papers_from_json()
    favorite_ids = load_favorite_ids()
    grouped_all_papers = group_papers_by_date(papers)

    return render_template(
        "all_papers.html",
        grouped_papers=grouped_all_papers,
        favorite_ids=favorite_ids,
        subject_map=config.SUBJECT_MAP,
        showcase=showcase_enabled(),
    )


@app.route("/paper/<short_id>")
def paper_detail(short_id):
    paper = next((item for item in load_papers_from_json() if item.get("short_id") == short_id), None)
    if paper is None:
        return ("Paper not found", 404)
    return render_template("paper_detail.html", paper=paper, showcase=showcase_enabled())


@app.route("/handoff/<short_id>")
def handoff_preview(short_id):
    paper = next((item for item in load_papers_from_json() if item.get("short_id") == short_id), None)
    if paper is None:
        return ("Paper not found", 404)
    return render_template("handoff_preview.html", paper=paper, showcase=showcase_enabled())


@app.route("/favorite/<short_id>", methods=["POST"])
def toggle_favorite(short_id):
    """Adds or removes a paper from the favorites list."""
    if not short_id:
        return redirect(url_for("index"))

    favorite_ids = load_favorite_ids()

    if short_id in favorite_ids:
        favorite_ids.remove(short_id)
    else:
        favorite_ids.append(short_id)

    save_favorite_ids(favorite_ids)

    return redirect(request.referrer or url_for("index"))


def run_web_app():
    """Runs the Flask web application."""
    print("▶ Starting the web application. Access it at http://127.0.0.1:8080")
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=8080)
