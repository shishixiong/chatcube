import { common } from '@kit.AbilityKit'
import { ITtsEngine, TTSCallback } from './tts/ITtsEngine'
import { SystemTtsEngine } from './tts/SystemTtsEngine'
import { MiMoTtsEngine } from './tts/MiMoTtsEngine'
import { TTS_ENGINE, TtsEngineType } from '../config/TtsConfig'
import { getAppSettingsState } from '../state/AppSettingsState'
import { ModelProvider } from '../models/ChatModels'

export { TTSCallback } from './tts/ITtsEngine'

export class TTSService {
  private systemEngine: SystemTtsEngine = new SystemTtsEngine()
  private mimoEngine: MiMoTtsEngine = new MiMoTtsEngine()
  private currentEngine: ITtsEngine | null = null

  async init(context: common.Context): Promise<void> {
    // 初始化系统引擎
    await this.systemEngine.init(context)

    // 初始化 MiMo 引擎（尝试从现有 MiniMax provider 读取 API key）
    await this.mimoEngine.init(context)

    this.currentEngine = this.resolveEngine()
    console.info('TTSService', `引擎选择: ${TTS_ENGINE}`)
  }

  async speak(text: string, callback: TTSCallback): Promise<void> {
    if (this.currentEngine === null) {
      callback.onError('朗读服务未初始化')
      return
    }

    // 预处理文本（移除 Markdown 符号、代码块等）
    const processedText = this.preprocessTextForTTS(text)

    if (processedText === '') {
      callback.onError('没有可朗读的内容')
      return
    }

    await this.currentEngine.speak(processedText, callback)
  }

  stop(): void {
    if (this.currentEngine !== null) {
      this.currentEngine.stop()
    }
  }

  isSpeaking(): boolean {
    if (this.currentEngine !== null) {
      return this.currentEngine.isSpeaking()
    }
    return false
  }

  destroy(): void {
    this.systemEngine.destroy()
    this.mimoEngine.destroy()
    this.currentEngine = null
  }

  // 运行时切换引擎（后续设置页会用到）
  switchEngine(engineType: TtsEngineType): void {
    if (this.currentEngine !== null && this.currentEngine.isSpeaking()) {
      this.currentEngine.stop()
    }
    this.currentEngine = engineType === 'mimo' ? this.mimoEngine : this.systemEngine
    console.info('TTSService', `引擎切换为: ${engineType}`)
  }

  getCurrentEngineType(): TtsEngineType {
    return TTS_ENGINE
  }

  private resolveEngine(): ITtsEngine {
    return TTS_ENGINE === 'mimo' ? this.mimoEngine : this.systemEngine
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
