import { describe, it, expect } from '@ohos/hypium'
import {
  VerticalMathOperation,
  VerticalMathValidationError,
  VerticalMathStep,
  VerticalMathBoardRow,
  validateVerticalMathInputs,
  solveVerticalAdd,
  solveVerticalSubtract,
  solveVerticalMultiply,
  solveVerticalDivide,
  solveVerticalMath
} from '../../../main/ets/utils/VerticalMathSolver'
import {
  VERTICAL_MATH_BOARD_TEXT,
  VERTICAL_MATH_BOARD_LINE,
  VERTICAL_MATH_DONE_TEXT,
  VERTICAL_MATH_CARRY_TEXT,
  VERTICAL_MATH_BORROW_TEXT
} from '../../../main/ets/utils/VerticalMathColors'

export default function verticalMathSolverTest() {
  describe('validateVerticalMathInputs', () => {
    it('returns null for valid addition', 0, () => {
      const err: VerticalMathValidationError | null = validateVerticalMathInputs(
        VerticalMathOperation.ADD, 47, 28
      )
      expect(err === null).assertEqual(true)
    })

    it('rejects A > 999', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.ADD, 1000, 1)
      expect(err instanceof VerticalMathValidationError).assertEqual(true)
    })

    it('rejects negative B', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.SUBTRACT, 50, -1)
      expect(err instanceof VerticalMathValidationError).assertEqual(true)
    })

    it('rejects non-integer A', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.ADD, 1.5, 2)
      expect(err instanceof VerticalMathValidationError).assertEqual(true)
    })

    it('rejects subtract when A < B', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.SUBTRACT, 10, 50)
      expect((err?.message ?? '')).assertEqual('不够减，建议换一道题哦')
    })

    it('rejects multiply when B > 9', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.MULTIPLY, 100, 10)
      expect((err?.message ?? '')).assertEqual('乘法的第二个数请输入 0–9')
    })

    it('rejects divide when B = 0', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.DIVIDE, 50, 0)
      expect((err?.message ?? '')).assertEqual('除数不能为 0')
    })

    it('rejects divide when B > 9', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.DIVIDE, 50, 12)
      expect((err?.message ?? '')).assertEqual('除数请输入 1–9')
    })

    it('accepts boundary A = 0', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.ADD, 0, 0)
      expect(err === null).assertEqual(true)
    })

    it('accepts boundary A = 999', 0, () => {
      let err: VerticalMathValidationError | null = validateVerticalMathInputs(
        VerticalMathOperation.ADD, 999, 999
      )
      expect(err === null).assertEqual(true)
      err = validateVerticalMathInputs(VerticalMathOperation.MULTIPLY, 999, 9)
      expect(err === null).assertEqual(true)
    })
  })

  describe('solveVerticalAdd', () => {
    it('47 + 28 = 75 with one carry', 0, () => {
      const s = solveVerticalAdd(47, 28)
      expect(s.result).assertEqual(75)
      expect(s.remainder).assertEqual(0)
      expect(s.columnCount).assertEqual(2)
      // alignment step first
      expect(s.steps[0].title).assertEqual('数位对齐')
      // exactly one step should carry (units: 7+8=15)
      const carrySteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))
      expect(carrySteps.length).assertEqual(1)
      // last step is the result
      expect(s.steps[s.steps.length - 1].showResultRow).assertEqual(true)
      expect(s.finalRow?.cells.join('')).assertEqual('75')
    })

    it('100 + 200 = 300 with no carry', 0, () => {
      const s = solveVerticalAdd(100, 200)
      expect(s.result).assertEqual(300)
      expect(s.steps.every((step: VerticalMathStep) =>
        !step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))).assertEqual(true)
    })

    it('999 + 1 = 1000 (carry cascades)', 0, () => {
      const s = solveVerticalAdd(999, 1)
      expect(s.result).assertEqual(1000)
      expect(s.columnCount).assertEqual(4)
      const carrySteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))
      expect(carrySteps.length >= 3).assertEqual(true)
    })

    it('0 + 0 = 0', 0, () => {
      const s = solveVerticalAdd(0, 0)
      expect(s.result).assertEqual(0)
      expect(s.columnCount).assertEqual(1)
    })
  })

  describe('solveVerticalSubtract', () => {
    it('503 - 278 = 225 with cascading borrow', 0, () => {
      const s = solveVerticalSubtract(503, 278)
      expect(s.result).assertEqual(225)
      // expect at least one step with a '•' topMark (borrow marker)
      const borrowSteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '•'))
      expect(borrowSteps.length >= 2).assertEqual(true)
    })

    it('100 - 50 = 50 with no borrow', 0, () => {
      const s = solveVerticalSubtract(100, 50)
      expect(s.result).assertEqual(50)
      const borrowSteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '•'))
      expect(borrowSteps.length).assertEqual(0)
    })

    it('999 - 999 = 0', 0, () => {
      const s = solveVerticalSubtract(999, 999)
      expect(s.result).assertEqual(0)
      expect(s.columnCount).assertEqual(3)
    })
  })

  describe('solveVerticalMultiply', () => {
    it('988 × 6 = 5928 with three aligned partial products', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      expect(s.result).assertEqual(5928)
      expect(s.columnCount).assertEqual(4)
      const expectedRows: string[] = ['  48', ' 48 ', '54  ']
      for (let index = 0; index < expectedRows.length; index++) {
        expect(s.steps[index + 1].rows[s.steps[index + 1].rows.length - 1].cells.join(''))
          .assertEqual(expectedRows[index])
      }
      expect(s.steps.every((step: VerticalMathStep) =>
        !step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))).assertEqual(true)
    })

    it('5 × 3 = 15 (single digit × single digit)', 0, () => {
      const s = solveVerticalMultiply(5, 3)
      expect(s.result).assertEqual(15)
      expect(s.columnCount).assertEqual(2)
    })

    it('123 × 0 = 0', 0, () => {
      const s = solveVerticalMultiply(123, 0)
      expect(s.result).assertEqual(0)
    })

    it('multiplier highlights pair with current multiplicand digit', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      for (let index = 1; index <= 3; index++) {
        const activeHighlights = s.steps[index].highlights.filter(highlight => highlight.kind === 'active')
        expect(activeHighlights.length >= 2).assertEqual(true)
        expect(activeHighlights.some(highlight => highlight.rowIndex === 1)).assertEqual(true)
        expect(activeHighlights.some(highlight => highlight.rowIndex === 0)).assertEqual(true)
      }
    })
  })

  describe('solveVerticalDivide', () => {
    it('84 ÷ 4 = 21 remainder 0', 0, () => {
      const s = solveVerticalDivide(84, 4)
      expect(s.result).assertEqual(21)
      expect(s.remainder).assertEqual(0)
    })

    it('85 ÷ 4 = 21 remainder 1', 0, () => {
      const s = solveVerticalDivide(85, 4)
      expect(s.result).assertEqual(21)
      expect(s.remainder).assertEqual(1)
    })

    it('3 ÷ 7 first digit < divisor (no leading zero)', 0, () => {
      const s = solveVerticalDivide(3, 7)
      expect(s.result).assertEqual(0)
      expect(s.remainder).assertEqual(3)
      // The narration should mention "首位不够除" at least once.
      expect(s.steps.some((step: VerticalMathStep) => step.narration.includes('首位不够除'))).assertEqual(true)
    })

    it('0 ÷ 5 = 0 remainder 0', 0, () => {
      const s = solveVerticalDivide(0, 5)
      expect(s.result).assertEqual(0)
      expect(s.remainder).assertEqual(0)
    })

    it('999 ÷ 9 = 111 remainder 0', 0, () => {
      const s = solveVerticalDivide(999, 9)
      expect(s.result).assertEqual(111)
      expect(s.remainder).assertEqual(0)
    })
  })

  describe('VerticalMathColors', () => {
    it('uses readable cream-board colors', 0, () => {
      expect(VERTICAL_MATH_BOARD_TEXT).assertEqual('#3a3320')
      expect(VERTICAL_MATH_BOARD_LINE).assertEqual('rgba(58, 51, 32, 0.55)')
      expect(VERTICAL_MATH_DONE_TEXT).assertEqual('#15803d')
      expect(VERTICAL_MATH_CARRY_TEXT).assertEqual('#dc2626')
      expect(VERTICAL_MATH_BORROW_TEXT).assertEqual('#7c3aed')
    })
  })

  describe('solveVerticalMath orchestrator', () => {
    it('dispatches to addition', 0, () => {
      const s = solveVerticalMath(VerticalMathOperation.ADD, 47, 28)
      expect(s.operation).assertEqual(VerticalMathOperation.ADD)
      expect(s.result).assertEqual(75)
      expect(s.errorMessage === undefined).assertEqual(true)
    })

    it('dispatches to subtraction', 0, () => {
      const s = solveVerticalMath(VerticalMathOperation.SUBTRACT, 503, 278)
      expect(s.result).assertEqual(225)
    })

    it('dispatches to multiplication', 0, () => {
      const s = solveVerticalMath(VerticalMathOperation.MULTIPLY, 988, 6)
      expect(s.result).assertEqual(5928)
    })

    it('dispatches to division', 0, () => {
      const s = solveVerticalMath(VerticalMathOperation.DIVIDE, 85, 4)
      expect(s.result).assertEqual(21)
      expect(s.remainder).assertEqual(1)
    })

    it('returns a validation-error solution on illegal inputs', 0, () => {
      const s = solveVerticalMath(VerticalMathOperation.SUBTRACT, 5, 50)
      expect(s.errorMessage !== undefined).assertEqual(true)
      expect(s.steps.length).assertEqual(0)
    })
  })
}
