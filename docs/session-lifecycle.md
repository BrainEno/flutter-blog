# Session lifecycle (no-wave)

> 状态：active ｜ 最后核对：2026-11-16 @ 7fc34ce

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

## 认证接口与持久化摘要（原 README，#298）

- **注册 / 登录**：`POST /auth/{register,login}`，body 仅 `{email,password}`；
  注册密码最短 **12 位**（客户端已同步前移校验）。成功即返回
  `{accessToken, refreshToken, …}`，注册后立即 `PUT /me/profile` 补写昵称。
- **会话持久化**：token 对存平台安全存储（iOS Keychain / Android Keystore，
  issue #46；SQLite 作为迁移源与降级兜底，`core/nowave/nowave_session.dart`）。
  启动时恢复，`GET /me` + `GET /me/profile` 解析身份。
  **哪一份副本有效由一个不含令牌的标记决定**（SQLite `metadata`，`#102`）：
  安全存储启动时先做写/读/删探针，不可用就直接写 SQLite，会话照常登录；迁移
  先把旧行复制到安全存储并**读回校验**才删除旧行，写坏或读不回就保留 SQLite
  副本；退出时**先写「无会话」标记**再清两处副本，即使 Keychain 删除失败，重启
  也不会复活旧账号，并把「本地副本未清干净」作为退出结果提示给用户。
- **刷新轮换**：`POST /auth/refresh` 单次有效且轮换；**重用已轮换的 refresh
  token 会撤销整个会话族**，因此客户端的刷新严格单飞（single-flight），
  access token 过期遇 401 时自动刷新并重放请求一次。刷新遇到超时、断流或 5xx
  时结果不明，客户端**不会重发同一个 refresh token**：会话保留（access token
  仍可继续用），但该 token 会被标记为已作废并持久化，重启后同样不会重发；
  access token 过期或再次需要刷新时本地登出，要求重新登录。刷新成功但新 token
  写盘失败时会清除存储里的旧副本，避免重启后拿旧 token 触发重放撤销。
- **退出**：`DELETE /me/session` 尽力撤销会话族并清除内存中的当前会话；
  安全存储或 SQLite 清除失败时旧副本可能留存，不能承诺已物理擦除。
- **会话同步**：`lib/features/auth/auth_session_sync.dart` 订阅会话状态流；
  后台刷新失败导致的登出会立即把用户带出登录态 UI。
- **email 展示**：在 no-wave 审计快照 [`55a24bd`](https://github.com/BrainEno/no-wave/tree/55a24bdaa1c01888fb5ecb5bf41befe219348049) 中，`GET /me` 可返回邮箱和验证状态；本客户端目前只使用其中的 id，账号页邮箱仍来自登录/注册时的本地缓存（见迁移文档）。
