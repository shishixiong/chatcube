/**
 * 星星礼物商城数据模型（spec docs/superpowers/specs/2026-10-19-star-gift-shop-design.md §4.5）
 *
 * gifts 表 / gift_redemptions 表的内存模型、内置目录与纯函数。
 * 刻意不触碰 models/StarEventModels——兑换是独立流水，不进星星事件 10 处漂移点。
 * 分类色 tint 是 brand 暖色绘本调色板的扩展（spec §5），与 KidsBrandTokens 平级；
 * 放在本文件因为它是分类数据的一部分，models 层不 import components 层。
 */

export type GiftCategory = 'building' | 'plush' | 'vehicle' | 'stationery' | 'other'

export const GIFT_CATEGORIES: GiftCategory[] = ['building', 'plush', 'vehicle', 'stationery', 'other']
export const GIFT_CATEGORY_ALL: string = 'all'

export interface GiftCategoryMeta {
  label: string
  iconPath: string
  tint: string
}

const GIFT_CATEGORY_META_MAP: Record<string, GiftCategoryMeta> = {
  'building': { label: '拼搭', iconPath: 'kids/gift_blocks.svg', tint: '#4E8FE0' } as GiftCategoryMeta,
  'plush': { label: '玩偶', iconPath: 'kids/gift_plush.svg', tint: '#E0567C' } as GiftCategoryMeta,
  'vehicle': { label: '玩具车', iconPath: 'kids/gift_vehicle.svg', tint: '#35A98A' } as GiftCategoryMeta,
  'stationery': { label: '文具', iconPath: 'kids/gift_stationery.svg', tint: '#8B72E0' } as GiftCategoryMeta,
  'other': { label: '其他', iconPath: 'kids/gift_other.svg', tint: '#FF9F43' } as GiftCategoryMeta
}

export function getGiftCategoryMeta(category: string): GiftCategoryMeta {
  const meta: GiftCategoryMeta | undefined = GIFT_CATEGORY_META_MAP[category]
  if (meta !== undefined) {
    return meta
  }
  return GIFT_CATEGORY_META_MAP['other']
}

export interface GiftItem {
  id: string
  name: string
  category: string
  priceStars: number
  isBuiltin: boolean
  enabled: boolean
  sortOrder: number
}

export const GIFT_STATUS_PENDING: string = 'pending'
export const GIFT_STATUS_PICKED: string = 'picked'

export interface GiftRedemptionRow {
  id: string
  giftId: string
  giftName: string
  category: string
  priceStars: number
  redeemCode: string
  status: string
  createdAt: number
  pickedAt: number
}

export interface GiftShopStats {
  earnedTotal: number
  redeemedTotal: number
  redeemCount: number
}

export interface GiftRedeemResult {
  success: boolean
  /** '' | 'gift_unavailable' | 'insufficient' | 'db_error' */
  reason: string
  /** reason === 'insufficient' 时为还差颗数，其余为 0 */
  shortfall: number
  redemption: GiftRedemptionRow | null
}

export interface BuiltinGiftSpec {
  name: string
  category: GiftCategory
  priceStars: number
}

/** 内置目录 12 件（spec §4.1 表格）；sortOrder = 数组下标 + 1 */
export const BUILTIN_GIFTS: BuiltinGiftSpec[] = [
  { name: '迷你积木车', category: 'building', priceStars: 60 } as BuiltinGiftSpec,
  { name: '小颗粒积木盒', category: 'building', priceStars: 150 } as BuiltinGiftSpec,
  { name: '卡通钥匙扣', category: 'plush', priceStars: 40 } as BuiltinGiftSpec,
  { name: '毛绒小熊', category: 'plush', priceStars: 120 } as BuiltinGiftSpec,
  { name: '回力小赛车', category: 'vehicle', priceStars: 50 } as BuiltinGiftSpec,
  { name: '遥控越野车', category: 'vehicle', priceStars: 300 } as BuiltinGiftSpec,
  { name: '贴纸一册', category: 'stationery', priceStars: 30 } as BuiltinGiftSpec,
  { name: '漂亮笔记本', category: 'stationery', priceStars: 60 } as BuiltinGiftSpec,
  { name: '彩铅套装', category: 'stationery', priceStars: 100 } as BuiltinGiftSpec,
  { name: '冰淇淋一支', category: 'other', priceStars: 30 } as BuiltinGiftSpec,
  { name: '绘本一本', category: 'other', priceStars: 80 } as BuiltinGiftSpec,
  { name: '周末公园野餐', category: 'other', priceStars: 200 } as BuiltinGiftSpec
]

/** 内置礼物固定 id（幂等种子用），index = BUILTIN_GIFTS 下标 */
export function builtinGiftId(index: number): string {
  return `gift_builtin_${String(index).padStart(2, '0')}`
}

// ── 纯函数（spec §9 测试策略）──

export function canAffordGift(balance: number, priceStars: number): boolean {
  return balance >= priceStars
}

export function shortfallFor(balance: number, priceStars: number): number {
  return Math.max(0, priceStars - balance)
}

export function countAffordableGifts(gifts: GiftItem[], balance: number): number {
  let count = 0
  for (let i = 0; i < gifts.length; i++) {
    const gift = gifts[i]
    if (gift.enabled && gift.priceStars <= balance) {
      count++
    }
  }
  return count
}

export function filterGiftsByCategory(gifts: GiftItem[], category: string): GiftItem[] {
  if (category === GIFT_CATEGORY_ALL) {
    return gifts
  }
  return gifts.filter((gift: GiftItem): boolean => gift.category === category)
}

export function sortGiftsForShop(gifts: GiftItem[]): GiftItem[] {
  const sorted: GiftItem[] = [...gifts]
  sorted.sort((a: GiftItem, b: GiftItem): number => a.sortOrder - b.sortOrder)
  return sorted
}

/** 兑换前置判定：礼物不可用 / 余额不足 / 通过。reason/shortfall 语义见 GiftRedeemResult */
export function canRedeem(balance: number, gift: GiftItem | null): GiftRedeemResult {
  if (gift === null || !gift.enabled) {
    const unavailable: GiftRedeemResult = { success: false, reason: 'gift_unavailable', shortfall: 0, redemption: null }
    return unavailable
  }
  if (!canAffordGift(balance, gift.priceStars)) {
    const insufficient: GiftRedeemResult =
      { success: false, reason: 'insufficient', shortfall: shortfallFor(balance, gift.priceStars), redemption: null }
    return insufficient
  }
  const ok: GiftRedeemResult = { success: true, reason: '', shortfall: 0, redemption: null }
  return ok
}
