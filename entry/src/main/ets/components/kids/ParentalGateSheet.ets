import { BusinessError } from '@kit.BasicServicesKit'
import { GateQuestion, generateGateQuestion, checkGateAnswer } from '../../utils/ParentalGateMath'
import {
  KIDS_BG,
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_MUTED,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_ACCENT,
  KIDS_CHINESE_INK,
  KIDS_STAR,
  KIDS_ON_GOLD,
  KIDS_ENGLISH_INK,
  KIDS_ON_HERO
} from './KidsBrandTokens'
import { StarEventRow, TodayStarSummary } from '../../models/StarEventModels'
import { getStarRewardService } from '../../services/StarRewardService'
import { getChildProfileService, ChildKnowledgeProfile } from '../../services/ChildProfileService'
import {
  buildTodayCategoryRows,
  buildTodayEventRows,
  formatDateLabel,
  formatWeekday,
  KidsTodayCategoryRow,
  KidsTodayEventRow
} from '../../utils/KidsSubjectUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

const SHAKE_OFFSETS: number[] = [10, -10, 6, -6, 0]
const SHAKE_STEP_MS: number = 60
const MAX_INPUT_LENGTH: number = 4
const DIGIT_KEYS: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9']

/**
 * 家长门（算术题验证）sheet 内容——自绘数字键盘版，两阶段（spec §4.7）：
 * gate = 算术门（对照 docs/kids-home-prototype.html 的 .gate 区块）；
 * summary = 答对后的「家长今日概览」（star-hero + 学科分布 + 今日记录）。
 *
 * 答案显示框（空态「输入答案」, 答错语文橙红边框 + 抖动 + 换题）
 * + 3×4 数字键盘（1–9 / ⌫ / 0 / 通栏「确定」）, 不依赖系统输入法。
 * 答对 → phase = summary（加载今日数据, 失败降级为 star-hero + 按钮）；
 * summary「进入家长设置」→ onPassed（宿主负责关 sheet + 置解锁态）;
 * 「知道了」/✕/拖拽 → onCancelled。sheet 每次打开都从 gate 开始——
 * 门语义不因看过概览而放宽。无状态持久化: 关闭即清空。
 */
@ComponentV2
export struct ParentalGateSheet {
  @Event onPassed: () => void = () => {}
  @Event onCancelled: () => void = () => {}
  @Local currentQuestion: GateQuestion = { text: '', answer: 0 } as GateQuestion
  @Local inputText: string = ''
  @Local showError: boolean = false
  @Local shakeX: number = 0
  private shakeTimerIds: number[] = []
  /** gate = 算术门; summary = 家长今日概览（spec §4.7） */
  @Local phase: string = 'gate'
  @Local summaryStars: number = 0
  @Local summaryCategoryRows: KidsTodayCategoryRow[] = []
  @Local summaryEventRows: KidsTodayEventRow[] = []
  @Local summaryChildName: string = ''
  @Local summaryLoaded: boolean = false

  aboutToAppear(): void {
    this.phase = 'gate'
    this.inputText = ''
    this.showError = false
    this.currentQuestion = generateGateQuestion()
  }

  aboutToDisappear(): void {
    this.clearShakeTimers()
  }

  private clearShakeTimers(): void {
    for (let i = 0; i < this.shakeTimerIds.length; i++) {
      clearTimeout(this.shakeTimerIds[i])
    }
    this.shakeTimerIds = []
  }

  private handleDigit(digit: string): void {
    this.showError = false
    if (this.inputText.length < MAX_INPUT_LENGTH) {
      this.inputText += digit
    }
  }

  private handleBackspace(): void {
    this.showError = false
    this.inputText = this.inputText.slice(0, -1)
  }

  private handleConfirm(): void {
    if (checkGateAnswer(this.currentQuestion, this.inputText)) {
      this.phase = 'summary'
      this.loadSummary()
      return
    }
    this.showError = true
    this.inputText = ''
    this.currentQuestion = generateGateQuestion()
    this.playShake()
  }

  private playShake(): void {
    this.clearShakeTimers()
    for (let i = 0; i < SHAKE_OFFSETS.length; i++) {
      const offset: number = SHAKE_OFFSETS[i]
      const timerId: number = setTimeout((): void => {
        this.shakeX = offset
      }, i * SHAKE_STEP_MS)
      this.shakeTimerIds.push(timerId)
    }
  }

  private loadSummary(): void {
    getStarRewardService().getTodaySummary().then((summary: TodayStarSummary): void => {
      this.summaryStars = summary.total
    }).catch((error: Object): void => {
      console.error('ParentalGateSheet', `Failed to load summary: ${(error as BusinessError).message ?? String(error)}`)
      this.summaryStars = 0
    })
    getStarRewardService().getTodayEvents().then((events: StarEventRow[]): void => {
      this.summaryCategoryRows = buildTodayCategoryRows(events)
      this.summaryEventRows = buildTodayEventRows(events)
      this.summaryLoaded = true
    }).catch((error: Object): void => {
      console.error('ParentalGateSheet', `Failed to load summary events: ${(error as BusinessError).message ?? String(error)}`)
      this.summaryCategoryRows = []
      this.summaryEventRows = []
      this.summaryLoaded = true  // 失败也降级显示 star-hero + 按钮，不阻塞进入家长设置
    })
    getChildProfileService().getProfile().then((profile: ChildKnowledgeProfile): void => {
      this.summaryChildName = profile.childName.trim()
    }).catch((error: Object): void => {
      console.error('ParentalGateSheet', `Failed to load child name: ${(error as BusinessError).message ?? String(error)}`)
      this.summaryChildName = ''
    })
  }

  private summaryDateLabel(): string {
    const now: number = Date.now()
    return `家长视图 · ${formatDateLabel(now)} ${formatWeekday(now)}`
  }

  private summaryHeadline(): string {
    const name: string = this.summaryChildName.length > 0 ? this.summaryChildName : '小朋友'
    return `${name}今天的学习情况，一眼读懂`
  }

  build() {
    Column() {
      if (this.phase === 'gate') {
        this.GatePhase()
      } else {
        this.SummaryPhase()
      }
    }
    .width('100%')
    .backgroundColor(KIDS_SURFACE)
  }

  @Builder
  GatePhase() {
    Column() {
      // 标题栏: 左占位保持标题居中, 右侧 ✕（close.svg, 44vp 触控目标）
      Row() {
        Column()
          .width(44)
          .height(44)

        Text('家长验证')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Column() {
          Image($rawfile('kids/close.svg')).width(16).height(16)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0F24211C')
        .onClick((): void => {
          this.onCancelled()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('请算出下面的题目，答对即可进入')
        .fontSize(12.5)
        .fontColor(KIDS_MUTED)
        .margin({ top: 14 })

      // 题目
      Text(this.currentQuestion.text)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .letterSpacing(1)
        .margin({ top: 14 })

      // 答案显示框（答错: 语文橙红边框 + 抖动，§6 不新增状态色）
      Column() {
        if (this.inputText.length > 0) {
          Text(this.inputText)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
            .letterSpacing(2)
        } else {
          Text('输入答案')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_SUBTLE)
        }
      }
      .width('100%')
      .height(56)
      .borderRadius(14)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(KIDS_BG)
      .border({ width: 2, color: this.showError ? KIDS_CHINESE_INK : KIDS_BORDER })
      .translate({ x: this.shakeX })
      .animation({ duration: SHAKE_STEP_MS, curve: Curve.EaseOut })
      .margin({ top: 14 })

      // 错误提示（固定高度避免布局跳动）
      Text(this.showError ? '答案不对，换一题啦' : ' ')
        .fontSize(12.5)
        .fontColor(KIDS_CHINESE_INK)
        .height(18)
        .margin({ top: 10 })

      // 数字键盘: 1-9 / ⌫ / 0 / 通栏确定
      Grid() {
        ForEach(DIGIT_KEYS, (key: string): void => {
          GridItem() {
            this.DigitKey(key)
          }
        }, (key: string): string => key)

        GridItem() {
          this.AltKey('⌫', (): void => {
            this.handleBackspace()
          })
        }

        GridItem() {
          this.DigitKey('0')
        }

        GridItem() {
          Column()
            .width('100%')
            .height(52)
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height(4 * 52 + 3 * 10)
      .scrollBar(BarState.Off)

      Button('确定')
        .width('100%')
        .height(52)
        .borderRadius(14)
        .backgroundColor(KIDS_ACCENT)
        .fontColor(KIDS_ON_HERO)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10 })
        .onClick((): void => {
          this.handleConfirm()
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 32 })
  }

  @Builder
  SummaryPhase() {
    Column() {
      // ── 头部: 标题 + ✕（44vp） ──
      Row() {
        Text('家长今日概览')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .layoutWeight(1)
        Column() {
          Image($rawfile('kids/close.svg')).width(16).height(16)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0F24211C')
        .onClick((): void => {
          this.onCancelled()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 14 }) {
          // 眉标 + 一句话
          Column({ space: 4 }) {
            Text(this.summaryDateLabel())
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(KIDS_ON_GOLD)
              .letterSpacing(1)
            Text(this.summaryHeadline())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_FG)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // star-hero（同 KidsStarDetailSheet 样式）
          Row({ space: 14 }) {
            Column() {
              Image($rawfile('kids/star.svg')).width(30).height(30)
            }
            .width(48)
            .height(48)
            .borderRadius(24)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(withColorAlpha(KIDS_STAR, '24'))

            Row({ space: 6 }) {
              Text(`${this.summaryStars}`)
                .fontSize(31)
                .fontWeight(FontWeight.Bold)
                .fontColor(KIDS_ON_GOLD)
              Text('颗 · 今日获得')
                .fontSize(12.5)
                .fontColor(KIDS_MUTED)
                .margin({ bottom: 5 })
            }
            .alignItems(VerticalAlign.Bottom)
          }
          .width('100%')
          .padding(18)
          .borderRadius(18)
          .backgroundColor(withColorAlpha(KIDS_STAR, '24'))
          .alignItems(VerticalAlign.Center)

          // 学科分布（今日有事件的学科行）
          ForEach(this.summaryCategoryRows, (row: KidsTodayCategoryRow): void => {
            Row({ space: 10 }) {
              Column() {
                Image($rawfile(row.iconPath)).width(18).height(18)
              }
              .width(32)
              .height(32)
              .borderRadius(10)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(withColorAlpha(row.tint, '26'))

              Column({ space: 2 }) {
                Text(row.name)
                  .fontSize(13.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(KIDS_FG)
                Text(row.detail)
                  .fontSize(11)
                  .fontColor(KIDS_SUBTLE)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(`${row.stars}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(KIDS_ON_GOLD)
              Image($rawfile('kids/star.svg')).width(14).height(14)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(14)
            .backgroundColor(KIDS_BG)
            .alignItems(VerticalAlign.Center)
          }, (row: KidsTodayCategoryRow, index: number): string => `${row.name}_${index}`)

          // 今日记录（时间 + 描述 + 「+N 星」药丸）
          ForEach(this.summaryEventRows, (row: KidsTodayEventRow): void => {
            Row({ space: 10 }) {
              Text(row.timeLabel)
                .fontSize(11)
                .fontColor(KIDS_SUBTLE)
                .width(38)
              Text(row.description)
                .fontSize(12.5)
                .fontColor(KIDS_FG)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(row.stars > 0 ? `+${row.stars} 星` : '0 星')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(row.stars > 0 ? KIDS_ENGLISH_INK : KIDS_SUBTLE)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(999)
                .backgroundColor(row.stars > 0 ? '#2635A98A' : '#0F24211C')
            }
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .alignItems(VerticalAlign.Center)
          }, (row: KidsTodayEventRow, index: number): string => `s_${row.timeLabel}_${index}`)

          // 说明条
          Text('完整报告与历史趋势在家长设置中查看')
            .fontSize(11.5)
            .fontColor(KIDS_MUTED)
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#0D24211C')
        }
        .width('100%')
        .padding({ top: 14, bottom: 10 })
      }
      .constraintSize({ maxHeight: 380 })
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // ── 两个 48vp 按钮 ──
      Button('进入家长设置')
        .width('100%')
        .height(48)
        .borderRadius(999)
        .backgroundColor(KIDS_ACCENT)
        .fontColor(KIDS_ON_HERO)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10 })
        .onClick((): void => {
          this.onPassed()
        })

      Button('知道了')
        .width('100%')
        .height(48)
        .borderRadius(999)
        .backgroundColor(Color.Transparent)
        .border({ width: 1.5, color: KIDS_BORDER })
        .fontColor(KIDS_MUTED)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 10 })
        .onClick((): void => {
          this.onCancelled()
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 32 })
  }

  @Builder
  DigitKey(digit: string) {
    Text(digit)
      .fontSize(21)
      .fontWeight(FontWeight.Bold)
      .fontColor(KIDS_FG)
      .width('100%')
      .height(52)
      .textAlign(TextAlign.Center)
      .borderRadius(14)
      .backgroundColor(KIDS_BG)
      .border({ width: 1, color: KIDS_BORDER })
      .onClick((): void => {
        this.handleDigit(digit)
      })
  }

  @Builder
  AltKey(label: string, action: () => void) {
    Text(label)
      .fontSize(17)
      .fontColor(KIDS_MUTED)
      .width('100%')
      .height(52)
      .textAlign(TextAlign.Center)
      .borderRadius(14)
      .backgroundColor(KIDS_BG)
      .border({ width: 1, color: KIDS_BORDER })
      .onClick((): void => {
        action()
      })
  }
}
