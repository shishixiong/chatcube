// entry/src/main/ets/components/city/CityEnglishCard.ets
/**
 * CityEnglishCard - 小词城 3D 英语探索（city_english 工具，讲解型）
 *
 * 渲染层：Web 容器加载 rawfile/city3d/index.html（three.js 0.185 本地内置，离线可用）。
 * 原型来自 open-design 的 word-city：120m × 90m 低多边形小城——东西向主街、四个街区、
 * 河流与中央广场，50 个可点击对象（地点 12 / 交通 10 / 街道 9 / 人物 8 / 自然 8 / 动物 3），
 * 公交车、汽车、自行车与行人沿道路循环，路口红绿灯按 25s 周期切换；5 个分区镜头
 * （全城 / 商业街 / 学校 / 公园 / 医院）；单词卡（英文 / 音标 / 中文 / 儿童解释 / 例句）、
 * 英文标签、词汇表与进度点阵。
 *
 * 原生职责：
 *  - TTS 发音（ArkWeb 没有 speechSynthesis，走 CityNativeBridge.speak → ServiceRegistry.tts；
 *    点击物品即自动朗读，单词卡「听发音」按钮保留作重播；语速 0.8 略慢便于跟读）
 *  - 原生标题栏（词汇表 / 夜灯 / 我学会了）与进度统计（桥上报 onProgress）
 * 讲解型工具不授星（与 map_card / room_english 一致），星星由后续 english_quiz 给。
 */

import { UIContext } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { ToolCall } from '../../models/ChatModels'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  CityEnglishValidationResult,
  resolveCityEnglishView,
  validateCityEnglishArgs
} from '../../utils/CityEnglishValidation'

// 与 mermaid / document-parser / room3d 同法：rawfile 里的本地页面用 resource:// 加载，
// 页面内相对路径（assets/three.min.js 等）由 ArkWeb 按同源解析。
const CITY_ENGLISH_PAGE_URL: string = 'resource://rawfile/city3d/index.html'
// 与 rawfile/city3d/assets/city-data.js 的单词总数保持一致
// （地点 12 + 交通 10 + 街道 9 + 人物 8 + 自然 8 + 动物 3）
const CITY_OBJECT_TOTAL: number = 50

/** 单词朗读语速：三个引擎（system/minimax/stepfun）通用范围 [0.5, 2]，0.8 略慢便于孩子跟读 */
const CITY_WORD_TTS_SPEED: number = 0.8

/** 完成回执：写进 toolCall.approvalReason，随 ToolResult 回给 AI。 */
export interface CityEnglishAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  focus: string
  skill_key: string
  cancelled: boolean
}

export interface CityEnglishArgsView {
  valid: boolean
  focus: string
  words: string[]
}

function createArgsView(): CityEnglishArgsView {
  const view: CityEnglishArgsView = { valid: false, focus: 'overview', words: [] }
  return view
}

export function parseCityEnglishArgs(raw: string): CityEnglishArgsView {
  const result: CityEnglishValidationResult = validateCityEnglishArgs(raw)
  const view: CityEnglishArgsView = createArgsView()
  view.valid = result.ok
  view.focus = result.focus
  view.words = result.words
  return view
}

/**
 * ArkWeb javaScriptProxy 注入对象。Web 侧通过 window.CityNativeBridge.xxx() 调用，
 * 见 rawfile/city3d/assets/city-app.js 里的 bridgeCall。
 */
class CityNativeBridge {
  speakHandler: (text: string, zh: string) => boolean = (): boolean => false
  stopHandler: () => void = (): void => {}
  readyHandler: () => void = (): void => {}
  selectHandler: (id: string, word: string) => void = (): void => {}
  progressHandler: (idsJson: string) => void = (): void => {}

  // 返回值统一用字符串：ArkWeb 代理方法对返回类型最宽容，且 Web 侧只判断真值。
  // zh 为物品的中文意思（可空）：原生先读中文、再读英文单词。
  speak(text: string, zh: string): string {
    const meaning: string = zh ? zh : ''
    return this.speakHandler(text, meaning) ? 'true' : 'false'
  }

  stopSpeak(): string {
    this.stopHandler()
    return 'true'
  }

  onReady(): string {
    this.readyHandler()
    return 'true'
  }

  onSelect(id: string, word: string): string {
    this.selectHandler(id, word)
    return 'true'
  }

  onProgress(idsJson: string): string {
    this.progressHandler(idsJson)
    return 'true'
  }
}

@ComponentV2
export struct CityEnglishCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  @Local argsView: CityEnglishArgsView = createArgsView()
  @Local exploredIds: string[] = []
  @Local pageReady: boolean = false
  @Local sceneFailed: boolean = false
  @Local speaking: boolean = false
  @Local hasCompleted: boolean = false
  @Local nightOn: boolean = false

  private lookup: Map<string, string> = new Map<string, string>()
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: CityNativeBridge = new CityNativeBridge()
  private submitted: boolean = false
  private focusApplied: boolean = false
  // Web 代理回调可能不在 UI 线程；状态写回统一 runScopedTask 到 UI 上下文。
  private uiContext: UIContext | null = null

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get exploredCount(): number {
    return this.exploredIds.length
  }

  /** 已探索 id → 英文单词（本次会话点过的才在 lookup 里，历史 id 退回 id）。 */
  private get exploredWords(): string[] {
    const out: string[] = []
    for (let i = 0; i < this.exploredIds.length; i++) {
      const id = this.exploredIds[i]
      const word = this.lookup.get(id)
      out.push(word !== undefined ? word : id)
    }
    return out
  }

  aboutToAppear(): void {
    this.uiContext = this.getUIContext()
    this.argsView = parseCityEnglishArgs(this.toolCall.arguments)
    this.bridge.speakHandler = (text: string, zh: string): boolean => this.speakWord(text, zh)
    this.bridge.stopHandler = (): void => this.stopSpeak()
    this.bridge.readyHandler = (): void => {
      this.runOnUi((): void => {
        this.pageReady = true
      })
    }
    this.bridge.selectHandler = (id: string, word: string): void => {
      this.runOnUi((): void => {
        this.noteSelected(id, word)
      })
    }
    this.bridge.progressHandler = (idsJson: string): void => {
      this.runOnUi((): void => {
        this.applyProgress(idsJson)
      })
    }
    if (this.isAnswered) {
      this.readAnsweredPayload()
    }
  }

  aboutToDisappear(): void {
    this.stopSpeak()
  }

  private runOnUi(task: () => void): void {
    const ctx = this.uiContext
    if (ctx !== null) {
      try {
        ctx.runScopedTask(task)
        return
      } catch (_e) {
        // 退回到直接执行
      }
    }
    task()
  }

  // ====== 桥回调 ======

  private noteSelected(id: string, word: string): void {
    if (id === '') {
      return
    }
    if (word !== '') {
      this.lookup.set(id, word)
    }
    if (this.exploredIds.indexOf(id) >= 0) {
      return
    }
    const nextIds: string[] = []
    for (let i = 0; i < this.exploredIds.length; i++) {
      nextIds.push(this.exploredIds[i])
    }
    nextIds.push(id)
    this.exploredIds = nextIds
  }

  private applyProgress(idsJson: string): void {
    try {
      const parsed = JSON.parse(idsJson) as Object[]
      const next: string[] = []
      if (Array.isArray(parsed)) {
        for (let i = 0; i < parsed.length; i++) {
          const item = parsed[i]
          if (typeof item === 'string') {
            next.push(item as string)
          }
        }
      }
      this.exploredIds = next
    } catch (_e) {
      // 解析失败保留现状，不影响浏览
    }
  }

  private speakWord(text: string, zh: string): boolean {
    try {
      ServiceRegistry.tts().stop()
      this.runOnUi((): void => {
        this.speaking = true
      })
      const speakEnglish: () => void = (): void => {
        this.runOnUi((): void => {
          this.speaking = true
        })
        ServiceRegistry.tts().speak(text, {
          onStart: (): void => {
            this.runOnUi((): void => {
              this.speaking = true
            })
          },
          onComplete: (): void => {
            this.runOnUi((): void => {
              this.speaking = false
            })
          },
          onError: (error: string): void => {
            this.runOnUi((): void => {
              this.speaking = false
            })
            console.error('CityEnglishCard', `tts error: ${error}`)
          }
        }, CITY_WORD_TTS_SPEED).catch((e: Error) => {
          this.runOnUi((): void => {
            this.speaking = false
          })
          console.error('CityEnglishCard', `tts speak failed: ${e.message}`)
        })
      }

      if (zh === '') {
        speakEnglish()
        return true
      }

      // 先念中文意思（“医院”），念完接着念英文单词（“hospital”）
      ServiceRegistry.tts().speak(zh, {
        onStart: (): void => {
          this.runOnUi((): void => {
            this.speaking = true
          })
        },
        onComplete: (): void => {
          speakEnglish()
        },
        onError: (error: string): void => {
          console.error('CityEnglishCard', `tts zh error: ${error}`)
          speakEnglish()
        }
      }, CITY_WORD_TTS_SPEED).catch((e: Error) => {
        this.runOnUi((): void => {
          this.speaking = false
        })
        console.error('CityEnglishCard', `tts zh speak failed: ${e.message}`)
        speakEnglish()
      })
      return true
    } catch (e) {
      this.runOnUi((): void => {
        this.speaking = false
      })
      return false
    }
  }

  private stopSpeak(): void {
    this.speaking = false
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
  }

  // ====== 已答态（时间线回看） ======

  private readAnsweredPayload(): void {
    try {
      const prev = JSON.parse(this.answeredPayload) as Record<string, Object>
      this.hasCompleted = prev['completed'] === true
      const words = prev['words'] as Object[]
      if (words !== undefined && words !== null && Array.isArray(words)) {
        const next: string[] = []
        for (let i = 0; i < words.length; i++) {
          const item = words[i]
          if (typeof item === 'string') {
            next.push(item as string)
          }
        }
        this.exploredIds = next
      }
    } catch (_e) {
      this.hasCompleted = false
    }
  }

  // ====== Web 控制 ======

  private runWeb(script: string): Promise<string> {
    try {
      return this.controller.runJavaScript(script)
    } catch (e) {
      return Promise.reject(e)
    }
  }

  /** 页面就绪后：切宿主模式（隐藏网页顶栏）、切到 focus 指定的街区、高亮第一个重点词。
   *  英文标签默认关闭，由孩子在场景里手动打开。 */
  private applyFocusWords(): void {
    if (this.focusApplied || !this.pageReady) {
      return
    }
    const view = resolveCityEnglishView(this.argsView.focus)
    const first = this.argsView.words.length > 0 ? `'${this.argsView.words[0]}'` : 'null'
    this.focusApplied = true
    const script = `(function(){try{var app=window.WordCityApp;if(!app){return;}app.setHostMode(true);app.setView('${view}');` +
      `if(${first}){app.select(${first});}}catch(e){}})();`
    this.controller.runJavaScript(script).catch((e: Error) => {
      console.error('CityEnglishCard', `apply focus words failed: ${e.message}`)
    })
  }

  private openVocab(): void {
    this.runWeb('(function(){try{var app=window.WordCityApp;if(app){app.openVocab();}}catch(e){}})();')
      .catch((e: Error): void => {
        console.error('CityEnglishCard', 'open vocab failed: ' + e.message)
      })
  }

  private toggleNight(): void {
    this.nightOn = !this.nightOn
    const on = this.nightOn ? 'true' : 'false'
    this.runWeb(`(function(){try{var app=window.WordCityApp;if(app){app.setNight(${on});}}catch(e){}})();`)
      .catch((e: Error): void => {
        console.error('CityEnglishCard', 'set night failed: ' + e.message)
      })
  }

  private retryLoad(): void {
    this.sceneFailed = false
    this.pageReady = false
    this.focusApplied = false
    try {
      this.controller.refresh()
    } catch (e) {
      console.error('CityEnglishCard', `refresh failed: ${String(e)}`)
    }
  }

  // ====== 提交 ======

  private buildPayload(completed: boolean, cancelled: boolean): CityEnglishAnswerPayload {
    const words: string[] = []
    for (let i = 0; i < this.exploredIds.length; i++) {
      words.push(this.exploredIds[i])
    }
    const payload: CityEnglishAnswerPayload = {
      completed: completed,
      explored_count: words.length,
      words: words,
      focus: this.argsView.focus,
      skill_key: 'english_vocab',
      cancelled: cancelled
    }
    return payload
  }

  private canSubmit(): boolean {
    return !this.isAnswered && !this.submitted && this.exploredCount > 0
  }

  private submit(): void {
    if (!this.canSubmit()) {
      return
    }
    this.submitted = true
    const payload: CityEnglishAnswerPayload = this.buildPayload(true, false)
    this.stopSpeak()
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  // ====== UI ======

  private get headerSubtitle(): string {
    if (this.exploredCount > 0) {
      return `已探索 ${this.exploredCount} / ${CITY_OBJECT_TOTAL} 个单词`
    }
    return '主街、学校、公园、医院，点一点就知道它叫什么'
  }

  private get headerActionLabel(): string {
    return this.exploredCount > 0 ? '我学会了' : '先探索一下'
  }

  private get headerActionEnabled(): boolean {
    return this.canSubmit()
  }

  private handleHeaderAction(): void {
    this.submit()
  }

  @Builder
  HeaderBar() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text('小词城 3D 英语探索')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.headerSubtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Capsule }) {
        Text('词汇表')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      }
      .height(30)
      .padding({ left: 10, right: 10 })
      .backgroundColor(withColorAlpha(this.themePrimary, '14'))
      .onClick(() => {
        this.openVocab()
      })

      Button({ type: ButtonType.Circle }) {
        Text(this.nightOn ? '☀️' : '🌙')
          .fontSize(13)
      }
      .width(30)
      .height(30)
      .backgroundColor(withColorAlpha(this.themePrimary, '14'))
      .onClick(() => {
        this.toggleNight()
      })

      Button({ type: ButtonType.Capsule }) {
        Text(this.headerActionLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.headerActionEnabled ? Color.White : $r('app.color.text_tertiary'))
      }
      .height(32)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.headerActionEnabled ? this.themePrimary : withColorAlpha(this.themePrimary, '14'))
      .enabled(this.headerActionEnabled)
      .onClick(() => {
        this.handleHeaderAction()
      })
    }
    .width('100%')
    .padding({ left: 16, right: 44, top: 8, bottom: 8 })
  }

  @Builder
  SummaryView() {
    Column({ space: 10 }) {
      Text(this.hasCompleted ? '小词城探索完成' : '这次没有探索完')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(`一共点开了 ${this.exploredCount} 个单词`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      if (this.exploredWords.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.exploredWords, (word: string) => {
            Text(word)
              .fontSize(12)
              .fontColor(this.themePrimary)
              .backgroundColor(withColorAlpha(this.themePrimary, '14'))
              .borderRadius(10)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .margin({ right: 6, bottom: 6 })
          }, (word: string) => 'city_word_' + word)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (this.isAnswered) {
        this.SummaryView()
      } else {
        this.HeaderBar()

        Stack({ alignContent: Alignment.Center }) {
          Web({ src: CITY_ENGLISH_PAGE_URL, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(false)
            .horizontalScrollBarAccess(false)
            .verticalScrollBarAccess(false)
            .backgroundColor(this.isDarkMode ? '#101614' : '#f4f8f5')
            .javaScriptProxy({
              object: this.bridge,
              name: 'CityNativeBridge',
              methodList: ['speak', 'stopSpeak', 'onReady', 'onSelect', 'onProgress'],
              controller: this.controller
            })
            .onPageEnd(() => {
              this.pageReady = true
              this.sceneFailed = false
              if (!this.isAnswered) {
                this.applyFocusWords()
              }
            })
            .onErrorReceive(() => {
              this.sceneFailed = true
            })

          if (!this.pageReady && !this.sceneFailed) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(this.themePrimary)
              Text('正在搭建小词城…')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
          }

          if (this.sceneFailed) {
            Column({ space: 12 }) {
              Text('3D 小城没有打开')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('可以点下面的按钮重新加载，或者先回到对话里。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Button({ type: ButtonType.Capsule }) {
                Text('重新加载')
                  .fontSize(13)
                  .fontColor(Color.White)
              }
              .height(32)
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.themePrimary)
              .onClick(() => {
                this.retryLoad()
              })
            }
            .padding(20)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(16)
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? '#101614' : '#f4f8f5')
  }
}
