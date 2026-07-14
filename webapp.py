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

from arxiv_discovery.config import load_settings
from arxiv_discovery.web.app import create_app, group_papers_by_date, run_web_app

app = create_app(load_settings(legacy=True))

__all__ = ["app", "create_app", "group_papers_by_date", "run_web_app"]
