// entry/src/main/ets/components/map/bodies/MapCompareBody.ets
/**
 * MapCompareBody - map_quiz compare 题型 body（面积比较 / 方位比较）
 *
 * 两种比较共用一张卡片：
 *  - area:      「这两个省，哪个更大？」两块剪影各自铺满一格（看起来差不多大），
 *               答完切成同一个比例尺重画——孩子亲眼看到「大」是什么意思。
 *  - direction: 「X 在 Y 的哪一边？」东南西北四选一，从地图数据算中心点方位。
 *
 * 答案全部由 utils/ChinaMapMetrics 从现有 path 算出，AI 只负责挑一对省；
 * 一对省是否能出题（面积比 ≥1.25 / 方位主轴 ≥1.6）已在预校验里把关。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../../state/AppUiState'
import { ToolCall } from '../../../models/ChatModels'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import {
  ChinaMapData, ChinaProvince, findProvinceByRef, getCachedChinaMapData, loadChinaMapData
} from '../../../utils/ChinaMapData'
import {
  dominantDirection, largerProvince, MAP_DIRECTIONS
} from '../../../utils/ChinaMapMetrics'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { KIDS_MUTED } from '../../kids/KidsBrandTokens'
import { MapQuizAnswerPayload, MapQuizArgsView, parseMapQuizArgs } from '../MapQuizTypes'
import {
  MapSilhouette, SILHOUETTE_LAYOUT_CELLS, SILHOUETTE_LAYOUT_SHARED
} from '../MapSilhouette'

const COMPARE_AREA: string = 'area'
const COMPARE_DIRECTION: string = 'direction'

@ComponentV2
export struct MapCompareBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local data: ChinaMapData | null = null
  @Local provinceA: ChinaProvince | null = null
  @Local provinceB: ChinaProvince | null = null
  @Local kind: string = COMPARE_AREA
  @Local optionLabels: string[] = []
  @Local correctLabel: string = ''
  @Local skillKey: string = 'general_social'
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local selectedLabel: string = ''

  private argsView: MapQuizArgsView = parseMapQuizArgs('')
  private submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图出题', subtitle: '比一比', icon: $r('sys.symbol.map'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '比对啦！真棒！', correctAnswerLabel: '正确答案'
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get isArea(): boolean {
    return this.kind === COMPARE_AREA
  }

  aboutToAppear(): void {
    this.argsView = parseMapQuizArgs(this.toolCall.arguments)
    this.initWithProvinces(getCachedChinaMapData())
    if (this.data === null) {
      const ctx = getContext(this) as common.UIAbilityContext
      loadChinaMapData(ctx).then((loaded: ChinaMapData | null) => {
        this.initWithProvinces(loaded)
      }).catch((_e: Error) => {
      })
    }
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.selectedLabel = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.hasSelection = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      } else {
        this.shellState.feedbackSuppressed = true
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    }
  }

  private initWithProvinces(loaded: ChinaMapData | null): void {
    if (loaded === null || !this.argsView.valid || this.argsView.provinceB === '') {
      return
    }
    const a = findProvinceByRef(loaded.provinces, this.argsView.province)
    const b = findProvinceByRef(loaded.provinces, this.argsView.provinceB)
    if (a === null || b === null || a.id === b.id) {
      return
    }
    this.data = loaded
    this.provinceA = a
    this.provinceB = b
    this.kind = this.argsView.compare === COMPARE_DIRECTION ? COMPARE_DIRECTION : COMPARE_AREA
    this.skillKey = this.argsView.skillKey
    if (this.isArea) {
      const larger = largerProvince(a, b)
      this.correctLabel = larger !== null ? larger.short : a.short
      // 两项随机左右，避免「总是第一个大」的规律被记住
      const labels: string[] = Math.random() < 0.5 ? [a.short, b.short] : [b.short, a.short]
      this.optionLabels = labels
    } else {
      this.correctLabel = dominantDirection(a, b)
      this.optionLabels = MAP_DIRECTIONS
    }
  }

  private parsePreviousAnswer(): MapQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as MapQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  private handleSelect(label: string): void {
    if (this.isAnswered || this.showResult || this.submitted) {
      return
    }
    const a = this.provinceA
    const b = this.provinceB
    if (a === null || b === null) {
      return
    }
    const correct = label === this.correctLabel
    this.selectedLabel = label
    this.showResult = true
    this.isCorrect = correct
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct

    const payload: MapQuizAnswerPayload = {
      answered: true,
      mode: 'compare',
      province: a.short,
      province_id: a.id,
      province_b: b.short,
      compare: this.kind,
      clue: '',
      child_answer: label,
      correct: correct,
      skill_key: this.skillKey
    }
    this.submitted = true
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private revealText(): string {
    const a = this.provinceA
    const b = this.provinceB
    if (a === null || b === null) {
      return ''
    }
    if (this.isArea) {
      const larger = largerProvince(a, b)
      const smaller = larger !== null && larger.id === a.id ? b : a
      const bigger = larger !== null ? larger : a
      return `同一个比例尺下看，「${bigger.short}」比「${smaller.short}」大。`
    }
    const dir = dominantDirection(a, b)
    return `「${a.short}」在「${b.short}」的${dir !== '' ? dir + '边' : '这一边'}。`
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.correctLabel,
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 10 }) {
        if (this.data !== null && this.provinceA !== null && this.provinceB !== null) {
          if (this.isArea) {
            Column() {
              MapSilhouette({
                provinces: [this.provinceA, this.provinceB],
                labels: [this.provinceA.short, this.provinceB.short],
                layout: this.showResult ? SILHOUETTE_LAYOUT_SHARED : SILHOUETTE_LAYOUT_CELLS,
                accentId: ''
              })
            }
            .width('100%')
            .height(150)
            .borderRadius(12)
            .clip(true)
            .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '0A' : '06'))

            Text('这两个省，哪个更大？')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          } else {
            Text(`「${this.provinceA.short}」在「${this.provinceB.short}」的哪一边？`)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          }

          if (!this.isAnswered && !this.showResult) {
            Grid() {
              ForEach(this.optionLabels, (label: string) => {
                GridItem() {
                  Button(label)
                    .fontSize(18)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .width('100%')
                    .height(52)
                    .backgroundColor(this.themePrimary)
                    .borderRadius(12)
                    .onClick(() => {
                      this.handleSelect(label)
                    })
                }
              }, (label: string, idx: number) => `cmp_opt_${idx}_${label}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
          } else if (this.showResult) {
            Text(this.isCorrect ? `对啦。${this.revealText()}` : `${this.revealText()}`)
              .fontSize(14)
              .fontColor(this.isCorrect ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
              .width('100%')
          }
        } else if (!this.isAnswered) {
          Text('这道地图题出错了，老师马上换一张')
            .fontSize(14).fontColor(KIDS_MUTED)
            .padding({ top: 8, bottom: 8 })
        } else {
          Text('已回答')
            .fontSize(13).fontColor($r('app.color.text_tertiary'))
            .padding({ top: 8, bottom: 8 })
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.isDarkMode
        ? withColorAlpha(this.themePrimary, '18')
        : withColorAlpha(this.themePrimary, '12'))
      .borderRadius(10)
    }
  }
}
