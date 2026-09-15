import { ChatSession } from '../../models/ChatModels'
import { KidsDayGroup, formatHourMinute } from '../../utils/KidsSubjectUtils'
import { subjectForAssistantId, KidsSubjectItem } from './KidsSubjectCatalog'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_MUTED,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_ACCENT,
  KIDS_ON_GOLD
} from './KidsBrandTokens'

/** 同日记录超过 N 条时折叠 */
const DAY_COLLAPSE_LIMIT: number = 3

/**
 * 学习乐园按天分组卡（spec 2026-09-15 §4.5）:
 * 天头（今天/昨天/日期 + 当日星星汇总药丸）+ 记录行列表（学科图标 +
 * 标题 + 老师名·时间 + 单会话星星）+ 同日 >3 条折叠/展开。
 * 展开态是内部 @Local，不持久化。
 */
@ComponentV2
export struct KidsDayGroupCard {
  @Param group: KidsDayGroup = new KidsDayGroup()
  @Param dayStars: number = 0
  @Param starBySession: Map<string, number> = new Map()
  @Event onOpenSession: (sessionId: string) => void = () => {}
  @Local expanded: boolean = false
  /** 按压反馈（spec §7: 记录行 scale 0.98 + 60-80ms）: 当前按下的会话 id（'' = 无） */
  @Local pressedSessionId: string = ''

  private visibleSessions(): ChatSession[] {
    if (this.expanded || this.group.sessions.length <= DAY_COLLAPSE_LIMIT) {
      return this.group.sessions
    }
    return this.group.sessions.slice(0, DAY_COLLAPSE_LIMIT)
  }

  private hiddenCount(): number {
    return Math.max(0, this.group.sessions.length - DAY_COLLAPSE_LIMIT)
  }

  private teacherName(session: ChatSession): string {
    const subject: KidsSubjectItem | null = subjectForAssistantId(session.assistantId)
    return subject !== null ? subject.teacher : '小星老师'
  }

  private sessionTitle(session: ChatSession): string {
    const title: string = session.title.trim()
    return title.length > 0 ? title : '和小星老师的学习'
  }

  build() {
    Column() {
      // ── 天头 ──
      Row({ space: 8 }) {
        Text(this.group.label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Text(this.group.subLabel)
          .fontSize(11.5)
          .fontColor(KIDS_MUTED)
        Blank()
        // 当日星星汇总药丸（金 24% 淡底）
        Row({ space: 4 }) {
          Image($rawfile('kids/star.svg')).width(12).height(12)
          Text(`+${this.dayStars}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_ON_GOLD)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(999)
        .backgroundColor('#3DF5B301')
        .accessibilityText(`当日获得 ${this.dayStars} 颗星`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      // ── 记录行 ──
      ForEach(this.visibleSessions(), (session: ChatSession, index: number): void => {
        this.RecordRow(session, index > 0)
      }, (session: ChatSession): string => session.id)

      // ── 折叠/展开 ──
      if (this.hiddenCount() > 0) {
        Row() {
          Text(this.expanded ? '收起' : `展开其余 ${this.hiddenCount()} 条`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_MUTED)
        }
        .width('100%')
        .height(44)
        .justifyContent(FlexAlign.Center)
        .border({ width: { top: 1 }, color: KIDS_BORDER, style: { top: BorderStyle.Dashed } })
        .onClick((): void => {
          this.expanded = !this.expanded
        })
      }
    }
    .width('100%')
    .borderRadius(20)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .clip(true)
  }

  @Builder
  RecordRow(session: ChatSession, showTopBorder: boolean) {
    Row({ space: 10 }) {
      this.RecordIcon(session)

      Column({ space: 2 }) {
        Text(this.sessionTitle(session))
          .fontSize(13.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(KIDS_FG)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.teacherName(session)} · ${formatHourMinute(session.updatedAt)}`)
          .fontSize(11)
          .fontColor(KIDS_SUBTLE)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 单会话星星（0 -> 灰色 0）
      if ((this.starBySession.get(session.id) ?? 0) > 0) {
        Row({ space: 3 }) {
          Text(`+${this.starBySession.get(session.id) ?? 0}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_ON_GOLD)
          Image($rawfile('kids/star.svg')).width(13).height(13)
        }
      } else {
        Text('0')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_SUBTLE)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .border(showTopBorder ?
      { width: { top: 1 }, color: KIDS_BORDER } :
      { width: { top: 0 }, color: Color.Transparent })
    .scale(this.pressedSessionId === session.id ? { x: 0.98, y: 0.98 } : { x: 1, y: 1 })
    .animation({ duration: 70, curve: Curve.EaseOut })
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down) {
        this.pressedSessionId = session.id
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedSessionId = ''
      }
    })
    .onClick((): void => {
      this.onOpenSession(session.id)
    })
  }

  @Builder
  RecordIcon(session: ChatSession) {
    // 学科会话: 学科图标 + 学科色 15% 淡底；小星老师: star.svg + 暖橙淡底
    if (subjectForAssistantId(session.assistantId) !== null) {
      Column() {
        Image($rawfile((subjectForAssistantId(session.assistantId) as KidsSubjectItem).iconPath))
          .width(20)
          .height(20)
      }
      .width(36)
      .height(36)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha((subjectForAssistantId(session.assistantId) as KidsSubjectItem).color, '26'))
    } else {
      Column() {
        Image($rawfile('kids/star.svg')).width(20).height(20)
      }
      .width(36)
      .height(36)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha(KIDS_ACCENT, '26'))
    }
  }
}
