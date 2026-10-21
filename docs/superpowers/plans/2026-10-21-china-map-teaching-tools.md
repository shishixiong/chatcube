# 中国地图教学工具（map_card + map_quiz）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为小星语文老师（kids_chinese）与小星老师（default）新增 `map_card`（讲解型中国地图课）与 `map_quiz`（choice/locate/write 三题型出题）两个互动教学工具，含数据管线、星星系统、全屏 sheet 集成。

**Architecture:** 纯函数数据层（rawfile 地图 JSON + Canvas 几何命中 + 校验/选项生成）→ adding-mini-game-tool 10 步配方工具集成（ID → 注册 → 分发 → 星星 → 锁定/提示词）→ CardShell 卡片族（薄路由 + bodies，镜像 chinese/ 先例）→ MazeCard v3「气泡横幅 → ChatPage 全屏 sheet」模式。

**Tech Stack:** ArkTS（@ComponentV2/@Trace/@Monitor）、Canvas 2D、hypium（entry/src/ohosTest）、resources/rawfile。

**Spec:** `docs/superpowers/specs/2026-10-21-china-map-teaching-tools-design.md`（行号依据以其 §7 引用的实读核对为准；本计划与 spec 一起读）

## Global Constraints

- 构建验证（每任务的 CLI 关卡）：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`。`hvigorw test` 不可用——hypium 测试在 DevEco Studio IDE 中运行（右键测试类），CLI 侧 assembleHap 绿是唯一命令行关卡。
- ArkTS 严格模式红线：禁止解构 `const [a,b]=`（10605074）；ForEach 回调体内禁 `const` 声明（10905209）；`map(p => ({...}))` 必须显式返回类型（10605038）；对象字面量必须 interface 标注（10605040）。
- rawSchemaJson 模板字符串内描述值**禁 ASCII `"`**，示例一律用「」；每任务改完 schema 立即跑 JSON.parse gauntlet（Task 5 Step 6 的命令）。
- `$r('sys.symbol.X')` 只允许仓库已确认存在的名字；本计划统一用 `sys.symbol.map`（MazeCard 横幅已用）。
- 不新增 `entry/oh-package.json5` 依赖。
- 192KB 地图数据只进 `resources/rawfile`，禁止内联进 .ets。
- 每任务结束 commit（conventional commits，英文 message）；一次任务一个 commit，不混合无关文件。
- 工具/常量/文案命名与 spec §5/§8 逐字一致：`map_card`、`map_quiz`、`MAP_CARD_TOOL_ID`、`MAP_QUIZ_TOOL_ID`、`isMapCardFunctionName`、`isMapQuizFunctionName`、`META_MAP_CARD`、`META_MAP_QUIZ`。
- 测试新增后需在 ohosTest 套件注册处登记：实读 `entry/src/ohosTest/ets/test/`（以 `VerticalMathHelpLayout.test.ets` 被注册的位置为准，镜像其写法）。

## Review Focus

Spec 隐含但任务测试不覆盖、最容易咬人的五类输入（每行已把测试钉进所属任务）：

1. **locate 点到海域/inset 附图**——期望：不触发任何判定，不算答错（原型 aria-hidden 同款）。钉子：Task 2 测试断言海点 `(891.6, 681.5)` 对全部 34 省 `pointInProvince === false`；Task 9 步骤：inset 绘制区不参与命中（命中仅遍历 34 省 path）。
2. **语音模式 choice 泄题**——期望：自动朗读文本绝不包含答案省名（语音模式孩子读不了屏）。钉子：Task 14 的 `buildQuizTtsText` choice 分支文案为固定字符串（不含 `province` 参数插值）+ Task 15 真机清单。
3. **历史会话恢复读到被污染的 toolResult**——期望：不出现假「再试一次」。钉子：Task 13 StepContent 恢复一律 `resolveStepAnswerPayload(step.toolResult, step.toolApprovalReason)`（`utils/ChatMessagePartsHelper.ets:55-58`）+ Task 15 真机清单。
4. **多子路径省份的奇偶语义**（广东 20 环含岛屿、上海 7 环、河北环抱北京为洞）——期望：岛屿内点判中、洞内点判不中。钉子：Task 2 用真实坐标断言（见该任务测试代码）。
5. **AI 对 capital===short 的 6 省传 `clue:'capital'`**——期望：校验层硬拒 + should_retry。钉子：Task 4 测试断言北京/天津/上海/重庆/香港/澳门全部 `{ok:false}`。

---

### Task 1: 地图数据资产 + ChinaMapData 加载/查询

**Files:**
- Create: `entry/src/main/resources/rawfile/map/china_provinces.json`
- Create: `entry/src/main/ets/utils/ChinaMapData.ets`
- Test: `entry/src/ohosTest/ets/test/utils/ChinaMapData.test.ets`

**Interfaces:**
- Consumes: `docs/map-learning/assets_china-provinces.js`（window.CHINA_MAP 单行 JS）
- Produces:
```ts
export interface ChinaProvince { id: string; name: string; short: string; abbr: string; capital: string; region: string; path: string }
export interface ChinaMapInset { path: string; width: number; height: number }
export interface ChinaMapData { viewBox: string; width: number; height: number; provinces: ChinaProvince[]; inset: ChinaMapInset }
export async function loadChinaMapData(context: common.UIAbilityContext): Promise<ChinaMapData | null>  // getRawFileContentSync('map/china_provinces.json') → util.TextDecoder('utf-8') → JSON.parse → 模块级缓存；任何一步失败返回 null
export function getCachedChinaMapData(): ChinaMapData | null
export function findProvinceByRef(provinces: ChinaProvince[], ref: string): ChinaProvince | null  // 依次匹配 short → name → id，大小写敏感，前后 trim
```

- [ ] **Step 1: 转换数据并落盘**

```bash
mkdir -p entry/src/main/resources/rawfile/map
python3 -c "
import json
raw = open('docs/map-learning/assets_china-provinces.js').read()
d = json.loads(raw[raw.index('{'):].rstrip().rstrip(';'))
open('entry/src/main/resources/rawfile/map/china_provinces.json','w').write(json.dumps(d, ensure_ascii=False, separators=(',',':')))
print(len(d['provinces']), 'provinces')
"
```
Expected: `34 provinces`。抽查：`python3 -c "import json;d=json.load(open('entry/src/main/resources/rawfile/map/china_provinces.json'));print(d['viewBox'], d['provinces'][0]['short'], d['inset']['width'])"` 输出 `0 0 1000 870 北京 89.86`。

- [ ] **Step 2: 写失败测试**（hypium；fixture 用内联 2 条假省份数据，不依赖 rawfile）

断言：`findProvinceByRef` 按 short/name/id 三口径命中；trim 后命中；未命中返回 null；空数组返回 null。测试类 `ChinaMapDataTest`，用例名 `testFindByShort/testFindByName/testFindById/testTrimMatch/testMissReturnsNull`。

- [ ] **Step 3: 在 ohosTest 套件注册处登记测试**

镜像 `VerticalMathHelpLayout.test.ets` 的注册方式（实读注册文件）。

- [ ] **Step 4: 实现 `ChinaMapData.ets`**

`import common from '@ohos.app.ability.common'`、`import util from '@ohos.util'`；模块级私有缓存 `let cached: ChinaMapData | null = null`；loader 按签名实现；注意 `getRawFileContentSync` 返回 `Uint8Array`，`util.TextDecoder.create('utf-8').decodeToString(bytes)`。JSON.parse 结果 cast 到 `ChinaMapData`（先 `as Record<string, Object>` 再逐字段收窄，遵守 10605038）。查询纯函数可直接对 `provinces` 线性扫。

- [ ] **Step 5: assembleHap 绿 + IDE 跑测试 PASS**

- [ ] **Step 6: Commit** `feat: add china provinces map data asset and loader`

---

### Task 2: ChinaMapGeometry 纯函数（解析/命中/包围盒）

**Files:**
- Create: `entry/src/main/ets/utils/ChinaMapGeometry.ets`
- Test: `entry/src/ohosTest/ets/test/utils/ChinaMapGeometry.test.ets`

**Interfaces:**
- Consumes: 无（纯函数，输入是 path 字符串）
- Produces:
```ts
export interface MapBBox { minX: number; minY: number; maxX: number; maxY: number }
export function parseProvincePolygons(path: string): number[][][]  // 返回环数组；每环为 [x,y] 点数组；M 开环、Z 闭合；连续 ZM… 拆多环；忽略未知命令
export function pointInProvince(path: string, x: number, y: number): boolean  // 射线法跨全部环的穿越奇偶（= evenodd），空 path / 无数字 → false
export function provinceBBox(path: string): MapBBox  // 全环顶点包围盒；空 path 返回 {0,0,0,0}
```

- [ ] **Step 1: 写失败测试**（全部用真实坐标，来源见断言注释）

```typescript
// 真实数据坐标（2026-10-21 从 docs/map-learning/assets_china-provinces.js 射线法程序计算）：
// 北京 centroid(730.0,329.5) 在北京环内；同一坐标在河北 = False（北京是河北外环的洞，evenodd 语义）
// 山西 centroid(671.3,391.5)；广东 ring0 centroid(709.0,707.9)（20 子路径含岛屿）；
// 上海 ring0 centroid(841.0,520.8)（7 子路径）；海点(891.6,681.5) 不属任何省。
// 合成用例：'M0 0L10 0L10 10Z' 方环；'M0 0L10 0L10 10ZM4 4L6 4L6 6L4 6Z' 洞环（点(5,5) 应为 false）。
```

用例清单：`testParseSquare`（1 环 4 点）、`testParseMultiSubpath`（ZM… 拆 2 环）、`testPointInsideSquare`、`testPointOutsideSquare`、`testHoleEvenOdd`（洞中心 false）、`testIslandEvenOdd`（岛环内点 true）、`testEmptyPathReturnsFalse`、`testBBox`、`testRealBeijingInside`（需在测试内嵌北京市 path 或经 `loadChinaMapData`——IDE 测试有 ability context，可加载真数据；若加载不可行则内嵌北京 path 字符串常量进测试文件）、`testRealBeijingNotInHebei`、`testRealShanxiInside`、`testRealGuangdongIslandInside`、`testRealSeaPointInNoProvince`（34 省全断言 false）。

- [ ] **Step 2: IDE 跑测试确认 FAIL**（函数未定义）

- [ ] **Step 3: 实现**（token 化 `re` 同款逻辑用手写循环：`/[MLZ]|-?\d+\.?\d*/g` 的 ArkTS 等价——逐字符扫描 + parseFloat；射线法标准实现；无 Q/C 分支——数据已验证纯 M/L/Z）

- [ ] **Step 4: IDE 测试 PASS + assembleHap 绿**

- [ ] **Step 5: Commit** `feat: add china map polygon geometry utils`

---

### Task 3: 省名笔画数据入库（101 字）

**Files:**
- Modify: `entry/src/main/ets/config/StrokeOrderData.ets`（`STROKE_ORDER_ENTRIES`，`// === 大写字母 ===` 注释之前）

**Interfaces:**
- Consumes: `.claude/skills/adding-stroke-order-data/gen_stroke_data.js` + `getStrokeOrder()/hasStrokeOrder()` 既有查询（不新增接口）
- Produces: 101 个新字可被 `getStrokeOrder()` 查到（Task 12 写字题依赖）

**精确字符清单**（省级行政区全字段去重后缺失的 101 字，2026-10-21 程序核对）：

```
乌京兰冀内别北区南原古台合吉吾呼和哈回壮夏太宁安家尔川州市庄庆建徽成拉政新族昆昌春晋杭桂武汉江沈沙沪河治津济浙浩海渝港湖湘湾滨澳特琼甘疆皖省福粤维肃肥自苏萨蒙藏行西豫贵赣辽郑都鄂重银长闽阳陕青香鲁黑齐龙
```

- [ ] **Step 1: 批量生成** `node .claude/skills/adding-stroke-order-data/gen_stroke_data.js 乌京兰…龙 > /tmp/map_chars.txt`（整串 101 字粘贴）

- [ ] **Step 2: 核对 label**——输出中所有 `??` 占位（chinese-character-strokes CDN 间歇不可用）逐字人工改为横/竖/撇/捺/点/折；不许留 `??`、不许用「笔画N」。抽查笔顺常识：疆 19 画、藏 17 画、澳 15 画、黑 12 画、龙 5 画。

- [ ] **Step 3: 插入 `STROKE_ORDER_ENTRIES`**（`// === 大写字母 ===` 注释之前，tuple 形状与既有条目一致；grep 每字确认无重复键——Map 构造后者覆盖前者是静默 bug）

- [ ] **Step 4: assembleHap 绿；grep 验证**：`grep -c "^  \['" entry/src/main/ets/config/StrokeOrderData.ets` 应等于原值 + 101（原值 Task 开始时先记录）

- [ ] **Step 5: Commit** `feat: add stroke order data for province name characters`

---

### Task 4: MapToolValidation + pickMapChoiceOptions（纯函数）

**Files:**
- Create: `entry/src/main/ets/utils/MapToolValidation.ets`
- Create: `entry/src/main/ets/utils/MapChoiceOptions.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MapToolValidation.test.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MapChoiceOptions.test.ets`

**Interfaces:**
- Consumes: `ChinaProvince` / `findProvinceByRef`（Task 1）
- Produces:
```ts
export interface MapToolValidationResult { ok: boolean; error: string }
export function validateMapCardArgs(args: string, provinces: ChinaProvince[] | null): MapToolValidationResult
export function validateMapQuizArgs(args: string, provinces: ChinaProvince[] | null): MapToolValidationResult
export function pickMapChoiceOptions(provinces: ChinaProvince[], targetId: string, rng: () => number): string[]  // 返回恰 4 个互异 province id、含 targetId；同大区优先取 2、其余池补 1（池不足时跨大区补满）；Fisher-Yates 用 rng
```

校验规则（spec §6 + §3.1 定案，错误文案全部写给 LLM 自行修正的中文提示，含「怎么改」）：
- map_card：JSON.parse 守卫；`skill_key` 必须恰为 `general_social`；`focus_province` 存在时必须 `findProvinceByRef` 命中（short/name/id 三口径）；provinces 为 null → `{ok:false, error:'地图数据未就绪…'}`
- map_quiz：mode 枚举 `['choice','locate','write']`；province 必填且命中；`clue` 仅 locate 可传且枚举 `['name','capital']`；choice/write 传 clue → fail；**locate+capital 且 `province.capital === province.short`（北京/天津/上海/重庆/香港/澳门）→ fail，文案含「请改用 clue:「name」」**；skill_key 同上

- [ ] **Step 1: 写两个失败测试**

`MapToolValidationTest` 用例：`testCardValid`、`testCardUnknownProvince`、`testCardBadSkillKey`、`testCardBadJson`、`testQuizChoiceValid`、`testQuizBadMode`、`testQuizUnknownProvince`、`testQuizClueOnChoiceRejected`、`testQuizCapitalSelfAnswerRejected`（fixture 中造 `capital===short` 的省 + 断言北京等真实 6 省在完整 fixture 中全部 `{ok:false}`）、`testQuizNullProvinces`。fixture：内联 4-6 条假省份（含一条 `capital===short`）。
`MapChoiceOptionsTest` 用例：`testExactlyFourDistinct`、`testContainsTarget`、`testSameRegionPreference`（注入 rng 断言同大区候选先被取走）、`testSmallRegionFallsBack`（target 所在大区仅 1 省时仍 4 个互异）、`testDeterministicWithFixedRng`（固定 rng 两次调用结果一致）。

- [ ] **Step 2: IDE 确认 FAIL → 实现 → IDE PASS → assembleHap 绿**

- [ ] **Step 3: Commit** `feat: add map tool arg validation and choice option generator`

---

### Task 5: 工具 ID 常量 + BuiltinTools 注册（配方步骤 1-2）

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`（ID 常量区 ~:34-37；`isXxxFunctionName` 函数区 ~:91；`isInteractiveQuizFunctionName` :230-250）
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`（interface 区、executor 区、definition/config 区、`registerBuiltinTools` :3579、`getBuiltinToolIds`）

**Interfaces:**
- Consumes: Task 4 校验函数（executor 桩不用）
- Produces: `MAP_CARD_TOOL_ID = 'map_card'`、`MAP_QUIZ_TOOL_ID = 'map_quiz'`、`isMapCardFunctionName(raw: string): boolean`、`isMapQuizFunctionName(raw: string): boolean`（实现镜像 `isHanziCardFunctionName`——归一化后比对）；`MapCardArgs`/`MapQuizArgs` interface；`MapCardExecutor`/`MapQuizExecutor` 桩类（镜像 `ChineseQuizExecutor` :3483-3499：解析失败兜底 ErrorOutput）

- [ ] **Step 1: SearchToolIdentityUtils 追加**——2 常量 + 2 检查函数；`isInteractiveQuizFunctionName` 的成员资格**镜像 hanzi_card**（已核实 hanzi_card 在内，故 map_card 一并加入；map_quiz 显然在内）。验证：`grep -c "MAP_CARD_TOOL_ID\|isMapCardFunctionName" entry/src/main/ets/utils/SearchToolIdentityUtils.ets` ≥ 3。

- [ ] **Step 2: BuiltinTools 追加两个工具注册**——schema JSON 逐字取 spec §5.1/§5.2（`required`：map_card `["skill_key"]`、map_quiz `["mode","province","skill_key"]`）；描述文本逐字取 spec §5（含「有效省份名列表：北京 天津 … 澳门」34 名全列 + INSTEAD 框架 + ⚠️ 负例句）；ToolConfig 中文名 `中国地图小课堂` / `中国地图出题`，中文一句话描述仿 hanzi_card 风格（「看中国地图认 34 个省级行政区的名字、简称和行政中心，可重点讲一个省。」/「出一道中国地图题：看图选名、按名找位置或手写省名。」），`ToolPermissionLevel.READ`；两个注册块镜像 hanzi_card :3858-3867；`getBuiltinToolIds()` 追加 2 个 ID。

- [ ] **Step 3: JSON.parse gauntlet**（解析文件内**全部** rawSchemaJson 块）：

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const parts=s.split('const rawSchemaJson');let n=0;for(let i=1;i<parts.length;i++){const m=parts[i].match(/\`([\s\S]*?)\`/);if(m){JSON.parse(m[1]);n++}}console.log('OK',n,'schemas')"
```
Expected: `OK N schemas`（N ≥ 原值 + 2，原值先记录），无异常。

- [ ] **Step 4: assembleHap 绿 + grep**：`grep -c "MAP_CARD_TOOL_ID" entry/src/main/ets/config/BuiltinTools.ets` ≥ 3（import/定义/config+register）；同查 MAP_QUIZ_TOOL_ID。

- [ ] **Step 5: 若 `utils/ToolIconMapping.ets` 存在工具图标白名单映射**（实读确认），为两工具补条目；否则跳过并在 commit message 注明。

- [ ] **Step 6: Commit** `feat: register map_card and map_quiz builtin tools`

---

### Task 6: ToolExecutionService 分发 handler（配方步骤 3）

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`（import 区 :21/:27 附近；handler 区（`handleHanziCard` :1406-1495 后）；dispatch 链 :2848 之后、`resolveToolId` 兜底 :2850 之前）

**Interfaces:**
- Consumes: Task 1 `getCachedChinaMapData()`（缓存命中则同步拿；miss 时 `await loadChinaMapData(context)`——context 获取方式镜像 `PreferencesService` 的 EntryAbility 注入模式，实读确认）；Task 4 两个校验函数；Task 5 两个 ID 常量
- Produces: `private async handleMapCard(toolCall: ToolCall, context: ToolCallContext): Promise<ToolResult>`、`private async handleMapQuiz(...)` 同签名

- [ ] **Step 1: 实现 `handleMapCard`**——逐臂镜像 `handleHanziCard` :1406-1495：元数据固化（displayName 空 → `中国地图小课堂`；sourceLabel 空 → `内置工具`）→ `validateMapCardArgs(toolCall.arguments, provinces)`（provinces 由 `getCachedChinaMapData()`，null 时先 `await loadChinaMapData(context)`）失败 → `approvalState='denied'` + `{error:'validation_failed', message, should_retry:true}` → pending 挂起（snapshot.toolId = MAP_CARD_TOOL_ID）→ 取消/null/reject 三臂文案 `小朋友未完成本课学习` → 成功臂 `approvalState='answered'` + `toolCall.approvalReason = answerJson` + `recordStarEvent('map_card', ...)`。

- [ ] **Step 2: 实现 `handleMapQuiz`**——同骨架；displayName `中国地图出题`；取消文案 `小朋友未回答该题目`；**不加** `runVocabRepeatGate`（spec §7 决策）；`recordStarEvent('map_quiz', ...)`。

- [ ] **Step 3: dispatch 块**插在 chinese_quiz 分支（:2844-2848）之后、`resolveToolId` 兜底（:2850）之前：

```typescript
if (isMapCardFunctionName(functionName)) {
  return this.handleMapCard(toolCall, context)
}
if (isMapQuizFunctionName(functionName)) {
  return this.handleMapQuiz(toolCall, context)
}
```

- [ ] **Step 4: 验证**：`grep -c "handleMapCard\|handleMapQuiz" entry/src/main/ets/services/ToolExecutionService.ets` ≥ 6（import 不计、定义 + dispatch 各 2）；dispatch 行号 < resolveToolId 行号（`grep -n "resolveToolId\|isMapCardFunctionName" 同文件` 人工核对顺序）。

- [ ] **Step 5: assembleHap 绿 → Commit** `feat: dispatch map_card and map_quiz to interactive handlers`

---

### Task 7: 星星系统（配方步骤 4）+ 学科计数

**Files:**
- Modify: `entry/src/main/ets/models/StarEventModels.ets`（10 处漂移点 × 2 类型）
- Modify: `entry/src/main/ets/services/StarRewardService.ets`（`computeStars` chinese_quiz 分支 :221-225 之后）
- Modify: `entry/src/main/ets/components/kids/KidsSubjectCatalog.ets`（:87 chinese 条目 `activityTypes` 数组追加 `'map_card', 'map_quiz'`）

**Interfaces:**
- Produces: `StarActivityType` 新成员 `'map_card'` / `'map_quiz'`；`META_MAP_CARD`（emoji `'🗺️'`，shortLabel `'地图'`，longLabel `'中国地图小课堂'`，grantedHint `'地图课学完'`，unit `'次'`）；`META_MAP_QUIZ`（emoji `'🧭'`，shortLabel `'地图题'`，longLabel `'中国地图出题'`，grantedHint `'地图题答对'`，unit `'题'`）；两类型的 `getActivitySymbol` 都返回 `$r('sys.symbol.map')`

- [ ] **Step 1: 10 处漂移点逐一修改**（spec §8.1 表格为准；插入位置在 'chinese_quiz' 相关条目附近保持语文族聚合）

- [ ] **Step 2: 4-grep gauntlet**（把技能里命令的 XXX 换成 MAP_CARD/MAP_QUIZ 跑 4 条；期望：`META_MAP_CARD` 恰 2 行、`byType.map_card` 恰 3 行、`return META_MAP_CARD` 恰 1 行、`return byType.map_card` 恰 1 行——map_quiz 同理；多 1 行即 typo，少 1 行即漏改）

- [ ] **Step 3: computeStars 两分支**（代码逐字取 spec §8.2，插在 chinese_quiz 分支后）

- [ ] **Step 4: KidsSubjectCatalog:87 追加**，assembleHap 绿

- [ ] **Step 5: Commit** `feat: add map_card/map_quiz star activity types`

---

### Task 8: 助手锁定 + 提示词（配方步骤 5）

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`（import :3-29；`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` :108-132；`KIDS_CHINESE_LOCKED_TOOL_IDS` :168-172；`DEFAULT_ASSISTANT_SYSTEM_PROMPT` :38-105；`KIDS_CHINESE_SYSTEM_PROMPT` :337-385）

**Interfaces:**
- Consumes: Task 5 ID 常量
- Produces: 两助手锁定集各 +2；提示词地图段（下为逐字内容）

**default 小星老师**——`## 语文（六步识字）` 段之后插入：

```
## 中国地图
孩子问到省份、家乡、简称、行政中心，或今日计划含地理点时，用 map_card 开一节中国地图课：一次聚焦不超过 3 个省，focus_province 传本次重点省的常用名。讲完用 map_quiz 出 1-3 题检验，mode 换着来。choice 的选项由卡片自动生成，不要自己编选项。locate 考行政中心时题干只出现行政中心名。⚠️ 严禁把答案省名或简称写进题目文字。⚠️ 严禁编造省份名——只允许工具描述列表内的 34 个名字。地理观察写 general_social 维度。
```

**kids_chinese 小星语文老师**——`## 语文教学策略` 步骤列表追加一步：

```
⑦ 地图课：孩子想认省份/学到地理话题时用 map_card 开中国地图小课堂（focus_province 传重点省），讲完用 map_quiz 换 mode 出题检验；choice 选项由卡片生成；⚠️ 严禁把答案写进题目、严禁编造省份名；地理观察写 general_social 维度。
```

并在 `## 出题契约` 段尾追加：

```
【出题契约】map_card：focus_province 是可选参数，只传本次重点讲的省。map_quiz：一次一道题；locate 的 clue 只能是 name 或 capital；capital 与省名相同的直辖市/特区（北京、天津、上海、重庆、香港、澳门）不许用 clue:「capital」。
```

- [ ] **Step 1: 三处数组/import 修改**，`grep -c "MAP_CARD_TOOL_ID\|MAP_QUIZ_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets` ≥ 6（import 2 + 两 locked list 4）

- [ ] **Step 2: 两份提示词段落逐字插入**（`SharedPromptFragments` 本次不动——spec §10 决策）

- [ ] **Step 3: assembleHap 绿 → Commit** `feat: lock map tools into default and kids_chinese assistants with prompts`

---

### Task 9: ChinaMapStage 地图渲染组件

**Files:**
- Create: `entry/src/main/ets/components/map/ChinaMapStage.ets`

**Interfaces:**
- Consumes: Task 1 `ChinaMapData/ChinaProvince/getCachedChinaMapData`；Task 2 三个几何函数
- Produces:
```ts
@ComponentV2
export struct ChinaMapStage {
  @Param data: ChinaMapData | null = null
  @Param targetId: string = ''
  @Param selectedId: string = ''
  @Param correctId: string = ''
  @Param wrongId: string = ''
  @Param interactive: boolean = false
  @Event onPickProvince: (provinceId: string) => void = () => {}
  // 内部：Canvas 2D + 底部右侧 ＋ / − / ⟲ 三按钮 overlay；捏合缩放 1x-4x + 拖拽平移（PanGesture/PinchGesture，distance 阈值防误触）
}
```

实现要点（每条一个可检查结果）：
- 前向变换：`fitScale = min(w/1000, h/870.2)` 居中 + `zoom` + `pan`；**命中判定必须用同一前向变换的逆变换**（触摸点 → 地图坐标 → `pointInProvince`，先 `provinceBBox` 粗筛再精确判定）；inset 附图区（右下角 scale 0.75 绘制）不参与命中。
- 绘制：每省 `ctx.beginPath()` → 手写 M/L/Z 逐环 moveTo/lineTo → `closePath()` → fill（**`ctx.fill('evenodd')`**）+ 0.5-1px stroke；四态色 target/correct/wrong/selected 走主题令牌 + `KIDS_CHINESE` 系强调色（实读 ChineseQuizCard bodies 取色方式照搬）；默认填充低饱和底色。
- 重绘触发：`onAreaChange`（`width as number` cast，先例 HandwritingCard :611-619）+ `@Monitor('targetId','selectedId','correctId','wrongId','data')` + 手势回调内按帧节流；组件销毁 `aboutToDisappear` 清理。
- 触摸隔离：`.onTouch(e => e.stopPropagation())`（防冒泡到聊天 List）；`interactive=false` 时画布不挂手势。
- data 为 null → 居中兜底文案「地图加载中…」。

- [ ] **Step 1: 实现**（本任务无单测——Canvas 组件；验证靠 Task 10/11 联调 + 真机清单）
- [ ] **Step 2: assembleHap 绿**（组件暂无调用方，仅编译验证）
- [ ] **Step 3: Commit** `feat: add ChinaMapStage canvas map renderer`

---

### Task 10: MapCard 讲解型卡片

**Files:**
- Create: `entry/src/main/ets/components/map/MapCard.ets`

**Interfaces:**
- Consumes: Task 9 stage；CardShell/CardShellState（`components/cardshell/`）；Task 1 数据
- Produces:
```ts
export interface MapCardResult { completed: boolean; focus_province: string; explored_count: number; skill_key: string }
export interface MapCardArgsView { valid: boolean; focusProvince: string }
export function parseMapCardArgs(raw: string): MapCardArgsView  // JSON.parse 守卫 + focus_province 字符串收窄
@ComponentV2
export struct MapCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}   // 全屏 sheet 的 ✕（镜像 MazeCard.ets:134）
}
```

实现要点：
- CardShell 范式逐条镜像 HanziCard（:145-211）：`shellState.feedbackSuppressed = true`（:202 同款）；shellConfig title `中国地图小课堂`、icon `$r('sys.symbol.map')`；invalid args 兜底文案「这张地图出错了，老师马上换一张」。
- 主体：`ChinaMapStage`（selectedId = focusProvince 的 id ?? 孩子当前点选；`interactive = !isAnswered`）+ 省份资料卡（region 徽章 + `short` 大字 + 简称印章 `abbr` + `行政中心：capital` + 🔊 朗读按钮——文案 `${name}。简称${abbr}。行政中心${capital}。`，TTS 走 HanziCard :366-417 的 `TtsEngineRegistry` 通道，`aboutToDisappear` 停播）。
- focus 进入时资料卡自动展示；`hasExplored` 计数（点过 ≥1 省或 focus 已展示）驱动「我学会了 · 继续」`canSubmit()`（disabled + 0.55 opacity，镜像 HanziCard :431-452/:627-636）。
- `submit()` 守卫 `submitted=true` → `onAnswer(toolCall.id, JSON.stringify(MapCardResult))`；`isAnswered` 恢复：`JSON.parse(answeredPayload)` 读 completed → 已完成药丸 + 静态地图。

- [ ] **Step 1: 实现 → assembleHap 绿 → Commit** `feat: add MapCard explainer card`

---

### Task 11: MapQuizCard 薄路由 + choice/locate bodies

**Files:**
- Create: `entry/src/main/ets/components/map/MapQuizCard.ets`
- Create: `entry/src/main/ets/components/map/bodies/MapChoiceBody.ets`
- Create: `entry/src/main/ets/components/map/bodies/MapLocateBody.ets`

**Interfaces:**
- Consumes: Task 9 stage；Task 1/4 数据与选项；CardShell
- Produces:
```ts
export interface MapQuizAnswerPayload {
  answered: boolean; mode: string; province: string; province_id: string
  clue: string; child_answer: string; correct: boolean; cancelled?: boolean; skill_key: string
}
@ComponentV2
export struct MapQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}
}
```
（薄路由镜像 `ChineseQuizCard.ets:17-72`：解析 mode → choice/locate/write 分发到 body，全部 @Param/@Event 透传；解析失败兜底 MapChoiceBody。）

- **MapChoiceBody**：`getCachedChinaMapData()` → target 省 → `pickMapChoiceOptions(provinces, target.id, Math.random)` 生成 4 id；地图 `interactive=false, targetId`；2×2 选项网格（文案 = short 名）；即判即交镜像 `ChineseChoiceBody.ets:99-120`（点选 → 选项绿/红 + 地图 correctId 环 → `onAnswer(payload)`，payload 按 MapQuizAnswerPayload，`clue:''`）；isAnswered 恢复镜像 :53-86（含 payload 不可解析 → `feedbackSuppressed=true` + 已回答药丸守卫）。
- **MapLocateBody**：题干 name → `在地图上找到：${short}`；capital → `行政中心是「${capital}」的是哪个省？`；地图 `interactive=true`，`onPickProvince` → 即判：correct → correctId 环 + `找对位置啦！`；错 → targetId（金）+ wrongId（红）+ `这里是${name}，简称${abbr}，行政中心在${capital}。你点的是${picked.short}。`（原型文案）→ payload（`clue` 透传）。

- [ ] **Step 1: 实现 → assembleHap 绿 → Commit** `feat: add MapQuizCard router with choice and locate bodies`

---

### Task 12: MapWriteBody 写字题 body

**Files:**
- Create: `entry/src/main/ets/components/map/bodies/MapWriteBody.ets`

**Interfaces:**
- Consumes: Task 9 stage；Task 3 `getStrokeOrder()/hasStrokeOrder()`；Task 11 payload interface；`CardShellState`
- Produces: MapQuizCard 路由的 `write` 分支目标（签名同其它 body）

实现要点：
- 地图 target 高亮（interactive=false）+ 手写 Canvas：`onTouch` 三分支 Down/Move/Up 采集 points，逐字镜像 `HandwritingCard.ets:173-208`（`stopPropagation` + beginPath/moveTo/lineTo/stroke）；「擦掉重写」清空。**不导出 base64**（自评语义，spec §9.3 决策）。
- 「整字描红」toggle：Canvas 底层叠 ghost `Text(short)` 大号浅色（原型 traceGuide 同款；米字格不需要——省名多字横排）。
- 「笔顺演示」展开面板：short 名逐字一行——字样 + `N 画` + 笔画名串（`getStrokeOrder()` 的 label 拼接）+ 小 demo Canvas 逐笔播放（镜像 `startPlayback/tick/redrawDemoCanvas` :246-321，`TICK_MS≈33`、`FADE_PER_TICK=0.05`、`SVG_GRID=1024` **含 Y 翻转** `(1024 - y)`——与地图数据不同，汉字是 Y-up！每字一个 Canvas，tap 重播）；`hasStrokeOrder` 为 false 的字降级 ghost Text（HandwritingCard 同款）。
- 「写好了，看答案」→ 参考答案区 `${name}（${short}） · 简称 ${abbr}`（name===short 时省略括注，原型同款）→ 自评三按钮 `我写对了` / `再写一次`（清墨重写）/ `这次没写对，继续` → payload `correct` 按自评。

- [ ] **Step 1: 实现 → assembleHap 绿 → Commit** `feat: add MapWriteBody handwriting body with stroke demos`

---

### Task 13: MessageBubble 挂载（配方步骤 7）+ ChatMessageListSection

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`（import :31/:34/:54 附近；内联渲染 ForEach :2344 附近；or 链 :2857/:2933/:2943；谓词 :3135 附近；点击 :3574；路由 :4041；StepContent builder :4405 附近）
- Modify: `entry/src/main/ets/components/chat/ChatMessageListSection.ets`（:58 `@Event onOpenMapCardSheet/onOpenMapQuizSheet` 声明 + :499 附近透传）

**Interfaces:**
- Consumes: Task 10/11 卡片组件；Task 5 检查函数
- Produces: MessageBubble 两个 `@Event onOpenMapCardSheet: (toolCall: ToolCall) => void` / `onOpenMapQuizSheet` 同签名（Task 14 在 ChatPage 接线）

- [ ] **Step 1: 每工具 7 处挂载**——待答态渲染**入口横幅**（32×32 徽章 `sys.symbol.map` + `中国地图小课堂`/`中国地图出题` + `点击打开` + `>`，镜像 maze 横幅 :2167-2212，`.onClick` → `onOpenMapCardSheet(toolCall)`）；谓词 `shouldRenderMapCardInteractionCard` 镜像 :3135-3140；3 条 or 链、`handleToolStepClick`、路由、StepContent builder 全部镜像 hanzi_card 对应行；**StepContent 恢复：内联静态卡**（`isAnswered:true, answeredPayload: resolveStepAnswerPayload(step.toolResult, step.toolApprovalReason)`，spec §3.1 定案）。

- [ ] **Step 2: exact-line 检查**：

```bash
grep -n "isMapCardFunctionName" entry/src/main/ets/components/MessageBubble.ets
grep -n "isMapQuizFunctionName" entry/src/main/ets/components/MessageBubble.ets
```
期望每工具 ≥ 8 行，逐一核对属于：import、内联渲染、`isToolStepClickable`、`isToolStepExpanded`、`isDefaultExpanded`、`shouldRender…` 谓词、`handleToolStepClick`、步骤路由。多出的行逐个看上下文（typo 或串粘贴）。

- [ ] **Step 3: assembleHap 绿 → Commit** `feat: mount map cards in message bubble and list section`

---

### Task 14: ChatPage 双全屏 sheet + 语音 TTS 分支（配方步骤 8）

**Files:**
- Modify: `entry/src/main/ets/pages/ChatPage.ets`（状态 :310-315 附近；入口回调 :2528-2537 附近；bindSheet :2872-2932 附近；Sheet Builder :3419-3451 附近；TTS 白名单 :4824+；`buildQuizTtsText` :4873 附近）

**Interfaces:**
- Consumes: Task 13 的两个 @Event；Task 10/11 卡片；Task 6 ID 常量
- Produces: 完整端到端链路（无新接口）

- [ ] **Step 1: 两组 sheet 状态 + 入口回调**（`showMapCardSheet/mapCardToolCall/mapCardAnswered` + `showMapQuizSheet/…`，镜像 :313-315 与 :2533-2537 的 maze 写法，不合并泛化）

- [ ] **Step 2: 两个 bindSheet**——`SheetSize.LARGE + dragBar: true + showClose: true + blurStyle + preferType: SheetType.BOTTOM`；`onDisappear` 未答自动回放弃 payload：map_card → `{completed:false, focus_province:'', explored_count:0, skill_key:'general_social'}`；map_quiz → `{answered:false, mode:<args 解析>, province:<args 解析>, clue:'', child_answer:'', correct:false, cancelled:true, skill_key:'general_social'}`（镜像 maze onDisappear :2900-2932）；Sheet Builder 里 `largeSize:true` + `onAnswer` 设 answered 标记 + `onRequestClose` 关 sheet（map_card 提交后即关；map_quiz 即判即交后关）。

- [ ] **Step 3: TTS**——`tryAutoTtsForQuizInteraction` 白名单 +2；`buildQuizTtsText` 加两个分支，文案**逐字**：

| 分支 | 文本 |
|------|------|
| map_card | focus 解析非空 → `我们来看「${focus}」的地图课吧。`；否则 `点一点地图上的省份，认识它们吧。` |
| map_quiz choice | **固定串** `看地图上金色的省份，选一选它的名字。`（无任何插值——泄题红线） |
| map_quiz locate | clue=name → `在地图上找到${province}。`；clue=capital → `行政中心是「${capital}」的是哪个省？`（capital 从数据查，非 args） |
| map_quiz write | 固定串 `看地图上高亮的省份，把它的名字写下来。` |

- [ ] **Step 4: assembleHap 绿 → Commit** `feat: add map full-screen sheets and voice tts branches`

---

### Task 15: 标签改名 + 文档同步 + 终局 gauntlet

**Files:**
- Modify: `entry/src/main/ets/services/ChildProfileService.ets`（:61 `general_social` 显示 label `社交礼仪` → `社会常识`）
- Modify: `entry/src/main/ets/pages/LearningProfilePage.ets`（grep `社交礼仪` 硬编码处同步，行号实读）
- Modify: `.claude/rules/teaching-architecture.md`（§2.1 kids_chinese 锁定工具子集 + §4 工具表 + 小星老师锁定计数 23→25 + 讲解/练习二分清单）
- Modify: `CLAUDE.md`（互动卡片表 + 工具计数）
- Modify: `docs/superpowers/specs/2026-10-21-china-map-teaching-tools-design.md`（如实现中有偏离，回写勘误）

- [ ] **Step 1: 标签改名**：`grep -rn "社交礼仪" entry/src/main/ets/` 找全（预期 2 处），全改 `社会常识`；维度 key `general_social` 与 LLM 侧 schema 描述**不动**（spec §3.1 定案）。

- [ ] **Step 2: 终局 gauntlet 全跑**：JSON.parse gauntlet（Task 5 命令）、4-grep（Task 7 命令）、exact-line（Task 13 命令）、`grep -c "getBuiltinToolIds" 工具中心返回数组含 2 新 ID` 人工看一眼。

- [ ] **Step 3: assembleHap 绿 → Commit** `docs: sync teaching docs for map tools; rename general_social label`

- [ ] **Step 4: 真机安装验证**（spec §15 清单逐项）：AI 调 map_card 全屏地图可点/资料卡/TTS/focus 高亮；三 mode 各一题；星星面板标签正确（非 MAP_PUZZLE 兜底）；语文科今日 N 题计数 +2 类；会话切走放弃回执；历史恢复无假「再试一次」；语音 choice 不泄答案；default 与 kids_chinese 可触发、math/english/games 助手工具列表无此二工具；画像页显示「社会常识」。
