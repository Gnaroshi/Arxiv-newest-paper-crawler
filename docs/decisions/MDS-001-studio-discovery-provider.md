# MDS-001: Studio discovery provider

- Status: superseded for presentation and Studio invocation
- Date: 2026-07-12
- Crawler baseline: `f633ce2a3ad3ea9818eed10af1cb2fe09eeca8cf`
- Provider ID: `arxiv-crawler`
- Manifest/integration contract: 1

This record describes the `v0.2.0` provider baseline. The schema-v1 candidate
contract remains available as a compatibility CLI, but the Flask presentation
and variable Studio command surface were superseded by the native application
and fixed bundled `status --json` helper documented in
[`../cross-repo-transition.md`](../cross-repo-transition.md).

## Product boundary

The crawler remains the independently runnable owner of arXiv discovery, optional translation, optional PDF downloads, favorites, cached candidates, and the Flask browser. Studio coordinates discovery, filtering, status, launch, and preview handoff. PaperFlow owns Zotero/import planning. Paper Lab owns private authoring and queue records.

No repository imports crawler source or reads its internal JSON directly.

## Preserved functionality

- `python main.py process`, `serve`, `all`, and default `all` dispatch.
- Legacy root `papers.json`, `favorites.json`, `pdfs/`, optional `config.py`, environment configuration, and same-day modification-time skip.
- Legacy all-result PDF download and translation attempt, now announced before execution.
- Saved/all Flask routes, favorite toggle, English abstract fallback, and category display.
- User PDFs are never removed or renamed by packaging, hygiene, export, or rollback.

## MDS guidance applied

- Installable typed package, fixed CLI identity, provider-owned manifest, and schema-v1 JSON envelope.
- New discovery defaults to no download and no translation.
- Timezone, cutoff time, categories, days, and maximum results are typed per-run inputs; the provider contract has no personal schedule.
- Stable version-independent candidate IDs, observed arXiv IDs, provenance, duplicate hints, explicit translation state, and null unknown update times.
- `none`, `selected`, and `all` download modes with explicit selection and path omission.
- Loopback/debug-off defaults for the new local web command.
- Atomic JSON replacement, backup, corruption blocker, and independent recovery.
- Missing translation credentials degrade translation only and never block English discovery.

## Intentional deviations

- The Flask UI is preserved rather than redesigned before provider tests. It remains a human browser, not an integration endpoint.
- Legacy web defaults remain all-interface/debug-on because changing them would break a currently used workflow; the README marks the boundary and the new command is safe by default.
- No background service, deep link, local HTTP contract, PaperFlow mutation, Paper Lab mutation, automatic import, or automatic translation is added.
- The old root runtime layout and new `data/` layout coexist; files are not moved automatically.

## Compatibility and migration

- Provider version `0.2.0` supports manifest schema 1, integration contract 1, health/recent activity contract 1, and Studio `>=0.1.0 <1.0.0`.
- Producer-first is preferred. New Studio with an old crawler shows setup/unavailable. New crawler without Studio remains fully usable.
- Studio invokes only `arxiv-discovery discover --json --download=none`, fixed doctor/export operations, local candidate filtering, preview handoffs, and validated arXiv URLs.
- Candidate fields are additive within contract 1. Unknown contract majors fail closed.
- Handoff is preview-only and idempotency keys use base arXiv ID.

## Validation

- Baseline fixtures cover commands, effects, runtime files, routes, schedule assumption, and ignored paths.
- Package tests cover legacy dispatch, source/wheel entrypoints, templates, runtime isolation, configurable windows, no-download collection, atomic backup, corruption, and Flask routes.
- Provider tests cover manifest, every candidate field, stable IDs across versions, stdout/stderr separation, no-write discovery, configurable inputs, export filtering, health/privacy, and all download modes.
- Repository hygiene is verified with `git ls-files` and ignored-path checks.
- Studio validates the real manifest and uses fake provider fixtures for discovery, timeout, malformed JSON, candidate privacy, filtering, and preview-only destinations.

## Rollback

1. Disable or revert the Studio arXiv adapter.
2. Revert this repository's documentation, download-mode, provider, packaging, and baseline commits in reverse order.
3. Reinstall the previous dependencies if needed.
4. Do not delete or move root/data papers, favorites, PDFs, backups, or local `config.py`.

Related commit and PR URLs are recorded in the linked pull requests after publication.
