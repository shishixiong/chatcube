# Numberblocks 认数字卡片（number_blocks）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `number_blocks` 讲解型工具——全屏 Web 场景展示 20 个 CSS 3D Numberblocks 角色，孩子从缩略长廊自选、放大到舞台、听原生 TTS 念数字。

**Architecture:** 完全镜像 `farm_english` 的「rawfile 本地网页 + javaScriptProxy 桥 + ChatPage 全屏 sheet」范式。原生只负责标题栏、TTS、进度与回执；20 个角色的 3D 造型、长廊、舞台、自动巡游全部在 `rawfile/numberblocks/` 里用 CSS 3D 实现（参考稿零依赖，不引入 three.js）。

**Tech Stack:** ArkTS / ArkUI V2（`@ComponentV2`、`@Local`、`@Param`、`@Event`）、ArkWeb（`webview.WebviewController` + `javaScriptProxy`）、原生 CSS 3D（`transform-style: preserve-3d`）、hypium 单测。

**Spec:** `docs/superpowers/specs/2026-11-14-numberblocks-card-design.md`

## Global Constraints

- 工具 id 恒为 `number_blocks`；`skill_key` 恒为 `math_counting`；`mode` v1 只接受 `display`
- 讲解型：**不调 `recordStarEvent`**，不改 `models/StarEventModels.ets` / `services/StarRewardService.ets`
- 锁给 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` + `KIDS_MATH_LOCKED_TOOL_IDS`，不进其它学科助手
- ArkTS 严格模式：禁止解构赋值；`ForEach` 回调体内不得写 `const x: T = {...}`；内联对象字面量必须显式标注类型
- `rawfile` 网页用 `resource://rawfile/numberblocks/index.html` 加载，页面内 `./assets/*.js` 由 ArkWeb 同源解析
- ArkWeb 没有 `speechSynthesis`，发音必须经 `javaScriptProxy` 转原生 `ServiceRegistry.tts()`
- `rawSchemaJson` 模板字符串里的描述文本**禁止出现 ASCII 双引号**，引用一律用 `「」`
- `$r('sys.symbol.X')` 只能用白名单：`plus` / `doc_plaintext` / `AI_pencil` / `folder` / `lightbulb` / `wand_and_stars` / `checkmark_circle` / `xmark_circle` / `chevron_down` / `pause` / `speaker_wave_2` / `translate` / `dot_grid_2x2` / `arrow_clockwise` / `checkmark_square_on_square`
- 构建：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
- 单测只能在 DevEco Studio 里跑（`hvigorw test` 在本仓是坏的），纯逻辑套件也可走 node shim

## Review Focus

1. **`numbers` 的畸形输入**：传 `[]` / 非数组 / 小数 / 大于 20 / 重复值时，卡片必须正常打开（回落到全部 20），而不是白屏或渲染出 0 号格子
2. **TTS 叠音**：快速连点不同数字时，旧朗读必须被 `stopSpeak()` 截断，不能两条声音叠在一起
3. **巡游中的生命周期**：自动巡游时点返回 / 下拉收起 sheet / 退出页面，计时器和朗读都必须停——否则页面销毁后仍在念数字
4. **舞台边界**：1 号左滑、20 号右滑不越界；长廊只有 20 格，不存在 0 或 21
5. **窄屏溢出**：320vp 宽的手机上 5 列 × 4 行仍要一屏放下、不横向溢出；平板宽屏不把格子拉成畸形

---

### Task 1: 参数校验纯函数 + hypium 单测

**Files:**
- Create: `entry/src/main/ets/utils/NumberBlocksValidation.ets`
- Create: `entry/src/ohosTest/ets/test/utils/NumberBlocksValidation.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（import + 调用）

**Interfaces:**
- Produces:
  - `export const NUMBER_BLOCKS_MAX: number = 20`
  - `export function allNumberBlocks(): number[]` — 返回 `[1,2,…,20]`
  - `export interface NumberBlocksValidationResult { ok: boolean; error: string; numbers: number[]; focus: number; mode: string }`
  - `export function validateNumberBlocksArgs(args: string): NumberBlocksValidationResult`
  - 成功时 `numbers` 为 1–20 升序去重的子集，`[]` 表示「全部」；`focus` 恒在 1–20；`mode` 恒为 `'display'`
  - 失败时 `ok=false` 且 `error` 是给 LLM 看的中文原因

- [ ] **Step 1: 写失败测试**

`entry/src/ohosTest/ets/test/utils/NumberBlocksValidation.test.ets`：

```ts
import { describe, it, expect } from '@ohos/hypium'
import {
  allNumberBlocks,
  NUMBER_BLOCKS_MAX,
  validateNumberBlocksArgs
} from '../../../../main/ets/utils/NumberBlocksValidation'

export default function numberBlocksValidationTest() {
  describe('NumberBlocksValidation', () => {
    it('全部数字是 1..20', 0, () => {
      const all = allNumberBlocks()
      expect(all.length).assertEqual(NUMBER_BLOCKS_MAX)
      expect(all[0]).assertEqual(1)
      expect(all[19]).assertEqual(20)
    })

    it('空对象合法，numbers 为空表示全部', 0, () => {
      const r = validateNumberBlocksArgs('{}')
      expect(r.ok).assertTrue()
      expect(r.numbers.length).assertEqual(0)
      expect(r.focus).assertEqual(1)
      expect(r.mode).assertEqual('display')
    })

    it('numbers 去重并升序', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[3,1,2,3]}')
      expect(r.ok).assertTrue()
      expect(r.numbers.length).assertEqual(3)
      expect(r.numbers[0]).assertEqual(1)
      expect(r.numbers[2]).assertEqual(3)
    })

    it('focus 不在 numbers 里时回落到第一个', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[4,5],"focus":9}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual(4)
    })

    it('focus 在 numbers 里时保留', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[4,5,6],"focus":5}')
      expect(r.focus).assertEqual(5)
    })

    it('拒绝超出 1-20 的数字', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[0,21]}')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('拒绝非整数', 0, () => {
      expect(validateNumberBlocksArgs('{"numbers":[1.5]}').ok).assertFalse()
      expect(validateNumberBlocksArgs('{"focus":2.5}').ok).assertFalse()
    })

    it('拒绝非数组 numbers', 0, () => {
      expect(validateNumberBlocksArgs('{"numbers":"3"}').ok).assertFalse()
    })

    it('拒绝 v1 不支持的 mode', 0, () => {
      expect(validateNumberBlocksArgs('{"mode":"split"}').ok).assertFalse()
      expect(validateNumberBlocksArgs('{"mode":"display"}').ok).assertTrue()
    })

    it('拒绝坏 JSON 与非对象 JSON', 0, () => {
      expect(validateNumberBlocksArgs('not json').ok).assertFalse()
      expect(validateNumberBlocksArgs('null').ok).assertFalse()
      expect(validateNumberBlocksArgs('[1,2]').ok).assertFalse()
    })
  })
}
```

`List.test.ets` 加 `import numberBlocksValidationTest from './utils/NumberBlocksValidation.test';` 和函数体末尾 `numberBlocksValidationTest();`。

- [ ] **Step 2: 跑测试确认失败**

DevEco Studio 右键测试文件 → Run。预期：`NumberBlocksValidation` 模块 not found / import 报错。

- [ ] **Step 3: 实现 `utils/NumberBlocksValidation.ets`**

结构照抄 `utils/FarmEnglishValidation.ets`：一个 `fail(msg)` 私有工厂 + 一个 `validateNumberBlocksArgs`。规则依次为——`JSON.parse` 失败 / 非对象（`null`、数组、标量）→ fail；`mode` 若不是 `'display'` → fail；`focus` 若不是 1–20 整数 → fail；`numbers` 若不是数组 → fail，逐项要求整数且 1–20，去重后 `sort((a,b)=>a-b)`；`focus` 缺省取 `numbers[0]`，若不在集合里同样回落到 `numbers[0]`，集合为空则取 `1`。

- [ ] **Step 4: 跑测试确认全绿**

DevEco Studio → Run。预期 10 个用例全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/utils/NumberBlocksValidation.ets \
        entry/src/ohosTest/ets/test/utils/NumberBlocksValidation.test.ets \
        entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(number_blocks): 参数预校验纯函数 + hypium 单测"
```

---

### Task 2: 工具身份常量 + BuiltinTools 注册

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`（常量区 L53 附近、函数区 L222 附近、分发列表 L309 附近）
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`（import 块 L20-56、Executor L4236 附近、Definition/Config L4256 附近、注册 L4719 附近、`getBuiltinToolIds` L4738）

**Interfaces:**
- Produces:
  - `export const NUMBER_BLOCKS_TOOL_ID: string = 'number_blocks'`
  - `export function isNumberBlocksFunctionName(functionName: string): boolean`
  - `interface NumberBlocksArgs { numbers?: number[]; focus?: number; mode?: string }`
  - `class NumberBlocksExecutor implements ToolExecutor`
  - `function createNumberBlocksToolDefinition(): ToolDefinition`
  - `function createNumberBlocksToolConfig(): ToolConfig`

- [ ] **Step 1: 加工具身份**

`SearchToolIdentityUtils.ets` 在 `FARM_ENGLISH_TOOL_ID` 后加常量；在 `isFarmEnglishFunctionName` 后加同构函数（`normalizeToolFunctionName(functionName) === NUMBER_BLOCKS_TOOL_ID`）；把它接进 L309 那个「是否互动卡片工具」的函数名分发列表。

- [ ] **Step 2: 加 schema / executor / config / 注册**

`BuiltinTools.ets`：
1. import 块加 `NUMBER_BLOCKS_TOOL_ID`
2. `NumberBlocksArgs`（三个字段全部可选）
3. `NumberBlocksExecutor.execute` 返回 `{opened:true, numbers, focus, mode, skill_key:'math_counting'}`（与 `FarmEnglishExecutor` 同构）
4. `createNumberBlocksToolDefinition` 的 `rawSchemaJson`：

```json
{
  "type": "object",
  "properties": {
    "numbers": {
      "type": "array",
      "items": { "type": "integer", "minimum": 1, "maximum": 20 },
      "description": "今天重点认识的数字, 1-20。长廊永远展示全部 20 个, 这些数字额外挂重点标记, 自动巡游只走这些; 不填 = 全部"
    },
    "focus": {
      "type": "integer",
      "minimum": 1,
      "maximum": 20,
      "description": "打开时长廊里高亮一次的格子, 不自动进舞台; 不填 = numbers 第一个"
    },
    "mode": {
      "type": "string",
      "enum": ["display"],
      "description": "v1 固定 display（认数字）。不要传其它值"
    }
  }
}
```

功能描述用英文（与 farm 一致），必须包含：这是讲解型卡片、长廊让孩子自选、点开即朗读中英文、**本身不判对错不授星**、看完可用 `math_quiz` / `picture_vocab` 复测。所有引号用 `「」`。

5. `createNumberBlocksToolConfig`：displayName `认数字 Numberblocks`，description `看看 20 个数字方块小人长什么样，点一点听数字，认识 1-20。`，参数与 `createFarmEnglishToolConfig` 完全同构（`true, false, ToolSourceType.BUILTIN, 'builtin', NUMBER_BLOCKS_TOOL_ID, '内置工具', ToolPermissionLevel.READ`）
6. `registerBuiltinTools` 末尾加 `if (!registry.isToolRegistered(NUMBER_BLOCKS_TOOL_ID)) { ... }` 块
7. `getBuiltinToolIds()` 数组末尾追加 `NUMBER_BLOCKS_TOOL_ID`

- [ ] **Step 3: 跑 JSON.parse 关卡**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const blocks=s.split('const rawSchemaJson: string = \`');let n=0;for(let i=1;i<blocks.length;i++){const body=blocks[i].split('\`')[0];JSON.parse(body);n++;}console.log('parsed',n,'schemas OK')"
```

预期：`parsed N schemas OK`，无异常抛出。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(number_blocks): 工具身份常量与 BuiltinTools 注册"
```

---

### Task 3: ToolExecutionService 特殊路径

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`（import L70/L78 附近、`handleFarmEnglish` L2103 附近之后、dispatch L3894 附近）

**Interfaces:**
- Consumes: `NUMBER_BLOCKS_TOOL_ID`、`isNumberBlocksFunctionName`、`validateNumberBlocksArgs`
- Produces: `private async handleNumberBlocks(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult>`

- [ ] **Step 1: 抄 handler**

完整镜像 `handleFarmEnglish`（L2103-2200 区间），逐项替换名字。必须保留的行为：
- 开头设 `toolCall.toolId`、`displayName` 缺省 `认数字 Numberblocks`、`sourceType`、`sourceLabel`、`permissionLevel = ToolPermissionLevel.READ`
- 先 `validateNumberBlocksArgs(toolCall.arguments)`；失败 → `approvalState='denied'` + `{error:'validation_failed', message, should_retry:true}`
- `approvalState='pending'` + `recordLedgerServed('number_blocks', toolCall, context)` + `PendingToolAnswerRuntime` 注册与 `publishPendingInteractionChanged()`
- 取消 / `null` 回答的路径与 farm 一致
- **不调 `recordStarEvent`**

- [ ] **Step 2: 加 dispatch 分支**

放在 `isFarmEnglishFunctionName` 那个分支之后、`const toolId = this.resolveToolId(...)` **之前**：

```ts
    // === number_blocks 特殊路径 ===
    // 认数字 Numberblocks 讲解卡, 由 NumberBlocksCard 收集「我学会了」完成回执。
    if (isNumberBlocksFunctionName(normalizedFunctionName)) {
      return await this.handleNumberBlocks(toolCall, context)
    }
```

- [ ] **Step 3: 校验落点**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && grep -n "isNumberBlocksFunctionName\|handleNumberBlocks\|recordStarEvent" entry/src/main/ets/services/ToolExecutionService.ets | sed -n '1,60p'
```

预期：`isNumberBlocksFunctionName` 出现在 import + dispatch 两处；`handleNumberBlocks` 出现在定义 + dispatch 两处；`handleNumberBlocks` 函数体（定义行到下一个 `private async`）之间**没有** `recordStarEvent`。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat(number_blocks): 工具执行特殊路径与分发分支"
```

---

### Task 4: 助手锁定 + 系统提示词

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`（import L11-40 附近、`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` L120-155、`KIDS_MATH_LOCKED_TOOL_IDS` L186-190、默认助手提示词的工具调用规则段）

**Interfaces:**
- Consumes: `NUMBER_BLOCKS_TOOL_ID`
- Produces: 无代码接口；两条锁定列表各含 `NUMBER_BLOCKS_TOOL_ID`

- [ ] **Step 1: 加 import 与两处锁定**

`import { ..., NUMBER_BLOCKS_TOOL_ID } from '../utils/SearchToolIdentityUtils'`；追加到 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 与 `KIDS_MATH_LOCKED_TOOL_IDS`。

- [ ] **Step 2: 加提示词段**

在默认助手提示词的「工具调用规则」列表里加一条（与相邻条目同样式）：

```
- 孩子刚开始认数字、想数数、问「数字长什么样」时，用 number_blocks 打开数字乐园：长廊里有 1-20 个数字方块小人，孩子自己点。numbers 填今天重点的 1-20（不填=全部），focus 填打开时高亮哪个。讲解型卡片，不判对错、不授星；看完后可在后续回合用 math_quiz 出认数题巩固。不要在文字里假装摆数字小人。
```

`kids_math` 的提示词段同样加一条，措辞改为第一人称教学口吻。

- [ ] **Step 3: 校验**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && grep -c "NUMBER_BLOCKS_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets
```

预期：`3`（import + 两条锁定列表）。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(number_blocks): 锁定给小星老师与数学老师 + 提示词"
```

---

### Task 5: Web 场景 — 素材移植与缩略长廊

**Files:**
- Create: `entry/src/main/resources/rawfile/numberblocks/index.html`
- Create: `entry/src/main/resources/rawfile/numberblocks/assets/numberblocks.css`
- Create: `entry/src/main/resources/rawfile/numberblocks/assets/numberblocks-models.js`
- Create: `entry/src/main/resources/rawfile/numberblocks/assets/numberblocks-data.js`
- Create: `entry/src/main/resources/rawfile/numberblocks/assets/numberblocks-scene.js`
- Create: `entry/src/main/resources/rawfile/numberblocks/assets/numberblocks-host.css`

**Interfaces:**
- Produces（页面全局，供 Task 6 与原生调用）:
  - `window.NumberBlocksApp.setHostMode(on: boolean): void`
  - `window.NumberBlocksApp.configure(cfg: {numbers: number[], focus: number}): void`
  - `window.NumberBlocksApp.showGallery(): void`
  - `window.NumberBlocksApp.showStage(n: number): void`
  - `window.NumberBlocksApp.destroy(): void`
  - 页面通过 `window.NumberBlocksNativeBridge` 回调原生（方法缺失时全部静默降级，便于浏览器里直接打开调试）

- [ ] **Step 1: 拆参考稿为四个文件**

以用户提供的 `artifact-e0f9006e-838b-4835-a5d6-f6396bd504e0-6.html` 为唯一素材来源：

| 目标文件 | 从参考稿搬什么 |
|---|---|
| `numberblocks.css` | `<style>` 全部规则（`.card` / `.stage` / 3D 层级 / `.pupil` / `.lens` / `.mouth` / `.juggle` / `.tent` / `.hand` / `.drift` / `.board` 等） |
| `numberblocks-models.js` | `el` / `cube` / `box` / `grid` / `blocks` / `planes` / `limb` / `crossed` / `ball` / `decal` / `num` / `tentacle` / `spiky` / `lens` / `mouth` / `bridge` / `starEye` / `glove` / `crown` / `hair` / `rbrow` / `splat` / `palette` / `greyRamp` / `mix` 及 `PAL` / `RAIN` / `GREYS` / `RAINBOW_STRIPE` / `STAR` / `FINGERS` 常量 |
| `numberblocks-data.js` | `const CHARS = [...]`（20 个角色定义，一字不改） |
| `numberblocks-scene.js` | 长廊 / 舞台控制器 + 桥接（新写，见 Step 2-4） |

`index.html` 骨架：`<div id="app">` → `<div id="gallery">` + `<div id="stage">`，尾部按顺序 `<script src="./assets/numberblocks-models.js">` / `numberblocks-data.js` / `numberblocks-scene.js`。不引入任何 CDN。

- [ ] **Step 2: 长廊布局**

`#gallery` 为 `display:grid; grid-template-columns:repeat(5,1fr); gap:8px; padding:10px`。

每格 `.thumb`：`position:relative; aspect-ratio:3/4; overflow:hidden; border-radius:14px`，底色取 `split || color` 的浅色调（用 CSS `color-mix(in srgb, X 18%, #fff)`，`X` 为角色色；不支持时回落 `#fff`）。

格子内部放一个 **300×600 的坐标舞台**：`<div class="thumb-space">`，`position:absolute; left:50%; width:300px; height:600px; margin-left:-150px; top:0; transform-origin:50% 0`。进入长廊后由 JS 按格子实际高度算 `scale = tileHeight / 560` 写入 `--thumb-scale`，并设 `top: calc(-10px * var(--thumb-scale))`，让 300×600 空间里的 y∈[10,550] 刚好落进格子。

每个 `.thumb-space` 里用 `anchor/bob` 同构节点调用 `CHARS[n-1].build()`——**但加 `.static` 类关掉所有动画**（长廊不浮动、不眨眼、道具静止）。左上角叠一个数字徽章 `.thumb-num`（`split || color` 作底、白字）；`numbers` 成员右上角叠一个小圆点 `.thumb-dot`。

- [ ] **Step 3: 选中与返回长廊**

点 `.thumb` → `showStage(n)`。`showStage` 时给对应 `.thumb` 加 `.active`（外圈 `3px solid` 主色 + 轻微上浮），并 `setTimeout` 清除。`focus` 那一格进页时加 `.focus-pulse` 类做一次 1.2s 的呼吸高亮后移除。

- [ ] **Step 4: host 模式与桥**

`numberblocks-host.css` 里 `body.host .brand-bar { display:none }`。`setHostMode(true)` 时给 `body` 加 `host` 类。

桥接封装：

```js
function bridge(name, ...args) {
  const b = window.NumberBlocksNativeBridge
  if (b && typeof b[name] === 'function') { try { b[name](...args) } catch (e) {} }
}
```

就绪时调 `bridge('onReady')`；`try/catch` 包住初始化，异常走 `bridge('onError', String(e))`。

- [ ] **Step 5: 手动验证**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/resources/rawfile/numberblocks && python3 -m http.server 8765
```

浏览器打开 `http://127.0.0.1:8765/`。预期：20 个缩略小人全部渲染、5 列 4 行不滚动、都不动；缩到 320px 宽仍不横向溢出；点任意格子 `.active` 出现。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/resources/rawfile/numberblocks
git commit -m "feat(number_blocks): Numberblocks 3D 素材移植与缩略长廊"
```

---

### Task 6: Web 场景 — 舞台、切换、自动巡游

**Files:**
- Modify: `entry/src/main/resources/rawfile/numberblocks/assets/numberblocks.css`
- Modify: `entry/src/main/resources/rawfile/numberblocks/assets/numberblocks-scene.js`
- Modify: `entry/src/main/resources/rawfile/numberblocks/index.html`

**Interfaces:**
- Consumes: Task 5 的 `window.NumberBlocksApp` 骨架、`CHARS`、模型函数
- Produces: `showStage(n)` 完整行为（朗读 / 切换 / 巡游 / 返回长廊）

- [ ] **Step 1: 舞台 DOM**

`#stage` 结构：顶部条（`‹ 长廊` 返回按钮 / 数字横幅 / `已认识 N / 20`）→ 中间 `.stage-body`（300×600 坐标舞台，等比放大到容器）→ 底部 `.stage-rail`（1–20 数字条，横向滚动）+ `.stage-actions`（`🔊 再听一次`、`▶ 自动巡游`）。

数字横幅沿用参考稿的 `head` / `split` / 主色底 + 大号数字三种样式，逐字搬。

- [ ] **Step 2: 舞台交互**

- `pointerdown/move/up`：横向累加 `ry`（不设上限），纵向 `rx` 夹在 ±60°
- 空闲时按 `sin(t/1000 + n*1.7)` 摆 ±18°；拖拽期间摆幅衰减到 0；松手 0.6s 后恢复
- 眨眼、呼吸、道具动画全部照跑（不加 `.static`）
- 点角色本体 = 重播朗读
- 左右滑超过 40px = 前一 / 后一个数字（1 与 20 边界不响应）
- 数字条点击 = 直接切

- [ ] **Step 3: 朗读**

数字词表放在 `numberblocks-data.js` 末尾：

```js
const NUM_EN = ['one','two','three','four','five','six','seven','eight','nine','ten',
  'eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen','twenty']
const NUM_ZH = ['一','二','三','四','五','六','七','八','九','十',
  '十一','十二','十三','十四','十五','十六','十七','十八','十九','二十']
```

进舞台固定调 `bridge('stopSpeak')` → `bridge('speak', NUM_EN[n-1], NUM_ZH[n-1])` → `bridge('onSelect', String(n))`。

- [ ] **Step 4: 自动巡游**

`startTour()` 用 `setInterval` 每 2400ms 步进一个（步进序列 = `numbers` 非空 ? `numbers` : 1..20），每步走 Step 3 的朗读流程。到达末尾后停在最后一个并清计时器。任何 `pointerdown`（捕获阶段）、切数字、返回长廊、`destroy()` 都必须 `clearInterval` + `bridge('stopSpeak')`。

- [ ] **Step 5: 手动验证**

浏览器打开同一页面。预期：
- 点格子进舞台，小人浮动、眨眼、3 号抛球、13 号黄块飘、14 号滑板晃
- 拖拽能一直横转，纵向到 ±60° 停住
- 1 号左滑无反应、20 号右滑无反应
- 点「自动巡游」按 1→20 走动；点任意处立刻停
- 直接刷新页面（模拟页面重载），再进舞台不报错

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/resources/rawfile/numberblocks
git commit -m "feat(number_blocks): 舞台交互、朗读与自动巡游"
```

---

### Task 7: 原生卡片 NumberBlocksCard

**Files:**
- Create: `entry/src/main/ets/components/numberblocks/NumberBlocksCard.ets`

**Interfaces:**
- Consumes: `NUMBER_BLOCKS_TOOL_ID`、`validateNumberBlocksArgs`、`ServiceRegistry.tts()`、`getAppUiState()`、`withColorAlpha`
- Produces:
  - `export interface NumberBlocksAnswerPayload { completed: boolean; explored_count: number; numbers: number[]; focus: number; mode: string; skill_key: string; cancelled: boolean }`
  - `@ComponentV2 export struct NumberBlocksCard`，参数：`@Param toolCall/isAnswered/answeredPayload/largeSize`、`@Event onAnswer(toolCallId, answerJson)`、`@Event onRequestClose()`、`@Event onRegisterDismissPayload(provider: () => string)`

- [ ] **Step 1: 骨架**

镜像 `FarmEnglishCard.ets` 的结构，逐段替换：
- 常量 `NUMBER_BLOCKS_PAGE_URL = 'resource://rawfile/numberblocks/index.html'`、`NUMBER_BLOCKS_TTS_SPEED = 0.8`、`NUMBER_BLOCKS_READY_TIMEOUT_MS = 10000`
- `class NumberBlocksNativeBridge`：`speak(en, zh)` / `stopSpeak()` / `onReady()` / `onError(reason)` / `onSelect(n)` / `onProgress(json)`，全部返回 `'true'`
- `@Local argsView / seenNumbers / pageReady / sceneFailed / hasCompleted`
- 看门狗 `armSceneWatchdog()` / `retryLoad()`
- `aboutToAppear` 解析参数 + 建 controller；`aboutToDisappear` 停 TTS + 清计时器

- [ ] **Step 1b: 已答态回放**

`readAnsweredPayload()`：从 `answeredPayload` 解析出 `completed` 与 `numbers`，把 `numbers` 填进 `seenNumbers`、`completed` 填进 `hasCompleted`。解析失败一律回落成空数组 + `false`，不抛错（时间线回看时卡片只展示、不重新建 controller）。

- [ ] **Step 2: seenNumbers 只增不减**

`onSelect(n)` 回调：解析成整数，1–20 之外丢弃；已在数组里则不动，否则 push 后 `sort((a,b)=>a-b)` 并重新赋值触发响应式。`onProgress(json)` 同样做并集，**永不覆盖、永不清空**。

- [ ] **Step 3: 标题栏**

`@Builder HeaderBar()`：标题 `认数字 Numberblocks`；副标题 `已认识 ${seenNumbers.length} / 20 · 点一点方块听数字`；右侧 `Button({type: ButtonType.Capsule})`，文案 `seenNumbers.length > 0 ? '我学会了' : '先看看数字'`，`enabled` 仅在 `seenNumbers.length > 0 && !isAnswered && !submitted`。

- [ ] **Step 4: Web 容器与就绪**

`Web({ src: NUMBER_BLOCKS_PAGE_URL, controller })` + `.javaScriptAccess(true)` + `.javaScriptProxy({ object: this.bridge, name: 'NumberBlocksNativeBridge', methodList: ['speak','stopSpeak','onReady','onError','onSelect','onProgress'], controller })`。`onReady` 后 `runJavaScript` 调 `NumberBlocksApp.setHostMode(true)` 与 `configure({numbers, focus})`（JSON.stringify 两次转义）。Web 代理回调可能在非 UI 线程，状态写回统一走 `uiContext.runScopedTask`（照抄 farm）。

- [ ] **Step 5: 回执与收起**

`submit()` 构造 `NumberBlocksAnswerPayload`（`completed:true`、`explored_count: seenNumbers.length`、`numbers: seenNumbers`、`focus`、`mode:'display'`、`skill_key:'math_counting'`、`cancelled:false`），`stopSpeak()` 后 `onAnswer(toolCall.id, JSON.stringify(payload))`。`onRegisterDismissPayload` 注册 `buildDismissJson`：`completed = seenNumbers.length > 0`、`cancelled:false`。

- [ ] **Step 6: 编译**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```

预期：`BUILD SUCCESSFUL`。注意：此时卡片还没被任何文件引用，**不会被编译**——Step 7 才证明它能编过。

- [ ] **Step 7: 探针编译**

给 `pages/ChatPage.ets` 加一行 `import { NumberBlocksAnswerPayload, NumberBlocksCard } from '../components/numberblocks/NumberBlocksCard'`（暂不使用，任务 9 会真正接线），重跑 Step 6 的构建命令。预期 `BUILD SUCCESSFUL`；若报错，错误就在这里，不在晚三个任务之后。

- [ ] **Step 8: 提交**

```bash
git add entry/src/main/ets/components/numberblocks/NumberBlocksCard.ets entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(number_blocks): 原生卡片骨架、TTS 桥与回执"
```

---

### Task 8: MessageBubble 接线（7 处）

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`

**Interfaces:**
- Consumes: `isNumberBlocksFunctionName`、`NumberBlocksCard` 无关（横幅只开 sheet）
- Produces: 待答横幅 + 已答回看

- [ ] **Step 1: import**

第 58 行的函数名 import 列表加 `isNumberBlocksFunctionName`。

- [ ] **Step 2: 内联横幅**

在 `farm_english` 横幅 ForEach 之后（L2568 附近）加同构块：`SymbolGlyph($r('sys.symbol.dot_grid_2x2'))`、标题 `认数字 Numberblocks`、副标题 `点开看看 20 个数字小人`、`.onClick(() => this.onOpenNumberBlocksSheet(toolCall))`，ForEach key `'number_blocks_' + toolCall.id + '_' + index.toString()`。

- [ ] **Step 3: 判定函数**

在 `shouldRenderFarmEnglishInteractionCard` 之后加：

```ts
  private shouldRenderNumberBlocksInteractionCard(toolCall: ToolCall, index: number): boolean {
    if (!isNumberBlocksFunctionName(toolCall.functionName) || this.shouldHideToolCallCard(toolCall)) {
      return false
    }
    return !this.isAskUserToolCallAnswered(toolCall, index)
  }
```

- [ ] **Step 4: 三处 or-chain**

`isToolStepExpanded`（L3368）、`toggleToolStep` 的 `isDefaultExpanded`（L3378）、`isToolStepClickable` 或链：各追加 `|| isNumberBlocksFunctionName(part.toolName)`。

- [ ] **Step 5: 点击分发 + 步骤内容**

`handleToolStepClick` 的 `farm_english` 分支后加 `if (isNumberBlocksFunctionName(part.toolName)) { this.toggleToolStep(part); return }`；`else if (isFarmEnglishFunctionName(step.toolName))` 后加 `} else if (isNumberBlocksFunctionName(step.toolName)) { this.NumberBlocksStepContent(step) }`，并新增 `@Builder NumberBlocksStepContent(step)`——已答态展示 `已认识 N / 20` + 看过的数字 chips（`resolveStepAnswerPayload` 读回执，**不要** `JSON.parse(toolResult)`）。

- [ ] **Step 6: 精确行校验**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && grep -n "isNumberBlocksFunctionName" entry/src/main/ets/components/MessageBubble.ets
```

预期恰好 **7** 行：import、横幅判定、`isToolStepExpanded`、`toggleToolStep`、`isToolStepClickable`、`handleToolStepClick`、步骤内容。多一行或少一行都要逐个核对。

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/components/MessageBubble.ets
git commit -m "feat(number_blocks): MessageBubble 横幅与回看接线"
```

---

### Task 9: ChatPage 全屏 sheet

**Files:**
- Modify: `entry/src/main/ets/pages/ChatPage.ets`（import L153 附近、`@Local` L346 附近、开 sheet L2606 附近、`bindSheet` L3179 附近、builder L3829 附近）

**Interfaces:**
- Consumes: `NumberBlocksCard`、`onOpenNumberBlocksSheet(toolCall)`
- Produces: `showNumberBlocksSheet` / `numberBlocksToolCall` / `numberBlocksAnswered` / `numberBlocksDismissPayload` / `NumberBlocksSheetBuilder()`

- [ ] **Step 1: 状态与打开**

照抄 farm 四件套：`@Local showNumberBlocksSheet`、`@Local numberBlocksToolCall`、`@Local numberBlocksAnswered`、`private numberBlocksDismissPayload`。在 `onOpenFarmEnglishSheet` 旁加 `onOpenNumberBlocksSheet(toolCall)`：写 toolCall、重置 answered 与 dismissPayload、`showNumberBlocksSheet = true`。

- [ ] **Step 2: bindSheet**

复制 L3179 的 farm `bindSheet` 块，全部换成 number_blocks 的字段。`onDisappearing` 里：若 sheet 在开且未 `answered`，取 `numberBlocksDismissPayload` 调一次 `handleAskUserAnswer`；随后 `answered = true` 并关闭。

- [ ] **Step 3: builder**

```ts
  @Builder
  NumberBlocksSheetBuilder() {
    NumberBlocksCard({
      toolCall: this.numberBlocksToolCall,
      isAnswered: false,
      answeredPayload: '',
      largeSize: true,
      onAnswer: (toolCallId: string, answerJson: string): void => {
        this.numberBlocksAnswered = true
        this.handleAskUserAnswer(toolCallId, answerJson)
        this.showNumberBlocksSheet = false
      },
      onRequestClose: (): void => {
        this.showNumberBlocksSheet = false
      },
      onRegisterDismissPayload: (provider: () => string): void => {
        this.numberBlocksDismissPayload = provider
      }
    })
  }
```

- [ ] **Step 4: 编译**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```

预期：`BUILD SUCCESSFUL`。

- [ ] **Step 5: @Builder 装饰器对账**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && for f in $(git diff --name-only HEAD); do echo "$f: $(grep -c '@Builder' $f)"; done
```

预期：`ChatPage.ets` 的 `@Builder` 计数比改动前**恰好 +1**（新增 `NumberBlocksSheetBuilder`）。少 1 说明插块时吃掉了相邻 builder 的装饰器——编译不报，真机一开 sheet 就崩。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(number_blocks): ChatPage 全屏 sheet 接线"
```

---

### Task 10: 全量关卡 + 真机验收

**Files:** 无新增

- [ ] **Step 1: 跑 SKILL 的四个关卡**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "NUMBER_BLOCKS_TOOL_ID\|isNumberBlocksFunctionName" entry/src/main/ets/utils/SearchToolIdentityUtils.ets
grep -n "isNumberBlocksFunctionName" entry/src/main/ets/components/MessageBubble.ets | wc -l
grep -c "NUMBER_BLOCKS_TOOL_ID" entry/src/main/ets/config/BuiltinTools.ets
grep -c "NUMBER_BLOCKS_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets
```

预期：分别 `≥2`、`7`、`≥3`、`3`。

- [ ] **Step 2: JSON.parse 关卡重跑**

同 Task 2 Step 3。预期无异常。

- [ ] **Step 3: clean 构建**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default && DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```

预期 `BUILD SUCCESSFUL`，产物 `entry/build/default/outputs/default/entry-default-signed.hap`。clean 是必须的——增量缓存会掩盖新文件的硬错误。

- [ ] **Step 4: 真机 / 模拟器验收清单**

逐条勾：

- [ ] 小星老师调 `number_blocks` → 横幅出现 → 点开全屏
- [ ] 长廊 20 个缩略角色全渲染，5 列不溢出；`numbers` 成员有小圆点；`focus` 呼吸一次
- [ ] 点格子进舞台，拖拽可一直横转、纵向 ±60° 停住
- [ ] 进舞台立即念「三。Three。」；快速连点不同数字不叠音
- [ ] 1 号左滑、20 号右滑无反应
- [ ] ▶ 自动巡游按 1→20 走；点任何地方立刻停
- [ ] 「我学会了」看 0 个时不可点；看过后可点，回执含 `numbers`
- [ ] 下拉收起 sheet 也回执，且声音立即停
- [ ] 星星数不变（讲解型不授星）
- [ ] 工具出现在工具中心
- [ ] 数学老师（`kids_math`）能调；英语/语文/游戏老师调不到

- [ ] **Step 5: 更新文档并提交**

`CLAUDE.md` 的互动卡片表加一行 `number_blocks`；`.claude/rules/teaching-architecture.md` §4 工具表加一行；`CHANGELOG.md` 记一条。

```bash
git add CLAUDE.md .claude/rules/teaching-architecture.md CHANGELOG.md
git commit -m "docs(number_blocks): 补充卡片表与教学架构工具清单"
```
