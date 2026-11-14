# 灵动岛 for Mac

> 原生 AppKit + SwiftUI，不用 Xcode 工程，`swiftc` 直接编成 `.app`。

macOS 上的悬浮灵动岛：纯黑本体、四角全圆、鼠标悬停弹簧展开，收起后变成顶部一颗小胶囊。展开时上半死黑、下半渐变到真透明，桌面壁纸清晰透出来 —— 玻璃用 macOS 26 的官方 `glassEffect(_:in:)`，不是自己画的假模糊。

无 Dock 图标（`LSUIElement`），菜单栏留一个胶囊入口进设置。

## English

A native macOS Dynamic Island in AppKit + SwiftUI — no Xcode project, just `swiftc` into a `.app`.

- Floating, fully rounded island (no fake notch). Hover to spring it open, move away and it collapses into a small capsule.
- Solid black top fading into real transparency at the bottom, using Apple's official Liquid Glass `glassEffect(_:in:)`.
- Seven tabs: Home, Launcher, File shelf, Music, Timer, Clipboard and an AI chat panel.
- AI chat speaks both **local Ollama** and **13 cloud providers** (OpenAI, DeepSeek, Gemini, Doubao/Ark, Qwen, Zhipu, Kimi, OpenRouter, xAI, Mistral, SiliconFlow, 01.AI, Perplexity) through one unified model picker.
- No Dock icon; a separate settings window with 9 pages covers everything from panel geometry to per-provider API keys.

Requires macOS 26 or later. Build with `./build.sh`.

## 运行

```bash
./build.sh                 # 产出 灵动岛.app
open 灵动岛.app
```

从别处拷来的包被杀，执行一次：

```bash
xattr -dr com.apple.quarantine "灵动岛.app"
```

只需要 Command Line Tools，不需要 Xcode.app。要求 macOS 26 及以上（液态玻璃 API 的门槛）。

## 页签

| 页签 | 能力 |
|---|---|
| 主页 `home` | 天气卡（Open-Meteo 实时 + 6 小时预报）、番茄钟（环形进度）、快速笔记、CPU/内存/磁盘、常用 App 快捷启动 |
| 启动台 `launcher` | 扫 `/Applications`、`/System/Applications`、`~/Applications` 的全 App 网格，顶部搜索实时过滤，名称走本地化字典 |
| 文件暂存 `files` | 真的能把文件拖进岛里（`NSDraggingDestination`），支持点选、逐行拖出、打开暂存目录 |
| 音乐 `music` | 读系统「正在播放」，封面 + 主色提取，上一首/播放/下一首、进度与剩余 |
| 计时 `timer` | 1/5/10/25 分钟，环形进度 + 结束时间；收起态常驻倒计时胶囊，到点响铃 |
| 剪贴板 `clipboard` | 复制即记录，去重、可配保留条数，点条目回填 |
| AI `chat` | 本地 Ollama 与云端厂商二合一，流式输出，思考型模型单独显示「思考中…」 |

展开面板按页签分别给尺寸，启动台和 AI 给得最大；收起态单独更小一档。全部尺寸随屏幕缩放（`scale = 屏宽 / 1728`）。

## AI：本地 + 云端一个下拉

顶部模型选择器是自绘的下拉浮层（不走系统 Menu，避免自绘内容被裁成纯文字）：

- **本地模型分组** — 硬盘图标，选中项高亮 + 对勾，走本机 Ollama（默认 `http://127.0.0.1:11434`）
- **分割线下面是各家云端厂商** — 每个厂商折叠出它的全部模型，每项旁边一个**实心云朵** `cloud.fill`

选本地项走本地 llama，选某个云端模型就切到对应厂商并把该模型设为当前。厂商卡片里填了 API Key 时会先 `GET /models` 拉账号下真实可用的模型列表，没填则展示内置的常见模型清单兜底。

请求统一走 OpenAI 兼容协议（`POST /chat/completions` 流式 SSE，`data: {json}` / `[DONE]`，Bearer 鉴权）。

## 设置窗口

菜单栏胶囊 →「打开灵动岛设置…」，或展开面板右上角齿轮。左侧侧边栏 + 右侧滚动内容，9 个分页：

- **通用** — 开机自启（`SMAppService`）、全局快捷键（Carbon `RegisterEventHotKey`，4 组预设）、专注模式（全屏检测自动免打扰，支持跨午夜）、HUD 行为
- **精细调节** — 24 项，全部接真实逻辑：强调色（跟随封面 + 6 预设）、阴影/描边/高光/透明度滑杆、动画速度、减弱动效、圆角、字号、菜单栏图标、外部点击、悬停延迟、收起延迟、剪贴板条数、番茄钟专注/休息时长、提示音开关与 6 种音效、音量、温标、24 小时制、天气刷新间隔、AI 轮数
- **外观与尺寸** — 预览块以 `assets/preview-wallpaper.png` 为底，拖滑杆实时预览：面板宽度、展开尺寸、圆角、收起态比例、玻璃浓度、收起态距顶/长度/厚度
- **页签** — 每个页签一个开关，全关自动回退全显
- **主页组件** — 天气城市 / 经纬度
- **本地 AI** — 后端地址、连接状态灯、刷新模型、`num_ctx` 与 `temperature`
- **云端 AI** — 13 家厂商预设网格（**真实品牌 logo**）、自定义服务商、每家的接口地址 / API Key（SecureField + 眼睛）/ 模型名，以及「聊天用哪个」单选
- **笔记与暂存** — 条数统计、清空、在访达中打开暂存目录
- **关于**

云端厂商图标取自 [LobeHub Icons](https://github.com/lobehub/lobe-icons)，SVG 统一把 `width="1em"` 换成 `24`（CoreSVG 不认 em 单位，否则会缩成 1×1 的小点）。

## 交互

- **鼠标移到岛上**：弹簧展开（response 0.66 / damping 0.84）；移开自动收回
- 例外只有两个：正在生成回答、或 AI 输入框里还有字
- **单击岛体**：固定展开，再点取消
- **鼠标穿透是硬保证**：25Hz 轮询光标位置，光标不在岛上时给窗口置 `ignoresMouseEvents = true`，点击在窗口服务器层直接落到下面的访达/桌面

## 屏幕适配

`scale = 屏宽 / 1728`（16" MacBook Pro 逻辑宽度为基准）。窗口贴主屏顶部居中、层级 = 菜单栏 + 3，全屏应用上也压得住。

换屏不跳屏、不错误缩放：`repositionIsland()` 全部用相对量定位，并监听 `didChangeScreenParametersNotification`；按旧窗口中心选屏，而不是简单取主屏。

## 数据落盘

`~/Library/Application Support/DynamicIsland/`：`notes.json`（快速笔记）、`stash.json`（文件暂存，只记路径不搬文件，启动时过滤掉已不存在的路径）。设置项与云端服务商配置在 `UserDefaults`（domain `local.niuniu.dynamicisland`），API Key 同样存本地 `UserDefaults`，不上传任何服务器。

## 自检命令行

```bash
"./灵动岛.app/Contents/MacOS/DynamicIsland" --probe                       # 窗口/命中区/后端/天气/应用数
"./灵动岛.app/Contents/MacOS/DynamicIsland" --snapshot /tmp/p.png         # 离屏渲染各面板布局
"./灵动岛.app/Contents/MacOS/DynamicIsland" --start-expanded=launcher     # 以指定页签展开启动
"./灵动岛.app/Contents/MacOS/DynamicIsland" --start-expanded=settings     # 同时打开设置窗口
"./灵动岛.app/Contents/MacOS/DynamicIsland" --open-model-picker           # 直接展开自绘模型下拉
"./灵动岛.app/Contents/MacOS/DynamicIsland" --ask=你好                    # 自动向当前模型发一问
"./灵动岛.app/Contents/MacOS/DynamicIsland" --hover-log=/tmp/h.log        # 记录光标进出岛体的穿透切换
```

## 重新编译

```bash
./build.sh     # swiftc -O -target arm64-apple-macos26.0 → ad-hoc 签名 → 灵动岛.app
```

本机命令行 `swiftc` 环境没有 SwiftUI 宏插件，所以代码里不能用 `@State` / `@StateObject` / `@Environment`，全部状态走 `@MainActor IslandModel`（`ObservableObject` + `@Published`），设置窗口的分页状态用 `@MainActor final class SettingsState`。

## 结构

```
src/
  main.swift              入口（MainActor.assumeIsolated）
  AppDelegate.swift       建窗口、屏幕自适应、穿透轮询、菜单栏图标、全局快捷键、自检参数
  IslandPanel.swift       IslandWindow(NSPanel) + IslandHostingView（命中区 + 拖放 + 悬停）
  IslandModel.swift       全部状态、按页签的几何、计时/音量/播放/剪贴板轮询、AI 对话、云端服务商
  IslandShape.swift       上下圆角可独立动画的形状
  IslandRootView.swift    玻璃层 + 纯黑/渐变遮罩 + 描边 + 内容
  CollapsedViews.swift    收起态各胶囊（按 compactScale 缩放）
  ExpandedViews.swift     展开容器 + 音乐/计时/剪贴板/AI 面板 + 自绘模型下拉
  HomeViews.swift         主页：天气卡、番茄钟、笔记、统计、快捷启动
  LauncherViews.swift     应用启动台网格
  SettingsWindow.swift    NSWindow + 设置分页 + 品牌 logo 加载
  HotKeyManager.swift     Carbon 全局快捷键
  Components.swift        封面、镜头点、均衡器、进度条、音量分段、环形图等
  Snapshot.swift          离屏预览
  Services/
    CloudChatService.swift  CloudProvider / 13 家预设 / OpenAI 兼容流式客户端
    LlamaService.swift      本地 Ollama 客户端
    NowPlaying.swift        MediaRemote 正在播放
    AudioService.swift      CoreAudio 音量
    SystemStats.swift       CPU / 内存 / 磁盘
    ColorExtractor.swift    封面主色提取
    WeatherService.swift    Open-Meteo
    LauncherService.swift   应用扫描与启动
    StashStore.swift        笔记与文件暂存持久化
assets/
  logos/                  13 家厂商品牌图标
  preview-wallpaper.png   设置页预览底图
```

## 已知边界

- 系统「正在播放」走私有框架 MediaRemote，音量走 CoreAudio，本机实测可用、不弹授权
- 启动台名称取 `CFBundleDisplayName` → `localizedInfoDictionary` → 访达显示名，个别第三方 App 名字太长会省略号截断
- 输入框要在展开态点一下才拿到键盘焦点（LSUIElement 无 Dock 图标，切到 AI 页签会主动激活自身）
- 暂存只记路径，原文件被删除后会自动从列表里消失
- CoreSVG 不识别 `em` 单位、不支持 Gemini 那套半透明渐变，所以厂商图标在入仓前已做过 SVG 兼容处理

## License

MIT
