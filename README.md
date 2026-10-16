# Arxiv Discovery

Arxiv Discovery is a native macOS application for finding recent arXiv papers, narrowing the candidate list, reading one abstract, and explicitly choosing whether to save, translate, open, or download it.

The SwiftUI app is the primary interface. Python remains available for compatibility and scripted public-metadata discovery; there is no local web server.

## What works

- Multi-date UTC discovery calendar with paper counts and searched/unsearched state
- Separate research-topic discovery (VLA / World Models by default) and explicit broad arXiv-category discovery
- Recoverable cleanup of unrelated unread Inbox/New papers, with preview, backup, excluded list, and undo
- Inbox, New, Reviewed, Saved, collection, VLA, World Models, subject, and text filters
- Persistent collections, per-paper notes, translations, and discovery history
- Explicit per-paper PDF download
- Optional per-paper Korean translation with a Keychain-stored Gemini key, selectable compatible model, and app-local token totals
- Private Studio backup export plus read-only status helper
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
- `library.json`: Inbox/Reviewed/Saved state, collections, and notes
- `discovery-history.json`: searched UTC dates, subject coverage, counts, and last search times
- `translation-usage.json`: app-local Gemini request and token totals
- `cleanup-state.json`: recoverable exclusions; original paper metadata and reading state remain intact
- `Backups/cleanup-*/`: snapshots written before cleanup or restore
- `status.json`: safe count and freshness summary for read-only integration
- `PDFs/`: PDFs downloaded by explicit action

Use the app Import command to merge an older `data/papers.json`. When a sibling `favorites.json` exists, favorites are imported too. Source files are never modified.

## Topic Discovery and Cleanup

In Calendar, choose **연구 주제** to fetch only VLA / World Models papers for the selected dates. Topic matching uses titles and abstracts, including robotics context for the VLA acronym. **arXiv 분야 태그** is a separate, explicitly broad mode that fetches entire selected categories. Changing mode or topics invalidates the previous calendar coverage for that date.

Open **라이브러리 정리** to preview unrelated unread Inbox papers, then choose **관련 없는 논문 제외**. Saved, Reviewed, viewed papers, collection members, notes, translations, and downloaded PDFs are protected. Excluded papers disappear from normal library views and remain available in **제외됨**. Restore one paper there, or choose **최근 정리 되돌리기** to undo the latest batch. Original metadata, PDF files, favorites and notes are not deleted.

For local maintenance while the app is closed:

```bash
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryMaintenance" cleanup
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryMaintenance" cleanup --apply
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryMaintenance" restore --apply
```

The maintenance command operates on the native app library and defaults to a read-only preview. The Python compatibility CLI continues to use its separately configured data directory.

## Optional Gemini translation

Open Settings, enter a Gemini API key, and save it to Keychain. The app loads models available to that key and shows only models supporting `generateContent`. Translation sends only the selected public paper title and abstract. Gemini response token metadata is accumulated locally; account-wide billing or quota usage is not claimed.

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

`status --json` emits counts and freshness only. The separately declared `backup --json` command emits a versioned private snapshot for Gnaroshi Studio. It includes the app's paper library and review state but never API keys, Keychain data, PDFs, downloaded-file paths, or another application's data. The general Python provider is not used as an implicit Studio command surface.

## Development checks

```bash
uv run pytest
uv run ruff check .
swift run --package-path ArxivDiscoveryApp ArxivDiscoveryCoreChecks
swift build -c release --package-path ArxivDiscoveryApp
./ArxivDiscoveryApp/build_app.sh
```

Product, architecture, design, distribution, compatibility, and rollback decisions are documented in [`docs/`](docs/).
