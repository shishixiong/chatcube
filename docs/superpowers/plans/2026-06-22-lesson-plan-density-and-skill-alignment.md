# 每日教学计划：扩充密度 + 技能对齐 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让备课老师每日生成的 lesson plan 满足密度下限（vocab 4+/math 4+/writing 2+/general 2+）并按 child profile 技能级别（8×6 math rubric）出题，不再出现"小朋友加法 lv3 却出个位数题"的脱节。

**Architecture:** 双侧改动——LLM 侧 (PLANNER_SYSTEM_PROMPT 加硬约束 + 8×6 rubric 详表) + 校验侧 (LessonPlanningService pipeline 在 parse 后调 validatePlannerOutput，3 次内部重试后 markFailed 一次)。验证逻辑提取到 utils 公共函数以便单元测试。

**Tech Stack:** ArkTS strict mode (HarmonyOS 6 / API 23), `@ohos/hypium` (test runner inside DevEco Studio only; CLI `hvigorw test` 不可用见 MEMORY.md)

## Global Constraints

[From spec — verbatim, applies to every task]

- 每个模块下限：vocab ≥ 4 / math ≥ 4 / writing ≥ 2 / generalKnowledge ≥ 2
- 8 个 math dimension 白名单：`math_counting / math_addition / math_subtraction / math_multiply / math_divide / math_shapes / math_comparison / math_time`（必须与 `ChildProfileService.SKILL_DEFINITIONS` 8 个 math_* 项一致）
- math 项 `targetSkillLevel` 必填且 ∈ [1, 5]（0 视为未填）
- `runPlanningPipeline` 每次 run 只调一次 `markFailed`，无论内部 3 次重试是否全部失败（不消耗当日 `MAX_FAILS_PER_DAY=3` 预算）
- 验证失败不传 attempt-specific 反馈给 LLM（让强化后的 system prompt 自己起作用）
- 历史 plan_json 不动；下次 pipeline 自然替换
- 不改 schemaVersion（仍 1，schema 形状没变）
- 编译命令：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
- CLI lint/test 不可用——以 IDE 侧手动验证为准

---

## 文件结构

**修改：**
- `entry/src/main/ets/utils/LessonPlanPromptUtils.ets` — PLANNER_SYSTEM_PROMPT 三处增强
- `entry/src/main/ets/services/LessonPlanningService.ets` — pipeline 解析+校验段替换为 3 次重试循环

**新增：**
- `entry/src/main/ets/utils/LessonPlannerValidation.ets` — 纯函数 validation 工具（spec §4.1 的"私有方法"调整为"utils 公共函数"，便于单元测试，与项目 `MathQuizGame.ets` / `CategorizationValidation.ets` 惯例一致）
- `entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets` — 对应 hypium 单元测试

**不动：** LessonPlanModels, renderDailyPlanSection, renderYesterdaySummarySection, buildChildProfileForPlanner, LearningTomorrowPlanPage, DB schema

---

## Task 1: 验证函数（test-first）

**Files:**
- Create: `entry/src/main/ets/utils/LessonPlannerValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets`

**Interfaces:**
- Consumes: `LessonPlan` / `LessonPlanMathItem` from `models/LessonPlanModels.ets`（已有）
- Produces:
  - `PlannerValidationResult { ok: boolean, issues: string[] }`
  - `validatePlannerOutput(plan: LessonPlan): PlannerValidationResult`
  - `MIN_PLANNER_COUNTS: Record<string, number>`（vocab=4/math=4/writing=2/general=2）
  - `VALID_MATH_DIMENSIONS: ReadonlyArray<string>`（8 个值）

- [ ] **Step 1: Write the failing test**

新建 `entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets`：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import {
  validatePlannerOutput,
  MIN_PLANNER_COUNTS,
  VALID_MATH_DIMENSIONS
} from '../../../../main/ets/utils/LessonPlannerValidation'
import {
  LessonPlan,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem,
  LessonPlanGeneralItem
} from '../../../../main/ets/models/LessonPlanModels'

/**
 * LessonPlannerValidation 单元测试
 *
 * 覆盖 spec docs/superpowers/specs/2026-06-22-...-design.md §4.1 全部校验分支。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function emptyPlan(): LessonPlan {
  return new LessonPlan()
}

function filledPlan(): LessonPlan {
  const p = new LessonPlan()
  for (let i = 0; i < 4; i++) {
    const v = new LessonPlanVocabItem()
    v.topicKey = `vocab.word${i}`
    v.word = `word${i}`
    p.vocab.push(v)
  }
  for (let i = 0; i < 4; i++) {
    const m = new LessonPlanMathItem()
    m.topicKey = `math.addition.q${i}`
    m.dimension = 'math_addition'
    m.targetSkillLevel = 2
    p.math.push(m)
  }
  for (let i = 0; i < 2; i++) {
    const w = new LessonPlanWritingItem()
    w.topicKey = `writing.char${i}`
    w.characterOrWord = `字${i}`
    p.writing.push(w)
  }
  for (let i = 0; i < 2; i++) {
    const g = new LessonPlanGeneralItem()
    g.topicKey = `general_nature.item${i}`
    g.dimension = 'general_nature'
    p.generalKnowledge.push(g)
  }
  return p
}

export default function lessonPlannerValidationTest() {
  describe('MIN_PLANNER_COUNTS 常量', () => {
    it('下限为 vocab=4 / math=4 / writing=2 / generalKnowledge=2', 0, () => {
      expect(MIN_PLANNER_COUNTS['vocab']).assertEqual(4)
      expect(MIN_PLANNER_COUNTS['math']).assertEqual(4)
      expect(MIN_PLANNER_COUNTS['writing']).assertEqual(2)
      expect(MIN_PLANNER_COUNTS['general']).assertEqual(2)
    })
  })

  describe('VALID_MATH_DIMENSIONS 常量', () => {
    it('白名单 8 个 math 维度, 与 SKILL_DEFINITIONS 一致', 0, () => {
      expect(VALID_MATH_DIMENSIONS.length).assertEqual(8)
      const expected = [
        'math_counting', 'math_addition', 'math_subtraction', 'math_multiply',
        'math_divide', 'math_shapes', 'math_comparison', 'math_time'
      ]
      for (let i = 0; i < expected.length; i++) {
        expect(VALID_MATH_DIMENSIONS.indexOf(expected[i]) >= 0).assertTrue()
      }
    })
  })

  describe('validatePlannerOutput - 合法路径', () => {
    it('最小合规 plan (vocab=4/math=4/writing=2/general=2) → ok=true', 0, () => {
      const r = validatePlannerOutput(filledPlan())
      expect(r.ok).assertTrue()
      expect(r.issues.length).assertEqual(0)
    })

    it('所有字段填齐 (vocab=5/math=5/writing=3/general=3) → ok=true', 0, () => {
      const p = filledPlan()
      p.vocab.push(new LessonPlanVocabItem())
      p.math.push(new LessonPlanMathItem())
      p.writing.push(new LessonPlanWritingItem())
      p.generalKnowledge.push(new LessonPlanGeneralItem())
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })
  })

  describe('validatePlannerOutput - 模块数量不足', () => {
    it('vocab=3 → ok=false, issues 包含 vocab 数量', 0, () => {
      const p = filledPlan()
      p.vocab.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues.length).assertEqual(1)
      expect(r.issues[0]).assertContain('vocab=3')
      expect(r.issues[0]).assertContain('< min 4')
    })

    it('math=3 → ok=false', 0, () => {
      const p = filledPlan()
      p.math.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('math=3')
    })

    it('writing=1 → ok=false', 0, () => {
      const p = filledPlan()
      p.writing.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('writing=1')
    })

    it('generalKnowledge=1 → ok=false', 0, () => {
      const p = filledPlan()
      p.generalKnowledge.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('generalKnowledge=1')
    })

    it('空 plan → ok=false, 4 个 issues', 0, () => {
      const r = validatePlannerOutput(emptyPlan())
      expect(r.ok).assertFalse()
      expect(r.issues.length).assertEqual(4)
    })
  })

  describe('validatePlannerOutput - math 必填字段', () => {
    it('math 项 dimension="" → ok=false, issues 包含 invalid dimension', 0, () => {
      const p = filledPlan()
      p.math[0].dimension = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid dimension')
    })

    it('math 项 dimension="math_logic" (不在白名单) → ok=false', 0, () => {
      const p = filledPlan()
      p.math[0].dimension = 'math_logic'
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid dimension')
      expect(r.issues[0]).assertContain('math_logic')
    })

    it('math 项 dimension="math_shapes" (白名单内) → ok=true', 0, () => {
      const p = filledPlan()
      p.math[0].dimension = 'math_shapes'
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })

    it('math 项 targetSkillLevel=0 → ok=false, issues 包含 out of [1,5]', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 0
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('targetSkillLevel=0')
      expect(r.issues[0]).assertContain('out of [1,5]')
    })

    it('math 项 targetSkillLevel=6 → ok=false', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 6
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('targetSkillLevel=6')
    })

    it('math 项 targetSkillLevel=1 (合法下限) → ok=true', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 1
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })

    it('math 项 targetSkillLevel=5 (合法上限) → ok=true', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 5
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })
  })

  describe('validatePlannerOutput - 多重 issues 累积', () => {
    it('vocab=3 + math 缺 dimension → 2 个 issues 都列出', 0, () => {
      const p = filledPlan()
      p.vocab.pop()
      p.math[0].dimension = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues.length).assertEqual(2)
    })
  })
}
```

- [ ] **Step 2: Verify test fails (missing module)**

不要跑测试（CLI 不可用）。改为：在 DevEco Studio 打开 `entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets`，IDE 会红波浪线提示 `Cannot find module '../../../../main/ets/utils/LessonPlannerValidation'`。这是预期的失败状态。

- [ ] **Step 3: Implement the validation module**

新建 `entry/src/main/ets/utils/LessonPlannerValidation.ets`：

```typescript
/**
 * 备课老师 LLM 输出验证器
 *
 * 集中定义每日 lesson plan 的密度下限 + math 必填字段校验。
 * - MIN_PLANNER_COUNTS: 每模块最小 item 数量
 * - VALID_MATH_DIMENSIONS: math 项 dimension 白名单（必须与 ChildProfileService.SKILL_DEFINITIONS 一致）
 * - validatePlannerOutput: 主入口, 返回 { ok, issues }
 *
 * 纯函数, 无副作用, 无 IO。可被 LessonPlanningService.runPlanningPipeline 在
 * 3 次内部重试循环中反复调用。
 *
 * Spec: docs/superpowers/specs/2026-06-22-lesson-plan-density-and-skill-alignment-design.md §4.1
 */

import {
  LessonPlan
} from '../models/LessonPlanModels'

/** 每模块最小 item 数量（用户选"中等"目标 5/5/3/3 的下限） */
export const MIN_PLANNER_COUNTS: Record<string, number> = {
  vocab: 4,
  math: 4,
  writing: 2,
  general: 2
}

/** math 项 dimension 白名单（8 个, 必须与 ChildProfileService.SKILL_DEFINITIONS 一致） */
export const VALID_MATH_DIMENSIONS: ReadonlyArray<string> = [
  'math_counting',
  'math_addition',
  'math_subtraction',
  'math_multiply',
  'math_divide',
  'math_shapes',
  'math_comparison',
  'math_time'
]

export interface PlannerValidationResult {
  ok: boolean
  issues: string[]
}

/**
 * 验证备课老师 LLM 输出的 plan。
 * 返回 { ok: boolean, issues: string[] }。
 * - 任一模块数量低于下限 → issues 加一条
 * - 任一 math 项 dimension 不在白名单 → issues 加一条
 * - 任一 math 项 targetSkillLevel 不在 [1, 5] 区间 → issues 加一条
 * - 全部通过 → ok=true, issues 为空数组
 */
export function validatePlannerOutput(plan: LessonPlan): PlannerValidationResult {
  const issues: string[] = []

  if (plan.vocab.length < MIN_PLANNER_COUNTS['vocab']) {
    issues.push(`vocab=${plan.vocab.length} < min ${MIN_PLANNER_COUNTS['vocab']}`)
  }
  if (plan.math.length < MIN_PLANNER_COUNTS['math']) {
    issues.push(`math=${plan.math.length} < min ${MIN_PLANNER_COUNTS['math']}`)
  }
  if (plan.writing.length < MIN_PLANNER_COUNTS['writing']) {
    issues.push(`writing=${plan.writing.length} < min ${MIN_PLANNER_COUNTS['writing']}`)
  }
  if (plan.generalKnowledge.length < MIN_PLANNER_COUNTS['general']) {
    issues.push(`generalKnowledge=${plan.generalKnowledge.length} < min ${MIN_PLANNER_COUNTS['general']}`)
  }

  for (let i = 0; i < plan.math.length; i++) {
    const item = plan.math[i]
    if (item.dimension === '' || VALID_MATH_DIMENSIONS.indexOf(item.dimension) < 0) {
      issues.push(`math item "${item.topicKey}" has invalid dimension="${item.dimension}"`)
    }
    if (item.targetSkillLevel < 1 || item.targetSkillLevel > 5) {
      issues.push(`math item "${item.topicKey}" has targetSkillLevel=${item.targetSkillLevel} (out of [1,5])`)
    }
  }

  return { ok: issues.length === 0, issues }
}
```

- [ ] **Step 4: Verify test compiles in IDE**

在 DevEco Studio 中打开 `LessonPlannerValidation.test.ets`，确认无 import 报错。**不要执行测试**——CLI 不可用，按 §10 验收清单在 IDE 中右键 Run。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/LessonPlannerValidation.ets \
        entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets
git commit -m "feat(lesson-plan): add planner output validator with tests

- MIN_PLANNER_COUNTS: vocab=4 / math=4 / writing=2 / general=2
- VALID_MATH_DIMENSIONS: 8 math skill_keys whitelist
- validatePlannerOutput(): returns { ok, issues }, pure function
- 14 unit tests cover valid path + count shortfalls + math field rules"
```

---

## Task 2: PLANNER_SYSTEM_PROMPT 三处增强

**Files:**
- Modify: `entry/src/main/ets/utils/LessonPlanPromptUtils.ets` 第 28-111 行的 `PLANNER_SYSTEM_PROMPT` 字符串

**Interfaces:**
- 无（常量字符串修改）
- 消费者：`LessonPlanningService.runPlanningPipeline` 调 LLM 时用 `PLANNER_SYSTEM_PROMPT` 作为 system 消息

**⚠ 重要：模板字符串内嵌 JSON schema 陷阱**（MEMORY.md 已记录）——如果 rubric 表格里写了 ASCII `"`，会在运行时炸 `JSON.parse`。本任务的 rubric 是 markdown 表格不是 JSON schema 字段，**无此风险**。但若日后在 prompt 内嵌入新的 JSON 描述字段，仍需用 `「」` 中文方头括号或全宽引号代替 ASCII `"`。

- [ ] **Step 1: 替换软约束段为硬目标**

定位 `LessonPlanPromptUtils.ets` 第 70 行附近，原文：

```
**4 个模块数组的强约束 (重要!)**:
- vocab、sentence / math / writing / generalKnowledge **每个数组都必须填入至少 1 个具体教学点**
- 禁止把内容写在 themeTitle/themeDescription/teacherNotes 里, 然后 4 个数组留空
- themeTitle 是 1 句话主题, 它**不替代** 4 个模块里的具体内容
- 典型配比: 1～5 个 vocab/sentence + 3～5 个 math + 1～5 个 writing + 1 个 generalKnowledge, 或视主题扩展
```

替换为：

```
**4 个模块数组的强约束 (重要!)**:
- vocab、sentence / math / writing / generalKnowledge **每个数组都必须填入至少 1 个具体教学点**
- 禁止把内容写在 themeTitle/themeDescription/teacherNotes 里, 然后 4 个数组留空
- themeTitle 是 1 句话主题, 它**不替代** 4 个模块里的具体内容
- **数量硬下限**（系统会拒绝重试）:
  - vocab: 至少 4 个, 建议 5 个
  - math: 至少 4 个, 建议 5 个
  - writing: 至少 2 个, 建议 3 个
  - generalKnowledge: 至少 2 个, 建议 3 个
  - 合计 12-16 个项目。低于下限视为不符合 schema, 调度会重试
```

- [ ] **Step 2: 在任务说明段（第 47-49 行附近）插入 math 必填字段段**

定位 `LessonPlanPromptUtils.ets` 第 47 行附近（原"5. **imagePrompt 必须是英文**"段），在它前面插入：

```
4.5 **math 模块必填字段 (硬约束)**:
- 每个 math 项的 `dimension` 字段必填, 必须是以下之一:
  math_counting / math_addition / math_subtraction / math_multiply / math_divide /
  math_shapes / math_comparison / math_time
- 每个 math 项的 `targetSkillLevel` 字段必填, 1-5 整数 (0 视为未填, 重试)
- 严禁 dimension 留空字符串; 严禁 targetSkillLevel 填 0 或超过 5
```

- [ ] **Step 3: 在"严禁"段（第 94-102 行）后追加 rubric 详表**

定位 `LessonPlanPromptUtils.ets` 第 94 行的 `# 严禁` 段，在该段后面（fallback 段之前）插入新段：

```
# math 题目难度 rubric (必须按 child skill level 查表出题)

| skill_key            | Lv0 入门 | Lv1 入门 | Lv2 初步 | Lv3 中等 | Lv4 良好 | Lv5 精通 |
|----------------------|---------|---------|---------|---------|---------|---------|
| math_counting        | 数字认读 1-5 | 数 1-10 | 数 1-20 + 倒数 5-1 | 数列 2,4,6... | 100 内数数 | 凑十/破十计数 |
| math_addition        | 0+0 概念 | 个位数 (3+5) | 两位无进位 (23+14) | 两位进位 (27+18) | 三位数 (123+234) | 多步/应用题 |
| math_subtraction     | 0-0 概念 | 个位数 (8-3) | 两位无退位 (35-12) | 两位退位 (42-17) | 三位数 (532-218) | 多步/应用题 |
| math_multiply        | 0×0 概念 | 1-5 表 | 1-9 表完整 | 多位数×1 位 | 多位数×2 位 | 应用题 |
| math_divide          | 平均分概念 | 表内除法 | 有余数除法 | 多位数÷1 位 | 多位数÷2 位 | 应用题 |
| math_shapes          | 圆形/方形识别 | 基本图形 | 组合形状 | 立体形状 | 周长/面积 | 体积/对称 |
| math_comparison      | 大小/长短 | 多少比较 | 3 项排序 | 多条件排序 | 应用题比较 | 复合比较 |
| math_time            | 整点认读 | 半点 | 5 分钟间隔 | 分钟精确 | 时间计算 | 日历/星期 |

# 出题规则
- 查 childProfile 中该 skill 的 level, 按上表对应行的内容出题
- 例: child math_addition.level=3 → 出 27+18 类型的两位数进位加法
- 如果 child level=0 但 difficultyTendency='harder', 可上跳一级 (取 Lv1 内容)
- description 字段必须描述具体题型 (如「两位数加两位数, 含进位」), 不要写"出加法题"这种模糊描述
```

- [ ] **Step 4: 在第 94 行 `# 严禁` 段补 2 条**

定位 `LessonPlanPromptUtils.ets` 第 94 行 `# 严禁` 段，在已有 6 条后追加：

```
- 严禁 math 项的 dimension 留空字符串; 严禁 targetSkillLevel 填 0 (系统会拒绝重试)
- 严禁 4 个模块任一少于下限 (vocab<4 / math<4 / writing<2 / generalKnowledge<2)
```

- [ ] **Step 5: Verify prompt template literal is valid**

`PLANNER_SYSTEM_PROMPT` 是模板字符串，无 JSON 嵌入。但表格里的 markdown `|` 不影响模板字符串合法性。运行 grep 确认修改未破坏模板字符串边界：

```bash
grep -c 'PLANNER_SYSTEM_PROMPT: string = `' entry/src/main/ets/utils/LessonPlanPromptUtils.ets
```

Expected: 1（模板字符串开头恰好一处）。同时：

```bash
# 确认反引号配对 (开头 1 个, 闭合 1 个)
grep -o '\`' entry/src/main/ets/utils/LessonPlanPromptUtils.ets | wc -l
```

Expected: 偶数。

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/LessonPlanPromptUtils.ets
git commit -m "feat(lesson-plan): strengthen planner prompt with hard constraints

- Module count lower bounds: vocab 4 / math 4 / writing 2 / general 2
- Math item mandatory fields: dimension + targetSkillLevel (1-5)
- 8x6 math rubric table mapping skill_key + level to problem types
- Output rejection rules added to 严禁 section"
```

---

## Task 3: pipeline 接入 3 次内部重试循环

**Files:**
- Modify: `entry/src/main/ets/services/LessonPlanningService.ets` 第 561-587 行附近

**Interfaces:**
- Consumes: `validatePlannerOutput` from `utils/LessonPlannerValidation`（Task 1 已建）
- Produces: 不变（外部 API 仍是 `runPlanningPipeline` 异步方法）

- [ ] **Step 1: 添加 import**

定位 `LessonPlanningService.ets` 第 1-80 行的 import 块，在合适位置加入：

```typescript
import {
  validatePlannerOutput
} from '../utils/LessonPlannerValidation'
```

放在其他 `../utils/...` import 之后。

- [ ] **Step 2: 替换解析+校验段为 3 次重试循环**

定位 `LessonPlanningService.ets` 第 561-587 行，原文：

```typescript
      // 7. 解析 + 校验 LLM 输出
      const cleaned = cleanPlannerJsonOutput(llmResult.content)
      if (cleaned === '' || !isValidJson(cleaned)) {
        await this.markFailed(planId, planDate, 'LLM 输出非合法 JSON', sessions.length, messageCount, sessionIdsJson)
        return
      }
      let plan = parseLessonPlan(cleaned)
      // 强制 planDate 同步为本地时区（防止 LLM 写出错误日期）
      plan.planDate = planDate
      plan.childSnapshot = childSnapshot

      // 校验: 4 个模块数组全空 + themeTitle/teacherNotes 非空 = LLM 把所有内容
      // 写成叙述文字塞进 theme, 没有按 schema 填入结构化模块。视为无效输出, 失败重试
      const hasAnyModuleItem = plan.vocab.length > 0 || plan.math.length > 0 ||
        plan.writing.length > 0 || plan.generalKnowledge.length > 0
      const hasNarrative = plan.themeTitle !== '' || plan.teacherNotes !== ''
      if (!hasAnyModuleItem && hasNarrative) {
        console.warn('LessonPlanningService',
          `LLM output for ${planDate} has all 4 module arrays empty (theme/notes only) — ` +
          `vocab=${plan.vocab.length} math=${plan.math.length} writing=${plan.writing.length} ` +
          `general=${plan.generalKnowledge.length} themeLen=${plan.themeTitle.length} ` +
          `notesLen=${plan.teacherNotes.length}. Marking failed.`)
        await this.markFailed(planId, planDate,
          'LLM 输出未遵循 schema: 4 个模块数组全空, 仅有 theme/teacherNotes 叙述',
          sessions.length, messageCount, sessionIdsJson)
        return
      }
```

替换为：

```typescript
      // 7. 解析 + 校验 LLM 输出 (3 次内部重试, 仅末次失败才 markFailed 一次)
      const MAX_INTERNAL_ATTEMPTS = 3
      let plan: LessonPlan | null = null
      let lastError = ''

      for (let attempt = 1; attempt <= MAX_INTERNAL_ATTEMPTS; attempt++) {
        // 内部重试时复用第一次的 llmResult 仅适合"LLM 偶发失败"场景。
        // 校验失败是因为 prompt 输出不符合 schema, 必须重新调 LLM 才能拿到更好的输出。
        const attemptLlm = attempt === 1 ? llmResult : await this.callPlannerLLM(userInput)
        if (!attemptLlm.success) {
          lastError = `LLM call failed: ${attemptLlm.errorMessage}`
          break
        }

        const cleaned = cleanPlannerJsonOutput(attemptLlm.content)
        if (cleaned === '' || !isValidJson(cleaned)) {
          lastError = `attempt ${attempt}: LLM output is not valid JSON`
          console.warn('LessonPlanningService', `Plan ${planDate} attempt ${attempt}: invalid JSON`)
          continue
        }

        const candidate = parseLessonPlan(cleaned)
        // 强制 planDate 同步为本地时区（防止 LLM 写出错误日期）
        candidate.planDate = planDate
        candidate.childSnapshot = childSnapshot

        const validation = validatePlannerOutput(candidate)
        if (validation.ok) {
          plan = candidate
          break
        }
        lastError = `attempt ${attempt}: ${validation.issues.join('; ')}`
        console.warn('LessonPlanningService',
          `Plan ${planDate} attempt ${attempt} validation failed: ${lastError}`)
      }

      // 3 次都不达标 → 记一次失败 (仅增 1 次计数, 不消耗当日 MAX_FAILS_PER_DAY 预算)
      if (plan === null) {
        await this.markFailed(planId, planDate, lastError, sessions.length, messageCount, sessionIdsJson)
        return
      }
```

**实现者注意：**
- `llmResult` 在原代码是 step 6 的局部变量。重试循环引用它意味着 attempt=1 复用第一次 LLM 结果。但 `validatePlannerOutput` 对**同一 JSON** 总是给同一结果——所以 attempt=1 失败的话，attempt=2 必须**重新调** LLM 才能拿到不同输出。
- 上面的实现 `attempt === 1 ? llmResult : await this.callPlannerLLM(userInput)` 正确处理了这点：第一次复用，后续重新调
- `callPlannerLLM` 是 `LessonPlanningService` 类内私有方法（已存在），签名不变

- [ ] **Step 3: Verify replacement preserves step numbering**

确认替换后 step 编号连续：8（持久化）、9（resetTodayFailCount）、10（refresh tick）、11（prefetchImages）保留不变。

定位 `LessonPlanningService.ets` 找到 `// 8.` 段开头：

```bash
grep -n '// 8\.\|// 9\.\|// 10\.\|// 11\.' entry/src/main/ets/services/LessonPlanningService.ets | head -5
```

Expected: 4 个匹配，分别指向持久化、reset、tick、prefetch 段。

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/services/LessonPlanningService.ets
git commit -m "feat(lesson-plan): 3-attempt internal retry in planner pipeline

- Replace parse+all-empty check with validatePlannerOutput() in retry loop
- Each pipeline run calls markFailed at most once regardless of retries
- Internal retries re-call LLM to get different outputs (not reuse stale result)
- Drop hasAnyModuleItem/hasNarrative check (subsumed by new validator)"
```

---

## Task 4: 编译 + IDE 侧验证

**Files:**
- 不修改代码

- [ ] **Step 1: Run assembleHap**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: BUILD SUCCESSFUL，无 ArkTS strict mode 报错。

**常见错误与修复：**

- `arkts-no-untyped-obj-literals (10605038)`：若循环体出现 `{ ok: false, issues: [] }` 内联对象，改为构造 `PlannerValidationResult` 实例或保留返回类型标注
- `arkts-no-obj-literals-as-types (10605040)`：若 `PlanValidationResult` 接口未声明直接当返回类型使用，需先 `export interface`

- [ ] **Step 2: 在 DevEco Studio 跑单元测试**

打开 `entry/src/ohosTest/ets/test/utils/LessonPlannerValidation.test.ets` → 右键 → Run 'hypium test'。

Expected: 14 个 test case 全部 PASS。
- 2 个常量测试
- 2 个合法路径测试
- 5 个数量不足测试
- 7 个 math 必填字段测试
- 1 个多重 issues 测试
- 总计 17 个

(实际期望数：MIN_PLANNER_COUNTS 1 + VALID_MATH_DIMENSIONS 1 + 合法 2 + 数量不足 5 + math 字段 7 + 多重 1 = 17 cases)

如果失败：在 IDE 中点击失败的 test case 查看期望值 vs 实际值。常见错误是 `filledPlan()` helper 复制粘贴时漏字段。

- [ ] **Step 3: 手动冒烟测试**

按 spec §10 验收清单：

1. **密度验收**：开启新对话 → 触发会话结束 → 等 5 分钟 debounce → 打开明日计划页面（LearningTomorrowPlanPage）→ 检查 vocab/math/writing/general 数量都 ≥ 下限
2. **math 字段验收**：点开 math 卡片 → 每条都带 `dimension`（如 `math_addition`）和 `targetSkillLevel`（如 `3`）
3. **难度对齐验收**：临时把 child profile 的 `math_addition.level` 改为 3 → 触发会话结束 → 等下次 pipeline → 明日 plan 中 `math_addition` 项 description 包含"两位数进位"或"27+18"等关键词

如果第 1 项返回 vocab < 4 → 检查 hilog 中是否有 `attempt N validation failed` 日志，确认 3 次重试都失败 → 检查 LLM 实际输出 + 验证 rubric 表是否被 LLM 看到（可能 prompt 截断）

- [ ] **Step 4: 无 commit（如有修改才提交）**

如果 Step 1-3 都没产生代码改动，**不 commit**。如果发现 bug 修了，先 commit fix，再合入下一个 task 或独立 fix commit。

---

## 附录 A：自检清单

**Spec 覆盖：**
- [x] §3.1 密度硬约束 → Task 2 Step 1
- [x] §3.2 math 必填字段 → Task 2 Step 2
- [x] §3.3 8×6 rubric 详表 → Task 2 Step 3
- [x] §3.4 严禁段补充 → Task 2 Step 4
- [x] §4.1 validatePlannerOutput 函数 → Task 1
- [x] §4.2 3 次内部重试循环 → Task 3
- [x] §4.3 不变的关键约束 → Task 3 Step 2 注释 + Step 4 commit message
- [x] §10 验收 → Task 4

**Placeholder scan：** 无 TBD/TODO/"implement later"。"类似"措辞只出现在实现者注释（解释设计意图），非省略步骤。

**Type consistency：**
- `PlannerValidationResult` / `validatePlannerOutput` / `MIN_PLANNER_COUNTS` / `VALID_MATH_DIMENSIONS` 在 Task 1 定义、Task 1 测试使用、Task 3 导入使用——名字一致
- `LessonPlan` / `LessonPlanVocabItem` / `LessonPlanMathItem` / `LessonPlanWritingItem` / `LessonPlanGeneralItem` 从 `models/LessonPlanModels` 导入，与现有 LessonPlanningService 用法一致

**Scope check：** 4 个 task，分别覆盖纯函数 + 测试、prompt 增强、pipeline 改造、编译验证。每个 task 独立可测，合并后产生完整功能。符合"单实施计划"颗粒度。