import { GiftRedemptionRow, GIFT_STATUS_PENDING, GIFT_STATUS_PICKED, getGiftCategoryMeta } from '../models/GiftModels'
import { getGiftShopService } from '../services/GiftShopService'
import { ParentalGateSheet } from '../components/kids/ParentalGateSheet'
import {
  KIDS_BG, KIDS_SURFACE, KIDS_FG, KIDS_MUTED, KIDS_SUBTLE, KIDS_BORDER,
  KIDS_ACCENT, KIDS_STAR, KIDS_DANGER, KIDS_ON_GOLD
} from '../components/kids/KidsBrandTokens'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { formatDateLabel, formatHourMinute } from '../utils/KidsSubjectUtils'

let giftRecordsPagePathStack: NavPathStack | null = null

/**
 * 我的兑换（spec 2026-10-19 §5.3）：兑换记录列表（快照 + 领取码 + 状态）。
 * 「家长核销」走 ParentalGateSheet(gateOnly)——通过后 markRedemptionPicked；
 * 孩子答错只换题，无核销副作用。空态 CTA 去商城。
 */
@ComponentV2
struct GiftRecordsPage {
  @Local records: GiftRedemptionRow[] = []
  @Local loaded: boolean = false
  @Local showGateSheet: boolean = false
  /** 待核销的记录 id（gate 通过后使用；'' = 无） */
  @Local pendingPickId: string = ''

  private get topInsetVp(): number {
    return px2vp(getAppUiState().topAvoidHeight)
  }

  aboutToAppear(): void {
    this.loadRecords()
  }

  private loadRecords(): void {
    getGiftShopService().getRedemptions().then((rows: GiftRedemptionRow[]): void => {
      this.records = rows
      this.loaded = true
    }).catch((): void => {
      this.records = []
      this.loaded = true
    })
  }

  private goBack(): void {
    if (giftRecordsPagePathStack !== null && giftRecordsPagePathStack.size() > 0) {
      giftRecordsPagePathStack.pop()
    }
  }

  private goShop(): void {
    if (giftRecordsPagePathStack !== null) {
      giftRecordsPagePathStack.pushPath({ name: 'GiftShopPage' })
    }
  }

  private statusLabel(row: GiftRedemptionRow): string {
    return row.status === GIFT_STATUS_PICKED ? '已领取' : '待领取'
  }

  private timeLabel(row: GiftRedemptionRow): string {
    return `${formatDateLabel(row.createdAt)} ${formatHourMinute(row.createdAt)}`
  }

  private openGate(row: GiftRedemptionRow): void {
    this.pendingPickId = row.id
    this.showGateSheet = true
  }

  private handleGatePassed(): void {
    this.showGateSheet = false
    if (this.pendingPickId === '') {
      return
    }
    const pickId: string = this.pendingPickId
    this.pendingPickId = ''
    getGiftShopService().markRedemptionPicked(pickId).then((): void => {
      this.loadRecords()
    }).catch((): void => {
      this.loadRecords()
    })
  }

  @Builder
  TopBar() {
    Row({ space: 8 }) {
      Image($rawfile('kids/chevron.svg'))
        .width(20).height(20)
        .rotate({ angle: 180 })
        .onClick((): void => {
          this.goBack()
        })
      Text('我的兑换')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInsetVp + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  EmptyState() {
    Column({ space: 10 }) {
      Image($rawfile('kids/gift_other.svg')).width(56).height(56).opacity(0.6)
      Text('还没有兑换过礼物')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
      Text('攒够星星后，去商城挑一件喜欢的吧')
        .fontSize(12)
        .fontColor(KIDS_MUTED)
      Text('去逛星星商城')
        .fontSize(13.5)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .padding({ left: 22, right: 22, top: 12, bottom: 12 })
        .borderRadius(999)
        .backgroundColor(KIDS_ACCENT)
        .onClick((): void => {
          this.goShop()
        })
    }
    .width('100%')
    .padding({ top: 80 })
  }

  @Builder
  RecordCard(row: GiftRedemptionRow) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column() {
          Image($rawfile(getGiftCategoryMeta(row.category).iconPath)).width(24).height(24)
        }
        .width(44).height(44)
        .borderRadius(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(withColorAlpha(getGiftCategoryMeta(row.category).tint, '26'))

        Column({ space: 2 }) {
          Text(row.giftName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
          Text(`${this.timeLabel(row)} · ${row.priceStars} 颗`)
            .fontSize(11)
            .fontColor(KIDS_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.statusLabel(row))
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(row.status === GIFT_STATUS_PICKED ? '#FFFFFF' : KIDS_ON_GOLD)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(999)
          .backgroundColor(row.status === GIFT_STATUS_PICKED ? '#22C55E' : KIDS_STAR)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Column({ space: 3 }) {
          Text('领取码')
            .fontSize(10)
            .fontColor(KIDS_SUBTLE)
          Text(row.redeemCode)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
            .letterSpacing(5)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (row.status === GIFT_STATUS_PENDING) {
          Text('家长核销')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_DANGER)
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .borderRadius(999)
            .border({ width: 1.5, color: withColorAlpha(KIDS_DANGER, '55') })
            .accessibilityText(`家长验证后，把${row.giftName}标记为已领取`)
            .onClick((): void => {
              this.openGate(row)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 12 })
    .borderRadius(19)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .shadow({ radius: 8, color: '#1424211C', offsetY: 3 })
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column({ space: 12 }) {
          if (this.loaded && this.records.length === 0) {
            this.EmptyState()
          }
          ForEach(this.records, (row: GiftRedemptionRow): void => {
            this.RecordCard(row)
          }, (row: GiftRedemptionRow): string => `${row.id}_${row.status}`)
          if (this.records.length > 0) {
            Text('到爸爸妈妈这里出示领取码，兑现后由家长标记「已领取」')
              .fontSize(11)
              .fontColor(KIDS_SUBTLE)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
  }

  @Builder
  GateSheetBuilder() {
    ParentalGateSheet({
      gateOnly: true,
      onPassed: (): void => {
        this.handleGatePassed()
      },
      onCancelled: (): void => {
        this.showGateSheet = false
      }
    })
  }
}

@Builder
export function GiftRecordsPageBuilder(_name: string, _param: Object) {
  NavDestination() {
    GiftRecordsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    giftRecordsPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (giftRecordsPagePathStack !== null && giftRecordsPagePathStack.size() > 0) {
      giftRecordsPagePathStack.pop()
    }
    return true
  })
}
