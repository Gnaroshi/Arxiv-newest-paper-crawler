# Arxiv newest paper crawler

Discover recent arXiv papers, optionally translate or download explicitly selected content, and review saved results through the existing local Flask UI. The installable provider is `arxiv-discovery`; the historical `main.py` workflow remains available.

## Setup

Requires Python 3.11+ and [uv](https://docs.astral.sh/uv/).

```bash
uv sync --extra translation --dev
```

`GOOGLE_API_KEY` is optional and used only by the explicit `translate` command or the legacy processing workflow. Discovery does not translate automatically.

## Safe provider CLI

Studio uses exactly:

```bash
uv run arxiv-discovery discover --json --download=none
```

The default download mode is `none`. Available commands are:

```bash
uv run arxiv-discovery discover --download=none
uv run arxiv-discovery discover --download=selected --select arxiv:2401.00001
uv run arxiv-discovery discover --download=all
uv run arxiv-discovery translate --candidate arxiv:2401.00001
uv run arxiv-discovery export --json
uv run arxiv-discovery doctor --json
uv run arxiv-discovery serve
```

`selected` requires at least one candidate or arXiv ID. `all` is intentionally explicit because it downloads every matching result. Only candidates downloaded by that invocation contain `downloadedLocalPath`.

Discovery-window options are per-run rather than a tracked personal schedule:

```bash
uv run arxiv-discovery discover \
  --timezone UTC \
  --cutoff-time 00:00 \
  --category cs.AI \
  --category cs.CL \
  --days 2 \
  --max-results 100 \
  --download=none
```

The new CLI defaults to UTC, midnight cutoff, one day, 200 results, the documented research categories, no translation, and no download. Environment overrides use the `ARXIV_DISCOVERY_` prefix; legacy `ARXIV_PAPER_CRAWLER_` configuration remains readable.

## Legacy compatibility

These commands remain available:

```bash
uv run python main.py process
uv run python main.py serve
uv run python main.py all
```

`process` and `all` preserve the historical behavior: they download every matching PDF, attempt translation when configured, and write root `papers.json`. They print that impact before starting. `serve` preserves the favorites and all-papers Flask views. The legacy defaults remain Asia/Seoul, 07:00, all-interface Flask binding, and debug mode for compatibility; use the new CLI for loopback-safe defaults.

## Candidate contract

JSON commands emit one schema-v1 value on stdout. Diagnostics go to stderr. Candidate records contain stable candidate/arXiv IDs, bibliographic fields, submitted/updated times, arXiv/PDF URLs, translation status, duplicate hint, and source provider. See [`docs/candidate-schema.md`](docs/candidate-schema.md).

Studio may discover, filter, preview a PaperFlow or Paper Lab handoff, and open the validated arXiv page. No Studio command downloads, translates, favorites, publishes, writes PaperFlow, or writes Paper Lab. Send actions are previews until the destination application confirms its own import.

## Local data and web UI

The new CLI uses ignored runtime files under `data/`:

- `data/papers.json`
- `data/favorites.json`
- `data/pdfs/`
- `*.bak` recovery copies created before JSON replacement

Legacy commands keep root `papers.json`, `favorites.json`, and `pdfs/`. Nothing migrates or deletes them automatically. See [`docs/migration.md`](docs/migration.md).

The Flask UI remains intentionally unchanged at this stage:

- `/`: saved/favorite papers
- `/all`: all cached papers
- `/favorite/<short_id>`: explicit favorite toggle

The new `serve` command binds to `127.0.0.1:8080` with debug disabled unless explicitly overridden. The UI is not a provider API; Studio consumes only the CLI JSON contract.

Gnaroshi Studio may start this same loopback-only `serve` entrypoint as an
app-owned local UI and open it in the user's browser. Studio owns that child
process and stops it when Studio exits; the standalone `arxiv-discovery serve`
workflow remains unchanged.

## Development

```bash
uv run pytest
uv run ruff check .
uv run python -m build
```
