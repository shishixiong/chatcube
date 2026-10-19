import { describe, it, expect } from '@ohos/hypium'
import { parseChainExpression, computeColumnPaperLayout } from '../../../../main/ets/utils/MathColumnPaperLayout'

/**
 * MathColumnPaperLayout 单元测试 (v2 分步块模型)
 *
 * 覆盖: 链式表达式解析 (合法/结构异常/不支持运算符) + 分步竖式块布局
 * (纯加法单块多数 / 含减法顺序块接力 / 进位借位 markExpected / 边界拒绝)。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */
export default function mathColumnPaperLayoutTest() {
  describe('parseChainExpression', () => {
    it('单步: 「47 + 28」解析为 2 操作数 1 运算符', 0, () => {
      const r = parseChainExpression('47 + 28')
      expect(r !== null).assertTrue()
      expect(r!.nums.length).assertEqual(2)
      expect(r!.ops.length).assertEqual(1)
      expect(r!.ops[0]).assertEqual('+')
    })

    it('三步连加连减: 「47 + 28 - 15 + 6」解析为 4 操作数 3 运算符', 0, () => {
      const r = parseChainExpression('47 + 28 - 15 + 6')
      expect(r !== null).assertTrue()
      expect(r!.nums.length).assertEqual(4)
      expect(r!.ops.length).assertEqual(3)
      expect(r!.ops[1]).assertEqual('-')
    })

    it('乘法表达式不支持: 「5 × 3」返回 null', 0, () => {
      expect(parseChainExpression('5 × 3')).assertNull()
    })

    it('除法表达式不支持: 「49 ÷ 7」返回 null', 0, () => {
      expect(parseChainExpression('49 ÷ 7')).assertNull()
    })

    it('结构异常 (运算符开头): 「+ 5」返回 null', 0, () => {
      expect(parseChainExpression('+ 5')).assertNull()
    })

    it('结构异常 (尾部悬挂运算符): 「5 +」返回 null', 0, () => {
      expect(parseChainExpression('5 +')).assertNull()
    })

    it('空表达式返回 null', 0, () => {
      expect(parseChainExpression('')).assertNull()
    })
  })

  describe('computeColumnPaperLayout - 合法路径', () => {
    it('单步加法: 8 + 5, 进位标记在十位, 结果逐位 LSB [3,1]', 0, () => {
      const r = computeColumnPaperLayout([8, 5], ['+'])
      expect(r !== null).assertTrue()
      expect(r!.blocks.length).assertEqual(1)
      const b = r!.blocks[0]
      expect(b.cols).assertEqual(2)
      expect(b.operands.length).assertEqual(2)
      expect(b.operands[0].op).assertEqual('')
      expect(b.operands[1].op).assertEqual('+')
      expect(b.markExpected[1]).assertEqual('carry')
      expect(b.resultCorrect[0]).assertEqual('3')
      expect(b.resultCorrect[1]).assertEqual('1')
      expect(b.answerPlaces).assertEqual(2)
      expect(b.chainedTop).assertFalse()
      expect(r!.expressionText).assertEqual('8 + 5')
    })

    it('多数连加: 12 + 34 + 56 单块 3 行, 个位十位连续进位', 0, () => {
      const r = computeColumnPaperLayout([12, 34, 56], ['+', '+'])
      expect(r !== null).assertTrue()
      expect(r!.blocks.length).assertEqual(1)
      const b = r!.blocks[0]
      expect(b.cols).assertEqual(3)
      expect(b.operands.length).assertEqual(3)
      expect(b.operands[2].op).assertEqual('+')
      expect(b.markExpected[1]).assertEqual('carry')
      expect(b.markExpected[2]).assertEqual('carry')
      expect(b.resultCorrect[0]).assertEqual('2')
      expect(b.resultCorrect[1]).assertEqual('0')
      expect(b.resultCorrect[2]).assertEqual('1')
    })

    it('顶层溢出无标记: 999 + 999 = 1998, 进位标记只在 1/2/3 位', 0, () => {
      const r = computeColumnPaperLayout([999, 999], ['+'])
      expect(r !== null).assertTrue()
      const b = r!.blocks[0]
      expect(b.cols).assertEqual(4)
      expect(b.markExpected[0]).assertEqual('')
      expect(b.markExpected[1]).assertEqual('carry')
      expect(b.markExpected[2]).assertEqual('carry')
      expect(b.markExpected[3]).assertEqual('carry')
      expect(b.resultCorrect[3]).assertEqual('1')
    })

    it('4 操作数连加 999×4 = 3996 仍在 4 位上限内, 合法', 0, () => {
      const r = computeColumnPaperLayout([999, 999, 999, 999], ['+', '+', '+'])
      expect(r !== null).assertTrue()
      expect(r!.blocks.length).assertEqual(1)
      expect(r!.blocks[0].cols).assertEqual(4)
    })

    it('混合链: 47 + 28 - 15 拆 2 块, 后块 chainedTop 且顶数接力 75 - 15', 0, () => {
      const r = computeColumnPaperLayout([47, 28, 15], ['+', '-'])
      expect(r !== null).assertTrue()
      expect(r!.blocks.length).assertEqual(2)
      expect(r!.blocks[0].chainedTop).assertFalse()
      expect(r!.blocks[0].resultCorrect[0]).assertEqual('5')
      expect(r!.blocks[0].resultCorrect[1]).assertEqual('7')
      const b2 = r!.blocks[1]
      expect(b2.chainedTop).assertTrue()
      expect(b2.operands.length).assertEqual(2)
      expect(b2.operands[1].op).assertEqual('-')
      expect(b2.resultCorrect[0]).assertEqual('0')
      expect(b2.resultCorrect[1]).assertEqual('6')
      expect(r!.expressionText).assertEqual('47 + 28 - 15')
    })

    it('连减: 500 - 123 - 88 拆 2 块, 借位标记走「划掉变小」语义', 0, () => {
      const r = computeColumnPaperLayout([500, 123, 88], ['-', '-'])
      expect(r !== null).assertTrue()
      expect(r!.blocks.length).assertEqual(2)
      const b1 = r!.blocks[0]
      // 500-123: 百位 5 被借走变小 → mark[2]; 中间 0 变 9 不标
      expect(b1.markExpected[2]).assertEqual('borrow')
      expect(b1.markExpected[1]).assertEqual('')
      expect(b1.resultCorrect[0]).assertEqual('7')
      expect(b1.resultCorrect[1]).assertEqual('7')
      expect(b1.resultCorrect[2]).assertEqual('3')
      const b2 = r!.blocks[1]
      // 377-88: 十位/百位连续借位
      expect(b2.chainedTop).assertTrue()
      expect(b2.markExpected[1]).assertEqual('borrow')
      expect(b2.markExpected[2]).assertEqual('borrow')
      expect(b2.resultCorrect[0]).assertEqual('9')
      expect(b2.resultCorrect[1]).assertEqual('8')
      expect(b2.resultCorrect[2]).assertEqual('2')
    })

    it('单步减法借位: 50 - 18 = 32, 十位标记借位', 0, () => {
      const r = computeColumnPaperLayout([50, 18], ['-'])
      expect(r !== null).assertTrue()
      const b = r!.blocks[0]
      expect(b.markExpected[1]).assertEqual('borrow')
      expect(b.resultCorrect[0]).assertEqual('2')
      expect(b.resultCorrect[1]).assertEqual('3')
    })
  })

  describe('computeColumnPaperLayout - 拒绝路径', () => {
    it('操作数过少 (1 个) 返回 null', 0, () => {
      expect(computeColumnPaperLayout([5], [])).assertNull()
    })

    it('操作数过多 (5 个 = 4 步链) 返回 null', 0, () => {
      expect(computeColumnPaperLayout([1, 2, 3, 4, 5], ['+', '+', '+', '+'])).assertNull()
    })

    it('ops 数与操作数数不匹配返回 null', 0, () => {
      expect(computeColumnPaperLayout([47, 28], ['+', '-'])).assertNull()
    })

    it('操作数超 999 返回 null', 0, () => {
      expect(computeColumnPaperLayout([1000, 5], ['+'])).assertNull()
    })

    it('操作数为负返回 null', 0, () => {
      expect(computeColumnPaperLayout([-3, 5], ['+'])).assertNull()
    })

    it('操作数非整数返回 null', 0, () => {
      expect(computeColumnPaperLayout([1.5, 5], ['+'])).assertNull()
    })

    it('不支持除法运算符返回 null', 0, () => {
      expect(computeColumnPaperLayout([5, 2], ['/'])).assertNull()
    })

    it('中间过程为负: 5 - 18 + 20 返回 null (顺序块 5 < 18)', 0, () => {
      expect(computeColumnPaperLayout([5, 18, 20], ['-', '+'])).assertNull()
    })
  })
}
