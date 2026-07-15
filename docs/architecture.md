# macOS application architecture

## Ownership

`ArxivDiscoveryApp` is a Swift package with three targets:

- `ArxivDiscoveryCore`: arXiv Atom parsing, domain models, merge rules, local JSON storage, and safe status records.
- `ArxivDiscoveryApp`: SwiftUI presentation, triage/collection/note state, calendar discovery, Keychain access, optional Gemini translation, explicit PDF download, and legacy import.
- `ArxivDiscoveryIntegration`: fixed JSON status and private backup-export executable bundled with the app.

The Python package continues to own its CLI collection path and the legacy repository-local `data/` layout. It does not serve UI.

## Native data

The native source of truth is:

```text
~/Library/Application Support/dev.gnaroshi.ArxivDiscovery/
├── papers.json
├── favorites.json
├── library.json
├── discovery-history.json
├── translation-usage.json
├── status.json
└── PDFs/
```

`papers.json` and `favorites.json` retain the legacy array shapes. Versioned state files own review/collection/note, discovery-day, and local translation-usage records. Writes are atomic. The app merges by stable arXiv identifier and does not synthesize missing translation or download state.

## Network boundaries

- Discovery performs a bounded read from the public arXiv Atom API.
- Translation sends only the selected public title and abstract to the Gemini API after the user presses Translate.
- PDF download requests only the selected public PDF URL.
- No background server, inbound port, analytics, or remote persistence is used.

## Studio boundary

`gnaroshi.app.json` declares launch, read-only status, and explicit private backup-export capabilities. The bundled integration executable accepts only `status --json` and `backup --json`. Status reads the safe summary. Backup reads only this app's owned JSON records and emits a versioned snapshot; it excludes credentials, Keychain data, PDFs, and local paths.

Ordinary paper metadata is retained for a configurable 30–365 day window (60 days by default), with a seven-day recent-fetch floor. Saved papers, collection members, notes, and translations are never pruned. Discovery history retains 400 UTC days and translation usage retains 365 days.

Studio may discover and launch the app and read its bounded status. Candidate handoff is intentionally deferred until a reviewed, versioned export contract exists.
