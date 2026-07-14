# Packaging and runtime-data migration

## Repository hygiene

The repository ignores Python caches, `.DS_Store`, test/lint caches, generated paper indexes, favorites, PDF downloads, temporary JSON files, and backups. The cleanup is forward-only; Git history is not rewritten.

No generated or local-only file is tracked at this baseline. If an older clone still has one in its index, stop tracking it without deleting the working copy:

```bash
git rm -r --cached --ignore-unmatch __pycache__ .pytest_cache .ruff_cache
git rm --cached --ignore-unmatch .DS_Store papers.json favorites.json
git rm -r --cached --ignore-unmatch pdfs data/pdfs
```

Do not run `rm`, `git clean`, or history-rewrite commands against local PDFs. After updating, verify with `git status` that each PDF is ignored and still present locally.

## Command coexistence

The installable package adds `arxiv-discovery`. `main.py` remains a compatibility wrapper for `process`, `serve`, and `all`.

| Surface | Runtime data | Download default | Translation default | Web default |
| --- | --- | --- | --- | --- |
| `arxiv-discovery` | `data/` | `none` | never during discover | `127.0.0.1`, debug off |
| `python main.py` | repository root | `all` for process/all | historical optional Gemini step | `0.0.0.0`, debug on |

This split prevents a package update from silently moving or deleting existing files. To use old records with the new export command, copy them manually after closing the Flask app, retain the originals, and run `arxiv-discovery doctor --json` before export. No automatic migration or backfill runs.

## Recovery

New JSON writes create a same-directory temporary file, flush it, and replace the destination atomically. When a previous destination exists it is copied to `<name>.bak` first. Corrupt JSON blocks export and appears as `local-data-corrupt`; it is not presented as an empty candidate set.

Restore by closing the app, preserving the corrupt file for inspection, copying the `.bak` content back to the original filename, and rerunning doctor. Favorites and PDFs are independent and must not be deleted during index recovery.
