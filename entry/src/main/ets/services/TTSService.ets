import { common } from '@kit.AbilityKit'
import { ITtsEngine, TTSCallback } from './tts/ITtsEngine'
import { resolveTtsEngine } from './registry/TtsEngineRegistry'
import { TtsEngineId, TTS_FALLBACK_ENGINE_ID } from '../config/TtsConfig'
import { getAppSettingsStore } from '../state/AppSettingsStore'
import { observeAppSettingsState } from '../state/AppSettingsState'

export { TTSCallback } from './tts/ITtsEngine'

export class TTSService {
  private currentEngine: ITtsEngine | null = null
  private currentEngineId: TtsEngineId = TTS_FALLBACK_ENGINE_ID
  private initContext: common.Context | null = null
  private unsubscribe: (() => void) | null = null

  async init(context: common.Context): Promise<void> {
    this.initContext = context
    this.resolveAndBindEngine(getAppSettingsStore().getTtsEngineId())

    this.unsubscribe = observeAppSettingsState('ttsEngineVersion', () => {
      this.resolveAndBindEngine(getAppSettingsStore().getTtsEngineId())
    })
    console.info('TTSService', `init done, current engine: ${this.currentEngineId}`)
  }

  async speak(text: string, callback: TTSCallback): Promise<void> {
    const processedText = this.preprocessTextForTTS(text)
    if (processedText === '') {
      callback.onError('没有可朗读的内容')
      return
    }
    if (this.currentEngine === null) {
      callback.onError('朗读服务未初始化')
      return
    }
    await this.currentEngine.speak(processedText, callback)
  }

  stop(): void {
    this.currentEngine?.stop()
  }

  isSpeaking(): boolean {
    return this.currentEngine !== null && this.currentEngine.isSpeaking()
  }

  getCurrentEngineId(): TtsEngineId {
    return this.currentEngineId
  }

  destroy(): void {
    this.currentEngine?.destroy()
    this.currentEngine = null
    this.unsubscribe?.()
    this.unsubscribe = null
    this.initContext = null
  }

  private resolveAndBindEngine(id: string): void {
    // 切换前: 如在朗读, 先停
    if (this.currentEngine !== null && this.currentEngine.isSpeaking()) {
      this.currentEngine.stop()
    }
    this.currentEngine?.destroy()

    const engine = resolveTtsEngine(id)
    if (engine !== null && this.initContext !== null) {
      try {
        engine.init(this.initContext)
        this.currentEngine = engine
        this.currentEngineId = id as TtsEngineId
        return
      } catch (err) {
        console.error('TTSService',
          `engine '${id}' init failed: ${JSON.stringify(err)}`)
      }
    }
    // fallback
    if (id !== TTS_FALLBACK_ENGINE_ID) {
      this.resolveAndBindEngine(TTS_FALLBACK_ENGINE_ID)
    } else {
      this.currentEngine = null
      this.currentEngineId = TTS_FALLBACK_ENGINE_ID
    }
  }

  // 文本预处理：移除代码块、清理Markdown符号等
  private preprocessTextForTTS(markdown: string): string {
    if (markdown === '') {
      return ''
    }

    let text = markdown

    // 移除代码块（```code```）
    text = text.replace(/```[\s\S]*?```/g, '')

    // 移除行内代码（`code`）
    text = text.replace(/`[^`]*`/g, '')

    // 清理Markdown符号
    text = text.replace(/\*\*\*([^*]+)\*\*\*/g, '$1')  // ***bold italic***
    text = text.replace(/\*\*([^*]+)\*\*/g, '$1')     // **bold**
    text = text.replace(/\*([^*]+)\*/g, '$1')         // *italic*
    text = text.replace(/___([^_]+)___/g, '$1')      // ___bold italic___
    text = text.replace(/__([^_]+)__/g, '$1')        // __bold__
    text = text.replace(/_([^_]+)_/g, '$1')          // _italic_
    text = text.replace(/~~([^~]+)~~/g, '')          // ~~strikethrough~~

    // 清理标题符号
    text = text.replace(/^#{1,6}\s+/gm, '')

    // 清理引用符号
    text = text.replace(/^>\s+/gm, '')

    // 清理链接语法 [text](url) -> text
    text = text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')

    // 清理图片语法 ![alt](url)
    text = text.replace(/!\[[^\]]*\]\([^)]+\)/g, '')

    // 清理无序列表符号
    text = text.replace(/^[-*+]\s+/gm, '')

    // 清理有序列表符号
    text = text.replace(/^\d+\.\s+/gm, '')

    // 清理水平线
    text = text.replace(/^[-*_]{3,}\s*$/gm, '')

    // 清理LaTeX公式（简单处理）
    text = text.replace(/\$\$[\s\S]*?\$\$/g, '公式')
    text = text.replace(/\$[^$]*\$/g, '公式')

    // 清理多余空行
    text = text.replace(/\n{3,}/g, '\n\n')

    // 限制长度
    if (text.length > 50000) {
      text = text.substring(0, 50000) + '...'
    }

    return text.trim()
  }
}

// 单例
let instance: TTSService | null = null

export function getTTSService(): TTSService {
  if (instance === null) {
    instance = new TTSService()
  }
  return instance
}
