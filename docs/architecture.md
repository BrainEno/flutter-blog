# 架构与约定

> 状态：active ｜ 最后核对：2026-11-19 @ eb363b3

> 从根 README 移出（#298）。依赖注入按功能拆在 `lib/di/`（#304），组合根是
> `lib/init_dependencies.dart`。

按 feature-first + 核心层分层的简化整洁架构：

```
lib/
├── core/                  # 与业务无关的基础设施
│   ├── common/            # 全局 cubit（AppUser）与通用控件
│   ├── config/            # 配置值唯一来源：等待时长 app_durations、分页/上限 app_limits（#295）
│   ├── error/             # Failure 契约 + 异常映射（error_mapper）
│   ├── l10n/              # 界面语言、内容语言，以及 Failure/标签/作者名文案 helper
│   ├── network/           # 连接检查
│   ├── nowave/            # API 客户端（envelope/401 刷新/媒体上传）+ 会话管理
│   ├── secrets/           # 编译期环境（API base URL、WEB base URL）
│   ├── startup/           # 启动失败兜底界面（依赖初始化抛错时）
│   ├── storage/           # Drift/SQLite：建表、迁移与原始行读写（Isar 已于 #107 移除）
│   ├── theme/             # 主题与 ThemeBloc
│   ├── usecase/           # UseCase 抽象
│   └── utils/             # AppLogger、重试、Snackbar、分享/深链解析等
├── features/
│   ├── auth/              # 登录注册（no-wave /auth/*）
│   ├── blog/              # 文章域：datasources / repository / usecases / blocs / pages
│   └── user/              # 个人资料
├── l10n/                  # ARB 目录（中文/英文）+ 生成物（git 忽略，pub get 生成）
├── router/                # go_router 路由（页面级 bloc 随页面创建销毁）；路径与跳转地址集中在 route_paths.dart（#295）
└── main.dart              # 入口 + 全局错误钩子
```

关键约定：

- **数据流向**：UI → Bloc → Usecase → Repository（`Either<Failure, T>`）→
  Datasource。Repository 是唯一把异常翻译成 `Failure` 的地方。
- **文章后端与 Notion bundle**：文章列表、详情、互动与发布仍由 no-wave `apps/api`
  提供。编辑器已支持用户主动导入或导出经 no-wave 后端处理的 Notion bundle；这不会
  直连 Notion API、读取 Notion 数据库或把 token 写入 App。把 Notion 数据库作为第二个
  运行时文章内容源仍处于评估阶段，所需抽象、风险与分期见
  [Notion 内容源评估](notion-content-source-assessment.md)，现有 no-wave 行为
  不受影响。
- **分层方向**：依赖只能从 feature 指向 `lib/core`，不能反向；`lib/core/storage`
  不得导入 Flutter UI 类型。规则由 `tool/ci/check_core_dependencies.py` 在 CI 中
  强制（`--root` 可对任意目录跑，unittest 也在真实仓库上验证）。
- **配置值单一来源**（#295）：超时、防抖、自动保存间隔、重试表与保留窗口写在
  `lib/core/config/app_durations.dart`；分页大小与行数上限写在
  `lib/core/config/app_limits.dart`；路由 `path:` 片段与页面跳转地址写在
  `lib/router/route_paths.dart`（动态段统一 `Uri.encodeComponent`）。调用方只引用
  常量；`test/unit/design/no_magic_durations_test.dart` 与
  `test/unit/core/route_paths_guard_test.dart` 拒绝在别处新增字面量。动画时长仍来自
  `NoWaveMotion`。
- **文章寻址双轨**：公开读 / 点赞按 slug（即 `Blog.id`），更新按服务端 UUID
  （`BlogModel.articleId`，仅写入路径使用）。
- **正文模型**：普通编辑器写入 no-wave `contentBlocks` v0 纯文本块（首张图
  视为封面）；只读的结构化 v0/v1 解析器保留块、行内样式与媒体顺序，转换为
  阅读和朗读共用的惰性 AST，不构造 HTML。未知/损坏格式明确警告。站点相对
  资源与头像（`/avatars/me.webp`，no-wave `validateProfileUrl` 允许的格式）
  仅按 `WEB_BASE_URL` 解析，不猜测 API origin；未配置时保留中性占位；
  不安全的 URL 不可交互、也不会被加载。
- **Failure 契约**（`core/error/failures.dart`）：`kind`
  （network/timeout/auth/permission/validation/storage/server/unknown）+
  面向用户的中文兜底 `message` + 稳定 `code` + 可选本地化标识 `l10nKey` +
  仅供诊断的 `cause`。UI 根据标识使用 ARB 资源显示本地化错误；原始异常
  文本不进入 UI（后端错误码经 `error_mapper` 分类）。
- **本地存储**：Drift (SQLite) 保存文章缓存、草稿、阅读历史与离线资料；
  会话通常保存在平台安全存储，不可用时可能回退 SQLite。新版草稿按后端、
  账号与文章隔离；旧版无归属草稿保留但不自动展示或分配，导出与降级限制见
  [旧草稿说明](unclaimed-drafts.md)。阅读历史按用户 ID 去重（不区分
  后端），退出时尽力清理。
  离线资料按后端和账号隔离；旧版没有归属信息的资料缓存保留但不再展示，
  联网后重新获取。存储失败、已在途写入或系统备份可能使退出清理不完整，
  不承诺物理擦除。
- **首页离线范围**：本机只保存曾获取的文章，不会预下载完整站点；其他设备
  上的删除或更新可能尚未同步，图片也不保证已缓存。首页在连接探测离线或
  首次请求遇到网络/超时错误时显示本机缓存；服务端权限、校验等错误不会
  被伪装成缓存成功。同一次滚动固定使用首页选定的数据源：恢复网络后下拉
  刷新以重新选择；在线翻页期间断网则提示错误并保留已有列表。缓存按
  `updated_at DESC, id ASC` 排序，SQLite 执行分页，每页最多解码 10 条。
  在线「最新」在兼容服务器使用游标；旧部署回退 offset，缓存、热门、精选和关注
  仍使用 offset，列表变化时可能重复或遗漏。游标对高密度时间边界会明确停止并提示，
  不是完整快照；具体限制见 [首页分页说明](latest-feed-cursor.md)。下拉刷新可重新加载。
  v4 数据库迁移仅添加对应索引，不删除文章、草稿或其他本地数据；索引会占用
  少量额外空间，首次升级的耗时随缓存大小增长。回退到旧版前应备份数据库，
  旧版不保证能打开新版 schema。

## 图片与媒体约定

- **上传**：`POST /me/media`，请求体为图片原始字节，MIME 放 `Content-Type`
  头。服务端统一**重编码为 WebP** 并剥离元数据，资产不可变（每次上传新 id）。
- **读取**：`GET /api/v1/media/:id`，immutable + ETag。公开 URL 由客户端统一
  构造为 `$API_BASE_URL/api/v1/media/<id>`（上传响应的 `src` 字段缺 `/v1`
  段，属上游不一致，勿直接使用）。
- **取消 ≠ 失败**：`pickImage()` 取消返回 `null`，真失败抛
  `PickImageException`，调用方（编辑器/资料页）对失败弹提示，不再吞掉。
- **重试与回收**：媒体上传当前没有服务端幂等键，相同内容多次提交仍会创建独立资产；封面和头像在连接失败或超时后不自动重发。失败时服务端是否已保存可能未知，手动重试仍可能产生重复资产；明确的 401 经刷新会话后的单次重放不属于断流盲重试。no-wave `13271b21` 已新增媒体库与手动删除，但其引用检查存在[误删风险](https://github.com/BrainEno/no-wave/issues/146)；修复前不要使用网页媒体库删除图片。Flutter 没有接入媒体列表或删除，也不提供回滚；没有定时回收。
- **缓存**：封面与头像 URL 不可变，无需 `?v=` cache-busting（`Blog.imageUrl`
  直接使用；曾经包一层的 `presentation/utils/cover_url.dart` 是恒等函数，
  2026-11 的整理中已删除）。
