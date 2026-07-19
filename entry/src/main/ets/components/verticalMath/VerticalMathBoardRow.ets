// components/verticalMath/VerticalMathBoardRow.ets
import {
  VERTICAL_MATH_BOARD_TEXT,
  VERTICAL_MATH_ACTIVE_BG,
  VERTICAL_MATH_ACTIVE_TEXT,
  VERTICAL_MATH_DONE_TEXT,
  VERTICAL_MATH_DONE_BG,
  VERTICAL_MATH_CARRY_TEXT
} from '../../utils/VerticalMathColors'
import {
  VerticalMathBoardRow as RowModel,
  VerticalMathHighlight
} from '../../utils/VerticalMathSolver'

@ComponentV2
export struct VerticalMathBoardRowView {
  @Param row: RowModel = new RowModel()
  @Param rowIndex: number = 0
  @Param highlights: VerticalMathHighlight[] = []
  @Param cellSize: number = 36
  @Param columnCount: number = 1

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
          .fontColor(VERTICAL_MATH_BOARD_TEXT)
          .width(this.cellSize)
          .textAlign(TextAlign.Center)
      }
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .borderRadius(8)
  }

  build() {
    Row() {
      if (this.row.operator !== undefined && this.row.operator !== '') {
        Text(this.row.operator)
          .fontSize(this.cellSize * 0.62)
          .fontWeight(FontWeight.Bold)
          .fontColor(VERTICAL_MATH_BOARD_TEXT)
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