// components/verticalMath/VerticalMathBoard.ets
import {
  VERTICAL_MATH_BOARD_BG_START,
  VERTICAL_MATH_BOARD_BG_MID,
  VERTICAL_MATH_BOARD_BG_END,
  VERTICAL_MATH_BOARD_TEXT,
  VERTICAL_MATH_BOARD_LINE,
  VERTICAL_MATH_CARRY_TEXT
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

  private getTopMarkOffset(row: VerticalMathBoardRow): number {
    const column: number = row.topMarkColumn === undefined ? 0 : row.topMarkColumn
    return this.getCellSize() + column * this.getCellSize()
  }

  private getTopMarkColor(row: VerticalMathBoardRow): string {
    return row.topMark === '•' ? VERTICAL_MATH_BOARD_TEXT : VERTICAL_MATH_CARRY_TEXT
  }

  private shouldShowLine(rowIndex: number): boolean {
    const rows: VerticalMathBoardRow[] = this.getCurrentRows()
    return rowIndex === 2 || (this.getShowFinalLine() && rowIndex === rows.length - 2)
  }

  @Builder
  private TopMark(row: VerticalMathBoardRow) {
    if (row.topMark !== undefined && row.topMark !== '') {
      Row() {
        Text(row.topMark)
          .fontSize(this.compact ? 15 : 18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTopMarkColor(row))
          .width(this.getCellSize())
          .textAlign(TextAlign.Center)
      }
      .width(this.getCellSize() * (this.solution.columnCount + 1))
      .padding({ left: this.getTopMarkOffset(row) })
      .justifyContent(FlexAlign.Start)
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 145,
          colors: [
            [VERTICAL_MATH_BOARD_BG_START, 0.0],
            [VERTICAL_MATH_BOARD_BG_MID, 0.66],
            [VERTICAL_MATH_BOARD_BG_END, 1.0]
          ]
        })
        .borderRadius(20)

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
        }, (_row: VerticalMathBoardRow, rowIndex: number) => `row_${rowIndex}`)
      }
      .padding(this.compact ? 14 : 20)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
