// entry/src/main/ets/components/body/Body3DCard.ets
/**
 * Body3DCard - 3D 身体英语课（body_3d 工具，讲解型）
 *
 * 渲染层：Web 容器加载 rawfile/body3d/index.html（three.js 本地内置，离线可用）。
 * 原型来自 open-design 的 xiaoxing-body-class：程序化低多边形小星、25 个可点击身体部位、
 * 单词卡（英文 / 音标 / 中文 / 儿童解释 / 单复数提示）、部位图与分组单词表。
 *
 * 原生职责：
 *  - TTS 发音（ArkWeb 没有 speechSynthesis，走 BodyNativeBridge.speak → ServiceRegistry.tts；
 *    点击部位即自动朗读英文两遍；语速 0.8 略慢便于跟读）
 *  - 进度统计（桥上报 onProgress）与「我学会了」完成回执（payload 回写 AI）
 * 讲解型工具不授星（与 room_english / map_card 一致），星星由后续 english_quiz / matching_pairs 给。
 */

import { UIContext } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { ToolCall } from '../../models/ChatModels'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { Body3DValidationResult, validateBody3DArgs } from '../../utils/Body3DValidation'

// 与 mermaid / room3d 同法：rawfile 里的本地页面用 resource:// 加载，
// 页面内相对路径（assets/three.min.js 等）由 ArkWeb 按同源解析。
const BODY_3D_PAGE_URL: string = 'resource://rawfile/body3d/index.html'
// 与 rawfile/body3d/assets/body-data.js 的部位总数保持一致
const BODY_PART_TOTAL: number = 25

/** 单词朗读语速：三个引擎（system/minimax/stepfun）通用范围 [0.5, 2]，0.8 略慢便于孩子跟读 */
const BODY_WORD_TTS_SPEED: number = 0.8

/** 完成回执：写进 toolCall.approvalReason，随 ToolResult 回给 AI。 */
export interface Body3DAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  labels: string[]
  focus: string
  skill_key: string
  cancelled: boolean
}

export interface Body3DArgsView {
  valid: boolean
  focus: string
  words: string[]
}

function createArgsView(): Body3DArgsView {
  const view: Body3DArgsView = { valid: false, focus: 'all', words: [] }
  return view
}

export function parseBody3DArgs(raw: string): Body3DArgsView {
  const result: Body3DValidationResult = validateBody3DArgs(raw)
  const view: Body3DArgsView = createArgsView()
  view.valid = result.ok
  view.focus = result.focus
  view.words = result.words
  return view
}

/**
 * ArkWeb javaScriptProxy 注入对象。Web 侧通过 window.BodyNativeBridge.xxx() 调用，
 * 见 rawfile/body3d/assets/body-app.js 里的 bridgeCall。
 */
class BodyNativeBridge {
  speakHandler: (text: string, zh: string) => boolean = (): boolean => false
  stopHandler: () => void = (): void => {}
  readyHandler: () => void = (): void => {}
  selectHandler: (id: string, word: string) => void = (): void => {}
  progressHandler: (idsJson: string) => void = (): void => {}

  // 返回值统一用字符串：ArkWeb 代理方法对返回类型最宽容，且 Web 侧只判断真值。
  // zh 为部位的中文意思（可空）：原生先读中文、再读英文单词（网页当前传空）。
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
export struct Body3DCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  @Local argsView: Body3DArgsView = createArgsView()
  @Local exploredIds: string[] = []
  @Local exploredLabels: string[] = []
  @Local pageReady: boolean = false
  @Local sceneFailed: boolean = false
  @Local speaking: boolean = false
  @Local hasCompleted: boolean = false

  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: BodyNativeBridge = new BodyNativeBridge()
  private submitted: boolean = false
  private focusApplied: boolean = false
  // 连续点词时，旧 TTS 的 onComplete/onError 可能晚到；用序号只让最后一次朗读复位口型。
  private speechSeq: number = 0
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
    this.argsView = parseBody3DArgs(this.toolCall.arguments)
    this.bridge.speakHandler = (text: string, zh: string): boolean => this.speakWord(text, zh)
    this.bridge.stopHandler = (): void => this.stopSpeak()
    this.bridge.readyHandler = (): void => {
      this.runOnUi((): void => {
        this.pageReady = true
        this.applyFocusWords()
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
    const nextLabels: string[] = []
    for (let i = 0; i < this.exploredLabels.length; i++) {
      nextLabels.push(this.exploredLabels[i])
    }
    nextLabels.push(word !== '' ? word : id)
    this.exploredIds = nextIds
    this.exploredLabels = nextLabels
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
      // Web 的 onProgress 只带 id，onSelect 已带来英文复数名（knees / feet）。
      // 这里按 id 保留已有 label，缺失时才用 id 占位，避免回执里的 labels 被覆盖成单数 id。
      const labels: string[] = []
      for (let i = 0; i < next.length; i++) {
        const id: string = next[i]
        const oldIndex: number = this.exploredIds.indexOf(id)
        if (oldIndex >= 0 && oldIndex < this.exploredLabels.length && this.exploredLabels[oldIndex] !== '') {
          labels.push(this.exploredLabels[oldIndex])
        } else {
          labels.push(id)
        }
      }
      this.exploredIds = next
      this.exploredLabels = labels
    } catch (_e) {
      // 解析失败保留现状，不影响浏览
    }
  }

  private notifySpeechEnded(): void {
    this.controller.runJavaScript(
      `(function(){try{if(window.BodyClassApp&&window.BodyClassApp.speechEnded){window.BodyClassApp.speechEnded();}}catch(e){}})();`
    ).catch((e: Error) => {
      console.error('Body3DCard', `notify speech ended failed: ${e.message}`)
    })
  }

  private speakWord(text: string, zh: string): boolean {
    try {
      ServiceRegistry.tts().stop()
      const seq: number = ++this.speechSeq
      this.runOnUi((): void => {
        this.speaking = true
      })
      const speakEnglish: () => void = (): void => {
        if (seq !== this.speechSeq) {
          return
        }
        this.runOnUi((): void => {
          this.speaking = true
        })
        ServiceRegistry.tts().speak(text, {
          onStart: (): void => {
            if (seq !== this.speechSeq) {
              return
            }
            this.runOnUi((): void => {
              this.speaking = true
            })
          },
          onComplete: (): void => {
            if (seq !== this.speechSeq) {
              return
            }
            this.runOnUi((): void => {
              this.speaking = false
            })
            this.notifySpeechEnded()
          },
          onError: (error: string): void => {
            if (seq !== this.speechSeq) {
              return
            }
            this.runOnUi((): void => {
              this.speaking = false
            })
            console.error('Body3DCard', `tts error: ${error}`)
            this.notifySpeechEnded()
          }
        }, BODY_WORD_TTS_SPEED).catch((e: Error) => {
          if (seq !== this.speechSeq) {
            return
          }
          this.runOnUi((): void => {
            this.speaking = false
          })
          console.error('Body3DCard', `tts speak failed: ${e.message}`)
          this.notifySpeechEnded()
        })
      }

      if (zh === '') {
        speakEnglish()
        return true
      }

      // 先念中文意思（“头”），念完接着念英文单词（“head”）
      ServiceRegistry.tts().speak(zh, {
        onStart: (): void => {
          if (seq !== this.speechSeq) {
            return
          }
          this.runOnUi((): void => {
            this.speaking = true
          })
        },
        onComplete: (): void => {
          if (seq === this.speechSeq) {
            speakEnglish()
          }
        },
        onError: (error: string): void => {
          if (seq !== this.speechSeq) {
            return
          }
          console.error('Body3DCard', `tts zh error: ${error}`)
          speakEnglish()
        }
      }, BODY_WORD_TTS_SPEED).catch((e: Error) => {
        if (seq !== this.speechSeq) {
          return
        }
        this.runOnUi((): void => {
          this.speaking = false
        })
        console.error('Body3DCard', `tts zh speak failed: ${e.message}`)
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
    this.speechSeq++
    this.runOnUi((): void => {
      this.speaking = false
    })
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
        this.exploredLabels = next
      }
      const labels = prev['labels'] as Object[]
      if (labels !== undefined && labels !== null && Array.isArray(labels)) {
        const nextLabels: string[] = []
        for (let i = 0; i < labels.length; i++) {
          const item = labels[i]
          if (typeof item === 'string') {
            nextLabels.push(item as string)
          }
        }
        if (nextLabels.length > 0) {
          this.exploredLabels = nextLabels
        }
      }
    } catch (_e) {
      this.hasCompleted = false
    }
  }

  // ====== Web 控制 ======

  /** 页面就绪后：把 focus 分组与本次重点词注入页面；显式 words 会立即选中第一个并朗读。 */
  private applyFocusWords(): void {
    if (this.focusApplied || !this.pageReady) {
      return
    }
    this.focusApplied = true
    const wordsJson: string = JSON.stringify(this.argsView.words)
    const script = `(function(){try{var app=window.BodyClassApp;if(!app){return;}app.setFocus('${this.argsView.focus}',${wordsJson});}}catch(e){}})();`
    this.controller.runJavaScript(script).catch((e: Error) => {
      console.error('Body3DCard', `apply focus words failed: ${e.message}`)
    })
  }

  private retryLoad(): void {
    this.sceneFailed = false
    this.pageReady = false
    this.focusApplied = false
    try {
      this.controller.refresh()
    } catch (e) {
      console.error('Body3DCard', `refresh failed: ${String(e)}`)
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
    const payload: Body3DAnswerPayload = {
      completed: true,
      explored_count: this.exploredCount,
      words: this.exploredIds,
      labels: this.exploredLabels,
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
        Text('3D 身体英语课')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.exploredCount > 0
          ? `已学会 ${this.exploredCount} / ${BODY_PART_TOTAL} 个部位`
          : '点一点小星身上的部位，听一听英语怎么说')
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
      Text(this.hasCompleted ? '身体课学完了' : '这次没有学完')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(`一共点开了 ${this.exploredCount} 个部位`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      if (this.exploredLabels.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.exploredLabels, (word: string) => {
            Text(word)
              .fontSize(12)
              .fontColor(this.themePrimary)
              .backgroundColor(withColorAlpha(this.themePrimary, '14'))
              .borderRadius(10)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .margin({ right: 6, bottom: 6 })
          }, (word: string) => 'body_word_' + word)
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
          Web({ src: BODY_3D_PAGE_URL, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(false)
            .horizontalScrollBarAccess(false)
            .verticalScrollBarAccess(true)
            .backgroundColor(this.isDarkMode ? '#101614' : '#f6f9fb')
            .javaScriptProxy({
              object: this.bridge,
              name: 'BodyNativeBridge',
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
              Text('正在请小星来上课…')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
          }

          if (this.sceneFailed) {
            Column({ space: 8 }) {
              Text('3D 小星没有站起来')
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
    .backgroundColor(this.isDarkMode ? '#101614' : '#f6f9fb')
  }
}
