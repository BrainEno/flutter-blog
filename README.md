# belog

Flutter 编写的移动博客客户端，正逐步向 no-wave 移动端体验靠拢；后端使用自托管
[no-wave](https://github.com/BrainEno/no-wave) `apps/api`（Node + TypeScript，
REST `/api/v1`，SQLite/Postgres）。支持离线缓存阅读、本地草稿、点赞收藏、
按标签浏览与文章搜索、Markdown 正文、阅读历史与数据导出。

阅读历史、本地草稿和缓存不会自动同步；主动发布文章会将当时编辑的内容发送
到后端，用户主动导出或分享则交由系统分享面板处理。外部图片和系统语音引擎
也可能访问网络，详见 [隐私政策草案](docs/privacy-policy-draft.md)。

后端迁移背景与逐接口核对结论见
[docs/supabase-to-nowave-migration.md](docs/supabase-to-nowave-migration.md)
（从 Supabase 迁移而来）。最近 no-wave API 与客户端的差距和接入顺序见
[docs/nowave-api-gap-audit.md](docs/nowave-api-gap-audit.md)。其他运行、
发布与历史资料见 [文档索引](docs/README.md)。

## 移动端视觉与组件

客户端正逐步向 [no-wave 移动网页设计](https://github.com/BrainEno/no-wave/blob/157aa6f5799d33891910ceb606cbaa8ec90f4e40/apps/web/docs/UI_DESIGN_SYSTEM.md) 靠拢：纸色与墨色、橙红强调、衬线标题、细线分隔和留白，并保留原生四标签导航及各自的页面栈。首页、搜索、阅读、作者主页和个人中心采用一致的编辑式布局；收藏和个人作品继续使用可操作的网格。这是逐步迭代，并非所有页面均已统一或与网页逐像素相同；应用包名和启动图标尚未变更。

- 颜色与文字样式集中在 `lib/core/theme/`；品牌、标题、作品行、封面、方形头像与操作行为可复用展示组件。作品行和操作行通过回调交给页面处理导航或动作，不依赖路由或业务状态；评论区的作者点击也由阅读页接管，保持所在标签的导航栈。
- 头像与作品封面优先展示原有 HTTP(S) 图片 URL，提供本地化图片语义。缺失、无效或加载失败时，头像使用中性人像图标；封面使用随包附带的原创抽象兜底图（由 AI 生成，不代表文章内容）。
- Latin 字体使用 [Instrument Serif](https://github.com/google/fonts/tree/main/ofl/instrumentserif) 和 [Inter Tight](https://github.com/google/fonts/tree/main/ofl/intertight)，各自的 SIL Open Font License 随 `assets/fonts/` 打包；中文使用系统衬线/无衬线字体回退。实际字形与行高会因设备而异。
- 继续支持浅色、深色、系统主题、系统字体缩放与中英文界面；系统要求减少动画时关闭标签切换淡入。视觉组件不翻译作品、作者或评论；内容请求仍为 `zh-CN`（见下文“本地化与无障碍”）。

## 功能

- 账号：邮箱注册（注册即登录，无邮箱确认步骤）/ 登录 / 退出，
  个人资料编辑（昵称、网站、头像）
- 文章：发布 / 编辑，简单 v0 正文按 **Markdown** 阅读并支持编辑预览；只读
  显示 no-wave v0/v1 结构化正文的标题、引用、列表、代码、行内样式及多图。
  不兼容的正文拒绝使用普通编辑器保存，避免覆盖格式。封面图与标签均可选
  （仅标题与正文必填），封面上传后由服务端统一转码 WebP、资产不可变
- 浏览：分页 Feed、下拉刷新、滚动加载更多、按标签筛选、文章搜索
  （含防抖与结果上限；已升级的服务端也搜索正文块文本，旧部署可能只查标题或摘要，
  离线只搜索本机缓存标题），文末相关阅读推荐（服务端 related，最多 6 篇）；首页可切换
  最新、编辑精选、按收藏排序的作品，以及登录后查看关注作者的作品。精选、收藏榜和关注
  仅在线读取，不能用公共缓存伪造排序或关注关系。
- 互动：点赞 / 取消点赞（乐观更新 + 服务端状态校准，显式置态），个人收藏列表，
  评论（纯文本 v0：嵌套回复、最旧在前、发送带幂等键安全重试、自有评论
  删除需确认且级联子回复；未登录显示登录提示）
- 作者：公开作者主页（资料、粉丝/关注数、TA 的文章），从搜索页按昵称或用户 ID
  发现作者，也可从作者页查看粉丝和关注用户，或从个人中心进入自己的作者页。
  作者搜索与关系列表仅在线、无需登录且不附带会话凭据；每次最多 100 人，
  达到上限时提示可能还有更多，后端目前不提供翻页。搜索词和结果资料仅保留在
  页面内存，头像图片沿用现有图片缓存；内容语言请求固定为 `zh-CN`。
  关注 / 取消关注由服务端校准（重复请求幂等，防连点；未登录引导登录；自己
  主页不显示关注按钮）。站点相对头像仍待 [#63](https://github.com/BrainEno/flutter-blog/issues/63)
- 阅读：设备本地阅读历史（按账号隔离，退出时尽力清理），分享文章到系统
  分享面板（链接指向 no-wave web 的文章页，需配置 `WEB_BASE_URL`）
- 数据导出：个人资料及最多 100 篇简体中文已发布作品的部分文字导出为 JSON，
  经系统分享面板保存；不含服务端草稿、其他语言及完整正文格式或图片，**不是完整备份**
- 草稿：按 API 后端、账号和文章隔离的本地草稿、恢复 / 丢弃对话框及 2 秒
  防抖自动保存；发布前保存快照，成功后仅在快照未变化时尝试清理。旧版无法
  证明归属的草稿保留但不自动显示或分配，服务端草稿是独立功能
- 离线：最新列表及通过详情接口取得的文章会缓存在 SQLite，可离线阅读；精选、
  收藏榜、关注等网络列表不写入普通列表缓存。结构化正文随已缓存文章保存，图片
  不保证离线可用。旧版 no-wave 缓存可能已经压平结构，升级后会提示可能不完整，
  联网重新获取可恢复。首页按每页 10 条读取缓存并标明可能不完整或过期；其他
  网络操作离线时快速失败并提示
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
- **退出**：`DELETE /me/session` 尽力撤销会话族并清除内存中的当前会话；
  安全存储或 SQLite 清除失败时旧副本可能留存，不能承诺已物理擦除。
- **会话同步**：`lib/features/auth/auth_session_sync.dart` 订阅会话状态流；
  后台刷新失败导致的登出会立即把用户带出登录态 UI。
- **email 展示**：在 no-wave 审计快照 [`55a24bd`](https://github.com/BrainEno/no-wave/tree/55a24bdaa1c01888fb5ecb5bf41befe219348049) 中，`GET /me` 可返回邮箱和验证状态；本客户端目前只使用其中的 id，账号页邮箱仍来自登录/注册时的本地缓存（见迁移文档）。

## 后端与客户端差距

以下状态依据 no-wave 审计快照 `effeb9a7`，不代表部署或生产验收结果；完整清单见 [API 差距审计](docs/nowave-api-gap-audit.md)：

- **我的文章与服务端草稿**：我的文章页读取账号作用域的 `GET /me/articles`（非公开作者列表），因此回收站恢复出来的草稿仍然可见，并带草稿标记；在编辑器中保存即按发布提交。结构不兼容（富文本/未知块）的草稿仍只能到 no-wave 网页编辑。旧部署没有该接口时自动回退到公开作者列表，只失去草稿可见性。
- **账号安全**（G2）：个人中心可修改登录态密码，需当前密码；输入按原样保留空格。旧版注册/登录曾自动去除首尾空格，旧账号请使用当时服务器实际收到的密码（可能不含首尾空格），不会自动尝试另一种密码。改密不自动重放；网络中断或服务器异常后密码可能已生效，但其他设备仍可能保持登录，请先使用新密码确认。服务端当前会话可能被错误撤销及异常时部分成功的问题分别见 [no-wave #129](https://github.com/BrainEno/no-wave/issues/129) 和 [#132](https://github.com/BrainEno/no-wave/issues/132)。修改邮箱、忘记/重置密码、邮箱验证及邮件链接处理仍未接入；邮件默认关闭，实际投递需配置并验证，验证邮箱当前不是登录或发布的前置条件。
- **内容语言**：界面支持中英文，但文章列表、搜索和详情等请求仍固定 `zh-CN`，仅有英文或繁体中文译文的作品可能不可见；内容语言选择与缓存隔离尚未实现。
- **富文本和多图**：已按当前 v0/v1 契约只读展示；未知或损坏格式及升级前已压平的 no-wave 缓存会提示可能不完整。站点相对图片和链接只有显式配置可信 `WEB_BASE_URL` 才可使用。富文本编辑尚未实现，普通编辑器拒绝覆盖不兼容结构；已读取摘要会回传，但不解决并发修改，正文块 ID 会重建，空摘要仍可能由服务端重算。

## 图片与媒体约定

- **上传**：`POST /me/media`，请求体为图片原始字节，MIME 放 `Content-Type`
  头。服务端统一**重编码为 WebP** 并剥离元数据，资产不可变（每次上传新 id）。
- **读取**：`GET /api/v1/media/:id`，immutable + ETag。公开 URL 由客户端统一
  构造为 `$API_BASE_URL/api/v1/media/<id>`（上传响应的 `src` 字段缺 `/v1`
  段，属上游不一致，勿直接使用）。
- **取消 ≠ 失败**：`pickImage()` 取消返回 `null`，真失败抛
  `PickImageException`，调用方（编辑器/资料页）对失败弹提示，不再吞掉。
- **重试与回收**：媒体上传当前没有服务端幂等键，相同内容多次提交仍会创建独立资产；封面和头像在连接失败或超时后不自动重发。失败时服务端是否已保存可能未知，手动重试仍可能产生重复资产；明确的 401 经刷新会话后的单次重放不属于断流盲重试。no-wave `13271b21` 已新增媒体库与手动删除，但其引用检查存在[误删风险](https://github.com/BrainEno/no-wave/issues/146)；修复前不要使用网页媒体库删除图片。Flutter 没有接入媒体列表或删除，也不提供回滚；没有定时回收。
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
- **正文模型**：普通编辑器写入 no-wave `contentBlocks` v0 纯文本块（首张图
  视为封面）；只读的结构化 v0/v1 解析器保留块、行内样式与媒体顺序，转换为
  阅读和朗读共用的惰性 AST，不构造 HTML。未知/损坏格式明确警告。站点相对
  资源仅按 `WEB_BASE_URL` 解析，不猜测 API origin；不安全的 URL 不可交互。
- **Failure 契约**（`core/error/failures.dart`）：`kind`
  （network/timeout/auth/permission/validation/storage/server/unknown）+
  面向用户的中文兜底 `message` + 稳定 `code` + 可选本地化标识 `l10nKey` +
  仅供诊断的 `cause`。UI 根据标识使用 ARB 资源显示本地化错误；原始异常
  文本不进入 UI（后端错误码经 `error_mapper` 分类）。
- **本地存储**：Drift (SQLite) 保存文章缓存、草稿、阅读历史与离线资料；
  会话通常保存在平台安全存储，不可用时可能回退 SQLite。新版草稿按后端、
  账号与文章隔离；旧版无归属草稿保留但不自动展示或分配，导出与降级限制见
  [旧草稿说明](docs/unclaimed-drafts.md)。阅读历史按用户 ID 去重（不区分
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
  不是完整快照；具体限制见 [首页分页说明](docs/latest-feed-cursor.md)。下拉刷新可重新加载。
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
中英、亮暗、窄屏大字和键盘操作有自动化覆盖。CI 已编译 iOS 模拟器版本并
检查测试配置的 ad-hoc IPA，但未完成 iOS/Android 真机视觉与 VoiceOver/TalkBack
验收，不能以自动测试或打包代替这些检查。

## 本地开发

本项目固定使用 **Flutter 3.47.8**（版本写在 `tool/flutter_version.txt`，CI 与
发布构建严格校验）。本地调试脚本只要求本机 SDK 的 Dart 版本满足 `pubspec.yaml`：
版本不一致时打印警告后继续启动，版本过低则给出升级步骤。需要精确匹配时可设置
`BELOG_STRICT_FLUTTER_VERSION=1`（PowerShell 也可加 `-StrictFlutterVersion`）；
iOS IPA 打包脚本始终要求精确版本。
Android 需要 Android Studio、Android SDK 的 emulator/platform-tools、已创建的
AVD 和 JDK 17（支持 17–20）。iOS 需要 macOS、完整 Xcode、iOS Simulator runtime、
CocoaPods 以及 Xcode 命令行工具。脚本只检查并使用现有工具，不安装 SDK、修改 AVD、
关闭模拟器或清除数据。

### 初始配置（每台机器一次）

从仓库根目录复制 `env.example.json` 为 `env.json`（Windows 用
`copy env.example.json env.json`，macOS 用 `cp env.example.json env.json`），
将 `API_BASE_URL` 改成 **设备/模拟器可访问的真实 no-wave API origin**。
`WEB_BASE_URL` 是可选的 no-wave Web origin，未使用时保持空字符串，分享入口
会隐藏，站点相对的正文图片和链接也无法加载或打开；它与 API origin 不能互相推导。
地址不要附加 `/api/v1`、路径、查询或
凭据，客户端会添加 `/api/v1`。模板的 `example.com` 是占位符，不可直接使用。

首次运行 Android 启动脚本时不必手工复制：`scripts\run_android.ps1`（及
`run_android.cmd`）发现默认 `env.json` 不存在时，会在交互终端里提示输入
`API_BASE_URL`（非法输入可重试三次）并写好后继续启动；也可以直接传入
`-ApiBaseUrl http://10.0.2.2:端口`，或设置 `BELOG_NO_PROMPT=1` 让脚本改为只打印
创建命令而不提问。脚本只写入这两个公开字段，不会猜测或验证你的后端地址。

`env.json` 和根目录下的 `env.*.json` 被 Git 忽略；传给 Flutter 的所有定义会
编译进应用，**不要放密码、API key、token、证书或其他秘密**，即使文件已忽略。
脚本只接受上述两个公开配置字段，不会输出文件内容。也可以用 `--config`/
`-Config` 指向其他本地 JSON（相对路径从仓库根目录解析）。

### Windows：一键启动 Android 调试

在仓库目录双击 `scripts\run_android.cmd`，或者在 PowerShell/命令提示符运行：

```powershell
.\scripts\run_android.cmd
.\scripts\run_android.cmd -ApiBaseUrl http://10.0.2.2:3000
.\scripts\run_android.cmd -Avd Pixel_8_API_35 -Config env.android.json -BootTimeoutSeconds 600
```

首次运行且没有 `env.json` 时，脚本会提示输入 API origin 并生成该文件（HTTPS 也可
直接传 `-ApiBaseUrl`）；已有的 `env.json` 不会被参数覆盖，需要换地址请直接编辑
文件或用 `-Config` 指向另一份。生成的 JSON 不带 BOM，只含两个公开字段。

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

### 本地启动常见阻塞

- **Flutter 版本不符**：脚本会打印实际版本与固定版本。若 Dart 版本仍满足
  `pubspec.yaml`（当前 `>=3.10.0`），调试会继续，只是与 CI 结果可能有差异。
  需要与 CI 完全一致时执行 `flutter upgrade`（或安装 3.47.8 并放在 PATH 最前），
  也可以设置 `BELOG_STRICT_FLUTTER_VERSION=1` 让漂移直接失败。
- **`flutter upgrade` 报 `upstream branch 'refs/heads/stable' not stored as a
  remote-tracking branch`**：这是 Flutter SDK 自身 Git 克隆缺少上游跟踪，不是
  本项目的问题。先修复 SDK，再升级：

  ```bash
  git -C "<Flutter SDK 目录>" fetch origin stable
  git -C "<Flutter SDK 目录>" branch --set-upstream-to=origin/stable stable
  flutter upgrade
  ```

- **`flutter pub get` 版本求解失败（`sqlite3` / `hooks` / `record_use` / `meta`）**：
  旧 Flutter SDK 把 `meta` 固定在旧版本，而 `sqlite3 >=3.6.0` 经 `hooks`
  → `record_use` 要求 `meta ^1.19.0`，于是报 `version solving failed`。dev-only 的
  `sqlite3` 约束已放宽到 `^3.5.2`（应用本身只用 Drift，它接受 `^3.4.0`），pub 会在
  旧 SDK 上解析到 3.5.2；固定版本的 CI 仍按 `pubspec.lock` 使用 3.8.0。若本地 lock
  仍按旧约束卡住，运行一次 `flutter pub upgrade sqlite3` 再启动，不要为了本地调试
  改回更高的下限。
- **启动后白屏**：现在不会再白屏。缺少 `API_BASE_URL`、地址非法或本地存储
  打不开时，首帧显示“无法启动 · Unable to start”，包含原始原因和修复命令
  （复制 `env.example.json` 为 `env.json`，或用启动脚本运行；启动脚本首次会
  提示/接受 `-ApiBaseUrl` 并自己生成 `env.json`）。VS Code 的默认
  `belog` 调试配置已带上 `--dart-define-from-file=env.json`。
- **后端没有启动**：App 仍可正常启动，不会崩溃或卡死。首帧会话恢复最多等待
  3 秒；首页在没有缓存时显示本地化网络错误与“重试”，有缓存时先显示缓存并
  标注来源；登录、发布等操作以同样的本地化错误反馈。启动脚本启用的
  `BELOG_DEV_BACKEND_CHECK` 只探测 `/api/v1/health`，因此后端不可达时约 3 秒内
  就能失败，而不是等 30 秒请求超时。把后端地址改成模拟器可访问的 origin
  （宿主机本地服务用 `http://10.0.2.2:端口`），或在后端启动后重试即可。

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

## GitHub Actions：个人设备安装包

改动合并到 `main` 后，可在 **Actions → Build personal mobile packages → Run workflow**
手动构建 IPA、APK 或两者。必须提供设备可访问的公开 no-wave HTTPS API origin；
地址会被编译进应用，不能填 token 或密码。IPA 不需要付费 Apple Developer 会员，
但下载后必须由 **AltStore Classic** 使用个人 Apple ID 重签；免费账号通常需每 7 天
刷新。Android `personal` 模式需要预先配置所有者的稳定签名密钥；`debug` 模式仅供
临时测试且不能保证跨构建升级。配置、下载、权限、限制与真机验收步骤详见
[docs/mobile-packages.md](docs/mobile-packages.md)。

## 发布

发布流程、签名与版本规则见 [docs/releasing.md](docs/releasing.md)。
CI 的 release-mode QA 构建需要显式 `BELOG_QA_BUILD=true` 且使用 debug 签名，
**不得**当作生产构建分发。另见
[docs/ci-observability.md](docs/ci-observability.md)、
[docs/isar-to-sqlite-migration.md](docs/isar-to-sqlite-migration.md)、
[docs/supabase-to-nowave-migration.md](docs/supabase-to-nowave-migration.md)、
[docs/agent-development.md](docs/agent-development.md)。

## 服务端（no-wave）差距与待办

客户端侧已迁移至 no-wave `apps/api`；剩余差距包含尚未接入的现有服务端能力、
部署验证和仍需服务端补齐的能力（以 [API 差距审计](docs/nowave-api-gap-audit.md)
及对应 issue 为准）：

- **G1 删除文章**：~~待补~~ **已解决**（软删 + 回收站 + 恢复已接入，
  `purgesAt` 30 天）。
- **G2 账号安全**：客户端已接入登录态改密（需当前密码；不自动重放，结果不明时提示先用新密码确认）。服务端“保留当前会话”的语义仍有问题，见 no-wave [#129](https://github.com/BrainEno/no-wave/issues/129) 与 [#132](https://github.com/BrainEno/no-wave/issues/132)；改邮箱 / 密码重置 / 邮箱验证尚未接入，邮件投递需单独配置和验证。
- **#23 离线发布队列**：no-wave 源码中的 `POST /articles` 已支持可选
  `Idempotency-Key`（no-wave #105），但实际部署版本/能力尚未确认；媒体上传
  幂等和孤儿清理仍待解决。本分支没有持久 outbox，草稿 PR #66 是安全子集，
  尚不能声称 #23 完成。
- **G3 `GET /me` 返回 email**：服务端已有返回；客户端当前仍使用本地登录邮箱。
- **媒体 `src` 字段缺 `/v1` 段**：上游小修（客户端已绕过）。

## 路线图

按 [issue 列表](https://github.com/BrainEno/flutter-blog/issues) 的优先级：

- **P2 已落地或部分落地**：Markdown 正文与编辑预览（#17）、阅读历史与有限数据导出（#22）、
  工程清理与图标配置修复（#25）、README/文档（#26）、中文文案与日期/阅读
  时长与中英双语本地化、无障碍适配（#24 部分）、分享（#21 出站部分）、评论（#19）、
  作者主页与关注（#20）
- **P2 进行中/延后**：分享深链接收（#21，等 web 部署 + association 文件
  可验证）、离线发布队列（#23，文章创建步已
  解锁、封面媒体仍受 #47 阻塞，见上）、举报屏蔽（#18）
- **P0/P1 已关闭**：#4 工具链升级、#7 schema 版本管理、#8 离线缓存语义

**许可证待定**：仓库暂无 LICENSE 文件；候选 MIT / Apache-2.0，定稿前请勿
分发二进制。相关讨论见 issue #26。

已完成的重点修复：草稿按后端、账号和文章隔离及快照安全清理（#14、#79）、Feed 分页与刷新竞态（#13）、
点赞并发与离线行为（#9）、异常契约统一（#12）、iOS 发布流水线（#6）、
点赞离线假成功（#3）、Supabase → no-wave 后端迁移、删除与回收站（G1）、
Markdown 正文（#17）、阅读历史与导出（#22）等。
