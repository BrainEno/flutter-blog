# belog

Flutter 编写的移动博客客户端（应用内品牌：Bottom Think），后端使用
[Supabase](https://supabase.com)（Postgres + Auth + Storage）。支持离线缓存阅读、
本地草稿、点赞收藏、按标签浏览与标题搜索。

## 功能

- 账号：邮箱注册 / 登录 / 退出，注册邮箱确认（深链回调自动登录），
  找回密码（重置邮件深链），个人资料编辑（昵称、网站、头像）
- 文章：发布 / 编辑 / 删除，封面图上传（压缩 + 版本化路径 + 旧对象清理），
  标签分类
- 浏览：分页 Feed、下拉刷新、滚动加载更多、按标签筛选、标题搜索（含防抖与结果上限）
- 互动：点赞 / 取消点赞（乐观更新 + 服务端状态校准），个人收藏列表
- 草稿：按文章隔离的本地草稿、恢复 / 丢弃对话框、2 秒防抖自动保存、发布后自动清理
- 离线：文章列表与详情 SQLite 缓存，离线可读；网络操作离线时快速失败并提示
- 主题：亮 / 暗 / 跟随系统，偏好本地持久化

## 深链与邮箱流程（auth callback）

注册确认与密码恢复邮件里的链接使用自定义 scheme 重定向回应用：

- **回调 URL**：`belog://auth-callback`
- **Android**：`android/app/src/main/AndroidManifest.xml` 中 MainActivity 的
  `intent-filter`（scheme `belog` + host `auth-callback`）
- **iOS**：`ios/Runner/Info.plist` 的 `CFBundleURLTypes`（scheme `belog`）
- **应用内**：`lib/features/auth/auth_link_handler.dart` 接收链接
  （`app_links`），用 gotrue 的 `getSessionFromUrl` 建立会话，按产生的
  auth 事件区分流程（`signedIn` = 邮箱确认、`passwordRecovery` = 密码恢复），
  并通过全局 SnackBar 给出成功 / 失败反馈
- **会话同步**：`lib/features/auth/auth_session_sync.dart` 订阅
  `onAuthStateChange`（signedIn / signedOut / tokenRefreshed / userUpdated /
  passwordRecovery），同步 `AppUserCubit`；token 刷新失败导致的登出同样生效

**owner 待办（控制台动作）**：在 Supabase Dashboard →
Authentication → URL Configuration → Redirect URLs 中加入
`belog://auth-callback`，否则邮件中的按钮不会带自定义 scheme 跳转。
密码恢复链接登录后，引导用户到「我的 → 账号安全」设置新密码。

## 账号安全约定

- **邮箱变更**：仅通过「账号安全」页（Supabase Auth `updateUser(email:)` +
  新邮箱确认邮件）。个人资料编辑页**不写** `profiles.email`
  （`UserModel.toProfileUpdateJson()` 刻意排除该列）。
- **密码变更**：`updateUser(password:)` 成功后自动 `signOut(scope: others)`
  撤销其他设备的会话（尽力而为，失败仅记日志）。
- **reauthentication**：若项目开启了"近期身份验证"要求，敏感更新会返回
  `reauthentication_required`，客户端映射为
  "出于安全考虑，请退出后重新登录，再进行此操作" 并原样传播到 UI。
- **注册确认**：`signUp` 未返回 session 时进入"请确认邮箱"等待页
  （可重发确认邮件），绝不把 auth user 当作已登录；
  profile 的创建由服务端触发器负责（见下节）。

## 架构

按 feature-first + 核心层分层的简化整洁架构：

```
lib/
├── core/                  # 与业务无关的基础设施
│   ├── common/            # 全局 cubit（AppUser）
│   ├── error/             # Failure 契约 + 异常映射（error_mapper）
│   ├── network/           # 连接检查
│   ├── storage/           # Drift/SQLite：缓存、草稿、主题（legacy/ 为旧 Isar 模型）
│   ├── theme/             # 主题与 ThemeBloc
│   └── utils/             # AppLogger、重试、Snackbar 等
├── features/
│   ├── auth/              # 登录注册（Supabase Auth）
│   ├── blog/              # 文章域：datasources / repository / usecases / blocs / pages
│   └── user/              # 个人资料与账号修改
├── router/                # go_router 路由（页面级 bloc 随页面创建销毁）
└── main.dart              # 入口 + 全局错误钩子
```

关键约定：

- **数据流向**：UI → Bloc → Usecase → Repository（`Either<Failure, T>`）→
  Datasource。Repository 是唯一把异常翻译成 `Failure` 的地方。
- **Failure 契约**（`core/error/failures.dart`）：`kind`
  （network/timeout/auth/permission/validation/storage/server/unknown）+
  面向用户的中文 `message` + 稳定 `code` + 仅供诊断的 `cause`。
  原始异常文本永远不会进入 UI。
- **本地存储**：Drift (SQLite) 保存文章缓存与草稿。缓存按业务 ID upsert 去重；
  草稿按 `blog_id` 作用域隔离（`null` = 新文章）。

## 本地开发

```bash
flutter pub get
flutter run            # 需要 Supabase 配置（见下）
flutter analyze
flutter test
dart format lib test
```

- Flutter 版本：CI 使用 **3.47.8**（stable），本地请保持一致。
- Android 构建需要 JDK 17–20（AGP/Gradle 兼容范围），如遇冲突执行
  `flutter config --jdk-dir=<JDK_DIRECTORY>`。
- `lib/core/secrets/` 中包含 Supabase 连接配置（当前仓库内置的是共享测试项目）。

## 测试与 CI

`.github/workflows/ci.yml`（PR / push 到 main 时运行，Flutter 3.47.8 + JDK 17）：

1. **format**：对本次改动的 `.dart` 文件强制 `dart format` 通过
   （全仓库格式审计仅告警，不阻断）。
2. **analyze**：`flutter analyze --fatal-infos`，零告警门禁（`avoid_print`
   已启用，请使用 `AppLogger`）。
3. **test**：`flutter test --coverage --concurrency=1`。
4. **build**：Android/iOS debug 构建冒烟（iOS 构建在 macOS runner 上执行）。

单元与 widget 测试覆盖：分页/刷新竞态（BlogBloc）、搜索竞态（BlogSearchBloc）、
点赞并发与回滚、草稿隔离与自动保存、异常映射矩阵、离线行为等。

## 发布

发布流程、签名与版本规则见 [docs/releasing.md](docs/releasing.md)。
CI 的 release-mode QA 构建需要显式 `BELOG_QA_BUILD=true` 且使用 debug 签名，
**不得**当作生产构建分发。另见
[docs/ci-observability.md](docs/ci-observability.md)、
[docs/isar-to-sqlite-migration.md](docs/isar-to-sqlite-migration.md)、
[docs/agent-development.md](docs/agent-development.md)。

## 服务端（Supabase）待办

本仓库目前只包含客户端，Supabase schema / RLS / Storage policy 尚未纳入版本管理
（[#7](https://github.com/BrainEno/flutter-blog/issues/7)）。以下 SQL 需要项目
owner 在 Supabase 控制台执行，是点赞并发修复的**服务端部分**：

```sql
-- 每个用户对每篇文章最多一个赞（客户端 toggle 依赖它防并发重复）
alter table likes add constraint likes_user_blog_unique unique (user_id, blog_id);

-- 行级安全：用户只能操作自己的点赞
alter table likes enable row level security;
create policy "likes are user-scoped" on likes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 标题搜索的性能索引（当前为 ilike 子串匹配，中文无需分词）
create index if not exists blogs_title_lower_idx on blogs (lower(title));
```

> 说明：客户端已按"先删后插"的原子语义实现 toggle，即使约束尚未加上也不会
> 双重翻转；但缺少唯一约束时极端并发可能产生重复行（下次 toggle 会自愈）。

**profile 创建归属（重要）**：`profiles` 行由服务端触发器
（`handle_new_user`，auth.users 插入后同步插入 profiles）负责创建，
客户端不做任何 profiles 插入。注册后若触发器缺失，客户端在
`getCurrentUserData` 中得到空 profile，会按"登录状态已失效"处理而不是
伪造登录态。owner 需在 Supabase 控制台确认该触发器存在（#7 待纳入版本管理）。

## 路线图

按 [issue 列表](https://github.com/BrainEno/flutter-blog/issues) 的优先级：

- **P0**：#4 Android Gradle 工具链升级
- **P1**：#7 Supabase schema/RLS 纳入版本管理 · #8 Isar 离线缓存语义 ·
  #10 图片压缩/MIME/孤儿对象 · #11 会话恢复与账号安全闭环
- **P2**：Markdown 正文、评论、关注、举报屏蔽、分享深链、离线发布队列、
  阅读历史、国际化与无障碍、工程清理等（#15–#26）

已完成的重点修复：草稿按文章隔离与发布清理（#14）、Feed 分页与刷新竞态（#13）、
点赞并发与离线行为（#9）、异常契约统一（#12）、iOS 发布流水线（#6）、
点赞离线假成功（#3）等。
