# room_english · 客餐厅 3D 英语探索 设计（2026-10-24）

## 1. 背景与目标

小星英语老师需要一个「能把孩子带进房间」的词汇教学工具：不是看图选词，而是让孩子在可旋转的 3D 客餐厅里点家具、听英文发音、看单词卡，把单词和实物对应起来。

原型来自 open-design（`kids-room-3d-english`，8m × 6m 低多边形客餐厅、25 件可点击物品、three.js 0.185 本地渲染）。本设计把它落到鸿蒙原生壳里，作为一个内置工具 `room_english` 挂在 `ToolRegistry` 上，由小星英语老师在「呈现」环节调用。

## 2. 方案选型

| 方案 | 结论 | 理由 |
| --- | --- | --- |
| **Web 容器 + rawfile 本地页面（采用）** | `Web` 组件加载 `resource://rawfile/room3d/index.html`，three.js / 字体 / CSS 全部打包在 rawfile，无网络依赖 | 原型是 three.js 网页，1:1 保真、零几何重写；项目里 `mermaid` / `document-parser` 已用同法加载 rawfile 页面并加载相对子资源，路径可靠 |
| ArkGraphics 3D 原生场景 | 不采用 | 原型是程序化低多边形几何（非 glTF），要重建成 glTF 资源 + 原生拾取/标签投影，工作量大且丢失原型视觉 |
| 原生 ArkUI 伪 3D | 不采用 | 旋转相机、悬停高亮、标签避让都需重写，效果不如原型 |

**边界**：ArkWeb 没有 `speechSynthesis`，发音改走原生 TTS 桥；原生标题栏接管「进度 + 我学会了」，页面切到 host 布局（隐藏自带品牌栏）。

## 3. 数据：25 个物品

`sofa / coffee_table / tv / tv_stand / remote_control / rug / cushion / floor_lamp / bookshelf / book / plant / curtain / window / picture / clock`（客厅 15）+ `air_conditioner / trash_can / dining_table / dining_chair / plate / bowl / cup / spoon / fork / kettle`（餐厅 10）。

每个物品带 `word / phonetic / zh / kidDefinition / example / category`，唯一数据源是 `rawfile/room3d/assets/scene-data.js`，工具侧校验白名单是 `utils/RoomEnglishValidation.ets` 的 `ROOM_OBJECT_IDS`。**两处必须同步**（单元测试断言 25 条）。

> 原型把空气调节器/垃圾桶归到餐厅（10 条），保持原分组不动，避免与原型 UI 的「15 / 10」计数冲突。

## 4. 工具契约

### 4.1 参数（schema 见 `config/BuiltinTools.ets`）

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `skill_key` | string enum `english_vocab` | 是 | 画像维度固定为英语词汇 |
| `focus` | string enum `living` / `dining` / `all` | 否 | 默认 `all`，本次重点区域（当前只进 payload + 文案，不做场景裁剪） |
| `words` | string[] | 否 | 本次重点词 id，最多 8 个；命中后自动显示英文标签并选中第一个词 |

### 4.2 回执（`ToolResult.result`）

```json
{
  "completed": true,
  "explored_count": 7,
  "words": ["sofa", "tv", "rug"],
  "focus": "all",
  "skill_key": "english_vocab",
  "cancelled": false
}
```

- 孩子点「我学会了」→ `completed: true` + 已点开物品清单。
- 直接关掉 sheet → `completed: false, cancelled: true`（ChatPage 的 `onDisappear` 兜底）。
- 预校验失败（坏 JSON / skill_key 错 / 非法 focus / 非法 word id / 超过 8 个词）→ `{ error: "validation_failed", should_retry: true }`，AI 自行修正。

## 5. 前端结构

`components/room/RoomEnglishCard.ets`

```
Column
├─ HeaderBar()            原生：标题 + 已收集 N/25 + 「我学会了」
└─ Stack
   ├─ Web(resource://rawfile/room3d/index.html)
   ├─ LoadingProgress     页面就绪前的「正在布置小房间…」
   └─ 错误面板 + 重新加载
```

- `isAnswered` 模式下不加载 Web，只渲染收集到的单词 chips（时间线回看用；实际时间线由 MessageBubble 的 `RoomEnglishStepContent` 显示）。
- 页面就绪（`onPageEnd`）后按 `words` 注入 `window.WordRoomApp.setLabels(true)` + `select(first)`。

### 5.1 桥协议（`RoomNativeBridge`，`javaScriptProxy` 注入）

| 方向 | 方法 | 说明 |
| --- | --- | --- |
| Web → 原生 | `speak(word)` | 返回 `'true'` 表示已交给原生 TTS；Web 侧据此跳过 `speechSynthesis` |
| Web → 原生 | `stopSpeak()` | 关闭单词卡 / 切词时停播 |
| Web → 原生 | `onReady()` | 3D 场景首帧就绪（Web 侧 loader 自行收起） |
| Web → 原生 | `onSelect(id, word)` | 选中物品，原生累计已收集单词 |
| Web → 原生 | `onProgress(idsJson)` | Web 侧 `discovered` 集合变化，原生以它为准覆盖进度 |

- Web 侧封装在 `assets/room-app.js` 的 `bridgeCall()`，桥缺失时全部降级为 no-op（浏览器里打开原型仍可用）。
- 原生侧状态写回统一走 `UIContext.runScopedTask`，避免 Web 代理回调线程直接改 `@Local`。
- `onSelect` / `onProgress` 同时带 id 与展示词：`words` 回执用 id（与工具白名单同口径），UI chips 用英文单词。

### 5.2 host 布局

`assets/room-host.css` 在 `body.room-host` 下隐藏页面自带 `.topbar` / `.skip-link`，`.workspace` 高度改 100dvh；原生 HeaderBar 顶替。该 class 由 `room-app.js` 无条件添加（这份 index.html 只在小词屋 sheet 里加载）。

## 6. 授星决定

**Decision：room_english 不授星**（与 `map_card` 一致）。

- 它是讲解型工具，没有对错判定；按项目规则「讲解课不是题」不记 `star_event`。
- 星星由小星老师在同一节课的后续 `english_quiz` / `matching_pairs` 给出（系统提示词里已明确写「room_english 本身不授星」）。
- 因此 **不改** `models/StarEventModels.ets` 与 `services/StarRewardService.ets`（10 处 drift 点全部跳过），也不出现在星星明细页。

## 7. 接入点（对照 `adding-mini-game-tool` 10 步配方）

| 步骤 | 文件 | 改动 |
| --- | --- | --- |
| 1 | `utils/SearchToolIdentityUtils.ets` | `ROOM_ENGLISH_TOOL_ID` + `isRoomEnglishFunctionName` + 加入 `isInteractiveQuizFunctionName` |
| 2 | `config/BuiltinTools.ets` | import、`RoomEnglishArgs`、`RoomEnglishExecutor`、`createRoomEnglishToolDefinition`、`createRoomEnglishToolConfig`、register、`getBuiltinToolIds` |
| 3 | `services/ToolExecutionService.ets` | import、`handleRoomEnglish`、dispatch（在 `resolveToolId` 之前） |
| 4a | `models/StarEventModels.ets` | **跳过**（见 §6） |
| 4b | `services/StarRewardService.ets` | **跳过**（见 §6） |
| 5 | `models/AssistantModels.ets` | import、默认助手 + 小星英语老师白名单、两段提示词 |
| 6 | `components/room/RoomEnglishCard.ets` | 新建（Web 容器 + 桥 + 完成回执） |
| 7 | `components/MessageBubble.ets` | import、`onOpenRoomEnglishSheet` @Event、待答横幅、7 处 step 判定、时间线回看 |
| 8 | `pages/ChatPage.ets` + `components/chat/ChatMessageListSection.ets` | 全屏 sheet 状态 / builder / `onDisappear` 兜底，事件透传 |
| 9 | 持久化 | **不需要**：仅 rawfile 静态资源，无用户数据 |
| 10 | 校验 | JSON.parse 26/26、`node --check` 4 个 JS、`assembleHap` 通过 |

## 8. 验收清单

- [ ] 小星老师调用 `room_english` 后，对话里出现「客餐厅 3D 英语探索 · 点击走进房间」横幅
- [ ] 点横幅打开全屏 sheet，3D 客餐厅渲染出来，可拖动旋转 / 双指缩放
- [ ] 点沙发 → 右侧（手机为下方）出现单词卡：sofa / /ˈsoʊfə/ / 沙发 / 儿童解释 / 例句
- [ ] 点「听发音」听到原生 TTS 英文，而不是「不支持语音朗读」提示
- [ ] 再点电视 → 单词卡切换，不叠加；点空白处 → 关闭单词卡
- [ ] 原生标题栏进度从 0/25 递增；点「我学会了」→ sheet 关闭，AI 收到 `explored_count` 与 `words`
- [ ] 时间线里这条工具步骤可展开，显示收集到的单词 chips
- [ ] 传 `words: ["sofa"]` 时进房间自动选中沙发并显示英文标签
- [ ] 直接下拉关闭 sheet → AI 收到 `cancelled: true`，不报错
- [ ] 非法 word id（如 `bathtub`）→ 工具返回 `should_retry`，AI 改用合法 id

## 9. 已知边界

- 3D 依赖 WebGL；极低端设备关闭硬件加速时显示「3D 房间没有打开」+ 重新加载，词汇表仍可在网页内使用（当前 sheet 直接展示错误面板，未做词汇表兜底）。
- 系统 TTS 必须已初始化（`EntryAbility` 已 init）；引擎不可用时返回 `'false'`，Web 侧回落到 `speechSynthesis`，再不行提示「当前设备不支持语音朗读」。
- `focus` 暂不裁剪场景（原型不支持按分类隐藏），只进回执与提示词。
- 深色模式下 Web 页自身主题固定浅色（原型只做了浅色），sheet 背景与原生标题栏会跟随深色，页内为浅色卡片，属预期。
