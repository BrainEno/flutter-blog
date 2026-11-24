# 本地开发

> 状态：active ｜ 最后核对：2026-11-19 @ 949a967

> 从根 README 移出（#298）。根 README 只保留「快速开始」；常见启动阻塞见
> [本地启动排障](troubleshooting.md)。

本项目固定使用 **Flutter 3.47.8**（版本写在 `tool/flutter_version.txt`，CI 与
发布构建严格校验）。本地调试脚本只要求本机 SDK 的 Dart 版本满足 `pubspec.yaml`：
版本不一致时打印警告后继续启动，版本过低则给出升级步骤。需要精确匹配时可设置
`BELOG_STRICT_FLUTTER_VERSION=1`（PowerShell 也可加 `-StrictFlutterVersion`）；
iOS IPA 打包脚本始终要求精确版本。
Android 需要 Android Studio、Android SDK 的 emulator/platform-tools、已创建的
AVD 和 JDK 17（支持 17–20）。iOS 需要 macOS、完整 Xcode、iOS Simulator runtime、
CocoaPods 以及 Xcode 命令行工具。脚本只检查并使用现有工具，不安装 SDK、修改 AVD、
关闭模拟器或清除数据。

## 初始配置（每台机器一次）

从仓库根目录复制 `env.example.json` 为 `env.json`（Windows 用
`copy env.example.json env.json`，macOS 用 `cp env.example.json env.json`），
将 `API_BASE_URL` 改成 **设备/模拟器可访问的真实 no-wave API origin**。
`WEB_BASE_URL` 是可选的 no-wave Web origin，未使用时保持空字符串，分享入口
会隐藏，站点相对的正文图片、链接和头像（`/avatars/...`）也无法加载或打开；
它与 API origin 不能互相推导。
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

## Windows：一键启动 Android 调试

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
`flutter pub get` 并以指定模拟器启动 `flutter run --debug --no-pub`。如果检测到
Pub 镜像归档哈希与 lockfile 不符，会仅重试一次官方 `pub.dev`；失败时提示而不
自动安装、删除或杀掉任何模拟器。若没有 AVD，请先在 Android Studio 的
Device Manager 创建；如找不到 SDK，设置 `ANDROID_SDK_ROOT` 或将 emulator 和
platform-tools 加入 PATH。可用 `emulator -list-avds` 查看 AVD 名称。

Android 模拟器中的 `localhost` 是模拟器自身，访问宿主机本地 API 通常使用
`http://10.0.2.2:端口`。一键脚本也支持已有配置使用 `localhost`、`127.0.0.1`
或 `::1`：开机后会自动执行 `adb reverse tcp:端口 tcp:端口`，把模拟器回环端口
转发到主机；手动运行 `flutter run` 时则需自行设置转发或改用 `10.0.2.2`。映射
保留到设备断开或手动移除；例如 `adb -s emulator-5554 reverse --remove tcp:4000`。
真机或其他模拟器必须使用它们能访问的地址。后端须自行启动，脚本不会启动或验证生产服务。

## macOS：一键模拟器调试与 IPA

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
分发资质，发布策略详见 [docs/releasing.md](releasing.md)。

## 调试网络与手动命令

Android `debug` 和 iOS `Debug` **仅开发构建**允许明文 HTTP（包括非本地地址）；
profile/release 不放宽平台安全策略。HTTP 会明文传输密码和会话，请仅在受信任
的隔离开发环境使用测试账号，生产及 IPA 使用 HTTPS。前置探测在所有构建模式
都请求配置后端的 `/api/v1/health`（无凭据），使没有公网的本地后端、私网部署和
离线演示环境仍可使用；HTTP 错误响应表示服务器可达，具体错误由真实 API 请求
报告。每次检查多一次短请求，不做任何公网探测；`BELOG_DEV_BACKEND_CHECK`
仍可传入但已无作用。

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
风险见 [docs/code-audit.md](code-audit.md)。

## 依赖升级

`pubspec.lock` 已入库，但 CI 与所有脚本只跑 `flutter pub get`（没有
`--enforce-lockfile`），所以改约束不会被锁死，也不会自动升级。升级目标包前先确认
它与固定的 Flutter 3.47.8 兼容：

```bash
flutter pub outdated                 # 需要能访问 pub.dev
flutter pub upgrade --major-versions # 或逐个改 pubspec.yaml
flutter pub get
```

`drift`（当前精确锁定，见 `docs/sqlite-storage.md`）和 `sqlite3`（下限故意放低，
旧 SDK 才能求解，见 `pubspec.yaml` 注释与 [本地启动排障](troubleshooting.md)）的约束
都有原因，不要顺手改高下限。`flutter_lints` 没有这类限制：2026-11 已升到 6
（`lints` 6.1），新规则 `use_null_aware_elements`（`if (x != null) x` 写成 `?x`）与
`unnecessary_underscores`（`__` 写成 `_`）已在全仓库修完。`go_router` 同月从 14 升到 18：
路径从 15 起区分大小写（应用内路径都是小写常量，深链统一改写成 `/view/<slug>`，
所以没有可达的变化）；17 起 shell 路由默认把标签内的跳转也通知根 observer，
`lib/router/app_router.dart` 显式设 `notifyRootObserver: false`，保持升级前
「根 observer 只看根 navigator」的行为（`test/widget/router_test.dart` 守护）。大版本升级后至少跑
`flutter analyze --fatal-infos`、`flutter test` 与
`python3 -m unittest discover -s scripts/tests`，再交给 CI 判定。
