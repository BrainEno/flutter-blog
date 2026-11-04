# no-wave transport layer

`NowaveApiClient` used to own everything one HTTP call does: compose the URL,
attach the token, decide what a 401 means, and map the response body. Those are
three independent rules with failure modes of their own, so they are now small
units in `lib/core/nowave/transport/` with their own tests. The client keeps
only the shell: `_request` (send, timeout, `sendForSession` fence) and `_send`.

## Pieces

| Unit | File | Guarantee |
| --- | --- | --- |
| `ApiBaseUrl` | `transport/api_base_url.dart` | One place that composes paths; rejects a base URL that already ends with `/api/v1` |
| `decodeEnvelope` / `EnvelopeOutcome` | `transport/api_envelope.dart` | Response body to `EnvelopeData` or `EnvelopeFailure`; every `>= 400` fails typed |
| `requireJsonMap` | `transport/api_envelope.dart` | Object-shaped payloads (upload) fail with a `FormatException` instead of a cast error |
| `decideUnauthorizedReplay` | `transport/unauthorized_replay.dart` | The single allowed reaction to a 401 |
| `NowaveApiException` | `transport/api_error.dart` | The stable `{code, statusCode, message, retryAfterSeconds}` error type |
| `NowaveMediaAsset` | `transport/media_asset.dart` | Upload response mapping, with WebP defaults |

`nowave_api_client.dart` re-exports `NowaveApiException` and
`NowaveMediaAsset`, so existing imports keep working; new code may import the
unit it needs.

## URL composition

`ApiBaseUrl.parse` keeps the configured origin (and any path prefix such as
`/backend`). `resolve` composes `pathPrefix + '/api/v1' + path` and is the only
place the versioned segment is added, so the client cannot spell it twice. Two
rules that used to be implicit:

- A configured query or fragment is dropped (string surgery plus reparse, so an
  explicit port survives verbatim); per-call queries are the only queries.
- A base URL that already ends with `/api/v1` throws `ArgumentError` at
  construction. Accepting it would send every request to `/api/v1/api/v1/...`,
  a total outage that no call-site test would attribute correctly.

`mediaUri` always builds `GET /api/v1/media/:id` rather than trusting the
`src` field the upload endpoint returns, which omits `/v1`.

## Response decoding

`decodeEnvelope` is the backend contract in one function, in this order:

1. Not valid UTF-8 to `EnvelopeFault.nonUtf8`.
2. Not valid JSON to `EnvelopeFault.nonJson`.
3. `{error: {code, message}}` to `NowaveApiException` (plus the parsed
   `Retry-After` header).
4. Any other `>= 400` body to `HTTP_<status>`, including a well-formed
   `{data: ...}` body. Callers must never receive a null payload for a server
   failure.
5. Otherwise the unwrapped `data` (or the whole body when it is not an object,
   and null for an empty body).

The client logs the fixed diagnostic token from `EnvelopeFault` before
rethrowing, which is what `DiagnosticsBuffer` records (issue #49).

## 401 replay

`decideUnauthorizedReplay` returns exactly one of `notApplicable`,
`reuseCurrentToken`, `refreshFirst`, `surfaceOriginal`:

- replay disabled or no token sent -> nothing happens;
- the token changed while the response was in flight and the authenticator is
  session-bound -> reuse it (another request already rotated the family
  successfully, #104);
- the token changed without that fence -> surface the 401, because the new
  token may belong to another account;
- the same token is still current -> `refresh()` once, then retry once;
- the session ended -> surface the original 401, never refresh.

Refreshing twice, or replaying a rotated refresh token, revokes the whole
family: see [session lifecycle](session-lifecycle.md) for that side.

## Rules when changing this code

- Add response-shape cases to `decodeEnvelope`, not to `_decode`.
- Add 401 cases to `decideUnauthorizedReplay` and its test, not to `_request`.
- Never return `data` on a `>= 400` response, even if the body looks valid.
- Keep URL composition in `ApiBaseUrl`; do not rebuild `_baseUrl.replace(...)`
  inside the client.

## Tests

`test/unit/nowave/` - `api_base_url_test` (prefix, port, prefix stripping,
rejection), `api_envelope_test` (payload, error envelope, non-JSON, non-UTF-8,
`>= 400` shapes), `unauthorized_replay_test` (the decision table),
`nowave_api_client_test` (the end-to-end call behaviour).

## Still open in #107

The client is ~555 lines and still holds `_request`/`_send`. Page-level splits
(`blog_detail_page.dart`, `edit_blog_page.dart`, `no_wave.dart`) and the domain
attachment interface that exposes `dart:io File` are separate steps.
