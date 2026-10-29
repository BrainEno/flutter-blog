# belog

Flutter 编写的移动博客客户端（应用内品牌：Bottom Think），后端使用自托管
[no-wave](https://github.com/BrainEno/no-wave) `apps/api`（Node + TypeScript，
REST `/api/v1`，SQLite/Postgres）。支持离线缓存阅读、本地草稿、点赞收藏、
按标签浏览与全文搜索。

后端迁移背景与逐接口核对结论见
[docs/supabase-to-nowave-migration.md](docs/supabase-to-nowave-migration.md)
（从 Supabase 迁移而来）。

## 功能

- 账号：邮箱注册（注册即登录，无邮箱确认步骤）/ 登录 / 退出，
  个人资料编辑（昵称、网站、头像）
- 文章：发布 / 编辑，封面图上传（服务端统一转码 WebP，资产不可变），标签分类
  （服务端 create-or-reuse，中文名可用）
- 浏览：分页 Feed、下拉刷新、滚动加载更多、按标签筛选、全文搜索（trigram，
  含防抖与结果上限）
- 互动：点赞 / 取消点赞（乐观更新 + 服务端状态校准，显式置态），个人收藏列表
- 草稿：按文章隔离的本地草稿、恢复 / 丢弃对话框、2 秒防抖自动保存、发布后自动清理
- 离线：文章列表与详情 SQLite 缓存，离线可读；网络操作离线时快速失败并提示
- 主题：亮 / 暗 / 跟随系统，偏好本地持久化

## 认证与会话（no-wave）

- **注册 / 登录**：`POST /auth/{register,login}`，body 仅 `{email,password}`；
  注册密码最短 **12 位**（客户端已同步前移校验）。成功即返回
  `{accessToken, refreshToken, …}`，注册后立即 `PUT /me/profile` 补写昵称。
- **会话持久化**：token 对存本地 SQLite（`core/nowave/nowave_session.dart`，
  `NowaveSessionStore` 接口可替换为平台安全存储）。启动时恢复，
  `GET /me` + `GET /me/profile` 解析身份。
- **刷新轮换**：`POST /auth/refresh` 单次有效且轮换；**重用已轮换的 refresh
  token 会撤销整个会话族**，因此客户端的刷新严格单飞（single-flight），
  access token 过期遇 401 时自动刷新并重放请求一次。
- **退出**：`DELETE /me/session` 撤销会话族（尽力而为），本地会话必定清除。
- **会话同步**：`lib/features/auth/auth_session_sync.dart` 订阅会话状态流；
  后台刷新失败导致的登出会立即把用户带出登录态 UI。
- **email 展示**：`GET /me` 只返回 id，账号页展示的邮箱来自登录/注册时本地
  缓存（G3，见迁移文档）。

## 后端差距（已知，入口已隐藏）

no-wave 现有 API 尚无对应端点，相关 UI 本次迁移先下线（详见迁移文档 G1/G2）：

- **删除文章**：无 `DELETE /articles/:id`，编辑器菜单已隐藏「删除文章」。
- **账号安全**：无改密码 / 改邮箱 / 密码重置 / 邮箱验证，登录页已隐藏
  「忘记密码」，「账号设置」入口已移除。

## 图片与媒体约定

- **上传**：`POST /me/media`，请求体为图片原始字节，MIME 放 `Content-Type`
  头。服务端统一**重编码为 WebP** 并剥离元数据，资产不可变（每次上传新 id）。
- **读取**：`GET /api/v1/media/:id`，immutable + ETag。公开 URL 由客户端统一
  构造为 `$API_BASE_URL/api/v1/media/<id>`（上传响应的 `src` 字段缺 `/v1`
  段，属上游不一致，勿直接使用）。
- **取消 ≠ 失败**：`pickImage()` 取消返回 `null`，真失败抛
  `PickImageException`，调用方（编辑器/资料页）对失败弹提示，不再吞掉。
- **无删除**：媒体无删除端点，旧资产自然失效为不可达（生命周期由服务端管理）。
  客户端不再有版本化路径 / 孤儿回滚逻辑。
- **缓存**：封面与头像 URL 不可变，无需 `?v=` cache-busting
  （`presentation/utils/cover_url.dart` 已简化）。

## 架构

按 feature-first + 核心层分层的简化整洁架构：

```
lib/
├── core/                  # 与业务无关的基础设施
│   ├── common/            # 全局 cubit（AppUser）
│   ├── error/             # Failure 契约 + 异常映射（error_mapper）
│   ├── network/           # 连接检查
│   ├── nowave/            # API 客户端（envelope/401 刷新/媒体上传）+ 会话管理
│   ├── storage/           # Drift/SQLite：缓存、草稿、主题、会话（legacy/ 为旧 Isar 模型）
│   ├── theme/             # 主题与 ThemeBloc
│   └── utils/             # AppLogger、重试、Snackbar 等
├── features/
│   ├── auth/              # 登录注册（no-wave /auth/*）
│   ├── blog/              # 文章域：datasources / repository / usecases / blocs / pages
│   └── user/              # 个人资料
├── router/                # go_router 路由（页面级 bloc 随页面创建销毁）
└── main.dart              # 入口 + 全局错误钩子
```

关键约定：

- **数据流向**：UI → Bloc → Usecase → Repository（`Either<Failure, T>`）→
  Datasource。Repository 是唯一把异常翻译成 `Failure` 的地方。
- **文章寻址双轨**：公开读 / 点赞按 slug（即 `Blog.id`），更新按服务端 UUID
  （`BlogModel.articleId`，仅写入路径使用）。
- **正文模型**：App 的纯文本正文 ↔ no-wave `contentBlocks`（v0 纯文本块），
  转换集中在 `features/blog/data/datasources/nowave_article_codec.dart`；
  封面 = 首个 image 块。
- **Failure 契约**（`core/error/failures.dart`）：`kind`
  （network/timeout/auth/permission/validation/storage/server/unknown）+
  面向用户的中文 `message` + 稳定 `code` + 仅供诊断的 `cause`。
  原始异常文本永远不会进入 UI（后端错误码经 `error_mapper` 分类，不透传英文）。
- **本地存储**：Drift (SQLite) 保存文章缓存、草稿与会话。缓存按业务 ID upsert
  去重；草稿按 `blog_id` 作用域隔离（`null` = 新文章）。

## 本地开发

```bash
flutter pub get
flutter run            # 需要 API_BASE_URL 配置（见下）
flutter analyze
flutter test
dart format lib test
```

- Flutter 版本：CI 使用 **3.47.8**（stable），本地请保持一致。
- Android 构建需要 JDK 17–20（AGP/Gradle 兼容范围），如遇冲突执行
  `flutter config --jdk-dir=<JDK_DIRECTORY>`。
- 后端地址通过 `--dart-define-from-file=env.json`（模板见 `env.example.json`）
  或 `--dart-define=API_BASE_URL=https://...` 注入，只需要一个 HTTP(S) origin，
  无客户端密钥。

## 测试与 CI

`.github/workflows/ci.yml`（PR / push 到 main 时运行，Flutter 3.47.8 + JDK 17）：

1. **format**：对本次改动的 `.dart` 文件强制 `dart format` 通过
   （全仓库格式审计仅告警，不阻断）。
2. **analyze**：`flutter analyze --fatal-infos`，零告警门禁（`avoid_print`
   已启用，请使用 `AppLogger`）。
3. **test**：`flutter test --coverage --concurrency=1`。
4. **build**：Android/iOS debug 构建冒烟（iOS 构建在 macOS runner 上执行）。

单元与 widget 测试覆盖：分页/刷新竞态（BlogBloc）、搜索竞态（BlogSearchBloc）、
点赞并发与回滚、草稿隔离与自动保存、异常映射矩阵、离线行为、API 客户端
envelope/401 刷新重放、会话刷新单飞、contentBlocks 编解码等。

## 发布

发布流程、签名与版本规则见 [docs/releasing.md](docs/releasing.md)。
CI 的 release-mode QA 构建需要显式 `BELOG_QA_BUILD=true` 且使用 debug 签名，
**不得**当作生产构建分发。另见
[docs/ci-observability.md](docs/ci-observability.md)、
[docs/isar-to-sqlite-migration.md](docs/isar-to-sqlite-migration.md)、
[docs/supabase-to-nowave-migration.md](docs/supabase-to-nowave-migration.md)、
[docs/agent-development.md](docs/agent-development.md)。

## 服务端（no-wave）差距与待办

客户端侧已全部迁移至 no-wave `apps/api`；剩余差距需要在 no-wave 仓库补端点
（完整核对见迁移文档 §4）：

- **G1 删除文章**：`DELETE /articles/:articleId`（owner 校验 + 事务清理
  taxonomy 关联）。补齐后恢复编辑器「删除文章」入口即可（bloc/usecase
  管线已保留）。
- **G2 账号安全**：改密码 / 改邮箱 / 密码重置 / 邮箱验证（需要邮件基础设施）。
- **G3 `GET /me` 返回 email**：或维持客户端本地缓存（现状）。
- **媒体 `src` 字段缺 `/v1` 段**：上游小修（客户端已绕过）。

## 路线图

按 [issue 列表](https://github.com/BrainEno/flutter-blog/issues) 的优先级：

- **P0**：#4 Android Gradle 工具链升级
- **P1**：#7 服务端 schema 纳入版本管理 · #8 Isar 离线缓存语义
- **P2**：Markdown 正文（contentBlocks v1 富文本）、评论、关注、举报屏蔽、
  分享深链、离线发布队列、阅读历史、国际化与无障碍、工程清理等（#15–#26）

已完成的重点修复：草稿按文章隔离与发布清理（#14）、Feed 分页与刷新竞态（#13）、
点赞并发与离线行为（#9）、异常契约统一（#12）、iOS 发布流水线（#6）、
点赞离线假成功（#3）、Supabase → no-wave 后端迁移等。
