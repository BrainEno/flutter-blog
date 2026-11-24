# 编辑器收敛与退役路线图

> 状态：active ｜ 最后核对：2026-11-19 @ 666f666

> 本文描述 Flutter 客户端当前能安全写回 no-wave 的边界，以及编辑器从「普通文本
> + 本地结构化原型」收敛为单一传统编辑器的过程。
> 它不是服务端能力承诺；未列为可写的形状必须继续只读，并引导作者到网页端编辑。

## 当前边界

应用只有**一个**作者编辑器：`BlogEditorPage`（`EditorSessionCoordinator` +
`EditorScreen`），和 no-wave 网页编辑器一样是「标题 + 正文」的传统写作界面。
正文是一份 Markdown 文本，使用固定的小方言，与 no-wave 的 block 一一对应
（`lib/features/blog/domain/authoring/article_markdown.dart`）：

| 正文写法 | no-wave block / mark |
|---|---|
| 空行分隔的文字 | `paragraph` |
| `## ` / `### ` / `#### ` | `heading` level 2–4（单个 `#` 记为 2，标题本身是 1 级） |
| `> ` 行 | `quote`（不含 attribution） |
| `- ` / `1. ` 行 | `list`（无序 / 有序） |
| ```` ```lang ```` 围栏 | `code`（未写语言时为 `text`） |
| 独占一行的 `![alt](src "caption")` | `image` |
| `**粗**` `*斜*` `~~删~~` `<u>下划</u>` `` `代码` `` `[文字](url)` | inline marks / link |

- **写入**：`articleBodyPayload` 先把正文解析成 blocks。完全没有格式的正文仍按
  原样写成 `contentBlocksVersion: 0`（与以前逐字节一致）；只要用了标题、列表、
  引用、代码、图片、链接、行内样式或转义，就写成 `contentBlocksVersion: 1`，
  网页端看到的是同样的结构而不是 Markdown 符号。块 id 写入时用 uuid 新生成。
- **打开**：`Blog.editableBody` 决定一篇文章能否进编辑器。旧的 v0 正文本来就是
  这份 Markdown；结构化文档会渲染成同一方言，并且**必须**解析回完全相同的
  blocks 才算可编辑（`editableBodyOf`）。带 attribution 的引用、无法表达的结构、
  未知文档版本都失败关闭：「我的文章」提示到网页端编辑，不进编辑器。
- **封面**：文档开头那张 alt 和 caption 都为空的图片是编辑器的封面，其余图片
  留在正文原位。
- **更新**：`BlogRepositoryImpl.editBlog` 先重新读取服务器文章；只有
  `plainEditorCompatible` 且 `editableBody != null`、有 server summary 时才继续，
  否则在上传封面或任何修改之前返回 `article.structuredEditUnsupported`。
  条件写入（`expectedRevision`）、草稿、离线队列和幂等键与以前相同。
- **摘要**：正文下方的「摘要（可选）」显示文章现有的摘要（≤2000 字，与服务端
  上限一致）。没改动时写入不带作者摘要——新文章由服务端根据正文生成，更新沿用
  刚读到的 server summary；改写后发送新内容，清空则发送空字符串，让服务端重新
  生成。本地草稿（`account_drafts.summary`）和离线队列（`publish_queue.summary`）
  只在改动过时保存它，NULL 表示「没碰过」。改写过的摘要会出现在版本冲突对比里。
- **存为草稿**：菜单里的「存为草稿（仅自己可见）」以 `publish: false` 写入
  服务端（新建或更新，同样走条件写入、幂等键和离线队列，队列行带
  `publish_queue.publish`，旧行按发布处理）。编辑已公开的文章时这一项是「转为草稿
  （取消公开）」，先确认再写。编辑草稿时会提示「这是一篇草稿」，「发布」即首次
  公开。原来的本地草稿入口改名「保存到本机」，与服务端草稿区分。幂等键只在
  同一种选择内复用：在发布与存草稿之间切换会换新键。
- **在「我的文章」切换发布状态**：文章操作里的「发布」/「转为草稿」发送的正是编辑器
  「打开后不改动直接保存」的那份 `UpdateBlogEvent`（`editableBody.markdown`、原标签、
  原语言版本、列表行的 `authoringRevision`，不带封面 / 分类 / 摘要），只翻转 `publish`。
  门槛与编辑器相同：`editableBody != null` 且有版本；正文为空的行也拒绝，避免把缩略
  列表行当成全文写回。服务端没有单独的发布开关（只有整篇 `PUT`）。

编辑器本身：键盘上方的格式工具栏（撤销/重做、H2–H4、粗体、斜体、删除线、下划线、
行内代码、引用、两种列表、代码块、链接、插入图片并上传）、实时 Markdown 高亮、
回车续写列表/引用（空项回车退出列表）、字数与阅读时长、专注模式（隐藏封面/标签/
分类/摘要）、带图标的自动保存状态，以及编辑/预览切换。

## 收敛结果（2026-11）

原计划的阶段 3 是把结构化 composer 嵌进正式编辑器。实际采用了更简单的方案：
不做 block 编辑器，而是让传统编辑器的 Markdown 与 no-wave blocks 无损互转。

- `structured_local_*_page.dart` 等 22 个本地结构编辑界面文件及其 widget 测试已
  删除；「我的文章」不再有「本地结构编辑」或本地恢复目录入口。
- `lib/features/blog/domain/editing/` 与 SQLite 恢复存储、`editor_module` 的 DI
  注册和单元测试保留为基础设施（见 [structured-session-recovery.md](structured-session-recovery.md)），
  当前没有界面打开它们。
- 下文「收敛顺序」和 Local … form 各节保留为历史记录，描述的是已移除的原型。

## 已落地的协调边界

`BlogEditorPage` 是保留原有构造参数的路由组合入口；
`EditorSessionCoordinator` 持有控制器、恢复、账号围栏、异步对话框、发布和
草稿状态，并将显示交给无持久化副作用的 `EditorScreen` / `EditorForm`。
`EditorSessionFence` 单独定义当前账号及 generation 匹配规则，方便独立测试；
`EditorNotionCoordinator` 管理单个 Notion 弹层及其精确路由，账号失效时移除该路由。
此次主要迁移原有协调逻辑，不改变 Markdown、草稿或队列协议。2026-11-19 起
协调器按职责拆成同一个库里的几个 part 文件：`editor_session_coordinator.dart`
保留状态字段（`_EditorSessionBase`）、初始化、账号失效、分类和构建；
`editor_session_drafts.dart`（自动保存、恢复、显式保存）、
`editor_session_cover.dart`（设备选图并裁剪、调整裁剪、撤销选择、媒体库、队列封面；
裁剪页 `cover_crop_page.dart` 与媒体选择弹层共用同一个根路由槽，账号失效时一并移除）和
`editor_session_publish.dart`（发布意图、队列移交、版本冲突核对）各是一个私有
mixin。它们仍共享同一份可变状态、同一组账号围栏检查，行为测试不变——这是
可读性上的拆分，编排复杂度本身并没有消失；若要真正独立成服务，仍需先把
共享状态收敛为显式的值对象。以下不可变工作避免异步流程拼接不同请求：

- `EditorPublishIntent` 同时生成 `BlogUploadBloc` 事件和离线 queue 行；文本、
  标签、分类三态（未触碰 / 清空 / 选择）、封面、目标语言、session generation、
  revision 和 idempotency key 都来自一次快照。
- `BlogRemoteDataSourceImpl` 是兼容 façade；公开/账号读路由位于
  `blog_remote_article_reads.dart`，创建、上传、条件更新、删除和恢复位于
  `blog_remote_article_writes.dart`。两者仍共享原来的错误映射、语言和 session
  fence，因此此次拆分不改变 REST 契约。
- 自动草稿、冲突核对和队列行仍只有 `EditorSessionCoordinator` 这一处协调。成功只能清理
  “本次发布前保存的精确 draft”，不能清理作者在请求期间继续输入的内容。

## 收敛顺序（历史）

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

### Local block-property form (removed)

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

### Local structural insertion and list actions (removed)

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
