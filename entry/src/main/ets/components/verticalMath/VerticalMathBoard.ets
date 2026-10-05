// components/verticalMath/VerticalMathBoard.ets
// 黑板棋盘容器（v2 黑板重设计）：深海军蓝底、行渲染、庆祝行定位。
// 行快照与高亮全部由 VerticalMathSolver 生成；规则线（横线/竖线）由行模型自带。
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../../utils/VerticalMathColors'
import {
  VerticalMathOperation,
  VerticalMathSolution,
  VerticalMathBoardRow,
  VerticalMathHighlight,
  VerticalMathStep
} from '../../utils/VerticalMathSolver'
import { VerticalMathBoardRowView } from './VerticalMathBoardRow'

const DIVIDER_WIDTH: number = 2.5

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

  // The answer row that celebrates on the final step: DIV keeps the quotient on
  // row 0 (above the 厂 top bar); ADD/SUB/MUL keep the result on the last row.
  private getAnswerRowIndex(): number {
    if (this.solution.operation === VerticalMathOperation.DIVIDE) return 0
    return this.getCurrentRows().length - 1
  }

  private isFinalStepVisible(): boolean {
    return this.solution.steps.length > 0 && this.visibleStepCount >= this.solution.steps.length
  }

  private getCellSize(): number {
    // 宽度档位按"等效列数"缩放：主区列数 + 运算符列（或除法左区折算列），
    // 防止万位竖式 / 多位乘数部分积溢出聊天气泡。
    const widthUnits: number = this.getWidthUnits()
    if (this.compact) {
      if (widthUnits >= 7.5) return 26
      if (widthUnits >= 6.5) return 28
      if (widthUnits >= 5.5) return 32
      return 36
    }
    if (widthUnits >= 7.5) return 30
    if (widthUnits >= 6.5) return 32
    if (widthUnits >= 5.5) return 38
    return 44
  }

  private getWidthUnits(): number {
    const columns: number = this.solution.columnCount
    if (this.solution.operation === VerticalMathOperation.DIVIDE) {
      const leftCount: number = String(this.solution.operandB).length
      return columns + leftCount * 0.72 + 0.1
    }
    return columns + 1
  }

  private getBoardWidth(): number {
    const padding: number = this.compact ? 14 : 20
    if (this.solution.operation === VerticalMathOperation.DIVIDE) {
      const leftCount: number = String(this.solution.operandB).length
      const cellSize: number = this.getCellSize()
      return leftCount * cellSize * 0.72 + DIVIDER_WIDTH + cellSize * this.solution.columnCount + 2 * padding
    }
    return this.getCellSize() * (this.solution.columnCount + 1) + 2 * padding
  }

  // 行 key = 行号 + 行内容。内容不变的行（操作数行）保持挂载，@Param 更新驱动高亮/划线流动；
  // 内容变化的行（标记行/结果行/除法逐步行）整行重挂，渲染成为步骤数据的纯函数——
  // 真机验证过 cell 级"key 含内容重挂"在重复步骤后不可靠（新数字/进位标记不显示），
  // 整行重挂是稳定路径。
  private boardRowContentKey(row: VerticalMathBoardRow): string {
    let key: string = row.cells.join('')
    if (row.operator !== undefined) {
      key += `|op:${row.operator}`
    }
    if (row.markRow === true) {
      key += '|m'
    }
    if (row.ruleUnder === true) {
      key += '|u'
    }
    if (row.barRight === true) {
      key += '|b'
    }
    if (row.leftCells !== undefined) {
      key += `|l:${row.leftCells.join('')}`
    }
    if (row.crossedColumns !== undefined) {
      key += `|x:${row.crossedColumns.join(',')}`
    }
    return key
  }

  @Builder
  private BoardRows() {
    Column() {
      ForEach(this.getCurrentRows(), (row: VerticalMathBoardRow, rowIndex: number) => {
        VerticalMathBoardRowView({
          row: row,
          rowIndex: rowIndex,
          highlights: this.getRowHighlights(rowIndex),
          cellSize: this.getCellSize(),
          columnCount: this.solution.columnCount,
          isDarkMode: this.isDarkMode,
          reduceMotion: this.reduceMotion,
          celebrate: this.isFinalStepVisible() && rowIndex === this.getAnswerRowIndex()
        })
      }, (row: VerticalMathBoardRow, rowIndex: number) => `board_row_${rowIndex}_${this.boardRowContentKey(row)}`)
    }
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      this.BoardRows()
    }
    .width(this.getBoardWidth())
    .padding(this.compact ? 14 : 20)
    .backgroundColor(this.palette.boardBg)
    .borderRadius(14)
  }
}
