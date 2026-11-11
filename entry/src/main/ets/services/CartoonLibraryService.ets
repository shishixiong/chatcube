/**
 * 动画片片库服务（spec 2026-11-10 §9）。
 *
 * - 片源不复制：文件选择器返回的 URI 走 fileShare.persistPermission 持久授权
 * - 片库 JSON 存 Preferences（cartoon_library_json）
 * - 启动时对 ok 条目做 activatePermission（重启后重新启用授权）
 */

import { fileIo, fileShare } from '@kit.CoreFileKit'
import { CartoonEntry, CARTOON_SESSION_LIMIT_MS } from '../models/CartoonModels'
import {
  appendCartoonEntry,
  buildCartoonEntryId,
  parseCartoonLibrary,
  parseEpisodeMetaFromUri,
  removeCartoonEntry,
  serializeCartoonLibrary,
  titleFromUri,
  updateCartoonEntry
} from '../utils/CartoonLibraryUtils'
import { readVideoDurationMs } from '../utils/CartoonVideoMetadata'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'

export interface CartoonAddOutcome {
  addedCount: number
  rejectedMessages: string[]
}

export class CartoonLibraryService {
  private static instance: CartoonLibraryService | null = null
  private entries: CartoonEntry[] = []
  private initialized: boolean = false

  static getInstance(): CartoonLibraryService {
    if (CartoonLibraryService.instance === null) {
      CartoonLibraryService.instance = new CartoonLibraryService()
    }
    return CartoonLibraryService.instance
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return
    }
    await this.load()
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i]
      if (entry.status !== 'ok') {
        continue
      }
      try {
        const policy: fileShare.PolicyInfo = {
          uri: entry.uri,
          operationMode: fileShare.OperationMode.READ_MODE
        }
        await fileShare.activatePermission([policy])
      } catch (error) {
        console.warn('CartoonLibraryService', `activatePermission failed: ${JSON.stringify(error)}`)
      }
    }
    this.initialized = true
  }

  private async load(): Promise<void> {
    try {
      const json = await getPreferencesService().getString(PreferenceKeys.CARTOON_LIBRARY_JSON, '')
      this.entries = parseCartoonLibrary(json)
    } catch (error) {
      console.error('CartoonLibraryService', `load failed: ${JSON.stringify(error)}`)
      this.entries = []
    }
  }

  private async persist(): Promise<void> {
    try {
      await getPreferencesService().setString(
        PreferenceKeys.CARTOON_LIBRARY_JSON,
        serializeCartoonLibrary(this.entries)
      )
    } catch (error) {
      console.error('CartoonLibraryService', `persist failed: ${JSON.stringify(error)}`)
    }
  }

  list(): CartoonEntry[] {
    return this.entries.slice()
  }

  findById(id: string): CartoonEntry | null {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].id === id) {
        return this.entries[i]
      }
    }
    return null
  }

  async isUriReadable(uri: string): Promise<boolean> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      fileIo.closeSync(file)
      return true
    } catch (_e) {
      return false
    }
  }

  async addFromUris(uris: string[]): Promise<CartoonAddOutcome> {
    const rejectedMessages: string[] = []
    let addedCount = 0
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i]
      const title = titleFromUri(uri)
      try {
        const policy: fileShare.PolicyInfo = {
          uri: uri,
          operationMode: fileShare.OperationMode.READ_MODE
        }
        await fileShare.persistPermission([policy])
      } catch (error) {
        console.warn('CartoonLibraryService', `persistPermission failed: ${JSON.stringify(error)}`)
        rejectedMessages.push(`无法授权 ${title}`)
        continue
      }
      const durationMs = await readVideoDurationMs(uri)
      if (durationMs <= 0) {
        rejectedMessages.push(`无法读取 ${title}，可能格式不支持`)
        continue
      }
      if (durationMs > CARTOON_SESSION_LIMIT_MS) {
        rejectedMessages.push(`${title} 超过 20 分钟，暂时不能放`)
        continue
      }
      const meta = parseEpisodeMetaFromUri(uri)
      const entry: CartoonEntry = {
        id: buildCartoonEntryId(Date.now(), Math.random().toString(36).slice(2, 6)),
        uri: uri,
        title: meta.title,
        tags: '',
        durationMs: durationMs,
        addedAt: Date.now(),
        status: 'ok',
        seriesTitle: meta.seriesTitle,
        season: meta.season,
        episode: meta.episode,
        lastWatchedAt: 0
      }
      const before = this.entries.length
      this.entries = appendCartoonEntry(this.entries, entry)
      if (this.entries.length > before) {
        addedCount += 1
      }
    }
    await this.persist()
    const outcome: CartoonAddOutcome = {
      addedCount: addedCount,
      rejectedMessages: rejectedMessages
    }
    return outcome
  }

  async updateEntry(id: string, seriesTitle: string, season: number, episode: number,
    title: string, tags: string): Promise<boolean> {
    if (this.findById(id) === null) {
      return false
    }
    this.entries = updateCartoonEntry(this.entries, id, seriesTitle, season, episode, title, tags)
    await this.persist()
    return true
  }

  /** 完整看完一集后才推进「下一集」 */
  async markWatched(id: string): Promise<void> {
    const entry = this.findById(id)
    if (entry === null) {
      return
    }
    entry.lastWatchedAt = Date.now()
    await this.persist()
  }

  async removeEntry(id: string): Promise<boolean> {
    const before = this.entries.length
    this.entries = removeCartoonEntry(this.entries, id)
    if (this.entries.length === before) {
      return false
    }
    await this.persist()
    return true
  }

  async refreshStatuses(): Promise<void> {
    let changed = false
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i]
      const readable = await this.isUriReadable(entry.uri)
      const nextStatus = readable ? 'ok' : 'unavailable'
      if (entry.status !== nextStatus) {
        entry.status = nextStatus
        changed = true
      }
    }
    if (changed) {
      await this.persist()
    }
  }

  /** 替换失效条目的 URI；返回 '' 表示成功，否则返回给家长的提示文案 */
  async relinkEntry(id: string, uri: string): Promise<string> {
    const entry = this.findById(id)
    if (entry === null) {
      return '这条动画片已经不在片库里了'
    }
    const title = titleFromUri(uri)
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE
      }
      await fileShare.persistPermission([policy])
    } catch (error) {
      return `无法授权 ${title}`
    }
    const durationMs = await readVideoDurationMs(uri)
    if (durationMs <= 0) {
      return `无法读取 ${title}，可能格式不支持`
    }
    if (durationMs > CARTOON_SESSION_LIMIT_MS) {
      return `${title} 超过 20 分钟，暂时不能放`
    }
    entry.uri = uri
    entry.durationMs = durationMs
    entry.status = 'ok'
    await this.persist()
    return ''
  }

  async updateDuration(id: string, durationMs: number): Promise<void> {
    const entry = this.findById(id)
    if (entry === null || durationMs <= 0 || entry.durationMs === durationMs) {
      return
    }
    entry.durationMs = durationMs
    await this.persist()
  }

  /** 播放前发现文件打不开时调用，管理页会显示「失效」 */
  async markUnavailable(id: string): Promise<void> {
    const entry = this.findById(id)
    if (entry === null || entry.status === 'unavailable') {
      return
    }
    entry.status = 'unavailable'
    await this.persist()
  }
}

export function getCartoonLibraryService(): CartoonLibraryService {
  return CartoonLibraryService.getInstance()
}
