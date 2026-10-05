// components/verticalMath/VerticalMathBoardRow.ets
// 单行黑板渲染器（v2 黑板重设计，docs/vertical_math_refine.html）：
// - 普通行：前置运算符列 + 主区格子（加/减/乘）
// - 厂字形除法行：左区窄列（除数）+ 竖线 + 主区格子，可选行下横线
// - 标记行（markRow）：小号黄字（进位 1 / 借位 -1），参与计算时带高亮底色
// - crossedColumns：原数字划线（历史会话兼容；现行减法不再划线）
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../../utils/VerticalMathColors'
import {
  VerticalMathBoardRow as RowModel,
  VerticalMathHighlight
} from '../../utils/VerticalMathSolver'

const DIVIDER_WIDTH: number = 2.5

@ComponentV2
export struct VerticalMathBoardRowView {
  @Param row: RowModel = new RowModel()
  @Param rowIndex: number = 0
  @Param highlights: VerticalMathHighlight[] = []
  @Param cellSize: number = 36
  @Param columnCount: number = 1
  @Param isDarkMode: boolean = false
  @Param reduceMotion: boolean = false
  @Param celebrate: boolean = false        // final step: answer row pops + green glow

  @Local celebrationScale: number = 1.0
  @Local celebrationGlow: number = 0

  aboutToAppear(): void {
    if (this.celebrate && !this.reduceMotion) {
      this.pulse()
    }
  }

  // 行组件按 rowIndex 复用（不随步骤重挂），celebrate 翻转时需监听补一次脉冲
  @Monitor('celebrate')
  onCelebrateChange(): void {
    if (this.celebrate && !this.reduceMotion) {
      this.pulse()
    }
  }

  private pulse(): void {
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

  private get palette(): VerticalMathPalette {
    return resolveVerticalMathPalette(this.isDarkMode)
  }

  private get hasDivisionLayout(): boolean {
    return this.row.leftCells !== undefined
  }

  private get leftCellWidth(): number {
    return this.cellSize * 0.72
  }

  private get ruleLeftInset(): number {
    if (this.hasDivisionLayout) {
      const leftCount: number = this.row.leftCells?.length ?? 0
      return leftCount * this.leftCellWidth + DIVIDER_WIDTH
    }
    return this.cellSize
  }

  private getHighlightKind(columnIndex: number): string {
    for (let index: number = 0; index < this.highlights.length; index++) {
      if (this.highlights[index].columnIndex === columnIndex) {
        return this.highlights[index].kind
      }
    }
    return ''
  }

  private isActiveCell(columnIndex: number): boolean {
    const kind: string = this.getHighlightKind(columnIndex)
    return kind === 'active' || kind === 'quotient'
  }

  private isCrossed(columnIndex: number): boolean {
    const crossed: number[] | undefined = this.row.crossedColumns
    if (crossed === undefined) {
      return false
    }
    return crossed.includes(columnIndex)
  }

  private getCellBackgroundColor(columnIndex: number): string {
    if (this.isActiveCell(columnIndex)) {
      return this.palette.boardActiveBg
    }
    if (this.getHighlightKind(columnIndex) === 'done') {
      return this.palette.boardDoneBg
    }
    return 'transparent'
  }

  private getCellTextColor(columnIndex: number): string {
    const kind: string = this.getHighlightKind(columnIndex)
    if (kind === 'done' || kind === 'final') {
      return this.palette.boardFinal
    }
    if (kind === 'product') {
      return this.palette.boardProduct
    }
    return this.palette.boardInk
  }

  // 新数字的"写入感"由整行重挂 + celebrate 脉冲承担；cell 级 TransitionEffect
  // 在 ForEach 重复重挂场景会卡在 opacity 0（真机验证），故不再使用。

  @Builder
  private MarkCell(text: string, colIndex: number) {
    Text(text)
      .fontSize(this.cellSize * 0.42)
      .fontWeight(FontWeight.Bold)
      .fontFamily('ui-monospace, SFMono-Regular, Menlo, monospace')
      .fontColor(this.palette.boardCarry)
      .width(this.cellSize)
      .height(this.cellSize * 0.62)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.isActiveCell(colIndex) ? this.palette.boardActiveBg : 'transparent')
      .borderRadius(8)
  }

  @Builder
  private CellGlyph(text: string, colIndex: number) {
    Stack() {
      if (text === ' ' || text === '') {
        Text('').width(this.cellSize)
      } else {
        Text(text)
          .fontSize(this.cellSize * 0.62)
          .fontWeight(FontWeight.Bold)
          .fontFamily('ui-monospace, SFMono-Regular, Menlo, monospace')
          .fontColor(this.getCellTextColor(colIndex))
          .width(this.cellSize)
          .textAlign(TextAlign.Center)
          .decoration({
            type: this.isCrossed(colIndex) ? TextDecorationType.LineThrough : TextDecorationType.None,
            color: this.palette.boardLine
          })
          .opacity(this.isCrossed(colIndex) ? 0.6 : 1)
      }
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .backgroundColor(this.getCellBackgroundColor(colIndex))
    .borderRadius(8)
  }

  @Builder
  private LeftZoneCell(text: string) {
    Text(text)
      .fontSize(this.cellSize * 0.62)
      .fontWeight(FontWeight.Bold)
      .fontFamily('ui-monospace, SFMono-Regular, Menlo, monospace')
      .fontColor(this.palette.boardInk)
      .width(this.leftCellWidth)
      .height(this.cellSize)
      .textAlign(TextAlign.Center)
  }

  @Builder
  private DivisionBar() {
    Row()
      .width(DIVIDER_WIDTH)
      .height(this.cellSize)
      .backgroundColor(this.palette.boardLine)
      .borderRadius(1)
  }

  build() {
    Column() {
      Row() {
        if (this.hasDivisionLayout) {
          ForEach(this.row.leftCells, (cell: string, idx: number) => {
            this.LeftZoneCell(cell)
          }, (cell: string, idx: number) => `left_${this.rowIndex}_${idx}_${cell}`)
          if (this.row.barRight === true) {
            this.DivisionBar()
          }
        } else if (this.row.operator !== undefined && this.row.operator !== '') {
          Text(this.row.operator)
            .fontSize(this.cellSize * 0.62)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.boardInk)
            .width(this.cellSize)
            .height(this.cellSize)
            .textAlign(TextAlign.Center)
        } else {
          Text('').width(this.cellSize).height(this.cellSize)
        }
        ForEach(this.row.cells, (cell: string, idx: number) => {
          if (this.row.markRow === true) {
            if (cell !== '' && cell !== ' ') {
              this.MarkCell(cell, idx)
            } else {
              Text('').width(this.cellSize).height(this.cellSize * 0.62)
            }
          } else {
            this.CellGlyph(cell, idx)
          }
        }, (cell: string, idx: number) => `${this.rowIndex}_${idx}_${cell}`)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .scale({ x: this.celebrationScale, y: this.celebrationScale })
      .shadow({
        radius: this.celebrationGlow,
        color: this.celebrationGlow > 0 ? this.palette.boardFinal : Color.Transparent,
        offsetY: 0
      })

      if (this.row.ruleUnder === true) {
        Row()
          .width(this.cellSize * this.columnCount)
          .height(DIVIDER_WIDTH)
          .margin({ left: this.ruleLeftInset, top: 3, bottom: 3 })
          .backgroundColor(this.palette.boardLine)
          .borderRadius(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
  }
}
