/**
 * MathQuizGame - 数学游戏纯逻辑层
 *
 * 与 MathQuizCard 解耦: 只有数据解析、判定、token 切分等无副作用函数,
 * 组件聚焦 UI 渲染, 也方便将来补 .ets 单测。
 */

import { evaluateMathExpression } from './MathExpressionParser'

// 题型联合: 5 种 math_quiz 子题型
// - arithmetic     算术(add/sub/mul/div/counting/word_problem)
// - shape          图形认知(math_shapes)
// - comparison     大小比较(math_comparison)
// - time           时间认知-读时间(math_time)
// - elapsed_time   时间认知-计时经过(math_time)
export type QuizType = 'arithmetic' | 'shape' | 'comparison' | 'time' | 'elapsed_time'

export interface MathQuizQuestion {
  type: QuizType
  question: string
  expression: string
  correctAnswer: string | number
  options: Array<string | number>
  skillKey: string
  // arithmetic 专用; true = 应用题模式（只渲染 question 文字, 不显示算式）
  wordProblem: boolean
  // comparison 专用; 其他 type 默认 0
  leftValue: number
  rightValue: number
  // comparison 专用; 默认 ['>', '<', '=']
  operatorOptions: string[]
  // time 专用; 其他 type 默认 0
  // hour ∈ [1, 12] (12 小时制), minute ∈ {0,5,10,...,55} (5 分钟步长)
  clockHour: number
  clockMinute: number
  // elapsed_time 专用; 其他 type 默认 0/0/0/0
  startHour: number
  startMinute: number
  endHour: number
  endMinute: number
}

export interface MathQuizAnswerPayload {
  answered: boolean
  child_answer: string | number
  child_answer_valid: boolean
  correct: boolean
  correct_answer: string | number
  expression: string
  question: string
  skill_key: string
  quiz_type: QuizType
}

export interface ExpressionToken {
  type: 'number' | 'op'
  value: string
}

// 单源的运算符字母表: AI 可能直接发中文 × ÷, 需与 ASCII 同等识别。
// 下方的显示正则字符类与 op 分类器必须与这里保持一致, 避免任一侧漏掉符号。
const MATH_OP_CHARS: string = '+-*/()×÷'

/**
 * 解析 AI 传入的 toolCall.arguments JSON 字符串为题目数据。
 * 解析失败时返回空对象, 不抛异常, 由上层决定如何降级渲染。
 */
export function parseMathQuiz(argsJson: string): MathQuizQuestion {
  const result: MathQuizQuestion = {
    type: 'arithmetic',
    question: '',
    expression: '',
    correctAnswer: 0,
    options: [],
    skillKey: '',
    wordProblem: false,
    leftValue: 0,
    rightValue: 0,
    operatorOptions: [],
    clockHour: 0,
    clockMinute: 0,
    startHour: 0,
    startMinute: 0,
    endHour: 0,
    endMinute: 0
  }
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>
    result.type = normalizeQuizType((parsed['type'] as string) ?? 'arithmetic')
    result.question = (parsed['question'] as string) ?? ''
    result.skillKey = (parsed['skill_key'] as string) ?? ''

    if (result.type === 'arithmetic') {
      // 算术题型: 维持原行为
      result.expression = (parsed['expression'] as string) ?? ''
      const rawCorrect = parsed['correct_answer']
      result.correctAnswer = typeof rawCorrect === 'number' ? (rawCorrect as number) : 0
      // 应用题旗标: AI 显式传 word_problem=true 时启用 (只渲染 question, 隐藏算式)
      const wp = parsed['word_problem']
      result.wordProblem = (wp === true || wp === 'true')
      const rawOptions = parsed['options']
      if (Array.isArray(rawOptions)) {
        const arr = rawOptions as Object[]
        for (let i = 0; i < arr.length; i++) {
          const val = arr[i]
          if (typeof val === 'number') {
            result.options.push(val as number)
          }
        }
      }
      if (result.correctAnswer === 0 && result.expression !== '') {
        try {
          result.correctAnswer = evaluateMathExpression(result.expression)
        } catch (_e) {
          // 无法计算, 保持 0
        }
      }
    } else if (result.type === 'shape') {
      // 图形认知: correct_answer / options 都是英文形状名
      const rawCorrect = parsed['correct_answer']
      result.correctAnswer = normalizeShapeName(typeof rawCorrect === 'string' ? rawCorrect : String(rawCorrect ?? ''))
      const rawOptions = parsed['options']
      if (Array.isArray(rawOptions)) {
        const arr = rawOptions as Object[]
        for (let i = 0; i < arr.length; i++) {
          const val = arr[i]
          if (typeof val === 'string') {
            const n = normalizeShapeName(val)
            if (n !== '') {
              result.options.push(n)
            }
          }
        }
      }
    } else if (result.type === 'comparison') {
      // 大小比较: left/right_value + operator
      const rawCorrect = parsed['correct_answer']
      result.correctAnswer = normalizeOperator(typeof rawCorrect === 'string' ? rawCorrect : String(rawCorrect ?? ''))
      result.leftValue = (parsed['left_value'] as number) ?? 0
      result.rightValue = (parsed['right_value'] as number) ?? 0
      const ops = parsed['operator_options']
      if (Array.isArray(ops)) {
        const arr = ops as Object[]
        for (let i = 0; i < arr.length; i++) {
          const v = arr[i]
          if (typeof v === 'string') {
            const n = normalizeOperator(v)
            if (n !== '') {
              result.operatorOptions.push(n)
            }
          }
        }
      }
      if (result.operatorOptions.length === 0) {
        result.operatorOptions = ['>', '<', '=']
      }
    } else if (result.type === 'time') {
      // 时间认知: clock_hour/clock_minute → 钟面指针; correct_answer/options 是 H:MM 字符串
      const rawHour = parsed['clock_hour']
      const rawMinute = parsed['clock_minute']
      const hour = normalizeClockHour(typeof rawHour === 'number' ? rawHour : Number(rawHour ?? 0))
      const minute = normalizeClockMinute(typeof rawMinute === 'number' ? rawMinute : Number(rawMinute ?? 0))
      result.clockHour = hour
      result.clockMinute = minute
      // 用归一化后的 hour/minute 覆写 correct_answer 字符串, 保证钟面指针与文字答案永远一致
      result.correctAnswer = formatClockTime(hour, minute)
      const rawOptions = parsed['options']
      if (Array.isArray(rawOptions)) {
        const arr = rawOptions as Object[]
        for (let i = 0; i < arr.length; i++) {
          const val = arr[i]
          if (typeof val === 'string') {
            const n = normalizeTimeString(val)
            if (n !== '') {
              result.options.push(n)
            }
          }
        }
      }
      // 兜底: AI 可能漏掉正确项; 若 options < 4 自动补上
      if (result.options.indexOf(result.correctAnswer as string) === -1 && result.options.length < 4) {
        result.options.push(result.correctAnswer as string)
      }
    } else if (result.type === 'elapsed_time') {
      // 计时经过: 两个钟面 (start → end), correct_answer/options 是时长字符串
      const rawStartHour = parsed['start_hour']
      const rawStartMin = parsed['start_minute']
      const rawEndHour = parsed['end_hour']
      const rawEndMin = parsed['end_minute']
      const sh = normalizeClockHour(typeof rawStartHour === 'number' ? rawStartHour : Number(rawStartHour ?? 0))
      const sm = normalizeClockMinute(typeof rawStartMin === 'number' ? rawStartMin : Number(rawStartMin ?? 0))
      const eh = normalizeClockHour(typeof rawEndHour === 'number' ? rawEndHour : Number(rawEndHour ?? 0))
      const em = normalizeClockMinute(typeof rawEndMin === 'number' ? rawEndMin : Number(rawEndMin ?? 0))
      result.startHour = sh
      result.startMinute = sm
      result.endHour = eh
      result.endMinute = em
      // 用归一化后的钟面数据重新计算正确时长, 保证选项与钟面永远一致
      const dur = computeElapsedDuration(sh, sm, eh, em)
      result.correctAnswer = formatDuration(dur.hours, dur.minutes)
      const rawOptions = parsed['options']
      if (Array.isArray(rawOptions)) {
        const arr = rawOptions as Object[]
        for (let i = 0; i < arr.length; i++) {
          const val = arr[i]
          if (typeof val === 'string') {
            const n = normalizeDurationString(val)
            if (n !== '') {
              result.options.push(n)
            }
          }
        }
      }
      // 兜底: AI 漏掉正确项时自动补
      if (result.options.indexOf(result.correctAnswer as string) === -1 && result.options.length < 4) {
        result.options.push(result.correctAnswer as string)
      }
    }
  } catch (_e) {}
  return result
}

/**
 * 解析已回答记录的 payload JSON。空字符串返回 null。
 */
export function parseMathQuizAnswer(payloadJson: string): MathQuizAnswerPayload | null {
  if (payloadJson === '') {
    return null
  }
  try {
    return JSON.parse(payloadJson) as MathQuizAnswerPayload
  } catch (_e) {
    return null
  }
}

/**
 * 将算式字符串拆分为数字 / 运算符 token, 用于分样式渲染。
 * 不支持的字符会被跳过; 空字符串返回单元素数组 (上层按空处理)。
 */
export function tokenizeExpression(expr: string): ExpressionToken[] {
  const tokens: ExpressionToken[] = []
  // 正则字符类必须与上方 MATH_OP_CHARS 保持同步
  const regex = /(\d+\.?\d*|[+\-*/()×÷])/g
  const matches = expr.match(regex)
  if (!matches) {
    return [{ type: 'number', value: expr }]
  }
  for (const m of matches) {
    if (m.length === 1 && MATH_OP_CHARS.includes(m)) {
      tokens.push({ type: 'op', value: m })
    } else {
      tokens.push({ type: 'number', value: m })
    }
  }
  return tokens
}

/**
 * ASCII 运算符转中文数学符号, 提升儿童可读性。
 * 已是中文符号 (×, ÷) 时原样返回。
 */
export function getOpDisplay(op: string): string {
  const map: Record<string, string> = {
    '*': '×',
    '/': '÷'
  }
  return map[op] ?? op
}

/**
 * 判定选项是否等于正确答案。
 * arithmetic 用 number, shape/comparison/time 用 string;
 * 跨类型直接 false(避免 '5' === 5 这种 silent true)。
 */
export function isCorrectAnswer(selected: string | number, correct: string | number): boolean {
  if (typeof selected !== typeof correct) {
    return false
  }
  return selected === correct
}

// ---------- normalize 纯函数 (LLM 幻觉防御) ----------

const SHAPE_WHITELIST: string[] =
  ['circle', 'square', 'triangle', 'rectangle', 'pentagon', 'star', 'heart']

export function normalizeQuizType(raw: string): QuizType {
  if (raw === 'shape' || raw === 'comparison' || raw === 'time' || raw === 'elapsed_time') {
    return raw
  }
  return 'arithmetic'
}

export function normalizeShapeName(raw: string): string {
  return SHAPE_WHITELIST.includes(raw) ? raw : ''
}

export function normalizeOperator(raw: string): string {
  if (raw === '>' || raw === '<' || raw === '=') {
    return raw
  }
  return ''
}

// 接受 H:MM 或 HH:MM; 03:30 → 3:30 归一化
export function normalizeTimeString(raw: string): string {
  const m = raw.match(/^(\d{1,2}):(\d{2})$/)
  if (m === null) {
    return ''
  }
  const h = parseInt(m[1], 10)
  if (h < 0 || h > 23) {
    return ''
  }
  return `${h}:${m[2]}`
}

// hour ∈ [1, 12]; 0 视为 12; 13-23 视为 1-11; NaN/负数 fallback 12
export function normalizeClockHour(raw: number): number {
  if (!Number.isFinite(raw)) {
    return 12
  }
  const h = Math.floor(raw)
  if (h <= 0) {
    return 12
  }
  if (h > 12) {
    return ((h - 1) % 12) + 1
  }
  return h
}

// minute 必须是 5 的倍数; round 到最近 5 倍数, 范围 0..55
export function normalizeClockMinute(raw: number): number {
  if (!Number.isFinite(raw)) {
    return 0
  }
  const m = Math.floor(raw)
  const wrapped = ((m % 60) + 60) % 60
  const rounded = Math.round(wrapped / 5) * 5
  return rounded === 60 ? 0 : rounded
}

// 3:05 / 3:30 / 12:00 格式; caller 应先用 normalizeClockHour/Minute 归一化
export function formatClockTime(hour: number, minute: number): string {
  return `${hour}:${minute < 10 ? '0' + minute : minute}`
}

// elapsed_time 专用: 时长结果接口 (避免 10605040 inline-object-literal 错误)
interface ElapsedDuration {
  hours: number
  minutes: number
}

// 12 小时制差值: end - start, 范围 [0, 12*60)
// 跨正午 (11:30 → 1:30 = 2 小时) 自然处理
export function computeElapsedDuration(startHour: number, startMinute: number,
                                       endHour: number, endMinute: number): ElapsedDuration {
  const startTotal = startHour * 60 + startMinute
  const endTotal = endHour * 60 + endMinute
  let diff = endTotal - startTotal
  if (diff < 0) {
    diff += 12 * 60  // 跨正午
  }
  if (diff > 12 * 60) {
    diff -= 12 * 60  // 防御 AI 传反序
  }
  const hours = Math.floor(diff / 60)
  const minutes = diff % 60
  const result: ElapsedDuration = { hours: hours, minutes: minutes }
  return result
}

// "1 小时 30 分" / "30 分" / "2 小时" / "0 分" 格式
export function formatDuration(hours: number, minutes: number): string {
  const parts: string[] = []
  if (hours > 0) {
    parts.push(`${hours} 小时`)
  }
  if (minutes > 0 || parts.length === 0) {
    parts.push(`${minutes} 分`)
  }
  return parts.join(' ')
}

// "1 小时 30 分" / "30 分" 解析; 非数字前缀拒绝
export function normalizeDurationString(raw: string): string {
  let hours = 0
  let minutes = 0
  const hMatch = raw.match(/(\d+)\s*小时/)
  if (hMatch !== null) {
    hours = parseInt(hMatch[1], 10)
  }
  const mMatch = raw.match(/(\d+)\s*分/)
  if (mMatch !== null) {
    minutes = parseInt(mMatch[1], 10)
  }
  // 既没匹配到小时也没匹配到分钟 = 拒绝 (避免 AI 乱写 "1.5 小时")
  if (hMatch === null && mMatch === null) {
    return ''
  }
  return formatDuration(hours, minutes)
}

// arithmetic 应用题旗标归一化: 接受 boolean true 或字符串 "true", 其他一律 false
export function normalizeWordProblemFlag(raw: Object | undefined): boolean {
  return raw === true || raw === 'true'
}
