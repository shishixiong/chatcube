import { describe, it, expect } from '@ohos/hypium'
import {
  VerticalMathOperation,
  VerticalMathValidationError,
  VerticalMathStep,
  VerticalMathBoardRow,
  VerticalMathHighlight,
  VerticalMathOverlay,
  validateVerticalMathInputs,
  solveVerticalAdd,
  solveVerticalSubtract,
  solveVerticalMultiply,
  solveVerticalDivide,
  solveVerticalMath
} from '../../../main/ets/utils/VerticalMathSolver'
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../../../main/ets/utils/VerticalMathColors'

export default function verticalMathSolverTest() {
  describe('VerticalMath presentation models', () => {
    it('creates empty step presentation metadata', 0, () => {
      const step: VerticalMathStep = new VerticalMathStep()
      expect(step.placeLabel).assertEqual('')
      expect(step.actionLabel).assertEqual('')
      expect(step.overlays.length).assertEqual(0)
    })

    it('creates a typed carry overlay', 0, () => {
      const overlay: VerticalMathOverlay = new VerticalMathOverlay()
      expect(overlay.kind).assertEqual('carry_path')
      expect(overlay.sourceColumn).assertEqual(-1)
      expect(overlay.targetColumn).assertEqual(-1)
      expect(overlay.startColumn).assertEqual(-1)
      expect(overlay.endColumn).assertEqual(-1)
      expect(overlay.value).assertEqual('')
    })
  })

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
      expect((err?.message ?? '')).assertEqual('第二个数只能填一位数字')
    })

    it('rejects divide when B = 0', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.DIVIDE, 50, 0)
      expect((err?.message ?? '')).assertEqual('0 不能做除数，换一个数字吧')
    })

    it('rejects divide when B > 9', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.DIVIDE, 50, 12)
      expect((err?.message ?? '')).assertEqual('除数请填 1 到 9')
    })

    it('uses child-friendly range copy', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.ADD, 1000, 1)
      expect(err?.message ?? '').assertEqual('请输入 0 到 999 的数字')
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
      // no standalone alignment step — first step is units computation
      expect(s.steps[0].title).assertEqual('个位相加')
      const carrySteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))
      expect(carrySteps.length).assertEqual(1)
      expect(s.steps[s.steps.length - 1].showResultRow).assertEqual(true)
      expect(s.finalRow?.cells.join('')).assertEqual('75')
    })

    it('shows result and carry path in the same units step', 0, () => {
      const s = solveVerticalAdd(47, 28)
      const units: VerticalMathStep = s.steps[0]
      const carries: VerticalMathOverlay[] = units.overlays.filter(
        (overlay: VerticalMathOverlay): boolean => overlay.kind === 'carry_path'
      )
      expect(units.placeLabel).assertEqual('个位')
      expect(units.actionLabel).assertEqual('算个位')
      expect(units.rows[3].cells[1]).assertEqual('5')
      expect(carries.length).assertEqual(1)
      expect(carries[0].sourceColumn).assertEqual(1)
      expect(carries[0].targetColumn).assertEqual(0)
      expect(carries[0].value).assertEqual('1')
      expect(units.narration.includes('个位写 5')).assertEqual(true)
      expect(units.narration.includes('送到十位')).assertEqual(true)
    })

    it('does not create an empty carry path', 0, () => {
      const s = solveVerticalAdd(22, 33)
      for (let index = 0; index < s.steps.length - 1; index++) {
        expect(s.steps[index].overlays.some(
          (overlay: VerticalMathOverlay): boolean => overlay.kind === 'carry_path'
        )).assertEqual(false)
        expect(s.steps[index].narration.includes('没有新进位')).assertEqual(true)
      }
    })

    it('labels every addition step for child navigation', 0, () => {
      const s = solveVerticalAdd(47, 28)
      expect(s.steps[0].placeLabel).assertEqual('个位')
      expect(s.steps[1].placeLabel).assertEqual('十位')
      expect(s.steps[1].actionLabel).assertEqual('算十位')
      expect(s.steps[s.steps.length - 1].placeLabel).assertEqual('完成')
      expect(s.steps[s.steps.length - 1].actionLabel).assertEqual('完成竖式')
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

    it('marks each newly written addition result digit active', 0, () => {
      const s = solveVerticalAdd(22, 33)
      for (let index = 0; index < s.steps.length - 1; index++) {
        const expectedColumn: number = s.columnCount - 1 - index
        const resultActive: VerticalMathHighlight[] = s.steps[index].highlights.filter(
          (highlight: VerticalMathHighlight): boolean =>
            highlight.rowIndex === 3 && highlight.kind === 'active'
        )
        expect(resultActive.length).assertEqual(1)
        expect(resultActive[0].columnIndex).assertEqual(expectedColumn)
      }
    })

    it('keeps carry columns on later snapshots', 0, () => {
      const s = solveVerticalAdd(47, 28)
      expect(s.steps[0].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
      expect(s.steps[1].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
      expect(s.steps[s.steps.length - 1].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
    })

    it('uses the persistent carry marker on the next higher-column step', 0, () => {
      const s = solveVerticalAdd(47, 28)
      const lowStep: VerticalMathStep = s.steps[0]
      const highStep: VerticalMathStep = s.steps[1]
      const lowActive: VerticalMathHighlight[] = lowStep.highlights.filter(
        (highlight: VerticalMathHighlight): boolean =>
          highlight.rowIndex === 0 && highlight.kind === 'active'
      )
      const highActive: VerticalMathHighlight[] = highStep.highlights.filter(
        (highlight: VerticalMathHighlight): boolean =>
          highlight.rowIndex === 0 && highlight.kind === 'active'
      )
      expect(lowActive[0].columnIndex).assertEqual(1)
      expect(highActive[0].columnIndex).assertEqual(0)
      expect(highStep.rows[0].carryColumns?.includes(highActive[0].columnIndex) ?? false)
        .assertEqual(true)
      expect(lowStep.rows[0].carryColumns?.includes(lowActive[0].columnIndex) ?? false)
        .assertEqual(false)
    })
  })

  describe('solveVerticalSubtract', () => {
    it('503 - 278 = 225 with cascading borrow', 0, () => {
      const s = solveVerticalSubtract(503, 278)
      expect(s.result).assertEqual(225)
      const borrowSteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows[0].borrowColumns !== undefined && step.rows[0].borrowColumns.length > 0)
      expect(borrowSteps.length >= 1).assertEqual(true)
    })

    it('100 - 50 = 50 marks only the hundreds donor', 0, () => {
      const s = solveVerticalSubtract(100, 50)
      expect(s.result).assertEqual(50)
      // Ones column (0-0) needs no borrow; tens column (0<5) borrows from hundreds.
      const onesMarks: number[] = s.steps[0].rows[0].borrowColumns ?? []
      expect(onesMarks.length).assertEqual(0)
      const tensMarks: number[] = s.steps[1].rows[0].borrowColumns ?? []
      expect(tensMarks.length).assertEqual(1)
      expect(tensMarks.includes(0)).assertEqual(true)
    })

    it('999 - 999 = 0', 0, () => {
      const s = solveVerticalSubtract(999, 999)
      expect(s.result).assertEqual(0)
      expect(s.columnCount).assertEqual(3)
    })

    it('marks only the donor column and keeps original digits', 0, () => {
      const s = solveVerticalSubtract(303, 178)
      // Step 0 (ones): 3<8 borrows from hundreds (donor col 0, via a zero at tens).
      const triggerMarks: number[] = s.steps[0].rows[0].borrowColumns ?? []
      expect(triggerMarks.length).assertEqual(1)
      expect(triggerMarks.includes(0)).assertEqual(true)
      // Original digits are preserved on the operand-A row (no 9s, no decrements).
      expect(s.steps[0].rows[0].cells.join('')).assertEqual('303')
      // The result column for the active step is highlighted.
      for (let index = 0; index < s.steps.length - 1; index++) {
        const expectedColumn: number = s.columnCount - 1 - index
        const resultActive: VerticalMathHighlight[] = s.steps[index].highlights.filter(
          (highlight: VerticalMathHighlight): boolean =>
            highlight.rowIndex === 3 && highlight.columnIndex === expectedColumn &&
              highlight.kind === 'active'
        )
        expect(resultActive.length).assertEqual(1)
      }
      // Borrow markers persist through later snapshots and the final answer.
      for (let index = 0; index < s.steps.length; index++) {
        const marks: number[] = s.steps[index].rows[0].borrowColumns ?? []
        expect(marks.length).assertEqual(1)
        expect(marks.includes(0)).assertEqual(true)
      }
    })

    it('marks the donor column for the active borrow step', 0, () => {
      const s = solveVerticalSubtract(503, 278)
      const activeStep: VerticalMathStep = s.steps[0]
      const activeA: VerticalMathHighlight[] = activeStep.highlights.filter(
        (highlight: VerticalMathHighlight): boolean =>
          highlight.rowIndex === 0 && highlight.kind === 'active'
      )
      expect(activeA.length).assertEqual(1)
      // The '-1' marker sits on the DONOR column (bridge sourceColumn), not the
      // active recipient column.
      const bridges: VerticalMathOverlay[] = activeStep.overlays.filter(
        (overlay: VerticalMathOverlay): boolean => overlay.kind === 'borrow_bridge'
      )
      const donorColumn: number = bridges[0].sourceColumn
      expect(activeStep.rows[0].borrowColumns?.includes(donorColumn) ?? false)
        .assertEqual(true)
      const finalStep: VerticalMathStep = s.steps[s.steps.length - 1]
      expect(finalStep.highlights.some(
        (highlight: VerticalMathHighlight): boolean =>
          highlight.rowIndex === 0 && highlight.kind === 'active'
      )).assertEqual(false)
    })

    it('creates a bridge for a direct borrow', 0, () => {
      const s = solveVerticalSubtract(42, 18)
      const units: VerticalMathStep = s.steps[0]
      const bridges: VerticalMathOverlay[] = units.overlays.filter(
        (overlay: VerticalMathOverlay): boolean => overlay.kind === 'borrow_bridge'
      )
      expect(bridges.length).assertEqual(1)
      expect(bridges[0].sourceColumn).assertEqual(0)
      expect(bridges[0].targetColumn).assertEqual(1)
      expect(units.narration.includes('2 不够减 8')).assertEqual(true)
      expect(units.narration.includes('从十位借 1')).assertEqual(true)
    })

    it('connects the donor to the target for a cascading borrow', 0, () => {
      const s = solveVerticalSubtract(503, 278)
      const units: VerticalMathStep = s.steps[0]
      const bridges: VerticalMathOverlay[] = units.overlays.filter(
        (overlay: VerticalMathOverlay): boolean => overlay.kind === 'borrow_bridge'
      )
      expect(bridges.length).assertEqual(1)
      expect(bridges[0].sourceColumn).assertEqual(0)
      expect(bridges[0].targetColumn).assertEqual(2)
      expect(units.rows[0].borrowColumns?.includes(0) ?? false).assertEqual(true)
      expect(units.rows[0].borrowColumns?.includes(1) ?? false).assertEqual(false)
      expect(units.rows[0].borrowColumns?.includes(2) ?? false).assertEqual(false)
    })

    it('labels every subtraction step for navigation', 0, () => {
      const s = solveVerticalSubtract(42, 18)
      expect(s.steps[0].placeLabel).assertEqual('个位')
      expect(s.steps[0].actionLabel).assertEqual('算个位')
      expect(s.steps[1].placeLabel).assertEqual('十位')
      expect(s.steps[s.steps.length - 1].placeLabel).assertEqual('完成')
    })

    it('150 - 64 step 1 shows original digits and marks only the tens donor', 0, () => {
      const s = solveVerticalSubtract(150, 64)
      expect(s.result).assertEqual(86)
      // Operand-A row keeps the original 150 (not mutated to 140).
      expect(s.steps[0].rows[0].cells.join('')).assertEqual('150')
      // Only the tens column (donor, col 1) carries the '-1' marker.
      const marks: number[] = s.steps[0].rows[0].borrowColumns ?? []
      expect(marks.length).assertEqual(1)
      expect(marks.includes(1)).assertEqual(true)
    })

    it('42 - 18 step 1 borrowColumns shows only the tens donor', 0, () => {
      const s = solveVerticalSubtract(42, 18)
      expect(s.result).assertEqual(24)
      const marks: number[] = s.steps[0].rows[0].borrowColumns ?? []
      expect(marks.length).assertEqual(1)
      expect(marks.includes(0)).assertEqual(true)
    })
    it('keeps accumulated subtraction borrow markers on later and final snapshots', 0, () => {
      const s150 = solveVerticalSubtract(150, 64)
      const s150Step2Marks: number[] = s150.steps[1].rows[0].borrowColumns ?? []
      expect(s150Step2Marks.join(',')).assertEqual('1,0')
      const s150Step3Marks: number[] = s150.steps[2].rows[0].borrowColumns ?? []
      expect(s150Step3Marks.join(',')).assertEqual('1,0')
      const s150FinalMarks: number[] = s150.steps[s150.steps.length - 1].rows[0].borrowColumns ?? []
      expect(s150FinalMarks.join(',')).assertEqual('1,0')

      const s42 = solveVerticalSubtract(42, 18)
      const s42Step2Marks: number[] = s42.steps[1].rows[0].borrowColumns ?? []
      expect(s42Step2Marks.join(',')).assertEqual('0')
      const s42FinalMarks: number[] = s42.steps[s42.steps.length - 1].rows[0].borrowColumns ?? []
      expect(s42FinalMarks.join(',')).assertEqual('0')

      const s503 = solveVerticalSubtract(503, 278)
      const s503Step2Marks: number[] = s503.steps[1].rows[0].borrowColumns ?? []
      expect(s503Step2Marks.join(',')).assertEqual('0')
      const s503Step3Marks: number[] = s503.steps[2].rows[0].borrowColumns ?? []
      expect(s503Step3Marks.join(',')).assertEqual('0')
      const s503FinalMarks: number[] = s503.steps[s503.steps.length - 1].rows[0].borrowColumns ?? []
      expect(s503FinalMarks.join(',')).assertEqual('0')

      const s100 = solveVerticalSubtract(100, 50)
      const s100Step3Marks: number[] = s100.steps[2].rows[0].borrowColumns ?? []
      expect(s100Step3Marks.join(',')).assertEqual('0')
      const s100FinalMarks: number[] = s100.steps[s100.steps.length - 1].rows[0].borrowColumns ?? []
      expect(s100FinalMarks.join(',')).assertEqual('0')
    })

    it('keeps addition carry markers unchanged', 0, () => {
      const s = solveVerticalAdd(56, 94)
      const tensMarks: number[] = s.steps[1].rows[0].carryColumns ?? []
      expect(tensMarks.join(',')).assertEqual('1')
      const hundredsMarks: number[] = s.steps[2].rows[0].carryColumns ?? []
      expect(hundredsMarks.join(',')).assertEqual('1')
      const finalMarks: number[] = s.steps[s.steps.length - 1].rows[0].carryColumns ?? []
      expect(finalMarks.join(',')).assertEqual('1')
    })
  })

  describe('solveVerticalMultiply', () => {
    it('988 × 6 = 5928 with three aligned partial products', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      expect(s.result).assertEqual(5928)
      expect(s.columnCount).assertEqual(4)
      const expectedRows: string[] = ['  48', ' 48 ', '54  ']
      for (let index = 0; index < expectedRows.length; index++) {
        expect(s.steps[index].rows[s.steps[index].rows.length - 1].cells.join(''))
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
      for (let index = 0; index < 3; index++) {
        const activeHighlights = s.steps[index].highlights.filter(highlight => highlight.kind === 'active')
        expect(activeHighlights.length >= 2).assertEqual(true)
        expect(activeHighlights.some(highlight => highlight.rowIndex === 1)).assertEqual(true)
        expect(activeHighlights.some(highlight => highlight.rowIndex === 0)).assertEqual(true)
      }
    })

    it('marks every non-empty current partial-product cell active', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      for (let index = 0; index < 3; index++) {
        const partialRowIndex: number = s.steps[index].rows.length - 1
        const partialCells: string[] = s.steps[index].rows[partialRowIndex].cells
        for (let column = 0; column < partialCells.length; column++) {
          if (partialCells[column] !== '') {
            expect(s.steps[index].highlights.some(
              (highlight: VerticalMathHighlight): boolean =>
                highlight.rowIndex === partialRowIndex && highlight.columnIndex === column &&
                  highlight.kind === 'active'
            )).assertEqual(true)
          }
        }
      }
    })

    it('matches each partial band to its non-empty product range', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      for (let index = 0; index < 3; index++) {
        const step: VerticalMathStep = s.steps[index]
        const partialRowIndex: number = step.rows.length - 1
        const cells: string[] = step.rows[partialRowIndex].cells
        let expectedStart: number = -1
        let expectedEnd: number = -1
        for (let column = 0; column < cells.length; column++) {
          if (cells[column] !== '') {
            if (expectedStart < 0) expectedStart = column
            expectedEnd = column
          }
        }
        const bands: VerticalMathOverlay[] = step.overlays.filter(
          (overlay: VerticalMathOverlay): boolean => overlay.kind === 'partial_band'
        )
        expect(bands.length).assertEqual(1)
        expect(bands[0].rowIndex).assertEqual(partialRowIndex)
        expect(bands[0].startColumn).assertEqual(expectedStart)
        expect(bands[0].endColumn).assertEqual(expectedEnd)
        expect(step.placeLabel.length > 0).assertEqual(true)
        expect(step.actionLabel.length > 0).assertEqual(true)
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
      // No alignment step: only the final answer step remains.
      expect(s.steps.length).assertEqual(1)
      expect(s.steps[0].title).assertEqual('得到答案')
    })

    it('999 ÷ 9 = 111 remainder 0', 0, () => {
      const s = solveVerticalDivide(999, 9)
      expect(s.result).assertEqual(111)
      expect(s.remainder).assertEqual(0)
    })

    it('marks each written quotient digit with the active quotient semantic', 0, () => {
      const s = solveVerticalDivide(84, 4)
      const quotientSteps: VerticalMathStep[] = s.steps.filter(
        (step: VerticalMathStep): boolean =>
          step.highlights.some((highlight: VerticalMathHighlight): boolean => highlight.kind === 'quotient')
      )
      expect(quotientSteps.length).assertEqual(2)
      for (let index = 0; index < quotientSteps.length; index++) {
        expect(quotientSteps[index].highlights.some(
          (highlight: VerticalMathHighlight): boolean =>
            highlight.rowIndex === 3 && highlight.columnIndex === index && highlight.kind === 'quotient'
        )).assertEqual(true)
      }
    })

    it('connects each dividend window to its quotient position', 0, () => {
      const s = solveVerticalDivide(84, 4)
      const quotientSteps: VerticalMathStep[] = s.steps.filter(
        (step: VerticalMathStep): boolean => step.overlays.some(
          (overlay: VerticalMathOverlay): boolean => overlay.kind === 'division_lane'
        )
      )
      expect(quotientSteps.length).assertEqual(2)
      for (let index = 0; index < quotientSteps.length; index++) {
        const lanes: VerticalMathOverlay[] = quotientSteps[index].overlays.filter(
          (overlay: VerticalMathOverlay): boolean => overlay.kind === 'division_lane'
        )
        expect(lanes.length).assertEqual(1)
        expect(lanes[0].targetColumn).assertEqual(index)
        expect(lanes[0].startColumn <= lanes[0].endColumn).assertEqual(true)
      }
    })

    it('does not invent a quotient target when the window is too small', 0, () => {
      const s = solveVerticalDivide(3, 7)
      expect(s.steps[0].overlays.some(
        (overlay: VerticalMathOverlay): boolean => overlay.kind === 'division_lane'
      )).assertEqual(false)
      expect(s.steps[0].highlights.some(
        (highlight: VerticalMathHighlight): boolean => highlight.kind === 'quotient'
      )).assertEqual(false)
    })
  })

  describe('VerticalMathColors', () => {
    it('resolves the approved light palette', 0, () => {
      const palette: VerticalMathPalette = resolveVerticalMathPalette(false)
      expect(palette.shell).assertEqual('#F2EEFB')
      expect(palette.paper).assertEqual('#FFFDF7')
      expect(palette.ink).assertEqual('#352E24')
      expect(palette.focus).assertEqual('#FFE15A')
      expect(palette.success).assertEqual('#56A779')
      expect(palette.carry).assertEqual('#FF6B57')
    })

    it('resolves the approved dark palette', 0, () => {
      const palette: VerticalMathPalette = resolveVerticalMathPalette(true)
      expect(palette.shell).assertEqual('#272238')
      expect(palette.paper).assertEqual('#302C27')
      expect(palette.ink).assertEqual('#F7F1E4')
      expect(palette.focus).assertEqual('#E7C74E')
      expect(palette.success).assertEqual('#6FC294')
      expect(palette.carry).assertEqual('#FF7C6D')
      expect(palette.borrow.length > 0).assertEqual(true)
      expect(palette.divider.length > 0).assertEqual(true)
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
