# 本地启动排障

> 状态：active ｜ 最后核对：2026-11-19 @ de5e8bc

> 从根 README 移出（#298）。配置与脚本用法见 [本地开发](local-development.md)，
> 连通性证据的边界见 [API 连通性证据](api-connectivity-evidence.md)。

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

- **`flutter pub get` 提示 `Downloaded archive ... had wrong content-hash`**：这是 Pub
  镜像返回的归档内容与 `pubspec.lock` 的 SHA-256 不符，不是 Flutter 版本问题。不要改锁文件
  哈希或关闭校验；`run_android.cmd` 会在明确的哈希不符时向官方 `https://pub.dev`
  重试一次，继续使用 Pub 的锁文件完整性校验，随后以 `flutter run --no-pub` 启动，
  避免再次访问坏镜像。若机器无法访问 `pub.dev`，需要恢复官方源连通性，或换用能返回
  锁定原始归档的可信镜像；
  `FLUTTER_STORAGE_BASE_URL`（Flutter SDK/引擎下载源）不受影响。
- **`flutter pub get` 版本求解失败（`sqlite3` / `hooks` / `record_use` / `meta`）**：
  旧 Flutter SDK 把 `meta` 固定在旧版本，而 `sqlite3 >=3.6.0` 经 `hooks`
  → `record_use` 要求 `meta ^1.19.0`，于是报 `version solving failed`。dev-only 的
  `sqlite3` 约束已放宽到 `^3.5.2`（应用本身只用 Drift，它接受 `^3.4.0`），pub 会在
  旧 SDK 上解析到 3.5.2；固定版本的 CI 仍按 `pubspec.lock` 使用 3.8.0。若本地 lock
  仍按旧约束卡住，运行一次 `flutter pub upgrade sqlite3` 再启动，不要为了本地调试
  改回更高的下限。注意 CI 只在固定版本上验证，3.5.2 这一组合没有 CI 作业覆盖；
  出现构建钩子（native assets）错误时仍应升级到固定版本。
- **启动后白屏**：现在不会再白屏。缺少 `API_BASE_URL`、地址非法或本地存储
  打不开时，首帧显示“无法启动 · Unable to start”，包含原始原因和修复命令
  （复制 `env.example.json` 为 `env.json`，或用启动脚本运行；启动脚本首次会
  提示/接受 `-ApiBaseUrl` 并自己生成 `env.json`）。VS Code 的默认
  `No Wave` 调试配置已带上 `--dart-define-from-file=env.json`。
- **env.json 填对了仍提示 API base URL not configured**：旧提交把
  `String.fromEnvironment('API_BASE_URL')` 写在普通 getter 里，而不是 `const`
  字段；Dart 只在 const 上下文保证读到 `--dart-define`/`--dart-define-from-file`
  的值，Android 上会静默回落成空字符串，于是启动脚本已经打印
  `Public client configuration OK.`，App 首帧仍显示“无法启动”。现在
  `AppSecrets` 用 `static const` 字段读取，这两个值只在 const 上下文求值；
  CI 增加了一步用 `--dart-define-from-file=env.json` 运行的
  `test/unit/core/app_secrets_define_test.dart`，防止再次退化成非 const 读取。
  拉取最新代码重新 `flutter run` 即可，不需要改 `env.json` 或启动脚本。
- **登录/点赞时提示“无法连接到网络”**：这条提示有两个来源，先分清再看。
  一是**前置探测**（任何请求发出之前）：**所有构建模式、所有 origin** 都直接用
  `GET /api/v1/health` 探测配置的后端本身（不带 Authorization/Cookie），公网探测
  不参与任何判定——公网探测在机器或模拟器连不上自己的公共端点时会把可达的后端
  判成离线，release/profile 里甚至会让真实请求一次都没发出（#105：私网部署、
  离线演示、公网受限但 API 可达的网络）。`BELOG_DEV_BACKEND_CHECK` 启动脚本仍会
  传，但已不改变行为。探测**只在明确的传输失败**
  （`SocketException`/`ClientException`：拒绝连接、无路由、明文被拦）时判离线；
  **探测超时（`TimeoutException`）不再等于离线**——冷启动的开发服务器、断点暂停或
  慢代理都可能超过 3 秒探测预算却仍能响应真实请求（真实请求的预算长得多），
  所以超时按“无法判定”处理，交给请求自己报错。二是**真实请求的传输错误**，
  说明配置的 origin 连不上。两种情况都会留下证据：登录页底部、登录失败提示条上的
  「查看诊断信息」按钮，以及「我的 → 关于我们」（按钮或长按版本号）都会打开诊断弹窗，
  也可直接访问 `/about?diagnostics=1`。弹窗内可复制、分享，或「导出日志文件」——把应用版本、
  构建、API origin 与最近至多 100 条脱敏记录写成文本文件交给系统分享面板，仅由用户
  主动触发，不自动上传（缓冲最多保留 24 小时，见 `lib/core/utils/diagnostics_file_export.dart`）；探测与请求记录形如
  `probe GET /api/v1/health inconclusive (TimeoutException after 3001ms, budget 3000ms)`
  或 `request POST /api/v1/auth/login unreachable (SocketException)`，debug 控制台里
  也会打印实际探测的 origin。本机先自查 `curl http://localhost:4000/api/v1/health`；
  连不上时重点看后端监听地址：Node/Express 里 `listen(4000, 'localhost')` 在 Windows
  上只绑定 `::1`，而模拟器的 `10.0.2.2` 走 IPv4 回环，可能被直接拒绝——改成监听
  `0.0.0.0`（或 `::`）。不改绑定时，`adb reverse tcp:4000 tcp:4000` 可将模拟器
  `localhost:4000` 转回主机；一键脚本检测到 `localhost` / `127.0.0.1` / `::1`
  配置会自动执行。手动运行 Flutter 时仍需自己执行 reverse，或改用
  `http://10.0.2.2:4000`。
- **先看这一行**：`API_BASE_URL` 是**编译期**注入的（`AppSecrets`），所以「连不上」先要确认
  手上这个包到底指向哪个后端。debug 控制台启动时会打印
  `api origin: http://10.0.2.2:4000 (http, debug build allows cleartext)`；同一个头部
  行也出现在诊断信息里（登录页底部 / 「我的 → 关于我们 → 查看诊断信息」，或
  `/about?diagnostics=1`），装好的包也能直接看到。读法：
  - origin 是 `https://example.invalid` → 这是 CI 编出来的 QA 包（CI 固定用不可达的
    假地址，见发布文档），它永远连不上你的后端，换成本地构建；
  - 结尾是 `(http, release/profile builds block cleartext on Android and iOS)` →
    这个包是 release/profile，系统会直接拦掉明文 HTTP，只能用 debug 构建或让后端走 HTTPS；
  - origin 里是 `localhost`/`127.0.0.1` → 模拟器里那是模拟器自己，见下一条；
  - 改过 `env.json` 后必须**重新构建**，热重启不会重新读取编译期常量。
- **后端没有启动**：App 仍可正常启动，不会崩溃或卡死。首帧会话恢复最多等待
  3 秒；首页在没有缓存时显示本地化网络错误与“重试”，有缓存时先显示缓存并
  标注来源；登录、发布等操作以同样的本地化错误反馈。前置探测（所有构建模式）
  只请求配置后端的 `/api/v1/health`：拒绝连接会立即判离线并提示，
  超时则视为无法判定、放行真实请求（最多 30 秒后按请求自身的结果报错，
  诊断里会留下 `timeout POST /api/v1/auth/login (budget 30000ms)`）。把后端地址改成
  模拟器可访问的 origin（宿主机本地服务用 `http://10.0.2.2:端口`），或在后端启动后
  重试即可；模拟器里也可用 `adb shell "toybox wget -O - http://10.0.2.2:4000/api/v1/health"`
  直接验证连通性。
