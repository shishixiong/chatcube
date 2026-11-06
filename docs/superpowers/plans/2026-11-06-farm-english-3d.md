# farm_english · 阳光农场 3D 英语探索 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 open-design 的「阳光农场 Sunny Farm」ArkWeb 原型接成 chatcube 的内置工具 `farm_english`，由小星老师 / 小星英语老师在英语词汇课中调用。

**Architecture:** `Web` 组件加载 `resource://rawfile/farm3d/index.html`（three.js 本地 UMD，离线）；`FarmNativeBridge` 注入原生 TTS；`FarmEnglishCard` 收集本次点开的单词并回执；后台 `ToolExecutionService.handleFarmEnglish` 预校验后挂起等待。讲解型不授星。

**Tech Stack:** ArkTS / ArkUI `@ComponentV2`、ArkWeb `Web` + `javaScriptProxy`、hvigor、hypium。

**Spec:** `docs/superpowers/specs/2026-11-06-farm-english-3d-design.md`

## Global Constraints

- 工具 id 固定 `farm_english`；`skill_key` 固定 `english_vocab`。
- 分区 id 固定：`overview` / `farmyard_zone` / `field_zone` / `pasture_zone` / `orchard_pond_zone`。
- 50 个单词 id 与原型 `farm-data.js` 完全一致，不重命名。
- 不授星：不改 `models/StarEventModels.ets`、`services/StarRewardService.ets`。
- TTS 语速 `0.8`，先中文后英文。
- 回执 `words` = 本次 sheet 会话点开的 id；`explored_count === words.length`。
- 所有 rawfile 资源只用相对路径，不联网、不依赖 `speechSynthesis`、不弹 `alert/confirm/prompt`。
- ArkTS 严格模式：对象字面量显式标注类型；不用解构；`ForEach` 回调内不写 `const x: Foo = {...}`。
- 本机构建命令：

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

## Review Focus

- **页面资源缺失**：`rawfile/farm3d/index.html` 任一 `./assets/*` 漏拷 → 页面空白或 404；打开 sheet 后应看到农场或明确错误面板，不能白屏。
- **AI 传了不存在的单词 id**：必须 `validation_failed + should_retry`，不得渲染空壳卡片。
- **历史收集启用提交**：孩子之前收集过单词、本次没点任何物体时，「我学会了」必须禁用，回执不能含历史词。
- **WebGL 失败**：ArkWeb 不支持 / 显存不足时应显示「3D 农场没有打开」+ 重新加载，而不是卡在 loading。
- **直接关 sheet**：未点「我学会了」关闭时必须回 `cancelled: true`，不能把 pending 工具卡永久挂起。

---

### Task 1: 搬运 rawfile 场景资源

**Files:**
- Create: `entry/src/main/resources/rawfile/farm3d/index.html`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm.css`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm-panel.css`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm-dialogs.css`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm-host.css`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm-data.js`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm-models.js`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/farm-app.js`
- Create: `entry/src/main/resources/rawfile/farm3d/assets/vendor/three.min.js`

**Interfaces:**
- Produces: 页面 URL `resource://rawfile/farm3d/index.html`；`window.FarmApp.{setHostMode,setView,select,openVocab,setNight,resetView}`；桥名 `FarmNativeBridge`；数据 `window.FarmData.objects`（50 条）。

- [ ] **Step 1: 整目录复制**

```bash
SRC="/Users/mac/Library/Application Support/Open Design/namespaces/release-stable-intel/data/projects/3b189cb2-2ebe-49da-bf8c-6f4d17bcf90a"
mkdir -p entry/src/main/resources/rawfile/farm3d
cp -R "$SRC/index.html" "$SRC/assets" entry/src/main/resources/rawfile/farm3d/
```

- [ ] **Step 2: 校验资源与语法**

```bash
ls entry/src/main/resources/rawfile/farm3d/assets/vendor/three.min.js
for f in farm-data farm-models farm-scene farm-app; do
  node --check "entry/src/main/resources/rawfile/farm3d/assets/$f.js" || exit 1
done
grep -c "phonetic:" entry/src/main/resources/rawfile/farm3d/assets/farm-data.js
grep -n "global.FarmApp\|FarmNativeBridge" entry/src/main/resources/rawfile/farm3d/assets/farm-app.js | head
```

Expected: `three.min.js` 存在；4 个 JS 无输出（语法通过）；`50`；能匹配到 `global.FarmApp` 与 `FarmNativeBridge`。

- [ ] **Step 3: 确认无网络 / 禁用 API**

```bash
grep -rnE "fetch\(|XMLHttpRequest|https?://|speechSynthesis|alert\(|confirm\(|prompt\(" \
  entry/src/main/resources/rawfile/farm3d/assets/*.js || echo "clean"
```

Expected: `clean`。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/resources/rawfile/farm3d
git commit -m "feat(farm): add offline sunny farm 3D scene assets"
```

---

### Task 2: 参数预校验 + hypium 测试

**Files:**
- Create: `entry/src/main/ets/utils/FarmEnglishValidation.ets`
- Create: `entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Produces:
  - `export const FARM_OBJECT_IDS: string[]`（50 条）
  - `export interface FarmEnglishValidationResult { ok: boolean; error: string; focus: string; words: string[] }`
  - `export function resolveFarmEnglishView(focus: string): string`
  - `export function validateFarmEnglishArgs(args: string): FarmEnglishValidationResult`

- [ ] **Step 1: 写失败测试**

`FarmEnglishValidation.test.ets` 镜像 `CityEnglishValidation.test.ets`，至少覆盖：

```ts
import { describe, it, expect } from '@ohos/hypium'
import { FARM_OBJECT_IDS, resolveFarmEnglishView, validateFarmEnglishArgs } from '../../../../main/ets/utils/FarmEnglishValidation'

export default function farmEnglishValidationTest() {
  describe('validateFarmEnglishArgs', () => {
    it('accepts minimal valid args', 0, () => {
      const r = validateFarmEnglishArgs('{"skill_key":"english_vocab"}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('overview')
      expect(r.words.length).assertEqual(0)
    })

    it('accepts every valid focus', 0, () => {
      const focuses = ['overview', 'farmyard_zone', 'field_zone', 'pasture_zone', 'orchard_pond_zone']
      for (let i = 0; i < focuses.length; i++) {
        const r = validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":"' + focuses[i] + '"}')
        expect(r.ok).assertTrue()
        expect(r.focus).assertEqual(focuses[i])
      }
    })

    it('normalizes all and empty focus to overview', 0, () => {
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":"all"}').focus).assertEqual('overview')
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":""}').focus).assertEqual('overview')
    })

    it('rejects unknown focus, wrong skill_key and malformed json', 0, () => {
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":"beach_zone"}').ok).assertFalse()
      expect(validateFarmEnglishArgs('{"skill_key":"general_social"}').ok).assertFalse()
      expect(validateFarmEnglishArgs('not json').ok).assertFalse()
    })

    it('rejects unknown word id and more than 8 words', 0, () => {
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","words":["cow","spaceship"]}').ok).assertFalse()
      const nine = FARM_OBJECT_IDS.slice(0, 9)
      const r = validateFarmEnglishArgs('{"skill_key":"english_vocab","words":["' + nine.join('","') + '"]}')
      expect(r.ok).assertFalse()
    })

    it('dedupes and rejects non-strings', 0, () => {
      const r = validateFarmEnglishArgs('{"skill_key":"english_vocab","words":["cow","cow","wheat"]}')
      expect(r.ok).assertTrue()
      expect(r.words.length).assertEqual(2)
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","words":[1,2]}').ok).assertFalse()
    })

    it('covers 50 unique farm objects', 0, () => {
      expect(FARM_OBJECT_IDS.length).assertEqual(50)
      for (let i = 0; i < FARM_OBJECT_IDS.length; i++) {
        expect(FARM_OBJECT_IDS.indexOf(FARM_OBJECT_IDS[i])).assertEqual(i)
      }
    })
  })

  describe('resolveFarmEnglishView', () => {
    it('keeps dedicated zones and falls back to overview', 0, () => {
      expect(resolveFarmEnglishView('farmyard_zone')).assertEqual('farmyard_zone')
      expect(resolveFarmEnglishView('orchard_pond_zone')).assertEqual('orchard_pond_zone')
      expect(resolveFarmEnglishView('all')).assertEqual('overview')
      expect(resolveFarmEnglishView('')).assertEqual('overview')
      expect(resolveFarmEnglishView('unknown')).assertEqual('overview')
    })
  })
}
```

在 `List.test.ets` 顶部 import 并在 `testsuite()` 中调用 `farmEnglishValidationTest()`（紧跟 `cityEnglishValidationTest()`）。

- [ ] **Step 2: 运行确认失败**

DevEco Studio 右键测试文件 → Run。Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现校验模块**

`FarmEnglishValidation.ets` 按 `CityEnglishValidation.ets` 写：JSON 解析失败 / `skill_key !== 'english_vocab'` / focus 非枚举 / words 非数组 / 非字符串 / 超过 8 / 不在 `FARM_OBJECT_IDS` 时返回 `ok:false, error:<中文可读信息>`；`all`/`''` → `overview`；去重保序。`FARM_OBJECT_IDS` 顺序：

```ts
places 10: farmhouse barn chicken_coop stable silo windmill greenhouse well gate fence
animals 14: cow pig sheep horse goat chicken rooster duck goose rabbit cat dog bee bird
crops 10: wheat corn potato carrot tomato pumpkin apple strawberry sunflower hay
machines 8: tractor trailer plow harvester wheelbarrow watering_can shovel pitchfork
nature 5: tree grass flower pond hill
people 3: farmer child grandma
```

`resolveFarmEnglishView` 只保留 5 个合法分区，其余返回 `'overview'`。

- [ ] **Step 4: 运行确认通过**

Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/utils/FarmEnglishValidation.ets \
  entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets \
  entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(farm): add farm_english args validation and tests"
```

---

### Task 3: 工具身份 + 注册（schema / executor / config）

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

**Interfaces:**
- Consumes: Task 2 的 `FARM_OBJECT_IDS` 文案（用于 schema 描述）。
- Produces:
  - `export const FARM_ENGLISH_TOOL_ID: string = 'farm_english'`
  - `export function isFarmEnglishFunctionName(functionName: string): boolean`
  - 已注册工具定义 `farm_english`，`getBuiltinToolIds()` 含它。

- [ ] **Step 1: 身份工具**

在 `SearchToolIdentityUtils.ets` 的 `CITY_ENGLISH_TOOL_ID` 旁加 `FARM_ENGLISH_TOOL_ID` 与 `isFarmEnglishFunctionName`；把 `isFarmEnglishFunctionName` 加入 `isInteractiveQuizFunctionName` 的 or 链末尾。

- [ ] **Step 2: 注册工具**

在 `BuiltinTools.ets` 的 city_english 段之后新增（import 处同步加 `FARM_ENGLISH_TOOL_ID`）：

```ts
interface FarmEnglishArgs {
  focus?: string
  words?: string[]
  skill_key: string
}

class FarmEnglishExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    try {
      const params = JSON.parse(_args) as FarmEnglishArgs
      return JSON.stringify({
        opened: true,
        focus: params.focus ?? 'overview',
        words: params.words ?? [],
        skill_key: 'english_vocab'
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`farm_english error: ${JSON.stringify(error)}`))
    }
  }
}
```

`createFarmEnglishToolDefinition()` 的 `rawSchemaJson`：

```json
{
  "type": "object",
  "properties": {
    "focus": {
      "type": "string",
      "enum": ["overview", "farmyard_zone", "field_zone", "pasture_zone", "orchard_pond_zone"],
      "description": "可选。本次重点探索的区域：overview=全农场（默认），farmyard_zone=农舍区（农舍 / 谷仓 / 鸡舍 / 马厩 / 筒仓 / 风车 / 水井 / 拖拉机），field_zone=田地区（小麦 / 玉米 / 土豆 / 胡萝卜 / 向日葵 / 温室），pasture_zone=牧场区（奶牛 / 绵羊 / 马 / 山羊 / 小山），orchard_pond_zone=果园池塘（苹果 / 草莓 / 池塘 / 鸭子 / 花）。传 all 等同于 overview。"
    },
    "words": {
      "type": "array",
      "items": { "type": "string" },
      "description": "可选。本次想重点教的单词 id，最多 8 个，传了会直接选中第一个词的单词卡。合法 id：地点 farmhouse barn chicken_coop stable silo windmill greenhouse well gate fence；动物 cow pig sheep horse goat chicken rooster duck goose rabbit cat dog bee bird；农作物 wheat corn potato carrot tomato pumpkin apple strawberry sunflower hay；农机 tractor trailer plow harvester wheelbarrow watering_can shovel pitchfork；自然 tree grass flower pond hill；人物 farmer child grandma。"
    },
    "skill_key": {
      "type": "string",
      "enum": ["english_vocab"],
      "description": "固定传 english_vocab（英语词汇）。"
    }
  },
  "required": ["skill_key"]
}
```

工具英文描述（`ToolFunction` 第二参）要点：`Open the 3D sunny farm` + 50 个可点对象分类 + 5 分区 + 点物体开单词卡（英文 / 音标 / 中文 / 儿童解释 / 例句 / TTS）；`Use this INSTEAD of describing a farm scene in plain text`；`After the receipt, follow up with english_quiz read_aloud to check and award stars`。

`createFarmEnglishToolConfig()`：名称 `阳光农场 3D 英语探索`，描述 `走进会动的 3D 农场：农舍、谷仓、奶牛、小麦、拖拉机、池塘，点一点听英文发音、看单词卡，认识 50 个农场单词。`，`BUILTIN` / `builtin` / `内置工具` / `READ`。

在 `registerBuiltinTools` 的 city_english 注册块后加 `if (!registry.isToolRegistered(FARM_ENGLISH_TOOL_ID)) { ... }`；`getBuiltinToolIds()` 数组末尾加 `FARM_ENGLISH_TOOL_ID`。

- [ ] **Step 3: JSON.parse 校验**

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const m=s.match(/function createFarmEnglishToolDefinition[\s\S]*?const rawSchemaJson: string = \`([\s\S]*?)\`/);if(!m)throw new Error('schema not found');JSON.parse(m[1]);console.log('schema ok')"
```

Expected: `schema ok`。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(farm): register farm_english tool"
```

---

### Task 4: 执行处理器 + 台账

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

**Interfaces:**
- Consumes: `FARM_ENGLISH_TOOL_ID`、`isFarmEnglishFunctionName`、`validateFarmEnglishArgs`。
- Produces: `private async handleFarmEnglish(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult>`；分发在 `resolveToolId` 兜底之前。

- [ ] **Step 1: 加 import**

`FARM_ENGLISH_TOOL_ID` / `isFarmEnglishFunctionName` 加入现有 `SearchToolIdentityUtils` import 块；新增 `import { validateFarmEnglishArgs } from '../utils/FarmEnglishValidation'`。

- [ ] **Step 2: 实现 handler**

完整镜像 `handleCityEnglish`（同文件），只改文案与 id：

- `toolCall.toolId = FARM_ENGLISH_TOOL_ID`
- 默认 `displayName = '阳光农场 3D 英语探索'`
- 预校验失败：`approvalState='denied'`，返回 `JSON.stringify({ error: 'validation_failed', message, should_retry: true })`
- 通过后 `approvalState='pending'` + `this.recordLedgerServed('farm_english', toolCall, context)`
- pending resolve / 取消 / answered 三段与 city 完全一致；取消文案 `小朋友未完成本课学习`。

- [ ] **Step 3: 分发 + taughtOnly**

在 `executeToolCall` 的 city_english 分支后加：

```ts
if (isFarmEnglishFunctionName(normalizedFunctionName)) {
  return await this.handleFarmEnglish(toolCall, context)
}
```

`recordLedgerServed` 内 `const taughtOnly = toolId === 'room_english' || toolId === 'city_english'` 改为末尾追加 `|| toolId === 'farm_english'`。

- [ ] **Step 4: 编译**

运行 Global Constraints 的 `assembleHap`。Expected: BUILD SUCCESS。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat(farm): handle farm_english tool interactions"
```

---

### Task 5: 助手白名单与提示词

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`

**Interfaces:**
- Consumes: `FARM_ENGLISH_TOOL_ID`。

- [ ] **Step 1: 白名单**

- import 块加 `FARM_ENGLISH_TOOL_ID`（与 `CITY_ENGLISH_TOOL_ID` 相邻）。
- `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 数组：`CITY_ENGLISH_TOOL_ID` 后加 `FARM_ENGLISH_TOOL_ID`。
- `KIDS_ENGLISH_LOCKED_TOOL_IDS`：`CITY_ENGLISH_TOOL_ID` 后加 `FARM_ENGLISH_TOOL_ID`。

- [ ] **Step 2: 默认助手提示词段**

在 `'## 小词城 3D 英语探索'` 后新增一条字符串：

```
'## 阳光农场 3D 英语探索\n孩子学农场/动物/农作物/农机/自然类词汇(cow、wheat、tractor、barn、farmer、pond…)时,先开 farm_english 走进 3D 阳光农场:用 words 传 3-8 个目标词,卡片会自动选中第一个词的单词卡;可用 focus 指定 overview / farmyard_zone / field_zone / pasture_zone / orchard_pond_zone 打开对应区域。农场里有转动的风车、吃草的奶牛、行驶的拖拉机和池塘里的鸭子,孩子可以一边逛一边听发音、看解释。回执带 explored_count 与本次实际点开的 words;讲解完立刻用 english_quiz(mode:「read_aloud」)复测 2-3 个目标词并授星(农场词不要用 picture_word,本地没有对应图片)——farm_english 本身不授星。一次课不要点开超过 8 个词,聚焦比刷量重要。\n',
```

- [ ] **Step 3: 小星英语老师提示词段**

在 `'  ②-2 城市词汇:...'` 后新增：

```
'  ②-3 农场词汇:学农场/动物/农作物/农机/自然词汇时改用 farm_english,用 words 传 3-8 个目标词,focus 可选 overview / farmyard_zone / field_zone / pasture_zone / orchard_pond_zone;卡片会选中第一个单词卡,孩子点「我学会了」回执带本次实际点开的 words;随后用 english_quiz(mode:"read_aloud") 复测 2-3 个词并授星。农场词不要用 picture_word(本地词库没有对应图片)。',
```

- [ ] **Step 4: 对账 + 编译**

```bash
grep -c "FARM_ENGLISH_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets   # ≥ 3
grep -c "farm_english" entry/src/main/ets/models/AssistantModels.ets           # ≥ 3
```

运行 `assembleHap`。Expected: BUILD SUCCESS。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(farm): expose farm_english to default and english teachers"
```

---

### Task 6: FarmEnglishCard

**Files:**
- Create: `entry/src/main/ets/components/farm/FarmEnglishCard.ets`

**Interfaces:**
- Consumes: `validateFarmEnglishArgs`、`resolveFarmEnglishView`、`ServiceRegistry.tts()`、`getAppUiState()`、`withColorAlpha`。
- Produces:
  - `export interface FarmEnglishAnswerPayload { completed: boolean; explored_count: number; words: string[]; focus: string; skill_key: string; cancelled: boolean }`
  - `export interface FarmEnglishArgsView { valid: boolean; focus: string; words: string[] }`
  - `export function parseFarmEnglishArgs(raw: string): FarmEnglishArgsView`
  - `@ComponentV2 export struct FarmEnglishCard`（`@Param toolCall/isAnswered/answeredPayload/largeSize`，`@Event onAnswer/onRequestClose`）

- [ ] **Step 1: 以 CityEnglishCard 为骨架新建**

复制 `components/city/CityEnglishCard.ets` 到 `components/farm/FarmEnglishCard.ets`，做以下替换：

- 页面 URL：`resource://rawfile/farm3d/index.html`
- 标题：`阳光农场 3D 英语探索`
- 空态副标题：`农舍、田地、牧场、果园池塘，点一点就知道它叫什么`
- 加载文案：`正在播种阳光农场…`
- 错误标题：`3D 农场没有打开`
- 桥类名：`FarmNativeBridge`；`methodList: ['speak','stopSpeak','onReady','onSelect','onProgress']`
- 页面控制对象：`window.FarmApp`
- 常量 `FARM_OBJECT_TOTAL = 50`

- [ ] **Step 2: 双集合状态**

新增/替换状态：

```ts
@Local sessionIds: string[] = []      // 本次会话点开
@Local discoveredIds: string[] = []   // 历史累计（仅 Header N/50）
@Local lookup: Map<string, string> = new Map<string, string>()
```

- `noteSelected(id, word)`：`lookup` 记录；`sessionIds` 与 `discoveredIds` 各自去重追加。
- `applyProgress(idsJson)`：只覆盖 `discoveredIds`。
- `exploredCount` getter = `sessionIds.length`；`discoveredCount` getter = `discoveredIds.length`。
- `exploredWords` 从 `sessionIds` 映射 `lookup`。
- `canSubmit()`：`!isAnswered && !submitted && sessionIds.length > 0`。
- `buildPayload`：`words = sessionIds 副本`，`explored_count = words.length`。
- `readAnsweredPayload`：`words` 写入 `sessionIds`；`hasCompleted` 照旧。

Header 副标题：

```ts
private get headerSubtitle(): string {
  if (this.sessionIds.length > 0) {
    return `本次 ${this.sessionIds.length} 个 · 农场收集 ${this.discoveredIds.length} / ${FARM_OBJECT_TOTAL}`
  }
  return `农场收集 ${this.discoveredIds.length} / ${FARM_OBJECT_TOTAL} · 点一点农场听英文`
}
```

- [ ] **Step 3: 页面控制**

`applyFocusWords()`：

```ts
const view = resolveFarmEnglishView(this.argsView.focus)
const first = this.argsView.words.length > 0 ? `'${this.argsView.words[0]}'` : 'null'
const script = `(function(){try{var app=window.FarmApp;if(!app){return;}app.setHostMode(true);` +
  `if(${first}){app.select(${first});}else{app.setView('${view}');}}catch(e){}})();`
```

`openVocab()` → `app.openVocab()`；`toggleNight()` → `app.setNight(on)`；错误重试用 `controller.refresh()`。

- [ ] **Step 4: UI**

HeaderBar 保持 city 结构：标题列（Flex layoutWeight 1）+「词汇表」胶囊 + 圆形 🌙/☀️ +「我学会了」胶囊。按钮可达高度 ≥ 30vp（保持 city 尺寸）。SummaryView 文案：

- 完成：`阳光农场探索完成`
- 未完成：`这次没有探索完`
- 计数：`一共点开了 ${exploredCount} 个单词`
- chips：`exploredWords`，key 前缀 `farm_word_`

`build()` 外壳背景：暗色 `#1A1510`，浅色 `#FFF8E7`（与原型主题色一致）。`isAnswered` 只渲染 SummaryView。

- [ ] **Step 5: 编译**

运行 `assembleHap`。Expected: BUILD SUCCESS。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/components/farm/FarmEnglishCard.ets
git commit -m "feat(farm): add FarmEnglishCard web container"
```

---

### Task 7: MessageBubble + ChatMessageListSection

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`
- Modify: `entry/src/main/ets/components/chat/ChatMessageListSection.ets`

**Interfaces:**
- Consumes: `isFarmEnglishFunctionName`、`readFarmEnglishWords`（内部函数）。
- Produces: `@Event onOpenFarmEnglishSheet: (toolCall: ToolCall) => void`；待答横幅；timeline step 回看。

- [ ] **Step 1: 函数名 import + payload 读取**

- `MessageBubble.ets` 顶部 import 块加 `isFarmEnglishFunctionName`。
- 在 `readCityEnglishWords` 后加：

```ts
/** farm_english 回执里的 words（本次点开的单词 id 列表），结构同 room/city。 */
function readFarmEnglishWords(payload: string): string[] {
  return readRoomEnglishWords(payload)
}
```

- [ ] **Step 2: @Event**

在 `@Event onOpenCityEnglishSheet` 后加：

```ts
@Event onOpenFarmEnglishSheet: (toolCall: ToolCall) => void = () => {}
```

- [ ] **Step 3: 待答横幅**

在 city_english 的待答 ForEach 后，复制一段 farm 横幅：

- `shouldRenderFarmEnglishInteractionCard(toolCall, index)`：同 city 判定。
- 图标 `SymbolGlyph($r('sys.symbol.leaf'))`（若编译报未知 symbol，改用 `$r('sys.symbol.house')`——先用 `leaf` 试编译）。
- 标题 `阳光农场 3D 英语探索`，副标题 `点击走进农场`。
- `onClick` → `this.onOpenFarmEnglishSheet(toolCall)`。
- ForEach key 前缀 `farm_english_`。

- [ ] **Step 4: 五处 step 接线**

按 city 的 5 个位置逐一加 farm 分支：

1. `handleToolStepClick`：`if (isFarmEnglishFunctionName(part.toolName)) { this.toggleToolStep(part); return }`
2. 两个 `or` 链（`isToolStepClickable` / 默认展开相关）：各追加 `|| isFarmEnglishFunctionName(part.toolName)` / `step.toolName`。
3. step content 的 `else if` 级联：`else if (isFarmEnglishFunctionName(step.toolName)) { this.FarmEnglishStepContent(step) }`
4. 新增 `@Builder FarmEnglishStepContent(step: MessagePart)` 与 `@Builder FarmEnglishStepSummary(step: MessagePart)`——复制 city 版，chips key 前缀 `farm_step_word_`，payload 用 `readFarmEnglishWords(...)`。

- [ ] **Step 5: 事件透传**

`ChatMessageListSection.ets`：

- `@Event onOpenFarmEnglishSheet`（同 city）。
- 在传参处加 `onOpenFarmEnglishSheet: (toolCall: ToolCall): void => { this.onOpenFarmEnglishSheet(toolCall) }`。

- [ ] **Step 6: 精确对账**

```bash
grep -n "isFarmEnglishFunctionName" entry/src/main/ets/components/MessageBubble.ets
```

Expected: 6 处（import + 待答 helper + handleToolStepClick + 2 or 链 + step cascade）。多出的行检查是否为拼写错误。另：

```bash
grep -c "@Builder" entry/src/main/ets/components/MessageBubble.ets
git diff entry/src/main/ets/components/MessageBubble.ets | grep "^+" | grep -c "@Builder"
```

确认新增 builder 数量与 `@Builder` 增量为 2，且相邻 builder 的装饰器没有被吃掉。

- [ ] **Step 7: 编译 + 提交**

运行 `assembleHap`。Expected: BUILD SUCCESS。

```bash
git add entry/src/main/ets/components/MessageBubble.ets entry/src/main/ets/components/chat/ChatMessageListSection.ets
git commit -m "feat(farm): render farm_english banner and timeline steps"
```

---

### Task 8: ChatPage 全屏 sheet

**Files:**
- Modify: `entry/src/main/ets/pages/ChatPage.ets`

**Interfaces:**
- Consumes: `FarmEnglishCard` / `FarmEnglishAnswerPayload`、`onOpenFarmEnglishSheet`。
- Produces: `showFarmEnglishSheet` / `farmEnglishToolCall` / `farmEnglishAnswered` 状态与 `FarmEnglishSheetBuilder()`。

- [ ] **Step 1: import + 状态**

- `import { FarmEnglishAnswerPayload, FarmEnglishCard } from '../components/farm/FarmEnglishCard'`
- 在 `showCityEnglishSheet` 状态组后加：

```ts
@Local showFarmEnglishSheet: boolean = false
@Local farmEnglishToolCall: ToolCall = new ToolCall()
@Local farmEnglishAnswered: boolean = false
```

- [ ] **Step 2: 事件**

在 `onOpenCityEnglishSheet` 回调后加：

```ts
onOpenFarmEnglishSheet: (toolCall: ToolCall): void => {
  this.farmEnglishToolCall = toolCall
  this.farmEnglishAnswered = false
  this.showFarmEnglishSheet = true
},
```

- [ ] **Step 3: bindSheet**

在 city 的 `bindSheet` 后复制一份，替换状态 / builder / 取消 payload：

```ts
Column()
  .width(0)
  .height(0)
  .bindSheet($$this.showFarmEnglishSheet, this.FarmEnglishSheetBuilder(), {
    height: SheetSize.LARGE,
    dragBar: true,
    showClose: true,
    blurStyle: BlurStyle.Thick,
    backgroundColor: this.themeBackground,
    preferType: SheetType.BOTTOM,
    onDisappear: () => {
      if (this.showFarmEnglishSheet && !this.farmEnglishAnswered) {
        const cancelResult: FarmEnglishAnswerPayload = {
          completed: false,
          explored_count: 0,
          words: [],
          focus: 'overview',
          skill_key: 'english_vocab',
          cancelled: true
        }
        this.handleAskUserAnswer(this.farmEnglishToolCall.id, JSON.stringify(cancelResult))
      }
      this.showFarmEnglishSheet = false
    }
  })
```

- [ ] **Step 4: builder**

```ts
@Builder
FarmEnglishSheetBuilder() {
  FarmEnglishCard({
    toolCall: this.farmEnglishToolCall,
    isAnswered: false,
    answeredPayload: '',
    largeSize: true,
    onAnswer: (toolCallId: string, answerJson: string): void => {
      this.farmEnglishAnswered = true
      this.handleAskUserAnswer(toolCallId, answerJson)
      this.showFarmEnglishSheet = false
    },
    onRequestClose: (): void => {
      this.showFarmEnglishSheet = false
    }
  })
}
```

- [ ] **Step 5: 编译 + 提交**

运行 `assembleHap`。Expected: BUILD SUCCESS。

```bash
git add entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(farm): open farm_english in full-screen sheet"
```

---

### Task 9: 台账 / 图标 / 儿童目录 / 文档

**Files:**
- Modify: `entry/src/main/ets/utils/LedgerExtractUtils.ets`
- Modify: `entry/src/main/ets/utils/ToolIconMapping.ets`
- Modify: `entry/src/main/ets/components/kids/KidsSubjectCatalog.ets`
- Modify: `.claude/rules/teaching-architecture.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: 无（纯配置/数据）。
- Produces: 台账曝光词、工具图标、学科目录同步、文档。

- [ ] **Step 1: 台账**

`LedgerExtractUtils.ets`：

- 复制 `cityEnglishItems` 为 `farmEnglishItems`，`compositeMode('farm_english', '')`，逻辑不变（words 下划线转空格逐项入账）。
- `extractLedgerItemsFromTool` 的 city 分支后加 `if (toolId === 'farm_english') { return farmEnglishItems(parsed) }`。
- `extractLedgerAnswerItems` 的讲解型列表加 `|| toolId === 'farm_english'`。

- [ ] **Step 2: 图标**

`ToolIconMapping.ets`：`CITY_KEYWORDS` 旁加 `const FARM_KEYWORDS: string[] = ['farm_english']`，并把 `FARM_KEYWORDS` 接入现有 `matchesAny` 判定链（与 city/room 同位置）。

- [ ] **Step 3: 儿童学科目录**

`KidsSubjectCatalog.ets` 英语 `activityTypes` 末尾加 `'farm_english'`（仅配置同步；该计数只读 star_events，farm 不产生星）。

- [ ] **Step 4: 文档**

- `.claude/rules/teaching-architecture.md`：§2.1 `kids_english` 锁定工具子集加 `farm_english`；§4 工具表加一行（讲解型、不授星、50 词/5 分区）；§10 触点无需新增（已覆盖）。
- `CLAUDE.md`：工具表加 `farm_english` 行；外部资源说明提到 `rawfile/farm3d/`。

- [ ] **Step 5: 编译 + 提交**

运行 `assembleHap`。Expected: BUILD SUCCESS。

```bash
git add entry/src/main/ets/utils/LedgerExtractUtils.ets \
  entry/src/main/ets/utils/ToolIconMapping.ets \
  entry/src/main/ets/components/kids/KidsSubjectCatalog.ets \
  .claude/rules/teaching-architecture.md CLAUDE.md
git commit -m "feat(farm): wire ledger, icon, kids catalog and docs"
```

---

### Task 10: 最终验收

**Files:** 无新增。

- [ ] **Step 1: 全量构建**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: `BUILD SUCCESS`，产物 `entry/build/default/outputs/default/entry-default-signed.hap`。

- [ ] **Step 2: 检查 drift 文件未被误改**

```bash
git diff --stat HEAD~9 -- entry/src/main/ets/models/StarEventModels.ets entry/src/main/ets/services/StarRewardService.ets
```

Expected: 空输出。

- [ ] **Step 3: 真机手点验收**

按 spec §8 清单逐项：横幅 → 全屏 sheet → 渲染 → 点奶牛发音 → words/focus 直达 → 词汇表 / 黄昏 → 本次门槛 → 关闭取消 → 非法参数 should_retry → 无星星 → 时间线 chips。

- [ ] **Step 4: 提交（如有验收修正）**

```bash
git add -A && git commit -m "fix(farm): address device acceptance findings"
```

---

## Self-Review

- **Spec coverage**：§1-§10 均映射到 Task 1-10；§4 工具契约 → Task 3/4；§5 卡片/桥/会话态 → Task 6；§6 接入点 → Task 2-9；§8 验收 → Task 10。
- **Type consistency**：`FarmEnglishAnswerPayload` / `FarmEnglishArgsView` / `parseFarmEnglishArgs` / `validateFarmEnglishArgs` / `resolveFarmEnglishView` 在 Task 2/6/8 中命名一致。
- **Review Focus**：资源缺失 → Task 1 Step 2/3；非法 id → Task 2 Step 1 + Task 4 Step 2；历史收集启用提交 → Task 6 Step 2 + Task 10 Step 3；WebGL 失败 → Task 6 Step 3/4（错误面板）；关 sheet 取消 → Task 8 Step 3。
