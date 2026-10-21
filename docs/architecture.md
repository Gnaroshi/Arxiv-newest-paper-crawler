# macOS application architecture

## Ownership

`ArxivDiscoveryApp` is a Swift package with five production/check targets and an application-model test target:

- `ArxivDiscoveryCore`: arXiv Atom parsing, domain models, merge rules, local JSON storage, and safe status records.
- `ArxivDiscoveryApp`: SwiftUI presentation, triage/collection/note state, calendar discovery, Keychain access, optional Gemini translation, explicit PDF download, and legacy import.
- `ArxivDiscoveryIntegration`: fixed JSON status and private backup-export executable bundled with the app.
- `ArxivDiscoveryMaintenance`: explicit local repair operations and a read-only search probe using an isolated temporary repository.
- `ArxivDiscoveryCoreChecks`: local parser, workflow, storage, performance and adversarial network fixtures.
- `ArxivDiscoveryAppTests`: headless tests of the real application model, draft ownership, revision handling, responsive pane metrics and cleanup prerequisites.

The Python package continues to own its CLI collection path and the legacy repository-local `data/` layout. It does not serve UI.

## Browser and validation ownership

`NoteDraftStore` owns transient per-paper edits separately from the browser's published state. Saves persist a copy before publishing it; failed writes leave drafts and saved reading state intact. The application termination delegate checks for unsaved work.

Topic edits build a revision-tagged index off-main. A newer revision invalidates older results. Bulk cleanup/restore prepares active and (only when needed) Trash indexes before installing a snapshot. Cleanup apply checks both topic rules and exact reviewed candidate IDs; it cannot silently apply a new preview. Individual restore shrinks the remaining undo batch.

`VerificationWindowController` hosts the same `ContentView` and `AppViewModel` on an explicitly selected fixture below the app's verification cache. The fixture marker and path are validated, preferences use a temporary suite, and its model blocks credentials, discovery, translation, download and external paper actions. The application target does not generate fixture data. Fixture generation belongs only to `ArxivDiscoveryCoreChecks`; it never writes the canonical library. A geometry diagnostic writes view frames only into that fixture folder.

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
- `DiscoverySearch` is the serial actor owning date grouping, paging, request spacing, a six-hour bounded page cache and per-page checkpoints. It never calls Gemini or downloads PDFs. The main actor receives only progress and a final snapshot; index preparation runs off-main.
- Adjacent selected UTC days share ranges of at most 31 days. Requests return up to 200 raw entries per page. Completeness uses OpenSearch totals/raw entry counts, not the number surviving topic filters. Saved pages do not consume the next run's ten-request budget.
- `BoundedHTTPClient` owns the live task, streaming byte cap, wall-clock timer and cancellation continuation. Discovery uses 12 seconds per request within a 45-second total network budget, with at least three seconds between starts. A 429 applies cooldown; 5xx/invalid feeds fail fast. Partial results are preserved and never become complete coverage.
- Discovery JSON/parsing/checkpoint work, cleanup previews and legacy import run outside the main actor. Library mutations and discovery are mutually excluded. Notes, favorites and collections are not replaced by discovery.
- Translation sends only the selected public title and abstract to the Gemini API after the user presses Translate.
- PDF download requests only the selected public PDF URL.
- Native PDF transfers stream to a temporary file, with a 45-second / 100-MB cap. File ownership is indexed and collisions never replace a reading copy. Gemini model loading and translation have 15-second and 30-second limits respectively, without automatic retry.
- Compatibility Python requests have explicit 5-second connect / 10-second read limits and no SDK retries. Gemini requests have a 30-second limit and one attempt. CLI PDF downloads stream to an exclusive temporary file and retain existing reading copies; their elapsed limit is checked between chunks, so a final read can add up to the read timeout. These CLI limits are not the native search's wall-clock deadline.
- No background server, inbound port, analytics, or remote persistence is used.

## Studio boundary

`gnaroshi.app.json` declares launch, read-only status, and explicit private backup-export capabilities. The bundled integration executable accepts only `status --json` and `backup --json`. Status reads the safe summary. Backup reads only this app's owned JSON records and emits a versioned snapshot; it excludes credentials, Keychain data, PDFs, and local paths.

Ordinary paper metadata is retained for a configurable 30–365 day window (60 days by default), with a seven-day recent-fetch floor. Saved papers, collection members, notes, and translations are never pruned. Discovery history retains 400 UTC days and translation usage retains 365 days.

Studio may discover and launch the app and read its bounded status. Candidate handoff is intentionally deferred until a reviewed, versioned export contract exists.
