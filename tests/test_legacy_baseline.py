from __future__ import annotations

import ast
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = json.loads(
    (ROOT / "tests/fixtures/legacy-baseline.json").read_text(encoding="utf-8")
)


class LegacyBaselineTests(unittest.TestCase):
    def test_fixture_records_the_committed_baseline(self) -> None:
        self.assertEqual(
            FIXTURE["baselineCommit"],
            "f633ce2a3ad3ea9818eed10af1cb2fe09eeca8cf",
        )
        self.assertEqual(FIXTURE["commands"]["default"], "all")
        self.assertIn("download-all-matching-pdfs", FIXTURE["commands"]["process"])

    def test_legacy_command_names_and_dispatch_remain_visible(self) -> None:
        source = (ROOT / "src/arxiv_discovery/legacy.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        strings = {
            node.value
            for node in ast.walk(tree)
            if isinstance(node, ast.Constant) and isinstance(node.value, str)
        }
        for command in ("process", "serve", "all"):
            self.assertIn(command, strings)
        self.assertIn('args.action in {"all", "process"}', source)
        self.assertIn('args.action in {"all", "serve"}', source)

    def test_legacy_runtime_files_and_web_routes_are_recorded(self) -> None:
        web_source = (ROOT / "src/arxiv_discovery/web/app.py").read_text(
            encoding="utf-8"
        )
        legacy_source = (ROOT / "src/arxiv_discovery/legacy.py").read_text(
            encoding="utf-8"
        )
        config_source = (ROOT / "src/arxiv_discovery/config.py").read_text(
            encoding="utf-8"
        )
        self.assertIn('runtime_root / "papers.json"', config_source)
        self.assertIn('runtime_root / "favorites.json"', config_source)
        self.assertIn('@app.route("/")', web_source)
        self.assertIn('@app.route("/all")', web_source)
        self.assertIn("download_pdfs=True", legacy_source)
        self.assertEqual(FIXTURE["runtimeFiles"]["pdfDirectory"], "pdfs")

    def test_generated_and_local_only_paths_are_ignored(self) -> None:
        ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        for pattern in (
            "__pycache__/",
            "*.py[cod]",
            ".DS_Store",
            "/papers.json",
            "/favorites.json",
            "/pdfs/*",
            ".cache/",
        ):
            self.assertIn(pattern, ignore)


if __name__ == "__main__":
    unittest.main()
