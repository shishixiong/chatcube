import { describe, it, expect } from '@ohos/hypium'
import { validateMathQuizArgs } from '../../../../main/ets/utils/MathQuizValidation'

/**
 * MathQuizValidation 单元测试
 *
 * 覆盖 5 种题型的合法路径 + 各类校验失败路径。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

// 显式声明的参数夹具接口: ArkTS 禁止把无类型对象字面量传给 Record/Object（arkts-no-untyped-obj-literals）
interface QuizArgsFixture {
  type?: string
  question?: string
  expression?: string
  correct_answer?: string | number
  options?: Array<string | number>
  skill_key?: string
  purpose?: string
  word_problem?: boolean
  shape_ask?: string
  shape?: string
  fraction_ask?: string
  frac_form?: string
  frac_parts?: number
  frac_shaded?: number
  frac_shaded2?: number
  left_value?: number
  right_value?: number
  operator_options?: string[]
  clock_hour?: number
  clock_minute?: number
  start_hour?: number
  start_minute?: number
  end_hour?: number
  end_minute?: number
}

function buildArgs(overrides: QuizArgsFixture): string {
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

    it('shape: 数边 (shape_ask=sides) 答案与图形一致, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: '正方形有几条边?', skill_key: 'math_shapes',
        shape_ask: 'sides', shape: 'square', correct_answer: 4,
        options: [3, 4, 5, 6]
      }))
      expect(r.ok).assertTrue()
    })

    it('shape: 数角 (shape_ask=corners) 答案与图形一致, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: '五边形有几个角?', skill_key: 'math_shapes',
        shape_ask: 'corners', shape: 'pentagon', correct_answer: 5,
        options: [3, 4, 5, 6]
      }))
      expect(r.ok).assertTrue()
    })

    it('fraction: identify 答案与 frac_shaded/frac_parts 一致, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: '涂色部分是几分之几?', skill_key: 'math_fractions',
        fraction_ask: 'identify', frac_form: 'pizza', frac_parts: 4, frac_shaded: 3,
        correct_answer: '3/4', options: ['1/4', '3/4', '2/4', '4/4']
      }))
      expect(r.ok).assertTrue()
    })

    it('fraction: compare 同分母比分子方向正确, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: '2/5 和 3/5 哪个大?', skill_key: 'math_fractions',
        fraction_ask: 'compare', frac_parts: 5, frac_shaded: 2, frac_shaded2: 3,
        correct_answer: '<', operator_options: ['>', '<', '='], options: []
      }))
      expect(r.ok).assertTrue()
    })

    it('fraction: compare 两边同样多时答案是「=」, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: '2/6 和 2/6 比一比', skill_key: 'math_fractions',
        fraction_ask: 'compare', frac_parts: 6, frac_shaded: 2, frac_shaded2: 2,
        correct_answer: '=', options: []
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

    it('连加连减超过 3 步 (4 个运算符), 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: 'q', expression: '1 + 2 + 3 + 4 + 5',
        correct_answer: 15, options: [10, 15, 20, 25]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('最多 3 步')).assertTrue()
    })

    it('连加连减 3 步 (3 个运算符) 且答案一致, 合法', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: 'q', expression: '47 + 28 - 15',
        correct_answer: 60, options: [45, 60, 75, 90]
      }))
      expect(r.ok).assertTrue()
    })

    it('计算结果为负数, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'arithmetic', question: 'q', expression: '5 - 18',
        correct_answer: -13, options: [-13, 0, 13, 23]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('负数')).assertTrue()
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

    it('shape: sides 答案错 (square 说 5 条边), 拒绝并指出真值', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: '正方形有几条边?', shape_ask: 'sides', shape: 'square',
        correct_answer: 5, options: [3, 4, 5, 6]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('边数是 4')).assertTrue()
    })

    it('shape: sides 用 circle, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: '圆形有几条边?', shape_ask: 'sides', shape: 'circle',
        correct_answer: 1, options: [0, 1, 2, 3]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('circle')).assertTrue()
    })

    it('shape: 数边题选项缺真值, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'shape', question: 'q', shape_ask: 'sides', shape: 'triangle',
        correct_answer: 3, options: [4, 5, 6]
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项里')).assertTrue()
    })

    it('fraction: 图是 3/4 但答案写 2/4, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: 'q', fraction_ask: 'identify',
        frac_parts: 4, frac_shaded: 3, correct_answer: '2/4',
        options: ['2/4', '3/4', '1/4']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('3/4')).assertTrue()
    })

    it('fraction: identify 选项缺正确分数, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: 'q', fraction_ask: 'identify',
        frac_parts: 4, frac_shaded: 3, correct_answer: '3/4',
        options: ['1/4', '2/4', '1/2']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项里')).assertTrue()
    })

    it('fraction: frac_parts 越界 (9), 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: 'q', fraction_ask: 'identify',
        frac_parts: 9, frac_shaded: 1, correct_answer: '1/9',
        options: ['1/9', '1/8']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('2-8')).assertTrue()
    })

    it('fraction: frac_shaded 取满 (整体 1), 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: 'q', fraction_ask: 'identify',
        frac_parts: 4, frac_shaded: 4, correct_answer: '4/4',
        options: ['1/4', '4/4']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('整体 1')).assertTrue()
    })

    it('fraction: compare 方向反了, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: 'q', fraction_ask: 'compare',
        frac_parts: 5, frac_shaded: 2, frac_shaded2: 3, correct_answer: '>', options: []
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('方向错误')).assertTrue()
    })

    it('fraction: compare 的 frac_shaded2 越界, 拒绝', 0, () => {
      const r = validateMathQuizArgs(buildArgs({
        type: 'fraction', question: 'q', fraction_ask: 'compare',
        frac_parts: 4, frac_shaded: 2, frac_shaded2: 4, correct_answer: '<', options: []
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('frac_shaded2')).assertTrue()
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
