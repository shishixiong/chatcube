// components/verticalMath/VerticalMathBoardRow.ets
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../../utils/VerticalMathColors'
import {
  VerticalMathBoardRow as RowModel,
  VerticalMathHighlight,
  VerticalMathOverlay
} from '../../utils/VerticalMathSolver'

@ComponentV2
export struct VerticalMathBoardRowView {
  @Param row: RowModel = new RowModel()
  @Param rowIndex: number = 0
  @Param highlights: VerticalMathHighlight[] = []
  @Param overlays: VerticalMathOverlay[] = []
  @Param cellSize: number = 36
  @Param columnCount: number = 1
  @Param isDarkMode: boolean = false

  private get palette(): VerticalMathPalette {
    return resolveVerticalMathPalette(this.isDarkMode)
  }

  private getHighlightKind(columnIndex: number): string {
    for (let index: number = 0; index < this.highlights.length; index++) {
      if (this.highlights[index].columnIndex === columnIndex) {
        return this.highlights[index].kind
      }
    }
    return ''
  }

  private isInPartialBand(columnIndex: number): boolean {
    for (let index = 0; index < this.overlays.length; index++) {
      const overlay: VerticalMathOverlay = this.overlays[index]
      if (overlay.kind === 'partial_band' && overlay.rowIndex === this.rowIndex &&
        columnIndex >= overlay.startColumn && columnIndex <= overlay.endColumn) {
        return true
      }
    }
    return false
  }

  private isActiveCell(columnIndex: number): boolean {
    const kind: string = this.getHighlightKind(columnIndex)
    return kind === 'active' || kind === 'quotient'
  }

  private getCellBackgroundColor(columnIndex: number): string {
    if (this.isInPartialBand(columnIndex)) return this.palette.focus
    const kind: string = this.getHighlightKind(columnIndex)
    if (kind === 'active' || kind === 'quotient') return this.palette.focus
    if (kind === 'done') return this.palette.successBackground
    return 'transparent'
  }

  private getCellTextColor(columnIndex: number): string {
    const kind: string = this.getHighlightKind(columnIndex)
    if (kind === 'active' || kind === 'quotient' || this.isInPartialBand(columnIndex)) {
      return this.palette.focusText
    }
    if (kind === 'done') return this.palette.success
    if (kind === 'carry') return this.palette.carry
    if (kind === 'borrow') return this.palette.borrow
    return this.palette.ink
  }

  @Builder
  private CellGlyph(text: string, colIndex: number) {
    Stack() {
      if (text === ' ') {
        Text('').width(this.cellSize)
      } else {
        Text(text)
          .fontSize(this.cellSize * 0.62)
          .fontWeight(FontWeight.Bold)
          .fontFamily('ui-monospace, SFMono-Regular, Menlo, monospace')
          .fontColor(this.getCellTextColor(colIndex))
          .width(this.cellSize)
          .textAlign(TextAlign.Center)
      }
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .backgroundColor(this.getCellBackgroundColor(colIndex))
    .borderRadius(8)
    .shadow({
      radius: this.isActiveCell(colIndex) ? 3 : 0,
      color: this.isActiveCell(colIndex) ? '#22000000' : Color.Transparent,
      offsetY: this.isActiveCell(colIndex) ? 2 : 0
    })
  }

  build() {
    Row() {
      if (this.row.operator !== undefined && this.row.operator !== '') {
        Text(this.row.operator)
          .fontSize(this.cellSize * 0.62)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.ink)
          .width(this.cellSize)
          .height(this.cellSize)
          .textAlign(TextAlign.Center)
      } else {
        Text('').width(this.cellSize).height(this.cellSize)
      }
      ForEach(this.row.cells, (cell: string, idx: number) => {
        this.CellGlyph(cell, idx)
      }, (cell: string, idx: number) => `${this.rowIndex}_${idx}_${cell}`)
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }
}
