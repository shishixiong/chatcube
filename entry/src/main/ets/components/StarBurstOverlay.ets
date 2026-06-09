/**
 * StarBurstOverlay - 星星授奖即时浮层
 *
 * 触发现场: ChatPage 收到 AppStorageKeys.STAR_EARNED_TICK 递增时,
 * 自增 burstTrigger 触发本组件内部的 @Monitor。
 *
 * 视觉:
 * 1. FloatStar (3 颗/burst): 屏幕下方 → 右上角 (标题栏菜单区域) 飘动,
 *    配 scale 0.6→1.3→1.0→0.5 + opacity 0→1→0, 1.2s 一组。
 * 2. BurstBadge: 浮动星中央的 "+N ⭐" 文字, 0.8s 渐显渐隐, 文字色 STAR_CELEBRATION_GOLD。
 * 3. MilestoneBanner: 当 total 跨越 5/10/15 阈值时,
 *    屏幕顶部居中滑入金色 banner "🎉 今日已达 N 颗 ⭐", 2.4s 停留后滑出。
 *
 * 设计取舍:
 * - 不做粒子 / confetti / 金币雨: 性能开销与场景收益不成正比。
 * - 浮星只用 3 颗: 6+ 颗在窄屏会重叠, 3 颗既能传达"多"又不会糊成一团。
 * - 不做"新纪录"边缘金光: HdsNavigationMenuItemOptions 不支持 chip 动画,
 *   等后续切到自定义 title bar 时再补。
 */

import { STAR_CELEBRATION_GOLD, STAR_SUCCESS_GREEN } from '../models/StarEventModels'
import { getAppUiState } from '../state/AppUiState'

interface FloatStarSpec {
  startXVp: number
  startYVp: number
  // 终点的横向偏移, 用来让 3 颗星的落点散开, 不重叠
  endXOffsetVp: number
  endXVp: number
  endYVp: number
  delayMs: number
  fontSize: number
  color: string
}

interface BurstSpec {
  id: string
  stars: number
  starsLayer: FloatStarSpec[]
}

interface MilestoneSpec {
  id: string
  total: number
}

const BURST_DURATION_MS: number = 1200
const BURST_BADGE_DURATION_MS: number = 800
const MILESTONE_HOLD_MS: number = 2400
// 终点横向 spread: 让左/中/右三颗星在右上角散开 (~25vp 间距)
const STAR_END_X_SPREAD_VP: number = 25

/**
 * FloatStar - 单颗浮动星, 自包含动画生命周期
 * 位置/缩放/透明度都通过 @Local + animation 驱动, aboutToAppear 推 3 段关键帧
 */
@ComponentV2
struct FloatStar {
  @Param startX: number = 0
  @Param startY: number = 0
  @Param endX: number = 0
  @Param endY: number = 0
  @Param delayMs: number = 0
  @Param fontSize: number = 32
  @Param color: string = STAR_CELEBRATION_GOLD

  @Local translateX: number = 0
  @Local translateY: number = 0
  @Local scaleValue: number = 0.6
  @Local opacityValue: number = 0
  @Local hasStarted: boolean = false
  private timerIds: number[] = []

  aboutToAppear(): void {
    this.timerIds.push(setTimeout((): void => {
      this.hasStarted = true
      // 阶段 1: 弹出 (scale 0.6 → 1.3, opacity 0 → 1)
      this.scaleValue = 1.3
      this.opacityValue = 1.0
      this.translateX = 0
      this.translateY = 0
    }, this.delayMs))

    this.timerIds.push(setTimeout((): void => {
      // 阶段 2: 飞行 (scale → 1.0, 平移到终点)
      this.scaleValue = 1.0
      this.translateX = this.endX - this.startX
      this.translateY = this.endY - this.startY
    }, this.delayMs + 300))

    this.timerIds.push(setTimeout((): void => {
      // 阶段 3: 缩小消失
      this.scaleValue = 0.5
      this.opacityValue = 0
    }, this.delayMs + BURST_DURATION_MS - 200))
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.timerIds.length; i++) {
      clearTimeout(this.timerIds[i])
    }
    this.timerIds = []
  }

  build() {
    Text('⭐')
      .fontSize(this.fontSize)
      .fontColor(this.color)
      .shadow({ radius: 6, color: '#40000000', offsetY: 2 })
      .position({ x: this.startX, y: this.startY })
      .translate({ x: this.translateX, y: this.translateY })
      .scale({ x: this.scaleValue, y: this.scaleValue })
      .opacity(this.opacityValue)
      .animation({
        duration: this.hasStarted ? 300 : 0,
        curve: Curve.EaseOut
      })
  }
}

/**
 * BurstBadge - "+N ⭐" 中心徽章
 */
@ComponentV2
struct BurstBadge {
  @Param stars: number = 0
  @Event onComplete: () => void = () => {}

  @Local scaleValue: number = 0.4
  @Local opacityValue: number = 0
  private timerIds: number[] = []

  aboutToAppear(): void {
    this.timerIds.push(setTimeout((): void => {
      this.scaleValue = 1.0
      this.opacityValue = 1.0
    }, 80))

    this.timerIds.push(setTimeout((): void => {
      this.scaleValue = 1.15
    }, 400))

    this.timerIds.push(setTimeout((): void => {
      this.scaleValue = 0.6
      this.opacityValue = 0
    }, 700))

    this.timerIds.push(setTimeout((): void => {
      this.onComplete()
    }, 400 + BURST_BADGE_DURATION_MS))
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.timerIds.length; i++) {
      clearTimeout(this.timerIds[i])
    }
    this.timerIds = []
  }

  build() {
    Text(`+${this.stars} ⭐`)
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor(STAR_CELEBRATION_GOLD)
      .shadow({ radius: 8, color: '#80000000', offsetY: 2 })
      .position({ x: '50%', y: '65%' })
      .translate({ x: '-50%', y: 0 })
      .scale({ x: this.scaleValue, y: this.scaleValue })
      .opacity(this.opacityValue)
      .animation({
        duration: 350,
        curve: Curve.EaseOut
      })
  }
}

/**
 * MilestoneBanner - 顶部金色里程碑 banner
 */
@ComponentV2
struct MilestoneBanner {
  @Param total: number = 0
  @Event onComplete: () => void = () => {}

  @Local scaleValue: number = 0.4
  @Local opacityValue: number = 0
  @Local translateY: number = -100
  private timerIds: number[] = []

  aboutToAppear(): void {
    this.timerIds.push(setTimeout((): void => {
      this.scaleValue = 1.0
      this.opacityValue = 1.0
      this.translateY = 0
    }, 50))

    this.timerIds.push(setTimeout((): void => {
      this.scaleValue = 0.8
      this.opacityValue = 0
      this.translateY = -40
    }, MILESTONE_HOLD_MS))

    this.timerIds.push(setTimeout((): void => {
      this.onComplete()
    }, MILESTONE_HOLD_MS + 600))
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.timerIds.length; i++) {
      clearTimeout(this.timerIds[i])
    }
    this.timerIds = []
  }

  build() {
    Row({ space: 8 }) {
      Text('🎉')
        .fontSize(22)
      Text(`今日已达 ${this.total} 颗 ⭐`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .padding({ left: 20, right: 20, top: 10, bottom: 10 })
    .backgroundColor(STAR_CELEBRATION_GOLD)
    .borderRadius(24)
    .shadow({ radius: 12, color: '#60000000', offsetY: 4 })
    .position({ x: '50%', y: '8%' })
    .translate({ x: '-50%', y: this.translateY })
    .scale({ x: this.scaleValue, y: this.scaleValue })
    .opacity(this.opacityValue)
    .animation({
      duration: 500,
      curve: Curve.EaseOut
    })
  }
}

@ComponentV2
export struct StarBurstOverlay {
  // 父级 (ChatPage) 每次自增时, 触发一次 burst; @Monitor 监听其变化
  @Param burstTrigger: number = 0
  // 父级传入的容器尺寸, 浮星位置才能算 vp (默认按 360×800, 避免窗口未初始化时崩)
  @Param containerWidthVp: number = 360
  @Param containerHeightVp: number = 800

  @Local activeBursts: BurstSpec[] = []
  @Local activeMilestones: MilestoneSpec[] = []
  // 内存中追踪当前"已庆祝过的最高阈值", 避免 5 颗后每次授星都重复触发 banner
  @Local celebratedThreshold: number = 0
  // 单调递增的 burst id 计数器, 避免 Date.now() 同毫秒碰撞
  private static burstIdCounter: number = 0
  private static milestoneIdCounter: number = 0

  aboutToAppear(): void {
    // 初始化时拉一次今日总数, 把 celebratedThreshold 校准到当前水平
    // (避免跨天 / 重新进入页面时, 上次会话的 5 颗后再次被触发)
    this.syncCelebratedThresholdFromState()
  }

  @Monitor('burstTrigger')
  onBurstTriggerChanged(): void {
    if (this.burstTrigger <= 0) {
      return
    }
    const uiState = getAppUiState()
    this.triggerBurst(uiState.starLastGrant, this.readTotalFromSummary(uiState.starTodaySummary))
  }

  private readTotalFromSummary(summaryJson: string): number {
    if (summaryJson === '') {
      return 0
    }
    try {
      const summary = JSON.parse(summaryJson) as Record<string, Object>
      return (summary['total'] as number) ?? 0
    } catch (_e) {
      return 0
    }
  }

  private syncCelebratedThresholdFromState(): void {
    const uiState = getAppUiState()
    this.celebratedThreshold = this.computeMilestoneThreshold(this.readTotalFromSummary(uiState.starTodaySummary))
  }

  private triggerBurst(grantJson: string, newTotal: number): void {
    if (grantJson === '') {
      return
    }
    let stars = 0
    try {
      const parsed = JSON.parse(grantJson) as Record<string, Object>
      stars = (parsed['stars'] as number) ?? 0
    } catch (_e) {
      return
    }
    if (stars <= 0) {
      return
    }
    const burst: BurstSpec = {
      id: `burst_${++StarBurstOverlay.burstIdCounter}`,
      stars: stars,
      starsLayer: this.buildFloatStarLayer(this.containerWidthVp, this.containerHeightVp)
    }
    this.activeBursts = [...this.activeBursts, burst]

    const newThreshold = this.computeMilestoneThreshold(newTotal)
    if (newThreshold > 0 && newThreshold > this.celebratedThreshold) {
      const milestone: MilestoneSpec = {
        id: `ms_${++StarBurstOverlay.milestoneIdCounter}`,
        total: newTotal
      }
      this.activeMilestones = [...this.activeMilestones, milestone]
      this.celebratedThreshold = newThreshold
    }
  }

  private computeMilestoneThreshold(total: number): number {
    if (total >= 15) return 15
    if (total >= 10) return 10
    if (total >= 5) return 5
    return 0
  }

  private removeBurst(id: string): void {
    this.activeBursts = this.activeBursts.filter((b: BurstSpec): boolean => b.id !== id)
  }

  private removeMilestone(id: string): void {
    this.activeMilestones = this.activeMilestones.filter((m: MilestoneSpec): boolean => m.id !== id)
  }

  private pctToVp(percent: number, totalVp: number): number {
    return (percent / 100) * totalVp
  }

  /**
   * 生成 3 颗浮星的预计算 spec, 颜色由 index 派生 (奇数绿, 偶数金)
   * 起点/终点在调用时换算成 vp, 避免在 build 路径反复算 (Quality #2)
   */
  private buildFloatStarLayer(widthVp: number, heightVp: number): FloatStarSpec[] {
    const startPositions: Array<[number, number]> = [[30, 70], [50, 72], [70, 70]]
    const endPositions: Array<[number, number]> = [[78, 14], [86, 10], [92, 14]]
    const fontSizes: number[] = [30, 40, 26]
    const delays: number[] = [0, 60, 120]
    const layer: FloatStarSpec[] = []
    for (let i = 0; i < 3; i++) {
      const startPos = startPositions[i]
      const endPos = endPositions[i]
      const xOffset = (i - 1) * STAR_END_X_SPREAD_VP
      layer.push({
        startXVp: this.pctToVp(startPos[0], widthVp),
        startYVp: this.pctToVp(startPos[1], heightVp),
        endXOffsetVp: xOffset,
        endXVp: this.pctToVp(endPos[0], widthVp) + xOffset,
        endYVp: this.pctToVp(endPos[1], heightVp),
        delayMs: delays[i],
        fontSize: fontSizes[i],
        color: i % 2 === 0 ? STAR_CELEBRATION_GOLD : STAR_SUCCESS_GREEN
      })
    }
    return layer
  }

  build() {
    Stack() {
      ForEach(this.activeBursts, (burst: BurstSpec): void => {
        ForEach(burst.starsLayer, (spec: FloatStarSpec): void => {
          FloatStar({
            startX: spec.startXVp,
            startY: spec.startYVp,
            endX: spec.endXVp,
            endY: spec.endYVp,
            delayMs: spec.delayMs,
            fontSize: spec.fontSize,
            color: spec.color
          })
        }, (spec: FloatStarSpec, index: number): string => `${burst.id}_star_${index}`)

        BurstBadge({
          stars: burst.stars,
          onComplete: (): void => {
            this.removeBurst(burst.id)
          }
        })
      }, (burst: BurstSpec): string => burst.id)

      ForEach(this.activeMilestones, (ms: MilestoneSpec): void => {
        MilestoneBanner({
          total: ms.total,
          onComplete: (): void => {
            this.removeMilestone(ms.id)
          }
        })
      }, (ms: MilestoneSpec): string => ms.id)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
