/**
 * NumberBlocksValidation - number_blocks 参数预校验纯逻辑层（2026-11-14）
 *
 * 在 ToolExecutionService.handleNumberBlocks 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 设计参考 utils/FarmEnglishValidation.ets（预校验 + should_retry 范式）。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 number_blocks schema）：
 *  - mode 可选，v1 只接受 display
 *  - focus 可选，整数 1-20；不在 numbers 集合里时回落到集合第一个
 *  - numbers 可选，整数 1-20 的数组，去重后升序；空数组表示「全部 20 个」
 */

/** 长廊里一共多少个数字（1..20） */
export const NUMBER_BLOCKS_MAX: number = 20

export interface NumberBlocksValidationResult {
  ok: boolean
  error: string
  /** 1-20 升序去重；空数组表示「全部」 */
  numbers: number[]
  /** 恒在 1-20 */
  focus: number
  /** v1 恒为 display */
  mode: string
}

/** 长廊的全部数字：[1, 2, …, 20] */
export function allNumberBlocks(): number[] {
  const list: number[] = []
  for (let n = 1; n <= NUMBER_BLOCKS_MAX; n++) {
    list.push(n)
  }
  return list
}

function isBlockNumber(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= NUMBER_BLOCKS_MAX
}

function fail(msg: string): NumberBlocksValidationResult {
  const r: NumberBlocksValidationResult = {
    ok: false,
    error: msg,
    numbers: [],
    focus: 1,
    mode: 'display'
  }
  return r
}

export function validateNumberBlocksArgs(args: string): NumberBlocksValidationResult {
  let parsedAny: Object
  try {
    parsedAny = JSON.parse(args) as Object
  } catch (_e) {
    return fail('number_blocks 参数不是合法 JSON, 请检查后重新打开数字乐园')
  }
  // JSON.parse('null'/'[]'/'123') 不抛错，必须挡住非对象文档，否则读字段时抛 TypeError 绕过 should_retry。
  if (parsedAny === null || typeof parsedAny !== 'object' || Array.isArray(parsedAny)) {
    return fail('number_blocks 参数必须是 JSON 对象, 例如 {"numbers":[1,2,3],"focus":1}')
  }
  const parsed = parsedAny as Record<string, Object>

  let mode = 'display'
  const modeRaw = parsed['mode']
  if (modeRaw !== undefined && modeRaw !== null) {
    if (typeof modeRaw !== 'string') {
      return fail('number_blocks 的 mode 必须是字符串, v1 只支持 display')
    }
    mode = (modeRaw as string).trim()
    if (mode === '') {
      mode = 'display'
    }
    if (mode !== 'display') {
      return fail(`number_blocks 的 mode「${mode}」暂不支持, v1 只支持 display（认数字）`)
    }
  }

  let focusRawValue: number = 0
  const focusRaw = parsed['focus']
  if (focusRaw !== undefined && focusRaw !== null) {
    if (typeof focusRaw !== 'number') {
      return fail('number_blocks 的 focus 必须是整数 1-20')
    }
    focusRawValue = focusRaw as number
    if (!isBlockNumber(focusRawValue)) {
      return fail(`number_blocks 的 focus「${focusRawValue}」无效, 必须是 1-${NUMBER_BLOCKS_MAX} 的整数`)
    }
  }

  const numbers: number[] = []
  const numbersRaw = parsed['numbers']
  if (numbersRaw !== undefined && numbersRaw !== null) {
    if (!Array.isArray(numbersRaw)) {
      return fail('number_blocks 的 numbers 必须是整数数组, 例如 [1,2,3]')
    }
    const list = numbersRaw as Object[]
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'number') {
        return fail('number_blocks 的 numbers 数组里只能放整数')
      }
      const n = item as number
      if (!isBlockNumber(n)) {
        return fail(`number_blocks 的 numbers 里「${n}」无效, 每个都必须是 1-${NUMBER_BLOCKS_MAX} 的整数`)
      }
      if (numbers.indexOf(n) < 0) {
        numbers.push(n)
      }
    }
    numbers.sort((a: number, b: number): number => a - b)
  }

  let focus = focusRawValue
  if (focus === 0) {
    focus = numbers.length > 0 ? numbers[0] : 1
  } else if (numbers.length > 0 && numbers.indexOf(focus) < 0) {
    focus = numbers[0]
  }

  const result: NumberBlocksValidationResult = {
    ok: true,
    error: '',
    numbers: numbers,
    focus: focus,
    mode: mode
  }
  return result
}
