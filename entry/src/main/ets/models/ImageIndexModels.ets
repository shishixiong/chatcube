/**
 * ImageIndex 数据模型
 *
 * 统一图片索引：替代原来两套并行的图片索引（EnglishQuizImageIndex Preferences +
 * prepared_media SQLite 表）。所有"查图片 / 存图片 / 标记消费 / 清理过期"统一走
 * ImageIndexService + image_index 表。
 *
 * 详见 plan: /Users/mac/.claude/plans/adaptive-stirring-feigenbaum.md
 */

// =================== Source 枚举 ===================

/**
 * 图片索引的来源。
 *
 * - LESSON_PLAN: 备课老师预生成的图（7 天 TTL，写入 prepared_media 风格的 row）
 * - ENGLISH_QUIZ: 英语题出题时生成的图（永不过期，写入 EnglishQuizImageIndex 风格的 row）
 */
export enum ImageSource {
  LESSON_PLAN = 'lesson_plan',
  ENGLISH_QUIZ = 'english_quiz'
}

// =================== Row 类型 ===================

/**
 * image_index 表的一行（DB 原生）。
 *
 * 字段含义：
 * - id: 行主键。由 ImageIndexService.generateId 生成：
 *   - lesson_plan → `pm_<safeKey>`（safeKey = key 中非字母数字字符替换为 `_` 后截断 60 字符）
 *   - english_quiz → `eq_<createdAtMs>_<safeKey>`
 * - source: 'lesson_plan' | 'english_quiz'，与 ImageSource 枚举一一对应。
 * - key: 业务 key。lesson_plan 是 topicKey（如 `vocab.apple`），english_quiz 是 `w:<word>` / `s:<sentence>`。
 * - filePath: 沙盒里的图片绝对路径。
 * - prompt: 生图时使用的原始 prompt。
 * - revisedPrompt: 模型在生图时实际使用的修订 prompt（可能与 prompt 不同）。
 * - providerId/providerName: 调用的模型服务商。
 * - modelId/modelName: 调用的具体模型。
 * - mimeType: 文件 MIME，默认 image/png。
 * - aspectRatio: 比例标签，默认 'square'。
 * - status: 'pending' | 'ready' | 'failed'。只有 'ready' 行可被 findByKey 命中。
 * - errorMessage: 生图失败原因。
 * - consumedCount: 被消费次数（命中 + 1）。
 * - lastConsumedAt: 上次消费时间戳。
 * - createdAt: 行创建时间。
 * - expiresAt: 过期时间戳；0 = 永不过期。
 * - planId: 仅 source='lesson_plan' 时有值；FK CASCADE 引用 daily_lesson_plans.id。
 */
export class ImageIndexRow {
  id: string = ''
  source: string = ImageSource.ENGLISH_QUIZ
  key: string = ''
  filePath: string = ''
  prompt: string = ''
  revisedPrompt: string = ''
  providerId: string = ''
  providerName: string = ''
  modelId: string = ''
  modelName: string = ''
  mimeType: string = 'image/png'
  aspectRatio: string = 'square'
  status: string = 'ready'           // 'pending' | 'ready' | 'failed'
  errorMessage: string = ''
  consumedCount: number = 0
  lastConsumedAt: number = 0
  createdAt: number = 0
  expiresAt: number = 0
  planId: string = ''
}

// =================== 元数据 ===================

/**
 * 写入索引时附带的可选元数据。
 *
 * 用途：复用既有图片文件（来自 prepared_media 表 / 外部导入）写入 image_index 时，
 * 保留 provider_* / model_* / revised_prompt / plan_id 这些原信息。现生图场景
 * （ImageIndexService.generateAndStore 内部）会从 ImageGenerationService 拿到
 * 这些字段自动填充，调用方无需手动传。
 *
 * 所有字段都可选；缺失的字段在 ImageIndexRow 中以空字符串 / 0 存。
 */
export interface ImageIndexMetadata {
  revisedPrompt?: string
  providerId?: string
  providerName?: string
  modelId?: string
  modelName?: string
  aspectRatio?: string
  planId?: string
}
