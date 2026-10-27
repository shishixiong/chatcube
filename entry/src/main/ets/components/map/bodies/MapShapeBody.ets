// entry/src/main/ets/components/map/bodies/MapShapeBody.ets
/**
 * MapShapeBody - map_quiz shape 题型 body（形状猜省）
 *
 * 只给一个省的轮廓（无名字、无底图、无相邻省份），2×2 简称选项。
 * 与 choice 的区别只在题面：choice 给整张地图 + 高亮，shape 给裸剪影——
 * 逼孩子记「形状」这一维，而不是「位置」。
 *
 * 选项沿用 pickMapChoiceOptions（同大区偏好 + 洗牌），AI 不传选项。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../../state/AppUiState'
import { ToolCall } from '../../../models/ChatModels'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import {
  ChinaMapData, ChinaProvince, findProvinceByRef, getCachedChinaMapData, loadChinaMapData
} from '../../../utils/ChinaMapData'
import { pickMapChoiceOptions } from '../../../utils/MapChoiceOptions'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { KIDS_MUTED } from '../../kids/KidsBrandTokens'
import { MapQuizAnswerPayload, MapQuizArgsView, parseMapQuizArgs } from '../MapQuizTypes'
import { MapSilhouette, SILHOUETTE_LAYOUT_SINGLE } from '../MapSilhouette'

@ComponentV2
export struct MapShapeBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local data: ChinaMapData | null = null
  @Local target: ChinaProvince | null = null
  @Local optionIds: string[] = []
  @Local skillKey: string = 'general_social'
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local selectedId: string = ''

  private argsView: MapQuizArgsView = parseMapQuizArgs('')
  private submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图出题', subtitle: '猜轮廓', icon: $r('sys.symbol.map'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '猜对啦！真棒！', correctAnswerLabel: '正确答案'
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
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
        this.selectedId = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.hasSelection = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      } else {
        // payload 缺失/不可解析：抑制反馈横幅，只显示「已回答」
        this.shellState.feedbackSuppressed = true
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    }
  }

  private initWithProvinces(loaded: ChinaMapData | null): void {
    if (loaded === null || !this.argsView.valid) {
      return
    }
    const target = findProvinceByRef(loaded.provinces, this.argsView.province)
    if (target === null) {
      return
    }
    this.data = loaded
    this.target = target
    this.skillKey = this.argsView.skillKey
    this.optionIds = pickMapChoiceOptions(loaded.provinces, target.id, Math.random)
  }

  private provinceById(id: string): ChinaProvince | null {
    const data = this.data
    if (data === null) {
      return null
    }
    for (const p of data.provinces) {
      if (p.id === id) {
        return p
      }
    }
    return null
  }

  private shortForId(id: string): string {
    const p = this.provinceById(id)
    return p !== null ? p.short : id
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

  private handleOptionSelect(optionId: string): void {
    if (this.isAnswered || this.showResult || this.submitted) {
      return
    }
    const target = this.target
    if (target === null) {
      return
    }
    const correct = optionId === target.id
    this.selectedId = optionId
    this.showResult = true
    this.isCorrect = correct
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct

    const payload: MapQuizAnswerPayload = {
      answered: true,
      mode: 'shape',
      province: target.short,
      province_id: target.id,
      clue: '',
      child_answer: this.shortForId(optionId),
      correct: correct,
      skill_key: this.skillKey
    }
    this.submitted = true
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.target !== null ? this.target.short : '',
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 10 }) {
        if (this.data !== null && this.target !== null) {
          Column() {
            // 题面阶段不给名字（只考形状），答完把名字标在轮廓下面
            MapSilhouette({
              provinces: [this.target],
              labels: [this.showResult ? this.target.short : ''],
              layout: SILHOUETTE_LAYOUT_SINGLE,
              accentId: this.target !== null ? this.target.id : ''
            })
          }
          .width('100%')
          .height(190)
          .borderRadius(12)
          .clip(true)
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '0A' : '06'))

          Text('只看这个轮廓，猜猜它是哪个省？')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          if (!this.isAnswered && !this.showResult) {
            Grid() {
              ForEach(this.optionIds, (optionId: string) => {
                GridItem() {
                  Button(this.shortForId(optionId))
                    .fontSize(18)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .width('100%')
                    .height(52)
                    .backgroundColor(this.themePrimary)
                    .borderRadius(12)
                    .onClick(() => {
                      this.handleOptionSelect(optionId)
                    })
                }
              }, (optionId: string, idx: number) => `shape_opt_${idx}_${optionId}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
          } else if (this.showResult) {
            Text(this.isCorrect
              ? `对啦，这是「${this.target !== null ? this.target.short : ''}」的轮廓。`
              : `这是「${this.target !== null ? this.target.short : ''}」的轮廓，记住它的样子。`)
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
