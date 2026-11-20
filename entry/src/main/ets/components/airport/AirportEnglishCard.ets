// entry/src/main/ets/components/airport/AirportEnglishCard.ets
/**
 * AirportEnglishCard - 3D 机场英语探索（airport_english 工具，讲解型）
 *
 * 渲染层：Web 容器加载 rawfile/airport3d/index.html（three.js r128 + GLTFLoader 本地内置，离线可用）。
 * 场景取自 polyfork.dev 的 Airport kit（CC BY 4.0）：航站楼、塔台、跑道、停机坪、机库维修区，
 * 50 个可点击实体（地点 14 / 飞机 6 / 车辆 12 / 人物 5 / 设施 13），点实体打开单词卡并朗读。
 *
 * 原生职责：
 *  - TTS 发音（ArkWeb 没有 speechSynthesis，走 AirportNativeBridge.speak → ServiceRegistry.tts；
 *    点击物品即自动朗读，先中文后英文；语速 0.8 略慢便于跟读）
 *  - 原生标题栏（词汇表 / 我学会了）与进度统计（桥上报 onProgress）
 * 讲解型工具不授星（与 map_card / room_english / city_english / farm_english 一致），星星由后续 english_quiz 给。
 */

import { UIContext } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { ToolCall } from '../../models/ChatModels'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  AirportEnglishValidationResult,
  resolveAirportEnglishView,
  validateAirportEnglishArgs
} from '../../utils/AirportEnglishValidation'

const AIRPORT_ENGLISH_PAGE_URL: string = 'resource://rawfile/airport3d/index.html'
// 与 rawfile/airport3d/assets/airport-data.js 的词表保持一致（50）。
const AIRPORT_WORD_TOTAL: number = 50

/** 单词朗读语速：三个引擎（system/minimax/stepfun）通用范围 [0.5, 2]，0.8 略慢便于孩子跟读 */
const AIRPORT_WORD_TTS_SPEED: number = 0.8

/** Web 页就绪看门狗：页面 begin 后超过该时限仍未收到桥 onReady（资源缺失 / 脚本报错）
 *  就切到原生错误面板，避免无限「正在装配机场…」。 */
const AIRPORT_SCENE_READY_TIMEOUT_MS: number = 20000

/** 完成回执：写进 toolCall.approvalReason，随 ToolResult 回给 AI。 */
export interface AirportEnglishAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  focus: string
  skill_key: string
  cancelled: boolean
}

export interface AirportEnglishArgsView {
  valid: boolean
  focus: string
  words: string[]
}

function createArgsView(): AirportEnglishArgsView {
  const view: AirportEnglishArgsView = { valid: false, focus: 'overview', words: [] }
  return view
}

export function parseAirportEnglishArgs(raw: string): AirportEnglishArgsView {
  const result: AirportEnglishValidationResult = validateAirportEnglishArgs(raw)
  const view: AirportEnglishArgsView = createArgsView()
  view.valid = result.ok
  view.focus = result.focus
  view.words = result.words
  return view
}

/**
 * ArkWeb javaScriptProxy 注入对象。Web 侧通过 window.AirportNativeBridge.xxx() 调用，
 * 见 rawfile/airport3d/assets/airport-app.js 里的 bridgeCall。
 */
class AirportNativeBridge {
  speakHandler: (text: string, zh: string) => boolean = (): boolean => false
  stopHandler: () => void = (): void => {}
  readyHandler: () => void = (): void => {}
  errorHandler: (reason: string) => void = (): void => {}
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

  onError(reason: string): string {
    this.errorHandler(reason ? reason : 'unknown')
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
export struct AirportEnglishCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}
  // 宿主（ChatPage）在 sheet 被下拉收起时调用这个 provider，拿到「此刻收起 = 完成本课」的回执。
  @Event onRegisterDismissPayload: (provider: () => string) => void = () => {}

  @Local argsView: AirportEnglishArgsView = createArgsView()
  /** 本次会话点开的 id（「我学会了」门槛 / 回执 / 完成页 chips） */
  @Local sessionIds: string[] = []
  /** 历史累计收集的 id（只用于 Header「机场收集 N/50」） */
  @Local discoveredIds: string[] = []
  @Local lookup: Map<string, string> = new Map<string, string>()
  @Local pageReady: boolean = false
  @Local sceneFailed: boolean = false
  @Local speaking: boolean = false
  @Local hasCompleted: boolean = false
  @Local labelsOn: boolean = false
  @Local fallbackVocab: boolean = false

  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: AirportNativeBridge = new AirportNativeBridge()
  private submitted: boolean = false
  private focusApplied: boolean = false
  private watchdogTimer: number = -1
  // Web 代理回调可能不在 UI 线程；状态写回统一 runScopedTask 到 UI 上下文。
  private uiContext: UIContext | null = null

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get exploredCount(): number {
    return this.sessionIds.length
  }

  private get discoveredCount(): number {
    return this.discoveredIds.length
  }

  /** 本次会话点开的 id → 英文单词（历史 id 退回 id）。 */
  private get exploredWords(): string[] {
    const out: string[] = []
    for (let i = 0; i < this.sessionIds.length; i++) {
      const id = this.sessionIds[i]
      const word = this.lookup.get(id)
      out.push(word !== undefined ? word : id)
    }
    return out
  }

  aboutToAppear(): void {
    this.uiContext = this.getUIContext()
    this.argsView = parseAirportEnglishArgs(this.toolCall.arguments)
    this.onRegisterDismissPayload((): string => this.buildDismissJson())
    this.bridge.speakHandler = (text: string, zh: string): boolean => this.speakWord(text, zh)
    this.bridge.stopHandler = (): void => this.stopSpeak()
    this.bridge.readyHandler = (): void => {
      this.runOnUi((): void => {
        this.clearSceneWatchdog()
        this.sceneFailed = false
        this.pageReady = true
        this.applyFocusWords()
      })
    }
    this.bridge.errorHandler = (reason: string): void => {
      this.runOnUi((): void => {
        this.handleSceneError(reason)
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
    this.clearSceneWatchdog()
    this.stopSpeak()
  }

  // ====== 就绪 / 失败 ======

  private armSceneWatchdog(): void {
    this.clearSceneWatchdog()
    this.watchdogTimer = setTimeout((): void => {
      this.watchdogTimer = -1
      if (!this.pageReady && !this.isAnswered) {
        this.sceneFailed = true
      }
    }, AIRPORT_SCENE_READY_TIMEOUT_MS)
  }

  private clearSceneWatchdog(): void {
    if (this.watchdogTimer >= 0) {
      clearTimeout(this.watchdogTimer)
      this.watchdogTimer = -1
    }
  }

  private handleSceneError(reason: string): void {
    this.clearSceneWatchdog()
    this.pageReady = false
    this.sceneFailed = true
    console.error('AirportEnglishCard', `scene failed: ${reason}`)
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
    this.sessionIds = appendUnique(this.sessionIds, id)
    this.discoveredIds = appendUnique(this.discoveredIds, id)
  }

  /** onProgress 只覆盖历史累计集合，绝不影响「我学会了」门槛。 */
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
      this.discoveredIds = next
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
            console.error('AirportEnglishCard', `tts error: ${error}`)
          }
        }, AIRPORT_WORD_TTS_SPEED).catch((e: Error) => {
          this.runOnUi((): void => {
            this.speaking = false
          })
          console.error('AirportEnglishCard', `tts speak failed: ${e.message}`)
        })
      }

      if (zh === '') {
        speakEnglish()
        return true
      }

      // 先念中文意思（“飞机”），念完接着念英文单词（“airplane”）
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
          console.error('AirportEnglishCard', `tts zh error: ${error}`)
          speakEnglish()
        }
      }, AIRPORT_WORD_TTS_SPEED).catch((e: Error) => {
        this.runOnUi((): void => {
          this.speaking = false
        })
        console.error('AirportEnglishCard', `tts zh speak failed: ${e.message}`)
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
        this.sessionIds = next
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

  /** 页面就绪后：切宿主模式（隐藏网页顶栏）；有 words 选中第一个词（镜头跟随该词），
   *  否则打开 focus 分区镜头。 */
  private applyFocusWords(): void {
    if (this.focusApplied || !this.pageReady) {
      return
    }
    const view = resolveAirportEnglishView(this.argsView.focus)
    const first = this.argsView.words.length > 0 ? `'${this.argsView.words[0]}'` : 'null'
    this.focusApplied = true
    const script = `(function(){try{var app=window.AirportApp;if(!app){return;}app.setHostMode(true);` +
      `if(${first}){app.select(${first});}else{app.setView('${view}');}}catch(e){}})();`
    this.controller.runJavaScript(script).catch((e: Error) => {
      console.error('AirportEnglishCard', `apply focus words failed: ${e.message}`)
    })
  }

  private openVocab(): void {
    this.runWeb('(function(){try{var app=window.AirportApp;if(app){app.openVocab();}}catch(e){}})();')
      .catch((e: Error): void => {
        console.error('AirportEnglishCard', 'open vocab failed: ' + e.message)
      })
  }

  private toggleLabels(): void {
    this.labelsOn = !this.labelsOn
    const on = this.labelsOn ? 'true' : 'false'
    this.runWeb(`(function(){try{var app=window.AirportApp;if(app){app.setLabels(${on});}}catch(e){}})();`)
      .catch((e: Error): void => {
        console.error('AirportEnglishCard', 'set labels failed: ' + e.message)
      })
  }

  private retryLoad(): void {
    this.sceneFailed = false
    this.pageReady = false
    this.focusApplied = false
    this.fallbackVocab = false
    try {
      this.controller.refresh()
    } catch (e) {
      console.error('AirportEnglishCard', `refresh failed: ${String(e)}`)
    }
    this.armSceneWatchdog()
  }

  // ====== 提交 ======

  private buildPayload(completed: boolean, cancelled: boolean): AirportEnglishAnswerPayload {
    const words: string[] = []
    for (let i = 0; i < this.sessionIds.length; i++) {
      words.push(this.sessionIds[i])
    }
    const payload: AirportEnglishAnswerPayload = {
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
    return !this.isAnswered && !this.submitted && this.sessionIds.length > 0
  }

  // 下拉收起 sheet = 本课到此为止（不是「取消」）：带上已经点开的单词正常回执，
  // 老师拿到结果后照常收尾总结；一个词都没点时 completed 为 false，让老师自己起个话头。
  private buildDismissJson(): string {
    return JSON.stringify(this.buildPayload(this.exploredCount > 0, false))
  }

  private submit(): void {
    if (!this.canSubmit()) {
      return
    }
    this.submitted = true
    const payload: AirportEnglishAnswerPayload = this.buildPayload(true, false)
    this.stopSpeak()
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  // ====== UI ======

  private get headerSubtitle(): string {
    if (this.sessionIds.length > 0) {
      return `本次 ${this.sessionIds.length} 个 · 机场收集 ${this.discoveredIds.length} / ${AIRPORT_WORD_TOTAL}`
    }
    return `机场收集 ${this.discoveredIds.length} / ${AIRPORT_WORD_TOTAL} · 点一点飞机和车听英文`
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
        Text('3D 机场英语探索')
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
        Text(this.labelsOn ? '标签开' : '标签')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.labelsOn ? Color.White : this.themePrimary)
      }
      .height(30)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.labelsOn ? this.themePrimary : withColorAlpha(this.themePrimary, '14'))
      .onClick(() => {
        this.toggleLabels()
      })

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
      Text(this.hasCompleted ? '机场探索完成' : '这次没有探索完')
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
          }, (word: string) => 'airport_word_' + word)
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
          Web({ src: AIRPORT_ENGLISH_PAGE_URL, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(false)
            .horizontalScrollBarAccess(false)
            .verticalScrollBarAccess(false)
            .backgroundColor(this.isDarkMode ? '#1A1510' : '#F3F0E4')
            .javaScriptProxy({
              object: this.bridge,
              name: 'AirportNativeBridge',
              methodList: ['speak', 'stopSpeak', 'onReady', 'onError', 'onSelect', 'onProgress'],
              controller: this.controller
            })
            .onPageBegin(() => {
              this.armSceneWatchdog()
            })
            .onErrorReceive(() => {
              this.handleSceneError('load')
            })
            .onConsole((event: OnConsoleEvent): boolean => {
              // 页面会话错误（脚本加载失败 / 场景初始化异常）转进 hilog，便于排查白屏。
              const msg = event.message
              console.info(`AirportEnglishCard web console[${msg.getMessageLevel()}]: ${msg.getMessage()}`)
              return false
            })

          if (!this.pageReady && !this.sceneFailed && !this.fallbackVocab) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(this.themePrimary)
              Text('正在装配机场…')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
          }

          if (this.sceneFailed && !this.fallbackVocab) {
            Column({ space: 12 }) {
              Text('3D 机场没有打开')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('可以点下面的按钮重新加载，或者先回到对话里。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Row({ space: 8 }) {
                Button({ type: ButtonType.Capsule }) {
                  Text('词汇表')
                    .fontSize(13)
                    .fontColor(this.themePrimary)
                }
                .height(32)
                .padding({ left: 16, right: 16 })
                .backgroundColor(withColorAlpha(this.themePrimary, '14'))
                .onClick(() => {
                  this.fallbackVocab = true
                  this.openVocab()
                })

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
    .backgroundColor(this.isDarkMode ? '#1A1510' : '#F3F0E4')
  }
}

/** 去重追加：返回新数组（ArkUI @Local 需要整数组替换才会触发刷新）。 */
function appendUnique(current: string[], id: string): string[] {
  if (current.indexOf(id) >= 0) {
    return current
  }
  const next: string[] = []
  for (let i = 0; i < current.length; i++) {
    next.push(current[i])
  }
  next.push(id)
  return next
}
