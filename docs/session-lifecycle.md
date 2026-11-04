# Session lifecycle (no-wave)

`NowaveSessionManager` owns the one long-lived credential the app holds. The
refresh token rotates on every use and the backend revokes the whole session
family when a rotated token is replayed, so the timing rules matter more than
the storage format. Those rules are separate, unit-tested units; this page maps
where each one lives and what it guarantees.

## Pieces

| Unit | File | Guarantee |
| --- | --- | --- |
| `NowaveSessionManager` | `lib/core/nowave/nowave_session.dart` | Binds the units below to the in-memory session, `POST /auth/refresh` and the sign-out result |
| `SessionGeneration` | `session/session_generation.dart` | Account fence: every multi-step operation captures `value` before its first `await` and checks `isCurrent` afterwards |
| `SerialQueue` | `session/serial_queue.dart` | Persistence lands in call order; a failed operation does not block the next |
| `KeyedSingleFlight` | `session/single_flight.dart` | One rotation per session generation; a newer session never joins an older flight |
| `decideSessionExpiry` | `session/session_expiry.dart` | Pure mapping from (access expiry, refresh expiry, spent) to one action |
| `NowaveSessionData` / `NowaveTokenPair` / codec | `session/session_data.dart` | Serialization; corrupt payloads read as "no session" |
| `NowaveSessionStore` / `SessionClearResult` | `session/session_store.dart` | Durable storage contract and how much of a sign-out survived |
| `NowaveSessionIdentity` | `session/session_identity.dart` | The synchronous identity signal used by sensitive UI |

`lib/core/nowave/nowave_session.dart` re-exports the value types, so existing
imports keep working; new code may import the unit it needs directly.

## Lifecycle

1. **Restore** (`restore`): advances the fence, reads the store through the
   queue, and only applies the result if the fence is still current.
2. **Adopt** (`adoptSession`): advances the fence, keeps the pair in memory,
   then persists. The returned `false` means *not durable* - the caller must not
   present the sign-in as a success (#100).
3. **Resolve identity** (`updateUserId`): records the id from `GET /me`;
   `notifySignedIn` is what broadcasts `NowaveAuthSignedIn`, so listeners never
   see a sign-in without a user id.
4. **Rotate**
   - Proactive (`ensureFreshAccess`): asks `decideSessionExpiry` first. A
     comfortably valid access token does no network work; an expired refresh
     token or a spent refresh token with a dead access token ends the session
     locally; only `rotate` reaches the network.
   - Reactive (401 path): `refresh()` is single-flight per generation.
   - A rejection (401/`UNAUTHENTICATED`) clears the session; an unknown outcome
     (timeout, dropped connection, 5xx) keeps the session but marks the refresh
     token spent, and that decision is persisted so a restart cannot replay the
     token (#101).
5. **Sign out** (`clearForSignOut`): advances the fence, drops memory first,
   then clears storage through the queue and reports `cleared` / `disowned` /
   `failed`. `NowaveAuthSignedOut` is broadcast only if no newer identity took
   over in the meantime (#102).

## Rules when changing this code

- Never `await` and then use a captured session without re-checking the fence.
- Never send `refreshToken` when `refreshTokenSpent` is true; end the session
  instead (a replay revokes the family).
- Route every store call through `SerialQueue`; a direct `await store.write`
  can land after a sign-out.
- Keep the expiry policy in `decideSessionExpiry` (a pure mapping) and add the
  case to `test/unit/nowave/session_expiry_test.dart` instead of growing
  `ensureFreshAccess` with branches.

## Tests

`test/unit/nowave/` - `session_expiry_test` (decision table),
`serial_queue_test` (ordering and error isolation), `keyed_single_flight_test`
(one rotation per session, slot release), `session_generation_test` (fence),
`nowave_session_test` (lifecycle), `nowave_session_race_test` (interleavings
across account changes), `nowave_session_refresh_unknown_test` (#101),
`resilient_session_store_test` and `session_store_migration_test` (#102).
