/**
 * MathQuizValidation - math_quiz 出题参数预校验纯逻辑层
 *
 * 与 MathQuizCard / MathQuizGame 解耦: 只做 AI 工具调用参数的合法性校验,
 * 在 ToolExecutionService.handleMathQuiz 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/CategorizationValidation.ets (预校验 + should_retry 范式)。
 * 归一化函数全部复用 utils/MathQuizGame.ets, 不重实现。
 *
 * 校验原则 (避免过度拒绝): 只拒绝「答案可证明错误」或「卡片不可玩」的题,
 * 纯外观问题 (question 文案缺失 / difficulty 怪异) 不在校验范围。
 *  1. arithmetic: correct_answer 是数字且在数字 options 里; expression 可计算时两者一致
 *  2. shape: correct_answer / options 都是白名单形状名, 正确答案在选项里
 *  3. comparison: left/right_value 是数字; correct_answer 是数学真值运算符 (方向校验)
 *  4. time: correct_answer 的 H:MM 与 clock_hour/clock_minute 一致
 *  5. elapsed_time: correct_answer 的时长与 start/end 四字段计算结果一致
 */

import { evaluateMathExpression } from './MathExpressionParser'
import {
  normalizeQuizType,
  normalizeShapeName,
  normalizeOperator,
  normalizeClockHour,
  normalizeClockMinute,
  formatClockTime,
  computeElapsedDuration,
  formatDuration,
  normalizeTimeString,
  normalizeDurationString
} from './MathQuizGame'

export interface MathQuizValidationResult {
  ok: boolean
  error: string
}

// 构造失败结果。模块级顶层函数, 避免组件内闭包。
function fail(msg: string): MathQuizValidationResult {
  return { ok: false, error: msg }
}

function pass(): MathQuizValidationResult {
  return { ok: true, error: '' }
}

// 从 options 数组里提取数字项 (非数字项静默跳过, 与 parseMathQuiz 行为一致)
function collectNumberOptions(parsed: Record<string, Object>): number[] {
  const result: number[] = []
  const raw = parsed['options']
  if (Array.isArray(raw)) {
    const arr = raw as Object[]
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i]
      if (typeof v === 'number') {
        result.push(v as number)
      }
    }
  }
  return result
}

// 从 options 数组里提取经过 normalizer 归一化后非空的字符串项
function collectNormalizedStringOptions(parsed: Record<string, Object>,
  normalizer: (raw: string) => string): string[] {
  const result: string[] = []
  const raw = parsed['options']
  if (Array.isArray(raw)) {
    const arr = raw as Object[]
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i]
      if (typeof v === 'string') {
        const n = normalizer(v as string)
        if (n !== '') {
          result.push(n)
        }
      }
    }
  }
  return result
}

function containsNumber(values: number[], target: number): boolean {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === target) {
      return true
    }
  }
  return false
}

function containsString(values: string[], target: string): boolean {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === target) {
      return true
    }
  }
  return false
}

// 尝试计算表达式; 无法计算返回 null (不抛异常)
function tryEvaluate(expression: string): number | null {
  try {
    return evaluateMathExpression(expression)
  } catch (_e) {
    return null
  }
}

function validateArithmetic(parsed: Record<string, Object>): MathQuizValidationResult {
  const rawCorrect = parsed['correct_answer']
  const expression = ((parsed['expression'] as string) ?? '').trim()

  // 期望答案: 优先 correct_answer; 缺失时回退用 expression 计算 (parseMathQuiz 同款兜底)
  let expected: number | null = null
  if (typeof rawCorrect === 'number') {
    expected = rawCorrect as number
  } else if (expression !== '') {
    expected = tryEvaluate(expression)
  }
  if (expected === null) {
    return fail('arithmetic 题缺少正确答案: correct_answer 必须是数字 (或提供可计算的 expression), 请修正后重新出题')
  }

  // expression 与 correct_answer 交叉验证 (两者都在且可计算时)
  if (expression !== '' && typeof rawCorrect === 'number') {
    const computed = tryEvaluate(expression)
    if (computed !== null && Math.abs(computed - (rawCorrect as number)) > 0.001) {
      return fail(`arithmetic 题答案不一致: expression「${expression}」计算结果是 ${computed}, 但 correct_answer 是 ${rawCorrect}, 请修正后重新出题`)
    }
  }

  const options = collectNumberOptions(parsed)
  if (options.length < 2) {
    return fail('arithmetic 题至少需要 2 个数字选项 (options), 请补充后重新出题')
  }
  if (!containsNumber(options, expected)) {
    return fail(`arithmetic 题的正确答案 ${expected} 不在选项里, 请把正确答案放进 options 后重新出题`)
  }
  return pass()
}

function validateShape(parsed: Record<string, Object>): MathQuizValidationResult {
  const rawCorrect = parsed['correct_answer']
  if (typeof rawCorrect !== 'string') {
    return fail('shape 题的 correct_answer 必须是英文形状名字符串 (circle/square/triangle/rectangle/pentagon/star/heart)')
  }
  const correct = normalizeShapeName((rawCorrect as string).trim())
  if (correct === '') {
    return fail(`shape 题的 correct_answer「${rawCorrect}」不是合法形状名, 应为 circle/square/triangle/rectangle/pentagon/star/heart 之一`)
  }
  const options = collectNormalizedStringOptions(parsed, normalizeShapeName)
  if (options.length < 2) {
    return fail('shape 题至少需要 2 个合法的英文形状名选项, 请补充后重新出题')
  }
  if (!containsString(options, correct)) {
    return fail(`shape 题的正确答案 ${correct} 不在选项里, 请把正确答案放进 options 后重新出题`)
  }
  return pass()
}

function validateComparison(parsed: Record<string, Object>): MathQuizValidationResult {
  const rawLeft = parsed['left_value']
  const rawRight = parsed['right_value']
  if (typeof rawLeft !== 'number' || typeof rawRight !== 'number') {
    return fail('comparison 题必须同时提供数字型的 left_value 和 right_value')
  }
  const rawCorrect = parsed['correct_answer']
  if (typeof rawCorrect !== 'string') {
    return fail('comparison 题的 correct_answer 必须是比较运算符字符串 (> / < / =)')
  }
  const op = normalizeOperator((rawCorrect as string).trim())
  if (op === '') {
    return fail(`comparison 题的 correct_answer「${rawCorrect}」不是合法运算符, 应为 > / < / = 之一`)
  }

  const left = rawLeft as number
  const right = rawRight as number
  const truth = left > right ? '>' : (left < right ? '<' : '=')
  if (op !== truth) {
    return fail(`comparison 题答案方向错误: left_value=${left} 与 right_value=${right} 比较的正确运算符是「${truth}」, 你给的是「${op}」。correct_answer 必须是使 left_value ○ right_value 数学成立的符号`)
  }

  // operator_options 若提供则必须包含正确运算符, 否则孩子无法选出正确答案
  const opsRaw = parsed['operator_options']
  if (opsRaw !== undefined && Array.isArray(opsRaw)) {
    const arr = opsRaw as Object[]
    const normalizedOps: string[] = []
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i]
      if (typeof v === 'string') {
        const n = normalizeOperator(v as string)
        if (n !== '') {
          normalizedOps.push(n)
        }
      }
    }
    if (!containsString(normalizedOps, op)) {
      return fail(`comparison 题的 operator_options 里没有正确运算符「${op}」, 请把它放进选项后重新出题`)
    }
  }
  return pass()
}

function validateTime(parsed: Record<string, Object>): MathQuizValidationResult {
  const rawHour = parsed['clock_hour']
  const rawMinute = parsed['clock_minute']
  if (typeof rawHour !== 'number' || typeof rawMinute !== 'number') {
    return fail('time 题必须同时提供数字型的 clock_hour (1-12) 和 clock_minute (5 分钟步长)')
  }
  const rawCorrect = parsed['correct_answer']
  if (typeof rawCorrect !== 'string') {
    return fail('time 题的 correct_answer 必须是 H:MM 格式的时间字符串, e.g. 3:30')
  }
  const normalizedAnswer = normalizeTimeString((rawCorrect as string).trim())
  if (normalizedAnswer === '') {
    return fail(`time 题的 correct_answer「${rawCorrect}」不是合法的 H:MM 时间字符串`)
  }
  const hour = normalizeClockHour(rawHour as number)
  const minute = normalizeClockMinute(rawMinute as number)
  const expected = formatClockTime(hour, minute)
  if (normalizedAnswer !== expected) {
    return fail(`time 题答案与钟面不一致: clock_hour=${rawHour}/clock_minute=${rawMinute} 对应的正确答案是「${expected}」, 但 correct_answer 是「${normalizedAnswer}」, 请修正后重新出题`)
  }
  const options = collectNormalizedStringOptions(parsed, normalizeTimeString)
  if (options.length < 2) {
    return fail('time 题至少需要 2 个合法的 H:MM 时间选项, 请补充后重新出题')
  }
  return pass()
}

function validateElapsedTime(parsed: Record<string, Object>): MathQuizValidationResult {
  const rawStartHour = parsed['start_hour']
  const rawStartMinute = parsed['start_minute']
  const rawEndHour = parsed['end_hour']
  const rawEndMinute = parsed['end_minute']
  if (typeof rawStartHour !== 'number' || typeof rawStartMinute !== 'number'
    || typeof rawEndHour !== 'number' || typeof rawEndMinute !== 'number') {
    return fail('elapsed_time 题必须同时提供数字型的 start_hour/start_minute/end_hour/end_minute')
  }
  const rawCorrect = parsed['correct_answer']
  if (typeof rawCorrect !== 'string') {
    return fail('elapsed_time 题的 correct_answer 必须是时长字符串, e.g. 「1 小时 30 分」')
  }
  const normalizedAnswer = normalizeDurationString((rawCorrect as string).trim())
  if (normalizedAnswer === '') {
    return fail(`elapsed_time 题的 correct_answer「${rawCorrect}」不是合法的时长字符串 (应为「X 小时 Y 分」格式)`)
  }
  const sh = normalizeClockHour(rawStartHour as number)
  const sm = normalizeClockMinute(rawStartMinute as number)
  const eh = normalizeClockHour(rawEndHour as number)
  const em = normalizeClockMinute(rawEndMinute as number)
  const dur = computeElapsedDuration(sh, sm, eh, em)
  const expected = formatDuration(dur.hours, dur.minutes)
  if (normalizedAnswer !== expected) {
    return fail(`elapsed_time 题答案与钟面不一致: start ${sh}:${sm} → end ${eh}:${em} 的经过时长是「${expected}」, 但 correct_answer 是「${normalizedAnswer}」, 请修正后重新出题`)
  }
  const options = collectNormalizedStringOptions(parsed, normalizeDurationString)
  if (options.length < 2) {
    return fail('elapsed_time 题至少需要 2 个合法的时长选项, 请补充后重新出题')
  }
  return pass()
}

/**
 * 解析并校验 AI 传来的 math_quiz 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validateMathQuizArgs(args: string): MathQuizValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('math_quiz 参数不是合法 JSON, 请检查后重新出题')
  }

  const quizType = normalizeQuizType(((parsed['type'] as string) ?? 'arithmetic'))
  if (quizType === 'shape') {
    return validateShape(parsed)
  }
  if (quizType === 'comparison') {
    return validateComparison(parsed)
  }
  if (quizType === 'time') {
    return validateTime(parsed)
  }
  if (quizType === 'elapsed_time') {
    return validateElapsedTime(parsed)
  }
  return validateArithmetic(parsed)
}
