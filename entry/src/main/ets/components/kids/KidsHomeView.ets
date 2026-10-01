import { BusinessError } from '@kit.BasicServicesKit'
import { ChatSession } from '../../models/ChatModels'
import { DEFAULT_ASSISTANT_ID, KIDS_BUILT_IN_ASSISTANT_IDS } from '../../models/AssistantModels'
import { StarEventRow, TodayStarSummary } from '../../models/StarEventModels'
import { getStarRewardService } from '../../services/StarRewardService'
import { getDatabaseService } from '../../services/DatabaseService'
import { getChildProfileService, ChildKnowledgeProfile } from '../../services/ChildProfileService'
import { getDayPartGreeting } from '../../utils/GreetingUtils'
import { getStartOfDayMs } from '../../utils/DateFormatUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  countTodayBySubject,
  findTodaySession,
  formatDateLabel,
  formatWeekday,
  groupSessionsByDay,
  KidsDayGroup
} from '../../utils/KidsSubjectUtils'
import { KIDS_SUBJECTS, KidsSubjectItem } from './KidsSubjectCatalog'
import { ParentalGateSheet } from './ParentalGateSheet'
import { KidsDayGroupCard } from './KidsDayGroupCard'
import { KidsStarDetailSheet } from './KidsStarDetailSheet'
import {
  KIDS_BG, KIDS_SURFACE, KIDS_FG, KIDS_MUTED, KIDS_SUBTLE, KIDS_BORDER,
  KIDS_ACCENT, KIDS_ACCENT_2, KIDS_ON_HERO, KIDS_ON_HERO_2,
  KIDS_AVATAR_INK, KIDS_AVATAR_1, KIDS_AVATAR_2, KIDS_GLASS
} from './KidsBrandTokens'

/** 学习乐园最多显示的「有记录的天」数 */
const KIDS_GARDEN_DAY_LIMIT: number = 7

/**
 * 儿童主屏 v2（spec 2026-09-15 三段式布局）:
 * 问候行（昵称头像 + 时段问候 + 星星药丸）-> hero 一天一会话主卡（今日日期眉标 +
 * 静态星星图标 + 两态副文案 + 主 CTA + 今日星星徽章 + 看明细）-> 2×2 学科卡
 * 「来获取星星」-> 学习乐园按天分组（KidsDayGroupCard，7 天上限，同日 >3 折叠）
 * -> 居中家长入口。
 *
 * hero 一天一会话: 今日的小星老师会话存在 -> onOpenSession 续接，否则
 * onNewChat('', DEFAULT) 开新会话。学科卡同为一天一会话（按学科 assistantId
 * 判定今日会话，有则 onOpenSession 续接），startPrompt 仅在新会话时传入、
 * 由 ChatPage 转成学科老师开场元指令（老师先开口，不再作为孩子消息发出）。
 * 学科卡仍受 dailyLimit 每日上限约束（学数学/英语/语文各 10、小游戏 20，
 * 按「今日 N 题/局」口径计数）——达上限后卡片降透明度置灰、点击无响应，次日自动恢复。
 * 恒定暖色绘本令牌（KidsBrandTokens），不随深色模式切换；图标一律 SVG，无 emoji。
 * 星星数据自加载, starRefreshTick 由宿主在导航栈 didShow(navBar) 时递增触发刷新。
 */
@ComponentV2
export struct KidsHomeView {
  @Param sessions: ChatSession[] = []
  @Param starRefreshTick: number = 0
  @Param topInsetVp: number = 0
  @Event onOpenSession: (sessionId: string) => void = () => {}
  /** 新建会话：hero 传 ('', DEFAULT)；学科卡传 (startPrompt, 学科 assistantId)——startPrompt 现为老师开场上下文 */
  @Event onNewChat: (initialPrompt: string, assistantId: string) => void = () => {}
  @Event onGatePassed: () => void = () => {}
  @Local totalStars: number = 0
  @Local todayStars: number = 0
  @Local todayEvents: StarEventRow[] = []
  @Local childName: string = ''
  @Local starBySession: Map<string, number> = new Map()
  @Local starByDay: Map<string, number> = new Map()
  /**
   * 星星 Map 异步加载完成计数（单调递增）。starByDay/starBySession 均为 DB 异步加载，
   * 解析后 @Local Map 引用变化不足以驱动 GardenSection 的 ForEach 重建子组件（key 未变时
   * ArkUI 复用旧 KidsDayGroupCard，@Param 不刷新）。把它折进 ForEach key，保证任一 Map
   * 落地后 key 变化 -> 子组件按新数据重挂。
   */
  @Local starLoadTick: number = 0
  @Local showGateSheet: boolean = false
  @Local showStarDetailSheet: boolean = false
  /** 按压反馈（spec §7: scale 0.98 + 60-80ms）: hero 卡 */
  @Local heroPressed: boolean = false
  /** 按压反馈: 当前按下的学科卡 id（'' = 无） */
  @Local pressedSubjectId: string = ''

  @Monitor('starRefreshTick')
  onStarRefreshTickChanged(): void {
    this.loadAll()
  }

  @Monitor('sessions')
  onSessionsChanged(): void {
    // 分组/今日会话是 build 内派生计算，sessions 变化自动生效；但 starByDay 是按最早
    // 显示天算 sinceMs 的异步 DB 加载——冷启动时 sessions 可能尚未就绪（分组为空 ->
    // starByDay 空 Map 且不再重试）。sessions 到达后必须重新触发 loadStarByDay。
    this.loadStarByDay()
  }

  aboutToAppear(): void {
    this.loadAll()
  }

  private loadAll(): void {
    getStarRewardService().getAllTimeStarTotal().then((total: number): void => {
      this.totalStars = total
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load total stars: ${(error as BusinessError).message ?? String(error)}`)
    })
    getStarRewardService().getTodaySummary().then((summary: TodayStarSummary): void => {
      this.todayStars = summary.total
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load today summary: ${(error as BusinessError).message ?? String(error)}`)
      this.todayStars = 0
    })
    getStarRewardService().getTodayEvents().then((events: StarEventRow[]): void => {
      this.todayEvents = events
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load today events: ${(error as BusinessError).message ?? String(error)}`)
      this.todayEvents = []
    })
    getDatabaseService().getStarTotalsBySession().then((totals: Map<string, number>): void => {
      this.starBySession = totals
      this.starLoadTick++
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load session star totals: ${(error as BusinessError).message ?? String(error)}`)
      this.starBySession = new Map()
    })
    this.loadChildName()
    this.loadStarByDay()
  }

  private loadChildName(): void {
    getChildProfileService().getProfile().then((profile: ChildKnowledgeProfile): void => {
      this.childName = profile.childName.trim()
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load child profile: ${(error as BusinessError).message ?? String(error)}`)
      this.childName = ''
    })
  }

  /** sinceMs = 最早显示天的 0 点（先分组拿最早 session，再查按天汇总） */
  private loadStarByDay(): void {
    const groups: KidsDayGroup[] = this.dayGroups()
    if (groups.length === 0) {
      this.starByDay = new Map()
      return
    }
    const lastGroup: KidsDayGroup = groups[groups.length - 1]
    const oldest: ChatSession = lastGroup.sessions[lastGroup.sessions.length - 1]
    const sinceMs: number = getStartOfDayMs(oldest.updatedAt)
    getDatabaseService().getStarTotalsByDay(sinceMs).then((totals: Map<string, number>): void => {
      this.starByDay = totals
      this.starLoadTick++
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load day star totals: ${(error as BusinessError).message ?? String(error)}`)
      this.starByDay = new Map()
    })
  }

  /** 5 个内置助手的会话（'' 遗留会话不可见），updatedAt 降序 */
  private kidsSessions(): ChatSession[] {
    const filtered: ChatSession[] = this.sessions.filter((session: ChatSession): boolean =>
      KIDS_BUILT_IN_ASSISTANT_IDS.includes(session.assistantId))
    filtered.sort((a: ChatSession, b: ChatSession): number => b.updatedAt - a.updatedAt)
    return filtered
  }

  private todayDefaultSessions(): ChatSession[] {
    return this.kidsSessions().filter((session: ChatSession): boolean =>
      session.assistantId === DEFAULT_ASSISTANT_ID)
  }

  /** hero 一天一会话：今日的小星老师会话（无则 null） */
  private todaySession(): ChatSession | null {
    return findTodaySession(this.todayDefaultSessions(), getStartOfDayMs(Date.now()))
  }

  /** 学科一天一会话：今日该学科助手的会话（无则 null） */
  private todaySessionFor(assistantId: string): ChatSession | null {
    const subjectSessions: ChatSession[] = this.kidsSessions().filter((session: ChatSession): boolean =>
      session.assistantId === assistantId)
    return findTodaySession(subjectSessions, getStartOfDayMs(Date.now()))
  }

  private dayGroups(): KidsDayGroup[] {
    return groupSessionsByDay(this.kidsSessions(), Date.now(), KIDS_GARDEN_DAY_LIMIT)
  }

  private todayCountFor(subject: KidsSubjectItem): number {
    return countTodayBySubject(this.todayEvents, subject.activityTypes)
  }

  /** 是否达到每日上限（今日 N 题/局口径，达上限当日不再开新会话） */
  private isCapped(subject: KidsSubjectItem): boolean {
    return this.todayCountFor(subject) >= subject.dailyLimit
  }

  private displayName(): string {
    return this.childName.length > 0 ? this.childName : '小朋友'
  }

  private avatarChar(): string {
    return this.childName.length > 0 ? this.childName.substring(0, 1) : ''
  }

  private greetingText(): string {
    return `${getDayPartGreeting(new Date().getHours())}，${this.displayName()}`
  }

  private heroDateLabel(): string {
    const now: number = Date.now()
    return `今日学习 · ${formatDateLabel(now)} ${formatWeekday(now)}`
  }

  private heroSubtitle(): string {
    return this.todaySession() !== null ?
      '小星老师 · 已进入今天的会话' :
      '小星老师 · 今天第一次学习，将开启新会话'
  }

  build() {
    Column() {
      // ── 问候行: 昵称头像 + 时段问候 + 星星药丸（固定不滚动） ──
      Row({ space: 12 }) {
        if (this.avatarChar().length > 0) {
          Text(this.avatarChar())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_AVATAR_INK)
            .width(46)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .linearGradient({ angle: 150, colors: [[KIDS_AVATAR_1, 0], [KIDS_AVATAR_2, 1]] })
            .shadow({ radius: 10, color: '#59FF9F43', offsetY: 4 })
        } else {
          // 无昵称 fallback: star.svg（去 emoji，spec §4.2）
          Column() {
            Image($rawfile('kids/star.svg')).width(24).height(24)
          }
          .width(46)
          .height(46)
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .linearGradient({ angle: 150, colors: [[KIDS_AVATAR_1, 0], [KIDS_AVATAR_2, 1]] })
          .shadow({ radius: 10, color: '#59FF9F43', offsetY: 4 })
        }

        Column({ space: 2 }) {
          Text(this.greetingText())
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('今天想和小星老师玩点什么？')
            .fontSize(12)
            .fontColor(KIDS_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 6 }) {
          Image($rawfile('kids/star.svg')).width(14).height(14)
          Text(`${this.totalStars}`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
          Text('颗')
            .fontSize(11)
            .fontColor(KIDS_MUTED)
        }
        .padding({ left: 13, right: 13, top: 8, bottom: 8 })
        .borderRadius(999)
        .backgroundColor(KIDS_SURFACE)
        .border({ width: 1, color: KIDS_BORDER })
        .shadow({ radius: 6, color: '#1A24211C', offsetY: 2 })
        .accessibilityText(`累计获得 ${this.totalStars} 颗星`)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topInsetVp + 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          this.HeroCard()
          this.SubjectSection()
          if (this.kidsSessions().length > 0) {
            this.GardenSection()
          }
          this.ParentEntry()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // bindSheet 宿主：每个 bindSheet 必须挂在独立组件上，避免多 bindSheet 冲突
      // （同节点链两个 sheet 时，后注册的会在重渲染时顶掉先挂载的——家长门弹窗即开即关）
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showGateSheet, this.GateSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          preferType: SheetType.BOTTOM,
          onDisappear: (): void => {
            this.showGateSheet = false
          }
        })
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showStarDetailSheet, this.StarDetailSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          preferType: SheetType.BOTTOM,
          onDisappear: (): void => {
            this.showStarDetailSheet = false
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
  }

  @Builder
  HeroCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 右上玻璃圆装饰（静态，无动画）
      Column()
        .width(130)
        .height(130)
        .borderRadius(65)
        .backgroundColor(KIDS_GLASS)
        .margin({ top: -34, right: -34 })

      Column({ space: 14 }) {
        // 眉标: mono 10.5vp
        Text(this.heroDateLabel())
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(KIDS_ON_HERO_2)
          .letterSpacing(1)

        Row({ space: 14 }) {
          // 静态星星图标块（替代 v1 吉祥物循环浮动，spec §8）
          Column() {
            Image($rawfile('kids/star.svg')).width(40).height(40)
          }
          .width(76)
          .height(76)
          .borderRadius(24)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#EBFFFDF8')
          .shadow({ radius: 14, color: '#333A2506', offsetY: 6 })

          Column({ space: 3 }) {
            Text('继续学习')
              .fontSize(23)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_ON_HERO)
            // 副文案允许换行不 ellipsis（v2.2 修正 6）
            Text(this.heroSubtitle())
              .fontSize(12.5)
              .fontColor(KIDS_ON_HERO_2)
              .lineHeight(19)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        Column({ space: 10 }) {
          // 主 CTA 白底胶囊 ≥44vp，独占一行（窄屏单行三件套会裁掉看明细）
          Row({ space: 8 }) {
            Text('开始今天的学习')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_FG)
            Image($rawfile('kids/chevron.svg')).width(14).height(14)
          }
          .width('100%')
          .height(46)
          .justifyContent(FlexAlign.Center)
          .borderRadius(999)
          .backgroundColor(KIDS_SURFACE)
          .shadow({ radius: 14, color: '#403A2506', offsetY: 6 })

          Row() {
            // 今日星星徽章（N=0 也显示——「今天还没来」动机）
            Row({ space: 5 }) {
              Image($rawfile('kids/star.svg')).width(12).height(12)
              Text(`今日 +${this.todayStars}`)
                .fontSize(12.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(KIDS_ON_HERO)
            }
            .padding({ left: 13, right: 13, top: 9, bottom: 9 })
            .borderRadius(999)
            .backgroundColor('#243A2506')
            .accessibilityText(`今日获得 ${this.todayStars} 颗星`)

            Blank()

            // 看明细（44vp 触控高、描边胶囊）
            Text('看明细')
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(KIDS_ON_HERO)
              .padding({ left: 14, right: 14 })
              .height(44)
              .borderRadius(999)
              .border({ width: 1.5, color: '#333A2506' })
              .textAlign(TextAlign.Center)
              .onClick((): void => {
                this.showStarDetailSheet = true
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
      }
      .padding(20)
      .width('100%')
    }
    .width('100%')
    .borderRadius(24)
    .clip(true)
    .linearGradient({ angle: 135, colors: [[KIDS_ACCENT, 0], [KIDS_ACCENT_2, 1]] })
    .shadow({ radius: 28, color: '#66FF9F43', offsetY: 10 })
    .scale(this.heroPressed ? { x: 0.98, y: 0.98 } : { x: 1, y: 1 })
    .animation({ duration: 70, curve: Curve.EaseOut })
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.heroPressed = true
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.heroPressed = false
      }
    })
    .onClick((): void => {
      // 一天一会话: 已有今日会话 -> 续接; 否则开新会话
      const today: ChatSession | null = this.todaySession()
      if (today !== null) {
        this.onOpenSession(today.id)
      } else {
        this.onNewChat('', DEFAULT_ASSISTANT_ID)
      }
    })
  }

  @Builder
  SubjectSection() {
    Column({ space: 12 }) {
      Row() {
        Text('来获取星星')
          .fontSize(17.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Blank()
        Text('选一个，马上开始')
          .fontSize(11.5)
          .fontColor(KIDS_SUBTLE)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Row({ space: 12 }) {
        this.SubjectCard(KIDS_SUBJECTS[0])
        this.SubjectCard(KIDS_SUBJECTS[1])
      }
      .width('100%')

      Row({ space: 12 }) {
        this.SubjectCard(KIDS_SUBJECTS[2])
        this.SubjectCard(KIDS_SUBJECTS[3])
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  SubjectCard(item: KidsSubjectItem) {
    Column() {
      Row({ space: 10 }) {
        // 图标块 44vp / 圆角 14 / 学科色 15% 淡底
        Column() {
          Image($rawfile(item.iconPath)).width(24).height(24)
        }
        .width(44)
        .height(44)
        .borderRadius(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(withColorAlpha(item.color, '26'))

        Column({ space: 2 }) {
          Text(item.label)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
          // 副标题固定 2 行高，保证卡片等高
          Text(item.subtitle)
            .fontSize(11.5)
            .fontColor(KIDS_MUTED)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .height(30)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 底部状态行: 1px 虚线上边框 + 今日计数（达上限换文案） + 开始 ›/继续 ›/明天见
      Row() {
        Text(this.isCapped(item) ?
          '今天练够啦，明天再来' :
          (this.todayCountFor(item) > 0 ?
            `今日 ${this.todayCountFor(item)} ${item.countUnit}` :
            (item.id === 'games' ? '今天还没玩' : '今天还没练')))
          .fontSize(10.5)
          .fontColor(KIDS_SUBTLE)
        Blank()
        Text(this.isCapped(item) ?
          '明天见' :
          (this.todaySessionFor(item.assistantId) !== null ? '继续 ›' : '开始 ›'))
          .fontSize(11.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isCapped(item) ? KIDS_SUBTLE : item.ink)
      }
      .width('100%')
      .height(30)
      .alignItems(VerticalAlign.Center)
      .border({ width: { top: 1 }, color: KIDS_BORDER, style: { top: BorderStyle.Dashed } })
    }
    .layoutWeight(1)
    .padding({ left: 14, right: 14, top: 14, bottom: 6 })
    .borderRadius(19)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .shadow({ radius: 8, color: '#1424211C', offsetY: 3 })
    .opacity(this.isCapped(item) ? 0.55 : 1)
    .accessibilityText(this.isCapped(item) ? `${item.label}今天练够啦` : `打开${item.label}`)
    .scale(this.pressedSubjectId === item.id ? { x: 0.98, y: 0.98 } : { x: 1, y: 1 })
    .animation({ duration: 70, curve: Curve.EaseOut })
    .onTouch((e: TouchEvent): void => {
      if (this.isCapped(item)) {
        return
      }
      if (e.type === TouchType.Down) {
        this.pressedSubjectId = item.id
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedSubjectId = ''
      }
    })
    .onClick((): void => {
      // 每日上限: 达到后当日整卡禁用（含进入会话）
      if (this.isCapped(item)) {
        return
      }
      // 学科一天一会话: 已有今日会话 -> 续接; 否则开新会话（老师先开口）
      const today: ChatSession | null = this.todaySessionFor(item.assistantId)
      if (today !== null) {
        this.onOpenSession(today.id)
      } else {
        this.onNewChat(item.startPrompt, item.assistantId)
      }
    })
  }

  @Builder
  GardenSection() {
    Column({ space: 12 }) {
      Row() {
        Text('我的学习乐园')
          .fontSize(17.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Blank()
        Text(`共 ${this.kidsSessions().length} 次学习`)
          .fontSize(11.5)
          .fontColor(KIDS_SUBTLE)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      ForEach(this.dayGroups(), (group: KidsDayGroup): void => {
        KidsDayGroupCard({
          group: group,
          dayStars: this.starByDay.get(group.dayKey) ?? 0,
          starBySession: this.starBySession,
          onOpenSession: (sessionId: string): void => {
            this.onOpenSession(sessionId)
          }
        })
      }, (group: KidsDayGroup): string =>
        `${group.dayKey}_${group.sessions.length}_${this.starByDay.get(group.dayKey) ?? 0}_${this.starRefreshTick}_${this.starLoadTick}`)
    }
    .width('100%')
  }

  @Builder
  ParentEntry() {
    Row({ space: 6 }) {
      Image($rawfile('kids/lock.svg')).width(13).height(13)
      Text('家长入口')
        .fontSize(12)
        .fontColor(KIDS_SUBTLE)
    }
    .width('100%')
    .height(46)
    .borderRadius(12)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      this.showGateSheet = true
    })
  }

  @Builder
  GateSheetBuilder() {
    ParentalGateSheet({
      onPassed: (): void => {
        this.showGateSheet = false
        this.onGatePassed()
      },
      onCancelled: (): void => {
        this.showGateSheet = false
      }
    })
  }

  @Builder
  StarDetailSheetBuilder() {
    KidsStarDetailSheet({
      onClose: (): void => {
        this.showStarDetailSheet = false
      }
    })
  }
}
