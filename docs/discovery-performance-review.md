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

## Actual-app workflow review

Continued on 2026-10-21 using the Developer ID-signed `/Applications/Arxiv Discovery.app`,
not a mock screen. The real library was backed up before installation. Browsing
was checked there without marking unread papers or modifying reading work.
Recoverable write tests used the same views/model in the explicitly marked offline
verification window: 7,003 active records and 6,534 existing Trash records. Fixture
generation is a CoreChecks tool, not an application dependency.

| Pass | Actual interaction and result | Fix or safety check |
|---|---|---|
| 1 | Switch VLA/World Models after scrolling; select a detail | Scope changes now reset the list to its top; repeated viewed selection skips writes; rows avoid repeated index/file work |
| 2 | Edit a note, switch topics, scroll, return, save | Draft survives; save feedback stays beside the editor; typing does not invalidate the browser |
| 3 | Resize to 900-point width; read a long title and scroll to the note | Persisted split widths are clamped, metadata reflows and detail scroll remains independent |
| 4 | Open Cleanup at minimum size | Initially reproduced hidden header/footer even after an outer viewport fix. A pane-local geometry bound, scrolling body and ordinary pinned footer fixed the observed overflow; rechecked both empty and candidate states |
| 5 | Cancel cleanup, then move two fixture papers; restore one in Trash, undo the remaining one | Active/Trash counts 7003/6534 → 7001/6536 → 7002/6535 → 7003/6534. Protected note retained. Older Trash records not restored |
| 6 | Deselect every topic; rapidly reselect; toggle sidebar and appearance; close with an unsaved note | Empty topic selection blocks apply. Latest preview wins. Light/dark and 900/1180-point widths fit. Close warning cancels without losing the draft; Revert returns to saved text |
| 7 | Clear search, scroll VLA twelve pages, switch World Models | Search clear restores the full scope; World Models starts with scrollbar at zero instead of inheriting the VLA offset |

Local regression coverage includes eleven application-model tests in addition to
the existing CoreChecks groups and 38 Python tests. The 7,000-record model test
checks 24 topic switches; worst pairs were about 34–38 ms in observed debug runs.
This measures filtering/model work, **not rendering FPS or a universal UI latency
guarantee**. Actual scrolling was checked through the installed UI. A process
sample after cleanup/restore showed the main thread idle in the event loop, not
blocked by background work. No Gemini requests or PDF downloads were made during
this interaction review, and permanent metadata deletion was not exercised.

GitHub Actions was not run or queried. The workflow remains manual-only; validation,
packaging, signature verification and installation were local.

Application tests use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
The standalone Command Line Tools attempt failed because its SDK lacked the
SwiftUI macro plugin; the full-Xcode rerun passed all eleven tests.
