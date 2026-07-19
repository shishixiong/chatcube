import { describe, it, expect } from '@ohos/hypium'
import {
  VerticalMathOperation,
  VerticalMathValidationError,
  VerticalMathStep,
  VerticalMathBoardRow,
  validateVerticalMathInputs,
  solveVerticalAdd,
  solveVerticalSubtract
} from '../../../main/ets/utils/VerticalMathSolver'

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
}
