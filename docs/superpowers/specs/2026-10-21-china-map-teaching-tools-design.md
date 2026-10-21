# 中国地图教学工具（map_card + map_quiz）设计文档

**日期：** 2026-10-21
**状态：** 待评审
**前置依据：** HTML 原型 `docs/map-learning/`（index.html / app.js / styles.css，已评审通过的产品形态）
**相关文档：** `.claude/rules/teaching-architecture.md`（§4 教学工具生态、讲解/练习二分）、`.claude/skills/adding-mini-game-tool/SKILL.md`（10 步配方）、`docs/brand-spec.md`

---

## 1. 意图与背景

为「小星语文老师」（`kids_chinese`）与小星老师（`default`）新增两个中国地图互动教学工具，让 6-7 岁孩子在聊天中认识 34 个省级行政区（名称、简称、行政中心、所在大区）：

- **`map_card`（讲解型）**：AI 在聊天中讲到地理话题时调出——全屏中国地图，孩子点省份看资料卡、听 TTS 朗读，学完点「我学会了 · 继续」提交回执。
- **`map_quiz`（练习型）**：AI 出一道地图题——三种题型（选一选 / 找一找 / 写一写），答对授星。

产品形态完全复刻 `docs/map-learning/` 原型（探索 + 闯关两视图已被用户确认拆为讲解/练习两个工具、跟着聊天节奏走），技术栈从浏览器（SVG DOM + hanzi-writer.js）移植为 ArkTS（Canvas 2D + 仓库既有笔画数据管线）。

**为什么放在语文老师名下**：省名/简称即识字与写字语料（写一写复用笔画数据），地理常识归入画像维度 `general_social`（常识-社会，已确认存在，不新增维度）。

## 2. 目标 / 非目标 / 反目标

**目标**
1. `map_card`：34 省可点击地图 + 省份资料卡（名称/简称/行政中心/大区）+ TTS 朗读 + 可选 `focus_province` 预高亮 + 缩放（找小省份）+ 南海诸岛 inset。
2. `map_quiz`：choice（4 选项选高亮省）/ locate（点地图找位置，可考行政中心）/ write（手写省名 + 描红 + 笔顺演示 + 自评）三题型，一次调用一道题，AI 控制节奏。
3. 全套 10 步配方集成（工具注册 → 分发 → 星星 → 锁定 → 卡片 → 气泡挂载 → 全屏 sheet），星星/画像/学科计数闭环。
4. 纯函数层（校验、选项生成、几何命中判定）可 hypium 单测。

**非目标（v1 明确不做）**
- 笔顺逐笔命中判定（原型的 hanzi-writer quiz 跟写体验）——v2 再做；v1 写字题 = 看逐笔动画 → 整字自由写 → 看答案自评。
- 独立入口页 / 儿童主屏新增学科卡（工具只在聊天中由 AI 调用）。
- 备课管线（LessonPlanningService）感知地图工具。
- 新增孩子画像技能维度（只复用 `general_social`）。
- 省份百科内容（特产/美食/历史）——数据表只有名称/简称/行政中心/大区，与原型一致。

**反目标（做了就算失败）**
- 让用户可编辑内置助手的地图工具白名单/提示词（锁定语义破坏）。
- 星星面板显示错标签（10 处漂移点漏改）。
- 手写题自动判分代替孩子自评（原型自评语义是产品决策）。
- 塞 192KB 省份路径进 .ets 源文件（必须 rawfile 运行时加载）。

## 3. 已确认的决策（用户拍板）

| 决策点 | 结论 |
|--------|------|
| 出场方式 | 聊天内卡片（讲解型 + 练习型，对齐 hanzi_card / chinese_quiz 二分） |
| map_quiz 题型 | choice / locate / write 三种全做 |
| 笔顺跟写逐笔判定 | v1 不做（看动画 + 自评） |
| 工具白名单 | kids_chinese + default 都锁 |
| 画像维度 | `general_social`（不新增维度） |

### 3.1 Builder check 后的定案（2026-10-21 第二轮）

builder 审查确认全部集成触点声明与代码一致，另产生 4 个问题，处理如下：

| 问题 | 结论 | 依据 |
|------|------|------|
| 语音朗读内容（choice 泄题口 / write 是否报名字） | 全部镜像原型 `speakQuestion` 语义：choice 只读通用导览句**绝不读答案省名**；locate 读 clue（capital 模式只读行政中心名）；write 只读「请把高亮省份的名字写下来」（回忆练习，不报名字）；map_card 自动朗读与资料卡 TTS 走 HanziCard 旁白接管语义（§12 详化） | 原型 app.js `speakQuestion` + HanziCard 先例 |
| locate+capital 自答省份（capital === short 的 6 个：北京/天津/上海/重庆/香港/澳门） | **校验层硬拒**：`clue:'capital'` 且目标省 `capital === short` → `should_retry`，错误文案提示 LLM 改用 `clue:'name'` | 原型 `capitalQuestion` 守卫原样移植 |
| 已答卡片的历史内联恢复 | 时间线展开时**内联渲染静态地图**（interactive=false，小尺寸）——只有待答的活地图才走「横幅 → 全屏 sheet」 | hanzi_card/maze 兄弟卡片先例（§9.4.7 的「不做内联地图」仅指待答态） |
| `general_social` 家长端标签「社交礼仪」与地理观察不符 | **显示层改名「社会常识」**（维度 key 不动）：`ChildProfileService.ets:61` 的 label + `LearningProfilePage.ets` 同名硬编码处，共 1-2 处字符串；LLM 侧 schema 描述不动 | 用户拍板 2026-10-21；与教学架构「常识-社会」本意对齐 |

## 4. 数据资产与管线

### 4.1 地图数据（新 rawfile）

`docs/map-learning/assets_china-provinces.js` 的 `window.CHINA_MAP` 转为 JSON：

- 落盘：`entry/src/main/resources/rawfile/map/china_provinces.json`（约 192KB）
- 顶层结构（已程序验证）：`{ viewBox: "0 0 1000 870", width: 1000, height: 870.2, provinces: [...], inset: { path, width, height } }`
- province 条目：`{ id("110000"), name("北京市"), short("北京"), abbr("京"), capital("北京"), region("华北"), path("M... L... Z...") }`，34 条
- **path 全部为 M/L/Z 纯多边形、Y-down、1000×870 坐标系**（无 Q/C 弧段）——Canvas 绘制与点内多边形命中判定都不需要曲线处理
- `inset` 是南海诸岛附图（独立小坐标系，右下角按 `width/height` 定位，绘制时 scale 0.75）

### 4.2 数据加载 util（新文件 `ets/utils/ChinaMapData.ets`）

- `export interface ChinaProvince / ChinaMapInset / ChinaMapData`（字段同 4.1）
- `export async function loadChinaMapData(context: common.UIAbilityContext): Promise<ChinaMapData | null>`——首次调用经 `context.resourceManager.getRawFileContentSync('map/china_provinces.json')`（先例 `RawfileImageSaveUtil.ets:68-75` 返回 Uint8Array；**context 必须由调用方组件传入，util 层拿不到 getContext()**）→ `util.TextDecoder` 解码 → `JSON.parse` → 模块级缓存；失败返回 null（调用方显示兜底文案，不 crash）
- `export function findProvinceByShort(name: string): ChinaProvince | null` 等查询函数（纯函数，可测）

### 4.3 笔画数据（扩展既有 `config/StrokeOrderData.ets`）

- 写一写/资料卡笔顺演示需要省名用字。34 省全部字段（short+name+abbr+capital）去重后共 114 字，其中 **101 字不在** `STROKE_ORDER_ENTRIES`（已核对清单）。
- 用 `.claude/skills/adding-stroke-order-data/gen_stroke_data.js` 批量生成（hanzi-writer-data CDN 已验证可拉通），一次性全部补入 Chinese 区段（`// === 大写字母 ===` 注释之前）。
- 注意 `chinese-character-strokes` CDN 间歇不可用：脚本可能输出 `??` 占位 label，必须逐字人工核对为横/竖/撇/捺/点/折后入库，不许留 `??`。
- 生成后 `node` 抽查若干字的 stroke 条数与汉字笔顺常识一致（如「疆」19 画）。

### 4.4 几何纯函数（新文件 `ets/utils/ChinaMapGeometry.ets`）

- `parseProvincePolygon(path: string): number[][]`——M/L/Z token 化 → 折线环数组（含多子路径 ZM… 拆分）
- `pointInProvince(path: string, x: number, y: number): boolean`——射线法，对 34 省 path 均有效（纯多边形）；与 Canvas 端 `ctx.fill('evenodd')` 奇偶规则一致（原型 path 渲染依赖 `fill-rule="evenodd"`，多子路径省份的洞/岛语义靠它）
- `provinceBBox(path: string): {minX, minY, maxX, maxY}`——点击粗筛 + 资料卡聚焦环计算
- 坐标换算：Canvas 触摸点 → 地图坐标系（`scale = canvasSize / 1000`，保持 1000:870.2 宽高比居中，含当前缩放/平移的逆变换）
- 全部纯函数（不含 Canvas 调用），hypium 覆盖：典型省内点 / 省外点 / inset 框 / 多子路径省（如广东含岛屿）/ 边界点容差

## 5. 工具定义（AI 侧契约）

### 5.1 `map_card`（讲解型）

**Schema**（rawSchemaJson 模板字符串，描述内引号一律「」，禁 ASCII `"`）：

```json
{
  "type": "object",
  "properties": {
    "focus_province": { "type": "string",
      "description": "可选。本次想重点讲的省级行政区常用名，如「山西」。传入后地图自动高亮并展示该省资料。不传则孩子自由探索。" },
    "skill_key": { "type": "string", "enum": ["general_social"],
      "description": "固定传 general_social（地理常识）。" }
  },
  "required": ["skill_key"]
}
```

**描述文本**（ToolFunction，英文首句 + 中文括注，`INSTEAD` 框架）：

> `Open the China map lesson card (中国地图小课堂): an interactive map of 34 province-level regions where the child taps provinces to learn names, abbreviations and capitals. Use this INSTEAD of describing geography in plain text. focus_province 是可选参数：当本节课围绕某个省（如讲到家乡、简称、地形）时传入该省常用名。有效省份名列表：北京 天津 河北 山西 内蒙古 辽宁 吉林 黑龙江 上海 江苏 浙江 安徽 福建 江西 山东 河南 湖北 湖南 广东 广西 海南 重庆 四川 贵州 云南 西藏 陕西 甘肃 青海 宁夏 新疆 台湾 香港 澳门。讲解完地图后可用 map_quiz 出题检验。`

### 5.2 `map_quiz`（练习型）

**Schema**：

```json
{
  "type": "object",
  "properties": {
    "mode": { "type": "string", "enum": ["choice", "locate", "write"],
      "description": "题型：choice=看高亮省份选名称（4 个选项，由卡片自动生成，不要自己传选项）；locate=按名称或行政中心在地图上点出该省；write=把高亮省份的名字手写下来（孩子自评）。" },
    "province": { "type": "string",
      "description": "目标省份常用名，如「黑龙江」，必须在有效省份列表内。" },
    "clue": { "type": "string", "enum": ["name", "capital"],
      "description": "仅 locate 有效：name=按省名找位置；capital=给行政中心找省份（如「行政中心是哈尔滨的是哪个省」）。choice/write 不要传。" },
    "skill_key": { "type": "string", "enum": ["general_social"],
      "description": "固定传 general_social。" }
  },
  "required": ["mode", "province", "skill_key"]
}
```

**描述文本**：`Present one China map question (中国地图出题) ... Use this INSTEAD of asking map questions in plain text. 每次调用只出一道题，由你在对话节奏中选择 mode。choice 的选项由卡片自动生成——⚠️ 严禁在参数中传选项数组。同一省份避免连续重复出同一 mode。⚠️ 严禁把答案直接写在题目文字里（locate+capital 模式题干只出现行政中心名）。有效省份名列表：（同 5.1）。`

**设计取舍：choice 选项由 App 端生成**（AI 只传目标省）——选项合法性由构造保证，消掉一整类校验失败面；选项生成纯函数复刻原型 `buildOptions` 策略：同大区取 2 + 任意取 1 + 正确项，洗牌。generateOptions 纯函数签名 `pickMapChoiceOptions(provinces: ChinaProvince[], targetId: string, rng: () => number): string[]`（rng 注入以便 hypium 定策测试；默认 `Math.random`）。

## 6. 校验（新文件 `ets/utils/MapToolValidation.ets`）

对齐 `HanziCardValidation.ets` 的 shape：`export interface MapToolValidationResult { ok: boolean; error: string }`，两个主函数：

- `validateMapCardArgs(args: string): MapToolValidationResult`——JSON.parse 守卫；`focus_province` 存在时必须命中 `findProvinceByShort` 或全名或 id（不命中 → error 文案列出有效名样例并提示修正）；`skill_key` 必须 `general_social`。
- `validateMapQuizArgs(args: string): MapToolValidationResult`——mode 枚举；province 必填且命中省份表；`clue` 仅 locate 可传且枚举合法；choice/write 传了 clue → fail；**locate + `clue:'capital'` 且 `province.capital === province.short`（北京/天津/上海/重庆/香港/澳门）→ fail，文案提示改用 `clue:'name'`**（自答题硬拒，原型守卫移植）；`skill_key` 校验同上。

失败文案写给 LLM 自行修正（中文、含错在哪 + 怎么改），调用方（ToolExecutionService）返回 `{error: 'validation_failed', message, should_retry: true}`。

## 7. 工具注册与分发（严格按 adding-mini-game-tool 10 步配方）

| 步骤 | 位置 | 内容 |
|------|------|------|
| 1 | `utils/SearchToolIdentityUtils.ets` | `MAP_CARD_TOOL_ID = 'map_card'` / `MAP_QUIZ_TOOL_ID = 'map_quiz'` 常量 + `isMapCardFunctionName()` / `isMapQuizFunctionName()`；**`isInteractiveQuizFunctionName`（:230-250）是否收录这两个 ID：镜像 hanzi_card / chinese_quiz 的成员资格**（builder 实读该函数确认 hanzi_card 在不在，在则同收录 map_card） |
| 2 | `config/BuiltinTools.ets` | 两个 `XxxArgs` interface + 两个 Executor（桩实现，兜底 JSON）+ 两个 `createXxxToolDefinition`（rawSchemaJson）+ 两个 `createXxxToolConfig`（中文名：`中国地图小课堂` / `中国地图出题`；icon 参照 §9）+ `registerBuiltinTools` 两个注册块 + `getBuiltinToolIds()` 追加。**完成后跑 JSON.parse gauntlet（node -e）** |
| 3 | `services/ToolExecutionService.ets` | 两个 handler 镜像 `handleHanziCard`（:1406-1495）/ `handleChineseQuiz`（:1709-1803）：元数据固化 → `validateMapXxxArgs`（失败 `approvalState='denied'` + should_retry 回执）→ pending 挂起（pendingAnswers + publishPendingInteractionChanged）→ 成功臂 `recordStarEvent('map_xxx', ...)` + `toolCall.approvalReason = answerJson`。**dispatch if 块插在 :2848 之后、`resolveToolId` 兜底（:2850）之前**。`map_quiz` 是否加 `runVocabRepeatGate`：**不加**（词级重复度门禁面向词汇题；地图题的查重靠提示词约束 + 省份表本身有限） |
| 4a | `models/StarEventModels.ets` | 两个新 activityType，10 处漂移点全改（见 §8），跑 4-grep gauntlet |
| 4b | `services/StarRewardService.ets` | `computeStars` 两个分支（见 §8） |
| 5 | `models/AssistantModels.ets` | import 两个 TOOL_ID；`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`（:108-132）追加；`KIDS_CHINESE_LOCKED_TOOL_IDS`（:168-172）追加；default 提示词语文段（:64 附近）+ 工具白名单句（:92）+ KIDS_CHINESE_SYSTEM_PROMPT 出题契约段（:363-371）各加地图段（见 §10） |
| 6 | 卡片组件（见 §9，新目录 `components/map/`） | build 通过 |
| 7 | `components/MessageBubble.ets` | 两个工具各 7 处挂载（见 §11），exact-line 检查 |
| 8 | `pages/ChatPage.ets` | 全屏 sheet（见 §9.4）——**Decision: YES**，地图 1000×870 在内联气泡不可用，两卡都走 MazeCard v3 模式 |
| 9 | PreferencesService / DatabaseService | **Decision: NO**——不存最佳成绩、不加记录表（星星事件 + 回执 payload 已够；原型 best 记录是独立 App 语义，聊天场景无对应 UI） |
| 10 | 全 gauntlet + assembleHap + 真机安装 | 全绿 |

**决策点 9 的理由展开**：原型 localStorage 存 `learned`（已认识省份集合）与 `best`（10 题最佳）。聊天场景下每次 `map_card` 是一节独立课、每次 `map_quiz` 是一道独立题，「已认识 34 省」的跨会话进度没有承载 UI（儿童主屏按天聚合星星，不按知识点）。故两者都不持久化；`map_card` 回执里的 `explored_count` 供 AI 画像用。

## 8. 星星系统（两个新 activityType）

### 8.1 StarEventModels.ets 10 处漂移点

新增 `'map_card'` 与 `'map_quiz'`（顺序排在 'chinese_quiz' / 'vertical_math' 附近，保持语文族聚合）：

| # | 位置 | map_card 值 | map_quiz 值 |
|---|------|------------|-------------|
| 1 | `StarActivityType` 联合（:10） | `'map_card'` | `'map_quiz'` |
| 2 | `TodayStarSummaryByType`（:39-58） | `map_card: StarTypeBucket` | `map_quiz: StarTypeBucket` |
| 3 | `createEmptyTodayStarSummary()`（:79-102） | `createEmptyBucket()` | 同 |
| 4 | `StarActivityMetaMap`（:112-132） | `map_card: StarActivityMeta` | 同 |
| 5 | `META_MAP_CARD`（:232 附近插入） | emoji `'🗺️'`，shortLabel `'地图'`，longLabel `'中国地图小课堂'`，grantedHint `'地图课学完'`，unit `'次'` | `META_MAP_QUIZ`：emoji `'🧭'`，shortLabel `'地图题'`，longLabel `'中国地图出题'`，grantedHint `'地图题答对'`，unit `'题'` |
| 6 | `metaRecord`（:268-288） | 两行 | |
| 7 | `activityTypes` 数组（:291） | 两个 | |
| 8 | `getBucketFromSummary`（:294-351） | 两个 if 分支（兜底前） | |
| 9 | `getActivityMeta`（:353-409） | 两个 if 分支（兜底 META_PUZZLE 前） | |
| 10 | `getActivitySymbol`（:415-471） | `$r('sys.symbol.map')`（MazeCard 横幅已用，确认存在） | 第二个符号 builder 从仓库已用符号里 grep 选定（候选 `sys.symbol.map` 复用或 lightbulb 族兜底；禁止臆造名字——sys.symbol 白名单红线） |

### 8.2 computeStars 分支（StarRewardService.ets，插在 chinese_quiz 分支 :221-225 后）

```ts
if (activityType === 'map_card') {
  // 中国地图小课堂 (讲解型): 完成探索提交即授星（hanzi_card 同款）
  const completed = payload['completed']
  return completed === true ? 1 : 0
}
if (activityType === 'map_quiz') {
  // 中国地图出题 (练习型): 答对授星，答错/自评未过 0
  const correct = payload['correct']
  return correct === true ? 1 : 0
}
```

### 8.3 学科计数

`components/kids/KidsSubjectCatalog.ets:87` 的 chinese 条目 `activityTypes` 数组追加 `'map_card', 'map_quiz'`——`countTodayBySubject`（hero 今日 N 题）与 `buildTodayCategoryRows`（星星明细）自动生效。「答对 N 题」文案对讲解型 map_card 的措辞误差与既有 `hanzi_card` 一致（先例在案，接受，不单独改 verb 逻辑）。

## 9. 组件设计（新目录 `ets/components/map/`）

### 9.1 `ChinaMapStage.ets`（可复用地图渲染器，@ComponentV2）

- **渲染**：Canvas 2D + 手写 M/L/Z 解析器（骨架复用 `HandwritingCard.drawSvgPath` :326-365，**不做 Y 翻转**——地图数据本就是 Y-down；`scale = min(w/1000, h/870.2)` 居中）。每个省：fill（选中/目标/正确/错误四态色，**`ctx.fill('evenodd')`**，多子路径省份的洞/岛语义依赖奇偶规则）+ 0.5-1px stroke 描边；inset 右下角 scale 0.75 绘制 + 底板。
- **手势**：单击 tap（含 pointInProvince 命中 → 回调 `onPickProvince(id)`）；拖拽平移 + 捏合缩放（1x-4x，约束在内容范围内）+ 外部按钮缩放（`+ / − / reset` 三键）。`hitTestBehavior` / `onTouch stopPropagation` 隔离聊天列表滚动（NumberPuzzleCard §6.3 先例）。缩放/平移状态经逆变换参与命中判定（§4.4）。
- **四态高亮 API**：`@Param targetId / selectedId / correctId / wrongId`（都是 string，空串表示无）+ `@Param interactive: boolean`。
- **性能**：34 省约 1.9 万个 path 点，整图绘制一次缓存为离屏（`CanvasRenderingContext2D` 全量重绘每帧仅在高亮/缩放变化时触发，绘制顺序 = 数据序，无需分层）。真机若卡顿，builder 可降级为「按 bbox 分层重绘」——先不做。
- 配色走 CardShell 系主题令牌 + `KIDS_CHINESE` 系强调色（与 chinese/ 卡片族一致；builder 实读 ChineseQuizCard bodies 的取色方式照搬）。默认填充用低饱和底色，四态用强调色系。

### 9.2 `MapCard.ets`（讲解型，CardShell 范式，镜像 HanziCard）

- **签名**：`@Param toolCall / isAnswered / answeredPayload / largeSize`，`@Event onAnswer`。**largeSize: YES**（全屏 sheet 专用，内联只渲染入口横幅）。
- **参数解析**：`parseMapCardArgs`（JSON.parse 守卫 + focus_province 解析），`valid: false` 兜底文案「这张地图出错了，老师马上换一张」。
- **结构**（CardShell 七区，`shellState.feedbackSuppressed = true`）：
  - head：`中国地图小课堂` + subtitle（focus 时 `今天认识「山西」` / 否则 `点一点省份，认识全中国`）
  - slot 主体：`ChinaMapStage`（selectedId = focus 或孩子当前点选）+ 省份资料卡（region 徽章 + 名称 + 简称印章 + 行政中心 + 🔊 TTS 朗读按钮，文案复刻原型 `province.name。简称X。行政中心Y。`）
  - focus 模式进入时资料卡自动展示 + TTS 自动朗读省名句（语音模式白名单见 §12）
  - actions：「我学会了 · 继续」——提交门槛 `canSubmit() = hasExplored`（点过 ≥1 个省或 focus 已展示），镜像 HanziCard 的 watched_strokes 门槛语义
- **回执 payload**：`{ completed: true, focus_province: string, explored_count: number, skill_key: 'general_social' }` → 1 星
- **isAnswered 恢复**：`JSON.parse(answeredPayload)` 读 completed → 显示「已完成」药丸 + 静态地图（interactive=false）
- **TTS**：资料卡朗读走 `TtsEngineRegistry` 既有通道（HanziCard 旁白 :366-417 范式），`aboutToDisappear` 停播

### 9.3 `MapQuizCard.ets`（练习型，薄路由 + 3 body，镜像 ChineseQuizCard）

- 薄路由：`parseChineseQuizModeArgs` 同款解析 mode → 分发 body；5 个 @Param/@Event 透传
- **`bodies/MapChoiceBody.ets`**：地图（interactive=false，targetId 高亮金色）+ 4 选项 2×2 网格（选项 = short 名，App 端 `pickMapChoiceOptions` 生成）；即判即交：点选 → 选项变绿/红 + 地图正确省绿色环 → payload `{ answered: true, mode: 'choice', province, child_answer, correct, skill_key }`
- **`bodies/MapLocateBody.ets`**：题干（name：`在地图上找到：山西` / capital：`行政中心是「太原」的是哪个省？`）+ 地图（interactive=true）；点击即判 → target/correct/wrong 三态环 + 反馈文案（复刻原型 `这里是山西，简称晋，行政中心在太原`）→ payload `{ answered: true, mode: 'locate', clue, province, child_answer, correct, skill_key }`
- **`bodies/MapWriteBody.ets`**：地图（target 高亮）+ 手写区：
  - 自由手写 Canvas（`onTouch` 采集 points，镜像 HandwritingCard :173-208 的 Down/Move/Up 三分支；**不**导出 base64——自评语义不需要图片回传，减一档数据面）
  - 「整字描红」toggle：Canvas 底层叠 ghost Text（省名 short，大号浅色）——原型 traceGuide 同款
  - 「笔顺演示」展开面板：short 名逐字显示——每字一张小 demo Canvas 播逐笔动画（HandwritingCard startPlayback/tick/redrawDemoCanvas 范式 :246-321）+ 笔画名列表（`getStrokeOrder()` 的 label 串）+ N 画计数；数据缺失字显示兜底 ghost Text（HandwritingCard 同款降级）
  - 「写好了，看答案」→ 展示参考答案（`name（short）· 简称 abbr`）→ 自评按钮「我写对了 / 再写一次 / 这次没写对，继续」→ payload `{ answered: true, mode: 'write', province, correct: <自评>, skill_key }`
  - 「擦掉重写」清空笔画
- 三 body 共用「已回答恢复」守卫：payload 缺失/不可解析 → `shellState.feedbackSuppressed = true` + 已回答药丸（ChineseChoiceBody :79-84 先例）；**恢复 payload 一律 `resolveStepAnswerPayload(step.toolResult, step.toolApprovalReason)`**（`utils/ChatMessagePartsHelper.ets:55-58`，toolResult 尾部会被追加带内指令，直接 JSON.parse(toolResult) 会静默失败）

### 9.4 ChatPage 全屏 sheet（MazeCard v3 模式 ×2）

两卡各自一套（镜像 showMazeSheet 的 7 个触点，不合并成一个泛化 sheet——遵循既有每工具一状态的先例）：

1. `@Local showMapCardSheet / mapCardToolCall / mapCardAnswered` + `showMapQuizSheet / mapQuizToolCall / mapQuizAnswered`（:313-315 附近）
2. MessageBubble `@Event onOpenMapCardSheet / onOpenMapQuizSheet`（:267-268 附近）
3. ChatMessageListSection 两个 `@Event` 透传（:58、:499-501 附近）
4. ChatPage 两个入口回调（:2533-2537 附近）
5. 两个 `bindSheet`（:2900-2932 附近，`SheetSize.LARGE + dragBar + showClose: true + preferType: BOTTOM`）；`onDisappear` 未答时回放弃 payload：map_card → `{completed: false}`，map_quiz → `{answered: false, correct: false, <mode>, province, cancelled: true}`
6. 两个 Sheet @Builder（:3419-3436 附近，`largeSize: true` + `onRequestClose` 事件关 sheet——MapCard/MapQuizCard 需带 `@Event onRequestClose`，镜像 MazeCard.ets:134）
7. 内联气泡（MessageBubble）只渲染紧凑入口横幅（32×32 徽章 + 标题 + 「点击打开中国地图」+ `>`，镜像 maze 横幅 :2167-2212），**不做内联地图**

## 10. 提示词（AssistantModels.ets）

- **default 小星老师**（:38-105）：`## 语文（六步识字）` 段后加 `## 中国地图` 段——何时开地图课（孩子问到省份/家乡/简称/行政中心，或今日计划含地理点时）、`map_card` 讲解要点（每课聚焦 ≤3 个省、focus_province 用法、讲完用 map_quiz 出 1-3 题检验）、出题契约（mode 选择节奏、choice 选项由卡片生成不要自己编、locate+capital 题干只给行政中心名）+ ⚠️ 严禁负例（严禁把「京」以外的答案拼进题干/严禁编造省份名——只允许有效列表内的名字）。
- **kids_chinese**（KIDS_CHINESE_SYSTEM_PROMPT :337-385）：`## 语文教学策略` 增补一步「⑦ 地图课」（map_card 用法），`## 出题契约` 段追加 map_card / map_quiz 逐工具约束（同上负例）。
- **child_profile 约束句**：两份提示词中说明地理观察写 `general_social` 维度（`child_profile(action:"update")` 只更新本学科维度——kids_chinese 既有约束已存在，补一句「省份/地理相关观察写 general_social」）。
- **SharedPromptFragments 复用检查**：改 `buildBasePrompt` 相关白名单文案前核对头注释列出的复用点（:49-64）；本次倾向不动 SharedPromptFragments（地图段是学科特有内容，进各自提示词数组）。

## 11. MessageBubble 挂载（每工具 7 处 + import，exact-line 检查）

以 `isMapCardFunctionName` 为例（`isMapQuizFunctionName` 同构追加）：

1. import（:31/:54 附近，卡组件 + 函数名检查）
2. 内联入口横幅渲染（ForEach 内 shouldRender 谓词命中 → 横幅 Row + onOpenMapCardSheet；~:2344 附近）
3. `isToolStepClickable` or 链（:2857 附近，`return this.isSuccessfulToolStep(part)` 同款）
4. `isToolStepExpanded` 默认展开 or 链（:2933 附近长 or 链尾部）
5. `toggleToolStep` 的 isDefaultExpanded or 链（:2943 附近）
6. `shouldRenderMapCardInteractionCard` 谓词（:3135-3140 同构）
7. `handleToolStepClick` switch（:3574 附近）+ 步骤内容路由 else-if（:4041 附近）+ `MapCardStepContent` @Builder（:4405-4458 同构，`isAnswered: true` + `answeredPayload: resolveStepAnswerPayload(...)`——历史展开时**内联渲染静态地图**（interactive=false 小尺寸），与 §9.2 恢复规格一致）

> 注意第 7 项包含 3 个物理位置（switch + 路由 + builder）——与 hanzi_card 的清点口径一致，共 9 个物理编辑点/工具。

## 12. 语音模式 TTS

`ChatPage.ets:4824+`：`tryAutoTtsForQuizInteraction` 白名单追加两个 TOOL_ID，**且必须在 `buildQuizTtsText`（:4873 附近）为两个工具各加分支**——白名单只放行，无分支则文本为空、静默（兄弟工具同款结构）。分支内容（镜像原型 `speakQuestion`，泄题口全堵）：

| 工具/mode | 朗读文本 |
|-----------|---------|
| map_card | focus 有值 → `我们来看「X」的地图课吧。`；无值 → `点一点地图上的省份，认识它们吧。` |
| map_quiz choice | 只读通用导览句 `看地图上金色的省份，选一选它的名字。`——**绝不读 province/答案**（语音模式孩子读不了屏，读答案即泄题） |
| map_quiz locate | clue=name → `在地图上找到X。`；clue=capital → `行政中心是「Y」的是哪个省？`（Y=行政中心名，非答案） |
| map_quiz write | 只读 `看地图上高亮的省份，把它的名字写下来。`——**不读省名**（回忆练习，与原型一致） |

map_card 卡内资料卡 TTS（§9.2）与上述自动朗读共存时，用 HanziCard 的旁白接管语义（自动朗读先播，卡内朗读由孩子点按钮触发，不叠加）。

## 13. 测试（hypium，`entry/src/ohosTest/ets/test/utils/`）

- `ChinaMapGeometry.test.ets`：parseProvincePolygon（单环/多环/Z 结尾/异常输入）、pointInProvince（山西内点、海外点、广东多子路径岛屿、bbox 外快速拒绝）、provinceBBox 边界
- `MapToolValidation.test.ets`：两工具合法/非法 args 全分支（坏 JSON、未知省份、mode 枚举越界、clue 误传、skill_key 错值）
- `MapChoiceOptions.test.ets`：注入 rng 定策——恰 4 个互异、含 target、同大区优先、target 不在干扰项
- `MapQuizValidation` 与星星分支：`computeStars` 两个新分支各 2 用例（completed/correct true/false）
- 组件层不写 ArkUI 测试（项目无基建，见 CLAUDE.md Tests 节）

## 14. 实施顺序（依赖序）

1. 数据先行：`china_provinces.json` 入 rawfile + `ChinaMapData.ets` / `ChinaMapGeometry.ets` + 101 字笔画数据入库（独立可测，不依赖任何集成点）
2. 纯函数层：MapToolValidation + pickMapChoiceOptions + hypium
3. 工具层：配方步骤 1-5（ID → 注册 → 分发 → 星星 → 锁定/提示词）——此时无 UI，AI 可调用但走兜底
4. 组件层：ChinaMapStage → MapCard → MapQuizCard 三 body（配方步骤 6）
5. 集成层：MessageBubble 14 处 + ChatPage 两个 sheet + TTS 白名单/buildQuizTtsText 分支（配方步骤 7-8）
6. 顺手项：`general_social` 显示标签「社交礼仪」→「社会常识」（`ChildProfileService.ets:61` + `LearningProfilePage.ets` 硬编码处，仅字符串；维度 key 与 LLM 侧 schema 不动）
7. gauntlet 全跑 + assembleHap + 真机验证清单（§15）

## 15. 验收清单

- [ ] AI 调 `map_card` → 横幅 → 点开全屏地图，34 省可点、资料卡/TTS 正常、focus_province 高亮生效
- [ ] AI 调 `map_quiz` 三 mode 各一题：choice 选项正确生成且答对得星；locate 点对/点错显示三态环；write 手写/描红/笔顺演示/自评链路通
- [ ] 星星面板两个新条目标签/emoji/符号正确（不是 MAP_PUZZLE 兜底）
- [ ] 语文科「今日 N 题」计数包含两类新事件
- [ ] 会话切走/停止：放弃回执正确（cancelled），无悬挂 pending
- [ ] 历史会话回看：已答卡片经 resolveStepAnswerPayload 恢复，无「再试一次」假象
- [ ] 语音模式下两工具自动朗读（choice 不泄答案省名；write 不报名字；buildQuizTtsText 有分支非静默）
- [ ] 家长画像页 `general_social` 显示为「社会常识」，地图课观察落该维度
- [ ] 小星老师（default）与小星语文老师会话均能触发；其它学科助手工具列表无此二工具
- [ ] 4-grep gauntlet / JSON.parse gauntlet / exact-line MessageBubble 检查全绿
- [ ] 真机安装验证（不只是 assembleHap 绿）

## 16. 开放风险

| 风险 | 缓解 |
|------|------|
| 34 省 Canvas 全量重绘在低端机卡顿 | 绘制按需触发 + §9.1 降级预案；真机验收把关 |
| `chinese-character-strokes` CDN 拉不到 → label 占位 | 人工核对 101 字 label；该 CDN 只影响笔画名不影响 path 数据源 |
| 触摸命中在 inset 缩放区误判 | inset 区不参与命中（原型 inset aria-hidden 同款）；pointInProvince 只查 34 省 path |
| AI 编造省份名/把答案写进题干 | schema 描述列全 34 名 + ⚠️ 负例 + validateMapQuizArgs 硬校验 should_retry 兜底 |
