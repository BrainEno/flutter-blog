# 界面设计系统（tokens 与组件）

> 状态：active ｜ 最后核对：2026-11-19 @ b61c0c5

本页是客户端「长什么样」的唯一入口：色板、间距、圆角、线宽、动效、断点，以及
共用组件的 API 和使用规则。目标是让新增页面**不需要**重新决定这些数字——需要时
改这里，而不是改页面。

> 与网页的关系：色板与排版沿用 no-wave 网页的纸色/墨色/橙红与衬线标题；本页描述
> 的是**原生**落地方式（Material 语义、点击区域、读屏），不追求与网页逐像素相同。
> 无障碍的验收边界另见[无障碍说明](accessibility.md)。

## 一、原则

1. **纸与墨，两色打底；橙色只回应手指。** 页面底色只有纸（浅色）与墨（深色）两种。
   结构性的记号——选中词下的线、文末方块——一律用墨色（`onSurface`），不用强调色；
   橙红只留给「回应操作」的地方：焦点与悬停洗色、输入框聚焦线、下拉刷新、阅读进度、
   主按钮。装饰性的橙色短线（小标题前、提示条前、底栏上沿）已全部去掉：标在文字前面的
   线只会拖慢读到字的那一刻。小字号强调文字用牛血红（`AppPalette.oxblood`），因为橙红
   在纸色上不到 4.5:1。
2. **方角。** 圆角只有一个例外（封面上的角标 2pt）。Material 的填充/描边按钮默认
   是胶囊形，主题层统一压平方，组件层不许另开圆角。
3. **留白与细线。** 分组靠留白，分隔靠 1pt 半透明细线，不用卡片阴影与抬升。
4. **一个页面一个主行动。** 次要行动用描边或纯文字，破坏性行动用错误色并要求二次
   确认。
5. **尺寸跟着文字走。** 字放大到 2× 时，内容重排而不是被裁掉；不设固定高度去夹
   文字。

## 二、Tokens

全部定义在 `lib/core/design/design_tokens.dart`。`AppPalette`（颜色）在
`lib/core/theme/app_palette.dart`，并转导出 `NoWaveSpacing`，所以只 import 色板的
页面照样能编译。

### 间距 `NoWaveSpacing`（4 点网格）

| token | 值 | 用在哪 |
| --- | --- | --- |
| `xs` | 4 | 标题与它的元信息、标签与值之间 |
| `small` | 8 | 同一组内（角标与标题、两行元信息） |
| `medium` | 16 | 两组之间的距离 |
| `large` | 24 | 标题块与它引入的内容之间 |
| `section` | 32 | 一页之中两个 section 之间 |
| `page` | 28 | 页面左右边距：比 `large` 再宽一格，手机上一栏两侧要留够空气，文字才不贴着屏幕边；应用栏标题（`titleSpacing`）也从这里起排，与下面的栏对齐 |

这张表只有五档，是故意的：档位少，页面才不会每一处都自己决定。**12 不在表里**，
因为它在代码里同时扮演两种角色，逐处判断后分给了相邻两档：

- 跟「它标注的东西」放一起（头像和名字、行内图标和文字、卡片内边距）→ `small`。
- 把两个块分开（一个字段和下个字段、错误文案和重试按钮、两张卡片之间）→ `medium`。

登录/注册页的「按钮 + 下面那排链接」算一个行动组，所以用的是 `small`：整页高度不
变才不会把小屏上的「诊断信息」入口挤到折叠线以下（`router_test.dart` 里有这条断言）。

### 几何

| token | 值 | 说明 |
| --- | --- | --- |
| `NoWaveRadius.none` | 0 | 按钮、输入框、卡片、对话框、面板 |
| `NoWaveRadius.badge` | 2 | 封面角标 |
| `NoWaveRadius.inline` | 4 | 正文里行内代码的底色 |
| `NoWaveRadius.thumbnail` | 6 | 列表行缩略图（阅读历史改成纯文字行后暂无调用方，数值保留） |
| `NoWaveRadius.surface` | 8 | 嵌入的内容面：代码块、正文图片、编辑器正文框、评论区登录提示 |
| `NoWaveRadius.container` | 12 | 大内容容器：封面上传框、私信气泡、发布队列条目、参与者面板头 |
| `NoWaveRadius.pill` | 999 | 胶囊：未读计数角标、面板拖拽条；无论位数和系统字号，两端都保持圆形 |
| `NoWaveStroke.hairline` | 1 | 分隔线、输入框边框、角标描边 |
| `NoWaveStroke.focus` | 2 | 焦点环、聚焦输入框边框 |
| `NoWaveIconSize.inline` | 18 | 与元信息文字同行 |
| `NoWaveIconSize.row` | 20 | 行尾箭头、更多 |
| `NoWaveIconSize.action` | 22 | 行动行前导图标、独立图标按钮 |
| `NoWaveIconSize.display` | 48 | 空态/对话框里的装饰字形 |
| `NoWaveSizes.tapTarget` | 48 | 最小点击区域 |
| `NoWaveSizes.primaryAction` | 52 | 整宽主按钮高度 |
| `NoWaveSizes.row` | 64 | 可点列表行最小高度 |
| `NoWaveSizes.tabBar` | 64 | 底栏高度（不含系统手势区）：图标加一个词，每格都远超 48 的点击区 |
| `NoWaveSizes.seekThumb` | 12 | 朗读进度条上的方形滑块：与文末墨色方块同一语言，不用 Material 的圆钮 |
| `NoWaveSizes.coverAspect` | 4/3 | 网格项里的封面比例 |
| `NoWaveSizes.coverAspectWide` | 16/10 | feed 头条卡片与阅读页头的封面比例 |
| `NoWaveSizes.maxReadingWidth` | 720 | 平板上的正文最大宽度 |
| `NoWaveSizes.contentColumn` | 680 | 列表、表单、设置等页面主栏的最大宽度（比正文窄，平板上居中） |
| `NoWaveSizes.coverEditorBox` | 250 | 编辑器里固定的封面框（三种状态同框，表单不跳） |
| `NoWaveSizes.emptyStateOffset` | 48 | 空态/加载态在列表里从多高开始 |
| `NoWaveSizes.listThumbnail` | 56 | 列表行前导缩略图（骨架屏的列表行） |
| `NoWaveSizes.listThumbnailSmall` | 48 | 行内还要放操作时的小缩略图（回收站、评论头像框） |
| `NoWaveSizes.bylineAvatar` | 40 | 阅读页署名行的方形头像：配两行字，不是独立的缩略图 |
| `NoWaveSizes.splashColumns` | 6 | 冷启动幕布切成的竖列数 |
| `NoWaveSizes.splashCounterMax` | 220 | 幕布计数器字号上限；实际取 `30vw` 与它的较小值（`splashCounterViewport`） |
| `NoWaveSizes.splashWordmark` | 40 | 幕布与启动失败页的字标 |
| `NoWaveSizes.masthead` | 22 | 应用栏里的紧凑字标 |
| `NoWaveSizes.splashProgress` | 3 | 幕布右下装饰段的厚度（装饰，不是进度条） |
| `NoWaveSizes.splashProgressLength` | 72 | 该装饰段的长度 |
| `NoWaveSizes.loadingRule` | 40 | 加载标签上方那道短横线 |
| `NoWaveSizes.skeletonLine` | 12 | 骨架屏一行的高度（≈正文 x-height） |
| `NoWaveSizes.activityChart` | 56 | 阅读统计 7 天活动条的高度 |
| `NoWaveSizes.activityBarEmpty` | 0.06 | 当天无阅读时活动条占图表高度的比例（保留可见基线） |
| `NoWaveSizes.accentRule` | 2 | 标记「位置」的细线厚度：页内选中词下的墨线、阅读进度线、刷新线 |
| `NoWaveSizes.entranceRise` | 12 | 列表项进场时上浮的距离 |
| `NoWaveSizes.arrowNudge` | 4 | 按下 / 悬停 / 聚焦时行尾箭头向前迈出的距离 |
| `NoWaveSizes.busySegment` | 0.4 | 忙碌标记里走动线段占图标槽位的比例（槽位很小，所以比刷新线段长） |
| `NoWaveSizes.endMark` | 8 | 文末那枚墨色小方块（杂志的终止符）的边长 |
| `NoWaveSizes.statusMeasure` | 320 | 空态/出错态那句话的最大行宽：断成居中的一小段，像引文，而不是横贯一页的一行 |
| `NoWaveSizes.formMeasure` | 480 | 账号页表单栏的最大宽度：再宽，下划线拉得太长，眼睛对不上标签 |
| `NoWaveSizes.refreshSegment` | 0.3 | 下拉刷新进行中，沿列表顶边移动的橙色线段占列表宽度的比例 |

编辑式界面本身仍是方角（`none`）：`inline` 到 `container` 这几档记录的是内容面
**已经在用**的圆角（#294 盘点时散落为 18 处 `BorderRadius.circular(数字)`），给它们起名
是为了让页面不再自己写数字，不是鼓励新圆角——要加一档，先在这里改表。原来的离群值
11 与 13 都是计数角标（`minWidth` 的一半），归入 `pill`：默认字号下渲染完全一致，
放大字号时角标保持胶囊而不是变成圆角矩形。两处拖拽条的 2 同理（高 4 的胶囊）。

### 直接字号 `NoWaveTypeScale`

优先使用主题文字角色（`TextTheme`）或 `NoWaveTypography`；下面几档只服务于仍需
直接设字号的地方，让它们有名字、能一起迁移。页面里不再出现 `fontSize: 数字`
（`test/unit/design/no_magic_radius_and_type_test.dart` 守护，`lib/core/theme/` 与
`lib/core/design/` 之外一处也不许）。

| token | 值 | 用在哪 |
| --- | --- | --- |
| `eyebrow` | 11 | 章节标题上方的小标题：小、字距拉开，也是全应用唯一的全大写文字 |
| `codeBlock` | 13 | 等宽块：代码块、诊断报告 |
| `codeInline` | 14 | 正文里的行内代码 |
| `tabLabel` | 12 | 底栏图标下的词 |
| `caption` | 12 | 评论名字下面那行日期与「已编辑」：一条评论里最小的一档 |
| `label` | 15 | 标签/分类 chip、页内切换词 |
| `actionRow` | 16 | 行动行（个人中心菜单）的文字：无衬线、w500——一列十来个入口读作菜单，而不是一排和账户名抢位置的标题 |
| `comment` | 16 | 评论正文（回复用 `label` 15），比正文小一号 |
| `hint` | 17 | 封面上传框里的提示 |
| `runningHead` | 17 | 阅读页书眉：标题滚走后，应用栏里重复的那行小标题 |
| `sectionTitle` | 18 | 文章下方的分节标题（评论、相关阅读） |
| `dialogTitle` | 24 | 对话框标题（衬线）：问读者的一句话是编辑文字，不是系统警告；文末分节头（相关阅读、评论）也用这一档 |
| `articleTitle` | 40 | 阅读页的文章标题（衬线）：读者在一篇文章里遇到的最大的字 |
| `heading` | 36 | 页面大标题（`NoWaveSectionHeading`）：列表页上最大的字 |
| `figure` | 40 | 摘要里数出来的数字（阅读历史的三个总数）；展示字体、等宽数字 |
| `articleBody` | 18 | 正文的「标准」字号（衬线，行高 1.9） |
| `readerBodySizes` | 16 / 18 / 20 / 22 / 24 | 阅读字号的五档正文字号；正文里的小标题、代码、图注按同一比例（相对 `articleBody`）缩放，叠加在系统字号之上 |

### 线与遮罩的不透明度 `NoWaveOpacity`

| token | alpha | 说明 |
| --- | --- | --- |
| `dividerAlpha` | 100（≈39%） | 分隔线、细线 |
| `focusAlpha` | 55（≈22%） | 焦点的强调色洗色 |
| `hoverAlpha` | 25（≈10%） | 指针悬停的强调色洗色：比焦点浅，悬停是浏览，焦点是键盘用户必须找得到的决定 |
| `disabledAlpha` | 97（≈38%） | 禁用控件的前景色 |
| `skeletonAlpha` | 28（≈11%） | 骨架屏填充：纸色和墨色两侧都用前景色的 11% |

用 alpha 而不是写死的灰，是因为同一条线要画在纸色和墨色两种底色上。

### 动效 `NoWaveMotion`

| token | 值 | 说明 |
| --- | --- | --- |
| `fast` | 120ms | 按下、开关等直接反馈 |
| `normal` | 200ms | 内容进出（提示条、列表刷新） |
| `slow` | 320ms | 页面与面板切换 |
| `enter` | 1000ms | 内容进入（揭示、遮罩打开） |
| `page` | 900ms | 路由转场 |
| `resume` | 700ms | 「从上次停下的地方继续」：沿同一篇文章滑到上次的位置——看得出是在同一页里走，又比转场短 |
| `counter` / `counterFinish` | 1800ms / 350ms | 幕布计数爬到 `088` 与最后一跳 `088 → 100` |
| `curtain` / `stagger` | 900ms / 80ms | 单列上撕与相邻列的错开 |
| `minimumSplash` / `splashBail` | 1400ms / 4500ms | 最短幕布时长与兜底揭幕 |
| `pressScale` | 0.98 | 文章被按下时下沉到的比例（像纸被指尖压下，不像玩具按钮） |
| `stampScale` | 1.3 | 切换态图标落下时的初始放大比例（盖章，而不是换图） |
| `entranceCount` | 6 | 新列表里逐个上浮进场的条目数（约一屏），间隔 `stagger` |
| `runningHeadRise` | 0.5 | 书眉出现时从自身高度一半处升到位（读作「升进栏里」，而不是从别处滑来） |
| `returnLeap` | 1.0 | 再点当前标签回顶部时，从多远开始「走」（屏数）：更远的先跳到这里，只走最后一屏 |
| `strokeLag` | 0.25 | 选中线移动时后沿比前沿晚走、晚到的比例（占 `slow`）：先伸长再收拢，像一笔，而不像橡皮筋；空态里按钮也晚句子这么多出现 |

幕布那几行只在冷启动用，语义与时序见 [冷启动与墨色幕布](startup.md)。

### 减少动效 `NoWaveMotionPolicy`

`NoWaveMotionPolicy.reducesMotion(context)` 用一个谓词回答「这个上下文要不要少动一点」：
系统的「移除动画」开关，或者读屏（TalkBack / VoiceOver 一次只读一个元素，页面在它下面
滑动会把读者的位置带走）。全仓只有这一处读这两个 flag，调用点不必各自记得。

| 成员 | 用途 |
| --- | --- |
| `reducesMotion(context)` | 需要少动时返回 `true` |
| `resolve(context, duration)` | 原样返回 token；少动时返回 `Duration.zero` |
| `curve` | 内容进出：`fastOutSlowIn`，起步快、落定软、不弹 |
| `travel` | 移动到某处（朗读跟随滚动）：`easeOut`，只减速落点 |

减少动效不是把 200ms 压成 20ms，而是根本不构建那个转场。`NoWaveFadeTransition`
（四个标签之间的淡入）就是这么做：少动时直接返回 child，连 `FadeTransition` 都不出现。

动效时长只从 `NoWaveMotion` 取。`test/unit/design/no_magic_durations_test.dart` 扫描
`lib/`，只放行「在等」的文件（请求超时、重试退避、自动保存、输入防抖），并在表里写明
理由；界面文件自己写 `Duration` 会失败。`fast`（按下反馈）与 `slow`（列表进场）已有
使用者；`enter` / `page` 目前没有
使用者，留给真的需要那一步的地方，不要为了用而用。

### 断点 `NoWaveBreakpoints`

| token | 值 | 说明 |
| --- | --- | --- |
| `medium` | 600 | 两列的上限；从这里起三列 |
| `expanded` | 900 | 从这里起四列 |

`columnsFor(width)`：< `medium` → 2 列，`medium`–`expanded` → 3 列，≥ `expanded` → 4 列。
列表、骨架屏和未来的平板侧栏都读这一个函数与它的 token，避免各算一套。

### 主题映射

`lib/core/theme/theme.dart` 把上表落到 Material 上，因此即使某个页面直接用
`FilledButton`、`OutlinedButton`、`TextField`、`AlertDialog`、`Chip`，形状、线宽和
最小高度也一致：

- 填充/描边/文字/图标按钮：方角，最小高度 ≥ 48，主按钮 52；
- 输入框：`medium` 内边距，1pt 边框，聚焦 2pt；
- 对话框：底色同页面，方角，0 阴影，四周一道前景色发丝线（同一张纸上靠边线浮起，
  像印刷卡片的切边）；标题用衬线 `dialogTitle`（24/w600），与分节标题同一种声音；
- 分隔线：`dividerAlpha` + 1pt；`Chip`：方角 1pt 描边；
- 卡片：0 阴影、0 色调、方角、`surface` 底色；列表项：`NoWaveSizes.row` 最小
  高度、`medium` 内边距、方角；
- 应用栏：0 阴影，标题从 `page` 起排（`titleSpacing`），与下面的栏左对齐；
  `centerTitle: false` 也写在主题里——原来 12 个页面各自要求居中、两个页面加了
  `elevation: 1`，同一个应用里标题一会儿居中一会儿靠左。页面不再自己设
  （`ui_consistency_guard_test` 守着）；
- 底部面板：底色同页面、0 阴影、方角，只在上沿有同样的发丝线（它从底边升起，
  另外三边贴着屏幕）；SnackBar：浅色下墨底纸字、深色下纸底墨字，
  方角 0 阴影，行动文字用强调色（深色用橙、浅色用牛血红）；
- 开关/复选框/分段按钮：选中态为强调色填充 + `onPrimary` 前景，未选中为 1pt
  `muted` 描边，方角，≥48pt。

## 三、组件

组件分两层：`lib/core/design/components/`（本系统新增的通用件）与
`lib/core/common/widgets/`（既有编辑式组件）。

| 组件 | 位置 | 用途 |
| --- | --- | --- |
| `NoWaveButton` | `design/components/no_wave_button.dart` | 主/次/静默/破坏性四种变体，含忙碌与禁用态 |
| `NoWaveBadge` | `design/components/no_wave_badge.dart` | 封面或标题旁的短标签（草稿、语言版本） |
| `NoWaveNotice` | `design/components/no_wave_notice.dart` | 内联提示（说明、限制、失败 + 重试） |
| `showNoWaveConfirmDialog` | `design/components/no_wave_confirm_dialog.dart` | 破坏性动作的二次确认 |
| `NoWaveStatus` | `common/widgets/no_wave_status.dart` | 空态/错误态：一句衬线排的话（无事可做是浅色，有行动是墨色）、可选一行小号说明（`detail`）、至多一个描边按钮；没有装饰记号；出现时淡入上浮，按钮稍晚 |
| `NoWaveSectionHeading` / `NoWaveEyebrow` | `common/widgets/no_wave_section_heading.dart` | 编辑式大标题（可换行）；可选的小标题 `NoWaveEyebrow`：只有一行小号、拉开字距的浅色字，拉丁字母全大写，前面不加线 |
| `NoWaveLinkButton` | `design/components/no_wave_link_button.dart` | 从栏边起排的文字链接：只留尾部内边距和 48pt 点按高度，链接与它所属的名字、标题对齐，而不是缩进一格；`forward` 在字后加箭头 |
| `NoWaveMenuGroup` | `common/widgets/no_wave_menu_group.dart` | 一组行动行：上面一行灰色小字名（不是眉题，只为长菜单能扫读），下面一道细线收尾；个人中心与「关于」共用 |
| `NoWaveActionRow` | `common/widgets/no_wave_action_row.dart` | 个人中心式的可点行动行；与文章卡片同样的回应（水波、橙色焦点/悬停洗色、行尾箭头前移），但不下沉 |
| `NoWaveMasthead` | `common/widgets/no_wave_masthead.dart` | 双字体字标 |
| `NoWaveAvatar` | `common/widgets/no_wave_avatar.dart` | 方形头像，失败回退中性图 |
| `NoWaveListNote` | `design/components/no_wave_list_note.dart` | 列表半路停下时的页脚：下一页加载失败，或这个排序只能翻这么深。一行浅色 `metaLabel`（与「正在加载更多」同一个声音）+ 一个静默按钮；是 `NoWaveStatus` 的小号兄弟 |
| `NoWaveLoadingLabel` | `design/components/no_wave_loading_label.dart` | 加载态：一道短横线 + 一句文案，没有转圈 |
| `NoWaveSkeleton` / `...List` / `...Line` / `...Block` / `...Divider` | `design/components/no_wave_skeleton.dart` | 内容形状的占位（列表、行、块、行间细线） |
| `BlogFeedSkeleton` | `features/blog/presentation/widgets/blog_feed_skeleton.dart` | feed 首帧与紧凑文章列表的静态占位；头条可关闭 |
| `BlogGridSkeleton` | `features/blog/presentation/widgets/blog_grid_skeleton.dart` | 网格首帧：与 `blogGridDelegate` 同列数、同高，封面沿用 4/3 |
| `NoWaveFadeTransition` | `design/components/no_wave_fade_transition.dart` | 标签切换的淡入；少动时不构建转场 |
| `NoWaveTabBar` / `NoWaveTabDestination` | `design/components/no_wave_tab_bar.dart` | 底栏：挂在上沿发丝线上，选中格在那条线上压一道与词同宽的墨线，换格时像一笔划过去；图标盖章成实心；少动时直接落位 |
| `NoWaveColumn` | `design/components/no_wave_column.dart` | 页面的文字栏：手机上满宽，宽屏上居中一栏；子组件总是**撑满**这一栏（原来 7 份手写的 `Align` + `ConstrainedBox` 会让标题缩到字宽再居中）；`inset` 给栏外要对齐的东西（应用栏字标、页内切换） |
| `NoWaveReturnToTop` | `design/components/no_wave_return_to_top.dart` | 再点当前底栏标签：屏幕上的列表回到顶部，栈不动；远处先跳近再走一屏；少动时直接跳 |
| `NoWaveRunningHead` | `design/components/no_wave_running_head.dart` | 阅读页书眉：正文标题滚到应用栏下面后，栏里升起一行小标题并出现一道发丝线；点它回到开头 |
| `NoWaveEndMark` | `design/components/no_wave_end_mark.dart` | 终止符：一枚墨色小方块，下面一行字。列表到底（「没有更多了」）两侧带发丝线；阅读页正文之后用 `ruled: false`，只留方块和「全文完」（作者已在文章顶部介绍，不再重复），断开交给下面换纸 |
| `NoWaveSnackBarContent` | `core/utils/show_snackbar.dart` | 所有提示条的内容：只有那句话（反色纸条本身就是信号）；由 `showSnackBar` 统一使用 |
| `NoWaveBusyMark` | `design/components/no_wave_busy_mark.dart` | 控件槽位里的忙碌态（按钮加载、行内恢复、发送图标）：图标大小的细线上走过一小段，颜色随控件；少动时停在中间 |
| `NoWaveRefresh` | `design/components/no_wave_refresh.dart` | 下拉刷新：沿用系统手势，不画转圈；顶边一道线随手指从中间长出，过了松手点变橙，刷新时一段橙线沿顶边走过 |
| `NoWaveSlidingTabs` / `NoWaveSlidingTab` | `design/components/no_wave_sliding_tabs.dart` | 页内的一排词（首页 feed 切换、作者页「最新 / 热门」）：站在一条通栏的浅色发丝线上，选中词下一道与词同宽的 2pt 墨线像一笔划过去，先伸长再收拢；大字号时横向滚动；少动时直接落位 |
| `NoWaveReadingProgress` | `design/components/no_wave_reading_progress.dart` | 阅读页顶部随滚动填满的橙色细线；跟手、不计时，读屏不读 |
| `NoWavePressable` / `NoWavePressArrow` | `design/components/no_wave_pressable.dart` | 文章卡片与网格项的可点表面：保留 InkWell 的水波、焦点与语义，按下时下沉，行尾箭头向前迈一步 |
| `NoWaveEntranceScope` / `NoWaveEntrance` | `design/components/no_wave_entrance.dart` | 新列表前一屏逐个上浮进场；同一位置只进场一次，换列表（`generation`）才重来 |
| `NoWaveStampSwitcher` | `design/components/no_wave_stamp_switcher.dart` | 切换态图标的「盖章」：新状态放大落下再归位（阅读页收藏） |
| `NoWaveSectionHead` | `design/components/no_wave_section_head.dart` | 文末分节头（相关阅读、评论）：不画线，24 号衬线标题靠字号和下方 16 的留白与行区分；可选右对齐数字压在同一基线 |
| `NoWaveCoverPlate` | `design/cover/no_wave_cover_plate.dart` | 四张编辑式默认封面，按文章身份稳定选一张 |
| `ArticleCover` | `features/blog/presentation/widgets/article_cover.dart` | 真封面 / 加载 / 失败三种状态共用同一张版 |
| `ArticleCategoryLabel` | `features/blog/presentation/widgets/article_category_label.dart` | 文章所属的分类（服务端给的名称；可点进分类列表）。默认是填充色块；阅读页的 kicker 里用 `quiet: true`，只是一个粗墨色的词 |
| `ArticleTagLabel` | `features/blog/presentation/widgets/article_tag_label.dart` | 作者写的标签（可点进标签列表）。默认描边；`quiet: true` 时是一个浅色的词（阅读页 kicker、首页与各列表的文章行） |

### 加载态：一句文案或一个形状

`lib/` 里已经没有页面级或区块级的转圈指示器，`Loader` 也随之删除。两种替代品：

- **`NoWaveLoadingLabel`** —— 屏幕级、区块级，以及列表页脚（`compact: true` 去掉短
  横线）。它同时是读屏播报（一个 `liveRegion`、一句话），所以那道横线在
  `ExcludeSemantics` 里。
- **`NoWaveSkeleton*`** —— 有形状可借的页面。列表（通知、私信、阅读历史）借
  `NoWaveSizes.row` / `listThumbnail`；首页 feed 借 `BlogFeedSkeleton`：一张 16:10 的
  头条封面 + 两个标题行 + 作者行，再跟若干行「元信息 / 两行标题 / 作者」，行与行之间用
  `NoWaveSkeletonDivider`。数据落地时页面不跳。**不动**：没有 shimmer、没有渐变扫光——
  动效由 `NoWaveMotionPolicy` 统一决定要不要发生，加载态不该先花掉用户的注意力，
  静态块在截图里也读得懂。作者、标签与分类文章列表复用紧凑行，关闭头条封面；
  分页续载仍使用紧凑文案，不改变请求或分页。
- 网格页（我的文章、收藏）借 `BlogGridSkeleton`：列数与 tile 高度直接来自
  `blogGridDelegate`，封面沿用 `NoWaveSizes.coverAspect`（4/3），padding 与真实网格一致
  （两页都在左右 `page` 槽宽的 `SliverPadding` 里；`blogGridDelegate(context, gutter:)`
  量列宽时先减掉两侧槽宽，骨架与真实网格同一算法）。收藏页与搜索页同构：应用栏刊头
  `titleSpacing` 用 `NoWaveColumn.inset`，下面一个 `NoWaveSectionHeading`，刊头、标题和
  网格共用同一条左边。
- 首页 feed 的首帧还多一条规矩：标题（`feedHeading` 等）是静态的，所以**加载时就画
  出来**，占位骨架接在它下面；数据回来时列表往已经占好的位置里长，而不是把页面往下推。

**边界**：控件自己的忙碌态仍由控件表达 —— `NoWaveButton(isLoading: true)` 保持标签
在布局里不变高、保持不可点；回收站行内的"恢复中"与私信发送图标位放不下一句文案，
用图标大小的 `NoWaveBusyMark`：一道细线上走过一小段（`busySegment`），和下拉刷新
是同一个图形，颜色跟随所在控件的前景色。至此 `lib/` 里没有任何转圈，
`no_spinner_test.dart` 的白名单为空。

`_row` 里那三道横线的宽度比例写在组件内部（`_lineWidths`），不是全局尺度：它们是
"一段话"的形状，不是间距。

### 封面：四张编辑式默认版

没有封面的文章以前共用一张图，于是八张卡片看起来像同一篇。现在有四张同族的版
（墨、网点、一处橘色），够读者把两张卡分开，又不假装图片有什么含义：

| 版 | 资产 | 构成 |
| --- | --- | --- |
| `arc` | `assets/images/no_wave_cover_arc.jpg` | 一道墨笔横扫 + 橘色渗边 |
| `halftone` | `assets/images/no_wave_cover_halftone.jpg` | 网点场 + 一条橘色横规 |
| `block` | `assets/images/no_wave_cover_block.jpg` | 牛血色与墨色方块叠在撕口纸上 |
| `column` | `assets/images/no_wave_cover_column.jpg` | 竖列墨条 + 一道橘色斜切 |

**选版规则**：`NoWaveCoverPlate.forSeed(seed)`，`seed` 是文章的**身份**（slug 或 id），
不是标题。哈希是 FNV-1a 32 位、输入 UTF-8 字节（`lib/core/utils/stable_hash.dart`）：
同样的文章在任何设备、任何版本、任何系统语言下都落在同一张版上。**禁止** `hashCode`
（可能按进程重新播种，Dart 版本间也变过）与 `Random`（每次重建都换图）；标题也不能当
种子，改标题不该换封面。

`ArticleCover` 先算出版、再去请求网络，所以占位、失败与最终帧是同一张图：请求失败时
图片不会变，读者看到的是「缺一张图」，不是「换了一篇」。

守这两条的是 `test/unit/core/stable_hash_test.dart`（对上 FNV-1a 公开向量）与
`test/unit/design/cover_plate_test.dart`（选版映射被钉住、四张都会被用到、资产确实存在
且是 JPEG、选版代码里没有 `hashCode` / `Random` / `DateTime.now`）。

### NoWaveButton

| 变体 | 外观 | 何时用 |
| --- | --- | --- |
| `primary` | 强调色填充 + 墨色字，52pt | 一页/一对话框唯一的主行动 |
| `secondary` | 透明 + 1pt 描边 | 真实的次要行动 |
| `quiet` | 纯文字，仍 48pt | 导航、行内行动、对话框取消 |
| `destructive` | 错误色描边 + 错误色字 | 删除、结束会话、清空历史 |

规则：

- **必须传可见标签**，只有图标时用带 tooltip 的 `IconButton`。
- `isLoading` 保留标签（宽度不跳）、拦截点击，并向读屏报告为「不可用」——当前
  Flutter 的语义里没有 busy 标志，所以忙碌态靠禁用播报加可见的 `NoWaveBusyMark` 表达；不要另外
  在页面上再弹一个「处理中」。
- `onPressed: null` 是禁用态，高度不变，避免整行按钮跳动。
- 标签在上下文里有歧义时（列表里一排「删除」）传 `semanticLabel`。
- 不使用 `ElevatedButton`/`FilledButton` 直接写业务按钮；它们只作为主题兜底。

### NoWaveNotice

- `tone`：`info`（背景信息）/`warning`（能继续用但有局限，比如旧部署）/`error`。
- **只有由动作产生、读者可能没看着那块区域的提示**才设 `isLive: true`；页面头部
  的常驻说明不要设，否则每次重建都打断读屏。
- 有下一步动作时把按钮放在提示里，不要塞进转瞬即逝的 SnackBar。
- 图标是装饰：语义里排除，含义必须由文案本身说清。

### 位置标记：选中词下的一道墨线

「你在这里」由三处回答：底栏、页内的一排词（首页 feed、作者页）和阅读页的进度线。

- **底栏（`NoWaveTabBar`）**：页内那排词的倒影。页内的词站在发丝线上、选中词下面压
  一道墨线；底栏从上沿一道发丝线上**挂下来**，选中的那一格在这条线**上**压一道与它的
  词同宽的 `accentRule` 墨线。换标签时墨线和页内一样像一笔划过去（同一个
  `NoWaveSlidingTabs.ruleAt`：前进方向的边先走、另一条边晚 `strokeLag`），所以两层导航
  只有一种「你在这里」的动作。选中的图标从描边「盖章」成实心（`NoWaveStampSwitcher`），
  词变墨色 w600，其余是浅色描边；按下时整格微微下沉。高 `tabBar`（64），词 `tabLabel`
  （12），字号最多随系统放大到 1.6 倍。每格是互斥组里的按钮，读屏读那个词；再点当前格
  照旧回到顶部。之前用的是 Material `NavigationBar` 关掉胶囊——只剩图标换实心，和任何
  一个默认应用没有区别；更早那道悬在半空的橙色短线也不会回来：这道线是墨色的，压在
  栏的边上，不是另画的一道。
- **`NoWaveReadingProgress`**：手机上没有滚动条也没有页码，长文读到哪儿只能靠
  猜。它包在阅读页正文外，只跟最外层纵向滚动（notification depth 0，横向代码块不
  影响），内容变长（图片加载完）时也会缩回真实比例；不滚动的页面算「没读」，不
  显示满格。进度由手指驱动，所以仍是橙色。
- **`NoWaveSlidingTabs`**：首页 feed 的「最新 / 精选 / 最多收藏 / 关注」原本是一排
  Material 的 `ChoiceChip`。现在是一排词，站在一条**通栏**的浅色发丝线上（与 `Divider`
  同色同粗，读作页头的下沿，而不是四个词的下划线）；选中词下压一道与词同宽的
  `accentRule` **墨线**。原来这条底线是全黑的、只和词一样宽并且居中，第一个词左边还
  露出一截黑线在橙线前面；现在底线贴满给它的宽度、颜色退到发丝级，选中线换成墨色，
  两条线不再争。切换时墨线像一笔划过去：朝前进方向的那条边先走，另一条边晚
  `strokeLag` 才出发，用 `slow` + `travel` 完成。所以线会先伸长跨过中间的词，再收拢
  到新词下面。从右往左的语言里方向也跟着反过来。
  - 每个槽位的宽度在布局前按选中字重（以及系统粗体设置）量好。选中只改变颜色和字重，
    不会挤动相邻的词，墨线在同一帧就知道每个词的位置。
  - 2× 字体、320dp 屏幕下这一排横向滚动，不换行。选中的词如果在屏幕外，会被滚进视野，
    并保留页边距。
  - 每个词都是互斥组里一个「已选中 / 未选中」的按钮，至少 `tapTarget` 高。按下用
    `NoWavePressable` 下沉，焦点和悬停用橙色洗色。
  - 「关注」在未登录时会先去登录：组件只报告点了哪个词，选中与否由调用方决定，
    所以墨线不会先走过去再弹回来。
  - 每个词贴着自己槽位的起点排，墨线从词的起点画起、与词同宽。`inset` 是这一排的
    页边距：首页传 `page`，第一个词与下面的标题左边对齐；作者页的栏本身已有页边距，
    传 `0`。
- 这些线都是装饰：`ExcludeSemantics` + `IgnorePointer`，选中态和位置由控件本身告诉
  读屏。进度线由手指驱动、没有时钟，所以「减少动效」下无需关闭；页内这排词在少动时
  直接落位，滚动改为跳转。
- **`NoWaveRefresh`**：系统的下拉刷新会在列表上落下一个转圈的圆片——全屏唯一一个
  不属于这套字体和配色的元素，也正是 `no_spinner_test.dart` 在别处挡掉的东西。现在
  12 处（11 个页面）都换成 `NoWaveRefresh`：手势仍由 Flutter 的
  `RefreshIndicator.noSpinner` 判定（什么时候开始、什么时候算数、iOS 的回弹），只换
  画的东西，全部在列表顶边一条 `accentRule` 厚的线上：
  - **下拉中**：一道发丝色的线从中间向两边长出，长度就是离松手点还有多远；
  - **过了松手点**：线变橙、碰到两边，并轻轻一次选择触感——「可以松手了」，不用一个字；
  - **刷新中**：一段 `refreshSegment` 宽的橙线以 `enter` 为周期、`travel` 曲线沿顶边
    从起点走到终点，像排字，直到 `onRefresh` 完成；
  - **完成 / 取消**：线淡出（`normal`）。
  - 松手点与框架一致：拉过视口高度的 25%。在会回弹的列表上（iOS、macOS），框架一进入
    `armed` 就会在回弹时刷新，所以那里 `armed` 就算过了松手点。
  - 线是装饰（`ExcludeSemantics` + `IgnorePointer`）。刷新中有一个 `liveRegion`，读出
    系统自带、已本地化的「刷新」标签，不新增文案。少动时线段不走，整条橙线停住直到
    完成，然后直接消失。
  - `no_spinner_test.dart` 现在也拦 `RefreshIndicator(`、`RefreshIndicator.adaptive(`、
    `RefreshProgressIndicator` 与 `CupertinoSliverRefreshControl`；只有
    `.noSpinner` 可以出现，而且只在这个组件里。
- 橙色在纸色上的非文字对比度约 3.5:1、墨色上约 4.8:1，都过 3:1 的图形要求，所以两种
  主题都用 `AppPalette.orange`，不换成牛血红。

### 小标题：章节标题上方的一行

杂志在栏目标题上方会印一行小字，说明这是什么栏目。`NoWaveSectionHeading` 的
`eyebrow` 现在画成 `NoWaveEyebrow`，不再是普通的元信息字：

- 前面**不加线**：原来有一道 16pt 的橙色短线，标在每个标题之前，只会推迟读到字的那
  一刻；小字号、拉开的字距和浅色已经足够把它和正文分开；
- 文字用 `NoWaveTypography.metaLabel`，字号 `NoWaveTypeScale.eyebrow`（11）、w600、
  `onSurfaceVariant` 色；
- 拉丁字母全大写，字距为字号的 14%——全应用只有这里用全大写，所以它读作标签，不会
  被当成一句话；中文没有大小写，保持原字，字距收到 8%，足以和正文区分，又不会把词
  拆成一个个孤立的字；
- 读屏读原文（`semanticsLabel`），不读大写，英文不会被逐字母拼读；
- **大标题**（`heading`，36，行高 1.15）和后面的斜体注（「最新 *Latest*」）是同一段文字：
  共用基线、像词一样换行。原来是 `Wrap` 里按底边对齐的两个盒子，中文衬线和拉丁斜体的
  下伸部不同，注总是比标题偏几个点；注现在用浅色，先读到标题；
- **日期**（`aside`）：首页把当天的「月 日 星期」放在小标题这一行的另一端，像报纸的
  报头日期——feed 读起来是「今天这一期」，而不是一条没有尽头的流；放不下时落到小标题
  下面一行。格式来自 `formatDateline`（仍是唯一构造 `DateFormat` 的文件）；
- **对齐**：标题块曾经被 `Align` 缩到字宽后**居中**，小标题比标题长时，整块看起来像
  居中又不像。现在由 `NoWaveColumn` 撑满文字栏，宽屏上应用栏字标（`titleSpacing`）、
  页内切换的第一个词、小标题、大标题和卡片都从同一条边起排；
- 长句在 2× 字号下换行，不截断。

**少用**：眉题只在它说了标题没说的话时才印。登录（「收藏、评论和写作，从这里开始」）、
注册、搜索（「按标题查找 · 或浏览标签与分类」）、收藏（「留着慢慢读的文章」）、离线书库
（「已下载 · 无网络也能读」，下面本来就有一句说明）、作者页文章区（「作品目录」，和
「TA 的文章」说的是同一件事）的眉题都删了，对应的 `*Eyebrow` 文案键一起删除；首页只留
日期（`aside`），不再印「独立文学出版 · 阅读与交流」——刊头已经说了这是什么。现在
`NoWaveEyebrow` 只用在阅读统计卡的标题上，那里它就是这一节的名字。

### 阅读页：少画线，用字号、留白和纸色分层

阅读页曾经从上到下有十来道线：带框的分类与标签、标题下的分隔线、朗读区上下的发丝线、
终止符两侧的线、相关阅读与评论的 2pt 墨线、每一行相关阅读和每一条评论上方的发丝线、
输入框下划线。线一多，每一道都不再说明什么，层级反而平了。现在全页只保留输入框的
下划线（它是控件，不是装饰），其余层级交给四样东西：

- **封面开篇、出血到屏幕两边**：封面紧贴应用栏，向左右各伸出 `page` 槽宽（`_Bleed`
  只在绘制上伸出，布局仍占文字栏宽），像杂志专题的开篇图。结构化正文自带图片时不另造
  封面，标题前留 `medium`。
- **kicker → 标题 → 署名**：封面下一行 kicker，分类是粗墨色的词、标签是浅色的词
  （`quiet: true`，不加框，仍各自是 48pt 的可点目标）；标题 40 号衬线
  （`NoWaveTypeScale.articleTitle`），是读者在文章里遇到的最大的字；署名行是 40pt 方形头像
  （`NoWaveSizes.bylineAvatar`）+ 粗体作者名 + 一行浅色「日期 · 阅读时长」，整行可点开作者页。
- **朗读是一张纸片**：`ReadAloudControls` 不再夹在两道线之间，而是一块
  `surfaceContainer`（浅色 #E9E3D8 / 深色 #211E1B）的平面，播放键是一枚墨色方块里反白的
  图标——纸片上唯一实心的东西，视线先落在「播放」上；「跟随朗读」的勾选框也是墨色。
  按下之前，纸片只有一行：方块旁边是「朗读文章」和一行浅色说明，两行字对着方块居中；
  进度条、语速、跟随、声音和定时这一层要到声音响起才从方块下展开（`NoWaveMotion.slow`
  的高度过渡，同时淡入），停止后再收起。还没开始听的读者不必先越过一整块控制面板才读到
  正文；少动模式下直接切换，没有过渡。
- **文末换纸**：正文之后只有一枚墨色方块和「全文完」（不带线）；相关阅读与评论放在一整块
  通栏的 `surfaceContainer` 上（`article-end-matter`），内容不足一屏时用
  `SliverFillRemaining` 把这块纸铺到底。一次换色比任何一道线都更明确地说「文章结束了」，
  所以里面的分节头、相关阅读行（`BlogCard(quiet: true)`：只留序号、日期、标题、作者，不列标签）和评论串都不再画线：评论串之间
  靠留白分组，回复挂在父评论的文字栏下。登录提示和评论头像的底色是页面本色，放在这块
  深一档的纸上才看得见。

### 账号页：和其他页面同一种排法

登录曾是一屏居中的粗黑体「登录」、两只带图标的方框输入框和一串居中的文字链接——很多人
打开应用看到的第一屏，却不像应用里任何一页。现在登录、注册、找回密码、重设密码都放在
`features/auth/presentation/widgets/auth_frame.dart` 的 `AuthFrame` 上：

- **同一套页头**：应用栏是 No Wave 刊头（有返回箭头时跟在箭头后，否则对齐栏边），下面是
  `NoWaveSectionHeading`：标题 + 斜体副词（「登录 *Sign in*」），上面不再印一行眉题——
  标题已经说了这页做什么，再加一句宣传语只会推迟读者看到输入框。`AuthFrame` 也不再接受
  `eyebrow`。需要先解释的页面（找回、重设）在标题下放一句
  `sectionTitle` 号的浅色衬线导语。
- **一条左边线**：栏宽止于 `NoWaveSizes.formMeasure`（480）；更宽的屏幕上整栏居中，
  刊头也从栏边开始。
- **输入框是一条线**：`AuthField` 不再是方框，而是墨色发丝下划线，标签在上方浮起；
  聚焦时线变成 2pt 橙色（「回应触摸」的那一处强调），出错时变成错误色。不再放前置图标。
- **按钮忙时不换页**：`AuthPrimaryButton(isLoading:)`——请求进行中按钮保留文字并报告
  忙碌，输入框暂时不可编辑；以前整页会换成一个加载标签，表单消失又出现。
- **按钮下的链接居中、分层**：`AuthLink` 是一行「浅色问句 + 粗体动作词」（「没有账号？**注册**」），
  紧跟主按钮；「暂不登录，先去逛逛」「查看诊断信息」这些不登录的出口放在更下面一组。
  它们都挂在通栏主按钮的中线下（`AuthLink` 默认 `alignment: center`，换行时也居中），
  和按钮读作一组，同样 48pt 可点。「找回密码」紧贴密码线下，也居中——整张表单只有一条
  中轴，不再有一个词单独靠右。

### 收藏页：跟上别处的收藏

收藏是账户的，不是这台手机的：在网页版或另一台设备上收藏、取消收藏，客户端听不到。
收藏页所以在每次**回到视野**时重读一次列表——切到「收藏」标签、关掉盖在上面的文章、
应用回到前台。底部标签用 `StatefulShellRoute.indexedStack` 保活，未选中的标签和被
盖住的页面都被关掉 `TickerMode`；`SavedBlogsPage` 在 `didChangeDependencies` 里读
`TickerMode.valuesOf(context).enabled`，由关变开就重读。几件事同时发生时（关掉文章既是
出栈又是重新可见）只发一次请求；不在视野里的收藏页回到前台时不读，等被打开时再读。

### 个人中心与收件箱：菜单是菜单，标题才是标题

个人中心曾是十三行一样大的衬线字，叠在账户名下面——每一行都像一个标题，页面反而没有了
顶。现在：

- **行是菜单项**：`NoWaveActionRow` 用无衬线 `actionRow`（16，w500），图标居中对齐单行
  文字；有说明时才顶对齐。「退出登录」不去任何一页，所以 `showArrow: false`。
- **分组**：`NoWaveMenuGroup` 把十三行分成「消息 / 写作与阅读 / 账户与安全」和最后一组
  无标题的「关于、退出登录」；有新消息的一组排最前。组名是一行灰色小字，不是眉题。
- **名字是这页唯一的标题**（衬线 32）；「查看我的作者主页」是从栏边起排的
  `NoWaveLinkButton`，和名字对齐。主题切换去掉了描边圆框，图标在切换时转一下、淡入。
- **收件箱**（私信、通知）：两侧都用页边距 28；未读靠字重说（w600 对 w400），通知行尾
  再加一个 8pt 墨色小方块，不再给整行铺底色。日期用 `formatRecent`：今天写时刻，一周内
  写星期，今年写月日，更早才写完整日期——二十分钟前的消息印成「2026年11月22日」什么也没
  说，还会在未读数旁边被截断。「文章地址可能已失效」只在列表底部说一次。
- **作者页、搜索结果**：第一张卡片上面不画线，线只在两张卡片之间。
- **我的文章**：删除不再是封面上的橙色实心圆，而是署名行尾一个安静的 `delete_outline`
  图标按钮（仍有「删除文章」提示与确认对话框）；长按仍可删除。

### 继续阅读：回到上次停下的地方

读到一半离开的文章，再打开时页脚浮起一张墨色纸条：「↓ 从上次停下的地方继续　42%」。

- **量的是正文**：位置是「已经滚过的正文」占「滚到文末『全文完』出现在屏幕底部」那段
  距离的比例，相关阅读和评论不算——它们晚到，会让每个已存的位置漂移。一屏放得下的文章
  不记。
- **什么时候记**：每次滚动停下（`ScrollEndNotification`），变化不足 1% 不写；只为已登录
  账号、跟阅读历史存在同一行（`reading_history.progress`，见
  [SQLite 存储](sqlite-storage.md)），退出登录随历史一起清掉。
- **什么时候提**：存下的位置在 `ReadingProgress.started`（5%）与 `finished`（95%）之间才
  提；点一下沿同一页用 `NoWaveMotion.resume`（700ms）滑过去，减少动效时直接跳到；自己往下
  读过了那里，纸条就收起；朗读进行中底部归朗读条，纸条让开。
- **为什么是墨色**：这是回到正文的路，不是主操作；橙色留给位置与焦点。深色主题里它是一张
  浅色纸条。
- **阅读历史**的日期后面写「读到 42%」或「已读完」，同样以 5% / 95% 为界。

### 列表行：一条左边线，和头条同一种收尾

首页、分类、标签、搜索和作者页的文章行曾经在左边单列一栏序号（36pt 宽），标签、标题、
作者都从序号后面开始，箭头钉在行的右上角。标签有 48pt 的可点区域，整行文字因此落在
48pt 的中线上，而序号和箭头贴着顶边——看上去比同一行的标签高出半格。现在：

- **序号进了眉行**：「02　散文　城市　11月17日」，墨色、半粗、等宽数字，和标签同在一条
  中线上；标题、作者不再缩进，和头条的标题从同一条栏边开始。窄屏上标题多出约 44pt。
- **箭头跟作者走**：作者名在左、箭头在同一行的行尾——头条（大图那一篇）一直是这样收尾的，
  现在每一行都一样，按下时箭头仍会往前推一点。
- 序号后面多空一档（`small`），读起来是这一行的编号，而不是又一个标签。

### 启动图标：一道会停下来的浪

桌面上的图标曾是一只像素锯齿的白色猴子，压在纯黑（#000）上，几乎顶满整块图标——放在
暖墨色的启动幕和纸色界面旁边，它是唯一一个「不是这套设计」的东西。现在它和网页的
favicon 是同一个记号：

- **记号**：一笔橙色（`AppPalette.orange`）从基线下方起笔，起伏一次，然后归于平直；
  平直那一段下面衬一条纸色（`AppPalette.paper`）细线——浪落定的那条线。比 favicon 画得
  更粗：笔画宽是记号宽度的 13%（原来 10%），细线和浪之间的距离跟着放宽，48px 时起伏和
  细线仍分得开。
- **底色**：`AppPalette.ink`（#0F0D0C），与启动幕同色，冷启动时图标和第一帧是同一块墨。
- **留白**：整个记号只占图标宽度的 60%，上下居中；安卓自适应图标前景再内缩 16%，
  记号落在 66dp 安全圆内，圆形、方圆、水滴遮罩都不会切到笔画。
- **主题图标**：安卓 13 的「主题图标」用 `logo-monochrome.png`：同一记号，只保留透明度，
  细线比浪淡一档，跟随系统配色。
- **来源只有一个**：三张源图都由 `tool/brand/launcher_icon.py` 按几何参数画出（需要
  pillow 与 numpy），不手工修图。改记号就改脚本里的参数、重跑，再
  `dart run flutter_launcher_icons`；CI 在发布构建前也会跑这一步，仓库里提交的安卓、
  iOS 图标文件与它的输出一致。

### 书眉：标题滚走以后

长文读过第一屏，应用栏里只剩返回箭头和两个图标，没有任何地方说明你在读什么。书籍的
做法是书眉——每页顶端印一行小号的书名。`NoWaveRunningHead` 就是阅读页的书眉：

- **何时出现**：正文标题整个滚到应用栏下面时（`NoWaveRunningHead.passed`：从布局里
  读出标题底边在内容中的位置，再与通知自带的滚动偏移比较，所以封面、提示、分类在不在、
  字号多大都不影响；不用标题的屏幕位置，因为滚动通知先于移动标题的那一帧到达，屏幕
  位置会慢一步，惯性滚动正好停在阈值上时会留下错误状态）；标题回来时
  离开。只看文章本身的纵向滚动（depth 0），横向代码块不算。
- **样子**：`NoWaveTypeScale.runningHead`（17）的衬线标题，单行省略；从自身一半高度处
  （`runningHeadRise`）随淡入升到位，`normal` + `curve`。同时应用栏下沿出现一道与
  `Divider` 同色的发丝线——书眉总是压在一道线上；回到顶部时线变透明。
- **点它回到开头**：`slow` + `travel` 滚回顶部；少动时直接跳。
- **读屏**：隐藏时根本不构建，页面上标题只有一份；出现时是一个按钮，名字是
  `readerRunningHead`（「标题，回到开头」），可见文字包含在名字里。少动时原地出现、
  原地消失。

### 再点一次：回到顶部

每个平台的底栏都这样做，读者也会不假思索地去试：在 feed 里翻得很深，再点一下「首页」
回到最新。`HomeShell` 把四个分支包在 `NoWaveReturnToTop` 里，点当前标签时调用
`toTop()`：

- **只动列表，不动栈**：读到一半的文章、打开的作者页都还在；它跟踪的是最近一次报告
  滚动的纵向列表（滚动通知，而不是控制器），所以每一页都不用改接线，包括自己持有
  控制器做翻页的 feed。横向的分类条、代码块不算。
- **什么时候不动**：列表已在顶部；或它所在的页面被别的页面盖住（路由不是当前的）。
- **怎么走**：比一屏（`returnLeap`）更远时先跳到离顶部一屏处，再用 `slow` + `travel`
  走完最后一屏——读起来是「回去」一个动作，而不是一路刷过所有文章。少动时直接跳到顶。

### 空态与出错：一句话、一条路

40 处空列表、无结果、加载失败都走 `NoWaveStatus`。它最早是一个 48pt 的斜体破折号，
上一轮换成过「方块 + 两段线」的记号；放到真机上，记号和上方的小标题短线、选中线挤在
一起，一屏里有四处小装饰在争注意力。现在不要任何记号：

- **一句话**：衬线、`sectionTitle`（18）、w400，居中，最宽 `statusMeasure`（320），断成
  一小段，像引文。**无事可做**（空列表、无结果）用 `onSurfaceVariant`，页面是安静的；
  **有一条路**（重试、登录）用墨色——这句话是对读者说的。颜色只由有没有行动决定，调用
  方不用改。
- **行动**：`NoWaveButton.secondary`（方角描边、48pt），与句子隔 `large`。
- **出现**：句子淡入并上浮 `entranceRise`，按钮晚 `strokeLag`，共 `slow` + `curve`。
  重试后又失败时会重新落一次，而不是看起来什么都没发生。只动绘制：句子和按钮从第一帧
  起就在原位、能点、能读（`alwaysIncludeSemantics`）。少动时不构建任何动画。
- **读屏**：整体仍是 live region。
- **说明（`detail`）**：需要多说一句「这里以后会出现什么」时，写在句子下面，
  `metaLabel`、`onSurfaceVariant`，隔 `small`，同一个宽度、和句子一起进场。阅读历史
  和离线文库原来各自在状态下面叠一行 `bodySmall`，阅读历史还画了一个 64pt 的图标。
- **整页失败也走它**：阅读页打不开、我的收藏、评论区整段加载失败，原来各自是一行正文
  字 + 一个裸 `TextButton`，现在都是同一句衬线话和描边按钮。

**列表翻到一半停下：`NoWaveListNote`**。下一页失败（首页、分类、标签、作者文章、作者
目录、评论）和「热门只能翻这么深」原来是七份手写的 `Column`：有的正文字、有的 meta、
有的 `bodySmall`，有的隔 8、有的不隔；首页的失败页脚甚至只有一个「重试」，不说为什么。
现在都是：

- 一行 `metaLabel`、`onSurfaceVariant`、居中，最宽 `statusMeasure`——和它替换掉的
  「正在加载更多」是同一个音量，列表底部不会从耳语突然变成标题。
- 下面隔 `xs` 一个 `NoWaveButton.quiet`：页脚不是这一页的主要行动，所以不加描边也不
  填色，但点击区仍是 48pt。
- 后台翻页失败是读者没看见发生的事，`live: true` 让读屏念出来；首页已经弹过提示条，
  深度上限是一直在那里的说明，这两处不重复朗读。
- 分类与标签列表翻完时也印 `NoWaveEndMark`（`feedNoMore`），和首页一样，最后一张卡片
  读起来是「最后」。

### 文末与提示条

- **`NoWaveSectionHead`**：文章下方的分节头（相关阅读、评论）。整栏一道 2pt 墨色线，
  标题 `sectionTitle`（18）上下各留 `medium`（16），所以上面的墨线和下面第一行的发丝线
  到标题的距离相等；可选的数字（「已加载 3 条」）用 `meta` 次要色、右对齐、和标题同一
  基线，不再紧贴在标题后面。列表行用发丝线，分节头用墨线，层级靠线的轻重区分。
  评论区不画线，见下面「评论：一条文字栏、四档字」。发送按钮是输入线末端一个 48pt 的
  方形描边按钮，不再是整块主色按钮。

- **`NoWaveEndMark`**：手机上正文直接接「相关阅读」和评论，读者分不清最后一段是结束
  还是停顿。杂志的做法是在最后一行后面印一枚实心小方块。这里把它做成一个分节符：
  两段与 `Divider` 同色同粗的发丝线，中间一枚 `endMark`（8）见方的**墨色**方块——印刷
  里的终止符本来就是黑的，结构性记号一律用墨色。下面一行 `metaLabel` 居中：
  `articleEnd`（全文完 / The end）。文章页不再接署名——作者在文章顶部已经介绍过，
  文末再写一遍是重复（组件仍保留可选的 `byline`）。线和方块不读，那一行
  照常朗读，读屏用户和看屏幕的人同样知道文章在哪里结束。
  首页 feed 与搜索结果翻到底时也印这一枚（`feedNoMore` / `feedCachedNoMore` /
  `searchNoMore` / `searchLimitReached` 作为那一行），最后一张卡片读起来是「最后」，
  而不是「还在加载」。
- **提示条（`showSnackBar`）**：仍是反色的一张纸条（纸上墨、墨上纸），方角无阴影。
  反色本身就说明「这是关于你刚才那个操作」，所以 `NoWaveSnackBarContent` 只有那句话；
  原来起始边那道橙线和小标题前的短线一样，标在文字前面只会拖慢阅读，已去掉。动作按钮
  仍是 Material 的 `SnackBarAction`。全应用 75 处调用都走 `showSnackBar`，所以一次改完。

### 评论：一条文字栏、四档字

评论曾经把名字和日期挤在头像旁的一行里，正文 16 号和 15 号的粗体名字几乎一样大，
日期和「回复」又是同一种灰——整块读起来没有层次。现在 `CommentTile`：

- **头部两行**：头像（话题首条 36、回复 28）旁边是上下两行——粗体名字在上，
  `caption`（12）的浅色日期在下（编辑过的接「· 已编辑」）。头像对着这两行的整体居中，
  不再只对齐其中一行。
- **一条文字栏**：头像和文字之间固定空 12（`small + xs`），每一层都一样；名字、日期、
  正文、「回复 / 编辑 / 删除」都从这条栏起排（话题首条是 `CommentTile.rootTextColumn`，48），
  回复的头像挂在父评论的文字栏上。深于两层不再缩进。「加载更多评论」也从这条栏起排、
  墨色，读起来是列表的延续；空态和「无法翻页」说明贴左，不再单独居中；未登录时的
  「登录后参与评论」卡片里文字和按钮也贴左。
- **四档字**，先靠字号和字重、再靠颜色：名字 15 粗体墨色（唯一的粗体墨色）→ 正文
  `comment` 16 常规（回复 `label` 15）→ 动作 13 半粗次要色 → 日期 12 常规次要色。
- **分组靠留白**：话题之间多留 `medium`，回复紧跟父评论，一眼一组对话。

### 触感：按下、进场、盖章

这三件小事让页面「回应手指」，而不只是换一帧：

- **按下（`NoWavePressable`）**：Material 水波只说「收到了」，不说按的是什么。文章
  卡片和网格项按下时整体下沉到 `pressScale`（`fast` + `curve`），松手回弹；同时卡片
  行尾的 `NoWavePressArrow` 沿阅读方向迈出 `arrowNudge`——「这一行通往某处」。悬停
  和键盘聚焦也会让箭头迈步，所以不用触屏的人得到同样的回答。仍然是 `InkWell`，焦点、
  悬停洗色（`focusAlpha` / `hoverAlpha`）与读屏语义都不变。
  个人中心与「关于」里的 `NoWaveActionRow` 也用它，但传 `sink: false`：整宽、顶上压着一道
  线的行一缩放，线就会从两边缩进去；所以行只用箭头迈步和洗色回答。
- **进场（`NoWaveEntrance`）**：首页 feed 第一次出现时，前 `entranceCount` 条依次
  淡入并上浮 `entranceRise`，间隔 `stagger`——像一页刚从印刷机上下来，而不是一帧里
  全部出现。只动绘制：布局、点击与语义从第一帧起就是最终状态（`Opacity` 设
  `alwaysIncludeSemantics`），进场中也能点、能读。同一位置只进场一次，所以下拉刷新、
  翻页、滚出再滚回都不会重播；换 feed 时 `generation` 变化才重新进场。等待用曲线前段
  的 `Interval` 表达，不开定时器，条目提前销毁也不会留下悬空回调。
  同一套进场也接在标签、分类文章列表与搜索结果上：标签/分类页每页一个 scope；搜索每次
  都会经过加载态，所以每次结果都是新的 scope、各进场一次。
- **阅读历史**：页面像一份报告的开头，而不是一张灰色圆角卡片里的仪表盘——
  `NoWaveEyebrow` 小标题，三个数字用展示字体的等宽数字（`figure`，40），说明是浅色
  `metaLabel`；活动条是墨色方柱，站在一道发丝线基线上，没读的那天是一截发丝线颜色的
  短柱，今天的星期写成墨色。下面每条记录照 feed 的行来排：上沿一道线，阅读日期、衬线
  标题（20）、作者各一行，行尾一个移除按钮，按下的回应与文章卡片相同，首屏逐条进场。
  去掉了缩略图——阅读历史是读过什么的索引，feed 的行本来就只有字。左滑露出的是提示条
  那样的反色纸条和一个「删除」，而不是红底加垃圾桶：从私人列表里划掉一行不是警报。
- **长出来（阅读统计活动条）**：阅读历史顶部的 7 天活动条第一次出现时，从基线由旧到新
  依次「长」出来，间隔半个 `stagger`、每根 `slow`——一周是从左往右读的，就从左往右
  画。只动绘制（以底边为锚的纵向缩放），柱高从第一帧起就是最终值；删除一条记录后，
  受影响的那天在 `normal` 内滑到新高度，而不是跳变。
- **盖章（`NoWaveStampSwitcher`）**：阅读页的收藏图标切换时，新状态从 `stampScale`
  落下归位，旧状态淡出——空心换实心太容易被忽略，而收藏是一次小小的承诺。时长只有
  `normal`，连点两下依然跟手。
- 这几种在「减少动效」下都不构建动画：不缩放、不上浮、不盖章、柱子直接落位，箭头不动；水波与焦点
  洗色照常显示状态。

### showNoWaveConfirmDialog

- 破坏性动作必须走它；`destructive: false` 只用于「保存草稿」这类非破坏确认。
- 取消路径永远可达：点遮罩、返回手势、Esc 都返回 `false`；**没有选择不等于同
  意**，调用方拿到的一定是 `true`/`false`。
- 文案由调用方从 ARB 取；组件不内置任何界面文案。
- 目前接入它的是：删除评论、结束单个/其他会话、清空阅读历史；草稿恢复与诊断信息
  两个对话框有各自的多个出口，保留自有结构，但按钮用 `NoWaveButton`。

## 四、无障碍契约（组件层已锁）

1. 所有可点组件 ≥ 48×48（`NoWaveSizes.tapTarget`）。
2. 文字与底色 ≥ 4.5:1（见 `test/unit/core/localization_test.dart` 的对比度断言）。
3. 2× 字体、320dp屏下不溢出：不设固定高度去裁字，长标签 `maxLines` + 省略。
4. 装饰性图标一律 `ExcludeSemantics`，可读文案只出现一次。
5. 位图/封面/头像都有可读替代文案；状态变化用 live region 而不是颜色。
6. 破坏性按钮用错误色 + 文案双通道表达，不靠颜色单独暗示。

## 五、加新组件或新页面的清单

1. 先在 `design_tokens.dart` 找现成 token；确实缺才加，并写清「用在哪」。
2. 组件放 `lib/core/design/components/`，文件名 `no_wave_*.dart`，类名 `NoWave*`。
3. 组件内不写界面文案；文案由调用方传（ARB 键）。
4. 断言式约束写进构造函数（例如「有按钮就必须有文案」），别留给调用方自觉。
5. 测试放在 `test/widget/design_components_test.dart`：变体、禁用/忙碌、2× 字体
   在浅色与深色下各跑一遍，并断言 `takeException()` 为空。
6. 本文的表格同步更新——文档落后于组件，比没有文档更糟。

## 六、守卫：`test/unit/design/no_magic_numbers_test.dart`

口径变成门禁：`lib/` 里 `SizedBox(width|height: N)`、`EdgeInsets.*`、
`Wrap/Flex` 的 `spacing`、写死的 `BorderSide(width:)` 都算「间距字面量」，`0` 不
算。三条断言：

1. `lib/core/design/`、`lib/core/common/widgets/`、`lib/core/theme/` 必须为 0；
2. 其他文件不得**超过**登记在测试里的预算（新增文件默认 0）；
3. 总量只会减少，测试里有一个只许下调的 `ceiling`。

真的需要一个非 token 数值时，在那一行加 `// design-token-ok: <理由>`，它会被跳过
并留下解释。迁移完成、计数下降后把预算调低（或删掉那一行）——**不要**只把数字
往上调。

## 七、已知缺口

- **暗色模式没有独立插画或位图**，只有色板翻转。
- **没有 golden 测试。** 一致性的回归靠 `design_tokens_test.dart` 的约束断言与页面
  级 widget 测试，而不是像素比对。
- **`lib/` 里已没有 `FilledButton` / `OutlinedButton` / `ElevatedButton`**：所有
  主行动、次要行动、破坏性行动与重试/空态行动都走 `NoWaveButton`；主题仍钉着这三类
  Material 按钮，避免以后有人顺手写回来时又变成胶囊形。剩下直接使用 Material 的是
  纯文字动作（`TextButton`）与图标动作（`IconButton`），它们由主题保证 48pt 触控
  目标与方角。
- **间距预算已归零**：`no_magic_numbers_test.dart` 的 `ceiling` 358 → 215 → 142 → 75
  → **0**，`budget` 表现在是空的。路径是：先改与 token 同值但没写 token 的（画面不
  变），再把 12 逐处判成 8 或 16（唯一会动像素的一步），最后把「尺寸」那批要么变成
  `NoWaveSizes.*`、要么在行尾写明理由。

  现在 `lib/` 里没有裸间距字面量，剩下的都是行尾 `design-token-ok` 的例外，共 13 行：

  | 理由 | 例子 |
  | --- | --- |
  | 贴基线的光学补正 | 消息气泡下的 `SizedBox(height: 2)` |
  | 角标/芯片贴合自己的字形 | 未读角标 `horizontal: 7`、行内 code chip `5` |
  | 固定在某一列上的宽度 | 有序列表标记列 `26`、回复缩进随 48pt 头像列 |
  | 失败占位不塌陷 | 正文图片加载失败的 `height: 40` |

  **规矩**：标记必须写在带数字的那一行，扫描会把那一行整行丢掉；写在多行
  `EdgeInsets` 上方不起作用。加标记的唯一理由是「这不是尺度上的一档」，不是为了让
  数字过关。

- **登录/注册页不再有自己的尺度**：它们曾用一组 `60 / 40 / 30` 把居中的表单
  「撑」在屏幕中间。现在四个账号页（登录、注册、找回密码、重设密码）都放在同一个
  `AuthFrame` 上，和其他页面一样从顶部排起，只用 `NoWaveSpacing` 的档位，那组局部
  常量随之删除。

## 移动端视觉方向（原 README，#298）

客户端正逐步向 [no-wave 移动网页设计](https://github.com/BrainEno/no-wave/blob/157aa6f5799d33891910ceb606cbaa8ec90f4e40/apps/web/docs/UI_DESIGN_SYSTEM.md) 靠拢（原生落地方式即本文）：纸色与墨色、橙红强调、衬线标题、细线分隔和留白，并保留原生四标签导航及各自的页面栈。首页、搜索、阅读、作者主页和个人中心采用一致的编辑式布局；收藏和个人作品继续使用可操作的网格。这是逐步迭代，并非所有页面均已统一或与网页逐像素相同；发布身份已统一为 `com.nodeman24.nowave`；启动图标与网页 favicon 用同一个「停下来的浪」记号（见上文「启动图标」）。

- 颜色与文字样式集中在 `lib/core/theme/`；品牌、标题、作品行、封面、方形头像与操作行为可复用展示组件。作品行和操作行通过回调交给页面处理导航或动作，不依赖路由或业务状态；评论区的作者点击也由阅读页接管，保持所在标签的导航栈。
- 头像与作品封面优先展示原有 HTTP(S) 图片 URL，提供本地化图片语义。缺失、无效或加载失败时，头像使用中性人像图标；封面使用随包附带的原创抽象兜底图（由 AI 生成，不代表文章内容）。
- Latin 字体使用 [Instrument Serif](https://github.com/google/fonts/tree/main/ofl/instrumentserif) 和 [Inter Tight](https://github.com/google/fonts/tree/main/ofl/intertight)，各自的 SIL Open Font License 随 `assets/fonts/` 打包；中文使用系统衬线/无衬线字体回退。实际字形与行高会因设备而异。
- 继续支持浅色、深色、系统主题、系统字体缩放与中英文界面；系统要求减少动画时关闭标签切换淡入。视觉组件不翻译作品、作者或评论；内容请求的语言随界面语言推导（见 [无障碍](accessibility.md)）。
