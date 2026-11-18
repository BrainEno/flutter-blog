# 编辑器收敛与退役路线图

> 状态：active | 分类基线：`7fc34ce`（仅文档分类，非逐项事实核验）

> 状态：2026-11-16。本文描述 Flutter 客户端当前能安全写回 no-wave 的
> 边界，以及把本地结构化原型收敛为可维护的单一作者流程所需的步骤。
> 它不是服务端能力承诺；未列为可写的形状必须继续只读或本地恢复。

## 当前边界

应用现在有两类正文来源，不能把它们混成同一种“可编辑文章”：

1. **普通文本正文**：`BlogEditorPage` 把 Markdown 文本写为 no-wave 的
   `contentBlocksVersion: 0`。编辑请求必须携带从打开文章或显式 rebase 得到
   的 `expectedRevision`，否则保留草稿并拒绝 PUT。发布失败会先持久化精确
   快照，再以同一 `Idempotency-Key` 放入账号隔离的 publish queue。
2. **结构化正文**：`structured_local_*_page.dart` 是本地探索、恢复和可视化
   工具；`MarkdownRenderer`/文章阅读器负责兼容性只读显示。它们不能把
   `contentBlocksVersion: 1`、未知 block 或未证明可逆的富文本压平成文本后
   远端提交。这样做会丢掉 block identity、图片说明、样式或摘要，也会绕开
   条件并发写入。

因此，临时结构化页面不应被当成第二个生产编辑器。它们有价值：用于验证选择、
range、rich-text 的本地操作，以及从损坏/不支持正文中恢复作者文字；但必须明确
标注本地、不可发布，并且不应在导航、deep link 或资料页中成为默认“编辑”入口。

## 已落地的协调边界

`BlogEditorPage` 是保留原有构造参数的路由组合入口；
`EditorSessionCoordinator` 持有控制器、恢复、账号围栏、异步对话框、发布和
草稿状态，并将显示交给无持久化副作用的 `EditorScreen` / `EditorForm`。
`EditorSessionFence` 单独定义当前账号及 generation 匹配规则，方便独立测试；
`EditorNotionCoordinator` 管理单个 Notion 弹层及其精确路由，账号失效时移除该路由。
此次主要迁移原有协调逻辑，不改变 Markdown、草稿或队列协议。协调器仍然较大，
后续应分步抽出草稿、媒体和冲突协调服务并保留既有行为测试，不能仅将文件
搬走就声称编排复杂度已经消失。以下不可变工作避免异步流程拼接不同请求：

- `EditorPublishIntent` 同时生成 `BlogUploadBloc` 事件和离线 queue 行；文本、
  标签、分类三态（未触碰 / 清空 / 选择）、封面、目标语言、session generation、
  revision 和 idempotency key 都来自一次快照。
- `BlogRemoteDataSourceImpl` 是兼容 façade；公开/账号读路由位于
  `blog_remote_article_reads.dart`，创建、上传、条件更新、删除和恢复位于
  `blog_remote_article_writes.dart`。两者仍共享原来的错误映射、语言和 session
  fence，因此此次拆分不改变 REST 契约。
- 自动草稿、冲突核对和队列行仍只有 `EditorSessionCoordinator` 这一处协调。成功只能清理
  “本次发布前保存的精确 draft”，不能清理作者在请求期间继续输入的内容。

## 收敛顺序

### 阶段 1：明确入口和数据所有权（下一次结构化功能变更前）

- 在每个 `structured_local_*` 页面显示“本地实验 / 不会发布”说明，并从默认
  作者入口、文章操作菜单和路由表移除直接入口；保留带显式 recovery 语义的入口。
- 为结构化本地文档定义版本化的 recovery record：来源 article slug、locale、
  原始 `contentBlocksVersion`、原始 blocks、创建时间和恢复文本必须一起保存。
  不可只保存扁平文字，否则无法说明恢复是否仍对应原文。
- 把“可从服务器安全编辑”的判定集中到 domain policy。页面不能仅通过“拿到
  title/content 字符串”猜测；必须要求 plain-editor compatibility、server summary、
  authoring article id 和 revision。

验收：普通编辑器永远不导航到结构化临时页；未知结构化文章能阅读并给出恢复选择，
但没有会发送 `PUT /articles/:id` 的按钮。

### 阶段 2：先完成无损文档模型，再做远端写入

- 为服务端确认支持的 block 版本建立 domain `ArticleDocument` 写入 codec，要求
  decode → edit → encode 保留未知字段、block id、image metadata、caption 和顺序。
- 为每一种本地编辑操作定义 transaction：输入 document、selection、操作、输出
  document、undo record；不要让 widget 直接修改 JSON map。
- 在 `UpdateBlog` 新增独立的 structured-write command，和 Markdown 更新一样
  强制 `expectedRevision`、目标 `locale`、session fence；它不得复用会生成 v0
  `contentBlocks` 的普通文本路径。
- 扩展离线 queue，使其能保存版本化 structured payload 与对应 media 引用；旧
  行仍按 v0 读取。无法确认 codec 版本的行应停止等待人工恢复，而不是降级发布。

验收：每个被宣称支持的 document fixture 均可无损往返；版本冲突保持本地 structured
snapshot；账号切换和重启后 queue 不会把正文发送给另一个账户或语言版本。

### 阶段 3：替换临时页面并退役

- 只在阶段 2 的 codec、条件写入、草稿、队列和可访问性验收完成后，将一个
  structured composer 嵌入正式 `BlogEditorPage` 的 editor surface。保留 Markdown
  输入作为明确选择，而不是静默转换已有文章。
- 迁移仍有价值的选择/样式/undo helpers 到正式 editor package；每次迁移一个 helper
  并附行为测试。不要复制一套 controller、draft 或 upload lifecycle。
- 临时页先改为只读 recovery viewer，再移除路由和实现。发布迁移说明，告诉作者如何
  导出本地 recovery 文本；在至少一个兼容版本后才删除旧 record reader。

验收：正式入口只有一个 publish coordinator；临时页面没有写网络的依赖；删除前版本
仍能读取旧 recovery record，且普通 v0 发布、编辑、冲突 rebase 和离线补发不回归。

## 不变量检查表

任何编辑器拆分或结构化迁移都必须保持：

- **账号隔离**：所有 private read、draft、media picker、queue 和写操作由同一个
  `NowaveSessionFence` 约束；代际变化立刻让旧 UI 失效。
- **精确条件写**：不能把 revision 字符串转为数字；缺失、畸形或冲突都不自动重试。
- **语言归属**：更新和队列重放写打开时的 article locale，不能读取当前界面语言猜测。
- **一次发布意图**：新建文章的 idempotency key 在不确定结果时稳定复用；封面上传成功
  URL 要记录，避免 retry 产生多份媒体。
- **不丢草稿**：网络回包、modal dismiss、账号切换和 dispose 都不能删除后续编辑；
  清理只能匹配已发布的 immutable snapshot。
- **无障碍与离线说明**：本地/只读/不可发布状态必须被文本和 semantics 说清楚，不能
  用禁用的图标让读者猜测。

### Local block-property form

The local structure editor can change image alternative text and optional
caption, code language and literal code, quote attribution, heading level,
and ordered-list display. It preserves image URLs, other blocks, text, inline
runs and list items. Optional-field absence remains different from an empty
value. These edits use the same strict schema and exact immutable body snapshot
as the local coordinator; a changed body or account invalidates the form.

The form is deliberately temporary: typing is not crash-recoverable and the
user is warned before leaving a dirty form. Applying a valid form queues the
existing local compare-and-swap writer; the parent editor reports pending,
failed or conflicting saves. Applying does not guarantee a disk write, alter
Markdown publishing, upload images, or publish a structured article. An input
method composition must finish before applying. Unsupported malformed UTF-16
is not rendered or edited through this form.

### Local structural insertion and list actions

The local structure editor can insert one of the six currently validated block
shapes after an existing block. IDs are generated locally and checked for
uniqueness by the existing document validator. Inputs remain literal, optional
caption/attribution presence is explicit, and URL, document-size, item and
block limits are validated before the coordinator accepts a snapshot. New
blocks do not imply uploads, publication or remote-write support.

List-item positions are bound to the exact selected body, not treated as stable
IDs. Inserting, removing or moving an item preserves the representation of all
other items; for formatted v1 lists their `itemInlines` entries move with the
corresponding text. A new item gets one unformatted run only when the list
already has inline runs. The last item cannot be removed and a 100-item list
cannot grow. Destructive removal requires confirmation. Changing the parent
snapshot or account invalidates a pending decision.

Insertion forms are temporary: typing is not crash-recoverable, changing type
requires confirmation when values were entered, and leaving a dirty form asks
before discarding it. The author must finish active input-method composition
before applying. Applying only queues an existing local CAS save, and the
editor displays saving, saved, failed or conflict state. Device termination
before a confirmed disk write can still lose pending input. No database schema,
Markdown publishing or queue behavior is changed.
