import { GiftItem, GIFT_CATEGORIES, getGiftCategoryMeta } from '../models/GiftModels'
import { getGiftShopService } from '../services/GiftShopService'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

let giftManagePagePathStack: NavPathStack | null = null

/**
 * 星星礼物管理（spec 2026-10-19 §6，成人壳设置入口）：内置礼物只读列表 + 自定义礼物 CRUD。
 * 内置礼物（is_builtin=1）无编辑/删除入口（服务层二次守卫）；
 * 兑换流水使用快照字段，删除自定义礼物不影响历史记录。
 */
@ComponentV2
struct GiftManagePage {
  @Local gifts: GiftItem[] = []
  /** 表单模式: 'hidden' | 'add' | 'edit' */
  @Local formMode: string = 'hidden'
  @Local editingId: string = ''
  @Local formName: string = ''
  @Local formCategory: string = GIFT_CATEGORIES[4]
  @Local formPrice: string = ''
  @Local formError: string = ''
  /** 删除二次确认目标 id（'' = 无） */
  @Local confirmDeleteId: string = ''

  private get topInsetVp(): number {
    return px2vp(getAppUiState().topAvoidHeight)
  }

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get textPrimary(): string {
    return getAppUiState().themeTextPrimary
  }

  private get textSecondary(): string {
    return getAppUiState().themeTextSecondary
  }

  aboutToAppear(): void {
    this.loadGifts()
  }

  private loadGifts(): void {
    getGiftShopService().getGiftsForManage().then((gifts: GiftItem[]): void => {
      this.gifts = gifts
    }).catch((): void => {
      this.gifts = []
    })
  }

  private builtinGifts(): GiftItem[] {
    return this.gifts.filter((gift: GiftItem): boolean => gift.isBuiltin)
  }

  private customGifts(): GiftItem[] {
    return this.gifts.filter((gift: GiftItem): boolean => !gift.isBuiltin)
  }

  private categoryOptions(): SelectOption[] {
    const options: SelectOption[] = []
    for (let i = 0; i < GIFT_CATEGORIES.length; i++) {
      const option: SelectOption = { value: getGiftCategoryMeta(GIFT_CATEGORIES[i]).label }
      options.push(option)
    }
    return options
  }

  private categoryIndex(category: string): number {
    for (let i = 0; i < GIFT_CATEGORIES.length; i++) {
      if (GIFT_CATEGORIES[i] === category) {
        return i
      }
    }
    return GIFT_CATEGORIES.length - 1
  }

  private openAddForm(): void {
    this.formMode = 'add'
    this.editingId = ''
    this.formName = ''
    this.formCategory = GIFT_CATEGORIES[4]
    this.formPrice = ''
    this.formError = ''
  }

  private openEditForm(gift: GiftItem): void {
    this.formMode = 'edit'
    this.editingId = gift.id
    this.formName = gift.name
    this.formCategory = gift.category
    this.formPrice = `${gift.priceStars}`
    this.formError = ''
  }

  private hideForm(): void {
    this.formMode = 'hidden'
  }

  private saveForm(): void {
    const name: string = this.formName.trim()
    const price: number = Math.floor(Number(this.formPrice))
    if (name.length === 0) {
      this.formError = '请填写礼物名称'
      return
    }
    if (!Number.isFinite(price) || price < 1) {
      this.formError = '星星价格至少为 1'
      return
    }
    if (this.formMode === 'add') {
      getGiftShopService().addCustomGift(name, this.formCategory, price).then((ok: boolean): void => {
        if (ok) {
          this.hideForm()
          this.loadGifts()
        } else {
          this.formError = '保存失败，稍后再试'
        }
      }).catch((): void => {
        this.formError = '保存失败，稍后再试'
      })
    } else {
      getGiftShopService().getGiftsForManage().then((all: GiftItem[]): void => {
        let target: GiftItem | null = null
        for (let i = 0; i < all.length; i++) {
          if (all[i].id === this.editingId) {
            target = all[i]
            break
          }
        }
        if (target === null) {
          this.formError = '礼物不存在'
          return
        }
        const updated: GiftItem = {
          id: target.id, name: name, category: this.formCategory, priceStars: price,
          isBuiltin: target.isBuiltin, enabled: target.enabled, sortOrder: target.sortOrder
        }
        getGiftShopService().updateCustomGift(updated).then((ok: boolean): void => {
          if (ok) {
            this.hideForm()
            this.loadGifts()
          } else {
            this.formError = '保存失败（内置礼物不可编辑）'
          }
        }).catch((): void => {
          this.formError = '保存失败，稍后再试'
        })
      }).catch((): void => {
        this.formError = '加载失败，稍后再试'
      })
    }
  }

  private deleteCustom(id: string): void {
    this.confirmDeleteId = ''
    getGiftShopService().deleteCustomGift(id).then((ok: boolean): void => {
      if (ok) {
        this.loadGifts()
      }
    }).catch((): void => {
      // 静默失败，列表保持原状
    })
  }

  @Builder
  TopBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(20)
        .fontColor([this.textPrimary])
        .onClick((): void => {
          if (giftManagePagePathStack !== null && giftManagePagePathStack.size() > 0) {
            giftManagePagePathStack.pop()
          }
        })
      Text($r('app.string.gift_manage_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInsetVp + 10, bottom: 10 })
  }

  @Builder
  GiftRow(gift: GiftItem, isCustom: boolean) {
    Row({ space: 12 }) {
      Column() {
        Image($rawfile(getGiftCategoryMeta(gift.category).iconPath)).width(22).height(22)
      }
      .width(40).height(40)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha(getGiftCategoryMeta(gift.category).tint, '1A'))

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(gift.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textPrimary)
          if (!isCustom) {
            Text('内置')
              .fontSize(9.5)
              .fontColor(this.textSecondary)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(withColorAlpha(this.themePrimary, '14'))
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(`${getGiftCategoryMeta(gift.category).label} · ${gift.priceStars} 颗`)
          .fontSize(11.5)
          .fontColor(this.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (isCustom) {
        Text('编辑')
          .fontSize(12.5)
          .fontColor(this.themePrimary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick((): void => {
            this.openEditForm(gift)
          })
        Text(this.confirmDeleteId === gift.id ? '确认删除？' : '删除')
          .fontSize(12.5)
          .fontColor(this.confirmDeleteId === gift.id ? '#EF4444' : this.textSecondary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick((): void => {
            if (this.confirmDeleteId === gift.id) {
              this.deleteCustom(gift.id)
            } else {
              this.confirmDeleteId = gift.id
            }
          })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(this.themeSurface)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  FormSection() {
    Column({ space: 10 }) {
      Row() {
        Text(this.formMode === 'add' ? '添加礼物' : '编辑礼物')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
          .layoutWeight(1)
        Text('取消')
          .fontSize(12.5)
          .fontColor(this.textSecondary)
          .onClick((): void => {
            this.hideForm()
          })
      }
      .width('100%')

      TextInput({ text: this.formName, placeholder: '礼物名称（如：冰淇淋一支）' })
        .fontSize(14)
        .height(44)
        .onChange((value: string): void => {
          this.formName = value
        })

      Select(this.categoryOptions())
        .selected(this.categoryIndex(this.formCategory))
        .value(getGiftCategoryMeta(this.formCategory).label)
        .fontColor(this.textPrimary)
        .font({ size: 14 })
        .width('100%')
        .onSelect((index: number): void => {
          this.formCategory = GIFT_CATEGORIES[index]
        })

      TextInput({ text: this.formPrice, placeholder: '星星价格（整数，如 50）' })
        .fontSize(14)
        .height(44)
        .type(InputType.NUMBER_DECIMAL)
        .onChange((value: string): void => {
          this.formPrice = value
        })

      if (this.formError.length > 0) {
        Text(this.formError)
          .fontSize(12)
          .fontColor('#EF4444')
      }

      Button('保存', { type: ButtonType.Capsule })
        .width('100%')
        .height(44)
        .fontSize(14.5)
        .backgroundColor(this.themePrimary)
        .onClick((): void => {
          this.saveForm()
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.themeSurface)
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column({ space: 12 }) {
          if (this.formMode !== 'hidden') {
            this.FormSection()
          } else {
            Button('＋ 添加自定义礼物', { type: ButtonType.Capsule })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor(this.themePrimary)
              .onClick((): void => {
                this.openAddForm()
              })
          }

          Text('内置礼物（只读）')
            .fontSize(12)
            .fontColor(this.textSecondary)
            .width('100%')
          ForEach(this.builtinGifts(), (gift: GiftItem): void => {
            this.GiftRow(gift, false)
          }, (gift: GiftItem): string => `builtin_${gift.id}`)

          Text('自定义礼物')
            .fontSize(12)
            .fontColor(this.textSecondary)
            .width('100%')
          if (this.customGifts().length === 0) {
            Text('还没有自定义礼物，点上方按钮添加')
              .fontSize(12)
              .fontColor(this.textSecondary)
              .width('100%')
              .padding(12)
          }
          ForEach(this.customGifts(), (gift: GiftItem): void => {
            this.GiftRow(gift, true)
          }, (gift: GiftItem): string => `custom_${gift.id}_${gift.name}_${gift.priceStars}`)

          Text('兑换记录使用礼物快照，编辑或删除不会影响已兑换的记录')
            .fontSize(11)
            .fontColor(this.textSecondary)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 24 })
        .constraintSize({ minWidth: 0 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
    .constraintSize({ minWidth: 0 })
  }
}

@Builder
export function GiftManagePageBuilder(_name: string, _param: Object) {
  NavDestination() {
    GiftManagePage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    giftManagePagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (giftManagePagePathStack !== null && giftManagePagePathStack.size() > 0) {
      giftManagePagePathStack.pop()
    }
    return true
  })
}
