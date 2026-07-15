# Arxiv Discovery product scope

## Promise

Arxiv Discovery is a local macOS application for finding a bounded set of recent arXiv papers, narrowing the list, inspecting one abstract, and explicitly choosing whether to save, translate, open, or download that paper.

The first useful workflow is:

1. Choose a recent time window.
2. Find papers in the configured AI categories.
3. Search or filter the returned metadata.
4. Inspect one candidate and save it when useful.
5. Translate or download only after an explicit action.

## Non-goals

- It is not a paper-reading or annotation system.
- It does not publish content or write into PaperFlow, Studio, or a research repository.
- It does not download every discovered PDF.
- It does not require a local HTTP server, browser tab, or source checkout.
- It does not infer reading completion, relevance scores, or research progress.

## Required states

- Empty: explain what discovery does and offer `Find recent papers`.
- Loading: preserve the current list and show that metadata is being requested.
- Success: show the observed count and refresh time.
- Error: keep existing local data, show a bounded error, and offer retry.
- Translation unavailable: explain that a Gemini key is optional and point to Settings.
- Offline: retain saved metadata and local PDFs without presenting stale data as a fresh result.

## Migration

The previous Python JSON arrays remain importable. Import merges by stable arXiv ID, preserves existing Korean abstracts, and copies favorites when a sibling `favorites.json` is present. The selected legacy files are never modified.
