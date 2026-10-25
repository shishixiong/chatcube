import { describe, it, expect } from '@ohos/hypium'
import {
  BUILTIN_GIFTS,
  GiftItem,
  GIFT_CATEGORIES,
  builtinGiftId,
  canAffordGift,
  shortfallFor,
  countAffordableGifts,
  filterGiftsByCategory,
  sortGiftsForShop,
  canRedeem,
  getGiftCategoryMeta,
  GIFT_CATEGORY_ALL
} from '../../../../main/ets/models/GiftModels'

/**
 * GiftModels 纯函数单元测试（spec 2026-10-19 §9）
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用（MEMORY.md）
 */
function makeGift(id: string, priceStars: number, enabled: boolean, sortOrder: number, category: string): GiftItem {
  const gift: GiftItem = {
    id: id, name: `礼物${id}`, category: category, priceStars: priceStars,
    isBuiltin: false, enabled: enabled, sortOrder: sortOrder
  }
  return gift
}

export default function giftModelsTest() {
  describe('GiftModels', () => {
    it('canAffordGift_边界_恰好等于', 0, () => {
      expect(canAffordGift(60, 60)).assertTrue()
      expect(canAffordGift(59, 60)).assertFalse()
      expect(canAffordGift(61, 60)).assertTrue()
    })
    it('shortfallFor_差几颗', 0, () => {
      expect(shortfallFor(59, 60)).assertEqual(1)
      expect(shortfallFor(100, 60)).assertEqual(0)
      expect(shortfallFor(0, 30)).assertEqual(30)
    })
    it('countAffordableGifts_只数enabled', 0, () => {
      const gifts: GiftItem[] = [
        makeGift('a', 30, true, 1, 'other'),
        makeGift('b', 60, true, 2, 'other'),
        makeGift('c', 40, false, 3, 'other')
      ]
      expect(countAffordableGifts(gifts, 50)).assertEqual(1)
      expect(countAffordableGifts(gifts, 100)).assertEqual(2)
      expect(countAffordableGifts(gifts, 0)).assertEqual(0)
    })
    it('filterGiftsByCategory_all_不过滤', 0, () => {
      const gifts: GiftItem[] = [
        makeGift('a', 30, true, 1, 'other'),
        makeGift('b', 60, true, 2, 'plush')
      ]
      expect(filterGiftsByCategory(gifts, GIFT_CATEGORY_ALL).length).assertEqual(2)
      expect(filterGiftsByCategory(gifts, 'plush').length).assertEqual(1)
      expect(filterGiftsByCategory(gifts, 'vehicle').length).assertEqual(0)
    })
    it('sortGiftsForShop_按sortOrder升序_不改原数组', 0, () => {
      const gifts: GiftItem[] = [makeGift('b', 60, true, 2, 'other'), makeGift('a', 30, true, 1, 'other')]
      const sorted: GiftItem[] = sortGiftsForShop(gifts)
      expect(sorted[0].id).assertEqual('a')
      expect(gifts[0].id).assertEqual('b')
    })
    it('canRedeem_三种拒绝_一种通过', 0, () => {
      const off: GiftItem = makeGift('x', 30, false, 1, 'other')
      expect(canRedeem(100, off).success).assertFalse()
      expect(canRedeem(100, off).reason).assertEqual('gift_unavailable')
      expect(canRedeem(100, null).reason).assertEqual('gift_unavailable')
      const poor: GiftItem = makeGift('x', 300, true, 1, 'other')
      const poorResult = canRedeem(100, poor)
      expect(poorResult.success).assertFalse()
      expect(poorResult.reason).assertEqual('insufficient')
      expect(poorResult.shortfall).assertEqual(200)
      const ok: GiftItem = makeGift('x', 100, true, 1, 'other')
      expect(canRedeem(100, ok).success).assertTrue()
    })
    it('builtinGiftId_两位序号', 0, () => {
      expect(builtinGiftId(0)).assertEqual('gift_builtin_00')
      expect(builtinGiftId(11)).assertEqual('gift_builtin_11')
      expect(builtinGiftId(12)).assertEqual('gift_builtin_12')
    })
    it('BUILTIN_GIFTS_13件_价格合法_分类合法', 0, () => {
      expect(BUILTIN_GIFTS.length).assertEqual(13)
      const lego = BUILTIN_GIFTS[12]
      expect(lego.name).assertEqual('乐高积木一盒')
      expect(lego.priceStars).assertEqual(500)
      expect(lego.category).assertEqual('building')
      for (let i = 0; i < BUILTIN_GIFTS.length; i++) {
        expect(BUILTIN_GIFTS[i].priceStars >= 1).assertTrue()
        expect(GIFT_CATEGORIES.indexOf(BUILTIN_GIFTS[i].category) >= 0).assertTrue()
      }
    })
    it('getGiftCategoryMeta_未知分类回退other', 0, () => {
      expect(getGiftCategoryMeta('plush').label).assertEqual('玩偶')
      expect(getGiftCategoryMeta('nope').label).assertEqual('其他')
    })
  })
}
