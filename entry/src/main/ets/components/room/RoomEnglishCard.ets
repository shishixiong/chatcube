// entry/src/main/ets/components/room/RoomEnglishCard.ets
/**
 * RoomEnglishCard - 3D 五间房英语探索（room_english 工具，讲解型）
 *
 * 渲染层：Web 容器加载 rawfile/room3d/index.html（three.js 0.185 本地内置，离线可用）。
 * 原型来自 open-design 的 kids-room-3d-english + kids-3d-bedrooms-wing + wet-room：五间低多边形房间
 * （11.8m × 6m 客餐厅 + 开放厨房、4.4m × 3.6m 儿童房、4.6m × 3.6m 主卧、2.4m × 2.0m 卫生间、
 * 3.6m × 1.4m 阳台）、85 件可点击物品，
 * 房卡顶部切换房间；单词卡（英文 / 音标 / 中文 / 儿童解释 / 例句）、英文标签、词汇表与进度点阵。
 *
 * 原生职责：
 *  - TTS 发音（ArkWeb 没有 speechSynthesis，走 RoomNativeBridge.speak → ServiceRegistry.tts；
 *    点击物品即自动朗读，单词卡「听发音」按钮保留作重播；语速 0.8 略慢便于跟读）
 *  - 进度统计（桥上报 onProgress）与「我学会了」完成回执（payload 回写 AI）
 * 讲解型工具不授星（与 map_card 一致），星星由后续 english_quiz / matching_pairs 给。
 */

import { UIContext } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { ToolCall } from '../../models/ChatModels'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { RoomEnglishValidationResult, validateRoomEnglishArgs } from '../../utils/RoomEnglishValidation'

// 与 mermaid / document-parser 同法：rawfile 里的本地页面用 resource:// 加载，
// 页面内相对路径（assets/three.min.js 等）由 ArkWeb 按同源解析。
const ROOM_ENGLISH_PAGE_URL: string = 'resource://rawfile/room3d/index.html'
// 与 rawfile/room3d/assets/scene-data.js 的物品总数保持一致
// （客厅 15 + 餐厅 10 + 厨房 12 + 儿童房 12 + 主卧 12 + 卫生间 12 + 阳台 12）
const ROOM_OBJECT_TOTAL: number = 85

/** 单词朗读语速：三个引擎（system/minimax/stepfun）通用范围 [0.5, 2]，0.8 略慢便于孩子跟读 */
const ROOM_WORD_TTS_SPEED: number = 0.8

/** 完成回执：写进 toolCall.approvalReason，随 ToolResult 回给 AI。 */
export interface RoomEnglishAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  focus: string
  skill_key: string
  cancelled: boolean
}

export interface RoomEnglishArgsView {
  valid: boolean
  focus: string
  words: string[]
}

function createArgsView(): RoomEnglishArgsView {
  const view: RoomEnglishArgsView = { valid: false, focus: 'all', words: [] }
  return view
}

export function parseRoomEnglishArgs(raw: string): RoomEnglishArgsView {
  const result: RoomEnglishValidationResult = validateRoomEnglishArgs(raw)
  const view: RoomEnglishArgsView = createArgsView()
  view.valid = result.ok
  view.focus = result.focus
  view.words = result.words
  return view
}

/**
 * ArkWeb javaScriptProxy 注入对象。Web 侧通过 window.RoomNativeBridge.xxx() 调用，
 * 见 rawfile/room3d/assets/room-app.js 里的 bridgeCall。
 */
class RoomNativeBridge {
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
export struct RoomEnglishCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  @Local argsView: RoomEnglishArgsView = createArgsView()
  @Local exploredIds: string[] = []
  @Local exploredWords: string[] = []
  @Local pageReady: boolean = false
  @Local sceneFailed: boolean = false
  @Local speaking: boolean = false
  @Local hasCompleted: boolean = false

  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: RoomNativeBridge = new RoomNativeBridge()
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

  aboutToAppear(): void {
    this.uiContext = this.getUIContext()
    this.argsView = parseRoomEnglishArgs(this.toolCall.arguments)
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
    if (id === '' || this.exploredIds.indexOf(id) >= 0) {
      return
    }
    const nextIds: string[] = []
    for (let i = 0; i < this.exploredIds.length; i++) {
      nextIds.push(this.exploredIds[i])
    }
    nextIds.push(id)
    const nextWords: string[] = []
    for (let i = 0; i < this.exploredWords.length; i++) {
      nextWords.push(this.exploredWords[i])
    }
    nextWords.push(word !== '' ? word : id)
    this.exploredIds = nextIds
    this.exploredWords = nextWords
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
            console.error('RoomEnglishCard', `tts error: ${error}`)
          }
        }, ROOM_WORD_TTS_SPEED).catch((e: Error) => {
          this.runOnUi((): void => {
            this.speaking = false
          })
          console.error('RoomEnglishCard', `tts speak failed: ${e.message}`)
        })
      }

      if (zh === '') {
        speakEnglish()
        return true
      }

      // 先念中文意思（“冰箱”），念完接着念英文单词（“fridge”）
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
          console.error('RoomEnglishCard', `tts zh error: ${error}`)
          speakEnglish()
        }
      }, ROOM_WORD_TTS_SPEED).catch((e: Error) => {
        this.runOnUi((): void => {
          this.speaking = false
        })
        console.error('RoomEnglishCard', `tts zh speak failed: ${e.message}`)
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
        this.exploredWords = next
      }
    } catch (_e) {
      this.hasCompleted = false
    }
  }

  // ====== Web 控制 ======

  /** focus 落在某个独立房间时，直接把这间房打开（living / dining / kitchen 都在客餐厅里）。 */
  private focusRoom(): string {
    const focus = this.argsView.focus
    if (focus === 'child' || focus === 'master' || focus === 'bathroom' || focus === 'balcony') {
      return focus
    }
    return 'main'
  }

  /** 页面就绪后：先切到 focus 指定的房间，再把本次重点单词的第一件物品高亮出来（选中即自动朗读）。
   *  英文标签默认不显示，由孩子点场景里的「显示英文标签」开关手动打开。 */
  private applyFocusWords(): void {
    if (this.focusApplied || !this.pageReady) {
      return
    }
    const room = this.focusRoom()
    const first = this.argsView.words.length > 0 ? `'${this.argsView.words[0]}'` : 'null'
    if (room === 'main' && first === 'null') {
      return
    }
    this.focusApplied = true
    const script = `(function(){try{var app=window.WordRoomApp;if(!app){return;}app.setRoom('${room}');` +
      `if(${first}){app.select(${first});}}catch(e){}})();`
    this.controller.runJavaScript(script).catch((e: Error) => {
      console.error('RoomEnglishCard', `apply focus words failed: ${e.message}`)
    })
  }

  private retryLoad(): void {
    this.sceneFailed = false
    this.pageReady = false
    try {
      this.controller.refresh()
    } catch (e) {
      console.error('RoomEnglishCard', `refresh failed: ${String(e)}`)
    }
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
    const payload: RoomEnglishAnswerPayload = {
      completed: true,
      explored_count: this.exploredCount,
      words: this.exploredIds,
      focus: this.argsView.focus,
      skill_key: 'english_vocab',
      cancelled: false
    }
    this.stopSpeak()
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  // ====== UI ======

  @Builder
  HeaderBar() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('3D 房间英语探索')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.exploredCount > 0
          ? `已收集 ${this.exploredCount} / ${ROOM_OBJECT_TOTAL} 个单词`
          : '客餐厅、厨房、儿童房、主卧、卫生间、阳台，点一点就知道它叫什么')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Capsule }) {
        Text(this.exploredCount > 0 ? '我学会了' : '先探索一下')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.canSubmit() ? Color.White : $r('app.color.text_tertiary'))
      }
      .height(32)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.canSubmit() ? this.themePrimary : withColorAlpha(this.themePrimary, '14'))
      .enabled(this.canSubmit() && !this.isAnswered)
      .onClick(() => {
        this.submit()
      })
    }
    .width('100%')
    .padding({ left: 16, right: 44, top: 8, bottom: 8 })
  }

  @Builder
  SummaryView() {
    Column({ space: 10 }) {
      Text(this.hasCompleted ? '房间探索完成' : '这次没有探索完')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(`一共点开了 ${this.exploredCount} 个物品`)
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
          }, (word: string) => 'room_word_' + word)
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
          Web({ src: ROOM_ENGLISH_PAGE_URL, controller: this.controller })
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
              name: 'RoomNativeBridge',
              methodList: ['speak', 'stopSpeak', 'onReady', 'onSelect', 'onProgress'],
              controller: this.controller
            })
            .onPageEnd(() => {
              this.pageReady = true
              this.sceneFailed = false
              this.applyFocusWords()
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
              Text('正在布置小房间…')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
          }

          if (this.sceneFailed) {
            Column({ space: 12 }) {
              Text('3D 房间没有打开')
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
