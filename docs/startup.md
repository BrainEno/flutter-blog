# 冷启动与墨色幕布

启动这一段的规矩只有一句：**第一帧就是品牌，初始化在它后面跑。**

旧流程是「先把依赖、语言、会话都 await 完，再 `runApp`」。这段时间里用户看到的是
操作系统那张静态启动图（黑底白猴），慢的时候能停五秒；而 Flutter 一旦画出第一帧，
应该已经是墨色幕布。

## 一、顺序

启动这一段放在 `lib/boot/`，不在 `lib/core/`：`test/unit/core/layering_test.dart` 规定
`lib/core` 是底层、不得 import `lib/features/`，而启动编排必然要建 `AuthBloc`、起
`PublishQueueService`——那是组合根，只能待在顶层（和 `app.dart`、`init_dependencies.dart`
一样）。幕布本身不碰 features，但它和「谁在什么时候揭幕」是一件事，跟着一起放。

```
WidgetsFlutterBinding.ensureInitialized()
  → _installGlobalErrorHandlers()        // FlutterError.onError + PlatformDispatcher.onError
  → runApp(const NoWaveBootApp())        // 不 await 任何依赖
```

`NoWaveBootApp`（`lib/boot/no_wave_boot_app.dart`）在 `initState` 里并行启动
`runBootSequence()`，同时立刻画：

1. 全屏 ink 占位（`AppPalette.ink`），不带任何内容；
2. 幕布 `MaterialApp` + `NoWaveSplashScreen`。

boot 成功后，真正的 `NoWaveApp`（`lib/app.dart`：router、`LocaleBloc`、`ThemeBloc`、
`MaterialApp.router`）被**插在原来的 ink 占位位置上**，也就是在幕布后面构建；幕布只在
六列都撕完之后才从树上移除。所以那是揭幕，不是替换。

boot 抛异常（`initDependencies` 校验 `API_BASE_URL`、打开本地存储）时不做戏剧化处理：
直接渲染 `StartupFailureApp`，因为「你的配置坏了」这句话不能等三秒。

## 二、时序

| 阶段 | 时长 | token |
| --- | --- | --- |
| 计数 `000 → 088` | 1800ms，`easeOut` | `NoWaveMotion.counter` |
| 最短幕布时长（boot 再快也不短于） | 1400ms | `NoWaveMotion.minimumSplash` |
| `088 → 100` | 350ms | `NoWaveMotion.counterFinish` |
| 计数淡出 + 放大到 1.12 | 350ms（与上式同一段） | — |
| 单列上撕 | 900ms，`Cubic(0.76, 0, 0.24, 1)` | `NoWaveMotion.curtain` |
| 相邻列错开 | 80ms × 5，顺序 `[2,0,4,1,5,3]` | `NoWaveMotion.stagger` |
| 兜底强制揭幕 | 4500ms | `NoWaveMotion.splashBail` |

**计数器是编舞，不是进度。** 没有任何请求测量它，它自己爬到 088，只有 boot 真的结束时
才跳 100。别在文案或无障碍标签里把它说成百分比。

## 三、三条降级路径

- **系统「减少动态效果」**（`MediaQuery.disableAnimationsOf`）：不计数、不撕幕布，静止
  首帧 + boot 一完成就交棒。
- **同一进程里已经播过**（`NoWaveSplashScreen._hasPlayed`）：热重载或重建不重播开屏，
  同样走静止首帧。测试里用 `resetForTest()` 复位。
- **boot 超时**（`splashBail`）：到点无条件揭幕，剩下的加载/错误交给 app 自己的状态。

## 四、原生静态启动图

OS 那张图和 Flutter 首帧必须是同一张：墨 `#0F0D0C` + 居中的 paper `000`。

- **Android（API < 31）**：`res/values/colors.xml` 的 `launch_background` 是唯一的墨色
  定义，晴天/夜间共用（幕布不随系统亮暗翻转，才不会有白闪）。
  `res/drawable*/launch_background.xml` = 纯色 + `@drawable/splash` 居中。
  `NormalTheme` 的 `windowBackground` 也改成同一个色，否则第一帧之后那一瞬还是会露白。
- **Android 12+**：系统自己画开屏，`windowBackground` 不生效，所以
  `res/values-v31/styles.xml` 与 `values-night-v31/styles.xml` 里补
  `windowSplashScreenBackground` 与 `windowSplashScreenAnimatedIcon`。图标是带内边距的
  方形位图，圆形遮罩不会裁到数字。
- **iOS**：`LaunchScreen.storyboard` 根视图背景是墨色，`LaunchImage` 是同一张 `000`，
  `LaunchBackground` 是 1×1 的墨色像素。

### 重新生成 `000`

字体是仓库里那份 Inter Tight 可变字体，取 `wght=700` 的静态实例再渲染（不要临时改
`assets/fonts/`）：

```sh
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools
/tmp/fontenv/bin/python - <<'PY'
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
f = TTFont('assets/fonts/InterTight-Variable.ttf')
instancer.instantiateVariableFont(f, {'wght': 700}).save('/tmp/InterTight-700.ttf')
PY

# 8 倍母版：232x112dp 画布，字面 200dp 宽，字距 -0.05em（pointsize 1000 时 kerning -50）
convert -background none -fill '#F2EEE6' -font /tmp/InterTight-700.ttf \
  -pointsize 1000 -kerning -50 label:000 -trim +repage \
  -filter Lanczos -resize 1600x624 -background none -gravity center -extent 1856x896 \
  /tmp/master.png
```

各密度按 232×112dp 缩放到 1 / 1.5 / 2 / 3 / 4 倍写入
`res/drawable-{m,h,xh,xxh,xxxh}dpi/splash.png`，iOS 写 1×/2×/3× 到
`ios/Runner/Assets.xcassets/LaunchImage.imageset/`。v31 图标另有 176×176dp 的方形母版，
字面 150dp 宽。

`-0.05em` 与 `NoWaveTypography.display` 的 `letterSpacing: -size * 0.05` 是同一个值，
改一边就要重出另一边，否则 OS 图与首帧的字距会不一致。

## 五、已知边界

- **计数器不代表真实进度**，只是开屏编舞。
- **Android 12+ 的尺寸不保证像素级一致**：系统会缩放并圆形遮罩图标，保证的是「同样的
  墨、同样的 `000`」，不是等宽等高。
- **桌面/启动器图标仍是旧标记**（`assets/icons/logo.png`，由 `flutter_launcher_icons`
  在 CI 里生成到 `android`/`ios`）。这一阶段只清掉**启动过程中**出现的旧 logo；换应用
  图标需要单独的设计确认与多尺寸导出，不在本次范围。
- **真机矩阵未验证**：Android 8/9、Android 12+、iOS、亮/暗、中/英、2× 字体、320dp、
  刘海、减少动效开关、慢网络、session 超时、init 失败、深链冷启动、热重载不重播——
  这些目前只有单元/widget 测试与 `flutter build apk --release` 的证据。
