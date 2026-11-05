# Issue 勘误与完成度核对（2026-11-05）

审查基线：`f471a87`（`main`，#129 合入之后）。

## 为什么有这份文件

#110 要求把 2026-11-02 审查里写偏的路径、行号回写到 #104–#109 正文。本次会话再次确认：当前 GitHub 集成对 Issue 的**正文 PATCH 与评论仍返回 `403 Resource not accessible by integration`**（唯一可行的关闭途径是合并一个正文含 `Closes #nn` 的 PR）。

因此按 #110 自己给出的备选方案，把权威勘误保存在仓库内：本文件随 PR 合入 `main`，各 Issue 通过 PR 的描述指向它。Issue 正文保持原样，产品问题与优先级不因定位修正而改变。

同时，本次核对发现 #100、#101、#102、#104 的验收标准**已经全部由 #95–#127 的实现与测试满足**，只是从未被关闭。下面第二～五节给出逐条证据，供关闭时核对。

## 一、定位勘误（相对 #110 记录的版本）

2026-11-02 之后的分层与拆分改动（#123、#125–#127、#129）使 #110 里的一部分路径再次过期。当前值如下。

| Issue | 说法 | 现状（`f471a87`） |
| --- | --- | --- |
| #104 | `UserEditBloc` 在 `lib/features/user/bloc/user_edit_bloc.dart#L24-L59` | 文件仍在，类定义 `L14`；fence 捕获 `L54`，结果校验 `L77`，`_currentFence` `L87`，`_isCurrent` `L97` |
| #104 | 多步资料流程在 `user_repository_impl.dart#L20-L53`（读公开资料 → 头像上传 → `PUT /me/profile`） | 现在 `L15-L63`，每步都带 `sessionFence`（`L26`、`L44`、`L58`） |
| #104 | 收藏读取 `blog_remote_data_source.dart#L503-L516` | 现在是 `L617-L641`，未激活账号走 `getJsonForViewer(expectedUserId:)` |
| #104 | 删除/回收站 `blog_remote_data_source.dart#L437-L479` | 回收站读取现在是 `getDeletedBlogs()` `L560`，恢复 `L593`，删除/清空同段落 |
| #105 | 探针在 `lib/init_dependencies.dart#L174-L188` | 现在是 `L203-L215`（一次 `GET /api/v1/health`，无公网探针） |
| #105 | 登录预探测 `auth_repository_impl.dart#L97-L120` | 现在在 `L97-L140` 附近，随 `AuthIntentGate` 一起判定 |
| #106 | 非交互标签 `article_tag_label.dart#L5-L25` | 现在是 `L12-L20`（`onTap` 为空即惰性标签） |
| #106 | 固定读 100 个标签再解析 slug `blog_remote_data_source.dart#L623-L640` | 现在是 `resolveTag()` `L400-L440`：`/tags?query=…` 服务端子串匹配 + 分页，不再全量拉取 |
| #107 | 反向依赖在 `lib/core/storage/app_database.dart#L1-L24` | `grep -rn "package:belog/features" lib/core` = **0 命中**，反向依赖已解除（#127）；规则现由 `test/unit/core/layering_test.dart` 守住 |
| #107 | 大文件统计：`blog_editor_page.dart` 853 行等 | 现在 `blog_editor_page.dart` 486、`nowave_api_client.dart` 551、`blog_remote_data_source.dart` 649、`nowave_session.dart` 392、`blog_viewer_page.dart` 163、`markdown_body.dart` 117（拆分已完成，#126/#127） |
| #108 | 固定 `zh-CN` 在 `blog_remote_data_source.dart#L248-L270` | 已由 #129 消除：27 处查询参数改为 `'locale': _locale`，缓存按 `(id, content_locale)` 分键 |
| #109 | 约 1.1 MiB 的 `assets/images/sffinks.png` | 该文件已不在仓库内；`assets/` 现只有字体、logo 与 `no_wave_cover_fallback.jpg` |

## 二、#100 登录幽灵会话 — 验收对照

| 验收 | 代码 | 测试 |
| --- | --- | --- |
| 注入 `/auth/login` 成功 + `/me` 失败、`/me/profile` 失败、持久化失败、畸形/空 token | `auth_remote_data_source.dart` 登录 `L150`、注册 `L67`；失败统一走 `_abandonAdoptedSession` `L298`；`adoptSession` 返回持久化结果 | `login_partial_failure_test.dart`：`a failed identity lookup leaves no session behind`、`a failed profile lookup leaves no session behind`、`a session that cannot be stored is not reported as success`、`an unusable token pair is rejected before it is adopted` |
| 内存 / 磁盘 / AuthState / AppUserCubit 一致 | 只有 `notifySignedIn()` 才广播登录（`nowave_session.dart` 内），且需已解析 userId | `the repository failure and the session store agree`、`a successful sign-in stores one session in memory and disk` |
| 重启不会在前次失败后进入账号 | 失败时清理同一 generation 的会话与磁盘副本 | `a failed identity lookup leaves no session behind`（断言 store 为空，即重启读回 null） |
| 迟到失败不清除更新账号；注册同等覆盖 | `_requireSession(generation, intent)` / `_requireIntent(intent)` 围栏 | `a late failure never clears a newer session`、`a sign-up that cannot load its profile is reported clearly` |

## 三、#101 refresh 结果未知 — 验收对照

| 验收 | 代码 | 测试 |
| --- | --- | --- |
| 服务端已轮换但客户端超时/断流后，不再重发旧 refresh | `nowave_session.dart` `_refreshLocked` `L212`，未知结果 → `_markRefreshTokenSpent` `L299`；再次主动刷新直接 `clear()`，401 路径同样拒绝重放 | `nowave_session_refresh_unknown_test.dart`：`an unknown rotation outcome retires the refresh token`、`a 5xx during the rotation is also an unknown outcome` |
| 新 token 写盘失败 + 重启不重放磁盘旧 token | 轮换后 `_persist()` 失败即清掉磁盘副本（`_refreshLocked` 内注释注明原因） | `a rotation that cannot be persisted drops the stale copy` |
| 401 reuse 与网络失败的用户状态/诊断不同 | 拒绝 → `clear()` + `NowaveAuthSignedOut`；未知结果 → 保留 access token、退役 refresh token；两者 `AppLogger.error` 文案不同 | `a rejection still drops the session at once`、`a spent token keeps a still-valid access token alive`、`test/unit/nowave/unauthorized_replay_test.dart` |
| single-flight / 主动刷新 / 401 重放 / 跨账号 | `KeyedSingleFlight` + `decideSessionExpiry`（`session_expiry.dart` `L32`） | `keyed_single_flight_test.dart`、`session_expiry_test.dart`、`nowave_session_test.dart`、`nowave_session_race_test.dart`、`unauthorized_replay_test.dart` |

## 四、#102 secure storage 韧性 — 验收对照

| 验收 | 代码 | 测试 |
| --- | --- | --- |
| 新装 secure 读/写失败时 SQLite 回退可用 | `resilient_nowave_session_store.dart` `open` `L134`：写入落空即迁移 authority；`session_store_migration.dart` 全流程 try/catch 保底 | `a broken secure medium falls back to SQLite, even on a fresh install`、`a secure write that fails at runtime moves the marker too` |
| 迁移写入成功但清除失败 / 崩溃 / 读取损坏时不会静默选回旧账号 | 迁移先回读校验再删旧副本；无法回读则 `adoptVerified(sqlite)`；marker 权威（`clearForSignOut` `L284`） | `a copy that does not read back is never trusted`、`an undeletable legacy row is disowned`、`an unreadable marked copy falls back to the other`、`leftovers are retried on the next read` |
| logout 清除失败不展示无条件成功；重启覆盖旧会话复活 | `nowave_session.dart` `clearForSignOut` `L327` 返回 `SessionClearResult`；`auth_repository_impl.dart` `L177` 映射为 `auth.localSignOutIncomplete` 并附「重启后若仍显示该账号，请再次退出」 | `an unwritable marker fails the sign-out`、`a clear that fails everywhere still disowns the copies`、`auth_repository_test.dart` 断言 `auth.localSignOutIncomplete` |
| refresh 新 token 持久化失败、登录 adopt 写失败向上传播 | `_persist` `L377` 返回 bool；轮换失败清副本、adopt 失败抛 `auth.sessionNotPersisted` | `a rotation that cannot be persisted drops the stale copy`、`a session that cannot be stored is not reported as success` |
| 不删用户其他数据、不记录 token/邮箱 | marker 只存介质与 generation | `the marker carries no credential`、`resilient_session_store_test.dart` 的日志断言 |

## 五、#104 账号隔离 fence — 验收对照

| 验收 | 代码 | 测试 |
| --- | --- | --- |
| 资料读取后、头像上传后、PUT 前/后注入 A→B 与 A→B→A | `user_edit_bloc.dart` `L54/L77`、`user_repository_impl.dart` `L44/L58`（fence 随每次请求下发） | `test/unit/user/user_edit_fence_test.dart`：`a switch during the profile read stops the write`、`a switch after the avatar upload stops the write`、`A -> B -> A is still a different operation`、`a switch after the write does not repaint the new account`、`an unchanged session saves normally`、`signed out means nothing is sent` |
| 收藏、回收站、删除同样的跨步骤测试 | `blog_remote_data_source.dart` `L560`（回收站）、`L617`（收藏）、`L593`（恢复） | `test/unit/blog/me_scoped_fence_test.dart`：`liked articles are refused for a viewer who is not active`、`the recycle bin is bound to the active account`、`a switch during the recycle-bin read is reported`、`a switch during the delete is reported, not retried`、`a switch during the like write is reported`、`restore follows the active account` |
| 切换后旧账号内存页清空；同 userId 新 generation 不可复用 | `SessionGeneration` 每次身份变更即 `advance()` | `test/unit/repositories/blog_liked_session_switch_test.dart`：`the saved list reloads for the new account on a switch`、`signing out clears the liked map and stops requesting`；`user_edit_fence_test.dart` 的 A→B→A 用例 |
| 服务端拒绝后 UI/诊断明确，不靠隐藏页面通过测试 | `SessionFence` 拒绝映射为 `server.*` 错误码，页面展示本地化失败 | `me_scoped_fence_test.dart` 断言 `server.UNAUTHENTICATED` / switch 错误码；`test/widget/saved_blogs_retry_test.dart`、`edit_user_info_page_test.dart` |

## 六、仍然开放的部分

- **#107**：`lib/core` → `lib/features` 已为 0 命中，千行级单元已拆分，「依赖规则测试」本次由 `test/unit/core/layering_test.dart` 补上（扫描 `lib/core` 是否导入 `package:belog/features/`、`lib/core/storage` 是否导入 `package:flutter/`，并额外断言扫描确实覆盖到文件）。残留一项：`lib/core/theme/sqlite_theme_store.dart#L10-L20` 仍以 Flutter 的 `ThemeMode` 作为端口类型，「存储层不依赖 Flutter UI 类型」在 theme 这一处尚未成立，需要把端口改成自有枚举再由表现层转换。
- **#109**：尚无 `LICENSE`（需维护者选定许可）；`pubspec.yaml` 仍是 `0.0.0+1`；Android `applicationId` 仍是 `com.example.belog`，其变更是升级/数据迁移决策，需所有者确认。**本次已做**：`coverage/lcov.info` 不再由源树承载，覆盖率改为 CI 产物（见 `docs/ci-observability.md`）。
- **#24**：品牌文案（Belog / Bottom Think）与界面语言切换已清理完成；剩余的是无障碍与文案统一的长期项。
- **#21 / #18**：功能类需求，需要单独排期。

## 七、复核方式

```bash
# 反向依赖
grep -rn "package:belog/features" lib/core        # 期望 0 命中
# 验收测试清单
grep -rn "  test(" test/unit/user/user_edit_fence_test.dart test/unit/blog/me_scoped_fence_test.dart
grep -rn "  test(" test/unit/nowave/nowave_session_refresh_unknown_test.dart
grep -rn "  test(" test/unit/nowave/resilient_session_store_test.dart test/unit/nowave/session_store_migration_test.dart
grep -rn "  test(" test/unit/auth/login_partial_failure_test.dart
# 行数漂移
wc -l lib/features/blog/presentation/pages/blog_editor_page.dart lib/core/nowave/nowave_api_client.dart
```
