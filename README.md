# Arxiv Discovery

Arxiv Discovery is a native macOS application for finding recent arXiv papers, narrowing the candidate list, reading one abstract, and explicitly choosing whether to save, translate, open, or download it.

The SwiftUI app is the primary interface. A compatible Python CLI remains available for scripted collection and Korean abstract translation; there is no local web server.

## What works

- Native arXiv discovery with 1, 3, or 7 day windows
- All, saved, subject, and text filters
- Persistent local paper and favorite JSON
- Explicit per-paper PDF download
- Optional per-paper Korean translation with a Keychain-stored Gemini key
- Read-only Studio status helper and versioned application manifest
- Import of the previous `papers.json` and sibling `favorites.json`
- Signed local app packaging and stable installation under `/Applications`

Discovery does not download PDFs or call Gemini. Those actions happen only after the user selects a paper and presses the corresponding button.

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

The installed application is:

```text
/Applications/Arxiv Discovery.app
```

The install script does not force-quit a running copy. Close the app normally and rerun the command when replacement is blocked.

## Native data

The app owns this local directory:

```text
~/Library/Application Support/dev.gnaroshi.ArxivDiscovery/
```

- `papers.json`: public arXiv metadata and optional Korean abstracts
- `favorites.json`: saved arXiv IDs
- `status.json`: safe count/freshness summary for read-only integration
- `PDFs/`: PDFs downloaded by explicit action

Use the app's Import command to merge an older `data/papers.json`. When a sibling `favorites.json` exists, favorites are imported too. Source files are never modified.

## Optional Gemini translation

Open Settings, enter a Gemini API key, and save it to Keychain. Translation sends only the selected public paper title and abstract. The default stable model is `gemini-3.5-flash`.

The CLI accepts `GEMINI_API_KEY`; the app does not read `.env`.

## Python compatibility CLI

```bash
uv run arxiv-paper-crawler process
uv run arxiv-paper-crawler process --download-pdfs
uv run arxiv-paper-crawler process --force-recrawl
uv run arxiv-paper-crawler all
```

`all` and the old `serve` spelling are retained temporarily as aliases that open the installed native app. Use `process` when a script still needs repository-local JSON.

Copy `.env.example` to `.env` only for CLI configuration. CLI runtime data remains in repository-local `data/`; native data is separate until explicitly imported.

## Integration status

The installed bundle contains a fixed read-only command:

```bash
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryIntegration" status --json
```

It emits counts and freshness only. It never emits titles, abstracts, credentials, PDF paths, or another application's data.

## Development checks

```bash
uv run pytest
uv run ruff check .
swift run --package-path ArxivDiscoveryApp ArxivDiscoveryCoreChecks
./ArxivDiscoveryApp/build_app.sh
```

Product, architecture, design, distribution, compatibility, and rollback decisions are documented in [`docs/`](docs/).
