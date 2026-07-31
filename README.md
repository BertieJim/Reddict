# Reddict

一个只住在 macOS 菜单栏里的多语言语境助手，可按用户的界面/解释语言和学习水平精读多语言内容。

## 功能

- 综合精读：本地规则立即按完整句子或语义块切分，不等待、不消耗模型 Token
- 长文本只自动深挖较长或高难度段；短/简单段保留在原位，可单独点「深度分析」
- 缺少明确句界的长块会先由模型做轻量语义分段，并返回 0–100 难度分
- 分句卡片先显示；每个深度分析段独立请求，最多 3 路并行，哪个先返回就先更新哪个卡片
- 等待中的卡片只显示当前文字状态，不用转圈或骨架屏打断阅读
- 单段使用独立的 8,000 Token 输出预算；检测到截断或损坏 JSON 后会自动压缩内容重试一次
- 信达雅翻译、实词、句法、文化/梗合在同一个页面
- 日语：假名、原型、词性、活用、JLPT 等级；排除助词与功能词
- 可添加多种学习语言；除日语使用 JLPT 外，其余语言统一使用 CEFR A1–C2
- 界面/解释语言可选简体中文或 English；精读译文的目标语言可独立设置
- 预设之外可输入自定义语言；当前模型会用一次请求验证其是否为可翻译语言、能否可靠理解分析
- 古汉语、拉丁语、克里贡语等真实历史/构造语言可以通过；物品、食物或无意义名称会被拒绝
- 当前模型无法分析某语言时显示模型品牌建议；模型拒绝推荐时回退建议 OpenAI GPT
- 可选择只显示当前水平及以上的分析项目，或显示全部有价值的分析项目
- 词汇只保留超出当前水平的重要词、习语、特殊转义和易混名词，难度标签固定在最左侧
- 句法使用彩色成分块与下标标记主语、动词、宾语等，并在下方对应解释
- 句法、词汇、语法文化词源及俚语区块默认折叠
- 固定分析顺序：核心骨架 → 组成部分 → 易混淆点
- 俚语固定结构：字面翻译 → 适用场景 → 文化与历史
- 四种自然回复，以及支持预设/已验证自定义目标语言的 How To Say
- 本地结构化历史与缓存：同样内容再次查询不调用模型，不消耗 Token
- 原生预设 DeepSeek、Gemini、Kimi、CLI-Proxy，也可接任意 OpenAI-compatible API

## 运行

用 Xcode 打开 `Reddict.xcodeproj`，运行 `Reddict` scheme。或者：

```bash
xcodebuild -project Reddict.xcodeproj \
  -scheme Reddict \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build

open DerivedData/Build/Products/Debug/Reddict.app
```

首次启动后，点菜单栏气泡图标 →「模型与 API 设置」：

1. 选择 DeepSeek、Gemini、Kimi、CLI-Proxy 或自定义。
2. 可直接修改 API Base URL 与 Model。
3. 输入 API Key，点击「测试连接」。App 会发送一个极小的真实模型请求，并显示响应时间与模型回复。
4. 测试通过后才能「保存并使用」。Reddict 只使用你在设置页手动输入并保存的 Key，不读取 macOS 钥匙串。
5. 自定义服务需要兼容 OpenAI `POST /chat/completions`。如果不接受 `response_format`，关闭设置中的 JSON 开关后重新测试。

同一设置页可设置界面/解释语言、精读翻译目标、学习语言与水平：日语使用 JLPT，其余语言使用 CEFR。自定义语言必须先由当前已保存的模型验证，通过后才会进入语言库并可保存使用。

CLI-Proxy 预设来自 `SELF_API_USAGE.md`：Base URL 为 `https://studyhuyu.com/llm/v1`。出于安全考虑，文档中的 Key 不会写进 App，仍需手动输入。

## 使用

1. 复制任意语言文字，按 `⌃⌥⌘L`，弹出综合精读；再次按下隐藏，第三次按下恢复原任务。
2. 或在浏览器选中文字，右键 → 服务 → `Reddict · 综合精读`。
3. 浮窗切换到其他 App 时仍保持在前面；隐藏或关闭浮窗不会取消正在运行的模型任务。
4. 精读和回复上方的文字框可以直接输入、粘贴和修改，点击「开始精读」或「生成回复」。
   精读开始后会立刻看到本地分句结果，各句分析随后逐卡片出现。
5. 浮框右上角时钟可检索历史记录；命中缓存时底部显示「来自历史 · 0 Token」。
6. `How To Say` 中输入内容，选择任一预设或已验证的自定义语言后点 `Go`。

如果系统服务未出现，到「系统设置 → 键盘 → 键盘快捷键 → 服务 → 文本」确认 Reddict 已启用，或重新登录一次。

## 安装到 Applications

```bash
xcodebuild -project Reddict.xcodeproj \
  -scheme Reddict \
  -configuration Release \
  -derivedDataPath build \
  build

ditto build/Build/Products/Release/Reddict.app /Applications/Reddict.app
open /Applications/Reddict.app
```
