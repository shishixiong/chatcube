/**
 * ImageIndexService - 统一图片索引数据访问层
 *
 * 替代原来两套并行的图片索引：
 *   1. EnglishQuizImageIndex (Preferences JSON) - 英语题缓存
 *   2. prepared_media (SQLite 表) - 备课老师预生成图
 *
 * 新方案：所有"查图片 / 存图片 / 标记消费 / 清理过期"都走 image_index 表 + 这个服务。
 * LessonPlanningService（备课）和 handleEnglishQuiz（出题）都是它的消费者。
 *
 * 详见 plan: /Users/mac/.claude/plans/adaptive-stirring-feigenbaum.md
 */

import {
  AttachmentType,
  MessageAttachment,
  ModelInfo,
  ModelProvider,
  OutputMode
} from '../models/ChatModels'
import {
  ImageAspectRatio,
  ImageGenerationRequest
} from '../models/ImageGenerationModels'
import { ImageIndexMetadata, ImageIndexRow, ImageSource } from '../models/ImageIndexModels'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import { getImageGenerationService, ImageGenerationService } from './ImageGenerationService'
import { getAttachmentStorageService, AttachmentStorageService } from './AttachmentStorageService'
import { getAppSettingsState } from '../state/AppSettingsState'
import { getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'

// =================== 常量 ===================

/** lesson_plan 源行 TTL：7 天 */
const LESSON_PLAN_TTL_MS = 200 * 24 * 60 * 60 * 1000

// =================== 类型别名 ===================

/** cleanupExpired 返回值。明确命名类型避免 ArkTS 10605040。 */
interface CleanupExpiredResult {
  files: number
  rows: number
}

/** resolveImageModel 返回值。 */
interface ResolvedImageModel {
  provider: ModelProvider
  model: ModelInfo
}

// =================== 服务实现 ===================

export class ImageIndexService {
  private static instance: ImageIndexService | null = null

  private get databaseService(): DatabaseService {
    return getDatabaseService()
  }

  private get imageGenerationService(): ImageGenerationService {
    return getImageGenerationService()
  }

  private get attachmentStorageService(): AttachmentStorageService {
    return getAttachmentStorageService()
  }

  private constructor() {
  }

  static getInstance(): ImageIndexService {
    if (ImageIndexService.instance === null) {
      ImageIndexService.instance = new ImageIndexService()
    }
    return ImageIndexService.instance
  }

  /**
   * 构建英语题索引 key。
   * - 单词题: w:<lowercase word>
   * - 句子题: s:<lowercase sentence, spaces→_, 截断 60 字符>
   * - 都为空: '' (无效 key)
   */
  static buildEnglishQuizKey(word: string, sentence: string): string {
    if (word !== '' && sentence === '') {
      return `w:${word.trim().toLowerCase()}`
    }
    if (sentence !== '') {
      return `s:${sentence.trim().toLowerCase().replace(/\s+/g, '_').substring(0, 60)}`
    }
    return ''
  }

  /**
   * 查：按 (source, key) 查找最近一张未过期的 ready 行。
   * 匹配规则：status='ready' AND (expires_at=0 OR expires_at>nowMs)。
   * 未命中返回 null。
   */
  async findByKey(source: ImageSource, key: string): Promise<ImageIndexRow | null> {
    if (key === '') {
      return null
    }
    return await this.databaseService.findImageIndexByKey(source, key, Date.now())
  }

  /**
   * 存：把已有图片文件写入索引。
   * 用途：复用 prepared_media 预生成的图、英文 quiz 命中 lesson_plan 后写回英语题缓存等。
   *
   * @param source 来源
   * @param key 业务 key
   * @param filePath 沙盒绝对路径
   * @param prompt 生成时使用的 prompt
   * @param mimeType MIME 类型（默认 image/png）
   * @param metadata 可选元数据（provider_*, model_*, revised_prompt, plan_id）
   * @returns 写入的行；source+key 已存在时返回已存在行（不覆盖）；参数非法返回 null
   */
  async putEntry(
    source: ImageSource,
    key: string,
    filePath: string,
    prompt: string,
    mimeType: string = 'image/png',
    metadata?: ImageIndexMetadata
  ): Promise<ImageIndexRow | null> {
    if (filePath === '' || key === '') {
      return null
    }
    const now = Date.now()
    const existing = await this.databaseService.findImageIndexByKey(source, key, now)
    if (existing !== null) {
      // UNIQUE 冲突 → 不覆盖，返回已有行
      console.info('ImageIndexService',
        `putEntry skipped: (source=${source}, key=${key}) already exists with id=${existing.id}`)
      return existing
    }
    const row = new ImageIndexRow()
    row.id = ImageIndexService.generateId(source, key, now)
    row.source = source
    row.key = key
    row.filePath = filePath
    row.prompt = prompt
    row.mimeType = mimeType
    row.status = 'ready'
    row.createdAt = now
    row.expiresAt = source === ImageSource.LESSON_PLAN ? now + LESSON_PLAN_TTL_MS : 0
    if (metadata !== undefined) {
      row.revisedPrompt = metadata.revisedPrompt ?? ''
      row.providerId = metadata.providerId ?? ''
      row.providerName = metadata.providerName ?? ''
      row.modelId = metadata.modelId ?? ''
      row.modelName = metadata.modelName ?? ''
      row.aspectRatio = metadata.aspectRatio ?? 'square'
      row.planId = metadata.planId ?? ''
    }
    const ok = await this.databaseService.upsertImageIndex(row)
    if (!ok) {
      // upsert 失败可能是真错误，也可能是 UNIQUE(source, key) 冲突：
      // 并发场景下另一个 caller 在我们 findByKey 检查之后、insert 之前抢占了。
      // 再查一次：如果现在有行，说明是 race，对外返回赢家行（保证 caller 拿到的是
      // 真实存在于 DB 中的 row，而不是带我们本地 id 的幻影）；否则是真失败。
      const winner = await this.databaseService.findImageIndexByKey(source, key, now)
      if (winner !== null) {
        console.info('ImageIndexService',
          `putEntry race resolved: (source=${source}, key=${key}) won by id=${winner.id}`)
        return winner
      }
      return null
    }
    return row
  }

  /**
   * 完整生图：解析默认 image model → 调 ImageGenerationService → 存到沙箱 → 写索引。
   * 失败（无 image model / 接口失败 / 沙箱写盘失败）返回 null。
   * 已有 (source, key) 时跳过生图直接返回已存在行。
   *
   * 并发说明：若两个 caller 同时对同一 (source, key) 调 generateAndStore，
   * 两者都会通过 findByKey 检查并各自生图（浪费 1 次生图 + 1 个孤儿文件）。
   * 第二个 caller 的 upsert 会因 UNIQUE 约束失败；此时 re-fetch 返回赢家行，
   * 让 caller 仍然拿到可用的 imagePath，避免因 race 丢失图。
   */
  async generateAndStore(
    source: ImageSource,
    key: string,
    prompt: string
  ): Promise<ImageIndexRow | null> {
    if (key === '' || prompt === '') {
      return null
    }
    const existing = await this.findByKey(source, key)
    if (existing !== null) {
      return existing
    }
    const resolved = await this.resolveImageModel()
    if (resolved === null) {
      console.error('ImageIndexService', 'generateAndStore: no image model available')
      return null
    }
    const provider: ModelProvider = resolved.provider
    const model: ModelInfo = resolved.model

    const request = new ImageGenerationRequest()
    request.providerId = provider.id
    request.modelId = model.id
    request.prompt = prompt
    request.numberOfImages = 1
    request.aspectRatio = ImageAspectRatio.SQUARE

    try {
      const imageResult = await this.imageGenerationService.generateImage(provider, model, request)
      if (imageResult.items.length === 0) {
        console.error('ImageIndexService', 'generateAndStore: empty result')
        return null
      }
      const item = imageResult.items[0]
      const id = ImageIndexService.generateId(source, key, Date.now())
      const ext = ImageIndexService.resolveExtension(item.mimeType)
      const attachment = new MessageAttachment(
        id,
        AttachmentType.IMAGE,
        `${id}${ext}`,
        '',
        item.mimeType,
        0
      )
      attachment.base64Data = item.base64Data
      const filePath = await this.attachmentStorageService.saveAttachment(attachment)
      if (filePath === '') {
        console.error('ImageIndexService', 'generateAndStore: sandbox save failed')
        return null
      }
      const row = new ImageIndexRow()
      row.id = id
      row.source = source
      row.key = key
      row.filePath = filePath
      row.prompt = prompt
      row.revisedPrompt = item.revisedPrompt
      row.providerId = provider.id
      row.providerName = provider.name
      row.modelId = model.id
      row.modelName = model.name !== '' ? model.name : model.id
      row.mimeType = item.mimeType
      row.aspectRatio = 'square'
      row.status = 'ready'
      const now = Date.now()
      row.createdAt = now
      row.expiresAt = source === ImageSource.LESSON_PLAN ? row.createdAt + LESSON_PLAN_TTL_MS : 0
      const ok = await this.databaseService.upsertImageIndex(row)
      if (!ok) {
        // 并发 race：另一个 caller 在我们 findByKey 之后、insert 之前抢占了
        // (source, key)。re-fetch 返回赢家行，避免 caller 因 race 拿到 null。
        const winner = await this.databaseService.findImageIndexByKey(source, key, now)
        if (winner !== null) {
          console.info('ImageIndexService',
            `generateAndStore race resolved: (source=${source}, key=${key}) won by id=${winner.id}`)
          return winner
        }
        return null
      }
      console.info('ImageIndexService',
        `generateAndStore success: source=${source}, key=${key}, id=${id}`)
      return row
    } catch (error) {
      console.error('ImageIndexService', `generateAndStore failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  /**
   * 标记消费：递增 consumed_count + 更新 last_consumed_at。
   * 行不存在时静默返回（best-effort）。
   */
  async markConsumed(id: string): Promise<void> {
    await this.databaseService.markImageIndexConsumed(id, Date.now())
  }

  /**
   * 清理过期行：expires_at > 0 AND expires_at < nowMs。
   * - 先列过期行（带 filePath） → 删沙箱文件（best-effort） → 删行
   * - 永不过期行（expires_at=0）不会被清理
   * 返回 { files: 删了几个文件, rows: 删了几行 }
   */
  async cleanupExpired(): Promise<CleanupExpiredResult> {
    const now = Date.now()
    const expired = await this.databaseService.listExpiredImageIndex(now)
    let filesDeleted = 0
    for (let i = 0; i < expired.length; i++) {
      const row = expired[i]
      if (row.filePath === '') {
        continue
      }
      try {
        await this.attachmentStorageService.deleteAttachment(row.filePath)
        filesDeleted += 1
      } catch (error) {
        console.warn('ImageIndexService',
          `cleanupExpired: failed to delete file ${row.filePath}: ${JSON.stringify(error)}`)
      }
    }
    const rowsDeleted = await this.databaseService.deleteExpiredImageIndex(now)
    if (rowsDeleted > 0 || filesDeleted > 0) {
      console.info('ImageIndexService',
        `cleanupExpired: files=${filesDeleted}, rows=${rowsDeleted}`)
    }
    const result: CleanupExpiredResult = { files: filesDeleted, rows: rowsDeleted }
    return result
  }

  /**
   * 管理：按 source 列出（dev 页面 / 统计用），按 created_at DESC 排序。
   */
  async getBySource(source: ImageSource, limit: number = 200): Promise<ImageIndexRow[]> {
    return await this.databaseService.listImageIndexBySource(source, limit)
  }

  /**
   * 管理：按 (source, key) 删除行（不删文件）。
   * 返回是否删除了至少一行。
   */
  async removeByKey(source: ImageSource, key: string): Promise<boolean> {
    return await this.databaseService.deleteImageIndexByKey(source, key)
  }

  // =================== 私有方法 ===================

  /**
   * 解析默认 image model。从 AppSettingsState.defaultImageModel 找第一个可用的图片模型。
   * 复用原 EnglishQuizImageIndex.generate 里的解析逻辑（40 行重复代码统一）。
   */
  private async resolveImageModel(): Promise<ResolvedImageModel | null> {
    const state = getAppSettingsState()
    const defaultImage = state.defaultImageModel
    let provider: ModelProvider | null = null
    let model: ModelInfo | null = null

    if (defaultImage.providerId !== '' && defaultImage.modelId !== '') {
      for (let i = 0; i < state.providers.length; i++) {
        const p = state.providers[i]
        if (p.id === defaultImage.providerId) {
          for (let j = 0; j < p.models.length; j++) {
            const m = p.models[j]
            if (m.id === defaultImage.modelId && getEffectiveOutputMode(m) === OutputMode.IMAGE) {
              provider = p
              model = m
              break
            }
          }
          break
        }
      }
    }

    if (provider === null || model === null) {
      for (let i = 0; i < state.providers.length; i++) {
        const p = state.providers[i]
        for (let j = 0; j < p.models.length; j++) {
          const m = p.models[j]
          if (m.isEnabled && getEffectiveOutputMode(m) === OutputMode.IMAGE) {
            provider = p
            model = m
            break
          }
        }
        if (provider !== null) {
          break
        }
      }
    }

    if (provider === null || model === null) {
      return null
    }
    const resolved: ResolvedImageModel = { provider, model }
    return resolved
  }

  private static generateId(source: ImageSource, key: string, nowMs: number): string {
    const safeKey = key.replace(/[^a-z0-9_]/gi, '_').substring(0, 60)
    if (source === ImageSource.LESSON_PLAN) {
      // 沿用 prepared_media 的命名风格: pm_<topicKey>
      return `pm_${safeKey}`
    } else {
      return `eq_${nowMs}_${safeKey}`
    }
  }

  private static resolveExtension(mimeType: string): string {
    if (mimeType === 'image/jpeg') {
      return '.jpg'
    }
    if (mimeType === 'image/webp') {
      return '.webp'
    }
    return '.png'
  }
}

// =================== 单例 helper ===================

export function getImageIndexService(): ImageIndexService {
  return ImageIndexService.getInstance()
}
