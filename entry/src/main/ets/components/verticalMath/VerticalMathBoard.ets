// components/verticalMath/VerticalMathBoard.ets
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../../utils/VerticalMathColors'
import {
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

  private getLaneHeight(): number {
    const rows: VerticalMathBoardRow[] = this.getCurrentRows()
    if (rows.length === 0) return 0
    let height: number = 0
    for (let index = 0; index < rows.length; index++) {
      const row: VerticalMathBoardRow = rows[index]
      const hasTopMark: boolean = this.hasPersistentTopMarks(row) ||
        (row.topMark !== undefined && row.topMark !== '')
      height += this.getCellSize() * (hasTopMark ? 2 : 1)
      if (this.shouldShowLine(index)) {
        height += 11
      }
    }
    return height
  }

  private getBridgeStartX(overlay: VerticalMathOverlay): number {
    return Math.min(this.getCellX(overlay.sourceColumn), this.getCellX(overlay.targetColumn)) +
      this.getCellSize() / 2
  }

  private getBridgeWidth(overlay: VerticalMathOverlay): number {
    return Math.abs(overlay.sourceColumn - overlay.targetColumn) * this.getCellSize()
  }

  private getTopMarkOffset(column: number): number {
    return this.getCellSize() + column * this.getCellSize()
  }

  private getTopMarkColor(mark: string): string {
    return mark === '•' ? this.palette.borrow : this.palette.carry
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
        .backgroundColor(isActive ? this.palette.focus : Color.Transparent)
        .textAlign(TextAlign.Center)
    }
    .width(this.getCellSize() * (this.solution.columnCount + 1))
    .padding({ left: this.getTopMarkOffset(column) })
    .justifyContent(FlexAlign.Start)
  }

  private resolveTopMarkColumn(row: VerticalMathBoardRow): number {
    return row.topMarkColumn === undefined ? 0 : row.topMarkColumn
  }

  @Builder
  private TopMark(row: VerticalMathBoardRow) {
    if (this.hasPersistentTopMarks(row)) {
      Stack() {
        ForEach(this.getCarryColumns(row), (column: number) => {
          this.TopMarkAt('1', column, column === this.getActiveColumn())
        }, (column: number) => `carry_${column}`)
        ForEach(this.getBorrowColumns(row), (column: number) => {
          this.TopMarkAt('•', column, column === this.getActiveColumn())
        }, (column: number) => `borrow_${column}`)
      }
    } else if (row.topMark !== undefined && row.topMark !== '') {
      this.TopMarkAt(row.topMark, this.resolveTopMarkColumn(row),
        this.resolveTopMarkColumn(row) === this.getActiveColumn())
    }
  }

  @Builder
  private BoardRows() {
    Column() {
      ForEach(this.getCurrentRows(), (row: VerticalMathBoardRow, rowIndex: number) => {
        Column() {
          this.TopMark(row)
          VerticalMathBoardRowView({
            row: row,
            rowIndex: rowIndex,
            highlights: this.getRowHighlights(rowIndex),
            overlays: this.getCurrentOverlays(),
            cellSize: this.getCellSize(),
            columnCount: this.solution.columnCount,
            isDarkMode: this.isDarkMode
          })
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
  private PlaceValueLaneOverlay() {
    if (this.getActiveColumn() >= 0) {
      Row()
        .width(this.getCellSize() - 6)
        .height(this.getLaneHeight())
        .position({
          x: this.getCellX(this.getActiveColumn()) + 3 + (this.compact ? 14 : 20),
          y: 0
        })
        .backgroundColor(this.palette.focus)
        .opacity(0.28)
        .border({ width: 2, color: this.palette.focus })
        .borderRadius(14)
        .animation({
          duration: this.reduceMotion ? 0 : 180,
          curve: Curve.EaseInOut
        })
    }
  }

  @Builder
  private RelationOverlay(overlay: VerticalMathOverlay) {
    if (overlay.kind === 'carry_path') {
      Row()
        .width(this.getBridgeWidth(overlay))
        .height(2)
        .position({ x: this.getBridgeStartX(overlay), y: 8 })
        .border({ width: { top: 2 }, color: this.palette.carry, style: BorderStyle.Dashed })
        .animation({ duration: this.reduceMotion ? 0 : 220, curve: Curve.EaseOut })
    } else if (overlay.kind === 'borrow_bridge') {
      Row()
        .width(this.getBridgeWidth(overlay))
        .height(2)
        .position({ x: this.getBridgeStartX(overlay), y: 8 })
        .border({ width: { top: 2 }, color: this.palette.borrow, style: BorderStyle.Dashed })
        .animation({ duration: this.reduceMotion ? 0 : 220, curve: Curve.EaseOut })
    } else if (overlay.kind === 'division_lane') {
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
      `${overlay.kind}_${overlay.sourceColumn}_${overlay.targetColumn}_${index}`)
  }

  build() {
    Stack() {
      this.PlaceValueLaneOverlay()
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
