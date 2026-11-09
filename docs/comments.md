# 评论线程

## 后端分页契约

Flutter 使用 no-wave 合入的评论线程 keyset 契约（[PR #253](https://github.com/BrainEno/no-wave/pull/253)，
[ADR 0034](https://github.com/BrainEno/no-wave/blob/bbe9d198208cc9f4267e18e3a4ddcc88b2ad535a/docs/architecture/decisions/0034-comment-thread-pagination.md)）。
`GET /api/v1/articles/:slug/comments` 仍返回普通数组，按 `(createdAt ASC, id ASC)`
从旧到新排列；`limit` 计算**顶级评论**，每条根评论连同完整回复树一起返回。

```text
GET /api/v1/articles/:slug/comments?locale=zh-CN&limit=50&cursor=…

cursor = base64url("<createdAt>|<id>")
```

续页 cursor 必须取上一页最后一条**顶级评论**的 `createdAt` 原文和 `id`：时间戳按 API
返回的字节原样使用，不先解析再格式化；回复不作为页边界。后端没有 `nextCursor` 或
`hasMore` 字段。顶级评论少于页大小表示已到末尾；整页返回时继续请求，直到下一页为空。

后端要求评论时间戳为毫秒精度；no-wave
[迁移 `0031`](https://github.com/BrainEno/no-wave/blob/bbe9d198208cc9f4267e18e3a4ddcc88b2ad535a/apps/api/src/persistence/migrations/0031_comment_created_at_millisecond_precision.sql)
统一 PostgreSQL 历史行、默认值与约束，SQLite 原有默认精度已是毫秒。应先部署包含该迁移的后端，再启用评论 cursor 请求。
契约、错误形状及数据库细节见 no-wave
[评论线程分页文档](https://github.com/BrainEno/no-wave/blob/bbe9d198208cc9f4267e18e3a4ddcc88b2ad535a/docs/api/comment-thread-pagination.md)。
源码存在不代表目标部署已升级。

## Flutter 行为

- 打开作品时读取第一批最多 50 条顶级评论；页尾提供「加载更早的评论」，按需续读。每页的
  回复树仍与根评论一起显示。页面计数明确写「已加载」（含回复），不冒充全线程总数（API 不提供总数）。
- cursor 由数据层从响应数组最后一个根评论生成，遵守原始时间戳和 UUID 格式；分页失败保留
  已显示内容及原 cursor，重试重复同一请求。
- 短页或空页停止分页。若旧部署忽略 cursor 并重返已经显示的根评论，或用 HTTP 400 拒绝
  cursor，客户端保留原内容、停止续页并显示兼容提示，不重复追加或无限重试。
- 新评论在已经加载的列表中按 `(createdAt, id)` 排序；续页仍使用服务器上一页边界的 cursor，
  不会因刚发布的评论而跳过尚未读取的旧评论。重新读取第一批时会丢弃之前追加的页。
- 分页 footer 的加载提示、重试、兼容说明与已加载计数均来自中英文 ARB；加载态使用
  `NoWaveLoadingLabel`。

这项客户端改动不改变评论创建、删除或回复语义，不改后端，也不包含举报、屏蔽或审核功能。
