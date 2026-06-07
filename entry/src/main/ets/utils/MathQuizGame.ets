/**
 * MathQuizGame - 数学游戏纯逻辑层
 *
 * 与 MathQuizCard 解耦: 只有数据解析、判定、token 切分等无副作用函数,
 * 组件聚焦 UI 渲染, 也方便将来补 .ets 单测。
 */

import { evaluateMathExpression } from './MathExpressionParser'

export interface MathQuizQuestion {
  question: string
  expression: string
  correctAnswer: number
  options: number[]
  skillKey: string
}

export interface MathQuizAnswerPayload {
  answered: boolean
  child_answer: number
  child_answer_valid: boolean
  correct: boolean
  correct_answer: number
  expression: string
  question: string
  skill_key: string
}

export interface ExpressionToken {
  type: 'number' | 'op'
  value: string
}

/**
 * 解析 AI 传入的 toolCall.arguments JSON 字符串为题目数据。
 * 解析失败时返回空对象, 不抛异常, 由上层决定如何降级渲染。
 */
export function parseMathQuiz(argsJson: string): MathQuizQuestion {
  const result: MathQuizQuestion = {
    question: '',
    expression: '',
    correctAnswer: 0,
    options: [],
    skillKey: ''
  }
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>
    result.question = (parsed['question'] as string) ?? ''
    result.expression = (parsed['expression'] as string) ?? ''
    result.correctAnswer = (parsed['correct_answer'] as number) ?? 0
    result.skillKey = (parsed['skill_key'] as string) ?? ''

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
  const regex = /(\d+\.?\d*|[+\-*/()])/g
  const matches = expr.match(regex)
  if (!matches) {
    return [{ type: 'number', value: expr }]
  }
  for (const m of matches) {
    if (m.length === 1 && '+-*/()'.includes(m)) {
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
 * 判定选项是否等于正确答案。选项都是 number, 直接 === 即可。
 */
export function isCorrectAnswer(selected: number, correct: number): boolean {
  return selected === correct
}
