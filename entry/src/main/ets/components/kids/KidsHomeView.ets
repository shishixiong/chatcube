import { ChatSession } from '../../models/ChatModels'
import { DEFAULT_ASSISTANT_ID } from '../../models/AssistantModels'
import { getStarRewardService } from '../../services/StarRewardService'
import { getDatabaseService } from '../../services/DatabaseService'
import { getChildProfileService, ChildKnowledgeProfile } from '../../services/ChildProfileService'
import { formatRelativeTime } from '../../utils/TimeFormatUtils'
import { getDayPartGreeting } from '../../utils/GreetingUtils'
import { getStartOfWeekMs } from '../../utils/DateFormatUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ParentalGateSheet } from './ParentalGateSheet'
import { KidsSessionCard } from './KidsSessionCard'
import { KIDS_ACTIVITIES, KidsActivityItem } from './KidsActivityCatalog'
import {
  KIDS_BG,
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_MUTED,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_ACCENT,
  KIDS_ACCENT_2,
  KIDS_ON_HERO,
  KIDS_ON_HERO_2,
  KIDS_AVATAR_INK,
  KIDS_AVATAR_1,
  KIDS_AVATAR_2,
  KIDS_GLASS,
  KIDS_INK_SOFT
} from './KidsBrandTokens'

/** 活动宫格单块高度（12 上衬 + 42 图标 + 7 间距 + ~14 标签 + 10 下衬） */
const ACTIVITY_TILE_HEIGHT: number = 85
/** 会话卡高度（与 KidsSessionCard 固定高度一致） */
const SESSION_CARD_HEIGHT: number = 118
/** 「我的学习乐园」最多保留的会话记录数（最近的 N 条，防网格无限增长） */
const KIDS_SESSION_DISPLAY_LIMIT: number = 20

/**
 * 儿童主屏（对照 docs/kids-home-prototype.html 五区块布局）:
 * 问候行（昵称头像 + 时段问候 + 星星药丸）→ 小星老师主卡（吉祥物 + CTA + 本周徽章）
 * → 活动八宫格「今天想玩什么」→ 2 列会话网格「我的学习乐园」→ 居中家长入口。
 *
 * 列表只读（无长按/删除/多选）; 只显示 assistantId === 'default' 的会话。
 * 恒定暖色绘本令牌（KidsBrandTokens），不随深色模式切换。
 * 星星数据自加载, starRefreshTick 由宿主在导航栈 didShow(navBar) 时递增触发刷新。
 */
@ComponentV2
export struct KidsHomeView {
  @Param sessions: ChatSession[] = []
  @Param starRefreshTick: number = 0
  @Param topInsetVp: number = 0
  @Event onOpenSession: (sessionId: string) => void = () => {}
  /** 新建小星老师会话; initialPrompt 非空时进入会话后自动发送（活动八宫格引导语） */
  @Event onNewChat: (initialPrompt: string) => void = () => {}
  @Event onGatePassed: () => void = () => {}
  @Local totalStars: number = 0
  @Local weekStars: number = 0
  @Local childName: string = ''
  @Local starBySession: Map<string, number> = new Map()
  @Local showGateSheet: boolean = false
  @Local mascotFloatY: number = 0

  @Monitor('starRefreshTick')
  onStarRefreshTickChanged(): void {
    this.loadStars()
    this.loadChildName()
  }

  aboutToAppear(): void {
    this.loadStars()
    this.loadChildName()
  }

  private loadStars(): void {
    getStarRewardService().getAllTimeStarTotal().then((total: number): void => {
      this.totalStars = total
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load total stars: ${JSON.stringify(error)}`)
    })
    getStarRewardService().getStarsSinceMs(getStartOfWeekMs(Date.now())).then((total: number): void => {
      this.weekStars = total
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load week stars: ${JSON.stringify(error)}`)
      this.weekStars = 0
    })
    getDatabaseService().getStarTotalsBySession().then((totals: Map<string, number>): void => {
      this.starBySession = totals
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load session star totals: ${JSON.stringify(error)}`)
      this.starBySession = new Map()
    })
  }

  private loadChildName(): void {
    getChildProfileService().getProfile().then((profile: ChildKnowledgeProfile): void => {
      this.childName = profile.childName.trim()
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load child profile: ${JSON.stringify(error)}`)
      this.childName = ''
    })
  }

  private kidsSessions(): ChatSession[] {
    // 严格只放行 assistantId === 'default': '' 是遗留成人时代会话, 不对儿童可见（spec §2）
    return this.sessions.filter((session: ChatSession): boolean =>
      session.assistantId === DEFAULT_ASSISTANT_ID)
  }

  private displayedKidsSessions(): ChatSession[] {
    return this.kidsSessions().slice(0, KIDS_SESSION_DISPLAY_LIMIT)
  }

  private starCountFor(sessionId: string): number {
    return this.starBySession.get(sessionId) ?? 0
  }

  private displayName(): string {
    return this.childName.length > 0 ? this.childName : '小朋友'
  }

  private avatarChar(): string {
    return this.childName.length > 0 ? this.childName.substring(0, 1) : '⭐'
  }

  private greetingText(): string {
    return `${getDayPartGreeting(new Date().getHours())}，${this.displayName()}`
  }

  private lastLessonLabel(): string {
    const kids: ChatSession[] = this.kidsSessions()
    if (kids.length > 0) {
      const title: string = kids[0].title.trim()
      return title.length > 0 ? `上次学到「${title}」` : '继续和小星老师的学习'
    }
    return '今天开启新的学习冒险'
  }

  private activityGridHeight(): number {
    const rows: number = Math.ceil(KIDS_ACTIVITIES.length / 4)
    return rows * ACTIVITY_TILE_HEIGHT + (rows - 1) * 10
  }

  private sessionsGridHeight(): number {
    const rows: number = Math.ceil(this.displayedKidsSessions().length / 2)
    return rows * SESSION_CARD_HEIGHT + Math.max(0, rows - 1) * 12
  }

  build() {
    Column() {
      // ── 问候行: 昵称头像 + 时段问候 + 星星药丸 ──
      Row({ space: 12 }) {
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

        Column({ space: 2 }) {
          Text(this.greetingText())
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('今天想和小星老师玩点什么？')
            .fontSize(12.5)
            .fontColor(KIDS_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 6 }) {
          Text('⭐')
            .fontSize(14)
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
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: this.topInsetVp + 12,
        bottom: 8
      })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          // ── 小星老师主卡 ──
          Stack({ alignContent: Alignment.TopEnd }) {
            // 右上玻璃圆装饰
            Column()
              .width(130)
              .height(130)
              .borderRadius(65)
              .backgroundColor(KIDS_GLASS)
              .margin({ top: -34, right: -34 })

            Column({ space: 16 }) {
              Row({ space: 14 }) {
                // 吉祥物: 白底圆角容器 + ⭐, 上下浮动
                Column() {
                  Text('⭐')
                    .fontSize(42)
                }
                .width(76)
                .height(76)
                .borderRadius(24)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#EBFFFDF8')
                .shadow({ radius: 14, color: '#333A2506', offsetY: 6 })
                .translate({ y: this.mascotFloatY })
                .onAppear((): void => {
                  this.getUIContext().animateTo({
                    duration: 2200,
                    curve: Curve.EaseInOut,
                    iterations: -1,
                    playMode: PlayMode.Alternate
                  }, (): void => {
                    this.mascotFloatY = -5
                  })
                })

                Column({ space: 3 }) {
                  Text('小星老师')
                    .fontSize(10.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(KIDS_ON_HERO_2)
                    .letterSpacing(1)
                  Text('找小星老师玩！')
                    .fontSize(23)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(KIDS_ON_HERO)
                  Text(this.lastLessonLabel())
                    .fontSize(12.5)
                    .fontColor(KIDS_ON_HERO_2)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .alignItems(VerticalAlign.Center)
              .width('100%')

              Row({ space: 10 }) {
                // 白色 CTA 胶囊（点击落在主卡 onClick 上, 无需独立手势）
                Row({ space: 8 }) {
                  Text(this.kidsSessions().length > 0 ? '继续学习' : '开始学习')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(KIDS_FG)
                  Text('→')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(KIDS_FG)
                }
                .padding({ left: 20, right: 20, top: 12, bottom: 12 })
                .borderRadius(999)
                .backgroundColor(KIDS_SURFACE)
                .shadow({ radius: 14, color: '#403A2506', offsetY: 6 })

                if (this.weekStars > 0) {
                  Row({ space: 5 }) {
                    Text('⭐')
                      .fontSize(11)
                    Text(`本周 +${this.weekStars}`)
                      .fontSize(12.5)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(KIDS_ON_HERO)
                  }
                  .padding({ left: 13, right: 13, top: 9, bottom: 9 })
                  .borderRadius(999)
                  .backgroundColor('#243A2506')
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .padding(20)
            .width('100%')
          }
          .width('100%')
          .borderRadius(24)
          .clip(true)
          .linearGradient({ angle: 135, colors: [[KIDS_ACCENT, 0], [KIDS_ACCENT_2, 1]] })
          .shadow({ radius: 28, color: '#66FF9F43', offsetY: 10 })
          .onClick((): void => {
            // 主卡/CTA 一律开启新的空会话（不复用最近会话）
            this.onNewChat('')
          })

          // ── 活动八宫格: 今天想玩什么 ──
          Column({ space: 12 }) {
            Row() {
              Text('今天想玩什么')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(KIDS_FG)
              Blank()
              Text('点一下，马上开始')
                .fontSize(11.5)
                .fontColor(KIDS_SUBTLE)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)

            Grid() {
              ForEach(KIDS_ACTIVITIES, (item: KidsActivityItem): void => {
                GridItem() {
                  Column({ space: 7 }) {
                    Text(item.emoji)
                      .fontSize(21)
                      .width(42)
                      .height(42)
                      .textAlign(TextAlign.Center)
                      .borderRadius(14)
                      .backgroundColor(withColorAlpha(item.color, '29'))
                    Text(item.label)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(KIDS_INK_SOFT)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .padding({ top: 12, bottom: 10, left: 4, right: 4 })
                  .borderRadius(18)
                  .backgroundColor(KIDS_SURFACE)
                  .border({ width: 1, color: KIDS_BORDER })
                  .accessibilityText(`打开${item.label}`)
                  .onClick((): void => {
                    this.onNewChat(item.startPrompt)
                  })
                }
              }, (item: KidsActivityItem): string => item.id)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
            .height(this.activityGridHeight())
            .scrollBar(BarState.Off)
          }
          .width('100%')

          // ── 我的学习乐园: 2 列会话网格 ──
          if (this.kidsSessions().length > 0) {
            Column({ space: 12 }) {
              Row() {
                Text('我的学习乐园')
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(KIDS_FG)
                Blank()
                Text(`共 ${this.displayedKidsSessions().length} 次学习`)
                  .fontSize(11.5)
                  .fontColor(KIDS_SUBTLE)
              }
              .width('100%')
              .alignItems(VerticalAlign.Bottom)

              Grid() {
                ForEach(this.displayedKidsSessions(), (session: ChatSession): void => {
                  GridItem() {
                    KidsSessionCard({
                      sessionTitle: session.title,
                      starCount: this.starCountFor(session.id),
                      timeLabel: formatRelativeTime(session.updatedAt),
                      themeColor: KIDS_ACCENT,
                      onTap: (): void => {
                        this.onOpenSession(session.id)
                      }
                    })
                  }
                }, (session: ChatSession): string => session.id)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(12)
              .rowsGap(12)
              .width('100%')
              .height(this.sessionsGridHeight())
              .scrollBar(BarState.Off)
            }
            .width('100%')
          }

          // ── 家长入口: 底部居中小灰字, 不吸引孩子 ──
          Row({ space: 6 }) {
            Text('🔒')
              .fontSize(11)
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
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
    .bindSheet($$this.showGateSheet, this.GateSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.showGateSheet = false
      }
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
}
