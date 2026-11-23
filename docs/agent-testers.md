# 人设巡检与 AI 真机测试员（mobile-agent-testers）

> 状态：active ｜ 最后核对：2026-11-19 @ cf4f250

[pierridotite/mobile-agent-testers](https://github.com/pierridotite/mobile-agent-testers)
是一套用 GitHub Actions 起 Android 模拟器 / iOS 模拟器、每台手机交给一个带「人设」的
Claude Code 代理去用的测试方式：代理截图、读控件树、点按和输入，最后写一份
`report.md` 和 `findings.json`。每个人设固定了机型、语言、系统字号和亮暗主题
（例如 grace：Pixel 7、2× 字号；sven：iPhone SE、最大辅助字号、深色）。

本仓库用它的方法做了两件事：

1. **人设巡检**（每次 push 都跑）：把代理在每个界面上做的机械检查搬进
   `flutter test`，可重复、零成本、不需要模拟器。
2. **真机代理跑一轮**（按需，手动触发）：需要 Claude 的凭据和一个测试后端，
   见第三节。

## 一、人设巡检（`test/widget/persona_sweep_test.dart`）

### 覆盖范围

- **人设**：取自该项目 `personas.json` 的 6 台，语言收窄到本应用发布的中英两种：

  | 人设 | 视口 | 字号 | 主题 | 语言 | 平台 |
  | --- | --- | --- | --- | --- | --- |
  | grace | 412×915 | 2× | 亮 | en | Android |
  | anna | 360×640 | 1.3× | 亮 | en | Android |
  | malik | 412×915 | 1× | 暗 | en | Android |
  | lucia | 1280×800 | 1× | 亮 | en | Android（平板） |
  | wei | 390×844 | 21/17 | 亮 | zh | iOS |
  | sven | 375×667 | 2× | 暗 | zh | iOS |

- **界面**：用真实路由打开，和代理第一次进应用的路线一致——首页、文章（访客 / 已登录）、
  登录、注册、找回密码、关于、个人中心、收藏、我的文章、搜索、作者页；再加上需要先布置或
  操作的状态：首页离线、评论加载失败、字号面板打开、朗读进行中、登录被拒。
- 每个界面在**顶部**审一次，能滚动的再**滚到底**审一次（像代理离开前往下划一遍）。

### 两遍：测试字体与真实字体

| | `persona_sweep_test.dart`（测试字体） | `persona_sweep_fonts_test.dart`（应用自带字体） |
| --- | --- | --- |
| 布局溢出 / 异常 | ✓（每个字都按 1em 宽，最宽情况） | ✓ |
| 点击区域 ≥ 48×48 | ✓ | — |
| 控件有可读名称 | ✓ | — |
| WCAG 文字对比度 | ✓ | — |
| 英文界面漏翻中文 | ✓ | — |
| 单行文字被截断 | — | ✓（真实字宽） |

两遍都由 `test/widget/persona_sweep.dart` 的 `definePersonaSweep` 定义。分两遍是
因为：测试字体（Ahem）把每个字画成实心方块，判截断会误报（「Search」比真机宽
得多）；而载入 Inter Tight / Instrument Serif 后，抗锯齿的字形边缘会让对比度检查
拿字形自身的两种灰去比。各取所长。

截断只查**单行**文字：标题、摘要按设计限制在两三行内，不算问题；标签、按钮、名字、
日期丢了结尾才算。滚到底之后被应用栏挡住一半的控件，如果在顶部已通过点击区域检查，
不再重复报——那是滚动遮挡，不是控件太小（代理的 `a11y.py` 同样跳过被滚动边缘切掉的元素）。

### 报告模式

失败时会列出该界面全部发现，读起来像一份代理报告。要一次收集所有发现而不失败：

```bash
flutter test test/widget/persona_sweep_test.dart test/widget/persona_sweep_fonts_test.dart \
  --dart-define=PERSONA_SWEEP_REPORT=true
```

末尾会打印 `===== persona sweep report (N findings) =====`，同一问题合并成一行，
后面列出出现它的人设。

### 这一轮巡检发现并修复的问题（#346）

| 发现 | 人设 | 修复 |
| --- | --- | --- |
| 评论作者名和头像是两个各自不到 48 dp 高的点击目标（18 处） | 全部 | 评论头部合并成一个最小 48 高的控件（`lib/features/blog/presentation/comments/comment_tile.dart`） |
| 注册页密码框把规则写进单行标签「Password (at least 12 characters)」，测试字体下五台人设都被截断 | grace、anna、malik、lucia、sven | 标签只写「密码」，规则改为可换行的提示（`AuthField.helperText`）；错误提示也允许换行 |
| 字号面板在 2× / 1.3× 字号下超出底部 101 / 19 px，五个档位被挤到 36.7 高，名称截成「Def…」 | grace、anna | 面板可滚动；档位名称放不下五分之一宽时改为纵向列表（字母框 + 名称，整行可点）（`lib/features/blog/presentation/viewer/reader_text_size_sheet.dart`） |

巡检**没有**覆盖的：删除评论的确认对话框。测试环境里删除按钮能点到，但
`_confirmCurrentDelete` 的账号围栏（`identityRevision`、`captureFence().userId`）
挡住了对话框，这个场景暂时去掉，由 `test/widget/comments_section_test.dart` 覆盖。

## 二、为什么不直接把代理接进 CI

- 每台手机每轮约 $0.15–0.55 的模型费用，需要 `CLAUDE_CODE_OAUTH_TOKEN` 或
  `ANTHROPIC_API_KEY`；iOS 人设要 macOS runner（私有仓库按 10 倍分钟计费）。
- 代理需要能登录的**测试后端**；它自动构建 Flutter 时不传 `--dart-define`，
  本应用没有 `API_BASE_URL` 就连不上任何后端（见 `env.example.json`）。
- 结果不确定，适合偶尔跑一轮找「人会注意到的问题」，不适合当门禁。机械检查交给上面的巡检。

## 三、真机代理跑一轮（手动）

1. 用模板建一个**自己的**测试仓库，并按提示生成结果加密密钥：

   ```bash
   gh repo create my-testers --public --template pierridotite/mobile-agent-testers --clone
   cd my-testers && ./setup.sh
   ```

   在该仓库的 Secrets 里放 `CLAUDE_CODE_OAUTH_TOKEN`（或 `ANTHROPIC_API_KEY`）、
   `ARTIFACT_PASSPHRASE`；本仓库若是私有的，再放一个只读的 `SOURCE_REPO_TOKEN`。
2. 把 `tool/agent-testers/no-wave-brief.md` 复制到该仓库（例如 `briefs/no-wave.md`）。
   它沿用模板的 `AGENT_BRIEF.md` 规则，只换目标：读文章、改字号、评论与回复、收藏、
   朗读、搜索、离线再回来；并说明只能用测试账号。
3. 因为需要后端地址，用自定义构建命令代替自动构建：

   ```bash
   gh workflow run agent-testers.yml \
     -f source_repo=BrainEno/flutter-blog \
     -f app_id=com.nodeman24.nowave \
     -f brief=briefs/no-wave.md \
     -f android_personas=grace,anna,malik \
     -f ios_personas=none \
     -f android_build='printf %s "{\"API_BASE_URL\":\"https://<测试后端>\",\"WEB_BASE_URL\":\"https://<测试站点>\"}" > env.json && flutter build apk --debug --dart-define-from-file=env.json' \
     -f apk_path=build/app/outputs/flutter-apk/app-debug.apk
   ```

4. 跑完后 `bash scripts/collect.sh <run id>` 解密下载每个人设的报告。真机代理报来的
   问题若能机械地复现，就在 `test/widget/persona_sweep.dart` 里补一个界面或检查，
   让它以后每次 push 都被拦住。
