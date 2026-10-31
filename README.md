# belog

Flutter 编写的移动博客客户端，正逐步向 no-wave 移动端体验靠拢；后端使用自托管
[no-wave](https://github.com/BrainEno/no-wave) `apps/api`（Node + TypeScript，
REST `/api/v1`，SQLite/Postgres）。支持离线缓存阅读、本地草稿、点赞收藏、
按标签浏览与文章搜索、Markdown 正文、阅读历史与数据导出。

隐私相关的本地数据（阅读历史、草稿、缓存）从不离开设备，除非用户主动
导出；详见 [docs/privacy-policy-draft.md](docs/privacy-policy-draft.md)
（隐私政策草案）。

后端迁移背景与逐接口核对结论见
[docs/supabase-to-nowave-migration.md](docs/supabase-to-nowave-migration.md)
（从 Supabase 迁移而来）。

## 移动端视觉与组件

客户端正逐步向 [no-wave 移动网页设计](https://github.com/BrainEno/no-wave/blob/157aa6f5799d33891910ceb606cbaa8ec90f4e40/apps/web/docs/UI_DESIGN_SYSTEM.md) 靠拢：纸色与墨色、橙红强调、衬线标题、细线分隔和留白，并保留原生四标签导航及各自的页面栈。首页、搜索、阅读、作者主页和个人中心采用一致的编辑式布局；收藏和个人作品继续使用可操作的网格。这是逐步迭代，并非所有页面均已统一或与网页逐像素相同；应用包名和启动图标尚未变更。

- 颜色与文字样式集中在 `lib/core/theme/`；品牌、标题、作品行、封面、方形头像与操作行为可复用展示组件。作品行和操作行通过回调交给页面处理导航或动作，不依赖路由或业务状态；评论区的作者点击也由阅读页接管，保持所在标签的导航栈。
- 头像与作品封面优先展示原有 HTTP(S) 图片 URL，提供本地化图片语义。缺失、无效或加载失败时，头像使用中性人像图标；封面使用随包附带的原创抽象兜底图（由 AI 生成，不代表文章内容）。
- Latin 字体使用 [Instrument Serif](https://github.com/google/fonts/tree/main/ofl/instrumentserif) 和 [Inter Tight](https://github.com/google/fonts/tree/main/ofl/intertight)，各自的 SIL Open Font License 随 `assets/fonts/` 打包；中文使用系统衬线/无衬线字体回退。实际字形与行高会因设备而异。
- 继续支持浅色、深色、系统主题、系统字体缩放与中英文界面；系统要求减少动画时关闭标签切换淡入。视觉组件不翻译作品、作者或评论；内容请求仍为 `zh-CN`（见下文“本地化与无障碍”）。

## 功能

- 账号：邮箱注册（注册即登录，无邮箱确认步骤）/ 登录 / 退出，
  个人资料编辑（昵称、网站、头像）
- 文章：发布 / 编辑，**Markdown 正文**（阅读端渲染，编辑器内置实时预览），
  封面图与标签均可选（仅标题与正文必填），封面图上传（服务端统一转码 WebP，
  资产不可变），标签分类（服务端 create-or-reuse，中文名可用）
- 浏览：分页 Feed、下拉刷新、滚动加载更多、按标签筛选、文章标题和摘要搜索
  （含防抖与结果上限），文末相关阅读推荐（服务端 related，最多 6 篇）
- 互动：点赞 / 取消点赞（乐观更新 + 服务端状态校准，显式置态），个人收藏列表，
  评论（纯文本 v0：嵌套回复、最旧在前、发送带幂等键安全重试、自有评论
  删除需确认且级联子回复；未登录显示登录提示）
- 作者：公开作者主页（资料、粉丝/关注数、TA 的文章），关注 / 取消关注
  （状态全程服务端解析：toggle 返回新鲜 profile，重复请求幂等，防连点；
  未登录引导登录；自己主页不显示关注按钮）
- 阅读：设备本地阅读历史（按账号隔离、退出登录即清除），分享文章到系统
  分享面板（链接指向 no-wave web 的文章页，需配置 `WEB_BASE_URL`）
- 数据自主：一键导出个人资料与全部文章为 JSON 文件（经由系统分享面板）
- 草稿：按文章隔离的本地草稿、恢复 / 丢弃对话框、2 秒防抖自动保存、发布后自动清理
- 离线：已获取的文章列表与详情会缓存在 SQLite，可离线阅读。首页按每页 10 条
  读取本机缓存，并标明缓存可能不完整或过期；没有缓存时提示联网重试，不会把
  本机空缓存当作服务端空列表。其他网络操作离线时快速失败并提示
- 语言与无障碍：简体中文 / 英文界面跟随系统语言；日期和数字按区域格式化，
  图片与操作提供语义标签，常用操作支持键盘与较大的字体；主题支持亮 / 暗 /
  跟随系统并在本地持久化

## 认证与会话（no-wave）

- **注册 / 登录**：`POST /auth/{register,login}`，body 仅 `{email,password}`；
  注册密码最短 **12 位**（客户端已同步前移校验）。成功即返回
  `{accessToken, refreshToken, …}`，注册后立即 `PUT /me/profile` 补写昵称。
- **会话持久化**：token 对存平台安全存储（iOS Keychain / Android Keystore，
  issue #46；SQLite 作为迁移源与降级兜底，`core/nowave/nowave_session.dart`）。
  启动时恢复，`GET /me` + `GET /me/profile` 解析身份。
- **刷新轮换**：`POST /auth/refresh` 单次有效且轮换；**重用已轮换的 refresh
  token 会撤销整个会话族**，因此客户端的刷新严格单飞（single-flight），
  access token 过期遇 401 时自动刷新并重放请求一次。
- **退出**：`DELETE /me/session` 撤销会话族（尽力而为），本地会话必定清除。
- **会话同步**：`lib/features/auth/auth_session_sync.dart` 订阅会话状态流；
  后台刷新失败导致的登出会立即把用户带出登录态 UI。
- **email 展示**：在 no-wave 审计快照 [`55a24bd`](https://github.com/BrainEno/no-wave/tree/55a24bdaa1c01888fb5ecb5bf41befe219348049) 中，`GET /me` 可返回邮箱和验证状态；本客户端目前只使用其中的 id，账号页邮箱仍来自登录/注册时的本地缓存（见迁移文档）。

## 后端与客户端差距

以下状态依据 no-wave 审计快照 `55a24bd`，不代表部署或生产验收结果（详见迁移文档）：

- **删除文章**：软删、回收站与恢复已接入客户端（我的文章页长按删除，AppBar 进回收站）。
- **账号安全**（G2）：服务端已有忘记密码、重置密码、邮箱验证和重发验证的接口；邮件功能默认关闭，实际投递需配置并验证。客户端尚未接入这些界面和邮件链接处理，登录页仍隐藏「忘记密码」；修改邮箱和登录态下直接修改密码也未提供。验证邮箱当前不是登录或发布的前置条件。

## 图片与媒体约定

- **上传**：`POST /me/media`，请求体为图片原始字节，MIME 放 `Content-Type`
  头。服务端统一**重编码为 WebP** 并剥离元数据，资产不可变（每次上传新 id）。
- **读取**：`GET /api/v1/media/:id`，immutable + ETag。公开 URL 由客户端统一
  构造为 `$API_BASE_URL/api/v1/media/<id>`（上传响应的 `src` 字段缺 `/v1`
  段，属上游不一致，勿直接使用）。
- **取消 ≠ 失败**：`pickImage()` 取消返回 `null`，真失败抛
  `PickImageException`，调用方（编辑器/资料页）对失败弹提示，不再吞掉。
- **重试与回收**：媒体上传当前没有服务端幂等键，相同内容多次提交仍会创建独立资产；封面和头像在连接失败或超时后不自动重发。失败时服务端是否已保存可能未知，手动重试仍可能产生重复资产；明确的 401 经刷新会话后的单次重放不属于断流盲重试。媒体没有删除端点，服务端的孤儿回收尚未完成，客户端也不提供回滚。
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
- **正文模型**：App 的 Markdown 正文 ↔ no-wave `contentBlocks`（v0 纯文本
  块），转换集中在 `features/blog/data/datasources/nowave_article_codec.dart`；
  封面 = 首个 image 块（可省略）。渲染端 `MarkdownBody` 直接消费 AST，从不
  构造 HTML（raw HTML 惰性降级为文本，仅 http(s) 链接/图片可交互）。
- **Failure 契约**（`core/error/failures.dart`）：`kind`
  （network/timeout/auth/permission/validation/storage/server/unknown）+
  面向用户的中文兜底 `message` + 稳定 `code` + 可选本地化标识 `l10nKey` +
  仅供诊断的 `cause`。UI 根据标识使用 ARB 资源显示本地化错误；原始异常
  文本不进入 UI（后端错误码经 `error_mapper` 分类）。
- **本地存储**：Drift (SQLite) 保存文章缓存、草稿、阅读历史与会话。缓存按
  业务 ID upsert 去重；草稿按 `blog_id` 作用域隔离（`null` = 新文章）；
  阅读历史按账号隔离（复合主键去重，重读置顶），退出登录时清除。
- **首页离线范围**：本机只保存曾获取的文章，不会预下载完整站点；其他设备
  上的删除或更新可能尚未同步，图片也不保证已缓存。首页在连接探测离线或
  首次请求遇到网络/超时错误时显示本机缓存；服务端权限、校验等错误不会
  被伪装成缓存成功。同一次滚动固定使用首页选定的数据源：恢复网络后下拉
  刷新以重新选择；在线翻页期间断网则提示错误并保留已有列表。缓存按
  `updated_at DESC, id ASC` 排序，SQLite 执行分页，每页最多解码 10 条。
  翻页时若缓存或线上列表发生变动，offset 可能位移；下拉刷新可重新加载。
  v4 数据库迁移仅添加对应索引，不删除文章、草稿或其他本地数据；索引会占用
  少量额外空间，首次升级的耗时随缓存大小增长。回退到旧版前应备份数据库，
  旧版不保证能打开新版 schema。

## 本地化与无障碍

界面由 `lib/l10n/app_zh.arb` 和 `app_en.arb` 维护，使用 Flutter 官方
`flutter_localizations` 与 `gen-l10n`；`flutter pub get` 会依据 `l10n.yaml`
生成被 git 忽略的 Dart 文件。新增文案时同时更新两种语言，带参数的消息在
英文模板中声明占位符（复数使用 ICU plural），然后运行 `flutter gen-l10n`
和测试。日期和计数使用 `intl`，内置标签只翻译显示文本，不改变已存储的值。
系统语言为中文或英文时自动匹配；其他语言暂回退简体中文。英文内容是界面
功能翻译，并非经过独立审校的营销文案。

iOS 的系统照片权限提示也提供双语资源。文章、评论、作者资料等用户内容不会
被机器翻译；目前 no-wave 按文章语言精确过滤且缺少跨语言回退，因此客户端的
内容 API 仍请求 `zh-CN`，切换界面语言不会改变既有内容或保存文章的语言。

常用操作提供文字/语义标签及可聚焦的按钮，布局遵循系统字体缩放。诊断信息
仍仅由用户主动查看、复制或分享，不因语言切换自动上传。作者页与个人中心的
中英、亮暗、窄屏大字和键盘操作有自动化覆盖；本轮未完成 iOS 构建、iOS/Android
真机视觉与 VoiceOver/TalkBack 验收，不能以自动测试代替这些检查。

## 本地开发

本项目使用 **Flutter 3.47.8**（与 CI 一致）；Android 需要 Android Studio、
Android SDK 的 emulator/platform-tools、已创建的 AVD 和 JDK 17（支持 17–20）。
iOS 需要 macOS、完整 Xcode、iOS Simulator runtime、CocoaPods 以及 Xcode 命令行工具。
脚本只检查并使用现有工具，不安装 SDK、修改 AVD、关闭模拟器或清除数据。

### 初始配置（每台机器一次）

从仓库根目录复制 `env.example.json` 为 `env.json`（Windows 用
`copy env.example.json env.json`，macOS 用 `cp env.example.json env.json`），
将 `API_BASE_URL` 改成 **设备/模拟器可访问的真实 no-wave API origin**。
`WEB_BASE_URL` 是可选的 no-wave Web origin，未使用时保持空字符串，分享入口
会隐藏；它与 API origin 不能互相推导。地址不要附加 `/api/v1`、路径、查询或
凭据，客户端会添加 `/api/v1`。模板的 `example.com` 是占位符，不可直接使用。

`env.json` 和根目录下的 `env.*.json` 被 Git 忽略；传给 Flutter 的所有定义会
编译进应用，**不要放密码、API key、token、证书或其他秘密**，即使文件已忽略。
脚本只接受上述两个公开配置字段，不会输出文件内容。也可以用 `--config`/
`-Config` 指向其他本地 JSON（相对路径从仓库根目录解析）。

### Windows：一键启动 Android 调试

在仓库目录双击 `scripts\run_android.cmd`，或者在 PowerShell/命令提示符运行：

```powershell
.\scripts\run_android.cmd
.\scripts\run_android.cmd -Avd Pixel_8_API_35 -Config env.android.json -BootTimeoutSeconds 600
```

脚本优先复用已运行的模拟器；指定 `-Avd` 时只使用该 AVD，否则在未运行时
选择按名称排序的第一个可用 AVD。它等待 `adb` 报告开机完成，执行
`flutter pub get` 并以指定模拟器启动 `flutter run --debug`。失败时提示而不
自动安装、删除或杀掉任何模拟器。若没有 AVD，请先在 Android Studio 的
Device Manager 创建；如找不到 SDK，设置 `ANDROID_SDK_ROOT` 或将 emulator 和
platform-tools 加入 PATH。可用 `emulator -list-avds` 查看 AVD 名称。

Android 模拟器中的 `localhost` 是模拟器自身，访问运行在宿主机上的本地 API
通常应使用 `http://10.0.2.2:端口`；真机或其他模拟器必须使用它们能访问的
地址。后端须自行启动，脚本不会启动或验证生产服务。

### macOS：一键模拟器调试与 IPA

双击可执行的 `scripts/run_ios.command` 启动或复用 iPhone Simulator；也可以在
Terminal 运行：

```bash
./scripts/run_ios.sh
./scripts/run_ios.sh --device '<simulator UDID>' --config env.ios.json --boot-timeout 600
```

默认优先复用已启动的 iPhone，否则选择最新已安装 iOS runtime 的一个 iPhone；
用 `xcrun simctl list devices available` 查看精确 UDID。脚本等待启动完成后运行
`flutter pub get` 和 `flutter run --debug`，不会擦除或关闭模拟器。Mac 上的 iOS
模拟器访问宿主机本地后端通常用 `http://localhost:端口`。

双击 `scripts/build_ios_ipa.command`，或运行：

```bash
./scripts/build_ios_ipa.sh --config env.release.json
# 可选：仅在本机已配置团队、证书与 provisioning 时使用真实 Xcode 导出设置
./scripts/build_ios_ipa.sh --mode signed --export-options /path/to/ExportOptions.plist --config env.release.json
```

默认生成 **ad-hoc 签名的 AltStore IPA**，位于 `build/ios/local-ipa/`，保留旧
产物、不覆盖；必须由 AltStore 用用户自己的 Apple ID 重新签名，**不是**
App Store/TestFlight 分发包。`signed` 模式调用 Xcode/Flutter 导出并要求本机
提供正确 Team、证书、provisioning 和 ExportOptions，不会创建或上传凭据。
两种模式均构建 release，要求 API（若配置 Web 也包括 Web）使用有效 HTTPS；
自签名证书还须被设备信任。仅结构/本地签名检查不代表已在真机安装或验证
分发资质，发布策略详见 [docs/releasing.md](docs/releasing.md)。

### 调试网络与手动命令

Android `debug` 和 iOS `Debug` **仅开发构建**允许明文 HTTP（包括非本地地址）；
profile/release 不放宽平台安全策略。HTTP 会明文传输密码和会话，请仅在受信任
的隔离开发环境使用测试账号，生产及 IPA 使用 HTTPS。脚本的 debug 构建启用
`BELOG_DEV_BACKEND_CHECK`，探测配置的 `/api/v1/health`，使没有公网的本地后端
仍可使用；HTTP 错误响应表示服务器可达，具体错误由真实 API 请求报告。每次
检查多一次短请求；release/profile 不启用该探测，仍使用原有公网连接检查。

```bash
flutter pub get
flutter gen-l10n
flutter run --debug --dart-define-from-file=env.json --dart-define=BELOG_DEV_BACKEND_CHECK=true
flutter analyze --fatal-infos
flutter test
dart format lib test
```

如 Android JDK 冲突，可用 `flutter config --jdk-dir=<JDK_DIRECTORY>` 指向 JDK 17。
应用图标仍由 `flutter_launcher_icons` 管理（`dart run flutter_launcher_icons`）。
脚本控制流测试使用模拟工具：`python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v`；
Windows PowerShell mock 测试为 `powershell -File scripts/tests/test_android.ps1`。
它们不等同于真实模拟器、后端、IPA 安装或签名验收。代码审查的修复与剩余
风险见 [docs/code-audit.md](docs/code-audit.md)。

## 测试与 CI

`.github/workflows/ci.yml`（PR / push 到 main 时运行，Flutter 3.47.8 + JDK 17）：

1. **format**：对本次改动的 `.dart` 文件强制 `dart format` 通过
   （全仓库格式审计仅告警，不阻断）。
2. **analyze**：`flutter analyze --fatal-infos`，零告警门禁（`avoid_print`
   已启用，请使用 `AppLogger`）。
3. **test**：`flutter test --coverage --concurrency=1`。
4. **android-release**：使用显式 QA debug 签名和不可路由配置构建 Android release APK，
   另编译 debug APK 并检查两者网络策略；不发布、不代表正式签名已验证。

`.github/workflows/local-scripts.yml` 在 Linux/macOS/Windows 上运行本地脚本的
mock 控制流测试，并在 macOS 上编译 iOS debug 模拟器版本、运行默认 ad-hoc IPA
脚本及检查 debug/release 网络策略。`.github/workflows/dart.yml` 的额外 iOS
无签名编译只在手动选择 `include_ios` 时执行。CI 编译/打包不等同于真实模拟器
启动、设备安装、后端或分发签名实测。

单元与 widget 测试覆盖：分页/刷新竞态（BlogBloc）、搜索竞态（BlogSearchBloc）、
点赞并发与回滚、草稿隔离与自动保存、异常映射矩阵、离线行为、API 客户端
envelope/401 刷新重放、会话刷新单飞、contentBlocks 编解码、Markdown 渲染
（结构/样式/原始 HTML 惰性/javascript: 链接不可点）、阅读历史（去重/排序/
按账号隔离/清空/v2→v3 升级）、导出文档形状、分享 URL 构造等。

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

- **G1 删除文章**：~~待补~~ **已解决**（软删 + 回收站 + 恢复已接入，
  `purgesAt` 30 天）。
- **G2 账号安全**：改密码 / 改邮箱 / 密码重置 / 邮箱验证（需要邮件基础设施）。
- **#23 离线发布队列**：no-wave 源码中的 `POST /articles` 已支持可选
  `Idempotency-Key`（no-wave #105），但实际部署版本/能力尚未确认；媒体上传
  幂等和孤儿清理仍待解决。本分支没有持久 outbox，草稿 PR #66 是安全子集，
  尚不能声称 #23 完成。
- **G3 `GET /me` 返回 email**：或维持客户端本地缓存（现状）。
- **媒体 `src` 字段缺 `/v1` 段**：上游小修（客户端已绕过）。

## 路线图

按 [issue 列表](https://github.com/BrainEno/flutter-blog/issues) 的优先级：

- **P2 已落地**：Markdown 正文与编辑预览（#17）、阅读历史与数据导出（#22）、
  工程清理与图标配置修复（#25）、README/文档（#26）、中文文案与日期/阅读
  时长与中英双语本地化、无障碍适配（#24）、分享（#21 出站部分）、评论（#19）、
  作者主页与关注（#20）
- **P2 进行中/延后**：分享深链接收（#21，等 web 部署 + association 文件
  可验证）、离线发布队列（#23，文章创建步已
  解锁、封面媒体仍受 #47 阻塞，见上）、举报屏蔽（#18）
- **P0/P1 已关闭**：#4 工具链升级、#7 schema 版本管理、#8 离线缓存语义

**许可证待定**：仓库暂无 LICENSE 文件；候选 MIT / Apache-2.0，定稿前请勿
分发二进制。相关讨论见 issue #26。

已完成的重点修复：草稿按文章隔离与发布清理（#14）、Feed 分页与刷新竞态（#13）、
点赞并发与离线行为（#9）、异常契约统一（#12）、iOS 发布流水线（#6）、
点赞离线假成功（#3）、Supabase → no-wave 后端迁移、删除与回收站（G1）、
Markdown 正文（#17）、阅读历史与导出（#22）等。
