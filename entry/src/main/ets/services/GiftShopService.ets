/**
 * 星星礼物商城服务（spec docs/superpowers/specs/2026-10-19-star-gift-shop-design.md §4.4）
 *
 * 单例，镜像 StarRewardService 模式。gifts/gift_redemptions 两表的唯一业务写入口：
 * - 余额 = StarRewardService.getAllTimeStarTotal() − getRedeemedStarsTotal()
 * - redeem() 是唯一兑换写路径：前置判定（canRedeem 纯函数）→ 领取码 → 写快照流水
 * - 内置礼物（is_builtin=1）对编辑/删除守卫拒绝，语义对齐内置助手锁定
 */

import { util } from '@kit.ArkTS'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import { getStarRewardService } from './StarRewardService'
import {
  GiftItem,
  GiftRedemptionRow,
  GiftRedeemResult,
  GiftShopStats,
  canRedeem,
  GIFT_STATUS_PENDING
} from '../models/GiftModels'
import { generateRedeemCode, REDEEM_CODE_RETRY_LIMIT } from '../utils/RedeemCodeUtils'

export class GiftShopService {
  private static instance: GiftShopService | null = null
  private database: DatabaseService

  private constructor() {
    this.database = getDatabaseService()
  }

  static getInstance(): GiftShopService {
    if (GiftShopService.instance === null) {
      GiftShopService.instance = new GiftShopService()
    }
    return GiftShopService.instance
  }

  /** 商城用：仅上架礼物，sort_order 升序 */
  async getGiftsForShop(): Promise<GiftItem[]> {
    const all = await this.database.getGifts()
    return all.filter((gift: GiftItem): boolean => gift.enabled)
  }

  /** 管理页用：全量（含下架/内置） */
  async getGiftsForManage(): Promise<GiftItem[]> {
    return await this.database.getGifts()
  }

  async addCustomGift(name: string, category: string, priceStars: number): Promise<boolean> {
    const gift: GiftItem = {
      id: `gift_custom_${util.generateRandomUUID(false)}`,
      name: name.trim(),
      category: category,
      priceStars: Math.max(1, Math.floor(priceStars)),
      isBuiltin: false,
      enabled: true,
      sortOrder: Date.now()
    }
    return await this.database.insertGift(gift)
  }

  async updateCustomGift(gift: GiftItem): Promise<boolean> {
    if (gift.isBuiltin) {
      console.warn('GiftShopService', 'refuse to update builtin gift')
      return false
    }
    return await this.database.updateGift(gift)
  }

  async deleteCustomGift(id: string): Promise<boolean> {
    const all = await this.database.getGifts()
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === id) {
        if (all[i].isBuiltin) {
          console.warn('GiftShopService', 'refuse to delete builtin gift')
          return false
        }
        return await this.database.deleteGift(id)
      }
    }
    return false
  }

  async getStarBalance(): Promise<number> {
    return await getStarRewardService().getStarBalance()
  }

  async getShopStats(): Promise<GiftShopStats> {
    const redemptions: GiftRedemptionRow[] = await this.database.getGiftRedemptions()
    let redeemedTotal = 0
    for (let i = 0; i < redemptions.length; i++) {
      redeemedTotal += redemptions[i].priceStars
    }
    const earnedTotal: number = await getStarRewardService().getAllTimeStarTotal()
    const stats: GiftShopStats = {
      earnedTotal: earnedTotal,
      redeemedTotal: redeemedTotal,
      redeemCount: redemptions.length
    }
    return stats
  }

  /**
   * 兑换（唯一写路径，spec §4.4 流程）：
   * 礼物可用性 → 余额（canRedeem 纯函数）→ 领取码（pending 碰撞重试 ≤3 次，
   * 仍碰撞用最后一个候选——31^6 空间下可忽略）→ 写快照流水。
   * 余额检查与写入无事务（单设备单用户，超兑至多 1 次且 UI 立即暴露）。
   */
  async redeem(giftId: string): Promise<GiftRedeemResult> {
    const gifts: GiftItem[] = await this.database.getGifts()
    let targetIndex = -1
    for (let i = 0; i < gifts.length; i++) {
      if (gifts[i].id === giftId) {
        targetIndex = i
        break
      }
    }
    const balance: number = await this.getStarBalance()
    if (targetIndex < 0) {
      const missing: GiftRedeemResult = { success: false, reason: 'gift_unavailable', shortfall: 0, redemption: null }
      return missing
    }
    const check: GiftRedeemResult = canRedeem(balance, gifts[targetIndex])
    if (!check.success) {
      return check
    }
    const gift: GiftItem = gifts[targetIndex]

    let code = ''
    for (let attempt = 0; attempt < REDEEM_CODE_RETRY_LIMIT; attempt++) {
      const candidate: string = generateRedeemCode()
      code = candidate
      const pending: GiftRedemptionRow[] = await this.database.getGiftRedemptions()
      let collision = false
      for (let i = 0; i < pending.length; i++) {
        if (pending[i].status === GIFT_STATUS_PENDING && pending[i].redeemCode === candidate) {
          collision = true
          break
        }
      }
      if (!collision) {
        break
      }
    }

    const redemption: GiftRedemptionRow = {
      id: `redeem_${util.generateRandomUUID(false)}`,
      giftId: gift.id,
      giftName: gift.name,
      category: gift.category,
      priceStars: gift.priceStars,
      redeemCode: code,
      status: GIFT_STATUS_PENDING,
      createdAt: Date.now(),
      pickedAt: 0
    }
    const ok: boolean = await this.database.insertGiftRedemption(redemption)
    if (!ok) {
      const failed: GiftRedeemResult = { success: false, reason: 'db_error', shortfall: 0, redemption: null }
      return failed
    }
    const success: GiftRedeemResult = { success: true, reason: '', shortfall: 0, redemption: redemption }
    return success
  }

  async getRedemptions(): Promise<GiftRedemptionRow[]> {
    return await this.database.getGiftRedemptions()
  }

  async getPendingRedemptionCount(): Promise<number> {
    const rows: GiftRedemptionRow[] = await this.database.getGiftRedemptions()
    let count = 0
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].status === GIFT_STATUS_PENDING) {
        count++
      }
    }
    return count
  }

  async markRedemptionPicked(id: string): Promise<boolean> {
    return await this.database.markRedemptionPicked(id, Date.now())
  }
}

export function getGiftShopService(): GiftShopService {
  return GiftShopService.getInstance()
}
