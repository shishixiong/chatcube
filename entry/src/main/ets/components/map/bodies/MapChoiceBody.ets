// entry/src/main/ets/components/map/bodies/MapChoiceBody.ets
/**
 * MapChoiceBody - map_quiz choice 题型 body
 *
 * 金色 target 地图 + 「看地图上金色的省份，选一选它的名字。」+ 2×2 简称选项。
 * 选项由 pickMapChoiceOptions 程序生成（同大区偏好 + 洗牌），AI 不传选项——
 * 即判即交镜像 ChineseChoiceBody（点选 → 绿/红 + 地图 correctId 环 → onAnswer）。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../../state/AppUiState'
import { ToolCall } from '../../../models/ChatModels'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { ChinaMapData, ChinaProvince, findProvinceByRef, getCachedChinaMapData, loadChinaMapData } from '../../../utils/ChinaMapData'
import { pickMapChoiceOptions } from '../../../utils/MapChoiceOptions'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { KIDS_MUTED } from '../../kids/KidsBrandTokens'
import { ChinaMapStage } from '../ChinaMapStage'
import { MapQuizAnswerPayload, MapQuizArgsView, parseMapQuizArgs } from '../MapQuizTypes'

@ComponentV2
export struct MapChoiceBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local data: ChinaMapData | null = null
  @Local targetId: string = ''
  @Local correctId: string = ''
  @Local wrongId: string = ''
  @Local optionIds: string[] = []
  @Local targetShort: string = ''
  @Local targetCapital: string = ''
  @Local skillKey: string = 'general_social'
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local selectedId: string = ''

  private argsView: MapQuizArgsView = parseMapQuizArgs('')
  private submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图出题', subtitle: '选名字', icon: $r('sys.symbol.map'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
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
        this.correctId = prev.correct ? prev.province_id : ''
        this.wrongId = prev.correct ? '' : prev.child_answer
        this.shellState.submitted = true
        this.shellState.hasSelection = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      } else {
        // payload 缺失/不可解析: 无法判定当时对错, 抑制反馈横幅 (ChineseChoiceBody 同款守卫)
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
    this.targetId = target.id
    this.targetShort = target.short
    this.targetCapital = target.capital
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
    const target = this.provinceById(this.targetId)
    if (target === null) {
      return
    }
    const correct = optionId === this.targetId
    this.selectedId = optionId
    this.showResult = true
    this.isCorrect = correct
    this.correctId = correct ? optionId : ''
    this.wrongId = correct ? '' : optionId
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct

    const payload: MapQuizAnswerPayload = {
      answered: true,
      mode: 'choice',
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
      correctAnswerText: this.targetShort,
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 10 }) {
        if (this.data !== null && this.targetId !== '') {
          Column() {
            ChinaMapStage({
              data: this.data,
              targetId: this.targetId,
              correctId: this.correctId,
              wrongId: this.wrongId,
              interactive: false
            })
          }
          .width('100%')
          .height(220)
          .borderRadius(12)
          .clip(true)
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '0A' : '06'))

          Text('看地图上金色的省份，选一选它的名字。')
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
              }, (optionId: string, idx: number) => `opt_${idx}_${optionId}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
          } else if (this.showResult && !this.isCorrect) {
            Text(`正确答案：${this.targetShort}`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
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
      .backgroundColor(this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12'))
      .borderRadius(10)
    }
  }
}
