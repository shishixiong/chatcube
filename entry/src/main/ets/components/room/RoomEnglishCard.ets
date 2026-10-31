// entry/src/main/ets/components/room/RoomEnglishCard.ets
/**
 * RoomEnglishCard - 全屋 3D 英语探索（room_english 工具，讲解型）
 *
 * 渲染层：Web 容器加载 rawfile/room3d/index.html（three.js 0.185 本地内置，离线可用）。
 * 原型来自 open-design 的 kids-room-3d-english + kids-3d-bedrooms-wing：四间低多边形房间
 * （11.8m × 6m 客餐厅 + 开放厨房、4.4m × 3.6m 儿童房、4.6m × 3.6m 主卧、6.6m × 2.4m 生活阳台）、
 * 76 件可点击物品，默认打开全屋户型，房卡顶部切换「全屋 / 四间房」；单词卡（英文 / 音标 / 中文 / 儿童解释 / 例句）、
 * 英文标签、词汇表与进度点阵。
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
import {
  RoomEnglishLessonPlan,
  RoomEnglishValidationResult,
  RoomLessonStep,
  resolveRoomEnglishArea,
  resolveRoomEnglishView,
  validateRoomEnglishArgs
} from '../../utils/RoomEnglishValidation'
import {
  RoomLessonTaskState,
  RoomTaskTapResult,
  advanceTask,
  buildRevealPrompt,
  buildSuccessPrompt,
  buildTaskPrompt,
  buildWrongPrompt,
  createTaskState,
  currentTargetId,
  isTaskComplete,
  judgeTaskTap,
  nextTourIndex
} from '../../utils/RoomEnglishLesson'

// 与 mermaid / document-parser 同法：rawfile 里的本地页面用 resource:// 加载，
// 页面内相对路径（assets/three.min.js 等）由 ArkWeb 按同源解析。
const ROOM_ENGLISH_PAGE_URL: string = 'resource://rawfile/room3d/index.html'
// 与 rawfile/room3d/assets/scene-data.js 的物品总数保持一致
// （客厅 15 + 餐厅 10 + 厨房 12 + 儿童房 12 + 主卧 12 + 阳台 15）
const ROOM_OBJECT_TOTAL: number = 76

/** 单词朗读语速：三个引擎（system/minimax/stepfun）通用范围 [0.5, 2]，0.8 略慢便于孩子跟读 */
const ROOM_WORD_TTS_SPEED: number = 0.8

/** 引导式课程回执（spec 2026-10-30）：带逛 + 听词找物的课堂统计。 */
export interface RoomEnglishLessonResult {
  tour_completed: boolean
  tour_words: string[]
  task_type: string
  task_targets: string[]
  task_correct: number
  task_first_try: number
  task_revealed: number
  task_total: number
  task_attempts: number
  task_completed: boolean
}

/** 完成回执：写进 toolCall.approvalReason，随 ToolResult 回给 AI。 */
export interface RoomEnglishAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  focus: string
  skill_key: string
  cancelled: boolean
  lesson: RoomEnglishLessonResult | null
}

export interface RoomEnglishArgsView {
  valid: boolean
  focus: string
  words: string[]
  lesson: RoomEnglishLessonPlan | null
}

/** 卡片本地 UI 阶段：free = 自由探索（无 lesson），其余为引导式课程。 */
type RoomLessonMode = 'free' | 'tour' | 'task' | 'summary' | 'answered'

function readStringArray(value: Object): string[] {
  const out: string[] = []
  if (value === undefined || value === null || !Array.isArray(value)) {
    return out
  }
  const list = value as Object[]
  for (let i = 0; i < list.length; i++) {
    const item = list[i]
    if (typeof item === 'string') {
      out.push(item as string)
    }
  }
  return out
}

function readNumber(value: Object): number {
  if (typeof value === 'number') {
    return value as number
  }
  return 0
}

function createArgsView(): RoomEnglishArgsView {
  const view: RoomEnglishArgsView = { valid: false, focus: 'all', words: [], lesson: null }
  return view
}

export function parseRoomEnglishArgs(raw: string): RoomEnglishArgsView {
  const result: RoomEnglishValidationResult = validateRoomEnglishArgs(raw)
  const view: RoomEnglishArgsView = createArgsView()
  view.valid = result.ok
  view.focus = result.focus
  view.words = result.words
  view.lesson = result.lesson
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

  // 引导式课程状态（lesson 为空时保持自由探索行为）
  @Local lessonMode: RoomLessonMode = 'free'
  @Local tourIndex: number = 0
  @Local tourCompleted: boolean = false
  @Local taskState: RoomLessonTaskState = createTaskState([])
  @Local bubbleText: string = ''
  @Local bubbleTextZh: string = ''
  @Local answeredLesson: RoomEnglishLessonResult | null = null

  private lesson: RoomEnglishLessonPlan | null = null
  private suppressSelectUntil: number = 0
  private advanceTimer: number = -1

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
    this.lesson = this.argsView.lesson
    this.bridge.speakHandler = (text: string, zh: string): boolean => this.speakWord(text, zh)
    this.bridge.stopHandler = (): void => this.stopSpeak()
    this.bridge.readyHandler = (): void => {
      this.runOnUi((): void => {
        this.pageReady = true
      })
    }
    this.bridge.selectHandler = (id: string, word: string): void => {
      this.runOnUi((): void => {
        if (Date.now() < this.suppressSelectUntil) {
          return
        }
        if (this.lessonMode === 'task') {
          this.handleTaskTap(id, word)
          return
        }
        this.noteSelected(id, word)
      })
    }
    this.bridge.progressHandler = (idsJson: string): void => {
      this.runOnUi((): void => {
        // 课程模式只统计孩子亲手点开的物品：Web 的 discovered 含程序化带逛/出题选中。
        if (this.lesson !== null) {
          return
        }
        this.applyProgress(idsJson)
      })
    }
    if (this.isAnswered) {
      this.readAnsweredPayload()
      this.lessonMode = 'answered'
    } else if (this.lesson !== null) {
      this.lessonMode = 'tour'
      this.taskState = createTaskState(this.lesson.task.targets)
      // 3D 场景加载期间先显示第一步讲解，避免空气泡空等
      if (this.lesson.steps.length > 0) {
        this.bubbleText = this.lesson.steps[0].say
        this.bubbleTextZh = this.lesson.steps[0].sayZh !== '' ? this.lesson.steps[0].sayZh : this.lesson.steps[0].zh
      }
    }
  }

  aboutToDisappear(): void {
    if (this.advanceTimer >= 0) {
      clearTimeout(this.advanceTimer)
      this.advanceTimer = -1
    }
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
      const lessonRaw = prev['lesson']
      if (lessonRaw !== undefined && lessonRaw !== null && typeof lessonRaw === 'object' && !Array.isArray(lessonRaw)) {
        this.answeredLesson = this.parseLessonResult(lessonRaw as Record<string, Object>)
      } else {
        this.answeredLesson = null
      }
    } catch (_e) {
      this.hasCompleted = false
      this.answeredLesson = null
    }
  }

  /** 回看态：宽松解析 lesson 统计，字段缺失时按 0 / false 兜底，不抛错。 */
  private parseLessonResult(raw: Record<string, Object>): RoomEnglishLessonResult {
    const result: RoomEnglishLessonResult = {
      tour_completed: raw['tour_completed'] === true,
      tour_words: readStringArray(raw['tour_words']),
      task_type: typeof raw['task_type'] === 'string' ? (raw['task_type'] as string) : '',
      task_targets: readStringArray(raw['task_targets']),
      task_correct: readNumber(raw['task_correct']),
      task_first_try: readNumber(raw['task_first_try']),
      task_revealed: readNumber(raw['task_revealed']),
      task_total: readNumber(raw['task_total']),
      task_attempts: readNumber(raw['task_attempts']),
      task_completed: raw['task_completed'] === true
    }
    return result
  }

  // ====== Web 控制 ======

  /** focus → 页面视图（living / dining / kitchen 都在客餐厅里，缺省打开全屋）。 */
  private focusRoom(): string {
    return resolveRoomEnglishView(this.argsView.focus)
  }

  /** 页面就绪后：先切到 focus 指定的房间，客餐厅再对准客厅/餐厅/厨房分区，
   *  最后把本次重点单词的第一件物品高亮出来（选中即自动朗读）。
   *  英文标签默认不显示，由孩子点场景里的「显示英文标签」开关手动打开。 */
  private applyFocusWords(): void {
    if (this.focusApplied || !this.pageReady) {
      return
    }
    const room = this.focusRoom()
    const area = resolveRoomEnglishArea(this.argsView.focus)
    const areaCall = area !== '' ? `app.setArea('${area}');` : ''
    const first = this.argsView.words.length > 0 ? `'${this.argsView.words[0]}'` : 'null'
    this.focusApplied = true
    const script = `(function(){try{var app=window.WordRoomApp;if(!app){return;}app.setRoom('${room}');` +
      areaCall + `if(${first}){app.select(${first});}}catch(e){}})();`
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

  private runWeb(script: string): Promise<string> {
    try {
      return this.controller.runJavaScript(script)
    } catch (e) {
      return Promise.reject(e)
    }
  }

  // ====== 引导式课程（spec 2026-10-30） ======

  private get lessonTargets(): string[] {
    return this.lesson !== null ? this.lesson.task.targets : []
  }

  private get tourStepCount(): number {
    return this.lesson !== null ? this.lesson.steps.length : 0
  }

  private stepForId(id: string): RoomLessonStep | null {
    if (this.lesson === null) {
      return null
    }
    for (let i = 0; i < this.lesson.steps.length; i++) {
      if (this.lesson.steps[i].id === id) {
        return this.lesson.steps[i]
      }
    }
    return null
  }

  /** id → 英文单词；不是本课步骤时退回 id。 */
  private wordForId(id: string): string {
    const step = this.stepForId(id)
    return step !== null ? step.word : id
  }

  /** Web 页面每次加载都会把 autoSpeak 重置为 true，所以每次 onPageEnd 都要重新关掉自动朗读。 */
  private startOrResumeLesson(): void {
    if (this.lesson === null) {
      return
    }
    this.runWeb('(function(){try{var app=window.WordRoomApp;if(app){app.setAutoSpeak(false);app.setLessonMode(true);}}catch(e){}})();')
      .catch((e: Error): void => {
        console.error('RoomEnglishCard', 'set auto speak failed: ' + e.message)
      })
    if (this.lessonMode === 'tour') {
      this.presentStep(this.tourIndex)
    } else if (this.lessonMode === 'task') {
      this.presentTaskStep()
    }
  }

  private presentStep(index: number): void {
    const lesson = this.lesson
    if (lesson === null || index < 0 || index >= lesson.steps.length) {
      this.tourCompleted = true
      this.startTask()
      return
    }
    const step = lesson.steps[index]
    this.tourIndex = index
    this.bubbleText = step.say
    // AI 省略 say_zh 时用单词中文兜底，气泡与 TTS 都要带中文
    const zh: string = step.sayZh !== '' ? step.sayZh : step.zh
    this.bubbleTextZh = zh
    const view = resolveRoomEnglishView(this.argsView.focus)
    const area = resolveRoomEnglishArea(this.argsView.focus)
    let script = '(function(){try{var app=window.WordRoomApp;if(!app){return;}app.setAutoSpeak(false);app.setRoom(\'' + view + '\');'
    if (area !== '') {
      script += 'app.setArea(\'' + area + '\');'
    }
    script += 'app.select(\'' + step.id + '\');}catch(e){}})();'
    this.suppressSelectUntil = Date.now() + 1000
    // select 会触发 Web 端 syncSelection → stopSpeak，必须等脚本执行完再朗读，否则刚开口就被打断
    this.runWeb(script).then((): void => {
      if (this.submitted || this.isAnswered) {
        return
      }
      this.speakWord(step.say, zh)
    }).catch((e: Error): void => {
      console.error('RoomEnglishCard', `present step failed: ${e.message}`)
      if (this.submitted || this.isAnswered) {
        return
      }
      this.speakWord(step.say, zh)
    })
  }

  private nextTourStep(): void {
    const next = nextTourIndex(this.tourIndex, this.tourStepCount)
    if (next < 0) {
      this.tourCompleted = true
      this.startTask()
    } else {
      this.presentStep(next)
    }
  }

  private skipTour(): void {
    this.tourCompleted = false
    this.startTask()
  }

  private startTask(): void {
    if (this.lesson === null) {
      return
    }
    // 带逛的程序化选中会开启 1s 抑制窗；进入任务阶段必须先清掉，否则首个目标点击会被丢弃
    this.suppressSelectUntil = 0
    this.lessonMode = 'task'
    this.taskState = createTaskState(this.lessonTargets)
    this.presentTaskStep()
  }

  private presentTaskStep(): void {
    const targets = this.lessonTargets
    if (targets.length === 0 || isTaskComplete(this.taskState, targets)) {
      this.finishTask()
      return
    }
    const targetId = currentTargetId(this.taskState, targets)
    const step = this.stepForId(targetId)
    if (step === null) {
      this.finishTask()
      return
    }
    this.bubbleText = buildTaskPrompt(step.word)
    this.bubbleTextZh = ''
    this.runWeb('(function(){try{var app=window.WordRoomApp;if(!app){return false;}app.setAutoSpeak(false);return app.prepareFind(\'' + step.id + '\');}catch(e){return false;}})();')
      .then((_result: string): void => {
        if (this.submitted || this.isAnswered) {
          return
        }
        this.speakBubble()
      })
      .catch((e: Error): void => {
        console.error('RoomEnglishCard', 'prepareFind failed: ' + e.message)
      })
  }

  private handleTaskTap(id: string, word: string): void {
    const targets = this.lessonTargets
    if (targets.length === 0) {
      return
    }
    const maxAttempts = this.lesson !== null ? this.lesson.task.maxAttempts : 2
    const result: RoomTaskTapResult = judgeTaskTap(this.taskState, targets, id, maxAttempts)
    if (result.verdict === 'ignore') {
      return
    }
    this.taskState = result.state
    this.noteSelected(id, word)
    const targetWord = this.wordForId(result.targetId)
    const step = this.stepForId(id)
    let tappedWord = id
    if (step !== null) {
      tappedWord = step.word
    } else if (word !== '') {
      tappedWord = word
    }
    if (result.verdict === 'correct') {
      this.bubbleText = buildSuccessPrompt(targetWord)
      this.bubbleTextZh = ''
      this.speakBubble()
      this.scheduleAdvance(1200)
    } else if (result.verdict === 'wrong') {
      this.bubbleText = buildWrongPrompt(tappedWord)
      this.bubbleTextZh = ''
      this.speakBubble()
    } else if (result.verdict === 'repeat_wrong') {
      this.speakBubble()
    } else if (result.verdict === 'reveal') {
      this.bubbleText = buildRevealPrompt(targetWord)
      this.bubbleTextZh = ''
      this.suppressSelectUntil = Date.now() + 1000
      this.runWeb('(function(){try{var app=window.WordRoomApp;if(!app){return;}app.setAutoSpeak(false);app.select(\'' + result.targetId + '\');}catch(e){}})();')
        .then((): void => {
          this.afterRevealSelect()
        })
        .catch((e: Error): void => {
          console.error('RoomEnglishCard', 'reveal select failed: ' + e.message)
          this.afterRevealSelect()
        })
    }
  }

  /** 高亮脚本结束后再朗读并推进，避免 Web 端 select 回声的 stopSpeak 打断 TTS；失败也推进，任务不会卡住。 */
  private afterRevealSelect(): void {
    if (this.submitted || this.isAnswered) {
      return
    }
    this.speakBubble()
    this.scheduleAdvance(1500)
  }

  private scheduleAdvance(delayMs: number): void {
    if (this.advanceTimer >= 0) {
      clearTimeout(this.advanceTimer)
    }
    this.advanceTimer = setTimeout((): void => {
      this.advanceTimer = -1
      this.advanceTaskStep()
    }, delayMs)
  }

  private advanceTaskStep(): void {
    const targets = this.lessonTargets
    this.taskState = advanceTask(this.taskState, targets)
    if (this.taskState.completed) {
      this.finishTask()
    } else {
      this.presentTaskStep()
    }
  }

  private finishTask(): void {
    this.lessonMode = 'summary'
    this.bubbleText = '太棒了！'
    this.bubbleTextZh = ''
    this.stopSpeak()
  }

  private speakBubble(): void {
    this.speakWord(this.bubbleText, this.bubbleTextZh)
  }

  // ====== 提交 ======

  private clearAdvanceTimer(): void {
    if (this.advanceTimer >= 0) {
      clearTimeout(this.advanceTimer)
      this.advanceTimer = -1
    }
  }

  private buildLessonResult(): RoomEnglishLessonResult | null {
    const lesson = this.lesson
    if (lesson === null) {
      return null
    }
    const tourWords: string[] = []
    for (let i = 0; i < lesson.steps.length; i++) {
      tourWords.push(lesson.steps[i].id)
    }
    const targets = this.lessonTargets
    const taskTargets: string[] = []
    for (let i = 0; i < targets.length; i++) {
      taskTargets.push(targets[i])
    }
    const result: RoomEnglishLessonResult = {
      tour_completed: this.tourCompleted,
      tour_words: tourWords,
      task_type: lesson.task.type,
      task_targets: taskTargets,
      task_correct: this.taskState.correct,
      task_first_try: this.taskState.firstTry,
      task_revealed: this.taskState.revealed,
      task_total: taskTargets.length,
      task_attempts: this.taskState.attempts,
      task_completed: this.taskState.completed
    }
    return result
  }

  private buildPayload(completed: boolean, cancelled: boolean): RoomEnglishAnswerPayload {
    const payload: RoomEnglishAnswerPayload = {
      completed: completed,
      explored_count: this.exploredCount,
      words: this.exploredIds,
      focus: this.argsView.focus,
      skill_key: 'english_vocab',
      cancelled: cancelled,
      lesson: this.buildLessonResult()
    }
    return payload
  }

  private canSubmit(): boolean {
    if (this.lesson !== null) {
      return this.lessonMode === 'summary' && this.taskState.completed && !this.isAnswered
    }
    return this.exploredCount > 0
  }

  private submit(): void {
    if (this.submitted || !this.canSubmit() || this.isAnswered) {
      return
    }
    this.submitted = true
    this.clearAdvanceTimer()
    const completed: boolean = this.lesson !== null ? this.taskState.completed : true
    const payload: RoomEnglishAnswerPayload = this.buildPayload(completed, false)
    this.stopSpeak()
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  /** 卡片右上角动作：带逛中「跳过带逛」，任务/小结中「退出本课」。 */
  private cancelLesson(): void {
    if (this.submitted || this.isAnswered) {
      return
    }
    this.submitted = true
    this.clearAdvanceTimer()
    this.stopSpeak()
    // 课程已结束时退出，completed 仍为 true（任务完成事实不变）；课程中途退出才是 false。
    const completed: boolean = this.lesson !== null ? this.taskState.completed : false
    const payload: RoomEnglishAnswerPayload = this.buildPayload(completed, true)
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  // ====== UI ======

  private get headerTitle(): string {
    return this.lessonMode === 'free' ? '3D 房间英语探索' : '3D 房间英语课'
  }

  private get headerSubtitle(): string {
    if (this.lessonMode === 'tour') {
      return `第 ${this.tourIndex + 1} / ${this.tourStepCount} 个词`
    }
    if (this.lessonMode === 'task') {
      return `任务 ${this.taskState.targetIndex + 1} / ${this.lessonTargets.length}`
    }
    if (this.lessonMode === 'summary' || this.lessonMode === 'answered') {
      return '本课完成'
    }
    return this.exploredCount > 0
      ? `已收集 ${this.exploredCount} / ${ROOM_OBJECT_TOTAL} 个单词`
      : '全屋、客餐厅、儿童房、主卧、阳台，点一点就知道它叫什么'
  }

  private get headerActionLabel(): string {
    if (this.lessonMode === 'tour') {
      return '跳过带逛'
    }
    if (this.lessonMode === 'task' || this.lessonMode === 'summary') {
      return '退出本课'
    }
    return this.exploredCount > 0 ? '我学会了' : '先探索一下'
  }

  private get headerActionEnabled(): boolean {
    if (this.submitted || this.isAnswered) {
      return false
    }
    if (this.lessonMode !== 'free') {
      return true
    }
    return this.canSubmit()
  }

  private get bubbleTitle(): string {
    if (this.lessonMode === 'task') {
      return '找一找'
    }
    if (this.lessonMode === 'summary') {
      return '本课小结'
    }
    return '小星老师'
  }

  private get summaryLine(): string {
    return `任务答对 ${this.taskState.correct} / ${this.lessonTargets.length}`
  }

  private get summarySubline(): string {
    let line = `第一次就找到 ${this.taskState.firstTry} 个`
    if (this.taskState.revealed > 0) {
      line += ` · 老师指了 ${this.taskState.revealed} 个`
    }
    return line
  }

  /** 回看态：把课程步骤 id 映射成英文单词，缺步骤时退回 id。 */
  private get tourWordsLabel(): string {
    const answered = this.answeredLesson
    if (answered === null) {
      return ''
    }
    const words: string[] = []
    for (let i = 0; i < answered.tour_words.length; i++) {
      const id = answered.tour_words[i]
      const step = this.stepForId(id)
      words.push(step !== null ? step.word : id)
    }
    return words.join(' / ')
  }

  private get answeredLessonSummary(): string {
    const answered = this.answeredLesson
    if (answered === null) {
      return ''
    }
    let line = `听词找物：答对 ${answered.task_correct} / ${answered.task_total} · 第一次就找到 ${answered.task_first_try}`
    if (answered.task_revealed > 0) {
      line += ` · 老师指了 ${answered.task_revealed} 个`
    }
    return line
  }

  private handleHeaderAction(): void {
    if (this.lessonMode === 'tour') {
      this.skipTour()
      return
    }
    if (this.lessonMode === 'task' || this.lessonMode === 'summary') {
      this.cancelLesson()
      return
    }
    this.submit()
  }

  @Builder
  HeaderBar() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.headerTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.headerSubtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
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
      .padding({ left: 14, right: 14 })
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
  LessonBubble() {
    Column() {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Column() {
            Text('英')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(withColorAlpha(this.themePrimary, '18'))
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text(this.bubbleTitle)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
            if (this.bubbleText !== '') {
              Text(this.bubbleText)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
            }
            if (this.bubbleTextZh !== '') {
              Text(this.bubbleTextZh)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            if (this.lessonMode === 'summary') {
              Text(this.summaryLine)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text(this.summarySubline)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: 8 }) {
          Button({ type: ButtonType.Capsule }) {
            Text('🔊 再听一次')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor(withColorAlpha(this.themePrimary, '14'))
          .onClick(() => {
            this.speakBubble()
          })

          if (this.lessonMode === 'tour') {
            Button({ type: ButtonType.Capsule }) {
              Text('下一个 ›')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
            }
            .height(30)
            .padding({ left: 12, right: 12 })
            .backgroundColor(this.themePrimary)
            .onClick(() => {
              this.nextTourStep()
            })
          }

          if (this.lessonMode === 'summary') {
            Button({ type: ButtonType.Capsule }) {
              Text('去答题，赢星星 ›')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
            }
            .height(30)
            .padding({ left: 12, right: 12 })
            .backgroundColor(this.themePrimary)
            .enabled(this.canSubmit())
            .onClick(() => {
              this.submit()
            })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
      .border({ width: 1, color: $r('app.color.divider') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 12 })
  }

  @Builder
  SummaryView() {
    Column({ space: 10 }) {
      Text(this.hasCompleted ? '房间探索完成' : '这次没有探索完')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.answeredLesson !== null) {
        Text(`本课带逛：${this.tourWordsLabel}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Text(this.answeredLessonSummary)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      } else {
        Text(`一共点开了 ${this.exploredCount} 个物品`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
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
              if (this.lesson !== null && !this.isAnswered) {
                this.startOrResumeLesson()
              } else {
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

        if (this.lessonMode !== 'free') {
          this.LessonBubble()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? '#101614' : '#f4f8f5')
  }
}
