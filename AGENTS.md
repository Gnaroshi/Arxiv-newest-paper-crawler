# Arxiv Discovery working agreements

## Product boundary

- `Arxiv Discovery.app` is the primary user interface. Do not add a local web server or browser UI.
- The Python package remains a compatible collection and translation CLI, not a second presentation layer.
- The app must launch and complete its discovery workflow without Gnaroshi Studio or a source checkout.
- PDF download and Gemini translation are explicit per-paper actions; neither runs during discovery by default.

## Data and privacy

- Native application data lives under the stable bundle-owned Application Support directory for `dev.gnaroshi.ArxivDiscovery`.
- Preserve compatibility with the existing `papers.json` and `favorites.json` arrays through explicit import. Do not mutate a selected legacy checkout.
- Store Gemini credentials only in Keychain. Never write keys into settings files, manifests, logs, screenshots, or repository content.
- Studio integration is read-only first and uses the bundled fixed integration executable plus `gnaroshi.app.json`.

## Interface and identity

- Follow `gnaroshi_mds` application, UI/UX, distribution, and app-icon guidance.
- Keep purpose, current state, prerequisite, and next action visible. Include honest empty, loading, error, and unavailable states.
- Use SwiftUI and SF Symbols for functional controls. Use the approved raster Arxiv Discovery identity only for the application icon.
- Keep the sky-blue role accent separate from semantic success, warning, and failure colors.

## Verification

```bash
uv run pytest
uv run ruff check .
swift run --package-path ArxivDiscoveryApp ArxivDiscoveryCoreChecks
./ArxivDiscoveryApp/build_app.sh
./ArxivDiscoveryApp/install_app.sh
```

Run the installed app from `~/Applications/Arxiv Discovery.app` for user-facing verification. Do not report Spotlight delivery unless the installed bundle, signing identity, provenance, and index are verified.
