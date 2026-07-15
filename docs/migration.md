# Runtime-data migration

## Repository hygiene

Python caches, generated paper indexes, favorites, PDFs, temporary JSON files, backups, native build products, and local showcase captures are ignored. The cleanup is forward-only; Git history is not rewritten and local PDFs must never be removed as part of migration.

## Data boundaries

| Surface | Runtime data | Download default | Translation default | Presentation |
| --- | --- | --- | --- | --- |
| Native app | Application Support | explicit per-paper action | explicit per-paper action | SwiftUI |
| `arxiv-discovery` | `data/` | `none` | never during discover | structured CLI output |
| `arxiv-paper-crawler` / `main.py` | `data/` | disabled unless requested | optional during process | compatibility CLI |

The native app never reads repository-local data implicitly. Use its Import command to select a previous `papers.json`; a sibling `favorites.json` is merged when present. The source files are preserved, records merge by stable arXiv ID, and an existing Korean abstract is not replaced by an empty value.

The safe provider contract remains useful for scripts and candidate export, but Studio invokes only the fixed read-only helper inside the installed app bundle. The old `serve` spelling opens the native app and never binds a local port.

## Recovery

CLI JSON writes replace the destination atomically and keep a same-directory `.bak` copy when a previous destination exists. Corrupt JSON blocks export rather than appearing as an empty result. Preserve the corrupt file, restore the backup, and rerun `arxiv-discovery doctor --json`.

Native rollback is app-bundle based. Close Arxiv Discovery, preserve Application Support, reinstall the previous verified bundle, and reopen it. Do not delete native or CLI data during a code rollback.
