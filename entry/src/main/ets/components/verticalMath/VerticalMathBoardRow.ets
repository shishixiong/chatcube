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
  @Param reduceMotion: boolean = false
  @Param celebrate: boolean = false        // final step: answer row pops + green glow

  @Local celebrationScale: number = 1.0
  @Local celebrationGlow: number = 0

  aboutToAppear(): void {
    if (this.celebrate && !this.reduceMotion) {
      // Answer-reveal pulse: grow with a success glow, then settle back.
      this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
        {
          duration: 140,
          curve: Curve.EaseOut,
          event: () => {
            this.celebrationScale = 1.12
            this.celebrationGlow = 14
          }
        },
        {
          duration: 280,
          curve: Curve.EaseInOut,
          event: () => {
            this.celebrationScale = 1.0
            this.celebrationGlow = 0
          }
        }
      ])
    }
  }

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

  // Reveal animation: rows ≥ 2 hold freshly-written digits (result / partial
  // product / quotient / product / remainder) — the active-highlighted cell in
  // those rows is exactly the digit written THIS step, so it alone pops in when
  // the board remounts per step. Operand rows (0/1) use 'active' only as a
  // "current column" cursor over old content, so they stay static.
  private resolveRevealTransition(colIndex: number): TransitionEffect {
    if (this.rowIndex < 2 || !this.isActiveCell(colIndex) || this.reduceMotion) {
      return TransitionEffect.IDENTITY
    }
    return TransitionEffect.scale({ x: 0.4, y: 0.4 })
      .combine(TransitionEffect.OPACITY)
      .animation({ duration: 240, curve: Curve.EaseOut })
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
    .transition(this.resolveRevealTransition(colIndex))
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
    .scale({ x: this.celebrationScale, y: this.celebrationScale })
    .shadow({
      radius: this.celebrationGlow,
      color: this.celebrationGlow > 0 ? this.palette.success : Color.Transparent,
      offsetY: 0
    })
  }
}
