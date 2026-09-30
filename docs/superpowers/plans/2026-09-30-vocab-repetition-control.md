# 词汇重复控制与间隔巩固 (Vocab Repetition Control) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为小星老师的英语/语文教学建立词级台账（learning_items + learning_item_events）、Leitner 间隔重复、三名单选词、prompt 动态注入与出题硬门禁，堵住"即兴出题绕过 7 天去重"的最大漏洞。

**Architecture:** 单一 SQLite 台账（写入侧：10 个 quiz handler 在 pending 态登记曝光、`recordStarEvent` 末尾回写作答；读取侧：`LearningLedgerService.buildSummary` 生成三名单注入 prompt + `checkRepeat` 硬门禁拦截重复出题）。所有提取/归一化/策略逻辑为纯函数（`utils/LedgerExtractUtils.ets` / `utils/VocabRepeatValidation.ets` / `models/LearningLedgerModels.ets`），服务层只做 DB 编排，handler 只加 1-3 行调用。

**Tech Stack:** ArkTS (API 23, stage model), relationalStore (SQLite), @ohos/hypium 单测（仅纯函数）。

**Spec:** `docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md`（Task 1 第一步把现存于 `docs/docs_superpowers_specs_2026-09-30-vocab-repetition-control-design.md` 的文件 `git mv` 到此路径；执行者须先读 spec 的 §3/§4/§5/§6.2/§7/§8/§9/§10）。

---

## Global Constraints

- **静默失败铁律（spec §10）**：所有台账读写、`checkRepeat`、`upsertPlanItems` 必须 try/catch 静默 + `hilog.warn`，**台账失败绝不阻断出题/授星/备课**。门禁查询失败 → 视为放行（`allowed=true`）。
- **单一归一化**：`normalizeItemKey` 只存在于 `utils/LedgerExtractUtils.ets`，写入侧（recordServed/upsertPlanItems）与门禁侧共用；严禁在任何 handler 或服务里内联归一化逻辑。
- **讲解型工具不推进掌握度**：`hanzi_card` / `pinyin_card` / `picture_talk` 记曝光（recordServed），`extractLedgerAnswerItems` 对它们恒返回 `[]`。
- **purpose 语义**：`purpose:"review"` 豁免 `same_mode_cooldown` 与 `mastered_recheck`，但**不豁免** `session_gap`（会话间隔任何 purpose 都生效）。
- **作答对账只挂 `recordStarEvent` 末尾**：取消/关闭卡片（resolvePendingAnswer 收到 null）的路径在 recordStarEvent 之前就 early-return，天然不会写台账——不得在其他位置再挂 recordAnswer。
- **不改动**：卡片组件 UI、`StarRewardService.computeStars`、`child_profile` 工具、现有 `validateXxxArgs` 校验器的判定语义、`computeStars` 授星逻辑。
- **ArkTS 严格模式**：`arr.map(p => ({...}))` 内联对象字面量必须显式标注返回类型（10605038）——本计划所有 map 回调只返回字符串/已有类型；禁止 `const [a, b] = ...` 解构（10605074）；ForEach builder 体内禁止 const 声明（10905209）；对象字面量必须带接口/类注解。
- **JSON-in-template-literal 陷阱**：改 `config/BuiltinTools.ets` schema 时，description 字段内禁用 ASCII 双引号（用 `「」`）；每次改完用 `node -e` 提取并 `JSON.parse` 验证（各任务内给出命令）。
- **测试运行限制**：`hvigorw test` CLI 已知损坏（scaffold mismatch）——hypium 测试**无法在 CLI 跑**。每个测试任务的验证 = ① 主模块 `assembleHap` 编译通过 ② ohosTest 模块编译通过（best-effort，命令见下）。测试的真实运行由用户在 DevEco Studio IDE 中右键执行。TDD 的"先写测试"保留（测试与实现同任务内先后编写，编译双验证）。
- **构建验证命令**（每任务结束跑，必须 exit 0）：
  ```bash
  cd /Users/mac/mygame/HarmonyOS-app/chatcube && DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
  ```
- **ohosTest 编译验证命令**（写测试的任务加跑，best-effort；若 target 名报错则跳过并记录）：
  ```bash
  cd /Users/mac/mygame/HarmonyOS-app/chatcube && DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug -p module=entry@ohosTest
  ```
- 每个任务结束 `git add -A && git commit`（信息在各任务给出）。
- 涉及行号的锚点（如 `:825`）是 2026-09-30 快照；**以锚点描述的代码特征定位为准**，行号漂移时用 grep。

## Review Focus

1. **台账失败不得阻断出题**——用户预期：数据库损坏/写满时，出题、授星、备课行为与现状完全一致。→ 钉住：Task 4 `checkRepeat` catch 返回 allowed；Task 5 `recordLedgerServed/recordLedgerAnswered` 全身 try/catch；代码评审时逐个确认 catch 存在且吞掉异常只打日志。
2. **写入侧与门禁侧必须共用同一个 `normalizeItemKey`**——否则同一词两种 key，台账静默漏记/门禁失效且无报错。→ 钉住：Task 2 测试 `normalizeItemKey` 各 subject/itemType 归一化（含大小写/标点/声调）；评审时 grep 确认无第二处归一化实现。
3. **讲解型工具不得推进掌握度**——用户预期：看 hanzi_card 讲解 100 次不会让 mastery 上升（讲解≠会做）。→ 钉住：Task 2 测试 `extractLedgerAnswerItems('hanzi_card', ...) === []`（pinyin_card/picture_talk 同）。
4. **purpose:"review" 豁免冷却但不豁免会话间隔**——用户预期：复习旧词仍不能在 5 题内刷屏。→ 钉住：Task 2 `evaluateRepeatPolicy` 真值表测试（review × session_gap → blocked；review × cooldown → allowed；new × cooldown → blocked；new × mastered_recheck → blocked）。
5. **取消作答不写台账**——用户预期：孩子关掉卡片没答，掌握度不变（曝光可记）。→ 钉住：Task 5 recordAnswer 挂钩只在 `recordStarEvent` 内（该方法仅由拿到 answerJson 的路径调用）；Task 2 测试 malformed answerJson → `[]`。

---

### Task 1: 数据模型 + 纯策略函数（models/LearningLedgerModels.ets）

**Files:**
- Create: `entry/src/main/ets/models/LearningLedgerModels.ets`
- Test: `entry/src/ohosTest/ets/test/utils/LearningLedgerModels.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册新 suite）
- Move: `docs/docs_superpowers_specs_2026-09-30-vocab-repetition-control-design.md` → `docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md`

**Interfaces:**
- Produces（后续所有任务依赖，签名逐字使用）：
  - 常量：`LEDGER_INTERVAL_DAYS: number[]`、`LEDGER_DAY_MS`、`SAME_MODE_COOLDOWN_MS`、`SESSION_GAP_ITEMS`、`MASTERED_RECHECK_MS`、`TOP_REPEATED_WINDOW_MS`、`SUMMARY_CACHE_TTL_MS`、`RECENT_WINDOW_CAPACITY`、`EVENT_RETENTION_MS`、`RECENT_SESSION_PRUNE_MAX`、`REPEAT_REASON_SESSION_GAP`、`REPEAT_REASON_SAME_MODE_COOLDOWN`、`REPEAT_REASON_MASTERED_RECHECK`
  - 类：`LearningItem`（20 字段）、`LedgerSummary`、`DueReviewHint{display,lastMode,dueInMs}`、`RepeatStat{display,count}`
  - 接口：`LedgerRecord`、`LedgerItemSeed`、`LedgerToolItem{subject,itemType,display,mode,skillKey}`、`LedgerAnswerItem{itemKey,isCorrect}`、`LedgerEventInsert`、`MasteryTransition`、`RepeatCheck{allowed,reason,itemKey,display}`、`RepeatPolicyInput`
  - 函数：`createEmptyLedgerSummary(): LedgerSummary`、`computeMasteryTransition(mastery: number, consecutiveCorrect: number, isCorrect: boolean, now: number): MasteryTransition`

- [ ] **Step 1: git mv 修 design 文档路径**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git mv docs/docs_superpowers_specs_2026-09-30-vocab-repetition-control-design.md docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md
```

- [ ] **Step 2: 写失败测试** `entry/src/ohosTest/ets/test/utils/LearningLedgerModels.test.ets`

```ets
import { describe, it, expect } from '@ohos/hypium'
import {
  LEDGER_INTERVAL_DAYS,
  MASTERED_RECHECK_MS,
  LearningItem,
  LedgerSummary,
  createEmptyLedgerSummary,
  computeMasteryTransition
} from '../../../../main/ets/models/LearningLedgerModels'

export default function learningLedgerModelsTest(): void {
  describe('learningLedgerModelsTest', () => {
    it('interval_table_has_6_slots', 0, () => {
      expect(LEDGER_INTERVAL_DAYS.length).assertEqual(6)
      expect(LEDGER_INTERVAL_DAYS[0]).assertEqual(0)
      expect(LEDGER_INTERVAL_DAYS[5]).assertEqual(15)
    })

    it('computeMasteryTransition_correct_twice_bumps_mastery', 0, () => {
      // streak=1, mastery=1 → 再对一次 → mastery 2, 间隔 2 天
      const t = computeMasteryTransition(1, 1, true, 1000000)
      expect(t.mastery).assertEqual(2)
      expect(t.consecutiveCorrect).assertEqual(2)
      expect(t.justMastered).assertFalse()
      expect(t.nextReviewAt).assertEqual(1000000 + 2 * 24 * 60 * 60 * 1000)
    })

    it('computeMasteryTransition_correct_once_no_bump', 0, () => {
      const t = computeMasteryTransition(0, 0, true, 1000000)
      expect(t.mastery).assertEqual(0)
      expect(t.consecutiveCorrect).assertEqual(1)
    })

    it('computeMasteryTransition_wrong_drops_and_resets', 0, () => {
      const t = computeMasteryTransition(3, 2, false, 1000000)
      expect(t.mastery).assertEqual(2)
      expect(t.consecutiveCorrect).assertEqual(0)
      expect(t.nextReviewAt).assertEqual(1000000 + 2 * 24 * 60 * 60 * 1000)
    })

    it('computeMasteryTransition_wrong_at_zero_floors', 0, () => {
      const t = computeMasteryTransition(0, 0, false, 1000000)
      expect(t.mastery).assertEqual(0)
      expect(t.nextReviewAt).assertEqual(1000000) // INTERVAL[0] = 0 天
    })

    it('computeMasteryTransition_mastery5_stays_and_uses_recheck_interval', 0, () => {
      // 已是 5：不再升, justMastered=false, 间隔 = 30 天抽检
      const t = computeMasteryTransition(5, 4, true, 1000000)
      expect(t.mastery).assertEqual(5)
      expect(t.justMastered).assertFalse()
      expect(t.nextReviewAt).assertEqual(1000000 + MASTERED_RECHECK_MS)
    })

    it('computeMasteryTransition_just_mastered_sets_flag_and_recheck', 0, () => {
      // mastery=4, streak=1 → 再对 → 升到 5, justMastered=true, 30 天抽检
      const t = computeMasteryTransition(4, 1, true, 1000000)
      expect(t.mastery).assertEqual(5)
      expect(t.justMastered).assertTrue()
      expect(t.nextReviewAt).assertEqual(1000000 + MASTERED_RECHECK_MS)
    })

    it('empty_summary_has_all_empty_lists', 0, () => {
      const s: LedgerSummary = createEmptyLedgerSummary()
      expect(s.newPool.length).assertEqual(0)
      expect(s.dueReview.length).assertEqual(0)
      expect(s.mastered.length).assertEqual(0)
      expect(s.cooling.length).assertEqual(0)
      expect(s.topRepeated.length).assertEqual(0)
    })

    it('learning_item_defaults', 0, () => {
      const item: LearningItem = new LearningItem()
      expect(item.itemKey).assertEqual('')
      expect(item.mastery).assertEqual(0)
      expect(item.exposureCount).assertEqual(0)
      expect(item.source).assertEqual('session')
    })
  })
}
```

- [ ] **Step 3: 注册 suite** —— `entry/src/ohosTest/ets/test/List.test.ets` 照现有 `KidsSubjectUtils.test` 的注册样式，加 import `learningLedgerModelsTest`（from `'./utils/LearningLedgerModels.test'`）与 `it` 数组/`testsuites` 条目（打开文件后仿照既有两行的写法补齐）。

- [ ] **Step 4: 跑 ohosTest 编译确认失败**（模块不存在 → 编译报错即"红"）。用 Global Constraints 的 ohosTest 编译命令；预期 FAIL（找不到 `models/LearningLedgerModels`）。

- [ ] **Step 5: 写实现** `entry/src/main/ets/models/LearningLedgerModels.ets`

```ets
/**
 * LearningLedgerModels - 词汇台账数据模型 + Leitner 掌握度状态机 + 常量
 *
 * 设计: docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md
 * 全部为纯数据/纯函数, 不依赖 ArkUI 与数据库, 可被 hypium 直接单测。
 * 所有调参常量集中于此, 避免散落漂移。
 */

/** Leitner 复习间隔 (天), 下标 = mastery 0..5 */
export const LEDGER_INTERVAL_DAYS: number[] = [0, 1, 2, 4, 7, 15]

export const LEDGER_DAY_MS: number = 24 * 60 * 60 * 1000
/** 同词同题型冷却 30 分钟 */
export const SAME_MODE_COOLDOWN_MS: number = 30 * 60 * 1000
/** 同一会话内同词至少间隔 5 题 */
export const SESSION_GAP_ITEMS: number = 5
/** 已掌握词抽检周期 30 天 */
export const MASTERED_RECHECK_MS: number = 30 * LEDGER_DAY_MS
/** 近 7 天高频统计窗口 */
export const TOP_REPEATED_WINDOW_MS: number = 7 * LEDGER_DAY_MS
/** buildSummary 缓存 TTL 60s (门禁只读缓存, 避免每题查库) */
export const SUMMARY_CACHE_TTL_MS: number = 60 * 1000
/** 每 session 近期出题环形缓冲容量 */
export const RECENT_WINDOW_CAPACITY: number = 20
/** learning_item_events 保留 90 天 */
export const EVENT_RETENTION_MS: number = 90 * LEDGER_DAY_MS
/** 内存 session 环形缓冲最多保留的 session 数 */
export const RECENT_SESSION_PRUNE_MAX: number = 24

/** 重复检查原因码 */
export const REPEAT_REASON_SESSION_GAP: string = 'session_gap'
export const REPEAT_REASON_SAME_MODE_COOLDOWN: string = 'same_mode_cooldown'
export const REPEAT_REASON_MASTERED_RECHECK: string = 'mastered_recheck'

/** learning_items 一行的内存模型 */
export class LearningItem {
  itemKey: string = ''
  subject: string = ''
  itemType: string = ''
  display: string = ''
  skillKey: string = ''
  firstTaughtAt: number = 0
  lastSeenAt: number = 0
  exposureCount: number = 0
  correctCount: number = 0
  wrongCount: number = 0
  mastery: number = 0
  consecutiveCorrect: number = 0
  modesSeen: string[] = []
  lastMode: string = ''
  lastSessionId: string = ''
  nextReviewAt: number = 0
  masteredAt: number = 0
  source: string = 'session'
  createdAt: number = 0
  updatedAt: number = 0
}

/** 待复习提示 */
export class DueReviewHint {
  display: string = ''
  lastMode: string = ''
  dueInMs: number = 0
}

/** 近 7 天高频统计 */
export class RepeatStat {
  display: string = ''
  count: number = 0
}

/** 注入 prompt / 供门禁的台账摘要 */
export class LedgerSummary {
  newPool: string[] = []
  dueReview: DueReviewHint[] = []
  mastered: string[] = []
  cooling: string[] = []
  topRepeated: RepeatStat[] = []
}

export function createEmptyLedgerSummary(): LedgerSummary {
  return new LedgerSummary()
}

/** recordServed 输入 */
export interface LedgerRecord {
  itemKey: string
  subject: string
  itemType: string
  display: string
  skillKey: string
  mode: string
  toolId: string
  sessionId: string
  now: number
}

/** 备课计划种子 (只建行, 不改掌握度) */
export interface LedgerItemSeed {
  subject: string
  itemType: string
  display: string
  skillKey: string
}

/** 出题侧从工具参数提取的目标项 (不含 itemKey, 由服务经 normalizeItemKey 计算) */
export interface LedgerToolItem {
  subject: string
  itemType: string
  display: string
  mode: string
  skillKey: string
}

/** 作答侧对账项 */
export interface LedgerAnswerItem {
  itemKey: string
  isCorrect: boolean
}

/** learning_item_events 插入 */
export interface LedgerEventInsert {
  id: string
  itemKey: string
  sessionId: string
  mode: string
  toolId: string
  servedAt: number
  display: string
}

/** 掌握度迁移结果 */
export interface MasteryTransition {
  mastery: number
  consecutiveCorrect: number
  nextReviewAt: number
  justMastered: boolean
}

/** 重复检查结论 (reason 为 REPEAT_REASON_* 之一, allowed=true 时为空串) */
export interface RepeatCheck {
  allowed: boolean
  reason: string
  itemKey: string
  display: string
}

/** evaluateRepeatPolicy 输入 (服务层收集 DB 行 + 会话环, 纯函数判定) */
export interface RepeatPolicyInput {
  purpose: string
  mode: string
  now: number
  found: boolean
  lastSeenAt: number
  lastMode: string
  mastery: number
  nextReviewAt: number
  inSessionGap: boolean
  itemKey: string
  display: string
}

/** mastery 对应的下次复习间隔 (毫秒)。mastery=5 走 30 天抽检, 其余走 INTERVAL_DAYS。 */
function nextIntervalMs(mastery: number): number {
  if (mastery >= 5) {
    return MASTERED_RECHECK_MS
  }
  const idx = Math.max(0, Math.min(5, mastery))
  return LEDGER_INTERVAL_DAYS[idx] * LEDGER_DAY_MS
}

/**
 * Leitner 掌握度状态机 (spec §5.3):
 * - 答对: streak+1; streak>=2 且 mastery<5 → mastery+1; nextReviewAt 按 INTERVAL 前移
 * - 答错: streak=0, mastery=max(0, mastery-1), nextReviewAt 提前
 * - mastery=5 已封顶时不再升, justMastered=false, 间隔走 30 天抽检
 */
export function computeMasteryTransition(mastery: number, consecutiveCorrect: number,
  isCorrect: boolean, now: number): MasteryTransition {
  const result: MasteryTransition = {
    mastery: mastery,
    consecutiveCorrect: consecutiveCorrect,
    nextReviewAt: now,
    justMastered: false
  }
  if (isCorrect) {
    const newStreak = consecutiveCorrect + 1
    const newMastery = (newStreak >= 2 && mastery < 5) ? mastery + 1 : mastery
    result.mastery = newMastery
    result.consecutiveCorrect = newStreak
    result.justMastered = newMastery === 5 && mastery < 5
    result.nextReviewAt = now + nextIntervalMs(newMastery)
  } else {
    result.mastery = Math.max(0, mastery - 1)
    result.consecutiveCorrect = 0
    result.nextReviewAt = now + nextIntervalMs(result.mastery)
  }
  return result
}
```

- [ ] **Step 6: 跑主模块构建 + ohosTest 编译**（两条命令均须 exit 0；ohosTest 编译通过即测试"绿"——hypium 运行时验证留给用户在 IDE 跑，Global Constraints 已说明）。

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(ledger): LearningLedgerModels 数据模型 + Leitner 状态机纯函数"
```

---

### Task 2: 提取/归一化/重复策略纯函数（utils/LedgerExtractUtils.ets + utils/VocabRepeatValidation.ets）

**Files:**
- Create: `entry/src/main/ets/utils/LedgerExtractUtils.ets`
- Create: `entry/src/main/ets/utils/VocabRepeatValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/LedgerExtractUtils.test.ets`
- Test: `entry/src/ohosTest/ets/test/utils/VocabRepeatValidation.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册两个新 suite）

**Interfaces:**
- Consumes: Task 1 的 `LedgerToolItem` / `LedgerAnswerItem` / `LedgerItemSeed` / `RepeatCheck` / `RepeatPolicyInput` / 常量；`models/LessonPlanModels.ets` 的 `LessonPlan`（`plan.vocab[].word`、`plan.writing[].characterOrWord`）。
- Produces:
  - `normalizeItemKey(subject: string, itemType: string, display: string): string`
  - `normalizePinyinSyllable(syllable: string): string`
  - `isCJKText(value: string): boolean`
  - `extractLedgerItemsFromTool(toolId: string, argsJson: string): LedgerToolItem[]`
  - `extractLedgerAnswerItems(toolId: string, argsJson: string, answerJson: string): LedgerAnswerItem[]`
  - `extractLedgerSeeds(plan: LessonPlan): LedgerItemSeed[]`
  - `parsePurpose(argsJson: string): string`（返回 `'new' | 'review'`）
  - `evaluateRepeatPolicy(input: RepeatPolicyInput): RepeatCheck`
  - `buildRepeatBlockedMessage(reason: string, display: string): string`
  - `VocabRepeatGateResult` 接口 `{blocked, error, message}`

- [ ] **Step 1: 写失败测试** `entry/src/ohosTest/ets/test/utils/LedgerExtractUtils.test.ets`

```ets
import { describe, it, expect } from '@ohos/hypium'
import {
  normalizeItemKey,
  normalizePinyinSyllable,
  isCJKText,
  extractLedgerItemsFromTool,
  extractLedgerAnswerItems,
  extractLedgerSeeds
} from '../../../../main/ets/utils/LedgerExtractUtils'
import { LessonPlan } from '../../../../main/ets/models/LessonPlanModels'

export default function ledgerExtractUtilsTest(): void {
  describe('ledgerExtractUtilsTest', () => {
    it('normalizeItemKey_en_vocab', 0, () => {
      expect(normalizeItemKey('en', 'vocab', '  Apple! ')).assertEqual('en:vocab:apple')
      expect(normalizeItemKey('en', 'vocab', "I'm OK")).assertEqual("en:vocab:i'm ok")
    })

    it('normalizeItemKey_en_sentence', 0, () => {
      expect(normalizeItemKey('en', 'sentence', 'I like apples.')).assertEqual('en:sentence:i|like|apples')
    })

    it('normalizeItemKey_zh_char_phrase', 0, () => {
      expect(normalizeItemKey('zh', 'char', '山')).assertEqual('zh:char:山')
      expect(normalizeItemKey('zh', 'phrase', '火车')).assertEqual('zh:phrase:火车')
    })

    it('normalizeItemKey_zh_pinyin_tone_digits', 0, () => {
      expect(normalizeItemKey('zh', 'pinyin', 'shān')).assertEqual('zh:pinyin:shan1')
      expect(normalizePinyinSyllable('Lǜ')).assertEqual('lv4')
      expect(normalizePinyinSyllable('nǚ')).assertEqual('nv3')
      expect(normalizePinyinSyllable('bá')).assertEqual('ba2')
    })

    it('normalizeItemKey_zh_sentence_strips_punct', 0, () => {
      expect(normalizeItemKey('zh', 'sentence', '我爱妈妈。')).assertEqual('zh:sentence:我爱妈妈')
    })

    it('isCJKText_classifies', 0, () => {
      expect(isCJKText('山')).assertTrue()
      expect(isCJKText('火车')).assertTrue()
      expect(isCJKText('apple')).assertFalse()
      expect(isCJKText('')).assertFalse()
    })

    it('extract_english_quiz_correct_answer', 0, () => {
      const args = '{"mode":"listen_choice","correct_answer":"apple","tts_text":"apple"}'
      const items = extractLedgerItemsFromTool('english_quiz', args)
      expect(items.length).assertEqual(1)
      expect(items[0].subject).assertEqual('en')
      expect(items[0].display).assertEqual('apple')
      expect(items[0].mode).assertEqual('english_quiz.listen_choice')
      expect(items[0].skillKey).assertEqual('english_vocab')
    })

    it('extract_english_quiz_read_aloud_is_sentence', 0, () => {
      const args = '{"mode":"read_aloud","correct_answer":"I like apples","target_text":"I like apples"}'
      const items = extractLedgerItemsFromTool('english_quiz', args)
      expect(items.length).assertEqual(1)
      expect(items[0].itemType).assertEqual('sentence')
      expect(items[0].skillKey).assertEqual('english_sentence')
    })

    it('extract_english_quiz_legacy_question_type', 0, () => {
      const args = '{"question_type":"word_choice","correct_answer":"cat"}'
      const items = extractLedgerItemsFromTool('english_quiz', args)
      expect(items.length).assertEqual(1)
      expect(items[0].mode).assertEqual('english_quiz.word_choice')
    })

    it('extract_picture_vocab_en_and_zh', 0, () => {
      const en = extractLedgerItemsFromTool('picture_vocab', '{"mode":"en","correct_answer":"dog"}')
      expect(en.length).assertEqual(1)
      expect(en[0].subject).assertEqual('en')
      const zh = extractLedgerItemsFromTool('picture_vocab', '{"mode":"zh","correct_answer":"火车"}')
      expect(zh.length).assertEqual(1)
      expect(zh[0].itemType).assertEqual('phrase')
      const zhChar = extractLedgerItemsFromTool('picture_vocab', '{"mode":"zh","correct_answer":"山"}')
      expect(zhChar[0].itemType).assertEqual('char')
    })

    it('extract_listening_quiz_word', 0, () => {
      const items = extractLedgerItemsFromTool('listening_quiz', '{"word":"bag","correct_answer":"bag"}')
      expect(items.length).assertEqual(1)
      expect(items[0].display).assertEqual('bag')
      expect(items[0].skillKey).assertEqual('english_vocab')
    })

    it('extract_pinyin_quiz_uses_correct_answer_as_display', 0, () => {
      const items = extractLedgerItemsFromTool('pinyin_quiz', '{"character":"山","correct_answer":"shān"}')
      expect(items.length).assertEqual(1)
      expect(items[0].itemType).assertEqual('pinyin')
      expect(items[0].display).assertEqual('shān')
      expect(items[0].skillKey).assertEqual('pinyin')
    })

    it('extract_explain_cards_record_served', 0, () => {
      const hanzi = extractLedgerItemsFromTool('hanzi_card', '{"character":"山"}')
      expect(hanzi.length).assertEqual(1)
      expect(hanzi[0].itemType).assertEqual('char')
      expect(hanzi[0].mode).assertEqual('hanzi_card')
      const pinyin = extractLedgerItemsFromTool('pinyin_card', '{"syllable":"bà"}')
      expect(pinyin.length).assertEqual(1)
      expect(pinyin[0].itemType).assertEqual('pinyin')
      const talk = extractLedgerItemsFromTool('picture_talk', '{"scene":"公园里孩子们在放风筝"}')
      expect(talk.length).assertEqual(1)
      expect(talk[0].itemType).assertEqual('sentence')
      expect(talk[0].skillKey).assertEqual('chinese_reading')
    })

    it('extract_chinese_quiz_per_mode', 0, () => {
      const wb = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"word_build","character":"山","answer":"火山"}')
      expect(wb.length).assertEqual(2) // zh:char + zh:phrase
      const so = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"sentence_order","words":["我","爱","妈妈"],"answer":"我爱妈妈"}')
      expect(so.length).assertEqual(1)
      expect(so[0].itemType).assertEqual('sentence')
      const la = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"lookalike","stem":"___ has apples","answer":"山","options":["山","出"]}')
      expect(la[0].itemType).assertEqual('char')
      const ant = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"antonym","character":"大","answer":"小"}')
      expect(ant.length).assertEqual(1)
      expect(ant[0].display).assertEqual('大')
    })

    it('extract_matching_pairs_left_items', 0, () => {
      const items = extractLedgerItemsFromTool('matching_pairs',
        '{"difficulty":1,"pairs":[{"left":"apple","right":"苹果"},{"left":"山","right":"mountain"}]}')
      expect(items.length).assertEqual(2)
      expect(items[0].subject).assertEqual('en')
      expect(items[1].itemType).assertEqual('char')
    })

    it('extract_handwriting_skips_numbers', 0, () => {
      const num = extractLedgerItemsFromTool('handwriting_practice', '{"character":"3","type":"number"}')
      expect(num.length).assertEqual(0)
      const zh = extractLedgerItemsFromTool('handwriting_practice', '{"character":"山","type":"chinese"}')
      expect(zh.length).assertEqual(1)
      expect(zh[0].itemType).assertEqual('char')
      const letter = extractLedgerItemsFromTool('handwriting_practice', '{"character":"A","type":"letter"}')
      expect(letter[0].subject).assertEqual('en')
    })

    it('extract_non_ledger_tools_return_empty', 0, () => {
      expect(extractLedgerItemsFromTool('math_quiz', '{"correct_answer":"8"}').length).assertEqual(0)
      expect(extractLedgerItemsFromTool('number_puzzle', '{"difficulty":3}').length).assertEqual(0)
      expect(extractLedgerItemsFromTool('english_quiz', 'not-json').length).assertEqual(0)
      expect(extractLedgerItemsFromTool('english_quiz', '{"mode":"listen_choice"}').length).assertEqual(0) // 无 correct_answer
    })

    it('answerItems_quiz_semantics', 0, () => {
      const args = '{"mode":"listen_choice","correct_answer":"apple"}'
      const right = extractLedgerAnswerItems('english_quiz', args, '{"correct":true}')
      expect(right.length).assertEqual(1)
      expect(right[0].itemKey).assertEqual('en:vocab:apple')
      expect(right[0].isCorrect).assertTrue()
      const wrong = extractLedgerAnswerItems('english_quiz', args, '{"correct":false}')
      expect(wrong[0].isCorrect).assertFalse()
    })

    it('answerItems_explain_cards_never_advance_mastery', 0, () => {
      // 讲解型: 无论 completed 与否, 不产生对账项 (Review Focus #3)
      expect(extractLedgerAnswerItems('hanzi_card', '{"character":"山"}', '{"completed":true}').length).assertEqual(0)
      expect(extractLedgerAnswerItems('pinyin_card', '{"syllable":"bà"}', '{"completed":true}').length).assertEqual(0)
      expect(extractLedgerAnswerItems('picture_talk', '{"scene":"公园"}', '{"completed":true}').length).assertEqual(0)
    })

    it('answerItems_completed_gated_tools', 0, () => {
      // 放弃 (completed=false) → 跳过, 不推进掌握度
      expect(extractLedgerAnswerItems('handwriting_practice', '{"character":"山","type":"chinese"}',
        '{"completed":false}').length).assertEqual(0)
      // 完成且全对 → 全部 left 项 isCorrect=true
      const done = extractLedgerAnswerItems('matching_pairs',
        '{"pairs":[{"left":"apple","right":"苹果"}]}', '{"completed":true,"mistakes":0}')
      expect(done.length).assertEqual(1)
      expect(done[0].isCorrect).assertTrue()
    })

    it('answerItems_malformed_answer_returns_empty', 0, () => {
      expect(extractLedgerAnswerItems('english_quiz', '{"correct_answer":"apple"}', 'not-json').length).assertEqual(0)
    })

    it('extractLedgerSeeds_vocab_and_writing', 0, () => {
      const plan: LessonPlan = new LessonPlan()
      // 手工塞两 vocab 两 writing (LessonPlan 模型字段为强类型数组)
      // 若 LessonPlan 构造后数组不可变, 直接按 models/LessonPlanModels.ets 的实际字段赋值方式写
      const seeds = extractLedgerSeeds(plan)
      expect(seeds.length).assertEqual(0) // 空 plan → 空 seeds
    })
  })
}
```

注意最后一条测试：`plan.vocab` / `plan.writing` 数组若为 let/const 数组属性则直接 `push`；打开 `models/LessonPlanModels.ets` 确认数组属性可变性后，把该用例改成 push 1 个 word='Apple' + 1 个 characterOrWord='山'，断言 seeds.length==2 且 key 分别为 `en:vocab:apple` / `zh:char:山`（用 `normalizeItemKey` 生成期望值断言 `seeds[0].display === 'Apple'`）。构造方式以该模型实际写法为准。

- [ ] **Step 2: 写失败测试** `entry/src/ohosTest/ets/test/utils/VocabRepeatValidation.test.ets`

```ets
import { describe, it, expect } from '@ohos/hypium'
import {
  parsePurpose,
  evaluateRepeatPolicy,
  buildRepeatBlockedMessage,
  VocabRepeatGateResult
} from '../../../../main/ets/utils/VocabRepeatValidation'
import { RepeatPolicyInput, SAME_MODE_COOLDOWN_MS, MASTERED_RECHECK_MS,
  REPEAT_REASON_SESSION_GAP, REPEAT_REASON_SAME_MODE_COOLDOWN, REPEAT_REASON_MASTERED_RECHECK
} from '../../../../main/ets/models/LearningLedgerModels'

function baseInput(): RepeatPolicyInput {
  const input: RepeatPolicyInput = {
    purpose: 'new',
    mode: 'english_quiz.listen_choice',
    now: 1000000,
    found: true,
    lastSeenAt: 1000000 - SAME_MODE_COOLDOWN_MS - 1000, // 默认已出冷却
    lastMode: 'english_quiz.listen_choice',
    mastery: 2,
    nextReviewAt: 1000000 + 60 * 60 * 1000,
    inSessionGap: false,
    itemKey: 'en:vocab:apple',
    display: 'apple'
  }
  return input
}

export default function vocabRepeatValidationTest(): void {
  describe('vocabRepeatValidationTest', () => {
    it('parsePurpose_defaults_to_new', 0, () => {
      expect(parsePurpose('{"mode":"listen_choice"}')).assertEqual('new')
      expect(parsePurpose('{"purpose":"review"}')).assertEqual('review')
      expect(parsePurpose('{"purpose":"NEW"}')).assertEqual('new')
      expect(parsePurpose('not-json')).assertEqual('new')
    })

    it('policy_new_item_allowed', 0, () => {
      const input = baseInput()
      input.found = false
      expect(evaluateRepeatPolicy(input).allowed).assertTrue()
    })

    it('policy_session_gap_blocks_any_purpose', 0, () => {
      // Review Focus #4: review 也不豁免 session_gap
      const inputNew = baseInput()
      inputNew.inSessionGap = true
      const checkNew = evaluateRepeatPolicy(inputNew)
      expect(checkNew.allowed).assertFalse()
      expect(checkNew.reason).assertEqual(REPEAT_REASON_SESSION_GAP)
      const inputReview = baseInput()
      inputReview.inSessionGap = true
      inputReview.purpose = 'review'
      const checkReview = evaluateRepeatPolicy(inputReview)
      expect(checkReview.allowed).assertFalse()
      expect(checkReview.reason).assertEqual(REPEAT_REASON_SESSION_GAP)
    })

    it('policy_review_bypasses_cooldown_and_recheck', 0, () => {
      const inCooldown = baseInput()
      inCooldown.lastSeenAt = 1000000 - 1000 // 1 秒前刚出, 同 mode → 冷却中
      inCooldown.purpose = 'review'
      expect(evaluateRepeatPolicy(inCooldown).allowed).assertTrue()
      const mastered = baseInput()
      mastered.mastery = 5
      mastered.nextReviewAt = 1000000 + MASTERED_RECHECK_MS
      mastered.purpose = 'review'
      expect(evaluateRepeatPolicy(mastered).allowed).assertTrue()
    })

    it('policy_new_blocked_by_same_mode_cooldown', 0, () => {
      const input = baseInput()
      input.lastSeenAt = 1000000 - 1000 // 冷却窗口内
      const check = evaluateRepeatPolicy(input)
      expect(check.allowed).assertFalse()
      expect(check.reason).assertEqual(REPEAT_REASON_SAME_MODE_COOLDOWN)
    })

    it('policy_new_allowed_when_mode_differs', 0, () => {
      // 同词不同题型 = 巩固, 放行
      const input = baseInput()
      input.lastSeenAt = 1000000 - 1000
      input.mode = 'english_quiz.spelling'
      expect(evaluateRepeatPolicy(input).allowed).assertTrue()
    })

    it('policy_new_blocked_by_mastered_recheck', 0, () => {
      const input = baseInput()
      input.mastery = 5
      input.nextReviewAt = 1000000 + MASTERED_RECHECK_MS
      // lastSeenAt 保持默认 (冷却窗口外), 只触发达标抽检
      const check = evaluateRepeatPolicy(input)
      expect(check.allowed).assertFalse()
      expect(check.reason).assertEqual(REPEAT_REASON_MASTERED_RECHECK)
    })

    it('blocked_message_contains_display_and_purpose_hint', 0, () => {
      const msg = buildRepeatBlockedMessage(REPEAT_REASON_SAME_MODE_COOLDOWN, 'apple')
      expect(msg.indexOf('apple') >= 0).assertTrue()
      expect(msg.indexOf('review') >= 0).assertTrue()
      const gap = buildRepeatBlockedMessage(REPEAT_REASON_SESSION_GAP, 'apple')
      expect(gap.indexOf('对话') >= 0).assertTrue()
      const gate: VocabRepeatGateResult = { blocked: true, error: 'repeat_blocked', message: msg }
      expect(gate.error).assertEqual('repeat_blocked')
    })
  })
}
```

- [ ] **Step 3: 注册两个 suite 到 List.test.ets**（同 Task 1 Step 3 样式）。

- [ ] **Step 4: ohosTest 编译确认红**（两个 utils 模块不存在）。

- [ ] **Step 5: 写 `entry/src/main/ets/utils/VocabRepeatValidation.ets`**

```ets
/**
 * VocabRepeatValidation - 出题重复度硬门禁的纯策略层
 *
 * 设计: docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md §7/§9
 * - evaluateRepeatPolicy: 纯函数真值表——session_gap 任何 purpose 都拦截;
 *   purpose="review" 豁免 same_mode_cooldown 与 mastered_recheck; 新词不受限。
 * - parsePurpose: LLM 未传 purpose 视为 "new" (spec §10 降级表)。
 * - buildRepeatBlockedMessage: 生成给 LLM 的 should_retry 修正提示。
 *
 * 服务层 (LearningLedgerService.checkRepeat) 负责收集 RepeatPolicyInput,
 * handler 侧 (ToolExecutionService.runVocabRepeatGate) 只消费结果。
 */
import {
  RepeatCheck,
  RepeatPolicyInput,
  SAME_MODE_COOLDOWN_MS,
  REPEAT_REASON_SESSION_GAP,
  REPEAT_REASON_SAME_MODE_COOLDOWN,
  REPEAT_REASON_MASTERED_RECHECK
} from '../models/LearningLedgerModels'

export interface VocabRepeatGateResult {
  blocked: boolean
  error: string
  message: string
}

export function parsePurpose(argsJson: string): string {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>
    const purpose = (parsed['purpose'] as string) ?? ''
    return purpose === 'review' ? 'review' : 'new'
  } catch (_e) {
    return 'new'
  }
}

export function evaluateRepeatPolicy(input: RepeatPolicyInput): RepeatCheck {
  const result: RepeatCheck = {
    allowed: true,
    reason: '',
    itemKey: input.itemKey,
    display: input.display
  }
  if (!input.found) {
    return result
  }
  // 1. 会话间隔: 任何 purpose 都生效 (复习也不能在 5 题内刷屏)
  if (input.inSessionGap) {
    result.allowed = false
    result.reason = REPEAT_REASON_SESSION_GAP
    return result
  }
  // 2. 复习豁免: 同题型冷却 + 已掌握抽检
  if (input.purpose === 'review') {
    return result
  }
  // 3. 已掌握 30 天抽检期内, 勿当新词
  if (input.mastery >= 5 && input.nextReviewAt > input.now) {
    result.allowed = false
    result.reason = REPEAT_REASON_MASTERED_RECHECK
    return result
  }
  // 4. 同词同题型 30 分钟冷却
  if (input.lastMode !== '' && input.lastMode === input.mode
    && input.lastSeenAt > input.now - SAME_MODE_COOLDOWN_MS) {
    result.allowed = false
    result.reason = REPEAT_REASON_SAME_MODE_COOLDOWN
  }
  return result
}

export function buildRepeatBlockedMessage(reason: string, display: string): string {
  if (reason === REPEAT_REASON_SESSION_GAP) {
    return `「${display}」刚在本次对话出现过, 请隔几题或换一个词再出`
  }
  if (reason === REPEAT_REASON_MASTERED_RECHECK) {
    return `「${display}」已经掌握, 抽检期内请勿作为新词出题; 若确实要复习请传 purpose:"review"`
  }
  return `「${display}」近期已用相同题型出现过, 请换词或换题型; 若确实要复习请传 purpose:"review"`
}
```

- [ ] **Step 6: 写 `entry/src/main/ets/utils/LedgerExtractUtils.ets`**

```ets
/**
 * LedgerExtractUtils - 台账写入侧的目标项提取与归一化 (纯函数)
 *
 * 设计: docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md §3/§6.2 (v1.1 已核对校验器字段名)
 * - normalizeItemKey 是全项目唯一的 key 归一化实现, 写入侧与门禁侧共用
 * - extractLedgerItemsFromTool: 从工具 arguments 提取目标学习项 (v1.1 校正的字段名见各分支注释)
 * - extractLedgerAnswerItems: 作答对账——quiz 型看顶层 correct; completed 型 (handwriting/matching_pairs)
 *   completed=false 跳过; 讲解型 (hanzi_card/pinyin_card/picture_talk) 恒返回 []
 * - mode 命名: compositeMode = toolId (无内部 mode) 或 `${toolId}.${modeValue}`,
 *   保证跨工具不同题型不互相误伤冷却
 */
import { LedgerAnswerItem, LedgerItemSeed, LedgerToolItem } from '../models/LearningLedgerModels'
import { LessonPlan } from '../models/LessonPlanModels'

/** 声调映射: 带调字母 → 基字母+调号 (spec §3.1, ü→v) */
const TONE_MAP: Record<string, string> = {
  'ā': 'a1', 'á': 'a2', 'ǎ': 'a3', 'à': 'a4',
  'ē': 'e1', 'é': 'e2', 'ě': 'e3', 'è': 'e4',
  'ī': 'i1', 'í': 'i2', 'ǐ': 'i3', 'ì': 'i4',
  'ō': 'o1', 'ó': 'o2', 'ǒ': 'o3', 'ò': 'o4',
  'ū': 'u1', 'ú': 'u2', 'ǔ': 'u3', 'ù': 'u4',
  'ǖ': 'v1', 'ǘ': 'v2', 'ǚ': 'v3', 'ǜ': 'v4',
  'ü': 'v'
}

export function normalizePinyinSyllable(syllable: string): string {
  const lowered = syllable.trim().toLowerCase()
  let out = ''
  for (let i = 0; i < lowered.length; i++) {
    const ch = lowered.charAt(i)
    const mapped = TONE_MAP[ch]
    out += mapped !== undefined ? mapped : ch
  }
  return out.replace(/\s+/g, '')
}

function stripEnPunctuation(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\s']/g, ' ').replace(/\s+/g, ' ').trim()
}

/** 全部字符都是 CJK 基本区汉字 (至少 1 个字符) */
export function isCJKText(value: string): boolean {
  const trimmed = value.trim()
  if (trimmed.length === 0) {
    return false
  }
  let allCjk = true
  for (let i = 0; i < trimmed.length; i++) {
    const code = trimmed.charCodeAt(i)
    if (!(code >= 0x4E00 && code <= 0x9FFF)) {
      allCjk = false
    }
  }
  return allCjk
}

/**
 * 唯一的 item_key 归一化实现 (spec §3.1)。
 * en:vocab 小写去标点; en:sentence 分词竖线连接; zh:char/phrase 原样;
 * zh:pinyin 声调数字化; zh:sentence 去标点空白。
 */
export function normalizeItemKey(subject: string, itemType: string, display: string): string {
  const raw = display.trim()
  if (subject === 'en') {
    if (itemType === 'sentence') {
      const words = raw.toLowerCase().split(/[^a-z0-9']+/)
      const kept: string[] = []
      for (let i = 0; i < words.length; i++) {
        if (words[i] !== '') {
          kept.push(words[i])
        }
      }
      return `en:sentence:${kept.join('|')}`
    }
    return `en:vocab:${stripEnPunctuation(raw)}`
  }
  if (itemType === 'pinyin') {
    return `zh:pinyin:${normalizePinyinSyllable(raw)}`
  }
  if (itemType === 'sentence') {
    return `zh:sentence:${raw.replace(/[\s，。！？、,.!?;；:：「」『』()（）]/g, '')}`
  }
  if (itemType === 'phrase') {
    return `zh:phrase:${raw}`
  }
  return `zh:char:${raw}`
}

function toolItem(subject: string, itemType: string, display: string, mode: string,
  skillKey: string): LedgerToolItem {
  const item: LedgerToolItem = {
    subject: subject,
    itemType: itemType,
    display: display,
    mode: mode,
    skillKey: skillKey
  }
  return item
}

function emptyItems(): LedgerToolItem[] {
  const items: LedgerToolItem[] = []
  return items
}

function compositeMode(toolId: string, mode: string): string {
  return mode === '' ? toolId : `${toolId}.${mode}`
}

function argString(parsed: Record<string, Object>, key: string): string {
  const v = parsed[key]
  return typeof v === 'string' ? (v as string).trim() : ''
}

/** 分类混排项 (matching_pairs 左列 / handwriting character): CJK 单字→zh:char, CJK 多字→zh:phrase, 其余→en:vocab */
function classifyMixedItem(text: string, mode: string): LedgerToolItem {
  if (isCJKText(text)) {
    if (text.length === 1) {
      return toolItem('zh', 'char', text, mode, 'chinese_vocab')
    }
    return toolItem('zh', 'phrase', text, mode, 'chinese_vocab')
  }
  return toolItem('en', 'vocab', text, mode, 'english_vocab')
}

function singleOf(item: LedgerToolItem): LedgerToolItem[] {
  const items: LedgerToolItem[] = [item]
  return items
}

/**
 * 从工具 arguments 提取目标学习项。字段名严格对照 v1.1 校正:
 * - english_quiz: correct_answer (六 mode 统一; read_aloud 空时回退 target_text);
 *   mode 空/legacy 时回退 question_type; read_aloud → en:sentence
 * - picture_vocab: correct_answer; mode=en→en:vocab, mode=zh→zh:char|zh:phrase
 * - listening_quiz: word (被朗读项; 单个拉丁字母 skill=english_alphabet)
 * - pinyin_quiz: correct_answer (带调拼音) 为 display, item=zh:pinyin (被考字本身不单独建行)
 * - hanzi_card: character → zh:char (讲解计曝光); pinyin_card: syllable;
 *   picture_talk: scene → zh:sentence
 * - chinese_quiz: word_build→[character zh:char + answer zh:phrase]; sentence_order→answer zh:sentence;
 *   lookalike→answer zh:char; antonym→character zh:char
 * - matching_pairs: pairs[].left 逐项分类; handwriting_practice: character+type (number 跳过)
 */
export function extractLedgerItemsFromTool(toolId: string, argsJson: string): LedgerToolItem[] {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(argsJson) as Record<string, Object>
  } catch (_e) {
    return emptyItems()
  }
  if (toolId === 'english_quiz') {
    const mode = argString(parsed, 'mode')
    const legacyType = argString(parsed, 'question_type')
    const effectiveMode = mode !== '' ? mode : legacyType
    let target = argString(parsed, 'correct_answer')
    if (target === '' && effectiveMode === 'read_aloud') {
      target = argString(parsed, 'target_text')
    }
    if (target === '') {
      return emptyItems()
    }
    const isSentence = effectiveMode === 'read_aloud'
    return singleOf(toolItem('en', isSentence ? 'sentence' : 'vocab', target,
      compositeMode(toolId, effectiveMode), isSentence ? 'english_sentence' : 'english_vocab'))
  }
  if (toolId === 'picture_vocab') {
    const target = argString(parsed, 'correct_answer')
    if (target === '') {
      return emptyItems()
    }
    const mode = argString(parsed, 'mode')
    if (mode === 'zh') {
      return singleOf(toolItem('zh', target.length === 1 ? 'char' : 'phrase', target,
        compositeMode(toolId, mode), 'chinese_vocab'))
    }
    return singleOf(toolItem('en', 'vocab', target, compositeMode(toolId, mode), 'english_vocab'))
  }
  if (toolId === 'listening_quiz') {
    const word = argString(parsed, 'word')
    if (word === '') {
      return emptyItems()
    }
    const isSingleLetter = /^[a-z]$/i.test(word)
    return singleOf(toolItem('en', 'vocab', word, compositeMode(toolId, ''),
      isSingleLetter ? 'english_alphabet' : 'english_vocab'))
  }
  if (toolId === 'pinyin_quiz') {
    const answer = argString(parsed, 'correct_answer')
    if (answer === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'pinyin', answer, compositeMode(toolId, ''), 'pinyin'))
  }
  if (toolId === 'hanzi_card') {
    const character = argString(parsed, 'character')
    if (character === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'char', character, compositeMode(toolId, ''), 'chinese_vocab'))
  }
  if (toolId === 'pinyin_card') {
    const syllable = argString(parsed, 'syllable')
    if (syllable === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'pinyin', syllable, compositeMode(toolId, ''), 'pinyin'))
  }
  if (toolId === 'picture_talk') {
    const scene = argString(parsed, 'scene')
    if (scene === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'sentence', scene, compositeMode(toolId, ''), 'chinese_reading'))
  }
  if (toolId === 'chinese_quiz') {
    const mode = argString(parsed, 'mode')
    const modeTag = compositeMode(toolId, mode)
    const items: LedgerToolItem[] = []
    if (mode === 'word_build') {
      const character = argString(parsed, 'character')
      const answer = argString(parsed, 'answer')
      if (character !== '') {
        items.push(toolItem('zh', 'char', character, modeTag, 'chinese_vocab'))
      }
      if (answer !== '') {
        items.push(toolItem('zh', 'phrase', answer, modeTag, 'chinese_vocab'))
      }
    } else if (mode === 'sentence_order') {
      const answer = argString(parsed, 'answer')
      if (answer !== '') {
        items.push(toolItem('zh', 'sentence', answer, modeTag, 'chinese_reading'))
      }
    } else if (mode === 'lookalike') {
      const answer = argString(parsed, 'answer')
      if (answer !== '') {
        items.push(toolItem('zh', 'char', answer, modeTag, 'chinese_vocab'))
      }
    } else {
      const character = argString(parsed, 'character')
      if (character !== '') {
        items.push(toolItem('zh', 'char', character, modeTag, 'chinese_vocab'))
      }
    }
    return items
  }
  if (toolId === 'matching_pairs') {
    const pairsRaw = parsed['pairs']
    if (!Array.isArray(pairsRaw)) {
      return emptyItems()
    }
    const arr = pairsRaw as Object[]
    const items: LedgerToolItem[] = []
    for (let i = 0; i < arr.length; i++) {
      const pair = arr[i] as Record<string, Object>
      const left = argString(pair, 'left')
      if (left !== '') {
        items.push(classifyMixedItem(left, compositeMode(toolId, '')))
      }
    }
    return items
  }
  if (toolId === 'handwriting_practice') {
    const character = argString(parsed, 'character')
    if (character === '' || argString(parsed, 'type') === 'number') {
      return emptyItems()
    }
    return singleOf(classifyMixedItem(character, compositeMode(toolId, '')))
  }
  return emptyItems()
}

/**
 * 作答对账。语义:
 * - english_quiz/picture_vocab/listening_quiz/pinyin_quiz/chinese_quiz: 全部 served 项 isCorrect = (payload.correct === true)
 * - handwriting_practice / matching_pairs: completed !== true → [] (放弃/中途关闭不推进掌握度);
 *   completed === true → 全部项 isCorrect=true
 * - hanzi_card/pinyin_card/picture_talk: 恒 [] (讲解型, 曝光已在 recordServed 记, 掌握度不因讲解推进)
 * - answerJson 非法 JSON → []
 */
export function extractLedgerAnswerItems(toolId: string, argsJson: string,
  answerJson: string): LedgerAnswerItem[] {
  const served = extractLedgerItemsFromTool(toolId, argsJson)
  const answers: LedgerAnswerItem[] = []
  if (served.length === 0) {
    return answers
  }
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(answerJson) as Record<string, Object>
  } catch (_e) {
    return answers
  }
  if (toolId === 'hanzi_card' || toolId === 'pinyin_card' || toolId === 'picture_talk') {
    return answers
  }
  let isCorrect = false
  if (toolId === 'handwriting_practice' || toolId === 'matching_pairs') {
    if (parsed['completed'] !== true) {
      return answers
    }
    isCorrect = true
  } else {
    isCorrect = parsed['correct'] === true
  }
  for (let i = 0; i < served.length; i++) {
    const servedItem = served[i]
    const answer: LedgerAnswerItem = {
      itemKey: normalizeItemKey(servedItem.subject, servedItem.itemType, servedItem.display),
      isCorrect: isCorrect
    }
    answers.push(answer)
  }
  return answers
}

/**
 * 备课计划 → 台账种子 (spec §6.1): plan.vocab[].word → en:vocab;
 * plan.writing[].characterOrWord 按 CJK 判定 zh:char|zh:phrase|en:vocab。按 key 去重。只建行不改掌握度。
 */
export function extractLedgerSeeds(plan: LessonPlan): LedgerItemSeed[] {
  const seeds: LedgerItemSeed[] = []
  const seen: string[] = []
  const vocabItems = plan.vocab
  for (let i = 0; i < vocabItems.length; i++) {
    const word = vocabItems[i].word.trim()
    if (word !== '') {
      pushSeed(seeds, seen, 'en', 'vocab', word, 'english_vocab')
    }
  }
  const writingItems = plan.writing
  for (let i = 0; i < writingItems.length; i++) {
    const text = writingItems[i].characterOrWord.trim()
    if (text === '') {
      continue
    }
    if (isCJKText(text)) {
      if (text.length === 1) {
        pushSeed(seeds, seen, 'zh', 'char', text, 'chinese_vocab')
      } else {
        pushSeed(seeds, seen, 'zh', 'phrase', text, 'chinese_vocab')
      }
    } else {
      pushSeed(seeds, seen, 'en', 'vocab', text, 'english_vocab')
    }
  }
  return seeds
}

function pushSeed(seeds: LedgerItemSeed[], seen: string[], subject: string, itemType: string,
  display: string, skillKey: string): void {
  const key = normalizeItemKey(subject, itemType, display)
  if (key === '' || seen.indexOf(key) >= 0) {
    return
  }
  seen.push(key)
  const seed: LedgerItemSeed = {
    subject: subject,
    itemType: itemType,
    display: display,
    skillKey: skillKey
  }
  seeds.push(seed)
}
```

- [ ] **Step 7: 跑主模块构建 + ohosTest 编译**（均须 exit 0）。

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(ledger): 目标项提取/归一化/重复策略纯函数 + hypium 测试"
```

---

### Task 3: 数据库层（DatabaseService 建表 + CRUD）

**Files:**
- Modify: `entry/src/main/ets/services/DatabaseService.ets`

**Interfaces:**
- Consumes: Task 1 的 `LearningItem` / `LedgerEventInsert` / `RepeatStat`。
- Produces（Task 4 依赖，签名逐字使用）:
  - `findLearningItemByKey(itemKey: string): Promise<LearningItem | null>`
  - `insertLearningItem(item: LearningItem): Promise<boolean>`
  - `upsertLearningItem(item: LearningItem): Promise<boolean>`（update-first，0 行受影响再 insert）
  - `queryLedgerNewPool(subject: string, limit: number): Promise<LearningItem[]>`（mastery ≤ 1，按 last_seen_at 倒序）
  - `queryLedgerDueReview(subject: string, now: number, limit: number): Promise<LearningItem[]>`（mastery 2-4 且 next_review_at ≤ now，按 next_review_at 升序）
  - `queryLedgerMastered(subject: string, limit: number): Promise<LearningItem[]>`（mastery = 5）
  - `queryLedgerCooling(subject: string, sinceMs: number, limit: number): Promise<LearningItem[]>`（last_seen_at ≥ sinceMs，倒序）
  - `insertLearningItemEvent(event: LedgerEventInsert): Promise<boolean>`
  - `updateLatestOpenLedgerEvent(itemKey: string, answeredAt: number, isCorrect: boolean): Promise<void>`
  - `getTopRepeatedEvents(subjectPrefix: string, sinceMs: number, limit: number): Promise<RepeatStat[]>`（querySql GROUP BY display）
  - `deleteLedgerEventsBefore(cutoffMs: number): Promise<number>`
  - `countLedgerMastered(subject: string): Promise<number>`
- TableNames 新增：`LEARNING_ITEMS = 'learning_items'`、`LEARNING_ITEM_EVENTS = 'learning_item_events'`

- [ ] **Step 1: TableNames 增量** —— `DatabaseService.ets:104` 的 `class TableNames` 内追加两个常量（照既有条目样式）：

```ts
  static readonly LEARNING_ITEMS: string = 'learning_items'
  static readonly LEARNING_ITEM_EVENTS: string = 'learning_item_events'
```

- [ ] **Step 2: 建表** —— 找到 `createTables` 中执行 CREATE TABLE 字符串序列的位置（grep `CREATE TABLE IF NOT EXISTS`，在最后一个建表执行之后、索引执行序列处），**learning_items 必须先于 learning_item_events**。DDL（注意：events 表比 spec §4.1 多一列 `display`——记录级冗余展示文本，让"近 7 天高频词"聚合不需要 JOIN 主表；FK 降级为逻辑关联，与 spec §4.3 的降级路径一致，SQLite 端不启用外键）：

```ts
    const createLearningItemsSql = `CREATE TABLE IF NOT EXISTS learning_items (
      item_key            TEXT PRIMARY KEY,
      subject             TEXT NOT NULL,
      item_type           TEXT NOT NULL,
      display             TEXT NOT NULL,
      skill_key           TEXT DEFAULT '',
      first_taught_at     INTEGER NOT NULL,
      last_seen_at        INTEGER NOT NULL,
      exposure_count      INTEGER NOT NULL DEFAULT 0,
      correct_count       INTEGER NOT NULL DEFAULT 0,
      wrong_count         INTEGER NOT NULL DEFAULT 0,
      mastery             INTEGER NOT NULL DEFAULT 0,
      consecutive_correct  INTEGER NOT NULL DEFAULT 0,
      modes_seen_json     TEXT DEFAULT '[]',
      last_mode           TEXT DEFAULT '',
      last_session_id     TEXT DEFAULT '',
      next_review_at      INTEGER NOT NULL DEFAULT 0,
      mastered_at         INTEGER NOT NULL DEFAULT 0,
      source              TEXT DEFAULT 'session',
      created_at          INTEGER NOT NULL,
      updated_at          INTEGER NOT NULL
    )`
    const createLearningItemEventsSql = `CREATE TABLE IF NOT EXISTS learning_item_events (
      id           TEXT PRIMARY KEY,
      item_key     TEXT NOT NULL,
      session_id   TEXT DEFAULT '',
      mode         TEXT DEFAULT '',
      tool_id      TEXT DEFAULT '',
      served_at    INTEGER NOT NULL,
      answered_at  INTEGER DEFAULT 0,
      is_correct   INTEGER DEFAULT -1,
      display      TEXT DEFAULT ''
    )`
```

索引（7 条，接在建表执行之后，与既有索引执行序列同款式）：

```ts
    CREATE INDEX IF NOT EXISTS idx_li_subject   ON learning_items(subject)
    CREATE INDEX IF NOT EXISTS idx_li_next_rev  ON learning_items(next_review_at)
    CREATE INDEX IF NOT EXISTS idx_li_mastery   ON learning_items(mastery)
    CREATE INDEX IF NOT EXISTS idx_li_last_seen ON learning_items(last_seen_at DESC)
    CREATE INDEX IF NOT EXISTS idx_lie_item     ON learning_item_events(item_key, served_at DESC)
    CREATE INDEX IF NOT EXISTS idx_lie_served   ON learning_item_events(served_at DESC)
    CREATE INDEX IF NOT EXISTS idx_lie_session  ON learning_item_events(session_id)
```

（写成 `const createXxxIdxSql = \`CREATE INDEX ...\`` 常量 + `await this.rdbStore.executeSql(...)`，与邻近建表/建索引代码同构。）

- [ ] **Step 3: CRUD 方法** —— 加到 DatabaseService 类内（放在既有教学数据 CRUD 区域附近，如 `getStarTotalsByDay` 之后），顶部补 `import { LearningItem, LedgerEventInsert, RepeatStat } from '../models/LearningLedgerModels'`。所有方法 try/catch + `console.warn`/hilog + 安全默认值（返回 null/空数组/false/0），与既有 CRUD 的失败风格一致：

```ts
  private learningItemFromResultSet(rs: relationalStore.ResultSet): LearningItem {
    const item = new LearningItem()
    item.itemKey = rs.getString(rs.getColumnIndex('item_key'))
    item.subject = rs.getString(rs.getColumnIndex('subject'))
    item.itemType = rs.getString(rs.getColumnIndex('item_type'))
    item.display = rs.getString(rs.getColumnIndex('display'))
    item.skillKey = rs.getString(rs.getColumnIndex('skill_key'))
    item.firstTaughtAt = rs.getLong(rs.getColumnIndex('first_taught_at'))
    item.lastSeenAt = rs.getLong(rs.getColumnIndex('last_seen_at'))
    item.exposureCount = rs.getLong(rs.getColumnIndex('exposure_count'))
    item.correctCount = rs.getLong(rs.getColumnIndex('correct_count'))
    item.wrongCount = rs.getLong(rs.getColumnIndex('wrong_count'))
    item.mastery = rs.getLong(rs.getColumnIndex('mastery'))
    item.consecutiveCorrect = rs.getLong(rs.getColumnIndex('consecutive_correct'))
    try {
      const modesJson = rs.getString(rs.getColumnIndex('modes_seen_json'))
      const parsed = JSON.parse(modesJson) as Object
      if (Array.isArray(parsed)) {
        const arr = parsed as Object[]
        for (let i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'string') {
            item.modesSeen.push(arr[i] as string)
          }
        }
      }
    } catch (_e) {
      item.modesSeen = []
    }
    item.lastMode = rs.getString(rs.getColumnIndex('last_mode'))
    item.lastSessionId = rs.getString(rs.getColumnIndex('last_session_id'))
    item.nextReviewAt = rs.getLong(rs.getColumnIndex('next_review_at'))
    item.masteredAt = rs.getLong(rs.getColumnIndex('mastered_at'))
    item.source = rs.getString(rs.getColumnIndex('source'))
    item.createdAt = rs.getLong(rs.getColumnIndex('created_at'))
    item.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'))
    return item
  }

  private learningItemToBucket(item: LearningItem): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'item_key': item.itemKey,
      'subject': item.subject,
      'item_type': item.itemType,
      'display': item.display,
      'skill_key': item.skillKey,
      'first_taught_at': item.firstTaughtAt,
      'last_seen_at': item.lastSeenAt,
      'exposure_count': item.exposureCount,
      'correct_count': item.correctCount,
      'wrong_count': item.wrongCount,
      'mastery': item.mastery,
      'consecutive_correct': item.consecutiveCorrect,
      'modes_seen_json': JSON.stringify(item.modesSeen),
      'last_mode': item.lastMode,
      'last_session_id': item.lastSessionId,
      'next_review_at': item.nextReviewAt,
      'mastered_at': item.masteredAt,
      'source': item.source,
      'created_at': item.createdAt,
      'updated_at': item.updatedAt
    }
    return bucket
  }

  async findLearningItemByKey(itemKey: string): Promise<LearningItem | null> {
    try {
      const predicates = new relationalStore.RdbPredicates(TableNames.LEARNING_ITEMS)
      predicates.equalTo('item_key', itemKey).limitAs(1)
      const rs = await this.rdbStore.query(predicates)
      let item: LearningItem | null = null
      if (rs.goToFirstRow()) {
        item = this.learningItemFromResultSet(rs)
      }
      rs.close()
      return item
    } catch (error) {
      console.warn('DatabaseService', `findLearningItemByKey failed: ${String(error)}`)
      return null
    }
  }

  async insertLearningItem(item: LearningItem): Promise<boolean> {
    try {
      const rowId = await this.rdbStore.insert(TableNames.LEARNING_ITEMS, this.learningItemToBucket(item))
      return rowId >= 0
    } catch (error) {
      console.warn('DatabaseService', `insertLearningItem failed: ${String(error)}`)
      return false
    }
  }

  /** update-first: 命中 0 行再 insert (codebase 无 CONFLICT_RESOLUTION 用法, 与既有 upsert 语义一致) */
  async upsertLearningItem(item: LearningItem): Promise<boolean> {
    try {
      const predicates = new relationalStore.RdbPredicates(TableNames.LEARNING_ITEMS)
      predicates.equalTo('item_key', item.itemKey)
      const rows = await this.rdbStore.update(this.learningItemToBucket(item), predicates)
      if (rows > 0) {
        return true
      }
      return await this.insertLearningItem(item)
    } catch (error) {
      console.warn('DatabaseService', `upsertLearningItem failed: ${String(error)}`)
      return false
    }
  }

  private async queryLedgerItems(predicates: relationalStore.RdbPredicates): Promise<LearningItem[]> {
    const items: LearningItem[] = []
    try {
      const rs = await this.rdbStore.query(predicates)
      while (rs.goToNextRow()) {
        items.push(this.learningItemFromResultSet(rs))
      }
      rs.close()
    } catch (error) {
      console.warn('DatabaseService', `queryLedgerItems failed: ${String(error)}`)
    }
    return items
  }

  async queryLedgerNewPool(subject: string, limit: number): Promise<LearningItem[]> {
    const predicates = new relationalStore.RdbPredicates(TableNames.LEARNING_ITEMS)
    predicates.equalTo('subject', subject).lessThanOrEqualTo('mastery', 1)
      .orderByDesc('last_seen_at').limitAs(limit)
    return await this.queryLedgerItems(predicates)
  }

  async queryLedgerDueReview(subject: string, now: number, limit: number): Promise<LearningItem[]> {
    const predicates = new relationalStore.RdbPredicates(TableNames.LEARNING_ITEMS)
    predicates.equalTo('subject', subject).between('mastery', 2, 4)
      .lessThanOrEqualTo('next_review_at', now)
      .orderByAsc('next_review_at').limitAs(limit)
    return await this.queryLedgerItems(predicates)
  }

  async queryLedgerMastered(subject: string, limit: number): Promise<LearningItem[]> {
    const predicates = new relationalStore.RdbPredicates(TableNames.LEARNING_ITEMS)
    predicates.equalTo('subject', subject).equalTo('mastery', 5)
      .orderByDesc('last_seen_at').limitAs(limit)
    return await this.queryLedgerItems(predicates)
  }

  async queryLedgerCooling(subject: string, sinceMs: number, limit: number): Promise<LearningItem[]> {
    const predicates = new relationalStore.RdbPredicates(TableNames.LEARNING_ITEMS)
    predicates.equalTo('subject', subject).greaterThanOrEqualTo('last_seen_at', sinceMs)
      .orderByDesc('last_seen_at').limitAs(limit)
    return await this.queryLedgerItems(predicates)
  }

  async insertLearningItemEvent(event: LedgerEventInsert): Promise<boolean> {
    try {
      const bucket: relationalStore.ValuesBucket = {
        'id': event.id,
        'item_key': event.itemKey,
        'session_id': event.sessionId,
        'mode': event.mode,
        'tool_id': event.toolId,
        'served_at': event.servedAt,
        'answered_at': 0,
        'is_correct': -1,
        'display': event.display
      }
      const rowId = await this.rdbStore.insert(TableNames.LEARNING_ITEM_EVENTS, bucket)
      return rowId >= 0
    } catch (error) {
      console.warn('DatabaseService', `insertLearningItemEvent failed: ${String(error)}`)
      return false
    }
  }

  async updateLatestOpenLedgerEvent(itemKey: string, answeredAt: number, isCorrect: boolean): Promise<void> {
    try {
      const sql = `UPDATE learning_item_events SET answered_at = ?, is_correct = ?
        WHERE id = (SELECT id FROM learning_item_events
          WHERE item_key = ? AND answered_at = 0 ORDER BY served_at DESC LIMIT 1)`
      await this.rdbStore.executeSql(sql, [answeredAt, isCorrect ? 1 : 0, itemKey])
    } catch (error) {
      console.warn('DatabaseService', `updateLatestOpenLedgerEvent failed: ${String(error)}`)
    }
  }

  async getTopRepeatedEvents(subjectPrefix: string, sinceMs: number, limit: number): Promise<RepeatStat[]> {
    const stats: RepeatStat[] = []
    try {
      const sql = `SELECT display, COUNT(*) AS cnt FROM learning_item_events
        WHERE item_key LIKE ? AND served_at >= ?
        GROUP BY display ORDER BY cnt DESC LIMIT ?`
      const rs = await this.rdbStore.querySql(sql, [subjectPrefix, sinceMs, limit])
      while (rs.goToNextRow()) {
        const stat = new RepeatStat()
        stat.display = rs.getString(rs.getColumnIndex('display'))
        stat.count = rs.getLong(rs.getColumnIndex('cnt'))
        stats.push(stat)
      }
      rs.close()
    } catch (error) {
      console.warn('DatabaseService', `getTopRepeatedEvents failed: ${String(error)}`)
    }
    return stats
  }

  async deleteLedgerEventsBefore(cutoffMs: number): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(TableNames.LEARNING_ITEM_EVENTS)
      predicates.lessThan('served_at', cutoffMs)
      return await this.rdbStore.delete(predicates)
    } catch (error) {
      console.warn('DatabaseService', `deleteLedgerEventsBefore failed: ${String(error)}`)
      return 0
    }
  }

  async countLedgerMastered(subject: string): Promise<number> {
    try {
      const sql = `SELECT COUNT(*) AS cnt FROM learning_items WHERE subject = ? AND mastery = 5`
      const rs = await this.rdbStore.querySql(sql, [subject])
      let count = 0
      if (rs.goToFirstRow()) {
        count = rs.getLong(rs.getColumnIndex('cnt'))
      }
      rs.close()
      return count
    } catch (error) {
      console.warn('DatabaseService', `countLedgerMastered failed: ${String(error)}`)
      return 0
    }
  }
```

若 querySql 的 bind 参数类型报 ArkTS 错，照 `DatabaseService` 内既有 `querySql` 调用点的参数数组写法调整（grep `querySql(`）。

- [ ] **Step 4: 构建验证**（主模块 assembleHap exit 0）。
- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(ledger): learning_items + learning_item_events 建表与 CRUD"
```

---

### Task 4: 服务核心（services/LearningLedgerService.ets + 注册 + 启动初始化）

**Files:**
- Create: `entry/src/main/ets/services/LearningLedgerService.ets`
- Modify: `entry/src/main/ets/services/ServiceRegistry.ets`（新增 `learningLedger()` 门面）
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`（initializeServices 中初始化）

**Interfaces:**
- Consumes: Task 1-3 全部产出；`getDatabaseService()`（`services/DatabaseService.ets:4852`）；`evaluateRepeatPolicy` / `normalizeItemKey`（Task 2）。
- Produces:
  - `getLearningLedgerService(): LearningLedgerService`
  - `async recordServed(input: LedgerRecord): Promise<void>`
  - `async recordAnswer(items: LedgerAnswerItem[], now: number): Promise<void>`（偏离 spec 单 item 签名——matching_pairs 一次产生多项，已在计划头注记）
  - `async upsertPlanItems(items: LedgerItemSeed[], now: number): Promise<void>`
  - `async buildSummary(subject: string, now: number): Promise<LedgerSummary>`（60s 内存缓存）
  - `async checkRepeat(sessionId: string, itemKey: string, mode: string, purpose: string, now: number, display: string): Promise<RepeatCheck>`（偏离 spec 签名——增加 sessionId 以查会话环形缓冲，已注记）
  - `async getTopRepeated(subject: string, sinceMs: number, limit: number): Promise<RepeatStat[]>`
  - `async getMasteredCount(subject: string): Promise<number>`
  - `async initialize(): Promise<void>`（清理 >90 天事件）
  - `ServiceRegistry.learningLedger(): LearningLedgerService`

- [ ] **Step 1: 写 `entry/src/main/ets/services/LearningLedgerService.ets`**

```ets
/**
 * LearningLedgerService - 词汇台账核心服务 (spec §5)
 *
 * 单例, 与 ImageIndexService 同构: 薄服务层 + CRUD 全在 DatabaseService。
 * 铁律: 任何失败都静默降级 (record/check 失败 → 放行/忽略), 绝不阻断出题与教学。
 *
 * 写入: recordServed (出题曝光) / recordAnswer (作答→掌握度) / upsertPlanItems (计划种子)
 * 读取: buildSummary (三名单+高频, 60s 缓存) / checkRepeat (门禁探针) / getTopRepeated / getMasteredCount
 * 会话内环形缓冲: 每 session 最近 20 条 {itemKey, mode}, 供 SESSION_GAP_ITEMS=5 间隔判定 (内存, 随进程销毁)
 */
import { hilog } from '@kit.PerformanceAnalysisKit'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import {
  LearningItem,
  LedgerAnswerItem,
  LedgerEventInsert,
  LedgerItemSeed,
  LedgerRecord,
  LedgerSummary,
  DueReviewHint,
  RepeatCheck,
  RepeatPolicyInput,
  RepeatStat,
  createEmptyLedgerSummary,
  computeMasteryTransition,
  SUMMARY_CACHE_TTL_MS,
  SAME_MODE_COOLDOWN_MS,
  SESSION_GAP_ITEMS,
  TOP_REPEATED_WINDOW_MS,
  EVENT_RETENTION_MS,
  RECENT_WINDOW_CAPACITY,
  RECENT_SESSION_PRUNE_MAX
} from '../models/LearningLedgerModels'
import { normalizeItemKey } from '../utils/LedgerExtractUtils'
import { evaluateRepeatPolicy } from '../utils/VocabRepeatValidation'

const DOMAIN = 0x0000
const TAG = 'LearningLedgerService'

interface CachedSummary {
  summary: LedgerSummary
  expiresAt: number
}

interface LedgerRecentEntry {
  itemKey: string
  mode: string
  servedAt: number
}

export class LearningLedgerService {
  private static instance: LearningLedgerService | null = null
  private summaryCache: Map<string, CachedSummary> = new Map()
  private recentServedBySession: Map<string, LedgerRecentEntry[]> = new Map()
  private recentSessionOrder: string[] = []

  private constructor() {
  }

  static getInstance(): LearningLedgerService {
    if (LearningLedgerService.instance === null) {
      LearningLedgerService.instance = new LearningLedgerService()
    }
    return LearningLedgerService.instance
  }

  private get databaseService(): DatabaseService {
    return getDatabaseService()
  }

  /** 启动清理 >90 天事件流水 (spec §7.1 跨会话统计窗口), 失败静默 */
  async initialize(): Promise<void> {
    try {
      const cutoff = Date.now() - EVENT_RETENTION_MS
      await this.databaseService.deleteLedgerEventsBefore(cutoff)
      hilog.info(DOMAIN, TAG, 'initialized (events pruned)')
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `initialize failed (ignored): ${String(error)}`)
    }
  }

  /**
   * 出题曝光登记 (spec §6): 主表 upsert + 事件流水 + 会话环。
   * recordServed 累加 exposureCount / 更新 lastSeenAt / lastMode / modesSeen; 不动掌握度。
   */
  async recordServed(input: LedgerRecord): Promise<void> {
    this.pushRecentServed(input.sessionId, input.itemKey, input.mode, input.now)
    try {
      const existing = await this.databaseService.findLearningItemByKey(input.itemKey)
      let item: LearningItem
      if (existing === null) {
        item = new LearningItem()
        item.itemKey = input.itemKey
        item.subject = input.subject
        item.itemType = input.itemType
        item.display = input.display
        item.skillKey = input.skillKey
        item.firstTaughtAt = input.now
        item.lastSeenAt = input.now
        item.exposureCount = 1
        item.modesSeen = [input.mode]
        item.lastMode = input.mode
        item.lastSessionId = input.sessionId
        item.source = 'session'
        item.createdAt = input.now
        item.updatedAt = input.now
      } else {
        item = existing
        item.lastSeenAt = input.now
        item.exposureCount = item.exposureCount + 1
        item.lastMode = input.mode
        item.lastSessionId = input.sessionId
        if (item.display === '') {
          item.display = input.display
        }
        if (item.modesSeen.indexOf(input.mode) < 0) {
          item.modesSeen.push(input.mode)
        }
        item.updatedAt = input.now
      }
      await this.databaseService.upsertLearningItem(item)
      const event: LedgerEventInsert = {
        id: `lie_${input.now}_${Math.floor(Math.random() * 100000)}`,
        itemKey: input.itemKey,
        sessionId: input.sessionId,
        mode: input.mode,
        toolId: input.toolId,
        servedAt: input.now,
        display: input.display
      }
      await this.databaseService.insertLearningItemEvent(event)
      this.invalidateSummaryCache(input.subject)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `recordServed failed (ignored): ${String(error)}`)
    }
  }

  /**
   * 作答对账 (spec §5.3): 每项走 computeMasteryTransition, 更新主表 + 回填最近一条未答事件。
   * 多项 (matching_pairs) 一次传入。台账无此行时跳过 (计划 seed 未被考过属正常)。
   */
  async recordAnswer(items: LedgerAnswerItem[], now: number): Promise<void> {
    try {
      for (let i = 0; i < items.length; i++) {
        const answer = items[i]
        const row = await this.databaseService.findLearningItemByKey(answer.itemKey)
        if (row === null) {
          continue
        }
        const transition = computeMasteryTransition(row.mastery, row.consecutiveCorrect, answer.isCorrect, now)
        if (answer.isCorrect) {
          row.correctCount = row.correctCount + 1
        } else {
          row.wrongCount = row.wrongCount + 1
        }
        row.mastery = transition.mastery
        row.consecutiveCorrect = transition.consecutiveCorrect
        row.nextReviewAt = transition.nextReviewAt
        if (transition.justMastered) {
          row.masteredAt = now
        }
        row.updatedAt = now
        await this.databaseService.upsertLearningItem(row)
        await this.databaseService.updateLatestOpenLedgerEvent(answer.itemKey, now, answer.isCorrect)
        this.invalidateSummaryCache(row.subject)
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `recordAnswer failed (ignored): ${String(error)}`)
    }
  }

  /** 计划侧种子 (spec §6.1): 只建缺失行 (source=plan), 不改已有行的掌握度/曝光 */
  async upsertPlanItems(items: LedgerItemSeed[], now: number): Promise<void> {
    try {
      for (let i = 0; i < items.length; i++) {
        const seed = items[i]
        const key = normalizeItemKey(seed.subject, seed.itemType, seed.display)
        if (key === '') {
          continue
        }
        const existing = await this.databaseService.findLearningItemByKey(key)
        if (existing !== null) {
          continue
        }
        const item = new LearningItem()
        item.itemKey = key
        item.subject = seed.subject
        item.itemType = seed.itemType
        item.display = seed.display
        item.skillKey = seed.skillKey
        item.firstTaughtAt = now
        item.lastSeenAt = now
        item.source = 'plan'
        item.createdAt = now
        item.updatedAt = now
        await this.databaseService.insertLearningItem(item)
        this.invalidateSummaryCache(seed.subject)
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `upsertPlanItems failed (ignored): ${String(error)}`)
    }
  }

  /** 三名单 + 近 7 天高频 (spec §7), 60s 缓存; 失败返回空 summary (prompt 段自动省略) */
  async buildSummary(subject: string, now: number): Promise<LedgerSummary> {
    const cached = this.summaryCache.get(subject)
    if (cached !== undefined && cached.expiresAt > now) {
      return cached.summary
    }
    try {
      const summary = createEmptyLedgerSummary()
      const newItems = await this.databaseService.queryLedgerNewPool(subject, 12)
      summary.newPool = newItems.map((item: LearningItem) => item.display)
      const dueItems = await this.databaseService.queryLedgerDueReview(subject, now, 12)
      const hints: DueReviewHint[] = []
      for (let i = 0; i < dueItems.length; i++) {
        const row = dueItems[i]
        const hint: DueReviewHint = {
          display: row.display,
          lastMode: row.lastMode,
          dueInMs: Math.max(0, row.nextReviewAt - now)
        }
        hints.push(hint)
      }
      summary.dueReview = hints
      const masteredItems = await this.databaseService.queryLedgerMastered(subject, 12)
      summary.mastered = masteredItems.map((item: LearningItem) => item.display)
      const coolingItems = await this.databaseService.queryLedgerCooling(subject, now - SAME_MODE_COOLDOWN_MS, 12)
      summary.cooling = coolingItems.map((item: LearningItem) => item.display)
      summary.topRepeated =
        await this.databaseService.getTopRepeatedEvents(`${subject}:%`, now - TOP_REPEATED_WINDOW_MS, 8)
      const entry: CachedSummary = { summary: summary, expiresAt: now + SUMMARY_CACHE_TTL_MS }
      this.summaryCache.set(subject, entry)
      hilog.info(DOMAIN, TAG, `Ledger stats: subject=${subject}, new=${summary.newPool.length}, ` +
        `due=${summary.dueReview.length}, cooling=${summary.cooling.length}, ` +
        `mastered=${summary.mastered.length}, topRepeat=${summary.topRepeated.length}`)
      return summary
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `buildSummary failed (empty): ${String(error)}`)
      return createEmptyLedgerSummary()
    }
  }

  /**
   * 门禁探针 (spec §9): 收集 DB 行状态 + 会话环, 交给 evaluateRepeatPolicy 纯函数判定。
   * 任何异常 → 放行 (allowed), 台账故障绝不拦题。
   */
  async checkRepeat(sessionId: string, itemKey: string, mode: string, purpose: string,
    now: number, display: string): Promise<RepeatCheck> {
    const allowed: RepeatCheck = { allowed: true, reason: '', itemKey: itemKey, display: display }
    try {
      const row = await this.databaseService.findLearningItemByKey(itemKey)
      const input: RepeatPolicyInput = {
        purpose: purpose,
        mode: mode,
        now: now,
        found: row !== null,
        lastSeenAt: row !== null ? row.lastSeenAt : 0,
        lastMode: row !== null ? row.lastMode : '',
        mastery: row !== null ? row.mastery : 0,
        nextReviewAt: row !== null ? row.nextReviewAt : 0,
        inSessionGap: this.isInSessionGap(sessionId, itemKey),
        itemKey: itemKey,
        display: display
      }
      return evaluateRepeatPolicy(input)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `checkRepeat failed (allow): ${String(error)}`)
      return allowed
    }
  }

  async getTopRepeated(subject: string, sinceMs: number, limit: number): Promise<RepeatStat[]> {
    try {
      return await this.databaseService.getTopRepeatedEvents(`${subject}:%`, sinceMs, limit)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `getTopRepeated failed: ${String(error)}`)
      const empty: RepeatStat[] = []
      return empty
    }
  }

  async getMasteredCount(subject: string): Promise<number> {
    try {
      return await this.databaseService.countLedgerMastered(subject)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `getMasteredCount failed: ${String(error)}`)
      return 0
    }
  }

  // ---------- 会话内近期出题环形缓冲 (内存) ----------

  private pushRecentServed(sessionId: string, itemKey: string, mode: string, servedAt: number): void {
    if (sessionId === '') {
      return
    }
    let ring = this.recentServedBySession.get(sessionId)
    if (ring === undefined) {
      ring = []
      this.recentServedBySession.set(sessionId, ring)
      this.recentSessionOrder.push(sessionId)
      if (this.recentSessionOrder.length > RECENT_SESSION_PRUNE_MAX) {
        const oldest = this.recentSessionOrder.shift()
        if (oldest !== undefined) {
          this.recentServedBySession.delete(oldest)
        }
      }
    }
    const entry: LedgerRecentEntry = { itemKey: itemKey, mode: mode, servedAt: servedAt }
    ring.push(entry)
    if (ring.length > RECENT_WINDOW_CAPACITY) {
      ring.shift()
    }
  }

  /** 最近 SESSION_GAP_ITEMS(5) 题内是否出现过该 item (spec §7.1 会话间隔, 任何 purpose 生效) */
  private isInSessionGap(sessionId: string, itemKey: string): boolean {
    if (sessionId === '') {
      return false
    }
    const ring = this.recentServedBySession.get(sessionId)
    if (ring === undefined || ring.length === 0) {
      return false
    }
    const checkCount = Math.min(SESSION_GAP_ITEMS, ring.length)
    for (let i = 0; i < checkCount; i++) {
      const entry = ring[ring.length - 1 - i]
      if (entry.itemKey === itemKey) {
        return true
      }
    }
    return false
  }

  private invalidateSummaryCache(subject: string): void {
    this.summaryCache.delete(subject)
  }
}

export function getLearningLedgerService(): LearningLedgerService {
  return LearningLedgerService.getInstance()
}
```

- [ ] **Step 2: ServiceRegistry 门面** —— `services/ServiceRegistry.ets` 照 `static lessonPlanning()` 的样式加（import + static 方法）：

```ts
  static learningLedger(): LearningLedgerService {
    return getLearningLedgerService()
  }
```

- [ ] **Step 3: EntryAbility 初始化** —— `entryability/EntryAbility.ets` 的 `initializeServices`，在 `ServiceRegistry.database().initialize(...)` + 日志行（`:135-136`）之后插入：

```ts
      // 初始化词汇台账服务 (清理过期事件流水)
      await ServiceRegistry.learningLedger().initialize();
      hilog.info(DOMAIN, 'testTag', 'LearningLedgerService initialized successfully');
```

- [ ] **Step 4: 构建验证**（主模块 assembleHap exit 0）。
- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(ledger): LearningLedgerService 服务核心 + ServiceRegistry 门面 + 启动初始化"
```

---

### Task 5: 会话写入链路（ToolExecutionService 10 handler + recordStarEvent 挂钩）

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

**Interfaces:**
- Consumes: `getLearningLedgerService()`（Task 4）、`extractLedgerItemsFromTool` / `extractLedgerAnswerItems` / `normalizeItemKey`（Task 2）、`LedgerRecord` 类型（Task 1）。
- Produces: 私有 helper `recordLedgerServed(toolId, toolCall, context)` / `recordLedgerAnswered(toolCall, context, answerJson)`（Task 8 无依赖，但评审时核对挂钩位置）。

- [ ] **Step 1: imports** —— 文件头补：

```ts
import { getLearningLedgerService } from './LearningLedgerService'
import { extractLedgerItemsFromTool, extractLedgerAnswerItems, normalizeItemKey } from '../utils/LedgerExtractUtils'
import { LedgerRecord } from '../models/LearningLedgerModels'
```

- [ ] **Step 2: 两个私有 helper** —— 加在 `recordStarEvent`（`:442`）附近：

```ts
  /**
   * 出题曝光登记 (fire-and-forget, spec §6.2): 在 handler 进入 pending 态后调用。
   * 静默失败——台账任何异常不影响出题。
   */
  private recordLedgerServed(toolId: string, toolCall: ToolCall, context: ToolExecutionContext): void {
    const items = extractLedgerItemsFromTool(toolId, toolCall.arguments)
    if (items.length === 0) {
      return
    }
    const now = Date.now()
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      const record: LedgerRecord = {
        itemKey: normalizeItemKey(item.subject, item.itemType, item.display),
        subject: item.subject,
        itemType: item.itemType,
        display: item.display,
        skillKey: item.skillKey,
        mode: item.mode,
        toolId: toolId,
        sessionId: context.sessionId,
        now: now
      }
      getLearningLedgerService().recordServed(record).catch((_e: Object) => {
        // 静默: 台账失败不阻断出题
      })
    }
  }

  /**
   * 作答对账 (fire-and-forget): 仅由 recordStarEvent 调用——该方法只在拿到 answerJson 的
   * 路径被触达 (取消/关闭卡片的 null 路径在此之前已 early-return), 因此取消不写掌握度。
   */
  private recordLedgerAnswered(toolId: string, toolCall: ToolCall, context: ToolExecutionContext,
    answerJson: string): void {
    const answers = extractLedgerAnswerItems(toolId, toolCall.arguments, answerJson)
    if (answers.length === 0) {
      return
    }
    getLearningLedgerService().recordAnswer(answers, Date.now()).catch((_e: Object) => {
      // 静默: 台账失败不阻断授星与对话
    })
  }
```

（若 `recordStarEvent` 内部对 `getStarRewardService().recordEvent(...)` 的调用方式是"不 await 的 void 调用"，本 helper 保持同款；`.catch((_e: Object) => {})` 形式以文件内既有 fire-and-forget 写法为准。）

- [ ] **Step 3: recordServed 挂钩 ×10** —— 在以下 10 个 handler 内、紧贴 `toolCall.approvalState = 'pending'` 赋值行**之后**各插一行（grep 定位：在各 handler 函数体内找 `approvalState = 'pending'`）：

| handler | 快照行号 | 插入语句 |
|---|---|---|
| handleEnglishQuiz | :825 | `this.recordLedgerServed('english_quiz', toolCall, context)` |
| handlePictureVocab | :1009 | `this.recordLedgerServed('picture_vocab', toolCall, context)` |
| handleListeningQuiz | :1131 | `this.recordLedgerServed('listening_quiz', toolCall, context)` |
| handlePinyinQuiz | :1222 | `this.recordLedgerServed('pinyin_quiz', toolCall, context)` |
| handleHanziCard | :1312 | `this.recordLedgerServed('hanzi_card', toolCall, context)` |
| handlePinyinCard | :1402 | `this.recordLedgerServed('pinyin_card', toolCall, context)` |
| handlePictureTalk | :1492 | `this.recordLedgerServed('picture_talk', toolCall, context)` |
| handleChineseQuiz | :1611 | `this.recordLedgerServed('chinese_quiz', toolCall, context)` |
| handleMatchingPairs | :2067 | `this.recordLedgerServed('matching_pairs', toolCall, context)` |
| handleHandwriting | :2138 | `this.recordLedgerServed('handwriting_practice', toolCall, context)` |

若 handler 内已有与字面量等价的 `toolId` 局部变量，用变量；否则用字面量。**不得**加到 math_quiz / number_puzzle / maze / sudoku / categorization handler（它们的 extract 返回空，挂了也无害，但按 spec 只挂这 10 个）。

- [ ] **Step 4: recordAnswer 挂钩 ×1** —— `recordStarEvent`（`:442`）方法体**末尾**追加：

```ts
    // 词级台账作答回写 (fire-and-forget): 非台账工具 extract 返回空, 天然 no-op
    this.recordLedgerAnswered(toolCall, context, answerJson)
```

放在 `getStarRewardService().recordEvent(...)` 调用语句之后、方法结束前。**注意顺序**：星星回写在前，台账在后，任一失败互不影响。钩子只加这一处——保证取消路径（resolvePendingAnswer 传 null → handler early-return → 不调 recordStarEvent）天然不写掌握度（Review Focus #5）。

- [ ] **Step 5: 构建验证**（主模块 assembleHap exit 0）。
- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(ledger): 10 个出题 handler 接入曝光登记, recordStarEvent 挂接作答回写"
```

---

### Task 6: 备课链路写入 + ledger 输入（LessonPlanningService）

**Files:**
- Modify: `entry/src/main/ets/services/LessonPlanningService.ets`

**Interfaces:**
- Consumes: `getLearningLedgerService().buildSummary / upsertPlanItems`（Task 4）、`extractLedgerSeeds`（Task 2）。
- Produces: 备课 userInput JSON 新增 `ledger` 字段（Task 7 的 PLANNER_SYSTEM_PROMPT 文案依赖它）。

- [ ] **Step 1: imports** —— 文件头补：

```ts
import { getLearningLedgerService } from './LearningLedgerService'
import { extractLedgerSeeds } from '../utils/LedgerExtractUtils'
import { LedgerSummary } from '../models/LearningLedgerModels'
```

- [ ] **Step 2: 文件级接口 + 构建函数** —— 加在 LessonPlanningService 类外（文件底部或顶部 interface 区）：

```ts
/** 备课输入的词级台账载荷 (spec §8.2); 台账不可用时为 null */
interface PlannerLedgerPayload {
  newCandidates: string[]
  dueReview: string[]
  mastered: string[]
  cooling: string[]
}
```

类内私有方法：

```ts
  /** 合并 en+zh 台账摘要为备课输入载荷; 失败返回 null (prompt 端容错) */
  private async buildPlannerLedgerPayload(): Promise<PlannerLedgerPayload | null> {
    try {
      const nowMs = Date.now()
      const ledger = getLearningLedgerService()
      const enSummary: LedgerSummary = await ledger.buildSummary('en', nowMs)
      const zhSummary: LedgerSummary = await ledger.buildSummary('zh', nowMs)
      const dueDisplays: string[] = []
      for (let i = 0; i < enSummary.dueReview.length; i++) {
        dueDisplays.push(enSummary.dueReview[i].display)
      }
      for (let i = 0; i < zhSummary.dueReview.length; i++) {
        dueDisplays.push(zhSummary.dueReview[i].display)
      }
      const payload: PlannerLedgerPayload = {
        newCandidates: enSummary.newPool.concat(zhSummary.newPool),
        dueReview: dueDisplays,
        mastered: enSummary.mastered.concat(zhSummary.mastered),
        cooling: enSummary.cooling.concat(zhSummary.cooling)
      }
      return payload
    } catch (error) {
      console.warn('LessonPlanningService', `buildPlannerLedgerPayload failed (ignored): ${String(error)}`)
      return null
    }
  }

  /** 计划落库后登记台账种子 (source=plan, 只建行); 静默失败 */
  private async recordPlanSeeds(plan: LessonPlan): Promise<void> {
    try {
      await getLearningLedgerService().upsertPlanItems(extractLedgerSeeds(plan), Date.now())
    } catch (error) {
      console.warn('LessonPlanningService', `recordPlanSeeds failed (ignored): ${String(error)}`)
    }
  }
```

- [ ] **Step 3: userInput 注入 ledger** —— `runPlanningPipeline` 内 `const userInput = JSON.stringify({...})`（快照 `:573-582`），在构建前加 `const ledgerPayload = await this.buildPlannerLedgerPayload()`，并在对象字面量里 `recentTopics: recentTopics,` 之后加一行 `ledger: ledgerPayload,`。

- [ ] **Step 4: 种子写入 ×2（两条持久化路径都要）**：
  1. **baseline 路径**：`setAppUiStateValue(AppStorageKeys.LESSON_PLAN_REFRESH_TICK, Date.now())`（快照 `:674`）之后、`console.info(...baseline...)`（`:675`）之前插入 `await this.recordPlanSeeds(baseline)`。
  2. **主路径**：第二个 `setAppUiStateValue(AppStorageKeys.LESSON_PLAN_REFRESH_TICK, Date.now())`（快照 `:695`）之后、`console.info('LessonPlanningService', \`Plan for ${planDate} generated successfully...` 之前插入 `await this.recordPlanSeeds(plan)`。

- [ ] **Step 5: 构建验证**（主模块 assembleHap exit 0）。
- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(ledger): 备课管线注入 ledger 输入 + 两条持久化路径登记计划种子"
```

---

### Task 7: Prompt 注入（renderVocabLedgerSection + 小星老师第 5 段 + 备课 prompt 改写）

**Files:**
- Modify: `entry/src/main/ets/utils/LessonPlanPromptUtils.ets`
- Modify: `entry/src/main/ets/viewmodels/ChatViewModel.ets`
- Test: `entry/src/ohosTest/ets/test/utils/VocabLedgerSection.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: `LedgerSummary` / `DueReviewHint`（Task 1）、`getLearningLedgerService()`（Task 4）。
- Produces: `renderVocabLedgerSection(en: LedgerSummary | null, zh: LedgerSummary | null): string`（两科四名单全空时返回 `''`，调用方省略该段）。

- [ ] **Step 1: 写失败测试** `entry/src/ohosTest/ets/test/utils/VocabLedgerSection.test.ets`

```ets
import { describe, it, expect } from '@ohos/hypium'
import { renderVocabLedgerSection } from '../../../../main/ets/utils/LessonPlanPromptUtils'
import { LedgerSummary, DueReviewHint, createEmptyLedgerSummary } from '../../../../main/ets/models/LearningLedgerModels'

function sampleEnSummary(): LedgerSummary {
  const summary = createEmptyLedgerSummary()
  summary.newPool = ['banana', 'dog']
  summary.dueReview = []
  summary.mastered = ['apple', 'cat']
  summary.cooling = ['red']
  return summary
}

export default function vocabLedgerSectionTest(): void {
  describe('vocabLedgerSectionTest', () => {
    it('empty_summaries_render_empty_string', 0, () => {
      const empty = createEmptyLedgerSummary()
      expect(renderVocabLedgerSection(null, null)).assertEqual('')
      expect(renderVocabLedgerSection(empty, empty)).assertEqual('')
    })

    it('en_only_renders_english_lines_and_rules', 0, () => {
      const text = renderVocabLedgerSection(sampleEnSummary(), null)
      expect(text.indexOf('【词汇台账】') >= 0).assertTrue()
      expect(text.indexOf('英语已掌握') >= 0).assertTrue()
      expect(text.indexOf('apple') >= 0).assertTrue()
      expect(text.indexOf('英语今日新词') >= 0).assertTrue()
      expect(text.indexOf('英语冷却中') >= 0).assertTrue()
      expect(text.indexOf('语文') < 0).assertTrue()
      expect(text.indexOf('出题规则') >= 0).assertTrue()
    })

    it('due_review_hint_shows_last_mode', 0, () => {
      const summary = createEmptyLedgerSummary()
      const hint: DueReviewHint = { display: 'banana', lastMode: 'english_quiz.listen_choice', dueInMs: 0 }
      summary.dueReview = [hint]
      const text = renderVocabLedgerSection(summary, null)
      expect(text.indexOf('banana(上次 english_quiz.listen_choice)') >= 0).assertTrue()
      expect(text.indexOf('换题型巩固') >= 0).assertTrue()
    })

    it('zh_lines_rendered_for_chinese_summary', 0, () => {
      const zh = createEmptyLedgerSummary()
      zh.mastered = ['山']
      const text = renderVocabLedgerSection(null, zh)
      expect(text.indexOf('语文已掌握') >= 0).assertTrue()
      expect(text.indexOf('山') >= 0).assertTrue()
    })
  })
}
```

- [ ] **Step 2: 注册 suite 到 List.test.ets**（同前样式）。
- [ ] **Step 3: ohosTest 编译确认红**。
- [ ] **Step 4: 实现 renderVocabLedgerSection** —— `utils/LessonPlanPromptUtils.ets` 文件头补 `import { LedgerSummary, DueReviewHint } from '../models/LearningLedgerModels'`，文件底部（`extractRecentTopics` 附近）加：

```ets
function ledgerSectionHasContent(summary: LedgerSummary): boolean {
  return summary.newPool.length > 0 || summary.dueReview.length > 0
    || summary.mastered.length > 0 || summary.cooling.length > 0
}

function appendLedgerSubjectLines(lines: string[], label: string, summary: LedgerSummary): void {
  if (summary.mastered.length > 0) {
    lines.push(`- ${label}已掌握(勿当新词考, 只在复习轮抽检): ${summary.mastered.join(', ')}`)
  }
  if (summary.newPool.length > 0) {
    lines.push(`- ${label}今日新词: ${summary.newPool.join(', ')}`)
  }
  if (summary.dueReview.length > 0) {
    const parts: string[] = []
    for (let i = 0; i < summary.dueReview.length; i++) {
      const hint = summary.dueReview[i]
      if (hint.lastMode !== '') {
        parts.push(`${hint.display}(上次 ${hint.lastMode})`)
      } else {
        parts.push(hint.display)
      }
    }
    lines.push(`- ${label}待复习(请换题型巩固): ${parts.join(' / ')}`)
  }
  if (summary.cooling.length > 0) {
    lines.push(`- ${label}冷却中(本轮勿出): ${summary.cooling.join(', ')}`)
  }
}

/**
 * 小星老师 prompt 的【词汇台账】段 (spec §8.1)。
 * 两科摘要都为 null 或四名单全空时返回 '' (调用方整段省略, 避免 prompt 出现空节)。
 */
export function renderVocabLedgerSection(en: LedgerSummary | null, zh: LedgerSummary | null): string {
  if (en === null && zh === null) {
    return ''
  }
  const hasEn = en !== null && ledgerSectionHasContent(en)
  const hasZh = zh !== null && ledgerSectionHasContent(zh)
  if (!hasEn && !hasZh) {
    return ''
  }
  const lines: string[] = []
  lines.push('【词汇台账】')
  if (en !== null && ledgerSectionHasContent(en)) {
    appendLedgerSubjectLines(lines, '英语', en)
  }
  if (zh !== null && ledgerSectionHasContent(zh)) {
    appendLedgerSubjectLines(lines, '语文', zh)
  }
  lines.push('出题规则: 新词优先; 复习词必须换一种题型复现, 不要同一题型连出同一词; ' +
    '同一词一节课最多出现 2 次(不同题型), 不要连续 5 题内重复。')
  return lines.join('\n')
}
```

- [ ] **Step 5: ChatViewModel 注入第 5 段** —— `injectTeachingSections`（快照 `:341-387`）：文件头补 import `renderVocabLedgerSection`（来自 `../utils/LessonPlanPromptUtils`，若已 import 该模块则并入既有语句）与 `import { getLearningLedgerService } from '../services/LearningLedgerService'`。在 `// 3. 今日教学目标` 块结束（`today !== null` 的 if 关闭大括号）之后、`// 4. 主动招呼元指令` 注释之前插入：

```ts
      // 3.5 词汇台账 (三名单, spec §8.1): 独立 try/catch——台账失败不拖垮整段教学注入
      try {
        const nowMs = Date.now()
        const ledgerEn = await getLearningLedgerService().buildSummary('en', nowMs)
        const ledgerZh = await getLearningLedgerService().buildSummary('zh', nowMs)
        const ledgerSection = renderVocabLedgerSection(ledgerEn, ledgerZh)
        if (ledgerSection !== '') {
          composed = this.assistantService.combineSystemPrompts(composed, ledgerSection)
        }
      } catch (ledgerError) {
        console.warn('ChatViewModel', `vocab ledger section skipped: ${String(ledgerError)}`)
      }
```

同时把方法 doc 注释的注入顺序列表 `1./2./3.` 更新为 `1. 昨日小结 2. 教学风格调整 3. 今日教学目标 3.5 词汇台账 4. greetingHint`。

- [ ] **Step 6: 备课 prompt 改写** —— `PLANNER_SYSTEM_PROMPT`（同文件）两处：
  1. **输入清单**（快照 `:35-39` 的 `- recentTopics: ...` 条目及其子 bullet 之后）追加一个条目：

```text
- ledger: 词级台账状态 (可能为 null), 包含:
  - newCandidates: 台账中的新词候选 (mastery<=1)
  - dueReview: 到期该复习的词
  - mastered: 已掌握 (mastery=5, 勿当新词)
  - cooling: 冷却中 (30 分钟内刚出过)
```

  2. **3.5 条改写**（快照 `:54-59` 整块替换）。旧文：

```text
3.5 **避免重复近 7 天内容**。输入 JSON 的 recentTopics 字段列出近 7 天已教内容,硬约束:
    - vocab[].word 严禁出现在 recentTopics.recentVocabWords 中 (大小写不敏感)
    - writing[].characterOrWord 严禁出现在 recentTopics.recentWritingChars 中
    - themeTitle 主题类别严禁与 recentTopics.recentThemeTitles 中的任一条重复 (例: 若近期有"和动物做朋友", 不得再出"动物"主题; 若近期有"果园里的水果", 不得再出"水果"主题)
    - math.description 不得与 recentTopics.recentMathDescriptions 中的任一条完全相同
    - 若 recentTopics 各数组均为空 (首次备课或历史清空),本约束自动失效
```

新文（去重权威源从"近 7 天计划词"迁移到台账，recentTopics 降级为主题轮换参考；主题类别的轮换约束**保留**并挪入此条，原 3.6 对 themeTitle 的重复约束不受影响）：

```text
3.5 **避免重复 (词级台账驱动)**。输入 JSON 的 ledger 字段给出词级状态, 硬约束:
    - vocab[].word 严禁出现在 ledger.mastered 或 ledger.cooling 中
    - 已掌握词最多 1 个仅作"复习轮"出现, 且必须换一种题型
    - 优先从 ledger.newCandidates / ledger.dueReview 中选词
    - 若 ledger 为 null 或各数组均为空 (首次使用/台账不可用), 本条硬约束自动失效
    - recentTopics 仍保留作主题类别轮换之用: themeTitle 严禁与 recentTopics.recentThemeTitles 重复;
      writing[].characterOrWord 仍避免与 recentTopics.recentWritingChars 完全相同 (台账为空的兜底)
```

- [ ] **Step 7: 构建 + ohosTest 编译验证**（均 exit 0）。
- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(ledger): 小星老师 prompt 词汇台账段 + 备课 prompt 3.5 台账化改写"
```

---

### Task 8: 出题硬门禁（ToolExecutionService 5 handler + schema purpose 字段）

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

**Interfaces:**
- Consumes: `extractLedgerItemsFromTool` / `normalizeItemKey`（Task 2）、`parsePurpose` / `buildRepeatBlockedMessage`（Task 2）、`getLearningLedgerService().checkRepeat`（Task 4）。
- Produces: 私有 `runVocabRepeatGate(toolId, toolCall, context): Promise<ToolResult | null>`（null=放行；非 null=已构造 repeat_blocked ToolResult）。5 个 schema 新增可选 `purpose` 属性。

- [ ] **Step 1: imports 补充** —— ToolExecutionService 在 Task 5 基础上加 `import { parsePurpose, buildRepeatBlockedMessage } from '../utils/VocabRepeatValidation'`。

- [ ] **Step 2: 门禁 helper** —— 加在 Task 5 的 `recordLedgerServed` 附近：

```ts
  /**
   * 出题重复度硬门禁 (spec §9): 预校验通过后、进 pending 前调用。
   * 返回 null = 放行; 非 null = 已构造 repeat_blocked ToolResult (should_retry, LLM 自纠换词)。
   * 台账任何异常 → 放行 (静默失败铁律)。
   */
  private async runVocabRepeatGate(toolId: string, toolCall: ToolCall,
    context: ToolExecutionContext): Promise<ToolResult | null> {
    try {
      const items = extractLedgerItemsFromTool(toolId, toolCall.arguments)
      if (items.length === 0) {
        return null
      }
      const purpose = parsePurpose(toolCall.arguments)
      const now = Date.now()
      for (let i = 0; i < items.length; i++) {
        const item = items[i]
        const itemKey = normalizeItemKey(item.subject, item.itemType, item.display)
        const check = await getLearningLedgerService()
          .checkRepeat(context.sessionId, itemKey, item.mode, purpose, now, item.display)
        if (!check.allowed) {
          const message = buildRepeatBlockedMessage(check.reason, check.display)
          // ToolResult 构造: 逐字镜像本 handler 内 validation_failed 失败返回的构造方式
          // (grep 同函数体内 'validation_failed' 抄结构), 仅替换 error/message:
          //   error: 'repeat_blocked'
          //   message: message  (buildRepeatBlockedMessage 已含 purpose:"review" 自救提示)
          //   should_retry: true
          return <按 validation_failed 同款构造, 替换上述三值>
        }
      }
      return null
    } catch (_e) {
      return null
    }
  }
```

> 实现注：`<按 ... 构造>` 不是占位——执行时打开目标 handler，找到它现有的 validation 失败分支（形如 `const result: ToolResult = { content: JSON.stringify({ 'error': 'validation_failed', 'message': ..., 'should_retry': true }), isError: ... }` 之类），**逐字段复制那份构造代码**，把 error 值换成 `'repeat_blocked'`、message 值换成 `message` 变量。ToolResult 的确切字段（content/isError 等）以代码为准，本计划不猜。

- [ ] **Step 3: 门禁接入 ×5** —— 在以下 5 个 handler 内、`validateXxxArgs(...)` 失败分支**之后**、`toolCall.approvalState = 'pending'` **之前**插入：

```ts
    const repeatBlock = await this.runVocabRepeatGate(toolId, toolCall, context)
    if (repeatBlock !== null) {
      return repeatBlock
    }
```

| handler | 校验调用快照行号（grep `validate` 定位） |
|---|---|
| handleEnglishQuiz | :807 |
| handlePictureVocab | :991 |
| handleListeningQuiz | :1113 |
| handlePinyinQuiz | :1204 |
| handleChineseQuiz | :1593 |

注意 hanzi_card / pinyin_card / picture_talk / matching_pairs / handwriting **不接门禁**（讲解型与配对型无"重复出题"语义；spec §9 只列 5 个出题工具）。

- [ ] **Step 4: schema 加 purpose** —— `config/BuiltinTools.ets` 在 `english_quiz` / `picture_vocab` / `listening_quiz` / `pinyin_quiz` / `chinese_quiz` 五个工具的 schema JSON 模板字符串内、`"required"` 键之前各加：

```json
"purpose": {"type": "string", "enum": ["new", "review"], "description": "出题目的。new=考新词或常规巩固(默认);review=显式复习近期学过的词,可绕过同题型冷却但仍受会话间隔限制。复现旧词时必须传 review,缺省视为 new"}
```

description 内无 ASCII 双引号（已用中文标点）。改完跑验证（对每个改动的 schema：从模板字符串里提取 JSON 并 parse）：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && node -e "
const fs = require('fs');
const src = fs.readFileSync('entry/src/main/ets/config/BuiltinTools.ets', 'utf8');
const re = /const rawSchemaJson: string = \`([^\`]*)\`/g;
let m, count = 0;
while ((m = re.exec(src)) !== null) { JSON.parse(m[1]); count++; }
console.log('schemas parsed OK:', count);
"
```

（预期输出所有 schema 块 parse OK；若项目内 rawSchemaJson 写法有变体，grep `rawSchemaJson` 确认覆盖到 5 个改动块即可。）

- [ ] **Step 5: 构建验证**（主模块 assembleHap exit 0）。
- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(ledger): 出题硬门禁 repeat_blocked 接入 5 个出题工具 + schema purpose 字段"
```

---

### Task 9: 可观测性（家长页台账区块）

**Files:**
- Modify: `entry/src/main/ets/pages/LearningProfilePage.ets`

**Interfaces:**
- Consumes: `getLearningLedgerService().getTopRepeated / getMasteredCount`（Task 4）、`RepeatStat`（Task 1）。

- [ ] **Step 1: 状态与方法** —— LearningProfilePage 内（照既有 @Local 字段与 aboutToAppear 的加载样式）：

```ts
  @Local ledgerMasteredCount: number = 0
  @Local ledgerTopRepeated: string[] = []

  private async loadLedgerStats(): Promise<void> {
    try {
      const ledger = getLearningLedgerService()
      const since = Date.now() - TOP_REPEATED_WINDOW_MS
      const enTop = await ledger.getTopRepeated('en', since, 8)
      const zhTop = await ledger.getTopRepeated('zh', since, 8)
      const merged: RepeatStat[] = enTop.concat(zhTop)
      merged.sort((a: RepeatStat, b: RepeatStat) => b.count - a.count)
      const displays: string[] = []
      for (let i = 0; i < Math.min(8, merged.length); i++) {
        displays.push(`${merged[i].display} ×${merged[i].count}`)
      }
      this.ledgerTopRepeated = displays
      const enCount = await ledger.getMasteredCount('en')
      const zhCount = await ledger.getMasteredCount('zh')
      this.ledgerMasteredCount = enCount + zhCount
    } catch (error) {
      console.warn('LearningProfilePage', `loadLedgerStats failed (ignored): ${String(error)}`)
    }
  }
```

imports 补 `getLearningLedgerService`（`../services/LearningLedgerService`）、`RepeatStat` 与 `TOP_REPEATED_WINDOW_MS`（`../models/LearningLedgerModels`）。在 `aboutToAppear`（快照 `:145`）末尾 fire-and-forget 调 `this.loadLedgerStats()`（照该文件既有异步加载写法，不 await）。

- [ ] **Step 2: UI 区块** —— 在孩子画像页 Scroll 内容（快照 `SkillChipList` @Builder `:381` 所在的内容列，Scroll 主体 `:554`）末尾追加一个分组卡片，视觉完全复用页面内既有分组卡（找页内现成的卡片 @Builder 抄外壳：背景/圆角/内边距/标题行样式），内容：

```text
词汇台账
- 已掌握词数: {this.ledgerMasteredCount}
- 近 7 天高频词: {this.ledgerTopRepeated 逐行渲染; 空数组时显示 '暂无数据'}
```

渲染时 `this.ledgerTopRepeated` 直接在 ForEach 中使用（@Local 数组，响应式正常）；空态显示"暂无数据"一行 `text_tertiary`。不改 `SkillChipList` 与页面其余结构。

- [ ] **Step 3: 构建验证**（主模块 assembleHap exit 0）。
- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(ledger): 家长画像页新增词汇台账区块 (已掌握词数 + 近 7 天高频词)"
```

---

## 验收对照（spec §14 → 任务映射）

| spec 验收项 | 覆盖任务 |
|---|---|
| 1. 词级可追溯 (exposureCount/lastSeenAt) | Task 4 recordServed + Task 5 |
| 2. 会话链路生效（不经备课也入账） | Task 5（10 handler 直写） |
| 3. 冷却生效 repeat_blocked | Task 2 策略测试 + Task 8 |
| 4. 换题型放行, modesSeen 增加 | Task 2 `policy_new_allowed_when_mode_differs` + Task 4 recordServed |
| 5. 间隔推进 (答对升/答错回落) | Task 1 computeMasteryTransition 测试 + Task 4 recordAnswer |
| 6. Prompt 注入（台账段 + ledger 字段） | Task 7 |
| 7. 已掌握 30 天抽检 | Task 1 (MASTERED_RECHECK 间隔) + Task 2 `policy_new_blocked_by_mastered_recheck` |
| 8. 双科统一 (subject 区分) | Task 3 表 + Task 4 buildSummary('en'/'zh') |
| 9. 不回归 (台账故障全兼容) | Global Constraints 静默铁律 + Review Focus #1，Task 4/5/8 的 catch 路径 |
| 10. 首次使用空台账正常 | Task 4 buildSummary 空态 + Task 7 renderVocabLedgerSection 空返回 '' |

## 用户手工验收（实现完成后）

hypium 测试无法 CLI 运行——请在 DevEco Studio 打开 `entry/src/ohosTest/ets/test/`，右键逐个 Run：`LearningLedgerModels.test` / `LedgerExtractUtils.test` / `VocabRepeatValidation.test` / `VocabLedgerSection.test`。端到端：连续出 5 道含 apple 的题 → 查 `learning_items` 表 `exposureCount==5`；30 分钟内同题型重出 → 应答 `repeat_blocked`。
