/**
 * math_teach 预校验（镜像 MathQuizValidation 范式：只拒绝「算理可证明矛盾」
 * 或「板不可玩」的课，纯外观问题不拦）。
 * 5 规则（spec §5）：mode 白名单 / 凑十一致性 / 概念-模式匹配 / 难度-画像一致 /
 * 演示后必练（规则 5 是 prompt 契约，此处不机器校验）。
 */

export interface MathTeachValidationResult {
  ok: boolean
  error: string
}

const TEACH_MODES: string[] = ['number_bond', 'number_line', 'ten_frame', 'place_value',
  'balance', 'shape', 'clock', 'bar_model']
const SHAPE_FOCUS: string[] = ['circle', 'square', 'triangle', 'rectangle']
const SKILL_KEYS: string[] = ['math_number_sense', 'math_counting', 'math_addition',
  'math_subtraction', 'math_multiply', 'math_divide', 'math_shapes', 'math_comparison',
  'math_time', 'math_word_problem']
const STAGES: string[] = ['warm_up', 'presentation', 'practice', 'production', 'review']

function fail(msg: string): MathTeachValidationResult {
  return { ok: false, error: msg }
}

function pass(): MathTeachValidationResult {
  return { ok: true, error: '' }
}

function getNumber(args: Record<string, Object>, key: string): number {
  const v: Object | undefined = args[key]
  if (typeof v === 'number') { return v as number }
  return NaN
}

function getString(args: Record<string, Object>, key: string): string {
  const v: Object | undefined = args[key]
  if (typeof v === 'string') { return v as string }
  return ''
}

function inRange(v: number, min: number, max: number): boolean {
  return !Number.isNaN(v) && Number.isInteger(v) && v >= min && v <= max
}

export function validateMathTeachArgs(rawArgs: string,
                                      profileLevels: Record<string, number> | null): MathTeachValidationResult {
  let args: Record<string, Object>
  try {
    args = JSON.parse(rawArgs) as Record<string, Object>
  } catch (_e) {
    return fail('math_teach 参数不是合法 JSON')
  }

  // 规则 1a：mode 白名单
  const mode: string = getString(args, 'mode')
  if (TEACH_MODES.indexOf(mode) < 0) {
    return fail('mode 必须是 ' + TEACH_MODES.join('/') + ' 之一，收到「' + mode + '」')
  }

  // 共享参数（规则 1b/3）
  const difficulty: number = getNumber(args, 'difficulty')
  if (!inRange(difficulty, 1, 5)) {
    return fail('difficulty 必须是 1-5 的整数')
  }
  const concept: string = getString(args, 'concept')
  if (concept === '') {
    return fail('concept 必须是一句给孩子看的知识点标题，不能为空')
  }
  const skillKey: string = getString(args, 'skill_key')
  if (SKILL_KEYS.indexOf(skillKey) < 0) {
    return fail('skill_key 必须是数学画像 10 维之一（math_ 开头），收到「' + skillKey + '」')
  }
  const stage: string = getString(args, 'stage')
  if (stage !== '' && STAGES.indexOf(stage) < 0) {
    return fail('stage 只能是 warm_up/presentation/practice/production/review')
  }

  // 规则 1c + 规则 2/3：mode 专属约束
  const modeCheck: MathTeachValidationResult = validateModeArgs(mode, args)
  if (!modeCheck.ok) { return modeCheck }

  // 规则 4：难度-画像一致（|difficulty - level| ≤ 1；level 0 = 未评估跳过；null 跳过）
  if (profileLevels !== null) {
    const lv: Object | undefined = profileLevels[skillKey]
    if (typeof lv === 'number') {
      const level: number = lv as number
      if (level >= 1 && Math.abs(difficulty - level) > 1) {
        return fail('difficulty=' + difficulty + ' 与画像等级 ' + skillKey + '=' + level +
          ' 偏差超过 1 级，请按画像调整难度')
      }
    }
  }

  return pass()
}

function validateModeArgs(mode: string, args: Record<string, Object>): MathTeachValidationResult {
  if (mode === 'number_bond') {
    const total: number = getNumber(args, 'total')
    if (!inRange(total, 2, 20)) { return fail('number_bond 的 total 必须是 2-20 的整数') }
  } else if (mode === 'number_line') {
    const start: number = getNumber(args, 'start')
    const step: number = getNumber(args, 'step')
    if (!inRange(start, 6, 9)) { return fail('number_line 的 start 必须是 6-9（保证能先跳到 10）') }
    if (!inRange(step, 1, 10)) { return fail('number_line 的 step 必须是 1-10 的整数') }
    const sum: number = start + step
    if (sum > 20) { return fail('number_line 的 start+step 不能超过 20') }
    if (sum <= 10) {
      return fail('number_line 只讲 20 以内进位加法：start+step 必须大于 10' +
        '（不进位的加法不需要凑十，用 math_quiz 或 vertical_math）')
    }
  } else if (mode === 'ten_frame') {
    const a: number = getNumber(args, 'a')
    const b: number = getNumber(args, 'b')
    if (!inRange(a, 5, 9)) { return fail('ten_frame 的 a 必须是 5-9（框内已有个数）') }
    if (!inRange(b, 1, 10)) { return fail('ten_frame 的 b 必须是 1-10 的整数') }
    const sum: number = a + b
    if (sum > 20) { return fail('ten_frame 的 a+b 不能超过 20') }
    if (sum <= 10) {
      return fail('ten_frame 只讲 20 以内进位加法：a+b 必须大于 10' +
        '（⚠️ 严禁 a+b 不超过 10 时使用 ten_frame，那样的题不需要凑十）')
    }
  } else if (mode === 'place_value') {
    const tens: number = getNumber(args, 'tens')
    const ones: number = getNumber(args, 'ones')
    if (!inRange(tens, 0, 8)) { return fail('place_value 的 tens 必须是 0-8 的整数') }
    if (!inRange(ones, 0, 9)) { return fail('place_value 的 ones 必须是 0-9 的整数') }
    if (tens === 0 && ones === 0) { return fail('place_value 的 tens 和 ones 不能同时为 0') }
  } else if (mode === 'balance') {
    const left: number = getNumber(args, 'left')
    const right: number = getNumber(args, 'right')
    if (!inRange(left, 1, 20)) { return fail('balance 的 left 必须是 1-20 的整数') }
    if (!inRange(right, 1, 20)) { return fail('balance 的 right 必须是 1-20 的整数') }
  } else if (mode === 'shape') {
    const focus: string = getString(args, 'focus')
    if (SHAPE_FOCUS.indexOf(focus) < 0) {
      return fail('shape 的 focus 必须是 circle/square/triangle/rectangle 之一')
    }
  } else if (mode === 'clock') {
    const hour: number = getNumber(args, 'hour')
    const minute: number = getNumber(args, 'minute')
    if (!inRange(hour, 1, 12)) { return fail('clock 的 hour 必须是 1-12 的整数') }
    if (minute !== 0 && minute !== 30) {
      return fail('clock 的 minute 只能是 0（整点）或 30（半点）')
    }
  } else if (mode === 'bar_model') {
    const pa: number = getNumber(args, 'part_a')
    const pb: number = getNumber(args, 'part_b')
    if (!inRange(pa, 1, 9)) { return fail('bar_model 的 part_a 必须是 1-9 的整数') }
    if (!inRange(pb, 1, 9)) { return fail('bar_model 的 part_b 必须是 1-9 的整数') }
  }
  return pass()
}
