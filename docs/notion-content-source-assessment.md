# Notion 作为第二个内容源：可行性评估与实施方案

> 状态：**评估稿（2026-11-05）**，尚未写任何实现代码。
> 目标：在现有 no-wave `apps/api` REST 后端继续可用的前提下，让同一个 App 也能读
> 一个 Notion 数据库里的文章。
> 结论前提：本文只依据仓库现有代码与 Notion 官方文档（`Notion-Version: 2026-03-11`）
> 推导；**没有**看到目标数据库的 schema（该库需要登录，见 §1.1），也没有真机实测。

## 0. 结论先说

1. **可行，但只能“只读 + 降级”地可行。** Notion 能提供标题、封面、标签、正文、
   发布时间这几样“文章”需要的东西；它提供不了评论、点赞、关注、回收站、服务端
   搜索排序、相关推荐、媒体上传这些 no-wave 侧的能力。所以这不是“换一个 API
   地址”，而是“让 App 接受一个能力更少的源”。
2. **不需要改 no-wave 的用法。** 现有 no-wave 路径可以一行不改地继续工作；新源
   作为第二个实现接在同一个领域接口后面。
3. **必须先在 App 里把“源”抽象出来，否则会写成一堆 `if (isNotion)`。** 现有代码
   有 8 处会把单一后端的假设硬塞进新功能里（§2），这些要先各自作为一个 PR 清掉。
4. **两个成本高但绕不开的点**：Notion 的图片是 1 小时过期的签名 URL（§1.2），
   以及 180 次/分钟的限流（§1.3）。两者都要求把“本地缓存 + 按需刷新”从附加
   功能升级为设计前提。
5. **最便宜的替代方案是先想清楚要不要“实时”**：如果 Notion 只是写作台、文章不常
   改，一个定时把 Notion 同步进现有后端的作业（§3 方案 0）比在 App 里加第二个源
   便宜一个数量级。三种形态的成本差距很大，先选形态再动手。

## 1. 先摆硬约束

### 1.1 这个数据库是私有的，token 是必需品

给到的链接 `https://app.notion.com/p/b1b40d23…?v=0aabeed6…` 打开后是 Notion 的
登录页（“Sign in to see this page”），说明它没有发布到公网。后果：

- 读取它**必须**带 Integration token（`Authorization: Bearer ntn_…`），并且要在
  Notion 里把该 integration 显式连接到这个数据库，否则 API 返回 404
  `object_not_found`。
- 我不能凭链接推断它的属性（property）名字和类型。**schema 需要你提供**（§7 Q4）。
- token 放哪里，直接决定架构（§3）：放进手机意味着“一台设备被拿到 = 这个库
  被读”；放进一个 serverless 函数意味着要部署和维护它。

### 1.2 正文和图片都不是“取一次就固定”的

- 页面正文要按 block 树取：`GET /v1/blocks/{block_id}/children`，单次最多 100 个
  block，嵌套 block（toggle / column / list）要逐层再取。一篇结构复杂的文章是
  **N+1 次请求**，不是 1 次。
- Notion 托管的文件（封面、正文里的图片）返回的是**签名 URL，约 1 小时过期**，
  官方明确要求“不要缓存或静态引用这些 URL，要刷新就重新取 file object”。
  现有模型把 `imageUrl` 当作不可变地址写进 SQLite（`blog_cache.image_url`），
  这个前提在 Notion 源上**不成立**：今天存下的图片地址，明天打开就是 403。
- 外部链接（`type: "external"`）不过期，但作者在 Notion 里贴的图默认是上传到
  Notion 的，属于上一种。

### 1.3 限流按分钟算，而且按连接算

- 非 Business/Enterprise 工作区：**180 请求 / 分钟**（平均 3/s），数据源查询另有
  约 3 rps 的独立限制；超限返回 429/529，`Retry-After` 最长可达 60 秒，还可能是
  “整个工作区共用的额度”被别人用完。
- 一次“冷启动打开首页并读一篇文章”大致是：1 次 query + 1 次块读取 × 文章层级数
  （10–30 次），如果开了预取会更快地用光预算。所以：**列表页不要抓正文，正文只在
  真正打开时抓，抓到的正文写进 SQLite，之后按 `last_edited_time` 判新旧。**

### 1.4 其他必须接受的事实

| 事实 | 影响 |
| --- | --- |
| `Notion-Version` 头是必填的，当前最新 `2026-03-11` | 必须显式钉版本；响应会“只增字段”，解析要忽略未知字段 |
| 页面链接格式变过（`notion.so/{id}` → `app.notion.com/p/{id}`，2026-06），官方说链接不是稳定标识 | 分享链接可以用，但**内部身份必须用 page id**，不能解析 URL 反推 |
| 游标（`next_cursor`）是不透明的，可能带会话信息 | 只能原样回传，不能解析、不能拼接、不能跨源复用 |
| `request_status.incomplete_reason` / 406 `row_limit_exceeded` | 列表可能是**不完整**的；App 必须能表达“这一页可能不全”，不能假装翻到底了 |
| 数据库可以是“多数据源”（multi-source），查询端点是 `/v1/data_sources/{id}/query` | 要先 `GET /v1/databases/{id}` 取 `data_sources[0].id`，不能直接把 database id 当 data source id 用 |
| 文件上传 API 存在（直传 ≤20MB，免费区 5MiB；上传 id 1 小时内必须挂到页面上） | 如果以后要“在 App 里写回 Notion”，封面/图片要走这条链路，成本不低 |

## 2. 现有代码里会卡住这个功能的 8 处（建议先各自清一个 PR）

**先说结论：GitHub 上唯一开放的 issue 是 #18（举报/屏蔽），它与本功能无因果关系，
不阻塞。** 真正会卡住的是下面这些“代码级 issue”，它们都没有编号，建议按顺序清：

### B1 领域契约里写着 no-wave 的类型

`lib/features/blog/domain/repositories/blog_repository.dart` 直接
`import 'core/nowave/nowave_session_fence.dart'`，`uploadBlog` / `editBlog` 的参数是
`NowaveSessionFence?`；`lib/features/user/domain/repositories/user_repository.dart`
同样。Notion 侧没有“会话代际”，实现方只能伪造一个假 fence —— 这正是抽象漏了的
信号。

- 清法：在 domain 里定义一个**不透明**的作用域类型（例如
  `domain/entities/write_scope.dart`，只是“这次写属于哪一次操作”的标识），
  no-wave 实现负责把 `userId + generation` 塞进去。#104 建立的语义（A→B 切换后
  第二步必须失败）保持不变，改的是“领域只认识一个不透明 token”。
- 风险：低（机械替换 + 现有 `user_edit_fence_test.dart` / `me_scoped_fence_test.dart`
  是回归网）。

### B2 启动时只允许一个后端

`lib/init_dependencies.dart` 在入口就要求 `API_BASE_URL`（缺失直接 `StateError`），
然后立刻构造唯一的 `NowaveApiClient`（:161）、唯一的 `NowaveSessionManager`，并在
:320 注册唯一的 `BlogRepository`。没有“内容源”这个概念，也没有“两个源都注册、
由谁激活”的机制。

- 清法：引入 `ContentSourceId`（`nowave` / `notion`）与一个
  `ActiveContentSource`；`env.json` 增加 `CONTENT_SOURCE`（默认 `nowave`，保持现有
  部署零变化）；DI 按源懒构造栈；`initDependencies` 只在“激活源是 no-wave”时
  强制要求 `API_BASE_URL`；`boot/startup_failure_app.dart` 的报错文案与
  `tool/ci/check_env_asset_contract.sh` 的契约一起更新。
- 风险：中（启动路径 + 脚本契约 + 诊断行 `describeApiOrigin` 都要跟着改）。

### B3 本地缓存的身份里没有“源”

`blog_cache` 的主键是 `(id, content_locale)`（`lib/core/storage/app_database.dart:139`，
schema v7），`reading_history` 是 `(user_id, blog_id)`；Notion 的 page id 和
no-wave 的 slug 撞车是迟早的事，而且“切换源之后离线还看到另一个源的文章”会直接
变成错误内容，不是过期内容。

- 好消息：`account_drafts` 已经有 `backend TEXT NOT NULL` 这一列
  （`sqlite_draft_store.dart:12,20` 用 API base URL 生成命名空间），照这个模式做
  就行。
- 清法：schema v8 给 `blog_cache`、`reading_history` 加 `source` 列并进主键/索引，
  老行迁移为 `nowave`；`BlogLocalDataSource`、`BlogFeedLoader`、点赞/收藏列表
  都带上 source。
- 风险：中（有先例的迁移，但涉及 SQLite 迁移测试与 `docs/sqlite-storage.md`）。

### B4 “文章 id” 同时是三样东西

`Blog.id` 是 no-wave 的 slug（公开寻址、深链、点赞）；`BlogModel.articleId` 是服务端
UUID（只用于更新）；`articleWebUrl()` 用 `WEB_BASE_URL` + `/articles/<slug>` 拼分享
地址；`article_deep_link.dart` 也只认 `nowave://article/<slug>` 和同源
`/articles/<slug>`。Notion 没有 slug，只有 page id，公开链接是
`app.notion.com/p/<id>`（而且官方说格式会变）。

- 清法：把“公开身份”升级为一个 `ArticleRef { source, id }`（或给 `Blog` 加
  `source` 字段）；分享/深链改成“按 source 解析”，Notion 用页面的 `url`
  （对外展示）而内部路由仍用 page id。
- 风险：中（跨了 router、share、深链、缓存四处，但都有现成测试）。

### B5 正文模型是 no-wave 的 block 版本

`Blog.document` 是 `ArticleDocument`（no-wave `contentBlocks` v0/v1，
`nowave_article_codec.dart` 解码），`Blog.content` 是旧的 Markdown/纯文本，
`viewer_article_body.dart:87/103` 在 `document == null` 或 `supported == false` 时
退回 `MarkdownBody(blog.content)`。

- 这条其实是**好消息**：Notion → Markdown 是一条现成的路，且
  `read_aloud_document.dart.` 的朗读就是基于 Markdown AST 的，所以“Notion 文章可朗读”
  自动成立。真正要新写的是 `Notion blocks → Markdown` 的转换器（以及未知 block
  类型的显式降级）。
- 如果以后要更好的排版保真，再写 `Notion blocks → ArticleDocument`（新增一个
  `version` 语义），属于第二阶段。
- 另外 `plainEditorCompatible` / 编辑器写入是 no-wave 专属：读到 Notion 文章时编辑器
  必须“明确不可编辑”，不能靠报错。

### B6 一堆能力在 Notion 侧没有对应物，而 UI 现在假设它们都在

评论（`CommentRepository`）、点赞（`ArticleLikeStore`，服务端状态读改写）、关注/粉丝、
回收站/恢复、服务端搜索与排序（featured/popular/following 三个 `BlogFeedKind`）、
相关推荐、媒体上传、草稿（服务端）。`lib/router/app_router.dart:89` 的保护前缀是
`['/saved', '/profile', '/editor']`，这些页面在 Notion 源下要么隐藏、要么改成“本地
收藏”。

- 清法：加一个**能力声明** `ContentSourceCapabilities`（comments / likes / follows /
  drafts / recycleBin / related / serverSearch / mediaUpload / editor），UI 与路由按
  能力渲染入口，不支持时是“这项功能在当前内容源不可用”的说明，而不是一个会失败的
  按钮。
- 风险：中（碰很多页面），但可以按页面分批做。

### B7 连接探测、诊断、分享都写死了 no-wave 的地址形状

`api_connection_checker.dart:22` 的探针是 `API_BASE_URL + /api/v1/health`；
`api_origin_report.dart` 打印“这个二进制在跟哪个后端说话”；分享用 `WEB_BASE_URL`。
Notion 没有 `/health`（可以用 `GET /v1/users/me` 代替），也没有“web 文章页”，分享
应该用页面自己的 `url`。

- 清法：把探针抽象成 `BackendProbe`（每源一个实现），诊断行带 source 名，分享
  地址由源提供。

### B8 密钥通路是“编译期常量”

`AppSecrets` 用 `String.fromEnvironment`，env.json 会被编进包里，`test/unit/core/
app_secrets_define_test.dart` 还专门钉住了这个契约。**Notion token 绝不能走这条
路**：一旦编进 release 包，等于把“能读你整个库”的凭据发给每一个安装包。

- 清法：token 运行时输入 → `flutter_secure_storage`（项目已有 `SecureNowaveSessionStore`
  与 `ResilientNowaveSessionStore` 的实现范式可抄），设置页里明确说明“这个 token
  能读到什么、存在哪里、怎么撤销”；再加一条 CI 守卫：仓库里出现 `ntn_` / `secret_`
  形态的字符串直接失败。
- 风险：低，但 UI + 文案 + 守卫是新工作。

**顺序建议**：B1 → B2 → B3 →（B7 + B4）→ B6 → B8。B5 是功能实现的一部分，不是前置。
B1/B2/B3 是真正的地基，越晚做越贵。

## 3. 三种形态：先选形态，再谈实现

| | 方案 0：定时同步进现有后端 | 方案 A：App 内第二个只读源（推荐起步） | 方案 B：serverless 适配层，代理 Notion | 方案 C：在 App 里直接写回 Notion |
| --- | --- | --- | --- | --- |
| 一句话 | 一个 cron 把 Notion 拉进 no-wave/SQLite，App 完全不动 | App 新增 `NotionBlogRepository`，token 存在设备安全存储里 | 一个 Cloudflare Worker/网盘函数，对 App 说 `/api/v1`，对 Notion 说 REST | App 里编辑 → Notion 页面/块写入 |
| App 改动 | 0 | 中（本文 §2 全部 + §4） | 小（只需要 B2/B4 的“源”概念，甚至可为零） | 大（B5 的正向写入 + 冲突处理） |
| 需要额外运维 | 一个 cron（已有 Actions 可以顶） | 无 | 一个函数 + 一个密钥 + 一份监控 | 同左 |
| 实时性 | 分钟~小时级延迟 | 实时 | 实时 | 实时 |
| token 暴露面 | 只在服务端 | **在设备上** | 只在服务端 | 只在服务端 |
| 能支撑写/评论 | 否 | 否 | 视实现 | 是（但要处理块级冲突） |
| 主要风险 | 双份真相、同步冲突 | 限流与 1 小时图片、离线语义 | 多维护一个服务，且要跟 no-wave 契约保持兼容 | 成本最高，Notion 写入 API 的坑很多 |
| 适合 | Notion 只是写作台、不常改 | 个人自用、单设备/自带 token | 多设备、想隐藏 token、以后要写 | 只有明确需要“在 App 里发文章到 Notion” |

**我的建议**：

- 如果目标只是“我自己在 Notion 写，App 里能看到” → **方案 A**（配合 B1/B2/B3 的地基），
  并且**先不要**做 §4 的第二阶段。
- 如果希望多台设备共享、或者不想把 workspace 级 token 放在手机上 → **方案 B**，
  但要在仓库里给它一个位置（例如 `serverless/notion-proxy/`）、一套契约测试，并接受
  “以后多一个要部署的东西”。
- “在 App 里写到 Notion”（方案 C）建议明确**不做**，至少不在前两期；它与现在的
  “发布即创建文章”流程、草稿自动保存、封面媒体上传全都要重新设计一遍。

## 4. 方案 A 的分期实施（每个 PR 都能单独合并、单独验收）

### P0 地基（3–4 个 PR，先把 §2 清掉）

1. **P0-a**：B1 领域契约去 no-wave 化（`WriteScope`），语义不变、测试不改断言。
2. **P0-b**：B2 内容源抽象与 `CONTENT_SOURCE` 配置；no-wave 行为零变化（默认值）。
3. **P0-c**：B3 缓存/阅读历史/点赞列表加 `source` 维度（schema v8 + 迁移 + 测试）。
4. **P0-d**：B7 探针/诊断/分享按源；B4 的 `ArticleRef`（可拆成两个小 PR）。

### P1 只读 Notion 源 MVP（3 个 PR）

1. **`NotionClient`**：`Notion-Version: 2026-03-11` 固定；429/529 按 `Retry-After`
   退避重试（上限固定、不无限重试）；游标原样回传；错误映射成现有
   `ServerException` + 稳定 code（`notion.unauthorized` / `notion.not_found` /
   `notion.rate_limited` / `notion.incomplete`）；忽略未知字段。单测用本地 JSON 固定
   样本，不打真网。
2. **`NotionSchema`（可配置映射）**：property 名 → 字段（标题、Slug、标签、状态、
   发布日、封面、摘要、作者）。默认值给一套约定，但**必须可覆盖**，因为我们还不知道
   你那张表的属性名。多数据源数据库要先 `GET /v1/databases/{id}` 取 data source id。
3. **`notion_blocks_to_markdown`**：paragraph/heading/list/quote/code/callout/toggle/
   divider/image/link_to_page/bookmark/table 的映射；未知类型输出显式占位而不是
   静默丢弃；图片输出占位 + 记录 block id（用于刷新签名 URL）；嵌套深度设上限。
4. **`NotionBlogRepository`**：只实现 feed / 详情 / 搜索（可选）；其余方法返回
   `Failure(code: 'source.unsupported')`，并由 B6 的能力声明让 UI 根本不展示。
5. **设置页 + 安全存储**：粘贴 token → 校验（`GET /v1/users/me`）→ 存
   `flutter_secure_storage`；显示“当前源 / 可读范围 / 撤销方法”；错误状态明确
   （未授权 / 数据库未连接 integration / 限流）。

### P2 打磨（2–3 个 PR）

- 标签页与“同标签推荐”（本地按 tag 过滤，不调用服务端 related）。
- 分享链接用页面 `url`；深链支持 Notion 页（`nowave://article/<pageid>`？——需要与
  B4 的 `ArticleRef` 一起定，别急着改 scheme）。
- 图片：要么每次打开详情时刷新签名 URL（简单、多请求），要么把图片抓进本地缓存
  （省请求、占磁盘）；两者都要处理“URL 过期 → 占位图 + 重试”的路径。
- 列表“可能不完整”的提示（`incomplete_reason` / 406）。
- 文档：本文件升级为 ADR + 更新 `README`、`docs/nowave-api-gap-audit.md` 的定位
  （后者从此只描述 no-wave 源）。

### P3 可选（1–2 个 PR）

- 方案 B 的 serverless 适配层：如果以后要多设备或隐藏 token。
- 写回 Notion：单独评估，不在本轮。

## 5. 数据映射表（方案 A）

| Notion | 领域字段 | 备注 |
| --- | --- | --- |
| `page.id`（UUID） | `Blog.id`（+ `source=notion`） | 稳定标识；深链/缓存/阅读历史都用它 |
| title property | `title` | 富文本，取 plain text |
| `Slug`（自定义 property，可选） | 分享用 slug | 没有就用 page id；不要从 title 派生后写回 |
| `Tags`（multi-select） | `tags`（名称列表） | 无需服务端 slug；标签页在本地聚合 |
| `Published`（date）或 `last_edited_time` | `updatedAt` / 排序键 | 用哪个要定；两者都存，排序用前者兜底后者 |
| `Status`（select） | `isDraft` | `draft` 不进公开列表（与 no-wave 语义对齐） |
| 页面 `cover` / `files` property | `imageUrl` | **1 小时签名 URL**：只作“当次可读地址”，不持久化为唯一真相 |
| 正文 block 树 | `content`（Markdown） | `document` 留 null，走现有 Markdown 渲染 + 朗读 |
| `created_by` / 配置常量 | `posterId` / `posterName` | 单作者库可以用固定值；多作者库映射 Notion user |
| `page.url` | 分享地址 | 只用于展示/分享，不作为身份 |

## 6. 验收方式（沿用仓库现有习惯）

- 单测：`NotionClient` 的重试/错误映射/游标、`NotionSchema` 属性解析（含缺属性、
  类型不符）、`notion_blocks_to_markdown`（固定 JSON 样本 + 未知 block）、
  capability 门控、token store 的读写与清除。
- widget 测试：Notion 源下首页/详情/分享/设置页；不支持的入口不可见或显示说明；
  图片 URL 过期后的占位与重试。
- 结构守卫：`test/unit/core/layering_test.dart` 增加“`features/notion` 不得 import
  `core/nowave`”（除非走接口），`service_locator_registration_test.dart` 会强制新
  类型都被注册；再加一条“仓库里没有 Notion token 形态字符串”的扫描。
- 真实网络验证：**无法在本仓库 CI 里做**（需要真 token 与真库）。这一条只能由所有者
  在本机跑，需要写进 PR 说明，不能假装验证过。

## 7. 需要你先决定的四件事

1. **形态**：Notion 只是“写作台”，还是要“多设备 / 隐藏 token / 以后能在 App 里写”？
   → 决定走方案 0 / A / B。
2. **写入**：App 里发布文章要不要落到 Notion？（做 = 方案 C，成本翻倍）
3. **两个源的关系**：App 内可切换（现在这个 App 一个源），还是“no-wave 为主、
   Notion 为辅”同时出现（这会让缓存分区与 UI 能力声明变成必需，而不是可选）。
4. **我需要这个数据库的 schema 才能写出准确的映射**：属性名 + 类型（标题/标签/日期/
   状态/封面/摘要/作者），最好再给一篇样张页面的 blocks JSON（脱敏即可）。
   注意：**不要把 token 贴给我**——按 §2 B8 的设计，token 只应存在于你的设备
   或你自己的部署环境里。

## 8. 明确不做 / 不能做的

- 不在文档或代码里内联 token，也不通过 `env.json`/`--dart-define` 传递。
- 不解析 Notion 自己的页面链接来推身份（官方说明链接格式会变）。
- 不假装 Notion 源支持评论/点赞/关注/回收站；这些要么隐藏，要么是“本地”实现，
  且必须与 no-wave 的“服务端真值”区分开。
- 不在第一阶段做 Notion 写入、媒体上传、块级冲突合并。
- 不把 `#18`（举报/屏蔽）当作本功能的前置——它需要 no-wave 侧先有接口，与内容源
  抽象无关；但它的存在提醒：能力矩阵里必须能表达“这个源没有这个功能”。
