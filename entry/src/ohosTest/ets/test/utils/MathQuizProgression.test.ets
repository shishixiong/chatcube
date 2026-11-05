import { describe, it, expect } from '@ohos/hypium'
import {
  applyMathQuizProgress, buildMathQuizProgressHint, buildMathQuizRecordExpression, buildTarget,
  evaluateMathQuizGate, getLevelSpec, getMaxLevel, getTrackLabel, initialLevelForTrack,
  normalizeExpressionKey, normalizePurpose, normalizeSkillKey, resolveMathQuizLevel
} from '../../../../main/ets/utils/MathQuizProgression'
import type {
  MathQuizGateInput, MathQuizLevelInfo, MathQuizLevelInput, MathQuizLevelSpec, MathQuizProgressHint,
  MathQuizProgressRow, MathQuizPurpose
} from '../../../../main/ets/models/MathQuizProgressionModels'

function arithmetic(expression: string, skillKey: string = ''): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'arithmetic', expression: expression, wordProblem: false, skillKey: skillKey,
    leftValue: 0, rightValue: 0, clockHour: 0, clockMinute: 0,
    startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
  }
  return input
}

function comparison(left: number, right: number): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'comparison', expression: '', wordProblem: false, skillKey: '',
    leftValue: left, rightValue: right, clockHour: 0, clockMinute: 0,
    startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
  }
  return input
}

function clock(hour: number, minute: number): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'time', expression: '', wordProblem: false, skillKey: '',
    leftValue: 0, rightValue: 0, clockHour: hour, clockMinute: minute,
    startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
  }
  return input
}

function elapsed(sh: number, sm: number, eh: number, em: number): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'elapsed_time', expression: '', wordProblem: false, skillKey: '',
    leftValue: 0, rightValue: 0, clockHour: 0, clockMinute: 0,
    startHour: sh, startMinute: sm, endHour: eh, endMinute: em
  }
  return input
}

function row(level: number, correct: number, wrong: number, updatedAt: number = Date.now()): MathQuizProgressRow {
  const r: MathQuizProgressRow = {
    track: 'add', currentLevel: level, correctAtLevel: correct,
    consecutiveWrong: wrong, updatedAt: updatedAt
  }
  return r
}

function gateInput(info: MathQuizLevelInfo, purpose: MathQuizPurpose, progressLevel: number,
  keys: string[], count: number, sessionId: string): MathQuizGateInput {
  const input: MathQuizGateInput = {
    info: info, purpose: purpose, progressLevel: progressLevel,
    recentExpressionKeys: keys, purposeCountInSession: count, sessionId: sessionId
  }
  return input
}

export default function mathQuizProgressionTest() {
  describe('normalizePurpose', () => {
    it('maps warmup variants and defaults invalid values to practice', 0, () => {
      expect(normalizePurpose('warm_up')).assertEqual('warm_up')
      expect(normalizePurpose('warmup')).assertEqual('warm_up')
      expect(normalizePurpose('warm-up')).assertEqual('warm_up')
      expect(normalizePurpose('review')).assertEqual('review')
      expect(normalizePurpose('')).assertEqual('practice')
      expect(normalizePurpose('foo')).assertEqual('practice')
    })
  })

  describe('normalizeSkillKey', () => {
    it('maps legacy short names and leaves canonical names intact', 0, () => {
      expect(normalizeSkillKey('addition')).assertEqual('math_addition')
      expect(normalizeSkillKey('subtraction')).assertEqual('math_subtraction')
      expect(normalizeSkillKey('multiply')).assertEqual('math_multiply')
      expect(normalizeSkillKey('divide')).assertEqual('math_divide')
      expect(normalizeSkillKey('word_problem')).assertEqual('math_word_problem')
      expect(normalizeSkillKey('math_addition')).assertEqual('math_addition')
      expect(normalizeSkillKey('foo')).assertEqual('')
    })
  })

  describe('normalizeExpressionKey', () => {
    it('normalizes whitespace, U+2212, and full-width operators', 0, () => {
      expect(normalizeExpressionKey(arithmetic('47 + 28'))).assertEqual('47+28')
      expect(normalizeExpressionKey(arithmetic('47+28'))).assertEqual('47+28')
      expect(normalizeExpressionKey(arithmetic('47 + 28 − 15'))).assertEqual('47+28-15')
      expect(normalizeExpressionKey(arithmetic('6 × 7'))).assertEqual('6*7')
      expect(normalizeExpressionKey(arithmetic('6 ÷ 2'))).assertEqual('6/2')
      expect(normalizeExpressionKey(arithmetic('47 － 28'))).assertEqual('47-28')
      expect(normalizeExpressionKey(arithmetic('3 ＋ 4'))).assertEqual('3+4')
      expect(normalizeExpressionKey(arithmetic('47 + 28')) === normalizeExpressionKey(arithmetic('47 + 29'))).assertFalse()
    })

    it('builds stable keys for comparison, clock, and elapsed', 0, () => {
      expect(normalizeExpressionKey(comparison(5, 3))).assertEqual('cmp:5:3')
      expect(normalizeExpressionKey(clock(3, 30))).assertEqual('clock:3:30')
      expect(normalizeExpressionKey(elapsed(3, 10, 3, 40))).assertEqual('elapsed:3:10-3:40')
    })

    it('builds readable record expressions for non-arithmetic questions', 0, () => {
      expect(buildMathQuizRecordExpression(arithmetic('47 + 28'))).assertEqual('47 + 28')
      expect(buildMathQuizRecordExpression(comparison(5, 3))).assertEqual('5 ? 3')
      expect(buildMathQuizRecordExpression(clock(3, 5))).assertEqual('3:05')
      expect(buildMathQuizRecordExpression(elapsed(3, 10, 3, 40))).assertEqual('3:10 → 3:40')
    })
  })

  describe('spec table and target', () => {
    it('returns the add L7 spec and target', 0, () => {
      const spec: MathQuizLevelSpec = getLevelSpec('add', 7) as MathQuizLevelSpec
      expect(spec.maxOperand).assertEqual(999)
      expect(spec.minSteps).assertEqual(1)
      expect(spec.maxSteps).assertEqual(1)
      expect(spec.carryRule).assertEqual('none')
      const target = buildTarget(spec)
      expect(target.level).assertEqual(7)
      expect(target.max_operand).assertEqual(999)
      expect(target.steps).assertEqual('1')
      expect(target.carry).assertEqual('none')
      expect(target.example).assertEqual('213 + 124')
    })

    it('returns a clock target with constraint and no arithmetic fields', 0, () => {
      const spec: MathQuizLevelSpec = getLevelSpec('clock', 3) as MathQuizLevelSpec
      const target = buildTarget(spec)
      expect(target.constraint).assertEqual('分钟为 10/15/20/25/35/40/45/50 之一')
      expect(target.max_operand === undefined).assertTrue()
      expect(target.steps === undefined).assertTrue()
    })

    it('caps max levels and returns null outside the table', 0, () => {
      expect(getMaxLevel('add')).assertEqual(15)
      expect(getMaxLevel('muldiv')).assertEqual(10)
      expect(getMaxLevel('compare')).assertEqual(6)
      expect(getMaxLevel('clock')).assertEqual(4)
      expect(getMaxLevel('elapsed')).assertEqual(4)
      expect(getLevelSpec('add', 16) === null).assertTrue()
      expect(getTrackLabel('add')).assertEqual('加法')
      expect(getTrackLabel('muldiv')).assertEqual('乘除')
    })
  })

  describe('initialLevelForTrack', () => {
    it('maps add/sub profile levels with sibling fallback', 0, () => {
      const add4: Record<string, number> = { 'math_addition': 4 }
      expect(initialLevelForTrack('add', add4)).assertEqual(8)
      const empty: Record<string, number> = {}
      expect(initialLevelForTrack('add', empty)).assertEqual(1)
      expect(initialLevelForTrack('sub', add4)).assertEqual(7)
      const sub5: Record<string, number> = { 'math_subtraction': 5 }
      expect(initialLevelForTrack('sub', sub5)).assertEqual(11)
      expect(initialLevelForTrack('add', sub5)).assertEqual(10)
    })

    it('takes max(mul, div) for muldiv and maps compare/time', 0, () => {
      const mulDiv: Record<string, number> = { 'math_multiply': 5, 'math_divide': 3 }
      expect(initialLevelForTrack('muldiv', mulDiv)).assertEqual(9)
      const mulOnly: Record<string, number> = { 'math_multiply': 2, 'math_divide': 0 }
      expect(initialLevelForTrack('muldiv', mulOnly)).assertEqual(3)
      const compare4: Record<string, number> = { 'math_comparison': 4 }
      expect(initialLevelForTrack('compare', compare4)).assertEqual(5)
      const time5: Record<string, number> = { 'math_time': 5 }
      expect(initialLevelForTrack('clock', time5)).assertEqual(4)
      expect(initialLevelForTrack('elapsed', time5)).assertEqual(4)
      const none: Record<string, number> = {}
      expect(initialLevelForTrack('clock', none)).assertEqual(1)
    })
  })

  describe('resolveMathQuizLevel arithmetic add/sub', () => {
    it('classifies the spec add/sub ladder', 0, () => {
      expect(resolveMathQuizLevel(arithmetic('7 + 2')).level).assertEqual(1)
      expect(resolveMathQuizLevel(arithmetic('9 − 3')).level).assertEqual(1)
      expect(resolveMathQuizLevel(arithmetic('12 + 5')).level).assertEqual(2)
      expect(resolveMathQuizLevel(arithmetic('8 + 7')).level).assertEqual(3)
      expect(resolveMathQuizLevel(arithmetic('9 + 9')).level).assertEqual(3)
      expect(resolveMathQuizLevel(arithmetic('47 + 28')).level).assertEqual(5)
      expect(resolveMathQuizLevel(arithmetic('63 − 27')).level).assertEqual(5)
      expect(resolveMathQuizLevel(arithmetic('47 + 28 − 15')).level).assertEqual(6)
      expect(resolveMathQuizLevel(arithmetic('213 + 124')).level).assertEqual(7)
      expect(resolveMathQuizLevel(arithmetic('568 − 235')).level).assertEqual(7)
      expect(resolveMathQuizLevel(arithmetic('487 + 265')).level).assertEqual(8)
      expect(resolveMathQuizLevel(arithmetic('503 − 178')).level).assertEqual(8)
      expect(resolveMathQuizLevel(arithmetic('4876 + 2657')).level).assertEqual(11)
      expect(resolveMathQuizLevel(arithmetic('21345 + 12432')).level).assertEqual(13)
      expect(resolveMathQuizLevel(arithmetic('48765 + 26578 − 13042')).level).assertEqual(15)
      expect(resolveMathQuizLevel(arithmetic('10 − 3 + 5')).level).assertEqual(3)
    })

    it('rejects negative intermediates, negative operands, and >5 digits', 0, () => {
      const negativeMiddle = resolveMathQuizLevel(arithmetic('3 − 5 + 10'))
      expect(negativeMiddle.gate).assertTrue()
      expect(negativeMiddle.error.length > 0).assertTrue()
      const negativeOperand = resolveMathQuizLevel(arithmetic('-3 + 5'))
      expect(negativeOperand.gate).assertTrue()
      expect(negativeOperand.error.length > 0).assertTrue()
      const tooBig = resolveMathQuizLevel(arithmetic('99999 + 1'))
      expect(tooBig.gate).assertTrue()
      expect(tooBig.error.length > 0).assertTrue()
    })

    it('routes decimal operands to none without a gate', 0, () => {
      const decimal = resolveMathQuizLevel(arithmetic('1.5 + 2'))
      expect(decimal.track).assertEqual('none')
      expect(decimal.gate).assertFalse()
      expect(decimal.error).assertEqual('')
    })

    it('classifies full-width operators like their ASCII forms', 0, () => {
      const minus = resolveMathQuizLevel(arithmetic('47 － 28'))
      expect(minus.track).assertEqual('sub')
      expect(minus.level).assertEqual(5)
      expect(minus.error).assertEqual('')
      const plus = resolveMathQuizLevel(arithmetic('3 ＋ 4'))
      expect(plus.track).assertEqual('add')
      expect(plus.level).assertEqual(1)
      expect(plus.error).assertEqual('')
    })

    it('enforces skill_key and expression consistency', 0, () => {
      expect(resolveMathQuizLevel(arithmetic('3 − 2', 'math_addition')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_subtraction')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_multiply')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('3 × 2', 'math_divide')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('3 + 2', 'addition')).track).assertEqual('add')
      expect(resolveMathQuizLevel(arithmetic('3 × 2', 'multiply')).track).assertEqual('muldiv')
      expect(resolveMathQuizLevel(arithmetic('3 + 2', 'foo')).track).assertEqual('add')
      expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_word_problem')).track).assertEqual('add')
      expect(resolveMathQuizLevel(arithmetic('', 'math_counting')).track).assertEqual('none')
      expect(resolveMathQuizLevel(arithmetic('', 'math_counting')).gate).assertFalse()
      const missing = resolveMathQuizLevel(arithmetic('', 'math_addition'))
      expect(missing.gate).assertTrue()
      expect(missing.error.length > 0).assertTrue()
    })
  })

  describe('resolveMathQuizLevel mul/div', () => {
    it('classifies the mul/div ladder', 0, () => {
      expect(resolveMathQuizLevel(arithmetic('2 × 2')).level).assertEqual(1)
      expect(resolveMathQuizLevel(arithmetic('10 × 3')).level).assertEqual(1)
      expect(resolveMathQuizLevel(arithmetic('1 × 7')).level).assertEqual(1)
      expect(resolveMathQuizLevel(arithmetic('2 × 3')).level).assertEqual(2)
      expect(resolveMathQuizLevel(arithmetic('4 × 6')).level).assertEqual(2)
      expect(resolveMathQuizLevel(arithmetic('7 × 8')).level).assertEqual(3)
      expect(resolveMathQuizLevel(arithmetic('3 × 7')).level).assertEqual(3)
      expect(resolveMathQuizLevel(arithmetic('20 × 3')).level).assertEqual(4)
      expect(resolveMathQuizLevel(arithmetic('23 × 3')).level).assertEqual(5)
      expect(resolveMathQuizLevel(arithmetic('27 × 3')).level).assertEqual(6)
      expect(resolveMathQuizLevel(arithmetic('23 × 4')).level).assertEqual(6)
      expect(resolveMathQuizLevel(arithmetic('213 × 3')).level).assertEqual(7)
      expect(resolveMathQuizLevel(arithmetic('12 ÷ 3')).level).assertEqual(8)
      expect(resolveMathQuizLevel(arithmetic('15 ÷ 5')).level).assertEqual(8)
      expect(resolveMathQuizLevel(arithmetic('24 ÷ 4')).level).assertEqual(8)
      expect(resolveMathQuizLevel(arithmetic('84 ÷ 4')).level).assertEqual(9)
      expect(resolveMathQuizLevel(arithmetic('369 ÷ 3')).level).assertEqual(10)
      expect(resolveMathQuizLevel(arithmetic('12 × 3 + 8')).level).assertEqual(10)
      expect(resolveMathQuizLevel(arithmetic('12 ÷ 3 + 8')).level).assertEqual(10)
    })

    it('rejects remainders and unsupported multiplication shapes', 0, () => {
      expect(resolveMathQuizLevel(arithmetic('10 ÷ 3')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('7 ÷ 2')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('12 ÷ 5 × 3')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('20 × 30')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('213 × 1')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('23 × 1')).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(arithmetic('5 ÷ 1')).error.length > 0).assertTrue()
    })
  })

  describe('resolveMathQuizLevel compare/clock/elapsed', () => {
    it('classifies comparison and clock levels', 0, () => {
      expect(resolveMathQuizLevel(comparison(5, 3)).level).assertEqual(1)
      expect(resolveMathQuizLevel(comparison(15, 3)).level).assertEqual(2)
      expect(resolveMathQuizLevel(comparison(999, 3)).level).assertEqual(4)
      expect(resolveMathQuizLevel(comparison(99999, 3)).level).assertEqual(6)
      expect(resolveMathQuizLevel(clock(3, 0)).level).assertEqual(1)
      expect(resolveMathQuizLevel(clock(3, 30)).level).assertEqual(2)
      expect(resolveMathQuizLevel(clock(3, 15)).level).assertEqual(3)
      expect(resolveMathQuizLevel(clock(3, 55)).level).assertEqual(4)
      expect(resolveMathQuizLevel(clock(3, 12)).error.length > 0).assertTrue()
    })

    it('classifies elapsed time levels and rejects invalid durations', 0, () => {
      expect(resolveMathQuizLevel(elapsed(3, 10, 3, 40)).level).assertEqual(1)
      expect(resolveMathQuizLevel(elapsed(3, 0, 4, 0)).level).assertEqual(2)
      expect(resolveMathQuizLevel(elapsed(3, 30, 4, 15)).level).assertEqual(3)
      expect(resolveMathQuizLevel(elapsed(11, 30, 1, 15)).level).assertEqual(4)
      expect(resolveMathQuizLevel(elapsed(3, 10, 3, 10)).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(elapsed(3, 40, 3, 10)).error.length > 0).assertTrue()
      expect(resolveMathQuizLevel(elapsed(3, 10, 3, 12)).error.length > 0).assertTrue()
    })

    it('handles shape and skill/type mismatches', 0, () => {
      const shape = resolveMathQuizLevel(arithmetic('', 'math_shapes'))
      expect(shape.gate).assertTrue()
      expect(shape.error.length > 0).assertTrue()
      const shapeInput: MathQuizLevelInput = {
        quizType: 'shape', expression: '', wordProblem: false, skillKey: 'math_shapes',
        leftValue: 0, rightValue: 0, clockHour: 0, clockMinute: 0,
        startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
      }
      const shapeOk = resolveMathQuizLevel(shapeInput)
      expect(shapeOk.track).assertEqual('shape')
      expect(shapeOk.gate).assertFalse()
      expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_shapes')).error.length > 0).assertTrue()
    })
  })

  describe('applyMathQuizProgress', () => {
    it('levels up on the 10th first-try correct', 0, () => {
      const up = applyMathQuizProgress(row(7, 9, 0), 7, 'practice', true, 1, Date.now())
      expect(up.counted).assertTrue()
      expect(up.row.currentLevel).assertEqual(8)
      expect(up.row.correctAtLevel).assertEqual(0)
      expect(up.row.consecutiveWrong).assertEqual(0)
      expect(up.status).assertEqual('level_up')
      expect(up.reason).assertEqual('first_try_correct')
    })

    it('keeps the level on a second-try correct but resets wrongs', 0, () => {
      const second = applyMathQuizProgress(row(7, 5, 1), 7, 'practice', true, 2, Date.now())
      expect(second.row.currentLevel).assertEqual(7)
      expect(second.row.correctAtLevel).assertEqual(5)
      expect(second.row.consecutiveWrong).assertEqual(0)
      expect(second.status).assertEqual('in_progress')
      expect(second.reason).assertEqual('second_try')
    })

    it('downgrades on the second two-wrong question and floors at 1', 0, () => {
      const wrong1 = applyMathQuizProgress(row(7, 5, 0), 7, 'practice', false, 2, Date.now())
      expect(wrong1.row.currentLevel).assertEqual(7)
      expect(wrong1.row.consecutiveWrong).assertEqual(1)
      const wrong2 = applyMathQuizProgress(row(7, 5, 1), 7, 'practice', false, 2, Date.now())
      expect(wrong2.row.currentLevel).assertEqual(6)
      expect(wrong2.row.correctAtLevel).assertEqual(0)
      expect(wrong2.row.consecutiveWrong).assertEqual(0)
      expect(wrong2.status).assertEqual('level_down')
      const floor = applyMathQuizProgress(row(1, 0, 1), 1, 'practice', false, 2, Date.now())
      expect(floor.row.currentLevel).assertEqual(1)
      expect(floor.row.consecutiveWrong).assertEqual(0)
    })

    it('caps at max level and downgrades from max on two wrongs', 0, () => {
      const max = applyMathQuizProgress(row(15, 9, 0), 15, 'practice', true, 1, Date.now())
      expect(max.row.currentLevel).assertEqual(15)
      expect(max.row.correctAtLevel).assertEqual(10)
      expect(max.status).assertEqual('max_level')
      const down = applyMathQuizProgress(row(15, 10, 1), 15, 'practice', false, 2, Date.now())
      expect(down.row.currentLevel).assertEqual(14)
      expect(down.status).assertEqual('level_down')
    })

    it('does not count warm_up, review, or stale-level answers', 0, () => {
      const warm = applyMathQuizProgress(row(7, 5, 0), 6, 'warm_up', true, 1, Date.now())
      expect(warm.counted).assertFalse()
      expect(warm.row.currentLevel).assertEqual(7)
      expect(warm.status).assertEqual('not_counted')
      expect(warm.reason).assertEqual('warm_up')
      const review = applyMathQuizProgress(row(7, 5, 0), 7, 'review', true, 1, Date.now())
      expect(review.reason).assertEqual('review')
      const stale = applyMathQuizProgress(row(7, 5, 0), 6, 'practice', true, 1, Date.now())
      expect(stale.reason).assertEqual('stale_level')
    })

    it('resets consecutive_wrong after 24 hours', 0, () => {
      const now = Date.now()
      const old = now - 25 * 60 * 60 * 1000
      const reset = applyMathQuizProgress(row(7, 5, 1, old), 7, 'practice', false, 2, now)
      expect(reset.row.currentLevel).assertEqual(7)
      expect(reset.row.consecutiveWrong).assertEqual(1)
    })

    it('builds a hint with the current target', 0, () => {
      const up = applyMathQuizProgress(row(7, 9, 0), 7, 'practice', true, 1, Date.now())
      const hint = buildMathQuizProgressHint(up, 'add', 10)
      expect(hint !== null).assertTrue()
      const h = hint as MathQuizProgressHint
      expect(h.level).assertEqual(8)
      expect(h.level_label).assertEqual('1000 以内进位/退位')
      expect(h.needed).assertEqual(10)
      expect(h.next_target.level).assertEqual(8)
    })
  })

  describe('evaluateMathQuizGate', () => {
    it('rejects practice below and above the target level', 0, () => {
      const info5 = resolveMathQuizLevel(arithmetic('47 + 28'))
      const info9 = resolveMathQuizLevel(arithmetic('487 + 265 − 130'))
      const easy = evaluateMathQuizGate(gateInput(info5, 'practice', 7, [], 0, 's1'))
      expect(easy.allowed).assertFalse()
      expect(easy.error).assertEqual('difficulty_gate')
      expect(easy.target !== null).assertTrue()
      const hard = evaluateMathQuizGate(gateInput(info9, 'practice', 7, [], 0, 's1'))
      expect(hard.error).assertEqual('difficulty_gate')
    })

    it('rejects a recent duplicate only for practice', 0, () => {
      const info7 = resolveMathQuizLevel(arithmetic('213 + 124'))
      const dup = evaluateMathQuizGate(gateInput(info7, 'practice', 7, [info7.expressionKey], 0, 's1'))
      expect(dup.error).assertEqual('duplicate_question')
      const review = evaluateMathQuizGate(gateInput(info7, 'review', 7, [info7.expressionKey], 0, 's1'))
      expect(review.allowed).assertTrue()
    })

    it('allows lower warm_up/review within quota and rejects over quota', 0, () => {
      const info5 = resolveMathQuizLevel(arithmetic('47 + 28'))
      expect(evaluateMathQuizGate(gateInput(info5, 'warm_up', 7, [], 0, 's1')).allowed).assertTrue()
      expect(evaluateMathQuizGate(gateInput(info5, 'warm_up', 7, [], 5, 's1')).error).assertEqual('purpose_quota_exceeded')
      expect(evaluateMathQuizGate(gateInput(info5, 'review', 7, [], 3, 's1')).error).assertEqual('purpose_quota_exceeded')
      expect(evaluateMathQuizGate(gateInput(info5, 'warm_up', 7, [], 99, '')).allowed).assertTrue()
    })

    it('rejects warm_up above the target and surfaces structural errors', 0, () => {
      const info8 = resolveMathQuizLevel(arithmetic('487 + 265'))
      expect(evaluateMathQuizGate(gateInput(info8, 'warm_up', 7, [], 0, 's1')).error).assertEqual('difficulty_gate')
      const bad = resolveMathQuizLevel(arithmetic('', 'math_addition'))
      const decision = evaluateMathQuizGate(gateInput(bad, 'practice', 4, [], 0, 's1'))
      expect(decision.allowed).assertFalse()
      expect(decision.error).assertEqual('difficulty_gate')
      expect(decision.message.length > 0).assertTrue()
    })

    it('does not lock a small key domain after every key was recently used', 0, () => {
      const info = resolveMathQuizLevel(clock(3, 0))
      expect(info.track).assertEqual('clock')
      expect(info.level).assertEqual(1)
      const keys: string[] = []
      for (let hour = 1; hour <= 12; hour++) {
        keys.push(`clock:${hour}:0`)
      }
      const decision = evaluateMathQuizGate(gateInput(info, 'practice', 1, keys, 0, 's1'))
      expect(decision.allowed).assertTrue()
    })

    it('still rejects a duplicate inside a large key domain', 0, () => {
      const info = resolveMathQuizLevel(arithmetic('213 + 124'))
      const keys: string[] = []
      for (let i = 0; i < 19; i++) {
        keys.push(`other:${i}`)
      }
      keys.push(info.expressionKey)
      const decision = evaluateMathQuizGate(gateInput(info, 'practice', 7, keys, 0, 's1'))
      expect(decision.error).assertEqual('duplicate_question')
    })

    it('gives a missing-expression error an executable target when skill_key names a track', 0, () => {
      const bad = resolveMathQuizLevel(arithmetic('', 'math_addition'))
      expect(bad.track).assertEqual('add')
      const decision = evaluateMathQuizGate(gateInput(bad, 'practice', 4, [], 0, 's1'))
      expect(decision.error).assertEqual('difficulty_gate')
      expect(decision.target !== null).assertTrue()
      if (decision.target !== null) {
        expect(decision.target.level).assertEqual(4)
      }
    })
  })
}
