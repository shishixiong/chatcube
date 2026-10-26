# 中国地图拼图（map_puzzle）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `map_puzzle` 互动教学工具——把省份碎片拖回地图（或点碎片再点地图），一局 3-8 块，自动聚焦本局区域；拼对 TTS 复述省名/简称/省会，按错误次数授 3/2/1 星。

**Architecture:** 纯函数层（视图拟合 → 托盘布局 → 落点判定 → 参数校验，全部 hypium 可测）→ adding-mini-game-tool 10 步配方（ID → 注册 → 分发 → 星星 → 锁定/提示词）→ 组件层（`MapPuzzleBoard` 纯画板 + `MapPuzzleCard` 状态机/拖拽层）→ MazeCard v3「气泡横幅 → ChatPage 全屏 sheet」模式。

**Tech Stack:** ArkTS（@ComponentV2/@Param/@Local/@Event）、Canvas 2D、hypium（entry/src/ohosTest）、复用 `rawfile/map/china_provinces.json`。

**Spec:** `docs/superpowers/specs/2026-10-26-china-map-puzzle-design.md`

## Global Constraints

- 构建关卡（每个任务结束跑到绿）：
  `hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
  （本 VM：`/usr/local/bin/hvigorw`，SDK 在 `/opt/harmonyos-cli/command-line-tools/sdk`；`hvigorw test` 不可用，hypium 在 DevEco 里跑，CLI 只认 assembleHap + 测试模块编译）
- 测试模块编译关卡：`hvigorw assembleHap --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug`（绿 = 新测试能编译）
- Lint：`/opt/harmonyos-cli/command-line-tools/codelinter/bin/codelinter <path> -c code-linter.json5`
  （末尾 EACCES 写日志可忽略，只认 `No defects found`）
- ArkTS 严格模式红线：禁止解构（10605074）；ForEach 回调体内禁 `const` 声明（10905209）；`map(p => ({...}))` 需显式返回类型（10605038）；对象字面量需 interface 标注。
- `rawSchemaJson` 模板字符串内**禁 ASCII 双引号**做描述，一律用「」；改完立即跑 JSON.parse gauntlet。
- `$r('sys.symbol.*')` 只用已确认存在的名字：`puzzle`、`checkmark`、`arrow_counterclockwise`、`arrow_right`、`pin`、`speaker_wave_2_fill`。
- 不新增第三方依赖；不新增 rawfile；不改 `ChinaMapStage`（拼图只在它之外复用几何 util）。
- 命名逐字一致：`map_puzzle` / `MAP_PUZZLE_TOOL_ID` / `isMapPuzzleFunctionName` / `META_MAP_PUZZLE` / `MapPuzzleCard` / `MapPuzzleBoard` / `MapPuzzleResult`。
- 每任务一个 commit（conventional commits）。
- 测试文件新增后必须在 `entry/src/ohosTest/ets/test/List.test.ets` 注册（import + 调用）。

## Pre-Step Audit（10 步配方的可选步骤，先写在纸上）

```
Decision step 8 (largeSize sheet): YES —— 棋盘 + 托盘需要全屏，气泡内放不下
Decision step 9a (PreferencesService best-score): NO —— 星星系统已覆盖，v1 不做最佳成绩
Decision step 9b (DatabaseService records table): NO —— star_events.metadataJson 已带完整回执
```

## Review Focus（最咬人的 5 类输入，测试钉在所属任务）

1. **落点落在邻省** —— 期望：判错（回弹 + mistakes+1），绝不因为「离某个省最近」就算对。钉子：Task 3 `resolveDrop` 断言「山西的碎片丢到河北多边形内 → wrong」。
2. **澳门/香港这种 tiny 省** —— 期望：碎片仍可点可拖，落点只要在它界外一个指头缝内就算对。钉子：Task 3 用 2×2 的 tiny 省断言「距边界 8 = 对、18 = 错」。
3. **细长/月牙形省（甘肃/内蒙古）** —— 期望：容差用**边界距离**而不是质心距离。实测甘肃的面积质心落在省外（距自身边界 3.4），用质心会让容差圆盖住邻省；边界距离无此问题。钉子：Task 1 的 `provinceEdgeDistance` 用例。
4. **拼图未完成就关 sheet** —— 期望：`completed:false, cancelled:true` 回执，星星行 0 颗或干脆不记事件。钉子：Task 12 的 `onDisappear` 取消回执 + Task 11 的 `submitted` 单次提交守卫。
5. **计时器/朗读泄漏** —— 期望：`aboutToDisappear` 清 interval + `tts.stop()`；连续拼对时旧朗读回调不覆盖新状态。钉子：Task 11 的 `speakSeq` 守卫 + `onPuzzleDisappear`。

---

### Task 1: `provinceEdgeDistance` 几何纯函数

> **为什么不是质心**：2026-10-26 用 node 跑真实 34 省做过对比——bbox 中心对甘肃/内蒙古落在省外；
> 面积质心**对甘肃也落在省外**（距自身边界 3.4，34 省里唯一一个）。容差必须用「到边界的距离」。

**Files:**
- Modify: `entry/src/main/ets/utils/ChinaMapGeometry.ets`
- Test: `entry/src/ohosTest/ets/test/utils/ChinaMapGeometry.test.ets`（追加 describe 块）

**Interfaces:**
```ts
/** 点到省份边界的最短距离（地图单位）；点在省内返回 0 */
export function provinceEdgeDistance(path: string, x: number, y: number): number
```

- [ ] **Step 1: 先写失败测试**（追加到 `ChinaMapGeometry.test.ets`，放在 `real full dataset` 之前）
```ts
describe('provinceEdgeDistance', () => {
  const SQUARE10 = 'M0 0L10 0L10 10L0 10Z'
  it('returns 0 for a point inside', 0, () => {
    expect(provinceEdgeDistance(SQUARE10, 5, 5)).assertEqual(0)
  })
  it('measures the distance to the nearest edge', 0, () => {
    expect(provinceEdgeDistance(SQUARE10, 15, 5)).assertEqual(5)
    expect(provinceEdgeDistance(SQUARE10, 5, 20)).assertEqual(10)
  })
  it('handles a concave (L shaped) province', 0, () => {
    const L = 'M0 0L40 0L40 40L100 40L100 100L0 100Z'
    expect(provinceEdgeDistance(L, 70, 30)).assertEqual(10)
  })
  it('keeps a finger-width tolerance out of the neighbour province', 0, () => {
    expect(provinceEdgeDistance(SHANXI_PATH, 725.1, 345.4) > 20).assertTrue()   // 河北质心 → 25.8
    expect(provinceEdgeDistance(SHANXI_PATH, 671.3, 391.5)).assertEqual(0)      // 山西质心在省内
  })
  it('works for a tiny province (Macau scale)', 0, () => {
    const tiny = 'M0 0L2 0L2 2L0 2Z'
    expect(provinceEdgeDistance(tiny, 10, 1)).assertEqual(8)
  })
})
```

- [ ] **Step 2: 实现** `provinceEdgeDistance`（点在省内 → 0；否则遍历全部环求点到线段最短距离），
  内核 `pointSegmentDistance(px, py, x1, y1, x2, y2)` 为私有函数（投影参数 t clamp 到 0..1）。

- [ ] **Step 3: 跑测试 → 绿；再跑 `assembleHap`**

- [ ] **Step 4: commit** `feat(map_puzzle): add province edge distance util`

---

### Task 2: `ChinaMapTransform` 视图变换

**Files:**
- Create: `entry/src/main/ets/utils/ChinaMapTransform.ets`
- Test: `entry/src/ohosTest/ets/test/utils/ChinaMapTransform.test.ets`（新）

**Interfaces:**
```ts
export interface MapPoint { x: number; y: number }
export interface MapTransform { scale: number; offsetX: number; offsetY: number }
/** 直接吃地图坐标的 bbox，调用方不用自己减原点 */
export function createFitTransform(bbox: MapBBox, viewW: number, viewH: number,
  padding: number): MapTransform
export function mapToScreen(t: MapTransform, x: number, y: number): MapPoint
export function screenToMap(t: MapTransform, x: number, y: number): MapPoint
export function screenLengthToMap(t: MapTransform, vp: number): number
```

- [ ] **Step 1: 写测试**

```ts
it('fits a 1000x870 content into a 340x300 view without distortion', 0, () => {
  const t = createFitTransform(1000, 870, 340, 300, 20)
  expect(Math.abs(t.scale - Math.min(300 / 1000, 260 / 870)) < 1e-6).assertTrue()
})
it('centres the content', 0, () => {
  const t = createFitTransform(100, 100, 300, 300, 0)   // scale 3, offset 0
  const o = mapToScreen(t, 50, 50)                       // 内容中心 → 视口中心
  expect(Math.round(o.x)).assertEqual(150)
  expect(Math.round(o.y)).assertEqual(150)
})
it('round-trips screen <-> map', 0, () => {
  const t = createFitTransform(1000, 870, 340, 300, 20)
  const m = screenToMap(t, 123, 77)
  const s = mapToScreen(t, m.x, m.y)
  expect(Math.abs(s.x - 123) < 0.01).assertTrue()
  expect(Math.abs(s.y - 77) < 0.01).assertTrue()
})
```

- [ ] **Step 2: 实现**（`scale = min((viewW-2p)/contentW, (viewH-2p)/contentH)`，`offset = (view - content*scale)/2`；`screenToMap` 是逆变换）

- [ ] **Step 3: 测试绿 + `assembleHap` + 在 `List.test.ets` 注册**

- [ ] **Step 4: commit** `feat(map_puzzle): add map viewport transform util`

---

### Task 3: `MapPuzzleLayout` 托盘布局与落点判定

**Files:**
- Create: `entry/src/main/ets/utils/MapPuzzleLayout.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MapPuzzleLayout.test.ets`（新）

**Interfaces:**
```ts
import { ChinaProvince } from './ChinaMapData'
import { MapBBox, pointInProvince, provinceBBox, provinceEdgeDistance } from './ChinaMapGeometry'
import { createFitTransform, MapTransform, screenLengthToMap, screenToMap } from './ChinaMapTransform'

export interface PuzzleSlot { x: number; y: number }
export interface PuzzleDropResult { correct: boolean; reason: string } // 'hit' | 'tolerance' | 'miss'

export const PUZZLE_FIT_PADDING: number = 26
export const PUZZLE_DROP_TOLERANCE_VP: number = 14
export function unionBBox(provinces: ChinaProvince[]): MapBBox
export function computePuzzleTransform(provinces: ChinaProvince[],
  boardW: number, boardH: number): MapTransform    // = createFitTransform(unionBBox(...), padding 26)
export function layoutTray(count: number, perRow: number,
  slot: number, gap: number, padX: number, padY: number): PuzzleSlot[]
export function trayRows(count: number, perRow: number): number
export function resolveDrop(province: ChinaProvince, t: MapTransform,
  dropX: number, dropY: number): PuzzleDropResult
```

- [ ] **Step 1: 写测试**（合成 path 钉死数值，真实 `SHANXI_PATH`/`HEBEI_PATH` 守反例）
  - `unionBBox`：两个正方形合并 → `{0,0,30,25}`；空数组 → 全零
  - `computePuzzleTransform`：200×100 的并集放进 340×300（padding 26）→ scale 1.44、offsetX 26
  - `layoutTray(5, 4, 56, 8, 12, 0)` → x = 12/76/140/204，第 5 个 wrap 到 `(12, 64)`；`trayRows(5,4)=2`
  - `resolveDrop`（恒等变换，直接喂地图坐标）：
    - 10×10 方块内 `(5,5)` → `hit`；`(15,5)` → `tolerance`（距边界 5 < 14）；`(30,5)` → `miss`（距边界 20）
    - **反例钉子**：山西碎片丢到河北质心 `(725.1, 345.4)` → `miss`（距山西边界 25.8 > 14）
    - **tiny 省**：2×2 方块，`(10,1)` → `tolerance`（边界距离 8），`(20,1)` → `miss`（18）
    - 缩放联动：`scale=2` 时同一屏幕位移对应的地图距离减半，20 地图单位变成 10vp < 14vp → 仍算对

- [ ] **Step 2: 实现** `resolveDrop`：
```ts
const m = screenToMap(t, dropX, dropY)
if (pointInProvince(province.path, m.x, m.y)) {
  return { correct: true, reason: 'hit' }
}
const tolerance = screenLengthToMap(t, PUZZLE_DROP_TOLERANCE_VP)
if (provinceEdgeDistance(province.path, m.x, m.y) <= tolerance) {
  return { correct: true, reason: 'tolerance' }
}
return { correct: false, reason: 'miss' }
```

- [ ] **Step 3: 测试绿 + `assembleHap` + 注册**

- [ ] **Step 4: commit** `feat(map_puzzle): add tray layout and drop resolution`

---

### Task 4: `MapPuzzleValidation` 参数预校验

**Files:**
- Create: `entry/src/main/ets/utils/MapPuzzleValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MapPuzzleValidation.test.ets`（新）

**Interfaces:**
```ts
import { MapToolValidationResult } from './MapToolValidation' // 复用 { ok, error }
import { ChinaProvince } from './ChinaMapData'
export const PUZZLE_REGIONS: string[] = ['华北', '东北', '华东', '华中', '华南', '西南', '西北']
export function parsePuzzleProvinces(provinces: ChinaProvince[] | null,
  mode: string, region: string, refs: string[]): ChinaProvince[]
export function validateMapPuzzleArgs(args: string,
  provinces: ChinaProvince[] | null): MapToolValidationResult
```

- [ ] **Step 1: 写测试**（七条规则逐条 + 边界：2 项、8 项、9 项、重复、未知名、非法 region、skill_key 错）
- [ ] **Step 2: 实现**（严格照 spec §7 文案；`parsePuzzleProvinces` 供卡片与 handler 共用）
- [ ] **Step 3: 测试绿 + `assembleHap` + 注册**
- [ ] **Step 4: commit** `feat(map_puzzle): add args validation`

---

### Task 5: 工具身份常量

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`

**Interfaces:**
```ts
export const MAP_PUZZLE_TOOL_ID: string = 'map_puzzle'
export function isMapPuzzleFunctionName(name: string): boolean
```

- [ ] **Step 1: 照 `MAP_QUIZ_TOOL_ID` / `isMapQuizFunctionName` 添加**
- [ ] **Step 2: 校验** `grep -c "MAP_PUZZLE_TOOL_ID\|isMapPuzzleFunctionName" entry/src/main/ets/utils/SearchToolIdentityUtils.ets` ≥ 2
- [ ] **Step 3: `assembleHap` 绿 → commit** `feat(map_puzzle): register tool identity`

---

### Task 6: BuiltinTools 注册（schema 是重点）

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

**Interfaces:**
```ts
interface MapPuzzleArgs { mode: string; region?: string; provinces?: string[]; skill_key: string }
class MapPuzzleExecutor implements ToolExecutor { async execute(args: string): Promise<string> }
function createMapPuzzleToolDefinition(): ToolDefinition
function createMapPuzzleToolConfig(): ToolConfig
```

- [ ] **Step 1: 加 import（`MAP_PUZZLE_TOOL_ID`）**
- [ ] **Step 2: 加 `MapPuzzleArgs` + `MapPuzzleExecutor`**（stub：回 `{ answered:false, mode, region, provinces, skill_key:'general_social' }`）
- [ ] **Step 3: 加 `createMapPuzzleToolDefinition()`**，schema 严格照 spec §6（描述值用「」，禁 ASCII `"`）
- [ ] **Step 4: 加 `createMapPuzzleToolConfig()`**（名称「中国地图拼图」，描述「拖动省份碎片拼回地图，练形状与位置记忆」，`READ` 权限）
- [ ] **Step 5: `registerBuiltinTools` 加注册块**（镜像 map_quiz 的 `if (!registry.isToolRegistered(...))` 写法）
- [ ] **Step 6: `getBuiltinToolIds()` 末尾追加 `MAP_PUZZLE_TOOL_ID`**
- [ ] **Step 7: JSON.parse gauntlet**
```bash
node -e "
const fs=require('fs');
const s=fs.readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf8');
const i=s.indexOf('createMapPuzzleToolDefinition');
const m=s.slice(i).match(/const rawSchemaJson: string = \`([\s\S]*?)\`/);
const o=JSON.parse(m[1]);
console.log('schema ok', Object.keys(o.properties));
"
```
Expect: `schema ok [ 'mode', 'region', 'provinces', 'skill_key' ]`
- [ ] **Step 8: `assembleHap` 绿 → commit** `feat(map_puzzle): register builtin tool`

---

### Task 7: ToolExecutionService 分发

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

- [ ] **Step 1: 加 import + `handleMapPuzzle`**（镜像 `handleMapQuiz`：校验 → `recordLedgerServed('map_puzzle', ...)` → pending → onAnswer 回执 `recordStarEvent('map_puzzle', ...)` → 取消分支回 `{ cancelled: true }`）
- [ ] **Step 2: 分发分支放在 `resolveToolId` 兜底之前**（与 map_card/map_quiz 分支相邻）
- [ ] **Step 3: 校验**
```bash
grep -c "handleMapPuzzle\|isMapPuzzleFunctionName" entry/src/main/ets/services/ToolExecutionService.ets   # ≥ 3
grep -n "handleMapPuzzle" entry/src/main/ets/services/ToolExecutionService.ets                            # 分支须早于兜底
```
- [ ] **Step 4: `assembleHap` 绿 → commit** `feat(map_puzzle): add execution handler`

---

### Task 8: 星星系统（10 处漂移点）

**Files:**
- Modify: `entry/src/main/ets/models/StarEventModels.ets`
- Modify: `entry/src/main/ets/services/StarRewardService.ets`

- [ ] **Step 1: 按 skill 的 10 处清单逐条加 `map_puzzle`**（union / byType / empty summary / metaMap / META 常量 / metaRecord / activityTypes / getBucketFromSummary / getActivityMeta / getActivitySymbol）
  `META_MAP_PUZZLE`：`emoji '🧩'`、`shortLabel '拼图'`、`longLabel '中国地图拼图'`、`grantedHint '拼完地图'`、`unit '局'`；symbol 用 `sys.symbol.puzzle`
- [ ] **Step 2: `computeStars` 插分支**（spec §8.1：未完成 0；完成读 `payload.stars`，clamp 1..3）
- [ ] **Step 3: 4-grep gauntlet**
```bash
grep -n "META_MAP_PUZZLE" entry/src/main/ets/models/StarEventModels.ets      # 2 处（声明 + metaRecord）
grep -n "byType.map_puzzle" entry/src/main/ets/models/StarEventModels.ets    # 3 处
grep -n "map_puzzle" entry/src/main/ets/models/StarEventModels.ets           # ≥ 8 处
grep -n "activityType === 'map_puzzle'" entry/src/main/ets/services/StarRewardService.ets  # 1 处
```
- [ ] **Step 4: `assembleHap` 绿 → commit** `feat(map_puzzle): add star activity type`

---

### Task 9: 助手白名单 + 系统提示词

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`

- [ ] **Step 1: import `MAP_PUZZLE_TOOL_ID`**
- [ ] **Step 2: 追加进 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`**（与 MAP_CARD / MAP_QUIZ 相邻）
- [ ] **Step 3: 追加提示词段**（spec §10 原文，注意与 map_card 段落相邻，形成「讲 → 拼 → 考」）
- [ ] **Step 4: 校验**
```bash
grep -c "MAP_PUZZLE_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets   # ≥ 3
grep -c "地图拼图" entry/src/main/ets/models/AssistantModels.ets              # ≥ 2（两套提示词都加）
```
- [ ] **Step 5: `assembleHap` 绿 → commit** `feat(map_puzzle): add assistant prompt`

---

### Task 10: `MapPuzzleBoard` 画板组件

**Files:**
- Create: `entry/src/main/ets/components/map/MapPuzzleBoard.ets`

**Interfaces:**
```ts
@ComponentV2 export struct MapPuzzleBoard {
  @Param data: ChinaMapData | null = null
  @Param targets: ChinaProvince[] = []
  @Param placedIds: string[] = []
  @Param hintId: string = ''
  @Param completed: boolean = false
  @Event onBoardTap: (boardX: number, boardY: number) => void = () => {}
}
```

- [ ] **Step 1: Canvas + `onAreaChange` 存尺寸，`computePuzzleTransform` 算变换**
- [ ] **Step 2: 绘制顺序**：纸张网格底 → 未放凹槽（`line` 虚线 1vp + `land` 8%）→ 已放（`land` 实色 + `line` 实线）→ `hintId` 呼吸（3 次，300ms）→ 完成印章
- [ ] **Step 3: 自制 tap（12vp/350ms）→ `onBoardTap(x, y)`**
- [ ] **Step 4: 复用 `getMapAtlasPalette(isDarkMode)`，dark 模式走同一套**
- [ ] **Step 5: `assembleHap` 绿 → commit** `feat(map_puzzle): add puzzle board renderer`

---

### Task 11: `MapPuzzleCard` 状态机 + 拖拽层

**Files:**
- Create: `entry/src/main/ets/components/map/MapPuzzleCard.ets`

**Interfaces:**
```ts
export interface MapPuzzleResult {
  completed: boolean; mode: string; region: string
  total: number; placed: number; mistakes: number; hints: number
  time_seconds: number; stars: number; provinces: string[]
  skill_key: string; cancelled?: boolean
}
@ComponentV2 export struct MapPuzzleCard {
  @Param toolCall: ToolCall
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void
  @Event onRequestClose: () => void
}
```

- [ ] **Step 1: 解析参数**（`parseMapPuzzleArgsView`）+ 加载 `loadChinaMapData` + `parsePuzzleProvinces` 得到 `targets`
- [ ] **Step 2: 大尺寸布局**：表头（`地理 · 拼一拼` / `已拼 N/M`）+ 棋盘卡（`MapPuzzleBoard`，layoutWeight 1）+ 托盘 + 页脚
- [ ] **Step 3: 托盘与拖拽**：`Stack` 内绝对定位碎片（`layoutTray` 给基础坐标）；`onTouch` Down 记 `grabDX/DY`、Move 更新 `dragX/dragY`、Up 调 `attemptPlace(pieceId, dropX, dropY)`
- [ ] **Step 4: 点击通道**：点碎片 → `selectedId`；点棋盘 → `attemptPlace(selectedId, x, y)`
- [ ] **Step 5: `attemptPlace`**：`resolveDrop` → 对：`placedIds.push` + `animateTo` 吸附 + TTS + `mistakes` 不变；错：回弹 + 抖动 + `mistakes++` + TTS
- [ ] **Step 6: 提示**：长按 600ms → `hintId` + 呼吸 3 次 + `hints++`
- [ ] **Step 7: 计时与清理**：`setInterval 1s`；`aboutToDisappear` 清 interval + `tts.stop()`；TTS 用 `speakSeq` 守卫
- [ ] **Step 8: 提交**：全 `placed` → `buildResult(true)` → `onAnswer`（`submitted` 守卫，只发一次）；取消回执不在这里，由 ChatPage `onDisappear` 发
- [ ] **Step 9: 小尺寸（时间线）**：静态缩略板（height 180）+ 成绩行 + 省份 chips，无交互
- [ ] **Step 10: `assembleHap` 绿 + codelinter → commit** `feat(map_puzzle): add puzzle card`

---

### Task 12: 气泡横幅 + 全屏 sheet

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`
- Modify: `entry/src/main/ets/pages/ChatPage.ets`

- [ ] **Step 1: MessageBubble 加 import + `shouldRenderMapPuzzleInteractionCard(toolCall, index)`**（镜像 map_card 的 7 处挂载：横幅 / 内联 / 时间线 step / 点击派发 / 步骤 builder）
- [ ] **Step 2: 横幅**：课卡样式（图标 `sys.symbol.puzzle`，标题「中国地图拼图」，副标题「拼图课 · 把省份拼回家」，右侧「打开」）
- [ ] **Step 3: ChatPage 加 3 个状态 + `MapPuzzleSheetBuilder` + `bindSheet`**（`height: SheetSize.LARGE, dragBar: true, showClose: true`）
  `onDisappear` 里若 `!mapPuzzleAnswered` 则发取消回执（字段见 spec §9.3），并判断是否已答避免重复
- [ ] **Step 4: 校验**（保证没有漏的链）
```bash
grep -c "MapPuzzle" entry/src/main/ets/components/MessageBubble.ets          # ≥ 6
grep -c "MapPuzzle" entry/src/main/ets/pages/ChatPage.ets                    # ≥ 5
```
- [ ] **Step 5: `assembleHap` 绿 → commit** `feat(map_puzzle): mount bubble banner and sheet`

---

### Task 13: 收尾验收

- [x] **Step 1: 全量构建**
```bash
hvigorw clean --mode module -p product=default && \
hvigorw assembleHap --mode module -p product=default -p buildMode=debug
hvigorw assembleHap --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug
```
- [x] **Step 2: lint**
```bash
/opt/harmonyos-cli/command-line-tools/codelinter/bin/codelinter \
  entry/src/main/ets/components/map entry/src/main/ets/utils/MapPuzzle*.ets \
  entry/src/main/ets/utils/ChinaMap*.ets -c code-linter.json5
```
- [ ] **Step 3: 按 spec §14 真机清单逐条走查**（华北 5 块全流程、错放回弹、提示、星星、关闭回执、时间线恢复、星星面板文案）
      —— 本机无设备/预览器，改为 spec §14.1 的离线数值核对（构建、lint、34 省落点、7 大区 148 组误判、澳门可放性）；手感项待真机
- [x] **Step 4: 更新 `CHANGELOG.md` 的「新增」段**（一行：新增中国地图拼图 `map_puzzle`）
- [x] **Step 5: commit** `feat(map_puzzle): complete acceptance pass`

---

## 依赖关系图

```
Task 1 (edge distance) ─┐
Task 2 (transform) ─┼─→ Task 3 (layout/drop) ─→ Task 11 (card)
Task 4 (validation)─┘                          ↗
Task 5 (id) → Task 6 (builtin) → Task 7 (handler) → Task 8 (stars) → Task 9 (prompt)
Task 10 (board) ────────────────────────────────┘
Task 11 → Task 12 (bubble/sheet) → Task 13 (acceptance)
```

Task 1-4 可并行；Task 5-9 严格串行（10 步配方依赖序）；Task 10 可与 5-9 并行。

## 工作量估计

| 部分 | 人日 |
|---|---|
| 纯函数层 + 测试（Task 1-4） | 0.5 |
| 10 步配方（Task 5-9） | 0.5 |
| 画板 + 卡片 + 拖拽（Task 10-11） | 1.5 |
| 挂载 + sheet（Task 12） | 0.5 |
| 真机走查 + 修手感（Task 13） | 1.0 |
| **合计** | **~4 人日** |
