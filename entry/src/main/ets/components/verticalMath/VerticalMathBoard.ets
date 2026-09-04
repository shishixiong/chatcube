// components/verticalMath/VerticalMathBoard.ets
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../../utils/VerticalMathColors'
import {
  VerticalMathOperation,
  VerticalMathSolution,
  VerticalMathBoardRow,
  VerticalMathHighlight,
  VerticalMathOverlay,
  VerticalMathStep
} from '../../utils/VerticalMathSolver'
import { VerticalMathBoardRowView } from './VerticalMathBoardRow'

@ComponentV2
export struct VerticalMathBoard {
  @Param solution: VerticalMathSolution = new VerticalMathSolution()
  @Param visibleStepCount: number = 0
  @Param compact: boolean = false
  @Param isDarkMode: boolean = false
  @Param reduceMotion: boolean = false

  private get palette(): VerticalMathPalette {
    return resolveVerticalMathPalette(this.isDarkMode)
  }

  private getCurrentStep(): VerticalMathStep | null {
    if (this.visibleStepCount <= 0 || this.solution.steps.length === 0) return null
    const index: number = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    return this.solution.steps[index]
  }

  private getCurrentOverlays(): VerticalMathOverlay[] {
    return this.getCurrentStep()?.overlays ?? []
  }

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

  private getActiveColumn(): number {
    const highlights: VerticalMathHighlight[] = this.getCurrentHighlights()
    for (let index = 0; index < highlights.length; index++) {
      if (highlights[index].rowIndex === 0 && highlights[index].kind === 'active') {
        return highlights[index].columnIndex
      }
    }
    return -1
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

  // The answer row that celebrates on the final step: ADD/SUB/MUL keep the
  // result/total on the last row; DIV puts the quotient on row 3 (product and
  // remainder rows follow below it).
  private getAnswerRowIndex(): number {
    if (this.solution.operation === VerticalMathOperation.DIVIDE) return 3
    return this.getCurrentRows().length - 1
  }

  private getCellSize(): number {
    return this.compact ? 36 : 44
  }

  private getBoardWidth(): number {
    const padding: number = this.compact ? 14 : 20
    return this.getCellSize() * (this.solution.columnCount + 1) + 2 * padding
  }

  private getCellX(column: number): number {
    return this.getCellSize() * (column + 1)
  }

  private getTopMarkOffset(column: number): number {
    return this.getCellSize() + column * this.getCellSize()
  }

  private getTopMarkColor(mark: string): string {
    return mark === '-1' ? this.palette.borrow : this.palette.carry
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

  // The previous step's rowA — used to tell freshly-added carry/borrow marks from
  // historical ones so only new chips pop in (历史标记保持静止).
  private getPreviousRowA(): VerticalMathBoardRow | null {
    if (this.visibleStepCount <= 1 || this.solution.steps.length === 0) return null
    const index: number = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    if (index <= 0) return null
    return this.solution.steps[index - 1].rows[0] ?? null
  }

  private isFreshMark(column: number, isCarry: boolean): boolean {
    const previous: VerticalMathBoardRow | null = this.getPreviousRowA()
    if (previous === null) return true
    const previousColumns: number[] = isCarry
      ? this.getCarryColumns(previous)
      : this.getBorrowColumns(previous)
    return !previousColumns.includes(column)
  }

  private resolveMarkTransition(isFresh: boolean): TransitionEffect {
    if (!isFresh || this.reduceMotion) return TransitionEffect.IDENTITY
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
      .animation({ duration: 260, curve: Curve.EaseOut })
  }

  private shouldShowLine(rowIndex: number): boolean {
    const rows: VerticalMathBoardRow[] = this.getCurrentRows()
    return rowIndex === 2 || (this.getShowFinalLine() && rowIndex === rows.length - 2)
  }

  @Builder
  private TopMarkAt(mark: string, column: number, isActive: boolean = false, isFresh: boolean = false) {
    Row() {
      Text(mark)
        .fontSize(this.compact ? 15 : 18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getTopMarkColor(mark))
        .width(this.getCellSize())
        .height(this.getCellSize())
        .borderRadius(this.getCellSize() / 2)
        .backgroundColor(isActive ? this.palette.focus : Color.Transparent)
        .textAlign(TextAlign.Center)
    }
    .width(this.getCellSize() * (this.solution.columnCount + 1))
    .padding({ left: this.getTopMarkOffset(column) })
    .justifyContent(FlexAlign.Start)
    .transition(this.resolveMarkTransition(isFresh))
  }

  @Builder
  private PersistentMarkerRow(sourceRow: VerticalMathBoardRow) {
    if (this.hasPersistentTopMarks(sourceRow)) {
      Stack() {
        ForEach(this.getCarryColumns(sourceRow), (column: number) => {
          this.TopMarkAt('+1', column, column === this.getActiveColumn(), this.isFreshMark(column, true))
        }, (column: number) => `carry_${column}`)
        ForEach(this.getBorrowColumns(sourceRow), (column: number) => {
          this.TopMarkAt('-1', column, column === this.getActiveColumn(), this.isFreshMark(column, false))
        }, (column: number) => `borrow_${column}`)
      }
    }
  }

  @Builder
  private BoardRows() {
    Column() {
      ForEach(this.getCurrentRows(), (row: VerticalMathBoardRow, rowIndex: number) => {
        Column() {
          VerticalMathBoardRowView({
            row: row,
            rowIndex: rowIndex,
            highlights: this.getRowHighlights(rowIndex),
            overlays: this.getCurrentOverlays(),
            cellSize: this.getCellSize(),
            columnCount: this.solution.columnCount,
            isDarkMode: this.isDarkMode,
            reduceMotion: this.reduceMotion,
            celebrate: this.getShowFinalLine() && rowIndex === this.getAnswerRowIndex()
          })
          if (rowIndex === 1) {
            this.PersistentMarkerRow(this.getCurrentRows()[0])
          }
          if (this.shouldShowLine(rowIndex)) {
            Row()
              .width(this.getCellSize() * this.solution.columnCount)
              .height(3)
              .margin({ left: this.getCellSize(), top: 4, bottom: 4 })
              .backgroundColor(this.palette.ink)
              .opacity(0.55)
              .borderRadius(2)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }, (_row: VerticalMathBoardRow, rowIndex: number) => `${this.visibleStepCount}_${rowIndex}`)
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RelationOverlay(overlay: VerticalMathOverlay) {
    if (overlay.kind === 'division_lane') {
      Row()
        .width((overlay.endColumn - overlay.startColumn + 1) * this.getCellSize())
        .height(4)
        .position({ x: this.getCellX(overlay.startColumn), y: 12 })
        .backgroundColor(this.palette.focus)
        .borderRadius(2)
        .animation({ duration: this.reduceMotion ? 0 : 220, curve: Curve.EaseOut })
    }
  }

  @Builder
  private StepRelationOverlays() {
    ForEach(this.getCurrentOverlays(), (overlay: VerticalMathOverlay, index: number) => {
      this.RelationOverlay(overlay)
    }, (overlay: VerticalMathOverlay, index: number) =>
      `${overlay.kind}_${overlay.startColumn}_${overlay.endColumn}_${index}`)
  }

  build() {
    Stack() {
      this.BoardRows()
      this.StepRelationOverlays()
    }
    .width(this.getBoardWidth())
    .padding(this.compact ? 14 : 20)
    .backgroundColor(this.palette.paper)
    .border({ width: 1, color: this.palette.divider })
    .borderRadius(14)
  }
}
