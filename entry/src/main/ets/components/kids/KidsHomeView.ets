import { ChatSession } from '../../models/ChatModels'
import { DEFAULT_ASSISTANT_ID } from '../../models/AssistantModels'
import { getStarRewardService } from '../../services/StarRewardService'
import { getDatabaseService } from '../../services/DatabaseService'
import { formatRelativeTime } from '../../utils/TimeFormatUtils'
import { ParentalGateSheet } from './ParentalGateSheet'
import { KidsSessionCard } from './KidsSessionCard'

const KIDS_THEME_COLOR: string = '#FF9F43'

/**
 * 儿童主屏: 顶部累计星星 + 大卡片（最近小星老师会话/新建）+ 图形化会话列表 + 家长入口。
 * 列表只读（无长按/删除/多选）; 只显示 assistantId === 'default' 的会话。
 * 星星数据自加载, starRefreshTick 由宿主在导航栈 didShow(navBar) 时递增触发刷新。
 */
@ComponentV2
export struct KidsHomeView {
  @Param sessions: ChatSession[] = []
  @Param starRefreshTick: number = 0
  @Param topInsetVp: number = 0
  @Param themeBackground: string = '#FAF8F3'
  @Event onOpenSession: (sessionId: string) => void = () => {}
  @Event onNewChat: () => void = () => {}
  @Event onGatePassed: () => void = () => {}
  @Local totalStars: number = 0
  @Local starBySession: Map<string, number> = new Map()
  @Local showGateSheet: boolean = false

  @Monitor('starRefreshTick')
  onStarRefreshTickChanged(): void {
    this.loadStars()
  }

  aboutToAppear(): void {
    this.loadStars()
  }

  private loadStars(): void {
    getStarRewardService().getAllTimeStarTotal().then((total: number): void => {
      this.totalStars = total
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load total stars: ${JSON.stringify(error)}`)
    })
    getDatabaseService().getStarTotalsBySession().then((totals: Map<string, number>): void => {
      this.starBySession = totals
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load session star totals: ${JSON.stringify(error)}`)
      this.starBySession = new Map()
    })
  }

  private kidsSessions(): ChatSession[] {
    return this.sessions.filter((session: ChatSession): boolean =>
      session.assistantId === DEFAULT_ASSISTANT_ID || session.assistantId === '')
  }

  private starCountFor(sessionId: string): number {
    return this.starBySession.get(sessionId) ?? 0
  }

  private handleBigCardTap(): void {
    const kids: ChatSession[] = this.kidsSessions()
    if (kids.length > 0) {
      this.onOpenSession(kids[0].id)
      return
    }
    this.onNewChat()
  }

  build() {
    Column() {
      // 顶部星星栏
      Row() {
        Text(`⭐ ${this.totalStars}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: this.topInsetVp + 12,
        bottom: 8
      })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          // 大卡片
          Column({ space: 8 }) {
            Text('⭐')
              .fontSize(52)
            Text('找小星老师玩！')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text(this.kidsSessions().length > 0 ? '继续上次的学习' : '开始新的学习')
              .fontSize(14)
              .fontColor('#E6FFFFFF')
          }
          .width('100%')
          .height(170)
          .justifyContent(FlexAlign.Center)
          .borderRadius(24)
          .linearGradient({ angle: 135, colors: [[KIDS_THEME_COLOR, 0], ['#F7B955', 1]] })
          .shadow({ radius: 12, color: '#33FF9F43', offsetY: 4 })
          .onClick((): void => {
            this.handleBigCardTap()
          })

          if (this.kidsSessions().length > 0) {
            Text('我的学习乐园')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            ForEach(this.kidsSessions(), (session: ChatSession): void => {
              KidsSessionCard({
                sessionTitle: session.title,
                starCount: this.starCountFor(session.id),
                timeLabel: formatRelativeTime(session.updatedAt),
                themeColor: KIDS_THEME_COLOR,
                onTap: (): void => {
                  this.onOpenSession(session.id)
                }
              })
            }, (session: ChatSession): string => session.id)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // 家长入口: 右下角小灰字, 不吸引孩子
      Row() {
        Blank()
        Text('家长入口')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(8)
          .onClick((): void => {
            this.showGateSheet = true
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 16 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
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
