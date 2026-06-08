import {
  AttachmentType,
  MessageAttachment,
  ModelInfo,
  ModelProvider,
  OutputMode
} from '../models/ChatModels'
import {
  ImageAspectRatio,
  ImageGenerationItem,
  ImageGenerationRequest
} from '../models/ImageGenerationModels'
import { getImageGenerationService } from './ImageGenerationService'
import { getAttachmentStorageService } from './AttachmentStorageService'
import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'
import { getAppSettingsState } from '../state/AppSettingsState'
import { getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'

/**
 * 英语出题工具图片缓存条目
 */
export class EnglishQuizImageEntry {
  key: string = ''
  word: string = ''
  sentence: string = ''
  prompt: string = ''
  filePath: string = ''
  mimeType: string = ''
  createdAt: number = 0

  constructor(key: string = '', word: string = '', sentence: string = '', prompt: string = '',
    filePath: string = '', mimeType: string = '') {
    this.key = key
    this.word = word
    this.sentence = sentence
    this.prompt = prompt
    this.filePath = filePath
    this.mimeType = mimeType
    this.createdAt = Date.now()
  }
}

/**
 * 英语出题工具图片缓存索引
 *
 * 缓存已生成的图片，避免重复调用图片生成 API。
 * key 策略：单词模式用 word 本身（小写），句子模式用 sentence 的简化形式。
 * 持久化到 PreferencesService JSON。
 */
export class EnglishQuizImageIndex {
  private static instance: EnglishQuizImageIndex | null = null
  private preferences: PreferencesService
  private index: Map<string, EnglishQuizImageEntry> = new Map()
  private isLoaded: boolean = false

  private constructor() {
    this.preferences = getPreferencesService()
  }

  static getInstance(): EnglishQuizImageIndex {
    if (EnglishQuizImageIndex.instance === null) {
      EnglishQuizImageIndex.instance = new EnglishQuizImageIndex()
    }
    return EnglishQuizImageIndex.instance
  }

  /**
   * 构建索引 key
   */
  static buildKey(word: string, sentence: string): string {
    if (word !== '' && sentence === '') {
      return `w:${word.trim().toLowerCase()}`
    }
    if (sentence !== '') {
      return `s:${sentence.trim().toLowerCase().replace(/\s+/g, '_').substring(0, 60)}`
    }
    return ''
  }

  /**
   * 确保索引已加载
   */
  private async ensureLoaded(): Promise<void> {
    if (this.isLoaded) {
      return
    }
    const json = await this.preferences.getString(PreferenceKeys.ENGLISH_QUIZ_IMAGE_INDEX_JSON, '')
    if (json !== '') {
      try {
        const parsed = JSON.parse(json) as Object
        const record = parsed as Record<string, Object>
        const keys = Object.keys(record)
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i]
          const entryObj = record[key] as Record<string, Object>
          const entry = new EnglishQuizImageEntry()
          entry.key = key
          entry.word = (entryObj['word'] as string) ?? ''
          entry.sentence = (entryObj['sentence'] as string) ?? ''
          entry.prompt = (entryObj['prompt'] as string) ?? ''
          entry.filePath = (entryObj['filePath'] as string) ?? ''
          entry.mimeType = (entryObj['mimeType'] as string) ?? ''
          entry.createdAt = (entryObj['createdAt'] as number) ?? 0
          if (entry.filePath !== '') {
            this.index.set(key, entry)
          }
        }
      } catch (error) {
        console.error('EnglishQuizImageIndex', `Failed to parse index JSON: ${JSON.stringify(error)}`)
      }
    }
    this.isLoaded = true
  }

  /**
   * 查找缓存的图片
   */
  async lookup(word: string, sentence: string): Promise<EnglishQuizImageEntry | null> {
    await this.ensureLoaded()
    const key = EnglishQuizImageIndex.buildKey(word, sentence)
    if (key === '') {
      return null
    }
    return this.index.get(key) ?? null
  }

  /**
   * 生成图片并缓存
   */
  async generate(word: string, sentence: string, prompt: string): Promise<EnglishQuizImageEntry | null> {
    await this.ensureLoaded()
    const key = EnglishQuizImageIndex.buildKey(word, sentence)
    if (key === '') {
      return null
    }

    // 解析图片生成 provider/model (复用 BuiltinTools 中的逻辑)
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

    // 回退: 扫描所有 provider 找到第一个可用的图片模型
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
      console.error('EnglishQuizImageIndex', 'No image generation model available')
      return null
    }

    // 构建请求
    const request = new ImageGenerationRequest()
    request.providerId = provider.id
    request.modelId = model.id
    request.prompt = prompt
    request.numberOfImages = 1
    request.aspectRatio = ImageAspectRatio.SQUARE

    try {
      const result = await getImageGenerationService().generateImage(provider, model, request)
      if (result.items.length === 0) {
        console.error('EnglishQuizImageIndex', 'Image generation returned no items')
        return null
      }

      const item: ImageGenerationItem = result.items[0]
      const id = `eq_${Date.now()}_${Math.floor(Math.random() * 100000)}`
      const attachment = new MessageAttachment(
        id,
        AttachmentType.IMAGE,
        `${id}${this.resolveExtension(item.mimeType)}`,
        '',
        item.mimeType,
        0
      )
      attachment.base64Data = item.base64Data
      const filePath = await getAttachmentStorageService().saveAttachment(attachment)
      attachment.base64Data = ''

      if (filePath === '') {
        console.error('EnglishQuizImageIndex', 'Failed to save generated image')
        return null
      }

      const entry = new EnglishQuizImageEntry(key, word, sentence, prompt, filePath, item.mimeType)
      this.index.set(key, entry)
      await this.persist()

      console.info('EnglishQuizImageIndex', `Generated and cached image for key="${key}", path="${filePath}"`)
      return entry
    } catch (error) {
      console.error('EnglishQuizImageIndex', `Image generation failed: ${JSON.stringify(error)}`)
      return null
    }
  }

  /**
   * 持久化索引到 Preferences
   */
  private async persist(): Promise<void> {
    const record: Record<string, Object> = {}
    this.index.forEach((entry: EnglishQuizImageEntry, key: string) => {
      const obj: Record<string, Object> = {
        'word': entry.word,
        'sentence': entry.sentence,
        'prompt': entry.prompt,
        'filePath': entry.filePath,
        'mimeType': entry.mimeType,
        'createdAt': entry.createdAt
      }
      record[key] = obj as Object
    })
    const json = JSON.stringify(record)
    await this.preferences.setString(PreferenceKeys.ENGLISH_QUIZ_IMAGE_INDEX_JSON, json)
  }

  private resolveExtension(mimeType: string): string {
    if (mimeType === 'image/jpeg') {
      return '.jpg'
    }
    if (mimeType === 'image/webp') {
      return '.webp'
    }
    return '.png'
  }

  /**
   * 获取缓存条目数量
   */
  async size(): Promise<number> {
    await this.ensureLoaded()
    return this.index.size
  }

  /**
   * 获取所有缓存条目（仅 filePath 非空），按 createdAt DESC 排序。
   * slice(0, 200) 防御性截断，避免返回过多数据。
   */
  async getAllEntries(): Promise<EnglishQuizImageEntry[]> {
    await this.ensureLoaded()
    const all: EnglishQuizImageEntry[] = []
    this.index.forEach((entry: EnglishQuizImageEntry) => {
      all.push(entry)
    })
    all.sort((a: EnglishQuizImageEntry, b: EnglishQuizImageEntry) => b.createdAt - a.createdAt)
    return all.slice(0, 200)
  }
}

export function getEnglishQuizImageIndex(): EnglishQuizImageIndex {
  return EnglishQuizImageIndex.getInstance()
}
