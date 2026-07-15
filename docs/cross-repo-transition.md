# Native macOS transition record

## Baseline and preservation matrix

| Repository | Baseline | Preserved behavior | Contract change | Migration | Validation | Rollback |
| --- | --- | --- | --- | --- | --- | --- |
| `Gnaroshi/Arxiv-newest-paper-crawler` | `main` provider release `v0.2.0` plus the native transition branch | bounded arXiv collection, schema-v1 candidate export, optional Korean abstract translation, JSON arrays, no default PDF download | primary UI changes from Flask to signed SwiftUI app; Studio invocation narrows to the bundled read-only status helper | explicit legacy JSON import; either `serve` spelling opens the installed app | Python provider/compatibility tests and lint, Swift checks/build, signed installed bundle | reinstall the previous app bundle and continue using the Python `process` or safe provider commands with preserved JSON |
| `Gnaroshi/gnaroshi.github.io` | `main` at `146fcf106160e109f7dcd53dd280ad5de0304b14` | public route shape, bilingual project model, evidence approval boundary | project facts and copy describe macOS/SwiftUI only after source delivery | production screenshot remains gated until owner approval | project readiness/copy, Astro checks/build, links, smoke/e2e/a11y | revert the website-only commit; app and local data remain unchanged |

## Guidance applied

- Application: standalone native vertical slice, local-first data, explicit permission-sensitive actions, empty/loading/error states.
- UI/UX: one visible workflow, current state and next action, shared spacing, minimum-window verification.
- Integration: independent application, versioned manifest, fixed typed status command, read-only first, degraded missing-data response.
- Distribution: stable bundle ID/path, Git provenance, Developer ID local signing, no forced quit, Spotlight verification.
- Identity: approved Arxiv Discovery raster master, SF Symbols for functional icons, sky role accent separate from semantic state.

## Intentional deviations

- The existing schema-v1 public-metadata export remains available to scripts, but candidate handoff is not wired into Studio or PaperFlow in the first native slice.
- Notarization is not claimed for local delivery. Public release packaging remains blocked until an explicit tagged release is requested.

## Compatibility and order

The application repository is committed and delivered first. The website then records that exact source commit. The old Flask code is removed, while the `serve` CLI spelling remains as a macOS launch compatibility alias for one transition window.
