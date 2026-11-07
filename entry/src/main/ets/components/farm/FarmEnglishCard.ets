// entry/src/main/ets/components/farm/FarmEnglishCard.ets
/**
 * FarmEnglishCard - 阳光农场 3D 英语探索（farm_english 工具，讲解型）
 *
 * 渲染层：Web 容器加载 rawfile/farm3d/index.html（three.js r128 本地内置，离线可用）。
 * 原型来自 open-design 的 sunny-farm：140m × 110m 低多边形农场——环形土路串起农舍区、
 * 田地区、牧场区、果园池塘，50 个可点击对象（地点 10 / 动物 14 / 农作物 10 / 农机 8 /
 * 自然 5 / 人物 3），拖拉机、农民、小朋友与小狗沿路移动，风车转动、作物轻摆、
 * 动物 idle、池塘波纹、蜜蜂悬停；5 个分区镜头（全农场 / 农舍区 / 田地区 / 牧场区 /
 * 果园池塘）；单词卡（英文 / 音标 / 中文 / 儿童解释 / 例句）、英文标签、词汇表与收集护照。
 *
 * 原生职责：
 *  - TTS 发音（ArkWeb 没有 speechSynthesis，走 FarmNativeBridge.speak → ServiceRegistry.tts；
 *    点击物品即自动朗读，单词卡「听发音」按钮保留作重播；语速 0.8 略慢便于跟读）
 *  - 原生标题栏（词汇表 / 黄昏 / 我学会了）与进度统计（桥上报 onProgress）
 * 讲解型工具不授星（与 map_card / room_english / city_english 一致），星星由后续 english_quiz 给。
 *
 * 会话态 vs 累计收集：Web 的 farm.discovered.v1 会跨会话累计，onReady 后立即上报全部历史 id。
 * 因此本卡维护两个集合——sessionIds（本次 sheet 会话点开，决定「我学会了」门槛与回执）与
 * discoveredIds（历史累计，只用于 Header 的「农场收集 N/50」）。
 */

import { UIContext } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { ToolCall } from '../../models/ChatModels'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  FarmEnglishValidationResult,
  resolveFarmEnglishView,
  validateFarmEnglishArgs
} from '../../utils/FarmEnglishValidation'

// 与 mermaid / document-parser / room3d / city3d 同法：rawfile 里的本地页面用 resource:// 加载，
// 页面内相对路径（assets/three.min.js 等）由 ArkWeb 按同源解析。
const FARM_ENGLISH_PAGE_URL: string = 'resource://rawfile/farm3d/index.html'
// 与 rawfile/farm3d/assets/farm-data.js 的单词总数保持一致
// （地点 10 + 动物 14 + 农作物 10 + 农机 8 + 自然 5 + 人物 3）
const FARM_OBJECT_TOTAL: number = 50

/** 单词朗读语速：三个引擎（system/minimax/stepfun）通用范围 [0.5, 2]，0.8 略慢便于孩子跟读 */
const FARM_WORD_TTS_SPEED: number = 0.8

/** Web 页就绪看门狗：页面 begin 后超过该时限仍未收到桥 onReady（资源缺失 / 脚本报错）
 *  就切到原生错误面板，避免无限「正在播种阳光农场…」。 */
const FARM_SCENE_READY_TIMEOUT_MS: number = 10000

/** 完成回执：写进 toolCall.approvalReason，随 ToolResult 回给 AI。 */
export interface FarmEnglishAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  focus: string
  skill_key: string
  cancelled: boolean
}

export interface FarmEnglishArgsView {
  valid: boolean
  focus: string
  words: string[]
}

function createArgsView(): FarmEnglishArgsView {
  const view: FarmEnglishArgsView = { valid: false, focus: 'overview', words: [] }
  return view
}

export function parseFarmEnglishArgs(raw: string): FarmEnglishArgsView {
  const result: FarmEnglishValidationResult = validateFarmEnglishArgs(raw)
  const view: FarmEnglishArgsView = createArgsView()
  view.valid = result.ok
  view.focus = result.focus
  view.words = result.words
  return view
}

/**
 * ArkWeb javaScriptProxy 注入对象。Web 侧通过 window.FarmNativeBridge.xxx() 调用，
 * 见 rawfile/farm3d/assets/farm-app.js 里的 bridgeCall。
 */
class FarmNativeBridge {
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

  // 页面侧启动失败（数据缺失 / WebGL 不可用）走这里，原生切错误面板。
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
export struct FarmEnglishCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}
  // 宿主（ChatPage）在 sheet 被下拉收起时调用这个 provider，拿到「此刻收起 = 完成本课」的回执：
  // 已经点开的单词不会丢，也不会被当成「工具调用已取消」。
  @Event onRegisterDismissPayload: (provider: () => string) => void = () => {}

  @Local argsView: FarmEnglishArgsView = createArgsView()
  /** 本次会话点开的 id（「我学会了」门槛 / 回执 / 完成页 chips） */
  @Local sessionIds: string[] = []
  /** 历史累计收集的 id（只用于 Header「农场收集 N/50」） */
  @Local discoveredIds: string[] = []
  @Local lookup: Map<string, string> = new Map<string, string>()
  @Local pageReady: boolean = false
  @Local sceneFailed: boolean = false
  @Local speaking: boolean = false
  @Local hasCompleted: boolean = false
  @Local nightOn: boolean = false

  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: FarmNativeBridge = new FarmNativeBridge()
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
    this.argsView = parseFarmEnglishArgs(this.toolCall.arguments)
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
    }, FARM_SCENE_READY_TIMEOUT_MS)
  }

  private clearSceneWatchdog(): void {
    if (this.watchdogTimer >= 0) {
      clearTimeout(this.watchdogTimer)
      this.watchdogTimer = -1
    }
  }

  /** 页面自报失败（数据缺失 / WebGL 不可用）或主资源加载失败 → 原生错误面板。 */
  private handleSceneError(reason: string): void {
    this.clearSceneWatchdog()
    this.pageReady = false
    this.sceneFailed = true
    console.error('FarmEnglishCard', `scene failed: ${reason}`)
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
            console.error('FarmEnglishCard', `tts error: ${error}`)
          }
        }, FARM_WORD_TTS_SPEED).catch((e: Error) => {
          this.runOnUi((): void => {
            this.speaking = false
          })
          console.error('FarmEnglishCard', `tts speak failed: ${e.message}`)
        })
      }

      if (zh === '') {
        speakEnglish()
        return true
      }

      // 先念中文意思（“奶牛”），念完接着念英文单词（“cow”）
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
          console.error('FarmEnglishCard', `tts zh error: ${error}`)
          speakEnglish()
        }
      }, FARM_WORD_TTS_SPEED).catch((e: Error) => {
        this.runOnUi((): void => {
          this.speaking = false
        })
        console.error('FarmEnglishCard', `tts zh speak failed: ${e.message}`)
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

  /** 页面就绪后：切宿主模式（隐藏网页顶栏）、打开 focus 指定区域或第一个重点词。
   *  有 words 时不再先 setView——FarmApp.select(id) 内部会按物体所属分区切镜头，
   *  而 setView 会在 960ms 后 openFocus 打开该区第一个重点词，覆盖用户刚选的词。 */
  private applyFocusWords(): void {
    if (this.focusApplied || !this.pageReady) {
      return
    }
    const view = resolveFarmEnglishView(this.argsView.focus)
    const first = this.argsView.words.length > 0 ? `'${this.argsView.words[0]}'` : 'null'
    this.focusApplied = true
    const script = `(function(){try{var app=window.FarmApp;if(!app){return;}app.setHostMode(true);` +
      `if(${first}){app.select(${first});}else{app.setView('${view}');}}catch(e){}})();`
    this.controller.runJavaScript(script).catch((e: Error) => {
      console.error('FarmEnglishCard', `apply focus words failed: ${e.message}`)
    })
  }

  private openVocab(): void {
    this.runWeb('(function(){try{var app=window.FarmApp;if(app){app.openVocab();}}catch(e){}})();')
      .catch((e: Error): void => {
        console.error('FarmEnglishCard', 'open vocab failed: ' + e.message)
      })
  }

  private toggleNight(): void {
    this.nightOn = !this.nightOn
    const on = this.nightOn ? 'true' : 'false'
    this.runWeb(`(function(){try{var app=window.FarmApp;if(app){app.setNight(${on});}}catch(e){}})();`)
      .catch((e: Error): void => {
        console.error('FarmEnglishCard', 'set night failed: ' + e.message)
      })
  }

  private retryLoad(): void {
    this.sceneFailed = false
    this.pageReady = false
    this.focusApplied = false
    try {
      this.controller.refresh()
    } catch (e) {
      console.error('FarmEnglishCard', `refresh failed: ${String(e)}`)
    }
    this.armSceneWatchdog()
  }

  // ====== 提交 ======

  private buildPayload(completed: boolean, cancelled: boolean): FarmEnglishAnswerPayload {
    const words: string[] = []
    for (let i = 0; i < this.sessionIds.length; i++) {
      words.push(this.sessionIds[i])
    }
    const payload: FarmEnglishAnswerPayload = {
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
    const payload: FarmEnglishAnswerPayload = this.buildPayload(true, false)
    this.stopSpeak()
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  // ====== UI ======

  private get headerSubtitle(): string {
    if (this.sessionIds.length > 0) {
      return `本次 ${this.sessionIds.length} 个 · 农场收集 ${this.discoveredIds.length} / ${FARM_OBJECT_TOTAL}`
    }
    return `农场收集 ${this.discoveredIds.length} / ${FARM_OBJECT_TOTAL} · 点一点农场听英文`
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
        Text('阳光农场 3D 英语探索')
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
      Text(this.hasCompleted ? '阳光农场探索完成' : '这次没有探索完')
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
          }, (word: string) => 'farm_word_' + word)
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
          Web({ src: FARM_ENGLISH_PAGE_URL, controller: this.controller })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(false)
            .horizontalScrollBarAccess(false)
            .verticalScrollBarAccess(false)
            .backgroundColor(this.isDarkMode ? '#1A1510' : '#FFF8E7')
            .javaScriptProxy({
              object: this.bridge,
              name: 'FarmNativeBridge',
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
              console.info(`FarmEnglishCard web console[${msg.getMessageLevel()}]: ${msg.getMessage()}`)
              return false
            })

          if (!this.pageReady && !this.sceneFailed) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(this.themePrimary)
              Text('正在播种阳光农场…')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
          }

          if (this.sceneFailed) {
            Column({ space: 12 }) {
              Text('3D 农场没有打开')
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
