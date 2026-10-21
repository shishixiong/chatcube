// entry/src/main/ets/components/map/bodies/MapLocateBody.ets
/**
 * MapLocateBody - map_quiz locate 题型 body（在地图上点出目标省）
 *
 * 题干：clue=name → 「在地图上找到：{short}」；clue=capital → 「行政中心是「X」的是哪个省？」
 * （capital===short 的直辖市/特区已在预校验拒绝，防御性回落 name）。即判即交：
 * 点对 → correctId 绿环 + 「找对位置啦！」；点错 → target 金 + wrong 红 +
 * 原型教学文案（本省简称/行政中心 + 孩子点的是谁）。一次作答，无重试。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../../state/AppUiState'
import { ToolCall } from '../../../models/ChatModels'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { ChinaMapData, ChinaProvince, findProvinceByRef, getCachedChinaMapData, loadChinaMapData } from '../../../utils/ChinaMapData'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { KIDS_MUTED } from '../../kids/KidsBrandTokens'
import { ChinaMapStage } from '../ChinaMapStage'
import { MapQuizAnswerPayload, MapQuizArgsView, parseMapQuizArgs } from '../MapQuizTypes'

@ComponentV2
export struct MapLocateBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local data: ChinaMapData | null = null
  @Local targetId: string = ''
  @Local correctId: string = ''
  @Local wrongId: string = ''
  @Local stem: string = ''
  @Local targetShort: string = ''
  @Local targetName: string = ''
  @Local targetAbbr: string = ''
  @Local targetCapital: string = ''
  @Local skillKey: string = 'general_social'
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local feedbackText: string = ''
  @Local answeredShort: string = ''

  private argsView: MapQuizArgsView = parseMapQuizArgs('')
  private submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图出题', subtitle: '找省份', icon: $r('sys.symbol.map'),
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
        this.showResult = true
        this.isCorrect = prev.correct
        this.answeredShort = prev.child_answer
        this.feedbackText = prev.correct ? '找对位置啦！' : this.feedbackText
        if (prev.correct) {
          this.correctId = prev.province_id
        } else {
          this.targetId = prev.province_id
          const picked = findProvinceByRef(this.allProvinces(), prev.child_answer)
          this.wrongId = picked !== null ? picked.id : ''
          const target = this.provinceById(prev.province_id)
          if (target !== null) {
            this.feedbackText = this.buildWrongFeedback(target, prev.child_answer)
          }
        }
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

  private allProvinces(): ChinaProvince[] {
    const data = this.data
    return data !== null ? data.provinces : []
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
    this.targetName = target.name
    this.targetAbbr = target.abbr
    this.targetCapital = target.capital
    this.skillKey = this.argsView.skillKey
    // clue=capital 且 capital===short 时回落 name（预校验已拦，防御兜底）
    if (this.argsView.clue === 'capital' && target.capital !== target.short) {
      this.stem = `行政中心是「${target.capital}」的是哪个省？`
    } else {
      this.stem = `在地图上找到：${target.short}`
    }
  }

  private provinceById(id: string): ChinaProvince | null {
    for (const p of this.allProvinces()) {
      if (p.id === id) {
        return p
      }
    }
    return null
  }

  private buildWrongFeedback(target: ChinaProvince, pickedShort: string): string {
    return `这里是${target.name}，简称${target.abbr}，行政中心在${target.capital}。你点的是${pickedShort}。`
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

  private handlePickProvince(provinceId: string): void {
    if (this.isAnswered || this.showResult || this.submitted) {
      return
    }
    const target = this.provinceById(this.targetId)
    const picked = this.provinceById(provinceId)
    if (target === null || picked === null) {
      return
    }
    const correct = provinceId === this.targetId
    this.showResult = true
    this.isCorrect = correct
    this.answeredShort = picked.short
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct
    if (correct) {
      this.correctId = provinceId
      this.feedbackText = '找对位置啦！'
    } else {
      this.wrongId = provinceId
      this.feedbackText = this.buildWrongFeedback(target, picked.short)
    }

    const payload: MapQuizAnswerPayload = {
      answered: true,
      mode: 'locate',
      province: target.short,
      province_id: target.id,
      clue: this.argsView.clue,
      child_answer: picked.short,
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
          Text(this.stem)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Column() {
            ChinaMapStage({
              data: this.data,
              targetId: this.showResult && !this.isCorrect ? this.targetId : '',
              correctId: this.correctId,
              wrongId: this.wrongId,
              interactive: !this.isAnswered && !this.showResult,
              onPickProvince: (provinceId: string): void => this.handlePickProvince(provinceId)
            })
          }
          .width('100%')
          .height(300)
          .borderRadius(12)
          .clip(true)
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '0A' : '06'))

          if (this.showResult && this.feedbackText !== '') {
            Text(this.feedbackText)
              .fontSize(14)
              .fontColor(this.isCorrect ? $r('app.color.status_success') : $r('app.color.text_secondary'))
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
