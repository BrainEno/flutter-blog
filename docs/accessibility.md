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

`test/widget/a11y_text_scale_test.dart` 在中文与英文下各跑一遍 2.0 字体缩放，
并断言 `takeException()` 为空：溢出条（`BOTTOM OVERFLOWED BY …`）在 widget
测试里就是一次异常，所以这条断言等价于「大字体下不破版」。

## 三、只能靠真机/模拟器确认的部分

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

## 四、已知边界

- 文章、评论、作者资料等内容不翻译，也不做机器翻译；界面语言切换不影响内容
  请求的语言（仍是 `zh-CN`）。
- 只有中文与英文两套资源；其他系统语言回退简体中文（`resolveAppLocale`）。
- 读屏对长文章是逐段播报，朗读功能（`docs/read-aloud.md`）是独立功能，不替代
  系统读屏。
