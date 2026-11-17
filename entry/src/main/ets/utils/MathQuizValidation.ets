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
 *  1. arithmetic: expression 可计算时权威复算答案 (math_verify 同款引擎, 复算值与
 *     correct_answer 不一致即拒绝); 期望答案必须在数字 options 里
 *  2. shape: 认名(correct_answer / options 都是白名单形状名) / 数边数角
 *     (正确答案是数字, 与图形真值一致)
 *  3. comparison: left/right_value 是数字; correct_answer 是数学真值运算符 (方向校验)
 *  4. time: correct_answer 的 H:MM 与 clock_hour/clock_minute 一致
 *  5. elapsed_time: correct_answer 的时长与 start/end 四字段计算结果一致
 *  6. fraction: 看图选分数的答案与 frac_parts/frac_shaded 一致; 同分母比较方向校验
 */

import {
  normalizeQuizType,
  normalizeShapeName,
  normalizeShapeAsk,
  normalizeFractionAsk,
  normalizeFractionNumber,
  normalizeFractionString,
  fractionCompareTruth,
  normalizeOperator,
  normalizeClockHour,
  normalizeClockMinute,
  formatClockTime,
  computeElapsedDuration,
  formatDuration,
  normalizeTimeString,
  normalizeDurationString,
  tryEvaluateExpression,
  sanitizeExpression,
  tokenizeExpression
} from './MathQuizGame'
import { shapePropsSides, shapePropsCorners, isCountableShape } from './MathTeachShapeProps'

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

// shape 数边/数角题: 数字项, 同时接受数字型字符串（与 parseMathQuiz 的覆写口径一致）
function collectShapeNumberOptions(parsed: Record<string, Object>): number[] {
  const result: number[] = []
  const raw = parsed['options']
  if (Array.isArray(raw)) {
    const arr = raw as Object[]
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i]
      if (typeof v === 'number') {
        result.push(v as number)
      } else if (typeof v === 'string') {
        const text: string = (v as string).trim()
        const n: number = Number(text)
        if (text !== '' && Number.isFinite(n)) {
          result.push(n)
        }
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

function validateArithmetic(parsed: Record<string, Object>): MathQuizValidationResult {
  const rawCorrect = parsed['correct_answer']
  const expression = ((parsed['expression'] as string) ?? '').trim()

  // LLM 声称的答案: 数字或字符串型数字都接受 (与 parseMathQuiz 同口径)
  let declared: number | null = null
  if (typeof rawCorrect === 'number') {
    declared = rawCorrect as number
  } else if (typeof rawCorrect === 'string') {
    const text: string = (rawCorrect as string).trim()
    const n: number = Number(text)
    if (text !== '' && Number.isFinite(n)) {
      declared = n
    }
  }

  // 权威复算: expression (sanitize 后) 可计算时以计算值为准 (math_verify 同款引擎)
  const computed = tryEvaluateExpression(expression)
  const expected: number | null = computed !== null ? computed : declared
  if (expected === null) {
    return fail('arithmetic 题缺少正确答案: correct_answer 必须是数字 (或提供可计算的 expression), 请修正后重新出题')
  }
  // 声称值与复算值同时存在且不一致 → 可证明答案错误, 拒绝并让 AI 自我修正
  if (computed !== null && declared !== null && Math.abs(computed - declared) > 0.001) {
    return fail(`arithmetic 题答案不一致: expression「${expression}」计算结果是 ${computed}, 但 correct_answer 是 ${declared}, 请修正后重新出题`)
  }

  // 连加连减适配 (2026-10-15): 步数上限 3 个运算符 (6-7 岁不适龄更长链),
  // 括号不计入; 结果不能为负数 (学龄前不涉及负数)。
  const sanitized = sanitizeExpression(expression)
  if (sanitized !== '') {
    const tokens = tokenizeExpression(sanitized)
    let opCount: number = 0
    for (const t of tokens) {
      if (t.type === 'op' && t.value !== '(' && t.value !== ')') {
        opCount += 1
      }
    }
    if (opCount > 3) {
      return fail(`arithmetic 题算式「${expression}」有 ${opCount} 个运算符, 连加连减最多 3 步, 请拆短后重新出题`)
    }
  }
  if (computed !== null && computed < 0) {
    return fail(`arithmetic 题算式「${expression}」计算结果是负数 (${computed}), 小朋友还没学负数, 请调整为结果非负的算式后重新出题`)
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
  const askRaw: Object | undefined = parsed['shape_ask']
  const ask: string = normalizeShapeAsk(typeof askRaw === 'string' ? (askRaw as string) : '')
  if (ask === 'name') {
    return validateShapeName(parsed)
  }
  const askZh: string = ask === 'sides' ? '边' : '角'
  const rawShape: Object | undefined = parsed['shape']
  const shape: string = typeof rawShape === 'string' ? (rawShape as string).trim() : ''
  if (!isCountableShape(shape)) {
    return fail(`shape 数${askZh}题的目标图形必须是 triangle/square/rectangle/pentagon 之一` +
      `（⚠️ 严禁 circle/star/heart，圆没有直的边，星形心形边角数不清），收到「${shape}」`)
  }
  const truth: number = ask === 'sides' ? shapePropsSides(shape) : shapePropsCorners(shape)
  const rawCorrect: Object | undefined = parsed['correct_answer']
  let declared: number | null = null
  if (typeof rawCorrect === 'number') {
    declared = rawCorrect as number
  } else if (typeof rawCorrect === 'string') {
    const text: string = (rawCorrect as string).trim()
    const n: number = Number(text)
    if (text !== '' && Number.isFinite(n)) {
      declared = n
    }
  }
  if (declared === null) {
    return fail(`shape 数${askZh}题的 correct_answer 必须是数字（该图形有 ${truth} 个${askZh}），请修正后重新出题`)
  }
  if (declared !== truth) {
    return fail(`${shape} 的${askZh}数是 ${truth}，你给的 correct_answer 是 ${declared}，请修正后重新出题`)
  }
  const options = collectShapeNumberOptions(parsed)
  if (options.length < 2) {
    return fail(`shape 数${askZh}题至少需要 2 个数字选项（options），请补充后重新出题`)
  }
  if (!containsNumber(options, truth)) {
    return fail(`shape 数${askZh}题的正确答案 ${truth} 不在选项里，请把正确答案放进 options 后重新出题`)
  }
  return pass()
}

function validateShapeName(parsed: Record<string, Object>): MathQuizValidationResult {
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

function validateFraction(parsed: Record<string, Object>): MathQuizValidationResult {
  const askRaw: Object | undefined = parsed['fraction_ask']
  const ask: string = normalizeFractionAsk(typeof askRaw === 'string' ? (askRaw as string) : '')
  const parts: number = normalizeFractionNumber(parsed['frac_parts'])
  if (parts < 2 || parts > 8) {
    return fail('fraction 题的 frac_parts 必须是 2-8 的整数（等分的份数，也就是分母）')
  }
  const shaded: number = normalizeFractionNumber(parsed['frac_shaded'])
  if (shaded < 1) {
    return fail('fraction 题的 frac_shaded 至少要取 1 份')
  }
  if (shaded >= parts) {
    return fail('frac_shaded 取满全部份数是整体 1，超出分数初步认识范围（⚠️ 严禁 frac_shaded ≥ frac_parts）')
  }
  if (ask === 'compare') {
    const shaded2: number = normalizeFractionNumber(parsed['frac_shaded2'])
    if (shaded2 < 1 || shaded2 >= parts) {
      return fail(`fraction 比较题的 frac_shaded2 必须是 1 到 ${parts - 1} 的整数（同分母比大小的右边分子）`)
    }
    const rawCorrect: Object | undefined = parsed['correct_answer']
    if (typeof rawCorrect !== 'string') {
      return fail('fraction 比较题的 correct_answer 必须是比较运算符字符串 (> / < / =)')
    }
    const op: string = normalizeOperator((rawCorrect as string).trim())
    if (op === '') {
      return fail(`fraction 比较题的 correct_answer「${rawCorrect}」不是合法运算符, 应为 > / < / = 之一`)
    }
    const truth: string = fractionCompareTruth(shaded, shaded2)
    if (op !== truth) {
      return fail(`fraction 比较题答案方向错误: ${shaded}/${parts} 与 ${shaded2}/${parts} 同分母，` +
        `比分子 ${shaded} 和 ${shaded2}，正确运算符是「${truth}」，你给的是「${op}」`)
    }
    const opsRaw: Object | undefined = parsed['operator_options']
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
      if (!containsString(normalizedOps, truth)) {
        return fail(`fraction 比较题的 operator_options 里没有正确运算符「${truth}」，请把它放进选项后重新出题`)
      }
    }
    return pass()
  }
  const rawCorrect: Object | undefined = parsed['correct_answer']
  const correct: string = normalizeFractionString(
    typeof rawCorrect === 'string' ? (rawCorrect as string) : String(rawCorrect ?? ''))
  if (correct === '') {
    return fail(`fraction 题的 correct_answer「${rawCorrect}」不是合法的分数字符串，应形如「${shaded}/${parts}」`)
  }
  const expected: string = `${shaded}/${parts}`
  if (correct !== expected) {
    return fail(`fraction 题答案与图不一致: 平均分成 ${parts} 份取 ${shaded} 份是「${expected}」，` +
      `你给的是「${correct}」，请修正后重新出题`)
  }
  const options = collectNormalizedStringOptions(parsed, normalizeFractionString)
  if (options.length < 2) {
    return fail('fraction 看图题至少需要 2 个合法的分数字符串选项（如「1/4」「3/4」），请补充后重新出题')
  }
  if (!containsString(options, expected)) {
    return fail(`fraction 题的正确答案 ${expected} 不在选项里，请把正确答案放进 options 后重新出题`)
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
  if (quizType === 'fraction') {
    return validateFraction(parsed)
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
