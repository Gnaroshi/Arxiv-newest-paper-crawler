# Discovery performance review

Date: 2026-10-21. Checks were local; GitHub Actions was neither queried nor run.

## Reviewed surfaces

Native date/topic query construction, HTTP transport, XML parser, paging, coverage,
cache, main-actor state ownership, list indexing/counts, partial storage, cancellation,
cleanup/import, PDF download and Gemini boundaries; Python collection, translation,
storage and provider compatibility; local build/install and workflow triggers.

## Confirmed defects and fixes

| Risk | Previous behavior | Correction |
|---|---|---|
| Multi-date latency | Serial request per day, repeated 30-second waits | Contiguous ranges, 12-second request and 45-second search network budgets |
| No reuse | Re-requested already-searched dates | Exact-scope six-hour coverage/page cache and explicit forced refresh |
| Truncation | First 500 entries only, incomplete dates could look complete | Raw-count/OpenSearch paging; incomplete coverage remains retryable |
| Lost progress | Save only after all days finish | Atomic checkpoint after every page; resume cached pages |
| Repeated outage | Error details discarded; next day repeated failure | Typed 429/5xx/timeout/feed/storage states; cooldown/circuit breaker |
| Invalid feed | HTML/error entry could become empty success | Reject non-feed roots, invalid entries, DTDs and missing valid result metadata |
| UI stalls | Discovery merge/JSON and bulk preview/import on main actor | Discovery actor and background bulk operations; visible elapsed/progress/cancel |
| Hidden actions | Restored oversized window could push actions below the display | Clamp restored non-fullscreen frames to visible area; safe-area-pinned action footer |
| Ambiguous acronym | Astronomy VLA pages fetched then discarded | Robotics context applied both remotely and locally |
| Data races | Overlapping library/search operations | One discovery owner; mutation prerequisites enforced in model and UI |
| PDF data loss | Same-title destination overwritten | Ownership index; no replacement of reading copies; bounded streaming |
| Legacy hazards | SDK timeout/retry defaults; corrupt JSON treated as empty | Explicit timeouts/no retries, strict corrupt-data error, atomic saves |

## Reproduction and verification

- `uv run pytest`: Python compatibility and network-safety fixtures; live HTTP is blocked in tests.
- `uv run ruff check .` and `git diff --check`.
- `swift run --package-path ArxivDiscoveryApp ArxivDiscoveryCoreChecks`: existing eleven core groups plus adversarial discovery fixtures.
- Fixtures cover silent and trickling servers, cancellation, overlapping runs, bounded response size, 16 adjacent days, nonadjacent days, cached holes, cache bypass, zero-result coverage, 429/cooldown, 503, paged partial save/resume, page-budget continuation, disk failure, invalid XML/HTML, old arXiv IDs, main-actor heartbeat, note preservation and PDF ownership/collisions.
- A temporary-repository live probe for VLA/World Models, 2026-10-01 through 2026-10-16, completed three serial requests and saved 562 matching papers in 8.08 seconds during testing. This was a point-in-time observation, not a server-performance guarantee. The probe did not write the user's library.
- Local probe: `ArxivDiscoveryMaintenance probe-search --from YYYY-MM-DD --to YYYY-MM-DD`. It uses a temporary repository, a 15-second network budget and at most five pages; it never downloads PDFs or calls Gemini.

## Limits

arXiv availability is external. Sparse dates, slow responses and large result sets can
exceed one search budget; partial results and unfinished dates are explicit. Local
disk writes and final list installation can add a short tail beyond the network
budget. A stalled filesystem cannot be solved by an HTTP timeout. Native startup
still reads owned JSON synchronously; the expensive search/import/preview paths do
not. Python compatibility commands are not claimed to have the native batch deadline.
