# GitHub Actions：个人安装用 IPA / APK

本文针对仓库所有者自己安装和调试。新流程位于 **Actions → Build personal mobile packages**，以 `workflow_dispatch` 手动运行；workflow 必须先合并到默认分支，GitHub 才会显示该入口。两个平台彼此独立，构建 iOS 不需要 Android keystore、Apple 开发者会员、Apple 证书、Apple ID 或密码上传到 GitHub。此流程只上传 Actions artifacts，不创建或覆盖 GitHub Release。

## 先准备后端

客户端需要已部署且设备能够访问的 **no-wave API HTTPS origin**，例如 `https://api.your-domain.tld`（示例并非可用后端）。不能填 `/api/v1`、路径、用户名密码、查询参数、token、`localhost` 或模板地址。可选的 `WEB_BASE_URL` 是独立的网页 origin；不设置时文章分享入口保持隐藏，站点相对的正文资源与头像也不会加载（保留中性占位）。两者可直接在 Actions 表单中输入，或者作为仓库级 Actions Variables `API_BASE_URL` / `WEB_BASE_URL` 预先配置；表单优先。两个平台使用同一次验证得到的相同配置。

这些地址会编译进应用，也可能对能下载 artifact 的人可见，**不能是秘密**；不要放任何 API key、密码、证书、Apple ID、用户 token 或真实用户数据。流程检查 HTTPS 和格式，**不证明**域名可解析、TLS 被设备信任、no-wave 服务已经部署、API 协议兼容或后端可用。没有真实可访问的 API 就不能产出可联网使用的个人包。PR 验证固定使用不可访问的测试地址和临时密钥，不会上传供个人安装的包。PR 的 Android personal 和 debug 验证各用独立 runner，避免同一工作区累积两套构建中间产物；日志记录磁盘余量，但不能保证 runner 永远不会耗尽空间。手动打包路径不变。

## 手动运行

1. 确认改动已合并 `main`，打开仓库 **Actions → Build personal mobile packages → Run workflow**，选择 `main`。
2. `target` 选 `ios`、`android` 或 `both`。填写公开的 `api_base_url` 和可选 `web_base_url`（或使用上面的仓库变量）。
3. 选择 Android `personal`（使用自己的稳定签名 key）或 `debug`（临时测试 key，下文说明）；只选 `ios` 时此项不影响 IPA。
4. 可选 `build_number` 默认取此 workflow 的运行序号，并须不小于 `pubspec.yaml` 的 `+BUILD`、不超过 Android 上限 2100000000。版本名取 `pubspec.yaml` 中的 `MAJOR.MINOR.PATCH`。如果设备上已有更高版本码，手动填入不低于已安装版本、后续递增的数字；签名、包名和版本码均影响升级。
5. 等待所选 job 成功，在该次 run 的 **Artifacts** 下载并先解压外层 GitHub ZIP，找到 `.ipa` 或 `.apk`；`SHA256SUMS.txt` 可用于核对下载完整性，`BUILD-INFO.txt` 记录提交、版本和产物类型。artifact 保留 30 天（受仓库/组织上限约束）；过期后须重新运行或由所有者自行安全保存。

`both` 时 iOS 和 Android 分别构建、分别上传。Android 缺少签名配置或受环境审批阻止，不影响独立的 iOS job；整体 run 可能因此显示失败或等待审批，仍可下载已成功 job 的 artifact。失败不会静默退回 debug key 或上传半成品。

## 用 AltStore Classic 安装 iOS

`BottomThink-ios-altstore-resign-required.ipa` 是 `flutter build ios --release --no-codesign` 后进行 **ad-hoc 签名（没有 Apple 身份、没有 provisioning profile）**、放入 `Payload/Runner.app` 的输入包。它**不能直接安装或运行**，不是 App Store/TestFlight 包；需要 **AltStore Classic** 在安装前用你的免费个人 Apple ID 重新签名并配置设备。AltStore PAL 和 Classic 是不同的产品，请使用支持自选 IPA 的 Classic。无需付费 Apple Developer Program 会员，也不要把 Apple ID、密码或验证码提供给 GitHub Actions 或本项目。

1. 参考 [AltStore Classic 官方安装说明](https://faq.altstore.io/getting-started/how-to-install-altstore)，在 Mac/Windows 电脑安装 AltServer，并将 AltStore Classic 安装到 iPhone/iPad。
2. 按 AltStore/iOS 的引导信任设备与开发者配置；iOS 16 及以后通常还需在 **设置 → 隐私与安全性 → 开发者模式**启用并重启。
3. 把下载并解压后的 `.ipa` 放进 iPhone 的“文件”，在 AltStore Classic 的 **My Apps → +** 选取它（或通过文件分享给 AltStore）。AltStore 使用你的个人 Apple ID 重新签名；首次安装/刷新要按 AltStore 要求连接 AltServer 和设备。
4. [AltStore 官方说明](https://faq.altstore.io/altstore-classic/your-altstore)：免费个人账号安装的应用通常 **7 天到期**，须在到期前让 AltServer 可用并在 AltStore 刷新；后台自动刷新不能保证始终成功。Apple 对活跃侧载应用和 App ID 有数量限制（通常 3 个活跃应用，AltStore 本身占一席）。过期、账户限制、系统更新或证书撤销都可能影响运行，不能承诺永久免维护。

IPA 经过归档结构、iPhoneOS/arm64 架构、包标识/版本、隐私提示、明文网络策略、归档完整性及嵌套 ad-hoc 签名检查，但这些不替代**实际 AltStore 重签、真机启动、联网及语音/相册测试**。App 当前最低 iOS 13；AltStore 和设备本身可能有更高要求。安装失败时先核对具体 AltStore 提示，不要为排错直接删除现有应用：卸载可能删除本地草稿和其他应用数据。

## Android：稳定签名的个人 APK

`personal` 用已有正式/个人 keystore 签名 release APK，并验证签名指纹、包名 `com.nodeman24.nowave`、版本、最终权限、非调试/禁止明文、ARM 32/64 位及 16 KiB 对齐。**稳定升级需要始终使用同一个签名证书和兼容的版本码**；如果曾安装过其他 key 签名的同包名应用，Android 不允许直接覆盖。不要在没有可靠备份前卸载旧应用，卸载可能清除本地草稿和数据。应用 ID 自 0.2.0 起统一为 `com.nodeman24.nowave`：与旧 `com.example.belog` 安装是**两个应用**，不就地升级、不共享数据，迁移步骤见 [releasing.md](releasing.md#upgrading-from-the-previous-identifier)。

在 GitHub **Settings → Environments → production** 中限制允许部署的分支为 `main`，按需启用审批；复用正式发布流程的环境变量/Secrets：

- Variables：`ANDROID_APPLICATION_ID_APPROVED` = `com.nodeman24.nowave`；`ANDROID_RELEASE_CERT_SHA256` = 所有者独立核对的签名证书 SHA-256 指纹（64 位十六进制，无冒号）。
- Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。

已有用户时应使用原签名 key，不要生成新 key。首次安装且没有旧 key 时，可在自己的电脑用 JDK `keytool -genkeypair -keystore <安全位置> -alias <别名> -keyalg RSA -keysize 3072 -validity 10000` 创建并按交互提示设置密码；妥善备份 keystore 与密码，切勿提交到仓库或发到聊天。用 `keytool -exportcert -rfc -keystore <安全位置> -alias <别名> | openssl x509 -noout -fingerprint -sha256` 独立取得指纹并去掉冒号；本机安全地将 keystore 的 base64 值放入对应 GitHub Secret。不要在公开终端、日志、截图或工作流输入里粘贴它们。丢失 key 将影响未来覆盖升级。

尚未配置个人 key 时，可选 `debug` 获取 `BottomThink-android-debug-temporary-key.apk` 用于临时调试。它**可调试、使用临时 debug 证书、允许 debug 明文网络策略**，不是正式包，每次 GitHub runner 生成的证书可能不同，不能保证升级或和个人签名版互相覆盖；不应分发或用于长期保存唯一数据。只有 `personal` 能提供由所有者控制的持续签名身份。项目最低 Android API 23。

## 实际权限与检查

- Android main manifest 明确声明 `INTERNET` 与 `ACCESS_NETWORK_STATE`，这两项为系统安装时授予的普通权限。流程检查**最终 APK**，而非只检查源码；HTTPS、mailto 和 TTS 服务可见性也已声明。
- 目前选择文章封面/头像使用系统图片选择器，不需要申请整个存储或相册权限；Android 没有盲目申请相机、麦克风、定位或全部文件权限。分享和系统朗读不需要录音权限。
- iOS 已提供相册和相机用途说明及中英文提示；实际是否显示照片授权提示由 iOS/选择器决定。系统权限须由用户在设备上响应，构建脚本不能替用户预先授予或绕过。当前代码只选择相册，不主动拍照。
- 打包 CI 只检查 manifest/Info.plist、结构和签名，不证明权限提示、选图、API、登录、分享、语音及生命周期在每种 iOS/Android 设备上都正常。建议安装后逐项手测；签名更新或系统版本变化也应重新验证。
