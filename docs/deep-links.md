# 分享与深链（#21）

> 状态：active ｜ 最后核对：2026-11-19 @ de5e8bc

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
