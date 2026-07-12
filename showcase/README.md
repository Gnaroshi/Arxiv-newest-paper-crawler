# Arxiv Discovery showcase

Run `GNAROSHI_SHOWCASE=1 python main.py serve`. The Flask app reads two deterministic synthetic VLA records, performs no crawler, translation, network, or PDF operation, and disables favorite writes. Normal execution continues to read its configured JSON records.

Capture `/all`, `/paper/example-vla-01`, and `/handoff/example-vla-01`. Add `?theme=light` only for the light verification image. Run `python -m unittest test_showcase.py` in an environment with Flask installed.
