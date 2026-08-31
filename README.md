<p align="center">
  <img src="Reddict/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png" width="128" alt="Reddict icon">
</p>

# Reddict

Reddict 是一个常驻 macOS 菜单栏的多语言语境助手。它把翻译、精读、词汇、句法、文化背景、自然回复和表达改写放进同一个轻量浮窗，帮助你读懂字面之外的意思。

## 核心能力

### 翻译与精读

- 本地先按完整句子或语义块分段，不等待模型，也不消耗 Token。
- 默认先返回整段译文，再并行分析较长或较难的片段；最多同时处理 3 段。
- 每句话都可点击查看对应译文，并可单独触发「精读这句」。
- 单句译文从整段译文本地对齐，不重复请求模型。
- 精读结果包含核心骨架、词汇、句法、易混淆点，以及文化、词源和俚语说明。
- 日语支持假名、原型、词性、活用和 JLPT 等级；其他语言使用 CEFR A1–C2。

### 回复与表达

- 「怎么回」一次生成四种自然回复。
- `How To Say` 支持多个目标语言和可编辑文风。
- 文风可以启用、停用、新增、改名、编辑 Prompt、删除或恢复预设。
- 语音输入使用 Apple Speech；停止录音后只把转写结果写入输入框，不会自动发送。

### 模型与语言

- 内置 DeepSeek、Gemini、Kimi 和 CLI-Proxy 预设，也支持任意 OpenAI-compatible Chat Completions API。
- 可通过兼容的 `GET /models` 接口刷新模型列表，也可以手动输入模型名。
- 精读、怎么回和 `How To Say` 可分别绑定不同的 API 配置。
- 界面语言、解释语言、翻译目标语言和学习水平彼此独立。
- 支持经模型验证的自定义自然语言、历史语言与构造语言。

### 本地体验

- 同样的输入和配置会命中本地历史缓存，不重复消耗 Token。
- 历史记录可搜索并一键清空。
- 浮窗保持在其他应用之上；切换功能时复用同一个窗口。
- 菜单栏应用，不占用 Dock。

## 快捷键

| 功能 | 快捷键 |
| --- | --- |
| 翻译 / 精读 | `⌃⌥⌘T` |
| 怎么回 | `⌃⌥⌘L` |
| How To Say | `⌃⌥⌘H` |

再次按当前功能的快捷键会隐藏浮窗；按另一个快捷键会在现有浮窗中切换功能。也可以选中文字后使用「右键 → 服务 → Reddict」。

## 系统要求

- macOS 15.0 或更高版本
- 包含 macOS 15 SDK 的 Xcode
- 至少一个可用的 OpenAI-compatible API Key

## 本地运行

用 Xcode 打开 `Reddict.xcodeproj` 并运行 `Reddict` scheme，或者执行：

```bash
xcodebuild -project Reddict.xcodeproj \
  -scheme Reddict \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build

open DerivedData/Build/Products/Debug/Reddict.app
```

首次启动后，点击菜单栏图标并打开「语言、显示与 API 设置」：

1. 选择服务商，或填写自定义 Base URL。
2. 输入 API Key 和模型名；需要时刷新模型列表。
3. 点击「测试连接」。
4. 为精读、怎么回和 `How To Say` 选择配置，然后保存。
5. 设置界面语言、翻译目标、学习语言和学习水平。

远程 API 必须使用 HTTPS；HTTP 只允许 `localhost`、`127.0.0.1` 等本机地址。请求不会自动跟随重定向，避免凭据被转发到其他主机。

## 隐私与权限

- Reddict 只使用你在应用内手动输入并保存的 API Key，不扫描环境变量，也不读取或迁移其他 macOS 钥匙串项目。
- 历史记录保存在当前用户的应用容器中；目录权限为 `700`，历史文件权限为 `600`。
- 麦克风和语音识别权限只在点击 `How To Say` 的语音按钮后请求。
- App Store 构建启用 App Sandbox，仅声明出站网络和麦克风输入权限。

## 开发与验证

格式化 Swift 源码：

```bash
xcrun swift-format format --in-place --recursive Reddict Tests
```

运行全部本地 smoke tests：

```bash
Scripts/run-smoke-tests.sh
```

验证 Debug 构建：

```bash
xcodebuild -project Reddict.xcodeproj \
  -scheme Reddict \
  -configuration Debug \
  -derivedDataPath build-debug \
  build
```

## 项目结构

```text
Reddict/
├── Reddict/                 AppKit / SwiftUI 应用源码与资源
├── Tests/                   可独立编译运行的 smoke tests
├── Scripts/                 本地开发辅助脚本
├── Reddict.xcodeproj/       Xcode 工程与共享 scheme
└── ExportOptions.plist      App Store Connect 导出配置
```

Bundle ID：`com.archest.reddict`
