/**
 * math_quiz 难度渐进 — 纯函数层
 *
 * 规格见 docs/superpowers/specs/2026-11-05-math-quiz-progression-design.md。
 * 本文件不含 IO: 级别判定、进度状态机、出题闸门全部是纯函数,
 * 可在 hypium (或离线 Node harness) 中直接单测。
 */

import {
  computeElapsedDuration, normalizeExpressionText, normalizeQuizType, sanitizeExpression, tokenizeExpression,
  tryEvaluateExpression
} from './MathQuizGame'
import type { ExpressionToken } from './MathQuizGame'
import type {
  MathQuizGateDecision, MathQuizGateInput, MathQuizLevelInfo, MathQuizLevelInput, MathQuizLevelSpec,
  MathQuizProgressHint, MathQuizProgressReason, MathQuizProgressRow, MathQuizProgressStatus,
  MathQuizProgressUpdate, MathQuizPurpose, MathQuizTarget, MathQuizTrack
} from '../models/MathQuizProgressionModels'

/** 同一级别累计首答正确多少次即视为掌握、升一级。 */
export const MATH_QUIZ_NEEDED_CORRECT: number = 10

/** 出题闸门回查的历史窗口（每轨最近 N 条）。 */
export const MATH_QUIZ_RECENT_LIMIT: number = 20

/** 每个会话允许的 warm_up 题数上限。 */
export const MATH_QUIZ_WARM_UP_LIMIT: number = 5

/** 每个会话允许的 review 题数上限。 */
export const MATH_QUIZ_REVIEW_LIMIT: number = 3

/** 连续两错计数超过这个时长没有新作答则重新计（跨天重置）。 */
export const MATH_QUIZ_WRONG_RESET_MS: number = 24 * 60 * 60 * 1000

interface LevelRow {
  level: number
  label: string
  maxOperand: number
  minSteps: number
  maxSteps: number
  carryRule: 'none' | 'required' | 'any'
  constraint: string
  example: string
}

function row(level: number, label: string, maxOperand: number, minSteps: number, maxSteps: number,
             carryRule: 'none' | 'required' | 'any', constraint: string, example: string): LevelRow {
  const r: LevelRow = {
    level: level, label: label, maxOperand: maxOperand, minSteps: minSteps, maxSteps: maxSteps,
    carryRule: carryRule, constraint: constraint, example: example
  }
  return r
}

/** 加减轨 15 级（到万位）——spec §4.2。 */
const ADD_SUB_ROWS: LevelRow[] = [
  row(1, '10 以内一步', 10, 1, 1, 'any', '', '7 + 2'),
  row(2, '20 以内不进位/不退位', 20, 1, 1, 'none', '', '12 + 5'),
  row(3, '20 以内进位/退位或两步混合', 20, 1, 3, 'any', '', '8 + 7'),
  row(4, '100 以内不进位/不退位', 100, 1, 1, 'none', '', '23 + 14'),
  row(5, '100 以内进位/退位', 100, 1, 1, 'required', '', '47 + 28'),
  row(6, '100 以内两步混合', 100, 2, 3, 'any', '', '47 + 28 − 15'),
  row(7, '1000 以内不进位/不退位', 999, 1, 1, 'none', '', '213 + 124'),
  row(8, '1000 以内进位/退位', 999, 1, 1, 'required', '', '487 + 265'),
  row(9, '1000 以内两步混合', 999, 2, 3, 'any', '', '487 + 265 − 130'),
  row(10, '10000 以内不进位/不退位', 9999, 1, 1, 'none', '', '2134 + 1243'),
  row(11, '10000 以内进位/退位', 9999, 1, 1, 'required', '', '4876 + 2657'),
  row(12, '10000 以内两步混合', 9999, 2, 3, 'any', '', '4876 + 2657 − 1304'),
  row(13, '100000 以内不进位/不退位', 99999, 1, 1, 'none', '', '21345 + 12432'),
  row(14, '100000 以内进位/退位', 99999, 1, 1, 'required', '', '48765 + 26578'),
  row(15, '100000 以内两步混合', 99999, 2, 3, 'any', '', '48765 + 26578 − 13042')
]

/** 乘除轨 10 级——spec §4.3。 */
const MULDIV_ROWS: LevelRow[] = [
  row(1, '2/5/10 表内乘法', 0, 1, 1, 'any', '', '2 × 2'),
  row(2, '3/4/6 表内乘法', 0, 1, 1, 'any', '', '2 × 3'),
  row(3, '7/8/9 表内乘法', 0, 1, 1, 'any', '', '7 × 8'),
  row(4, '整十数 × 一位数', 0, 1, 1, 'any', '', '20 × 3'),
  row(5, '两位数 × 一位数不进位', 0, 1, 1, 'any', '', '23 × 3'),
  row(6, '两位数 × 一位数含进位', 0, 1, 1, 'any', '', '27 × 3'),
  row(7, '三位数 × 一位数', 0, 1, 1, 'any', '', '213 × 3'),
  row(8, '表内除法', 0, 1, 1, 'any', '', '15 ÷ 5'),
  row(9, '两位数 ÷ 一位数', 0, 1, 1, 'any', '', '84 ÷ 4'),
  row(10, '三位数 ÷ 一位数或两步混合', 0, 1, 3, 'any', '', '369 ÷ 3')
]

/** 比较轨 6 级——spec §4.4。 */
const COMPARE_ROWS: LevelRow[] = [
  row(1, '比较两个数的大小', 10, 0, 0, 'any', '比较两个数的大小，数值不超过 10', '5 ○ 3'),
  row(2, '比较两个数的大小', 20, 0, 0, 'any', '比较两个数的大小，数值不超过 20', '15 ○ 3'),
  row(3, '比较两个数的大小', 100, 0, 0, 'any', '比较两个数的大小，数值不超过 100', '47 ○ 28'),
  row(4, '比较两个数的大小', 999, 0, 0, 'any', '比较两个数的大小，数值不超过 999', '213 ○ 124'),
  row(5, '比较两个数的大小', 9999, 0, 0, 'any', '比较两个数的大小，数值不超过 9999', '2134 ○ 1243'),
  row(6, '比较两个数的大小', 99999, 0, 0, 'any', '比较两个数的大小，数值不超过 99999', '21345 ○ 12432')
]

/** 认钟轨 4 级——spec §4.4。 */
const CLOCK_ROWS: LevelRow[] = [
  row(1, '整点', 0, 0, 0, 'any', '整点，分钟为 0', '3:00'),
  row(2, '半点', 0, 0, 0, 'any', '半点，分钟为 30', '3:30'),
  row(3, '5 分刻度（非临近整点）', 0, 0, 0, 'any', '分钟为 10/15/20/25/35/40/45/50 之一', '3:15'),
  row(4, '临近整点（差几分）', 0, 0, 0, 'any', '分钟为 5 或 55（临近整点）', '3:55')
]

/** 经过时间轨 4 级——spec §4.4。 */
const ELAPSED_ROWS: LevelRow[] = [
  row(1, '同一小时内', 0, 0, 0, 'any', '起止在同一小时，分钟差为 5–55 的 5 的倍数', '3:10 → 3:40'),
  row(2, '跨整点、分钟相同', 0, 0, 0, 'any', '跨一个整点，起止分钟相同', '3:00 → 4:00'),
  row(3, '跨整点、分钟不同', 0, 0, 0, 'any', '跨一个整点，起止分钟不同', '3:30 → 4:15'),
  row(4, '跨 2 小时以上或跨 12 点', 0, 0, 0, 'any', '跨 ≥2 小时，或跨 12 点', '11:30 → 1:15')
]

const SKILL_ALIASES: Record<string, string> = {
  'addition': 'math_addition',
  'subtraction': 'math_subtraction',
  'multiply': 'math_multiply',
  'divide': 'math_divide',
  'shapes': 'math_shapes',
  'comparison': 'math_comparison',
  'time': 'math_time',
  'counting': 'math_counting',
  'number_sense': 'math_number_sense',
  'word_problem': 'math_word_problem',
  'math_counting': 'math_counting',
  'math_number_sense': 'math_number_sense',
  'math_addition': 'math_addition',
  'math_subtraction': 'math_subtraction',
  'math_multiply': 'math_multiply',
  'math_divide': 'math_divide',
  'math_shapes': 'math_shapes',
  'math_comparison': 'math_comparison',
  'math_time': 'math_time',
  'math_word_problem': 'math_word_problem'
}

// 画像 level 0–5 直接做下标（index level，不是 level+1）。
const ADD_SUB_INIT: number[] = [1, 2, 3, 5, 8, 11]
const MUL_INIT: number[] = [1, 1, 3, 5, 6, 7]
const DIV_INIT: number[] = [1, 1, 8, 9, 10, 10]
const COMPARE_INIT: number[] = [1, 2, 3, 4, 5, 6]
const TIME_INIT: number[] = [1, 1, 2, 2, 3, 4]

export function normalizePurpose(raw: string): MathQuizPurpose {
  const text: string = typeof raw === 'string' ? raw.trim().toLowerCase() : ''
  if (text === 'warm_up' || text === 'warmup' || text === 'warm-up') {
    return 'warm_up'
  }
  if (text === 'review') {
    return 'review'
  }
  return 'practice'
}

export function normalizeSkillKey(raw: string): string {
  if (typeof raw !== 'string') {
    return ''
  }
  const text: string = raw.trim()
  if (text === '') {
    return ''
  }
  const mapped: Object | undefined = SKILL_ALIASES[text]
  return mapped === undefined ? '' : mapped as string
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

export function normalizeExpressionKey(input: MathQuizLevelInput): string {
  if (input.quizType === 'comparison') {
    return `cmp:${input.leftValue}:${input.rightValue}`
  }
  if (input.quizType === 'time') {
    return `clock:${input.clockHour}:${input.clockMinute}`
  }
  if (input.quizType === 'elapsed_time') {
    return `elapsed:${input.startHour}:${input.startMinute}-${input.endHour}:${input.endMinute}`
  }
  const sanitized: string = sanitizeExpression(normalizeExpressionText(input.expression))
  if (sanitized === '') {
    return ''
  }
  return sanitized.replace(/×/g, '*').replace(/÷/g, '/')
}

export function buildMathQuizRecordExpression(input: MathQuizLevelInput): string {
  if (input.quizType === 'comparison') {
    return `${input.leftValue} ? ${input.rightValue}`
  }
  if (input.quizType === 'time') {
    return `${input.clockHour}:${pad2(input.clockMinute)}`
  }
  if (input.quizType === 'elapsed_time') {
    return `${input.startHour}:${pad2(input.startMinute)} → ${input.endHour}:${pad2(input.endMinute)}`
  }
  return input.expression
}

export function getMaxLevel(track: MathQuizTrack): number {
  if (track === 'add' || track === 'sub') {
    return ADD_SUB_ROWS.length
  }
  if (track === 'muldiv') {
    return MULDIV_ROWS.length
  }
  if (track === 'compare') {
    return COMPARE_ROWS.length
  }
  if (track === 'clock') {
    return CLOCK_ROWS.length
  }
  if (track === 'elapsed') {
    return ELAPSED_ROWS.length
  }
  return 0
}

function rowsForTrack(track: MathQuizTrack): LevelRow[] {
  if (track === 'add' || track === 'sub') {
    return ADD_SUB_ROWS
  }
  if (track === 'muldiv') {
    return MULDIV_ROWS
  }
  if (track === 'compare') {
    return COMPARE_ROWS
  }
  if (track === 'clock') {
    return CLOCK_ROWS
  }
  if (track === 'elapsed') {
    return ELAPSED_ROWS
  }
  return []
}

export function getLevelSpec(track: MathQuizTrack, level: number): MathQuizLevelSpec | null {
  const rows: LevelRow[] = rowsForTrack(track)
  if (rows.length === 0 || !Number.isInteger(level) || level < 1 || level > rows.length) {
    return null
  }
  const source: LevelRow = rows[level - 1]
  const spec: MathQuizLevelSpec = {
    track: track,
    level: source.level,
    label: source.label,
    maxOperand: source.maxOperand,
    minSteps: source.minSteps,
    maxSteps: source.maxSteps,
    carryRule: source.carryRule,
    constraint: source.constraint,
    example: source.example
  }
  return spec
}

export function getTrackLabel(track: MathQuizTrack): string {
  if (track === 'add') {
    return '加法'
  }
  if (track === 'sub') {
    return '减法'
  }
  if (track === 'muldiv') {
    return '乘除'
  }
  if (track === 'compare') {
    return '比较'
  }
  if (track === 'clock') {
    return '认钟'
  }
  if (track === 'elapsed') {
    return '经过时间'
  }
  if (track === 'shape') {
    return '图形'
  }
  return '数数'
}

export function buildTarget(spec: MathQuizLevelSpec): MathQuizTarget {
  const track: MathQuizTrack = spec.track
  if (track === 'add' || track === 'sub' || track === 'muldiv') {
    const steps: string = spec.minSteps === spec.maxSteps
      ? `${spec.minSteps}`
      : `${spec.minSteps}-${spec.maxSteps}`
    if (track === 'muldiv') {
      const muldivTarget: MathQuizTarget = {
        track: track, level: spec.level, label: spec.label, steps: steps,
        carry: spec.carryRule, example: spec.example
      }
      return muldivTarget
    }
    const arithmeticTarget: MathQuizTarget = {
      track: track, level: spec.level, label: spec.label, max_operand: spec.maxOperand,
      steps: steps, carry: spec.carryRule, example: spec.example
    }
    return arithmeticTarget
  }
  const constraintTarget: MathQuizTarget = {
    track: track, level: spec.level, label: spec.label,
    constraint: spec.constraint, example: spec.example
  }
  return constraintTarget
}

function clampProfileLevel(value: number): number {
  if (!Number.isFinite(value) || Number.isNaN(value)) {
    return 0
  }
  const rounded: number = Math.floor(value)
  if (rounded < 0) {
    return 0
  }
  if (rounded > 5) {
    return 5
  }
  return rounded
}

function readLevel(levels: Record<string, number>, key: string): number {
  const raw: Object | undefined = levels[key]
  if (raw === undefined || raw === null) {
    return 0
  }
  const value: number = raw as number
  return clampProfileLevel(value)
}

export function initialLevelForTrack(track: MathQuizTrack, levels: Record<string, number>): number {
  if (track === 'add' || track === 'sub') {
    const ownKey: string = track === 'add' ? 'math_addition' : 'math_subtraction'
    const siblingKey: string = track === 'add' ? 'math_subtraction' : 'math_addition'
    const own: number = readLevel(levels, ownKey)
    if (own > 0) {
      return ADD_SUB_INIT[own]
    }
    const sibling: number = readLevel(levels, siblingKey)
    if (sibling > 0) {
      return Math.max(1, ADD_SUB_INIT[sibling] - 1)
    }
    return 1
  }
  if (track === 'muldiv') {
    const mul: number = readLevel(levels, 'math_multiply')
    const div: number = readLevel(levels, 'math_divide')
    if (mul === 0 && div === 0) {
      return 1
    }
    return Math.max(MUL_INIT[mul], DIV_INIT[div])
  }
  if (track === 'compare') {
    return COMPARE_INIT[readLevel(levels, 'math_comparison')]
  }
  if (track === 'clock' || track === 'elapsed') {
    return TIME_INIT[readLevel(levels, 'math_time')]
  }
  return 0
}

// ---------------------------------------------------------------------------
// 题目级别判定（Task 2）
// ---------------------------------------------------------------------------

export interface MathQuizGatingArgs {
  input: MathQuizLevelInput
  purpose: MathQuizPurpose
}

function rawString(raw: Record<string, Object>, key: string): string {
  const value: Object | undefined = raw[key]
  return typeof value === 'string' ? value as string : ''
}

function rawNumber(raw: Record<string, Object>, key: string): number {
  const value: Object | undefined = raw[key]
  if (value === undefined || value === null) {
    return 0
  }
  const n: number = Number(value)
  return Number.isFinite(n) ? n : 0
}

export function buildMathQuizLevelInput(raw: Record<string, Object>): MathQuizLevelInput {
  const wordProblemRaw: Object | undefined = raw['word_problem']
  const input: MathQuizLevelInput = {
    quizType: normalizeQuizType(rawString(raw, 'type')),
    expression: rawString(raw, 'expression'),
    wordProblem: wordProblemRaw === true || wordProblemRaw === 'true',
    skillKey: rawString(raw, 'skill_key'),
    leftValue: rawNumber(raw, 'left_value'),
    rightValue: rawNumber(raw, 'right_value'),
    clockHour: rawNumber(raw, 'clock_hour'),
    clockMinute: rawNumber(raw, 'clock_minute'),
    startHour: rawNumber(raw, 'start_hour'),
    startMinute: rawNumber(raw, 'start_minute'),
    endHour: rawNumber(raw, 'end_hour'),
    endMinute: rawNumber(raw, 'end_minute')
  }
  return input
}

export function parseMathQuizGatingArgs(argsJson: string): MathQuizGatingArgs | null {
  try {
    const raw: Record<string, Object> = JSON.parse(argsJson) as Record<string, Object>
    if (raw === null || raw === undefined) {
      return null
    }
    const result: MathQuizGatingArgs = {
      input: buildMathQuizLevelInput(raw),
      purpose: normalizePurpose(rawString(raw, 'purpose'))
    }
    return result
  } catch (_e) {
    return null
  }
}

function okInfo(track: MathQuizTrack, level: number, input: MathQuizLevelInput): MathQuizLevelInfo {
  const spec: MathQuizLevelSpec | null = getLevelSpec(track, level)
  const info: MathQuizLevelInfo = {
    track: track, level: level, gate: true, spec: spec,
    expressionKey: normalizeExpressionKey(input), error: ''
  }
  return info
}

function errInfo(track: MathQuizTrack, message: string, input: MathQuizLevelInput): MathQuizLevelInfo {
  const key: string = (track === 'none' || track === 'shape') ? '' : normalizeExpressionKey(input)
  const info: MathQuizLevelInfo = {
    track: track, level: 0, gate: true, spec: null, expressionKey: key, error: message
  }
  return info
}

function passInfo(track: MathQuizTrack, input: MathQuizLevelInput): MathQuizLevelInfo {
  const info: MathQuizLevelInfo = {
    track: track, level: 0, gate: false, spec: null, expressionKey: '', error: ''
  }
  return info
}

function isArithmeticSkill(skill: string): boolean {
  return skill === 'math_addition' || skill === 'math_subtraction' || skill === 'math_multiply' ||
    skill === 'math_divide' || skill === 'math_word_problem'
}

function trackForArithmeticSkill(skill: string): MathQuizTrack {
  if (skill === 'math_addition') {
    return 'add'
  }
  if (skill === 'math_subtraction') {
    return 'sub'
  }
  if (skill === 'math_multiply' || skill === 'math_divide') {
    return 'muldiv'
  }
  return 'none'
}

function mismatchError(skill: string, quizType: string): string {
  return `skill_key「${skill}」与题型「${quizType}」不匹配，请改用与该题型一致的知识点`
}

function bestEffortTrack(quizType: string, expression: string): MathQuizTrack {
  if (quizType !== 'arithmetic') {
    return 'none'
  }
  const text: string = normalizeExpressionText(expression)
  if (text.indexOf('×') >= 0 || text.indexOf('÷') >= 0 || text.indexOf('*') >= 0 || text.indexOf('/') >= 0) {
    return 'muldiv'
  }
  if (text.indexOf('+') < 0 && text.indexOf('-') >= 0) {
    return 'sub'
  }
  return 'add'
}

function hasCarry(a: number, b: number): boolean {
  let x: number = Math.abs(Math.floor(a))
  let y: number = Math.abs(Math.floor(b))
  while (x > 0 || y > 0) {
    if ((x % 10) + (y % 10) > 9) {
      return true
    }
    x = Math.floor(x / 10)
    y = Math.floor(y / 10)
  }
  return false
}

function hasBorrow(a: number, b: number): boolean {
  let x: number = Math.abs(Math.floor(a))
  let y: number = Math.abs(Math.floor(b))
  while (x > 0 || y > 0) {
    if (x % 10 < y % 10) {
      return true
    }
    x = Math.floor(x / 10)
    y = Math.floor(y / 10)
  }
  return false
}

function hasMulCarry(a: number, b: number): boolean {
  const multiplicand: number = Math.max(Math.abs(a), Math.abs(b))
  const multiplier: number = Math.min(Math.abs(a), Math.abs(b))
  let x: number = multiplicand
  while (x > 0) {
    if ((x % 10) * multiplier > 9) {
      return true
    }
    x = Math.floor(x / 10)
  }
  return false
}

function mulTableLevel(maxFactor: number): number {
  if (maxFactor === 2 || maxFactor === 5 || maxFactor === 10) {
    return 1
  }
  if (maxFactor === 3 || maxFactor === 4 || maxFactor === 6) {
    return 2
  }
  return 3
}

function isBetween(v: number, min: number, max: number): boolean {
  return Number.isInteger(v) && v >= min && v <= max
}

function classifyMulDiv(input: MathQuizLevelInput, values: number[], ops: string[],
                        hasTimes: boolean, hasDivide: boolean): MathQuizLevelInfo {
  const skill: string = normalizeSkillKey(input.skillKey)
  if (skill === 'math_addition' || skill === 'math_subtraction') {
    return errInfo('muldiv', mismatchError(skill, 'arithmetic'), input)
  }
  if (skill === 'math_multiply' && hasDivide) {
    return errInfo('muldiv', 'skill_key 是乘法，但算式里出现了除号', input)
  }
  if (skill === 'math_divide' && hasTimes) {
    return errInfo('muldiv', 'skill_key 是除法，但算式里出现了乘号', input)
  }
  if (ops.length >= 2) {
    for (let i = 0; i + 1 < values.length; i++) {
      if (ops[i] === '/' || ops[i] === '÷') {
        const divisor: number = values[i + 1]
        if (divisor === 0 || values[i] % divisor !== 0) {
          return errInfo('muldiv', '除法必须整除，不能有余数', input)
        }
      }
    }
    const final: number | null = tryEvaluateExpression(normalizeExpressionText(input.expression))
    if (final === null || !Number.isFinite(final)) {
      return errInfo('muldiv', '算式无法计算，请检查后重试', input)
    }
    return okInfo('muldiv', 10, input)
  }
  if (values.length !== 2) {
    return errInfo('muldiv', '乘除题必须是一个运算符连接两个整数', input)
  }
  const a: number = values[0]
  const b: number = values[1]
  if (!Number.isInteger(a) || !Number.isInteger(b)) {
    return errInfo('muldiv', '乘除题的操作数必须是整数', input)
  }
  if (hasTimes) {
    if (a === 0 || b === 0) {
      return okInfo('muldiv', 1, input)
    }
    if (a < 1 || b < 1) {
      return errInfo('muldiv', '乘法的操作数不能为负数', input)
    }
    if (isBetween(a, 1, 10) && isBetween(b, 1, 10)) {
      if (a === 1 || b === 1) {
        return okInfo('muldiv', 1, input)
      }
      return okInfo('muldiv', mulTableLevel(Math.max(a, b)), input)
    }
    const big: number = Math.max(a, b)
    const small: number = Math.min(a, b)
    if (isBetween(small, 2, 9)) {
      if (isBetween(big, 20, 90) && big % 10 === 0) {
        return okInfo('muldiv', 4, input)
      }
      if (isBetween(big, 10, 99)) {
        return okInfo('muldiv', hasMulCarry(big, small) ? 6 : 5, input)
      }
      if (isBetween(big, 100, 999)) {
        return okInfo('muldiv', 7, input)
      }
    }
    return errInfo('muldiv', '暂不支持这个乘法形状：乘数须为一位数（2–9），被乘数不超过三位数', input)
  }
  // 除法
  const divisor: number = b
  if (!isBetween(divisor, 2, 10)) {
    return errInfo('muldiv', '除法的除数必须是 2–10 的整数', input)
  }
  if (!Number.isInteger(a) || a % divisor !== 0) {
    return errInfo('muldiv', '除法必须整除，不能有余数', input)
  }
  const quotient: number = a / divisor
  if (isBetween(quotient, 1, 10)) {
    return okInfo('muldiv', 8, input)
  }
  if (isBetween(a, 10, 99) && isBetween(divisor, 2, 9)) {
    return okInfo('muldiv', 9, input)
  }
  if (isBetween(a, 100, 999) && isBetween(divisor, 2, 9)) {
    return okInfo('muldiv', 10, input)
  }
  return errInfo('muldiv', '暂不支持这个除法形状：被除数不超过三位数，除数 2–9', input)
}

function classifyAddSub(input: MathQuizLevelInput, values: number[], ops: string[],
                        hasPlus: boolean, hasMinus: boolean, hasParen: boolean): MathQuizLevelInfo {
  const skill: string = normalizeSkillKey(input.skillKey)
  if (skill === 'math_multiply' || skill === 'math_divide') {
    return errInfo('muldiv', mismatchError(skill, 'arithmetic'), input)
  }
  if (skill === 'math_addition' && !hasPlus) {
    return errInfo('add', 'skill_key 是加法，但算式里没有加号', input)
  }
  if (skill === 'math_subtraction' && !hasMinus) {
    return errInfo('sub', 'skill_key 是减法，但算式里没有减号', input)
  }
  const track: MathQuizTrack = skill === 'math_subtraction' ? 'sub'
    : (skill === 'math_addition' ? 'add' : (hasMinus && !hasPlus ? 'sub' : 'add'))
  const expr: string = normalizeExpressionText(input.expression)
  const final: number | null = tryEvaluateExpression(expr)
  if (final === null || !Number.isFinite(final)) {
    return errInfo(track, '算式无法计算，请检查后重试', input)
  }
  if (final < 0) {
    return errInfo(track, '中间结果不能为负数', input)
  }
  let maxAbs: number = Math.abs(final)
  for (let i = 0; i < values.length; i++) {
    maxAbs = Math.max(maxAbs, Math.abs(values[i]))
  }
  if (!hasParen) {
    let acc: number = values.length > 0 ? values[0] : 0
    for (let i = 0; i < ops.length; i++) {
      const operand: number = values[i + 1]
      acc = ops[i] === '+' ? acc + operand : acc - operand
      if (acc < 0) {
        return errInfo(track, '中间结果不能为负数', input)
      }
      maxAbs = Math.max(maxAbs, Math.abs(acc))
    }
  }
  if (maxAbs > 99999) {
    return errInfo(track, '最高到 5 位数，中间结果也不能超过 99999', input)
  }
  const steps: number = ops.length
  let carry: boolean = false
  if (steps === 1 && values.length === 2) {
    carry = ops[0] === '+' ? hasCarry(values[0], values[1]) : hasBorrow(values[0], values[1])
  }
  let level: number = 1
  if (maxAbs <= 10 && steps === 1 && final <= 10) {
    level = 1
  } else if (maxAbs <= 20) {
    level = (steps >= 2 || carry) ? 3 : 2
  } else if (maxAbs <= 100) {
    level = steps >= 2 ? 6 : (carry ? 5 : 4)
  } else if (maxAbs <= 999) {
    level = steps >= 2 ? 9 : (carry ? 8 : 7)
  } else if (maxAbs <= 9999) {
    level = steps >= 2 ? 12 : (carry ? 11 : 10)
  } else {
    level = steps >= 2 ? 15 : (carry ? 14 : 13)
  }
  return okInfo(track, level, input)
}

const CLOCK_ERROR: string = '认钟的分钟必须是 0–55 的 5 的倍数（如 0/5/…/55），小时 1–12'
const ELAPSED_ERROR: string = '时长必须大于 0，且不能倒着走'

function validClock(hour: number, minute: number): boolean {
  return Number.isInteger(hour) && hour >= 1 && hour <= 12 && Number.isInteger(minute) &&
    minute >= 0 && minute <= 55 && minute % 5 === 0
}

function classifyClock(input: MathQuizLevelInput): MathQuizLevelInfo {
  if (!validClock(input.clockHour, input.clockMinute)) {
    return errInfo('clock', CLOCK_ERROR, input)
  }
  const minute: number = input.clockMinute
  let level: number = 3
  if (minute === 0) {
    level = 1
  } else if (minute === 30) {
    level = 2
  } else if (minute === 5 || minute === 55) {
    level = 4
  }
  return okInfo('clock', level, input)
}

function classifyElapsed(input: MathQuizLevelInput): MathQuizLevelInfo {
  if (!validClock(input.startHour, input.startMinute) || !validClock(input.endHour, input.endMinute)) {
    return errInfo('elapsed', CLOCK_ERROR, input)
  }
  const sameHour: boolean = input.startHour === input.endHour
  if (sameHour && input.endMinute <= input.startMinute) {
    return errInfo('elapsed', ELAPSED_ERROR, input)
  }
  const duration = computeElapsedDuration(input.startHour, input.startMinute, input.endHour, input.endMinute)
  const total: number = duration.hours * 60 + duration.minutes
  if (total <= 0) {
    return errInfo('elapsed', ELAPSED_ERROR, input)
  }
  if (sameHour) {
    return okInfo('elapsed', 1, input)
  }
  const startTotal: number = input.startHour * 60 + input.startMinute
  const endTotal: number = input.endHour * 60 + input.endMinute
  if (total >= 120 || endTotal < startTotal) {
    return okInfo('elapsed', 4, input)
  }
  if (input.startMinute === input.endMinute) {
    return okInfo('elapsed', 2, input)
  }
  return okInfo('elapsed', 3, input)
}

function classifyComparison(input: MathQuizLevelInput): MathQuizLevelInfo {
  const left: number = input.leftValue
  const right: number = input.rightValue
  if (!Number.isFinite(left) || !Number.isFinite(right) || left < 0 || right < 0) {
    return errInfo('compare', '比较的两个数必须是非负整数', input)
  }
  const maxValue: number = Math.max(left, right)
  if (maxValue > 99999) {
    return errInfo('compare', '比较的两个数不能超过 99999', input)
  }
  let level: number = 6
  if (maxValue <= 10) {
    level = 1
  } else if (maxValue <= 20) {
    level = 2
  } else if (maxValue <= 100) {
    level = 3
  } else if (maxValue <= 999) {
    level = 4
  } else if (maxValue <= 9999) {
    level = 5
  }
  return okInfo('compare', level, input)
}

function classifyArithmetic(input: MathQuizLevelInput): MathQuizLevelInfo {
  const skill: string = normalizeSkillKey(input.skillKey)
  const expr: string = normalizeExpressionText(input.expression)
  const sanitized: string = sanitizeExpression(expr)
  if (sanitized === '') {
    if (skill === 'math_counting' || skill === 'math_number_sense') {
      return passInfo('none', input)
    }
    return errInfo(trackForArithmeticSkill(skill),
      '算术题必须填 expression（应用题也要填隐藏算式，如「3 + 2」；卡片只显示 question）', input)
  }
  const tokens: ExpressionToken[] = tokenizeExpression(sanitized)
  const values: number[] = []
  const ops: string[] = []
  for (let i = 0; i < tokens.length; i++) {
    const token: ExpressionToken = tokens[i]
    if (token.type === 'number') {
      if (token.value.indexOf('.') >= 0) {
        return passInfo('none', input)
      }
      values.push(Number(token.value))
    } else if (token.value === '+' || token.value === '-' || token.value === '*' ||
      token.value === '/' || token.value === '×' || token.value === '÷') {
      const prev: ExpressionToken | null = i > 0 ? tokens[i - 1] : null
      const atStart: boolean = prev === null
      const afterOperator: boolean = prev !== null && prev.type === 'op' && prev.value !== ')'
      if (token.value === '-' && (atStart || afterOperator)) {
        return errInfo('none', '算式不能包含负数的操作数，请换成两个非负数的加减', input)
      }
      ops.push(token.value)
    }
  }
  const steps: number = ops.length
  if (steps === 0) {
    return passInfo('none', input)
  }
  if (steps > 3) {
    return errInfo('none', '最多 3 个运算符', input)
  }
  let hasPlus: boolean = false
  let hasMinus: boolean = false
  let hasTimes: boolean = false
  let hasDivide: boolean = false
  for (let i = 0; i < ops.length; i++) {
    const op: string = ops[i]
    if (op === '+') {
      hasPlus = true
    } else if (op === '-') {
      hasMinus = true
    } else if (op === '*' || op === '×') {
      hasTimes = true
    } else {
      hasDivide = true
    }
  }
  if (hasTimes || hasDivide) {
    return classifyMulDiv(input, values, ops, hasTimes, hasDivide)
  }
  const hasParen: boolean = sanitized.indexOf('(') >= 0
  return classifyAddSub(input, values, ops, hasPlus, hasMinus, hasParen)
}

export function resolveMathQuizLevel(input: MathQuizLevelInput): MathQuizLevelInfo {
  const skill: string = normalizeSkillKey(input.skillKey)
  const quizType: string = normalizeQuizType(input.quizType)

  // 1. skill / 题型一致性
  let mismatched: boolean = false
  if (skill === 'math_shapes') {
    mismatched = quizType !== 'shape'
  } else if (skill === 'math_comparison') {
    mismatched = quizType !== 'comparison'
  } else if (skill === 'math_time') {
    mismatched = quizType !== 'time' && quizType !== 'elapsed_time'
  } else if (isArithmeticSkill(skill)) {
    mismatched = quizType !== 'arithmetic'
  }
  if (mismatched) {
    return errInfo(bestEffortTrack(quizType, input.expression),
      mismatchError(skill, quizType), input)
  }

  if (quizType === 'shape') {
    const shapeInfo: MathQuizLevelInfo = {
      track: 'shape', level: 0, gate: false, spec: null, expressionKey: '', error: ''
    }
    return shapeInfo
  }
  if (quizType === 'comparison') {
    return classifyComparison(input)
  }
  if (quizType === 'time') {
    return classifyClock(input)
  }
  if (quizType === 'elapsed_time') {
    return classifyElapsed(input)
  }
  return classifyArithmetic(input)
}

// ---------------------------------------------------------------------------
// 进度状态机 / 提示 / 出题闸门（Task 3）
// ---------------------------------------------------------------------------

function copyRow(row: MathQuizProgressRow, updatedAt: number): MathQuizProgressRow {
  const copy: MathQuizProgressRow = {
    track: row.track, currentLevel: row.currentLevel, correctAtLevel: row.correctAtLevel,
    consecutiveWrong: row.consecutiveWrong, updatedAt: updatedAt
  }
  return copy
}

export function applyMathQuizProgress(current: MathQuizProgressRow, questionLevel: number,
                                      purpose: MathQuizPurpose, correct: boolean, attempts: number,
                                      now: number): MathQuizProgressUpdate {
  const counted: boolean = purpose === 'practice' && questionLevel === current.currentLevel
  if (!counted) {
    let reason: MathQuizProgressReason = 'stale_level'
    if (purpose === 'warm_up') {
      reason = 'warm_up'
    } else if (purpose === 'review') {
      reason = 'review'
    }
    const unchanged: MathQuizProgressUpdate = {
      row: copyRow(current, current.updatedAt), counted: false, status: 'not_counted', reason: reason
    }
    return unchanged
  }
  const track: MathQuizTrack = current.track as MathQuizTrack
  const maxLevel: number = getMaxLevel(track)
  let level: number = current.currentLevel
  let correctCount: number = current.correctAtLevel
  let wrongCount: number = current.consecutiveWrong
  if (now - current.updatedAt > MATH_QUIZ_WRONG_RESET_MS) {
    wrongCount = 0
  }
  let status: MathQuizProgressStatus = 'in_progress'
  let reason: MathQuizProgressReason = 'first_try_correct'
  const firstTry: boolean = correct && attempts === 1
  if (firstTry) {
    correctCount = Math.min(MATH_QUIZ_NEEDED_CORRECT, correctCount + 1)
    wrongCount = 0
    if (correctCount >= MATH_QUIZ_NEEDED_CORRECT) {
      if (level < maxLevel) {
        level = level + 1
        correctCount = 0
        status = 'level_up'
      } else {
        status = 'max_level'
      }
    }
  } else if (correct) {
    wrongCount = 0
    reason = 'second_try'
  } else {
    wrongCount = wrongCount + 1
    reason = 'two_wrong'
    if (wrongCount >= 2) {
      if (level > 1) {
        level = level - 1
        correctCount = 0
        wrongCount = 0
        status = 'level_down'
      } else {
        wrongCount = 0
      }
    }
  }
  const updated: MathQuizProgressRow = {
    track: current.track, currentLevel: level, correctAtLevel: correctCount,
    consecutiveWrong: wrongCount, updatedAt: now
  }
  const result: MathQuizProgressUpdate = {
    row: updated, counted: true, status: status, reason: reason
  }
  return result
}

export function buildMathQuizProgressHint(update: MathQuizProgressUpdate, track: MathQuizTrack,
                                          needed: number): MathQuizProgressHint | null {
  const spec: MathQuizLevelSpec | null = getLevelSpec(track, update.row.currentLevel)
  if (spec === null) {
    return null
  }
  const hint: MathQuizProgressHint = {
    track: track,
    level: update.row.currentLevel,
    level_label: spec.label,
    correct_at_level: update.row.correctAtLevel,
    needed: needed,
    consecutive_wrong: update.row.consecutiveWrong,
    status: update.status,
    reason: update.reason,
    next_target: buildTarget(spec)
  }
  return hint
}

function rejectDecision(error: string, message: string, target: MathQuizTarget | null): MathQuizGateDecision {
  const decision: MathQuizGateDecision = {
    allowed: false, error: error, message: message, target: target
  }
  return decision
}

function allowDecision(target: MathQuizTarget | null): MathQuizGateDecision {
  const decision: MathQuizGateDecision = {
    allowed: true, error: '', message: '', target: target
  }
  return decision
}

function targetSuffix(spec: MathQuizLevelSpec | null): string {
  if (spec === null) {
    return ''
  }
  return `（${spec.label}，如 ${spec.example}）`
}

function tooEasyMessage(info: MathQuizLevelInfo, progressLevel: number, spec: MathQuizLevelSpec | null): string {
  const label: string = getTrackLabel(info.track)
  return `当前${label}目标 L${progressLevel}${targetSuffix(spec)}。你出的题是 L${info.level}，太简单了。` +
    '请按 target 重新出题，不要降低难度。如果这是热身/复习，请把 purpose 设为 warm_up 或 review（有每会话配额）。'
}

function tooHardMessage(info: MathQuizLevelInfo, progressLevel: number, spec: MathQuizLevelSpec | null): string {
  const label: string = getTrackLabel(info.track)
  return `当前${label}目标 L${progressLevel}${targetSuffix(spec)}。你出的题是 L${info.level}，太难了。请按 target 重新出题。`
}

/**
 * 估算某一关卡可出题的「去重键空间」大小（同一 key 视为同一道题）。
 * 只有键空间可能小于回查窗口的轨道/关卡才需要: 键空间用尽后若仍拒绝重复,
 * 该轨道会被永久锁死（孩子无法靠 warm_up/review 推进, 而 practice 全被
 * duplicate_question 拒绝）。宁小勿大: 估值偏小只会让去重提前放行。
 */
export function estimateLevelKeySpace(track: MathQuizTrack, level: number): number {
  if (track === 'clock') {
    if (level === 4) {
      return 24   // 分钟 5/55 × 12 小时
    }
    if (level === 3) {
      return 96   // 8 种分钟 × 12 小时
    }
    return 12     // 整点 / 半点 × 12 小时
  }
  if (track === 'muldiv') {
    if (level === 2) {
      return 11   // 2–9 内 max ∈ {3,4,6} 的有序对
    }
    if (level === 3) {
      return 39   // 2–9 内 max ∈ {7,8,9} 的有序对
    }
    if (level >= 4) {
      return 64   // 多位数乘除，估值
    }
    return 44     // 1 参与或 max ∈ {2,5,10} 的乘法对
  }
  return 100      // 加减 / 比较 / 经过时间: 键空间远大于回查窗口
}

function duplicateWindowSaturated(recentKeys: string[], keySpace: number): boolean {
  const seen: string[] = []
  for (let i = 0; i < recentKeys.length; i++) {
    if (seen.indexOf(recentKeys[i]) < 0) {
      seen.push(recentKeys[i])
    }
  }
  return seen.length >= keySpace
}

export function evaluateMathQuizGate(input: MathQuizGateInput): MathQuizGateDecision {
  const track: MathQuizTrack = input.info.track
  const spec: MathQuizLevelSpec | null = getLevelSpec(track, input.progressLevel)
  const target: MathQuizTarget | null = spec === null ? null : buildTarget(spec)
  if (input.info.error !== '') {
    return rejectDecision('difficulty_gate', input.info.error, target)
  }
  if (!input.info.gate) {
    return allowDecision(target)
  }
  const level: number = input.info.level
  if (input.purpose === 'practice') {
    if (level < input.progressLevel) {
      return rejectDecision('difficulty_gate', tooEasyMessage(input.info, input.progressLevel, spec), target)
    }
    if (level > input.progressLevel) {
      return rejectDecision('difficulty_gate', tooHardMessage(input.info, input.progressLevel, spec), target)
    }
    const key: string = input.info.expressionKey
    if (key !== '' && !duplicateWindowSaturated(input.recentExpressionKeys,
      estimateLevelKeySpace(track, input.progressLevel)) &&
      input.recentExpressionKeys.indexOf(key) >= 0) {
      const message: string = `这道题在最近 ${MATH_QUIZ_RECENT_LIMIT} 道同轨题里做过了。` +
        `请保持 L${input.progressLevel} 难度，换一组数字。`
      return rejectDecision('duplicate_question', message, target)
    }
    return allowDecision(target)
  }
  // warm_up / review
  if (level > input.progressLevel) {
    return rejectDecision('difficulty_gate', tooHardMessage(input.info, input.progressLevel, spec), target)
  }
  const limit: number = input.purpose === 'warm_up' ? MATH_QUIZ_WARM_UP_LIMIT : MATH_QUIZ_REVIEW_LIMIT
  if (input.sessionId !== '' && input.purposeCountInSession >= limit) {
    const message: string = `本会话 ${input.purpose} 已用 ${limit} 道，不能再用了。` +
      '请改用 purpose=\'practice\'，按 target 出正式练习。'
    return rejectDecision('purpose_quota_exceeded', message, target)
  }
  return allowDecision(target)
}
