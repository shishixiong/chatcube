# 3D 身体英语课（body_3d）设计

- 日期：2026-10-31
- 状态：已实现
- 参考原型：`open-design` 项目 `edaffe26-e901-4614-879f-21318c506981/xiaoxing-body-class.html`
  （小星英语 · 3D 身体课，React + three.js + framer-motion 单文件原型）
- 同类工具：`room_english`（全屋 3D 英语探索，讲解型）、`map_card`（中国地图小课堂，讲解型）

## 1. 背景与目标

5–7 岁孩子学英语身体部位时，最常见的问题是「词和自己的身体对不上」：
`head / eyes / nose / hands / knees / feet` 这些词只听发音很难建立意义。
原型用一只可旋转的低多边形小星，把 25 个部位做成可点击热点，点一下同时给出
英文、音标、中文、儿童化解释、单复数提示和发音，并配一张身体部位图。

本工具把这套体验搬进 Cube Chat：

1. AI 在对话里判断孩子要学身体部位，调用 `body_3d` 开课；
2. 气泡内出现紧凑横幅，点开全屏 3D 身体课；
3. 孩子拖动、点部位、跟读、看单词卡，进度自动记下；
4. 点「我学会了」把这次点开的部位回传给 AI，AI 接着出 `english_quiz` / `matching_pairs`
   检验并授星。

`body_3d` 是讲解型工具，本身不授星。这与 `room_english`、`map_card` 一致：
先呈现、再出题，星星留给真正作答的题型。

## 2. 非目标

- 不替代 `picture_vocab` / `english_quiz`：`body_3d` 只负责「看 + 听 + 认识」，
  不判对错、不记错题、不授星。
- 不做全身骨骼/器官科普：25 个部位都是幼儿英语词汇范围内的外部身体部位。
- 不依赖在线 CDN：three.js、数据、场景、样式全部打进 `rawfile`，离线可用。
- 不引入新的游戏 activity type：不新增 `StarEventModels` 活动类型。

## 3. 用户体验

### 3.1 入口与状态

| 状态 | 展示 |
|------|------|
| 待答 | 气泡内横幅「3D 身体英语课 / 点击和小星一起认识身体」→ 点开 LARGE bottom sheet |
| 作答中 | `Body3DCard`：顶部标题 + 已学会数量 +「我学会了」按钮，下面是 Web 3D 课 |
| 已答 | 时间线工具步骤可展开，展示这次点开的英文部位名；sheet 关闭 |

关闭 sheet 且未提交时，向 `handleAskUserAnswer` 回 `cancelled: true`，与 `room_english` 相同。

### 3.2 页面布局

桌面（≥980px）：

```
┌──────────────────────────────┬──────────────────┐
│ 拖动提示 / 本节重点           │ 单词表 | 部位图   │
│ ┌──────────┐                 │ 已学会 0/25       │
│ │ 单词卡    │   3D 小星        │ [head] [hair]... │
│ └──────────┘                 │ ...              │
│ 左转 挥手 右转        正面     │ 老师小提示        │
└──────────────────────────────┴──────────────────┘
```

移动端（<600px）：单词卡不再压在 3D 上，而是排在舞台下方（`position: static`），
避免遮住小星的头；单词表继续在页面下方滚动。

### 3.3 交互

- 拖动旋转（超过 5px 才算拖动，避免误触点击），松手有惯性；`左转 / 右转 / 正面` 按钮。
- 点击身体部位：选中 + 高亮 + 单词卡 + 原生 TTS 朗读英文两遍。
- 选中光环朝向相机（billboard），按部位取不同 z/半径，避免横成一条线或埋进身体。
- 三个呼吸指示点引导孩子发现可点区域；学会第一个部位后顶部提示自动淡出。
- 挥手按钮触发小星抬手动画，说话时嘴部开合。
- 单词卡：中文、英文、音标、儿童解释、单复数提示、`听一听`（再听一遍）、
  `已学会` 状态。关闭后舞台左上出现「打开单词卡」。
- 单词表按 Head(8) / Body(10) / Legs(4) / Whole(3) 分组，chip 显示已学会状态；
  本节重点词有暖色描边；顶部统计「已学会 / 25」「百分比」。
- 部位图：14 个代表部位的 pin 叠在 SVG 小人上，点 pin 选中并显示底部小卡；
  讲解「head 是头、hair 是头发」的对照。
- `localStorage` 持久化已学会与当前选中部位（同设备下次打开继续）。

## 4. 数据

### 4.1 25 个部位

| 分组 | 数量 | id |
|------|------|----|
| Head | 8 | `head hair face ear eye nose mouth teeth` |
| Body | 10 | `neck shoulder arm elbow hand finger thumb chest belly back` |
| Legs | 4 | `leg knee foot toe` |
| Whole | 3 | `body skin tummy` |

每个部位字段：

```js
{
  id: 'knee',            // 参数/进度用的稳定 id
  en: 'knees',           // 展示的英文（通常用复数，符合孩子指认两只的习惯）
  cn: '膝盖',
  ipa: '/niːz/',
  desc: '膝盖弯一弯，就能蹲下来。',
  kind: 'pair',          // single / pair / multi，决定单复数提示
  once: 'knee',          // pair 的单数形式，用于生成 note
  grp: 'leg'             // head / body / leg / whole
}
```

`body-data.js` 同时导出：

- `groups`：分组标题与说明；
- `guide`：3 个引导点在小星身上的位置；
- `hit`：点击兜底球（`{c:[x,y,z], r}`）；
- `mapLabels`：部位图上的 14 个 pin；
- `pluralCn()`：单复数提示文案；
- `groupOf(focus)`：`legs → leg`。

### 4.2 参数

```json
{
  "skill_key": "english_vocab",
  "focus": "head | body | legs | whole | all",
  "words": ["head", "eyes", "knees"]
}
```

- `skill_key` 必填且只能 `english_vocab`；
- `focus` 可选，默认 `all`；`legs` 在数据层映射为 `leg`；
- `words` 可选，最多 8 个，必须是上述 id；重复自动去重；
- 坏参数返回 `{ error: 'validation_failed', should_retry: true, message }`，
  AI 据此自行修正，不弹卡片。

### 4.3 完成回执

```json
{
  "completed": true,
  "explored_count": 5,
  "words": ["head", "eye", "knee"],
  "labels": ["head", "eyes", "knees"],
  "focus": "all",
  "skill_key": "english_vocab",
  "cancelled": false
}
```

`labels` 是给孩子看的时间线英文名；`words` 是给后续出题/账本用的稳定 id。
`readBody3DLabels()` 读不到 `labels` 时回退到 `words`。

## 5. 校验（`utils/Body3DValidation.ets`）

纯函数，无 ArkUI / rawfile 依赖，hypium 可直测：

- JSON 解析失败 → `body_3d 参数不是合法 JSON`
- 非对象 / 数组 → 必须是 JSON 对象
- `skill_key !== 'english_vocab'` → 固定传 `english_vocab`
- `focus` 非字符串或不在枚举 → 列出合法值
- `words` 非数组 / 超过 8 个 / 非字符串 / 未知 id → 报错并列出 25 个合法 id
- 合法时返回 `{ ok, focus, words }`，words 去重保序

`resolveBody3DFocusGroup(focus)` 负责 `legs → leg`。

## 6. 原生接入

| 层 | 文件 | 改动 |
|----|------|------|
| 注册 | `config/BuiltinTools.ets` | `body_3d` schema / config / executor / 注册 / `getBuiltinToolIds()` |
| 执行 | `services/ToolExecutionService.ets` | `handleBody3D` + 派发；pending 快照 `toolId = body_3d` |
| 身份 | `utils/SearchToolIdentityUtils.ets` | `BODY_3D_TOOL_ID`、`isBody3DFunctionName`（含 `3d_body` / `body3d` / `body_english` 别名）、加入 `isInteractiveQuizFunctionName` |
| 白名单 | `models/AssistantModels.ets` | import + `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` + 默认/小星英语提示词 |
| 卡片 | `components/body/Body3DCard.ets` | Web 容器、TTS、进度、提交 |
| 气泡 | `MessageBubble.ets` | 横幅、`Body3DStepContent` / `Body3DStepSummary`、可展开、事件 |
| 列表 | `chat/ChatMessageListSection.ets` | 事件透传 |
| 页面 | `pages/ChatPage.ets` | sheet 状态、builder、`onDisappear` 取消回执 |
| 图标 | `utils/ToolIconMapping.ets` | `BODY_KEYWORDS` → `sys.symbol.person_2` |
| 学科 | `components/kids/KidsSubjectCatalog.ets` | 英语 activityTypes 加 `body_3d` |

### 6.1 Web 与原生桥

页面加载：`Web({ src: 'resource://rawfile/body3d/index.html' })`，
`assets/` 相对路径由 ArkWeb 同源解析。ArkWeb 没有 `speechSynthesis`，
发音走 `javaScriptProxy`：

| 方向 | 方法 | 说明 |
|------|------|------|
| Web → 原生 | `speak(text, zh)` | `zh` 非空时先读中文再读英文；当前只传英文 |
| Web → 原生 | `stopSpeak()` | 页面隐藏/切词时停 |
| Web → 原生 | `onReady()` | 场景首帧完成，原生随后注入 focus |
| Web → 原生 | `onSelect(id, word)` | 点开新部位，原生记进度 |
| Web → 原生 | `onProgress(idsJson)` | 批量同步已学会 id |
| 原生 → Web | `BodyClassApp.setFocus(focus, words)` | 参数注入；words 首个自动选中并朗读 |
| 原生 → Web | `BodyClassApp.speechEnded()` | TTS 结束，复位嘴巴/播放态 |

TTS 语速 0.8，三个引擎通用范围 `[0.5, 2]`；`onComplete` 与 `onError` 都调用
`speechEnded`，避免 Web 侧一直显示「正在读」。

## 7. 3D 场景

`assets/body-scene.js` 是原型的 vanilla three.js 移植，不依赖 React/Babel：

- 程序化小星：头/头发/耳朵/眼睛/眉毛/鼻子/嘴/牙齿/舌头/腮红/脖子/围巾/园徽/
  身体/后背衣片/手臂/手/手指/腿/鞋，全部低多边形 `MeshStandardMaterial`；
- 相机按角色高度取景：`fov=26`，`LOOK=2.28`，`fitZ = max(zH, zW, 9.8)`；
  原型按像素宽算 `fitZ ≈ 1836`（far=100），会看不到模型，本实现改成角色高度；
- 平台、灯光、阴影、接触阴影；
- 选中光环：torus + ping + 半透明盘 + 径向渐变 sprite，全部 `lookAt(camera)`；
- 点击拾取：`MESH_PART` 前缀映射 → 部位 id；无效时用 `HIT` 球兜底；
- 呼吸、眨眼、挥手、嘴部开合、旋转惯性、拖拽阈值；
- WebGL 不可用时回调 `onError`，页面显示「3D 小星没有站起来」，单词表/TTS 仍可用。

## 8. 提示词

默认助手新增：

> 孩子学身体部位时，先开 `body_3d`；`focus` 选 `head / body / legs / whole`，
> `words` 传本次 3–5 个目标部位 id；讲完再出 `english_quiz` 或 `matching_pairs`
> 检验并授星——`body_3d` 本身不授星；一次课不超过 5 个新词。

小星英语老师的「呈现」步骤也补了 `body_3d` 分支。

## 9. 测试

- `entry/src/ohosTest/ets/test/utils/Body3DValidation.test.ets`：
  最小参数、focus、legs 映射、坏 JSON、错 skill_key、未知 focus、未知 id、
  超 8 词、去重、非字符串、25 个 id 覆盖、整体分组。
- 已注册到 `List.test.ets`。
- Web 侧用 Playwright 做本地冒烟：25 个 chip、14 个 pin、点击 `chest`、
  切部位图、`back` 转身、`setFocus('legs',['knee','foot'])`、桥协议
  `onReady/onSelect/onProgress/speak`、`speechEnded`。

## 10. 已知取舍

- 模样是「小星」而不是真人比例：头大、四肢短，5–7 岁更愿意点。
- 部位图 14 个 pin 在窄面板上仍可能拥挤；文字标签用小字号 + 左右错位，
  点 pin 后底部小卡显示完整信息。
- `localStorage` 是网页内进度，和原生学习账本独立；原生账本只记
  「点开了哪些部位」的完成回执。
- 单词默认用复数（eyes / knees / teeth），单词卡 note 说明单数形式；
  这是幼儿指认身体时的自然说法，也避免「一只眼睛」的歧义。
