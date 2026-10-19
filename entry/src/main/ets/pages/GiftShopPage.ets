import { GiftItem, GiftShopStats, GiftRedemptionRow, GiftRedeemResult,
  countAffordableGifts, filterGiftsByCategory, sortGiftsForShop,
  canAffordGift, shortfallFor,
  getGiftCategoryMeta, GIFT_CATEGORIES, GIFT_CATEGORY_ALL } from '../models/GiftModels'
import { getGiftShopService } from '../services/GiftShopService'
import {
  KIDS_BG, KIDS_SURFACE, KIDS_FG, KIDS_MUTED, KIDS_SUBTLE, KIDS_BORDER,
  KIDS_ACCENT, KIDS_ACCENT_2, KIDS_ON_HERO, KIDS_ON_HERO_2, KIDS_STAR, KIDS_ON_GOLD,
  KIDS_DANGER
} from '../components/kids/KidsBrandTokens'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

/**
 * 星星商城（spec 2026-10-19 §5.2）：余额 hero + 统计条 + 分类 chips + 礼物网格。
 * 恒定 Kids 暖色绘本皮肤；入口 = 儿童主屏星星药丸（KidsHomeView onOpenGiftShop）。
 * 兑换确认/成功 sheet 见 Task 8。
 */

let giftShopPagePathStack: NavPathStack | null = null

@ComponentV2
struct GiftShopPage {
  @Local balance: number = 0
  @Local stats: GiftShopStats = { earnedTotal: 0, redeemedTotal: 0, redeemCount: 0 } as GiftShopStats
  @Local gifts: GiftItem[] = []
  @Local selectedCategory: string = GIFT_CATEGORY_ALL
  @Local pendingCount: number = 0
  @Local showConfirmSheet: boolean = false
  @Local confirmGift: GiftItem | null = null
  /** 'confirm' | 'success' | 'error' */
  @Local redeemState: string = 'confirm'
  @Local lastRedemption: GiftRedemptionRow | null = null
  @Local redeemError: string = ''
  /** 兑换请求在途（防双击双扣：redeem() 异步窗口内禁用确认按钮） */
  @Local redeemInFlight: boolean = false

  private get topInsetVp(): number {
    return px2vp(getAppUiState().topAvoidHeight)
  }

  aboutToAppear(): void {
    this.loadAll()
  }

  private loadAll(): void {
    getGiftShopService().getStarBalance().then((balance: number): void => {
      this.balance = balance
    }).catch((): void => {
      this.balance = 0
    })
    getGiftShopService().getShopStats().then((stats: GiftShopStats): void => {
      this.stats = stats
    }).catch((): void => {
      this.stats = { earnedTotal: 0, redeemedTotal: 0, redeemCount: 0 } as GiftShopStats
    })
    getGiftShopService().getGiftsForShop().then((gifts: GiftItem[]): void => {
      this.gifts = sortGiftsForShop(gifts)
    }).catch((): void => {
      this.gifts = []
    })
    getGiftShopService().getPendingRedemptionCount().then((count: number): void => {
      this.pendingCount = count
    }).catch((): void => {
      this.pendingCount = 0
    })
  }

  /** ForEach 回调体内不能声明对象（10905209）——抽方法 */
  private chipKeys(): string[] {
    const keys: string[] = [GIFT_CATEGORY_ALL]
    for (let i = 0; i < GIFT_CATEGORIES.length; i++) {
      keys.push(GIFT_CATEGORIES[i])
    }
    return keys
  }

  private visibleGifts(): GiftItem[] {
    return filterGiftsByCategory(this.gifts, this.selectedCategory)
  }

  private affordableCount(): number {
    return countAffordableGifts(this.gifts, this.balance)
  }

  private chipLabel(key: string): string {
    if (key === GIFT_CATEGORY_ALL) {
      return '全部'
    }
    return getGiftCategoryMeta(key).label
  }

  private goBack(): void {
    if (giftShopPagePathStack !== null && giftShopPagePathStack.size() > 0) {
      giftShopPagePathStack.pop()
    }
  }

  private goRecords(): void {
    if (giftShopPagePathStack !== null) {
      giftShopPagePathStack.pushPath({ name: 'GiftRecordsPage' })
    }
  }

  private openConfirmSheet(gift: GiftItem): void {
    this.confirmGift = gift
    this.redeemState = 'confirm'
    this.redeemError = ''
    this.lastRedemption = null
    this.redeemInFlight = false
    this.showConfirmSheet = true
  }

  private confirmRedeem(): void {
    if (this.confirmGift === null || this.redeemInFlight) {
      return
    }
    this.redeemInFlight = true
    const giftId: string = this.confirmGift.id
    getGiftShopService().redeem(giftId).then((result: GiftRedeemResult): void => {
      this.redeemInFlight = false
      if (result.success && result.redemption !== null) {
        this.lastRedemption = result.redemption
        this.redeemState = 'success'
        this.loadAll()
      } else if (result.reason === 'insufficient') {
        this.redeemState = 'error'
        this.redeemError = `星星还差 ${result.shortfall} 颗，再攒一攒吧`
      } else {
        this.redeemState = 'error'
        this.redeemError = '兑换没有成功，稍后再试试'
      }
    }).catch((): void => {
      this.redeemInFlight = false
      this.redeemState = 'error'
      this.redeemError = '兑换没有成功，稍后再试试'
    })
  }

  private goRecordsFromSheet(): void {
    this.showConfirmSheet = false
    this.goRecords()
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
      Text('星星商城')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .layoutWeight(1)
      Row({ space: 4 }) {
        Text('我的兑换')
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(KIDS_FG)
        if (this.pendingCount > 0) {
          Text(`${this.pendingCount}`)
            .fontSize(10.5)
            .fontColor(KIDS_ON_GOLD)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(999)
            .backgroundColor(withColorAlpha(KIDS_STAR, '45'))
        }
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(999)
      .backgroundColor(KIDS_SURFACE)
      .border({ width: 1, color: KIDS_BORDER })
      .onClick((): void => {
        this.goRecords()
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInsetVp + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BalanceHero() {
    Column({ space: 6 }) {
      Text('我的星星')
        .fontSize(11.5)
        .fontColor(KIDS_ON_HERO_2)
      Row({ space: 6 }) {
        Image($rawfile('kids/star.svg')).width(30).height(30)
        Text(`${this.balance}`)
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_ON_HERO)
        Text('颗')
          .fontSize(14)
          .fontColor(KIDS_ON_HERO_2)
      }
      .alignItems(VerticalAlign.Center)
      Text(this.affordableCount() > 0 ? `可换 ${this.affordableCount()} 件礼物` : '再攒一攒，很快能换啦')
        .fontSize(12.5)
        .fontColor(KIDS_ON_HERO)
    }
    .width('100%')
    .padding(20)
    .borderRadius(24)
    .linearGradient({ angle: 135, colors: [[KIDS_ACCENT, 0], [KIDS_ACCENT_2, 1]] })
    .shadow({ radius: 28, color: '#66FF9F43', offsetY: 10 })
  }

  @Builder
  StatsStrip() {
    Row({ space: 12 }) {
      this.StatCell('累计获得', 0)
      this.StatCell('累计兑换', 1)
      this.StatCell('兑换件数', 2)
    }
    .width('100%')
  }

  /** 数字在 builder 体内直读 this.stats（@Trace getter 依赖）——传字符串快照会断响应式（CLAUDE.md 已知坑） */
  @Builder
  StatCell(caption: string, kind: number) {
    Column({ space: 2 }) {
      if (kind === 0) {
        Text(`${this.stats.earnedTotal}`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
      } else if (kind === 1) {
        Text(`${this.stats.redeemedTotal}`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
      } else {
        Text(`${this.stats.redeemCount}`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
      }
      Text(caption)
        .fontSize(10.5)
        .fontColor(KIDS_SUBTLE)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  CategoryChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.chipKeys(), (key: string): void => {
          Text(this.chipLabel(key))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedCategory === key ? '#FFFFFF' : KIDS_FG)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(999)
            .backgroundColor(this.selectedCategory === key ? KIDS_ACCENT : KIDS_SURFACE)
            .border({ width: 1, color: this.selectedCategory === key ? KIDS_ACCENT : KIDS_BORDER })
            .onClick((): void => {
              this.selectedCategory = key
            })
        }, (key: string): string => key)
      }
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  GiftGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.visibleGifts(), (gift: GiftItem): void => {
        this.GiftCard(gift)
      }, (gift: GiftItem): string => `${gift.id}_${gift.priceStars}_${this.balance}`)
    }
    .width('100%')
  }

  @Builder
  GiftCard(gift: GiftItem) {
    Column({ space: 8 }) {
      Column() {
        Image($rawfile(getGiftCategoryMeta(gift.category).iconPath)).width(34).height(34)
      }
      .width(64)
      .height(64)
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha(getGiftCategoryMeta(gift.category).tint, '26'))

      Text(gift.name)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 4 }) {
        Image($rawfile('kids/star.svg')).width(13).height(13)
        Text(`${gift.priceStars}`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
      }

      Text(gift.priceStars <= this.balance ? '点击兑换' : `还差 ${shortfallFor(this.balance, gift.priceStars)} 颗`)
        .fontSize(10.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(gift.priceStars <= this.balance ? getGiftCategoryMeta(gift.category).tint : KIDS_SUBTLE)
    }
    .layoutWeight(1)
    .padding(14)
    .margin({ bottom: 12 })
    .borderRadius(19)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .shadow({ radius: 8, color: '#1424211C', offsetY: 3 })
    .opacity(gift.priceStars <= this.balance ? 1 : 0.55)
    .accessibilityText(gift.priceStars <= this.balance ?
      `兑换${gift.name}，需要 ${gift.priceStars} 颗星` :
      `${gift.name}需要 ${gift.priceStars} 颗星，还差 ${shortfallFor(this.balance, gift.priceStars)} 颗`)
    .onClick((): void => {
      this.openConfirmSheet(gift)
    })
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column({ space: 16 }) {
          this.BalanceHero()
          this.StatsStrip()
          this.CategoryChips()
          this.GiftGrid()
          Text('和爸爸妈妈商量好，兑换后把领取码给他们看')
            .fontSize(11)
            .fontColor(KIDS_SUBTLE)
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
        .bindSheet($$this.showConfirmSheet, this.ConfirmSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          preferType: SheetType.BOTTOM,
          onDisappear: (): void => {
            this.showConfirmSheet = false
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
  }

  @Builder
  ConfirmSheetBuilder() {
    Column({ space: 14 }) {
      Row() {
        Text(this.redeemState === 'success' ? '兑换成功' : (this.redeemState === 'error' ? '换个目标吧' : '确认兑换'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Blank()
        Text('✕')
          .fontSize(15)
          .fontColor(KIDS_SUBTLE)
          .width(36).height(36)
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            this.showConfirmSheet = false
          })
      }
      .width('100%')

      if (this.redeemState === 'confirm' && this.confirmGift !== null) {
        Row({ space: 12 }) {
          Column() {
            Image($rawfile(getGiftCategoryMeta(this.confirmGift.category).iconPath)).width(28).height(28)
          }
          .width(52).height(52)
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(withColorAlpha(getGiftCategoryMeta(this.confirmGift.category).tint, '26'))
          Column({ space: 2 }) {
            Text(this.confirmGift.name)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_FG)
            Text(`现有 ${this.balance} 颗 · 需要 ${this.confirmGift.priceStars} 颗`)
              .fontSize(12)
              .fontColor(KIDS_MUTED)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`兑换后可用余额变为 ${this.balance - this.confirmGift.priceStars} 颗`)
          .fontSize(12)
          .fontColor(KIDS_SUBTLE)

        Row({ space: 8 }) {
          Text('再想想')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_FG)
            .layoutWeight(1)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .border({ width: 1.5, color: KIDS_BORDER })
            .onClick((): void => {
              this.showConfirmSheet = false
            })
          Text(`用 ${this.confirmGift.priceStars} 颗星星兑换`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(2)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .backgroundColor(KIDS_ACCENT)
            .opacity(canAffordGift(this.balance, this.confirmGift.priceStars) && !this.redeemInFlight ? 1 : 0.5)
            .onClick((): void => {
              if (this.confirmGift !== null && !this.redeemInFlight &&
                canAffordGift(this.balance, this.confirmGift.priceStars)) {
                this.confirmRedeem()
              }
            })
        }
        .width('100%')
      }

      if (this.redeemState === 'success' && this.lastRedemption !== null) {
        Text('把领取码给爸爸妈妈看吧')
          .fontSize(12.5)
          .fontColor(KIDS_MUTED)
        Text(this.lastRedemption.redeemCode)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .letterSpacing(6)
          .padding(14)
          .width('100%')
          .textAlign(TextAlign.Center)
          .borderRadius(16)
          .backgroundColor(withColorAlpha(KIDS_ACCENT, '14'))
        Row({ space: 8 }) {
          Text('好的')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_FG)
            .layoutWeight(1)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .border({ width: 1.5, color: KIDS_BORDER })
            .onClick((): void => {
              this.showConfirmSheet = false
            })
          Text('去查看我的兑换')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(2)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .backgroundColor(KIDS_ACCENT)
            .onClick((): void => {
              this.goRecordsFromSheet()
            })
        }
        .width('100%')
      }

      if (this.redeemState === 'error') {
        Text(this.redeemError)
          .fontSize(13)
          .fontColor(KIDS_DANGER)
        Text('知道了')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width('100%')
          .height(46)
          .textAlign(TextAlign.Center)
          .borderRadius(999)
          .backgroundColor(KIDS_ACCENT)
          .onClick((): void => {
            this.showConfirmSheet = false
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 28 })
  }
}

@Builder
export function GiftShopPageBuilder(_name: string, _param: Object) {
  NavDestination() {
    GiftShopPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    giftShopPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (giftShopPagePathStack !== null && giftShopPagePathStack.size() > 0) {
      giftShopPagePathStack.pop()
    }
    return true
  })
}
