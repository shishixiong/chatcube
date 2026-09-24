# english_quiz v2 五步英语教学闭环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `english_quiz` 从 3 题型升级为 6 mode（listen_choice / picture_word / phonics_blend / sentence_fill / read_aloud / letter_trace），配预校验、mode 子组件卡片、五步课提示词与 `english_reading` 画像维度。

**Architecture:** 单工具 + `mode` 枚举（不新增工具）。卡片侧把现有 900 行 `EnglishQuizCard` 重组为 `components/english/` 薄路由器 + 5 个 body 子组件（LegacyBody 原样搬运保历史会话）；校验侧在 `EnglishQuizValidation.ets` 加 `resolveQuizMode` + 按 mode 校验函数（纯函数 + hypium）。MessageBubble 挂载点除 import 路径外零改动；StarEventModels 零漂移。

**Tech Stack:** ArkTS (HarmonyOS API 23, @ComponentV2/@Local/@Param/@Event/@Monitor), hypium 单测, 既有 ImageIndexService/TTS/ASR 服务。

**Spec:** `docs/superpowers/specs/2026-09-24-english-quiz-v2-design.md`（执行者必须同时读 spec 与本 plan；spec §4/§5/§9 含契约矩阵与提示词全文）

## Global Constraints

- ArkTS 严格模式：`arr.map(p => ({...}))` 内联对象字面量必须显式标注返回类型（10605038）；ForEach 回调体内**不能**写 `const x: Foo = {...}` 声明（10905209）——抽成返回已构造对象的方法；不允许 `const [a, b] = ...` 解构（10605074）。
- `@Local` 的 `Map` 修改后必须整体重赋值才触发响应式。
- `@Builder` 函数体内不允许 `const` 声明与 `return`。
- `Row.alignItems` 用 `VerticalAlign`，`Column.alignItems` 用 `HorizontalAlign`。
- JSON-in-template-literal 陷阱：schema description 字符串里**禁止 ASCII 双引号**，用「」或单引号；schema 改完必须 `node -e` 提取并 `JSON.parse` 验证（相应任务已含该步骤）。
- CLI `hvigorw test` 不可用（脚手架不匹配，见 MEMORY.md）——hypium 测试在 DevEco Studio 右键测试文件运行；任务内验证 = 编译通过，最终验证 = 干净 `assembleHap`。
- 构建命令：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
- 不新增 npm 依赖；不修改 `models/StarEventModels.ets`、`services/StarRewardService.ets`、`components/PictureVocabCard.ets`、`components/ListeningQuizCard.ets`、`services/SpeechRecognitionService.ets`。
- 测试文件不注册进 `List.test.ets`（沿用 `EnglishQuizValidation.test.ets` 现状：DevEco Studio 右键运行）。

## Review Focus

执行前通读；每条都已在对应任务里落了测试或验收步骤。

1. **legacy 容错行为回退**：`question_type` 缺省/未知值历史上按 `word` 处理（parseQuiz 同款）。新 `resolveQuizMode` 必须保留该容错——只有 mode 与 question_type **都为空**才 fail。Task 2 测试覆盖。
2. **options 大小写匹配**：AI 可能给 `correct_answer: 'Apple'` 而 options 里是 `'apple'`。4-choice 正确性判定与「options 含 correct_answer」校验都必须大小写不敏感。Task 3 测试覆盖。
3. **read_aloud 转写噪声**：ASR 常在目标句前后粘词（"Well, I like apples"）。归一化匹配必须接受子串包含。Task 1 测试覆盖。
4. **历史 answered payload 无 `mode` 字段**：路由器必须按 args（而非 payload）解析 mode，且解析失败一律回落 LegacyBody。Task 11 步骤覆盖。
5. **handler 注入 image_path 失败的 picture_word**：卡片不得卡死 loading——QuizImageResolver 三层兜底 + 120s 超时失败态必须保留（从现有卡搬运）。Task 5/7 覆盖。

---

### Task 1: ReadAloudMatcher 纯函数（read_aloud 评分）

**Files:**
- Create: `entry/src/main/ets/utils/ReadAloudMatcher.ets`
- Test: `entry/src/ohosTest/ets/test/utils/ReadAloudMatcher.test.ets`

**Interfaces:**
- Produces: `normalizeEnglishText(raw: string): string`、`isReadAloudMatch(transcript: string, target: string): boolean`（Task 9 ReadAloudBody 消费）

- [ ] **Step 1: 写失败测试**

```typescript
// entry/src/ohosTest/ets/test/utils/ReadAloudMatcher.test.ets
import { describe, it, expect } from '@ohos/hypium'
import { normalizeEnglishText, isReadAloudMatch } from '../../../../main/ets/utils/ReadAloudMatcher'

/**
 * ReadAloudMatcher 单元测试
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */
export default function readAloudMatcherTest() {
  describe('normalizeEnglishText', () => {
    it('小写 + 去标点 + 折叠空格', 0, () => {
      expect(normalizeEnglishText('  I like Apples.  ')).assertEqual('i like apples')
    })
    it('撇号保留 (don\'t)', 0, () => {
      expect(normalizeEnglishText("Don't stop!")).assertEqual("don't stop")
    })
  })
  describe('isReadAloudMatch', () => {
    it('全等命中', 0, () => {
      expect(isReadAloudMatch('I like apples', 'I like apples.')).assertTrue()
    })
    it('大小写标点差异命中', 0, () => {
      expect(isReadAloudMatch('I LIKE APPLES!', 'I like apples')).assertTrue()
    })
    it('前后粘词 (子串包含) 命中', 0, () => {
      expect(isReadAloudMatch('Well, I like apples very much', 'I like apples')).assertTrue()
    })
    it('漏词不命中', 0, () => {
      expect(isReadAloudMatch('I like', 'I like apples')).assertFalse()
    })
    it('完全不同不命中', 0, () => {
      expect(isReadAloudMatch('red bus', 'I like apples')).assertFalse()
    })
    it('空串不命中', 0, () => {
      expect(isReadAloudMatch('', 'I like apples')).assertFalse()
      expect(isReadAloudMatch('I like apples', '')).assertFalse()
    })
  })
}
```

- [ ] **Step 2: 运行确认失败**——DevEco Studio 右键 `ReadAloudMatcher.test.ets` → Run；Expected: 编译失败（模块不存在）。无设备时可跳过运行，靠 Step 3 后再跑。
- [ ] **Step 3: 实现**

```typescript
// entry/src/main/ets/utils/ReadAloudMatcher.ets
/**
 * ReadAloudMatcher - english_quiz read_aloud 跟读评分纯逻辑层
 *
 * 归一化: 小写 → 非字母数字(保留撇号)替换为空格 → 折叠空格 → trim。
 * 命中: 归一化后全等, 或转写包含目标句(ASR 常在前后粘词, 如 "Well, I like apples")。
 * 设计见 docs/superpowers/specs/2026-09-24-english-quiz-v2-design.md §6.4。
 */

export function normalizeEnglishText(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9\s']/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

export function isReadAloudMatch(transcript: string, target: string): boolean {
  const said = normalizeEnglishText(transcript)
  const want = normalizeEnglishText(target)
  if (said === '' || want === '') {
    return false
  }
  return said === want || said.includes(want)
}
```

- [ ] **Step 4: 运行测试确认全过**（DevEco Studio 右键运行）。
- [ ] **Step 5: Commit** `git add entry/src/main/ets/utils/ReadAloudMatcher.ets entry/src/ohosTest/ets/test/utils/ReadAloudMatcher.test.ets && git commit -m "feat(english): ReadAloudMatcher 归一化跟读匹配纯函数"`

### Task 2: resolveQuizMode + 校验结果携带 mode

**Files:**
- Modify: `entry/src/main/ets/utils/EnglishQuizValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/EnglishQuizValidation.test.ets`（追加 describe 块）

**Interfaces:**
- Consumes: 现有 `validateEnglishQuizArgs(args: string): EnglishQuizValidationResult`
- Produces: `resolveQuizMode(parsed: Record<string, Object>): ResolvedQuizMode`；`EnglishQuizValidationResult` 增加字段 `mode: string`、`isLegacy: boolean`（Task 3 校验函数、Task 13 ToolExecutionService 消费）

**兼容铁律**：mode 合法 → 新路径；否则 question_type 非空 → legacy（**未知 question_type 值仍按现有行为视作 word**，parseQuiz 同款容错）；两者都空 → fail。现有 102 行校验逻辑行为一个字不改，只是搬进 `validateLegacyArgs` 私有函数并在 fail/pass 上补 mode/isLegacy 字段。

- [ ] **Step 1: 追加失败测试**（在 `EnglishQuizValidation.test.ets` 末尾 `}` 前插入；import 行补 `resolveQuizMode`）

```typescript
  describe('resolveQuizMode', () => {
    it('mode 合法 → 新路径', 0, () => {
      const r = resolveQuizMode(JSON.parse('{"mode":"read_aloud"}') as Record<string, Object>)
      expect(r.mode).assertEqual('read_aloud')
      expect(r.isLegacy).assertFalse()
    })
    it('mode 缺失 + question_type 合法 → legacy', 0, () => {
      const r = resolveQuizMode(JSON.parse('{"question_type":"phonics_choice"}') as Record<string, Object>)
      expect(r.mode).assertEqual('phonics_choice')
      expect(r.isLegacy).assertTrue()
    })
    it('mode 非法 + question_type 缺失 → 容错按 word (parseQuiz 同款)', 0, () => {
      const r = resolveQuizMode(JSON.parse('{"mode":"bogus"}') as Record<string, Object>)
      expect(r.mode).assertEqual('word')
      expect(r.isLegacy).assertTrue()
    })
    it('mode 与 question_type 都空 → mode 为空串 (校验层 fail)', 0, () => {
      const r = resolveQuizMode(JSON.parse('{}') as Record<string, Object>)
      expect(r.mode).assertEqual('')
    })
  })
  describe('validateEnglishQuizArgs - 结果携带 mode/isLegacy', () => {
    it('新 mode 合法题回填 mode + isLegacy=false', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: '听一听', correct_answer: 'cat',
        options: ['cat', 'cap', 'can', 'hat'], tts_text: 'cat'
      }))
      expect(r.ok).assertTrue()
      expect(r.mode).assertEqual('listen_choice')
      expect(r.isLegacy).assertFalse()
    })
    it('legacy word 题回填 question_type + isLegacy=true', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '苹果', image_prompt: 'an apple',
        correct_answer: 'apple', question_type: 'word'
      }))
      expect(r.ok).assertTrue()
      expect(r.mode).assertEqual('word')
      expect(r.isLegacy).assertTrue()
    })
    it('mode 与 question_type 都空 → 拒绝且提示 mode', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({ question: 'q', correct_answer: 'apple' }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('mode')).assertTrue()
    })
  })
```

- [ ] **Step 2: 实现 resolveQuizMode 并重构入口**（`EnglishQuizValidation.ets`）

接口与解析器加在文件头注释后；现有 `fail`/`pass` 改带 mode/isLegacy 参数；`validateEnglishQuizArgs` 改为：parse → resolveQuizMode → 空则 fail → isLegacy 则调抽出的 `validateLegacyArgs`（原 102 行逻辑原样搬入，行为不变）→ 否则 Task 3 的 switch 分派（本任务先临时统一 fail('...') 占位由 Task 3 替换——为避免中间态编译失败，本任务 switch 对 6 个新 mode 全部 `return fail('该 mode 校验将在后续任务实现', resolved.mode, false)`）。

```typescript
export interface EnglishQuizValidationResult {
  ok: boolean
  error: string
  mode: string      // 六个新 mode 之一, 或 legacy 'word'/'sentence'/'phonics_choice'; 解析失败为 ''
  isLegacy: boolean
}

export interface ResolvedQuizMode {
  mode: string
  isLegacy: boolean
}

const NEW_MODES: string[] = ['listen_choice', 'picture_word', 'phonics_blend', 'sentence_fill', 'read_aloud', 'letter_trace']
const LEGACY_TYPES: string[] = ['word', 'sentence', 'phonics_choice']

/**
 * 解析出题 mode:
 * - mode 字段合法 → 新契约路径
 * - 否则 question_type 非空 → legacy 路径 (未知值容错按 word, 与 parseQuiz 默认行为一致)
 * - 两者都空 → mode='' (调用方 fail)
 */
export function resolveQuizMode(parsed: Record<string, Object>): ResolvedQuizMode {
  const mode = ((parsed['mode'] as string) ?? '').trim()
  if (NEW_MODES.indexOf(mode) >= 0) {
    const r: ResolvedQuizMode = { mode: mode, isLegacy: false }
    return r
  }
  const legacyType = ((parsed['question_type'] as string) ?? '').trim()
  if (legacyType !== '') {
    const effective = LEGACY_TYPES.indexOf(legacyType) >= 0 ? legacyType : 'word'
    const r: ResolvedQuizMode = { mode: effective, isLegacy: true }
    return r
  }
  const r: ResolvedQuizMode = { mode: '', isLegacy: false }
  return r
}
```

`validateEnglishQuizArgs` 新结构（`validateLegacyArgs` 为原逻辑整体搬移，逐字保留）：

```typescript
export function validateEnglishQuizArgs(args: string): EnglishQuizValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('english_quiz 参数不是合法 JSON, 请检查后重新出题', '', false)
  }
  const resolved = resolveQuizMode(parsed)
  if (resolved.mode === '') {
    return fail('english_quiz 缺少 mode 字段 (listen_choice/picture_word/phonics_blend/sentence_fill/read_aloud/letter_trace 六选一); 历史兼容的 question_type 也不再接受空值', '', false)
  }
  if (resolved.isLegacy) {
    return validateLegacyArgs(parsed, resolved.mode)
  }
  switch (resolved.mode) {
    case 'listen_choice':
    case 'picture_word':
    case 'phonics_blend':
    case 'sentence_fill':
    case 'read_aloud':
    case 'letter_trace':
      return fail(`mode「${resolved.mode}」的校验规则将在后续任务实现`, resolved.mode, false)
    default:
      return fail(`未知的 mode「${resolved.mode}」`, '', false)
  }
}

function validateLegacyArgs(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  // ===== 原 validateEnglishQuizArgs 的 question_type 分支逻辑逐字搬入 =====
  // 原 fail(...)/pass() 调用点改为 fail(msg, mode, true) / pass(mode, true)
}
```

`fail`/`pass` 签名：

```typescript
function fail(msg: string, mode: string, isLegacy: boolean): EnglishQuizValidationResult {
  return { ok: false, error: msg, mode: mode, isLegacy: isLegacy }
}

function pass(mode: string, isLegacy: boolean): EnglishQuizValidationResult {
  return { ok: true, error: '', mode: mode, isLegacy: isLegacy }
}
```

- [ ] **Step 3: 跑新旧全部用例**——DevEco Studio 右键 `EnglishQuizValidation.test.ets`。Expected: 既有 legacy 用例 + 新 resolveQuizMode/结果字段用例全过；6 个新 mode 的占位 fail 不在本任务断言范围。
- [ ] **Step 4: Commit** `git commit -am "feat(english): resolveQuizMode + 校验结果携带 mode/isLegacy, legacy 逻辑零行为变化"`

### Task 3: 六个新 mode 的校验函数 + CVC 检查

**Files:**
- Modify: `entry/src/main/ets/utils/EnglishQuizValidation.ets`（替换 Task 2 的占位 switch）
- Test: `entry/src/ohosTest/ets/test/utils/EnglishQuizValidation.test.ets`（追加 describe 块）

**Interfaces:**
- Consumes: `resolveQuizMode`、`fail/pass`（Task 2）
- Produces: 私有 `validateOptions4(optionsRaw, correct, modeLabel): string`（'' = 通过）、`parseShortVowelRule(rule): string`（返回元音字母或 ''）、`validateLetterTrace(parsed, mode): EnglishQuizValidationResult`。对外仍只有 `validateEnglishQuizArgs`。

- [ ] **Step 1: 追加失败测试**

```typescript
  describe('listen_choice', () => {
    it('齐全合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: '听一听,选出你听到的单词', correct_answer: 'cat',
        options: ['cat', 'cap', 'can', 'hat'], tts_text: 'cat'
      }))
      expect(r.ok).assertTrue()
    })
    it('options 缺正确答案, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'cat',
        options: ['cap', 'can', 'hat', 'hop'], tts_text: 'cat'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('正确答案')).assertTrue()
    })
    it('options 重复项 (去重后 <4), 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'cat',
        options: ['cat', 'cat', 'can', 'hat'], tts_text: 'cat'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('重复')).assertTrue()
    })
    it('options 大小写不敏感含答案, 通过', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'Apple',
        options: ['apple', 'banana', 'orange', 'pear'], tts_text: 'apple'
      }))
      expect(r.ok).assertTrue()
    })
    it('tts_text 缺失, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'cat',
        options: ['cat', 'cap', 'can', 'hat']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('tts_text')).assertTrue()
    })
  })
  describe('picture_word', () => {
    it('齐全合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'picture_word', question: '看图选词', correct_answer: 'apple',
        options: ['apple', 'banana', 'orange', 'pear'],
        image_prompt: 'A bright red apple, children illustration style'
      }))
      expect(r.ok).assertTrue()
    })
    it('image_prompt 缺失, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'picture_word', question: 'q', correct_answer: 'apple',
        options: ['apple', 'banana', 'orange', 'pear']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('image_prompt')).assertTrue()
    })
  })
  describe('phonics_blend', () => {
    it('short a 规则全 CVC 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: '拼一拼', correct_answer: 'cat',
        options: ['cat', 'ham', 'map', 'bat'], phonics_rule: 'short a'
      }))
      expect(r.ok).assertTrue()
    })
    it('correct_answer 不符合 short a (r-controlled car), 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'car',
        options: ['car', 'ham', 'map', 'bat'], phonics_rule: 'short a'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('phonics_rule')).assertTrue()
    })
    it('干扰项违反规则, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'cat',
        options: ['cat', 'ham', 'map', 'bed'], phonics_rule: 'short a'
      }))
      expect(r.ok).assertFalse()
    })
    it('不可解析的规则 (如 long vowel / digraph) 仅放行', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'rain',
        options: ['rain', 'pain', 'main', 'train'], phonics_rule: 'long a (ai)'
      }))
      expect(r.ok).assertTrue()
    })
    it('phonics_rule 缺失, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'cat',
        options: ['cat', 'ham', 'map', 'bat']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('phonics_rule')).assertTrue()
    })
  })
  describe('sentence_fill', () => {
    it('恰一个空合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'sentence_fill', question: '选词填空', correct_answer: 'apples',
        options: ['apples', 'banana', 'milk', 'eggs'], pattern: 'I like ___.'
      }))
      expect(r.ok).assertTrue()
    })
    it('0 个空, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'sentence_fill', question: 'q', correct_answer: 'apples',
        options: ['apples', 'banana', 'milk', 'eggs'], pattern: 'I like apples.'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('___')).assertTrue()
    })
    it('2 个空, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'sentence_fill', question: 'q', correct_answer: 'apples',
        options: ['apples', 'banana', 'milk', 'eggs'], pattern: '___ and ___.'
      }))
      expect(r.ok).assertFalse()
    })
  })
  describe('read_aloud', () => {
    it('短句合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'read_aloud', question: '跟我读', correct_answer: 'I like apples',
        target_text: 'I like apples', phonetic_hint: 'th → this'
      }))
      expect(r.ok).assertTrue()
    })
    it('超 8 词, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'read_aloud', question: 'q', correct_answer: 'a b c d e f g h i',
        target_text: 'a b c d e f g h i'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('8')).assertTrue()
    })
  })
  describe('letter_trace', () => {
    it('upper 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: '描一描', correct_answer: 'A',
        letter: 'A', 'case': 'upper'
      }))
      expect(r.ok).assertTrue()
    })
    it('lower 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: 'q', correct_answer: 'a', letter: 'a', 'case': 'lower'
      }))
      expect(r.ok).assertTrue()
    })
    it('letter 非单字符, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: 'q', correct_answer: 'ab', letter: 'ab', 'case': 'upper'
      }))
      expect(r.ok).assertFalse()
    })
    it('case 非法值, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: 'q', correct_answer: 'a', letter: 'a', 'case': 'both'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('case')).assertTrue()
    })
  })
```

（JSON 里 `case` 是合法键名，`buildArgs({... 'case': 'upper'})` 用引号键即可。）

- [ ] **Step 2: 实现校验函数**（`EnglishQuizValidation.ets`；把 Task 2 的占位 switch 替换为真实分派）

```typescript
const VOWELS: string[] = ['a', 'e', 'i', 'o', 'u']

function readString(parsed: Record<string, Object>, key: string): string {
  return ((parsed[key] as string) ?? '').trim()
}

/**
 * 校验 options: 恰 4 个非空字符串, 去重后仍 4, 大小写不敏感含 correct。
 * 返回 '' = 通过; 否则返回写给 LLM 的错误信息。
 */
function validateOptions4(optionsRaw: Object | undefined, correct: string, modeLabel: string): string {
  if (!Array.isArray(optionsRaw)) {
    return `${modeLabel} 题缺少 options (恰好 4 个英文选项, 必须包含 correct_answer)`
  }
  const arr = optionsRaw as Object[]
  if (arr.length !== 4) {
    return `${modeLabel} 题 options 必须恰好 4 个 (当前 ${arr.length} 个)`
  }
  const seen: Set<string> = new Set()
  const lower: string[] = []
  for (let i = 0; i < arr.length; i++) {
    const s = typeof arr[i] === 'string' ? (arr[i] as string).trim() : ''
    if (s === '') {
      return `${modeLabel} 题 options 含空项, 请补全后重新出题`
    }
    const k = s.toLowerCase()
    if (seen.has(k)) {
      return `${modeLabel} 题 options 有重复项「${s}」, 4 个选项必须互不相同`
    }
    seen.add(k)
    lower.push(k)
  }
  const correctLower = correct.toLowerCase()
  if (lower.indexOf(correctLower) < 0) {
    return `${modeLabel} 题 options 里没有正确答案「${correct}」, 请把它放进选项后重新出题`
  }
  return ''
}

/**
 * 解析 short 元音规则 (如 "short a") → 返回元音字母; 不可解析返回 '' (调用方仅警告不拦)。
 */
function parseShortVowelRule(rule: string): string {
  const parts = rule.toLowerCase().trim().split(/\s+/)
  if (parts.length === 2 && parts[0] === 'short' && VOWELS.indexOf(parts[1]) >= 0) {
    return parts[1]
  }
  return ''
}

/** CVC 结构且元音位 == vowel (如 short a → cat ✓, car ✗) */
function isCvcWithVowel(word: string, vowel: string): boolean {
  const w = word.toLowerCase().trim()
  if (w.length !== 3) {
    return false
  }
  return w[1] === vowel && VOWELS.indexOf(w[0]) < 0 && VOWELS.indexOf(w[2]) < 0
}

function validateListenChoice(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('listen_choice 题缺少 correct_answer (听到的那个词)', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'listen_choice')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  if (readString(parsed, 'tts_text') === '') {
    return fail('listen_choice 题缺少 tts_text (TTS 要朗读的英文词), 没有它小朋友听不到题目, 请补上后重新出题', mode, false)
  }
  return pass(mode, false)
}

function validatePictureWord(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('picture_word 题缺少 correct_answer (图对应的词)', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'picture_word')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  if (readString(parsed, 'image_prompt') === '') {
    return fail('picture_word 题缺少 image_prompt — 没有图片描述卡片无法出图, 请补上后重新出题', mode, false)
  }
  return pass(mode, false)
}

function validatePhonicsBlend(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('phonics_blend 题缺少 correct_answer', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'phonics_blend')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  const rule = readString(parsed, 'phonics_rule')
  if (rule === '') {
    return fail('phonics_blend 题缺少 phonics_rule (如「short a」), 请声明拼读规则后重新出题', mode, false)
  }
  const vowel = parseShortVowelRule(rule)
  if (vowel !== '') {
    // 可解析的 short 元音规则: correct_answer 与全部选项都必须是该元音的 CVC 词
    if (!isCvcWithVowel(correct, vowel)) {
      return fail(`phonics_blend 题的 correct_answer「${correct}」不符合 phonics_rule「${rule}」(需为 3 字母辅-元-辅且元音是 ${vowel}); 严禁混入违反规则的词 (如 r-controlled 的 car), 请重新出题`, mode, false)
    }
    const arr = parsed['options'] as Object[]
    for (let i = 0; i < arr.length; i++) {
      const s = (arr[i] as string).trim()
      if (!isCvcWithVowel(s, vowel)) {
        return fail(`phonics_blend 题的选项「${s}」不符合 phonics_rule「${rule}」, 4 个选项都必须是 ${vowel} 的短元音 CVC 词, 请重新出题`, mode, false)
      }
    }
  } else {
    console.warn('EnglishQuizValidation', `phonics_blend rule not parseable, skip structure check: "${rule}"`)
  }
  return pass(mode, false)
}

function validateSentenceFill(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('sentence_fill 题缺少 correct_answer (空格处的词)', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'sentence_fill')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  const pattern = readString(parsed, 'pattern')
  const blanks = pattern === '' ? 0 : pattern.split('___').length - 1
  if (pattern === '' || blanks !== 1) {
    return fail(`sentence_fill 题的 pattern 必须恰好含一个 ___ 空格 (当前 ${blanks} 个), 如「I like ___.」; 严禁 0 个或多个空, 请修正后重新出题`, mode, false)
  }
  return pass(mode, false)
}

function validateReadAloud(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const target = readString(parsed, 'target_text')
  if (target === '') {
    return fail('read_aloud 题缺少 target_text (孩子要跟读的目标句)', mode, false)
  }
  const words = target.split(/\s+/).filter((w: string): boolean => w.length > 0)
  if (words.length > 8) {
    return fail(`read_aloud 题的 target_text 共 ${words.length} 个词, 上限 8 词 (level 0-1→3 词, 2-3→5 词, 4-5→8 词), 请缩短后重新出题`, mode, false)
  }
  return pass(mode, false)
}

function validateLetterTrace(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const letter = readString(parsed, 'letter')
  const isSingleAsciiLetter = letter.length === 1 &&
    ((letter >= 'a' && letter <= 'z') || (letter >= 'A' && letter <= 'Z'))
  if (!isSingleAsciiLetter) {
    return fail(`letter_trace 题的 letter「${letter}」必须是单个英文字母 (a-z 或 A-Z)`, mode, false)
  }
  const letterCase = readString(parsed, 'case')
  if (letterCase !== 'upper' && letterCase !== 'lower') {
    return fail(`letter_trace 题的 case 必须是「upper」或「lower」(当前「${letterCase}」)`, mode, false)
  }
  return pass(mode, false)
}
```

Task 2 的 switch 占位替换为：

```typescript
  switch (resolved.mode) {
    case 'listen_choice':
      return validateListenChoice(parsed, resolved.mode)
    case 'picture_word':
      return validatePictureWord(parsed, resolved.mode)
    case 'phonics_blend':
      return validatePhonicsBlend(parsed, resolved.mode)
    case 'sentence_fill':
      return validateSentenceFill(parsed, resolved.mode)
    case 'read_aloud':
      return validateReadAloud(parsed, resolved.mode)
    case 'letter_trace':
      return validateLetterTrace(parsed, resolved.mode)
    default:
      return fail(`未知的 mode「${resolved.mode}」`, '', false)
  }
```

- [ ] **Step 3: 跑全部用例**（DevEco Studio）。Expected: 全过（含 Task 2 legacy 回归）。
- [ ] **Step 4: Commit** `git commit -am "feat(english): english_quiz 六 mode 出题预校验 (options 唯一性/phonics CVC/句型空格/跟读长度)"`

### Task 4: components/english/ModeTypes.ets（mode 解析 + 显示名 + 默认 skill_key）

**Files:**
- Create: `entry/src/main/ets/components/english/ModeTypes.ets`

**Interfaces:**
- Consumes: `resolveQuizMode`（Task 2）
- Produces: `EnglishQuizMode` 类型、`EnglishQuizModeArgs` 接口、`parseEnglishQuizModeArgs(argsJson: string): EnglishQuizModeArgs`、`defaultSkillKeyForMode(mode: EnglishQuizMode): string`、`modeDisplayName(mode: EnglishQuizMode): string`（Task 6-11 全部 body 与路由器消费）；payload 接口 `EnglishQuizAnswerPayload`（v2，含可选 mode/stage/pattern/target_text/completed）

- [ ] **Step 1: 实现**

```typescript
// entry/src/main/ets/components/english/ModeTypes.ets
/**
 * ModeTypes - english_quiz v2 六 mode 的类型、参数解析与展示映射
 *
 * 路由器 (EnglishQuizCard) 用 parseEnglishQuizModeArgs 决定渲染哪个 body;
 * 各 body 再用同一份解析结果取自己的字段, 保证解析只有一处。
 * 纯逻辑 (无 ArkUI 依赖), resolveQuizMode 复用 utils/EnglishQuizValidation。
 * 设计见 docs/superpowers/specs/2026-09-24-english-quiz-v2-design.md §6。
 */

import { resolveQuizMode } from '../../utils/EnglishQuizValidation'

export type EnglishQuizMode =
  | 'listen_choice' | 'picture_word' | 'phonics_blend'
  | 'sentence_fill' | 'read_aloud' | 'letter_trace' | 'legacy'

/** answer payload v2: 现有字段全保留 (ToolExecutionService/AI 契约不动), 新增字段全部可选 */
export interface EnglishQuizAnswerPayload {
  answered: boolean
  child_answer: string
  correct: boolean
  correct_answer: string
  word: string
  sentence: string
  question_type: string        // 新 mode 回包统一回填 mode 本身 (消费方仅 legacy 分支判 'phonics_choice')
  skill_key: string
  letter_options?: string[]
  sound_text?: string
  mode?: string
  stage?: string
  pattern?: string
  target_text?: string
  completed?: boolean          // letter_trace 置 true
}

export interface EnglishQuizModeArgs {
  mode: EnglishQuizMode
  question: string
  correctAnswer: string
  options: string[]
  imagePath: string            // handleEnglishQuiz 注入的 image_path (可能为 '')
  imagePrompt: string
  phonicsRule: string
  pattern: string
  ttsText: string
  targetText: string
  phoneticHint: string
  letter: string
  letterCase: string
  skillKey: string
  difficulty: number
  stage: string
  theme: string
  legacyQuestionType: string   // legacy 三题型原值 ('word'/'sentence'/'phonics_choice')
  legacyLetterOptions: string[]
  legacySoundText: string
}

/** AI 未传 skill_key 时的默认映射 (spec §8.2) */
export function defaultSkillKeyForMode(mode: EnglishQuizMode): string {
  switch (mode) {
    case 'listen_choice': return 'english_alphabet'
    case 'picture_word': return 'english_vocab'
    case 'phonics_blend': return 'english_phonics'
    case 'sentence_fill': return 'english_sentence'
    case 'read_aloud': return 'english_reading'
    case 'letter_trace': return 'english_writing'
    default: return 'english_vocab'   // legacy 默认, 与原 parseQuiz 一致
  }
}

export function modeDisplayName(mode: EnglishQuizMode): string {
  switch (mode) {
    case 'listen_choice': return '听音选词'
    case 'picture_word': return '看图选词'
    case 'phonics_blend': return '自然拼读'
    case 'sentence_fill': return '句型填空'
    case 'read_aloud': return '跟我读'
    case 'letter_trace': return '字母描红'
    default: return '英语小游戏'
  }
}

/**
 * 解析 toolCall.arguments → ModeArgs。
 * 解析失败 / mode 与 question_type 都缺 → mode='legacy' (路由器回落 LegacyBody, 最安全)。
 */
export function parseEnglishQuizModeArgs(argsJson: string): EnglishQuizModeArgs {
  const empty: EnglishQuizModeArgs = {
    mode: 'legacy', question: '', correctAnswer: '', options: [],
    imagePath: '', imagePrompt: '', phonicsRule: '', pattern: '',
    ttsText: '', targetText: '', phoneticHint: '', letter: '', letterCase: '',
    skillKey: 'english_vocab', difficulty: 1, stage: '', theme: '',
    legacyQuestionType: 'word', legacyLetterOptions: [], legacySoundText: ''
  }
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(argsJson) as Record<string, Object>
  } catch (_e) {
    return empty
  }
  const resolved = resolveQuizMode(parsed)
  const result: EnglishQuizModeArgs = {
    mode: 'legacy',
    question: ((parsed['question'] as string) ?? '').trim(),
    correctAnswer: ((parsed['correct_answer'] as string) ?? '').trim(),
    options: [],
    imagePath: ((parsed['image_path'] as string) ?? '').trim(),
    imagePrompt: ((parsed['image_prompt'] as string) ?? '').trim(),
    phonicsRule: ((parsed['phonics_rule'] as string) ?? '').trim(),
    pattern: ((parsed['pattern'] as string) ?? '').trim(),
    ttsText: ((parsed['tts_text'] as string) ?? '').trim(),
    targetText: ((parsed['target_text'] as string) ?? '').trim(),
    phoneticHint: ((parsed['phonetic_hint'] as string) ?? '').trim(),
    letter: ((parsed['letter'] as string) ?? '').trim(),
    letterCase: ((parsed['case'] as string) ?? '').trim(),
    skillKey: ((parsed['skill_key'] as string) ?? '').trim(),
    difficulty: (parsed['difficulty'] as number) ?? 1,
    stage: ((parsed['stage'] as string) ?? '').trim(),
    theme: ((parsed['theme'] as string) ?? '').trim(),
    legacyQuestionType: resolved.isLegacy ? resolved.mode : '',
    legacyLetterOptions: [],
    legacySoundText: ((parsed['sound_text'] as string) ?? '').trim()
  }
  if (resolved.isLegacy) {
    result.mode = 'legacy'
    result.skillKey = result.skillKey !== '' ? result.skillKey : 'english_vocab'
    const rawLetters = parsed['letter_options']
    if (Array.isArray(rawLetters)) {
      const arr = rawLetters as Object[]
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string') {
          result.legacyLetterOptions.push(arr[i] as string)
        }
      }
    }
    return result
  }
  // 新 mode
  const modeValue = resolved.mode as EnglishQuizMode
  result.mode = modeValue
  result.skillKey = result.skillKey !== '' ? result.skillKey : defaultSkillKeyForMode(modeValue)
  const rawOptions = parsed['options']
  if (Array.isArray(rawOptions)) {
    const arr = rawOptions as Object[]
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'string') {
        result.options.push((arr[i] as string).trim())
      }
    }
  }
  return result
}
```

- [ ] **Step 2: 编译验证**——运行 assembleHap（见 Global Constraints 命令）。Expected: 编译通过（新文件尚无调用方）。
- [ ] **Step 3: Commit** `git commit -am "feat(english): ModeTypes 六 mode 解析/展示/默认 skill_key + answer payload v2"`

### Task 5: QuizImageResolver（三层图片解析抽为纯异步函数）

**Files:**
- Create: `entry/src/main/ets/components/english/QuizImageResolver.ets`

**Interfaces:**
- Consumes: `getImageIndexService()`、`ImageIndexService.buildEnglishQuizKey`、`ImageSource`（既有服务）
- Produces: `resolveQuizImagePath(word: string, sentence: string, imagePrompt: string): Promise<string>`（返回沙箱路径；失败/无输入返回 ''。Task 6 LegacyBody、Task 7 ChoiceModeBody 消费）

- [ ] **Step 1: 实现**（逻辑逐字对应现 `EnglishQuizCard.resolveImage` 的 Tier1→Tier2→Tier3，仅改为纯异步返回值风格）

```typescript
// entry/src/main/ets/components/english/QuizImageResolver.ets
/**
 * QuizImageResolver - english_quiz 图片三层解析纯异步函数
 * (自原 EnglishQuizCard.resolveImage 抽出; 卡片侧只负责 loading 态/120s 超时/file:// 转换)
 *
 * Tier 1: ENGLISH_QUIZ 本地缓存 (含历史现生图 + 写回的备课图)
 * Tier 2: LESSON_PLAN 备课预生成图 (仅单词题有干净映射, 命中后写回 Tier1 + markConsumed)
 * Tier 3: generateAndStore 现生图兜底
 *
 * 任何一步失败都静默降级到下一层, 全失败返回 ''。
 */

import { getImageIndexService, ImageIndexService } from '../../services/ImageIndexService'
import { ImageSource } from '../../models/ImageIndexModels'

export async function resolveQuizImagePath(word: string, sentence: string, imagePrompt: string): Promise<string> {
  if (word === '' && sentence === '' && imagePrompt === '') {
    return ''
  }
  const imageIndex = getImageIndexService()
  const quizKey = ImageIndexService.buildEnglishQuizKey(word, sentence)
  try {
    // Tier 1: 英语题本地缓存
    const hit = await imageIndex.findByKey(ImageSource.ENGLISH_QUIZ, quizKey)
    if (hit !== null && hit.filePath !== '') {
      return hit.filePath
    }
    // Tier 2: 备课预生成图 (仅单词题)
    const isWordQuiz = sentence === '' && word !== ''
    if (isWordQuiz && imagePrompt !== '') {
      const topicKey = `vocab.${word.toLowerCase().trim()}`
      try {
        const planHit = await imageIndex.findByKey(ImageSource.LESSON_PLAN, topicKey)
        if (planHit !== null && planHit.filePath !== '') {
          // 写回 Tier1 + 标记消费 (best-effort; 失败不影响返回路径)
          try {
            await imageIndex.putEntry(ImageSource.ENGLISH_QUIZ, quizKey, planHit.filePath,
              planHit.prompt !== '' ? planHit.prompt : imagePrompt,
              planHit.mimeType,
              { revisedPrompt: planHit.revisedPrompt })
            imageIndex.markConsumed(planHit.id).catch((_e: Error) => {})
          } catch (_e) {}
          return planHit.filePath
        }
      } catch (_e) {}
    }
    // Tier 3: 现生图
    if (imagePrompt !== '') {
      const gen = await imageIndex.generateAndStore(ImageSource.ENGLISH_QUIZ, quizKey, imagePrompt)
      if (gen !== null) {
        return gen.filePath
      }
    }
    return ''
  } catch (_e) {
    return ''
  }
}
```

- [ ] **Step 2: 编译验证**（assembleHap）。Expected: 通过。
- [ ] **Step 3: Commit** `git commit -am "refactor(english): 图片三层解析抽为 QuizImageResolver 纯异步函数"`

### Task 6: LegacyBody（现有卡片 UI 原样搬运）

**Files:**
- Create: `entry/src/main/ets/components/english/bodies/LegacyBody.ets`
- （不删旧文件——Task 11 删除）

**Interfaces:**
- Consumes: `EnglishQuizAnswerPayload`（Task 4）、`resolveQuizImagePath`（Task 5）、既有 CardShell/CardShellState/CardShellCopy、SpeechRecognitionService、ServiceRegistry
- Produces: `LegacyBody` @ComponentV2——签名 `@Param toolCall: ToolCall`、`@Param isAnswered: boolean`、`@Param answeredPayload: string`、`@Param largeSize: boolean`、`@Event onAnswer: (toolCallId: string, answerJson: string) => void`（Task 11 路由器消费；四个 body 统一同签名）

**搬运铁律：本任务是把 `components/EnglishQuizCard.ets` 的交互逻辑整体搬家，除下面列出的 3 处机械调整外，渲染、状态机、判定逻辑一个字不改——历史会话渲染零风险全押在这里。**

- [ ] **Step 1: 创建 LegacyBody.ets，按下表搬移**

从 `components/EnglishQuizCard.ets`（900 行）原样复制以下成员（行号为现文件位置，复制时保持实现不变）：

| 成员 | 原行号 | 说明 |
|---|---|---|
| `interface EnglishQuizQuestion` | 25-36 | 文件级 interface 原样带走 |
| `@Local inputText/showResult/isCorrect/correctAnswerText/isRecording/recognitionPreview/voicePermissionDenied/wasCancelled/resolvedImagePath/displayImagePath/isImageLoading/imageLoadFailed/letterOptions/soundText` | 58-78 | 全部照搬 |
| `private imageLoadTimer` | 79 | 照搬 |
| `shellConfig` 初始值 + `shellState` | 81-91 | 照搬 |
| `themePrimary`/`isDarkMode` getter | 93-99 | 照搬 |
| `aboutToAppear`（含 isAnswered 恢复 + shellConfig 重建 + phonics 早退 + resolveImage 调用） | 101-146 | 照搬；仅 Step 2 的调整 2 |
| `@Monitor('toolCall.arguments') onArgumentsChanged` | 153-167 | 照搬 |
| `aboutToDisappear`（timer 清理 + TTS stop） | 169-181 | 照搬 |
| `toFileUrl` | 186-195 | 照搬 |
| `resolveImage` | 206-314 | **替换**为 Step 2 的调整 3 版本 |
| `parseQuiz` | 316-357 | 照搬 |
| `parsePreviousAnswer` | 359-368 | 照搬（返回类型用 Task 4 的 `EnglishQuizAnswerPayload`，见调整 1） |
| `checkAnswer`/`softWordEqual`/`levenshteinDistance` | 377-478 | 照搬 |
| `handleSubmit`/`handleRetry`/`handleLetterSelect`/`handlePlaySound` | 480-588 | 照搬 |
| `handleVoiceRecordStart/Finish/Cancel` | 590-653 | 照搬 |
| `getCardBackgroundColor` | 655-657 | 照搬 |
| `build` + `QuizContent`/`InputArea`/`PhonicsContent`/`LetterOptionsGrid` @Builder | 659-899 | 照搬 |

**3 处机械调整**：

1. **类型引用**：删除文件内 `EnglishQuizAnswerPayload` interface（原 38-49 行），改为 `import { EnglishQuizAnswerPayload } from '../ModeTypes'`。`EnglishQuizQuestion` 保留在文件内（legacy 专用）。
2. **组件名与外壳标题**：struct 改名 `LegacyBody`；`shellConfig.title` 保持原逻辑（`quiz.questionType === 'phonics_choice' ? '自然拼读' : '英语小游戏'`）不变。
3. **resolveImage 内部替换**：Tier1/2/3 链路换成 `QuizImageResolver` 调用（入参 image_path 注入检查与 120s 超时保留在组件内）：

```typescript
  private resolveImage(): void {
    const quiz = this.parseQuiz()

    // 已有 image_path (由 handleEnglishQuiz 注入)
    if (quiz.imagePath !== '') {
      this.resolvedImagePath = quiz.imagePath
      this.displayImagePath = quiz.imagePath
      return
    }
    if (quiz.word === '' && quiz.sentence === '' && quiz.imagePrompt === '') {
      return
    }

    this.isImageLoading = true
    const word = quiz.word
    const sentence = quiz.sentence
    const imagePrompt = quiz.imagePrompt

    // 120s 超时兜底 (防御性保留; 正常路径 handler 已同步注入)
    this.imageLoadTimer = setTimeout(() => {
      if (this.isImageLoading && this.resolvedImagePath === '') {
        this.isImageLoading = false
        this.imageLoadFailed = true
      }
    }, 120000)

    resolveQuizImagePath(word, sentence, imagePrompt).then((filePath: string) => {
      if (filePath !== '') {
        this.resolvedImagePath = filePath
        this.displayImagePath = filePath
      } else {
        this.imageLoadFailed = true
      }
      this.isImageLoading = false
      if (this.imageLoadTimer >= 0) {
        clearTimeout(this.imageLoadTimer)
        this.imageLoadTimer = -1
      }
    })
  }
```

（import 补 `import { resolveQuizImagePath } from '../QuizImageResolver'`；相对路径按 bodies/ 子目录。）

- [ ] **Step 2: 编译验证**（assembleHap；LegacyBody 尚无调用方，仅验证编译）。Expected: 通过。
- [ ] **Step 3: Commit** `git commit -am "refactor(english): LegacyBody 原样搬运现有 english_quiz 卡片交互 (free-input + phonics_choice)"`

### Task 7: ChoiceModeBody（listen_choice / picture_word / phonics_blend 共用）

**Files:**
- Create: `entry/src/main/ets/components/english/bodies/ChoiceModeBody.ets`

**Interfaces:**
- Consumes: Task 4 ModeTypes、Task 5 QuizImageResolver、CardShell 族、ServiceRegistry.tts()
- Produces: `ChoiceModeBody`（签名同 Task 6 四 Param + onAnswer）

**交互设计**：listen_choice / phonics_blend 渲染大听音按钮（🔊 点一下 TTS 朗读——listen_choice 读 `tts_text`，phonics_blend 读 `tts_text` 缺省时的 `correct_answer`）；picture_word 渲染图片区（复用 loading/失败四态）不渲染听音钮；三者共用 2×2 单词选项网格；点选项即判即交（直提路径，同现卡 `handleLetterSelect` 模式：同步 shellState.hasSelection/submitted/isCorrect，不再走确认按钮）。

- [ ] **Step 1: 实现**

```typescript
// entry/src/main/ets/components/english/bodies/ChoiceModeBody.ets
/**
 * ChoiceModeBody - english_quiz v2 三种 4 选 1 mode 的共用 body
 * listen_choice: TTS 朗读 → 选听到的词 (需要 tts_text)
 * picture_word:  看图 → 选对应的词 (需要 image_prompt, 渲染图片区)
 * phonics_blend: TTS 朗读 → 选符合 phonics_rule 的词 (tts_text 缺省朗读 correct_answer)
 * 点选项即判即交; 授星走 english_quiz 既有分支 (correct=true → 1 星)。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig, CardShellCopy } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { ServiceRegistry } from '../../../services/ServiceRegistry'
import { common } from '@kit.AbilityKit'
import {
  EnglishQuizAnswerPayload, EnglishQuizMode, EnglishQuizModeArgs, modeDisplayName,
  parseEnglishQuizModeArgs
} from '../ModeTypes'
import { resolveQuizImagePath } from '../QuizImageResolver'

@ComponentV2
export struct ChoiceModeBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local mode: EnglishQuizMode = 'listen_choice'
  @Local question: string = ''
  @Local options: string[] = []
  @Local correctAnswer: string = ''
  @Local speakText: string = ''
  @Local showImage: boolean = false
  @Local displayImagePath: string = ''
  @Local isImageLoading: boolean = false
  @Local imageLoadFailed: boolean = false
  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local isPlayingSound: boolean = false
  @Local skillKey: string = 'english_vocab'
  @Local stage: string = ''
  private imageLoadTimer: number = -1
  private shellConfig: CardShellConfig = {
    title: '听音选词', subtitle: '', icon: $r('sys.symbol.speaker_wave_2_fill'),
    stem: '', hasAudio: false, usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    const args: EnglishQuizModeArgs = parseEnglishQuizModeArgs(this.toolCall.arguments)
    this.mode = args.mode
    this.question = args.question
    this.options = args.options
    this.correctAnswer = args.correctAnswer
    this.skillKey = args.skillKey
    this.stage = args.stage
    this.speakText = args.ttsText !== '' ? args.ttsText : args.correctAnswer
    this.showImage = args.mode === 'picture_word'
    this.shellConfig = {
      title: modeDisplayName(args.mode), subtitle: args.theme !== '' ? `主题 · ${args.theme}` : '',
      icon: this.showImage ? $r('sys.symbol.picture') : $r('sys.symbol.speaker_wave_2_fill'),
      stem: '', hasAudio: false, usesConfirm: true,
      feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
    }
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.selectedOption = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.hasSelection = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    } else if (this.showImage) {
      this.resolveImage()
    }
  }

  aboutToDisappear(): void {
    if (this.imageLoadTimer >= 0) {
      clearTimeout(this.imageLoadTimer)
      this.imageLoadTimer = -1
    }
    if (this.isPlayingSound) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {}
      this.isPlayingSound = false
    }
  }

  // handleEnglishQuiz 异步注入 image_path 时主动刷新 (原卡 @Monitor 同款)
  @Monitor('toolCall.arguments')
  onArgumentsChanged(): void {
    if (this.isAnswered || !this.showImage) {
      return
    }
    const args = parseEnglishQuizModeArgs(this.toolCall.arguments)
    if (args.imagePath !== '' && args.imagePath !== this.displayImagePath) {
      this.displayImagePath = args.imagePath
      this.isImageLoading = false
    }
  }

  private parsePreviousAnswer(): EnglishQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as EnglishQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  private toFileUrl(path: string): string {
    if (path === '') {
      return ''
    }
    if (path.startsWith('file://') || path.startsWith('data:') ||
        path.startsWith('http://') || path.startsWith('https://')) {
      return path
    }
    return 'file://' + path
  }

  private resolveImage(): void {
    const args = parseEnglishQuizModeArgs(this.toolCall.arguments)
    if (args.imagePath !== '') {
      this.displayImagePath = args.imagePath
      return
    }
    this.isImageLoading = true
    this.imageLoadTimer = setTimeout(() => {
      if (this.isImageLoading && this.displayImagePath === '') {
        this.isImageLoading = false
        this.imageLoadFailed = true
      }
    }, 120000)
    resolveQuizImagePath(args.correctAnswer, '', args.imagePrompt).then((filePath: string) => {
      if (filePath !== '') {
        this.displayImagePath = filePath
      } else {
        this.imageLoadFailed = true
      }
      this.isImageLoading = false
      if (this.imageLoadTimer >= 0) {
        clearTimeout(this.imageLoadTimer)
        this.imageLoadTimer = -1
      }
    })
  }

  private handlePlaySound(): void {
    if (this.speakText === '' || this.isPlayingSound) {
      return
    }
    this.isPlayingSound = true
    ServiceRegistry.tts().speak(this.speakText, {
      onStart: () => {},
      onComplete: () => {
        this.isPlayingSound = false
      },
      onError: (error: string) => {
        this.isPlayingSound = false
        console.error('ChoiceModeBody', `TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      this.isPlayingSound = false
      console.error('ChoiceModeBody', `TTS speak failed: ${e.message}`)
    })
  }

  private handleOptionSelect(option: string): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    const correct = option.trim().toLowerCase() === this.correctAnswer.trim().toLowerCase()
    this.selectedOption = option
    this.showResult = true
    this.isCorrect = correct
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct

    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: option,
      correct: correct,
      correct_answer: this.correctAnswer,
      word: this.correctAnswer,
      sentence: '',
      question_type: this.mode,
      skill_key: this.skillKey,
      mode: this.mode,
      stage: this.stage
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.correctAnswer,
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 10 }) {
        if (this.showImage) {
          this.ImageArea()
        }
        if (!this.showImage) {
          this.ListenButton()
        }
        Text(this.question)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        if (!this.isAnswered && !this.showResult) {
          this.OptionsGrid()
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
    }
  }

  @Builder
  ListenButton() {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
          .fontSize(20)
          .fontColor([Color.White])
        Text(this.isPlayingSound ? CardShellCopy.PLAYING : CardShellCopy.REPLAY)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
    }
    .type(ButtonType.Normal)
    .width('100%')
    .height(56)
    .backgroundColor(this.isPlayingSound ? '#FF9F43' : this.themePrimary)
    .borderRadius(28)
    .enabled(!this.isPlayingSound)
    .onClick(() => {
      this.handlePlaySound()
    })
  }

  @Builder
  ImageArea() {
    if (this.displayImagePath !== '') {
      Image(this.toFileUrl(this.displayImagePath))
        .width('100%')
        .height(180)
        .objectFit(ImageFit.Contain)
        .borderRadius(10)
        .backgroundColor($r('app.color.surface'))
    } else if (this.isImageLoading) {
      this.ImagePlaceholder('图片加载中...')
    } else if (this.imageLoadFailed) {
      this.ImagePlaceholder('图片加载失败')
    } else {
      this.ImagePlaceholder('准备中...')
    }
  }

  @Builder
  ImagePlaceholder(label: string) {
    Column() {
      SymbolGlyph($r('sys.symbol.doc_plaintext'))
        .fontSize(32)
        .fontColor([$r('app.color.text_tertiary')])
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
  }

  @Builder
  OptionsGrid() {
    Grid() {
      ForEach(this.options, (option: string, idx: number) => {
        GridItem() {
          Button(option)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(56)
            .backgroundColor(this.themePrimary)
            .borderRadius(12)
            .onClick(() => {
              this.handleOptionSelect(option)
            })
        }
      }, (option: string, idx: number) => `opt_${idx}_${option}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .width('100%')
  }
}
```

注意：`icon: $r('sys.symbol.picture')` 若该符号不存在会编译告警/渲染空白——执行时若不确定，替换为已验证存在的 `sys.symbol.doc_plaintext`（现卡同款）。

- [ ] **Step 2: 编译验证**（assembleHap）。Expected: 通过。
- [ ] **Step 3: Commit** `git commit -am "feat(english): ChoiceModeBody 听音选词/看图选词/拼读共用 4 选 1 body"`

### Task 8: SentenceFillBody（句型填空）

**Files:**
- Create: `entry/src/main/ets/components/english/bodies/SentenceFillBody.ets`

**Interfaces:**
- Consumes/Produces: 同 Task 7 签名模式

**交互设计**：pattern 按 `___` 切两段，空位渲染高亮槽（未选显示 `?`，选中显示词）；下方 4 个词块 2×2；点选即判即交（同 Task 7 直提路径）。payload：`child_answer=选中词`、`sentence=correct_answer`、`pattern` 回填。

- [ ] **Step 1: 实现**

```typescript
// entry/src/main/ets/components/english/bodies/SentenceFillBody.ets
/**
 * SentenceFillBody - english_quiz v2 句型填空 body
 * pattern 按 ___ 切分, 空位高亮槽 + 4 词块点选, 点选即判即交。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import {
  EnglishQuizAnswerPayload, EnglishQuizModeArgs, parseEnglishQuizModeArgs
} from '../ModeTypes'

@ComponentV2
export struct SentenceFillBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local patternBefore: string = ''
  @Local patternAfter: string = ''
  @Local question: string = ''
  @Local options: string[] = []
  @Local correctAnswer: string = ''
  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local skillKey: string = 'english_sentence'
  @Local stage: string = ''
  private shellConfig: CardShellConfig = {
    title: '句型填空', subtitle: '', icon: $r('sys.symbol.square_and_pencil'),
    stem: '', hasAudio: false, usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    const args: EnglishQuizModeArgs = parseEnglishQuizModeArgs(this.toolCall.arguments)
    // 校验层已保证恰一个 ___; 防御: 多于一个时按第一段截断
    const firstSplit = args.pattern.split('___')
    this.patternBefore = firstSplit.length > 0 ? firstSplit[0] : args.pattern
    this.patternAfter = firstSplit.length > 1 ? firstSplit[1] : ''
    this.question = args.question
    this.options = args.options
    this.correctAnswer = args.correctAnswer
    this.skillKey = args.skillKey
    this.stage = args.stage
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.selectedOption = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.hasSelection = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    }
  }

  private parsePreviousAnswer(): EnglishQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as EnglishQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  private handleOptionSelect(option: string): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    const correct = option.trim().toLowerCase() === this.correctAnswer.trim().toLowerCase()
    this.selectedOption = option
    this.showResult = true
    this.isCorrect = correct
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct

    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: option,
      correct: correct,
      correct_answer: this.correctAnswer,
      word: '',
      sentence: this.correctAnswer,
      question_type: 'sentence_fill',
      skill_key: this.skillKey,
      mode: 'sentence_fill',
      stage: this.stage,
      pattern: this.patternBefore + '___' + this.patternAfter
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.correctAnswer,
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 12 }) {
        Text(this.question)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        // 句型行: 前 _ 空位槽 _ 后
        Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
          Text(this.patternBefore)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.showResult || this.selectedOption !== '' ? this.selectedOption : '?')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.showResult ? (this.isCorrect ? '#4CAF50' : '#FF6B6B') : this.themePrimary)
            .backgroundColor(this.showResult ? Color.Transparent : withColorAlpha(this.themePrimary, '1A'))
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .constraintSize({ minWidth: 48 })
            .textAlign(TextAlign.Center)
          Text(this.patternAfter)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.getCardBackgroundColor())
        .borderRadius(10)
        if (!this.isAnswered && !this.showResult) {
          this.OptionsGrid()
        }
      }
      .width('100%')
      .padding(12)
    }
  }

  @Builder
  OptionsGrid() {
    Grid() {
      ForEach(this.options, (option: string, idx: number) => {
        GridItem() {
          Button(option)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(52)
            .backgroundColor(this.themePrimary)
            .borderRadius(12)
            .onClick(() => {
              this.handleOptionSelect(option)
            })
        }
      }, (option: string, idx: number) => `fill_${idx}_${option}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .width('100%')
  }
}
```

- [ ] **Step 2: 编译验证**（assembleHap）。Expected: 通过。
- [ ] **Step 3: Commit** `git commit -am "feat(english): SentenceFillBody 句型填空 body"`

### Task 9: ReadAloudBody（跟读 + ASR 匹配评分）

**Files:**
- Create: `entry/src/main/ets/components/english/bodies/ReadAloudBody.ets`

**Interfaces:**
- Consumes: `isReadAloudMatch`（Task 1）、CardShell 族（`usesGiveUp: true` + `onGiveUp`）、`ServiceRegistry.speechRecognition()`（现卡语音流程原样复用）
- Produces: `ReadAloudBody`（签名同 Task 7）

**交互设计**（spec §6.4）：目标句大字展示 + phonetic_hint 小字；按住说话（原卡 `InputArea` onTouch 流程原样复用）；识别完成即评——命中自动提交 `correct=true`（1 星）；未命中本地提示「再试一次」（**不动 shellState.submitted**，不触发外壳答错横幅，孩子可无限重录）；键盘输入兜底（TextInput + 外壳确认按钮提交，走同一匹配函数，`voicePermissionDenied` 降级模式原样复用）；「放弃本局」走 CardShell `usesGiveUp` → 提交 `correct=false`。

- [ ] **Step 1: 实现**

```typescript
// entry/src/main/ets/components/english/bodies/ReadAloudBody.ets
/**
 * ReadAloudBody - english_quiz v2 跟读评分 body
 * ASR 转写 → ReadAloudMatcher 归一化匹配; 命中自动提交, 未命中可无限重录, 放弃提交 correct=false。
 * 语音流程/权限降级复用原 EnglishQuizCard 语音路径。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { ServiceRegistry } from '../../../services/ServiceRegistry'
import { SpeechRecognitionCallback } from '../../../services/SpeechRecognitionService'
import { common } from '@kit.AbilityKit'
import { isReadAloudMatch } from '../../../utils/ReadAloudMatcher'
import {
  EnglishQuizAnswerPayload, EnglishQuizModeArgs, parseEnglishQuizModeArgs
} from '../ModeTypes'

@ComponentV2
export struct ReadAloudBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local targetText: string = ''
  @Local phoneticHint: string = ''
  @Local question: string = ''
  @Local skillKey: string = 'english_reading'
  @Local stage: string = ''
  @Local isRecording: boolean = false
  @Local recognitionPreview: string = ''
  @Local lastHeard: string = ''
  @Local attemptFailed: boolean = false
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local inputText: string = ''
  @Local voicePermissionDenied: boolean = false
  @Local wasCancelled: boolean = false
  private shellConfig: CardShellConfig = {
    title: '跟我读', subtitle: '', icon: $r('sys.symbol.mic'),
    stem: '', hasAudio: false, usesConfirm: true, usesGiveUp: true,
    feedbackTitleCorrect: '读得真棒！', correctAnswerLabel: '目标句'
  }
  private shellState: CardShellState = new CardShellState()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    const args: EnglishQuizModeArgs = parseEnglishQuizModeArgs(this.toolCall.arguments)
    this.targetText = args.targetText !== '' ? args.targetText : args.correctAnswer
    this.phoneticHint = args.phoneticHint
    this.question = args.question
    this.skillKey = args.skillKey
    this.stage = args.stage
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.lastHeard = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    }
  }

  private parsePreviousAnswer(): EnglishQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as EnglishQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  /** 匹配并提交 (命中或放弃或键盘提交共用); failed=false 表示命中 */
  private submitAttempt(childAnswer: string, correct: boolean): void {
    this.showResult = true
    this.isCorrect = correct
    this.shellState.submitted = true
    this.shellState.isCorrect = correct
    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: childAnswer,
      correct: correct,
      correct_answer: this.targetText,
      word: '',
      sentence: this.targetText,
      question_type: 'read_aloud',
      skill_key: this.skillKey,
      mode: 'read_aloud',
      stage: this.stage,
      target_text: this.targetText
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  /** ASR onResult(final): 命中 → 提交 correct=true; 未命中 → 记录 + 本地重试提示 */
  private evaluateAttempt(transcript: string): void {
    this.lastHeard = transcript
    if (isReadAloudMatch(transcript, this.targetText)) {
      this.submitAttempt(transcript, true)
    } else {
      this.attemptFailed = true
    }
  }

  private handleGiveUp(): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    if (this.isRecording) {
      this.handleVoiceRecordCancel()
    }
    this.submitAttempt(this.lastHeard, false)
  }

  private handleTypedSubmit(): void {
    if (this.inputText.trim() === '' || this.isAnswered || this.showResult) {
      return
    }
    this.evaluateAttempt(this.inputText.trim())
  }

  // ===== 语音流程 (原 EnglishQuizCard handleVoiceRecord* 原样复用, 仅 onComplete 改调 evaluateAttempt) =====

  private handleVoiceRecordStart(): void {
    if (this.isRecording || this.isAnswered || this.showResult || this.voicePermissionDenied) {
      return
    }
    const speechService = ServiceRegistry.speechRecognition()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    speechService.checkPermission(context).then((granted: boolean) => {
      if (!granted) {
        this.voicePermissionDenied = true
        return
      }
      speechService.init().then(() => {
        this.isRecording = true
        this.recognitionPreview = ''
        const callback: SpeechRecognitionCallback = {
          onStart: () => {},
          onResult: (text: string, isFinal: boolean) => {
            if (isFinal) {
              this.recognitionPreview = text
            }
          },
          onComplete: (finalText: string) => {
            this.isRecording = false
            if (this.wasCancelled) {
              this.wasCancelled = false
              return
            }
            if (finalText.trim() !== '') {
              this.evaluateAttempt(finalText.trim())
            }
          },
          onCancel: () => {
            this.isRecording = false
          },
          onError: (code: number, message: string) => {
            this.isRecording = false
            console.error('ReadAloudBody', `Voice recognition error: ${code} ${message}`)
          }
        }
        speechService.startListening(callback)
      }).catch((err: Error) => {
        console.error('ReadAloudBody', `Failed to init speech: ${err.message}`)
      })
    })
  }

  private handleVoiceRecordFinish(): void {
    ServiceRegistry.speechRecognition().finishListening()
  }

  private handleVoiceRecordCancel(): void {
    ServiceRegistry.speechRecognition().cancelListening()
    this.isRecording = false
    this.wasCancelled = true
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.targetText,
      onConfirm: (): void => { this.handleTypedSubmit() },
      onRetry: (): void => {
        // 外壳「再试一次」仅键盘路径使用: 清输入, 不重复计分
        this.inputText = ''
        this.shellState.hasSelection = false
        this.shellState.submitted = false
        this.shellState.isCorrect = false
      },
      onGiveUp: (): void => { this.handleGiveUp() }
    }) {
      Column({ space: 10 }) {
        Text(this.question)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        Text(this.targetText)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        if (this.phoneticHint !== '') {
          Text(`小提示: ${this.phoneticHint}`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        if (this.attemptFailed && !this.showResult) {
          Text(`听到的是「${this.lastHeard}」, 再试一次!`)
            .fontSize(12)
            .fontColor('#FF6B6B')
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        if (!this.isAnswered && !this.showResult) {
          this.InputArea()
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
    }
  }

  @Builder
  InputArea() {
    Column({ space: 8 }) {
      if (!this.voicePermissionDenied) {
        Row() {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.mic'))
                .fontSize(16)
                .fontColor([Color.White])
              Text(this.isRecording ? '松开结束' : '按住说话')
                .fontSize(14)
                .fontColor(Color.White)
            }
          }
          .type(ButtonType.Normal)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.isRecording ? '#FF6B6B' : this.themePrimary)
          .borderRadius(20)
          .onTouch((event: TouchEvent) => {
            if (this.isAnswered || this.showResult) {
              return
            }
            if (event.type === TouchType.Down) {
              this.handleVoiceRecordStart()
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              if (this.isRecording) {
                if (event.type === TouchType.Cancel) {
                  this.handleVoiceRecordCancel()
                } else {
                  this.handleVoiceRecordFinish()
                }
              }
            }
          })
        }
        .width('100%')
      } else {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.mic'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
          Text('麦克风不可用 · 打字读出来也可以 ✏️')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
        .enabled(false)
      }
      if (this.isRecording && this.recognitionPreview !== '') {
        Text(`识别中: ${this.recognitionPreview}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      Row({ space: 8 }) {
        TextInput({ text: this.inputText, placeholder: '打不出来? 输入这句话...' })
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(10)
          .onChange((value: string) => {
            this.inputText = value
            this.shellState.hasSelection = value.trim() !== ''
          })
          .onSubmit(() => {
            this.handleTypedSubmit()
          })
      }
      .width('100%')
    }
    .width('100%')
  }
}
```

- [ ] **Step 2: 编译验证**（assembleHap）。Expected: 通过。
- [ ] **Step 3: Commit** `git commit -am "feat(english): ReadAloudBody ASR 归一化匹配跟读 body (重录/键盘兜底/放弃)"`

### Task 10: LetterTraceBody（内嵌 HandwritingCard）

**Files:**
- Create: `entry/src/main/ets/components/english/bodies/LetterTraceBody.ets`

**Interfaces:**
- Consumes: `HandwritingCard`（既有，签名同四 Param + onAnswer）、`ToolCall` 构造器
- Produces: `LetterTraceBody`（签名同 Task 7）

**映射契约**（spec §6.5）：`{letter, case}` → 合成 ToolCall arguments `{type: 'letter', character: <letter 原样>}`；HandwritingCard 回包 `{character, type, completed, stroke_count, handwriting_base64?}` → 适配为 english_quiz payload v2（`completed → correct` 透传，`completed:true → 授 1 星`）。answered 恢复：HandwritingCard 的 `parsePreviousResult` 读 payload 的 `completed` 字段——english_quiz payload v2 已含 `completed`，直接把 `answeredPayload` 透传给内嵌卡片即可。

- [ ] **Step 1: 实现**

```typescript
// entry/src/main/ets/components/english/bodies/LetterTraceBody.ets
/**
 * LetterTraceBody - english_quiz v2 字母描红 body
 * 把 letter_trace 参数映射为 handwriting_practice(type:'letter') 契约后内嵌 HandwritingCard;
 * 回包 completed → correct 适配为 english_quiz payload v2 (描红完成 = 1 星, 与 handwriting 同语义)。
 */

import { ToolCall } from '../../../models/ChatModels'
import { HandwritingCard } from '../../HandwritingCard'
import { EnglishQuizAnswerPayload } from '../ModeTypes'

interface HandwritingResultPayload {
  character: string
  type: string
  completed: boolean
  stroke_count: number
  handwriting_base64?: string
}

@ComponentV2
export struct LetterTraceBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  private letter: string = ''
  private letterCase: string = ''
  private correctAnswer: string = ''
  private skillKey: string = 'english_writing'
  private stage: string = ''
  // 合成 ToolCall 只构造一次, 避免每次 build 重建对象
  private innerToolCall: ToolCall = new ToolCall()

  aboutToAppear(): void {
    let parsed: Record<string, Object> = {}
    try {
      parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
    } catch (_e) {}
    this.letter = ((parsed['letter'] as string) ?? 'A').trim()
    this.letterCase = ((parsed['case'] as string) ?? 'upper').trim()
    this.correctAnswer = ((parsed['correct_answer'] as string) ?? this.letter).trim()
    this.skillKey = ((parsed['skill_key'] as string) ?? '').trim() !== ''
      ? ((parsed['skill_key'] as string) ?? '').trim() : 'english_writing'
    this.stage = ((parsed['stage'] as string) ?? '').trim()
    // letter_trace → handwriting_practice 契约映射: character 传原样大小写字母
    const mappedArgs = JSON.stringify({
      type: 'letter',
      character: this.letter,
      difficulty: (parsed['difficulty'] as number) ?? 1
    } as Record<string, Object>)
    this.innerToolCall = new ToolCall(
      this.toolCall.id, 'handwriting_practice', mappedArgs,
      'handwriting_practice', '字母描红'
    )
  }

  // HandwritingCard 回包 → english_quiz payload v2 适配
  private handleInnerAnswer(_toolCallId: string, answerJson: string): void {
    let completed = true
    let childAnswer = this.letter
    try {
      const hw = JSON.parse(answerJson) as HandwritingResultPayload
      completed = hw.completed
      childAnswer = hw.character
    } catch (_e) {}
    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: childAnswer,
      correct: completed,
      correct_answer: this.correctAnswer,
      word: '',
      sentence: '',
      question_type: 'letter_trace',
      skill_key: this.skillKey,
      mode: 'letter_trace',
      stage: this.stage,
      completed: completed
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  build() {
    HandwritingCard({
      toolCall: this.innerToolCall,
      isAnswered: this.isAnswered,
      answeredPayload: this.isAnswered ? this.answeredPayload : '',
      largeSize: this.largeSize,
      onAnswer: (toolCallId: string, answerJson: string): void => {
        this.handleInnerAnswer(toolCallId, answerJson)
      }
    })
  }
}
```

- [ ] **Step 2: 编译验证**（assembleHap）。Expected: 通过。
- [ ] **Step 3: Commit** `git commit -am "feat(english): LetterTraceBody 内嵌 HandwritingCard 字母描红 body"`

### Task 11: 路由器替换 + MessageBubble import 更新 + 删除旧文件

**Files:**
- Create: `entry/src/main/ets/components/english/EnglishQuizCard.ets`（新路由器）
- Delete: `entry/src/main/ets/components/EnglishQuizCard.ets`（900 行旧实现）
- Modify: `entry/src/main/ets/components/MessageBubble.ets:17`（仅 import 路径）

**Interfaces:**
- Consumes: 5 个 body（Task 6-10）、`parseEnglishQuizModeArgs`（Task 4）
- Produces: `EnglishQuizCard`（导出名不变）——MessageBubble 两处挂载（pending ~2065 / answered ~4061）的参数签名不变，零改动

- [ ] **Step 1: 创建路由器**

```typescript
// entry/src/main/ets/components/english/EnglishQuizCard.ets
/**
 * EnglishQuizCard - english_quiz v2 薄路由器
 *
 * 按 toolCall.arguments 的 mode 选择 body; 解析失败/legacy 一律回落 LegacyBody
 * (历史会话渲染零风险)。MessageBubble 挂载签名与旧版完全一致:
 * toolCall / isAnswered / answeredPayload / largeSize / onAnswer。
 * 设计见 docs/superpowers/specs/2026-09-24-english-quiz-v2-design.md §6。
 */

import { ToolCall } from '../../models/ChatModels'
import { parseEnglishQuizModeArgs } from './ModeTypes'
import { LegacyBody } from './bodies/LegacyBody'
import { ChoiceModeBody } from './bodies/ChoiceModeBody'
import { SentenceFillBody } from './bodies/SentenceFillBody'
import { ReadAloudBody } from './bodies/ReadAloudBody'
import { LetterTraceBody } from './bodies/LetterTraceBody'

@ComponentV2
export struct EnglishQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  build() {
    if (this.isChoiceMode()) {
      ChoiceModeBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isSentenceFillMode()) {
      SentenceFillBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isReadAloudMode()) {
      ReadAloudBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isLetterTraceMode()) {
      LetterTraceBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else {
      LegacyBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    }
  }

  // ===== build 内不能调用带复杂逻辑的方法签名限制, 用小型判谓方法 (每次 build 解析一次 args, 开销可忽略) =====

  private resolveMode(): string {
    return parseEnglishQuizModeArgs(this.toolCall.arguments).mode
  }

  private isChoiceMode(): boolean {
    const m = this.resolveMode()
    return m === 'listen_choice' || m === 'picture_word' || m === 'phonics_blend'
  }

  private isSentenceFillMode(): boolean {
    return this.resolveMode() === 'sentence_fill'
  }

  private isReadAloudMode(): boolean {
    return this.resolveMode() === 'read_aloud'
  }

  private isLetterTraceMode(): boolean {
    return this.resolveMode() === 'letter_trace'
  }
}
```

- [ ] **Step 2: 更新 MessageBubble import 并删除旧文件**

```bash
# MessageBubble.ets:17
#   旧: import { EnglishQuizCard } from './EnglishQuizCard'
#   新: import { EnglishQuizCard } from './english/EnglishQuizCard'
grep -rn "from './EnglishQuizCard'" entry/src/main/ets/   # 确认只有 MessageBubble 一处
git rm entry/src/main/ets/components/EnglishQuizCard.ets
```

- [ ] **Step 3: 编译验证**（assembleHap）。Expected: 通过——若有第三方遗漏 import 旧路径，编译器会指认。
- [ ] **Step 4: Commit** `git commit -am "refactor(english): EnglishQuizCard 改为 mode 薄路由器, 旧实现由 bodies/ 接管"`

### Task 12: BuiltinTools schema v2 + 工具描述重写

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`（`createEnglishQuizToolDefinition()` 的 rawSchemaJson + ToolFunction description；`createEnglishQuizToolConfig()` 的 displayName/描述）

**Interfaces:**
- Consumes: 无
- Produces: LLM 可见的 english_quiz v2 schema——`required: ["question", "mode", "correct_answer"]`，`question_type` 保留标注 deprecated

- [ ] **Step 1: 替换 rawSchemaJson**（保留外层模板字符串结构；description 内**禁用 ASCII 双引号**，用「」或单引号）

```typescript
function createEnglishQuizToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "mode": {
        "type": "string",
        "enum": ["listen_choice", "picture_word", "phonics_blend", "sentence_fill", "read_aloud", "letter_trace"],
        "description": "Quiz mode, exactly one of six. listen_choice: child hears a word via TTS and picks it from 4 options (tts_text REQUIRED). picture_word: child sees an image and picks the matching word (image_prompt REQUIRED). phonics_blend: pick the word matching phonics_rule from 4 same-rule options (phonics_rule REQUIRED). sentence_fill: fill the one blank in pattern by picking from 4 options (pattern REQUIRED). read_aloud: child reads target_text aloud, card auto-scores via speech recognition (target_text REQUIRED). letter_trace: trace a single letter (letter and case REQUIRED)."
      },
      "question": {
        "type": "string",
        "description": "Chinese instruction shown to the child, e.g. 「听一听, 选出你听到的单词」 / 「看图选出对应的英文」 / 「跟我读下面这句话」."
      },
      "correct_answer": {
        "type": "string",
        "description": "The correct English answer for this mode: the heard word (listen_choice), the pictured word (picture_word), the rule-matching word (phonics_blend), the blank word (sentence_fill), or the target sentence itself (read_aloud), or the letter (letter_trace)."
      },
      "difficulty": {
        "type": "number",
        "description": "Difficulty level 1-5 based on the child's english_* profile levels."
      },
      "skill_key": {
        "type": "string",
        "description": "Child profile skill dimension this quiz targets: english_alphabet / english_vocab / english_phonics / english_sentence / english_reading / english_writing. Optional — a sensible default is applied per mode if omitted."
      },
      "stage": {
        "type": "string",
        "enum": ["warm_up", "presentation", "practice", "production", "review"],
        "description": "Optional lesson stage tag for the five-step English lesson. Informational only."
      },
      "theme": {
        "type": "string",
        "description": "Optional theme of this quiz: 颜色/动物/食物/家庭/数字/身体/学校/天气. All 4 options must belong to the same theme."
      },
      "options": {
        "type": "array",
        "items": { "type": "string" },
        "description": "REQUIRED for listen_choice / picture_word / phonics_blend / sentence_fill: EXACTLY 4 distinct English words including correct_answer. 严禁跨主题混词 (apple/bus/red 是坏题); 严禁重复项; 严禁 3 个或 5 个选项."
      },
      "image_prompt": {
        "type": "string",
        "description": "REQUIRED only for picture_word. English image-generation prompt with a single clearly recognizable subject, child illustration style. Other modes must omit it."
      },
      "phonics_rule": {
        "type": "string",
        "description": "REQUIRED only for phonics_blend, e.g. 「short a」. All 4 options must fully satisfy the rule (short a → cat/ham/map/bat). 严禁混入违反规则的词 (r-controlled 的 car, 长元音的 cake)."
      },
      "pattern": {
        "type": "string",
        "description": "REQUIRED only for sentence_fill, e.g. 「I like ___.」. Must contain EXACTLY ONE ___ blank. 严禁 0 个或 2 个以上空格."
      },
      "tts_text": {
        "type": "string",
        "description": "REQUIRED only for listen_choice: the English word TTS will read aloud. Must be plain TTS-readable English (not IPA, not letter names)."
      },
      "target_text": {
        "type": "string",
        "description": "REQUIRED only for read_aloud: the sentence the child reads aloud. Max 8 words; level 0-1 → max 3 words, 2-3 → max 5, 4-5 → max 8. Use english_sentence level from child_profile."
      },
      "phonetic_hint": {
        "type": "string",
        "description": "Optional for read_aloud: tricky-sound hint, e.g. 「th → this」."
      },
      "letter": {
        "type": "string",
        "description": "REQUIRED only for letter_trace: a single English letter (a-z or A-Z)."
      },
      "case": {
        "type": "string",
        "enum": ["upper", "lower"],
        "description": "REQUIRED only for letter_trace: letter case to practice."
      },
      "question_type": {
        "type": "string",
        "enum": ["word", "sentence", "phonics_choice"],
        "description": "DEPRECATED legacy field for historical sessions only. New calls must use mode instead; sending question_type alone renders the legacy free-input card."
      },
      "letter_options": {
        "type": "array",
        "items": { "type": "string", "minLength": 1, "maxLength": 3 },
        "description": "仅 legacy phonics_choice 用: 3-4 个字母选项 (含 correct_answer), distractor 选同类或相近音字母 (k/c/g, b/d/p/q, m/n)。新调用不要发此字段."
      },
      "sound_text": {
        "type": "string",
        "description": "仅 legacy phonics_choice 用: TTS 可读的字母音拼写 (如 /k/ 写作「kuh」)。新调用不要发此字段."
      }
    },
    "required": ["question", "mode", "correct_answer"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    ENGLISH_QUIZ_TOOL_ID,
    'Present an English quiz to the child as an interactive card. Six modes cover the five-step English lesson: listen_choice (hear and pick), picture_word (see image and pick), phonics_blend (same-rule word pick), sentence_fill (fill one blank), read_aloud (read aloud, auto-scored), letter_trace (trace a letter). Choice modes need options: EXACTLY 4 distinct words including correct_answer, all from the SAME theme. Use this INSTEAD of writing English questions in plain text — only this tool can grade answers and record stars. Pick mode and difficulty from the child_profile english_* levels. 严禁在文字里直接出英语题, 严禁跨主题混选项, 严禁 phonics_blend 里混入违反 phonics_rule 的词.',
    parameters
  )

  return new ToolDefinition(func)
}
```

同时更新 `createEnglishQuizToolConfig()`：displayName `'英语看图说话'` → `'英语趣味题'`，描述 → `'英语听说读写互动题: 听音选词/看图选词/自然拼读/句型填空/跟读/字母描红, 答对自动记星。'`。

- [ ] **Step 2: JSON 有效性验证（必做，防 JSON-in-template-literal 陷阱）**

```bash
node -e "
const fs = require('fs');
const src = fs.readFileSync('entry/src/main/ets/config/BuiltinTools.ets', 'utf8');
const m = src.match(/function createEnglishQuizToolDefinition[\s\S]*?const rawSchemaJson: string = \`([\s\S]*?)\`;/);
if (!m) { console.error('schema block not found'); process.exit(1); }
const obj = JSON.parse(m[1]);
console.log('OK required =', JSON.stringify(obj.required));
console.log('mode enum =', obj.properties.mode.enum.join(','));
"
```

Expected: `OK required = ["question","mode","correct_answer"]`。

- [ ] **Step 3: 编译验证**（assembleHap）。
- [ ] **Step 4: Commit** `git commit -am "feat(english): english_quiz schema v2 — mode 六选一 + 新字段, question_type 标 deprecated"`

### Task 13: ToolExecutionService 图片管线收窄

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`（`handleEnglishQuiz` 内两处：displayName 兜底、图片管线门条件 + picture_word 的 word/sentence 推导）

**Interfaces:**
- Consumes: `validateEnglishQuizArgs` 返回的 `mode` 字段（Task 2）
- Produces: 行为变化——仅 `picture_word` / legacy `word` / legacy `sentence` 走三层图片解析，其余 5 mode 跳过整条管线

- [ ] **Step 1: 修改**（基于 `handleEnglishQuiz` 现文，行号 ~663-790）

1. displayName 兜底 `'英语看图说话'` → `'英语趣味题'`（两处：`toolCall.displayName.trim() === ''` 分支）。
2. 校验失败分支不变（`englishValidation.ok` 判定已存在）。
3. 图片管线门：现条件 `if (questionType === 'phonics_choice') { skip } else { pipeline }` 改为——

```typescript
      const parsed = JSON.parse(toolCall.arguments) as Record<string, Object>
      const resolvedMode = englishValidation.mode   // Task 2 已携带
      const needsImage = resolvedMode === 'picture_word' || resolvedMode === 'word' || resolvedMode === 'sentence'

      if (!needsImage) {
        console.info('ToolExecutionService',
          `english_quiz mode=${resolvedMode}: skip image pipeline`)
      } else {
        const question = (parsed['question'] as string) ?? ''
        const answer = (parsed['correct_answer'] as string) ?? ''
        let word = ''
        let sentence = ''
        if (resolvedMode === 'sentence') {
          sentence = answer
        } else {
          // picture_word 与 legacy word 都是单词图
          word = answer
        }
        // ……以下三层查找代码保持不变 (quizKey/tier1/tier2/tier3 + image_path 注入)
```

其余（tier 查找、image_path 注入、pending Promise）不动。原 `questionType` 局部变量删除，统一用 `resolvedMode`。

- [ ] **Step 2: 编译验证 + 手工核对**——assembleHap 通过；grep 确认 `handleEnglishQuiz` 内不再引用 `questionType` 局部变量。
- [ ] **Step 3: Commit** `git commit -am "feat(english): 图片管线收窄为 picture_word + legacy word/sentence"`

### Task 14: english_reading 画像维度（23 → 24）

**Files:**
- Modify: `entry/src/main/ets/services/ChildProfileService.ets:48`（SKILL_DEFINITIONS english 组末尾插入）
- Modify: `entry/src/main/ets/pages/LearningProfilePage.ets:50-59`（english 组 keys）
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`（child_profile skill_key 描述 2 处：schema description + tool description）
- Modify: `.claude/rules/teaching-architecture.md` §5.1

- [ ] **Step 1: ChildProfileService**——在 `['english_phonics', '自然拼读'],`（行 48）后插入：

```typescript
  ['english_reading', '英语跟读'],
```

- [ ] **Step 2: LearningProfilePage**——english 组 keys 数组 `'english_phonics',` 后加 `'english_reading',`（english_writing 保持在末位）。
- [ ] **Step 3: BuiltinTools child_profile 两处 skill_key 枚举描述**——`english_phonics,` 后补 `english_reading,`（行 ~1247 schema description 与行 ~1284 tool description 的 Available skill keys 列表各一处）。
- [ ] **Step 4: teaching-architecture.md §5.1**——「英语 4」改「英语 5」并加 `english_reading`；总数 23 → 24（§5.1 表头与 §11.5 的 23 维表述同步）；§4 工具表 `english_quiz` 行备注更新为「六 mode（v2）」。
- [ ] **Step 5: 编译验证**（assembleHap）。
- [ ] **Step 6: Commit** `git commit -am "feat(profile): 新增 english_reading 画像维度 (23→24), 四触点同步"`

### Task 15: 小写字母笔顺数据（a-z）或降级拦截

**Files:**
- Modify: `entry/src/main/ets/config/StrokeOrderData.ets`
- Test: `entry/src/ohosTest/ets/test/utils/StrokeOrderCoverage.test.ets`（新建）

**Interfaces:**
- Consumes: `adding-stroke-order-data` skill（项目内配方——**实施本任务前先读该 skill**）
- Produces: `getStrokeOrder('a'..'z')` 全部返回非 null（或走降级方案）

- [ ] **Step 1: 先调用 adding-stroke-order-data skill**，按其配方为 a-z 26 个小写字母生成程序化粗线段 SVG 路径条目（与现有 A-Z 大写同风格，追加到 `STROKE_ORDER_ENTRIES` 字母区段）。
- [ ] **Step 2: 写覆盖测试**

```typescript
// entry/src/ohosTest/ets/test/utils/StrokeOrderCoverage.test.ets
import { describe, it, expect } from '@ohos/hypium'
import { hasStrokeOrder } from '../../../../main/ets/config/StrokeOrderData'

export default function strokeOrderCoverageTest() {
  describe('letter_trace 小写笔顺覆盖', () => {
    it('a-z 26 个小写字母全部有笔顺数据', 0, () => {
      let missing: string = ''
      for (let i = 0; i < 26; i++) {
        const ch = String.fromCharCode(97 + i)
        if (!hasStrokeOrder(ch)) {
          missing += ch
        }
      }
      expect(missing).assertEqual('')
    })
    it('A-Z 大写回归不受影响', 0, () => {
      expect(hasStrokeOrder('A')).assertTrue()
      expect(hasStrokeOrder('Z')).assertTrue()
    })
  })
}
```

- [ ] **Step 3: 运行测试**（DevEco Studio）确认 a-z 覆盖。
- [ ] **Step 4（降级方案，仅当 Step 1 生成成本超预期时执行）**：`EnglishQuizValidation.ets` 的 `validateLetterTrace` 加分支——`letterCase === 'lower'` 时 `return fail('letter_trace 本轮仅支持大写字母 (case=upper), 请改出大写描红题', mode, false)`，并在 Task 12 schema 的 `case` description 补「本轮仅支持 upper」；同时删除本任务测试或改为断言降级行为。**二选一，不许两头都不做**（否则 lower 描红会渲染无笔顺引导的空卡）。
- [ ] **Step 5: 编译验证 + Commit** `git commit -am "feat(english): 小写 a-z 笔顺数据覆盖 letter_trace case=lower"`

### Task 16: AssistantModels 提示词（default + kids_english）

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`

**Interfaces:**
- Consumes: spec §9.1 / §9.2 全文（**执行者须打开 spec 逐字取用**）
- Produces: 默认助手与小星英语老师的 v2 教学协议

- [ ] **Step 1: 替换 default 三段**——`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 数组中以下三行（行 53-55，特征：以 `'【英语】4 维` / `'【看图识词】` / `'【听力】` 开头）**删除**，替换为 spec §9.1 的「英语（五步课）/【出题契约】/【纠错话术】/【主题纪律】」四段（每段一个数组元素字符串，注意单引号字符串内不能出现未转义单引号——spec 文本已用「」，照抄即可）。
- [ ] **Step 2: 改写 KIDS_ENGLISH_SYSTEM_PROMPT 策略段**——`'- 聚焦 4 个维度` 行起，至 `- child_profile(action: "update") 只更新 english_ 开头的技能维度,notes 必须基于本轮具体表现。` 行止，整块替换为 spec §9.2 的策略段（保持数组元素逐行结构）。
- [ ] **Step 3: 编译验证**（assembleHap）+ grep 自检：`grep -c "热身→呈现" entry/src/main/ets/models/AssistantModels.ets` 应 ≥ 2（default 与 kids_english 的五步课推进各一处）；`grep -c "english_reading" entry/src/main/ets/models/AssistantModels.ets` 应 ≥ 2。
- [ ] **Step 4: Commit** `git commit -am "feat(prompt): 小星老师/小星英语老师切换五步英语教学协议 (english_quiz mode 契约)"`

### Task 17: 收尾验证

**Files:** 无新改动（验证任务）

- [ ] **Step 1: 干净构建**

```bash
hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: BUILD SUCCESSFUL，产物 `entry/build/default/outputs/default/entry-default-signed.hap`（签名偶发 CEN 失败为 hvigor daemon 陈旧 bug，重跑即可，见 MEMORY.md）。

- [ ] **Step 2: 触点完整性 4-grep 自检**（借用 adding-mini-game-tool 配方思路，本改造不加新工具，检查面收窄为）

```bash
grep -rn "question_type" entry/src/main/ets/services/ToolExecutionService.ets | grep -v resolvedMode   # 应无残留裸读 question_type 的管线分支
grep -c "english_reading" entry/src/main/ets/services/ChildProfileService.ets                          # ≥1
grep -rn "from './EnglishQuizCard'" entry/src/main/ets/                                                # 应无输出 (旧路径已删)
grep -c "mode" entry/src/main/ets/utils/EnglishQuizValidation.ets                                      # 新逻辑存在
```

- [ ] **Step 3: 手工验收清单**（spec §14 逐条）：六 mode 端到端出题→作答→授星→payload v2；坏题 should_retry；历史会话渲染不变；read_aloud 权限拒/放弃路径；letter_trace upper 描红 1 星；picture_word 三层图管线；画像页「英语跟读」出现；新会话五步课推进。真机/模拟器在 DevEco Studio 运行。
- [ ] **Step 4: 汇报**——把验收结果（含未过项）如实写进 PR 描述 / 会话总结。

## Self-Review 记录

- **Spec 覆盖**：§4 契约→Task 12；§5 校验→Task 2/3；§6 卡片→Task 4-11；§6.5 小写缺口→Task 15；§7 管线→Task 13；§8 维度→Task 14；§9 提示词→Task 16；§12 测试→Task 1/2/3/15 + Task 17 手工清单；§13 触点全覆盖。MessageBubble 仅 import（Task 11 Step 2）。
- **类型一致性**：`EnglishQuizAnswerPayload` 唯一定义在 ModeTypes（Task 4），6 body 引用同源；`resolveQuizPath` 签名 `(word, sentence, imagePrompt)` 在 Task 5/6/7 一致；body 四 Param + onAnswer 签名在 Task 6 定版、7-11 沿用。
- **Review Focus 回填**：条目 1→Task 2 测试；条目 2→Task 3 options 大小写用例；条目 3→Task 1 子串用例；条目 4→Task 11 路由回落 + Task 6 LegacyBody 恢复路径；条目 5→Task 5/7 resolver + 超时 + @Monitor。

