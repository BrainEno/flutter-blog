# 代码健壮性与分层审查（2026-10）

## 范围与结论

本次基于 main 的 `8d87d05` 和本分支变更审查了认证/会话、文章缓存与删除、
草稿、导出、依赖注入和本地构建路径；并非逐行安全审计或生产后端验证。
项目已有 entity/use case/repository 分层与测试，但**尚不完全符合 Clean Architecture**。
未合并的 [#66](https://github.com/BrainEno/flutter-blog/pull/66) 不在 main，
不能将其 outbox 当作当前功能；本轮审查未改数据库 schema 或清除数据。
#23 当前已关闭，但草稿 PR #66 的相关验收仍有未完成项。

> 2026-11 更新：普通本地草稿按后端和账号隔离，并保留无法归属的旧草稿；
> 这是独立于 #66 outbox 的修复。旧版应用降级、设备数据提取及服务器授权仍有
> 各自的限制，见 [旧草稿说明](unclaimed-drafts.md)。
>
> 2026-11-04 更新（#107）：Isar 依赖及其一次性导入器已彻底删除（见
> [SQLite 存储](sqlite-storage.md)），`lib/core` 不再依赖 feature 或 Flutter UI
> 类型；死代码清理删除了无调用方的 `ApiConnectionChecker.servesPrivateOrigin`、
> `AppLogger.connectivityOffline`、`DiagnosticsBuffer.recordOffline`、未使用的
> `markdownImageAlt` 文案与 data 层兼容导出。本文其余条目仍然有效，但「旧 Isar
> 导入」相关的正面评价不再适用。
>
> 2026-11-04 更新（#107 第三步）：会话时序从 `NowaveSessionManager` 拆成独立单元
> ——`SessionGeneration`（账号 fence）、`SerialQueue`（持久化排序）、
> `KeyedSingleFlight`（每会话一次刷新）、`decideSessionExpiry`（纯决策表），
> 各自带时序/映射测试；`docs/session-lifecycle.md` 是这些规则与改动守则的入口。
> `nowave_session.dart` 由 570 行降到约 390 行，公开 API 与行为不变。
>
> 2026-11-04 更新（#107 第四步）：`NowaveApiClient` 传输细节拆成
> `lib/core/nowave/transport/`：`ApiBaseUrl`（URL 组合与 `/api/v1` 拒绝）、
> `decodeEnvelope`（响应信封映射与 `EnvelopeFault`）、
> `decideUnauthorizedReplay`（401 唯一反应）、`NowaveApiException`、
> `NowaveMediaAsset`，各自带单测；`nowave_api_client.dart` 由 682 行降到约 555
> 行并保留两个 `export` 兼容层，公开 API 与行为不变。规则与改动守则见
> [no-wave transport](nowave-transport.md)。

## 本轮修复

- 文章编辑页通过 domain 的 `BlogDraftStore` 接口访问草稿，个人中心通过
  `ExportUserData` 端口调用导出；具体 SQLite/分享实现由组合根注入。
  data 层的 `blog_draft_store.dart` 兼容导出已无调用方，在 2026-11 的死代码
  清理中删除；草稿读写和迁移逻辑没有变化。
- 文章详情/搜索的 SQLite 读写、删除前缓存读取和连接探测异常统一返回
  `Failure`；服务端已删除但本地清理失败时明确警告可能出现离线旧副本，并刷新
  在线的个人文章列表。返回 `false` 的删除不再显示成功。账号仓库和个人资料
  编辑的异常也不再逃出其 `Either` 契约。
- 会话刷新/恢复/持久化以代际和串行写入约束旧结果；401 重放不会跨会话，
  迟到的 sign-out 不会清除已切换的会话，账号变化时提示**请求可能已提交**，
  不假装所有写入都失败。新增针对刷新、存储和 API 时序的回归测试。
- 调试脚本、配置验证及 debug-only HTTP 例外见 README；生产/发布安全策略未放宽。

## 后续隐私修复

- 离线资料缓存按后端与账号隔离；账号变更期间的旧资料恢复不会覆盖新账号。
  登录/注册的身份解析、注册资料写入和 UI 发布增加会话校验；多个未认证登录
  请求的意图乱序已由 `AuthIntentGate` 收敛（#99）。旧的 `cached_profile_v1`
  缺少归属，保留在本地但不读取或自动分配；更新后首次离线可能暂时没有昵称和
  头像，联网成功后按账号重建缓存。
- 登录/注册改为「全有或全无」（#100）：令牌先落盘再认领会话，落盘失败即报
  `auth.sessionNotPersisted` 而不是假成功；认领之后的任何失败（身份解析、
  资料读取、注册资料写入）只在 generation 与 intent 仍属于本次尝试时尽力
  撤销服务端会话并清除本地会话，因此「显示登录失败、重启却已登录」的幽灵
  会话不再出现，迟到的失败也不会清掉新账号。`GET /me` 失败属于可恢复情况，
  改用 profile 里的同一 userId 补齐；两者都读不到才放弃。令牌为空或过期时间
  无法解析时在认领前直接拒绝（`auth.parse.invalidTokens`）。注册在账号已创建
  但未完成登录时给出单独文案（`auth.signedUpButSignedOut`）。
- 实际接入了退出登录时的阅读历史清理；只清理退出账号。阅读历史页切换账号
  时立即隐藏旧列表，并拒绝迟到查询或旧账号确认操作。退出清理仍是尽力而为，
  存储故障、已在途写入、系统备份或回退旧版均不保证物理擦除。

## 需要后续处理的风险

| 优先级 | 发现 | 建议与限制 |
| --- | --- | --- |
| 已缓解 | 原普通草稿只按文章/新文章隔离，共享设备切号可能看到旧账号草稿。 | 新记录按后端和账号隔离；旧记录无法证明归属，保留但不自动显示。退出不等于物理擦除，降级旧版仍可能泄露；#66 outbox 仍是独立工作。 |
| 高 | ~~本次保护会话刷新、请求重放和迟到的退出，但未实现整个登录/注册/退出流程的用户意图串行化~~ —— #99 已补：`AuthIntentGate` 为每次登录/注册/退出分配单调 intent，数据层在 adopt 前和每个 await 后校验，bloc 用同一 id 决定是否改写 UI/缓存。仍未覆盖的是**跨步骤业务写入**（资料保存、收藏、删除）与退出时的服务端撤销时序（#104）。 | 继续把 intent 传给业务写路径（#104），并把「旧响应结果不明」的文案与重放策略单独收敛。 |
| 已缓解 | ~~刷新结果未知（超时、断流、5xx）后旧 refresh token 仍可重试~~ —— #101 已收敛：未知结果会把该 refresh token 标记为 spent 并随会话持久化，重启后也不会重发；会话只靠仍有效的 access token 维持，access 过期或再次请求刷新时本地登出。刷新成功但新 token 落盘失败时清除磁盘旧副本。401 撤销与网络失败的诊断文案、用户状态和重新登录路径彼此区分。 | 真正「重试而不撤销」需要服务端为 refresh 提供幂等/replay 契约（相同请求取回首次结果），当前没有对应 no-wave 能力与联调证据，未验证。 |
| 已缓解 | ~~安全存储迁移失败会回退 SQLite；清除失败只记录日志，重启可能重新读到旧会话~~ —— #102 已收敛：`ResilientNowaveSessionStore` 用 SQLite `metadata` 里**不含令牌的标记**（`nowave_session_authority_v1`）记录哪一份副本有效。安全存储启动探针（写/读/删，独立 key）失败即写 SQLite；迁移先写入再读回校验，校验不过就保留 SQLite 副本；退出**先写「无会话」标记**再清两处副本，因此删除失败也不会在重启后复活账号，并把 `cleared / disowned / failed` 作为退出结果向上传播（`AuthLogoutFailure` + `auth.localSignOutIncomplete`）。 | 仍未验证真实平台的 Keychain/Keystore 故障注入、系统备份恢复与越狱/root 场景；标记本身写在 SQLite，若 SQLite 整体不可用，退出会明确报 `failed`，此时不能承诺重启后不复活。字段置空不等于物理擦除。 |
| 中 | 阅读历史只按用户 ID 而非后端隔离；退出清理与在途写入或同账号重新登录尚未完全串行。 | 后续设计后端归属、迁移和写入/清理协调，不能承诺所有旧记录或副本都已擦除。 |
| 高 | 文章/媒体写入超时后的结果可能未知。线上服务的文章幂等能力、媒体去重/孤儿清理尚未验证；当前分支没有持久 outbox。 | #23 虽已关闭，#66 尚未合并且验收有缺口；需要服务端部署能力证据、持久账号隔离、状态/退避及媒体补偿，不能盲重试或凭客户端代码宣称端到端幂等。 |
| 已缓解（部分） | ~~`lib/core/storage/app_database.dart` 和 `sqlite_blog_cache.dart` 仍依赖 feature data 模型，`core/storage` 中也有带 Flutter 类型/具体存储的实现~~ —— #107 第一步已收敛：`lib/core` 不再导入 `lib/features`（`SqliteBlogCache`、`SqliteBlogDraftStore`、阅读历史实现移入 `features/blog`），`AppDatabase` 只接受原始类型（`setTheme(String)`、`upsertBlogRow(...)`），主题偏好实现移到 `core/theme`；`tool/ci/check_core_dependencies.py` 加上 `flutter test` 之外的 unittest 守护这两条规则。仍开放：domain 的附件接口使用 `dart:io File`，`blog_detail_page.dart` / `edit_blog_page.dart` / `no_wave.dart` 等大页面尚未按职责拆分（`nowave_session.dart`、`nowave_api_client.dart` 已分别于第三步、第四步拆分）。 | 后续继续保持规则零违规，并按「认证拆分 session 状态机 / refresh 单飞 / 账号 fence」逐步拆单元；保留现有 SQLite 表与数据/迁移测试，不宜为分层一次性迁移数据库；Isar 依赖已按「不维护即移除」原则在 #107 第二步彻底删除（见 docs/sqlite-storage.md）。 |
| 中 | 部分 repository 将未分类异常转为 feature-specific 的通用失败，可能丢失网络/超时分类。 | 按操作逐项梳理可重试性、结果未知、日志脱敏和本地化，而不是对所有异常一律重试或返回成功。 |

本次新增自动化测试覆盖上述**已修复**路径；mock 测试不能代替真实 Android/iOS
设备、后端联调、平台 secure storage 故障注入、签名与无障碍验收。
