# Supabase → no-wave apps/api 迁移核对文档

> 原始目标：`github.com/BrainEno/no-wave` `apps/api`，2026-10-29 的迁移核对与设计记录。
> **2026-10-31 增量复核**：[no-wave `55a24bd`](https://github.com/BrainEno/no-wave/tree/55a24bdaa1c01888fb5ecb5bf41befe219348049)；下方「当前状态」优先。其后的逐接口表保留了迁移前调用点与设计背景，不是全部部署或验收清单；不应据此推断新代码已经上线。

### 2026-10-31 当前状态与修正

- G1：软删、回收站、恢复已实现并接入 App；服务端过期清扫由写入触发，不能保证准时清除。
- G2：服务端已有 `POST /auth/forgot-password`、`POST /auth/reset-password`、`POST /auth/verify-email`、`POST /me/email-verification`，可配置 SMTP；邮件默认关闭，实际部署和投递未验证。App 仍没有忘记密码、验证、重发及邮件链接处理界面；当前也没有改邮箱或登录态下直接改密码的接口。注册后可立即登录，邮箱验证不是登录/发布门槛。
- G3：`GET /me` 可包含邮箱与验证状态；App 目前只用 id，账号页邮箱依旧来自本地缓存，未与服务端资料同步。
- 媒体：每次上传产生独立资产，尚无服务端幂等或完整孤儿回收；本客户端封面及头像不对连接失败或超时自动重发。断流时写入结果可能未知，手动重试仍可能重复。明确的 401 经刷新后的单次请求重放保留。
- 截至该快照，上传响应的 `src` 与实际媒体路由仍不一致；客户端继续根据 id 构造版本化 URL。部署状态、真实邮件投递及生产数据不在本核对范围。

## 0. 结论先行：能否直接迁移

核心博客的读写、搜索、互动、作者资料和媒体已接入 no-wave；账号安全等仍有客户端或服务端缺口，不能视为全部迁移完成：

| # | 当前状态 | 影响 | 后续 |
|---|----------|------|------|
| G1 | 服务端软删、回收站、恢复已实现，App 已接入 | 删除和恢复文章 | 清扫由写入触发，需单独解决准时回收 |
| G2 | 服务端已有密码重置、邮箱验证和重发验证；修改邮箱和登录态直接改密未提供 | App 缺少对应界面与邮件链接处理 | 先修复和验证服务端身份/邮件流程，再设计安全的 App 接入；不假装已完成 |
| G3 | `GET /me` 可返回 email 和验证状态，App 目前只读取 id | 账号页仍显示登录时本地缓存的邮箱 | 若要同步，需明确兼容旧部署和本地缓存策略 |

下面的调用点和实施顺序包含迁移前设计记录；与「当前状态」冲突时以上方快照结论为准。

---

## 1. no-wave apps/api 契约速览（已核对源码）

- Node + TypeScript，REST 独占：所有业务端点在 `/api/v1/*`（`handleRest` 强校验前缀，其余 404）。
- 健康检查：`GET /health`、`GET /ready`（无版本前缀）。
- 请求体规则：写操作必须 `Content-Type: application/json`、≤2MiB、**未知字段直接 400 拒绝**（requireOnly）。
- 错误统一格式：`{"error":{"code","message"}}`；域错误映射 BAD_USER_INPUT→400 / FORBIDDEN→403 / NOT_FOUND→404 / CONFLICT→409 / UNAUTHENTICATED→401 / RATE_LIMITED→429（带 `Retry-After` 头）。
- 限流：写操作按 用户+IP 双桶；register 20/IP/h、login 60/IP + 5/email/窗口。
- locale：写入仅支持 `zh-CN`（body/query 传其他值一律 400）；读取默认 zh-CN。
- 响应包一层 `{data: ...}`，列表无分页 meta（用 `limit/offset`，是否还有下一页由「本页条数==limit」判断）。

### 1.1 认证（已核对 application/identity.ts、transport/rest/http.ts）

| 端点 | 请求 | 响应 |
|------|------|------|
| `POST /auth/register` | `{email,password}`（**仅此二字段**；密码注册时 ≥12 ≤128 字符；email 小写化+严格格式校验） | `{data:{accessToken, tokenType:"Bearer", accessExpiresAt, refreshToken, refreshExpiresAt}}` |
| `POST /auth/login` | `{email,password}`（密码 ≥1） | 同上 |
| `POST /auth/refresh` | `{refreshToken}` | 同上（**轮换**：旧 refresh 一次性作废；**重用即撤销整个会话族**） |
| `POST /auth/logout` | `{refreshToken}` | `{data:{ok:true}}` |
| `DELETE /me/session` | — | 撤销当前会话族（含仍有效的 access token：JWT 内嵌 sessionId，服务端每请求查撤销表） |
| `GET /me` | Bearer | `{data:{id,email,emailVerifiedAt}}`（后两项可为空） |
| `POST /auth/forgot-password` | `{email}` | 邮件开启时返回 202，避免枚举账号 |
| `POST /auth/reset-password` | `{token,password}` | 单次 token 重置密码 |
| `POST /auth/verify-email` | `{token}` | 单次 token 验证邮箱 |
| `POST /me/email-verification` | Bearer | 邮件开启时请求或重发自己的验证邮件 |

- accessToken 为短时效 JWT（`config.ttlSeconds`），`Authorization: Bearer <jwt>`。
- 公开读端点可带可不带 token；带错 token 不报错只降级为匿名 viewer。
- 邮箱验证、忘记/重置密码、重发验证已有服务端代码；客户端未接入。邮件默认关闭。当前无修改邮箱或登录态下直接修改密码的端点。

### 1.2 资料（profile）

- `GET /me/profile` → `{data:{userId,displayName,bio,avatarUrl,websiteUrl,locale,followerCount,followingCount,isFollowing,createdAt,updatedAt}}`。
- `PUT /me/profile` body 仅允许 `{displayName(必填,≤120), bio?, avatarUrl?, websiteUrl?, locale?}`；avatarUrl 允许站点相对路径或 http(s)。
- `GET /authors/:userId`（path 参数名为 username 但实际是**稳定 userId/UUID**，README 的 userId 说法正确）→ 作者档案（含计数、viewer 的 isFollowing）。

### 1.3 文章

对象形状（store mapArticle + serializeRestArticle 展开，camelCase）：

```jsonc
{
  "id": "uuid", "authorId": "uuid", "slug": "…", "workType": "other",
  "status": "draft|published", "locale": "zh-CN",
  "title": "…", "summary": "…", "contentBlocks": [ … ],
  "contentBlocksVersion": 0, "createdAt": "ISO", "updatedAt": "ISO", "publishedAt": "ISO|null",
  "author": { …profile… }, "categories": [ … ], "tags": [ {id,kind,slug,name,description,locale,createdBy,articleCount} ]
}
```

| 端点 | 说明 |
|------|------|
| `GET /articles?locale&query&limit(1-100,默认20)&offset` | 已发布列表 + 全文搜索（trigram，title/summary），viewer 可选 |
| `GET /articles/:slug?locale` | 公开详情（**只能按 slug**，无按 id 的公开读） |
| `GET /me/articles?locale&limit` | 自己的文章（含草稿） |
| `GET /me/liked-articles?locale&limit` | 收藏列表 |
| `GET /articles/:slug/like?locale` | `{data:{articleId,slug,likeCount,likedByViewer}}` |
| `PUT /articles/:slug/like` body `{liked:bool}` | **显式置态**（非 toggle），返回新的 likeInfo |
| `POST /articles` | body 字段白名单：`slug?,title,summary?,locale?,contentBlocks|editorState(二选一),contentBlocksVersion?,publish?,workType?,categoryIds?,tagIds?`。**slug 可省略**：从 title 自动生成，冲突自动加去重后缀。201 返回序列化文章 |
| `PUT /articles/:articleId` | path 参数是 **articleId(UUID)**；body **必须**含 `slug`（当前或新 slug）与 `publish`(bool)，其余同 POST。**只能改自己的**（actor 校验） |
| `GET /articles/:slug/comments`、`/related` | 评论与相关阅读已接入客户端 |
| `DELETE /articles/:articleId`、`POST /articles/:articleId/restore` | 软删与恢复已接入客户端 |

- `title` ≤250；`summary` ≤2000（省略或空 → 服务端从正文自动摘要）；`contentBlocks` 1–200 块。
- `workType` 枚举：`novel, short_story, poetry, essay, criticism, literary_criticism, nonfiction, serial, other`（可省略 → other）。博客的「诗歌/小说」等标签语义上接近，但按标签走 tags 即可，workType 固定省略。
- **双轨寻址**：公开读按 slug，更新按 articleId。二者都会在 `GET /me/articles` 与 `POST/PUT` 响应中同时返回。

### 1.4 contentBlocks（v0 纯文本足够本 App）

- v0 块类型：`paragraph / heading / quote / list / image / code`。
- 最简单映射（App 正文是纯文本字符串）：按空行/换行切分为若干 `{type:"paragraph", text:"…"}` 块；封面用 `{type:"image", src, alt, caption?}`（src ≤2048，http(s) 或站内相对；alt ≤1000）。
- v1 才有 inline marks/links，本 App 不需要，`contentBlocksVersion` 固定 0（省略亦可）。

### 1.5 媒体（已核对 application/media-assets.ts）

- `POST /me/media`（Bearer）：**请求体就是图片原始字节**，MIME 放 `Content-Type` 头。服务端统一**重编码为 WebP**（压缩、裁剪元数据），存对象存储。
  响应 201：`{data:{id, src:"/api/media/<id>", contentType:"image/webp", byteSize, width, height}}`。
- `GET /api/v1/media/:id`：immutable + ETag/304（**路由测试确认带 v1 前缀**；上传响应里的 `src` 少了 `/v1` 段，属上游不一致 —— 客户端应自拼 `$apiBase/api/v1/media/$id`，勿直接用 src。建议顺手在 no-wave 修掉）。
- **无删除媒体端点**，资产不可变（每次上传新 id）；服务端孤儿回收尚未完成。App 不提供版本化路径或孤儿回滚；遇连接失败不自动重发非幂等上传。

### 1.6 标签/分类

- `POST /tags` body `{name, locale?}` → **create-or-reuse**（同名归一化后复用），201 返回 `{data:{id,kind:"tag",slug,name,…}}`。中文没问题：displayName 保留 Unicode，slug 自动生成为 `tag-<sha256前16位>`（ASCII stem 为空时）。
- `GET /tags?locale&query&limit&offset`、`GET /tags/:slug`、`GET /tags/:slug/articles?locale&limit&offset`。
- 文章写入用 `tagIds`（UUID 数组）—— 客户端需「按名解析或创建 → 拿 id」。
- 分类（categories）同理，本 App 用不上。

---

## 2. 调用点逐项核对（flutter-blog → no-wave）

### 2.1 `AuthRemoteDataSource`

| 现有方法（Supabase） | no-wave 对应 | 迁移判定 |
|---|---|---|
| `signUpWithEmailPassword(name,email,password)` | `POST /auth/register {email,password}` → 拿到会话后 `PUT /me/profile {displayName:name}` 补写名字 | ✅ 已迁移。注册即登录，验证邮箱不是前置条件；**密码最短 12 位**，客户端已同步校验。 |
| `loginWithEmailPassword` | `POST /auth/login` | ✅。返回无 user 对象：id 从后续 `GET /me` 拿，或解析 JWT（推荐前者） |
| `currentUserSession` / 会话恢复 | 本地 secure storage 存 `{accessToken,refreshToken,…}`；恢复时 `GET /me` 验活 | ✅。需自建 `TokenSessionManager`：401 时单飞刷新（`POST /auth/refresh`），**refresh 单次有效且轮换**，并发请求必须共享一次刷新，拿到新对后原子替换；刷新失败（重用被撤族）→ 清会话登出 |
| `resendConfirmationEmail` | `POST /me/email-verification` | 服务端已有，客户端未接入；邮件默认关闭 |
| `sendPasswordResetEmail` | `POST /auth/forgot-password`、`POST /auth/reset-password` | 服务端已有，客户端未接入；需先修复并验证完整流程 |
| `logout` | `POST /auth/logout {refreshToken}`（撤销 refresh）+ 可选 `DELETE /me/session`（连 access 一起撤） | ✅。推荐登出即 `DELETE /me/session` + 本地清 token |
| `getCurrentUserData` | `GET /me`（拿 id）+ `GET /me/profile`（拿档案） | ⚠️ G3：当前 `/me` 可返回 email 和验证状态，App 仍使用登录/注册时的本地缓存；name ← displayName |

旧 Supabase 邮件回调已下线；no-wave 的邮件链接处理尚未接入客户端，需与界面和可信站点/深链配置一并设计、验证。

### 2.2 `BlogRemoteDataSource`

| 现有方法（Supabase） | no-wave 对应 | 迁移判定 |
|---|---|---|
| `uploadBlog` | ① 有封面则 `POST /me/media` → asset；② tag 名单逐个 `POST /tags`（create-or-reuse）→ tagIds；③ `POST /articles {title, contentBlocks:[image?,paragraphs…], tagIds, publish:true, locale:"zh-CN"}`（slug 省略走自动生成） | ✅ 可迁移（模型适配见 §3） |
| `uploadBlogImage` | `POST /me/media`（原始字节 + Content-Type）→ 存 `$apiBase/api/v1/media/$id` | ✅。服务端转 WebP；无需客户端版本化路径 |
| `removeBlogImage` | 无删除媒体端点 | 客户端无回滚；孤儿和重复资产仍需服务端回收方案 |
| `getAllBlogs(page)` | `GET /articles?limit=kBlogPageSize&offset=(page-1)*size` | ✅。「还有更多」= 本页条数==limit |
| `getBlogById(id)` | `GET /articles/{slug}` | ⚠️ 寻址改 slug：见 §3.3 |
| `getBlogsByPosterId` | `GET /authors/{userId}/articles?limit&offset` | ✅（含草稿吗：此端点列已发布；自己草稿走 `GET /me/articles` —— 现有 App 本就只显示已发布，等价） |
| `getBlogsByTag(tag)` | `GET /tags?query=<名>`（或全量 `GET /tags` 后本地匹配）→ `GET /tags/{slug}/articles` | ✅（两跳；slug 无法本地推导，必须先解析） |
| `searchBlogs(query)` | `GET /articles?query=<q>&limit=kMaxSearchResults` | ✅。trigram 全文检索，语义优于现在的 ilike |
| `editBlog(blog)` | `PUT /articles/{articleId}` body **必须含** `{slug(当前或新), publish:true, title, contentBlocks, tagIds?, summary?, workType?}` | ✅（需 BlogModel 存服务端 articleId + slug） |
| `deleteBlog(id)` | `DELETE /articles/{articleId}`（墓碑软删，200 返回 `{id, deletedAt}`；地址是服务端 UUID 非 slug） | ✅ 已接入（缓存/远端解析 UUID，成功后清除本地缓存行）。配套：`GET /me/articles/deleted`（回收站，含 `purgesAt`）与 `POST /articles/{id}/restore?locale=`（恢复为草稿） |
| `getUserLikedBlogs(userId)` | `GET /me/liked-articles?limit=100` | ✅（只能看自己的，现有调用即当前用户，等价） |
| `toggleLikeBlog(userId,blogId)` | `PUT /articles/{slug}/like {liked:!当前态}` → 响应即新状态 `{likedByViewer,likeCount}` | ✅。改造为「读当前态（可来自 UI 缓存）→ 显式置反」，响应为准回写 |
| `isBlogLikedByUser(userId,blogId)` | `GET /articles/{slug}/like` → `likedByViewer` | ✅ |

### 2.3 `UserRemoteDataSource`

| 现有方法（Supabase） | no-wave 对应 | 迁移判定 |
|---|---|---|
| `getUserById` | `GET /authors/{userId}` | ✅。name←displayName，website←websiteUrl，email 空（G3 本地缓存） |
| `uploadAvatar` | `POST /me/media` → `PUT /me/profile {avatarUrl: mediaUrl}` | ✅ |
| `removeAvatar` | 无删除媒体端点 | ➖ 不再需要 |
| `editUserInfo` | `PUT /me/profile {displayName, bio:"", avatarUrl, websiteUrl}` | ✅。注意 body 白名单不含 email/updated_at（服务端自管） |
| `changeEmail` | 无端点 | ❌ G2 |
| `changePassword` | 无端点 | ❌ G2（顺带失去「改密后撤其他会话」能力；no-wave 有 `DELETE /me/session` 可配合将来实现） |

### 2.4 其余接触点

| 文件 | 现状 | 迁移 |
|---|---|---|
| `init_dependencies.dart` | `Supabase.initialize(url,anonKey)` 注入 client | 改为注入自建 `NowaveApiClient`（baseURL + TokenSessionManager）；移除 supabase_flutter 依赖 |
| `core/secrets/app_secrets.dart` | SUPABASE_URL/ANON_KEY | 改 `API_BASE_URL` 单值（无 anon key 概念）；`env.example.json` 同步 |
| `core/utils/storage_objects.dart` | Supabase Storage 路径/URL 工具 | 整文件删除（连同两个桶常量） |
| `core/error/error_mapper.dart` | PostgrestException/StorageException 映射 | 重写为 no-wave 错误码映射（`error.code`：BAD_USER_INPUT/UNAUTHENTICATED/FORBIDDEN/NOT_FOUND/CONFLICT/RATE_LIMITED(读 Retry-After)） |
| `retry_on_connection_closed` | 旧迁移方案中的连接重试 | 只对有安全重试契约的调用使用；媒体 POST 遇断流不得盲重试 |
| 本地 SQLite 博客缓存（lib/core/storage/） | 键为 UUID | 需加列/字段 `slug`（及 contentBlocks 原文可选）；缓存刷新逻辑不变 |
| `auth_session_sync.dart` | 监听 Supabase auth 状态流 | 改为监听自建会话管理器的状态流（登录/登出/刷新失败三态） |

---

## 3. 模型适配设计（迁移实现要点）

### 3.1 Blog 内容 ↔ contentBlocks

- **写**：`Blog.content`（纯文本）按换行切段 → `[{type:"paragraph",text}…]`；封面图（现 `imageUrl`）→ 首块 `{type:"image",src:mediaUrl,alt:title}`。`contentBlocksVersion` 不传（默认 0）。
- **读**：`contentBlocks` 中 image 块（取首个）→ `BlogModel.imageUrl`；paragraph 块 join("\n\n") → `content`。quote/heading 等块按文本降级拼入 content。
- `summary`、`workType` 不由 App 管理（服务端自动摘要 / 默认 other）。

### 3.2 tags ↔ tagIds

- **写**：`Blog.tags`(中文串) → 逐个 `POST /tags {name}`（幂等 create-or-reuse）→ 收集 `tag.id` → `tagIds`。建议 App 内做内存缓存 name→tag 对象，避免每次发表重复请求。
- **读**：文章响应 `tags:[{name,…}]` → `BlogModel.tags = names`。
- **按标签浏览**：`GET /tags?query=` 解析 slug → `GET /tags/{slug}/articles`。

### 3.3 ID / slug 双轨

- `BlogModel` 增加 `slug` 与 `articleId` 两个字段：对外路由/详情/点赞用 `slug`，编辑用 `articleId`。
- 导航层 BlogViewerPage 目前以 `id` 传参 —— 改传 `slug`（`/view/:slug`），或保持 id=articleId 并在跳转前查缓存换 slug。**推荐直接改传 slug**，公开 URL 也更友好。
- 本地缓存主键改用 `slug`（或双键索引）。

### 3.4 会话管理器（新组件）

- 存储：flutter_secure_storage（iOS Keychain / Android Keystore 加密存储，issue #46）存 `{accessToken, accessExpiresAt, refreshToken, refreshExpiresAt, userId, email}`。旧版曾落在 SQLite `metadata` 表，启动时由 `migrateSessionStoreToSecureStorage` 一次性迁入安全存储并删除旧行；迁移失败（安全存储不可用）保留 SQLite 兜底，下次启动重试。
- 请求封装：统一加 Bearer；认证请求前先经 `ensureFreshAccess`（廉价时间比较，access 距过期不足 30s 才单飞轮换，省掉每个过期点的 401 往返，issue #48）；仍遇 401 → 单飞 `POST /auth/refresh` → 重放原请求一次。
- 刷新失败语义：仅当后端明确拒绝（401/UNAUTHENTICATED，即会话族被撤销）才清储并广播登出；网络/超时/5xx **保留会话**，由 401 路径兜底。refresh token 本身已过期时本地直接登出，不发网络请求。
- 启动恢复：本地有对 → `GET /me` 校验 → 失败尝试刷新一次。
- 注意并发：refresh 轮换下**绝不能并发刷新两次**（第二次会因重用旧 token 撤销全家）。

### 3.5 UI/文案变更

- 注册页密码规则 6 位 → **12 位**（服务端硬校验，客户端同步前移）。
- 「邮箱验证」「忘记密码」「重发邮件」入口：G2 决策前先隐藏。
- 账号安全页（改密码/改邮箱）：同上。
- 删除博客入口：已接入——我的文章页长按删除（确认弹窗），AppBar 进入回收站（恢复/查看剩余保留天数）。
- 封面图说明：上传后服务端转 WebP（体积更小），无需改动选择器；现有 imageQuality 压缩可保留亦可移除（服务端会再压）。

---

## 4. 差距清单汇总（按处置分组）

**A. 已接入核心功能**：登录/注册/登出/会话恢复、博客 CRUD 与恢复、搜索、标签、点赞、收藏、作者页、头像、资料编辑；部署和所有异常场景另需验证。

**B. 需 no-wave 加端点（建议先做）**：
1. ~~`DELETE /articles/:articleId`（G1）~~ 已落地（no-wave #100/#101）：软删墓碑 + 回收站 + 恢复 + `ARTICLE_TOMBSTONE_RETENTION_DAYS` 过期清扫（默认 30 天）。
2. 修改邮箱、登录态直接改密仍缺端点；密码重置和邮箱验证已有服务端代码，但需完善并验证，再接入 App（G2）。

**C. 需 no-wave 修的小问题（顺手）**：
1. `POST /me/media` 响应 `src` 缺 `/v1` 段（与 `GET /api/v1/media/:id` 不一致）。
2. `GET /me` 已可返回 email（G3）；App 尚未使用该字段同步本地缓存。

**D. App 侧未接入项**：no-wave 邮箱验证/重置链接处理、媒体孤儿回滚、直接修改邮箱/密码。Supabase 依赖和旧存储版本化逻辑已移除；没有客户端回滚不代表服务端不会产生孤儿。

---

## 5. 原迁移实施顺序（历史记录）

1. **决策 G1/G2**（本文件 §0）—— 决定是否先动 no-wave。
2. App 侧搭 `NowaveApiClient` + `TokenSessionManager` + 错误映射（不动 UI）。
3. 数据层逐接口替换（§2 表顺序：auth → blog 读 → blog 写 → user），每步跑现有 widget/unit 测试（mock 数据源改 no-wave 形状）。
4. 模型与缓存迁移（slug/articleId、contentBlocks 适配器、tags 解析缓存）。
5. UI 文案与入口调整（密码 12 位、隐藏 G1/G2 缺口入口）。
6. `env.example.json`、README、CI（如涉及 secret）同步更新。
