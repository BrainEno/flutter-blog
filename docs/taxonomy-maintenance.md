# 分类目录的编辑端维护（#381）

> 状态：active ｜ 最后核对：2026-11-27 @ 9306709

分类是作品摆放的编辑架子：作者只能从目录里已有的项中挑选，目录本身由编辑共同维护
（no-wave ADR 0016）。在 #381 之前，客户端只能读这份目录（编辑器里的多选器、分类
页），增删只能去网页后台。这一页记录把它接进应用时的取舍：哪些是服务端事实，哪些
是界面必须替读者与编辑承担的歧义，哪些是**故意**没做的。

服务端事实核对自 no-wave `main`（`apps/api/src/transport/rest/routes.ts`、
`routes/taxonomies.ts`、`bodies.ts`、`openapi/operations.ts`、`openapi/schemas.ts`）。
这些行为是否已在某个部署上升级，本仓库未验证——没有可连的 no-wave 部署。

## 这一屏面对的三个事实

- **目录只有一份，写侧只吃 `zh-CN`。** 读侧 `GET /categories?locale=` 按内容语言给出
  译名，写侧 `POST /taxonomies` 的 `locale` 只接受 `zh-CN` 或省略（`bodies.ts`
  直接判定）。所以在英文界面新建的一条，进的仍是那一份中文目录；界面把这句无条件
  写在上面（`taxonomyAdminLocaleNote`），而不是让用户以为自己在维护当前语言的目录。
- **目录只有一页。** `GET /categories` 的 `limit` 上限 100 且没有总数，
  `kCategoryListLimit` 满了只意味着「后面可能还有」，不意味着「这就是全部」。界面在
  满页时补一行说明，其余时候也照实说「这是目录的一页」。
- **删除的收据只有一个布尔。** `DELETE /taxonomies/:id` 回 `{deleted: boolean}`，
  `openapi/schemas.ts` 明写 false 同时覆盖「这条不归你删」与「这一行本来就不在」。
  因此界面只说「服务端没有删掉它」，不替服务端挑一个理由；一个裸布尔（另一条删除
  路由的形状）在这里算读不懂，不算确认。

## 写入策略

一次写就是这一次：

- 请求体恰好 `{kind, slug, name, description}` 四个键，**不带 `locale`**。服务端对
  白名单外的任何键整份 400（`The request contains unsupported fields.`），所以「顺手
  多带一个字段」会变成看起来像用户填错、其实是客户端写错。`locale` 不复读：那是
  服务端今天的常量，把它抄进客户端就把应用钉死在今天。
- 离线先拒，不进会话栅栏，也不把「未知」当成可能的结果——这是唯一一次「可能已经
  写进去了」为假的场合。
- 新增走 `postJsonForViewerOnce`：401 不重放、不跟随重定向。分类的新建**不需要**二次
  确认，它不替换任何人的东西。
- 删除走 `deleteJson(..., sessionFence: …, followRedirects: false)`，且必须
  `showNoWaveConfirmDialog` 确认后才发第一个请求。
- `403` → 「这个服务器不把你的账号当作编辑」；`404`/`405` → 「这个部署没有可供使用
  的分类维护」；读不懂的 `2xx` → 「可能已经生效」+ **重读**，绝不重发（这条 API 没有
  条件写，重发一次就是往公共目录里多插一行）。其余异常走 `mapErrorToFailure` 既有
  分类：409 用 `server.CONFLICT`，400 用 `server.BAD_USER_INPUT`，服务端英文原文一律
  不复读。
- 任何一次写之后都重读目录。界面不把自己刚发出去的那一行拼进列表：`slug` 由服务端
  落地、`id` 由服务端生成，本地拼出来的是一条既没有名字保证、也删不掉的行。

## 本地只拒绝「自己读不回来的形状」

`taxonomyDraftProblem` 不看正则、不猜命名规范：后端对 `name`/`slug` 只说「必须是
字符串」。它只拒绝应用**自己**读不回来的一切——空名字、不能进 URL 的 slug（`.`、
`..`、首尾带空格、超过 300）、超过 2000 字的说明。理由不是洁癖：分类解析器遇到这种
行是整页抛错（`_parseCategory` in
`lib/features/blog/data/datasources/category_remote_data_source.dart`），一条这样的
分类会连带砸掉所有人的分类页，而届时再没有任何界面能把它删掉。说明的长度上限与服务端
同一个数（`kTaxonomyDescriptionLimit`），计数器与拒绝用的是同一个常量。

## 数据通路

| 层 | 文件 |
| --- | --- |
| 领域 | `lib/features/blog/domain/repositories/taxonomy_admin_repository.dart`（含 `kTaxonomyDescriptionLimit` 与 `taxonomyDraftProblem`）、`lib/features/blog/domain/entities/taxonomy_draft.dart` |
| 数据 | `lib/features/blog/data/repositories/taxonomy_admin_repository_impl.dart` |
| 界面 | `lib/features/blog/presentation/pages/taxonomy_admin_page.dart`（路由 `profile/taxonomy-admin`） |
| 目录读 | `lib/features/blog/domain/repositories/category_repository.dart`（与读者同一条路径） |
| 角色 | `lib/features/auth/presentation/bloc/editorial_capacity_cubit.dart`（复用 #377，不新建第二套判断） |

写之后那次重读还有个测试上的后果值得记一句：**通知渲染在列表里面**，而重读期间
`_loading` 为真、整块列表被占位符换掉（这是 #377 那一屏已有的形状）。所以断言「写入的
答复」之前，测试必须先把那一次重读回答掉，否则读到的是一棵还在转圈的树——绿了也只是
碰巧。`test/widget/taxonomy_admin_page_test.dart` 的四个写入用例都按这个顺序写。

锁住这些选择的测试：`test/unit/blog/taxonomy_admin_guard_test.dart` 检查 body 只在
`_door` 里成形、`/taxonomies` 不被第二处使用、两次写都是一次性且过栅栏、界面不自己
发请求、每次写后都重读、没有 id 的行不给删除按钮，以及 `taxonomyAdmin*` 键在两份目录
里既不缺也不闲；`test/unit/blog/taxonomy_admin_repository_test.dart` 与
`test/widget/taxonomy_admin_page_test.dart` 逐条断言上述行为。

## 未核对，别靠猜实现

1. `slug` 的正则与长度（`schemas.ts` 只写 `TEXT`），以及撞车时 409 的确切 body。
2. 删除**仍被文章引用**的分类会怎样：是拒绝（什么码）、留空引用，还是级联。这直接
   决定确认框该不该说「有 N 篇作品在用」——未确认之前不编造这个计数。
3. 未登录（`sendUnauthenticated` 的 401）与非编辑（403）在真实部署上的先后与文案差别。
4. `MAX_TAXONOMY_OFFSET` 的具体值，以及目录总条数是否有上限。

## 有意不做

- 不改名、不译名：后端没有给分类任何按行更新的入口（`routes.ts` 里只有
  `POST /taxonomies` 与 `DELETE /taxonomies/:id`），所以界面上没有可编辑字段——一个
  没有请求可发的输入框比没有更糟。要改名字，就删掉重建，而这条路径的后果见上面第 2
  条未核对项。
- 不做标签（tag）的编辑与合并：`POST /tags` 的语义是「创建或复用」，且标签是作者自己
  的话，不是编辑结构。
- 不做 `PUT /users/:id/role`：改的是权限本身，失败模式需要服务端配合验证。
- 不做离线草稿与发布队列：目录是共享数据，一条排在队列里的「删除」在别人已经重建同名
  分类之后再落地，就是删掉别人的行。
