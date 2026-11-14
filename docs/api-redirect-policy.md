# API redirect policy

`NowaveApiClient` does not follow HTTP redirects, for public reads as well as
private reads, credential exchanges and writes. Every `http.Request` is sent
with `followRedirects = false`. Legacy optional `followRedirects: false`
arguments remain accepted, but an explicit `true` is rejected before any
request or authentication refresh. The default cannot be relaxed per call.

The current no-wave API responds directly to `/api/v1/auth/*` JSON exchanges
and `/api/v1/me/media` uploads. Deployments must configure the final API origin
and path prefix in `API_BASE_URL`, including the correct scheme and port;
proxies must not rely on redirects to canonicalize API requests. A redirect
that used to work may now fail, deliberately, even on a public endpoint. No
attempt is made to parse, validate, or contact the `Location` header.

On native IO transports, a response with any status in 300–399 is rejected at
headers with `NowaveApiException(code: HTTP_REDIRECT, statusCode: ...)`. The
response stream is cancelled without waiting for an arbitrary body. Neither the
redirect body, destination, query parameters, bearer token, credentials nor
upload bytes are placed in the exception or diagnostics. A response still
counts as backend reachability evidence, not authorization or API success.
A client that throws before exposing an HTTP status cannot supply the status:
for example, browser `fetch` may surface a redirect as `ClientException` when
redirect following is disabled. Browser behavior is not validated by the native
loopback tests and must not be described as an `HTTP_REDIRECT` guarantee.

A redirect does not start a 401 refresh and is never replayed by this policy.
If a real 401 caused the existing single permitted refresh/retry, the retry is
also forbidden to follow a redirect. Existing identity fences still win when
the account changes while a response is in flight. Login/registration cannot
adopt a fake redirect body, and a redirected refresh retires the token as an
unknown outcome rather than resending it. Password recovery also reports an
unknown outcome: a server or proxy may have committed the original write
before returning 3xx. Consumers must not infer that a redirected write failed,
nor automatically retry a non-idempotent operation.

Tests include simulated redirects across methods and authentication paths,
stalled response bodies, token rotation and identity changes, plus real local
IO servers for both same-origin and cross-origin 302/307 destinations. These
are not production-backend, browser, mobile-device, proxy or TLS acceptance
tests. No storage migration or new dependency is introduced.
