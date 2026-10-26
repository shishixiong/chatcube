# 中国地图拼图（map_puzzle）设计文档

**日期：** 2026-10-26
**状态：** 待评审
**前置依据：** `2026-10-21-china-map-teaching-tools-design.md`（地图数据/几何/校验/星星管线）、`2026-10-23-map-card-atlas-redesign.md`（纸质地图册皮肤）
**相关文档：** `.claude/skills/adding-mini-game-tool/SKILL.md`（10 步配方，本工具必须全走）、`.claude/rules/teaching-architecture.md`（讲解/练习二分）

---

## 1. 意图与背景

`map_card` 解决的是「**认名字**」：点省 → 看资料卡 → 听读音。`map_quiz` 解决的是「**检验**」。
但 6-7 岁孩子记地理，最先记住的其实是**形状和位置**——「像一只靴子的那个是哪个省」「这块该放在这里」。
这两个工具都没有用手去「拼」，孩子看十遍地图不如自己拼一遍。

`map_puzzle`（拼一拼）补上这一段：**把省份从地图上拆下来，让孩子拖回去**。

- 刚讲过某个大区（比如华北五省）→ 立刻拼一拼，把「听过」变成「拼过」。
- 拼对了 TTS 报「山西，简称晋，行政中心太原」——**拼一次等于复习一遍资料卡**。
- 拼完接 `map_quiz` 复检，形成「讲 → 拼 → 考」的完整闭环。

复用现有全部资产：34 省 path（`rawfile/map/china_provinces.json`）、几何纯函数（`ChinaMapGeometry`）、
地图册皮肤（`MapAtlasTokens`）、星星/画像（`general_social`）。

## 2. 目标 / 非目标 / 反目标

**目标**
1. 一局 3-8 块（按大区自动组卷，或 AI 指定省份），棋盘自动**聚焦到本局省份的并集区域**（小省也放得大）。
2. 拖拽放置 + 「轻点碎片 → 点地图」双通道（低龄/手抖孩子也能完成）。
3. 落对即时吸附 + 印章 + TTS 复述「省名/简称/行政中心」；落错回弹、计数、不泄露答案位置。
4. 提示：长按碎片 → 目标轮廓闪烁；计入 `hints`（不影响上限，只进回执）。
5. 星星按错误次数评 3/2/1；完成回执写入会话时间线（内联静态完成卡）。
6. 纯函数层（视图拟合、碎片布局、落点解算、参数校验）全部 hypium 可测。

**非目标（v1 明确不做）**
- 全国 34 块一局（屏幕放不下、孩子挫败感强）——v1 最大 8 块，全国拼图留 v2 作为「挑战模式」。
- 碎片旋转（`rotate` 手势与拖拽冲突，且不增加地理价值）。
- 计时排名 / 跨局最佳成绩（`PreferencesService` 不新增键）。
- 拼图过程录像回放。
- 新地图数据（世界/家乡）——属于「地图舞台泛化」那条线，不在本 spec。
- 缩放控件（棋盘已自动聚焦，再给缩放会让孩子更迷糊）。

**反目标（做了就算失败）**
- 允许把碎片拖到**错误的省份但判定为对**（命中判定必须用目标省自身多边形 + 边界距离，不能用最近省份）。
- 拼对后不朗读——那就退化成「贴纸游戏」，失去教学价值。
- 星星标签显示成「数字华容道」/「地图题」（StarEventModels 10 处漂移点漏改）。
- 用第三方拖拽库或 WebView 实现棋盘（ArkTS 原生 + Canvas，与 `ChinaMapStage` 同源）。
- 把 192KB 省份路径内联进 .ets。

## 3. 已确认与默认决策

| 决策点 | 结论 | 依据 |
|--------|------|------|
| 工具名 / ID | `map_puzzle` / `MAP_PUZZLE_TOOL_ID` | 与 `map_card`/`map_quiz` 命名一致 |
| 类型 | 练习型（动手），**授星** | 有对错、可重玩，同 `map_quiz` |
| 出题规模 | 3-8 块 | 大区数据天然 3-8：东北 3、华中 3、华北/华南/西南/西北 5、华东 8 |
| 视角 | 自动聚焦本局省份并集 bbox | 东北 3 省若按全国比例只有屏幕 1/8，太小 |
| 拖拽 vs 点击 | **两条都做**，共用同一判定 | 6 岁孩子拖拽命中率低，点击是兜底 |
| 失败提示 | 只说「再找找看」，不给位置 | 否则变成找茬游戏 |
| 星星 | 0-1 错 3 星 / 2-3 错 2 星 / ≥4 错 1 星；未完成 0 | 镜像 `maze` 的「表现型」而非难度型 |
| 画像维度 | `general_social`（不新增） | 与 `map_card`/`map_quiz` 一致 |
| 白名单 | `default` + `kids_chinese` 都锁 | 同地图家族 |
| 语音模式 | 拼对/拼错/完成都走 TTS（与 `map_card` 自动朗读同款） | 孩子拼图时眼睛在棋盘上 |

> 待用户确认的只有一条：**是否给「完成但错误 ≥4 次」也发 1 星**（默认发，符合「完成即有奖励」的既有口径）。

## 4. 玩法设计

### 4.1 一局的结构

```
表头   地理 · 拼一拼                  [已拼 2/5]
棋盘卡 华北 · 5 块 · 错 1 次
       ┌──────────────────────────┐
       │      目标省份淡色轮廓      │  ← 自动聚焦本局并集
       │   （已放省份填实色）        │
       └──────────────────────────┘
       提示：拖动碎片，或点碎片再点地图
托盘   [🧩][🧩][🧩][🧩][🧩]        ← 未放置的碎片
页脚   已拼 2/5 · 用时 0:42    [重新开始]
```

- **大区模式**（`mode: 'district'`）：AI 传 `region`，卡片从 34 省里筛出该区全部省份。
- **自定义模式**（`mode: 'custom'`）：AI 传 2-8 个省名，适合「刚讲过的三个省」。
- 一局结束（全部放对）→ 棋盘盖「拼好啦」印章 + 成绩行 + 「回聊天」按钮。

### 4.2 棋盘

| 项 | 规则 |
|---|---|
| 视图 | `fitViewport(unionBBox(本局省份), boardW, boardH, padding=26vp)` |
| 背景 | 地图册纸张网格（复用 `MapAtlasTokens.water/grid`），与 `ChinaMapStage` 视觉连续 |
| 未放省份 | 描边用 `line` 虚线 + 填充 `land` 8%——是「凹槽」，不是答案提示 |
| 已放省份 | 填充 `visited`→落定后 `land` 实色 + `line` 实线 1vp |
| 落定瞬间 | 该省 `selected` 闪一帧（`animateTo` 180ms）后转实色 |
| 提示高亮 | `hintId` 对应的凹槽描边透明度 0.3→1 呼吸 3 次 |
| 印章 | 全部完成后右下角盖「拼好啦」印章（旋转 -6°，复用 `MapCard` 印章语言） |

**各大区实测**（340×300 棋盘、padding 26 下的自动缩放比，2026-10-26 用现有数据算得）：

| 大区 | 块数 | 拟合缩放 | 山西级容差 | 说明 |
|---|---|---|---|---|
| 华中 | 3 | 0.95 | 38.5vp | 最舒展 |
| 华南 | 5 | 1.12 | 45.4vp | 含港澳，靠 14vp 地板兜底 |
| 东北 | 3 | 0.76 | 30.9vp | |
| 华东 | 8 | 0.69 | 28.0vp | 块数最多，托盘两行 |
| 华北 | 5 | 0.58 | 23.6vp | 内蒙古把 bbox 拉宽 |
| 西南 | 5 | 0.50 | 20.4vp | 西藏把 bbox 拉大 |
| 西北 | 5 | 0.46 | 18.8vp | 新疆把 bbox 拉大 |

> 结论：西北/西南虽然只有 5 块，但新疆（bbox 623 单位）、西藏（574）把缩放压到 0.46-0.50，
> 同区小省被连带压小（宁夏在西北视图只有 26×43vp，香港在华南视图 12×10vp）。
> 提示词里建议**先拼华中/华北/东北**，西北、西南放后面；港澳靠托盘碎片（固定 56vp）识别，不靠凹槽。

### 4.3 碎片托盘

- 每块碎片 = 56×56 的 Canvas + 阴影 + 1vp 描边；形状按自身 bbox **等比放大填满 56**（澳门、香港也看得清）。
- 布局：不做横向滚动，按 4 个/行 wrap（8 块 = 2 行），托盘高度随行数 96 / 152vp。
- 不显示省名（显示就变成「对字」而不是「对形状」）；长按提示兜底。

### 4.4 放置与判定

**拖拽**：碎片 `onTouch` 跟手（`baseX + touch.x - grabDX`），拖起时 `scale 1.06` + 阴影加深；
松手时以**碎片中心**作为落点。

**轻点**：点碎片 → 选中态（上浮 2vp、描边加粗）；再点棋盘 → 以点击点为落点。

**判定顺序**（纯函数 `resolveDrop`）：

1. 落点换算到地图坐标（`screenToMap`）。
2. `pointInProvince(目标省 path, 落点)` → **正确**。
3. 落点明确落在**同局别的省份**里 → **错误**（`occupied`）。容差只服务于「指头粗」和
   「小省 / 海岸线」，不能拿来把「丢在邻省身上」判对：0.58 缩放下天津在屏幕上只有 8vp 宽，
   14vp 容差环会把整个北京盖住——2026-10-26 用真实数据跑 7 个大区 148 组「丢到另一省最深处」，
   不加这一步有 **27 组误判**（京津、沪苏、川渝、粤港澳…），加上只剩 2 组。
4. 落点在空白/水域：到目标省**边界**距离 ≤ `14vp / 当前缩放比` → **正确**（`tolerance`）。
   - 14vp ≈ 2.2mm，就是「离省界一个指头缝」；同一个 14vp 在同一块棋盘的任何区域都一致，
     不需要按大区调参（华北视图 ≈ 24 地图单位、华南视图 ≈ 12.5 地图单位）。
   - 用**边界距离**而不是「到质心的距离」：面积质心对甘肃这种月牙形会落到省外
     （2026-10-26 用真实 34 省数据验证，唯一一个质心在省外的就是甘肃，距自身边界 3.4），
     容差圆会跑到邻省；边界距离对所有形状都成立。
   - 边界距离同时天然解决了 tiny 省（澳门 bbox 1.5×2.3）：只要落在它界外的海面一个指头缝内就算对
     （实测澳门向 8 个方向 ×2/4/6vp，海侧方向全部判对；陆地侧判错是对的，那是广东）。
5. 其余 → **错误**（`miss`）。

> 只对「碎片自己的省份」做判定，绝不会因为落在别的省上就算对。
> 反例守护：山西碎片丢到河北质心（距山西边界 25.8）必须判错——这条写进了单测。

**反馈**：

| 结果 | 表现 | 计数 | TTS |
|---|---|---|---|
| 正确 | 吸附动画（180ms）→ 印章闪 → 凹槽变实色 | `placed++` | `${name}，简称${abbr}，行政中心${capital}。` |
| 错误 | 回弹到托盘（180ms）+ 棋盘左右抖 2 次（±3vp） | `mistakes++` | `再找找看，${short}在哪儿呢？` |
| 提示 | 目标凹槽呼吸 3 次 | `hints++` | `${short}在这附近，看这里。` |

**完成**：全部 `placed` → 停止计时 → 印章 + 成绩 + 星星 → 回执。

### 4.5 星星

```ts
// MapPuzzleCard 内计算，写入 payload.stars（镜像 MazeCard）
stars = completed ? (mistakes <= 1 ? 3 : mistakes <= 3 ? 2 : 1) : 0
// StarRewardService.computeStars 读取并 clamp 1..3
```

### 4.6 视觉

完全沿用 `2026-10-23-map-card-atlas-redesign.md` 的地图册皮肤：`getMapAtlasPalette(isDarkMode)`、
`schema` 同上、卡片圆角 22/16、页脚 54vp 主按钮。**不新增配色令牌**。

## 5. 数据与纯函数层

### 5.1 数据（无新增 rawfile）

复用 `ChinaMapData.loadChinaMapData()` 的 34 省；大区筛选走 `ChinaProvince.region`（七值：华北 5 / 东北 3 / 华东 8 / 华中 3 / 华南 5 / 西南 5 / 西北 5）。

### 5.2 `utils/ChinaMapTransform.ets`（新）

```ts
export interface MapPoint { x: number; y: number }
export interface MapTransform { scale: number; offsetX: number; offsetY: number }

/** 让 bbox 区域等比填满视口（四周留 padding）并居中；直接吃地图坐标，调用方不用再减 bbox 原点 */
export function createFitTransform(bbox: MapBBox, viewW: number, viewH: number,
  padding: number): MapTransform
export function mapToScreen(t: MapTransform, x: number, y: number): MapPoint
export function screenToMap(t: MapTransform, x: number, y: number): MapPoint
/** vp 长度 → 地图单位（容差换算） */
export function screenLengthToMap(t: MapTransform, vp: number): number
```

> `ChinaMapStage` **本次不改**（它有自己的 zoom/pan 变换，重构风险大于收益）；本 util 只服务拼图，
> v2 做「世界地图泛化」时再把两处合并。

### 5.3 `utils/ChinaMapGeometry.ets`（扩展）

```ts
/** 点到省份边界的最短距离（地图单位）；点在省内返回 0 */
export function provinceEdgeDistance(path: string, x: number, y: number): number
```

为什么既不用 bbox 中心也不用面积质心（2026-10-26 用 node 跑真实 34 省数据得出）：

| 方案 | 问题 |
|---|---|
| bbox 中心 | 甘肃、内蒙古的 bbox 中心直接落在省外 |
| 面积质心 | **甘肃的质心也落在省外**（距自身边界 3.4；34 省里唯一一个），容差圆会覆盖邻省 |
| 边界距离 | 对所有形状成立，语义直白（「离省界多近」），单一阈值即可覆盖大省与澳门 |

实现为「点是否在省内 → 0；否则遍历全部环求点到线段最短距离」。34 省约 4000 段，
只在松手那一下算一次，耗时 < 1ms。

### 5.4 `utils/MapPuzzleLayout.ets`（新）

```ts
export interface PuzzleSlot { x: number; y: number }
export interface PuzzleDropResult { correct: boolean; reason: string }  // hit | tolerance | occupied | miss

export const PUZZLE_FIT_PADDING: number = 26        // 棋盘四周留白（vp）
export const PUZZLE_DROP_TOLERANCE_VP: number = 14  // 落点容差（vp）

export function unionBBox(provinces: ChinaProvince[]): MapBBox
export function computePuzzleTransform(provinces: ChinaProvince[],
  boardW: number, boardH: number): MapTransform      // = createFitTransform(unionBBox, padding 26)
export function layoutTray(count: number, perRow: number,
  slot: number, gap: number, padX: number, padY: number): PuzzleSlot[]
export function trayRows(count: number, perRow: number): number   // 卡片算托盘高度
export function resolveDrop(province: ChinaProvince, siblings: ChinaProvince[],
  t: MapTransform, dropX: number, dropY: number): PuzzleDropResult
// siblings = 本局全部省份（含自己）：用来判「是不是丢在别省身上了」
```

`PuzzleSlot` 只带 x/y，id 由调用方按 targets 顺序对齐——省掉一次字符串比较，也让托盘布局可以脱离省份数据单测。

## 6. 工具契约（AI 侧）

```json
{
  "type": "object",
  "properties": {
    "mode": { "type": "string", "enum": ["district", "custom"],
              "description": "district=按大区组卷（推荐）；custom=指定 2-8 个省" },
    "region": { "type": "string",
                "enum": ["华北", "东北", "华东", "华中", "华南", "西南", "西北"],
                "description": "mode=district 时必填，如「华北」" },
    "provinces": { "type": "array", "items": { "type": "string" },
                   "description": "mode=custom 时必填，2-8 个省名，如「山西」「广东」" },
    "skill_key": { "type": "string", "enum": ["general_social"],
                   "description": "固定传 general_social（地理常识）。" }
  },
  "required": ["mode", "skill_key"]
}
```

工具描述（`ToolFunction` 的 description）要点：
- 「让孩子拖拽拼回省份，练形状与位置记忆；一次 3-8 块」
- 「刚讲完某个大区就用 district 拼该区；只讲了两三个省就用 custom」
- 「⚠️ 严禁编造省份名，只能从 34 省列表里选」
- 34 省名列表（与 `map_card` 同一串，避免 LLM 造名）

## 7. 校验（`utils/MapPuzzleValidation.ets`）

| 规则 | 失败文案（回给 LLM 的 `should_retry`） |
|---|---|
| `skill_key === 'general_social'` | `map_puzzle 的 skill_key 必须固定传 general_social（地理常识），收到「X」` |
| `mode ∈ {district, custom}` | `map_puzzle 的 mode 只能是 district 或 custom，收到「X」` |
| district：`region ∈ 七大区` | `map_puzzle 的 region 必须是 华北/东北/华东/华中/华南/西南/西北 之一` |
| district：该区省份数 ≥ 3 | `「X」大区的省份不足 3 个，请改用 custom 指定省份` |
| custom：`provinces` 数组 2-8 项 | `map_puzzle 的 provinces 需要 2-8 个省名，收到 N 个` |
| custom：每项 `findProvinceByRef` 命中 | `「X」不是有效的省份名（34 省列表见工具描述）` |
| custom：去重后 ≥ 2 | `map_puzzle 的 provinces 有重复项，去重后不足 2 个省` |
| 数据未就绪 | `map_puzzle 地图数据未就绪, 请稍后重试` |

## 8. 集成（严格按 10 步配方）

### 8.1 星星：新增 `map_puzzle` activityType

10 处漂移点全改（`StarEventModels.ets`），新增常量：

```ts
const META_MAP_PUZZLE: StarActivityMeta = {
  emoji: '🧩', shortLabel: '拼图', longLabel: '中国地图拼图',
  grantedHint: '拼完地图', unit: '局'
}
```

`getActivitySymbol` 用 `sys.symbol.puzzle`（已确认存在于 `sysResource.js`）。
`StarRewardService.computeStars` 分支（插在 `map_quiz` 分支后）：

```ts
if (activityType === 'map_puzzle') {
  const completed = payload['completed']
  if (completed !== true) { return 0 }
  const rating = (payload['stars'] as number) ?? 1
  return Math.min(3, Math.max(1, rating))
}
```

### 8.2 分发

`ToolExecutionService.handleMapPuzzle`（镜像 `handleMapQuiz`）：
校验前置 → `recordLedgerServed('map_puzzle', ...)` → pending → 回执回来 `recordStarEvent('map_puzzle', ...)`。
分发分支必须放在 `resolveToolId` 兜底**之前**。

## 9. 组件设计

### 9.1 `components/map/MapPuzzleBoard.ets`（新，纯画板）

```ts
@Param data: ChinaMapData | null
@Param targets: ChinaProvince[]        // 本局全部省份
@Param placedIds: string[]             // 已放对
@Param hintId: string                  // 呼吸高亮的省
@Param completed: boolean
@Event onBoardTap: (boardX: number, boardY: number) => void
```

- Canvas 绘制：网格底 → 未放凹槽（虚线+8% 填充）→ 已放实色 → 提示呼吸 → 完成印章。
- `onAreaChange` 记录尺寸 → 重算 `MapTransform`；`onTouch` Up 判定 tap（复用 `ChinaMapStage` 的 12vp/350ms 自制 tap）。
- 不持有游戏状态，不改数据；只负责画和报点。

### 9.2 `components/map/MapPuzzleCard.ets`（新，状态机 + 托盘 + 拖拽）

```
@Param toolCall / isAnswered / answeredPayload / largeSize
@Event onAnswer / onRequestClose

@Local data / targets / placedIds / mistakes / hints / elapsedSeconds
@Local dragId / dragX / dragY / selectedId / hintId / completed / submitting
```

- 大尺寸（sheet）：表头 + `MapPuzzleBoard` + 托盘（`Stack` + 绝对定位碎片，拖拽层同 Stack）+ 页脚。
- 小尺寸（时间线已答）：静态缩略板（height 180）+ 成绩行 + 省份 chips。
- 计时：`setInterval 1s`，`aboutToDisappear` 清理（镜像 `MazeCard`）。
- TTS 走 `ServiceRegistry.tts()`，连续操作时用序号守卫旧回调（镜像 `MapCard.speakSeq`）。
- 提交：全部放对 → `onAnswer(toolCall.id, JSON.stringify(buildResult(true)))`，只提交一次（`submitted` 守卫）。

### 9.3 全屏 sheet

`ChatPage` 增 `showMapPuzzleSheet` / `mapPuzzleSheetToolCall` / `mapPuzzleAnswered`，
`bindSheet(height: SheetSize.LARGE, dragBar: true, showClose: true)`，镜像 `MapCardSheetBuilder`。

**取消回执由 ChatPage 发**（卡片在 sheet 里拿不到「被关掉」的时机）：`onDisappear` 且未答时回
`{ completed:false, cancelled:true, mode:'', region:'', total:0, placed:0, mistakes:0, hints:0,
time_seconds:0, stars:0, provinces:[], skill_key:'general_social' }`。
内联复原把 `cancelled===true` 渲染成「这一局没拼完」灰态卡，不显示成绩与星星。

### 9.4 气泡横幅

`MessageBubble` 加 `shouldRenderMapPuzzleInteractionCard` + 课卡式横幅（复用地图入口卡的视觉，
文案「拼图课 · 把省份拼回家」，图标 `sys.symbol.puzzle`）。

## 10. 提示词（`AssistantModels.ets`）

追加一段：

> `## 中国地图拼图` 孩子刚学完某片区域、需要动手记形状和位置时，用 `map_puzzle` 开一局拼图：
> `mode:'district'` 传刚讲过的大区（华北/东北/华东/华中/华南/西南/西北），只讲了两三个省就
> `mode:'custom'` 传那两三个省名。一局 3-8 块，别贪多；拼完用 `map_quiz` 复检一题。
> ⚠️ 严禁编造省份名。地理观察写 `general_social` 维度。

`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 追加 `MAP_PUZZLE_TOOL_ID`。

## 11. TTS 文案

| 时机 | 文案 |
|---|---|
| 拼对 | `${name}，简称${abbr}，行政中心${capital}。` |
| 拼错 | `再找找看，${short}在哪儿呢？` |
| 提示 | `${short}在这附近，看这里。` |
| 开局 | `我们来拼${region}的 ${n} 个地方，拖动碎片放到地图上。` |
| 完成 | `都拼好啦！你认识了 ${n} 个地方。` |

## 12. 测试（hypium）

| 文件 | 断言重点 |
|---|---|
| `ChinaMapGeometry.test.ets`（追加） | 省内点=0；外点=到最近边距离；L 形凹口 =10；真实山西：省内质心=0、河北质心 25.8 |
| `ChinaMapTransform.test.ets`（新） | 等比不变形、居中、padding 生效；`screenToMap(mapToScreen(p)) ≈ p` 往返；退化 bbox 回 identity、scale=0 不出 NaN |
| `MapPuzzleLayout.test.ets`（新） | 并集 bbox 正确；托盘 4/行 wrap 的 x/y；`resolveDrop` 命中自己=对、命中邻省=错（山西↔河北反例 + `occupied` 优先级用例）、空白处容差内=对、容差外=错；tiny 省（澳门尺度）海侧容差可放；容差随缩放联动 |
| `MapPuzzleValidation.test.ets`（新） | 七条规则逐条；`provinces` 重复/超 8/未知名；`region` 非法 |

CLI 侧唯一边界是 `assembleHap` 绿；hypium 在 DevEco 里跑（`hvigorw test` 在本仓库不可用）。

## 13. 实施顺序（依赖序）

1. 几何/变换/布局/校验 4 个纯函数层 + 测试（无 UI，先把算法钉死）
2. 10 步配方：ID → BuiltinTools → ToolExecutionService → StarEventModels → StarRewardService → AssistantModels
3. `MapPuzzleBoard` → `MapPuzzleCard` → `MessageBubble` 横幅 → `ChatPage` sheet
4. 真机走查 + 验收

## 14. 验收清单

- [ ] 华北（5 块）从横幅进 sheet，棋盘聚焦华北，碎片可拖可点
- [ ] 拖回正确省份 → 吸附 + TTS 报「省名/简称/省会」；拖错 → 回弹 + 抖动 + 不泄露位置
- [ ] 长按碎片 → 目标凹槽呼吸 3 次，`hints` 计数 +1
- [ ] 澳门/香港（最小省）碎片可点中、拖拽判定有容差
- [ ] 全对 → 印章 + 成绩 + 星星（0-1 错 3 星）；回执字段完整
- [ ] 中途关闭 sheet → `completed:false, cancelled:true`，不产生星星行
- [ ] 时间线展开已完成的拼图 → 内联静态卡，无交互、无崩溃
- [ ] 星星面板显示「拼图 / 中国地图拼图」而不是其它游戏名
- [ ] 语音模式下 TTS 不泄露未拼省份位置
- [ ] `hvigorw assembleHap` 绿 + codelinter 无新增缺陷

### 14.1 验收记录（2026-10-26，无真机）

本机没有设备也没有预览器，上面前 9 条都是**人手在屏幕上**才能确认的手感项，因此只勾「可离线证实」的部分；
纯函数与数据层用 node 直跑真实 `rawfile/map/china_provinces.json`（脚本见 commit message 与本节说明）。

| 验收项 | 离线证据 | 结论 |
|---|---|---|
| 华北 5 块 / 聚焦 / 可拖可点 | `computePuzzleTransform(华北,343,300)` → scale 0.581，棋盘占用 242×248vp（画布 343×300，四周 26vp 留白）；托盘 5 块 1 行、8 块 2 行 | ✅ 数值成立 |
| 拖对吸附 + 朗读 / 拖错回弹 + 不泄露 | 34 省各自丢回自己最深点 → **34/34 判对**；7 大区 148 组「丢到另一省最深处」→ **2 组误判**（均为地图数据自身重叠：广东含香港、浙江含福建一角），规则本身 0 误判 | ✅（残 2 组为数据问题，已记录） |
| 长按提示 | `hintSeq` 驱动 `@Monitor` 重播呼吸；`hints` 计数 | ⚠️ 手感需真机 |
| 澳门/香港可点中、有容差 | 澳门 bbox 1.5×2.3 单位；向外 8 方向采样，海侧方向 2/4/6vp 全部判对，陆地侧判错（那是广东，符合预期） | ✅ 数值成立 |
| 全对 → 印章 + 星星（0-1 错 3 星） | `stars = mistakes<=1?3 : mistakes<=3?2 : 1`；`computeStars` 对 `completed!==true` 直接 0 | ✅ |
| 中途关闭 → `cancelled:true` 不落星 | `isCancelledPuzzlePayload` 在 `recordStarEvent` 前拦截 | ✅ |
| 时间线展开静态卡 | 小尺寸分支只渲染棋盘 + 成绩行，`onBoardTap` 为空实现 | ⚠️ 需真机看布局 |
| 星星面板文案 | `META_MAP_PUZZLE`: 拼图 / 中国地图拼图 / 🧩 | ✅ |
| 语音不泄露位置 | auto-TTS 只读「我们来拼大区的地图吧」，不读省名清单；错放只读「再找找看」 | ✅ |
| 构建 + lint | `assembleHap`（main / ohosTest）均成功；codelinter `No defects found` | ✅ |

## 15. 开放风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| 拖拽手感 | ArkUI 无拖拽原语，`onTouch` 自绘；不同设备触点上报频率不同 | 拖拽层用 `animateTo` 收尾；点击通道兜底 |
| 小省可点性 | 澳门/香港 path 极小于全国视图（bbox 1.5×2.3 单位） | 碎片本身 56×56，点击靠碎片而非地图；落点容差加 **14vp 屏幕地板**（见 §4.4） |
| 华东 8 块偏多 | 8 块 + 两行托盘，5 寸屏可能挤 | 托盘高度自适应；AI 提示词建议先拼 3-5 块大区 |
| 与 `map_quiz` 功能重叠感 | 都考位置 | 分工写进提示词：拼图=学，quiz=考 |
| 计时器泄漏 | sheet 反复开关 | `aboutToDisappear` 清 interval + TTS stop |

## 16. 已知取舍（v1 不做）

| 项 | 说明 | 后续 |
|---|---|---|
| 南海诸岛附图 | 棋盘只画本局省份、不画全国轮廓，因此没放 `ChinaMapStage` 右下角那张附图章；整局不会出现「全国地图缺一块」的观感 | 若以后加「全国 34 块」模式，必须补附图 |
| 最佳成绩 | 不存历史最好星数/最快用时（`PreferencesService` 那条可选步骤判定为 NO） | 星星事件表里已有完整回执，需要时再加 |
| 连线/层级提示 | 提示只有「凹槽呼吸三下」，没有「相邻省该放哪」的渐进提示 | 从 `LearningLedgerService` 的错省统计里挑高频错配，做二次课 |
| 世界地图 | v1 只做中国 34 个省级行政区 | 泛化时把 `ChinaMapTransform` 与 `ChinaMapStage` 的变换合并 |
