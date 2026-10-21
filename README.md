# Arxiv Discovery

Arxiv Discovery is a native macOS application for finding recent arXiv papers, narrowing the candidate list, reading one abstract, and explicitly choosing whether to save, translate, open, or download it.

The SwiftUI app is the primary interface. Python remains available for compatibility and scripted public-metadata discovery; there is no local web server.

## What works

- Multi-date UTC discovery calendar with paper counts and searched/unsearched state
- Separate research-topic discovery (VLA / World Models by default) and explicit broad arXiv-category discovery
- Searchable, user-editable topic rules with required and excluded phrases
- Recoverable cleanup of unrelated unread Inbox/New papers, with preview, backup, Trash, and undo
- Inbox, New, Reviewed, Saved, collection, VLA, World Models, subject, and text filters
- Daily local reading shortlist with reasons, a configurable limit/focus, and manual priority choices
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
- Full Xcode for SwiftUI builds and application tests (standalone Command Line Tools can lack SwiftUI macro plugins)
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

- `papers.json`: active public arXiv metadata and optional Korean abstracts
- `favorites.json`: saved arXiv IDs
- `library.json`: Inbox/Reviewed/Saved state, collections, and notes
- `discovery-history.json`: searched UTC dates, subject coverage, counts, and last search times
- `last-discovery.json`: terminal search outcome, timing, partial results and failure reason
- `reading-review.json`: your reading-focus preferences and explicit priority decisions
- `daily-reading.json`: the latest locally generated reading recommendations and reasons
- `Cache/Discovery/`: response pages reused for six hours, capped at 128 files / 64 MB
- `pdf-index.json`: paper-to-local-PDF ownership, avoiding same-title collisions
- `translation-usage.json`: app-local Gemini request and token totals
- `cleanup-state.json`: removal tombstones, preventing silent rediscovery
- `trash.json`: removed paper metadata, loaded only when Trash is opened
- `Backups/cleanup-*/`: snapshots written before cleanup or restore
- `status.json`: safe count and freshness summary for read-only integration
- `PDFs/`: PDFs downloaded by explicit action

Use the app Import command to merge an older `data/papers.json`. When a sibling `favorites.json` exists, favorites are imported too. Source files are never modified.

## Topic Discovery and Cleanup

In Calendar, choose **Research topics**, then **Find or create topics**. Search existing rules or create a named topic with comma-separated **Match any**, optional **Require all**, and **Exclude any** phrases. Select the topics and dates, then choose **Find topic papers**. VLA and World Models are included by default. Matching uses titles and abstracts, including robotics context for the VLA acronym. **arXiv categories** is a separate broad mode that fetches entire selected categories. Editing a rule invalidates previous calendar coverage for that rule.

Adjacent selected dates share one range query; nonadjacent dates never include unselected days. Results are paged and saved after every page, off the UI thread. The calendar shows elapsed time, completed dates, matching papers saved, and Cancel. A request has a 12-second wall-clock limit and the search has a 45-second network budget. arXiv requests are serial and spaced at least three seconds apart, following its [API guidance](https://info.arxiv.org/help/api/tou.html). Service errors and rate limits stop the batch instead of repeating the same failure for every date.

Complete coverage and response pages are reused for six hours. **Retry N unfinished dates** resumes the original date selection and partial pages, including after relaunch. Changing selected topic rules/categories disables that retry until the original scope is restored; use a new search for changed conditions. **Search options → Refresh selected dates (ignore saved results)** explicitly bypasses the cache. Partial dates remain marked as needing search. Large searches may require another run; a time/page limit is never reported as complete. Results distinguish new papers from existing IDs; `last-discovery.json` records the scope, exact matched IDs, timing and outcome without credentials.

Open **Cleanup** to preview unrelated unread Inbox papers, then choose **Move N to Trash**. Saved, Reviewed, viewed papers, collection members, notes, translations, and downloaded PDFs are protected. Removed metadata leaves the active array and remains in **Trash**. Restore one paper there, or choose **Undo last removal (N)** to restore the latest remaining batch; the confirmation shows its exact count. Older batches stay in Trash. Backups are written before changes. PDFs and notes are never deleted by cleanup. Changing topic rules invalidates the preview; only the reviewed candidate set can be applied.

Switching a topic starts its list at the top. Narrow windows constrain the list/detail split; if there is not enough room for both, a single-pane detail has **Back to papers**. Notes keep their drafts across navigation. **Save note** persists a draft, **Revert** keeps the previously saved note, and closing with drafts asks whether to save, cancel, or discard them.

Every row has bookmark (**Save for later**), checkmark (**Mark reviewed**) and trash (**Move to Trash**) actions with tooltips. Saving does not download a PDF. Reviewing does not clear bookmarks, collections or notes. The Delete key also moves the selected paper to Trash. In Trash, **Delete metadata…** explicitly confirms removal of the metadata row; downloaded PDFs, reading notes, backups and the rediscovery tombstone remain.

The interface is English. Korean remains an explicit abstract translation action.

For local maintenance while the app is closed:

```bash
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryMaintenance" cleanup
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryMaintenance" cleanup --apply
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryMaintenance" restore --apply
"/Applications/Arxiv Discovery.app/Contents/MacOS/ArxivDiscoveryMaintenance" migrate-trash --apply
```

The maintenance command operates on the native app library, uses the built-in VLA/World Models rules, and defaults to a read-only preview. Use Cleanup in the app for your selected custom topic rules. The Python compatibility CLI continues to use its separately configured data directory.

## Today's reading

The app opens on **Today's reading**, with five suggested papers by default. **Show** separates **Read first**, **Skim**, **Not now**, and **Needs context**. Recommendations use your selected research topics, optional focus phrases, saved papers and reading notes. They are transparent relevance heuristics, not a claim about scientific quality or citation impact. Missing title/abstract evidence goes to Needs context rather than an automatic rejection.

Open **Reading focus** beside the heading to change the daily limit or add phrases, such as `inverse dynamics`. A paper's detail and context menu offer **Read first**, **Reconsider tomorrow**, **Not now**, and **Automatic**. Manual pins are additional to the automatic daily limit. Tomorrow deferrals expire at the next local midnight; Not now stays until you change it. Reviewed papers leave the queue unless you explicitly pin them for rereading.

Priorities update locally when the date changes while the app is open, when it is activated/reopened, and after relevant library/topic changes. A closed app is not woken by a scheduled job. This feature never automatically collects papers, calls Gemini, downloads PDFs, marks papers reviewed, or moves/deletes anything. All papers remain accessible from All papers. Manual reading pins are protected from topic cleanup and retention pruning; reading decisions are included in private backups.

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
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
uv run pytest
uv run ruff check .
swift run --package-path ArxivDiscoveryApp ArxivDiscoveryCoreChecks
swift test --package-path ArxivDiscoveryApp
swift build -c release --package-path ArxivDiscoveryApp
./ArxivDiscoveryApp/build_app.sh
```

For safe actual-app workflow checks, export an offline fixture into a new directory under `~/Library/Caches/dev.gnaroshi.ArxivDiscovery/UIVerification/`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift run --package-path ArxivDiscoveryApp ArxivDiscoveryCoreChecks --export-ui-fixture "$HOME/Library/Caches/dev.gnaroshi.ArxivDiscovery/UIVerification/my-check"
```

In the installed app, **Help → Diagnostics → Open verification library…** opens it with the same product views and model, isolated preferences, and no credentials or network. It contains 7,003 active papers, two cleanup candidates, and a protected note. Fixture creation refuses an existing destination. The diagnostics menu can resize this window and switch its appearance without changing the normal library. Synthetic fixture generation is not bundled in the app. See the local interaction checklist in [`docs/discovery-performance-review.md`](docs/discovery-performance-review.md).

Product, architecture, design, distribution, compatibility, and rollback decisions are documented in [`docs/`](docs/).
