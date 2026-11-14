# Backend connectivity evidence

The repository preflight is a hint about the configured API, not a network
permission check, authentication result, or guarantee that a later request
will succeed. One app-scoped `ApiConnectionChecker` is shared by repositories.
A burst of checks awaits one credential-free `GET /api/v1/health`, including
for concurrent detail, related-content and comment loads. The probe does not
follow redirects and treats any completed HTTP status as reachability: a 401,
403, 500, or redirect must not disguise an application error as offline.

Only a fully received HTTP response creates a two-second positive lease. The
primary and session HTTP transports supply evidence for their configured
origin and API path prefix, and reuse one app-lifetime business HTTP client.
The probe has its own reusable client so timing out or disposing it cannot
close the business pool. A failed or timed-out probe closes its client before
another one is created. No credentials, cookies, response bodies, query strings
or account identifiers are retained in the reachability state.

A definitive transport error invalidates the lease; it is not negatively
cached, so the next check can immediately detect reconnection. A probe timeout
remains inconclusive and lets the business request decide, preserving the
existing cold-server and slow-proxy behavior. A timeout is not cached as a
success. Evidence is ordered so a late probe cannot replace a more recent
business response or failure. A monotonic clock prevents a wall-clock change
from extending a lease. Backend instances are isolated, and disposed checkers
cannot be revived by a late response.

The lease intentionally permits a request to start after the network goes down.
The home feed already falls back on a transport failure for an unpinned feed;
article detail and persisted-session restoration now do the same for a definite
network error. Detail returns a storage failure if the cache cannot be read;
profile restoration remains generation-fenced and reads only the current
account's profile. Server, permission, validation and timeout errors are not
silently converted into cached success. A pinned network feed never switches
source mid-pagination. Other mutations still use their own error handling and
are never retried or replayed by the connectivity layer.

This change does not migrate storage, add dependencies, eliminate every first
probe, guarantee instantaneous offline detection for every repository, or
establish cross-device/server concurrency. Network transitions on real devices,
TLS behavior against a deployed service, and platform background behavior have
not been validated by these unit tests.
