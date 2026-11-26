# 分享与深链（#21）

> 状态：active ｜ 最后核对：2026-11-25 @ d076e1b

> 从根 README 移出（#298）。行为以 `lib/core/utils/article_deep_link.dart` 与
> `lib/router/app_router.dart` 为准。

**出站分享（可用）**：阅读页的分享按钮只在配置了 `WEB_BASE_URL` 时出现，payload
是**标题 + 一段纯文本摘要 + canonical URL**（`https://<WEB_BASE_URL>/articles/<slug>`）。
摘要取正文第一条有内容的行，去掉标题/引用/列表/链接/强调标记后最多 120 字符；
分享内容只由公开 slug 拼接，不含草稿、本机路径、token 或临时签名 URL。

**入站深链（已接入，真机未验收）**：

| 形式 | 今天的行为 |
| --- | --- |
| `nowave://article/<slug>` | 应用内打开文章。Android intent-filter 与 iOS `CFBundleURLTypes` 已声明，冷启动与运行中收到都会改写成 `/view/<slug>` |
| `https://<WEB_BASE_URL>/articles/<slug>` | 应用会把**自己 web origin** 上的文章 URL 解析成同一篇文章；但系统目前仍把它交给浏览器。要让点击直接进 App 需要把 `assetlinks.json` / `apple-app-site-association` 托管在 web origin 并完成域名校验——本仓库没有这些文件，也不声称做过 |
| 其它 scheme / 其它站点 / 缺少 slug | 不当成文章：按普通路由处理，未知路径落到「页面不存在 + 返回首页」 |
| 文章不存在、已删除或未公开 | 链接只携带 slug，可见性仍由服务端决定：阅读页按普通取文失败展示本地化错误与重试，不因「来自链接」而绕过 |

实现只有两处：`core/utils/article_deep_link.dart` 是纯函数（URL → 应用内位置，
含 scheme/主机/路径段/编码/超长校验），`router/app_router.dart` 的 `redirect`
在匹配前改写。`flutter test` 覆盖这些映射和「冷启动、运行中」两种进入方式，
但不能代替真机：Android 用
`adb shell am start -a android.intent.action.VIEW -d "nowave://article/<slug>"`，
iOS 用 `xcrun simctl openurl booted "nowave://article/<slug>"`，各跑一次才算验收。


## 让 https 链接进 App：前置条件、验证方式与 owner（#367）

上一节的表格说明「今天是什么」，这一节是给「要变成什么」用的清单。仓库这一侧能
钉住的已经钉住：`scripts/tests/test_platform_configs.py` 的
`ArticleDeepLinkSurfaceTests` 断言 Android 只有一个 `nowave://article` 的 VIEW
过滤器（没有 `autoVerify`、没有 `*`、没有 `pathPrefix`）、iOS 两个 plist 的
`CFBundleURLTypes` 恰为 `['nowave']` 且没有 `com.apple.developer.associated-domains`
entitlement，并把这三处与 `lib/core/utils/article_deep_link.dart` 里的
`kArticleDeepLinkScheme` / `kArticleDeepLinkHost` 对齐。于是「先声明、后补验证」
这种半截配置进不来；反过来说，**下面每一行都在仓库之外，谁打勾都写明了**。

| # | 前置条件 | 落点 | owner | 怎么验证 |
| --- | --- | --- | --- | --- |
| 1 | 定下 canonical HTTPS origin，并与 dart-define 的 `WEB_BASE_URL` 完全一致（含是否带 `www`、是否带端口） | DNS／反代 + 构建参数 | 域名与部署维护者 | `curl -fsSI "https://<origin>/articles/<slug>"` 返回 200，且 origin 与 App 分享按钮拼出来的那个字符串一字不差 |
| 2 | 正式 Android application ID 与 release 签名证书指纹 | `android/app/build.gradle` + keystore（**不进 Git**，见 `docs/releasing.md`） | 应用发布 owner | `openssl x509 -noout -fingerprint -sha256 -inform pem -in <cert.pem>` 的值与将写入 `assetlinks.json` 的 `certificate_fingerprint` 一致（分隔符格式两种都要看一眼） |
| 3 | 在 web origin 上托管 `/.well-known/assetlinks.json` | 服务器/静态目录 | 域名维护者 | `curl -fsSI https://<origin>/.well-known/assetlinks.json`：`content-type: application/json`、不 301 到别的 origin、无鉴权；正文含 `relation: ["delegate_permission/common.handle_all_urls"]`、`target.namespace: "AndroidApp"`、第 2 行的 package 与指纹 |
| 4 | 托管 `/.well-known/apple-app-site-association`（**无 `.json` 后缀**） | 同上 | 同上 | `curl -fsSI` 同样要求 `application/json` 且公开可读；正文 `applinks.details` 里 `apps: []` + `paths: ["/articles/*"]`，`appIDs` 写成 `<TeamID>.<bundle id>` |
| 5 | iOS 打开 associated domains capability（会新增 `.entitlements` 并改变签名） | `ios/Runner/Runner.entitlements` + Xcode signing | 持有 Apple 开发者账号的 owner | 重新签名装机后，Safari 里点文章链接应直接进 App。**注意**：一旦 `ios/` 下出现 `.entitlements`，`ArticleDeepLinkSurfaceTests` 会红——那是在提醒你在同一个 commit 里把断言从「没有 associated-domains」改成「associated-domains 只含 `applinks:<批准 origin>`」 |
| 6 | Android 增加带 `android:autoVerify="true"` 的 https intent-filter，host 只列批准的 origin | `android/app/src/main/AndroidManifest.xml` | 客户端 owner 与域名维护者**同一次**改动 | 装好后 `adb shell pm get-app-links <applicationId>`，批准的 origin 那行状态须为 `verified` |
| 7 | 设备侧验收：冷启动与热启动 × 普通 slug、编码/非 ASCII slug（如 `/articles/詩-1a2b`）、非文章 URL、malformed URL；未安装 App 时回退浏览器 | 真机或模拟器 | 跑验收的人 | 自定义 scheme 现在就能试：`adb shell am start -a android.intent.action.VIEW -d "nowave://article/<slug>"`、`xcrun simctl openurl booted "nowave://article/<slug>"`；https 那两行等第 3–6 行齐了再跑，同一份清单也服务 #365 的屏幕验收 |

**这些命令在沙箱里没有设备与域名可跑，因此都是未执行的**——它们是给 owner 的核对
方式，不是仓库测试的证据。仓库测试能负责的只有「配置没有被写宽」和「URL → 应用内
位置的映射正确」（`test/unit/core/article_deep_link_test.dart` 与
`test/widget/*` 的冷启动/运行中用例）。

**顺序建议**：1 → 2 → 3/4（先让服务器给得出两个文件，再动客户端），因为反过来
做会得到一个「声明了但验证不过」的中间态——Android 在这种情况下不报错，只是把链接
留给浏览器，最难查。第 6 行之前的任何时刻，App 的行为都还是今天表格里写的那样。
