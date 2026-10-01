# 今日计划按学科拆分 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `LessonPlan` 新增语文模块与 writing 学科标签，备课老师产出语文内容，数学/英语/语文老师在 system prompt 中只拿到本学科的计划段。

**Architecture:** 保持 5 个强类型模块 + freeform 的存储结构，新增 `chinese[]` 模块与 `writing.subject` 标签；学科过滤由纯函数层（`LessonPlanSubjectUtils`）完成，渲染器按学科出两个变体（全量分组 / 单学科），注入门控在 `ChatViewModel.buildRequestSystemPrompt` 非 default 分支按 assistantId 映射学科后拼接。旧 v1 计划经 hydrate 容错自然兼容（学科视图为空 → 不注入）。

**Tech Stack:** ArkTS (HarmonyOS API 23) + hypium 单元测试；无新依赖。

**Spec:** `docs/superpowers/specs/2026-10-01-lesson-plan-subject-split-design.md`

## Global Constraints

- 构建/编译验证（本项目 CLI 无 lint 任务、`hvigorw test` 因脚手架损坏不可用，hypium 测试只能在 DevEco Studio IDE 中运行）：
  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```
- 因此每个任务的 TDD 循环为：**写测试 → assembleHap 确认编译（含测试代码）→ 实现 → assembleHap → commit**；测试的"运行通过"由最后一个任务统一在 IDE 中执行确认。
- ArkTS 严格模式：内联对象字面量必须显式标注类型（`10605038`）；**ForEach 回调体内不能写 `const x: Foo = {...}`**（`10905209`）；不允许 `const [a, b] = ...` 解构（`10605074`）；`arr.map()` 需显式返回类型。
- `@Builder` 方法体内不能有 `const` 声明和提前 return；`Row.alignItems` 用 `VerticalAlign`、`Column.alignItems` 用 `HorizontalAlign`。
- `PLANNER_SYSTEM_PROMPT` 是展示文本（不运行时 JSON.parse），模板串内 ASCII 引号安全；但改完后必须跑 Task 5 的 prompt 标记测试防回归。
- 新建 hypium 测试文件必须同步注册进 `entry/src/ohosTest/ets/test/List.test.ets`（import + 调用两行）。
- 注释/文案使用中文，与仓库现状一致。
- 禁止改动：`MessageBubble.ets`、`StarEventModels.ets`、`ToolExecutionService.ets`、`LessonPlanningService.prefetchImages`/`extractPrefetchRequests`（chinese 项 imagePrompt 为空自然跳过）。

## Review Focus

以下是 spec 未被测试覆盖、最可能咬人的输入类别（每行已在对应任务中以测试钉住或写明人工验证点）：

1. **旧 v1 计划 JSON（无 chinese / writing 无 subject）在运行时被 hydrate** → 学科老师不注入任何计划段、小星老师渲染不报错、家长页正常 —— Task 1 测试钉住 hydrate 兼容，Task 6 测试钉住"空学科视图返回 ''"。
2. **LLM 不遵守输出契约**（writing 缺 subject / chinese 数量不足 / dimension 越界）→ 校验器拦截 + 3 次重试 + baseline 兜底仍合规 —— Task 4 测试钉住全部新校验分支，Task 3 测试钉住 baseline 通过新规则。
3. **chinese 项内容为脏数据**（dimension 未知但 character 是 CJK / pinyin 维度带调音节）→ 台账种子按维度映射不炸、能归则归 —— Task 8 测试钉住三类映射与脏数据跳过。
4. **今日计划拉取异常 / plan 为 null**（DB 错误、首次使用无计划）→ 学科老师静默无计划段，对话不被阻塞 —— Task 7 代码内 try/catch + 编译验证（服务层无法 hypium 化，列入人工验证）。
5. **themeTitle 为空但本学科有条目** → 学科段只少主题行，教学点照常输出 —— Task 6 测试钉住。

---

### Task 1: 数据模型 — chinese 模块 + writing.subject + hydrate 兼容

**Files:**
- Modify: `entry/src/main/ets/models/LessonPlanModels.ets`
- Test: `entry/src/ohosTest/ets/test/utils/LessonPlanModels.test.ets`（新建）
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册）

**Interfaces:**
- Consumes: 无（本任务是链条起点）
- Produces: `LessonPlanChineseItem` 类（字段 `topicKey/imagePrompt/dimension/character/description/targetSkillLevel`）；`LessonPlanWritingItem.subject: string`；`LessonPlan.chinese: LessonPlanChineseItem[]`；`LessonPlan.schemaVersion` 默认 2；`parseLessonPlan()` 对 v1/v2 JSON 均可解析——后续所有任务依赖这些。

- [ ] **Step 1: 写失败测试** — 新建 `entry/src/ohosTest/ets/test/utils/LessonPlanModels.test.ets`：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { parseLessonPlan, serializeLessonPlan } from '../../../../main/ets/models/LessonPlanModels'

/**
 * LessonPlanModels 单元测试 (2026-10-01 学科拆分)
 * 覆盖: v2 水合 / v1 兼容 / 候选 key 容错 / 序列化回环
 * 运行: DevEco Studio → 右键该文件 → Run (CLI hvigorw test 不可用)
 */
export default function lessonPlanModelsTest() {
  describe('parseLessonPlan - v2 水合', () => {
    it('chinese 数组 + writing.subject 正确水合', 0, () => {
      const json = `{
        "schemaVersion": 2, "planDate": "2026-10-02",
        "themeTitle": "秋天的山",
        "chinese": [
          {"topicKey": "chinese.chinese_vocab.shan", "dimension": "chinese_vocab",
           "character": "山", "description": "认读并组词", "targetSkillLevel": 2, "imagePrompt": ""},
          {"topicKey": "chinese.pinyin.shan", "dimension": "pinyin",
           "character": "shān", "description": "拼读第一声", "targetSkillLevel": 1, "imagePrompt": ""}
        ],
        "writing": [
          {"topicKey": "writing.山", "characterOrWord": "山", "subject": "chinese", "description": "", "imagePrompt": ""},
          {"topicKey": "writing.A", "characterOrWord": "A", "subject": "english", "description": "", "imagePrompt": ""}
        ]
      }`
      const plan = parseLessonPlan(json)
      expect(plan.schemaVersion).assertEqual(2)
      expect(plan.chinese.length).assertEqual(2)
      expect(plan.chinese[0].dimension).assertEqual('chinese_vocab')
      expect(plan.chinese[0].character).assertEqual('山')
      expect(plan.chinese[0].targetSkillLevel).assertEqual(2)
      expect(plan.chinese[1].character).assertEqual('shān')
      expect(plan.writing.length).assertEqual(2)
      expect(plan.writing[0].subject).assertEqual('chinese')
      expect(plan.writing[1].subject).assertEqual('english')
    })
  })

  describe('parseLessonPlan - v1 兼容 (Review Focus #1)', () => {
    it('无 chinese key / writing 无 subject → 空数组 + 空串, 不抛错', 0, () => {
      const json = `{
        "schemaVersion": 1, "planDate": "2026-09-30",
        "themeTitle": "旧计划",
        "writing": [{"topicKey": "writing.一", "characterOrWord": "一", "description": "", "imagePrompt": ""}]
      }`
      const plan = parseLessonPlan(json)
      expect(plan.schemaVersion).assertEqual(1)
      expect(plan.chinese.length).assertEqual(0)
      expect(plan.writing.length).assertEqual(1)
      expect(plan.writing[0].subject).assertEqual('')
    })
  })

  describe('parseLessonPlan - 容错', () => {
    it('chineseItems 候选 key 命中', 0, () => {
      const json = `{"chineseItems": [{"topicKey": "chinese.pinyin.ma", "dimension": "pinyin", "character": "mā", "description": "", "targetSkillLevel": 1, "imagePrompt": ""}]}`
      const plan = parseLessonPlan(json)
      expect(plan.chinese.length).assertEqual(1)
      expect(plan.chinese[0].character).assertEqual('mā')
    })
    it('chinese 不是数组 → 降级空数组; 非法 JSON → 空 plan', 0, () => {
      const p1 = parseLessonPlan('{"chinese": "oops"}')
      expect(p1.chinese.length).assertEqual(0)
      const p2 = parseLessonPlan('not-json')
      expect(p2.themeTitle).assertEqual('')
      expect(p2.chinese.length).assertEqual(0)
    })
    it('新 LessonPlan 默认 schemaVersion=2', 0, () => {
      const plan = parseLessonPlan(serializeLessonPlan(parseLessonPlan('')))
      expect(plan.schemaVersion).assertEqual(2)
    })
  })
}
```

- [ ] **Step 2: 注册测试** — `List.test.ets` 加 import 与调用（保持字母序插入）：

```typescript
import lessonPlanModelsTest from './utils/LessonPlanModels.test';
// testsuite() 体内:
  lessonPlanModelsTest();
```

- [ ] **Step 3: 编译确认失败** — 跑 Global Constraints 中的 assembleHap 命令。Expected: 编译失败（`LessonPlanModels.test.ets` 引用不存在的导出不会报错，但 Step 6 之前此文件应能编译通过——本步骤确认测试文件本身无语法问题即可）。

- [ ] **Step 4: 实现** — `models/LessonPlanModels.ets` 四处修改：

(a) `LessonPlanWritingItem`（现 `:36-40`）加字段：

```typescript
/** 写字项 */
export class LessonPlanWritingItem extends LessonPlanItemBase {
  characterOrWord: string = '' // 写字/组词
  subject: string = ''         // 学科标签: '' | 'english' | 'chinese' | 'math' (2026-10-01 学科拆分)
  description: string = ''
  imagePrompt: string = ''     // 写字插图
}
```

(b) `LessonPlanGeneralItem` 之后（现 `:47` 后）新增类：

```typescript
/** 语文项 (2026-10-01 学科拆分)。imagePrompt 约定留空: 语文卡片自带笔画数据 / picture_talk 运行时生图 */
export class LessonPlanChineseItem extends LessonPlanItemBase {
  dimension: string = ''        // 白名单: 'pinyin' | 'chinese_vocab' | 'chinese_reading'
  character: string = ''        // 汉字 / 词 / 拼音音节（带调，如 'shān'）/ 短句
  description: string = ''      // 教学描述（中文）
  targetSkillLevel: number = 0  // 目标 level 1-5，对齐 math 项
}
```

(c) `LessonPlan` 根（现 `:69-85`）：`schemaVersion` 默认值 `1` → `2`（注释同步），`generalKnowledge` 之后加 `chinese: LessonPlanChineseItem[] = []`，类注释「4 个强类型核心模块」改为「5 个强类型核心模块」。

(d) `hydrateLessonPlan`（现 `:110-143`）：`plan.generalKnowledge = ...` 之后加一行；`hydrateWritingItem` 加 subject 读取；文件内新增 `hydrateChineseItem`：

```typescript
  plan.chinese = extractArray(r, ['chinese', 'chineseItems', 'hanzi'], hydrateChineseItem)
```

```typescript
function hydrateWritingItem(raw: Object): LessonPlanWritingItem {
  const r = raw as Record<string, Object>
  const item = new LessonPlanWritingItem()
  item.topicKey = stringField(r, 'topicKey')
  item.characterOrWord = stringField(r, 'characterOrWord')
  item.subject = stringField(r, 'subject')
  item.description = stringField(r, 'description')
  item.imagePrompt = stringField(r, 'imagePrompt')
  return item
}

function hydrateChineseItem(raw: Object): LessonPlanChineseItem {
  const r = raw as Record<string, Object>
  const item = new LessonPlanChineseItem()
  item.topicKey = stringField(r, 'topicKey')
  item.dimension = stringField(r, 'dimension')
  item.character = stringField(r, 'character')
  item.description = stringField(r, 'description')
  if (typeof r['targetSkillLevel'] === 'number') {
    item.targetSkillLevel = r['targetSkillLevel'] as number
  }
  item.imagePrompt = stringField(r, 'imagePrompt')
  return item
}
```

- [ ] **Step 5: 编译确认通过** — assembleHap。Expected: BUILD SUCCESSFUL。
- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/models/LessonPlanModels.ets entry/src/ohosTest/ets/test/utils/LessonPlanModels.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(lesson-plan): chinese 模块 + writing.subject 字段 + hydrate v1/v2 兼容"
```

---

### Task 2: LessonPlanSubjectUtils — 学科映射与收集纯函数

**Files:**
- Create: `entry/src/main/ets/utils/LessonPlanSubjectUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/LessonPlanSubjectUtils.test.ets`（新建）
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册）

**Interfaces:**
- Consumes: Task 1 的 `LessonPlan.chinese` / `LessonPlanWritingItem.subject`；`models/AssistantModels.ets:132-134` 的 `KIDS_MATH_ASSISTANT_ID` / `KIDS_ENGLISH_ASSISTANT_ID` / `KIDS_CHINESE_ASSISTANT_ID`
- Produces: `export type PlanSubject = 'chinese' | 'math' | 'english'`；`planSubjectForAssistant(assistantId: string): PlanSubject | null`；`collectPlanItemsForSubject(plan: LessonPlan, subject: PlanSubject): SubjectPlanItems`（`SubjectPlanItems` 含 `chinese/vocab/math/writing` 四数组）——Task 6、Task 7 按这些签名调用。

- [ ] **Step 1: 写失败测试** — 新建 `entry/src/ohosTest/ets/test/utils/LessonPlanSubjectUtils.test.ets`：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import {
  planSubjectForAssistant,
  collectPlanItemsForSubject
} from '../../../../main/ets/utils/LessonPlanSubjectUtils'
import {
  LessonPlan,
  LessonPlanChineseItem,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem
} from '../../../../main/ets/models/LessonPlanModels'

function buildMixedPlan(): LessonPlan {
  const p = new LessonPlan()
  const c1 = new LessonPlanChineseItem()
  c1.topicKey = 'chinese.chinese_vocab.shan'
  c1.dimension = 'chinese_vocab'
  c1.character = '山'
  p.chinese.push(c1)
  const v1 = new LessonPlanVocabItem()
  v1.topicKey = 'vocab.apple'
  v1.word = 'apple'
  p.vocab.push(v1)
  const m1 = new LessonPlanMathItem()
  m1.topicKey = 'math.addition.q1'
  m1.dimension = 'math_addition'
  m1.targetSkillLevel = 2
  p.math.push(m1)
  const wc = new LessonPlanWritingItem()
  wc.topicKey = 'writing.山'
  wc.characterOrWord = '山'
  wc.subject = 'chinese'
  p.writing.push(wc)
  const we = new LessonPlanWritingItem()
  we.topicKey = 'writing.A'
  we.characterOrWord = 'A'
  we.subject = 'english'
  p.writing.push(we)
  const wn = new LessonPlanWritingItem()
  wn.topicKey = 'writing.3'
  wn.characterOrWord = '3'
  wn.subject = 'math'
  p.writing.push(wn)
  const wu = new LessonPlanWritingItem()
  wu.topicKey = 'writing.old'
  wu.characterOrWord = '旧'
  wu.subject = ''
  p.writing.push(wu)
  return p
}

export default function lessonPlanSubjectUtilsTest() {
  describe('planSubjectForAssistant', () => {
    it('3 个学科助手正确映射', 0, () => {
      expect(planSubjectForAssistant('kids_math')).assertEqual('math')
      expect(planSubjectForAssistant('kids_english')).assertEqual('english')
      expect(planSubjectForAssistant('kids_chinese')).assertEqual('chinese')
    })
    it('default / kids_games / 未知 id → null', 0, () => {
      expect(planSubjectForAssistant('default')).assertNull()
      expect(planSubjectForAssistant('kids_games')).assertNull()
      expect(planSubjectForAssistant('custom_x')).assertNull()
    })
  })

  describe('collectPlanItemsForSubject', () => {
    it('math → math 模块 + writing[math]', 0, () => {
      const out = collectPlanItemsForSubject(buildMixedPlan(), 'math')
      expect(out.math.length).assertEqual(1)
      expect(out.vocab.length).assertEqual(0)
      expect(out.chinese.length).assertEqual(0)
      expect(out.writing.length).assertEqual(1)
      expect(out.writing[0].characterOrWord).assertEqual('3')
    })
    it('english → vocab 模块 + writing[english]', 0, () => {
      const out = collectPlanItemsForSubject(buildMixedPlan(), 'english')
      expect(out.vocab.length).assertEqual(1)
      expect(out.vocab[0].word).assertEqual('apple')
      expect(out.writing.length).assertEqual(1)
      expect(out.writing[0].characterOrWord).assertEqual('A')
    })
    it('chinese → chinese 模块 + writing[chinese]', 0, () => {
      const out = collectPlanItemsForSubject(buildMixedPlan(), 'chinese')
      expect(out.chinese.length).assertEqual(1)
      expect(out.chinese[0].character).assertEqual('山')
      expect(out.writing.length).assertEqual(1)
      expect(out.writing[0].characterOrWord).assertEqual('山')
    })
    it('未打标签 writing 对任何学科不可见 (Review Focus #1 兜底)', 0, () => {
      const outM = collectPlanItemsForSubject(buildMixedPlan(), 'math')
      const outE = collectPlanItemsForSubject(buildMixedPlan(), 'english')
      const outC = collectPlanItemsForSubject(buildMixedPlan(), 'chinese')
      const all = outM.writing.concat(outE.writing).concat(outC.writing)
      for (let i = 0; i < all.length; i++) {
        expect(all[i].characterOrWord !== '旧').assertTrue()
      }
    })
    it('空 plan → 全空数组', 0, () => {
      const out = collectPlanItemsForSubject(new LessonPlan(), 'chinese')
      expect(out.chinese.length).assertEqual(0)
      expect(out.writing.length).assertEqual(0)
    })
  })
}
```

- [ ] **Step 2: 注册测试** — `List.test.ets` 加 `lessonPlanSubjectUtilsTest`（import + 调用）。
- [ ] **Step 3: 编译确认失败** — assembleHap。Expected: FAIL（`LessonPlanSubjectUtils` 不存在）。
- [ ] **Step 4: 实现** — 新建 `entry/src/main/ets/utils/LessonPlanSubjectUtils.ets`：

```typescript
/**
 * LessonPlanSubjectUtils - 今日计划学科拆分纯函数
 *
 * Spec: docs/superpowers/specs/2026-10-01-lesson-plan-subject-split-design.md §3.4
 * - PlanSubject: 计划学科三元组（常识 generalKnowledge 不在其中, 仅小星老师消费）
 * - planSubjectForAssistant: 学科助手 id → 学科; kids_games / default / 自定义 → null
 * - collectPlanItemsForSubject: 按学科收集计划条目; 未打标签的 writing 项对学科老师不可见
 *
 * 纯函数, 无 ArkUI 依赖, 可被 hypium 覆盖。
 */
import {
  LessonPlan,
  LessonPlanChineseItem,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem
} from '../models/LessonPlanModels'
import {
  KIDS_MATH_ASSISTANT_ID,
  KIDS_ENGLISH_ASSISTANT_ID,
  KIDS_CHINESE_ASSISTANT_ID
} from '../models/AssistantModels'

export type PlanSubject = 'chinese' | 'math' | 'english'

/** 单学科计划视图: 仅与 subject 相关的模块数组非空 */
export interface SubjectPlanItems {
  chinese: LessonPlanChineseItem[]
  vocab: LessonPlanVocabItem[]
  math: LessonPlanMathItem[]
  writing: LessonPlanWritingItem[]
}

export function planSubjectForAssistant(assistantId: string): PlanSubject | null {
  if (assistantId === KIDS_MATH_ASSISTANT_ID) {
    return 'math'
  }
  if (assistantId === KIDS_ENGLISH_ASSISTANT_ID) {
    return 'english'
  }
  if (assistantId === KIDS_CHINESE_ASSISTANT_ID) {
    return 'chinese'
  }
  return null
}

export function collectPlanItemsForSubject(plan: LessonPlan, subject: PlanSubject): SubjectPlanItems {
  const out: SubjectPlanItems = { chinese: [], vocab: [], math: [], writing: [] }
  for (let i = 0; i < plan.writing.length; i++) {
    if (plan.writing[i].subject === subject) {
      out.writing.push(plan.writing[i])
    }
  }
  if (subject === 'math') {
    for (let i = 0; i < plan.math.length; i++) {
      out.math.push(plan.math[i])
    }
  } else if (subject === 'english') {
    for (let i = 0; i < plan.vocab.length; i++) {
      out.vocab.push(plan.vocab[i])
    }
  } else {
    for (let i = 0; i < plan.chinese.length; i++) {
      out.chinese.push(plan.chinese[i])
    }
  }
  return out
}
```

- [ ] **Step 5: 编译确认通过** — assembleHap。Expected: BUILD SUCCESSFUL。
- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/LessonPlanSubjectUtils.ets entry/src/ohosTest/ets/test/utils/LessonPlanSubjectUtils.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(lesson-plan): PlanSubject 学科映射与按学科收集纯函数"
```

---

### Task 3: baseline 兜底计划 — DEFAULT_CHINESE + writing 标签

**Files:**
- Modify: `entry/src/main/ets/utils/LessonPlannerBaseline.ets`
- Test: `entry/src/ohosTest/ets/test/utils/LessonPlannerBaseline.test.ets`（扩展）

**Interfaces:**
- Consumes: Task 1 的 `LessonPlanChineseItem` / `LessonPlanWritingItem.subject`
- Produces: `generateBaselinePlan()` 输出含 ≥2 个合规 chinese 项 + 全部 writing 项带 subject 标签 —— Task 4 校验器生效后 baseline 仍必过 `validatePlannerOutput`（该契约由本任务与 Task 4 的测试共同钉住）。

- [ ] **Step 1: 扩展测试** — `LessonPlannerBaseline.test.ets` 顶部 import 补 `LessonPlanChineseItem`，主 describe 内追加用例：

```typescript
    it('空 childSnapshot → chinese >= 2 且维度在白名单内', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', new ChildSnapshot(), null)
      // 用字面量 2 而非 MIN_PLANNER_COUNTS.chinese — 该常量 Task 4 才创建
      expect(plan.chinese.length >= 2).assertTrue()
      const dims: string[] = ['pinyin', 'chinese_vocab', 'chinese_reading']
      for (let i = 0; i < plan.chinese.length; i++) {
        expect(dims.indexOf(plan.chinese[i].dimension) >= 0).assertTrue()
        expect(plan.chinese[i].character !== '').assertTrue()
      }
    })
    it('writing 项全部带 subject 标签', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', new ChildSnapshot(), null)
      for (let i = 0; i < plan.writing.length; i++) {
        expect(['english', 'chinese', 'math'].indexOf(plan.writing[i].subject) >= 0).assertTrue()
      }
    })
    it('yesterday plan 提供 chinese → baseline 复用其 chinese 项', 0, () => {
      const yesterday = new LessonPlan()
      const c = new LessonPlanChineseItem()
      c.topicKey = 'chinese.chinese_vocab.huo'
      c.dimension = 'chinese_vocab'
      c.character = '火'
      yesterday.chinese.push(c)
      const plan = generateBaselinePlan('2026-06-24', new ChildSnapshot(), yesterday)
      let found = false
      for (let i = 0; i < plan.chinese.length; i++) {
        if (plan.chinese[i].topicKey === 'chinese.chinese_vocab.huo') {
          found = true
        }
      }
      expect(found).assertTrue()
    })
```

注意：文件顶部需确认已 import `generateBaselinePlan` / `ChildSnapshot` / `MIN_PLANNER_COUNTS` / `LessonPlan`（现有用例已在用，缺什么补什么）。

- [ ] **Step 2: 编译确认失败** — assembleHap。Expected: FAIL（`LessonPlanChineseItem` 已在 Task 1 存在所以 import 能过；断言逻辑在运行时会败——本步骤确认测试文件编译通过即可，运行验证在 Task 10 IDE 统一执行）。

  **顺序说明：** 本任务先让 baseline 具备 chinese 内容，Task 4 再上校验规则——若反过来，baseline 会在 3 次重试全失败后产出不合规兜底计划。

- [ ] **Step 3: 实现** — `utils/LessonPlannerBaseline.ets`：

(a) import 补 `LessonPlanChineseItem`。

(b) 镜像常量区（现 `:39-42`）加 `const MIN_CHINESE_COUNT = 2`。

(c) `WritingTemplate` 接口加 `subject: string`；`DEFAULT_WRITING`（现 `:116-125`）补标签：一/二 → `subject: 'chinese'`，A/B → `subject: 'english'`。

(d) `GeneralTemplate` 之后新增：

```typescript
interface ChineseTemplate {
  topicKey: string
  dimension: string
  character: string
  description: string
  targetSkillLevel: number
}

// 覆盖语文 3 维度 (pinyin / chinese_vocab / chinese_reading) 各 1 条 + 1 条备用, 确定性无随机
const DEFAULT_CHINESE: ChineseTemplate[] = [
  { topicKey: 'chinese.chinese_vocab.shan', dimension: 'chinese_vocab', character: '山',
    description: '认读"山"并组词（高山、山水）', targetSkillLevel: 1 },
  { topicKey: 'chinese.pinyin.shan', dimension: 'pinyin', character: 'shān',
    description: '拼读 sh—ān→shān，认读第一声', targetSkillLevel: 1 },
  { topicKey: 'chinese.chinese_reading.hello', dimension: 'chinese_reading', character: '你好呀',
    description: '看图说一句完整的打招呼话', targetSkillLevel: 1 },
  { topicKey: 'chinese.chinese_vocab.shui', dimension: 'chinese_vocab', character: '水',
    description: '认读"水"并组词（喝水、水杯）', targetSkillLevel: 1 }
]
```

(e) `makeWritingItem`（现 `:200-207`）加 `w.subject = t.subject`；其后新增：

```typescript
function makeChineseItem(t: ChineseTemplate): LessonPlanChineseItem {
  const c = new LessonPlanChineseItem()
  c.topicKey = t.topicKey
  c.dimension = t.dimension
  c.character = t.character
  c.description = t.description
  c.targetSkillLevel = clampSkillLevel(t.targetSkillLevel)
  return c
}
```

(f) `generateBaselinePlan` 的 generalKnowledge 段之后（现 `:401` 后，`return plan` 之前）新增 chinese 段，镜像 writing 段的「复用昨日 + 模板补齐」模式：

```typescript
  // ---- chinese: 复用 yesterday + 默认 (2026-10-01 学科拆分) ----
  const yesterdayChinese: LessonPlanChineseItem[] =
    yesterdayPlan !== null ? yesterdayPlan.chinese : []
  const reusedChinese = pickUnique(yesterdayChinese, usedKeys, MIN_CHINESE_COUNT)
  for (let i = 0; i < reusedChinese.length; i++) {
    usedKeys.push(reusedChinese[i].topicKey)
  }
  const chineseTemplates: ChineseTemplate[] = DEFAULT_CHINESE.slice()
  const paddedChineseTemplates = padWithTemplates(chineseTemplates, usedKeys, MIN_CHINESE_COUNT,
    (i): ChineseTemplate => {
      const base = DEFAULT_CHINESE[i % DEFAULT_CHINESE.length]
      return {
        topicKey: `chinese.placeholder${i}`,
        dimension: base.dimension,
        character: base.character,
        description: base.description,
        targetSkillLevel: base.targetSkillLevel
      }
    })
  for (let i = 0; i < reusedChinese.length; i++) {
    plan.chinese.push(reusedChinese[i])
  }
  for (let i = 0; i < paddedChineseTemplates.length; i++) {
    plan.chinese.push(makeChineseItem(paddedChineseTemplates[i]))
  }
```

- [ ] **Step 4: 编译确认通过** — assembleHap。Expected: BUILD SUCCESSFUL。
- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/LessonPlannerBaseline.ets entry/src/ohosTest/ets/test/utils/LessonPlannerBaseline.test.ets
git commit -m "feat(lesson-plan): baseline 兜底计划补 chinese 模块与 writing 学科标签"
```

---

### Task 4: 校验器 — chinese 下限 + 双白名单 + subject 白名单

**Files:**
- Modify: `entry/src/main/ets/utils/LessonPlannerValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets`（扩展 + fixture 修正）

**Interfaces:**
- Consumes: Task 1 的 `LessonPlanChineseItem`；Task 3 已让 baseline 满足新规则
- Produces: `MIN_PLANNER_COUNTS.chinese: number = 2`；`VALID_CHINESE_DIMENSIONS: ReadonlyArray<string>` —— Task 5（提示词一致性）与 `LessonPlanningService` 重试循环（现有调用，无签名变化）依赖。

- [ ] **Step 1: 更新既有 fixture + 扩展测试** — `LessonPlannerValidation.test.ets`：

(a) import 补 `LessonPlanChineseItem` 与（Step 1(c) 用的）`VALID_CHINESE_DIMENSIONS`。

(b) **修正 `filledPlan()`（现 `:28-56`）**——不加 Chinese 项的话既有用例会在新规则下全线变红：writing 循环体内 `w.characterOrWord = ...` 后加 `w.subject = 'chinese'`；循环之后追加：

```typescript
  for (let i = 0; i < 2; i++) {
    const c = new LessonPlanChineseItem()
    c.topicKey = `chinese.chinese_vocab.zi${i}`
    c.dimension = 'chinese_vocab'
    c.character = `字${i}`
    c.targetSkillLevel = 2
    p.chinese.push(c)
  }
```

(c) 常量 describe 更新：

- `MIN_PLANNER_COUNTS` 用例（现 `:60-65`）加 `expect(MIN_PLANNER_COUNTS.chinese).assertEqual(2)`，用例名同步为「vocab=4 / math=4 / writing=2 / general=2 / chinese=2」。
- 新增 `VALID_CHINESE_DIMENSIONS` 用例（3 个值 `pinyin / chinese_vocab / chinese_reading`，仿照 `VALID_MATH_DIMENSIONS` 用例写法）。

(d) 数量 describe 更新：

- `空 plan → ok=false, 4 个 issues`（现 `:134-138`）改为 **5 个 issues**。
- 「所有字段填齐」用例（现 `:88-96`）在新规则下会因 push 的空 writing（subject=''）变红——改为：

```typescript
    it('所有字段填齐 (vocab=5/math=5/chinese=3/writing=3/general=3) → ok=true', 0, () => {
      const p = filledPlan()
      p.vocab.push(new LessonPlanVocabItem())
      p.math.push(new LessonPlanMathItem())
      const wNew = new LessonPlanWritingItem()
      wNew.subject = 'english'
      p.writing.push(wNew)
      const cNew = new LessonPlanChineseItem()
      cNew.dimension = 'pinyin'
      cNew.character = 'mā'
      cNew.targetSkillLevel = 1
      p.chinese.push(cNew)
      p.generalKnowledge.push(new LessonPlanGeneralItem())
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })
```

- 新增用例（代码）：

```typescript
    it('chinese=1 → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('chinese=1')
    })
```

(e) 文件末尾（主 describe 内）新增两个 describe：

```typescript
  describe('validatePlannerOutput - chinese 必填字段', () => {
    it('chinese 项 dimension="" → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese[0].dimension = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid dimension')
    })
    it('chinese 项 dimension="math_addition" (串科) → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese[0].dimension = 'math_addition'
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('math_addition')
    })
    it('chinese 项 targetSkillLevel=0 → ok=false, 含 out of [1,5]', 0, () => {
      const p = filledPlan()
      p.chinese[0].targetSkillLevel = 0
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('targetSkillLevel=0')
    })
    it('chinese 项 targetSkillLevel=6 → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese[0].targetSkillLevel = 6
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('targetSkillLevel=6')
    })
  })

  describe('validatePlannerOutput - writing subject 白名单', () => {
    it('writing 项 subject="" → ok=false', 0, () => {
      const p = filledPlan()
      p.writing[0].subject = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid subject')
    })
    it('writing 项 subject="french" (白名单外) → ok=false', 0, () => {
      const p = filledPlan()
      p.writing[0].subject = 'french'
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('french')
    })
    it('writing 项 subject="math" (白名单内) → ok=true', 0, () => {
      const p = filledPlan()
      p.writing[0].subject = 'math'
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })
  })
```

- [ ] **Step 2: 编译确认失败** — assembleHap。Expected: FAIL（`MIN_PLANNER_COUNTS.chinese` / `VALID_CHINESE_DIMENSIONS` 不存在）。
- [ ] **Step 3: 实现** — `utils/LessonPlannerValidation.ets`：

(a) `MinPlannerCounts` 接口加 `chinese: number`；`MIN_PLANNER_COUNTS` 加 `chinese: 2`；新增：

```typescript
/** chinese 项 dimension 白名单 (3 个, 对齐语文 3 维画像: pinyin/chinese_vocab/chinese_reading) */
export const VALID_CHINESE_DIMENSIONS: ReadonlyArray<string> = [
  'pinyin',
  'chinese_vocab',
  'chinese_reading'
]

/** writing 项 subject 白名单 */
const VALID_WRITING_SUBJECTS: ReadonlyArray<string> = ['english', 'chinese', 'math']
```

(b) `validatePlannerOutput` 中 generalKnowledge 数量检查（现 `:73-75`）之后加：

```typescript
  if (plan.chinese.length < MIN_PLANNER_COUNTS.chinese) {
    issues.push(`chinese=${plan.chinese.length} < min ${MIN_PLANNER_COUNTS.chinese}`)
  }
```

(c) math 项循环（现 `:77-85`）之后加两个循环：

```typescript
  for (let i = 0; i < plan.chinese.length; i++) {
    const item = plan.chinese[i]
    if (item.dimension === '' || VALID_CHINESE_DIMENSIONS.indexOf(item.dimension) < 0) {
      issues.push(`chinese item "${item.topicKey}" has invalid dimension="${item.dimension}"`)
    }
    if (item.targetSkillLevel < 1 || item.targetSkillLevel > 5) {
      issues.push(`chinese item "${item.topicKey}" has targetSkillLevel=${item.targetSkillLevel} (out of [1,5])`)
    }
  }

  for (let i = 0; i < plan.writing.length; i++) {
    const item = plan.writing[i]
    if (VALID_WRITING_SUBJECTS.indexOf(item.subject) < 0) {
      issues.push(`writing item "${item.topicKey}" has invalid subject="${item.subject}"`)
    }
  }
```

(d) 文件头注释「集中定义每日 lesson plan 的密度下限 + math 必填字段校验」补 chinese / subject 说明。

- [ ] **Step 4: 编译确认通过** — assembleHap。Expected: BUILD SUCCESSFUL（baseline 测试仍在编译范围内，Task 3 已保证其合规）。
- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/LessonPlannerValidation.ets entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets
git commit -m "feat(lesson-plan): 校验器加 chinese 密度下限 + 维度/subject 白名单"
```

---

### Task 5: 备课提示词 — chinese 内容要求 + 输出模板 v2

**Files:**
- Modify: `entry/src/main/ets/utils/LessonPlanPromptUtils.ets`（仅 `PLANNER_SYSTEM_PROMPT` 常量，`:29-167`）
- Test: `entry/src/ohosTest/ets/test/utils/LessonPlanSectionRender.test.ets`（新建，本任务先落 prompt 断言组）
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册）

**Interfaces:**
- Consumes: 无新代码依赖（纯文本常量）
- Produces: 提示词要求 LLM 输出 `chinese[]`（`topicKey/dimension/character/description/targetSkillLevel/imagePrompt`）、writing 项 `subject`、`"schemaVersion": 2` —— Task 4 校验器与 Task 6 渲染器消费的正是这些字段。

- [ ] **Step 1: 写失败测试** — 新建 `entry/src/ohosTest/ets/test/utils/LessonPlanSectionRender.test.ets`（本任务只写 prompt 断言组；Task 6 在同文件追加渲染用例）：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { PLANNER_SYSTEM_PROMPT } from '../../../../main/ets/utils/LessonPlanPromptUtils'

/**
 * 备课提示词 + 计划 Section 渲染单元测试
 * (Task 5 落 prompt 标记断言; Task 6 追加渲染用例)
 */
export default function lessonPlanSectionRenderTest() {
  describe('PLANNER_SYSTEM_PROMPT - v2 输出契约标记', () => {
    it('包含 chinese 模块示例与字段', 0, () => {
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"chinese"') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"dimension": "pinyin"') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"character"') >= 0).assertTrue()
    })
    it('包含 writing subject 字段与 schemaVersion 2', 0, () => {
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"subject"') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"schemaVersion": 2') >= 0).assertTrue()
    })
    it('包含 chinese 密度下限与台账约束文案', 0, () => {
      expect(PLANNER_SYSTEM_PROMPT.indexOf('chinese: 至少 2 个') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('chinese[].character') >= 0).assertTrue()
    })
  })
}
```

- [ ] **Step 2: 注册测试** — `List.test.ets` 加 `lessonPlanSectionRenderTest`（import + 调用）。
- [ ] **Step 3: 编译确认失败** — assembleHap。Expected: FAIL（prompt 尚无这些标记）。
- [ ] **Step 4: 实现** — `PLANNER_SYSTEM_PROMPT` 八处修改（保持现有编号风格）：

(a) `# 你的输入` 中 ledger 说明（现 `:41`）改为：

```
- ledger: 词级台账状态 (可能为 null), 覆盖英语词与语文项 (汉字/词/拼音/句子), 包含:
```

(b) `# 你的任务` 第 1 条（现 `:57`）改为覆盖 5 模块至少 4 个：

```
1. **聚焦 4-6 个核心点**。今天学太多会让孩子反感。覆盖 vocab / math / chinese / writing / generalKnowledge 中至少 4 个模块。
```

(c) 第 3.5 条台账硬约束（现 `:60-66`）末尾追加一行：

```
    - chinese[].character 同样受台账约束: 严禁出现在 ledger.mastered / ledger.cooling 中; 优先取 newCandidates / dueReview 中的语文项
```

(d) 输出格式「数量硬下限」块（现 `:98-103`）改为（合计同步 14-19）：

```
  - vocab: 至少 4 个, 建议 5 个
  - math: 至少 4 个, 建议 5 个
  - chinese: 至少 2 个, 建议 3 个
  - writing: 至少 2 个, 建议 3 个
  - generalKnowledge: 至少 2 个, 建议 3 个
  - 合计 14-19 个项目。低于下限视为不符合 schema, 调度会重试
```

(e) 输出 JSON 模板（现 `:107-125`）：`"schemaVersion": 1` → `"schemaVersion": 2`；`math` 数组之后插入：

```
  "chinese": [
    {"topicKey": "chinese.pinyin.shan", "dimension": "pinyin", "character": "shān", "description": "拼读 sh—ān→shān", "targetSkillLevel": 2, "imagePrompt": ""}
  ],
```

`writing` 数组示例项补 `"subject": "chinese"` 字段。

(f) 新增 `# 语文模块要求` 小节（放在 `# math 题目难度 rubric` 之前）：

```
# 语文模块要求 (chinese[])

- dimension 必填, 只能是以下之一: pinyin / chinese_vocab / chinese_reading
  - pinyin: 拼音认读 (character 填带调音节, 如 "shān"), 可配合 pinyin_quiz / pinyin_card 出题
  - chinese_vocab: 识字组词 (character 填单字或词, 如 "山" / "高山"), 可配合 hanzi_card / chinese_quiz 出题
  - chinese_reading: 阅读表达 (character 填短句), 可配合 picture_talk / chinese_quiz sentence_order 出题
- targetSkillLevel 必填 1-5, 参考 childProfile 中对应 skill (pinyin / chinese_vocab / chinese_reading) 的 level
- imagePrompt 一律留空 (语文卡片自带笔画数据 / 运行时生图, 无需预生成图)
- topicKey 推荐格式: "chinese.<dimension>.<topic>", 全局唯一
- 中文内容必须地道、6-7 岁孩子能懂; 拼音音节必须带声调符号
```

(g) `# 严禁` 列表（现 `:127-136`）追加三条：

```
- 严禁 chinese 项的 dimension 留空或填白名单外的值; 严禁 targetSkillLevel 填 0 (系统会拒绝重试)
- 严禁 writing 项的 subject 留空或填 english/chinese/math 之外的值 (系统会拒绝重试)
- 严禁 5 个模块任一少于下限 (vocab<4 / math<4 / chinese<2 / writing<2 / generalKnowledge<2)
```

（原有「严禁 4 个模块任一少于下限」一行删除，被上一条取代。）

(h) Fallback 最小合法 JSON（现 `:166-167`）：`"schemaVersion"` → 2，`writing` 示例项补 `"subject": "chinese"`，`math` 数组之后插入：

```
"chinese": [{"topicKey": "chinese.chinese_vocab.shan", "dimension": "chinese_vocab", "character": "山", "description": "认读"山"", "targetSkillLevel": 1, "imagePrompt": ""}, {"topicKey": "chinese.pinyin.shan", "dimension": "pinyin", "character": "shān", "description": "拼读第一声", "targetSkillLevel": 1, "imagePrompt": ""}],
```

  ⚠ 该行 description 内的中文引号 `"山"` 是模板展示文本，安全；但为避免歧义统一写成「认读汉字山，并组词」这样的无引号描述。

- [ ] **Step 5: 编译确认通过** — assembleHap。Expected: BUILD SUCCESSFUL。
- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/LessonPlanPromptUtils.ets entry/src/ohosTest/ets/test/utils/LessonPlanSectionRender.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(lesson-plan): 备课提示词要求 chinese 模块与 writing subject 标签 (schema v2)"
```

---

### Task 6: 渲染器 — 分组渲染 + 单学科渲染

**Files:**
- Modify: `entry/src/main/ets/utils/LessonPlanPromptUtils.ets`（import 区 + `renderDailyPlanSection` + 新函数）
- Test: `entry/src/ohosTest/ets/test/utils/LessonPlanSectionRender.test.ets`（追加用例）

**Interfaces:**
- Consumes: Task 2 的 `collectPlanItemsForSubject` / `PlanSubject`；Task 1 的 `LessonPlanChineseItem`
- Produces: `renderDailyPlanSectionForSubject(plan: LessonPlan, planDate: string, weekday: string, subject: PlanSubject): string`（学科 0 条 → `''`）——Task 7 按此签名调用。

- [ ] **Step 1: 追加失败测试** — `LessonPlanSectionRender.test.ets` import 区补：

```typescript
import {
  PLANNER_SYSTEM_PROMPT,
  renderDailyPlanSection,
  renderDailyPlanSectionForSubject
} from '../../../../main/ets/utils/LessonPlanPromptUtils'
import {
  LessonPlan,
  LessonPlanChineseItem,
  LessonPlanVocabItem,
  LessonPlanWritingItem
} from '../../../../main/ets/models/LessonPlanModels'
```

文件尾部（export default 函数体内）追加：

```typescript
  describe('renderDailyPlanSection - 四学科分组 (Review Focus #5)', () => {
    it('条目按 语文/数学/英语/常识 分组, 空组无空节', 0, () => {
      const p = new LessonPlan()
      p.themeTitle = '秋天的山'
      const c = new LessonPlanChineseItem()
      c.dimension = 'chinese_vocab'
      c.character = '山'
      c.description = '认读并组词'
      c.targetSkillLevel = 2
      p.chinese.push(c)
      const v = new LessonPlanVocabItem()
      v.word = 'apple'
      v.translation = '苹果'
      p.vocab.push(v)
      const wc = new LessonPlanWritingItem()
      wc.characterOrWord = '山'
      wc.subject = 'chinese'
      p.writing.push(wc)
      const we = new LessonPlanWritingItem()
      we.characterOrWord = 'A'
      we.subject = 'english'
      p.writing.push(we)
      const wu = new LessonPlanWritingItem()
      wu.characterOrWord = '旧'
      wu.subject = ''
      p.writing.push(wu)
      const section = renderDailyPlanSection(p, '2026-10-02', '五')
      expect(section.indexOf('### 语文') >= 0).assertTrue()
      expect(section.indexOf('### 英语') >= 0).assertTrue()
      expect(section.indexOf('### 常识') >= 0).assertTrue()
      expect(section.indexOf('### 数学') < 0).assertTrue()   // 空组不输出
      expect(section.indexOf('### 常识') > section.indexOf('### 英语')).assertTrue()
      expect(section.indexOf('apple') >= 0).assertTrue()
      expect(section.indexOf('山') >= 0).assertTrue()
      expect(section.indexOf('旧') > section.indexOf('### 常识')).assertTrue() // 未标签 writing 归常识组
    })
  })

  describe('renderDailyPlanSectionForSubject', () => {
    it('语文视图: 主题句 + chinese 条目 + writing[chinese], 无 teacherNotes / image 指引', 0, () => {
      const p = new LessonPlan()
      p.themeTitle = '秋天的山'
      p.teacherNotes = '记得复习昨天内容'
      const c = new LessonPlanChineseItem()
      c.dimension = 'pinyin'
      c.character = 'shān'
      c.description = '拼读第一声'
      c.targetSkillLevel = 1
      p.chinese.push(c)
      const wc = new LessonPlanWritingItem()
      wc.characterOrWord = '山'
      wc.subject = 'chinese'
      p.writing.push(wc)
      const s = renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'chinese')
      expect(s.indexOf('语文教学目标') >= 0).assertTrue()
      expect(s.indexOf('主题: 秋天的山') >= 0).assertTrue()
      expect(s.indexOf('shān') >= 0).assertTrue()
      expect(s.indexOf('山') >= 0).assertTrue()
      expect(s.indexOf('记得复习昨天内容') < 0).assertTrue()
      expect(s.indexOf('image_generation') < 0).assertTrue()
      expect(s.indexOf('预生成') < 0).assertTrue()
    })
    it('本学科 0 条 → 返回空字符串 (v1 旧计划静默)', 0, () => {
      const p = new LessonPlan()
      p.themeTitle = '旧计划'
      const v = new LessonPlanVocabItem()
      v.word = 'apple'
      p.vocab.push(v)
      expect(renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'chinese')).assertEqual('')
      expect(renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'math')).assertEqual('')
    })
    it('数学视图: math 条目 + writing[math]', 0, () => {
      const p = new LessonPlan()
      const wc = new LessonPlanWritingItem()
      wc.characterOrWord = '3'
      wc.subject = 'math'
      p.writing.push(wc)
      const s = renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'math')
      expect(s.indexOf('数学教学目标') >= 0).assertTrue()
      expect(s.indexOf('3') >= 0).assertTrue()
      expect(s.indexOf('主题:') < 0).assertTrue()   // themeTitle 为空 → 无主题行 (Review Focus #5)
    })
  })
```

- [ ] **Step 2: 编译确认失败** — assembleHap。Expected: FAIL（`renderDailyPlanSectionForSubject` 不存在）。
- [ ] **Step 3: 实现** — `utils/LessonPlanPromptUtils.ets`：

(a) import 区（现 `:13-19`）补 `LessonPlanChineseItem`，并新增：

```typescript
import { collectPlanItemsForSubject, PlanSubject } from './LessonPlanSubjectUtils'
```

(b) `formatGeneralLine` 之后新增：

```typescript
function formatChineseLine(item: LessonPlanChineseItem): string {
  const parts: string[] = []
  parts.push(`- [${item.dimension}] ${item.character}`)
  if (item.description !== '') {
    parts.push(`— ${item.description}`)
  }
  if (item.targetSkillLevel > 0) {
    parts.push(`(目标 level ${item.targetSkillLevel})`)
  }
  return parts.join(' ')
}
```

(c) **重写 `renderDailyPlanSection`**（现 `:173-236`）——教学点部分改为分组输出（`hasAnyItem` 判定加 `plan.chinese.length > 0`；主题/使用建议段保持原样）：

```typescript
export function renderDailyPlanSection(plan: LessonPlan, planDate: string, weekday: string): string {
  const hasAnyItem =
    plan.vocab.length > 0 ||
    plan.math.length > 0 ||
    plan.chinese.length > 0 ||
    plan.writing.length > 0 ||
    plan.generalKnowledge.length > 0 ||
    Object.keys(plan.freeform).length > 0
  if (!hasAnyItem && plan.themeTitle === '') {
    return ''
  }

  const lines: string[] = []
  lines.push(`## 今日教学目标 (${planDate}, 星期${weekday})`)
  lines.push('')
  lines.push(SHARED_OVERRIDE_HEADER)
  if (plan.themeTitle !== '') {
    lines.push(`主题: ${plan.themeTitle}`)
  }
  if (plan.themeDescription !== '') {
    lines.push(`简介: ${plan.themeDescription}`)
  }
  lines.push('')
  lines.push('### 推荐教学点')
  lines.push('')
  // 四学科分组 (2026-10-01 学科拆分): 未打标签 writing 归常识组 (防御性, 校验器使其实际不出现)
  appendSubjectGroup(lines, '语文', collectGroupLines(plan, 'chinese'))
  appendSubjectGroup(lines, '数学', collectGroupLines(plan, 'math'))
  appendSubjectGroup(lines, '英语', collectGroupLines(plan, 'english'))
  appendSubjectGroup(lines, '常识', collectGeneralGroupLines(plan))
  // freeform 扩展模块
  const freeformKeys = Object.keys(plan.freeform)
  for (let i = 0; i < freeformKeys.length; i++) {
    const k = freeformKeys[i]
    const v = plan.freeform[k]
    if (Array.isArray(v)) {
      for (let j = 0; j < v.length; j++) {
        const entry = v[j] as Record<string, Object>
        lines.push(`- [${k}] ${formatFreeformEntry(entry)}`)
      }
    }
  }
  lines.push('')
  if (plan.teacherNotes !== '') {
    lines.push('### 教学提示')
    lines.push(plan.teacherNotes)
    lines.push('')
  }
  lines.push('### 使用建议')
  lines.push('- 不要一次教完所有点,每次聚焦 1-2 个,先聊后教')
  lines.push('- 教新点前调用 child_profile(action:"read") 确认小朋友当前水平')
  lines.push('- 教词汇/数学图形/写字插图时,优先用 image_generation 工具')
  lines.push('  提示词: 直接使用本计划中给出的 imagePrompt, 并在末尾追加 `<topic_key><该条目的topicKey></topic_key>`')
  lines.push('  (例: image_generation prompt="a cute apple, <topic_key>vocab.apple</topic_key>")')
  lines.push('  系统会优先返回备课老师昨晚预生成的图,大幅降低等待时间')
  lines.push('- 已教过的点不要重复出题;可围绕主题变体出题巩固')
  return lines.join('\n')
}

/** 单学科分组行 (chinese: chinese 模块 + writing[chinese]; math/english 同理) */
function collectGroupLines(plan: LessonPlan, subject: PlanSubject): string[] {
  const items = collectPlanItemsForSubject(plan, subject)
  const out: string[] = []
  for (let i = 0; i < items.chinese.length; i++) {
    out.push(formatChineseLine(items.chinese[i]))
  }
  for (let i = 0; i < items.vocab.length; i++) {
    out.push(formatVocabLine(items.vocab[i]))
  }
  for (let i = 0; i < items.math.length; i++) {
    out.push(formatMathLine(items.math[i]))
  }
  for (let i = 0; i < items.writing.length; i++) {
    out.push(formatWritingLine(items.writing[i]))
  }
  return out
}

/** 常识组行: generalKnowledge 模块 + 未打标签 writing (防御性兜底) */
function collectGeneralGroupLines(plan: LessonPlan): string[] {
  const out: string[] = []
  for (let i = 0; i < plan.generalKnowledge.length; i++) {
    out.push(formatGeneralLine(plan.generalKnowledge[i]))
  }
  for (let i = 0; i < plan.writing.length; i++) {
    const w = plan.writing[i]
    if (w.subject === '') {
      out.push(formatWritingLine(w))
    }
  }
  return out
}

/** 非空组才输出标题 (避免空节) */
function appendSubjectGroup(lines: string[], title: string, groupLines: string[]): void {
  if (groupLines.length === 0) {
    return
  }
  lines.push(`### ${title}`)
  lines.push('')
  for (let i = 0; i < groupLines.length; i++) {
    lines.push(groupLines[i])
  }
  lines.push('')
}
```

(d) `renderDailyPlanSection` 之后新增单学科渲染器：

```typescript
/**
 * 渲染"本学科教学目标"section 注入学科老师 system prompt (spec §6.2)。
 * - 本学科 0 条 → 返回 '' (调用方整段省略; v1 旧计划自然静默)
 * - 给主题句, 不给 teacherNotes; 不含 image_generation 指引 (学科助手锁定工具无此工具)
 */
export function renderDailyPlanSectionForSubject(plan: LessonPlan, planDate: string, weekday: string,
  subject: PlanSubject): string {
  const items = collectPlanItemsForSubject(plan, subject)
  const hasItems = items.chinese.length > 0 || items.vocab.length > 0 ||
    items.math.length > 0 || items.writing.length > 0
  if (!hasItems) {
    return ''
  }
  const title = subject === 'math' ? '数学' : (subject === 'english' ? '英语' : '语文')
  const lines: string[] = []
  lines.push(`## ${title}教学目标 (${planDate}, 星期${weekday})`)
  lines.push('')
  lines.push(SHARED_OVERRIDE_HEADER)
  if (plan.themeTitle !== '') {
    lines.push(`主题: ${plan.themeTitle}`)
    lines.push('')
  }
  lines.push('### 推荐教学点')
  lines.push('')
  for (let i = 0; i < items.chinese.length; i++) {
    lines.push(formatChineseLine(items.chinese[i]))
  }
  for (let i = 0; i < items.vocab.length; i++) {
    lines.push(formatVocabLine(items.vocab[i]))
  }
  for (let i = 0; i < items.math.length; i++) {
    lines.push(formatMathLine(items.math[i]))
  }
  for (let i = 0; i < items.writing.length; i++) {
    lines.push(formatWritingLine(items.writing[i]))
  }
  lines.push('')
  lines.push('### 使用建议')
  lines.push('- 不要一次教完所有点,每次聚焦 1-2 个,先聊后教')
  lines.push('- 教新点前调用 child_profile(action:"read") 确认小朋友当前水平')
  lines.push('- 已教过的点不要重复出题;可围绕主题变体出题巩固')
  return lines.join('\n')
}
```

- [ ] **Step 4: 编译确认通过** — assembleHap。Expected: BUILD SUCCESSFUL。
- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/LessonPlanPromptUtils.ets entry/src/ohosTest/ets/test/utils/LessonPlanSectionRender.test.ets
git commit -m "feat(lesson-plan): 渲染器四学科分组 + 单学科视图 renderDailyPlanSectionForSubject"
```

---

### Task 7: 注入门控 — 学科老师拿到本学科计划段

**Files:**
- Modify: `entry/src/main/ets/viewmodels/ChatViewModel.ets`（`buildRequestSystemPrompt` `:322-328` + 新私有方法 + import 区）

**Interfaces:**
- Consumes: Task 2 的 `planSubjectForAssistant` / `PlanSubject`；Task 6 的 `renderDailyPlanSectionForSubject`；现有 `getLessonPlanningService().getTodayPlan()` / `weekdayLabel()`（`ChatViewModel.ets:408`）
- Produces: 无新导出（行为变化：kids_math/english/chinese 会话的 system prompt 携带本学科计划段）

- [ ] **Step 1: 更新 import** — `ChatViewModel.ets` 现有 `LessonPlanPromptUtils` import 行补 `renderDailyPlanSectionForSubject`，并新增：

```typescript
import { planSubjectForAssistant, PlanSubject } from '../utils/LessonPlanSubjectUtils'
```

- [ ] **Step 2: 改造非 default 分支** — `buildRequestSystemPrompt` 中现 `:322-328`：

```typescript
	    // 动态教学计划注入：仅当助手是小星老师时生效（其他助手保持原 prompt 纯净）
	    if (assistantConfig.assistantId !== DEFAULT_ASSISTANT_ID) {
	      // 非小星老师助手不注入教学段, 但保留主动招呼元指令（学科老师开场, 2026-09-25）
	      if (greetingHint.trim() !== '') {
	        return this.assistantService.combineSystemPrompts(withExtra, greetingHint)
	      }
	      return withExtra
	    }
```

替换为：

```typescript
	    // 动态教学计划注入：小星老师拿全量教学段; 学科老师只拿本学科计划段 (2026-10-01 学科拆分)
	    if (assistantConfig.assistantId !== DEFAULT_ASSISTANT_ID) {
	      let composed = withExtra
	      const subject = planSubjectForAssistant(assistantConfig.assistantId)
	      if (subject !== null) {
	        composed = await this.injectSubjectPlanSection(composed, subject)
	      }
	      // 保留主动招呼元指令（学科老师开场, 2026-09-25）, 末尾最高优先级
	      if (greetingHint.trim() !== '') {
	        return this.assistantService.combineSystemPrompts(composed, greetingHint)
	      }
	      return composed
	    }
```

- [ ] **Step 3: 新增私有方法** — `injectTeachingSections`（现 `:345`）之前插入：

```typescript
  /**
   * 把"本学科今日计划"段拼到学科老师 system prompt (spec 2026-10-01 §7)。
   * 计划拉取/渲染失败时静默降级返回原 prompt, 不阻塞对话 (与 injectTeachingSections 同款容错)。
   */
  private async injectSubjectPlanSection(basePrompt: string, subject: PlanSubject): Promise<string> {
    try {
      const today = await getLessonPlanningService().getTodayPlan()
      if (today === null) {
        return basePrompt
      }
      const planDate = today.plan.planDate
      const weekday = this.weekdayLabel(planDate)
      const section = renderDailyPlanSectionForSubject(today.plan, planDate, weekday, subject)
      if (section === '') {
        return basePrompt
      }
      return this.assistantService.combineSystemPrompts(basePrompt, section)
    } catch (error) {
      console.error('ChatViewModel', `injectSubjectPlanSection failed: ${JSON.stringify(error)}`)
      return basePrompt
    }
  }
```

- [ ] **Step 4: 编译验证** — assembleHap。Expected: BUILD SUCCESSFUL。（ViewModel 层无 hypium 覆盖——人工验证点：见 Review Focus #4，`getTodayPlan()` 抛错 / 返回 null / section 为 '' 三条路径均静默降级。）
- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/viewmodels/ChatViewModel.ets
git commit -m "feat(lesson-plan): 学科老师注入本学科今日计划段 (kids_math/english/chinese)"
```

---

### Task 8: 台账种子 — extractLedgerSeeds 收 chinese 项

**Files:**
- Modify: `entry/src/main/ets/utils/LedgerExtractUtils.ets`（`extractLedgerSeeds` `:330-357`）
- Test: `entry/src/ohosTest/ets/test/utils/LedgerExtractUtils.test.ets`（扩展）

**Interfaces:**
- Consumes: Task 1 的 `LessonPlan.chinese`；现有 `normalizeItemKey` / `normalizePinyinSyllable` / `isCJKText` / `pushSeed`
- Produces: 无签名变化（`extractLedgerSeeds(plan)` 返回类型不变，种子多收 chinese 项）——`LessonPlanningService.recordPlanSeeds` 现有调用直接受益。

- [ ] **Step 1: 追加失败测试** — `LedgerExtractUtils.test.ets` 现有 `extractLedgerSeeds` describe 内追加（import 区按需补 `LessonPlanChineseItem`）：

```typescript
    it('chinese 三维度 → zh:pinyin / zh:char|phrase / zh:sentence 种子', 0, () => {
      const plan = new LessonPlan()
      const p1 = new LessonPlanChineseItem()
      p1.topicKey = 'chinese.pinyin.shan'
      p1.dimension = 'pinyin'
      p1.character = 'shān'
      plan.chinese.push(p1)
      const c1 = new LessonPlanChineseItem()
      c1.topicKey = 'chinese.chinese_vocab.shan'
      c1.dimension = 'chinese_vocab'
      c1.character = '山'
      plan.chinese.push(c1)
      const c2 = new LessonPlanChineseItem()
      c2.topicKey = 'chinese.chinese_vocab.gao_shan'
      c2.dimension = 'chinese_vocab'
      c2.character = '高山'
      plan.chinese.push(c2)
      const r1 = new LessonPlanChineseItem()
      r1.topicKey = 'chinese.chinese_reading.hello'
      r1.dimension = 'chinese_reading'
      r1.character = '你好呀'
      plan.chinese.push(r1)
      const seeds = extractLedgerSeeds(plan)
      const keys: string[] = []
      for (let i = 0; i < seeds.length; i++) {
        keys.push(normalizeItemKey(seeds[i].subject, seeds[i].itemType, seeds[i].display))
      }
      expect(keys.indexOf('zh:pinyin:shan1') >= 0).assertTrue()
      expect(keys.indexOf('zh:char:山') >= 0).assertTrue()
      expect(keys.indexOf('zh:phrase:高山') >= 0).assertTrue()
      expect(keys.indexOf('zh:sentence:你好呀') >= 0).assertTrue()
    })
    it('chinese 脏数据: dimension 未知但 CJK → 按 chinese_vocab 归类; 非中文且非 pinyin → 跳过 (Review Focus #3)', 0, () => {
      const plan = new LessonPlan()
      const bad1 = new LessonPlanChineseItem()
      bad1.topicKey = 'chinese.unknown.x'
      bad1.dimension = ''
      bad1.character = '水'
      plan.chinese.push(bad1)
      const bad2 = new LessonPlanChineseItem()
      bad2.topicKey = 'chinese.unknown.y'
      bad2.dimension = ''
      bad2.character = 'abc'
      plan.chinese.push(bad2)
      const seeds = extractLedgerSeeds(plan)
      const keys: string[] = []
      for (let i = 0; i < seeds.length; i++) {
        keys.push(normalizeItemKey(seeds[i].subject, seeds[i].itemType, seeds[i].display))
      }
      expect(keys.indexOf('zh:char:水') >= 0).assertTrue()
      expect(keys.length).assertEqual(1)
    })
```

- [ ] **Step 2: 编译确认失败** — assembleHap。Expected: FAIL（现有实现不收 chinese，`keys.length` 断言为 1 而实际 0——编译能过但断言逻辑必败；确认测试文件编译通过即可，运行时验证在 IDE）。
- [ ] **Step 3: 实现** — `extractLedgerSeeds` 的 writing 循环之后（现 `:355` 前）追加：

```typescript
  const chineseItems = plan.chinese
  for (let i = 0; i < chineseItems.length; i++) {
    const item = chineseItems[i]
    const text = item.character.trim()
    if (text === '') {
      continue
    }
    if (item.dimension === 'pinyin') {
      pushSeed(seeds, seen, 'zh', 'pinyin', text, 'pinyin')
    } else if (item.dimension === 'chinese_reading') {
      pushSeed(seeds, seen, 'zh', 'sentence', text, 'chinese_reading')
    } else if (isCJKText(text)) {
      // chinese_vocab 与未知 dimension 的 CJK 内容按字/词归类 (防御性默认)
      if (text.length === 1) {
        pushSeed(seeds, seen, 'zh', 'char', text, 'chinese_vocab')
      } else {
        pushSeed(seeds, seen, 'zh', 'phrase', text, 'chinese_vocab')
      }
    }
    // 非 pinyin/reading 且非 CJK (脏数据) → 跳过
  }
```

同时更新函数头注释（现 `:327-329`）：补「plan.chinese[].character 按 dimension 映射 zh:pinyin / zh:char|phrase / zh:sentence」。

- [ ] **Step 4: 编译确认通过** — assembleHap。Expected: BUILD SUCCESSFUL。
- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/LedgerExtractUtils.ets entry/src/ohosTest/ets/test/utils/LedgerExtractUtils.test.ets
git commit -m "feat(lesson-plan): 台账种子收集 chinese 计划项 (按维度映射 item_type)"
```

---

### Task 9: 家长计划页 — 语文分区 + 空判定 + writing 学科标签

**Files:**
- Modify: `entry/src/main/ets/pages/LearningTomorrowPlanPage.ets`
- Modify: `entry/src/main/resources/base/element/string.json`

**Interfaces:**
- Consumes: Task 1 的 `LessonPlan.chinese` / `LessonPlanWritingItem.subject`；现有 `getSkillLabel`（`utils/SkillLabelUtils.ets:20`，已覆盖 pinyin/chinese_vocab/chinese_reading 三个 key，见其 `:70`）
- Produces: 无（纯 UI）

- [ ] **Step 1: 加字符串资源** — `resources/base/element/string.json` 的 `learning_section_writing` 条目后插入：

```json
    {
      "name": "learning_section_chinese",
      "value": "语文"
    },
```

- [ ] **Step 2: 页面 import + 空判定** — `LearningTomorrowPlanPage.ets`：

(a) `LessonPlanWritingItem` 的 model import 行补 `LessonPlanChineseItem`。

(b) `isEmpty()`（现 `:333-343`）与 `isPlanBroken()`（现 `:350-357`）的模块空判定各加一行 `p.chinese.length === 0 &&`（位置在 `p.generalKnowledge.length === 0` 之前，保持四模块后加第五模块的一致顺序）。

- [ ] **Step 3: 新增语文分区 @Builder** — `GeneralSection`（现 `:781-789`）之后插入（块结构镜像 `GeneralBlock`）：

```typescript
  @Builder
  private ChineseSection() {
    Column({ space: 6 }) {
      this.SectionTitle($r('app.string.learning_section_chinese'))
      this.ChineseBlock(this.plan)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ChineseBlock(plan: LessonPlan) {
    if (plan.chinese.length === 0) {
      Column() {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .padding(14)
      }
      .width('100%')
      .backgroundColor(this.themeSurface)
      .borderRadius(16)
      .clip(true)
      .border({ width: 1, color: $r('app.color.divider') })
      .visualEffect(buildPointLightBorderEffect())
    } else {
      Column() {
        ForEach(plan.chinese, (item: LessonPlanChineseItem, index: number) => {
          Column() {
            this.ChineseRow(item)
            if (index < plan.chinese.length - 1) {
              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 14, right: 14 })
            }
          }
        }, (item: LessonPlanChineseItem, index: number) => `c_${index}_${item.topicKey}`)
      }
      .width('100%')
    }
  }

  @Builder
  private ChineseRow(item: LessonPlanChineseItem) {
    Column({ space: 4 }) {
      Text(item.character !== '' ? item.character : '—')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      if (item.description !== '') {
        Text(item.description)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(20)
          .width('100%')
      }
      if (item.dimension !== '') {
        Text(getSkillLabel(item.dimension, item.dimension) +
          (item.targetSkillLevel > 0 ? ` · 目标 ${item.targetSkillLevel}` : ''))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .alignItems(HorizontalAlign.Start)
  }
```

- [ ] **Step 4: WritingRow 加学科小标签** — `WritingRow`（现 `:713-730`）中 `Text(item.characterOrWord ...)` 之后、description Text 之前插入：

```typescript
      if (item.subject !== '') {
        Text(item.subject === 'chinese' ? '中' : (item.subject === 'english' ? '英' : '数'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.divider') })
      }
```

- [ ] **Step 5: 挂载分区** — 主 build 中 `this.WritingSection()` 的 Column 块（现 `:1325-1331`）与 `this.GeneralSection()` 的 Column 块（现 `:1332-1338`）之间插入：

```typescript
            Column() {
              this.ChineseSection()
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(HorizontalAlign.Start)
```

- [ ] **Step 6: 编译验证** — assembleHap。Expected: BUILD SUCCESSFUL。
- [ ] **Step 7: Commit**

```bash
git add entry/src/main/ets/pages/LearningTomorrowPlanPage.ets entry/src/main/resources/base/element/string.json
git commit -m "feat(lesson-plan): 家长计划页新增语文分区 + writing 学科标签"
```

---

### Task 10: 文档同步 + IDE 全量测试 + 收尾验证

**Files:**
- Modify: `.claude/rules/teaching-architecture.md`

**Interfaces:**
- Consumes: 前 9 个任务全部落地
- Produces: 文档与代码一致；全部 hypium 用例 IDE 运行通过

- [ ] **Step 1: 更新 teaching-architecture.md** 三处：

(a) §3「注入条件」段：在「其他助手（含 4 个学科助手）拿到的是干净的…」之后补一句：

```
> **2026-10-01 学科拆分**：`kids_math` / `kids_english` / `kids_chinese` 会注入**本学科专属**的"今日教学目标"段（`renderDailyPlanSectionForSubject`：主题句 + 本学科条目，无 teacherNotes / 无 image 指引）；`kids_games` 与自定义助手维持纯净。计划拉取失败静默降级。
```

(b) §5.2 模块表格：加一行 `| chinese | LessonPlanChineseItem[] | 语文点（pinyin/chinese_vocab/chinese_reading 三维白名单，无预生成图） |`，并注明 `writing` 项含 `subject` 标签（english/chinese/math）；「4 个模块数组至少一个有内容」的严格校验描述更新为「5 个模块（含 chinese≥2）+ writing 项 subject 白名单 + chinese 维度白名单」。

(c) §7.3 与 §4 的 `math_quiz` 等工具表不动；在 §12 文件清单表补一行 `| utils/LessonPlanSubjectUtils.ets | 计划学科拆分纯函数（PlanSubject / planSubjectForAssistant / collectPlanItemsForSubject） |`。

- [ ] **Step 2: IDE 全量测试** — 提示用户在 DevEco Studio 中运行（CLI 不可用）：

  右键运行以下测试文件，预期全绿：
  - `utils/LessonPlanModels.test.ets`（Task 1）
  - `utils/LessonPlanSubjectUtils.test.ets`（Task 2）
  - `utils/LessonPlannerBaseline.test.ets`（Task 3，含新增 chinese 用例）
  - `utils/LessonPlannerValidation.test.ets`（Task 4，fixture 已更新）
  - `utils/LessonPlanSectionRender.test.ets`（Task 5+6）
  - `utils/LedgerExtractUtils.test.ets`（Task 8，含新增用例）

- [ ] **Step 3: 人工验证清单**（模拟器/真机，对应 Review Focus）：
  - 手动触发一次备课（家长计划页「重新生成」），确认新计划 JSON 含非空 chinese 数组与 writing.subject（家长页语文分区有内容）
  - 分别从儿童主屏进数学/英语/语文学科会话发消息，确认老师首条回复贴合计划主题句（日志层面可抓 `injectSubjectPlanSection` 无 error）
  - 打开升级前的旧计划（如有），确认学科会话正常、家长页不空白

- [ ] **Step 4: 终验编译** — assembleHap 最后一跑。Expected: BUILD SUCCESSFUL。
- [ ] **Step 5: Commit**

```bash
git add .claude/rules/teaching-architecture.md
git commit -m "docs: teaching-architecture 同步计划学科拆分 (chinese 模块 + 学科老师定向注入)"
```

---

## 任务依赖图

```
Task 1 (模型)
  ├─ Task 2 (SubjectUtils) ──────┐
  ├─ Task 3 (baseline) ─ Task 4 (校验器) ─ Task 5 (提示词) ─ Task 6 (渲染器) ─ Task 7 (门控)
  ├─ Task 8 (台账种子)
  └─ Task 9 (家长页)
                                                        Task 10 (文档 + IDE 测试 + 收尾)
```

Task 2/3/8/9 相互独立（都只依赖 Task 1），可并行派发；Task 4 依赖 3（baseline 先合规再上规则）；Task 5/6 同文件串行；Task 7 依赖 2+6。
