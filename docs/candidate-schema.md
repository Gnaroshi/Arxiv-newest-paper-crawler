# Candidate schema

## Envelope

Every machine-readable command writes one JSON object to stdout:

```json
{
  "schemaVersion": 1,
  "provider": {
    "id": "arxiv-crawler",
    "version": "0.4.0",
    "contractVersion": 1
  },
  "capability": "discover-papers",
  "generatedAt": "2026-07-12T00:00:00+00:00",
  "status": "ok",
  "data": {},
  "warnings": [],
  "errors": []
}
```

Status is one of `ok`, `partial`, `blocked`, `unavailable`, `stale`, `incompatible`, or `failed`. Errors have stable codes and redacted messages. Human diagnostics use stderr.

## Candidate

```json
{
  "candidateId": "arxiv:2401.00001",
  "arxivId": "2401.00001v2",
  "title": "Example paper",
  "authors": ["Ada Example"],
  "abstract": "Original arXiv abstract",
  "categories": ["cs.AI"],
  "submittedAt": "2026-07-11T01:00:00+00:00",
  "updatedAt": "2026-07-11T02:00:00+00:00",
  "paperUrl": "https://arxiv.org/abs/2401.00001v2",
  "pdfUrl": "https://arxiv.org/pdf/2401.00001v2",
  "translationStatus": "not-requested",
  "duplicateHint": {
    "kind": "arxiv-id",
    "value": "2401.00001"
  },
  "sourceProvider": "arxiv-crawler"
}
```

`candidateId` is version-independent; `arxivId` retains the observed version. `updatedAt` is `null` when arXiv or a migrated legacy record did not provide it. Translation status is `not-requested`, `available`, `unavailable`, or `failed` and is never inferred as successful.

`downloadedLocalPath` is omitted unless the user explicitly selected `download=selected` or `download=all` and that candidate downloaded successfully. It is a provider-relative reference, not an instruction for Studio to read a private directory.

## Handoff

Studio may filter candidates and preview one of two destinations:

- PaperFlow receives the candidate object as metadata input and remains responsible for duplicate checks, PDF selection, Zotero planning, and confirmation.
- Paper Lab receives the candidate object as a private queue preview and remains responsible for idempotency by base arXiv ID and explicit save.

Neither preview translates, downloads, favorites, publishes, or writes the destination. A future destination write contract must preserve the candidate ID, arXiv ID, provider provenance, and observed timestamps.
