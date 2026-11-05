# 通知收件箱（#23 之后）

通知只有一个来源：服务端在事件发生时写入的收件箱。**它没有推送**——no-wave 目前
只提供 `me.notifications*` 这组 REST 接口，没有移动设备令牌、SSE 或 WebSocket，
所以客户端能做的是「进页面读一次」，而不是「实时提醒」。

## 与服务器的契约

| 接口 | 客户端用法 |
| --- | --- |
| `GET /me/notifications?limit=50` | 唯一的数据来源；`1..100`，默认 50，越界 400 |
| `PUT /me/notifications/{id}/read` | 单条已读；服务端 `COALESCE` 保留首次已读时间，可重复提交 |
| `POST /me/notifications/read-all` | 全部已读；返回本次变更数 |
| `GET /me/notifications/unread-count` | **未使用**：列表已经带着 `readAt`，未读数由当前页推导，少一次请求就少一次失败面 |

一行形如 `{id, eventKey, payload, createdAt, readAt|null}`。`payload` 是**字符串**
（服务端对事件投影做 `JSON.stringify`），客户端解析一次，绝不原样显示。

## 客户端行为

- **进页面读一次 + 下拉刷新。** 不轮询、不定时器、不假装推送；页面停留期间不会
  自行变化，用户下拉即重新读取。
- **不落盘、不缓存、不写日志。** 通知只活在当前页面的内存里；离线打开就是离线
  失败，不会拿旧列表冒充新状态。
- **账号围栏全程携带。** 每次请求都带发起时的 `NowaveSessionFence`；请求在途时
  切换账号，结果会被丢弃，界面按新账号重读，不会把 A 的通知显示给 B。
- **旧部署说「不可用」。** 没有这组路由的部署返回 404/405，界面明确提示服务器
  暂不提供通知，而不是显示空列表让人以为「没有通知」。
- **已读是唯一写入。** 单条与全部已读在服务端幂等；失败时行保持未读并提示原因，
  不做「本地已读、服务端未读」的猜测。

## 能显示什么

| `payload.type` | 行文案 | 备注 |
| --- | --- | --- |
| `message.created` | 收到一条新的私信（应用内暂不支持查看会话） | 携带 `conversationId`，但会话页尚未实现，不做深链 |
| `article.deleted` | 你评论过的作品已被作者删除，你的评论会在 `purgesAt` 随作品一起清除 | 无日期时省略日期分句 |
| 其他 / 读不懂 | 有一条新通知 | 未知事件照常列出，不静默丢弃 |

`payload` 解析是宽容的，**信封**是严格的：`id`/`payload`/`createdAt`/`readAt` 缺失
或时间不带时区偏移都算坏行（`FormatException` → `client.parse`），因为把半懂的行
当成懂了展示，比报错更危险；而「事件类型不认识」只是这一版没跟上服务端，仍然值得
让用户知道有东西发生过。

## 已知限制

- **只有最近一页。** 服务端没有游标或 offset，列表最多 100 条（客户端取 50）。拿满
  一页时页面底部会说明更早的通知暂不可见；未读数是**这一页里**的未读数。
- **没有推送。** 应用不在前台就不会读到新通知；标题不作实时承诺。
- **`article.deleted` 尚未在线上部署普遍出现。** 它由服务端软删文章时写入，字段
  （`articleId`、`purgesAt`）已由网页端共用；旧部署可能根本不会产生这类通知。
- **没有会话页。** `message.created` 只能陈述事实，不能跳转阅读私信。

## 测试

- `test/unit/notifications/notification_codec_test.dart`：信封严格、payload 宽容、
  时区必填、未知类型保留。
- `test/unit/notifications/notification_repository_test.dart`：路径/查询/空体、
  401/404/405/429/5xx 分类、坏信封 → `client.parse`、围栏失效不发请求。
- `test/unit/notifications/notification_inbox_cubit_test.dart`：加载、失败重试、
  单条/全部已读与回滚、切换账号后旧响应被丢弃。
- `test/widget/notification_inbox_page_test.dart`：进页面只读一次、行文案、已读反馈、
  空态、错误重试、未登录态。
