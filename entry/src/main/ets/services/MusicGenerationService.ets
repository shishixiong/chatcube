import { util } from '@kit.ArkTS'
import { ApiStyle, ModelInfo, ModelProvider, ProviderType } from '../models/ChatModels'
import {
  MusicGenerationAudioSetting,
  MusicGenerationItem,
  MusicGenerationOutputFormat,
  MusicGenerationRequest,
  MusicGenerationResult,
  resolveAudioExtension,
  resolveAudioMimeType
} from '../models/MusicGenerationModels'
import { HttpRequestController, HttpResponse } from './HttpService'
import { getMusicGenerationRcpClient, MusicGenerationRcpClient } from './MusicGenerationRcpClient'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { normalizeCustomHeaderName, parseCustomHeadersMap } from '../utils/CustomHeaderUtils'
import { ImageGenerationCapabilityResolver } from './ImageGenerationCapabilityResolver'

interface MinimaxMusicAudioSettingBody {
  sample_rate: number
  bitrate: number
  format: string
  channel: number
}

interface MinimaxMusicRequestBody {
  model: string
  prompt: string
  lyrics?: string
  refer_voice?: string
  refer_instrumental?: string
  audio_setting?: MinimaxMusicAudioSettingBody
  output_directory?: string
  stream: boolean
}

interface MinimaxMusicData {
  audio?: string
  audio_format?: string
  audio_length_ms?: number
}

interface MinimaxMusicBaseResp {
  status_code: number
  status_msg: string
}

interface MinimaxMusicResponse {
  data?: MinimaxMusicData
  trace_id?: string
  base_resp?: MinimaxMusicBaseResp
}

class MusicApiUrlResolver {
  static buildUrl(baseUrl: string, path: string): string {
    let url = baseUrl.trim()
    let apiPath = path
    if (url.endsWith('/')) {
      url = url.slice(0, -1)
    }
    if (!apiPath.startsWith('/')) {
      apiPath = '/' + apiPath
    }
    if (/\/v\d+\w*/.test(url) || url.includes('/beta')) {
      const baseUrlEnd = url.substring(url.lastIndexOf('/'))
      if (apiPath.includes(baseUrlEnd) && apiPath.startsWith(baseUrlEnd)) {
        const versionIndex = apiPath.indexOf('/', 1)
        apiPath = versionIndex !== -1 ? apiPath.substring(versionIndex) : ''
      }
    }
    return url + apiPath
  }
}

export class MusicGenerationService {
  private static instance: MusicGenerationService | null = null
  private rcpClient: MusicGenerationRcpClient = getMusicGenerationRcpClient()

  static getInstance(): MusicGenerationService {
    if (MusicGenerationService.instance === null) {
      MusicGenerationService.instance = new MusicGenerationService()
    }
    return MusicGenerationService.instance
  }

  async generateMusic(
    provider: ModelProvider,
    model: ModelInfo,
    request: MusicGenerationRequest,
    controller?: HttpRequestController
  ): Promise<MusicGenerationResult> {
    this.validateProvider(provider)
    const body = this.buildRequestBody(model, request)
    const response = await this.rcpClient.postJson(
      this.buildUrl(provider, '/music_generation'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return this.parseMinimaxResponse(response)
  }

  private validateProvider(provider: ModelProvider): void {
    if (!ImageGenerationCapabilityResolver.isMinimaxProvider(provider)) {
      throw new Error('当前模型所属服务商不支持音乐生成接口, 请使用 MiniMax 服务商')
    }
  }

  private buildUrl(provider: ModelProvider, path: string): string {
    const baseUrl = provider.baseUrl.trim()
    if (baseUrl === '') {
      throw new Error('当前模型所属服务商地址为空')
    }
    if (/\/v\d+\w*/.test(baseUrl)) {
      return MusicApiUrlResolver.buildUrl(baseUrl, path)
    }
    return MusicApiUrlResolver.buildUrl(baseUrl, `/v1${path}`)
  }

  private buildRequestBody(model: ModelInfo, request: MusicGenerationRequest): MinimaxMusicRequestBody {
    const body: MinimaxMusicRequestBody = {
      model: model.id,
      prompt: request.prompt,
      stream: false
    }
    if (request.lyrics.trim() !== '') {
      body.lyrics = request.lyrics
    }
    if (request.referVoice.trim() !== '') {
      body.refer_voice = request.referVoice.trim()
    }
    if (request.referInstrumental.trim() !== '') {
      body.refer_instrumental = request.referInstrumental.trim()
    }
    const setting = this.buildAudioSetting(request.audioSetting)
    if (setting !== null) {
      body.audio_setting = setting
    }
    if (request.outputDirectory.trim() !== '') {
      body.output_directory = request.outputDirectory.trim()
    }
    return body
  }

  private buildAudioSetting(setting: MusicGenerationAudioSetting): MinimaxMusicAudioSettingBody | null {
    if (setting === null) {
      return null
    }
    const sampleRate = Number(setting.sampleRate)
    const bitrate = Number(setting.bitrate)
    const channel = Number(setting.channel)
    if (!Number.isFinite(sampleRate) || !Number.isFinite(bitrate) || !Number.isFinite(channel)) {
      return null
    }
    return {
      sample_rate: sampleRate,
      bitrate: bitrate,
      format: setting.format,
      channel: channel
    }
  }

  private buildJsonHeaders(provider: ModelProvider): Record<string, string> {
    const headers = this.buildBaseHeaders(provider)
    headers['Content-Type'] = 'application/json'
    return headers
  }

  private buildBaseHeaders(provider: ModelProvider): Record<string, string> {
    const headers = JSON.parse('{}') as Record<string, string>
    const apiKey = this.getProviderApiKey(provider)
    if (apiKey !== '') {
      if (provider.type === ProviderType.AZURE) {
        headers['api-key'] = apiKey
      } else if (provider.apiStyle === ApiStyle.GOOGLE) {
        headers['x-goog-api-key'] = apiKey
      } else if (provider.apiStyle === ApiStyle.OPENAI) {
        headers['Authorization'] = `Bearer ${apiKey}`
      }
    }
    const customHeaders = parseCustomHeadersMap(provider.customHeadersJson)
    const keys = Object.keys(customHeaders)
    for (let i = 0; i < keys.length; i++) {
      const name = keys[i]
      const normalized = normalizeCustomHeaderName(name)
      if (normalized === 'authorization' || normalized === 'content-type' || normalized === 'x-goog-api-key' || normalized === 'api-key') {
        continue
      }
      headers[name] = customHeaders[name]
    }
    return headers
  }

  private getProviderApiKey(provider: ModelProvider): string {
    return getEffectiveApiKey(provider.id, provider.apiKey).trim()
  }

  private parseMinimaxResponse(response: HttpResponse): MusicGenerationResult {
    const result = new MusicGenerationResult()
    if (!response.success) {
      throw new Error(this.formatMusicHttpError(response))
    }
    let parsed: MinimaxMusicResponse
    try {
      parsed = JSON.parse(response.data) as MinimaxMusicResponse
    } catch (error) {
      console.error('MusicGenerationService', `Failed to parse music response: ${JSON.stringify(error)}`)
      throw new Error('音乐生成接口返回数据格式错误')
    }
    if (parsed.base_resp !== undefined && parsed.base_resp.status_code !== 0) {
      throw new Error(parsed.base_resp.status_msg !== undefined && parsed.base_resp.status_msg !== ''
        ? parsed.base_resp.status_msg
        : `MiniMax 音乐生成失败 (${parsed.base_resp.status_code})`)
    }
    if (parsed.data === undefined || parsed.data.audio === undefined || parsed.data.audio === '') {
      throw new Error('音乐生成接口未返回音频数据')
    }
    result.traceId = parsed.trace_id !== undefined ? parsed.trace_id : ''
    const format = this.resolveFormat(parsed.data.audio_format)
    const item = new MusicGenerationItem()
    item.hexData = parsed.data.audio
    item.audioFormat = format
    item.audioLengthMs = parsed.data.audio_length_ms !== undefined ? parsed.data.audio_length_ms : 0
    item.mimeType = resolveAudioMimeType(format)
    result.items.push(item)
    if (result.items.length === 0) {
      throw new Error('音乐生成接口未返回可用音频')
    }
    return result
  }

  private resolveFormat(raw: string | undefined): MusicGenerationOutputFormat {
    if (raw === undefined) {
      return MusicGenerationOutputFormat.MP3
    }
    const lower = raw.toLowerCase().trim()
    if (lower === 'wav') {
      return MusicGenerationOutputFormat.WAV
    }
    if (lower === 'flac') {
      return MusicGenerationOutputFormat.FLAC
    }
    if (lower === 'pcm') {
      return MusicGenerationOutputFormat.PCM
    }
    return MusicGenerationOutputFormat.MP3
  }

  private formatMusicHttpError(response: HttpResponse): string {
    const apiMessage = this.extractApiErrorMessage(response.data)
    if (apiMessage !== '') {
      return apiMessage
    }
    if (response.statusCode === 401 || response.statusCode === 403) {
      return '认证失败，请检查 API Key'
    }
    if (response.statusCode === 404) {
      return '当前模型或服务商不支持音乐生成接口'
    }
    if (response.statusCode === 429) {
      return '请求过于频繁，请稍后重试'
    }
    if (response.statusCode >= 500) {
      return '音乐生成服务暂不可用，请稍后重试'
    }
    if (response.errorMessage !== '') {
      return response.errorMessage
    }
    return `音乐生成失败 (${response.statusCode})`
  }

  private extractApiErrorMessage(data: string): string {
    const trimmed = data.trim()
    if (trimmed === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object>
      const baseRespObj = parsed['base_resp'] as Record<string, Object> | undefined
      if (baseRespObj !== undefined) {
        const statusCode = baseRespObj['status_code'] as number | undefined
        const statusMsg = baseRespObj['status_msg'] as string | undefined
        if (statusCode !== undefined && statusCode !== 0 && statusMsg !== undefined && statusMsg !== '') {
          return statusMsg
        }
      }
      const errorObj = parsed['error'] as Record<string, string> | undefined
      if (errorObj !== undefined) {
        const message = errorObj['message']
        if (message !== undefined && message !== '') {
          return message
        }
      }
    } catch (_error) {
      if (trimmed.length <= 240 && !trimmed.startsWith('<')) {
        return trimmed
      }
    }
    return ''
  }
}

export function getMusicGenerationService(): MusicGenerationService {
  return MusicGenerationService.getInstance()
}

// 公开工具: hex 字符串 → base64 字符串
// MiniMax 音乐生成返回 hex 编码音频, 复用 AttachmentStorageService 的 base64 写入路径
export function hexToBase64(hex: string): string {
  const cleaned = hex.trim()
  if (cleaned === '') {
    return ''
  }
  if (cleaned.length % 2 !== 0) {
    throw new Error('音频 hex 长度不是 2 的倍数, 数据可能已损坏')
  }
  const bytes = new Uint8Array(cleaned.length / 2)
  for (let i = 0; i < bytes.length; i++) {
    const byteHex = cleaned.substring(i * 2, i * 2 + 2)
    const value = parseInt(byteHex, 16)
    if (Number.isNaN(value)) {
      throw new Error('音频 hex 包含非法字符, 数据可能已损坏')
    }
    bytes[i] = value
  }
  const helper = new util.Base64Helper()
  return helper.encodeToStringSync(bytes)
}

export { resolveAudioExtension }
