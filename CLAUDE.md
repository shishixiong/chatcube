# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- 使用 DevEco Studio 5.0+ 打开项目，同步后运行
- 目标 SDK: HarmonyOS 6 (API 23)，stage 模型
- 构建前需将 `build-profile.json5.example` 复制为 `build-profile.json5` 并填入签名配置
- 调试/发布构建模式在 `build-profile.json5` 的 `buildModeSet` 中管理
编译：
`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk 
 /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap
 --mode module -p product=default -p buildMode=debug`

## Architecture

这是一个纯 ArkTS 原生 AI 聊天客户端（非 WebView），采用 **MVVM** 架构，运行在 HarmonyOS stage 模型上。

### 分层结构

```
entry/src/main/ets/
├── pages/          # 页面（NavDestination），每个页面通过 router_map.json 注册
├── components/     # 可复用 UI 组件，按功能域分子目录（chat/, index/, provider/, settings/ 等）
├── viewmodels/     # ViewModel 层，处理业务逻辑和状态管理
├── services/        # 服务层，单例服务，通过 ServiceRegistry 门面统一访问
├── state/           # 全局响应式状态对象（@ObservedV2 + @Trace），通过 AppStorageV2.connect() 绑定
├── models/          # 数据模型/类型定义，使用 @ObservedV2 + @Trace 装饰器
├── config/          # 应用配置常量（AppStorage 键名、预设服务商、内置工具注册等）
├── utils/           # 工具函数
└── widget/          # 桌面小组件页面
```

### 核心入口

- **EntryAbility** (`entryability/EntryAbility.ets`): 应用入口，launchType 为 singleton。onCreate 中初始化所有服务（偏好设置 → 数据库 → 附件存储 → 设置 → 默认模型 → 助手 → 主题），onWindowStageCreate 中加载 `pages/Index`
- **Index** (`pages/Index.ets`): 首页，包含会话列表、底部标签导航（对话/生图/设置），使用 NavPathStack 管理导航
- **ChatPage** (`pages/ChatPage.ets`): 对话页面 NavDestination，其逻辑按流程拆分到 `pages/chat/` 下的辅助模块（ChatSendFlow, ChatStopFlow, ChatInlineEditFlow 等）
- 所有页面通过 `router_map.json` 注册（共 24 个页面入口），`main_pages.json` 只声明 Index 为首页

### 状态管理

- 模型类和状态对象使用 `@ObservedV2` + `@Trace` 实现响应式
- 全局状态通过 `AppStorageV2.connect()` 连接 `AppUiState`（UI 瞬态 + 主题）和 `AppSettingsState`（服务商/助手/默认模型配置）
- 标量值通过 `AppStorage.setOrCreate()` 写入，键名集中在 `config/AppStorageKeys.ets`
- `AppSettingsStore` 负责将配置写入 SQLite 后同步到内存状态（写库 → 替换数组 → 递增版本号触发 @Trace）

### 服务层

- **ServiceRegistry** (`services/ServiceRegistry.ets`): 统一门面，所有服务通过 `ServiceRegistry.xxx()` 静态方法访问
- **AIApiService**: AI API 网关，支持 OpenAI（Chat Completions/Responses）、Anthropic（Messages）、Google（Gemini）三种格式的流式/非流式调用
- **HttpService**: 底层 HTTP 客户端，支持重试、取消、二进制数据
- **AITaskService**: 后台 AI 任务编排，带通知集成
- **DatabaseService**: 基于 relamStore (SQLite) 的持久化
- **PreferencesService**: 基于 preferences KV 存储的键值对持久化
- **ToolExecutionService**: 函数调用执行引擎，处理工具审批流
- **ToolRegistry**: 工具注册中心，内置工具在 `config/BuiltinTools.ets` 注册

### 核心数据模型 (`models/ChatModels.ets`)

- `ChatSession`: 会话（含 messages[]、draftText/Attachments）
- `ChatMessage`: 消息（含 parts[] 支持交错内容类型）
- `ModelProvider`: 服务商配置（apiStyle 决定 OpenAI/Anthropic/Google 格式）
- `ModelInfo`: 模型信息（含 ModelCapabilities：tools/reasoning/web_search/vision/streaming）

### 导航

使用 HarmonyOS NavDestination 导航，非旧版 router.pushUrl。Index 通过 NavPathStack 推入目标页面，页面名称在 `router_map.json` 中映射到构建函数。

### 外部依赖

- `@lyb/media-preview` ^1.3.5: 媒体预览
- `@luvi/lv-markdown-in` ^3.4.2: Markdown 渲染
