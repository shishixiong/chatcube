/**
 * CardShell - 互动卡片统一外壳
 *
 * 7 区固定顺序: head → [feedbackAboveSlot 时: celebration] → stem → replay(可选)
 * → slot(卡片自绘) → [默认: feedback] → actions。
 * 卡片通过 config 声明静态配置, 通过 CardShellState 传递响应式状态,
 * 通过 @Event 接收确认/重试/重听。外壳不含任何游戏判定逻辑。
 *
 * 视觉: 颜色从 AppUiState 的 themePrimary/themeAiBubble 派生(随主题+深色模式)。
 * 设计: docs/superpowers/specs/2026-09-12-cardshell-design.md
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { CardShellConfig, CardShellCopy } from './CardShellTypes'
import { CardShellState } from './CardShellState'

@ComponentV2
export struct CardShell {
  @Require @Param config: CardShellConfig
  @Require @Param state: CardShellState
  /** 历史会话只读态(payload 已回传) */
  @Param isAnswered: boolean = false
  /** 答错反馈显示的正确答案; '' 不渲染该行 */
  @Param correctAnswerText: string = ''
  /** 全屏 sheet 模式: 透明背景无边框, 由 sheet 接管外壳 */
  @Param largeSize: boolean = false
  /** true 时拦截触摸事件冒泡(CategorizationCard 的拖拽隔离需要) */
  @Param blockTouch: boolean = false
  /** 卡片自绘插槽: 选项组/棋盘/连线层等 */
  @BuilderParam slot: () => void
  @Event onConfirm: () => void = () => {}
  @Event onRetry: () => void = () => {}
  @Event onRequestReplay: () => void = () => {}
  /** 放弃本局(棋盘卡); 带默认值, 不传的卡片零影响 */
  @Event onGiveUp: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  build() {
    Column({ space: 10 }) {
      this.HeadRegion()
      if (this.config.feedbackAboveSlot === true) {
        this.CelebrationRegion()
      }
      this.StemRegion()
      this.ReplayRegion()
      this.slot()
      if (this.config.feedbackAboveSlot !== true) {
        this.FeedbackRegion()
      }
      this.ActionsRegion()
    }
    .width('100%')
    .padding(this.largeSize ? 24 : 12)
    .backgroundColor(this.largeSize ? Color.Transparent : this.themeAiBubble)
    .borderRadius(this.largeSize ? 0 : 12)
    .border(this.largeSize
      ? { width: 0, color: Color.Transparent, style: BorderStyle.Solid }
      : { width: 1, color: $r('app.color.divider'), style: BorderStyle.Solid })
    .alignItems(HorizontalAlign.Start)
    .onTouch((e: TouchEvent) => {
      if (this.blockTouch) {
        e.stopPropagation()
      }
    })
  }

  // ================ head: 图标徽章 + 标题/副标题 + 徽章/状态药丸 ================
  @Builder
  HeadRegion() {
    Row() {
      Column() {
        SymbolGlyph(this.config.icon)
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(this.config.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.config.subtitle !== '') {
          Text(this.config.subtitle)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
      .layoutWeight(1)

      if (this.state.headBadge !== '') {
        Text(this.state.headBadge)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .margin({ right: 6 })
      }
      if (this.state.headPill !== '') {
        Text(this.state.headPill)
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(this.state.headPillColor)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ================ stem: 题干一行 ================================
  @Builder
  StemRegion() {
    if (this.config.stem !== '') {
      Text(this.config.stem)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
  }

  // ================ replay: 重听音轨(仅 hasAudio) ==================
  @Builder
  ReplayRegion() {
    if (this.config.hasAudio) {
      Row({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.speaker_wave_2'))
            .fontSize(16)
            .fontColor([Color.White])
          Text(this.state.isPlaying ? CardShellCopy.PLAYING : CardShellCopy.REPLAY)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .height(40)
        .padding({ left: 16, right: 16 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.state.isPlaying ? withColorAlpha(this.themePrimary, '59') : this.themePrimary)
        .borderRadius(20)
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.onRequestReplay()
        })

        if (this.state.isPlaying) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.text_tertiary'))
        }

        Text(this.state.isPlaying ? CardShellCopy.PLAYING_HINT : CardShellCopy.REPLAY_HINT)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  // ================ celebration: 棋盘卡庆祝横幅(feedbackAboveSlot) ====
  // 门控仅看 submitted(不含 isAnswered): 放弃局及放弃局的历史恢复都不显示横幅,
  // 与迁移前三卡的 if (hasWon) 门控一致; 恢复路径由卡片按 hasWon 写 submitted。
  @Builder
  CelebrationRegion() {
    if (this.state.submitted) {
      Row({ space: 10 }) {
        Text('🎉')
          .fontSize(26)
        Column() {
          Text(this.state.feedbackTitle !== '' ? this.state.feedbackTitle : this.config.feedbackTitleCorrect)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.status_success'))
          if (this.state.feedbackDetail !== '') {
            Text(this.state.feedbackDetail)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.state.feedbackBadge !== '') {
          Text(this.state.feedbackBadge)
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(CardShellCopy.SUCCESS_GREEN)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(withColorAlpha(CardShellCopy.SUCCESS_GREEN, this.isDarkMode ? '18' : '0C'))
      .borderRadius(12)
      .border({
        width: 1,
        color: withColorAlpha(CardShellCopy.SUCCESS_GREEN, this.isDarkMode ? '38' : '28'),
        style: BorderStyle.Solid
      })
    }
  }

  // ================ feedback: 对/错统一横幅 ========================
  @Builder
  FeedbackRegion() {
    if (this.state.submitted || this.isAnswered) {
      Column({ space: 8 }) {
        if (this.state.isCorrect) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('🌟')
                .fontSize(22)
              Text(this.state.feedbackTitle !== '' ? this.state.feedbackTitle : this.config.feedbackTitleCorrect)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.Green)
            }
            .width('100%')

            if (this.state.feedbackDetail !== '') {
              Text(this.state.feedbackDetail)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          }
          .width('100%')
        } else {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('💪')
                .fontSize(20)
              Text(this.state.feedbackTitle !== '' ? this.state.feedbackTitle : CardShellCopy.RETRY)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')

            if (this.correctAnswerText !== '') {
              Row({ space: 4 }) {
                Text(`${this.config.correctAnswerLabel}：`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Text(this.correctAnswerText)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.Green)
              }
              .width('100%')
            }

            if (this.config.usesConfirm && !this.isAnswered) {
              Row() {
                Text(CardShellCopy.RETRY)
                  .fontSize(14)
                  .fontColor(this.themePrimary)
              }
              .width('100%')
              .height(38)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(withColorAlpha(this.themePrimary, '1F'))
              .borderRadius(8)
              .onClick(() => {
                this.onRetry()
              })
            }
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(10)
      .backgroundColor(withColorAlpha(this.state.isCorrect ? '#22C55E' : '#FF6B6B', '1A'))
      .borderRadius(8)
      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    }
  }

  // ================ actions: 确认主按钮(usesConfirm) ===============
  @Builder
  ActionsRegion() {
    if (this.config.usesConfirm && this.state.hasSelection && !this.state.submitted && !this.isAnswered) {
      Row() {
        Text(CardShellCopy.CONFIRM)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.themePrimary)
      .borderRadius(10)
      .animation({ duration: 150, curve: Curve.EaseOut })
      .onClick(() => {
        this.onConfirm()
      })
    }
    if (this.config.usesGiveUp === true && !this.state.isFinished && !this.isAnswered) {
      Row() {
        Blank()
        Text(this.config.giveUpLabel ?? CardShellCopy.GIVE_UP)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(8)
          .onClick(() => {
            this.onGiveUp()
          })
      }
      .width('100%')
    }
  }
}
