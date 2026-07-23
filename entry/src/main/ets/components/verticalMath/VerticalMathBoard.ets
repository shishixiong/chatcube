// components/verticalMath/VerticalMathBoard.ets
import {
  VERTICAL_MATH_ACTIVE_BG,
  VERTICAL_MATH_BOARD_LINE,
  VERTICAL_MATH_CARRY_TEXT,
  VERTICAL_MATH_BORROW_TEXT,
  VERTICAL_MATH_NARRATOR_BG
} from '../../utils/VerticalMathColors'
import {
  VerticalMathSolution,
  VerticalMathBoardRow,
  VerticalMathHighlight
} from '../../utils/VerticalMathSolver'
import { VerticalMathBoardRowView } from './VerticalMathBoardRow'

@ComponentV2
export struct VerticalMathBoard {
  @Param solution: VerticalMathSolution = new VerticalMathSolution()
  @Param visibleStepCount: number = 0
  @Param compact: boolean = false

  private getCurrentRows(): VerticalMathBoardRow[] {
    if (this.solution.steps.length === 0 || this.visibleStepCount === 0) {
      return this.solution.initialRows
    }
    const index: number = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    return this.solution.steps[index].rows
  }

  private getCurrentHighlights(): VerticalMathHighlight[] {
    if (this.solution.steps.length === 0 || this.visibleStepCount === 0) {
      return []
    }
    const index: number = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    return this.solution.steps[index].highlights
  }

  private getActiveOperandColumn(): number {
    const active: VerticalMathHighlight | undefined = this.getCurrentHighlights().find(
      (highlight: VerticalMathHighlight): boolean =>
        highlight.rowIndex === 0 && highlight.kind === 'active'
    )
    return active === undefined ? -1 : active.columnIndex
  }

  private isActiveTopMark(column: number): boolean {
    return column === this.getActiveOperandColumn()
  }

  private getRowHighlights(rowIndex: number): VerticalMathHighlight[] {
    return this.getCurrentHighlights().filter((highlight: VerticalMathHighlight): boolean =>
      highlight.rowIndex === rowIndex)
  }

  private getShowFinalLine(): boolean {
    if (this.solution.steps.length === 0 || this.visibleStepCount === 0) {
      return false
    }
    const index: number = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    return this.solution.steps[index].showFinalLine === true
  }

  private getCellSize(): number {
    return this.compact ? 32 : 40
  }

  private getTopMarkOffset(column: number): number {
    return this.getCellSize() + column * this.getCellSize()
  }

  private getTopMarkColor(mark: string): string {
    return mark === '•' ? VERTICAL_MATH_BORROW_TEXT : VERTICAL_MATH_CARRY_TEXT
  }

  private getCarryColumns(row: VerticalMathBoardRow): number[] {
    return row.carryColumns ?? []
  }

  private getBorrowColumns(row: VerticalMathBoardRow): number[] {
    return row.borrowColumns ?? []
  }

  private hasPersistentTopMarks(row: VerticalMathBoardRow): boolean {
    return this.getCarryColumns(row).length > 0 || this.getBorrowColumns(row).length > 0
  }

  private shouldShowLine(rowIndex: number): boolean {
    const rows: VerticalMathBoardRow[] = this.getCurrentRows()
    return rowIndex === 2 || (this.getShowFinalLine() && rowIndex === rows.length - 2)
  }

  @Builder
  private TopMarkAt(mark: string, column: number, isActive: boolean = false) {
    Row() {
      Text(mark)
        .fontSize(this.compact ? 15 : 18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getTopMarkColor(mark))
        .width(this.getCellSize())
        .height(this.getCellSize())
        .borderRadius(this.getCellSize() / 2)
        .backgroundColor(isActive ? VERTICAL_MATH_ACTIVE_BG : Color.Transparent)
        .textAlign(TextAlign.Center)
    }
    .width(this.getCellSize() * (this.solution.columnCount + 1))
    .padding({ left: this.getTopMarkOffset(column) })
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private TopMark(row: VerticalMathBoardRow) {
    if (this.hasPersistentTopMarks(row)) {
      Stack() {
        ForEach(this.getCarryColumns(row), (column: number) => {
          this.TopMarkAt('1', column, this.isActiveTopMark(column))
        }, (column: number) => `carry_${column}`)
        ForEach(this.getBorrowColumns(row), (column: number) => {
          this.TopMarkAt('•', column, this.isActiveTopMark(column))
        }, (column: number) => `borrow_${column}`)
      }
    } else if (row.topMark !== undefined && row.topMark !== '') {
      this.TopMarkAt(row.topMark, row.topMarkColumn === undefined ? 0 : row.topMarkColumn,
        this.isActiveTopMark(row.topMarkColumn === undefined ? 0 : row.topMarkColumn))
    }
  }

  build() {
    Column() {
      ForEach(this.getCurrentRows(), (row: VerticalMathBoardRow, rowIndex: number) => {
        Column() {
          this.TopMark(row)
          VerticalMathBoardRowView({
            row: row,
            rowIndex: rowIndex,
            highlights: this.getRowHighlights(rowIndex),
            cellSize: this.getCellSize(),
            columnCount: this.solution.columnCount
          })
          if (this.shouldShowLine(rowIndex)) {
            Row()
              .width(this.getCellSize() * this.solution.columnCount)
              .height(4)
              .margin({ left: this.getCellSize(), top: 4, bottom: 4 })
              .backgroundColor(VERTICAL_MATH_BOARD_LINE)
              .borderRadius(2)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }, (_row: VerticalMathBoardRow, rowIndex: number) => `${this.visibleStepCount}_${rowIndex}`)
    }
    .padding(this.compact ? 14 : 20)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .backgroundColor(VERTICAL_MATH_NARRATOR_BG)
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(14)
  }
}
