/**
 * MathColumnPaperBoard - 草稿纸「竖式计算」面板 (v2 分步块 + 自检)
 *
 * 参考 docs/math_draft_refine.html 原型:
 * - 纯加法链 → 单块多操作数竖式; 含减法链 → 顺序两数块, 前块填完前其后块顶数留空, 填完自动接力
 * - 每列数字下方、横线上方都挂虚线标记格, 不预设哪列有进/借位 (2026-10-19 用户定的:
 *   位置对齐教学板标记行 + 全列挂格防泄题), 点一下标 1/-1, 再点取消 (tap-toggle)
 * - 「检查」本地自检: 结果逐位 + 标记逐格 ✓/×, 状态条反馈 (不回传、不判星、不持久化)
 * - 借位提示语义 = 「划掉变小才算借位」(布局层 markExpected)
 *
 * 布局数据来自 utils/MathColumnPaperLayout.computeColumnPaperLayout (纯函数 + hypium)。
 * 输入数组采用「重建再赋值」触发响应式; 状态读取放在 @Builder 作用域内保持依赖注册。
 * 结果格自动推进为「从个位向左」——匹配竖式从低位算起的书写习惯。
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ColumnBlock, ColumnBlockOperand, ColumnPaperLayout } from '../../utils/MathColumnPaperLayout'
import { getOpDisplay } from '../../utils/MathQuizGame'
import { resolveVerticalMathPalette, VerticalMathPalette } from '../../utils/VerticalMathColors'

const CELL_SIZE: number = 46
const CELL_GAP: number = 2
const OP_SLOT_WIDTH: number = 30
const SLOT_HEIGHT: number = 26
const DIGIT_ROW_HEIGHT: number = 40
const RESULT_CELL_HEIGHT: number = 48
const KEY_ROWS: string[][] = [
  ['1', '2', '3', '4'],
  ['5', '6', '7', '8'],
  ['9', '0', '⌫']
]
const KEY_WIDTH: number = 56
const KEY_HEIGHT: number = 44
const KEY_GAP: number = 8
const KEY_PAD_WIDTH: number = KEY_WIDTH * 4 + KEY_GAP * 3

const STATUS_OK: string = '#22C55E'
const STATUS_BAD: string = '#DC5044'

@ComponentV2
export struct MathColumnPaperBoard {
  @Param layout: ColumnPaperLayout = { blocks: [], expressionText: '' }
  @Param clearTick: number = 0

  @Local resultInputs: string[][] = []
  @Local markInputs: string[][] = []
  @Local checked: boolean = false
  @Local badCount: number = 0
  @Local selectedBlock: number = 0
  @Local selectedPlace: number = -1
  @Local statusTone: string = ''

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get palette(): VerticalMathPalette {
    return resolveVerticalMathPalette(this.isDarkMode)
  }

  @Monitor('clearTick')
  onClearTickChange(): void {
    this.resetInputs()
  }

  aboutToAppear(): void {
    this.resetInputs()
  }

  // ---- 输入状态初始化 / 重建赋值 ----

  private resetInputs(): void {
    const results: string[][] = []
    const marks: string[][] = []
    for (let bi = 0; bi < this.layout.blocks.length; bi++) {
      const r: string[] = []
      const m: string[] = []
      for (let p = 0; p < this.layout.blocks[bi].cols; p++) {
        r.push('')
        m.push('')
      }
      results.push(r)
      marks.push(m)
    }
    this.resultInputs = results
    this.markInputs = marks
    this.checked = false
    this.badCount = 0
    this.statusTone = ''
    this.selectedBlock = 0
    // 默认选中块 0 的个位格: 数字键盘开箱即用, 清空后同样回到个位
    this.selectedPlace = this.layout.blocks.length > 0 && this.layout.blocks[0].answerPlaces > 0
      ? this.layout.blocks[0].answerPlaces - 1 : -1
  }

  private cellValue(arr: string[][], bi: number, p: number): string {
    if (bi < 0 || bi >= arr.length) {
      return ''
    }
    const row = arr[bi]
    if (p < 0 || p >= row.length) {
      return ''
    }
    const v = row[p]
    return v === undefined ? '' : v
  }

  private charAt1d(cells: string[], p: number): string {
    const v = cells[p]
    return v === undefined ? '' : v
  }

  private setResultCell(bi: number, p: number, d: string): void {
    const next = this.resultInputs.map((row: string[], i: number): string[] => {
      if (i !== bi) {
        return row
      }
      const r = row.slice()
      r[p] = d
      return r
    })
    this.resultInputs = next
  }

  private toggleMark(bi: number, p: number, kind: string): void {
    const cur = this.cellValue(this.markInputs, bi, p)
    const nextVal = cur === kind ? '' : kind
    const next = this.markInputs.map((row: string[], i: number): string[] => {
      if (i !== bi) {
        return row
      }
      const r = row.slice()
      r[p] = nextVal
      return r
    })
    this.markInputs = next
    if (this.checked) {
      this.checked = false
      this.statusTone = ''
    }
  }

  // ---- 键盘写入 ----

  private handleDigit(digit: string): void {
    if (this.selectedPlace < 0 || this.selectedBlock < 0 || this.selectedBlock >= this.layout.blocks.length) {
      return
    }
    this.setResultCell(this.selectedBlock, this.selectedPlace, digit)
    // 从个位向左推进
    if (this.selectedPlace > 0) {
      this.selectedPlace -= 1
    }
  }

  private handleBackspace(): void {
    if (this.selectedPlace < 0 || this.selectedBlock >= this.resultInputs.length) {
      return
    }
    this.setResultCell(this.selectedBlock, this.selectedPlace, '')
  }

  private selectResult(bi: number, p: number): void {
    this.selectedBlock = bi
    this.selectedPlace = p
  }

  // ---- 链式块顶数 (上一块结果接力) ----

  private isBlockComplete(bi: number): boolean {
    if (bi < 0 || bi >= this.layout.blocks.length) {
      return false
    }
    const b = this.layout.blocks[bi]
    for (let p = 0; p < b.answerPlaces; p++) {
      if (this.cellValue(this.resultInputs, bi, p) === '') {
        return false
      }
    }
    return true
  }

  private isTopPending(bi: number): boolean {
    return bi > 0 && !this.isBlockComplete(bi - 1)
  }

  /** 链式顶行显示: 未接力时留空 (不显示 ?), 接力后取孩子自己填的上一块结果 */
  private chainDisplayDigit(bi: number, p: number): string {
    if (this.isTopPending(bi)) {
      return ''
    }
    const prev = this.layout.blocks[bi - 1]
    return p < prev.answerPlaces ? this.cellValue(this.resultInputs, bi - 1, p) : ''
  }

  // ---- 检查自检 ----

  private isResultOk(bi: number, p: number): boolean {
    return this.cellValue(this.resultInputs, bi, p) === this.layout.blocks[bi].resultCorrect[p]
  }

  private isMarkOk(bi: number, p: number): boolean {
    return this.cellValue(this.markInputs, bi, p) === this.layout.blocks[bi].markExpected[p]
  }

  private handleCheck(): void {
    let bad = 0
    for (let bi = 0; bi < this.layout.blocks.length; bi++) {
      const b = this.layout.blocks[bi]
      for (let p = 0; p < b.answerPlaces; p++) {
        if (!this.isResultOk(bi, p)) {
          bad += 1
        }
      }
      for (let p = 0; p < b.cols; p++) {
        // 全列核对: 该标没标、不该标乱标都算错 (markExpected 为 '' 的列必须留空)
        if (!this.isMarkOk(bi, p)) {
          bad += 1
        }
      }
    }
    this.badCount = bad
    this.statusTone = bad === 0 ? 'ok' : 'bad'
    this.checked = true
  }

  private get statusText(): string {
    if (this.checked) {
      return this.badCount === 0 ? '全部正确, 太棒了!' : `有 ${this.badCount} 处要再看看`
    }
    let anyCarry = false
    let anyBorrow = false
    for (let bi = 0; bi < this.layout.blocks.length; bi++) {
      const m = this.layout.blocks[bi].markExpected
      for (let p = 0; p < m.length; p++) {
        if (m[p] === 'carry') {
          anyCarry = true
        }
        if (m[p] === 'borrow') {
          anyBorrow = true
        }
      }
    }
    let hint = '点空格填入数字'
    if (anyCarry) {
      hint += '; 哪一位有进位, 点它下方小格标「1」'
    }
    if (anyBorrow) {
      hint += '; 哪一位要借位, 点它下方小格标「-1」'
    }
    return hint
  }

  private statusDotColor(): string {
    if (this.statusTone === 'ok') {
      return STATUS_OK
    }
    if (this.statusTone === 'bad') {
      return STATUS_BAD
    }
    return this.themePrimary
  }

  private statusTextColor(): ResourceColor {
    if (this.statusTone === 'ok') {
      return STATUS_OK
    }
    if (this.statusTone === 'bad') {
      return STATUS_BAD
    }
    return $r('app.color.text_secondary')
  }

  // ForEach 数据源辅助
  private indexArray(count: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < count; i++) {
      arr.push(i)
    }
    return arr
  }

  private reverseCols(cols: number): number[] {
    const arr: number[] = []
    for (let p = cols - 1; p >= 0; p--) {
      arr.push(p)
    }
    return arr
  }

  // ---- 渲染 ----

  /** 块内标记种类齐次: 加法块标 carry, 减法块标 borrow (由第二个操作数的运算符决定) */
  private markKindFor(block: ColumnBlock): string {
    return block.operands.length > 1 && block.operands[1].op === '-' ? 'borrow' : 'carry'
  }

  @Builder
  MarkSlot(bi: number, place: number, kind: string) {
    Row() {
      Text(this.cellValue(this.markInputs, bi, place) === 'carry' ? '1'
        : this.cellValue(this.markInputs, bi, place) === 'borrow' ? '-1' : '')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(kind === 'carry' ? this.palette.carry : this.palette.borrow)
    }
    .width(CELL_SIZE)
    .height(SLOT_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .border({
      width: 1.5,
      color: kind === 'carry' ? this.palette.carry : this.palette.borrow,
      style: this.cellValue(this.markInputs, bi, place) === '' ? BorderStyle.Dashed : BorderStyle.Solid
    })
    .backgroundColor(kind === 'carry'
      ? withColorAlpha(this.palette.carry, this.isDarkMode ? '26' : '14')
      : withColorAlpha(this.palette.borrow, this.isDarkMode ? '26' : '14'))
    .onClick(() => {
      this.toggleMark(bi, place, kind)
    })
  }

  @Builder
  OperandCell(digit: string) {
    Row() {
      Text(digit)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .width(CELL_SIZE)
    .height(DIGIT_ROW_HEIGHT)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ResultCell(bi: number, block: ColumnBlock, place: number) {
    if (place < block.answerPlaces) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Row() {
          Text(this.cellValue(this.resultInputs, bi, place))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .width(CELL_SIZE - 6)
        .height(RESULT_CELL_HEIGHT - 8)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .border({
          width: this.isResultSelected(bi, place) ? 2.5 : 1.5,
          color: this.resultBorderColor(bi, place),
          style: this.cellValue(this.resultInputs, bi, place) === '' && !this.isResultSelected(bi, place)
            ? BorderStyle.Dashed : BorderStyle.Solid
        })
        .backgroundColor(this.resultBackground(bi, place))

        if (this.checked && this.isResultOk(bi, place)) {
          Text('✓')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(STATUS_OK)
            .margin({ right: -2, top: -4 })
        }
        if (this.checked && !this.isResultOk(bi, place)) {
          Text('×')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(STATUS_BAD)
            .margin({ right: -2, top: -4 })
        }
      }
      .width(CELL_SIZE)
      .height(RESULT_CELL_HEIGHT)
      .onClick(() => {
        this.selectResult(bi, place)
      })
    } else {
      Row()
        .width(CELL_SIZE)
        .height(RESULT_CELL_HEIGHT)
    }
  }

  private isResultSelected(bi: number, p: number): boolean {
    return this.selectedBlock === bi && this.selectedPlace === p
  }

  private resultBorderColor(bi: number, p: number): string {
    if (this.checked) {
      return this.isResultOk(bi, p) ? STATUS_OK : STATUS_BAD
    }
    if (this.isResultSelected(bi, p)) {
      return this.themePrimary
    }
    return this.isDarkMode ? '#44506B' : '#C9D6EC'
  }

  private resultBackground(bi: number, p: number): ResourceColor {
    if (this.checked) {
      return this.isResultOk(bi, p)
        ? withColorAlpha(STATUS_OK, this.isDarkMode ? '2E' : '1A')
        : withColorAlpha(STATUS_BAD, this.isDarkMode ? '2E' : '1A')
    }
    if (this.isResultSelected(bi, p)) {
      return withColorAlpha(this.themePrimary, this.isDarkMode ? '2E' : '1A')
    }
    return Color.Transparent
  }

  @Builder
  BlockView(bi: number, block: ColumnBlock) {
    Column({ space: 5 }) {
      if (bi > 0) {
        Row()
          .width('100%')
          .height(1)
          .border({ width: 1, color: this.palette.divider, style: BorderStyle.Dashed })
          .margin({ top: 4, bottom: 2 })
      }

      // 操作数行
      ForEach(block.operands, (opnd: ColumnBlockOperand, oi: number) => {
        Row({ space: CELL_GAP }) {
          Text(opnd.op === '' ? '' : getOpDisplay(opnd.op))
            .width(OP_SLOT_WIDTH)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themePrimary)
            .textAlign(TextAlign.Center)
          ForEach(this.reverseCols(block.cols), (p: number) => {
            if (block.chainedTop && bi > 0 && oi === 0) {
              this.OperandCell(this.chainDisplayDigit(bi, p))
            } else {
              this.OperandCell(this.charAt1d(opnd.cells, p))
            }
          }, (p: number) => `opd_${bi}_${oi}_${p}`)
        }
        .height(DIGIT_ROW_HEIGHT)
      }, (opnd: ColumnBlockOperand, oi: number) => `oprow_${bi}_${oi}_${opnd.op}`)

      // 进位/借位标记行: 数字下方、横线上方 (与教学板 markRow 同序); 全列挂格不预设位置,
      // 标记种类由块的运算符决定, 孩子自行判断哪列要标
      Row({ space: CELL_GAP }) {
        Row().width(OP_SLOT_WIDTH).height(SLOT_HEIGHT)
        ForEach(this.reverseCols(block.cols), (p: number) => {
          this.MarkSlot(bi, p, this.markKindFor(block))
        }, (p: number) => `slot_${bi}_${p}`)
      }

      // 横线
      Row()
        .width(OP_SLOT_WIDTH + CELL_SIZE * block.cols + CELL_GAP * block.cols)
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.isDarkMode ? '#8B98B0' : '#3A4356')

      // 结果行
      Row({ space: CELL_GAP }) {
        Row().width(OP_SLOT_WIDTH).height(RESULT_CELL_HEIGHT)
        ForEach(this.reverseCols(block.cols), (p: number) => {
          this.ResultCell(bi, block, p)
        }, (p: number) => `res_${bi}_${p}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  KeyCap(key: string) {
    if (key === '⌫') {
      Text(key)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themePrimary)
        .width(KEY_WIDTH)
        .height(KEY_HEIGHT)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '2E' : '1A'))
        .onClick(() => {
          this.handleBackspace()
        })
    } else {
      Text(key)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width(KEY_WIDTH)
        .height(KEY_HEIGHT)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor(this.isDarkMode ? '#2A3450' : '#F1F5FC')
        .border({ width: 1, color: this.isDarkMode ? '#3A4665' : '#DDE6F5' })
        .onClick(() => {
          this.handleDigit(key)
        })
    }
  }

  build() {
    Column({ space: 10 }) {
      // 状态条: 引导提示 / 检查结果
      Row({ space: 9 }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.statusDotColor())
        Text(this.statusText)
          .fontSize(12.5)
          .fontWeight(this.checked ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.statusTextColor())
          .layoutWeight(1)
          .lineHeight(18)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(12)
      .backgroundColor(this.isDarkMode ? '#1C2333' : '#F1F5FC')

      if (this.layout.blocks.length > 0) {
        // 分步块 (可滚动, 多块链在小屏不溢出)
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.indexArray(this.layout.blocks.length), (bi: number) => {
              this.BlockView(bi, this.layout.blocks[bi])
            }, (bi: number) => `block_${bi}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        Blank()
      }

      // 检查按钮
      Row() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(17)
          .fontColor([Color.White])
        Text('检查一下')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .margin({ left: 7 })
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
      .borderRadius(14)
      .backgroundColor(this.themePrimary)
      .onClick(() => {
        this.handleCheck()
      })

      // 数字键盘: 选中格子后写入; ⌫ 清除当前格; 固定网格宽度让三行列位对齐
      Column({ space: KEY_GAP }) {
        ForEach(KEY_ROWS, (rowKeys: string[], rowIdx: number) => {
          Row({ space: KEY_GAP }) {
            ForEach(rowKeys, (key: string) => {
              this.KeyCap(key)
            }, (key: string) => `key_${rowIdx}_${key}`)
          }
          .width(KEY_PAD_WIDTH)
        }, (rowKeys: string[], rowIdx: number) => `keyrow_${rowIdx}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
