import { describe, it, expect } from '@ohos/hypium'
import { validateMathQuizArgs } from '../../../../main/ets/utils/MathQuizValidation'

/**
 * MathQuizValidation 单元测试
 *
 * 覆盖 5 种题型的合法路径 + 各类校验失败路径。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function buildArgs(overrides: Record<string, Object>): string {
  return JSON.stringify(overrides)
}

export default function mathQuizValidationTest() {
  describe('validateMathQuizArgs - 合法路径', () => {
    it('arithmetic: 数字答案在 4 个数字选项里, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: '3 加 2 等于几?', expression: '3 + 2',
        correct_answer: 5, options: [3, 5, 7, 9], skill_key: 'math_addition'
      }))
      expect(r.ok).assertTrue()
    })

    it('arithmetic: 缺 correct_answer 但 expression 可计算, 走兜底仍合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: '3 加 2 等于几?', expression: '3 + 2',
        options: [3, 5, 7, 9]
      }))
      expect(r.ok).assertTrue()
    })

    it('shape: 合法形状名 + 选项含答案, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: '哪个是圆形?',
        correct_answer: 'circle', options: ['circle', 'square', 'triangle', 'star']
      }))
      expect(r.ok).assertTrue()
    })

    it('comparison: 3 < 7, 答案「<」方向正确, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'comparison', question: '3 和 7 比一比',
        left_value: 3, right_value: 7, correct_answer: '<',
        operator_options: ['>', '<', '='], options: []
      }))
      expect(r.ok).assertTrue()
    })

    it('comparison: 相等场景 答案「=」, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'comparison', question: '5 和 5 比一比',
        left_value: 5, right_value: 5, correct_answer: '=', options: []
      }))
      expect(r.ok).assertTrue()
    })

    it('time: H:MM 与钟面一致, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'time', question: '钟面上是几点?',
        clock_hour: 3, clock_minute: 30, correct_answer: '3:30',
        options: ['3:30', '3:15', '4:30', '6:00']
      }))
      expect(r.ok).assertTrue()
    })

    it('elapsed_time: 时长与 start/end 计算一致, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'elapsed_time', question: '经过多久?',
        start_hour: 10, start_minute: 0, end_hour: 11, end_minute: 30,
        correct_answer: '1 小时 30 分',
        options: ['1 小时 30 分', '30 分', '2 小时', '1 小时']
      }))
      expect(r.ok).assertTrue()
    })

    it('elapsed_time: 跨正午 (11:30 → 1:30 = 2 小时), 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'elapsed_time', question: '经过多久?',
        start_hour: 11, start_minute: 30, end_hour: 1, end_minute: 30,
        correct_answer: '2 小时',
        options: ['2 小时', '1 小时', '30 分', '3 小时']
      }))
      expect(r.ok).assertTrue()
    })
  })

  describe('validateMathQuizArgs - arithmetic 失败路径', () => {
    it('正确答案不在选项里, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: 'q', expression: '3 + 2',
        correct_answer: 5, options: [3, 4, 6, 7]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项里')).assertTrue()
    })

    it('correct_answer 与 expression 计算结果不一致, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: 'q', expression: '3 + 2',
        correct_answer: 6, options: [3, 6, 7, 9]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不一致')).assertTrue()
    })

    it('correct_answer 非数字且无 expression, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: 'q', correct_answer: 'five', options: [3, 5, 7, 9]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('缺少正确答案')).assertTrue()
    })

    it('数字选项少于 2 个, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: 'q', expression: '3 + 2',
        correct_answer: 5, options: [5]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('至少需要 2 个数字选项')).assertTrue()
    })

    it('参数不是合法 JSON, 拒绝', 0, () => {
      const r = validateMathQuizArgs('{not json')
      expect(r.ok).assertFalse()
      expect(r.error.includes('JSON')).assertTrue()
    })
  })

  describe('validateMathQuizArgs - shape/comparison 失败路径', () => {
    it('shape: 非法形状名, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: 'q', correct_answer: 'oval',
        options: ['circle', 'square', 'oval', 'star']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不是合法形状名')).assertTrue()
    })

    it('shape: 正确答案不在选项里, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: 'q', correct_answer: 'circle',
        options: ['square', 'triangle', 'star', 'heart']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项里')).assertTrue()
    })

    it('comparison: 方向反了 (3<7 却答「>」), 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'comparison', question: 'q',
        left_value: 3, right_value: 7, correct_answer: '>', options: []
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('方向错误')).assertTrue()
      expect(r.error.includes('<')).assertTrue()
    })

    it('comparison: 缺 left_value, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'comparison', question: 'q',
        right_value: 7, correct_answer: '<', options: []
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('left_value')).assertTrue()
    })

    it('comparison: operator_options 缺正确运算符, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'comparison', question: 'q',
        left_value: 3, right_value: 7, correct_answer: '<',
        operator_options: ['>', '='], options: []
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('operator_options')).assertTrue()
    })

    it('comparison: correct_answer 非法字符, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'comparison', question: 'q',
        left_value: 3, right_value: 7, correct_answer: '大', options: []
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不是合法运算符')).assertTrue()
    })
  })

  describe('validateMathQuizArgs - time/elapsed_time 失败路径', () => {
    it('time: 答案与钟面不一致 (3:30 答成 3:15), 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'time', question: 'q', clock_hour: 3, clock_minute: 30,
        correct_answer: '3:15', options: ['3:15', '3:30', '4:30', '6:00']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不一致')).assertTrue()
    })

    it('time: 缺 clock_minute, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'time', question: 'q', clock_hour: 3,
        correct_answer: '3:00', options: ['3:00', '3:30', '4:30', '6:00']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('clock_hour')).assertTrue()
    })

    it('time: 合法时间选项少于 2 个, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'time', question: 'q', clock_hour: 3, clock_minute: 30,
        correct_answer: '3:30', options: ['三点', '早上']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('至少需要 2 个')).assertTrue()
    })

    it('elapsed_time: 时长答案与钟面计算不一致, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'elapsed_time', question: 'q',
        start_hour: 10, start_minute: 0, end_hour: 11, end_minute: 30,
        correct_answer: '30 分',
        options: ['30 分', '1 小时 30 分', '2 小时', '1 小时']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('1 小时 30 分')).assertTrue()
    })

    it('elapsed_time: 缺 end_hour, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'elapsed_time', question: 'q',
        start_hour: 10, start_minute: 0, end_minute: 30,
        correct_answer: '30 分',
        options: ['30 分', '1 小时 30 分', '2 小时', '1 小时']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('end_hour')).assertTrue()
    })
  })
}
