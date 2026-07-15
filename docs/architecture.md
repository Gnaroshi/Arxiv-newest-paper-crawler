# macOS application architecture

## Ownership

`ArxivDiscoveryApp` is a Swift package with three targets:

- `ArxivDiscoveryCore`: arXiv Atom parsing, domain models, merge rules, local JSON storage, and safe status records.
- `ArxivDiscoveryApp`: SwiftUI presentation, Keychain access, optional Gemini translation, explicit PDF download, and legacy import.
- `ArxivDiscoveryIntegration`: a fixed read-only JSON status executable bundled with the app.

The Python package continues to own its CLI collection path and the legacy repository-local `data/` layout. It does not serve UI.

## Native data

The native source of truth is:

```text
~/Library/Application Support/dev.gnaroshi.ArxivDiscovery/
├── papers.json
├── favorites.json
├── status.json
└── PDFs/
```

`papers.json` and `favorites.json` retain the legacy array shapes. Writes are atomic. The app merges by stable arXiv identifier and does not synthesize missing translation, download, or review state.

## Network boundaries

- Discovery performs a bounded read from the public arXiv Atom API.
- Translation sends only the selected public title and abstract to the Gemini API after the user presses Translate.
- PDF download requests only the selected public PDF URL.
- No background server, inbound port, analytics, or remote persistence is used.

## Studio boundary

`gnaroshi.app.json` declares launch and read-only status capabilities. The bundled integration executable accepts only the fixed `status --json` command, reads the app-owned safe status record, emits one versioned JSON response, and never reads paper abstracts, credentials, PDFs, or another application's storage.

Studio may discover and launch the app and read its bounded status. Candidate handoff is intentionally deferred until a reviewed, versioned export contract exists.
