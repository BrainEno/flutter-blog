# 发布队列（#23）

发帖有两种失败：**内容被拒**和**网络没送到**。前者需要人改，后者只需要再试一次。
发布队列只负责后者：用户按下发布后，这一意图先落盘，再按同一幂等键重试，直到
服务端接受或需要人处理。

## 状态

| 状态 | 含义 | 谁会离开这里 |
| --- | --- | --- |
| `queued` | 等待会话、网络或退避窗口 | 下一次 drain |
| `uploading` | 有一次发送在途（**持久化**） | 成功、失败，或下次启动的 `recoverInterrupted` |
| `failed` | 停止自动重试 | 用户在队列页「重试」或「移除」 |

`uploading` 故意写进数据库：进程在发送中被杀，下次启动能看到并**用同一个幂等键
重放**，而不是当作没发生过。

## 三条硬规则

1. **不会静默重复建文。** 每个意图在入队时生成一次 `Idempotency-Key`，之后每次
   尝试都带同一个键。服务端按该键重放（no-wave `POST /articles` 支持，长度 ≤300
   且非空），所以「响应丢了但文章已建」只会在下次重放时返回同一篇。
2. **不会串账号、串后端。** 行带 `backend`（由 `API_BASE_URL` 派生，见
   `lib/core/storage/backend_key.dart`）和 `user_id`；drain 只处理当前登录账号的
   行。`sessionFence` 在每次发送前用**当前**会话重建，所以同一账号退出再登录会
   继续排队（那是账号的长期意图），换账号则不会被别人发出去。
3. **一次只发一条。** 发送前先在事务里 `queued → uploading` 抢占；第二个 drain
   拿不到同一行，页面也不能绕过 runner 直接发。

## 重试与退避

| 失败类别 | 处理 |
| --- | --- |
| `network` / `timeout` / `storage` | 重试，1m → 5m → 15m → 60m → 3h |
| `server` / `unknown` | 同上，但最多 5 次，之后 `failed` |
| `auth`（会话过期/退出） | 保持 `queued`，**不消耗**重试次数，等重新登录 |
| `permission` / `validation` | 立即 `failed`，等人处理 |

编辑器的失败分类与这里一致：只有可能被重试修好的失败才入队，表单校验类失败仍
按原来的错误提示呈现。

## 触发时机

- 应用启动（`main.dart` 调用 `PublishQueueService.start()`：先修 `uploading`，
  再 drain）；
- 会话身份变化（登录/退出/切换账号）；
- 应用回到前台（离线设备重新联网的典型时刻）；
- 打开「发布队列」页并下拉刷新，或点「立即发送」；
- 编辑器把一次发布放进队列之后。

**没有**轮询、没有后台任务、没有服务端推送：队列只在上述事件发生时推进。不联网
时 drain 会直接返回，不消耗任何尝试。

## 封面

选图器给的是临时文件，可能在这条记录等待期间被清理，所以入队时把字节复制到应用
目录 `publish_queue/<entry-id>.bin`，MIME 存在行里；成功或移除时删除文件。

已知限制：no-wave 的媒体上传**没有幂等键**，所以一次重试会重新上传一次封面，可能
在服务端留下一个未被引用的媒体资源。文章本身仍然只有一篇（幂等键保证）。孤儿
清理属于服务端范围，客户端不做定时删除。

## 存储与代码位置

- 表：`publish_queue`（schema v8），唯一主键 `id`，索引
  `publish_queue_due(backend, user_id, state, created_at)`；
- 端口：`lib/features/blog/domain/repositories/publish_queue_store.dart`、
  `publish_queue_drainer.dart`；
- SQLite 实现：`lib/features/blog/data/datasources/sqlite_publish_queue_store.dart`；
- 发送：`lib/features/blog/data/publish/publish_queue_runner.dart`；
- 事件接线：`lib/features/blog/data/publish/publish_queue_service.dart`；
- UI：`profile → 发布队列`（`/profile/publish-queue`）。

## 范围

只排队**新建文章**。编辑已有文章仍走原来的同步请求：更新是按文章 id 的幂等操作，
重试不会建出第二篇，也不需要队列来保证安全。删除、点赞等其它写操作同理不在本队列
范围内。

## 与草稿的关系

草稿是「我写了」，队列是「我要发」。编辑器发布前仍先存一份精确草稿快照；一旦
入队成功，本地草稿即被清理，因为队列行已经持有同样的文字与封面。发布期间继续
编辑的内容仍留在草稿里，不会被丢掉。

## 测试

- `test/unit/storage/publish_queue_store_test.dart`：入库/抢占/退避/修复/清理、
  账号与后端隔离、重开数据库后仍在；
- `test/unit/publish/publish_queue_runner_test.dart`：带上幂等键发送、失败分类、
  无会话不发、串账号不发、离线不消耗尝试、FIFO、并发 drain 只发一次。
