# 精选书架的编辑端策展（#377）

> 状态：active ｜ 最后核对：2026-11-25 @ 9b3bdb8

首页「精选」标签的顺序由编辑决定，而不是由算法决定——这句话在客户端此前只是
只读：应用会显示服务端给的顺序，却没有任何地方可以改它。本页记录把
`PUT /featured` 接进应用时的取舍：哪些是服务端事实，哪些是界面必须替读者与编辑
承担的歧义，以及哪些能力**故意**没有做。

服务端事实核对自 no-wave `main` 的 `dff0183`（`apps/api/src/transport/rest/routes.ts`、
`article.ts`、`featured-algorithm.ts`、`postgres-article-store.ts`）。这些行为是否
已在某个部署上升级，本仓库未验证。

## 服务端给的四个约束

1. **一份书架按内容语言分开存**。读写都要带 `?locale=`，取的是
   `ContentLocale.instance.tag`（内容语言），不是界面语言。
2. **一次写入替换整份列表**。请求体只允许 `{"articleIds": string[]}`；多出任何键
   都会得到 `400 The request contains unsupported fields.`。所以「移除一篇」在
   客户端不是 DELETE，而是把剩下的整份重新发一遍。
3. **上限 20 篇**（`MAX_FEATURED_ARTICLES`），且**整份拒绝**：超长、非 UUID、重复 id、
   列表里含草稿或已删除作品，任何一项都会让这次写入整体失败。服务端宁可拒绝，
   也不要一份「悄悄丢掉编辑两篇选择」的书架——所以客户端也不自己过滤坏行，
   而是发送并把拒绝读回来。
4. **没人排过书架时，`GET /featured` 回退到「按字数从多到少」的已发布作品**，
   并且响应里**没有任何字段**说明这次是策展还是回退。

第 4 条是这块界面全部额外复杂度的来源：界面看到的样子无法区分「别人排好的」和
「算法兜底的」，而保存会把屏幕上的一切固定成编辑的答案。因此界面在两种情况下都
把这句话写出来（`featuredShelfFallbackNote`），而不是假装看见的就是策展结果。

## 角色是三态，不是布尔

`GET /me` 的 `isEditor` 正是为「要不要显示编辑入口」加的，但老部署会正常应答而
不带这个字段。于是 `AccountEditorialCapacity` 有三种：

| 值 | 含义 | 入口与界面 |
| --- | --- | --- |
| `granted` | 服务端说这是编辑 | 显示入口，正常保存 |
| `denied` | 服务端说不是 | **隐藏**「我的」里的入口 |
| `unknown` | 服务端答了但没给角色 | 显示入口，界面额外说明「由服务端在写入时判定」 |

读取失败（网络、5xx）不等于 `unknown`：仓储把它报成 `Failure`，界面保持上一次的
答案。把「请求没答」包装成「服务端说没有」，会让一个只是断线的编辑丢掉入口。

容量读取由 `EditorialCapacityCubit` 负责：冷状态是 `denied`（先出现再消失的入口
像故障），账号变化时回到 `denied` 并重读，不轮询。书架与角色两次读取**串行**：
并发的一对新旧结果可能在换账号后把「新角色 + 旧书架」拼在一起。

## 保存的语义

- 界面上的按钮只在「与已存顺序不同」且「这份列表本身可发送」时可点。脏比较是
  `_ids` 与 `_storedIds` 逐项比较，顺序也算。
- 点保存先弹确认；确认之后才产生请求。
- 403 报成 `refused`，404/405 报成 `unavailable`，读不懂的 2xx 报成 `unknown`。
  `unknown` 意味着**可能已经写进去了**，所以界面重读而**绝不重发**：整份替换
  再发一次会覆盖掉中间另一位编辑的保存。
- 任何一次保存之后都重读。若服务端存回来的顺序与刚发出去的不同，界面说
  「服务端记住的顺序不一样」（`featuredShelfChangedElsewhere`），而不是静默采用
  本地列表。
- 离线时直接拒发，不进入会话栅栏，也不把「未知」当成可能的结果。

写请求经 `putJsonForViewerOnce` 走会话栅栏（`NowaveSessionFence`），
`followRedirects: false`，401 后不自动重试。

## 为什么是上移/下移，不是拖拽

一次误拖就会改写所有人看到的首页，而一个没有可读名称的放置目标对读屏器不是
可操作项。三枚带标签的按钮（上移 / 下移 / 移出）把同样的能力拆开，每一步都能
被念出来；保存进行中三枚按钮一起禁用，确保屏幕上这份就是发出去那份。

这不是说法，有测试钉着：`test/widget/featured_shelf_page_test.dart` 里一例只用
`find.byTooltip(...)`（也就是读屏器播报的那三个名字）走完「删一条 → 上移 →
保存 → 确认 → 回读」，另有 `en` / `zh` 两例在 320dp 宽、2x 系统字号下断言标题、
三枚按钮与保存键都在，且 `takeException()` 为空——溢出横幅会以测试异常冒出来。

## 数据通路

| 层 | 文件 |
| --- | --- |
| 领域 | `lib/features/blog/domain/entities/featured_shelf_entry.dart`、`lib/features/blog/domain/repositories/featured_shelf_repository.dart`（含 `kFeaturedShelfCapacity` 与 `featuredShelfProblem`） |
| 数据 | `lib/features/blog/data/repositories/featured_shelf_repository_impl.dart` |
| 界面 | `lib/features/blog/presentation/pages/featured_shelf_page.dart`（路由 `RoutePaths.featuredShelf`） |
| 角色 | `lib/features/auth/domain/account_editorial_capacity.dart`、`lib/features/auth/presentation/bloc/editorial_capacity_cubit.dart` |

`featuredShelfProblem` 由界面与仓储**共用**：界面据此提前说明「还不能保存」，
仓储据此避免为一个服务端必然拒绝的 body 花掉一次请求。

书架**不**通过首页 feed 的 `BlogFeedKind.featured` 读取：那条通路按 feed 分页尺寸
（10）取列表，而书架上限是 20——用它会读到 10 篇并把 10 篇存回去。
`test/unit/blog/featured_shelf_write_guard_test.dart` 锁住这四件事：`'articleIds'`
字面量只出现在门文件；`'/featured'` 只出现在门文件与 feed 读取处；feed 数据源保持
只读；策展界面不引用 `BlogFeedKind`。

## 明确没做的

- **分类（taxonomy）维护**与 **`PUT /users/:id/role`（授予编辑）**：需要各自的界面
  与规则，留给后续 Issue。本功能里「谁是编辑」只读不写。
- 拖拽排序、批量导入、按标签填充书架。
- 编辑入口不做全局缓存：`EditorialCapacityCubit` 是**每开一次菜单一个实例**，
  常驻副本正是「被降级后仍看得见入口」的成因。

## 验证状态

沙箱内无 Flutter/Dart SDK，`flutter analyze`、`flutter test`、`dart format` 一律
未在本地执行；上述实现的通过与否以仓库 CI 运行为准。本地执行过的只有：Dart 语法
解析（tree-sitter）、80 列与 formatter 稳定性扫描、`tool/ci/` 三个契约门，以及把
守卫测试的匹配逻辑移植到 Python 后做的反向/变异检查（加一处 `'articleIds'` 会被
抓、注释里的关键字不误报）。
