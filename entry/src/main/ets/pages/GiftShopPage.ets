import { GiftItem, GiftShopStats, GiftRedemptionRow,
  countAffordableGifts, filterGiftsByCategory, sortGiftsForShop,
  getGiftCategoryMeta, GIFT_CATEGORIES, GIFT_CATEGORY_ALL } from '../models/GiftModels'
import { getGiftShopService } from '../services/GiftShopService'
import {
  KIDS_BG, KIDS_SURFACE, KIDS_FG, KIDS_MUTED, KIDS_SUBTLE, KIDS_BORDER,
  KIDS_ACCENT, KIDS_ACCENT_2, KIDS_ON_HERO, KIDS_ON_HERO_2, KIDS_STAR, KIDS_ON_GOLD
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
  // Task 8: 兑换 sheet 状态（showConfirmSheet / confirmGift / redeemState / lastRedemption / redeemError）

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
      this.StatCell(`${this.stats.earnedTotal}`, '累计获得')
      this.StatCell(`${this.stats.redeemedTotal}`, '累计兑换')
      this.StatCell(`${this.stats.redeemCount}`, '兑换件数')
    }
    .width('100%')
  }

  @Builder
  StatCell(numText: string, caption: string) {
    Column({ space: 2 }) {
      Text(numText)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
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

      // Task 8: 点击卡片 → 打开兑换确认 sheet（余额不足置灰 + 「还差 N 颗」）
    }
    .layoutWeight(1)
    .padding(14)
    .margin({ bottom: 12 })
    .borderRadius(19)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .shadow({ radius: 8, color: '#1424211C', offsetY: 3 })
    .opacity(gift.priceStars <= this.balance ? 1 : 0.55)
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
      // Task 8: bindSheet 宿主（独立零尺寸 Column）
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
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
