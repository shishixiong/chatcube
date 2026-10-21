// entry/src/main/ets/components/map/MapCard.ets
/**
 * MapCard - 中国地图小课堂（map_card 工具，讲解型回执）
 *
 * 镜像 HanziCard 范式：CardShell 外壳 + feedbackSuppressed 永久抑制反馈横幅，
 * 无对错判定，孩子探索地图（focus 省自动展示 / 自由点选）后点「我学会了 · 继续」
 * 提交完成回执 → computeStars: completed=true → 1 星。
 * 省份资料卡：region 徽章 + 简称大字 + abbr 印章 + 行政中心 + 🔊 TTS 朗读。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../state/AppUiState'
import { ToolCall } from '../../models/ChatModels'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { ChinaMapData, ChinaProvince, findProvinceByRef, loadChinaMapData } from '../../utils/ChinaMapData'
import { CardShell } from '../cardshell/CardShell'
import { CardShellConfig } from '../cardshell/CardShellTypes'
import { CardShellState } from '../cardshell/CardShellState'
import { KIDS_MUTED } from '../kids/KidsBrandTokens'
import { ChinaMapStage } from './ChinaMapStage'

export interface MapCardResult {
  completed: boolean
  focus_province: string
  explored_count: number
  skill_key: string
}

export interface MapCardArgsView {
  valid: boolean
  focusProvince: string
  skillKey: string
}

function createDefaultArgsView(): MapCardArgsView {
  const view: MapCardArgsView = { valid: false, focusProvince: '', skillKey: 'general_social' }
  return view
}

export function parseMapCardArgs(raw: string): MapCardArgsView {
  const view: MapCardArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    view.valid = true
    const focus: Object | undefined = obj['focus_province']
    if (typeof focus === 'string') {
      view.focusProvince = (focus as string).trim()
    }
    const skill: Object | undefined = obj['skill_key']
    if (typeof skill === 'string' && (skill as string).trim() !== '') {
      view.skillKey = (skill as string).trim()
    }
  } catch (_e) {
    return createDefaultArgsView()
  }
  return view
}

@ComponentV2
export struct MapCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  @Local argsView: MapCardArgsView = createDefaultArgsView()
  @Local data: ChinaMapData | null = null
  @Local focusId: string = ''
  @Local selectedId: string = ''
  @Local currentInfo: ChinaProvince | null = null
  @Local exploredCount: number = 0

  private submitted: boolean = false
  private hasCompleted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图小课堂', subtitle: '', icon: $r('sys.symbol.map'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '学完啦！', correctAnswerLabel: ''
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    this.argsView = parseMapCardArgs(this.toolCall.arguments)
    this.shellState.feedbackSuppressed = true
    if (this.isAnswered) {
      try {
        const prev = JSON.parse(this.answeredPayload) as Record<string, Object>
        this.hasCompleted = prev['completed'] === true
      } catch (_e) {
        this.hasCompleted = false
      }
    }
    const ctx = getContext(this) as common.UIAbilityContext
    loadChinaMapData(ctx).then((loaded: ChinaMapData | null) => {
      if (loaded === null) {
        return
      }
      this.data = loaded
      if (this.argsView.focusProvince !== '') {
        const focus = findProvinceByRef(loaded.provinces, this.argsView.focusProvince)
        if (focus !== null) {
          this.focusId = focus.id
          this.selectedId = focus.id
          this.currentInfo = focus
          this.noteExplored()
        }
      }
    }).catch((_e: Error) => {
    })
  }

  aboutToDisappear(): void {
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
  }

  private noteExplored(): void {
    // 探索计数：每省只计一次（focus 已展示也算探索过）
    if (this.currentInfo === null) {
      return
    }
    // exploredCount 以「当前展示省是否已计」为界——卡片会话内简单以 1 起步、点新省递增
    if (this.exploredCount === 0) {
      this.exploredCount = 1
    }
  }

  private handlePickProvince(provinceId: string): void {
    if (this.isAnswered || this.data === null) {
      return
    }
    let picked: ChinaProvince | null = null
    for (const p of this.data.provinces) {
      if (p.id === provinceId) {
        picked = p
        break
      }
    }
    if (picked === null) {
      return
    }
    const isNew = this.selectedId !== provinceId
    this.selectedId = provinceId
    this.currentInfo = picked
    if (isNew) {
      this.exploredCount = this.exploredCount + 1
    } else if (this.exploredCount === 0) {
      this.exploredCount = 1
    }
  }

  // ====== TTS 朗读（HanziCard narrateLesson 同通道） ======

  private speakProvinceInfo(): void {
    const info = this.currentInfo
    if (info === null) {
      return
    }
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
    ServiceRegistry.tts().speak(`${info.name}。简称${info.abbr}。行政中心${info.capital}。`, {
      onStart: () => {},
      onComplete: () => {},
      onError: (error: string) => {
        console.error('MapCard', `province info TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      console.error('MapCard', `province info TTS speak failed: ${e.message}`)
    })
  }

  // ====== 提交 ======

  private canSubmit(): boolean {
    return this.exploredCount > 0
  }

  private submit(): void {
    if (this.submitted || !this.canSubmit() || this.isAnswered) {
      return
    }
    this.submitted = true
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
    const result: MapCardResult = {
      completed: true,
      focus_province: this.argsView.focusProvince,
      explored_count: this.exploredCount,
      skill_key: this.argsView.skillKey
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  // ====== 省份资料卡 ======

  @Builder
  ProvinceInfoCard() {
    if (this.currentInfo !== null) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(this.currentInfo.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.currentInfo.region)
            .fontSize(11)
            .fontColor(this.themePrimary)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '1F' : '14'))
            .borderRadius(8)
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Text('🔊').fontSize(14)
          }
          .width(30)
          .height(30)
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '1F' : '12'))
          .onClick(() => this.speakProvinceInfo())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Text(this.currentInfo.short)
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themePrimary)
          Text(`简称「${this.currentInfo.abbr}」`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(8)
            .border({ width: 1, color: withColorAlpha(this.themePrimary, '4D') })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`行政中心：${this.currentInfo.capital}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '12' : '0A'))
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ControlArea() {
    if (this.isAnswered) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14)
          .fontColor([$r('app.color.status_success')])
        Text('已学会')
          .fontSize(13)
          .fontColor($r('app.color.status_success'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    } else if (this.argsView.valid) {
      Button('我学会了 · 继续')
        .width('100%').height(44)
        .fontSize(15)
        .backgroundColor(this.canSubmit() ? this.themePrimary : withColorAlpha(this.themePrimary, '33'))
        .fontColor(Color.White)
        .enabled(this.canSubmit())
        .opacity(this.canSubmit() ? 1 : 0.55)
        .onClick(() => {
          this.submit()
        })
    }
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: '',
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 12 }) {
        if (this.argsView.valid) {
          Column() {
            ChinaMapStage({
              data: this.data,
              targetId: this.focusId,
              selectedId: this.selectedId,
              interactive: !this.isAnswered,
              onPickProvince: (provinceId: string): void => this.handlePickProvince(provinceId)
            })
          }
          .width('100%')
          .height(260)
          .borderRadius(12)
          .clip(true)
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '0A' : '06'))

          this.ProvinceInfoCard()
          this.ControlArea()
        } else {
          Text('这张地图出错了，老师马上换一张')
            .fontSize(14).fontColor(KIDS_MUTED)
            .padding({ top: 8, bottom: 8 })
        }
      }
      .width('100%')
    }
  }
}
