# 本地化与无障碍（#24）

本文记录「界面文案统一」和「无障碍」这两条长期项的实际边界：哪些行为已经被
自动化测试锁住，哪些仍然只能靠真机人工验收。文案本身在
`lib/l10n/app_zh.arb` / `app_en.arb` 维护，流程见 README 的「本地化与无障碍」。

## 一、文案规则

1. 面向用户的文案只来自 ARB。新增一句界面文案 = 两个 ARB 都加键 + `flutter
   pub get` 重新生成 + 通过 `context.l10n` 读取。
2. `test/unit/core/ui_copy_literals_test.dart` 扫描整个 `lib/`：凡是把中文字面量
   直接交给 `Text` / `TextSpan` / `tooltip` / `hintText` / `labelText` /
   `semanticLabel` / `errorText` / `label` / `title` 的地方都会让测试失败。
   它守的是「文案能不能跟随系统语言」，不是「代码里有没有中文」。
3. 不在扫描范围内、也不应该进 ARB 的三类字符串：
   - **数据层兜底**：`Failure('…')` 的中文 `message` 只是显示安全的兜底，界面
     真正展示的是 `core/l10n/failure_l10n.dart` 按稳定 `code` 选出的本地化文案。
   - **已存储的分类值**：`editorTagOptions` 里的 `诗歌 / 小说 / 原创 / 其他` 是
     内容值，显示时经 `core/l10n/tag_l10n.dart` 翻译，值本身不能改。
   - **诊断与日志**：`AppLogger` 和诊断头面向维护者，跟随界面语言没有意义。
4. 启动失败页（`lib/boot/startup_failure_app.dart`）是唯一允许保留自有
   文案的文件，并在守卫测试里登记了原因：它出现的前提正是 locale、偏好存储和
   ARB delegate 都可能还没跑起来，所以中英双语同时显示。

### 中文排版约定

- 中文句子里的标点用全角：`：`、`，`、`「」`；不要在中文标签里写 `: ` 再加空格。
- 品牌与技术名词保持稳定写法：`No Wave`、`GitHub`、`Markdown`、`iOS`、`API`。
- 标签类文案（邮箱、GitHub、应用版本）不再自带尾随空格：它们各自是独立的
  `Text`，空格由布局提供。
- 作者/读者昵称为空时用 `anonymousAuthor` / `anonymousReader`，不要留白或写死
  `Unknown`。

## 二、自动化覆盖（`flutter test`）

| 关注点 | 位置 |
| --- | --- |
| 文案不外泄中文 | `test/unit/core/ui_copy_literals_test.dart` |
| 双语按键与错误映射 | `test/unit/core/localization_test.dart`、`test/widget/localized_auth_test.dart` |
| 双语列表 / 搜索 / 日期 | `test/widget/localized_feed_search_test.dart` |
| 评论区的双语与异常态 | `test/widget/comments_section_test.dart` |
| 日期、数字、阅读时长 | `test/unit/core/reading_time_and_date_test.dart` |
| 图片、头像、封面语义 | `test/widget/no_wave_design_test.dart`、`test/widget/no_wave_avatar_test.dart` |
| 内联代码链接的 link 语义 | `test/widget/markdown_body_test.dart` |
| 2× 字体、320 dp 窄屏 | `test/widget/a11y_text_scale_test.dart`、`test/widget/localized_feed_search_test.dart` |
| 点击区域 ≥48 dp | `test/widget/article_tag_label_test.dart` |
| 系统字体缩放不被夹取 | `test/widget/a11y_text_scale_test.dart`（源码扫描） |
| 加载态没有转圈 | `test/unit/design/no_spinner_test.dart`、`test/widget/no_wave_loading_test.dart` |
| 减少动效 | `test/widget/no_wave_fade_transition_test.dart`、`test/unit/design/no_magic_durations_test.dart`、`test/widget/no_wave_splash_test.dart` |
| 无封面文章的可区分与稳定性 | `test/unit/design/cover_plate_test.dart`、`test/unit/core/stable_hash_test.dart`、`test/widget/no_wave_design_test.dart` |
| 文档不指向不存在的组件或测试 | `test/unit/core/docs_contract_test.dart` |

`test/widget/a11y_text_scale_test.dart` 在中文与英文下各跑一遍 2.0 字体缩放，
并断言 `takeException()` 为空：溢出条（`BOTTOM OVERFLOWED BY …`）在 widget
测试里就是一次异常，所以这条断言等价于「大字体下不破版」。

## 三、动效、加载态与图片

这三件事在近两个阶段里从「各处自定」收成了规则，所以在这里写清楚它们的无障碍含义。

### 减少动效

`NoWaveMotionPolicy.reducesMotion(context)` 是唯一的判断口，它把两个开关当成同一件事：

1. 系统的「减少动态效果 / 移除动画」；
2. 读屏（TalkBack / VoiceOver）。读屏是一次读一个元素的，页面在它下面淡入、滑动，
   会把读者刚定位到的位置带走。

需要少动时，`NoWaveMotionPolicy.resolve` 把时长变成零；但真正的做法是**根本不构建**
那个转场：`NoWaveFadeTransition` 少动时直接返回 child，开屏走静止首帧，朗读跟随滚动
改成一次 `jumpTo`——不是「把 200ms 压成 20ms」。

`test/unit/design/no_magic_durations_test.dart` 守另一半：`lib/` 里的 `Duration` 要么
来自 `NoWaveMotion`，要么是「在等」（请求超时、重试退避、自动保存、输入防抖）并登记了
理由。页面不许自己发明一个动效时长。

### 加载态

页面级与区块级的加载不再是转圈，而是一句话（`NoWaveLoadingLabel`）或一个形状
（`NoWaveSkeleton*`）：

- 播报**只发生一次**：`NoWaveLoadingLabel` 根部是一个 `liveRegion` 的 `Semantics`，
  短横线与文案都在 `ExcludeSemantics` 里，读屏读到的是一句可翻译的话而不是「一条线」，
  也不会因为重建重复播报。
- 骨架屏是纯装饰，并且**不动**：没有 shimmer、没有扫光，开着「减少动效」的用户与截图
  里看到的一致。列表页（通知、私信、阅读历史）与首页 feed（`BlogFeedSkeleton`）用的是
  这个形状，语义仍是一句 `loading` / `loadingArticles`，播报次数不变。
- 控件内部的忙碌态仍保留系统小转圈（`NoWaveButton` 加载态、回收站行内恢复、私信发送
  图标位）——那些槽位放不下一句文案，三个位置在 `test/unit/design/no_spinner_test.dart`
  里带理由登记。

### 封面与图片

- 没有封面的文章按身份（slug）稳定落在四张编辑式版之一（`NoWaveCoverPlate`）：同一篇
  文章在任何设备、任何版本上都是同一张图，读者可以靠它定位。
- 封面对读屏是装饰：`excludeFromSemantics`，语义只有一句「《标题》的封面」；标题就在
  旁边，图片内容不进播报。
- 占位、失败与最终帧是同一张版——请求失败时图片不会变成另一张，对读屏与对眼睛都是
  同一件事。

## 四、只能靠真机/模拟器确认的部分

自动化测试跑的是 Flutter 自己的语义树，不能替代读屏软件。以下项目仍需人工检查，
在这之前不要在文档或 issue 里声称「无障碍已验收」：

1. **TalkBack（Android）**：打开「随选朗读/语音反馈」后打开首页 → 文章 → 评论，
   确认封面播报「《标题》的封面」、头像播报「某某的头像」、正文里的链接被读成
   「链接」并且双击能打开、禁用状态的按钮不被读成可点。
2. **VoiceOver（iOS）**：同上，另外确认转子（rotor）里的「链接」「标题」条目能
   定位到文章标题和内联链接。
3. **系统字体放大**：iOS 设置 → 辅助功能 → 更大字体（含「更大的辅助功能字体」），
   Android 设置 → 显示 → 字体大小与显示大小都调到最大，逐页检查阅读页、评论、
   编辑器和「我的」。
4. **键盘**：Windows/macOS 构建用 Tab 走完登录、列表、文章、评论；焦点环可见，
   顺序与视觉顺序一致，Esc 能关闭对话框。
5. **对比度**：亮/暗两种主题下检查次级文字（日期、阅读时长）与禁用态按钮。
6. **减少动效**：打开系统「移除动画 / 减少动态效果」，再走一遍开屏、四个标签切换、
   朗读跟随滚动，确认没有淡入与滑动、内容仍然都在；打开读屏后同样检查一次（读屏在本
   项目里被当成同一个开关）。
7. **加载态与读屏**：慢网络下打开列表页与阅读页，确认只播报一次「载入中 · LOADING」
   （不是反复播报、也不是播报「一条线」），且屏幕上没有转圈动画；骨架屏静止不动。

## 五、已知边界

- 文章、评论、作者资料等内容不翻译，也不做机器翻译；内容请求语言由
  `content_language.dart` 按界面语言决定：中文请求 `zh-CN`，英文请求 `en`，
  跟随系统时与界面语言解析保持一致。应用没有 `zh-TW` 界面，繁体译文只会在
  “我的文章 → 全部语言版本”等明确入口中出现。
- 只有中文与英文两套资源；其他系统语言回退简体中文（`resolveAppLocale`）。
- 读屏对长文章是逐段播报，朗读功能（`docs/read-aloud.md`）是独立功能，不替代
  系统读屏。
