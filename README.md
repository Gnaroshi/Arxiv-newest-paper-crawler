# Arxiv Discovery

Arxiv Discovery is a native macOS application for finding recent arXiv papers, narrowing the candidate list, reading one abstract, and explicitly choosing whether to save, translate, open, or download it.

The SwiftUI app is the primary interface. Python remains available for compatibility and scripted public-metadata discovery; there is no local web server.

## What works

- Native arXiv discovery with 1, 3, or 7 day windows
- All, saved, subject, and text filters
- Persistent local paper and favorite JSON
- Explicit per-paper PDF download
- Optional per-paper Korean translation with a Keychain-stored Gemini key
- Read-only Studio status helper and versioned application manifest
- Import of the previous `papers.json` and sibling `favorites.json`
- Safe schema-v1 candidate discovery and export from the Python provider
- Signed local app packaging and stable installation under `/Applications`

Discovery does not download PDFs or call Gemini. Those actions happen only after the user selects a paper and requests them.

## Requirements

- macOS 14+
- Swift 5.9+
- Python 3.11+
- [`uv`](https://docs.astral.sh/uv/)
- A local Apple Development or Developer ID Application signing identity for stable installation

## Build and install the macOS app

```bash
uv sync --dev
./ArxivDiscoveryApp/build_app.sh
./ArxivDiscoveryApp/install_app.sh
```

The installed application is `/Applications/Arxiv Discovery.app`. The install script does not force-quit a running copy; close the app normally and rerun the command when replacement is blocked.

## Native data

The app owns `~/Library/Application Support/dev.gnaroshi.ArxivDiscovery/`:

- `papers.json`: public arXiv metadata and optional Korean abstracts
- `favorites.json`: saved arXiv IDs
- `status.json`: safe count and freshness summary for read-only integration
- `PDFs/`: PDFs downloaded by explicit action

Use the app Import command to merge an older `data/papers.json`. When a sibling `favorites.json` exists, favorites are imported too. Source files are never modified.

## Optional Gemini translation

Open Settings, enter a Gemini API key, and save it to Keychain. Translation sends only the selected public paper title and abstract. The default stable model is `gemini-3.5-flash`.

The compatibility CLIs accept `GEMINI_API_KEY`; the app does not read `.env`.

## Python CLIs

The safe provider retains schema-v1 discovery and export for scripts without becoming the Studio integration endpoint:

```bash
uv run arxiv-discovery discover --json --download=none
uv run arxiv-discovery discover --download=selected --select arxiv:2401.00001
uv run arxiv-discovery export --json
uv run arxiv-discovery doctor --json
uv run arxiv-discovery version --json
uv run arxiv-discovery recent --json --limit 5
```

`discover` defaults to no download and no translation. `selected` and `all` download modes remain explicit. Candidate fields and handoff boundaries are documented in [`docs/candidate-schema.md`](docs/candidate-schema.md).

The previous processing workflow also remains available:

```bash
uv run arxiv-paper-crawler process
uv run arxiv-paper-crawler process --download-pdfs
uv run arxiv-paper-crawler process --force-recrawl
uv run arxiv-paper-crawler all
```

`all` and either CLI's old `serve` spelling open the installed native app. Use `process` when a script still needs repository-local JSON. Copy `.env.example` to `.env` only for CLI configuration; CLI runtime data remains in `data/`, separate from native data until explicitly imported.

## Integration status

Studio uses the fixed executable bundled with the app:

```bash
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryIntegration" status --json
```

It emits counts and freshness only. It never emits titles, abstracts, credentials, PDF paths, or another application's data. The general Python provider is not used as an implicit Studio command surface.

## Development checks

```bash
uv run pytest
uv run ruff check .
swift run --package-path ArxivDiscoveryApp ArxivDiscoveryCoreChecks
swift build -c release --package-path ArxivDiscoveryApp
./ArxivDiscoveryApp/build_app.sh
```

Product, architecture, design, distribution, compatibility, and rollback decisions are documented in [`docs/`](docs/).
