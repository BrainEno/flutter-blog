# Supabase → no-wave apps/api 迁移核对文档

> 状态：核对完成，结论见「能否直接迁移」。
> 目标后端：`github.com/BrainEno/no-wave` `apps/api`（main 分支，核对日期 2026-10-29）。
> 核对方式：逐文件阅读 apps/api 源码（路由表、bodies、identity、media-assets、article/taxonomy/profile/engagement store、server.ts），
> 并与 flutter-blog 全部 Supabase 调用点逐一比对。所有结论均出自源码，非 README 推测。

## 0. 结论先行：能否直接迁移

**核心博客功能可以直接迁移**（读、写、搜、标签、点赞、收藏、作者页、头像、资料），
但 **3 个功能在 no-wave 现有 API 上没有对应端点，属于硬缺口**，需要先决策：

| # | 缺口 | 影响的 App 功能 | 处置选项 |
|---|------|----------------|---------|
| G1 | 无 `DELETE /articles/:id`（路由表 `articles.item` 仅 GET/PUT） | `deleteBlog`（我的博客页删除文章） | A. 先在 no-wave 加端点（推荐，改动小：owner 校验 + 软删/硬删 + taxonomy 清理已有事务样板）；B. 迁移时暂时隐藏删除入口 |
| G2 | 无任何账号安全端点：无改密码、无改邮箱、无密码重置邮件、无邮箱验证/resend | `changePassword`、`changeEmail`、`sendPasswordResetEmail`、`resendConfirmationEmail` 及整个深链验证流（auth_link_handler） | A. 先在 no-wave 加端点（需要新的邮件基础设施）；B. 迁移时下线「账号安全」页与忘记密码入口 |
| G3 | `GET /me` 只返回 `{data:{id}}`，不回 email | 账号页展示邮箱、`getCurrentUserData` 组装 | 客户端本地缓存登录时输入的 email（登录/注册响应也不含 email，需在 UI 层留存），或推动 `/me` 返回 email |

推荐路线：**G1/G2 先在 no-wave 补端点（用户是仓库所有者，加端点成本低），App 侧同时开始可迁移部分的改造**；
G3 用本地缓存即可，不阻塞。

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
| `GET /me` | Bearer | `{data:{id}}` **仅此** |

- accessToken 为短时效 JWT（`config.ttlSeconds`），`Authorization: Bearer <jwt>`。
- 公开读端点可带可不带 token；带错 token 不报错只降级为匿名 viewer。
- **无**：邮箱验证、密码重置、改密码、改邮箱、OTP/resend —— 全部不存在。

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
| `GET /articles/:slug/comments`、`/related` | 博客 App 暂不需要 |
| **无 DELETE** | `articles.item` 路由仅注册 GET,PUT |

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
- **无删除媒体端点**，资产不可变（每次上传新 id）。App 里的版本化路径/孤儿清理/存储桶逻辑全部不需要了。

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
| `signUpWithEmailPassword(name,email,password)` | `POST /auth/register {email,password}` → 拿到会话后 `PUT /me/profile {displayName:name}` 补写名字 | ✅ 可迁移。注意：**无邮箱验证**，注册即登录（总有 session，`SignUpOutcome.user` 恒可填）；**密码最短 12 位**（现 UI 按 Supabase 6 位校验，需改文案与校验） |
| `loginWithEmailPassword` | `POST /auth/login` | ✅。返回无 user 对象：id 从后续 `GET /me` 拿，或解析 JWT（推荐前者） |
| `currentUserSession` / 会话恢复 | 本地 secure storage 存 `{accessToken,refreshToken,…}`；恢复时 `GET /me` 验活 | ✅。需自建 `TokenSessionManager`：401 时单飞刷新（`POST /auth/refresh`），**refresh 单次有效且轮换**，并发请求必须共享一次刷新，拿到新对后原子替换；刷新失败（重用被撤族）→ 清会话登出 |
| `resendConfirmationEmail` | 无对应 | ❌ G2，下线或补端点 |
| `sendPasswordResetEmail` | 无对应 | ❌ G2，下线或补端点 |
| `logout` | `POST /auth/logout {refreshToken}`（撤销 refresh）+ 可选 `DELETE /me/session`（连 access 一起撤） | ✅。推荐登出即 `DELETE /me/session` + 本地清 token |
| `getCurrentUserData` | `GET /me`（拿 id）+ `GET /me/profile`（拿档案） | ⚠️ G3：email 不返回。email 从本地缓存（登录/注册时留存）读；name ← displayName；avatarUrl/websiteUrl 直接对应 |

深链流（`auth_link_handler.dart`、`auth_callback_resolver.dart`、`auth_session_sync.dart` 中 Supabase 回调部分）：无邮件流即无深链需求 → 整体下线（保留 app_links 依赖与否随 G2 决策）。

### 2.2 `BlogRemoteDataSource`

| 现有方法（Supabase） | no-wave 对应 | 迁移判定 |
|---|---|---|
| `uploadBlog` | ① 有封面则 `POST /me/media` → asset；② tag 名单逐个 `POST /tags`（create-or-reuse）→ tagIds；③ `POST /articles {title, contentBlocks:[image?,paragraphs…], tagIds, publish:true, locale:"zh-CN"}`（slug 省略走自动生成） | ✅ 可迁移（模型适配见 §3） |
| `uploadBlogImage` | `POST /me/media`（原始字节 + Content-Type）→ 存 `$apiBase/api/v1/media/$id` | ✅。服务端转 WebP；无需客户端版本化路径 |
| `removeBlogImage` | 无删除媒体端点 | ➖ 不再需要（媒体不可变、无孤儿问题）。方法删除 |
| `getAllBlogs(page)` | `GET /articles?limit=kBlogPageSize&offset=(page-1)*size` | ✅。「还有更多」= 本页条数==limit |
| `getBlogById(id)` | `GET /articles/{slug}` | ⚠️ 寻址改 slug：见 §3.3 |
| `getBlogsByPosterId` | `GET /authors/{userId}/articles?limit&offset` | ✅（含草稿吗：此端点列已发布；自己草稿走 `GET /me/articles` —— 现有 App 本就只显示已发布，等价） |
| `getBlogsByTag(tag)` | `GET /tags?query=<名>`（或全量 `GET /tags` 后本地匹配）→ `GET /tags/{slug}/articles` | ✅（两跳；slug 无法本地推导，必须先解析） |
| `searchBlogs(query)` | `GET /articles?query=<q>&limit=kMaxSearchResults` | ✅。trigram 全文检索，语义优于现在的 ilike |
| `editBlog(blog)` | `PUT /articles/{articleId}` body **必须含** `{slug(当前或新), publish:true, title, contentBlocks, tagIds?, summary?, workType?}` | ✅（需 BlogModel 存服务端 articleId + slug） |
| `deleteBlog(id)` | **无端点** | ❌ G1，硬缺口 |
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
| `retry_on_connection_closed` | Postgrest 连接被关重试 | 通用 http 客户端下改为对连接级异常的简单重试或直接移除 |
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
- 请求封装：统一加 Bearer；遇 401 → 单飞 `POST /auth/refresh` → 重放原请求；刷新 401 → 清储并广播登出。
- 启动恢复：本地有对 → `GET /me` 校验 → 失败尝试刷新一次。
- 注意并发：refresh 轮换下**绝不能并发刷新两次**（第二次会因重用旧 token 撤销全家）。

### 3.5 UI/文案变更

- 注册页密码规则 6 位 → **12 位**（服务端硬校验，客户端同步前移）。
- 「邮箱验证」「忘记密码」「重发邮件」入口：G2 决策前先隐藏。
- 账号安全页（改密码/改邮箱）：同上。
- 删除博客入口：G1 决策前先隐藏或保留报「暂不支持」。
- 封面图说明：上传后服务端转 WebP（体积更小），无需改动选择器；现有 imageQuality 压缩可保留亦可移除（服务端会再压）。

---

## 4. 差距清单汇总（按处置分组）

**A. 可直接迁移（无需后端改动）**：登录/注册/登出/会话恢复、博客 CRUD（除删除）、搜索、标签、点赞、收藏、作者页、头像、资料编辑。

**B. 需 no-wave 加端点（建议先做）**：
1. `DELETE /articles/:articleId`（G1）—— owner 校验 + 删除 + 事务清理 taxonomy 关联即可。
2. 改密码（`PUT /auth/password`，带旧密码验证）+ 改邮箱 + 密码重置邮件流（G2）—— 依赖邮件基础设施，工作量最大，可后置。

**C. 需 no-wave 修的小问题（顺手）**：
1. `POST /me/media` 响应 `src` 缺 `/v1` 段（与 `GET /api/v1/media/:id` 不一致）。
2. `GET /me` 不回 email（G3）—— 或 App 本地缓存解决。

**D. App 侧下线项**：邮箱验证深链流、存储版本化/孤儿清理、Supabase 依赖（supabase_flutter 从 pubspec 移除，包体减小）、changePassword 后撤其他会话（无对应）。

---

## 5. 建议实施顺序

1. **决策 G1/G2**（本文件 §0）—— 决定是否先动 no-wave。
2. App 侧搭 `NowaveApiClient` + `TokenSessionManager` + 错误映射（不动 UI）。
3. 数据层逐接口替换（§2 表顺序：auth → blog 读 → blog 写 → user），每步跑现有 widget/unit 测试（mock 数据源改 no-wave 形状）。
4. 模型与缓存迁移（slug/articleId、contentBlocks 适配器、tags 解析缓存）。
5. UI 文案与入口调整（密码 12 位、隐藏 G1/G2 缺口入口）。
6. `env.example.json`、README、CI（如涉及 secret）同步更新。
