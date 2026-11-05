# belog / flutter-blog 全面代码审查报告

> - **首次审查**：2026-11-02
> - **最近复核**：2026-11-03
> - **代码基线**：`9bf57f6cfe9a141fc75f0874cf69b1d2ece8147f`（PR #97 后的 `main`；复核时仍为远端最新 `main`，当前工作区 tracked 源码与其一致）
> - **审查分支**：`arena/f8c9ef29-flutter-blog`
> - **审查方式**：当前源码静态审查、脚本测试、GitHub PR/CI 证据复核、现有 Issue 验收对照
> - **重要边界**：本环境没有 Flutter/Dart SDK；未运行 Flutter analyze/test/build、真实后端、模拟器或真机，也未做生产数据验证。

## 0. 勘误（基线之后的进展，读本文前先看这里）

本文是 `9bf57f6`（2026-11-02）的**时点快照**，正文数字与结论按当时状态保留。之后的变化：

- **#107 第一步已完成**（PR #122）：`lib/core` 不再导入 `lib/features`，`core/storage` 不再导入 Flutter UI 类型；`SqliteBlogCache`／`SqliteBlogDraftStore`／阅读历史实现移入 `features/blog`，主题偏好实现移入 `core/theme`，`AppDatabase` 只接受原始类型。`tool/ci/check_core_dependencies.py` 加 unittest 守护。第 119 行、第 96 行以及「架构与可维护性」一行里“core 仍依赖 feature model / Flutter 类型”的描述已不适用。
- **Isar 依赖已彻底删除**：`isar_community*` 三个包、`lib/core/storage/legacy/` 生成代码（本文第 54 行的 3,991 行）、`tool/legacy_isar_fixture/`（第 56 行）、`test/fixtures/legacy_isar_3_1_0/`、一次性导入器与导入测试、`build.yaml` 全部移除，`docs/isar-to-sqlite-migration.md` 改写为 [sqlite-storage.md](sqlite-storage.md)。第 30 行、第 114 行关于“旧 Isar 复制导入”的正面评价不再适用（导入能力已不存在）。
- **Issue 状态（2026-11-05）**：#99、#101、#103–#110 与 #21、#24 全部关闭，**仓库只剩 #18（举报与屏蔽）开放**，且它需要 no-wave 侧先提供接口。本文的 issue 表格与行号只反映 11-02 的状态，别再据此判断“仍开放”。
- 当前债务清单以 [code-audit.md](code-audit.md) 为准；本文的 issue 表格只反映 11-02 的状态。

## 1. 执行摘要

这个项目已经不是简单的 UI 示例：它有较完整的 no-wave REST 接入、feature-first 分层、Bloc 状态管理、SQLite 缓存与迁移、双语资源、语义/大字测试、会话刷新单飞、账号代际围栏，以及较严格的 CI/发布防误配检查。

当前最重要的结论不是“再增加功能”，而是：

1. **先恢复交付门禁**：PR #97 在 format/test 红灯下合并；当前 main 的 format 和 test 也已失败。详见 [#98](https://github.com/BrainEno/flutter-blog/issues/98)。
2. **把认证当成一个跨请求状态机处理**：登录意图、令牌持久化、身份解析、refresh 结果未知、退出清理和切号 fence 不能分别靠局部补丁推断。详见 [#99](https://github.com/BrainEno/flutter-blog/issues/99)–[#105](https://github.com/BrainEno/flutter-blog/issues/105)。
3. **立即修复确定的数据丢失问题**：资料页把“简介”写进 website，保存时固定发送空 `bio`。详见 [#103](https://github.com/BrainEno/flutter-blog/issues/103)。
4. **UI 基础较好，但不能把 widget 测试当成真机验收**：视觉、双语、语义和大字已有工程投入；标签浏览断链、内容语言固定、相对头像和真机无障碍仍是明确缺口。
5. **架构值得保留并渐进调整**：不建议推倒重写；优先解除 core→feature 反向依赖，并围绕认证时序拆出可测试单元。详见 [#107](https://github.com/BrainEno/flutter-blog/issues/107)。

### 多维度结论

| 维度 | 评价 | 主要依据与限制 |
|---|---|---|
| 架构与可维护性 | **良好，存在局部反向依赖** | feature-first、Usecase/Repository/Datasource 边界清楚；`core/storage` 仍依赖 feature model 和 Flutter 类型。 |
| 认证与会话健壮性 | **需优先修复** | 有 single-flight、代际检查和 401 单次重放；但登录意图、ghost session、refresh 重用、存储失败与跨步骤切号仍有风险。 |
| 网络与离线 | **设计较细，release 路径有缺口** | 缓存范围、错误分类、游标/offset 回退有说明；release/profile 仍可能被公网预探测短路。 |
| UI/UX 与无障碍 | **基础良好，人工验收未完成** | 纸墨视觉、四标签独立栈、ARB、语义、键盘和 2× 字体测试较完整；真机视觉和 VoiceOver/TalkBack 未验证。 |
| 数据与迁移 | **较稳健，失败语义需补强** | SQLite schema v6、旧 Isar 复制导入和账号草稿隔离较审慎；session 写入/清除失败仍被吞掉。 |
| 安全与隐私 | **工程意识较好，不等于安全审计通过** | 当前树未发现真实 env/私钥；敏感诊断需用户主动查看/分享，release 签名 fail-closed；会话持久化与 refresh 风险仍待修复。 |
| 测试与 CI | **测试资产较多，当前交付门禁不通过** | `test/` 有 103 个 Dart 文件；但 main format/test 红灯，且仓库内旧 LCOV 不能代表当前覆盖率。 |
| 发布准备度 | **尚需整理** | Android/iOS/桌面有构建检查；许可证、占位版本、通用 applicationId、资源与构建产物边界仍需明确。 |

### 复核增量（2026-11-03）

- **代码对照**：本地 `HEAD` 仍为 `5c0ef3a`，所以 `git status` 显示的 11 个 tracked 修改是 PR #97 相对旧 `HEAD` 的内容；以远端最新 `main`（`9bf57f6`）为旧端时，tracked diff 为 **0**。这些文件不能被记为 #98 的后续修复或新的工作区候选补丁。
- **Issue 状态**：#88 与 #59 已于 2026-11-02 关闭；#98–#110 在复核时仍全部开放。原报告中的认证、资料、标签、内容语言与发布债务没有因本次文档复核而自动消除。
- **CI 状态**：最新 `main` 的 CI 仍为 format/test 失败；审查文档 PR #112 的 format/analyze 等检查通过，但 Flutter test 也失败。不能把“文档 PR 已打开”写成“质量门禁已恢复”。

**新增 P3 观察：登录页固定诊断入口与 README 的直接打开承诺不一致（未单独新建 Issue）。**

- `lib/features/auth/presentation/pages/login_page.dart` 的固定按钮使用 `context.push('/about')`；只有登录失败 SnackBar 的 `_openDiagnostics()` 使用 `/about?diagnostics=1`。
- `lib/router/app_router.dart` 仅在查询参数 `diagnostics=1` 时向 `AboutPage` 传入 `openDiagnostics: true`，而 `AboutPage` 只在该标志为真时自动打开诊断弹窗。因此固定按钮实际只到 About 页面，README 中两个登录入口“都会打开诊断弹窗”的描述不准确。
- `test/widget/router_test.dart` 的固定入口测试目前只断言 `AboutPage` 出现，没有断言诊断弹窗出现，所以覆盖不到这个差别。建议固定按钮复用 `_openDiagnostics`，并把测试加强为直接断言报告可见；若产品意图只是进入 About，则应收窄 README 描述。此项不影响探测超时判定逻辑本身，也不能据此宣称 #98 已修复。

## 2. 代码规模与资产

以下为当前工作树的**物理行**统计，包含注释和空行，不等于有效语句数、复杂度或质量。

| 分类 | 文件数 | 行数 | 说明 |
|---|---:|---:|---|
| 手写应用 Dart（`lib/`，不含 3 个 legacy `.g.dart`） | 205 | 21,407 | 生产代码、UI、领域、数据与基础设施 |
| 生成的 legacy Dart | 3 | 3,991 | 旧 Isar model 的生成代码，保留用于导入 |
| 测试 Dart（`test/`） | 103 | 21,931 | 77 个 unit、24 个 widget，另有 2 个 support 文件 |
| legacy fixture 工具 Dart（`tool/legacy_isar_fixture/`） | 7 | 4,161 | 含 fixture 自身的手写与生成代码 |
| **Dart 合计** | **318** | **51,490** | 不将测试行数等同于覆盖率 |
| Python / PowerShell / Shell | 41 | 3,552 | 开发、CI、发布与校验脚本 |
| YAML | 13 | 1,666 | CI 与配置 |
| ARB | 2 | 824 | 简体中文、英文界面资源 |

补充观察：

- 测试代码量与手写应用代码量接近，说明回归测试投入较大；但认证分布式时序、平台存储故障和真机体验仍需要针对性测试，而不是继续堆通用 widget 数量。
- 相对较大的手写文件包括 `blog_editor_page.dart` 853 行、`nowave_api_client.dart` 681 行、`blog_remote_data_source.dart` 667 行、`markdown_body.dart` 580 行、`blog_viewer_page.dart` 512 行。**行数本身不是 bug**，只用于安排评审和渐进拆分。
- 当前 tracked `coverage/lcov.info` 是局部/残旧产物；本报告没有从它推导全量覆盖率。

## 3. 设计思路与架构

### 3.1 分层与数据流

项目采用简化 Clean Architecture，按业务 feature 组织，而不是按所有页面/所有 model 全局堆放：

```text
UI / Page
   ↓
Bloc / Cubit（状态、加载、错误、用户动作）
   ↓
Usecase（应用动作）
   ↓
Repository 接口 ← RepositoryImpl（Either<Failure, T>、异常翻译）
   ↓
Remote / Local Datasource
   ↓
no-wave REST / Drift SQLite / secure storage / 平台能力
```

核心组成：

| 区域 | 职责与设计评价 |
|---|---|
| `lib/features/auth/` | 注册、登录、退出、改密与身份恢复；领域边界明确，但跨事件意图仍需统一。 |
| `lib/features/blog/` | 文章、Feed、搜索、评论、收藏、编辑、回收站、阅读与朗读；功能最集中。 |
| `lib/features/user/` | 作者、关注关系、资料、会话列表与个人中心。 |
| `lib/core/nowave/` | API envelope、媒体 URL、session、refresh、401 重放和存储迁移。 |
| `lib/core/storage/` | SQLite 缓存、草稿、历史、主题及旧 Isar 导入；当前仍有 core→feature 依赖。 |
| `lib/router/` | `go_router` 与四个保留状态的标签导航栈；页面级 Bloc 随页面装配。 |
| `lib/init_dependencies.dart` | GetIt 组合根；依赖集中，但网络探测的 build-mode 分支需要特别测试。 |
| `lib/l10n/` + ARB | 官方 `flutter_localizations`/`gen-l10n`，界面跟随系统中英文。 |

`fpdart.Either` 让业务失败显式进入状态层；`Failure` 同时携带分类、稳定 code、可选 l10n key 和诊断 cause，避免直接把原始异常展示给用户。这是较好的错误设计。

### 3.2 文章与正文模型

- 公开读取、点赞和评论以 **slug** 寻址；更新/删除使用服务端 UUID，避免把两种 ID 混用。
- 普通编辑器写 no-wave `contentBlocks` v0；阅读器只读解析 v0/v1，保留标题、列表、代码、引用、图片和行内样式。
- Markdown/结构化正文转换成阅读和朗读共用 AST，不构造或执行 HTML，降低注入面。
- 不兼容结构拒绝普通编辑器覆盖，这是正确的数据保护策略；但它不是完整富文本编辑器，也没有解决服务端并发更新冲突。

### 3.3 本地数据与离线策略

- Drift/SQLite schema 当前为 v6；最新列表与通过详情接口获得的文章可离线缓存，精选、热门、关注不伪装成公共离线结果。
- 本地草稿按后端、账号和文章隔离；无法证明归属的旧草稿保留但不自动展示，避免为了“清理”而删除用户数据。
- 旧 Isar 导入采用复制、事务标记和保留原文件的方式，比原地破坏性迁移稳妥。
- 首页在线 latest 支持游标并兼容旧服务端 offset；其他列表仍有分页上限或服务端快照限制。

### 3.4 架构债务

`lib/core/storage/app_database.dart` 导入 feature 的 `BlogModel` 和 Flutter `ThemeMode`，使 core 不能真正独立于业务/UI。建议通过 port/DTO/adapter 渐进解除，而不是重写数据库。详见 [#107](https://github.com/BrainEno/flutter-blog/issues/107)及其证据勘误 [#110](https://github.com/BrainEno/flutter-blog/issues/110)。

## 4. API 与关键契约

客户端统一在 `$API_BASE_URL/api/v1` 下访问 no-wave。以下描述基于当前客户端和仓库的上游快照审计，**不证明实际部署已升级到相同版本**。

| 能力 | 主要 API / 契约 | 当前状态与注意事项 |
|---|---|---|
| 注册/登录 | `POST /auth/register`、`POST /auth/login` | 返回 access/refresh token；注册后补写昵称，登录后解析身份与资料。 |
| 会话刷新/退出 | `POST /auth/refresh`、`DELETE /me/session` | refresh token 单次轮换；重用可能撤销整个 session family；客户端 single-flight，401 后重放一次。 |
| 当前账号 | `GET /me`、`GET/PUT /me/profile` | 身份和公开资料分两次解析；资料保存存在 bio 缺陷。 |
| 账号安全 | `PUT /me/password`、`GET /me/sessions` | 改密不盲重试；会话列表只读，单个/批量撤销未接入。 |
| 公共/个人 Feed | `GET /articles`、`GET /featured`、`GET /me/feed` | latest 支持 cursor/offset 兼容；关注和精选不读取公共缓存。 |
| 搜索/发现 | `GET /articles?query=…`、`GET /users?query=…`、`GET /tags` | 新后端可搜索部分正文；用户/标签列表存在最多 100 条边界。 |
| 文章详情/相关 | `GET /articles/:slug`、`GET /articles/:slug/related` | slug 公开读；相关阅读最多 6 条。 |
| 文章写入 | `POST/PUT/DELETE /articles…`、`POST /articles/:id/restore` | UUID 写路径；我的文章/回收站有 100 条上限；普通发布缺稳定跨重试幂等键。 |
| 点赞/收藏/评论 | `/articles/:slug/like`、`/me/liked-articles`、`/articles/:slug/comments` | 点赞显式置态并串行化；评论发送有幂等键；收藏 `/me` 路径需要账号 fence。 |
| 作者与关注 | `/authors/:id`、`/users/:id/follow`、`/users/:id/{followers,following}` | 公开关系列表无需凭据；最多 100 条，无完整分页。 |
| 媒体 | `POST /me/media`、`GET /media/:id` | 原始字节上传，服务端转 WebP；资源 immutable；上传无幂等键，不断言断流后可安全重发。 |
| 分享 | no-wave Web canonical URL + `share_plus` | 出站分享已有；接收 universal link/deep link 仍未完成。 |

### 已接入但未形成完整闭环的上游能力

- 内容 locale 选择、修改邮箱/邮箱验证、找回密码、通知、私信、分类维护、编辑角色、媒体库列表/删除等尚未完整接入。
- 富文本目前“只读保护”强于“可编辑往返”；导出也只是部分 JSON，不是可恢复完整备份。
- 离线 outbox 不能从已关闭的 #23 或未合并的 #66 推导为已完成。
- 改密的上游会话撤销和部分成功风险见 [no-wave #129](https://github.com/BrainEno/no-wave/issues/129)与[#132](https://github.com/BrainEno/no-wave/issues/132)；客户端提示不能替代服务端修复。

完整差距应继续以 [`docs/nowave-api-gap-audit.md`](nowave-api-gap-audit.md) 为准，而不是把本报告当成新的 API 规范。

## 5. 登录与会话专项审查

### 5.1 当前主链路

```text
启动恢复（最多等待 3 秒）
  → 读取持久 session
  → GET /me + GET /me/profile
  → 更新 AppUser / 登录 UI

主动登录
  → POST /auth/login
  → adoptSession（先写 session）
  → GET /me
  → GET /me/profile
  → notifySignedIn

已认证请求
  → 必要时主动 refresh（single-flight）
  → 发请求
  → 401 时 refresh 并重放一次
  → session fence 阻止明显的跨账号旧请求重放
```

已有的正面措施不能忽略：refresh 单飞、session generation、部分账号作用域 API 的 fence、敏感写操作的结果未知提示、后台登出同步，以及 #97 对“健康检查超时不等于离线”的修正，都在降低风险。本报告没有把 #94–#97 已做的改进重复报成“完全未实现”。

### 5.2 仍需优先解决的问题

| 风险 | 代码层面结论 | 当前证据性质 | Issue |
|---|---|---|---|
| 旧登录意图覆盖新意图 | 默认并发 Bloc handler 没有统一的 latest-intent/串行语义；慢 A 可在快 B 后 adopt | 可由异步顺序推导，需 Completer 故障注入回归 | [#99](https://github.com/BrainEno/flutter-blog/issues/99) |
| ghost session | token 已 adopt/持久化后，`/me` 或 profile 失败仍返回普通登录失败，但未一致清理或进入降级成功 | 控制流可确定；具体 UI/重启组合需测试 | [#100](https://github.com/BrainEno/flutter-blog/issues/100) |
| refresh token 重用 | 超时/5xx 后保留旧 session，后续可能再次 refresh；若服务端已轮换，会构成旧 token 重放 | 高风险时序候选，未声称已在生产复现 | [#101](https://github.com/BrainEno/flutter-blog/issues/101) |
| secure storage 故障 | 新装没有写探测；`_persist()`/`clear()` 吞异常，可能掉登录或重启复活旧账号 | 代码路径确定，平台故障需真实注入 | [#102](https://github.com/BrainEno/flutter-blog/issues/102) |
| 跨步骤切号写入 | 资料、收藏、回收站等缺少贯穿整个用户操作的 userId+generation fence | 单次请求 fence 不足以覆盖多 await；需 A→B→A 测试 | [#104](https://github.com/BrainEno/flutter-blog/issues/104) |
| release 登录被误判离线 | release/profile 使用公网 checker，真实登录前先预探测；API 可达也可能零请求失败 | build-mode 分支和调用顺序可确定 | [#105](https://github.com/BrainEno/flutter-blog/issues/105) |

这些问题适合作为一个**认证一致性工作包**设计，但实现时仍应拆成可独立验证的小 PR。尤其不能通过“所有失败都退出登录”或“所有请求都重试”来掩盖结果未知。

### 5.3 建议的统一验收矩阵

至少覆盖以下注入点，并同时断言内存 session、磁盘 session、AuthState、AppUserCubit 和后续请求：

1. A 登录慢、B 登录快及相反顺序；同账号重登；登录/注册/退出/恢复交错。
2. token 写成功、`/me` 失败；`/me` 成功、profile 失败；持久化失败；空 token/异常 envelope。
3. 服务端已轮换但客户端超时；新 token 已写内存但写盘失败；重启后读取旧副本。
4. secure storage 读失败、写失败、清除失败、迁移到一半崩溃。
5. A→B 与 A→B→A 发生在资料读取后、媒体上传后、PUT 前/后，以及收藏/回收站/删除流程中。

## 6. 其他维度详评

### 6.1 健壮性与错误处理

**优点**：

- Repository 统一把异常翻译成 `Failure`，UI 使用本地化表现，诊断 cause 与用户文案分离。
- 对连接关闭、超时、401、权限、校验和结果未知做了区分，不是一律“网络错误”。
- 点赞 toggling、评论幂等键、标签 create-or-reuse 等局部并发有专门处理。
- 缓存不在权限/校验错误时伪装成功，离线与空态有区分。

**不足**：

- 认证和资料的多步骤副作用仍缺统一状态语义。
- 部分列表固定 100 条，标签 UI 尚未接通；超过上限不能被当成“没有更多”。
- 文章创建、媒体上传和离线 outbox 的端到端幂等仍不能承诺。

### 6.2 UI、视觉与可访问性

**优点**：

- 纸色/墨色、橙红强调、衬线标题、细线和留白有集中主题与复用组件。
- 首页、搜索、阅读、作者和个人中心具有一致方向；四标签保留各自导航栈。
- 封面/头像有加载失败兜底与本地化语义；常用操作有键盘、大字体和亮暗测试。
- 英文未知错误使用本地化通用文案，而不是泄漏原始异常。

**不足**：

- `ArticleTagLabel` 是非交互组件，`getBlogsByTag` 没有 UI/use-case 调用链，与 README 的“按标签浏览”不一致：[#106](https://github.com/BrainEno/flutter-blog/issues/106)。
- 资料字段存在明确的标签/数据契约错误：[#103](https://github.com/BrainEno/flutter-blog/issues/103)。
- 站点相对头像仍未解决，见既有 [#63](https://github.com/BrainEno/flutter-blog/issues/63)。
- 未做真机视觉、VoiceOver/TalkBack 和完整 iOS 人工验收，不应仅凭自动测试关闭相关体验 Issue。

### 6.3 本地化与内容语言

界面 ARB、日期/数字格式、复数与系统 locale 解析已具备基础；但 UI locale 不等于内容 locale。文章请求仍固定 `zh-CN`，没有 contentLocale 设置和跨语言缓存身份。直接替换请求字符串会导致旧缓存/旧分页混用，应作为独立功能设计：[#108](https://github.com/BrainEno/flutter-blog/issues/108)。

### 6.4 安全与隐私

**已观察到的正面措施**：

- 当前 tracked tree 未发现真实 `env.json`、私钥或签名材料；配置白名单只允许公开 origin 字段。
- release 不允许依赖 cleartext 调试例外，签名检查 fail-closed；CI 使用 `example.invalid` 等非生产 fixture。
- 日志为内存有界诊断，查看/复制/分享由用户主动触发；未见自动上传遥测。
- SQL 使用参数化语句；正文不构造 HTML；公开作者/关系请求不附带会话凭据。

**边界与风险**：

- 这不是全历史 secret scan、依赖漏洞审计或服务端授权审计。
- token 的 secure/SQLite 双副本、迁移和清除失败语义仍需修复。
- 外部图片、系统分享和语音引擎有各自平台/网络边界，应以隐私政策与实际设备验证为准。

### 6.5 性能与资源

- SQLite 首页分页、每页少量正文解码、图片缓存、搜索防抖和草稿防抖是合理方向。
- 阅读 AST 与朗读共用模型有助于避免重复解析；诊断日志有容量上限。
- 尚未做启动时间、滚动帧率、大图内存、数据库迁移耗时或 APK/AAB 体积基准，不能给出量化性能结论。
- 约 1.1 MiB 的 `assets/images/sffinks.png` 在源码中未找到引用，发布前应确认移除或压缩；不要凭文件名删除系统/原生库。

## 7. 本次新建 Issue 索引

每个产品/工程 Issue 均包含**详情证据、解决思路和验收标准**。下表只做导航，不替代 Issue 正文。

| Issue | 优先级/类别 | 核心问题 | 验收重点 |
|---|---|---|---|
| [#98](https://github.com/BrainEno/flutter-blog/issues/98) | P1 · CI/登录 | #97 后 format/test 红灯 | 修复真实登录诊断 widget；main format/analyze/test 全绿 |
| [#99](https://github.com/BrainEno/flutter-blog/issues/99) | P1 · Auth | 旧登录/注册/退出意图可覆盖新意图 | 任意响应顺序下只有有效意图更新全局状态 |
| [#100](https://github.com/BrainEno/flutter-blog/issues/100) | P1 · Auth | token 已保存但 UI 显示普通登录失败 | 注入身份/资料/存储失败，重启语义一致 |
| [#101](https://github.com/BrainEno/flutter-blog/issues/101) | P1 · Auth | refresh 结果未知后可能重用单次 token | 已轮换超时时不得再发旧 refresh；覆盖写盘失败重启 |
| [#102](https://github.com/BrainEno/flutter-blog/issues/102) | P1 · Storage | secure storage 写/清失败被吞 | 新装回退、迁移崩溃、退出复活和 refresh 写盘故障 |
| [#103](https://github.com/BrainEno/flutter-blog/issues/103) | P1 · 资料/UI | Bio 标签写 website，保存固定清空 bio | 未编辑字段保留，请求体与作者页一致 |
| [#104](https://github.com/BrainEno/flutter-blog/issues/104) | P1 · 账号隔离 | 多步骤资料/收藏/回收站缺统一 fence | A→B→A 各 await 点均不能串号或覆盖 UI |
| [#105](https://github.com/BrainEno/flutter-blog/issues/105) | P1 · 网络 | release/profile 被公网预探测短路 | 公网失败但 API 成功时真实登录仍发出 |
| [#106](https://github.com/BrainEno/flutter-blog/issues/106) | P2 · 浏览 | 标签无入口，slug 查询只有前 100 条 | 标签路由、分页、超过 100 条与可访问性 |
| [#107](https://github.com/BrainEno/flutter-blog/issues/107) | P2 · 架构 | core→feature/Flutter 反向依赖与评审单元集中 | 依赖规则、schema/迁移回归、渐进小步拆分 |
| [#108](https://github.com/BrainEno/flutter-blog/issues/108) | P2 · 内容/API | UI 英文但内容请求固定中文 | contentLocale、缓存/分页隔离与慢响应 |
| [#109](https://github.com/BrainEno/flutter-blog/issues/109) | P2 · 发布 | 许可证、版本、applicationId、产物/资源边界 | 明确发布身份、升级策略、当前覆盖率证据和 APK 分析 |

> **证据勘误**：#104–#109 初版中部分路径、行号、文件统计或事实描述与当前工作树不一致。因 GitHub 集成拒绝正文编辑和评论，权威更正集中记录在 [#110](https://github.com/BrainEno/flutter-blog/issues/110)。阅读这六个 Issue 时必须同时查看 #110；本报告已使用更正后的证据。#110 是文档回写元 Issue，不是新的产品缺陷。

## 8. 现有开放 Issue：关闭评估

### 8.1 原建议关闭，现已关闭

| Issue | 结论与证据 | 验证边界 |
|---|---|---|
| [#88 本地调试被工具链版本与启动配置卡住](https://github.com/BrainEno/flutter-blog/issues/88) | **已关闭**。PR #89 落地兼容版本策略、strict mode、唯一 pin、启动失败页、VS Code 配置和文档；当前基线脚本测试 30 项通过。[PR CI 41391480345](https://github.com/BrainEno/flutter-blog/actions/runs/41391480345) 的 format/analyze/test/Android 通过，Windows PowerShell mock 和 macOS/iOS 脚本检查也通过。 | 只关闭本地版本/启动范围，不宣称真实模拟器人工验收或当前 main 全绿；#97 的回归由 #98 跟踪。 |
| [#59 对齐 no-wave 移动视觉系统与核心阅读流](https://github.com/BrainEno/flutter-blog/issues/59) | **已按原书面范围关闭**。PR #60 完成主题、核心页面、复用组件、图像兜底及双语/键盘/语义/窄屏大字测试；[CI 41165662599](https://github.com/BrainEno/flutter-blog/actions/runs/41165662599) 全绿，且文档已列出真机/iOS 未验证项，满足该 Issue“列出未做验证”的验收要求。 | 不宣称真机视觉、VoiceOver/TalkBack 或生产 API 已验收；后续作者/个人中心和完整无障碍仍由 #61/#24 跟踪。 |

**实际状态说明（2026-11-03 复核）**：#88 于 2026-11-02 13:30:04 UTC 关闭，#59 于同日 13:30:28 UTC 关闭，原报告的两项关闭建议均已落实。关闭仍不代表真实模拟器、真机读屏或生产 API 验收已经完成；这些边界继续由对应开放 Issue 跟踪。

### 8.2 必须保持开放

| Issue | 尚未满足的验收/原因 |
|---|---|
| [#63 相对头像地址](https://github.com/BrainEno/flutter-blog/issues/63) | 可信 `WEB_BASE_URL` 解析、跨页面一致性、安全输入、无凭据图片请求和真机/实际部署核对仍未完成。 |
| [#61 作者与个人中心、回收站导航](https://github.com/BrainEno/flutter-blog/issues/61) | 代码与自动测试较多，但 PR #62 明确“不把尚未完成的真机验收视为 issue 已完成”；iOS/真机视觉、读屏及真实后端仍待验收，相对头像另见 #63。 |
| [#24 国际化与无障碍](https://github.com/BrainEno/flutter-blog/issues/24) | ARB 和自动测试已大幅推进，但 PR #58 明确保留 iOS 构建及真机 VoiceOver/TalkBack、键盘和动态字体人工验收。 |
| [#21 分享与文章深链](https://github.com/BrainEno/flutter-blog/issues/21) | 原生出站分享已完成；Android/iOS 链接接收、冷启动/运行中路由、关联域名和 fallback 未完成，不能只关闭为“分享已完成”。 |
| [#18 举报、屏蔽与审核闭环](https://github.com/BrainEno/flutter-blog/issues/18) | 举报/屏蔽入口、治理数据模型、权限负向测试、审核队列和审计闭环尚未形成；不是补一个前端按钮即可完成。 |

### 8.3 已关闭但仍有遗留工作的条目

[#23 离线可靠发布/outbox](https://github.com/BrainEno/flutter-blog/issues/23)虽已关闭，但 `docs/code-audit.md` 与 API 差距审计仍明确记录 #66 未合并、验收有缺口，需要重做。它不属于“当前开放 Issue 可关闭”清单；后续应优先复核并考虑重开原 Issue，而不是新建重复条目或宣称离线发布已可靠完成。

## 9. 建议实施顺序

### 第一阶段：恢复可信交付与阻止数据损失

1. 处理 #98：保留失败断言，修复登录诊断 widget 和格式，不在红灯下继续合并。
2. 处理 #103：先用小 PR 修正 website/bio 字段并加入完整请求体回归，避免继续清空用户简介。
3. 将 #99–#102 作为同一设计评审，明确认证状态、结果未知和持久化语义，再分小步实现。

### 第二阶段：账号隔离与实际 release 网络

1. 用统一 fence 处理 #104，并复用认证工作包的 generation/intent 规则。
2. 处理 #105，增加 release/profile 依赖注入和“公网失败、API 成功”的测试。
3. 在隔离后端完成 refresh/改密/媒体/文章写入的结果未知与幂等联调；客户端不能替代服务端事务保证。

### 第三阶段：体验缺口与工程债

1. #106 标签浏览、#63 相对头像、#108 内容语言分别补齐用户入口和缓存语义。
2. 按 #61/#24/#21 的剩余验收安排 iOS、Android 真机、读屏与 deep link 验证。
3. 渐进处理 #107 架构和 #109 发布工程，不与认证修复混成不可评审的大 PR。

## 10. 实际验证记录

### 本地已执行并通过（2026-11-03 重跑）

| 命令 | 结果 |
|---|---|
| `python3 -m unittest discover -s scripts/tests -p 'test_*.py'` | **30 项通过** |
| `python3 -m unittest discover -s tool/ci -p 'test_check*.py' -v` | **7 项通过** |
| `python3 -m unittest discover -s tool/release -p 'test_*.py' -v` | **16 项通过** |
| `bash tool/ci/validate_agent_contract.sh` | **通过** |
| `bash tool/ci/check_env_asset_contract.sh` | **通过** |
| `bash tool/ci/test_ci_scripts.sh` | **通过** |

合计本地 Python 测试 **53 项通过**，另有工程 shell 检查通过。这些结果不能替代 Flutter 测试。

### GitHub CI 证据

- 前一基线 `5c0ef3a` 的 [CI 41445667088](https://github.com/BrainEno/flutter-blog/actions/runs/41445667088) 六项全部成功，说明红灯是近期变化后的状态，而不是本报告假设项目从未有绿色构建。
- PR #97 的 [CI 41450084311](https://github.com/BrainEno/flutter-blog/actions/runs/41450084311) 已完成：format/test 失败，analyze/config/guardrails/Android 成功。测试评论尾部为 `+732 -1`，列出的失败是 `test/widget/router_test.dart: a network login failure offers the diagnostics report`。
- 当前 main `9bf57f6` 的 [CI 41450924663](https://github.com/BrainEno/flutter-blog/actions/runs/41450924663) 已完成，整体结论为 **failure**：format/test 失败，analyze/config/guardrails 成功；Android job 成功，其 release/debug 构建、INTERNET、16 KiB 和签名保护步骤均通过。
- 同一 main 的 [Read-aloud desktop compile checks 41450924643](https://github.com/BrainEno/flutter-blog/actions/runs/41450924643) 与 [Local development scripts and iOS build checks 41450924539](https://github.com/BrainEno/flutter-blog/actions/runs/41450924539) 已成功。
- 审查文档 PR #112 的 [CI 41454803554](https://github.com/BrainEno/flutter-blog/actions/runs/41454803554) 在复核时仍为 **test 失败**；format、analyze、config、guardrails、Android 构建及桌面/移动脚本检查通过。该结果说明文档分支本身也尚未满足全绿合并条件，而不是把 main 的红灯误记成已恢复。

GitHub 日志/artifact 下载曾返回远端 `EOF`；本次复核下载 PR #112 失败日志时再次得到相同错误。因此没有把 PR 的失败断言直接当成 main 的完整根因，也没有编造 main 或 PR #112 的堆栈。

### 未执行或不能宣称完成

- `flutter pub get`、正式 `dart format`、`flutter analyze`、`flutter test`、`flutter build`：本地命令不存在；仅引用上述 CI 的实际结果。
- 真机/模拟器、iOS 人工 UI、VoiceOver/TalkBack、deep link 冷/热启动：未运行。
- 生产或独立 no-wave 后端联调、PostgreSQL、secure storage 平台故障注入：未运行。
- 当前全量覆盖率、性能基准、依赖安全公告全量审计：未取得有效证据。
- 未修改数据库 schema、未迁移/清除用户数据、未向生产服务写入测试内容。

## 11. 总结

belog 的优势是**功能面广、分层清楚、对离线/错误/迁移和发布误配已有较多防御性设计**。它当前的主要弱点不是缺少更多页面，而是若干跨请求、跨存储和跨账号的边界仍靠局部约定维持；同时最新 main 的质量门禁已经变红。

最合理的下一步是：**先恢复 CI 与修复 bio 数据损失，再统一认证一致性和账号 fence，随后补 release 网络及体验缺口**。架构上保持现有 feature-first 方向、做小步解耦，通常比全仓重写更安全。
