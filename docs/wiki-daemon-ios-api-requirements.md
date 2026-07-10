# wiki-daemon iOS API Requirements

Date: 2026-06-23

## Context

WikiReader started as an Obsidian-like iOS Markdown vault reader. The product
direction is now to make it the mobile reading and query interface for an
LLM-maintained wiki vault.

`wiki-daemon` is the canonical backend for the wiki. It already owns the query
operation:

- `wiki query --vault <path> "<question>"`
- `wiki query --vault <path> "<question>" --save`

Internally, this is implemented by `wiki_daemon.ops.query`. The operation invokes
the configured agentic CLI provider (`claude`, `gemini`, or `codex`) with
read-only tools by default and returns a Markdown answer. With `--save`, it
allows writes and verifies that a `wiki/queries/*.md` page records the question
in frontmatter.

Hermes and Telegram are existing control surfaces, but they should not sit
between WikiReader and `wiki-daemon` for app queries.

Target architecture:

```text
WikiReader iOS app
  -> wiki-daemon HTTP API
      -> existing wiki_daemon.ops.query(...)
      -> configured provider CLI: claude / gemini / codex

Hermes agent
  -> wiki-daemon CLI or HTTP API
```

## Existing Query Contract

Current Python result type:

```python
@dataclass
class QueryResult:
    ok: bool
    answer: str = ""
    saved: bool = False
    reason: str = ""
    kind: str = ""
```

Current behavior:

- `save=False`
  - provider runs read-only.
  - answer is provider stdout.
  - no files are modified.
- `save=True`
  - provider may write/edit `wiki/queries/`, `wiki/index.md`, and `wiki/log.md`.
  - answer is still returned even if save verification fails.
  - save verification checks for a query page whose `query:` frontmatter matches
    the question after whitespace normalization.
- failures classify provider errors into `kind`, such as auth failures.

Important implication for the API:

- v1 should wrap this existing operation rather than invent a new query engine.
- Markdown citations currently live inside `answer` as `[[wiki-links]]`.
- Structured citation metadata can be added by the API layer, but it is an
  enhancement over the current CLI contract.

## Goals

1. Let WikiReader ask questions against the wiki vault.
2. Return the existing Markdown answer so the iOS app can render it directly.
3. Preserve the existing read-only vs save-query semantics.
4. Provide enough machine-readable metadata for the app to show status, errors,
   and saved-query results.
5. Keep `wiki-daemon` as the source of truth for query behavior, prompts,
   retrieval, and LLM invocation.
6. Make the API usable by Hermes and future clients without going through
   Telegram.

## Non-Goals For Initial Version

- Public multi-user SaaS API.
- Complex permissions beyond a private-user authentication token.
- Replacing the existing CLI.
- Rewriting query prompts or maintainer behavior.
- Making WikiReader edit arbitrary wiki files through the API.
- Streaming UI polish as a hard dependency for v1.
- Requiring structured citations before the first useful iOS integration.
- Routing app queries through Telegram or Hermes.

## Deployment Assumptions

- `wiki-daemon` runs on the user's home machine.
- WikiReader connects over a private network first, preferably Tailscale,
  WireGuard, or LAN.
- HTTPS is preferred. Plain HTTP is acceptable only on trusted private network
  during early development.
- The daemon has filesystem access to the wiki vault and existing provider CLI
  authentication.
- The iOS app also has local read access to the same vault via iCloud Drive
  security-scoped bookmark, so any paths returned by the API should be
  vault-relative.

## API Versioning

All app-facing endpoints should be namespaced:

```text
/api/v1/...
```

Responses should include:

```json
{
  "schemaVersion": 1
}
```

## Authentication

Initial version should support a single bearer token:

```http
Authorization: Bearer <token>
```

Requirements:

- Token is configured on the daemon.
- Token can be rotated without changing app code.
- Unauthorized requests return `401`.
- Forbidden or disabled operations return `403`.
- Never log the token.

Future options:

- mTLS over private network.
- Device-specific tokens.
- OAuth is not needed for the personal v1.

## Endpoint: Health

### `GET /api/v1/health`

Purpose: let the app verify connection and show a useful setup state.

Response:

```json
{
  "schemaVersion": 1,
  "status": "ok",
  "daemonVersion": "0.1.0",
  "vaultName": "Personal Wiki",
  "vaultPath": "/Users/name/Wiki",
  "queryAvailable": true,
  "provider": "claude"
}
```

Notes:

- `vaultPath` may be omitted or redacted if exposing it is undesirable.
- The app needs `queryAvailable` to distinguish network success from backend
  query/provider misconfiguration.
- `provider` should reflect the resolved `Config.provider`.

## Endpoint: Query

### `POST /api/v1/query`

Purpose: ask a natural-language question against the wiki and return the
Markdown answer produced by the existing query operation.

This endpoint should call:

```python
wiki_daemon.ops.query(cfg, question, save=save)
```

Request:

```json
{
  "question": "What did I decide about the graph view?",
  "save": false,
  "extractCitations": true
}
```

Fields:

- `question`: required non-empty user question.
- `save`: optional, default `false`. Maps directly to existing `save` argument.
- `extractCitations`: optional, default `true`. If true, the API may parse
  `[[wiki-links]]` from the Markdown answer and return best-effort citation
  metadata.

Successful response:

```json
{
  "schemaVersion": 1,
  "queryId": "qry_20260623_153012_abcd",
  "status": "done",
  "ok": true,
  "answerMarkdown": "# Short Answer\n\nThe graph view should cite [[Graph View Notes]].",
  "saved": false,
  "saveError": null,
  "citations": [
    {
      "title": "Graph View Notes",
      "wikiLink": "Graph View Notes",
      "path": "wiki/concepts/graph-view-notes.md",
      "exists": true
    }
  ],
  "provider": "claude",
  "startedAt": "2026-06-23T15:30:12Z",
  "completedAt": "2026-06-23T15:30:37Z"
}
```

Response mapping:

- `QueryResult.ok` -> `ok`
- `QueryResult.answer` -> `answerMarkdown`
- `QueryResult.saved` -> `saved`
- `QueryResult.reason` on save verification failure -> `saveError`
- `QueryResult.kind` on provider failure -> error `details.kind`

Save behavior:

- If `save=false`, API must not allow writes.
- If `save=true`, use the existing save-query behavior.
- If the provider returns an answer but save verification fails, return HTTP
  `200` with:

```json
{
  "ok": true,
  "answerMarkdown": "...",
  "saved": false,
  "saveError": "no query page records this question"
}
```

This mirrors the CLI behavior: the answer is useful even if filing it failed.

Markdown requirements:

- `answerMarkdown` should be returned exactly enough to preserve the CLI answer.
- The app will render headings, lists, tables, code fences, blockquotes, Mermaid
  fences, and `[[wiki-links]]`.
- Do not strip Markdown formatting.
- Do not include terminal progress text, stderr, or ANSI colors in
  `answerMarkdown`.

## Citation Extraction

Current CLI answers cite pages via `[[wiki-links]]` in Markdown prose. They do
not produce structured citations.

For iOS, structured citations are useful but should be best-effort v1 behavior:

1. Parse `[[Page Name]]` and `[[Page Name|Alias]]` from `answerMarkdown`.
2. Resolve each link against known wiki pages if a resolver exists.
3. Return `wikiLink`, display `title`, optional `path`, and `exists`.
4. Do not fail the query if citation extraction fails.

Example:

```json
{
  "title": "Graph View Notes",
  "wikiLink": "Graph View Notes",
  "path": "wiki/concepts/graph-view-notes.md",
  "exists": true
}
```

If page resolution is not already available, v1 can return only:

```json
{
  "wikiLink": "Graph View Notes",
  "title": "Graph View Notes",
  "path": null,
  "exists": null
}
```

WikiReader can still use local graph/page lookup to resolve links.

## Long-Running Query Support

The existing query operation shells out to an agentic CLI and may take longer
than a normal mobile request.

Recommended v1:

- Start with synchronous `POST /api/v1/query`.
- Set an explicit server-side timeout higher than typical query latency.
- Return structured timeout errors.

Add job endpoints only if real use shows timeouts or poor UX.

### Future: `POST /api/v1/query-jobs`

Response:

```json
{
  "schemaVersion": 1,
  "jobId": "job_20260623_153012_abcd",
  "status": "queued"
}
```

### Future: `GET /api/v1/query-jobs/{jobId}`

Response while running:

```json
{
  "schemaVersion": 1,
  "jobId": "job_20260623_153012_abcd",
  "status": "running",
  "progressMessage": "Querying wiki..."
}
```

Response when done should match the synchronous query response.

## Optional Endpoint: List Pages

### `GET /api/v1/pages`

Purpose: optional daemon-side page index for clients that do not have local
filesystem access. WikiReader can already browse the local vault, so this is
not required for the first iOS query feature.

Response:

```json
{
  "schemaVersion": 1,
  "pages": [
    {
      "title": "Graph View Notes",
      "path": "wiki/concepts/graph-view-notes.md",
      "modifiedAt": "2026-06-23T10:15:00Z"
    }
  ]
}
```

## Optional Endpoint: Read Page

### `GET /api/v1/pages/{path}`

Purpose: optional fallback for clients without local vault access.

Response:

```json
{
  "schemaVersion": 1,
  "title": "Graph View Notes",
  "path": "wiki/concepts/graph-view-notes.md",
  "markdown": "# Graph View Notes\n\n...",
  "modifiedAt": "2026-06-23T10:15:00Z"
}
```

Security requirement:

- Prevent path traversal. Only vault-relative Markdown files may be read.

## Error Model

All errors should use JSON:

```json
{
  "schemaVersion": 1,
  "error": {
    "code": "query_failed",
    "message": "Provider failed while generating the answer.",
    "retryable": true,
    "details": {
      "kind": "auth",
      "provider": "claude"
    }
  }
}
```

Initial error codes:

- `unauthorized`
- `forbidden`
- `bad_request`
- `vault_unavailable`
- `query_unavailable`
- `query_timeout`
- `query_failed`
- `provider_failed`
- `not_found`
- `internal_error`

Mapping from `QueryResult` failure:

- `ok=False`, `kind="auth"` -> `401` or `503`, depending on whether the API
  token is valid but provider auth is broken. Prefer `503` with
  `code="provider_failed"` for provider auth/config failures.
- `ok=False`, other `kind` -> `500` or `503`, based on whether the daemon can
  classify it as transient.
- Empty or missing question -> `400`.

HTTP status mapping:

- `400`: invalid request.
- `401`: missing/invalid API token.
- `403`: operation disabled.
- `404`: page/job not found.
- `408` or `504`: timeout.
- `500`: daemon bug or unexpected failure.
- `503`: daemon alive but query/provider subsystem unavailable.

## iOS Client Expectations

WikiReader will need:

1. Settings screen fields:
   - daemon base URL
   - bearer token
   - connection test button
2. Ask screen:
   - question input
   - save-answer toggle
   - submit/cancel
   - loading state
   - Markdown answer rendering
   - citation/wiki-link list when available
3. Citation behavior:
   - open local vault file if a citation path or wiki link resolves locally
   - show missing/not-downloaded state if unavailable
4. Query history:
   - store recent questions/results locally
   - future option to save answer into wiki if it was not saved initially

## Operational Requirements

- Daemon should log request ID, timing, status, and high-level operation.
- Do not log bearer tokens.
- Avoid logging full private questions/answers by default; make verbose logging
  opt-in.
- Limit concurrent API queries initially, e.g. one active query at a time, unless
  current provider runner behavior already supports safe concurrency.
- Return clear errors when provider CLI auth is missing or expired.
- Preserve existing daemon single-writer invariants. Read-only query must not
  write. Save-query may write only through the existing `save=True` path.

## Testing Requirements

Daemon-side tests should cover:

1. `GET /api/v1/health` returns configured daemon/vault/provider status.
2. `POST /api/v1/query` validates missing/empty question.
3. Unauthorized requests fail with `401`.
4. Query endpoint calls an injected fake query service rather than the real
   provider CLI.
5. Successful read-only query maps `QueryResult(answer=...)` to
   `answerMarkdown`.
6. `save=false` does not enable writes.
7. `save=true` maps successful save to `saved: true`.
8. `save=true` with save verification failure returns the answer plus
   `saved: false` and `saveError`.
9. Provider failure maps to structured JSON error using `QueryResult.kind`.
10. Citation extraction parses `[[Page]]` and `[[Page|Alias]]` without failing
    the query when resolution is unavailable.
11. Optional page-read endpoint rejects path traversal.

Prefer injecting a fake query backend so API tests do not call Claude, Gemini,
or Codex.

## Suggested Implementation Sequence

1. Add an internal API server module behind a config option.
2. Add bearer-token auth middleware.
3. Add `/api/v1/health`.
4. Add a small `QueryService` adapter around existing `ops.query`.
5. Add synchronous `POST /api/v1/query`.
6. Map `QueryResult` to the API response shape.
7. Add best-effort wiki-link extraction from `answerMarkdown`.
8. Add API tests with a fake query service.
9. Document private-network setup in README.
10. Add job-based query only if synchronous query proves too slow for iOS.

## Open Questions

1. Should API `save=true` be exposed in WikiReader v1, or should mobile only do
   read-only queries first?
2. Should citation resolution live in `wiki-daemon`, WikiReader, or both?
3. Is there already a canonical page resolver for `[[wiki-links]]`, or should
   the first API return unresolved link titles only?
4. Should the first API server bind only to localhost by default, requiring
   Tailscale/SSH forwarding for remote access?
5. What timeout is realistic for `ops.query` with each provider?

## Recommended v1 Scope

Build only:

- `GET /api/v1/health`
- `POST /api/v1/query`
- bearer-token auth
- response mapping from existing `QueryResult`
- best-effort `[[wiki-link]]` extraction
- tests using a fake query service

Defer:

- streaming
- jobs
- page editing
- remote ingest
- multi-user auth
- public internet deployment
- mandatory structured citations from the LLM prompt

