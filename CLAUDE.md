# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目

**Cube Chat**（仓库 `chatcube`）：纯 ArkTS 原生 AI 聊天客户端（非 WebView），运行在 HarmonyOS 6 (API 23) stage 模型上。支持 15+ AI 服务商、MCP 工具接入、桌面小组件、后台任务；同时承担"小星老师/小鹿老师"幼儿教学助手场景（数学题、英文题、分类、华容道、学写字、连一连等互动卡片 + 星星奖励系统）。

## Build & Run

- 使用 DevEco Studio 5.0+ 打开项目，同步后运行
- 构建前需将 `build-profile.json5.example` 复制为 `build-profile.json5` 并填入签名配置
- 调试/发布构建模式在 `build-profile.json5` 的 `buildModeSet` 中管理
- 编译：

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

- 清理：`hvigorw clean --mode module -p product=default`
- 产物：`entry/build/default/outputs/default/entry-default-signed.hap`

## Tests

`entry/src/ohosTest/` 是鸿蒙侧测试工程，使用 `@ohos/hypium` + `@ohos/hamock`（见 `entry/oh-package.json5` devDependencies）。运行：在 DevEco Studio 中右键测试文件 → Run，或通过 `hvigorw test` 在模块模式下执行。

当前测试覆盖较薄（`Ability.test.ets` / `List.test.ets` 是脚手架示例），新增业务逻辑时**优先在 `utils/` 抽出纯函数并补 hypium 单元测试**——组件层 ArkUI 测试成本高且项目内尚无基建。

## Linting

`code-linter.json5` 已开启 `@performance/recommended` + `@typescript-eslint/recommended` 规则集，并加严了一组 `@security/no-unsafe-*` 加密学规则（AES/hash/MAC/DH/DSA/ECDSA/RSA/3DES）。运行 lint：

```bash
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw lint --mode module -p product=default
```

## Architecture

MVVM 分层（`entry/src/main/ets/`）：

```
├── pages/          # 页面（NavDestination），通过 router_map.json 注册
├── components/     # 可复用 UI 组件，按功能域分子目录（chat/, index/, provider/, settings/ 等）
│   └── kids/       # 儿童模式主屏组件（KidsHomeView / KidsSessionCard / ParentalGateSheet）
├── viewmodels/     # ViewModel 层，业务逻辑和状态管理
├── services/       # 服务层单例；通过 ServiceRegistry.ets 静态门面统一访问
│   ├── registry/   # 模型/服务商能力注册子命名空间（ProviderProfileRegistry, ModelAbilityRegistry, ModelProfileRegistry）
│   ├── search/     # 搜索引擎注册（SearchEngineRegistry）
│   └── tts/        # TTS 引擎抽象与实现（ITtsEngine, SystemTtsEngine, MiMoTtsEngine）
├── state/          # 全局响应式状态对象（@ObservedV2 + @Trace），AppStorageV2.connect() 绑定
├── models/         # 数据模型/类型定义
├── config/         # 应用配置常量（AppStorage 键名、预设服务商、内置工具注册等）
├── utils/          # 工具函数（与 components/ 1:N 平行调用）
├── ui/             # 通用 UI 原语（与 components/ 区别：ui/ 不绑定业务）
├── entryability/   # 入口 Ability（主 + backup + form 三种）
├── widget/         # 桌面小组件页面
└── viewmodels/     # 业务 ViewModel（含 migrations/ 子目录做 Settings 版本迁移）
```

### 核心入口

- **EntryAbility** (`entryability/EntryAbility.ets`): 应用入口，launchType 为 singleton。`onCreate` 中按顺序初始化所有服务（偏好设置 → 数据库 → 附件存储 → 设置 → 默认模型 → 助手 → 主题），`onWindowStageCreate` 中加载 `pages/Index`
- **Index** (`pages/Index.ets`): 首页（会话列表 + 底部 HdsTabs：对话/生图/设置 + 推荐提示词 + 智感握姿适配），使用 NavPathStack 管理导航
- **ChatPage** (`pages/ChatPage.ets`): 对话页面 NavDestination；其逻辑按流程拆分到 `pages/chat/` 下的辅助模块（ChatSendFlow, ChatStopFlow, ChatInlineEditFlow, ChatScrollUiFlow, ChatToolIdHelper 等）
- 所有页面通过 `router_map.json` 注册，`main_pages.json` 只声明 Index 为首页
- **桌面小组件**：单独 `entryformability/`，由 `widget/` 下的页面承载

### 状态管理

- 模型类和状态对象使用 `@ObservedV2` + `@Trace` 实现响应式
- 全局状态通过 `AppStorageV2.connect()` 连接 `AppUiState`（UI 瞬态 + 主题）和 `AppSettingsState`（服务商/助手/默认模型配置）
- 标量值通过 `AppStorage.setOrCreate()` 写入，键名集中在 `config/AppStorageKeys.ets`
- `AppSettingsStore` 负责将配置写入 SQLite 后同步到内存状态（写库 → 替换数组 → 递增版本号触发 @Trace）

### 服务层（ServiceRegistry 门面）

- **AIApiService**: AI API 网关，支持 OpenAI（Chat Completions/Responses）、Anthropic（Messages）、Google（Gemini）三种格式的流式/非流式调用
- **HttpService**: 底层 HTTP 客户端，支持重试、取消、二进制数据
- **AITaskService** + **ChatTaskOrchestratorService**: 后台 AI 任务编排，带通知集成（`ChatNotificationService`）
- **DatabaseService**: 基于 relamStore (SQLite) 的持久化
- **PreferencesService**: 基于 preferences KV 存储的键值对持久化
- **ToolExecutionService** + **ToolRegistry** + **config/BuiltinTools.ets**: 函数调用执行引擎 + 工具注册中心
- **WebSearchService** + **services/search/**: 联网搜索（Bing local / Tavily / Exa）+ 搜索引擎注册
- **McpService**: 远端 streamable MCP Server 接入
- **ImageGenerationService** + **GeneratedMediaRepository**: 图像生成主链路（OpenAI Responses 生图、参考图、比例、历史图库）
- **DocumentParseService** / **AttachmentContentService** / **AttachmentStorageService**: 文档附件（OFD/PDF/Word/Excel）解析与存储
- **WebDAVService** / **WebDAVSyncService** / **ImportExportService**: 数据备份与跨设备同步
- **LessonPlanningService** / **ChildProfileService** / **StarRewardService**: 教学规划、孩子画像、星星奖励
- **AssistantService** / **AssistantAvatarCache**: 助手管理与头像
- **ImagePromptTemplateService**: 提示词模板库

### 核心数据模型

- `models/ChatModels.ets`: `ChatSession`（含 messages[]、draftText/Attachments）、`ChatMessage`（含 parts[] 支持交错内容）、`ModelProvider`（apiStyle 决定 OpenAI/Anthropic/Google 格式）、`ModelInfo`（含 ModelCapabilities：tools/reasoning/web_search/vision/streaming）
- `models/MessageParts.ets`: 消息 part 类型定义（文本/工具调用/深度思考/联网查询/图片/HTML/Mermaid/LaTeX 等）
- `models/StarEventModels.ets`: **星星奖励系统的活动类型联合**——加新游戏/题型时必须更新 10 处位置（详见 `.claude/skills/adding-mini-game-tool/SKILL.md`）
- `models/AssistantModels.ets`: 助手模型；`models/ThemeColors.ets`: 10 种主题色板

### 导航

使用 HarmonyOS NavDestination 导航（非旧版 router.pushUrl）。Index 通过 NavPathStack 推入目标页面，页面名称在 `router_map.json` 中映射到构建函数。

### 工具调用与互动卡片

`ToolRegistry` + `BuiltinTools.ets` 注册所有 AI 可调用的工具。工具执行走 `ToolExecutionService` → 视情况进入 `handleNumberPuzzle` / `handleCategorization` / `handleHandwriting` 等专门路径 → 渲染对应 `components/*Card.ets` → 用户在卡片内交互 → `onAnswer(toolCallId, resultJson)` 回写。

主要互动卡片组件：

| 组件 | 工具名 | 用途 |
|------|--------|------|
| `MathQuizCard` | `math_quiz` | 数学题选择/验证（5 题型，含竖式帮助 sheet） |
| `EnglishQuizCard` | `english_quiz` | 英文题（含 phonics） |
| `VerticalMathCard` | `vertical_math` | 竖式计算演示 |
| `CategorizationCard` | `categorization` | 分类小管家 |
| `NumberPuzzleCard` | `number_puzzle` | 数字华容道（2–5×5 随机打乱；旧名 `huarongdao` 已规范化） |
| `HandwritingCard` | `handwriting_practice` | 学写字（笔画+米字格+轨迹评分） |
| `MazeCard` | `maze` | 走迷宫 |
| `SudokuCard` | `sudoku` | 数独（5 难度） |
| `PictureVocabCard` | `picture_vocab` | 看图识词（en/zh） |
| `ListeningQuizCard` | `listening_quiz` | 英语听力辨音（TTS 朗读） |
| `PinyinQuizCard` | `pinyin_quiz` | 拼音认读（看字选拼音，内置字表） |
| `MatchingPairsCard` | `matching_pairs` | 连一连观察配对 |
| `AskUserCard` | `ask_user` | AI 反问收集偏好 |

出题类工具（math_quiz / english_quiz / picture_vocab / listening_quiz / pinyin_quiz / matching_pairs / categorization）参数在渲染前经 `utils/*Validation.ets` 预校验，坏题以 `should_retry` 回传 LLM 自行修正。

完整设计文档见 `docs/superpowers/specs/`。

## 关键文档

| 路径 | 用途 |
|------|------|
| `README.md` / `README_EN.md` | 用户向文档（功能、版本、构建） |
| `CHANGELOG.md` | 版本变更历史 |
| `teacher.md` | "小鹿老师"助手系统提示词示例（教学风格、工具调用、出题格式） |
| `docs/superpowers/specs/` | 工具/功能的详细设计 spec（v1 数字华容道、学写字、分类小管家、教学提示词 等） |
| `docs/superpowers/plans/` | 实施 plan（与 spec 一一对应） |
| `.claude/rules/` | 项目级规则文档（如 `number-puzzle-card.md` 描述该组件的完整设计） |
| `.claude/skills/adding-mini-game-tool/SKILL.md` | **新增互动小游戏工具的 10 步配方 + 4-grep 校验**——加新工具前必读 |

## 外部依赖

`entry/oh-package.json5`:
- `@lyb/media-preview` ^1.3.5: 媒体预览
- `@luvi/lv-markdown-in` ^3.4.2: Markdown 渲染

## 已知踩坑（详见 MEMORY.md）

- **JSON-in-template-literal 陷阱**：`rawSchemaJson` 模板字符串中嵌入 JSON schema 时，描述字段里的 ASCII `"` 会在运行时炸 `JSON.parse`——用 `「」` 中文方头括号或全宽引号代替。改完后用 `node -e ...` 提取并 `JSON.parse` 验证，不能只看编译通过。
- **ArkTS 严格模式**：`arr.map(p => ({...}))` 内联对象字面量需显式标注返回类型（`10605038`）；ForEach 回调体内**不能**写 `const x: Foo = {...}` 声明（`10905209`）——抽成返回已构造对象的方法；不允许 `const [a, b] = ...` 解构（`10605074`）。
- **`sys.symbol.*` 命名空间 ≠ iOS SF Symbols**：`stop_fill` / `doc_on_clipboard` 等不存在，可用 `pause_fill` / `doc` 等。
- **`Row.alignItems` 用 `VerticalAlign`、`Column.alignItems` 用 `HorizontalAlign`**——互相翻转时易错。
- **`@Trace` 字段必须在子 Builder 的形参里**才能被识别为响应式依赖；直接读 `this.xxx` 在 `@Builder` 内部有效，**但传字符串快照会断响应式**。
