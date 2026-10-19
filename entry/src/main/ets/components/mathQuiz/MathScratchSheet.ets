/**
 * MathScratchSheet - 数学题「草稿纸」sheet (chrome)
 *
 * 从 MathQuizCard 通过 bindSheet 打开 (LARGE + BOTTOM, 沿用旧 VerticalMathHelpSheet 模式)。
 * 两个 tab: 手写草稿 (MathScratchDrawBoard, Canvas 自由绘制) /
 * 竖式计算 (MathColumnPaperBoard, 分步竖式块 + 进/借位标记 + 本地自检)。
 * 纯工作区: 不判分、不持久化、不回传, 正确性由 MathQuizCard 的点选作答决定。
 *
 * 两 tab 内容常驻 Stack (visibility 切换), 保留各自的笔迹/输入;
 * 清空只作用于当前可见面板 (两个独立 clearTick 分别广播)。
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ColumnPaperLayout } from '../../utils/MathColumnPaperLayout'
import { MathScratchDrawBoard } from './MathScratchDrawBoard'
import { MathColumnPaperBoard } from './MathColumnPaperBoard'

@ComponentV2
export struct MathScratchSheet {
  /** 竖式布局; null = 仅手写 tab (防御分支, 正常入口已由 canShowScratch 保证非空) */
  @Param layout: ColumnPaperLayout | null = null
  @Event onClose: () => void = () => {}

  /** 0 = 手写草稿, 1 = 竖式计算 */
  @Local mode: number = 0
  /** 清空广播: 递增触发对应面板 @Monitor 清空 (两面板独立, 清空不互删另一 tab 的内容) */
  @Local drawClearTick: number = 0
  @Local columnClearTick: number = 0

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get expressionText(): string {
    return this.layout !== null ? this.layout.expressionText : ''
  }

  private get hasColumn(): boolean {
    return this.layout !== null
  }

  // 供 MathColumnPaperBoard 的非空 @Param 使用; 仅在 hasColumn 为 true 时被渲染路径触达
  private get safeLayout(): ColumnPaperLayout {
    if (this.layout !== null) {
      return this.layout
    }
    const empty: ColumnPaperLayout = { blocks: [], expressionText: '' }
    return empty
  }

  @Builder
  SegTab(label: string, tabIndex: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.mode === tabIndex ? this.themePrimary : $r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(38)
      .borderRadius(10)
      .backgroundColor(this.mode === tabIndex
        ? withColorAlpha(this.themePrimary, this.isDarkMode ? '33' : '1F')
        : Color.Transparent)
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onClick(() => {
        this.mode = tabIndex
      })
  }

  build() {
    Column({ space: 10 }) {
      // 标题栏: ✏️ 草稿纸 ······ [清空] [✕]
      Row({ space: 10 }) {
        Text('✏️')
          .fontSize(18)
        Text('草稿纸')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('清空')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .height(36)
          .padding({ left: 14, right: 14 })
          .borderRadius(18)
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '2E' : '14'))
          .onClick(() => {
            if (this.mode === 0) {
              this.drawClearTick += 1
            } else {
              this.columnClearTick += 1
            }
          })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .width(36)
          .height(36)
          .onClick(() => {
            this.onClose()
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 算式提示: 在下面算一算, 回去选答案
      Column({ space: 4 }) {
        Text(this.expressionText)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themePrimary)
          .width('100%')
          .textAlign(TextAlign.Center)
        Text('在下面算一算, 回去聊天里选答案')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })

      // tab 切换 (仅竖式可用时显示; 防御: layout 为 null 时只有手写)
      if (this.hasColumn) {
        Row({ space: 4 }) {
          this.SegTab('手写草稿', 0)
          this.SegTab('竖式计算', 1)
        }
        .width('100%')
        .padding(4)
        .borderRadius(13)
        .backgroundColor(this.isDarkMode ? '#1C2333' : '#F1F5FC')
      }

      // 内容区: 两面板常驻 Stack, visibility 切换保留笔迹/输入
      Stack() {
        MathScratchDrawBoard({ clearTick: this.drawClearTick })
          .visibility(this.mode === 0 ? Visibility.Visible : Visibility.None)

        if (this.layout !== null) {
          MathColumnPaperBoard({ layout: this.safeLayout, clearTick: this.columnClearTick })
            .visibility(this.mode === 1 ? Visibility.Visible : Visibility.None)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
  }
}
