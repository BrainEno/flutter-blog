# No Wave

Flutter 编写的移动博客客户端，正逐步向 no-wave 移动端体验靠拢；后端使用自托管
[no-wave](https://github.com/BrainEno/no-wave) `apps/api`（Node + TypeScript，
REST `/api/v1`，SQLite/Postgres）。支持离线缓存阅读、本地草稿、点赞收藏、
按标签浏览与文章搜索、Markdown 正文、阅读历史与数据导出。

阅读历史、本地草稿和缓存不会自动同步；主动发布文章会将当时编辑的内容发送
到后端，用户主动导出或分享则交由系统分享面板处理。外部图片和系统语音引擎
也可能访问网络，详见 [隐私政策草案](docs/privacy-policy-draft.md)。

> **命名说明**：产品名统一为 **No Wave**（中文「无浪潮」），Android/iOS/macOS/Windows
> 的应用名、应用内文案与文档都已按此改名，发布身份统一为 `com.nodeman24.nowave`
> （0.2.0 起，见 [发布策略](docs/releasing.md)）。仓库内仍保留 `belog` 的地方都是
> 兼容性标识，改动会破坏构建或让本地数据变成孤儿：Dart 包名 `belog` 与
> `package:belog/...` 导入、`BELOG_*` 构建变量、`belog.sqlite` 数据文件、
> `belog.exe`、原生通道名 `belog/read_aloud` 与发布流水线的产物文件名。

后端迁移背景与逐接口核对结论见
[docs/supabase-to-nowave-migration.md](docs/supabase-to-nowave-migration.md)
（从 Supabase 迁移而来）。最近 no-wave API 与客户端的差距和接入顺序见
[docs/nowave-api-gap-audit.md](docs/nowave-api-gap-audit.md)。其他运行、
发布与历史资料见 [文档索引](docs/README.md)。

> 本 README 只保留入口信息（#298）。细节已下沉到 `docs/`，每节末尾给出链接；
> 完整列表见 [文档索引](docs/README.md)。

## 功能

| 领域 | 摘要 | 详情 |
| --- | --- | --- |
| 账号 | 邮箱注册（注册即登录）/ 登录 / 退出；资料编辑；登录态改密、改邮箱、忘记密码 | [会话生命周期](docs/session-lifecycle.md)、[账户邮箱](docs/account-email.md)、[密码恢复](docs/password-recovery.md) |
| 文章 | 发布 / 编辑 v0 Markdown 正文并预览；只读展示 v0/v1 结构化正文；不兼容正文拒绝普通编辑器覆盖 | [编辑器路线图](docs/editor-architecture-roadmap.md)、[语言版本](docs/article-editions.md) |
| 浏览 | 分页 Feed（最新 / 精选 / 收藏榜 / 关注）、标签与分类、文章搜索（登录后记住最近搜索）、文末相关阅读 | [首页分页](docs/latest-feed-cursor.md) |
| 离线 | SQLite 缓存可离线阅读；搜索页「离线书库」按服务器与内容语言有界检索 | [离线书库](docs/offline-library.md)、[SQLite 存储](docs/sqlite-storage.md) |
| 互动 | 点赞（乐观更新 + 服务端校准）、收藏列表、纯文本嵌套评论（幂等发送） | [评论线程](docs/comments.md) |
| 作者 | 公开作者主页、关注 / 取关、粉丝与关注列表、作者目录与搜索 | [功能清单](docs/features.md) |
| 消息 | 通知收件箱与私信，打开时读取、不轮询，按账号围栏 | [通知](docs/notifications.md)、[私信](docs/messages.md) |
| 阅读 | 设备本地阅读历史（列表标出「读到 42%」/「已读完」）、系统朗读、分享到系统面板、`nowave://article/<slug>` 深链 | [分享与深链](docs/deep-links.md)、[朗读](docs/read-aloud.md) |
| 草稿与发布 | 按后端 / 账号 / 文章隔离的本地草稿与 2 秒防抖自动保存；离线发布队列带幂等键重试 | [发布队列](docs/publish-queue.md)、[未归属旧草稿](docs/unclaimed-drafts.md) |
| Notion bundle | 编辑器可预览后导入、或把已保存内容导出为经 no-wave 后端处理的 Notion bundle | 见下文「Notion 的范围」 |
| 数据导出 | 资料与最多 100 篇简体中文已发布作品的部分文字导出为 JSON，**不是完整备份** | [功能清单](docs/features.md) |
| 语言与无障碍 | 简体中文 / 英文界面，日期数字按区域格式化，语义标签、键盘与系统字体缩放 | [无障碍](docs/accessibility.md) |

两条容易误解的边界：

- **站点相对资源**：分享入口、站点相对的正文图片 / 链接和头像（`/avatars/...`）
  只在配置可信 `WEB_BASE_URL` 时可用；未配置或地址不安全时头像显示中性占位，
  不从 API origin 猜测。
- **隐私**：阅读历史、本地草稿和缓存不会自动同步；诊断信息只由用户主动查看、
  复制或导出，不自动上传。

每项功能的完整边界说明见 [功能清单（详细版）](docs/features.md)。

### Notion 的范围（#287，核对于 2026-11-19）

- **已实现**：编辑器内由用户显式发起的 Notion bundle **导入 / 导出**，经 no-wave
  后端处理（`lib/features/blog/data/notion_import/`、
  `lib/features/blog/data/notion_export/`，入口在
  `lib/features/blog/presentation/editor/editor_notion_coordinator.dart`）。App 不直连
  Notion API、不保存 Notion token。
- **导入的预览计划保护（#308）**：导入需要支持预览计划保护的 no-wave 服务端；
  旧服务端预览不返回计划时不允许确认。计划只在内存中使用，选择或账号变化、过期
  或失败后需重新预览。服务端按作品保护，多作品可能部分成功；超时或断线后先检查
  文章再预览，不会自动重发。
- **未实现**：把 Notion 数据库作为第二个**运行时文章内容源**（直接读取 Notion 数据库
  的文章列表与正文）。方案、风险与分期见
  [Notion 内容源评估](docs/notion-content-source-assessment.md)；现有 no-wave 行为不受影响。

## 快速开始

本项目固定使用 **Flutter 3.47.8**（`tool/flutter_version.txt`，CI 与发布构建严格校验）。

1. 复制配置：`cp env.example.json env.json`（Windows：`copy env.example.json env.json`），
   把 `API_BASE_URL` 改成**设备 / 模拟器能访问的** no-wave API origin（不要带
   `/api/v1`、路径、查询或凭据；Android 模拟器访问宿主机用 `http://10.0.2.2:端口`）。
   `WEB_BASE_URL` 可留空。`env.json` 会编译进应用，**不要放任何秘密**。
2. 运行：

   ```bash
   flutter pub get
   flutter run --debug --dart-define-from-file=env.json
   flutter test
   ```

3. 或者用一键脚本：Windows 双击 `scripts\run_android.cmd`（首次会提示输入 API origin
   并生成 `env.json`），macOS 运行 `./scripts/run_ios.sh`。

脚本参数、Android / iOS 前置条件、明文 HTTP 策略、IPA 打包与依赖升级见
[本地开发](docs/local-development.md)；版本不符、Pub 哈希错误、白屏、「无法连接到网络」
等常见阻塞见 [本地启动排障](docs/troubleshooting.md)。

## 架构

feature-first + 核心层的简化整洁架构：

```
lib/
├── core/        # 与业务无关的基础设施：API 客户端与会话、存储、主题、l10n、设计 token
├── features/    # auth / blog / user / messages / notifications：data / domain / presentation
├── di/          # 按功能拆分的依赖注册模块（#304），由 app_modules.dart 汇总
├── boot/        # 冷启动编排与墨色幕布
├── router/      # go_router 路由（页面级 bloc 随页面创建销毁）
├── l10n/        # ARB（中文 / 英文）
├── init_dependencies.dart  # 组合根：校验 API origin、打开存储与会话、注册 lib/di 模块
└── main.dart    # 入口 + 全局错误钩子
```

- **数据流**：UI → Bloc → Usecase → Repository（`Either<Failure, T>`）→ Datasource；
  Repository 是唯一把异常翻译成 `Failure` 的地方。
- **分层方向**：依赖只能从 feature 指向 `lib/core`，由
  `tool/ci/check_core_dependencies.py` 在 CI 中强制。
- **依赖注入**：新功能在 `lib/di/` 加一个模块并在 `lib/di/app_modules.dart` 登记；
  `test/unit/di/app_modules_test.dart` 会从真实模块解析每一个注册类型。
- **设计系统**：页面只读 `lib/core/design/design_tokens.dart` 的 token，间距、圆角与
  直接字号都有测试守护，见 [界面设计系统](docs/design-system.md)。

正文模型、Failure 契约、本地存储、首页离线范围与图片 / 媒体约定见
[架构与约定](docs/architecture.md)。

## 测试与 CI

`.github/workflows/ci.yml`（PR 与 push 到 main，Flutter 3.47.8 + JDK 17）：

1. **format**：改动的 `.dart` 文件必须通过 `dart format`。
2. **analyze**：`flutter analyze --fatal-infos`，零告警。
3. **test**：`flutter test --coverage --concurrency=1`，随后按
   `tool/ci/coverage_threshold.json` 的最低行覆盖率门禁（只升不降）。
4. **android-release**：QA debug 签名的 release APK 与网络策略检查（不是正式签名）。

其余工作流（本地脚本 mock、iOS 模拟器编译、桌面 runner）与覆盖范围见
[CI 可观测性](docs/ci-observability.md)。工程约束与 PR 证据要求见 [AGENTS.md](AGENTS.md)。

## 安装包与发布

- **个人设备安装包**：合并到 `main` 后在 **Actions → Build personal mobile packages**
  手动构建 IPA / APK；IPA 需用 AltStore Classic 以个人 Apple ID 重签。详见
  [个人安装 IPA / APK](docs/mobile-packages.md)。
- **发布**：签名、版本与发布身份（`com.nodeman24.nowave`、`0.2.0+1`）见
  [发布流程](docs/releasing.md)。CI 的 release-mode QA 构建**不得**当作生产构建分发。

## 后端差距与路线图

客户端已迁移到 no-wave `apps/api`；仍需服务端补齐或部署验证的能力（媒体上传幂等、
举报与屏蔽、通用链接 / App Links 等）见 [后端差距摘要](docs/backend-gaps.md) 与
[API 差距审计](docs/nowave-api-gap-audit.md)。已落地阶段与重点修复见
[路线图](docs/roadmap.md)；开放工作以
[GitHub issue 列表](https://github.com/BrainEno/flutter-blog/issues) 的优先级为准。

## 状态

- 文档结构核对于 2026-11-19（#298）：本 README 只做入口，事实以 `docs/` 与源码为准。
- **许可证**：[Apache License 2.0](LICENSE)。随包分发的字体等第三方资源及其许可证见
  [NOTICE](NOTICE)；Dart/Flutter 依赖的解析结果固定在 `pubspec.lock`。
