import { getHttpService, HttpResponse, HttpService } from './HttpService'
import { util } from '@kit.ArkTS'
import { http } from '@kit.NetworkKit'
import {
  ProviderType,
  ApiStyle,
  MessageAttachment,
  AttachmentType,
  ReasoningLevel,
  ToolDefinition,
  ToolCall,
  OpenAITransport
} from '../models/ChatModels'
import { AIGeneratedImageFileResult, AIGeneratedImageFileSink } from '../models/AIGeneratedImageFileModels'
import { SearchReference } from '../models/SearchReference'
import {
  AnthropicAuthStrategy,
  CompatibilityProviderInfo,
  ModelDiscoveryStrategy,
  OpenAIStreamContentMode,
  ProviderCompatibilityProfile,
  ReasoningRequestStrategy,
  normalizeReasoningLevelForControl,
  resolveProviderCompatibilityProfile,
  resolveReasoningRequestStrategyWithOverride
} from './registry/CompatibilityResolver'
import { AttachmentContentService } from './AttachmentContentService'
import { normalizeCustomHeaderName, parseCustomHeadersMap } from '../utils/CustomHeaderUtils'

const STREAM_DROP_PREFIX_MAX_LEN = 192
const STREAM_IMAGE_RESULT_SCAN_MAX_LEN = 64 * 1024
const STREAM_IMAGE_BASE64_CALLBACK_CHARS = 32 * 1024

export interface AIGeneratedImageFileCallbacks {
  createSink: (mimeType: string) => AIGeneratedImageFileSink | null
  onFile: (result: AIGeneratedImageFileResult) => void
}

// URL 解析工具类
class ApiUrlResolver {
  /**
   * 构建 API URL，处理 baseUrl 和 path 的拼接
   * @param baseUrl 基础 URL（如 https://api.example.com 或 https://api.example.com/v1）
   * @param path API 路径（如 /chat/completions 或 v1/chat/completions）
   * @returns 完整的 API URL
   */
  static buildUrl(baseUrl: string, path: string): string {
    let url = baseUrl
    let apiPath = path

    // 移除 baseUrl 末尾的斜杠
    if (url.endsWith('/')) {
      url = url.slice(0, -1)
    }

    // 确保 path 以斜杠开头
    if (!apiPath.startsWith('/')) {
      apiPath = '/' + apiPath
    }

    // 检查 baseUrl 是否已经包含版本路径（如 /v1, /v2, /v3, /beta 等）
    if (/\/v\d+\w*/.test(url) || url.includes('/beta')) {
      // baseUrl 已包含版本路径，直接拼接
      // 但要避免重复的 /v1
      const baseUrlEnd = url.substring(url.lastIndexOf('/'))
      if (apiPath.includes(baseUrlEnd) && apiPath.startsWith(baseUrlEnd)) {
        // path 包含相同的版本前缀，去掉 path 中的版本部分
        const versionIndex = apiPath.indexOf('/', 1) // 跳过开头的 /
        if (versionIndex !== -1) {
          apiPath = apiPath.substring(versionIndex)
        } else {
          apiPath = ''
        }
      }
    }

    return url + apiPath
  }
}

class StreamLineAccumulator {
  private segments: Uint8Array[] = []
  private length: number = 0
  private droppingLine: boolean = false
  private dropOpenAIResponsesLargeLines: boolean = false
  private imageFileCallbacks?: AIGeneratedImageFileCallbacks
  private imageMimeType: string = 'image/png'
  private onHostedImageCompleted?: (itemId: string, outputIndex: number) => void
  private streamingImageLine: boolean = false
  private imageSink: AIGeneratedImageFileSink | null = null
  private imageItemId: string = ''
  private imageOutputIndex: number = -1
  private imageBase64Chunk: string = ''
  private imageEscapePending: boolean = false
  private protocolCompleted: boolean = false

  constructor(
    dropOpenAIResponsesLargeLines: boolean,
    imageFileCallbacks?: AIGeneratedImageFileCallbacks,
    imageMimeType: string = 'image/png',
    onHostedImageCompleted?: (itemId: string, outputIndex: number) => void
  ) {
    this.dropOpenAIResponsesLargeLines = dropOpenAIResponsesLargeLines
    this.imageFileCallbacks = imageFileCallbacks
    this.imageMimeType = imageMimeType
    this.onHostedImageCompleted = onHostedImageCompleted
  }

  append(chunk: Uint8Array): Uint8Array[] {
    const lines: Uint8Array[] = []
    let start = 0
    while (start < chunk.length) {
      const newlineIndex = this.indexOfNewline(chunk, start)
      const hasLineEnd = newlineIndex >= 0
      const end = newlineIndex >= 0 ? newlineIndex : chunk.length

      if (this.droppingLine) {
        if (newlineIndex >= 0) {
          this.droppingLine = false
          start = newlineIndex + 1
          continue
        }
        return lines
      }

      const segment = chunk.subarray(start, end)
      if (this.streamingImageLine) {
        const completed = this.consumeImageResultBytes(segment)
        if (completed && !hasLineEnd) {
          this.droppingLine = true
          return lines
        }
        if (!completed && !this.streamingImageLine && !hasLineEnd) {
          this.droppingLine = true
          return lines
        }
        if (hasLineEnd) {
          if (this.streamingImageLine) {
            this.abortImageLine('image result line ended before closing quote')
          }
          start = newlineIndex + 1
          continue
        }
        return lines
      }

      if (this.segments.length === 0 && this.length === 0 && this.shouldDropLinePrefix(segment)) {
        if (newlineIndex >= 0) {
          start = newlineIndex + 1
          continue
        }
        this.droppingLine = true
        return lines
      }

      if (segment.length > 0) {
        this.segments.push(segment)
        this.length += segment.length
      }

      if (this.tryConsumePendingImageResultLine(hasLineEnd)) {
        if (!hasLineEnd) {
          return lines
        }
        start = newlineIndex + 1
        continue
      }

      if (this.shouldDropPendingLine()) {
        this.clearPending()
        if (!hasLineEnd) {
          this.droppingLine = true
          return lines
        }
        start = newlineIndex + 1
        continue
      }

      if (newlineIndex >= 0) {
        if (this.segments.length === 0) {
          this.markProtocolCompletedIfNeeded(segment)
          lines.push(segment)
        } else {
          const line = this.mergeSegments()
          this.clearPending()
          this.markProtocolCompletedIfNeeded(line)
          lines.push(line)
        }
        start = newlineIndex + 1
        continue
      }

      return lines
    }
    return lines
  }

  flush(): Uint8Array | null {
    if (this.streamingImageLine) {
      this.abortImageLine('stream ended before image result completed')
      return null
    }
    if (this.droppingLine) {
      this.droppingLine = false
      this.clearPending()
      return null
    }
    if (this.length === 0) {
      return null
    }
    if (this.tryConsumePendingImageResultLine(true)) {
      return null
    }
    const line = this.mergeSegments()
    this.clearPending()
    this.markProtocolCompletedIfNeeded(line)
    return line
  }

  hasProtocolCompleted(): boolean {
    return this.protocolCompleted
  }

  abortActiveImageFile(): void {
    if (this.streamingImageLine || this.imageSink !== null) {
      this.abortImageLine('stream aborted')
    }
  }

  private tryConsumePendingImageResultLine(lineEnded: boolean): boolean {
    if (!this.dropOpenAIResponsesLargeLines || this.imageFileCallbacks === undefined || this.length < 32) {
      return false
    }
    const scanBytes = this.length > STREAM_IMAGE_RESULT_SCAN_MAX_LEN ?
      this.getPendingPrefixBytes(STREAM_IMAGE_RESULT_SCAN_MAX_LEN) :
      this.mergeSegments()
    const resultStart = this.findJsonStringValueStartBytes(scanBytes, 'result', 0)
    if (resultStart < 0) {
      if (!lineEnded && this.length >= STREAM_IMAGE_RESULT_SCAN_MAX_LEN &&
        this.isLikelyResponsesImageDonePrefix(scanBytes)) {
        console.warn('AIApiService', 'Dropping oversized image_generation line before result field was found')
        this.clearPending()
        this.droppingLine = true
        return true
      }
      return false
    }
    if (this.indexOfAsciiPattern(scanBytes, 'response.output_item.done', 0, resultStart) < 0 ||
      this.indexOfAsciiPattern(scanBytes, 'image_generation_call', 0, resultStart) < 0) {
      return false
    }

    const sink = this.imageFileCallbacks.createSink(this.imageMimeType)
    if (sink === null) {
      return false
    }
    this.imageSink = sink
    this.streamingImageLine = true
    this.imageBase64Chunk = ''
    this.imageEscapePending = false
    this.imageItemId = this.readStringBefore(scanBytes, 'id', resultStart)
    this.imageOutputIndex = this.findJsonNumberValueBeforeBytes(scanBytes, 'output_index', resultStart)

    const completed = this.consumePendingBytesFrom(resultStart)
    this.clearPending()
    if (completed && !lineEnded) {
      this.droppingLine = true
    }
    if (!completed && !this.streamingImageLine && !lineEnded) {
      this.droppingLine = true
    }
    if (lineEnded && this.streamingImageLine) {
      this.abortImageLine('image result line ended before closing quote')
    }
    return true
  }

  private consumePendingBytesFrom(startOffset: number): boolean {
    let offset = 0
    for (let i = 0; i < this.segments.length; i++) {
      const segment = this.segments[i]
      const nextOffset = offset + segment.length
      if (nextOffset <= startOffset) {
        offset = nextOffset
        continue
      }
      const localStart = Math.max(0, startOffset - offset)
      const completed = this.consumeImageResultBytes(segment.subarray(localStart))
      if (completed) {
        return true
      }
      offset = nextOffset
    }
    return false
  }

  private consumeImageResultBytes(bytes: Uint8Array): boolean {
    for (let i = 0; i < bytes.length; i++) {
      const byte = bytes[i]
      if (this.imageEscapePending) {
        this.imageEscapePending = false
        if (byte === 47 || byte === 43 || byte === 61 || this.isBase64Byte(byte)) {
          if (!this.appendImageBase64Byte(byte)) {
            return false
          }
        } else if (byte === 110 || byte === 114 || byte === 116) {
          // Escaped whitespace is ignored; OpenAI normally does not emit it, but this keeps proxies tolerant.
        } else {
          this.abortImageLine('unsupported escape in image result')
          return false
        }
        continue
      }

      if (byte === 34) {
        if (!this.flushImageBase64Chunk()) {
          return false
        }
        return this.completeImageFile()
      }
      if (byte === 92) {
        this.imageEscapePending = true
        continue
      }
      if (this.isJsonWhitespaceByte(byte)) {
        continue
      }
      if (!this.isBase64Byte(byte) && byte !== 43 && byte !== 47 && byte !== 61) {
        this.abortImageLine('invalid byte in image result')
        return false
      }
      if (!this.appendImageBase64Byte(byte)) {
        return false
      }
    }
    return false
  }

  private appendImageBase64Byte(byte: number): boolean {
    this.imageBase64Chunk += String.fromCharCode(byte)
    if (this.imageBase64Chunk.length >= STREAM_IMAGE_BASE64_CALLBACK_CHARS) {
      return this.flushImageBase64Chunk()
    }
    return true
  }

  private flushImageBase64Chunk(): boolean {
    if (this.imageBase64Chunk === '') {
      return true
    }
    const sink = this.imageSink
    if (sink === null) {
      this.abortImageLine('image sink missing')
      return false
    }
    try {
      sink.appendBase64Chunk(this.imageBase64Chunk)
      this.imageBase64Chunk = ''
      return true
    } catch (error) {
      console.error('AIApiService', `Failed to write image base64 chunk: ${JSON.stringify(error)}`)
      this.abortImageLine('image sink write failed')
      return false
    }
  }

  private completeImageFile(): boolean {
    const sink = this.imageSink
    const callbacks = this.imageFileCallbacks
    if (sink === null || callbacks === undefined) {
      this.abortImageLine('image sink missing at completion')
      return false
    }
    try {
      const result = sink.complete(this.imageItemId, this.imageOutputIndex)
      if (this.onHostedImageCompleted !== undefined) {
        this.onHostedImageCompleted(this.imageItemId, this.imageOutputIndex)
      }
      callbacks.onFile(result)
      this.resetImageLineState()
      return true
    } catch (error) {
      console.error('AIApiService', `Failed to complete generated image file: ${JSON.stringify(error)}`)
      this.abortImageLine('image sink completion failed')
      return false
    }
  }

  private abortImageLine(reason: string): void {
    console.warn('AIApiService', `Abort streaming image result: ${reason}`)
    if (this.imageSink !== null) {
      try {
        this.imageSink.abort()
      } catch (_e) {
        // ignore cleanup failures
      }
    }
    this.resetImageLineState()
  }

  private resetImageLineState(): void {
    this.streamingImageLine = false
    this.imageSink = null
    this.imageItemId = ''
    this.imageOutputIndex = -1
    this.imageBase64Chunk = ''
    this.imageEscapePending = false
  }

  private shouldDropLinePrefix(segment: Uint8Array): boolean {
    if (!this.dropOpenAIResponsesLargeLines || segment.length === 0) {
      return false
    }
    const prefixLength = Math.min(segment.length, STREAM_DROP_PREFIX_MAX_LEN)
    const prefixBytes = segment.subarray(0, prefixLength)
    if (this.isOpenAIResponsesCompletedEventPrefix(prefixBytes)) {
      this.protocolCompleted = true
      return true
    }
    return this.isOpenAIResponsesLargeEventPrefix(prefixBytes)
  }

  private shouldDropPendingLine(): boolean {
    if (!this.dropOpenAIResponsesLargeLines || this.length < 32) {
      return false
    }
    const prefixBytes = this.getPendingPrefixBytes(STREAM_DROP_PREFIX_MAX_LEN)
    if (prefixBytes.length === 0) {
      return false
    }
    if (this.isOpenAIResponsesCompletedEventPrefix(prefixBytes)) {
      this.protocolCompleted = true
      return true
    }
    return this.isOpenAIResponsesLargeEventPrefix(prefixBytes)
  }

  private isOpenAIResponsesLargeEventPrefix(prefixBytes: Uint8Array): boolean {
    const prefix = this.bytesToAsciiString(prefixBytes).trimStart()
    if (!prefix.startsWith('data:')) {
      return false
    }
    return prefix.includes('"type":"response.completed"') ||
      prefix.includes('"type": "response.completed"') ||
      prefix.includes('"type":"response.image_generation_call.partial_image"') ||
      prefix.includes('"type": "response.image_generation_call.partial_image"')
  }

  private isOpenAIResponsesCompletedEventPrefix(prefixBytes: Uint8Array): boolean {
    const prefix = this.bytesToAsciiString(prefixBytes).trimStart()
    if (!prefix.startsWith('data:')) {
      return false
    }
    return prefix.includes('"type":"response.completed"') ||
      prefix.includes('"type": "response.completed"')
  }

  private markProtocolCompletedIfNeeded(line: Uint8Array): void {
    const prefixLength = Math.min(line.length, STREAM_DROP_PREFIX_MAX_LEN)
    const prefix = this.bytesToAsciiString(line.subarray(0, prefixLength)).trim()
    if (prefix === 'data: [DONE]' || prefix === 'data:[DONE]' || prefix === '[DONE]') {
      this.protocolCompleted = true
      return
    }
    if (this.isOpenAIResponsesCompletedEventPrefix(line.subarray(0, prefixLength))) {
      this.protocolCompleted = true
    }
  }

  private isLikelyResponsesImageDonePrefix(prefixBytes: Uint8Array): boolean {
    const prefix = this.bytesToAsciiString(prefixBytes).trimStart()
    return prefix.startsWith('data:') &&
      prefix.includes('response.output_item.done') &&
      prefix.includes('image_generation_call')
  }

  private bytesToAsciiString(bytes: Uint8Array): string {
    let result = ''
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i])
    }
    return result
  }

  private getPendingPrefixBytes(maxLength: number): Uint8Array {
    const total = Math.min(this.length, maxLength)
    const prefix = new Uint8Array(total)
    let offset = 0
    for (let i = 0; i < this.segments.length && offset < total; i++) {
      const remaining = total - offset
      const segment = this.segments[i]
      const take = Math.min(segment.length, remaining)
      prefix.set(segment.subarray(0, take), offset)
      offset += take
    }
    return prefix
  }

  private mergeSegments(): Uint8Array {
    if (this.segments.length === 1 && this.segments[0].length === this.length) {
      return this.segments[0]
    }
    const merged = new Uint8Array(this.length)
    let offset = 0
    for (let i = 0; i < this.segments.length; i++) {
      merged.set(this.segments[i], offset)
      offset += this.segments[i].length
    }
    return merged
  }

  private indexOfNewline(chunk: Uint8Array, start: number): number {
    for (let i = start; i < chunk.length; i++) {
      if (chunk[i] === 10) {
        return i
      }
    }
    return -1
  }

  private clearPending(): void {
    this.segments = []
    this.length = 0
  }

  private readStringBefore(bytes: Uint8Array, key: string, beforeIndex: number): string {
    const valueStart = this.findJsonStringValueStartBeforeBytes(bytes, key, beforeIndex)
    if (valueStart < 0) {
      return ''
    }
    const valueEnd = this.indexOfByte(bytes, 34, valueStart)
    if (valueEnd <= valueStart) {
      return ''
    }
    return this.bytesToAsciiString(bytes.subarray(valueStart, valueEnd))
  }

  private indexOfByte(bytes: Uint8Array, target: number, fromIndex: number): number {
    for (let i = Math.max(0, fromIndex); i < bytes.length; i++) {
      if (bytes[i] === target) {
        return i
      }
    }
    return -1
  }

  private indexOfAsciiPattern(bytes: Uint8Array, pattern: string, fromIndex: number, beforeIndex: number): number {
    if (pattern.length === 0) {
      return -1
    }
    const start = Math.max(0, fromIndex)
    const limit = Math.min(beforeIndex, bytes.length) - pattern.length
    const first = pattern.charCodeAt(0)
    for (let i = start; i <= limit; i++) {
      if (bytes[i] !== first) {
        continue
      }
      let matched = true
      for (let j = 1; j < pattern.length; j++) {
        if (bytes[i + j] !== pattern.charCodeAt(j)) {
          matched = false
          break
        }
      }
      if (matched) {
        return i
      }
    }
    return -1
  }

  private findJsonStringValueStartBytes(bytes: Uint8Array, key: string, fromIndex: number): number {
    let searchIndex = fromIndex
    const keyPattern = `"${key}"`
    while (searchIndex < bytes.length) {
      const keyIndex = this.indexOfAsciiPattern(bytes, keyPattern, searchIndex, bytes.length)
      if (keyIndex < 0) {
        return -1
      }
      const valueStart = this.findJsonValueStartAfterKeyBytes(bytes, keyIndex + keyPattern.length)
      if (valueStart >= 0 && bytes[valueStart] === 34) {
        return valueStart + 1
      }
      searchIndex = keyIndex + keyPattern.length
    }
    return -1
  }

  private findJsonStringValueStartBeforeBytes(bytes: Uint8Array, key: string, beforeIndex: number): number {
    let searchIndex = 0
    let result = -1
    while (searchIndex < beforeIndex) {
      const found = this.findJsonStringValueStartBytes(bytes, key, searchIndex)
      if (found < 0 || found >= beforeIndex) {
        return result
      }
      result = found
      searchIndex = found + 1
    }
    return result
  }

  private findJsonNumberValueBeforeBytes(bytes: Uint8Array, key: string, beforeIndex: number): number {
    let searchIndex = 0
    let result = -1
    while (searchIndex < beforeIndex) {
      const keyPattern = `"${key}"`
      const keyIndex = this.indexOfAsciiPattern(bytes, keyPattern, searchIndex, beforeIndex)
      if (keyIndex < 0) {
        return result
      }
      const valueStart = this.findJsonValueStartAfterKeyBytes(bytes, keyIndex + keyPattern.length)
      if (valueStart >= 0 && valueStart < beforeIndex) {
        const parsed = this.parseJsonNumberAtBytes(bytes, valueStart, beforeIndex)
        if (parsed >= 0) {
          result = parsed
        }
      }
      searchIndex = keyIndex + keyPattern.length
    }
    return result
  }

  private findJsonValueStartAfterKeyBytes(bytes: Uint8Array, fromIndex: number): number {
    let index = fromIndex
    while (index < bytes.length && this.isJsonWhitespaceByte(bytes[index])) {
      index++
    }
    if (index >= bytes.length || bytes[index] !== 58) {
      return -1
    }
    index++
    while (index < bytes.length && this.isJsonWhitespaceByte(bytes[index])) {
      index++
    }
    return index < bytes.length ? index : -1
  }

  private parseJsonNumberAtBytes(bytes: Uint8Array, fromIndex: number, beforeIndex: number): number {
    let index = fromIndex
    let value = 0
    let hasDigit = false
    while (index < beforeIndex) {
      const byte = bytes[index]
      if (byte < 48 || byte > 57) {
        break
      }
      value = value * 10 + byte - 48
      hasDigit = true
      index++
    }
    return hasDigit ? value : -1
  }

  private isJsonWhitespaceByte(byte: number): boolean {
    return byte === 32 || byte === 9 || byte === 10 || byte === 13
  }

  private isBase64Byte(byte: number): boolean {
    return (byte >= 48 && byte <= 57) ||
      (byte >= 65 && byte <= 90) ||
      (byte >= 97 && byte <= 122)
  }
}

// 请求消息格式
export class RequestMessage {
  role: string = ''
  content: string = ''
  reasoningContent: string = ''
  // OpenAI Responses API reasoning item 原文(JSON 字符串,含 encrypted_content)
  // 仅 role === 'assistant' 时可能有值,用于跨轮保持推理状态
  reasoningSignatureBlob: string = ''
  // 图片附件（用于多模态请求）
  attachments: MessageAttachment[] = []
  // Function Calling 相关字段
  toolCallId: string = ''      // 用于 tool 角色消息
  toolCalls: ToolCall[] = []   // 用于 assistant 消息中的工具调用

  constructor(role: string, content: string, attachments: MessageAttachment[] = []) {
    this.role = role
    this.content = content
    this.attachments = attachments
  }

  // 检查是否包含图片
  hasImages(): boolean {
    return this.attachments.some(a => a.type === AttachmentType.IMAGE)
  }

  // 检查是否包含任何附件（图片或文件）
  hasAttachments(): boolean {
    return this.attachments.length > 0 && this.attachments.some(a => a.base64Data !== '' || a.parsedText !== '')
  }

  // 检查是否包含文件（非图片）
  hasFiles(): boolean {
    return this.attachments.some(a => a.type === AttachmentType.FILE && (a.base64Data !== '' || a.parsedText !== ''))
  }

  // 检查是否是工具结果消息
  isToolResultMessage(): boolean {
    return this.role === 'tool' && this.toolCallId !== ''
  }

  // 检查是否包含工具调用
  hasToolCalls(): boolean {
    return this.toolCalls.length > 0
  }

  // 创建工具结果消息
  static createToolResultMessage(toolCallId: string, content: string): RequestMessage {
    const msg = new RequestMessage('tool', content)
    msg.toolCallId = toolCallId
    return msg
  }

  // 创建带工具调用的 assistant 消息
  static createAssistantWithToolCalls(content: string, toolCalls: ToolCall[]): RequestMessage {
    const msg = new RequestMessage('assistant', content)
    msg.toolCalls = toolCalls
    return msg
  }
}

// 多模态消息内容部分（OpenAI Vision 格式）
interface MultimodalContentPart {
  type: string
  text?: string
  image_url?: ImageUrl
}

interface ImageUrl {
  url: string
  detail?: string
}

// 多模态消息内容接口
interface MultimodalMessageContent {
  role: string
  content: string | MultimodalContentPart[]
  // DeepSeek-V4 thinking 模式下,assistant 历史消息必须原样回传 reasoning_content（即使为空串）。
  reasoning_content?: string
}

// 消息内容接口
interface MessageContent {
  role: string
  content: string
  reasoning_content?: string
  reasoning_details?: MiniMaxReasoningDetail[]
}

// 测试请求接口
interface TestRequestBody {
  model: string
  messages: RequestMessage[]
  max_tokens?: number
  max_completion_tokens?: number
}

// OpenAI 工具定义接口（用于 API 请求）
interface OpenAIToolFunction {
  name: string
  description: string
  parameters: object
}

interface OpenAITool {
  type: string
  function: OpenAIToolFunction
}

// OpenAI Responses 工具定义
// type === 'function' 时使用 name/description/parameters
// type === 'web_search' 时可选 search_context_size / user_location
// type === 'image_generation' 时可选 model/size/quality/output_format/output_compression/background/partial_images
export interface OpenAIResponsesUserLocation {
  type?: string
  city?: string
  region?: string
  country?: string
  timezone?: string
}

interface OpenAIResponsesTool {
  type: string
  // function 专用字段
  name?: string
  description?: string
  parameters?: object
  // web_search 专用
  search_context_size?: string
  user_location?: OpenAIResponsesUserLocation
  // image_generation 专用
  model?: string
  size?: string
  quality?: string
  output_format?: string
  output_compression?: number
  background?: string
  partial_images?: number
}

// 用于聊天/任务层向 AIApiService 透传 OpenAI Responses 内置 (hosted) 工具配置
// kind === 'web_search' / 'image_generation'
export enum BuiltInResponsesToolKind {
  WEB_SEARCH = 'web_search',
  IMAGE_GENERATION = 'image_generation'
}

export class BuiltInResponsesToolSpec {
  kind: BuiltInResponsesToolKind
  // web_search 选项
  searchContextSize?: string
  searchUserLocation?: OpenAIResponsesUserLocation
  // image_generation 选项
  imageModel?: string
  imageSize?: string
  imageQuality?: string
  imageOutputFormat?: string
  imageOutputCompression?: number
  imageBackground?: string
  // partial_images 取值 0-3; 不显式设置时走 OpenAI 默认值。
  imagePartialImages?: number

  constructor(kind: BuiltInResponsesToolKind) {
    this.kind = kind
  }
}

// OpenAI 工具调用接口（用于 API 响应）
interface OpenAIToolCallFunction {
  name: string
  arguments: string
}

interface OpenAIToolCall {
  id: string
  type: string
  function: OpenAIToolCallFunction
}

// 工具结果消息接口
interface ToolResultMessageContent {
  role: string
  tool_call_id: string
  content: string
}

// 带工具调用的 assistant 消息接口
interface AssistantMessageWithToolCalls {
  role: string
  content: string | null
  tool_calls: OpenAIToolCall[]
  reasoning_content?: string
}

// 通用思考配置接口（小米 MiMo / 智谱 GLM 等模型）
interface ThinkingConfig {
  type: string           // "enabled" | "disabled"
  clear_thinking?: boolean  // GLM 特有：是否清除历史推理内容（默认 false 保留）
}

interface OpenRouterReasoningConfig {
  effort?: string
  max_tokens?: number
  exclude?: boolean
  enabled?: boolean
}

// OpenAI 请求体接口
interface OpenAIRequestBody {
  model: string
  messages: (MessageContent | MultimodalMessageContent | ToolResultMessageContent | AssistantMessageWithToolCalls)[]
  temperature?: number
  max_tokens?: number
  max_completion_tokens?: number  // OpenAI gpt-5 / o-系列推理模型必须使用此字段替代 max_tokens
  stream?: boolean
  reasoning_effort?: string  // OpenAI/OpenAI-compatible 推理级别: none, low, medium, high, xhigh/max
  reasoning?: OpenRouterReasoningConfig  // OpenRouter 统一推理控制
  reasoning_split?: boolean  // MiniMax 推理内容分离（reasoning_details 字段）
  thinking?: ThinkingConfig  // Kimi / DeepSeek / 小米 MiMo / 智谱 GLM 思考模式配置
  enable_thinking?: boolean  // DashScope / SiliconFlow chat/completions 思考开关
  thinking_budget?: number   // DashScope / SiliconFlow chat/completions 推理 token 上限
  tools?: OpenAITool[]       // Function Calling 工具定义
  tool_choice?: string       // 工具选择策略: "auto" | "none" | "required"
  top_p?: number             // Top P 采样参数
  presence_penalty?: number  // 存在惩罚
  frequency_penalty?: number // 频率惩罚
}

interface OpenAIResponsesContentPart {
  type: string
  text?: string
  image_url?: string
  detail?: string
}

// web_search_call item 上的 action 字段, OpenAI 会在 output_item.added/done 携带:
//   { type: 'search', query: '...' } / { type: 'search', queries: [...] } / { type: 'open_page', url: '...' }
// 用来给用户展示"这一轮在搜什么 / 在读什么"。
interface OpenAIResponsesItemAction {
  type?: string
  query?: string
  queries?: string[]
  url?: string
}

interface OpenAIResponsesInputItem {
  type?: string
  role?: string
  content?: OpenAIResponsesContentPart[]
  status?: string
  call_id?: string
  name?: string
  arguments?: string
  output?: string
  result?: string
  id?: string
  // reasoning item 专用字段(仅当 type === 'reasoning' 时出现)
  summary?: OpenAIResponsesReasoningSummaryItem[]
  encrypted_content?: string
  // web_search_call 专用: 当次搜索动作(关键词或读取的页面)
  action?: OpenAIResponsesItemAction
}

interface OpenAIResponsesReasoningConfig {
  effort?: string
  summary?: string
}

export interface OpenAIResponsesToolChoiceObject {
  type: string
}

export type OpenAIResponsesToolChoice = string | OpenAIResponsesToolChoiceObject

interface OpenAIResponsesRequestBody {
  model: string
  input: OpenAIResponsesInputItem[] | string
  instructions?: string
  temperature?: number
  max_output_tokens?: number
  reasoning?: OpenAIResponsesReasoningConfig
  enable_thinking?: boolean
  thinking_budget?: number
  // 请求 Responses 在流中返回额外字段,例如 'reasoning.encrypted_content'
  include?: string[]
  tools?: OpenAIResponsesTool[]
  tool_choice?: OpenAIResponsesToolChoice
  stream?: boolean
}

// Anthropic 思考配置接口
interface AnthropicThinking {
  type: string
  budget_tokens?: number
  display?: string
}

interface AnthropicOutputConfig {
  effort?: string
}

// Anthropic 请求体接口
interface AnthropicRequestBody {
  model: string
  messages: (MessageContent | AnthropicMultimodalMessage)[]
  max_tokens: number
  temperature?: number
  system?: string
  stream?: boolean
  thinking?: AnthropicThinking  // Claude 扩展思考配置
  output_config?: AnthropicOutputConfig
}

// Anthropic 多模态消息内容部分
interface AnthropicContentPart {
  type: string
  text?: string
  source?: AnthropicDocumentSource
}

interface AnthropicDocumentSource {
  type: string
  media_type: string
  data: string
}

// Anthropic 多模态消息
interface AnthropicMultimodalMessage {
  role: string
  content: AnthropicContentPart[]
}

// 选择项
export interface ChoiceMessage {
  role: string
  content: string
  // 推理内容（DeepSeek R1 等模型）
  reasoning_content?: string
  // 推理内容（OpenAI-compat 一些供应商使用 reasoning 字段）
  reasoning?: string
  // 图片数据
  image_url?: string
  image_base64?: string
  image_mime_type?: string
  // Function Calling 工具调用
  tool_calls?: OpenAIToolCall[]
}

export interface Choice {
  index: number
  message: ChoiceMessage
  finish_reason: string
}

// 使用量信息
export interface UsageInfo {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

// 聊天完成响应
export interface ChatCompletionResponse {
  id: string
  object: string
  created: number
  model: string
  choices: Choice[]
  usage: UsageInfo
}

// API 错误响应
export interface ApiErrorResponse {
  error: ApiError
}

export interface ApiError {
  message: string
  type: string
  code: string
}

// 模型列表响应
export interface ModelsListResponse {
  object: string
  data: ModelData[]
}

export interface ModelData {
  id: string
  object: string
  created: number
  owned_by: string
}

// Google ListModels 响应:GET /v1beta/models 返回 { models: [{ name, supportedGenerationMethods, ... }] }
// 字段名与 OpenAI 完全不同,不能复用 ModelsListResponse
interface GoogleModelDescriptor {
  name: string
  supportedGenerationMethods?: string[]
}

interface GoogleModelsListResponse {
  models?: GoogleModelDescriptor[]
}

// AI API 服务配置
export interface AIApiConfig {
  providerId: string
  providerType: ProviderType
  apiStyle: ApiStyle
  apiKey: string
  baseUrl: string
  apiPath?: string  // 可选的自定义 API 路径（如 /v1/chat/completions）
  openaiTransport?: string
  customHeadersJson?: string  // 可选的服务商级自定义请求头
  modelReasoningStrategyOverride?: string
  modelSupportsReasoning?: boolean
  // 模型参数（可选）
  topP?: number
  presencePenalty?: number
  frequencyPenalty?: number
}

// AI API 响应结果
export interface AIApiResult {
  success: boolean
  content: string
  errorMessage: string
  usage: UsageInfo | null
  // 新增：推理内容（用于支持 o1, DeepSeek R1 等推理模型）
  reasoningContent: string
  // 图片数据（非流式响应）
  imageData?: string
  imageMimeType?: string
  // Function Calling 相关字段
  toolCalls?: ToolCall[]     // AI 请求的工具调用
  finishReason?: string      // 完成原因: "stop" | "tool_calls"
  // OpenAI Responses API reasoning item 原文序列化(JSON 字符串)
  // 用于下一轮请求原样注入,保持跨轮推理状态
  reasoningSignatureBlob?: string
}

// 模型列表结果
export interface ModelsListResult {
  success: boolean
  models: string[]
  errorMessage: string
}

// Anthropic 图片来源接口
interface AnthropicImageSource {
  type: string
  media_type: string
  data: string
}

// Anthropic 响应内容
interface AnthropicContent {
  type: string
  text?: string
  // 图片数据
  source?: AnthropicImageSource
}

// Anthropic 响应格式
interface AnthropicResponse {
  id: string
  content: AnthropicContent[]
  usage: UsageInfo
}

// Google Gemini 请求体接口
interface GoogleContentPart {
  text?: string
  inline_data?: GoogleInlineData
  thought?: boolean
  thoughtSignature?: string
}

interface GoogleInlineData {
  mime_type: string
  data: string
}

interface GoogleContent {
  role: string
  parts: GoogleContentPart[]
}

interface GoogleSystemInstruction {
  parts: GoogleContentPart[]
}

interface GoogleThinkingConfig {
  includeThoughts?: boolean
  thinkingBudget?: number
  thinkingLevel?: string
}

interface GoogleGenerationConfig {
  temperature?: number
  // maxOutputTokens 留 optional, 助手未配置 max output (0 / undefined) 时直接不下发, 让 Google
  // 模型走自身默认上限。
  maxOutputTokens?: number
  thinkingConfig?: GoogleThinkingConfig
}

interface GoogleRequestBody {
  contents: GoogleContent[]
  generationConfig: GoogleGenerationConfig
  systemInstruction?: GoogleSystemInstruction
}

// Google Gemini 响应接口
interface GoogleCandidate {
  content: GoogleContent
  finishReason?: string
}

interface GoogleResponse {
  candidates: GoogleCandidate[]
}

interface OpenAIResponsesOutputContentItem {
  type: string
  text?: string
  refusal?: string
}

interface OpenAIResponsesReasoningSummaryItem {
  type: string
  text?: string
}

interface OpenAIResponsesOutputItem {
  type: string
  role?: string
  content?: OpenAIResponsesOutputContentItem[]
  summary?: OpenAIResponsesReasoningSummaryItem[]
  encrypted_content?: string
  result?: string
  id?: string
}

interface OpenAIResponsesUsageInfo {
  input_tokens?: number
  output_tokens?: number
  total_tokens?: number
}

interface OpenAIResponsesResponse {
  output_text?: string
  output?: OpenAIResponsesOutputItem[]
  usage?: OpenAIResponsesUsageInfo
}

// 流式 url_citation annotation
interface OpenAIResponsesAnnotation {
  type?: string
  url?: string
  title?: string
  start_index?: number
  end_index?: number
  // file_citation 等其它类型预留, 当前不展示
  file_id?: string
  index?: number
}

interface OpenAIResponsesStreamEvent {
  type?: string
  delta?: string
  arguments?: string
  text?: string
  output_index?: number
  item_id?: string
  item?: OpenAIResponsesInputItem
  error?: ApiError
  // response.output_text.annotation.added 携带的引用
  annotation?: OpenAIResponsesAnnotation
  annotation_index?: number
  content_index?: number
  // response.image_generation_call.partial_image
  partial_image_b64?: string
  partial_image_index?: number
}

// OpenAI 流式响应块增量
// MiniMax reasoning_details 项
interface MiniMaxReasoningDetail {
  text?: string
  type?: string
}

// 流式响应中的工具调用增量
interface OpenAIStreamToolCallFunction {
  name?: string
  arguments?: string
}

interface OpenAIStreamToolCall {
  index: number
  id?: string
  type?: string
  function?: OpenAIStreamToolCallFunction
}

interface OpenAIStreamDelta {
  content?: string
  // 推理内容（DeepSeek R1 等模型）
  reasoning_content?: string
  // 推理内容（OpenAI-compat 一些供应商使用 reasoning 字段）
  reasoning?: string
  // MiniMax 推理内容（数组格式，每个元素有 text 字段）
  reasoning_details?: MiniMaxReasoningDetail[]
  // 图片数据（兼容 OpenAI DALL-E 或第三方服务的图片响应）
  image_url?: string  // 图片 URL
  image_base64?: string  // base64 编码的图片数据
  image_mime_type?: string  // 图片 MIME 类型
  // Function Calling 工具调用增量
  tool_calls?: OpenAIStreamToolCall[]
}

// OpenAI 流式响应块选择项
interface OpenAIStreamChoice {
  delta: OpenAIStreamDelta
  finish_reason?: string
}

// OpenAI 流式响应块
interface OpenAIStreamChunk {
  choices: OpenAIStreamChoice[]
}

// Anthropic 流式响应块增量
interface AnthropicStreamDelta {
  text?: string
  // 图片数据（Anthropic image_block 增量）
  image_source?: AnthropicImageSource
}

// Anthropic 流式响应块
interface AnthropicStreamChunk {
  type: string
  delta?: AnthropicStreamDelta
}

// Google 流式响应块部分
interface GoogleStreamPart {
  text?: string
  inline_data?: GoogleStreamInlineData
  thought?: boolean
  thoughtSignature?: string
}

// Google 流式响应块内联数据（图片等）
interface GoogleStreamInlineData {
  mime_type: string
  data: string
}

// Google 流式响应块内容
interface GoogleStreamContent {
  parts: GoogleStreamPart[]
}

// Google 流式响应块候选
interface GoogleStreamCandidate {
  content: GoogleStreamContent
  finishReason?: string
}

// Google 流式响应块
interface GoogleStreamChunk {
  candidates: GoogleStreamCandidate[]
}

// OpenAI Responses 内置工具 (hosted tool) 运行事件类型
export enum HostedResponsesToolEventKind {
  WEB_SEARCH_STARTED = 'web_search_started',
  WEB_SEARCH_SEARCHING = 'web_search_searching',
  WEB_SEARCH_COMPLETED = 'web_search_completed',
  IMAGE_GENERATION_STARTED = 'image_generation_started',
  IMAGE_GENERATION_PARTIAL = 'image_generation_partial',
  IMAGE_GENERATION_COMPLETED = 'image_generation_completed'
}

export class HostedResponsesToolEvent {
  kind: HostedResponsesToolEventKind
  itemId: string
  outputIndex: number
  // image_generation_partial 渐进序号, 其它事件为 -1
  partialIndex: number
  // web_search_call 携带: 当次 action 类型、搜索关键词 / queries 或读取的页面 url。
  // 其它事件为 ''. 上层可用于在搜索卡片实时展示"在搜什么 / 在读什么".
  query: string
  url: string
  actionType: string
  queries: string[]

  constructor(
    kind: HostedResponsesToolEventKind,
    itemId: string = '',
    outputIndex: number = -1,
    partialIndex: number = -1,
    query: string = '',
    url: string = '',
    actionType: string = '',
    queries: string[] = []
  ) {
    this.kind = kind
    this.itemId = itemId
    this.outputIndex = outputIndex
    this.partialIndex = partialIndex
    this.query = query
    this.url = url
    this.actionType = actionType
    this.queries = queries
  }
}

// 流式响应块解析结果
interface StreamChunkResult {
  content: string
  reasoningContent: string
  // 推理内容是否来自结构化字段（reasoning/reasoning_content/reasoning_details 等）。
  // 若来自 <think> 标签解析，则为 false/undefined（避免做 overlap 裁剪等“猜测”）。
  reasoningIsStructured?: boolean
  // 图片数据（Gemini 生成图片 / OpenAI Responses image_generation_call 都走这里）
  imageData?: string
  imageMimeType?: string
  // image_generation_call.partial_image 返回的是阶段性预览，用于让 UI 区分“最终”与“渐进”图
  imageIsPartial?: boolean
  imagePartialIndex?: number
  // Function Calling 工具调用增量
  toolCallDeltas?: ToolCallDelta[]
  finishReason?: string
  errorMessage?: string
  // OpenAI Responses 一个完整的 reasoning output item(type='reasoning',含 encrypted_content)
  // 来自 response.output_item.done 事件,供 ChatViewModel 累积到 aiMessage.reasoningSignatureBlob
  reasoningItem?: OpenAIResponsesInputItem
  // OpenAI Responses 内置工具 (web_search / image_generation) 状态事件
  hostedToolEvent?: HostedResponsesToolEvent
  // OpenAI Responses url_citation annotation 产生的引用增量
  searchReferences?: SearchReference[]
}

// 工具调用增量（用于流式响应累积）
export interface ToolCallDelta {
  index: number
  id?: string
  functionName?: string
  arguments?: string
}

// AI API 服务
export class AIApiService {
  private static instance: AIApiService | null = null
  private readonly managedProviderHeaderNames: string[] = [
    'authorization',
    'content-type',
    'accept',
    'api-key',
    'x-api-key',
    'anthropic-version'
  ]
  private httpService: HttpService
  // DeepSeek-R1 <think> 标签解析状态
  private isInThinkingBlock: boolean = false
  // 当前 OpenAI 流是否使用 MiniMax 的累计 content 语义
  private currentOpenAIStreamUsesCumulativeContent: boolean = false
  private currentResponsesHostedImageMimeType: string = 'image/png'
  // MiniMax reasoning_details 累积内容缓冲区（用于计算增量）
  private minimaxReasoningBuffer: string = ''
  // MiniMax content 累积内容缓冲区（用于计算增量，因为 MiniMax 的 content 也是累积的）
  private minimaxContentBuffer: string = ''
  // 部分标签缓冲区（处理跨 chunk 的标签）
  private partialTagBuffer: string = ''
  // Function Calling 工具调用累积状态（流式响应）
  private streamToolCalls: Map<number, ToolCall> = new Map()
  // OpenAI Responses 流里收集到的完整 reasoning items(含 encrypted_content),
  // 在 onComplete 之前由 ChatViewModel 通过 consumeLastStreamResponsesReasoningBlob 取走
  private streamResponsesReasoningItems: OpenAIResponsesInputItem[] = []

  private constructor() {
    this.httpService = getHttpService()
  }

  // 重置 thinking 状态（每次新请求前调用）
  resetThinkingState(): void {
    this.isInThinkingBlock = false
    this.currentOpenAIStreamUsesCumulativeContent = false
    this.currentResponsesHostedImageMimeType = 'image/png'
    this.minimaxReasoningBuffer = ''
    this.minimaxContentBuffer = ''
    this.partialTagBuffer = ''
    this.streamToolCalls = new Map()
    this.streamResponsesReasoningItems = []
  }

  // 取走并清空本轮流式累积的 Responses reasoning items,序列化成可持久化的 JSON blob。
  // 空串表示没有需透传的 reasoning。
  consumeLastStreamResponsesReasoningBlob(): string {
    if (this.streamResponsesReasoningItems.length === 0) {
      return ''
    }
    const blob = this.serializeResponsesReasoningItems(this.streamResponsesReasoningItems)
    this.streamResponsesReasoningItems = []
    return blob
  }

  private toCompatibilityInfo(config: AIApiConfig): CompatibilityProviderInfo {
    return {
      providerId: config.providerId,
      baseUrl: config.baseUrl,
      apiStyle: config.apiStyle
    }
  }

  private getCompatibilityProfile(config: AIApiConfig): ProviderCompatibilityProfile {
    return resolveProviderCompatibilityProfile(this.toCompatibilityInfo(config))
  }

  private getReasoningRequestStrategy(config: AIApiConfig, model: string): ReasoningRequestStrategy {
    const rawOverride = config.modelReasoningStrategyOverride
    const hasOverride = rawOverride !== undefined && rawOverride !== ''
    const strategy = resolveReasoningRequestStrategyWithOverride(
      this.toCompatibilityInfo(config),
      model,
      rawOverride
    )
    if (!hasOverride && strategy === ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT &&
      config.modelSupportsReasoning !== true) {
      return ReasoningRequestStrategy.NONE
    }
    if (!hasOverride && strategy === ReasoningRequestStrategy.DEEPSEEK_THINKING &&
      config.modelSupportsReasoning !== true) {
      return ReasoningRequestStrategy.NONE
    }
    if (!hasOverride && strategy === ReasoningRequestStrategy.MIMO_THINKING &&
      config.modelSupportsReasoning !== true) {
      return ReasoningRequestStrategy.NONE
    }
    if (!hasOverride && strategy === ReasoningRequestStrategy.DASHSCOPE_THINKING &&
      config.modelSupportsReasoning !== true) {
      return ReasoningRequestStrategy.NONE
    }
    if (!hasOverride && strategy === ReasoningRequestStrategy.KIMI_THINKING &&
      config.modelSupportsReasoning !== true) {
      return ReasoningRequestStrategy.NONE
    }
    if (!hasOverride && config.modelSupportsReasoning === false) {
      return ReasoningRequestStrategy.NONE
    }
    return strategy
  }

  private configureStreamState(config: AIApiConfig, model: string): void {
    const compatibilityProfile = this.getCompatibilityProfile(config)
    const usesMiniMaxReasoningSplit = this.getReasoningRequestStrategy(config, model) ===
      ReasoningRequestStrategy.OPENAI_REASONING_SPLIT
    this.currentOpenAIStreamUsesCumulativeContent =
      compatibilityProfile.openAIStreamContentMode === OpenAIStreamContentMode.CUMULATIVE &&
      usesMiniMaxReasoningSplit
  }

  private getMiniMaxIncrementalContent(rawContent: string): string {
    if (rawContent === '' || rawContent.length <= this.minimaxContentBuffer.length) {
      return ''
    }
    const incrementalContent = rawContent.substring(this.minimaxContentBuffer.length)
    this.minimaxContentBuffer = rawContent
    return incrementalContent
  }

  private tryEmitResponsesImageDoneLine(
    jsonStr: string,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): boolean {
    if (!jsonStr.includes('response.output_item.done') || !jsonStr.includes('image_generation_call')) {
      return false
    }
    const resultStart = this.findJsonStringValueStart(jsonStr, 'result', 0)
    if (resultStart < 0) {
      return false
    }
    const resultEnd = jsonStr.indexOf('"', resultStart)
    if (resultEnd <= resultStart) {
      return false
    }
    const base64Data = jsonStr.substring(resultStart, resultEnd)
    if (base64Data === '') {
      return false
    }
    const itemIdStart = this.findJsonStringValueStartBefore(jsonStr, 'id', resultStart)
    let itemId = ''
    if (itemIdStart >= 0) {
      const itemIdEnd = jsonStr.indexOf('"', itemIdStart)
      if (itemIdEnd > itemIdStart) {
        itemId = jsonStr.substring(itemIdStart, itemIdEnd)
      }
    }
    const outputIndex = this.findJsonNumberValueBefore(jsonStr, 'output_index', resultStart)
    if (onHostedToolEvent !== undefined) {
      try {
        onHostedToolEvent(new HostedResponsesToolEvent(
          HostedResponsesToolEventKind.IMAGE_GENERATION_COMPLETED,
          itemId,
          outputIndex
        ))
      } catch (error) {
        console.error('AIApiService', `Error in onHostedToolEvent callback: ${JSON.stringify(error)}`)
      }
    }
    if (onImageData !== undefined) {
      try {
        onImageData(base64Data, this.currentResponsesHostedImageMimeType, false)
      } catch (error) {
        console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(error)}`)
      }
    }
    return true
  }

  private tryEmitResponsesImageDoneBytes(
    lineBytes: Uint8Array,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): boolean {
    if (!this.containsAsciiPattern(lineBytes, 'response.output_item.done')) {
      return false
    }
    if (!this.containsAsciiPattern(lineBytes, 'image_generation_call')) {
      return false
    }
    const resultStart = this.findJsonStringValueStartBytes(lineBytes, 'result', 0)
    const itemIdStart = resultStart >= 0 ?
      this.findJsonStringValueStartBeforeBytes(lineBytes, 'id', resultStart) :
      this.findJsonStringValueStartBytes(lineBytes, 'id', 0)
    let itemId = ''
    if (itemIdStart >= 0) {
      const itemIdEnd = this.indexOfByte(lineBytes, 34, itemIdStart)
      if (itemIdEnd > itemIdStart) {
        itemId = this.decodeUtf8Bytes(lineBytes.subarray(itemIdStart, itemIdEnd))
      }
    }
    const outputIndex = resultStart >= 0 ?
      this.findJsonNumberValueBeforeBytes(lineBytes, 'output_index', resultStart) :
      this.findJsonNumberValueBytes(lineBytes, 'output_index', 0)
    if (resultStart < 0) {
      this.emitHostedImageGenerationCompleted(itemId, outputIndex, onHostedToolEvent)
      return true
    }
    const resultEnd = this.indexOfByte(lineBytes, 34, resultStart)
    if (resultEnd <= resultStart) {
      this.emitHostedImageGenerationCompleted(itemId, outputIndex, onHostedToolEvent)
      return true
    }
    const base64Data = this.decodeUtf8Bytes(lineBytes.subarray(resultStart, resultEnd))
    if (base64Data === '') {
      this.emitHostedImageGenerationCompleted(itemId, outputIndex, onHostedToolEvent)
      return true
    }
    this.emitHostedImageGenerationCompleted(itemId, outputIndex, onHostedToolEvent)
    this.emitResponsesImageData(base64Data, onImageData)
    return true
  }

  private emitResponsesImageData(
    base64Data: string,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void
  ): void {
    if (onImageData === undefined) {
      return
    }
    try {
      onImageData(base64Data, this.currentResponsesHostedImageMimeType, false)
    } catch (error) {
      console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(error)}`)
    }
  }

  private emitHostedImageGenerationCompleted(
    itemId: string,
    outputIndex: number,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): void {
    if (onHostedToolEvent !== undefined) {
      try {
        onHostedToolEvent(new HostedResponsesToolEvent(
          HostedResponsesToolEventKind.IMAGE_GENERATION_COMPLETED,
          itemId,
          outputIndex
        ))
      } catch (error) {
        console.error('AIApiService', `Error in onHostedToolEvent callback: ${JSON.stringify(error)}`)
      }
    }
  }

  private decodeUtf8Bytes(bytes: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8')
    return decoder.decodeToString(bytes)
  }

  private indexOfByte(bytes: Uint8Array, target: number, fromIndex: number): number {
    for (let i = Math.max(0, fromIndex); i < bytes.length; i++) {
      if (bytes[i] === target) {
        return i
      }
    }
    return -1
  }

  private containsAsciiPattern(bytes: Uint8Array, pattern: string): boolean {
    return this.indexOfAsciiPattern(bytes, pattern, 0, bytes.length) >= 0
  }

  private indexOfAsciiPattern(bytes: Uint8Array, pattern: string, fromIndex: number, beforeIndex: number): number {
    if (pattern.length === 0) {
      return -1
    }
    const start = Math.max(0, fromIndex)
    const limit = Math.min(beforeIndex, bytes.length) - pattern.length
    const first = pattern.charCodeAt(0)
    for (let i = start; i <= limit; i++) {
      if (bytes[i] !== first) {
        continue
      }
      let matched = true
      for (let j = 1; j < pattern.length; j++) {
        if (bytes[i + j] !== pattern.charCodeAt(j)) {
          matched = false
          break
        }
      }
      if (matched) {
        return i
      }
    }
    return -1
  }

  private findJsonStringValueStartBytes(bytes: Uint8Array, key: string, fromIndex: number): number {
    let searchIndex = fromIndex
    const keyPattern = `"${key}"`
    while (searchIndex < bytes.length) {
      const keyIndex = this.indexOfAsciiPattern(bytes, keyPattern, searchIndex, bytes.length)
      if (keyIndex < 0) {
        return -1
      }
      const valueStart = this.findJsonValueStartAfterKeyBytes(bytes, keyIndex + keyPattern.length)
      if (valueStart >= 0 && bytes[valueStart] === 34) {
        return valueStart + 1
      }
      searchIndex = keyIndex + keyPattern.length
    }
    return -1
  }

  private findJsonStringValueStartBeforeBytes(bytes: Uint8Array, key: string, beforeIndex: number): number {
    let searchIndex = 0
    let result = -1
    while (searchIndex < beforeIndex) {
      const found = this.findJsonStringValueStartBytes(bytes, key, searchIndex)
      if (found < 0 || found >= beforeIndex) {
        return result
      }
      result = found
      searchIndex = found + 1
    }
    return result
  }

  private findJsonNumberValueBytes(bytes: Uint8Array, key: string, fromIndex: number): number {
    const keyPattern = `"${key}"`
    const keyIndex = this.indexOfAsciiPattern(bytes, keyPattern, fromIndex, bytes.length)
    if (keyIndex < 0) {
      return -1
    }
    const valueStart = this.findJsonValueStartAfterKeyBytes(bytes, keyIndex + keyPattern.length)
    if (valueStart < 0) {
      return -1
    }
    return this.parseJsonNumberAtBytes(bytes, valueStart, bytes.length)
  }

  private findJsonNumberValueBeforeBytes(bytes: Uint8Array, key: string, beforeIndex: number): number {
    let searchIndex = 0
    let result = -1
    while (searchIndex < beforeIndex) {
      const keyPattern = `"${key}"`
      const keyIndex = this.indexOfAsciiPattern(bytes, keyPattern, searchIndex, beforeIndex)
      if (keyIndex < 0) {
        return result
      }
      const valueStart = this.findJsonValueStartAfterKeyBytes(bytes, keyIndex + keyPattern.length)
      if (valueStart >= 0 && valueStart < beforeIndex) {
        const parsed = this.parseJsonNumberAtBytes(bytes, valueStart, beforeIndex)
        if (parsed >= 0) {
          result = parsed
        }
      }
      searchIndex = keyIndex + keyPattern.length
    }
    return result
  }

  private findJsonValueStartAfterKeyBytes(bytes: Uint8Array, fromIndex: number): number {
    let index = fromIndex
    while (index < bytes.length && this.isJsonWhitespaceByte(bytes[index])) {
      index++
    }
    if (index >= bytes.length || bytes[index] !== 58) {
      return -1
    }
    index++
    while (index < bytes.length && this.isJsonWhitespaceByte(bytes[index])) {
      index++
    }
    return index < bytes.length ? index : -1
  }

  private parseJsonNumberAtBytes(bytes: Uint8Array, fromIndex: number, beforeIndex: number): number {
    let index = fromIndex
    let value = 0
    let hasDigit = false
    while (index < beforeIndex) {
      const byte = bytes[index]
      if (byte < 48 || byte > 57) {
        break
      }
      value = value * 10 + byte - 48
      hasDigit = true
      index++
    }
    return hasDigit ? value : -1
  }

  private isJsonWhitespaceByte(byte: number): boolean {
    return byte === 32 || byte === 9 || byte === 10 || byte === 13
  }

  private findJsonStringValueStart(source: string, key: string, fromIndex: number): number {
    const compactPattern = `"${key}":"`
    const spacedPattern = `"${key}": "`
    const compactIndex = source.indexOf(compactPattern, fromIndex)
    const spacedIndex = source.indexOf(spacedPattern, fromIndex)
    if (compactIndex < 0 && spacedIndex < 0) {
      return -1
    }
    if (spacedIndex < 0 || (compactIndex >= 0 && compactIndex < spacedIndex)) {
      return compactIndex + compactPattern.length
    }
    return spacedIndex + spacedPattern.length
  }

  private findJsonStringValueStartBefore(source: string, key: string, beforeIndex: number): number {
    const compactPattern = `"${key}":"`
    const spacedPattern = `"${key}": "`
    const compactIndex = source.lastIndexOf(compactPattern, beforeIndex)
    const spacedIndex = source.lastIndexOf(spacedPattern, beforeIndex)
    if (compactIndex < 0 && spacedIndex < 0) {
      return -1
    }
    if (spacedIndex < 0 || compactIndex > spacedIndex) {
      return compactIndex + compactPattern.length
    }
    return spacedIndex + spacedPattern.length
  }

  private findJsonNumberValueBefore(source: string, key: string, beforeIndex: number): number {
    const keyIndex = source.lastIndexOf(`"${key}"`, beforeIndex)
    if (keyIndex < 0) {
      return -1
    }
    const colonIndex = source.indexOf(':', keyIndex)
    if (colonIndex < 0 || colonIndex >= beforeIndex) {
      return -1
    }
    let start = colonIndex + 1
    while (start < beforeIndex && source.charAt(start) === ' ') {
      start++
    }
    let end = start
    while (end < beforeIndex) {
      const ch = source.charAt(end)
      if (ch < '0' || ch > '9') {
        break
      }
      end++
    }
    if (end <= start) {
      return -1
    }
    const parsed = Number(source.substring(start, end))
    return isNaN(parsed) ? -1 : parsed
  }

  private shouldUseOpenAIResponses(config: AIApiConfig, forceChatCompletions: boolean = false): boolean {
    return !forceChatCompletions &&
      config.apiStyle === ApiStyle.OPENAI &&
      config.openaiTransport === OpenAITransport.RESPONSES
  }

  private isMoonshotCompatibleProvider(config: AIApiConfig): boolean {
    const providerId = config.providerId.toLowerCase()
    const baseUrl = config.baseUrl.toLowerCase()
    return providerId.includes('kimi') ||
      providerId.includes('moonshot') ||
      baseUrl.includes('api.moonshot.cn') ||
      baseUrl.includes('api.moonshot.ai') ||
      baseUrl.includes('platform.moonshot')
  }

  private compactMoonshotToolParameters(parameters: object): object {
    try {
      const cloned = JSON.parse(JSON.stringify(parameters)) as Object
      return this.stripMoonshotToolSchemaMetadata(cloned) as object
    } catch (error) {
      console.warn('AIApiService', `Failed to compact Moonshot tool schema: ${JSON.stringify(error)}`)
      return parameters
    }
  }

  private isMoonshotToolSchemaMetadataKey(key: string): boolean {
    return key === 'description' ||
      key === 'title' ||
      key === 'default' ||
      key === 'examples' ||
      key === 'markdownDescription' ||
      key === 'deprecated' ||
      key === 'readOnly' ||
      key === 'writeOnly'
  }

  private stripMoonshotToolSchemaMetadata(value: Object): Object {
    if (Array.isArray(value)) {
      const sourceArray = value as Object[]
      const resultArray: Object[] = []
      for (let i = 0; i < sourceArray.length; i++) {
        resultArray.push(this.stripMoonshotToolSchemaMetadata(sourceArray[i]))
      }
      return resultArray as Object
    }
    if (typeof value !== 'object' || value === null) {
      return value
    }
    const source = value as Record<string, Object>
    const result = JSON.parse('{}') as Record<string, Object>
    const keys = Object.keys(source)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      if (this.isMoonshotToolSchemaMetadataKey(key)) {
        continue
      }
      const child = source[key]
      if (typeof child === 'object' && child !== null) {
        result[key] = this.stripMoonshotToolSchemaMetadata(child)
      } else {
        result[key] = child
      }
    }
    return result
  }

  private getToolParametersForProvider(config: AIApiConfig, tool: ToolDefinition): object {
    const parameters = tool.function.parameters.toJsonObject()
    if (this.isMoonshotCompatibleProvider(config)) {
      return this.compactMoonshotToolParameters(parameters)
    }
    return parameters
  }

  private buildOpenAIChatTools(config: AIApiConfig, tools: ToolDefinition[]): OpenAITool[] {
    const openaiTools: OpenAITool[] = []
    for (let i = 0; i < tools.length; i++) {
      const tool = tools[i]
      openaiTools.push({
        type: 'function',
        function: {
          name: tool.function.name,
          description: tool.function.description,
          parameters: this.getToolParametersForProvider(config, tool)
        }
      })
    }
    return openaiTools
  }

  private buildOpenAIResponsesTools(
    config: AIApiConfig,
    tools: ToolDefinition[],
    builtInTools?: BuiltInResponsesToolSpec[]
  ): OpenAIResponsesTool[] {
    const responseTools: OpenAIResponsesTool[] = []
    for (let i = 0; i < tools.length; i++) {
      const tool = tools[i]
      responseTools.push({
        type: 'function',
        name: tool.function.name,
        description: tool.function.description,
        parameters: this.getToolParametersForProvider(config, tool)
      })
    }
    if (builtInTools !== undefined) {
      for (let i = 0; i < builtInTools.length; i++) {
        const spec = builtInTools[i]
        if (spec.kind === BuiltInResponsesToolKind.WEB_SEARCH) {
          const tool: OpenAIResponsesTool = { type: 'web_search' }
          if (spec.searchContextSize !== undefined && spec.searchContextSize !== '') {
            tool.search_context_size = spec.searchContextSize
          }
          if (spec.searchUserLocation !== undefined) {
            tool.user_location = spec.searchUserLocation
          }
          responseTools.push(tool)
        } else if (spec.kind === BuiltInResponsesToolKind.IMAGE_GENERATION) {
          const tool: OpenAIResponsesTool = { type: 'image_generation' }
          tool.model = spec.imageModel !== undefined && spec.imageModel !== '' ? spec.imageModel : 'gpt-image-2'
          this.currentResponsesHostedImageMimeType = 'image/png'
          console.info('AIApiService',
            `[Responses] image_generation tool: model=${tool.model}, request=minimal_rikkahub`)
          responseTools.push(tool)
        }
      }
    }
    return responseTools
  }

  private buildResponsesUsageInfo(usage?: OpenAIResponsesUsageInfo): UsageInfo | null {
    if (usage === undefined || usage === null) {
      return null
    }
    return {
      prompt_tokens: usage.input_tokens !== undefined ? usage.input_tokens : 0,
      completion_tokens: usage.output_tokens !== undefined ? usage.output_tokens : 0,
      total_tokens: usage.total_tokens !== undefined ? usage.total_tokens : 0
    }
  }

  private extractOpenAIResponsesContent(response: OpenAIResponsesResponse): string {
    if (response.output_text !== undefined && response.output_text !== null && response.output_text !== '') {
      return response.output_text
    }

    let content = ''
    if (response.output === undefined || response.output === null) {
      return content
    }

    for (let i = 0; i < response.output.length; i++) {
      const item = response.output[i]
      if (item.type !== 'message' || item.content === undefined || item.content === null) {
        continue
      }
      for (let j = 0; j < item.content.length; j++) {
        const part = item.content[j]
        if ((part.type === 'output_text' || part.type === 'text') && part.text !== undefined) {
          content += part.text
        } else if (part.type === 'refusal' && part.refusal !== undefined) {
          content += part.refusal
        }
      }
    }

    return content
  }

  private extractOpenAIResponsesImageData(response: OpenAIResponsesResponse): string {
    if (response.output === undefined || response.output === null) {
      return ''
    }
    for (let i = 0; i < response.output.length; i++) {
      const item = response.output[i]
      if (item.type === 'image_generation_call' && item.result !== undefined && item.result !== '') {
        return item.result
      }
    }
    return ''
  }

  // 获取累积的工具调用（流式响应完成后调用）
  getAccumulatedToolCalls(): ToolCall[] {
    const result: ToolCall[] = []
    this.streamToolCalls.forEach((toolCall, index) => {
      const normalizedId = this.normalizeToolCallId(toolCall.id, index)
      const normalizedName = this.normalizeToolFunctionName(toolCall.functionName)
      const normalizedArgs = this.normalizeToolArguments(toolCall.arguments)
      result.push(new ToolCall(normalizedId, normalizedName, normalizedArgs))
    })
    return result
  }

  private normalizeToolCallId(rawId: string, index: number): string {
    const value = rawId as string | null | undefined
    if (value === undefined || value === null || value.trim() === '') {
      return `tool_call_${Date.now()}_${index}`
    }
    return value.trim()
  }

  private normalizeToolFunctionName(rawName: string): string {
    const value = rawName as string | null | undefined
    if (value === undefined || value === null) {
      return ''
    }
    return value.trim()
  }

  private mergeToolFunctionName(previousName: string, incomingName: string): string {
    const prev = this.normalizeToolFunctionName(previousName)
    const next = this.normalizeToolFunctionName(incomingName)
    if (next === '') {
      return prev
    }
    if (prev === '') {
      return next
    }
    if (next.startsWith(prev)) {
      return next
    }
    if (prev.startsWith(next)) {
      return prev
    }
    if (next.endsWith(prev)) {
      return next
    }
    if (prev.endsWith(next)) {
      return prev
    }
    return prev + next
  }

  private normalizeToolArguments(rawArgs: string): string {
    const value = rawArgs as string | Object | null | undefined
    if (value === undefined || value === null) {
      return '{}'
    }
    if (typeof value === 'string') {
      const trimmed = value.trim()
      return trimmed !== '' ? trimmed : '{}'
    }
    try {
      return JSON.stringify(value)
    } catch (error) {
      console.warn('AIApiService', `Failed to stringify tool arguments: ${JSON.stringify(error)}`)
      return '{}'
    }
  }

  private normalizeToolArgumentsChunk(rawArgs: string): string {
    const value = rawArgs as string | Object | null | undefined
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value
    }
    try {
      return JSON.stringify(value)
    } catch (error) {
      console.warn('AIApiService', `Failed to stringify tool argument chunk: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private getOpenAIResponsesToolCallIndex(event: OpenAIResponsesStreamEvent): number {
    if (event.output_index !== undefined && event.output_index >= 0) {
      return event.output_index
    }
    return this.streamToolCalls.size
  }

  private upsertOpenAIResponsesToolCall(
    index: number,
    callId: string,
    functionName: string,
    argumentsChunk: string,
    replaceArguments: boolean
  ): ToolCallDelta {
    let existingToolCall = this.streamToolCalls.get(index)
    if (existingToolCall === undefined) {
      existingToolCall = new ToolCall('', '', '')
      this.streamToolCalls.set(index, existingToolCall)
    }

    const normalizedCallId = callId.trim()
    if (normalizedCallId !== '') {
      existingToolCall.id = normalizedCallId
    }

    const normalizedName = this.normalizeToolFunctionName(functionName)
    if (normalizedName !== '') {
      existingToolCall.functionName = this.mergeToolFunctionName(existingToolCall.functionName, normalizedName)
    }

    const normalizedArgs = this.normalizeToolArgumentsChunk(argumentsChunk)
    if (normalizedArgs !== '') {
      if (replaceArguments) {
        existingToolCall.arguments = normalizedArgs
      } else {
        existingToolCall.arguments += normalizedArgs
      }
    }

    const delta: ToolCallDelta = {
      index: index,
      id: normalizedCallId !== '' ? normalizedCallId : undefined,
      functionName: normalizedName !== '' ? normalizedName : undefined,
      arguments: normalizedArgs !== '' ? normalizedArgs : undefined
    }
    return delta
  }

  // 说明：不做“内容像推理”的启发式判断（Kelivo 策略）
  // 若供应商未提供结构化推理字段（reasoning_content/reasoning_details 等）或显式 <think> 标签，
  // 则不尝试拆分，避免出现“推理被拆出一部分、另一部分仍在正文”的不一致体验。

  static getInstance(): AIApiService {
    if (AIApiService.instance === null) {
      AIApiService.instance = new AIApiService()
    }
    return AIApiService.instance
  }

  // 发送聊天请求
  async sendChatRequest(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    temperature?: number,
    maxTokens?: number,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  ): Promise<AIApiResult> {
    const url = this.buildChatUrl(config, model)
    const requestBody = this.buildRequestBody(config, messages, model, temperature, maxTokens, reasoningLevel)
    this.configureStreamState(config, model)
    const response = await this.postWithResolvedAuth(
      config,
      url,
      JSON.stringify(requestBody),
      120000 // 2分钟超时
    )

    if (!response.success) {
      const result: AIApiResult = {
        success: false,
        content: '',
        errorMessage: this.extractHttpErrorMessage(response, '请求失败'),
        usage: null,
        reasoningContent: ''
      }
      return result
    }

    return this.parseResponse(config, response.data)
  }

  // 测试连接
  async testConnection(config: AIApiConfig, modelId: string = ''): Promise<AIApiResult> {
    const testMessages: RequestMessage[] = [
      new RequestMessage('user', 'Hi')
    ]

    const testModel = modelId !== '' ? modelId : this.getCompatibilityProfile(config).defaultTestModel
    if (testModel === '') {
      return {
        success: false,
        content: '',
        errorMessage: '请先添加一个模型后再测试连接',
        usage: null,
        reasoningContent: ''
      }
    }
    const url = this.buildChatUrl(config, testModel)

    // 根据 API 风格构建测试请求
    let requestBodyStr: string
    if (config.apiStyle === ApiStyle.GOOGLE) {
      const googleBody: GoogleRequestBody = {
        contents: [{ role: 'user', parts: [{ text: 'Hi' }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: 10 }
      }
      requestBodyStr = JSON.stringify(googleBody)
    } else if (config.apiStyle === ApiStyle.ANTHROPIC) {
      const anthropicBody: AnthropicRequestBody = {
        model: testModel,
        messages: [{ role: 'user', content: 'Hi' }],
        max_tokens: 10,
        temperature: 0.7
      }
      requestBodyStr = JSON.stringify(anthropicBody)
    } else if (this.shouldUseOpenAIResponses(config)) {
      const responsesBody: OpenAIResponsesRequestBody = {
        model: testModel,
        input: 'Hi',
        max_output_tokens: 16
      }
      requestBodyStr = JSON.stringify(responsesBody)
    } else {
      const openaiBody: TestRequestBody = {
        model: testModel,
        messages: testMessages
      }
      if (this.requiresMaxCompletionTokens(testModel)) {
        openaiBody.max_completion_tokens = 10
      } else {
        openaiBody.max_tokens = 10
      }
      requestBodyStr = JSON.stringify(openaiBody)
    }

    const response = await this.postWithResolvedAuth(
      config,
      url,
      requestBodyStr,
      15000 // 15秒超时
    )

    if (!response.success) {
      return {
        success: false,
        content: '',
        errorMessage: this.extractHttpErrorMessage(response, '测试连接失败'),
        usage: null,
        reasoningContent: ''
      }
    }

    // 2xx 响应 — 连接成功
    return {
      success: true,
      content: 'Connection successful',
      errorMessage: '',
      usage: null,
      reasoningContent: ''
    }
  }

  // 获取模型列表
  async getModels(config: AIApiConfig): Promise<ModelsListResult> {
    const compatibilityProfile = this.getCompatibilityProfile(config)
    if (compatibilityProfile.modelDiscoveryStrategy === ModelDiscoveryStrategy.STATIC_CATALOG) {
      return {
        success: true,
        models: compatibilityProfile.staticModels.slice(),
        errorMessage: ''
      }
    }

    const url = this.buildModelsUrl(config)
    const headers = this.buildHeaders(config)

    const response = await this.httpService.get(url, headers)

    if (!response.success) {
      return {
        success: false,
        models: [],
        errorMessage: this.extractHttpErrorMessage(response, '获取模型列表失败')
      }
    }

    try {
      if (config.apiStyle === ApiStyle.GOOGLE) {
        // Google 返回 { models: [{ name: "models/gemini-2.5-flash", supportedGenerationMethods: [...] }] }
        // 需要:1) 取 name 字段 2) 去掉 "models/" 前缀(否则后续拼 chat URL 会变成 models/models/xxx) 3) 过滤掉
        // 不支持 generateContent 的模型(embedding / tts 之类),避免用户选完打 chat 时再 404
        const googleResponse = JSON.parse(response.data) as GoogleModelsListResponse
        const googleModelIds: string[] = []
        if (googleResponse.models !== undefined && googleResponse.models !== null) {
          for (let i = 0; i < googleResponse.models.length; i++) {
            const descriptor = googleResponse.models[i]
            const methods = descriptor.supportedGenerationMethods
            if (methods !== undefined && methods.indexOf('generateContent') === -1) {
              continue
            }
            let modelId = descriptor.name
            if (modelId.startsWith('models/')) {
              modelId = modelId.substring(7)
            }
            if (modelId !== '') {
              googleModelIds.push(modelId)
            }
          }
        }
        const googleResult: ModelsListResult = {
          success: true,
          models: googleModelIds,
          errorMessage: ''
        }
        return googleResult
      }

      const modelsResponse = JSON.parse(response.data) as ModelsListResponse
      const modelIds: string[] = []
      if (modelsResponse.data !== undefined && modelsResponse.data !== null) {
        for (let i = 0; i < modelsResponse.data.length; i++) {
          modelIds.push(modelsResponse.data[i].id)
        }
      }
      const result: ModelsListResult = {
        success: true,
        models: modelIds,
        errorMessage: ''
      }
      return result
    } catch (error) {
      const result: ModelsListResult = {
        success: false,
        models: [],
        errorMessage: 'Failed to parse models list'
      }
      return result
    }
  }

  // 构建聊天 API URL
  private buildChatUrl(config: AIApiConfig, model: string = '', forceChatCompletions: boolean = false): string {
    // 如果提供了自定义 apiPath，直接使用
    if (config.apiPath && config.apiPath.trim() !== '') {
      return ApiUrlResolver.buildUrl(config.baseUrl, config.apiPath)
    }

    let baseUrl = config.baseUrl
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.slice(0, -1)
    }

    // 根据 API 风格构建 URL
    if (config.apiStyle === ApiStyle.GOOGLE) {
      // Google Gemini API: https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
      // 检查 baseUrl 是否已包含版本路径，避免重复拼接
      const versionPrefix = /\/v\d+\w*/.test(baseUrl) ? '' : '/v1beta'
      if (baseUrl.includes('googleapis.com')) {
        return `${baseUrl}${versionPrefix}/models/${model}:generateContent?key=${config.apiKey}`
      }
      return `${baseUrl}${versionPrefix}/models/${model}:generateContent`
    }

    if (config.apiStyle === ApiStyle.ANTHROPIC) {
      if (/\/v\d+\w*/.test(baseUrl)) {
        return `${baseUrl}/messages`
      }
      return `${baseUrl}/v1/messages`
    }

    const openAIPath = this.shouldUseOpenAIResponses(config, forceChatCompletions)
      ? '/responses'
      : '/chat/completions'
    if (/\/v\d+\w*/.test(baseUrl)) {
      return `${baseUrl}${openAIPath}`
    }
    return `${baseUrl}/v1${openAIPath}`
  }

  // 构建模型列表 API URL
  private buildModelsUrl(config: AIApiConfig): string {
    // 如果提供了自定义 apiPath，推导 models 端点
    if (config.apiPath && config.apiPath.trim() !== '') {
      // 将 /chat/completions 替换为 /models
      const modelsPath = config.apiPath.replace('/chat/completions', '/models').replace('/completions', '/models')
      return ApiUrlResolver.buildUrl(config.baseUrl, modelsPath)
    }

    let baseUrl = config.baseUrl
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.slice(0, -1)
    }

    // Google Gemini: 通过 URL 参数携带 API key,且默认拼 /v1beta
    if (config.apiStyle === ApiStyle.GOOGLE) {
      const versionPrefix = /\/v\d+\w*/.test(baseUrl) ? '' : '/v1beta'
      if (baseUrl.includes('googleapis.com')) {
        return `${baseUrl}${versionPrefix}/models?key=${config.apiKey}`
      }
      return `${baseUrl}${versionPrefix}/models`
    }

    // 检查 baseUrl 是否已包含版本路径（如 /v1、/v2、/v3 等）
    if (/\/v\d+\w*/.test(baseUrl)) {
      return `${baseUrl}/models`
    }
    return `${baseUrl}/v1/models`
  }

  // 构建请求头
  private buildHeaders(
    config: AIApiConfig,
    anthropicAuthStrategy?: AnthropicAuthStrategy
  ): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    }

    if (config.apiStyle === ApiStyle.ANTHROPIC) {
      const resolvedAuthStrategy = anthropicAuthStrategy ?? this.getCompatibilityProfile(config).anthropicAuthStrategy
      if (resolvedAuthStrategy === AnthropicAuthStrategy.BEARER && config.apiKey !== '') {
        headers['Authorization'] = `Bearer ${config.apiKey}`
      } else {
        headers['x-api-key'] = config.apiKey
      }
      headers['anthropic-version'] = '2023-06-01'
    } else if (config.apiStyle === ApiStyle.GOOGLE) {
      // Google API key 通过 URL 参数传递，不需要额外的 header
    } else if (config.providerType === ProviderType.AZURE) {
      headers['api-key'] = config.apiKey
    } else if (config.apiKey !== '') {
      headers['Authorization'] = `Bearer ${config.apiKey}`
    }

    const customHeaders = parseCustomHeadersMap(config.customHeadersJson !== undefined ? config.customHeadersJson : '')
    const customHeaderNames = Object.keys(customHeaders)
    for (let i = 0; i < customHeaderNames.length; i++) {
      const headerName = customHeaderNames[i]
      if (this.isManagedProviderHeaderName(headerName)) {
        continue
      }
      headers[headerName] = customHeaders[headerName]
    }

    return headers
  }

  private isManagedProviderHeaderName(name: string): boolean {
    return this.managedProviderHeaderNames.includes(normalizeCustomHeaderName(name))
  }

  private async postWithResolvedAuth(
    config: AIApiConfig,
    url: string,
    requestBody: string,
    timeout: number
  ): Promise<HttpResponse> {
    let response = await this.httpService.postWithTimeout(
      url,
      requestBody,
      this.buildHeaders(config),
      timeout
    )

    if (!this.shouldRetryMiniMaxAnthropicWithBearer(config, response.statusCode)) {
      return response
    }

    console.warn('AIApiService', `Retrying MiniMax Anthropic request with Bearer auth: ${url}`)
    response = await this.httpService.postWithTimeout(
      url,
      requestBody,
      this.buildHeaders(config, AnthropicAuthStrategy.BEARER),
      timeout
    )
    return response
  }

  private shouldRetryMiniMaxAnthropicWithBearer(config: AIApiConfig, statusCode: number): boolean {
    return config.apiStyle === ApiStyle.ANTHROPIC &&
      this.getCompatibilityProfile(config).anthropicBearerRetryOnAuthFailure &&
      (statusCode === 401 || statusCode === 403)
  }

  private extractHttpErrorMessage(response: HttpResponse, fallbackMessage: string): string {
    if (response.statusCode === 0) {
      return response.errorMessage !== '' ? response.errorMessage : fallbackMessage
    }

    const apiErrorMessage = this.extractApiErrorMessage(response.data)
    if (apiErrorMessage !== '') {
      return apiErrorMessage
    }

    if (response.statusCode === 401 || response.statusCode === 403) {
      return 'API Key 认证失败'
    }
    if (response.statusCode >= 500) {
      return `服务器错误 (${response.statusCode})`
    }
    if (response.errorMessage !== '') {
      return response.errorMessage
    }
    return `${fallbackMessage} (${response.statusCode})`
  }

  private extractApiErrorMessage(responseData: string): string {
    if (responseData.trim() === '') {
      return ''
    }

    try {
      const parsed = JSON.parse(responseData) as ApiErrorResponse
      if (parsed.error !== undefined && parsed.error !== null && parsed.error.message !== '') {
        return parsed.error.message
      }
    } catch (_error) {}

    try {
      const parsed = JSON.parse(responseData) as Record<string, Object | string>
      if (typeof parsed.message === 'string' && parsed.message !== '') {
        return parsed.message
      }
      if (typeof parsed.detail === 'string' && parsed.detail !== '') {
        return parsed.detail
      }
      if (parsed.base_resp !== undefined && parsed.base_resp !== null) {
        const baseResp = parsed.base_resp as Record<string, Object | string>
        if (typeof baseResp.status_msg === 'string' && baseResp.status_msg !== '') {
          return baseResp.status_msg
        }
      }
    } catch (_error) {}

    if (responseData.length <= 200) {
      return responseData
    }
    return ''
  }

  private extractOpenAIResponsesReasoningContent(response: OpenAIResponsesResponse): string {
    if (response.output === undefined || response.output === null) {
      return ''
    }

    const reasoningParts: string[] = []
    for (let i = 0; i < response.output.length; i++) {
      const item = response.output[i]
      if (item.type !== 'reasoning' || item.summary === undefined || item.summary === null) {
        continue
      }
      for (let j = 0; j < item.summary.length; j++) {
        const summaryItem = item.summary[j]
        if (summaryItem.text !== undefined && summaryItem.text !== '') {
          reasoningParts.push(summaryItem.text)
        }
      }
    }
    return reasoningParts.join('\n')
  }

  // 从非流式 Responses 响应里收集完整 reasoning items(含 encrypted_content),
  // 供跨轮推理透传使用。ArkTS 不支持跨 interface 隐式 cast,故显式拷贝需要字段。
  private collectOpenAIResponsesReasoningItems(response: OpenAIResponsesResponse): OpenAIResponsesInputItem[] {
    if (response.output === undefined || response.output === null) {
      return []
    }
    const items: OpenAIResponsesInputItem[] = []
    for (let i = 0; i < response.output.length; i++) {
      const rawItem = response.output[i]
      if (rawItem.type !== 'reasoning') {
        continue
      }
      const item: OpenAIResponsesInputItem = {
        type: 'reasoning'
      }
      if (rawItem.id !== undefined) {
        item.id = rawItem.id
      }
      if (rawItem.encrypted_content !== undefined) {
        item.encrypted_content = rawItem.encrypted_content
      }
      if (rawItem.summary !== undefined) {
        item.summary = rawItem.summary
      }
      items.push(item)
    }
    return items
  }

  // 构建请求体
  //
  // maxTokens 语义:
  // - undefined / 0 表示"无限制", 仅在 Anthropic Claude 路径会兜底成 64_000 (Anthropic API 强制要求);
  // - OpenAI Chat / OpenAI Responses / Google Gemini 等路径在 0/undefined 时直接不下发对应字段,
  //   让模型按自身上限输出, 避免被全局 4096 锁死。
  // 调用方应将助手配置中的 maxOutputTokens (0 = 无限制) 直接透传到这里。
  private buildRequestBody(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    temperature: number | undefined,
    maxTokens?: number,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    tools?: ToolDefinition[],
    toolChoice?: OpenAIResponsesToolChoice,
    forceChatCompletions: boolean = false,
    builtInResponsesTools?: BuiltInResponsesToolSpec[]
  ): OpenAIRequestBody | OpenAIResponsesRequestBody | AnthropicRequestBody | GoogleRequestBody {
    const reasoningRequestStrategy = this.getReasoningRequestStrategy(config, model)
    const normalizedReasoningLevel = normalizeReasoningLevelForControl(reasoningLevel)
    const reasoningTokenLimit = this.getReasoningTokenLimit(normalizedReasoningLevel)

    if (config.apiStyle === ApiStyle.GOOGLE) {
      // Google Gemini 格式
      const googleContents: GoogleContent[] = []
      const googleSystemInstruction = this.buildGoogleSystemInstruction(messages)

      for (let i = 0; i < messages.length; i++) {
        const msg = messages[i]
        if (msg.role !== 'system') {
          const role = msg.role === 'assistant' ? 'model' : 'user'
          const parts: GoogleContentPart[] = []

          // 添加附件（图片和文件，包括 PDF）
          if (msg.hasAttachments()) {
            for (let j = 0; j < msg.attachments.length; j++) {
              const attachment = msg.attachments[j]
              if (attachment.base64Data !== '' && !AttachmentContentService.canExtractInlineText(attachment)) {
                // Google Gemini 支持通过 inline_data 直接发送图片和 PDF
                const inlineDataPart: GoogleContentPart = {
                  inline_data: {
                    mime_type: attachment.mimeType,
                    data: attachment.base64Data
                  }
                }
                parts.push(inlineDataPart)
              }
            }
          }

          // 添加文本
          const textContent = AttachmentContentService.appendInlineTextAttachments(msg.content, msg.attachments)
          if (textContent !== '') {
            const textPart: GoogleContentPart = {
              text: textContent
            }
            parts.push(textPart)
          }

          const content: GoogleContent = {
            role: role,
            parts: parts
          }
          googleContents.push(content)
        }
      }

      const googleBody: GoogleRequestBody = {
        contents: googleContents,
        generationConfig: {}
      }
      if (temperature !== undefined) {
        googleBody.generationConfig.temperature = temperature
      }
      if (maxTokens !== undefined && maxTokens > 0) {
        googleBody.generationConfig.maxOutputTokens = maxTokens
      }
      if (googleSystemInstruction !== undefined) {
        googleBody.systemInstruction = googleSystemInstruction
      }
      const googleThinkingConfig = this.getGoogleThinkingConfig(
        model,
        reasoningRequestStrategy,
        normalizedReasoningLevel
      )
      if (googleThinkingConfig !== undefined) {
        googleBody.generationConfig.thinkingConfig = googleThinkingConfig
      }
      return googleBody
    }

    if (config.apiStyle === ApiStyle.ANTHROPIC) {
      // Anthropic 格式
      const anthropicMessages: (MessageContent | AnthropicMultimodalMessage)[] = []
      let systemPrompt = ''

      for (let i = 0; i < messages.length; i++) {
        const msg = messages[i]
        if (msg.role === 'system') {
          systemPrompt = msg.content
        } else if (msg.hasAttachments()) {
          // Anthropic 多模态消息（支持图片和 PDF）
          const contentParts: AnthropicContentPart[] = []

          // 添加附件
          for (let j = 0; j < msg.attachments.length; j++) {
            const attachment = msg.attachments[j]
            if (attachment.base64Data !== '') {
              if (attachment.type === AttachmentType.IMAGE) {
                // 图片使用 image 类型
                const imagePart: AnthropicContentPart = {
                  type: 'image',
                  source: {
                    type: 'base64',
                    media_type: attachment.mimeType,
                    data: attachment.base64Data
                  }
                }
                contentParts.push(imagePart)
              } else if (!AttachmentContentService.canExtractInlineText(attachment)) {
                // PDF 等文件使用 document 类型
                const docPart: AnthropicContentPart = {
                  type: 'document',
                  source: {
                    type: 'base64',
                    media_type: attachment.mimeType,
                    data: attachment.base64Data
                  }
                }
                contentParts.push(docPart)
              }
            }
          }

          // 添加文本
          const textContent = AttachmentContentService.appendInlineTextAttachments(msg.content, msg.attachments)
          if (textContent !== '') {
            const textPart: AnthropicContentPart = {
              type: 'text',
              text: textContent
            }
            contentParts.push(textPart)
          }

          const multimodalMsg: AnthropicMultimodalMessage = {
            role: msg.role,
            content: contentParts
          }
          anthropicMessages.push(multimodalMsg)
        } else {
          const msgContent: MessageContent = {
            role: msg.role,
            content: msg.content
          }
          anthropicMessages.push(msgContent)
        }
      }

      // Anthropic Claude API 强制要求 max_tokens 字段, 助手未配置时按 RikkaHub 兜底 64_000,
      // 覆盖 Claude 4 系列 64K 输出能力。其他 provider 不传字段就好, 不要在这里改成 4096。
      const claudeMaxTokens = (maxTokens !== undefined && maxTokens > 0) ? maxTokens : 64_000

      if (systemPrompt !== '') {
        const bodyWithSystem: AnthropicRequestBody = {
          model: model,
          messages: anthropicMessages,
          max_tokens: claudeMaxTokens,
          system: systemPrompt
        }
        if (temperature !== undefined) {
          bodyWithSystem.temperature = temperature
        }
        this.applyAnthropicReasoningConfig(
          bodyWithSystem,
          model,
          reasoningRequestStrategy,
          normalizedReasoningLevel,
          reasoningTokenLimit
        )
        return bodyWithSystem
      }

      const body: AnthropicRequestBody = {
        model: model,
        messages: anthropicMessages,
        max_tokens: claudeMaxTokens
      }
      if (temperature !== undefined) {
        body.temperature = temperature
      }
      this.applyAnthropicReasoningConfig(
        body,
        model,
        reasoningRequestStrategy,
        normalizedReasoningLevel,
        reasoningTokenLimit
      )
      return body
    }

    const useOpenAIResponses = this.shouldUseOpenAIResponses(config, forceChatCompletions)

    if (useOpenAIResponses) {
      const responseInputs: OpenAIResponsesInputItem[] = []
      const instructionParts: string[] = []
      const compatibilityProfile = this.getCompatibilityProfile(config)
      const allowEncryptedReasoning = compatibilityProfile.supportsOpenAIResponsesEncryptedReasoning &&
        (reasoningRequestStrategy === ReasoningRequestStrategy.OPENAI_REASONING_EFFORT ||
          reasoningRequestStrategy === ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT)

      for (let i = 0; i < messages.length; i++) {
        const msg = messages[i]
        if (msg.role === 'system') {
          if (msg.content.trim() !== '') {
            instructionParts.push(msg.content.trim())
          }
          continue
        }
        // 助手消息(含 tool_calls 的 assistant 也算)前注入上一轮保存的 reasoning items,
        // 配合 include=reasoning.encrypted_content 让官方 Responses API 跨轮保持推理状态。
        if (msg.role === 'assistant' && allowEncryptedReasoning && msg.reasoningSignatureBlob.trim() !== '') {
          const reasoningItems = this.parseResponsesReasoningBlob(msg.reasoningSignatureBlob)
          for (let k = 0; k < reasoningItems.length; k++) {
            responseInputs.push(reasoningItems[k])
          }
        }
        if (msg.hasToolCalls()) {
          if (msg.content !== '') {
            responseInputs.push({
              type: 'message',
              role: 'assistant',
              status: 'completed',
              content: [{
                type: 'output_text',
                text: msg.content
              }]
            })
          }
          for (let j = 0; j < msg.toolCalls.length; j++) {
            const toolCall = msg.toolCalls[j]
            responseInputs.push({
              type: 'function_call',
              call_id: toolCall.id,
              name: toolCall.functionName,
              arguments: toolCall.arguments
            })
          }
          continue
        }
        if (msg.isToolResultMessage()) {
          responseInputs.push({
            type: 'function_call_output',
            call_id: msg.toolCallId,
            output: msg.content
          })
          continue
        }

        const contentParts: OpenAIResponsesContentPart[] = []
        const fileTextContent = AttachmentContentService.buildNonInlineFileAttachmentText(msg.attachments)
        const isAssistantMessage = msg.role === 'assistant'

        for (let j = 0; j < msg.attachments.length && !isAssistantMessage; j++) {
          const attachment = msg.attachments[j]
          if (attachment.base64Data === '') {
            continue
          }
          if (attachment.type === AttachmentType.IMAGE) {
            contentParts.push({
              type: 'input_image',
              image_url: `data:${attachment.mimeType};base64,${attachment.base64Data}`,
              detail: 'auto'
            })
          }
        }

        let textContent = AttachmentContentService.appendInlineTextAttachments(msg.content, msg.attachments)
        if (fileTextContent !== '') {
          textContent = textContent !== '' ? `${fileTextContent}\n${textContent}` : fileTextContent
        }
        if (textContent !== '') {
          contentParts.unshift({
            type: isAssistantMessage ? 'output_text' : 'input_text',
            text: textContent
          })
        }

        if (contentParts.length === 0) {
          continue
        }

        if (isAssistantMessage) {
          responseInputs.push({
            type: 'message',
            role: 'assistant',
            status: 'completed',
            content: contentParts
          })
        } else {
          responseInputs.push({
            role: 'user',
            content: contentParts
          })
        }
      }

      const responsesBody: OpenAIResponsesRequestBody = {
        model: model,
        input: responseInputs,
        max_output_tokens: maxTokens
      }
      if (temperature !== undefined) {
        responsesBody.temperature = temperature
      }
      // gpt-5 / o-系列推理模型在 Responses API 也只接受 temperature=1,与 Chat Completions 一致。
      if (this.requiresMaxCompletionTokens(model)) {
        responsesBody.temperature = undefined
      }
      if (instructionParts.length > 0) {
        responsesBody.instructions = instructionParts.join('\n\n')
      }
      if (reasoningRequestStrategy === ReasoningRequestStrategy.OPENAI_REASONING_EFFORT ||
        reasoningRequestStrategy === ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT) {
        const effort = this.getOpenAIReasoningEffortForStrategy(
          reasoningRequestStrategy,
          model,
          normalizedReasoningLevel
        )
        // ReasoningLevel.AUTO 不传 effort (让服务端按模型默认决策), 但仍然需要主动开 summary='auto',
        // 否则 OpenAI Responses 在 SSE 流里不会下发 response.reasoning_summary_text.delta,
        // 客户端会出现 "模型其实推理了, 但前端拿不到推理摘要" 的现象 (see ChatPage feedback 2026-05-23)。
        if (normalizedReasoningLevel !== ReasoningLevel.OFF) {
          responsesBody.reasoning = { summary: 'auto' }
          if (effort !== undefined) {
            responsesBody.reasoning.effort = effort
          }
        } else if (effort !== undefined) {
          // OFF + 模型支持 'none' effort 时仍要把 effort 设上 (gpt-5 系列), 但不开 summary
          responsesBody.reasoning = { effort: effort }
        }
        console.info('AIApiService',
          `[Responses] reasoning config: level=${normalizedReasoningLevel}, effort=${effort ?? 'unset'}, ` +
          `summary=${responsesBody.reasoning?.summary ?? 'unset'}`)
        // 跨轮保持推理状态:请求头里声明需要 encrypted_content,并把上一轮的 reasoning items 一起回传
        if (allowEncryptedReasoning && normalizedReasoningLevel !== ReasoningLevel.OFF) {
          responsesBody.include = ['reasoning.encrypted_content']
        }
      } else if (reasoningRequestStrategy === ReasoningRequestStrategy.DASHSCOPE_THINKING) {
        this.applyDashScopeReasoningConfig(responsesBody, normalizedReasoningLevel, reasoningTokenLimit)
      }
      const effectiveFunctionTools: ToolDefinition[] = tools !== undefined ? tools : []
      const hasFunctionTools = effectiveFunctionTools.length > 0
      const hasBuiltInTools = builtInResponsesTools !== undefined && builtInResponsesTools.length > 0
      if (hasFunctionTools || hasBuiltInTools) {
        responsesBody.tools = this.buildOpenAIResponsesTools(
          config,
          effectiveFunctionTools,
          builtInResponsesTools
        )
        if (toolChoice !== undefined) {
          if (typeof toolChoice === 'string') {
            if (toolChoice !== '') {
              responsesBody.tool_choice = toolChoice
            }
          } else {
            responsesBody.tool_choice = toolChoice
          }
        }
      }
      return responsesBody
    }

    // OpenAI 兼容格式
    const openaiMessages: (MessageContent | MultimodalMessageContent | ToolResultMessageContent | AssistantMessageWithToolCalls)[] = []
    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]

      // 处理工具结果消息（tool 角色）
      if (msg.isToolResultMessage()) {
        const toolResultMsg: ToolResultMessageContent = {
          role: 'tool',
          tool_call_id: msg.toolCallId,
          content: msg.content
        }
        openaiMessages.push(toolResultMsg)
        continue
      }

      // 处理带工具调用的 assistant 消息
      if (msg.hasToolCalls()) {
        const toolCallsForApi: OpenAIToolCall[] = []
        for (let j = 0; j < msg.toolCalls.length; j++) {
          const tc = msg.toolCalls[j]
          const apiToolCall: OpenAIToolCall = {
            id: tc.id,
            type: 'function',
            function: {
              name: tc.functionName,
              arguments: tc.arguments
            }
          }
          toolCallsForApi.push(apiToolCall)
        }
        const assistantWithTools: AssistantMessageWithToolCalls = {
          role: 'assistant',
          content: msg.content !== '' ? msg.content : null,
          tool_calls: toolCallsForApi
        }
        if (this.shouldPreserveReasoningContentForToolMessages(reasoningRequestStrategy)) {
          // DeepSeek-V4 等 provider 的 thinking 模式下,reasoning_content 字段必须原样回传:
          // 即使内容为空串也要保留字段,丢字段会触发 HTTP 400 invalid_request_error。
          assistantWithTools.reasoning_content = msg.reasoningContent
        }
        openaiMessages.push(assistantWithTools)
        continue
      }

      // 检查是否有附件
      if (msg.hasAttachments()) {
        // 构建多模态消息
        const contentParts: MultimodalContentPart[] = []
        const fileTextContent = AttachmentContentService.buildNonInlineFileAttachmentText(msg.attachments)

        // 处理附件
        for (let j = 0; j < msg.attachments.length; j++) {
          const attachment = msg.attachments[j]
          if (attachment.base64Data !== '') {
            if (attachment.type === AttachmentType.IMAGE) {
              // 图片使用 image_url 类型
              const imagePart: MultimodalContentPart = {
                type: 'image_url',
                image_url: {
                  url: `data:${attachment.mimeType};base64,${attachment.base64Data}`
                }
              }
              contentParts.push(imagePart)
            }
          }
        }

        // 添加文本（包含文件提示信息）
        let textContent = AttachmentContentService.appendInlineTextAttachments(msg.content, msg.attachments)
        if (fileTextContent !== '') {
          textContent = textContent !== '' ? `${fileTextContent}\n${textContent}` : fileTextContent
        }
        if (textContent !== '') {
          const textPart: MultimodalContentPart = {
            type: 'text',
            text: textContent
          }
          contentParts.push(textPart)
        }

        const multimodalMsg: MultimodalMessageContent = {
          role: msg.role,
          content: contentParts
        }
        if (msg.role === 'assistant' &&
          this.shouldPreserveReasoningContentForToolMessages(reasoningRequestStrategy)) {
          multimodalMsg.reasoning_content = msg.reasoningContent
        }
        openaiMessages.push(multimodalMsg)
      } else {
        // 纯文本消息
        const msgContent: MessageContent = {
          role: msg.role,
          content: msg.content
        }
        if (msg.role === 'assistant') {
          if (this.shouldPreserveReasoningContentForToolMessages(reasoningRequestStrategy)) {
            // DeepSeek-V4 等 provider 的 thinking 模式下,assistant 历史的 reasoning_content
            // 必须原样回传(空串也要保留字段),否则会触发 HTTP 400。
            msgContent.reasoning_content = msg.reasoningContent
          }
          if (msg.reasoningContent.trim() !== '' &&
            this.getCompatibilityProfile(config).preserveAssistantReasoningDetails) {
            const reasoningDetail: MiniMaxReasoningDetail = {
              text: msg.reasoningContent,
              type: 'text'
            }
            msgContent.reasoning_details = [reasoningDetail]
          }
        }
        openaiMessages.push(msgContent)
      }
    }

    const requestBody: OpenAIRequestBody = {
      model: model,
      messages: openaiMessages
    }
    if (temperature !== undefined) {
      requestBody.temperature = temperature
    }
    if (this.requiresMaxCompletionTokens(model)) {
      // gpt-5 / o-系列推理模型只接受 temperature=1,自定义值会被官方接口拒绝(HTTP 400)。
      // 不下发字段即走默认 1,既不破坏行为又规避 400。
      requestBody.temperature = undefined
      if (maxTokens !== undefined && maxTokens > 0) {
        requestBody.max_completion_tokens = maxTokens
      }
    } else if (maxTokens !== undefined && maxTokens > 0) {
      requestBody.max_tokens = maxTokens
    }

    // 添加显式启用的采样参数。未启用时 config 中不会出现对应字段,请求体就不下发。
    if (config.topP !== undefined) {
      requestBody.top_p = config.topP
    }
    if (config.presencePenalty !== undefined) {
      requestBody.presence_penalty = config.presencePenalty
    }
    if (config.frequencyPenalty !== undefined) {
      requestBody.frequency_penalty = config.frequencyPenalty
    }

    if (reasoningRequestStrategy === ReasoningRequestStrategy.OPENAI_REASONING_EFFORT ||
      reasoningRequestStrategy === ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT) {
      const effort = this.getOpenAIReasoningEffortForStrategy(
        reasoningRequestStrategy,
        model,
        normalizedReasoningLevel
      )
      if (effort !== undefined) {
        requestBody.reasoning_effort = effort
      }
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.OPENAI_REASONING_SPLIT &&
      normalizedReasoningLevel !== ReasoningLevel.OFF) {
      requestBody.reasoning_split = true
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.OPENROUTER_REASONING) {
      const openRouterReasoning = this.getOpenRouterReasoningConfig(normalizedReasoningLevel, reasoningTokenLimit)
      if (openRouterReasoning !== undefined) {
        requestBody.reasoning = openRouterReasoning
      }
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.DEEPSEEK_THINKING) {
      if (normalizedReasoningLevel !== ReasoningLevel.OFF) {
        requestBody.thinking = { type: 'enabled' }
        const effort = this.getDeepSeekReasoningEffort(normalizedReasoningLevel)
        if (effort !== undefined) {
          requestBody.reasoning_effort = effort
        }
      } else {
        requestBody.thinking = { type: 'disabled' }
      }
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.MIMO_THINKING) {
      requestBody.thinking = {
        type: normalizedReasoningLevel === ReasoningLevel.OFF ? 'disabled' : 'enabled'
      }
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.ZHIPU_THINKING) {
      if (normalizedReasoningLevel !== ReasoningLevel.OFF) {
        requestBody.thinking = { type: 'enabled', clear_thinking: false }
      } else {
        requestBody.thinking = { type: 'disabled' }
      }
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.DASHSCOPE_THINKING) {
      this.applyDashScopeReasoningConfig(requestBody, normalizedReasoningLevel, reasoningTokenLimit)
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.KIMI_THINKING) {
      this.applyKimiReasoningConfig(requestBody, normalizedReasoningLevel)
    } else if (reasoningRequestStrategy === ReasoningRequestStrategy.SILICONFLOW_THINKING) {
      if (normalizedReasoningLevel === ReasoningLevel.OFF) {
        requestBody.enable_thinking = false
      } else if (normalizedReasoningLevel !== ReasoningLevel.AUTO) {
        requestBody.thinking_budget = this.getSiliconFlowThinkingTokenLimit(reasoningTokenLimit)
      }
    }
    // 添加 Function Calling 工具定义
    if (tools !== undefined && tools.length > 0) {
      requestBody.tools = this.buildOpenAIChatTools(config, tools)
      if (typeof toolChoice === 'string' && toolChoice !== '') {
        requestBody.tool_choice = toolChoice
      }
    }
    return requestBody
  }

  // 解析响应
  private parseResponse(config: AIApiConfig, responseData: string): AIApiResult {
    try {
      // 先尝试解析为错误响应
      const errorCheck = JSON.parse(responseData) as ApiErrorResponse
      if (errorCheck.error !== undefined && errorCheck.error !== null) {
        const result: AIApiResult = {
          success: false,
          content: '',
          errorMessage: errorCheck.error.message,
          usage: null,
          reasoningContent: ''
        }
        return result
      }

      if (config.apiStyle === ApiStyle.GOOGLE) {
        return this.parseGoogleResponse(responseData)
      }

      if (config.apiStyle === ApiStyle.ANTHROPIC) {
        return this.parseAnthropicResponse(responseData)
      }

      if (this.shouldUseOpenAIResponses(config)) {
        return this.parseOpenAIResponsesResponse(responseData)
      }
      return this.parseOpenAIResponse(responseData)
    } catch (error) {
      const result: AIApiResult = {
        success: false,
        content: '',
        errorMessage: `Failed to parse response: ${JSON.stringify(error)}`,
        usage: null,
        reasoningContent: ''
      }
      return result
    }
  }

  private parseOpenAIResponsesResponse(responseData: string): AIApiResult {
    const response = JSON.parse(responseData) as OpenAIResponsesResponse
    const content = this.extractOpenAIResponsesContent(response)
    const imageData = this.extractOpenAIResponsesImageData(response)
    const reasoningContent = this.extractOpenAIResponsesReasoningContent(response)
    const reasoningItems = this.collectOpenAIResponsesReasoningItems(response)
    const result: AIApiResult = {
      success: content !== '' || imageData !== '',
      content: content,
      errorMessage: content !== '' || imageData !== '' ? '' : 'No output in response',
      usage: this.buildResponsesUsageInfo(response.usage),
      reasoningContent: reasoningContent
    }
    if (imageData !== '') {
      result.imageData = imageData
      result.imageMimeType = 'image/png'
    }
    const blob = this.serializeResponsesReasoningItems(reasoningItems)
    if (blob !== '') {
      result.reasoningSignatureBlob = blob
    }
    return result
  }

  // 解析 OpenAI 响应
  private parseOpenAIResponse(responseData: string): AIApiResult {
    const response = JSON.parse(responseData) as ChatCompletionResponse
    if (response.choices !== undefined && response.choices.length > 0) {
      const choice = response.choices[0]
      const structuredReasoning = (choice.message.reasoning_content !== undefined && choice.message.reasoning_content !== '')
        || (choice.message.reasoning !== undefined && choice.message.reasoning !== '')
      const result: AIApiResult = {
        success: true,
        content: choice.message.content || '',
        errorMessage: '',
        usage: response.usage,
        reasoningContent: choice.message.reasoning_content || choice.message.reasoning || '',
        finishReason: choice.finish_reason
      }
      if (structuredReasoning && result.reasoningContent !== '' && result.content !== '') {
        result.content = this.stripReasoningOverlap(result.content, result.reasoningContent, false)
      }

      // 处理图片响应（base64 格式）
      if (choice.message.image_base64 && choice.message.image_mime_type) {
        result.imageData = choice.message.image_base64
        result.imageMimeType = choice.message.image_mime_type
      }
      // 处理图片 URL
      else if (choice.message.image_url) {
        result.imageData = choice.message.image_url
        result.imageMimeType = 'image/jpeg'
      }

      // 解析 Function Calling 工具调用
      if (choice.message.tool_calls !== undefined && choice.message.tool_calls.length > 0) {
        const toolCalls: ToolCall[] = []
        for (let i = 0; i < choice.message.tool_calls.length; i++) {
          const tc = choice.message.tool_calls[i]
          const normalizedId = this.normalizeToolCallId(tc.id, i)
          const rawName = tc.function !== undefined ? tc.function.name : ''
          const rawArgs = tc.function !== undefined ? tc.function.arguments : ''
          const normalizedName = this.normalizeToolFunctionName(rawName)
          const normalizedArgs = this.normalizeToolArguments(rawArgs)
          const toolCall = new ToolCall(
            normalizedId,
            normalizedName,
            normalizedArgs
          )
          toolCalls.push(toolCall)
        }
        result.toolCalls = toolCalls
      }

      return result
    }
    const result: AIApiResult = {
      success: false,
      content: '',
      errorMessage: 'No choices in response',
      usage: null,
      reasoningContent: ''
    }
    return result
  }

  // 解析 Anthropic 响应
  private parseAnthropicResponse(responseData: string): AIApiResult {
    const response = JSON.parse(responseData) as AnthropicResponse
    if (response.content !== undefined && response.content.length > 0) {
      let content = ''
      let reasoningContent = ''
      let imageData = ''
      let imageMimeType = ''

      for (let i = 0; i < response.content.length; i++) {
        const block = response.content[i]
        if (block.type === 'text') {
          content += block.text
        } else if (block.type === 'thinking') {
          // Anthropic 的思考内容
          reasoningContent += block.text
        } else if (block.type === 'image' && block.source) {
          // Anthropic 的图片响应
          imageData = block.source.data
          imageMimeType = block.source.media_type
          console.info('AIApiService', `Received Anthropic image: ${imageMimeType}, size: ${imageData.length}`)
        }
      }

      const result: AIApiResult = {
        success: true,
        content: content,
        errorMessage: '',
        usage: response.usage,
        reasoningContent: reasoningContent
      }

      // 添加图片数据
      if (imageData && imageMimeType) {
        result.imageData = imageData
        result.imageMimeType = imageMimeType
      }

      return result
    }
    const result: AIApiResult = {
      success: false,
      content: '',
      errorMessage: 'No content in response',
      usage: null,
      reasoningContent: ''
    }
    return result
  }

  // 解析 Google Gemini 响应
  private parseGoogleResponse(responseData: string): AIApiResult {
    const response = JSON.parse(responseData) as GoogleResponse
    if (response.candidates !== undefined && response.candidates.length > 0) {
      const candidate = response.candidates[0]
      if (candidate.content !== undefined && candidate.content.parts !== undefined && candidate.content.parts.length > 0) {
        let content = ''
        let reasoningContent = ''
        let imageData = ''
        let imageMimeType = ''
        for (let i = 0; i < candidate.content.parts.length; i++) {
          const part = candidate.content.parts[i]
          if (part.text !== undefined && part.text !== '') {
            if (part.thought === true) {
              reasoningContent += part.text
            } else {
              content += part.text
            }
          } else if (part.inline_data !== undefined) {
            imageData = part.inline_data.data
            imageMimeType = part.inline_data.mime_type
          }
        }
        const result: AIApiResult = {
          success: true,
          content: content,
          errorMessage: '',
          usage: null,
          reasoningContent: reasoningContent,
          finishReason: candidate.finishReason
        }
        if (imageData !== '' && imageMimeType !== '') {
          result.imageData = imageData
          result.imageMimeType = imageMimeType
        }
        return result
      }
    }
    const result: AIApiResult = {
      success: false,
      content: '',
      errorMessage: 'No candidates in response',
      usage: null,
      reasoningContent: ''
    }
    return result
  }

  private getReasoningTokenLimit(level: ReasoningLevel): number {
    switch (level) {
      case ReasoningLevel.OFF:
        return 0
      case ReasoningLevel.AUTO:
        return -1
      case ReasoningLevel.LOW:
        return 1024
      case ReasoningLevel.MEDIUM:
        return 16000
      case ReasoningLevel.HIGH:
        return 32000
      case ReasoningLevel.XHIGH:
        return 64000
      default:
        return -1
    }
  }

  private getAnthropicThinkingTokenLimit(tokenLimit: number): number {
    if (tokenLimit > 0) {
      return tokenLimit
    }
    return 16000
  }

  private normalizeModelId(model: string): string {
    return model.trim().toLowerCase()
  }

  private supportsAnthropicAdaptiveThinking(model: string): boolean {
    const modelLower = this.normalizeModelId(model)
    return modelLower.includes('claude-opus-4-7') ||
      modelLower.includes('claude-opus-4-6') ||
      modelLower.includes('claude-sonnet-4-6') ||
      modelLower.includes('claude-mythos')
  }

  // 判断 assistant 历史消息是否需要原样回传 reasoning_content 字段。
  // 名字保留为 ForToolMessages 是历史原因,实际覆盖所有 assistant 消息(tool_call / 纯文本 / multimodal)。
  // 命中的 strategy 即使 reasoning_content 为空串也必须保留字段:
  // DeepSeek-V4 thinking 模式下,丢字段会触发 HTTP 400 invalid_request_error。
  private shouldPreserveReasoningContentForToolMessages(strategy: ReasoningRequestStrategy): boolean {
    return strategy === ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT ||
      strategy === ReasoningRequestStrategy.DEEPSEEK_THINKING ||
      strategy === ReasoningRequestStrategy.MIMO_THINKING ||
      strategy === ReasoningRequestStrategy.KIMI_THINKING
  }

  // 反序列化消息里持久化的 Responses reasoning 项。
  // blob 是 JSON 字符串,内容为 OpenAIResponsesInputItem[];解析失败返回空数组避免把请求打挂。
  private parseResponsesReasoningBlob(blob: string): OpenAIResponsesInputItem[] {
    if (blob.trim() === '') {
      return []
    }
    try {
      const parsed = JSON.parse(blob) as Object
      if (!Array.isArray(parsed)) {
        return []
      }
      const result: OpenAIResponsesInputItem[] = []
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i] as OpenAIResponsesInputItem
        if (item !== null && item !== undefined && item.type === 'reasoning') {
          result.push(item)
        }
      }
      return result
    } catch (_e) {
      return []
    }
  }

  // 序列化 Responses reasoning items 到 JSON 字符串,供 ChatMessage.reasoningSignatureBlob 持久化
  private serializeResponsesReasoningItems(items: OpenAIResponsesInputItem[]): string {
    if (items.length === 0) {
      return ''
    }
    try {
      return JSON.stringify(items)
    } catch (_e) {
      return ''
    }
  }

  private applyDashScopeReasoningConfig(
    body: OpenAIRequestBody | OpenAIResponsesRequestBody,
    level: ReasoningLevel,
    tokenLimit: number
  ): void {
    if (level === ReasoningLevel.OFF) {
      body.enable_thinking = false
      body.thinking_budget = undefined
      return
    }
    body.enable_thinking = true
    body.thinking_budget = tokenLimit > 0 ? tokenLimit : undefined
  }

  private applyKimiReasoningConfig(body: OpenAIRequestBody, level: ReasoningLevel): void {
    body.thinking = {
      type: level === ReasoningLevel.OFF ? 'disabled' : 'enabled'
    }
  }

  private getAnthropicAdaptiveEffort(model: string, level: ReasoningLevel): string | undefined {
    switch (level) {
      case ReasoningLevel.LOW:
        return 'low'
      case ReasoningLevel.MEDIUM:
        return 'medium'
      case ReasoningLevel.HIGH:
        return 'high'
      case ReasoningLevel.XHIGH:
        return this.getAnthropicMaxEffort(model)
      default:
        return undefined
    }
  }

  private getAnthropicMaxEffort(model: string): string {
    const modelLower = this.normalizeModelId(model)
    if (modelLower.includes('claude-opus-4-7')) {
      return 'xhigh'
    }
    if (modelLower.includes('claude-opus-4-6') ||
      modelLower.includes('claude-sonnet-4-6') ||
      modelLower.includes('claude-mythos')) {
      return 'max'
    }
    return 'high'
  }

  private applyAnthropicReasoningConfig(
    body: AnthropicRequestBody,
    model: string,
    strategy: ReasoningRequestStrategy,
    level: ReasoningLevel,
    tokenLimit: number
  ): void {
    if (strategy !== ReasoningRequestStrategy.ANTHROPIC_THINKING) {
      return
    }

    if (level === ReasoningLevel.OFF) {
      body.thinking = { type: 'disabled' }
      return
    }

    if (this.supportsAnthropicAdaptiveThinking(model)) {
      body.thinking = {
        type: 'adaptive',
        display: 'summarized'
      }
      body.temperature = undefined
      const effort = this.getAnthropicAdaptiveEffort(model, level)
      if (effort !== undefined) {
        body.output_config = { effort: effort }
      }
      return
    }

    body.thinking = {
      type: 'enabled',
      budget_tokens: this.getAnthropicThinkingTokenLimit(tokenLimit)
    }
  }

  // 获取 OpenAI 推理强度
  private getOpenAIReasoningEffortForStrategy(
    strategy: ReasoningRequestStrategy,
    model: string,
    level: ReasoningLevel
  ): string | undefined {
    if (strategy === ReasoningRequestStrategy.OPENAI_COMPAT_REASONING_EFFORT) {
      return this.getOpenAICompatReasoningEffort(level)
    }
    return this.getOpenAIReasoningEffort(model, level)
  }

  private getOpenAIReasoningEffort(model: string, level: ReasoningLevel): string | undefined {
    switch (level) {
      case ReasoningLevel.OFF:
        return this.supportsOpenAINoReasoning(model) ? 'none' : undefined
      case ReasoningLevel.AUTO:
        return undefined
      case ReasoningLevel.LOW:
        return 'low'
      case ReasoningLevel.MEDIUM:
        return 'medium'
      case ReasoningLevel.HIGH:
        return 'high'
      case ReasoningLevel.XHIGH:
        return this.supportsOpenAIXhighReasoning(model) ? 'xhigh' : 'high'
      default:
        return undefined
    }
  }

  private supportsOpenAINoReasoning(model: string): boolean {
    const modelLower = this.normalizeModelId(model)
    return modelLower.startsWith('gpt-5')
  }

  // OpenAI gpt-5 系列与 o-系列推理模型在 Chat Completions 必须用 max_completion_tokens,
  // 下发 max_tokens 会被官方接口拒绝(HTTP 400 unsupported_parameter)。
  // AiHubMix / 各种 OpenAI 代理透传请求,因此也会触发同样错误。
  private requiresMaxCompletionTokens(model: string): boolean {
    const modelLower = this.normalizeModelId(model)
    return modelLower.startsWith('gpt-5') ||
      modelLower.startsWith('o1') ||
      modelLower.startsWith('o3') ||
      modelLower.startsWith('o4')
  }

  private supportsOpenAIXhighReasoning(model: string): boolean {
    const modelLower = this.normalizeModelId(model)
    return modelLower.startsWith('gpt-5.4') ||
      modelLower.startsWith('gpt-5.3-codex') ||
      modelLower.startsWith('gpt-5.3-chat-latest') ||
      modelLower.startsWith('gpt-5.2')
  }

  private getOpenAICompatReasoningEffort(level: ReasoningLevel): string | undefined {
    // 通用 OpenAI 兼容协议没有统一的"关闭推理"取值;'none' 是 OpenAI gpt-5 系列扩展,
    // DeepSeek / SiliconFlow / 火山方舟等仅接受 low/medium/high/xhigh/max,下发 'none' 会触发 HTTP 400。
    // 此处对 OFF/AUTO 一律不下发字段,让后端走默认行为(对应 OpenAI 官方 gpt-5 路径走的是 getOpenAIReasoningEffort)。
    switch (level) {
      case ReasoningLevel.OFF:
        return undefined
      case ReasoningLevel.AUTO:
        return undefined
      case ReasoningLevel.LOW:
        return 'low'
      case ReasoningLevel.MEDIUM:
        return 'medium'
      case ReasoningLevel.HIGH:
        return 'high'
      case ReasoningLevel.XHIGH:
        return 'xhigh'
      default:
        return undefined
    }
  }

  private getDeepSeekReasoningEffort(level: ReasoningLevel): string | undefined {
    switch (level) {
      case ReasoningLevel.OFF:
      case ReasoningLevel.AUTO:
        return undefined
      case ReasoningLevel.XHIGH:
        return 'max'
      case ReasoningLevel.LOW:
      case ReasoningLevel.MEDIUM:
      case ReasoningLevel.HIGH:
      default:
        return 'high'
    }
  }

  private getOpenRouterReasoningConfig(level: ReasoningLevel, tokenLimit: number): OpenRouterReasoningConfig | undefined {
    switch (level) {
      case ReasoningLevel.OFF:
        return { enabled: false }
      case ReasoningLevel.AUTO:
        return { enabled: true }
      case ReasoningLevel.LOW:
      case ReasoningLevel.MEDIUM:
      case ReasoningLevel.HIGH:
      case ReasoningLevel.XHIGH:
        return { enabled: true, max_tokens: tokenLimit }
      default:
        return undefined
    }
  }

  private getSiliconFlowThinkingTokenLimit(tokenLimit: number): number {
    return tokenLimit > 0 ? tokenLimit : 16000
  }

  private collectGoogleSystemPrompt(messages: RequestMessage[]): string {
    const parts: string[] = []
    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]
      if (msg.role === 'system' && msg.content.trim() !== '') {
        parts.push(msg.content.trim())
      }
    }
    return parts.join('\n\n')
  }

  private buildGoogleSystemInstruction(messages: RequestMessage[]): GoogleSystemInstruction | undefined {
    const systemPrompt = this.collectGoogleSystemPrompt(messages)
    if (systemPrompt === '') {
      return undefined
    }
    return {
      parts: [{ text: systemPrompt }]
    }
  }

  private normalizeGoogleModelId(model: string): string {
    return model.trim().toLowerCase().replace(/^models\//, '')
  }

  private isGeminiThreeThinkingModel(model: string): boolean {
    return this.normalizeGoogleModelId(model).startsWith('gemini-3')
  }

  private isGeminiTwoFiveThinkingModel(model: string): boolean {
    const normalizedModel = this.normalizeGoogleModelId(model)
    return normalizedModel.startsWith('gemini-2.5') ||
      normalizedModel.startsWith('gemini-robotics')
  }

  private isGeminiTwoFiveProModel(model: string): boolean {
    return this.normalizeGoogleModelId(model).startsWith('gemini-2.5-pro')
  }

  private getGoogleThinkingLevel(level: ReasoningLevel): string | undefined {
    switch (level) {
      case ReasoningLevel.OFF:
        return 'minimal'
      case ReasoningLevel.AUTO:
        return undefined
      case ReasoningLevel.LOW:
        return 'low'
      case ReasoningLevel.XHIGH:
      case ReasoningLevel.HIGH:
        return 'high'
      case ReasoningLevel.MEDIUM:
      default:
        return 'medium'
    }
  }

  private getGoogleThinkingTokenLimit(model: string, level: ReasoningLevel): number | undefined {
    switch (level) {
      case ReasoningLevel.OFF:
        return this.isGeminiTwoFiveProModel(model) ? 128 : 0
      case ReasoningLevel.AUTO:
        return -1
      case ReasoningLevel.LOW:
        return 1024
      case ReasoningLevel.MEDIUM:
        return 16000
      case ReasoningLevel.HIGH:
        return 32000
      case ReasoningLevel.XHIGH:
        return 64000
      default:
        return undefined
    }
  }

  private getGoogleThinkingConfig(
    model: string,
    reasoningRequestStrategy: ReasoningRequestStrategy,
    reasoningLevel: ReasoningLevel
  ): GoogleThinkingConfig | undefined {
    if (reasoningRequestStrategy !== ReasoningRequestStrategy.GOOGLE_THINKING_CONFIG) {
      return undefined
    }

    if (this.isGeminiThreeThinkingModel(model)) {
      const config: GoogleThinkingConfig = {
        includeThoughts: reasoningLevel !== ReasoningLevel.OFF
      }
      const thinkingLevel = this.getGoogleThinkingLevel(reasoningLevel)
      if (thinkingLevel !== undefined) {
        config.thinkingLevel = thinkingLevel
      }
      return config
    }

    if (this.isGeminiTwoFiveThinkingModel(model)) {
      const thinkingTokenLimit = this.getGoogleThinkingTokenLimit(model, reasoningLevel)
      const config: GoogleThinkingConfig = {
        includeThoughts: reasoningLevel !== ReasoningLevel.OFF
      }
      if (thinkingTokenLimit !== undefined) {
        config.thinkingBudget = thinkingTokenLimit
      }
      return config
    }

    return undefined
  }

  private isIgnorableTailStreamError(error: string): boolean {
    const lower = error.toLowerCase()
    return lower.includes('stream read error') ||
      lower.includes('read error') ||
      error.includes('接收数据失败')
  }

  // 流式发送聊天请求
  streamChatRequest(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    onData: (content: string) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    temperature?: number,
    maxTokens?: number,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,  // 推理级别参数
    builtInResponsesTools?: BuiltInResponsesToolSpec[],
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void,
    imageFileCallbacks?: AIGeneratedImageFileCallbacks
  ): http.HttpRequest {
    this.resetThinkingState()

    const useOpenAIResponses = this.shouldUseOpenAIResponses(config)
    let url = this.buildChatUrl(config, model)
    const headers = this.buildHeaders(config)
    if (config.apiStyle !== ApiStyle.GOOGLE) {
      headers['Accept'] = 'text/event-stream'
    }
    const requestBody = this.buildRequestBody(
      config, messages, model, temperature, maxTokens, reasoningLevel,
      undefined, undefined, false, builtInResponsesTools
    )
    this.configureStreamState(config, model)

    if (config.apiStyle === ApiStyle.OPENAI) {
      if (useOpenAIResponses) {
        (requestBody as OpenAIResponsesRequestBody).stream = true
      } else {
        (requestBody as OpenAIRequestBody).stream = true
      }
    } else if (config.apiStyle === ApiStyle.ANTHROPIC) {
      (requestBody as AnthropicRequestBody).stream = true
    }
    if (config.apiStyle === ApiStyle.GOOGLE) {
      url = url.replace('generateContent', 'streamGenerateContent')
      // Gemini streamGenerateContent 默认返回 JSON 数组流,无法被现有 stream-line 解析器消费;
      // 显式指定 alt=sse 让服务端走 SSE,与 OpenAI/Anthropic 同口径。
      url += url.includes('?') ? '&alt=sse' : '?alt=sse'
    }

    console.info('AIApiService', `Streaming request to: ${url}`)
    console.info('AIApiService', `Request body: ${JSON.stringify(requestBody).substring(0, 500)}...`)

    const lineAccumulator = new StreamLineAccumulator(
      useOpenAIResponses,
      imageFileCallbacks,
      this.currentResponsesHostedImageMimeType,
      (itemId: string, outputIndex: number) => {
        this.emitHostedImageGenerationCompleted(itemId, outputIndex, onHostedToolEvent)
      }
    )

    return this.httpService.streamPost(
      url,
      JSON.stringify(requestBody),
      headers,
      (chunk: ArrayBuffer) => {
        try {
          const lines = lineAccumulator.append(new Uint8Array(chunk))
          for (let i = 0; i < lines.length; i++) {
            this.handleStreamLineBytes(config.apiStyle, useOpenAIResponses, lines[i],
              onData, onError, onReasoningData, onImageData, onSearchReferences, onHostedToolEvent)
          }
        } catch (e) {
          console.error('AIApiService', `Stream decode error: ${JSON.stringify(e)}`)
        }
      },
      (response) => {
        const remainingLine = lineAccumulator.flush()
        if (remainingLine !== null) {
          this.handleStreamLineBytes(config.apiStyle, useOpenAIResponses, remainingLine,
            onData, onError, onReasoningData, onImageData, onSearchReferences, onHostedToolEvent)
        }
        if (!response.success) {
          lineAccumulator.abortActiveImageFile()
          console.error('AIApiService', `Stream response error: ${response.errorMessage}`)
          onError(response.errorMessage)
          return
        }
        console.info('AIApiService', 'Stream completed successfully')
        onComplete()
      },
      (error) => {
        if (lineAccumulator.hasProtocolCompleted() && this.isIgnorableTailStreamError(error)) {
          console.warn('AIApiService', `Ignoring tail stream error after protocol completion: ${error}`)
          const remainingLine = lineAccumulator.flush()
          if (remainingLine !== null) {
            this.handleStreamLineBytes(config.apiStyle, useOpenAIResponses, remainingLine,
              onData, onError, onReasoningData, onImageData, onSearchReferences, onHostedToolEvent)
          }
          onComplete()
          return
        }
        lineAccumulator.abortActiveImageFile()
        console.error('AIApiService', `Stream error: ${error}`)
        onError(error)
      }
    )
  }

  // 流式发送聊天请求（支持 Function Calling）
  streamChatRequestWithTools(
    config: AIApiConfig,
    messages: RequestMessage[],
    model: string,
    onData: (content: string) => void,
    onComplete: (toolCalls: ToolCall[]) => void,
    onError: (error: string) => void,
    temperature?: number,
    maxTokens?: number,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    tools?: ToolDefinition[],
    toolChoice?: OpenAIResponsesToolChoice,
    onToolCallDelta?: (toolCallDeltas: ToolCallDelta[]) => void,
    builtInResponsesTools?: BuiltInResponsesToolSpec[],
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void,
    imageFileCallbacks?: AIGeneratedImageFileCallbacks
  ): http.HttpRequest {
    this.resetThinkingState()

    const useOpenAIResponses = this.shouldUseOpenAIResponses(config)
    let url = this.buildChatUrl(config, model)
    const headers = this.buildHeaders(config)
    if (config.apiStyle !== ApiStyle.GOOGLE) {
      headers['Accept'] = 'text/event-stream'
    }
    const requestBody = this.buildRequestBody(
      config, messages, model, temperature, maxTokens, reasoningLevel,
      tools, toolChoice, false, builtInResponsesTools
    )
    this.configureStreamState(config, model)

    if (config.apiStyle === ApiStyle.OPENAI) {
      if (useOpenAIResponses) {
        (requestBody as OpenAIResponsesRequestBody).stream = true
      } else {
        (requestBody as OpenAIRequestBody).stream = true
      }
    } else if (config.apiStyle === ApiStyle.ANTHROPIC) {
      (requestBody as AnthropicRequestBody).stream = true
    }
    if (config.apiStyle === ApiStyle.GOOGLE) {
      url = url.replace('generateContent', 'streamGenerateContent')
      // 同 streamChatRequest:Gemini 默认是 JSON 数组流,需要 alt=sse 走 SSE。
      url += url.includes('?') ? '&alt=sse' : '?alt=sse'
    }

    console.info('AIApiService', `Streaming request with tools to: ${url}`)
    console.info('AIApiService', `Request body: ${JSON.stringify(requestBody).substring(0, 500)}...`)

    const lineAccumulator = new StreamLineAccumulator(
      useOpenAIResponses,
      imageFileCallbacks,
      this.currentResponsesHostedImageMimeType,
      (itemId: string, outputIndex: number) => {
        this.emitHostedImageGenerationCompleted(itemId, outputIndex, onHostedToolEvent)
      }
    )

    return this.httpService.streamPost(
      url,
      JSON.stringify(requestBody),
      headers,
      (chunk: ArrayBuffer) => {
        try {
          const lines = lineAccumulator.append(new Uint8Array(chunk))
          for (let i = 0; i < lines.length; i++) {
            this.handleStreamLineWithToolsBytes(config.apiStyle, useOpenAIResponses, lines[i],
              onData, onError, onReasoningData, onImageData, onToolCallDelta, onSearchReferences, onHostedToolEvent)
          }
        } catch (e) {
          console.error('AIApiService', `Stream decode error: ${JSON.stringify(e)}`)
        }
      },
      (response) => {
        const remainingLine = lineAccumulator.flush()
        if (remainingLine !== null) {
          this.handleStreamLineWithToolsBytes(config.apiStyle, useOpenAIResponses, remainingLine,
            onData, onError, onReasoningData, onImageData, onToolCallDelta, onSearchReferences, onHostedToolEvent)
        }
        if (!response.success) {
          lineAccumulator.abortActiveImageFile()
          console.error('AIApiService', `Stream response error: ${response.errorMessage}`)
          onError(response.errorMessage)
          return
        }
        console.info('AIApiService', 'Stream completed successfully')
        const accumulatedToolCalls = this.getAccumulatedToolCalls()
        onComplete(accumulatedToolCalls)
      },
      (error) => {
        if (lineAccumulator.hasProtocolCompleted() && this.isIgnorableTailStreamError(error)) {
          console.warn('AIApiService', `Ignoring tail stream error after protocol completion: ${error}`)
          const remainingLine = lineAccumulator.flush()
          if (remainingLine !== null) {
            this.handleStreamLineWithToolsBytes(config.apiStyle, useOpenAIResponses, remainingLine,
              onData, onError, onReasoningData, onImageData, onToolCallDelta, onSearchReferences, onHostedToolEvent)
          }
          const accumulatedToolCalls = this.getAccumulatedToolCalls()
          onComplete(accumulatedToolCalls)
          return
        }
        lineAccumulator.abortActiveImageFile()
        console.error('AIApiService', `Stream error: ${error}`)
        onError(error)
      }
    )
  }

  // 处理流式响应行（支持工具调用回调）
  private handleStreamLineWithToolsBytes(
    apiStyle: ApiStyle,
    useOpenAIResponses: boolean,
    lineBytes: Uint8Array,
    onData: (content: string) => void,
    onError: (error: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onToolCallDelta?: (toolCallDeltas: ToolCallDelta[]) => void,
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): void {
    if (apiStyle === ApiStyle.OPENAI && useOpenAIResponses &&
      this.tryEmitResponsesImageDoneBytes(lineBytes, onImageData, onHostedToolEvent)) {
      return
    }
    this.handleStreamLineWithTools(
      apiStyle,
      useOpenAIResponses,
      this.decodeUtf8Bytes(lineBytes),
      onData,
      onError,
      onReasoningData,
      onImageData,
      onToolCallDelta,
      onSearchReferences,
      onHostedToolEvent
    )
  }

  private handleStreamLineWithTools(
    apiStyle: ApiStyle,
    useOpenAIResponses: boolean,
    line: string,
    onData: (content: string) => void,
    onError: (error: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onToolCallDelta?: (toolCallDeltas: ToolCallDelta[]) => void,
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): void {
    const trimmedLine = line.trim()
    if (trimmedLine === '') {
      return
    }
    if (trimmedLine === 'data: [DONE]' || trimmedLine === 'data:[DONE]' || trimmedLine === '[DONE]') {
      return
    }

    let jsonStr: string = ''
    if (trimmedLine.startsWith('data:')) {
      jsonStr = trimmedLine.substring(5).trim()
    } else if (trimmedLine.startsWith('{') || trimmedLine.startsWith('[')) {
      jsonStr = trimmedLine
    } else {
      return
    }

    if (jsonStr === '[DONE]') {
      return
    }

    if (apiStyle === ApiStyle.OPENAI && useOpenAIResponses &&
      this.tryEmitResponsesImageDoneLine(jsonStr, onImageData, onHostedToolEvent)) {
      return
    }

    try {
      const json = JSON.parse(jsonStr) as object
      this.emitStreamContentWithTools(apiStyle, useOpenAIResponses, json,
        onData, onError, onReasoningData, onImageData, onToolCallDelta, onSearchReferences, onHostedToolEvent)
    } catch (_e) {
      console.warn('AIApiService', `JSON parse error for line: ${jsonStr.substring(0, 100)}...`)
    }
  }

  // 发送流式内容（支持工具调用回调）
  private emitStreamContentWithTools(
    apiStyle: ApiStyle,
    useOpenAIResponses: boolean,
    json: object,
    onData: (content: string) => void,
    onError: (error: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onToolCallDelta?: (toolCallDeltas: ToolCallDelta[]) => void,
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): void {
    if (Array.isArray(json)) {
      const items = json as object[]
      for (let i = 0; i < items.length; i++) {
        const result = this.parseStreamChunk(apiStyle, useOpenAIResponses, items[i])
        if (result.errorMessage !== undefined && result.errorMessage !== '') {
          onError(result.errorMessage)
        }
        if (result.reasoningContent !== '' && onReasoningData) {
          onReasoningData(result.reasoningContent)
        }
        if (result.toolCallDeltas && result.toolCallDeltas.length > 0 && onToolCallDelta) {
          try {
            onToolCallDelta(result.toolCallDeltas)
          } catch (e) {
            console.error('AIApiService', `Error in onToolCallDelta callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.content !== '') {
          onData(result.content)
        }
        if (result.hostedToolEvent !== undefined && onHostedToolEvent) {
          try {
            onHostedToolEvent(result.hostedToolEvent)
          } catch (e) {
            console.error('AIApiService', `Error in onHostedToolEvent callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.imageData && result.imageMimeType && onImageData) {
          try {
            onImageData(result.imageData, result.imageMimeType, result.imageIsPartial === true)
          } catch (e) {
            console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.searchReferences !== undefined && result.searchReferences.length > 0 && onSearchReferences) {
          try {
            onSearchReferences(result.searchReferences)
          } catch (e) {
            console.error('AIApiService', `Error in onSearchReferences callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.reasoningItem !== undefined) {
          this.streamResponsesReasoningItems.push(result.reasoningItem)
        }
      }
      return
    }

    const result = this.parseStreamChunk(apiStyle, useOpenAIResponses, json)
    if (result.errorMessage !== undefined && result.errorMessage !== '') {
      onError(result.errorMessage)
    }
    if (result.reasoningContent !== '' && onReasoningData) {
      onReasoningData(result.reasoningContent)
    }
    if (result.toolCallDeltas && result.toolCallDeltas.length > 0 && onToolCallDelta) {
      try {
        onToolCallDelta(result.toolCallDeltas)
      } catch (e) {
        console.error('AIApiService', `Error in onToolCallDelta callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.content !== '') {
      onData(result.content)
    }
    if (result.hostedToolEvent !== undefined && onHostedToolEvent) {
      try {
        onHostedToolEvent(result.hostedToolEvent)
      } catch (e) {
        console.error('AIApiService', `Error in onHostedToolEvent callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.imageData && result.imageMimeType && onImageData) {
      try {
        onImageData(result.imageData, result.imageMimeType, result.imageIsPartial === true)
      } catch (e) {
        console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.searchReferences !== undefined && result.searchReferences.length > 0 && onSearchReferences) {
      try {
        onSearchReferences(result.searchReferences)
      } catch (e) {
        console.error('AIApiService', `Error in onSearchReferences callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.reasoningItem !== undefined) {
      this.streamResponsesReasoningItems.push(result.reasoningItem)
    }
  }

  // 解析 DeepSeek-R1 的 <think>...</think> 标签
  // 处理流式响应中标签可能跨块的情况
  private parseThinkingTags(text: string): StreamChunkResult {
    const result: StreamChunkResult = { content: '', reasoningContent: '' }

    // 将上次缓冲的部分标签与当前文本合并
    let remaining = this.partialTagBuffer + text
    this.partialTagBuffer = ''

    let contentParts: string[] = []
    let reasoningParts: string[] = []

    while (remaining.length > 0) {
      if (this.isInThinkingBlock) {
        const endIndex = remaining.indexOf('</think>')
        if (endIndex !== -1) {
          reasoningParts.push(remaining.substring(0, endIndex))
          remaining = remaining.substring(endIndex + 8)
          this.isInThinkingBlock = false
        } else {
          const partialEndTags = ['</think', '</thin', '</thi', '</th', '</t', '</', '<']
          let foundPartial = false
          for (let i = 0; i < partialEndTags.length; i++) {
            const partial = partialEndTags[i]
            if (remaining.endsWith(partial)) {
              this.partialTagBuffer = partial
              reasoningParts.push(remaining.substring(0, remaining.length - partial.length))
              remaining = ''
              foundPartial = true
              break
            }
          }
          if (!foundPartial) {
            reasoningParts.push(remaining)
            remaining = ''
          }
        }
      } else {
        const startIndex = remaining.indexOf('<think>')
        if (startIndex !== -1) {
          if (startIndex > 0) {
            contentParts.push(remaining.substring(0, startIndex))
          }
          remaining = remaining.substring(startIndex + 7)
          this.isInThinkingBlock = true
        } else {
          const partialStartTags = ['<think', '<thin', '<thi', '<th', '<t', '<']
          let foundPartial = false
          for (let i = 0; i < partialStartTags.length; i++) {
            const partial = partialStartTags[i]
            if (remaining.endsWith(partial)) {
              this.partialTagBuffer = partial
              contentParts.push(remaining.substring(0, remaining.length - partial.length))
              remaining = ''
              foundPartial = true
              break
            }
          }
          if (!foundPartial) {
            contentParts.push(remaining)
            remaining = ''
          }
        }
      }
    }

    result.content = contentParts.join('')
    result.reasoningContent = reasoningParts.join('')
    return result
  }

  private getOpenAIResponsesActionType(action?: OpenAIResponsesItemAction): string {
    if (action === undefined || action.type === undefined) {
      return ''
    }
    return action.type.trim()
  }

  private getOpenAIResponsesActionQueries(action?: OpenAIResponsesItemAction): string[] {
    if (action === undefined || action.queries === undefined || !Array.isArray(action.queries)) {
      return []
    }
    const queries: string[] = []
    const rawQueries = action.queries as string[]
    for (let i = 0; i < rawQueries.length; i++) {
      const item = rawQueries[i]
      if (typeof item === 'string' && item.trim() !== '') {
        queries.push(item.trim())
      }
    }
    return queries
  }

  private getOpenAIResponsesActionQuery(action?: OpenAIResponsesItemAction): string {
    if (action === undefined) {
      return ''
    }
    if (action.query !== undefined && action.query.trim() !== '') {
      return action.query.trim()
    }
    return this.getOpenAIResponsesActionQueries(action).join('\n')
  }

  private getOpenAIResponsesActionUrl(action?: OpenAIResponsesItemAction): string {
    if (action === undefined || action.url === undefined) {
      return ''
    }
    return action.url.trim()
  }

  private parseStreamChunk(apiStyle: ApiStyle, useOpenAIResponses: boolean, json: object): StreamChunkResult {
    const result: StreamChunkResult = { content: '', reasoningContent: '' }
    let hasReasoningDetails: boolean = false

    if (apiStyle === ApiStyle.OPENAI) {
      if (useOpenAIResponses) {
        const event = json as OpenAIResponsesStreamEvent
        if (event.type === 'response.output_text.delta' && event.delta !== undefined) {
          result.content = event.delta
        } else if ((event.type === 'response.reasoning_summary_text.delta' ||
          event.type === 'response.reasoning_text.delta') && event.delta !== undefined) {
          result.reasoningContent = event.delta
          result.reasoningIsStructured = true
        } else if ((event.type === 'response.output_item.added' || event.type === 'response.output_item.done') &&
          event.item !== undefined && event.item.type === 'function_call') {
          const item = event.item
          const index = this.getOpenAIResponsesToolCallIndex(event)
          const replaceArguments = event.type === 'response.output_item.done'
          result.toolCallDeltas = [
            this.upsertOpenAIResponsesToolCall(
              index,
              item.call_id !== undefined ? item.call_id : '',
              item.name !== undefined ? item.name : '',
              item.arguments !== undefined ? item.arguments : '',
              replaceArguments
            )
          ]
        } else if (event.type === 'response.output_item.done' &&
          event.item !== undefined && event.item.type === 'reasoning') {
          // 抓取完整 reasoning item 原文(含 encrypted_content),供下一轮请求原样回传
          result.reasoningItem = event.item
        } else if (event.type === 'response.output_item.done' &&
          event.item !== undefined && event.item.type === 'image_generation_call' &&
          event.item.result !== undefined && event.item.result !== '') {
          // 最终图(image_generation_call 完成)
          result.imageData = event.item.result
          result.imageMimeType = 'image/png'
          result.imageIsPartial = false
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.IMAGE_GENERATION_COMPLETED,
            event.item.id !== undefined ? event.item.id : '',
            event.output_index !== undefined ? event.output_index : -1
          )
        } else if (event.type === 'response.output_item.added' &&
          event.item !== undefined && event.item.type === 'image_generation_call') {
          // 生图开始
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.IMAGE_GENERATION_STARTED,
            event.item.id !== undefined ? event.item.id : '',
            event.output_index !== undefined ? event.output_index : -1
          )
        } else if (event.type === 'response.image_generation_call.partial_image' &&
          event.partial_image_b64 !== undefined && event.partial_image_b64 !== '') {
          // 渐进图: 让 onImageData 链路按"最新预览"覆盖式刷新
          result.imageData = event.partial_image_b64
          result.imageMimeType = 'image/png'
          result.imageIsPartial = true
          result.imagePartialIndex = event.partial_image_index !== undefined ?
            event.partial_image_index : -1
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.IMAGE_GENERATION_PARTIAL,
            event.item_id !== undefined ? event.item_id : '',
            event.output_index !== undefined ? event.output_index : -1,
            event.partial_image_index !== undefined ? event.partial_image_index : -1
          )
        } else if (event.type === 'response.image_generation_call.in_progress' ||
          event.type === 'response.image_generation_call.generating') {
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.IMAGE_GENERATION_STARTED,
            event.item_id !== undefined ? event.item_id : '',
            event.output_index !== undefined ? event.output_index : -1
          )
        } else if (event.type === 'response.image_generation_call.completed') {
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.IMAGE_GENERATION_COMPLETED,
            event.item_id !== undefined ? event.item_id : '',
            event.output_index !== undefined ? event.output_index : -1
          )
        } else if (event.type === 'response.output_item.added' &&
          event.item !== undefined && event.item.type === 'web_search_call') {
          // added 时 item.action 一般已经携带 query/url, 是最早能拿到关键词的位置
          const action = event.item.action
          const actionQuery = this.getOpenAIResponsesActionQuery(action)
          const actionUrl = this.getOpenAIResponsesActionUrl(action)
          const actionType = this.getOpenAIResponsesActionType(action)
          const actionQueries = this.getOpenAIResponsesActionQueries(action)
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.WEB_SEARCH_STARTED,
            event.item.id !== undefined ? event.item.id : '',
            event.output_index !== undefined ? event.output_index : -1,
            -1,
            actionQuery,
            actionUrl,
            actionType,
            actionQueries
          )
        } else if (event.type === 'response.web_search_call.in_progress') {
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.WEB_SEARCH_STARTED,
            event.item_id !== undefined ? event.item_id : '',
            event.output_index !== undefined ? event.output_index : -1
          )
        } else if (event.type === 'response.web_search_call.searching') {
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.WEB_SEARCH_SEARCHING,
            event.item_id !== undefined ? event.item_id : '',
            event.output_index !== undefined ? event.output_index : -1
          )
        } else if (event.type === 'response.web_search_call.completed' ||
          (event.type === 'response.output_item.done' &&
            event.item !== undefined && event.item.type === 'web_search_call')) {
          // done 时 action 一定完整, 兜底再取一次 (有些版本只在 done 上挂 action)
          const doneItem = event.item
          const doneAction = doneItem !== undefined ? doneItem.action : undefined
          const doneQuery = this.getOpenAIResponsesActionQuery(doneAction)
          const doneUrl = this.getOpenAIResponsesActionUrl(doneAction)
          const doneActionType = this.getOpenAIResponsesActionType(doneAction)
          const doneQueries = this.getOpenAIResponsesActionQueries(doneAction)
          result.hostedToolEvent = new HostedResponsesToolEvent(
            HostedResponsesToolEventKind.WEB_SEARCH_COMPLETED,
            event.item !== undefined && event.item.id !== undefined ? event.item.id :
              (event.item_id !== undefined ? event.item_id : ''),
            event.output_index !== undefined ? event.output_index : -1,
            -1,
            doneQuery,
            doneUrl,
            doneActionType,
            doneQueries
          )
        } else if (event.type === 'response.output_text.annotation.added' &&
          event.annotation !== undefined && event.annotation.type === 'url_citation' &&
          event.annotation.url !== undefined && event.annotation.url !== '') {
          // url_citation -> SearchReference, 唯一 id 用 url + index 拼接保持稳定
          const ann = event.annotation
          const annUrl: string = ann.url !== undefined ? ann.url : ''
          const annTitle: string = ann.title !== undefined && ann.title !== '' ? ann.title : annUrl
          const annIndex = event.annotation_index !== undefined ? event.annotation_index : 0
          const refId = `ws_${event.item_id !== undefined ? event.item_id : 'na'}_${annIndex}`
          const ref = new SearchReference(refId, annTitle, annUrl, '')
          result.searchReferences = [ref]
        } else if (event.type === 'response.function_call_arguments.delta' && event.delta !== undefined) {
          const index = this.getOpenAIResponsesToolCallIndex(event)
          result.toolCallDeltas = [
            this.upsertOpenAIResponsesToolCall(index, '', '', event.delta, false)
          ]
        } else if (event.type === 'response.function_call_arguments.done') {
          const index = this.getOpenAIResponsesToolCallIndex(event)
          result.toolCallDeltas = [
            this.upsertOpenAIResponsesToolCall(
              index,
              '',
              '',
              event.arguments !== undefined ? event.arguments : '',
              event.arguments !== undefined
            )
          ]
        } else if (event.type === 'response.completed') {
          result.finishReason = 'stop'
        } else if (event.type === 'error' && event.error !== undefined) {
          result.errorMessage = event.error.message
        }
        return result
      }

      const chunk = json as OpenAIStreamChunk
      if (chunk.choices && chunk.choices.length > 0) {
        const delta = chunk.choices[0].delta
        let rawContent = delta?.content || ''
        if (delta?.reasoning_details && delta.reasoning_details.length > 0) {
          hasReasoningDetails = true
          result.reasoningIsStructured = true
          const details: MiniMaxReasoningDetail[] = delta.reasoning_details
          for (let i = 0; i < details.length; i++) {
            const detail = details[i]
            if (detail.text && detail.text.length > 0) {
              const fullText = detail.text
              if (fullText.length > this.minimaxReasoningBuffer.length) {
                result.reasoningContent = fullText.substring(this.minimaxReasoningBuffer.length)
                this.minimaxReasoningBuffer = fullText
              }
            }
          }
          const incrementalContent = this.getMiniMaxIncrementalContent(rawContent)
          if (incrementalContent !== '') {
            const parsed = this.parseThinkingTags(incrementalContent)
            result.content = parsed.content
            if (result.reasoningContent === '' && parsed.reasoningContent !== '') {
              result.reasoningContent = parsed.reasoningContent
            }
          } else {
            result.content = ''
          }
        } else if (delta?.reasoning_content && delta.reasoning_content.length > 0) {
          result.reasoningContent = delta.reasoning_content
          result.reasoningIsStructured = true
          result.content = rawContent || ''
        } else if (delta?.reasoning && delta.reasoning.length > 0) {
          result.reasoningContent = delta.reasoning
          result.reasoningIsStructured = true
          result.content = rawContent || ''
        } else if (this.currentOpenAIStreamUsesCumulativeContent && rawContent !== '') {
          const incrementalContent = this.getMiniMaxIncrementalContent(rawContent)
          if (incrementalContent !== '') {
            const parsed = this.parseThinkingTags(incrementalContent)
            result.content = parsed.content
            if (parsed.reasoningContent !== '') {
              result.reasoningContent = parsed.reasoningContent
            }
          } else {
            result.content = ''
          }
        } else if (rawContent !== '') {
          const parsed = this.parseThinkingTags(rawContent)
          result.content = parsed.content
          result.reasoningContent = parsed.reasoningContent
        } else {
          result.content = rawContent
        }

        if (delta?.image_base64 && delta?.image_mime_type) {
          result.imageData = delta.image_base64
          result.imageMimeType = delta.image_mime_type
          console.info('AIApiService', `Received OpenAI image: ${delta.image_mime_type}, size: ${delta.image_base64.length}`)
        } else if (delta?.image_url) {
          result.imageData = delta.image_url
          result.imageMimeType = 'image/jpeg'
          console.info('AIApiService', `Received OpenAI image URL: ${delta.image_url}`)
        }

        if (delta?.tool_calls && delta.tool_calls.length > 0) {
          const toolCallDeltas: ToolCallDelta[] = []
          for (let i = 0; i < delta.tool_calls.length; i++) {
            const tc = delta.tool_calls[i]
            const incomingName = this.normalizeToolFunctionName(tc.function?.name || '')
            const incomingArgs = this.normalizeToolArgumentsChunk(tc.function?.arguments || '')
            const tcDelta: ToolCallDelta = {
              index: tc.index,
              id: tc.id,
              functionName: incomingName !== '' ? incomingName : undefined,
              arguments: incomingArgs !== '' ? incomingArgs : undefined
            }
            toolCallDeltas.push(tcDelta)

            let existingToolCall = this.streamToolCalls.get(tc.index)
            if (existingToolCall === undefined) {
              existingToolCall = new ToolCall('', '', '')
              this.streamToolCalls.set(tc.index, existingToolCall)
            }
            const incomingId = tc.id as string | null | undefined
            if (incomingId !== undefined && incomingId !== null && incomingId !== '') {
              existingToolCall.id = incomingId
            }
            if (incomingName !== '') {
              existingToolCall.functionName = this.mergeToolFunctionName(existingToolCall.functionName, incomingName)
            }
            if (incomingArgs !== '') {
              existingToolCall.arguments += incomingArgs
            }
          }
          result.toolCallDeltas = toolCallDeltas
        }

        const finishReason = chunk.choices[0].finish_reason
        if (finishReason !== undefined && finishReason !== null) {
          result.finishReason = finishReason
        }
      }
    } else if (apiStyle === ApiStyle.ANTHROPIC) {
      const chunk = json as AnthropicStreamChunk
      if (chunk.type === 'content_block_delta' && chunk.delta?.text) {
        result.content = chunk.delta.text
      }
      if (chunk.type === 'thinking_delta' && chunk.delta?.text) {
        result.reasoningContent = chunk.delta.text
        result.reasoningIsStructured = true
      }
      if (chunk.type === 'content_block_delta' && chunk.delta?.image_source) {
        result.imageData = chunk.delta.image_source.data
        result.imageMimeType = chunk.delta.image_source.media_type
        console.info('AIApiService', `Received Anthropic image: ${chunk.delta.image_source.media_type}, size: ${chunk.delta.image_source.data.length}`)
      }
    } else if (apiStyle === ApiStyle.GOOGLE) {
      const chunk = json as GoogleStreamChunk
      if (chunk.candidates && chunk.candidates.length > 0) {
        const candidate = chunk.candidates[0]
        result.finishReason = candidate.finishReason
        if (candidate.content && candidate.content.parts && candidate.content.parts.length > 0) {
          for (let i = 0; i < candidate.content.parts.length; i++) {
            const part = candidate.content.parts[i]
            if (part.text) {
              if (part.thought === true) {
                result.reasoningContent += part.text
              } else {
                result.content += part.text
              }
            } else if (part.inline_data) {
              result.imageData = part.inline_data.data
              result.imageMimeType = part.inline_data.mime_type
              console.info('AIApiService', `Received image: ${part.inline_data.mime_type}, size: ${part.inline_data.data.length}`)
            }
          }
        }
      }
    }
    if (!hasReasoningDetails && result.reasoningIsStructured === true &&
      result.reasoningContent !== '' && result.content !== '') {
      result.content = this.stripReasoningOverlap(result.content, result.reasoningContent, hasReasoningDetails)
    }
    return result
  }

  private stripReasoningOverlap(content: string, reasoning: string, aggressive: boolean = false): string {
    if (content === '' || reasoning === '') {
      return content
    }
    const lead = content.length - content.trimStart().length
    const c = content.substring(lead)
    const r = reasoning.trimStart()
    if (c === '' || r === '') {
      return content
    }

    const aggressiveMin = 6
    if (aggressive && r.length >= aggressiveMin) {
      if (c.startsWith(r)) {
        const stripped = content.substring(lead + r.length)
        return this.trimLeadingPunctuationAfterStrip(stripped)
      }
      if (r.startsWith(c) && c.length >= aggressiveMin) {
        return ''
      }
    }

    let i = 0
    const max = Math.min(c.length, r.length)
    while (i < max && c.charAt(i) === r.charAt(i)) {
      i++
    }
    if (i >= 16) {
      const stripped = content.substring(lead + i)
      return this.trimLeadingPunctuationAfterStrip(stripped)
    }
    if (i === c.length && c.length >= 8) {
      return ''
    }
    return content
  }

  private trimLeadingPunctuationAfterStrip(text: string): string {
    if (text === '') {
      return text
    }
    const trimmed = text.trimStart()
    if (trimmed === '') {
      return trimmed
    }
    const first = trimmed.charAt(0)
    const punctuations = [',', '，', '。', ';', '；', ':', '：']
    for (let i = 0; i < punctuations.length; i++) {
      if (first === punctuations[i]) {
        return trimmed.substring(1).trimStart()
      }
    }
    return trimmed
  }

  private handleStreamLineBytes(
    apiStyle: ApiStyle,
    useOpenAIResponses: boolean,
    lineBytes: Uint8Array,
    onData: (content: string) => void,
    onError: (error: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): void {
    if (apiStyle === ApiStyle.OPENAI && useOpenAIResponses &&
      this.tryEmitResponsesImageDoneBytes(lineBytes, onImageData, onHostedToolEvent)) {
      return
    }
    this.handleStreamLine(
      apiStyle,
      useOpenAIResponses,
      this.decodeUtf8Bytes(lineBytes),
      onData,
      onError,
      onReasoningData,
      onImageData,
      onSearchReferences,
      onHostedToolEvent
    )
  }

  private handleStreamLine(
    apiStyle: ApiStyle,
    useOpenAIResponses: boolean,
    line: string,
    onData: (content: string) => void,
    onError: (error: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): void {
    const trimmedLine = line.trim()
    if (trimmedLine === '') {
      return
    }
    if (trimmedLine === 'data: [DONE]' || trimmedLine === 'data:[DONE]' || trimmedLine === '[DONE]') {
      return
    }

    let jsonStr: string = ''
    if (trimmedLine.startsWith('data:')) {
      jsonStr = trimmedLine.substring(5).trim()
    } else if (trimmedLine.startsWith('{') || trimmedLine.startsWith('[')) {
      jsonStr = trimmedLine
    } else {
      return
    }

    if (jsonStr === '[DONE]') {
      return
    }

    if (apiStyle === ApiStyle.OPENAI && useOpenAIResponses &&
      this.tryEmitResponsesImageDoneLine(jsonStr, onImageData, onHostedToolEvent)) {
      return
    }

    try {
      const json = JSON.parse(jsonStr) as object
      this.emitStreamContent(apiStyle, useOpenAIResponses, json,
        onData, onError, onReasoningData, onImageData, onSearchReferences, onHostedToolEvent)
    } catch (_e) {
      console.warn('AIApiService', `JSON parse error for line: ${jsonStr.substring(0, 100)}...`)
    }
  }

  private emitStreamContent(
    apiStyle: ApiStyle,
    useOpenAIResponses: boolean,
    json: object,
    onData: (content: string) => void,
    onError: (error: string) => void,
    onReasoningData?: (content: string) => void,
    onImageData?: (base64Data: string, mimeType: string, isPartial: boolean) => void,
    onSearchReferences?: (references: SearchReference[]) => void,
    onHostedToolEvent?: (event: HostedResponsesToolEvent) => void
  ): void {
    if (Array.isArray(json)) {
      const items = json as object[]
      for (let i = 0; i < items.length; i++) {
        const result = this.parseStreamChunk(apiStyle, useOpenAIResponses, items[i])
        if (result.errorMessage !== undefined && result.errorMessage !== '') {
          onError(result.errorMessage)
        }
        if (result.content !== '') {
          onData(result.content)
        }
        if (result.reasoningContent !== '' && onReasoningData) {
          onReasoningData(result.reasoningContent)
        }
        if (result.hostedToolEvent !== undefined && onHostedToolEvent) {
          try {
            onHostedToolEvent(result.hostedToolEvent)
          } catch (e) {
            console.error('AIApiService', `Error in onHostedToolEvent callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.imageData && result.imageMimeType && onImageData) {
          try {
            onImageData(result.imageData, result.imageMimeType, result.imageIsPartial === true)
          } catch (e) {
            console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.searchReferences !== undefined && result.searchReferences.length > 0 && onSearchReferences) {
          try {
            onSearchReferences(result.searchReferences)
          } catch (e) {
            console.error('AIApiService', `Error in onSearchReferences callback: ${JSON.stringify(e)}`)
          }
        }
        if (result.reasoningItem !== undefined) {
          this.streamResponsesReasoningItems.push(result.reasoningItem)
        }
      }
      return
    }

    const result = this.parseStreamChunk(apiStyle, useOpenAIResponses, json)
    if (result.errorMessage !== undefined && result.errorMessage !== '') {
      onError(result.errorMessage)
    }
    if (result.content !== '') {
      onData(result.content)
    }
    if (result.reasoningContent !== '' && onReasoningData) {
      onReasoningData(result.reasoningContent)
    }
    if (result.hostedToolEvent !== undefined && onHostedToolEvent) {
      try {
        onHostedToolEvent(result.hostedToolEvent)
      } catch (e) {
        console.error('AIApiService', `Error in onHostedToolEvent callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.imageData && result.imageMimeType && onImageData) {
      try {
        onImageData(result.imageData, result.imageMimeType, result.imageIsPartial === true)
      } catch (e) {
        console.error('AIApiService', `Error in onImageData callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.searchReferences !== undefined && result.searchReferences.length > 0 && onSearchReferences) {
      try {
        onSearchReferences(result.searchReferences)
      } catch (e) {
        console.error('AIApiService', `Error in onSearchReferences callback: ${JSON.stringify(e)}`)
      }
    }
    if (result.reasoningItem !== undefined) {
      this.streamResponsesReasoningItems.push(result.reasoningItem)
    }
  }
}

// 导出单例实例获取方法
export function getAIApiService(): AIApiService {
  return AIApiService.getInstance()
}
