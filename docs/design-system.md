# 界面设计系统（tokens 与组件）

本页是客户端「长什么样」的唯一入口：色板、间距、圆角、线宽、动效、断点，以及
共用组件的 API 和使用规则。目标是让新增页面**不需要**重新决定这些数字——需要时
改这里，而不是改页面。

> 与网页的关系：色板与排版沿用 no-wave 网页的纸色/墨色/橙红与衬线标题；本页描述
> 的是**原生**落地方式（Material 语义、点击区域、读屏），不追求与网页逐像素相同。
> 无障碍的验收边界另见[无障碍说明](accessibility.md)。

## 一、原则

1. **纸与墨，两色打底。** 页面底色只有纸（浅色）与墨（深色）两种，强调色橙红只
   用于大色块与焦点，小字号强调文字用牛血红（`AppPalette.oxblood`），因为橙红在
   纸色上不到 4.5:1。
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
| `medium` | 16 | 页面左右边距、两组之间的距离（= `page`） |
| `large` | 24 | 标题块与它引入的内容之间 |
| `section` | 32 | 一页之中两个 section 之间 |
| `page` | 16 | 页面 gutter，语义化别名 |

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
| `NoWaveRadius.badge` | 2 | 封面角标（系统里唯一的圆角） |
| `NoWaveStroke.hairline` | 1 | 分隔线、输入框边框、角标描边 |
| `NoWaveStroke.focus` | 2 | 焦点环、聚焦输入框边框 |
| `NoWaveIconSize.inline` | 18 | 与元信息文字同行 |
| `NoWaveIconSize.row` | 20 | 行尾箭头、更多 |
| `NoWaveIconSize.action` | 22 | 行动行前导图标、独立图标按钮 |
| `NoWaveIconSize.display` | 48 | 空态/对话框里的装饰字形 |
| `NoWaveSizes.tapTarget` | 48 | 最小点击区域 |
| `NoWaveSizes.primaryAction` | 52 | 整宽主按钮高度 |
| `NoWaveSizes.row` | 64 | 可点列表行最小高度 |
| `NoWaveSizes.coverAspect` | 4/3 | 所有文章封面 |
| `NoWaveSizes.maxReadingWidth` | 720 | 平板上的正文最大宽度 |
| `NoWaveSizes.coverEditorBox` | 250 | 编辑器里固定的封面框（三种状态同框，表单不跳） |
| `NoWaveSizes.emptyStateOffset` | 48 | 空态/加载态在列表里从多高开始 |
| `NoWaveSizes.listThumbnail` | 56 | 列表行前导缩略图（阅读历史） |
| `NoWaveSizes.listThumbnailSmall` | 48 | 行内还要放操作时的小缩略图（回收站、评论头像框） |
| `NoWaveSizes.splashColumns` | 6 | 冷启动幕布切成的竖列数 |
| `NoWaveSizes.splashCounterMax` | 220 | 幕布计数器字号上限；实际取 `30vw` 与它的较小值（`splashCounterViewport`） |
| `NoWaveSizes.splashWordmark` | 40 | 幕布与启动失败页的字标 |
| `NoWaveSizes.masthead` | 22 | 应用栏里的紧凑字标 |
| `NoWaveSizes.splashProgress` | 3 | 幕布右下装饰段的厚度（装饰，不是进度条） |
| `NoWaveSizes.splashProgressLength` | 72 | 该装饰段的长度 |
| `NoWaveSizes.loadingRule` | 40 | 加载标签上方那道短横线 |
| `NoWaveSizes.skeletonLine` | 12 | 骨架屏一行的高度（≈正文 x-height） |

### 线与遮罩的不透明度 `NoWaveOpacity`

| token | alpha | 说明 |
| --- | --- | --- |
| `dividerAlpha` | 100（≈39%） | 分隔线、细线 |
| `focusAlpha` | 55（≈22%） | 焦点/悬停的强调色洗色 |
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
| `counter` / `counterFinish` | 1800ms / 350ms | 幕布计数爬到 `088` 与最后一跳 `088 → 100` |
| `curtain` / `stagger` | 900ms / 80ms | 单列上撕与相邻列的错开 |
| `minimumSplash` / `splashBail` | 1400ms / 4500ms | 最短幕布时长与兜底揭幕 |

幕布那几行只在冷启动用，语义与时序见 [冷启动与墨色幕布](startup.md)；`enter` / `page`
留给后续阶段的动效系统，目前只有 token、没有使用者。

### 断点 `NoWaveBreakpoints`

`columnsFor(width)`：< 600 → 2 列，600–899 → 3 列，≥ 900 → 4 列。列表、骨架屏和
未来的平板侧栏都读这一个函数，避免各算一套。

### 主题映射

`lib/core/theme/theme.dart` 把上表落到 Material 上，因此即使某个页面直接用
`FilledButton`、`OutlinedButton`、`TextField`、`AlertDialog`、`Chip`，形状、线宽和
最小高度也一致：

- 填充/描边/文字/图标按钮：方角，最小高度 ≥ 48，主按钮 52；
- 输入框：`medium` 内边距，1pt 边框，聚焦 2pt；
- 对话框：底色同页面，方角，标题 20/w700；
- 分隔线：`dividerAlpha` + 1pt；`Chip`：方角 1pt 描边；
- 卡片：0 阴影、0 色调、方角、`surface` 底色；列表项：`NoWaveSizes.row` 最小
  高度、`medium` 内边距、方角；
- 底部面板：底色同页面、0 阴影、方角；SnackBar：浅色下墨底纸字、深色下纸底墨字，
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
| `NoWaveStatus` | `common/widgets/no_wave_status.dart` | 空态/错误态（带可选行动） |
| `NoWaveSectionHeading` | `common/widgets/no_wave_section_heading.dart` | 编辑式大标题（可换行、带 eyebrow） |
| `NoWaveActionRow` | `common/widgets/no_wave_action_row.dart` | 个人中心式的可点行动行 |
| `NoWaveMasthead` | `common/widgets/no_wave_masthead.dart` | 双字体字标 |
| `NoWaveAvatar` | `common/widgets/no_wave_avatar.dart` | 方形头像，失败回退中性图 |
| `NoWaveLoadingLabel` | `design/components/no_wave_loading_label.dart` | 加载态：一道短横线 + 一句文案，没有转圈 |
| `NoWaveSkeleton` / `...List` / `...Line` / `...Block` | `design/components/no_wave_skeleton.dart` | 内容形状的占位（列表、行、块） |

### 加载态：一句文案或一个形状

`lib/` 里已经没有页面级或区块级的转圈指示器，`Loader` 也随之删除。两种替代品：

- **`NoWaveLoadingLabel`** —— 屏幕级、区块级，以及列表页脚（`compact: true` 去掉短
  横线）。它同时是读屏播报（一个 `liveRegion`、一句话），所以那道横线在
  `ExcludeSemantics` 里。
- **`NoWaveSkeletonList`** —— 列表型页面（通知、私信、阅读历史）。行高与缩略图尺寸
  直接借 `NoWaveSizes.row` / `listThumbnail`，数据落地时页面不跳。**不动**：没有
  shimmer、没有渐变扫光——动效是阶段三的事，加载态不该先花掉用户的注意力，静态块在
  截图里也读得懂。

**边界**：控件自己的忙碌态仍由控件表达 —— `NoWaveButton(isLoading: true)` 保持标签
在布局里不变高、保持不可点；回收站行内的"恢复中"与私信发送图标位保留系统小转圈，
因为那是控件槽位里的图标，一句文案放不进去。

`_row` 里那三道横线的宽度比例写在组件内部（`_lineWidths`），不是全局尺度：它们是
"一段话"的形状，不是间距。

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
  Flutter 的语义里没有 busy 标志，所以忙碌态靠禁用播报加可见的转圈表达；不要另外
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

- **首页 feed 用文案而不是骨架。** `BlogCard` 是封面卡而不是缩略图行，骨架的行形态
  套不上；等阶段四把编辑式图像层（默认封面 + 稳定 hash）定下来，再给 feed 一个卡片
  骨架。列表型页面（通知、私信、阅读历史）已经用 `NoWaveSkeletonList`。
- **控件内部的忙碌指示仍是系统小转圈**（`NoWaveButton` 的加载态、回收站行内恢复、
  私信发送图标位）。它们的尺寸由控件自己的槽位决定，放不下一句文案；页面级与区块级
  已经全部换成 `NoWaveLoadingLabel` / 骨架。
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

  现在 `lib/` 里没有裸间距字面量，剩下的都是行尾 `design-token-ok` 的例外，共 14 行：

  | 理由 | 例子 |
  | --- | --- |
  | 贴基线的光学补正 | 消息气泡下的 `SizedBox(height: 2)` |
  | 角标/芯片贴合自己的字形 | 未读角标 `horizontal: 7`、行内 code chip `5` |
  | 固定在某一列上的宽度 | 卡片序号列 `36`、有序列表标记列 `26`、回复缩进随 48pt 头像列 |
  | 失败占位不塌陷 | 正文图片加载失败的 `height: 40` |

  **规矩**：标记必须写在带数字的那一行，扫描会把那一行整行丢掉；写在多行
  `EdgeInsets` 上方不起作用。加标记的唯一理由是「这不是尺度上的一档」，不是为了让
  数字过关。

- **登录/注册页的比例不进军全局尺度**：这两屏的 `60 / 40 / 30` 放在
  `lib/features/auth/presentation/auth_rhythm.dart` 的 `AuthRhythm` 里。它们是一屏
  的构图（标题—字段堆—按钮），不是别处可复用的间距；写进 `NoWaveSpacing` 会让每个
  页面都以为自己也该喘这么宽。字段之间仍用 `medium`、链接行之间仍用 `small`。
