/**
 * MathColumnPaperLayout - 竖式草稿纸布局纯函数层 (v2 分步块模型)
 *
 * 参考 docs/math_draft_refine.html 原型: 竖式纸按「块」组织——
 * - 纯加法链 (12+34+56) → 单块多操作数行, 一次进位模拟
 * - 含减法的链 (47+28-15 / 500-123-88) → 拆成顺序两数块, 前块结果接后块被减数 (chainedTop)
 * 每块自带: 列数 / 操作数逐位格 / 正确结果逐位 / 各列进位借位预期 (markExpected)。
 * markExpected 采用「划掉变小才算借位」语义 (原型 buildSub: 中间 0 变 9 不标)。
 *
 * 与 MathQuizCard / MathScratchSheet 解耦, 无 ArkUI 依赖, 方便补 hypium 单测。
 * 竖式纸仍不回传、不判星; 「检查」自检由 MathColumnPaperBoard 本地完成。
 */

import { tokenizeExpression } from './MathQuizGame'

/** 竖式块一行操作数: op 为 '' 表示首行; cells[place] = 该位数字字符或 '' (place 0 = 个位) */
export interface ColumnBlockOperand {
  op: string
  cells: string[]
}

/** 单块竖式: 两数或多数加法 / 单步减法; 全部位索引 place 从 0 (个位) 起 */
export interface ColumnBlock {
  /** 格子列数 */
  cols: number
  /** 操作数行 (渲染顺序由调用方反转) */
  operands: ColumnBlockOperand[]
  /** 正确结果逐位 (LSB-first, 超出 answerPlaces 的位为 '') */
  resultCorrect: string[]
  /** 结果位数 */
  answerPlaces: number
  /** 各列标记预期: '' | 'carry' | 'borrow' */
  markExpected: string[]
  /** true = 首行操作数来自上一块结果 (上一块填完前显示 ?) */
  chainedTop: boolean
}

/** 竖式纸布局结果; null = 不支持 (调用方隐藏草稿纸入口) */
export interface ColumnPaperLayout {
  /** 1..3 个顺序块 */
  blocks: ColumnBlock[]
  /** 算式显示串, e.g. "47 + 28 - 15" */
  expressionText: string
}

const MAX_OPERANDS: number = 4   // 1-3 步链式 = 2-4 个操作数
const MAX_DIGITS: number = 4     // 999 + 999 × 3 = 3996 → 4 位封顶
const MAX_OPERAND_VALUE: number = 999

/** 链式表达式解析结果 */
export interface ChainExpression {
  nums: number[]
  ops: string[]
}

/**
 * 把算式字符串解析为 + − 链式序列。
 * 要求 token 序列严格为 数字 (op 数字)*, op 仅 + 或 -;
 * 含 × ÷ * / ( ) 或结构异常时返回 null。
 */
export function parseChainExpression(expr: string): ChainExpression | null {
  const tokens = tokenizeExpression(expr)
  const nums: number[] = []
  const ops: string[] = []
  // 期望态: true=等数字, false=等运算符
  let expectNumber: boolean = true
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i]
    if (expectNumber) {
      if (token.type !== 'number') {
        return null
      }
      const n = Number(token.value)
      if (!Number.isFinite(n) || !Number.isInteger(n)) {
        return null
      }
      nums.push(n)
      expectNumber = false
    } else {
      if (token.type !== 'op' || (token.value !== '+' && token.value !== '-')) {
        return null
      }
      ops.push(token.value)
      expectNumber = true
    }
  }
  if (expectNumber || nums.length < 2) {
    return null
  }
  const result: ChainExpression = { nums: nums, ops: ops }
  return result
}

function digitCount(n: number): number {
  return String(n).length
}

/** 数字 → LSB-first 逐位字符数组, 补 '' 到 cols 位 (place 0 = 个位) */
function digitsLsb(n: number, cols: number): string[] {
  const chars = String(n).split('')
  const cells: string[] = []
  // chars 是 MSB-first, 反向取
  for (let p = 0; p < cols; p++) {
    const idx = chars.length - 1 - p
    cells.push(idx >= 0 ? chars[idx] : '')
  }
  return cells
}

/** 0..cols-1 索引 (内部辅助) */
function emptyCells(cols: number): string[] {
  const cells: string[] = []
  for (let p = 0; p < cols; p++) {
    cells.push('')
  }
  return cells
}

/** 第 place 位数字 (超出长度按 0 参与模拟, 与竖式空位一致) */
function digitAtLsb(n: number, place: number): number {
  const chars = String(n)
  const idx = chars.length - 1 - place
  if (idx < 0) {
    return 0
  }
  return Number(chars.charAt(idx))
}

/** 多数加法块: 一次竖式模拟, 进位落在下一位则标记 'carry' */
function buildAddBlock(nums: number[]): ColumnBlock {
  let total = 0
  let cols = 0
  for (let i = 0; i < nums.length; i++) {
    total += nums[i]
    cols = Math.max(cols, digitCount(nums[i]))
  }
  cols = Math.max(cols, digitCount(total))

  const operands: ColumnBlockOperand[] = []
  for (let i = 0; i < nums.length; i++) {
    const row: ColumnBlockOperand = {
      op: i === 0 ? '' : '+',
      cells: digitsLsb(nums[i], cols)
    }
    operands.push(row)
  }

  const markExpected = emptyCells(cols)
  let carry = 0
  for (let p = 0; p < cols; p++) {
    let s = carry
    for (let i = 0; i < nums.length; i++) {
      s += digitAtLsb(nums[i], p)
    }
    carry = Math.floor(s / 10)
    if (carry > 0 && p + 1 < cols) {
      markExpected[p + 1] = 'carry'
    }
  }

  const block: ColumnBlock = {
    cols: cols,
    operands: operands,
    resultCorrect: digitsLsb(total, cols),
    answerPlaces: digitCount(total),
    markExpected: markExpected,
    chainedTop: false
  }
  return block
}

/** 单步减法块 (要求 a ≥ b): 借位标记采用「划掉变小」语义, 中间 0 变 9 不标 */
function buildSubBlock(a: number, b: number): ColumnBlock {
  const diff = a - b
  const cols = Math.max(digitCount(a), digitCount(b), digitCount(diff))

  const markExpected = emptyCells(cols)
  // t = 被减数工作副本 (LSB-first 数值), orig 保留原值用于「变小」判定
  const t: number[] = []
  const orig: number[] = []
  for (let p = 0; p < cols; p++) {
    t.push(digitAtLsb(a, p))
    orig.push(digitAtLsb(a, p))
  }
  for (let p = 0; p < cols; p++) {
    const need = digitAtLsb(b, p)
    if (t[p] < need) {
      // 向上找最近非零位借 1, 中间 0 变 9
      let h = p + 1
      while (h < cols && t[h] === 0) {
        h++
      }
      if (h < cols) {
        t[h] -= 1
        for (let k = h - 1; k > p; k--) {
          t[k] += 9
        }
        if (t[h] < orig[h]) {
          markExpected[h] = 'borrow'
        }
      }
      t[p] += 10
    }
  }

  const operands: ColumnBlockOperand[] = []
  const rowA: ColumnBlockOperand = { op: '', cells: digitsLsb(a, cols) }
  const rowB: ColumnBlockOperand = { op: '-', cells: digitsLsb(b, cols) }
  operands.push(rowA)
  operands.push(rowB)

  const block: ColumnBlock = {
    cols: cols,
    operands: operands,
    resultCorrect: digitsLsb(diff, cols),
    answerPlaces: digitCount(diff),
    markExpected: markExpected,
    chainedTop: false
  }
  return block
}

/**
 * 计算竖式纸布局 (v2 分步块)。任何一项不满足即返回 null (MathQuizCard 据此隐藏草稿纸按钮):
 * - 操作数 2..4 个 (1-3 步), ops 数 = 操作数数 - 1, op 仅 +/-
 * - 每个输入操作数为 0..999 整数
 * - 纯加法链 → 单块多数竖式; 含减法 → 顺序两数块, 前块结果接后块被减数
 * - 每步减法要求 被减数 ≥ 减数 (中间过程非负), 否则 null
 * - 块内列数 ≤ 4
 */
export function computeColumnPaperLayout(nums: number[], ops: string[]): ColumnPaperLayout | null {
  if (nums.length < 2 || nums.length > MAX_OPERANDS) {
    return null
  }
  if (ops.length !== nums.length - 1) {
    return null
  }
  for (let i = 0; i < nums.length; i++) {
    const n = nums[i]
    if (!Number.isFinite(n) || !Number.isInteger(n) || n < 0 || n > MAX_OPERAND_VALUE) {
      return null
    }
  }
  for (let i = 0; i < ops.length; i++) {
    if (ops[i] !== '+' && ops[i] !== '-') {
      return null
    }
  }

  let blocks: ColumnBlock[] = []
  let allAdd = true
  for (let i = 0; i < ops.length; i++) {
    if (ops[i] === '-') {
      allAdd = false
      break
    }
  }

  let expressionText = `${nums[0]} ${ops[0]} ${nums[1]}`
  for (let i = 2; i < nums.length; i++) {
    expressionText = `${expressionText} ${ops[i - 1]} ${nums[i]}`
  }

  if (allAdd) {
    blocks.push(buildAddBlock(nums))
  } else {
    // 含减法: 顺序两数块, running 接力
    let running = nums[0]
    for (let i = 1; i < nums.length; i++) {
      const next = nums[i]
      if (ops[i - 1] === '-') {
        if (running < next) {
          return null
        }
        blocks.push(buildSubBlock(running, next))
        running -= next
      } else {
        blocks.push(buildAddBlock([running, next]))
        running += next
      }
    }
    for (let bi = 1; bi < blocks.length; bi++) {
      blocks[bi].chainedTop = true
    }
  }

  for (let bi = 0; bi < blocks.length; bi++) {
    if (blocks[bi].cols > MAX_DIGITS) {
      return null
    }
  }

  const layout: ColumnPaperLayout = {
    blocks: blocks,
    expressionText: expressionText
  }
  return layout
}
