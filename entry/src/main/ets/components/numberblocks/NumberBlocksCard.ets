// entry/src/main/ets/components/numberblocks/NumberBlocksCard.ets
/**
 * NumberBlocksCard - 认数字 Numberblocks（number_blocks 工具，讲解型）
 *
 * 渲染层：Web 容器加载 rawfile/numberblocks/index.html（纯 CSS 3D，零第三方依赖）。
 * 长廊 5×4 共 20 个方块小人，孩子自己点；点开的角色进舞台，可拖拽旋转、快扫切换、
 * 点一下重播，另有一条 1–20 数字条与「自动巡游」。
 *
 * 原生职责：
 *  - TTS 朗读（ArkWeb 没有 speechSynthesis，走 NumberBlocksNativeBridge.speak →
 *    ServiceRegistry.tts；先中文「三」再英文「three」，语速 0.8 便于跟读）
 *  - 原生标题栏（已认识 N/20 + 我学会了）与进度合并（桥上报 onSelect / onProgress）
 * 讲解型工具不授星（与 map_card / room_english / city_english / farm_english 一致），
 * 星星由后续 math_quiz / picture_vocab 给。
 *
 * 「已看」口径：舞台出现过一次就算看过（长廊点进去 / 滑过去 / 数字条点过去 / 巡游念到）。
 * 本次 sheet 生命周期内有效，不做跨会话收集；原生集合只增不减，页面重载也只做并集。
 */

import { UIContext } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { ToolCall } from '../../models/ChatModels'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  NUMBER_BLOCKS_MAX,
  NumberBlocksValidationResult,
  validateNumberBlocksArgs
} from '../../utils/NumberBlocksValidation'

// 与 mermaid / document-parser / room3d / city3d / farm3d 同法：rawfile 里的本地页面用 resource:// 加载，
// 页面内相对路径（assets/numberblocks-*.js）由 ArkWeb 按同源解析。
const NUMBER_BLOCKS_PAGE_URL: string = 'resource://rawfile/numberblocks/index.html'

/** 数字朗读语速：三个引擎（system/minimax/stepfun）通用范围 [0.5, 2]，0.8 略慢便于孩子跟读 */
const NUMBER_BLOCKS_TTS_SPEED: number = 0.8

/** Web 页就绪看门狗：页面 begin 后超过该时限仍未收到桥 onReady（资源缺失 / 脚本报错）
 *  就切到原生错误面板，避免无限「正在打开数字乐园…」。 */
const NUMBER_BLOCKS_READY_TIMEOUT_MS: number = 10000

/** 完成回执：写进 toolCall.approvalReason，随 ToolResult 回给 AI。 */
export interface NumberBlocksAnswerPayload {
  completed: boolean
  explored_count: number
  numbers: number[]
  focus: number
  mode: string
  skill_key: string
  cancelled: boolean
}

export interface NumberBlocksArgsView {
  valid: boolean
  numbers: number[]
  focus: number
  mode: string
}

function createArgsView(): NumberBlocksArgsView {
  const view: NumberBlocksArgsView = { valid: false, numbers: [], focus: 1, mode: 'display' }
  return view
}

export function parseNumberBlocksArgs(raw: string): NumberBlocksArgsView {
  const result: NumberBlocksValidationResult = validateNumberBlocksArgs(raw)
  const view: NumberBlocksArgsView = createArgsView()
  view.valid = result.ok
  view.numbers = result.numbers
  view.focus = result.focus
  view.mode = result.mode
  return view
}

/** 去重合并：原生集合只增不减（页面重载也走并集），返回新数组触发 @Local 刷新。 */
function mergeNumbers(current: number[], incoming: number[]): number[] {
  let changed = false
  const next: number[] = []
  for (let i = 0; i < current.length; i++) {
    next.push(current[i])
  }
  for (let i = 0; i < incoming.length; i++) {
    const n = incoming[i]
    if (n >= 1 && n <= NUMBER_BLOCKS_MAX && next.indexOf(n) < 0) {
      next.push(n)
      changed = true
    }
  }
  if (!changed) {
    return current
  }
  next.sort((a: number, b: number): number => a - b)
  return next
}

/**
 * ArkWeb javaScriptProxy 注入对象。Web 侧通过 window.NumberBlocksNativeBridge.xxx() 调用，
 * 见 rawfile/numberblocks/assets/numberblocks-scene.js 里的 bridge()。
 */
class NumberBlocksNativeBridge {
  speakHandler: (text: string, zh: string) => boolean = (): boolean => false
  stopHandler: () => void = (): void => {}
  readyHandler: () => void = (): void => {}
  errorHandler: (reason: string) => void = (): void => {}
  selectHandler: (n: string) => void = (): void => {}
  progressHandler: (json: string) => void = (): void => {}

  // 返回值统一用字符串：ArkWeb 代理方法对返回类型最宽容，且 Web 侧只判断真值。
  // zh 为中文数字（可空）：原生先读中文、再读英文。
  speak(text: string, zh: string): string {
    const chinese: string = zh ? zh : ''
    return this.speakHandler(text, chinese) ? 'true' : 'false'
  }

  stopSpeak(): string {
    this.stopHandler()
    return 'true'
  }

  onReady(): string {
    this.readyHandler()
    return 'true'
  }

  // 页面侧启动失败（数据缺失 / 脚本异常）走这里，原生切错误面板。
  onError(reason: string): string {
    this.errorHandler(reason ? reason : 'unknown')
    return 'true'
  }

  onSelect(n: string): string {
    this.selectHandler(n ? n : '')
    return 'true'
  }

  onProgress(json: string): string {
    this.progressHandler(json ? json : '[]')
    return 'true'
  }
}

@ComponentV2
export struct NumberBlocksCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}
  // 宿主（ChatPage）在 sheet 被下拉收起时调用这个 provider，拿到「此刻收起 = 本课到此为止」的回执：
  // 已经看过的数字不会丢，也不会被当成「工具调用已取消」。
  @Event onRegisterDismissPayload: (provider: () => string) => void = () => {}

  @Local argsView: NumberBlocksArgsView = createArgsView()
  /** 本次会话进过舞台的数字（「我学会了」门槛 / 回执 / 完成页 chips） */
  @Local seenNumbers: number[] = []
  @Local pageReady: boolean = false
  @Local sceneFailed: boolean = false
  @Local speaking: boolean = false
  @Local hasCompleted: boolean = false

  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: NumberBlocksNativeBridge = new NumberBlocksNativeBridge()
  private submitted: boolean = false
  private configured: boolean = false
  private watchdogTimer: number = -1
  /** 朗读代次：旧请求的迟到回调靠它丢弃（见 speakNumber） */
  private speakSeq: number = 0
  /** 卡片已销毁：之后任何迟到的 TTS 回调都不得再改状态或接着念 */
  private disposed: boolean = false
  // Web 代理回调可能不在 UI 线程；状态写回统一 runScopedTask 到 UI 上下文。
  private uiContext: UIContext | null = null

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get exploredCount(): number {
    return this.seenNumbers.length
  }

  aboutToAppear(): void {
    this.uiContext = this.getUIContext()
    this.argsView = parseNumberBlocksArgs(this.toolCall.arguments)
    this.onRegisterDismissPayload((): string => this.buildDismissJson())
    this.bridge.speakHandler = (text: string, zh: string): boolean => this.speakNumber(text, zh)
    this.bridge.stopHandler = (): void => this.stopSpeak()
    this.bridge.readyHandler = (): void => {
      this.runOnUi((): void => {
        this.clearSceneWatchdog()
        this.sceneFailed = false
        this.pageReady = true
        // 页面可能自行重载（ArkWeb 回收 / 刷新），每次都重新下发配置，避免长廊丢掉重点与 focus
        this.configured = false
        this.applyConfig()
      })
    }
    this.bridge.errorHandler = (reason: string): void => {
      this.runOnUi((): void => {
        this.handleSceneError(reason)
      })
    }
    this.bridge.selectHandler = (n: string): void => {
      this.runOnUi((): void => {
        this.noteSelected(n)
      })
    }
    this.bridge.progressHandler = (json: string): void => {
      this.runOnUi((): void => {
        this.applyProgress(json)
      })
    }
    if (this.isAnswered) {
      this.readAnsweredPayload()
    }
  }

  aboutToDisappear(): void {
    this.disposed = true
    this.speakSeq += 1
    this.clearSceneWatchdog()
    this.stopSpeak()
    this.runWeb('(function(){try{var app=window.NumberBlocksApp;if(app){app.destroy();}}catch(e){}})();')
  }

  // ====== 就绪 / 失败 ======

  private armSceneWatchdog(): void {
    this.clearSceneWatchdog()
    this.watchdogTimer = setTimeout((): void => {
      this.watchdogTimer = -1
      if (!this.pageReady && !this.isAnswered) {
        this.sceneFailed = true
      }
    }, NUMBER_BLOCKS_READY_TIMEOUT_MS)
  }

  private clearSceneWatchdog(): void {
    if (this.watchdogTimer >= 0) {
      clearTimeout(this.watchdogTimer)
      this.watchdogTimer = -1
    }
  }

  /** 页面自报失败（脚本异常）或主资源加载失败 → 原生错误面板。 */
  private handleSceneError(reason: string): void {
    this.clearSceneWatchdog()
    this.pageReady = false
    this.sceneFailed = true
    console.error('NumberBlocksCard', `scene failed: ${reason}`)
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

  private noteSelected(n: string): void {
    const value = parseInt(n, 10)
    if (isNaN(value)) {
      return
    }
    this.seenNumbers = mergeNumbers(this.seenNumbers, [value])
  }

  /** onProgress 只是页面侧已看集合的并集来源，绝不覆盖、绝不清空原生集合。 */
  private applyProgress(json: string): void {
    try {
      const parsed = JSON.parse(json) as Object[]
      if (!Array.isArray(parsed)) {
        return
      }
      const incoming: number[] = []
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i]
        if (typeof item === 'number') {
          incoming.push(item as number)
        }
      }
      this.seenNumbers = mergeNumbers(this.seenNumbers, incoming)
    } catch (_e) {
      // 页面给的 JSON 坏掉只影响进度展示，不影响主流程
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

  /** 页面就绪后：切宿主模式、下发本次重点数字与 focus。 */
  private applyConfig(): void {
    if (this.configured || !this.pageReady) {
      return
    }
    this.configured = true
    const numbersJson = JSON.stringify(this.argsView.numbers)
    const script = `(function(){try{var app=window.NumberBlocksApp;if(!app){return;}app.setHostMode(true);` +
      `app.configure({numbers:${numbersJson},focus:${this.argsView.focus}});}catch(e){}})();`
    this.controller.runJavaScript(script).catch((e: Error) => {
      console.error('NumberBlocksCard', `apply config failed: ${e.message}`)
    })
  }

  private retryLoad(): void {
    this.sceneFailed = false
    this.pageReady = false
    this.configured = false
    try {
      this.controller.refresh()
    } catch (e) {
      console.error('NumberBlocksCard', `refresh failed: ${String(e)}`)
    }
    this.armSceneWatchdog()
  }

  // ====== TTS ======

  private speakNumber(text: string, zh: string): boolean {
    try {
      ServiceRegistry.tts().stop()
      // 朗读代次：每次朗读 +1。旧请求的 onComplete / onError 可能在新的朗读开始后才到达，
      // 没这个守卫就会「中文刚念一半就跳到英文」，或者在 sheet 关掉后继续念。
      this.speakSeq += 1
      const seq: number = this.speakSeq
      const isCurrent = (): boolean => seq === this.speakSeq && !this.disposed
      this.runOnUi((): void => {
        this.speaking = true
      })
      const speakEnglish: () => void = (): void => {
        if (!isCurrent()) {
          return
        }
        ServiceRegistry.tts().speak(text, {
          onStart: (): void => {
            if (!isCurrent()) {
              return
            }
            this.runOnUi((): void => {
              this.speaking = true
            })
          },
          onComplete: (): void => {
            if (!isCurrent()) {
              return
            }
            this.runOnUi((): void => {
              this.speaking = false
            })
          },
          onError: (error: string): void => {
            if (!isCurrent()) {
              return
            }
            this.runOnUi((): void => {
              this.speaking = false
            })
            console.error('NumberBlocksCard', `tts error: ${error}`)
          }
        }, NUMBER_BLOCKS_TTS_SPEED).catch((e: Error) => {
          if (!isCurrent()) {
            return
          }
          this.runOnUi((): void => {
            this.speaking = false
          })
          console.error('NumberBlocksCard', `tts speak failed: ${e.message}`)
        })
      }

      if (zh === '') {
        speakEnglish()
        return true
      }

      // 先念中文数字（「十三」），念完接着念英文（「thirteen」）
      ServiceRegistry.tts().speak(zh, {
        onStart: (): void => {
          if (!isCurrent()) {
            return
          }
          this.runOnUi((): void => {
            this.speaking = true
          })
        },
        onComplete: (): void => {
          if (!isCurrent()) {
            return
          }
          speakEnglish()
        },
        onError: (error: string): void => {
          if (!isCurrent()) {
            return
          }
          console.error('NumberBlocksCard', `tts zh error: ${error}`)
          speakEnglish()
        }
      }, NUMBER_BLOCKS_TTS_SPEED).catch((e: Error) => {
        if (!isCurrent()) {
          return
        }
        this.runOnUi((): void => {
          this.speaking = false
        })
        console.error('NumberBlocksCard', `tts zh speak failed: ${e.message}`)
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
      const list = prev['numbers'] as Object[]
      if (list !== undefined && list !== null && Array.isArray(list)) {
        const incoming: number[] = []
        for (let i = 0; i < list.length; i++) {
          const item = list[i]
          if (typeof item === 'number') {
            incoming.push(item as number)
          }
        }
        this.seenNumbers = mergeNumbers([], incoming)
      }
    } catch (_e) {
      this.hasCompleted = false
    }
  }

  // ====== 提交 ======

  private buildPayload(completed: boolean, cancelled: boolean): NumberBlocksAnswerPayload {
    const numbers: number[] = []
    for (let i = 0; i < this.seenNumbers.length; i++) {
      numbers.push(this.seenNumbers[i])
    }
    const payload: NumberBlocksAnswerPayload = {
      completed: completed,
      explored_count: numbers.length,
      numbers: numbers,
      focus: this.argsView.focus,
      mode: 'display',
      skill_key: 'math_counting',
      cancelled: cancelled
    }
    return payload
  }

  private canSubmit(): boolean {
    return !this.isAnswered && !this.submitted && this.seenNumbers.length > 0
  }

  // 下拉收起 sheet = 本次到此为止（不是「取消」）：带上已经看过的数字正常回执，
  // 老师拿到结果后照常收尾总结；一个都没点时 completed 为 false，让老师自己起个话头。
  private buildDismissJson(): string {
    return JSON.stringify(this.buildPayload(this.exploredCount > 0, false))
  }

  private submit(): void {
    if (!this.canSubmit()) {
      return
    }
    this.submitted = true
    const payload: NumberBlocksAnswerPayload = this.buildPayload(true, false)
    this.stopSpeak()
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  // ====== UI ======

  private get headerSubtitle(): string {
    if (this.seenNumbers.length > 0) {
      return `本次 ${this.seenNumbers.length} 个 · 点一点方块听数字`
    }
    return '点一点方块小人，听听它是几'
  }

  private get headerActionLabel(): string {
    return this.seenNumbers.length > 0 ? '我学会了' : '先看看数字'
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
        Text('认数字 Numberblocks')
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
      Text(this.hasCompleted ? '数字乐园逛完啦' : '这次没有看完')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(`一共看了 ${this.exploredCount} 个数字`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      if (this.seenNumbers.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.seenNumbers, (n: number) => {
            Text(String(n))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
              .backgroundColor(withColorAlpha(this.themePrimary, '14'))
              .borderRadius(12)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
              .margin({ right: 6, bottom: 6 })
          }, (n: number) => 'nb_seen_' + n.toString())
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
          Web({ src: NUMBER_BLOCKS_PAGE_URL, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(false)
            .horizontalScrollBarAccess(false)
            .verticalScrollBarAccess(false)
            .backgroundColor('#EEF2F7')
            .javaScriptProxy({
              object: this.bridge,
              name: 'NumberBlocksNativeBridge',
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
              console.info(`NumberBlocksCard web console[${msg.getMessageLevel()}]: ${msg.getMessage()}`)
              return false
            })

          if (!this.pageReady && !this.sceneFailed) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(this.themePrimary)
              Text('正在打开数字乐园…')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
          }

          if (this.sceneFailed) {
            Column({ space: 12 }) {
              Text('数字乐园没有打开')
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
    .backgroundColor(this.isDarkMode ? '#1A1510' : '#FFF8E7')
  }
}
