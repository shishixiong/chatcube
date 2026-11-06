# farm_english · 阳光农场 3D 英语探索 设计（2026-11-06）

## 1. 背景与目标

小星英语老师已有一套「把词汇放进 3D 场景」的教学工具：`room_english`（全屋 76 件物品）与 `city_english`（小词城 50 个单词）。本设计补上同系列的**农场**场景：140m × 110m 低多边形农场，5 个分区、50 个可点单词（地点 / 动物 / 农作物 / 农机 / 自然 / 人物），让孩子点动物、作物、房子听发音、看单词卡，作为「呈现」环节的词汇课入口。

原型来自 open-design 项目 `3b189cb2-2ebe-49da-bf8c-6f4d17bcf90a`（「阳光农场 Sunny Farm」，2026-11-06 快照，three.js r128 UMD）。它已经是按本 App 集成方式编写的离线 ArkWeb 页面：`three.min.js` 本地 UMD、相对路径 `./assets/`、`FarmNativeBridge` 桥、`window.FarmApp` 控制接口、host 布局 CSS 一应俱全。因此实现方式是**1:1 搬运该目录 + 按 `city_english` 模式接线**，不重写几何；50 个 id、5 个分区 id、`FarmApp` API 均以该快照为准，不重命名。

## 2. 目标 / 非目标

**目标**

- 新增内置工具 `farm_english`，由小星老师 / 小星英语老师在英语词汇课中调用。
- 全屏 sheet 内加载 `resource://rawfile/farm3d/index.html`，可拖动旋转、双指缩放、点物体开单词卡。
- 原生接管 TTS（先中文后英文，语速 0.8）、词汇表入口、黄昏切换、「我学会了」完成回执。
- 预校验 + `should_retry`：坏 focus / 非法单词 id / 超过 8 个词不渲染卡片。
- 教学台账记「曝光」（`recordTaught`，与 room/city 同法）——按 **AI 传入的目标词** 记账，不按孩子实际点击回填。

**非目标**

- 不授星（讲解型，与 `map_card` / `room_english` / `city_english` 一致）。
- 不改 `StarEventModels.ets` / `StarRewardService.ets`（10 处 drift 点全部跳过）。
- 不把农场做成独立页面或一级入口。
- 不新增图片资源、不联网、不依赖 `speechSynthesis`。
- 不做「实际点击词」的台账回填（台账仍按 AI 目标词在工具开始时记曝光）。

**失败定义**

- 孩子点开 3D 场景后看不到或点不动物体（WebGL / 路径 / host 模式问题）。
- AI 能调用但 `words` 传了不存在的 id，卡片仍渲染空壳。
- 讲解完却给了星星（破坏「讲解课不是题」的规则）。

## 3. 数据：50 个单词 / 5 个分区

唯一数据源：`rawfile/farm3d/assets/farm-data.js`（搬自原型，不改 id）。

| 分类 | 数量 | id |
| --- | --- | --- |
| places 地点 | 10 | farmhouse barn chicken_coop stable silo windmill greenhouse well gate fence |
| animals 动物 | 14 | cow pig sheep horse goat chicken rooster duck goose rabbit cat dog bee bird |
| crops 农作物 | 10 | wheat corn potato carrot tomato pumpkin apple strawberry sunflower hay |
| machines 农机 | 8 | tractor trailer plow harvester wheelbarrow watering_can shovel pitchfork |
| nature 自然 | 5 | tree grass flower pond hill |
| people 人物 | 3 | farmer child grandma |

分区 id（`window.FarmApp.setView` 取值）：`overview` / `farmyard_zone` / `field_zone` / `pasture_zone` / `orchard_pond_zone`。

工具侧白名单 `utils/FarmEnglishValidation.ets` 的 `FARM_OBJECT_IDS` 与 `farm-data.js` **必须同步**（50 条，按上表顺序）。

## 4. 工具契约

### 4.1 参数（`config/BuiltinTools.ets` schema）

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `skill_key` | string enum `english_vocab` | 是 | 画像维度固定为英语词汇 |
| `focus` | string enum `overview` / `farmyard_zone` / `field_zone` / `pasture_zone` / `orchard_pond_zone` | 否 | 默认 `overview`；兼容 `all` / `''` → `overview` |
| `words` | string[]（可点 id，最多 8 个，去重） | 否 | 传了会直接选中第一个词；不传则按 `focus` 飞到分区并打开该区第一个重点词 |

`resolveFarmEnglishView(focus)`：合法分区原样返回，其余一律 `overview`。

### 4.2 回执（`ToolResult.result`）

```json
{
  "completed": true,
  "explored_count": 3,
  "words": ["cow", "wheat", "tractor"],
  "focus": "farmyard_zone",
  "skill_key": "english_vocab",
  "cancelled": false
}
```

- `words` = **本次 sheet 会话里孩子实际点开的 id**（`sessionIds`），与 `explored_count` 长度一致；不是 AI 请求的 `words`，也不是历史累计收集。AI 自己知道它请求了哪些目标词，可用回执里的实际点击词安排复测。
- 点「我学会了」→ `completed: true`；直接关 sheet → `completed: false, cancelled: true`（ChatPage `onDisappear` 兜底）。
- 预校验失败 → `{ error: "validation_failed", message, should_retry: true }`，AI 自行修正。
- 讲解型：`extractLedgerAnswerItems` 恒返回 `[]`（掌握度不因「看了」推进），曝光在 `recordLedgerServed` 阶段按 AI 目标词记。

## 5. 前端结构

`components/farm/FarmEnglishCard.ets` — 结构与 `CityEnglishCard` 同构：

```
Column
├─ HeaderBar()   标题 +「本次 X 个 · 农场收集 N/50」+ [词汇表] [🌙/☀️] [我学会了]
└─ Stack
   ├─ Web(resource://rawfile/farm3d/index.html)
   ├─ LoadingProgress  「正在播种阳光农场…」
   └─ 错误面板 + 重新加载
```

- `isAnswered` 时不加载 Web，只渲染本次点开的单词 chips（时间线回看）。
- `onPageEnd` → 注入一次：

```js
var app = window.FarmApp;
app.setHostMode(true);
if (firstWord) { app.select(firstWord); } else { app.setView(view); }
```

> 与 city 的差异：`select(id)` 内部会按物体所属分区 `setZone(id.zone, { openFocus: false })`，因此有 `words` 时**不再先 `setView`**，避免 960ms 后 `openFocus` 把用户刚点的词覆盖掉。

### 5.0 会话态 vs 累计收集（比 city 更严格）

Web 原型的 `farm.discovered.v1` 会跨会话累计，`onReady` 后立即 `onProgress(全部历史 id)`。若照搬 city，孩子一打开 sheet 就能直接点「我学会了」并回执一堆历史单词。农场卡因此维护两个集合：

| 字段 | 来源 | 用途 |
| --- | --- | --- |
| `sessionIds` | 本次 `onSelect` 追加 | 「我学会了」门槛（≥1）、回执 `words` / `explored_count`、完成页 chips |
| `discoveredIds` | `onProgress` 覆盖（含历史） | Header 的「农场收集 N/50」、Web 内收集护照 |

「我学会了」只在 `sessionIds.length > 0` 时可点；点过历史上收集过的词也算本次（`onSelect` 仍会回调）。

### 5.1 桥协议（`FarmNativeBridge`，`javaScriptProxy` 注入）

| 方向 | 方法 | 说明 |
| --- | --- | --- |
| Web → 原生 | `speak(text, zh)` | 原生先念中文再念英文，返回 `'true'` |
| Web → 原生 | `stopSpeak()` | 关词卡 / 切词 / 离开时停播 |
| Web → 原生 | `onReady()` | 场景与 UI 初始化完成 |
| Web → 原生 | `onSelect(id, word)` | 选中单词：`sessionIds` + `discoveredIds` 各记一次 |
| Web → 原生 | `onProgress(idsJson)` | 累计收集进度（localStorage 持久化），只更新 `discoveredIds` |

- 原生状态写回统一 `UIContext.runScopedTask`，避免 Web 代理线程直接改 `@Local`。
- 回执 `words` 用 id（与白名单同口径），UI chips 用英文单词（`lookup` 映射，历史 id 退回 id）。

### 5.2 host 布局

原型 `farm-host.css` 在 `.app.host-mode` 下隐藏自带 `.topbar`，保留分区 tab / 英文标签 / 重置视角；`setHostMode(true)` 由卡片在页面就绪后调用一次。

## 6. 接入点

| 文件 | 改动 |
| --- | --- |
| `resources/rawfile/farm3d/` | 新建：`index.html` + `assets/`（css / farm-data / farm-models / farm-scene / farm-app / vendor/three.min.js） |
| `utils/SearchToolIdentityUtils.ets` | `FARM_ENGLISH_TOOL_ID` + `isFarmEnglishFunctionName` + 加入 `isInteractiveQuizFunctionName` |
| `utils/FarmEnglishValidation.ets` | 新建：50 id 白名单 + focus 枚举 + `resolveFarmEnglishView` + `validateFarmEnglishArgs` |
| `entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets` + `List.test.ets` | 新建 hypium 用例（镜像 CityEnglishValidation.test）：合法/非法 focus、id 白名单、去重、上限 8、50 条无重复 |
| `config/BuiltinTools.ets` | import、`FarmEnglishArgs`、`FarmEnglishExecutor`、`createFarmEnglishToolDefinition`、`createFarmEnglishToolConfig`、register、`getBuiltinToolIds` |
| `services/ToolExecutionService.ets` | import、`handleFarmEnglish`（预校验 → pending → 回执）、dispatch、`recordLedgerServed` 的 `taughtOnly` 加入 `farm_english` |
| `models/AssistantModels.ets` | import、默认助手 + `KIDS_ENGLISH_LOCKED_TOOL_IDS` 白名单、默认助手提示词段 + 小星英语老师策略段 |
| `components/farm/FarmEnglishCard.ets` | 新建（按 §5） |
| `components/MessageBubble.ets` | import、`readFarmEnglishWords`、`onOpenFarmEnglishSheet` @Event、待答横幅、`shouldRenderFarmEnglishInteractionCard`、点击分支、`or` 链 ×2、step content + summary |
| `components/chat/ChatMessageListSection.ets` | `onOpenFarmEnglishSheet` @Event + 透传 |
| `pages/ChatPage.ets` | import、sheet 状态 / toolCall / answered、`onOpenFarmEnglishSheet`、`bindSheet` + `onDisappear` 取消回执、`FarmEnglishSheetBuilder` |
| `utils/ToolIconMapping.ets` | `FARM_KEYWORDS = ['farm_english']` |
| `utils/LedgerExtractUtils.ets` | `farmEnglishItems`（words 下划线转空格入账）+ dispatch + 讲解型跳过掌握度 |
| `components/kids/KidsSubjectCatalog.ets` | 英语学科 `activityTypes` 加 `farm_english`（与 room/city 一致；因不产生 star_event，对今日计数无实际影响，仅保持配置同步） |
| `.claude/rules/teaching-architecture.md` + `CLAUDE.md` | 工具表与导出说明补 `farm_english` |

**跳过**：`models/StarEventModels.ets`、`services/StarRewardService.ets`（不授星）。

## 7. 提示词

默认助手（小星老师）新增一段：

> 孩子学农场 / 动物 / 农作物 / 农机 / 自然类词汇（cow、wheat、tractor、barn、farmer…）时，先开 farm_english 走进 3D 阳光农场：用 words 传 3-8 个目标词；可用 focus 指定 overview / farmyard_zone / field_zone / pasture_zone / orchard_pond_zone。回执带 explored_count 与 words；讲解完立刻用 english_quiz(mode:"read_aloud") 复测 2-3 个目标词并授星（农场词不要用 picture_word）——farm_english 本身不授星。

小星英语老师「呈现」段新增 `②-3 农场词汇`，与 `②-2 城市词汇` 并列。

## 8. 验收清单

- [ ] 小星老师调用 `farm_english` → 对话出现「阳光农场 3D 英语探索 · 点击走进农场」横幅
- [ ] 点横幅打开全屏 sheet：3D 农场渲染，可拖动旋转 / 双指缩放 / 点物体
- [ ] 点奶牛 → 听到「奶牛」+「cow」，单词卡显示 cow / /kaʊ/ / 奶牛 / 儿童解释 / 例句
- [ ] 传 `words:["cow","wheat"]` → 直接选中 cow 并打开词卡
- [ ] 传 `focus:"field_zone"` 不传 words → 相机飞到田地区并打开 wheat 词卡
- [ ] 顶栏「词汇表」打开 Web 词汇表；🌙 切换黄昏，窗灯 / 萤火虫过渡
- [ ] **本次**探索 ≥1 个词后「我学会了」才可点（历史收集的词不算本次）；回执 `explored_count` / `words` 只含本次点开的词
- [ ] 直接关 sheet → 取消回执（`cancelled: true`）
- [ ] 非法 `focus` / 非法 word id / 9 个词 → `validation_failed` + `should_retry`，不出现卡片
- [ ] 讲解完成不产生星星事件（与 room/city 一致）
- [ ] 时间线回看显示本次点开的单词 chips
- [ ] `assembleHap` 编译通过

## 9. 验证方式

- `node --check` 4 个 JS（farm-data / farm-models / farm-scene / farm-app）+ `JSON.parse` 校验 `rawSchemaJson`。
- DevEco Studio 运行 `FarmEnglishValidation.test.ets`（CLI 的 `hvigorw test` 不可用，见 MEMORY）。
- `hvigorw assembleHap --mode module -p product=default -p buildMode=debug`。
- 真机 / 模拟器手点 §8 清单（ArkWeb WebGL 与 TTS 必须真机确认）。

## 10. 已定调用（builder 无需再问）

- 工具名 `farm_english`（与 `room_english` / `city_english` 同族命名）。
- 不授星、不进备课管线；挂默认助手 + 小星英语老师。
- 原生标题栏与 city 一致（词汇表 / 黄昏 / 我学会了），不改 Web 自带分区 tab。
- 数据 id / 分区 id 原样保留，不重命名。
- 回执 `words` = 本次会话点开的 id（非 AI 目标词、非历史累计）；`explored_count === words.length`。
- 「我学会了」门槛只看本次会话（`sessionIds`），历史 `discoveredIds` 只用于 Header「农场收集 N/50」。
- 台账只按 AI 目标词记曝光；自由探索的实际点击不回填（与 city 一致）。
- 儿童主屏「今日 N 题」不因 farm_english 变化（它只统计 star_events）；`KidsSubjectCatalog` 的条目仅为配置同步。
