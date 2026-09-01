import {
  AttachmentType,
  MessageAttachment,
  ModelInfo,
  ModelProvider,
  OutputMode,
  ToolConfig,
  ToolDefinition,
  ToolFunction,
  ToolParameterProperty,
  ToolParameters,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import { ToolExecutor, RegisteredTool, getToolRegistry } from '../services/ToolRegistry'
import { getWebSearchService, SearchResult, WebSearchResult } from '../services/WebSearchService'
import {
  ASK_USER_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MUSIC_GENERATION_TOOL_ID,
  LEGACY_WEB_SEARCH_TOOL_ID,
  SCRAPE_WEB_TOOL_ID,
  SEARCH_WEB_TOOL_ID,
  CHILD_PROFILE_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID,
  HANDWRITING_PRACTICE_TOOL_ID,
  CATEGORIZATION_TOOL_ID,
  VERTICAL_MATH_TOOL_ID,
  MAZE_TOOL_ID,
  SUDOKU_TOOL_ID,
  PICTURE_VOCAB_TOOL_ID,
  GRANT_STAR_TOOL_ID
} from '../utils/SearchToolIdentityUtils'
import { i18n } from '@kit.LocalizationKit'
import {
  GeneratedMedia,
  GeneratedMediaType,
  ImageAspectRatio,
  ImageGenerationItem,
  ImageGenerationQuality,
  ImageGenerationRequest
} from '../models/ImageGenerationModels'
import { getImageGenerationService } from '../services/ImageGenerationService'
import { getMusicGenerationService, hexToBase64 } from '../services/MusicGenerationService'
import {
  MusicGenerationAudioSetting,
  MusicGenerationBitrate,
  MusicGenerationChannel,
  MusicGenerationOutputFormat,
  MusicGenerationRequest,
  MusicGenerationSampleRate,
  resolveAudioExtension
} from '../models/MusicGenerationModels'
import { getAttachmentStorageService } from '../services/AttachmentStorageService'
import { getGeneratedMediaRepository } from '../services/GeneratedMediaRepository'
import { getAppSettingsState } from '../state/AppSettingsState'
import { getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'
import { getChildProfileService, ChildProfileService, ChildKnowledgeProfile } from '../services/ChildProfileService'
import { evaluateMathExpression } from '../utils/MathExpressionParser'


// search_web 工具参数接口
interface SearchWebArgs {
  query: string
}

// scrape_web 工具参数接口
interface ScrapeWebArgs {
  url?: string
  query?: string
}

// 搜索结果项接口（用于格式化输出）
class SearchResultItem {
  index: number = 0
  id: string = ''
  title: string = ''
  url: string = ''
  snippet: string = ''

  constructor(index: number, id: string, title: string, url: string, snippet: string) {
    this.index = index
    this.id = id
    this.title = title
    this.url = url
    this.snippet = snippet
  }
}


// 搜索结果输出接口
class SearchResultOutput {
  query: string = ''
  searchEngine: string = ''
  results: SearchResultItem[] = []
  summary: string = ''

  constructor(query: string, searchEngine: string, results: SearchResultItem[], summary: string) {
    this.query = query
    this.searchEngine = searchEngine
    this.results = results
    this.summary = summary
  }
}

// 错误输出接口
class ErrorOutput {
  error: string = ''

  constructor(error: string) {
    this.error = error
  }
}

class WebSearchResultFormatter {
  buildSnippet(content: string): string {
    const trimmed = content.replace(/\s+/g, ' ').trim()
    if (trimmed.length <= 200) {
      return trimmed
    }
    return trimmed.substring(0, 200) + '...'
  }

  formatWebResult(result: WebSearchResult): string {
    if (!result.success) {
      return JSON.stringify(new ErrorOutput(result.errorMessage))
    }

    const output = new SearchResultOutput(
      result.url,
      result.sourceName !== '' ? result.sourceName : 'URL抓取',
      [new SearchResultItem(
        1,
        `ref_${Date.now()}`,
        result.title,
        result.url,
        this.buildSnippet(result.content)
      )],
      `标题: ${result.title}\n来源: ${result.url}\n\n${result.content}`
    )
    return JSON.stringify(output)
  }

  formatResult(result: SearchResult): string {
    if (!result.success) {
      return JSON.stringify(new ErrorOutput(result.errorMessage))
    }

    // 返回结构化的搜索结果（包含 index 和 id）
    const formattedResults: SearchResultItem[] = []
    for (let i = 0; i < result.references.length; i++) {
      const ref = result.references[i]
      formattedResults.push(new SearchResultItem(
        i + 1,  // index 从 1 开始
        ref.id,
        ref.title,
        ref.url,
        ref.snippet
      ))
    }

    const output = new SearchResultOutput(
      result.query,
      result.searchEngine,
      formattedResults,
      result.contentForAI
    )
    return JSON.stringify(output)
  }
}

// search_web 执行器
class SearchWebExecutor implements ToolExecutor {
  private formatter: WebSearchResultFormatter = new WebSearchResultFormatter()

  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as SearchWebArgs
      if (params.query === undefined || params.query.trim() === '') {
        return JSON.stringify(new ErrorOutput('搜索关键词不能为空'))
      }

      const query = params.query.trim()
      console.info('SearchWebExecutor', `Executing web search: ${query}`)
      const searchResult = await getWebSearchService().search(query)
      return this.formatter.formatResult(searchResult)
    } catch (error) {
      console.error('SearchWebExecutor', `Search error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`搜索失败: ${JSON.stringify(error)}`))
    }
  }
}

// scrape_web 执行器
class ScrapeWebExecutor implements ToolExecutor {
  private formatter: WebSearchResultFormatter = new WebSearchResultFormatter()

  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as ScrapeWebArgs
      const rawUrl = params.url !== undefined ? params.url : (params.query !== undefined ? params.query : '')
      if (rawUrl === undefined || rawUrl.trim() === '') {
        return JSON.stringify(new ErrorOutput('网页 URL 不能为空'))
      }

      const url = rawUrl.trim()
      console.info('ScrapeWebExecutor', `Executing web scrape: ${url}`)
      const webResult = await getWebSearchService().fetchUrlContent(url)
      return this.formatter.formatWebResult(webResult)
    } catch (error) {
      console.error('ScrapeWebExecutor', `Scrape error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`网页读取失败: ${JSON.stringify(error)}`))
    }
  }
}

// 兼容旧 web_search：历史调用和旧 provider 输出仍可执行，但新请求不再注入该工具。
class LegacyWebSearchExecutor implements ToolExecutor {
  private formatter: WebSearchResultFormatter = new WebSearchResultFormatter()

  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as SearchWebArgs
      if (params.query === undefined || params.query.trim() === '') {
        return JSON.stringify(new ErrorOutput('搜索关键词不能为空'))
      }

      const query = params.query.trim()
      const webSearchService = getWebSearchService()
      const extractedUrl = webSearchService.extractUrl(query)
      const isPureUrl = extractedUrl !== null && extractedUrl === query
      if (isPureUrl && extractedUrl !== null) {
        console.info('LegacyWebSearchExecutor', `Executing web scrape: ${extractedUrl}`)
        const webResult = await webSearchService.fetchUrlContent(extractedUrl)
        return this.formatter.formatWebResult(webResult)
      }

      console.info('LegacyWebSearchExecutor', `Executing web search: ${query}`)
      const searchResult = await webSearchService.search(query)
      return this.formatter.formatResult(searchResult)
    } catch (error) {
      console.error('LegacyWebSearchExecutor', `Search error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`搜索失败: ${JSON.stringify(error)}`))
    }
  }
}

function createSearchWebToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('query', new ToolParameterProperty(
    'string',
    '聚焦搜索关键词。用于搜索外部实时、特定或需要验证的信息，不要传入整段用户问题。'
  ))
  parameters.addRequired('query')

  const func = new ToolFunction(
    SEARCH_WEB_TOOL_ID,
    'Search the web for up-to-date, specific, or verifiable information. First decide whether web access is truly needed; use your own knowledge for common stable facts and pure generation tasks. Each search has real cost, so generate focused keywords and run multiple searches only when more evidence is needed. Cite used sources as standard Markdown links like [title](url), not bare [1] or [2] numbers.',
    parameters
  )

  return new ToolDefinition(func)
}

function createScrapeWebToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('url', new ToolParameterProperty(
    'string',
    '要读取的网页 URL。用户给出 URL 或要求总结、分析某个网页时，原样传入 URL。'
  ))
  parameters.addRequired('url')

  const func = new ToolFunction(
    SCRAPE_WEB_TOOL_ID,
    'Scrape a URL for detailed page content. Use this when the user provides a specific URL, asks to read or summarize a page, or search snippets are insufficient. Avoid using it for common questions unless the user asks.',
    parameters
  )

  return new ToolDefinition(func)
}

function createLegacyWebSearchToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('query', new ToolParameterProperty(
    'string',
    '聚焦搜索关键词或网页 URL。'
  ))
  parameters.addRequired('query')

  const func = new ToolFunction(
    LEGACY_WEB_SEARCH_TOOL_ID,
    '兼容旧版联网搜索工具。新请求会使用 search_web 或 scrape_web。',
    parameters
  )

  return new ToolDefinition(func)
}

function createSearchToolConfig(id: string, name: string, description: string): ToolConfig {
  return new ToolConfig(
    id,
    name,
    description,
    null,
    false,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    id,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== ask_user 工具 =====
// ask_user 是"人机交互工具"(human-in-the-loop): 模型提出问题, UI 展示 AskUserCard,
// 用户填完答案提交后, 答案 JSON 作为 tool_result 回传给模型。
// 这里只注册定义, 执行器是占位; 真正的等待/回收答案逻辑在 ToolExecutionService.handleAskUser
// 里拦截 ask_user 函数名并走 answerCallback 完成。

// 占位执行器: 不应被实际调用, 一旦被调用说明 ToolExecutionService 的分流失效
class AskUserExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    return JSON.stringify(new ErrorOutput('ask_user should be resolved by the user, not executed by the tool runtime'))
  }
}

function createAskUserToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  // questions[] 是对象数组 + enum, ToolParameters.addProperty 不足以表达,
  // 通过 JSON 字符串反序列化成 Object 再 setRawSchema, 避开 ArkTS "无类型对象字面量" 限制。
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "questions": {
        "type": "array",
        "description": "1-3 question prompts to clarify the user's intent. Each item must include id, question, selection_type; include options[] when selection_type is single or multi.",
        "minItems": 1,
        "maxItems": 3,
        "items": {
          "type": "object",
          "properties": {
            "id": {
              "type": "string",
              "description": "Unique identifier used to key the answer in the returned JSON, e.g. 'q1' or 'format'."
            },
            "question": {
              "type": "string",
              "description": "Concise question text shown to the user, 10-60 Chinese characters or ~100 English characters."
            },
            "selection_type": {
              "type": "string",
              "enum": ["single", "multi", "text"],
              "description": "single=user must pick one from options; multi=user may pick multiple from options; text=free-form input."
            },
            "options": {
              "type": "array",
              "description": "Required when selection_type is single or multi; optional hints when selection_type is text.",
              "items": { "type": "string" }
            }
          },
          "required": ["id", "question", "selection_type"]
        }
      }
    },
    "required": ["questions"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    ASK_USER_TOOL_ID,
    'Present an interactive question card on screen for the user (typically a child) to answer. Use this INSTEAD of writing questions in plain text and then answering them yourself — plain-text questions cannot capture the user\'s answer, only this tool can. selection_type=single (one answer from options, with optional custom answer), multi (multiple answers from options), text (free-form input + optional chip hints). Batch 1-3 related questions in a single call to avoid multiple back-and-forth rounds. Each question needs a unique id, concise question text, selection_type, and options[] when selection_type is single or multi. The tool result will be a JSON object of the user answers keyed by question id; use those answers to continue your reply.',
    parameters
  )

  return new ToolDefinition(func)
}

function createAskUserToolConfig(): ToolConfig {
  // permissionLevel 用 READ: ask_user 不是"写外部状态", 是"等用户答复",
  // 让 ToolExecutionService 早期 isAskUserFunctionName 分流直接走 handleAskUser,
  // 不走通用 write 审批 sheet, 避免两个弹窗争抢用户注意力。
  //
  // enabled 默认 true: 零配置即可用, 用户在"设置 > 工具服务 > 内置工具"里可显式关闭,
  // 关闭后 ChatPage.rebuildAvailableChatTools 会把它过滤出 availableChatTools,
  // AI 便感知不到该工具, 不会再发起调用。
  return new ToolConfig(
    ASK_USER_TOOL_ID,
    '向用户提问',
    '模型需要澄清时向你发起的提问, 你的答复会作为工具结果回给模型继续生成。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    ASK_USER_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== get_time_info 工具 =====
// 给模型提供"当前设备本地时间"的能力。无参数, 调用后返回 year/month/day/weekday/datetime/timezone 等字段。
// 与 rikkahub LocalTools.kt 的 timeTool 对齐, 但用 ArkTS 标准 Date + @kit.LocalizationKit 实现。

class TimeInfoOutput {
  year: number = 0
  month: number = 0
  day: number = 0
  weekday: string = ''
  weekday_en: string = ''
  weekday_index: number = 0
  date: string = ''
  time: string = ''
  datetime: string = ''
  timezone: string = ''
  utc_offset: string = ''
  timestamp_ms: number = 0
}

const WEEKDAY_NAMES_ZH: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
const WEEKDAY_NAMES_EN: string[] = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

function buildUtcOffset(now: Date): string {
  // getTimezoneOffset 返回 UTC - local 的分钟数, 东八区为 -480, 这里取反得到 +480
  const offsetMinutes = -now.getTimezoneOffset()
  const sign = offsetMinutes >= 0 ? '+' : '-'
  const abs = Math.abs(offsetMinutes)
  return `${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`
}

function resolveTimezoneId(): string {
  try {
    return i18n.getTimeZone().getID()
  } catch (e) {
    return ''
  }
}

class GetTimeInfoExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    const now = new Date()
    const output = new TimeInfoOutput()
    output.year = now.getFullYear()
    output.month = now.getMonth() + 1
    output.day = now.getDate()
    const weekdayJs = now.getDay() // 0=Sunday ... 6=Saturday
    output.weekday = WEEKDAY_NAMES_ZH[weekdayJs]
    output.weekday_en = WEEKDAY_NAMES_EN[weekdayJs]
    // ISO 8601: 1=Monday ... 7=Sunday
    output.weekday_index = weekdayJs === 0 ? 7 : weekdayJs
    output.date = `${output.year}-${pad2(output.month)}-${pad2(output.day)}`
    output.time = `${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}`
    output.utc_offset = buildUtcOffset(now)
    output.datetime = `${output.date}T${output.time}${output.utc_offset}`
    const tzId = resolveTimezoneId()
    output.timezone = tzId !== '' ? tzId : `UTC${output.utc_offset}`
    output.timestamp_ms = now.getTime()
    return JSON.stringify(output)
  }
}

function createGetTimeInfoToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  // 无参数, 但保留显式 type=object 结构, 避免某些 provider 校验空 schema 抱怨
  parameters.setRawSchema(JSON.parse('{"type":"object","properties":{}}') as Object)

  const func = new ToolFunction(
    GET_TIME_INFO_TOOL_ID,
    'Get the current local date and time from the device. Returns year/month/day, weekday, ISO date/time strings, timezone, UTC offset, and millisecond timestamp. Call this whenever the user asks "what time is it", needs to compute relative dates, or schedules anything tied to "today"/"now".',
    parameters
  )

  return new ToolDefinition(func)
}

function createGetTimeInfoToolConfig(): ToolConfig {
  // 纯读 + 无副作用, READ 权限即可, 不需要审批; 默认 enabled=true, 仍由助手白名单决定 AI 是否能看到。
  return new ToolConfig(
    GET_TIME_INFO_TOOL_ID,
    '获取当前时间',
    '返回设备当前本地日期、时间、时区、时间戳等信息, 供模型回答与时间相关的问题。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    GET_TIME_INFO_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== image_generation 工具 =====
// 让 AI 对话模型调用图片生成能力, 使用用户已配置的图片生成模型(默认 MiniMax)。
// 执行器调用现有的 ImageGenerationService, 生成结果保存到本地文件并在聊天中显示缩略图。

interface ImageGenerationArgs {
  prompt: string
  aspect_ratio?: string
  number_of_images?: number
  quality?: string
  style?: string
}

class ImageGenerationOutputItem {
  filePath: string = ''
  mimeType: string = ''
  prompt: string = ''
  revisedPrompt: string = ''

  constructor(filePath: string, mimeType: string, prompt: string, revisedPrompt: string) {
    this.filePath = filePath
    this.mimeType = mimeType
    this.prompt = prompt
    this.revisedPrompt = revisedPrompt
  }
}

class ImageGenerationOutput {
  images: ImageGenerationOutputItem[] = []

  constructor(images: ImageGenerationOutputItem[]) {
    this.images = images
  }
}

class ImageGenErrorOutput {
  error: string = ''

  constructor(error: string) {
    this.error = error
  }
}

// ===== 音乐生成参数/输出 =====

interface MusicGenerationArgs {
  prompt?: string
  lyrics?: string
  audio_format?: string
  sample_rate?: number
  bitrate?: number
  channel?: number
}

class MusicGenerationOutputItem {
  filePath: string = ''
  mimeType: string = ''
  prompt: string = ''
  audioLengthMs: number = 0

  constructor(filePath: string, mimeType: string, prompt: string, audioLengthMs: number) {
    this.filePath = filePath
    this.mimeType = mimeType
    this.prompt = prompt
    this.audioLengthMs = audioLengthMs
  }
}

class MusicGenerationOutput {
  audio: MusicGenerationOutputItem[] = []

  constructor(audio: MusicGenerationOutputItem[]) {
    this.audio = audio
  }
}

class MusicGenErrorOutput {
  error: string = ''

  constructor(error: string) {
    this.error = error
  }
}

function resolveExtension(mimeType: string): string {
  if (mimeType === 'image/jpeg') {
    return '.jpg'
  }
  if (mimeType === 'image/webp') {
    return '.webp'
  }
  return '.png'
}

class ImageGenerationExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as ImageGenerationArgs
      if (params.prompt === undefined || params.prompt.trim() === '') {
        return JSON.stringify(new ImageGenErrorOutput('图片描述不能为空'))
      }

      const prompt = params.prompt.trim()
      const numberOfImages = Math.min(Math.max(params.number_of_images !== undefined ? params.number_of_images : 1, 1), 4)

      // 解析宽高比
      let aspectRatio = ImageAspectRatio.SQUARE
      const ratioStr = (params.aspect_ratio !== undefined ? params.aspect_ratio : '1:1').trim()
      if (ratioStr === '16:9') {
        aspectRatio = ImageAspectRatio.LANDSCAPE
      } else if (ratioStr === '9:16') {
        aspectRatio = ImageAspectRatio.PORTRAIT
      }

      // 解析图片生成 provider/model
      const state = getAppSettingsState()
      const defaultImage = state.defaultImageModel
      let provider: ModelProvider | null = null
      let model: ModelInfo | null = null

      // 从默认图片模型配置中查找
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
        return JSON.stringify(new ImageGenErrorOutput('未找到可用的图片生成模型, 请先在设置中配置图片生成服务商'))
      }

      console.info('ImageGenerationExecutor',
        `Generating: prompt="${prompt}", provider=${provider.id}, model=${model.id}, n=${numberOfImages}, ratio=${aspectRatio}`)

      // 构建请求 & 调用服务
      const request = new ImageGenerationRequest()
      request.providerId = provider.id
      request.modelId = model.id
      request.prompt = prompt
      request.numberOfImages = numberOfImages
      request.aspectRatio = aspectRatio
      if (params.quality !== undefined && params.quality.trim() !== '') {
        request.quality = params.quality.trim() as ImageGenerationQuality
      }
      if (params.style !== undefined && params.style.trim() !== '') {
        request.styleType = params.style.trim()
      }

      const result = await getImageGenerationService().generateImage(provider, model, request)
      const outputItems: ImageGenerationOutputItem[] = []
      const attachmentService = getAttachmentStorageService()
      const repository = getGeneratedMediaRepository()
      const itemPrompt = request.prompt

      for (let i = 0; i < result.items.length; i++) {
        const item: ImageGenerationItem = result.items[i]
        const id = `gen_${Date.now()}_${i}_${Math.floor(Math.random() * 100000)}`
        const attachment = new MessageAttachment(
          id,
          AttachmentType.IMAGE,
          `${id}${resolveExtension(item.mimeType)}`,
          '',
          item.mimeType,
          0
        )
        attachment.base64Data = item.base64Data
        const filePath = await attachmentService.saveAttachment(attachment)
        attachment.base64Data = ''
        if (filePath === '') {
          console.error('ImageGenerationExecutor', `Failed to save image ${i}`)
          continue
        }

        // 持久化到图库
        const media = new GeneratedMedia()
        media.id = id
        media.type = GeneratedMediaType.IMAGE_GENERATION
        media.prompt = itemPrompt
        media.providerId = provider!.id
        media.providerName = provider!.name
        media.modelId = model!.id
        media.modelName = model!.name !== '' ? model!.name : model!.id
        media.filePath = filePath
        media.mimeType = item.mimeType
        media.aspectRatio = aspectRatio
        media.revisedPrompt = item.revisedPrompt
        media.createdAt = Date.now()
        await repository.insert(media)

        outputItems.push(new ImageGenerationOutputItem(
          filePath,
          item.mimeType,
          itemPrompt,
          item.revisedPrompt
        ))
      }

      if (outputItems.length === 0) {
        return JSON.stringify(new ImageGenErrorOutput('图片生成失败, 所有图片保存出错'))
      }

      return JSON.stringify(new ImageGenerationOutput(outputItems))
    } catch (error) {
      const err = error as BusinessError
      const detail = err.message !== undefined && err.message !== '' ? err.message : String(error)
      console.error('ImageGenerationExecutor', `Image generation error: ${detail}`)
      return JSON.stringify(new ImageGenErrorOutput(`图片生成失败: ${detail}`))
    }
  }
}

function createImageGenerationToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('prompt', new ToolParameterProperty(
    'string',
    'Detailed description of the image to generate, in the user\'s language. Include style, subject, composition, colors, and mood. ~20-200 characters.'
  ))
  parameters.addProperty('aspect_ratio', new ToolParameterProperty(
    'string',
    'Image aspect ratio. "1:1" for square, "16:9" for widescreen landscape, "9:16" for portrait/vertical.'
  ))
  parameters.addProperty('number_of_images', new ToolParameterProperty(
    'integer',
    'Number of images to generate, between 1 and 4. Default 1.'
  ))
  parameters.addProperty('quality', new ToolParameterProperty(
    'string',
    'Image quality: "auto", "low", "medium", or "high". Leave as default "auto" unless the user specifically requests a quality level.'
  ))
  parameters.addProperty('style', new ToolParameterProperty(
    'string',
    'Optional image style. Must be one of the MiniMax-supported Chinese values: 漫画, 元气, 中世纪, 水彩. If omitted or unknown, the image is generated without a style hint.'
  ))
  parameters.addRequired('prompt')

  const func = new ToolFunction(
    IMAGE_GENERATION_TOOL_ID,
    'Generate images from text descriptions. Use this when the user asks you to draw, create, or generate an image, picture, illustration, or artwork. The generated images will be displayed directly in the chat. Describe the desired image in detail including subject, style, composition, colors, and mood.',
    parameters
  )

  return new ToolDefinition(func)
}

function createImageGenerationToolConfig(): ToolConfig {
  return new ToolConfig(
    IMAGE_GENERATION_TOOL_ID,
    '生成图片',
    '根据文本描述生成图片, 结果直接展示在对话中。使用已配置的图片生成服务商(如 MiniMax)。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    IMAGE_GENERATION_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== 音乐生成 Executor =====
// 与图片生成执行器同构:
// 1. 解析 args, 校验 prompt 非空
// 2. 从默认音乐生成配置中查找 provider/model, 否则扫描所有 provider 兜底
// 3. 调用 MusicGenerationService.generateMusic
// 4. hex → base64 → AttachmentStorageService.saveAttachment
// 5. 返回 MusicGenerationOutput (含文件路径) 或 MusicGenErrorOutput

class MusicGenerationExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = this.parseArgs(args)
      if (params.prompt === undefined || params.prompt.trim() === '') {
        return JSON.stringify(new MusicGenErrorOutput('音乐描述不能为空'))
      }

      const prompt = params.prompt.trim()
      const lyrics = params.lyrics !== undefined ? params.lyrics : ''

      // 解析音频参数
      const audioFormat = this.parseAudioFormat(params.audio_format)
      const audioSetting = new MusicGenerationAudioSetting()
      audioSetting.format = audioFormat
      const parsedSampleRate = this.parseSampleRate(params.sample_rate)
      if (parsedSampleRate !== null) {
        audioSetting.sampleRate = parsedSampleRate
      }
      const parsedBitrate = this.parseBitrate(params.bitrate)
      if (parsedBitrate !== null) {
        audioSetting.bitrate = parsedBitrate
      }
      const parsedChannel = this.parseChannel(params.channel)
      if (parsedChannel !== null) {
        audioSetting.channel = parsedChannel
      }

      // 解析音乐生成 provider/model
      const state = getAppSettingsState()
      const defaultMusic = state.defaultMusicModel
      let provider: ModelProvider | null = null
      let model: ModelInfo | null = null

      if (defaultMusic.providerId !== '' && defaultMusic.modelId !== '') {
        for (let i = 0; i < state.providers.length; i++) {
          const p = state.providers[i]
          if (p.id === defaultMusic.providerId) {
            for (let j = 0; j < p.models.length; j++) {
              const m = p.models[j]
              if (m.id === defaultMusic.modelId && getEffectiveOutputMode(m) === OutputMode.MUSIC) {
                provider = p
                model = m
                break
              }
            }
            break
          }
        }
      }

      // 回退: 扫描所有 provider 找到第一个可用的音乐模型
      if (provider === null || model === null) {
        for (let i = 0; i < state.providers.length; i++) {
          const p = state.providers[i]
          for (let j = 0; j < p.models.length; j++) {
            const m = p.models[j]
            if (m.isEnabled && getEffectiveOutputMode(m) === OutputMode.MUSIC) {
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
        return JSON.stringify(new MusicGenErrorOutput('未找到可用的音乐生成模型, 请先在设置中配置音乐生成服务商'))
      }

      console.info('MusicGenerationExecutor',
        `Generating: provider=${provider.id}, model=${model.id}, lyricsLen=${lyrics.length}, format=${audioFormat}`)

      const request = new MusicGenerationRequest()
      request.providerId = provider.id
      request.modelId = model.id
      request.prompt = prompt
      if (lyrics.trim() !== '') {
        request.lyrics = lyrics
      }
      request.audioSetting = audioSetting

      const result = await getMusicGenerationService().generateMusic(provider, model, request)
      const outputItems: MusicGenerationOutputItem[] = []
      const attachmentService = getAttachmentStorageService()
      const itemPrompt = request.prompt

      for (let i = 0; i < result.items.length; i++) {
        const item = result.items[i]
        const id = `music_${Date.now()}_${i}_${Math.floor(Math.random() * 100000)}`
        const ext = resolveAudioExtension(item.audioFormat)
        const fileName = `${id}${ext}`
        let base64Data = ''
        try {
          base64Data = hexToBase64(item.hexData)
        } catch (error) {
          console.error('MusicGenerationExecutor', `Failed to decode audio hex: ${JSON.stringify(error)}`)
          continue
        }
        const attachment = new MessageAttachment(
          id,
          AttachmentType.FILE,
          fileName,
          '',
          item.mimeType,
          0
        )
        attachment.base64Data = base64Data
        const filePath = await attachmentService.saveAttachment(attachment)
        attachment.base64Data = ''
        if (filePath === '') {
          console.error('MusicGenerationExecutor', `Failed to save audio ${i}`)
          continue
        }

        outputItems.push(new MusicGenerationOutputItem(
          filePath,
          item.mimeType,
          itemPrompt,
          item.audioLengthMs
        ))
      }

      if (outputItems.length === 0) {
        return JSON.stringify(new MusicGenErrorOutput('音乐生成失败, 所有音频保存出错'))
      }

      return JSON.stringify(new MusicGenerationOutput(outputItems))
    } catch (error) {
      console.error('MusicGenerationExecutor', `Music generation error: ${JSON.stringify(error)}`)
      return JSON.stringify(new MusicGenErrorOutput(`音乐生成失败: ${JSON.stringify(error)}`))
    }
  }

  private parseArgs(args: string): MusicGenerationArgs {
    const parsed = JSON.parse(args) as MusicGenerationArgs
    return parsed
  }

  private parseAudioFormat(raw: string | undefined): MusicGenerationOutputFormat {
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

  private parseSampleRate(raw: number | undefined): MusicGenerationSampleRate | null {
    if (raw === undefined) {
      return null
    }
    if (raw === 16000) {
      return MusicGenerationSampleRate.RATE_16000
    }
    if (raw === 24000) {
      return MusicGenerationSampleRate.RATE_24000
    }
    if (raw === 44100) {
      return MusicGenerationSampleRate.RATE_44100
    }
    return MusicGenerationSampleRate.RATE_32000
  }

  private parseBitrate(raw: number | undefined): MusicGenerationBitrate | null {
    if (raw === undefined) {
      return null
    }
    if (raw === 64000) {
      return MusicGenerationBitrate.BITRATE_64000
    }
    if (raw === 96000) {
      return MusicGenerationBitrate.BITRATE_96000
    }
    if (raw === 192000) {
      return MusicGenerationBitrate.BITRATE_192000
    }
    if (raw === 256000) {
      return MusicGenerationBitrate.BITRATE_256000
    }
    if (raw === 320000) {
      return MusicGenerationBitrate.BITRATE_320000
    }
    return MusicGenerationBitrate.BITRATE_128000
  }

  private parseChannel(raw: number | undefined): MusicGenerationChannel | null {
    if (raw === undefined) {
      return null
    }
    if (raw === 2) {
      return MusicGenerationChannel.STEREO
    }
    if (raw === 1) {
      return MusicGenerationChannel.MONO
    }
    return null
  }
}

function createMusicGenerationToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('prompt', new ToolParameterProperty(
    'string',
    'Detailed description of the music to generate, in the user\'s language. Include style, mood, tempo, instruments, and scene. 20-200 characters.'
  ))
  parameters.addProperty('lyrics', new ToolParameterProperty(
    'string',
    'Optional song lyrics, with lines separated by \\n. Only used by music-2.6 (ignored by instrumental models like music-cover).'
  ))
  parameters.addProperty('audio_format', new ToolParameterProperty(
    'string',
    'Output audio format: "mp3", "pcm", "wav", or "flac". Default "mp3".'
  ))
  parameters.addProperty('sample_rate', new ToolParameterProperty(
    'integer',
    'Audio sample rate in Hz: 16000, 24000, 32000, or 44100. Default 32000.'
  ))
  parameters.addProperty('bitrate', new ToolParameterProperty(
    'integer',
    'Audio bitrate in bps: 64000, 96000, 128000, 192000, 256000, or 320000. Default 128000.'
  ))
  parameters.addProperty('channel', new ToolParameterProperty(
    'integer',
    'Audio channel count: 1 for mono, 2 for stereo. Default 1.'
  ))
  parameters.addRequired('prompt')

  const func = new ToolFunction(
    MUSIC_GENERATION_TOOL_ID,
    'Generate original music (instrumental or with lyrics) from a text prompt. Use this when the user asks you to compose, generate, or create music, songs, background music, or jingles. The generated audio will be saved as a file in the chat. Describe the desired music in detail including style, mood, tempo, instruments, and scene. Do NOT use this for sound effects, voice synthesis, or audio editing.',
    parameters
  )

  return new ToolDefinition(func)
}

function createMusicGenerationToolConfig(): ToolConfig {
  return new ToolConfig(
    MUSIC_GENERATION_TOOL_ID,
    '生成音乐',
    '根据文本描述生成音乐/歌曲, 结果作为音频文件保存到对话中。使用已配置的音乐生成服务商(如 MiniMax)。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    MUSIC_GENERATION_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== child_profile 工具 =====
// 儿童学习画像工具：让小星老师等教育类助手可以读取和更新小朋友的知识画像，实现因材施教。
// 画像通过 ChildProfileService 持久化到 PreferencesService JSON，跨会话保留。

class ChildProfileSkillSummary {
  key: string = ''
  label: string = ''
  level: number = 0
  lastAssessed: number = 0
  notes: string = ''

  constructor(key: string, label: string, level: number, lastAssessed: number, notes: string) {
    this.key = key
    this.label = label
    this.level = level
    this.lastAssessed = lastAssessed
    this.notes = notes
  }
}

class ChildProfileSummary {
  childName: string = ''
  ageYears: number = 0
  overallNote: string = ''
  sessionCount: number = 0
  lastInteraction: number = 0
  strengths: string[] = []
  weakAreas: string[] = []
  skills: ChildProfileSkillSummary[] = []

  constructor(
    childName: string, ageYears: number, overallNote: string,
    sessionCount: number, lastInteraction: number,
    strengths: string[], weakAreas: string[],
    skills: ChildProfileSkillSummary[]
  ) {
    this.childName = childName
    this.ageYears = ageYears
    this.overallNote = overallNote
    this.sessionCount = sessionCount
    this.lastInteraction = lastInteraction
    this.strengths = strengths
    this.weakAreas = weakAreas
    this.skills = skills
  }
}

interface ChildProfileArgs {
  action: string
  child_name?: string
  age_years?: number
  skill_updates?: Object[]
  overall_note?: string
  strengths?: string[]
  weak_areas?: string[]
}

interface SkillUpdateItem {
  key: string
  level: number
  notes?: string
}

class ChildProfileExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as ChildProfileArgs
      const action = (params.action ?? '').trim()
      const service = getChildProfileService()

      if (action === 'read') {
        const profile = await service.getProfile()
        return JSON.stringify(this.formatProfileForAI(profile))
      } else if (action === 'update') {
        return await this.handleUpdate(params, service)
      } else {
        return JSON.stringify(new ErrorOutput(`Unknown action: '${action}'. Use 'read' or 'update'.`))
      }
    } catch (error) {
      console.error('ChildProfileExecutor', `Error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`child_profile error: ${JSON.stringify(error)}`))
    }
  }

  private async handleUpdate(params: ChildProfileArgs, service: ChildProfileService): Promise<string> {
    const profile = await service.getProfile()

    if (params.child_name !== undefined && params.child_name.trim() !== '') {
      profile.childName = params.child_name.trim()
    }
    if (params.age_years !== undefined && params.age_years > 0) {
      profile.ageYears = params.age_years
    }
    if (params.overall_note !== undefined) {
      profile.overallNote = params.overall_note
    }

    // 更新技能维度
    if (params.skill_updates !== undefined && Array.isArray(params.skill_updates)) {
      const now = Date.now()
      for (let i = 0; i < params.skill_updates.length; i++) {
        const item = params.skill_updates[i] as Record<string, Object>
        const key = (item['key'] as string) ?? ''
        if (key === '' || profile.skills[key] === undefined) {
          continue
        }
        const level = (item['level'] as number) ?? profile.skills[key].level
        const notes = (item['notes'] as string) ?? ''
        const clampedLevel = Math.max(0, Math.min(5, level))
        profile.skills[key].level = clampedLevel
        profile.skills[key].lastAssessed = now
        if (notes !== '') {
          profile.skills[key].notes = notes
        }
      }
    }

    if (params.strengths !== undefined && Array.isArray(params.strengths)) {
      profile.strengths = []
      for (let i = 0; i < params.strengths.length; i++) {
        if (typeof params.strengths[i] === 'string') {
          profile.strengths.push(params.strengths[i] as string)
        }
      }
    }
    if (params.weak_areas !== undefined && Array.isArray(params.weak_areas)) {
      profile.weakAreas = []
      for (let i = 0; i < params.weak_areas.length; i++) {
        if (typeof params.weak_areas[i] === 'string') {
          profile.weakAreas.push(params.weak_areas[i] as string)
        }
      }
    }

    profile.lastInteraction = Date.now()
    await service.saveProfile(profile)
    return JSON.stringify(this.formatProfileForAI(profile))
  }

  private formatProfileForAI(profile: ChildKnowledgeProfile): Object {
    const skillsArray: ChildProfileSkillSummary[] = []
    const keys = Object.keys(profile.skills)
    for (let i = 0; i < keys.length; i++) {
      const dim = profile.skills[keys[i]]
      skillsArray.push(new ChildProfileSkillSummary(
        dim.key, dim.label, dim.level, dim.lastAssessed, dim.notes
      ))
    }
    return new ChildProfileSummary(
      profile.childName, profile.ageYears, profile.overallNote,
      profile.sessionCount, profile.lastInteraction,
      profile.strengths, profile.weakAreas, skillsArray
    )
  }
}

function createChildProfileToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["read", "update"],
        "description": "Action to perform. 'read' to get the child's current learning profile. 'update' to save new assessment data."
      },
      "child_name": {
        "type": "string",
        "description": "Child's name. Only include when updating."
      },
      "age_years": {
        "type": "number",
        "description": "Child's age in years. Only include when updating."
      },
      "skill_updates": {
        "type": "array",
        "description": "Array of skill assessments to update. Each item: {key, level (0-5), notes}. Only include for skills where you observed the child's actual performance.",
        "items": {
          "type": "object",
          "properties": {
            "key": {
              "type": "string",
              "description": "Skill dimension key: math_counting, math_addition, math_subtraction, math_multiply, math_divide, math_shapes, math_comparison, math_time, english_alphabet, english_vocab, english_sentence, english_phonics, general_nature, general_social, general_life, logic_thinking, observation, spatial_reasoning, fine_motor, english_writing, chinese_writing, categorization"
            },
            "level": {
              "type": "number",
              "description": "Assessed level 0-5. 0=unassessed, 1=beginner, 2=basic, 3=intermediate, 4=good, 5=mastery. Base on actual demonstrated ability."
            },
            "notes": {
              "type": "string",
              "description": "Brief observation note, e.g. 'Correctly solved 3+5 and 7+2 without counting on fingers'"
            }
          },
          "required": ["key", "level"]
        }
      },
      "overall_note": {
        "type": "string",
        "description": "Overall observation or summary note about the child."
      },
      "strengths": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Tags for the child's strengths, e.g. ['quick learner', 'good memory']."
      },
      "weak_areas": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Tags for areas that need more practice, e.g. ['subtraction', 'English sentences']."
      }
    },
    "required": ["action"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    CHILD_PROFILE_TOOL_ID,
    'Read or update the child\'s learning profile. Call \'read\' at the START of each conversation to understand the child\'s current level across math, English, general knowledge, and cognitive dimensions. Call \'update\' after observing the child\'s actual performance on a topic to track their progress. Levels are 0-5 (0=unassessed, 5=mastery). Always update based on demonstrated ability, not guesses. Available skill keys: math_counting, math_addition, math_subtraction, math_multiply, math_divide, math_shapes, math_comparison, math_time, english_alphabet, english_vocab, english_sentence, english_phonics, general_nature, general_social, general_life, logic_thinking, observation, spatial_reasoning, fine_motor, english_writing, chinese_writing, categorization.',
    parameters
  )

  return new ToolDefinition(func)
}

function createChildProfileToolConfig(): ToolConfig {
  return new ToolConfig(
    CHILD_PROFILE_TOOL_ID,
    '学习画像',
    '读取或更新小朋友的学习画像(知识水平评估), 用于教育类助手因材施教。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    CHILD_PROFILE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== math_verify 工具 =====
// 数学验证工具：让小星老师在出完数学题后，通过程序化计算验证小朋友的答案是否正确。

interface MathVerifyArgs {
  expression: string
  child_answer: number
}

class MathVerifyResult {
  correct: boolean = false
  correct_answer: number = 0
  expression: string = ''
  child_answer: number = 0

  constructor(correct: boolean, correctAnswer: number, expression: string, childAnswer: number) {
    this.correct = correct
    this.correct_answer = correctAnswer
    this.expression = expression
    this.child_answer = childAnswer
  }
}

class MathVerifyExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as MathVerifyArgs
      const expression = (params.expression ?? '').trim()
      const childAnswer = params.child_answer ?? 0

      if (expression === '') {
        return JSON.stringify(new ErrorOutput('expression is required'))
      }

      const correctAnswer = evaluateMathExpression(expression)
      const isCorrect = Math.abs(correctAnswer - childAnswer) < 0.001

      return JSON.stringify(new MathVerifyResult(isCorrect, correctAnswer, expression, childAnswer))
    } catch (error) {
      console.error('MathVerifyExecutor', `Error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`math_verify error: ${JSON.stringify(error)}`))
    }
  }
}

function createMathVerifyToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "expression": {
        "type": "string",
        "description": "The arithmetic expression to evaluate, e.g. '3 + 5', '12 / 4', '(8 - 3) * 2'. Only numbers, +, -, *, /, parentheses, and decimals."
      },
      "child_answer": {
        "type": "number",
        "description": "The answer the child gave."
      }
    },
    "required": ["expression", "child_answer"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    MATH_VERIFY_TOOL_ID,
    'Verify the child\'s answer to a math problem. Submit the arithmetic expression and the child\'s answer. Returns whether the answer is correct and the correct answer. Use this INSTEAD of computing math answers yourself in plain text — this tool returns a structured correctness signal that the child profile updater reads; computing in plain text leaves skill levels stale. Use this AFTER the child answers a math_quiz question or a verbal math question.',
    parameters
  )

  return new ToolDefinition(func)
}

function createMathVerifyToolConfig(): ToolConfig {
  return new ToolConfig(
    MATH_VERIFY_TOOL_ID,
    '数学验证',
    '验证小朋友的数学答案是否正确, 通过程序计算算术表达式。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    MATH_VERIFY_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== math_quiz 工具 =====
// 数学游戏工具：让小星老师以互动卡片形式出数学题, 小朋友在屏幕上点选答案。

interface MathQuizArgs {
  type?: 'arithmetic' | 'shape' | 'comparison' | 'time' | 'elapsed_time'
  question: string
  expression?: string
  correct_answer: string | number
  options: Array<string | number>
  skill_key?: string
  // arithmetic 专用; true = 应用题模式 (隐藏算式, 只显示 question 场景描述)
  word_problem?: boolean
  // comparison 专用
  left_value?: number
  right_value?: number
  operator_options?: string[]
  // time 专用
  clock_hour?: number
  clock_minute?: number
  // elapsed_time 专用
  start_hour?: number
  start_minute?: number
  end_hour?: number
  end_minute?: number
}

class MathQuizResult {
  answered: boolean = false
  child_answer: number = 0
  child_answer_valid: boolean = false
  correct: boolean = false
  correct_answer: string | number = 0
  expression: string = ''

  constructor(answered: boolean, childAnswer: number, childAnswerValid: boolean,
    correct: boolean, correctAnswer: string | number, expression: string) {
    this.answered = answered
    this.child_answer = childAnswer
    this.child_answer_valid = childAnswerValid
    this.correct = correct
    this.correct_answer = correctAnswer
    this.expression = expression
  }
}

class MathQuizExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // math_quiz 工具的执行由前端 MathQuizCard 组件处理交互。
    // 后端只需要返回参数解析成功即可, 实际答案由前端 onAnswer 回调提交。
    // 如果工具被直接调用(没有前端交互), 返回提示信息。
    try {
      const params = JSON.parse(_args) as MathQuizArgs
      // arithmetic 类型 correct_answer 期望 number; 其他 4 种 type 期望 string.
      // 后端只透传, 真实答案由前端 onAnswer 提交, 不做语义校验。
      const isArithmetic = (params.type ?? 'arithmetic') === 'arithmetic'
      const correct: string | number =
        isArithmetic ? Number(params.correct_answer ?? 0) : String(params.correct_answer ?? '')
      return JSON.stringify(new MathQuizResult(
        false, 0, false, false, correct, params.expression ?? ''
      ))
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`math_quiz error: ${JSON.stringify(error)}`))
    }
  }
}

function createMathQuizToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "type": {
        "type": "string",
        "enum": ["arithmetic", "shape", "comparison", "time", "elapsed_time"],
        "description": "题目类型. arithmetic=算术(add/sub/mul/div/counting/word_problem), shape=图形认知, comparison=大小比较, time=时间认知-读时间 (必须同时传 clock_hour 和 clock_minute), elapsed_time=时间认知-计时经过 (必须同时传 start_hour/start_minute/end_hour/end_minute, correct_answer 是时长字符串 e.g. 「1 小时 30 分」). 缺省视为 arithmetic."
      },
      "question": {
        "type": "string",
        "description": "The quiz question in natural spoken language, e.g. 「桌上有 3 个苹果, 再放 2 个, 一共几个呀」."
      },
      "expression": {
        "type": "string",
        "description": "arithmetic 专用: 算式字符串, e.g. 「3 + 2」. 显示为 「3 + 2 = ?」. 应用题模式 (word_problem=true) 时 expression 留空. 其他 type 不用填."
      },
      "word_problem": {
        "type": "boolean",
        "description": "arithmetic 专用: true=应用题模式, 只渲染 question 场景描述 (如「桌上有 3 个苹果又放 2 个」), 隐藏算式. 小朋友需要把语言翻译成算式再点答案. 缺省 false=普通算式题."
      },
      "clock_hour": {
        "type": "integer",
        "minimum": 1,
        "maximum": 12,
        "description": "time 专用: 钟面上的小时数 (1-12 整数, 12 小时制). 整 1 点填 1, 整 12 点填 12. 不要填 0 也不要填 13 以上."
      },
      "clock_minute": {
        "type": "integer",
        "minimum": 0,
        "maximum": 55,
        "multipleOf": 5,
        "description": "time 专用: 钟面上的分钟数 (5 分钟步长, 只能填 0/5/10/15/20/25/30/35/40/45/50/55). 整点填 0, 半点填 30."
      },
      "start_hour": {
        "type": "integer",
        "minimum": 1,
        "maximum": 12,
        "description": "elapsed_time 专用: 开始钟面的小时数 (1-12 整数, 12 小时制). 必须与 start_minute 配合, 不能单独使用."
      },
      "start_minute": {
        "type": "integer",
        "minimum": 0,
        "maximum": 55,
        "multipleOf": 5,
        "description": "elapsed_time 专用: 开始钟面的分钟数 (5 分钟步长, 0/5/10/15/20/25/30/35/40/45/50/55)."
      },
      "end_hour": {
        "type": "integer",
        "minimum": 1,
        "maximum": 12,
        "description": "elapsed_time 专用: 结束钟面的小时数 (1-12 整数, 12 小时制). 必须与 end_minute 配合, 不能单独使用."
      },
      "end_minute": {
        "type": "integer",
        "minimum": 0,
        "maximum": 55,
        "multipleOf": 5,
        "description": "elapsed_time 专用: 结束钟面的分钟数 (5 分钟步长, 0/5/10/15/20/25/30/35/40/45/50/55)."
      },
      "correct_answer": {
        "type": ["string", "number"],
        "description": "正确答案. arithmetic=数字 e.g. 5. shape=英文形状名 e.g. circle / square / triangle. comparison=比较运算符 e.g. 「>」. time=数字时钟字符串 e.g. 「3:30」 或 「12:00」, 必须与 clock_hour/clock_minute 一致, 5 分钟步长. elapsed_time=时长字符串 e.g. 「1 小时 30 分」 或 「30 分」, 必须与 start_hour/start_minute/end_hour/end_minute 计算结果一致."
      },
      "options": {
        "type": "array",
        "items": { "type": ["string", "number"] },
        "description": "3-4 个选项. arithmetic 用数字; shape 用英文形状名; time 用数字时钟字符串 (H:MM, 5 分钟步长); elapsed_time 用时长字符串 (X 小时 Y 分 格式). comparison 一般留空, 用 operator_options 替代. 必须包含正确答案, 打乱顺序."
      },
      "skill_key": {
        "type": "string",
        "description": "Optional. 教学目标维度 key, e.g. math_addition / math_shapes / math_comparison / math_time. Used for updating the child's profile after answering."
      },
      "left_value": {
        "type": "number",
        "description": "comparison 专用: 左侧数字, e.g. 5."
      },
      "right_value": {
        "type": "number",
        "description": "comparison 专用: 右侧数字, e.g. 3."
      },
      "operator_options": {
        "type": "array",
        "items": { "type": "string" },
        "description": "comparison 专用: 提供的运算符按钮, e.g. [>,<,=]. 缺省给三个全选."
      }
    },
    "required": ["question", "options"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    MATH_QUIZ_TOOL_ID,
    'Present a math quiz to the child as an interactive game card on screen. Use this INSTEAD of writing math problems in plain text. Set the type field: arithmetic=加减乘除算术题 (含应用题), shape=图形认知, comparison=大小比较, time=时间认知-读时间, elapsed_time=时间认知-计时经过. Provide 3-4 options including the correct answer. For comparison, fill left_value/right_value and operator_options, leave options empty. For time questions, also fill clock_hour (1-12) and clock_minute (5-minute step: 0/5/.../55) so the card can render an analog clock face. For arithmetic word problems, set word_problem=true and write the scenario in question (e.g. 「桌上有 3 个苹果, 再放 2 个, 一共几个呀」); leave expression empty. For elapsed_time questions, set type=elapsed_time and fill start_hour (1-12), start_minute (5-min step), end_hour (1-12), end_minute (5-min step). The correct_answer and options are duration strings like 「1 小时 30 分」,「30 分」,「2 小时」.',
    parameters
  )

  return new ToolDefinition(func)
}

function createMathQuizToolConfig(): ToolConfig {
  return new ToolConfig(
    MATH_QUIZ_TOOL_ID,
    '数学游戏',
    '以互动卡片形式给小朋友出数学题, 小朋友可以在屏幕上点选答案。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    MATH_QUIZ_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== english_quiz 工具 =====
// 英语看图说话工具：让 AI 出示图片，小朋友通过语音或文字说出对应的英语单词/句子。
// 图片优先从本地缓存加载（ImageIndexService 统一数据访问层：ENGLISH_QUIZ + LESSON_PLAN 双源），
// 缓存未命中时调用图片生成 API。交互由前端 EnglishQuizCard 组件处理，与 math_quiz 模式类似。

interface EnglishQuizArgs {
  question: string
  image_prompt: string
  correct_answer: string
  question_type: string
  difficulty: number
  skill_key: string
  letter_options?: string[]   // 仅 phonics_choice 用: 3-4 个字母选项 (含 correct_answer)
  sound_text?: string          // 仅 phonics_choice 用: TTS 朗读的自然拼读音 (如 "kuh")
}

class EnglishQuizExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // english_quiz 工具的交互由前端 EnglishQuizCard 组件处理。
    // 后台由 ToolExecutionService.handleEnglishQuiz 拦截处理图片生成/缓存逻辑。
    // 如果工具被直接调用（没有前端交互），返回提示信息。
    try {
      const params = JSON.parse(_args) as EnglishQuizArgs
      const questionType = (params.question_type ?? 'word').trim()
      const answer = params.correct_answer ?? ''
      let word = ''
      let sentence = ''
      let letter = ''
      if (questionType === 'sentence') {
        sentence = answer
      } else if (questionType === 'phonics_choice') {
        letter = answer
      } else {
        word = answer
      }
      return JSON.stringify({
        answered: false,
        correct_answer: params.correct_answer ?? '',
        word: word,
        sentence: sentence,
        letter: letter,
        letter_options: params.letter_options ?? [],
        sound_text: params.sound_text ?? ''
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`english_quiz error: ${JSON.stringify(error)}`))
    }
  }
}

function createEnglishQuizToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "question": {
        "type": "string",
        "description": "The Chinese word or sentence the child needs to say in English. For word quizzes: the Chinese word (e.g. '苹果', '小狗'). For sentence quizzes: the Chinese sentence (e.g. '我喜欢吃苹果')."
      },
      "image_prompt": {
        "type": "string",
        "description": "Detailed English prompt for generating the image. Should be child-friendly, colorful, and clearly depict the word/concept. e.g. 'A bright red apple on a wooden table, children illustration style, colorful, simple background'"
      },
      "correct_answer": {
        "type": "string",
        "description": "The correct English answer. For word quiz: the English word. For sentence quiz: the English sentence. e.g. 'apple' or 'I like apples'"
      },
      "question_type": {
        "type": "string",
        "enum": ["word", "sentence", "phonics_choice"],
        "description": "Type of quiz: 'word' for single word, 'sentence' for full sentence, 'phonics_choice' for letter sound recognition (TTS plays sound_text, child taps correct letter)."
      },
      "difficulty": {
        "type": "number",
        "description": "Difficulty level 1-5. 1=very easy (common objects), 5=harder (abstract concepts). Base on child profile."
      },
      "skill_key": {
        "type": "string",
        "description": "The child profile skill dimension this quiz targets: 'english_vocab' for words, 'english_sentence' for sentences, 'english_phonics' for phonics-related."
      },
      "letter_options": {
        "type": "array",
        "items": { "type": "string", "minLength": 1, "maxLength": 3 },
        "description": "仅 phonics_choice 必填: 3-4 个字母选项 (字符串数组), 必须包含 correct_answer。例如 ['k', 'c', 's', 'p']。distractor 选取同类或相近音的字母 (k/c/g, b/d/p/q, m/n)。"
      },
      "sound_text": {
        "type": "string",
        "description": "仅 phonics_choice 必填: TTS 可读的自然拼读音拼写 (不是 IPA 也不是字母名)。例如 /k/ 写作「kuh」、/ae/ 写作「aah」、/t/ 写作「tuh」。长度不超过 10 个字符, 单个短音节或单词。"
      }
    },
    "required": ["correct_answer", "question_type", "image_prompt", "question"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    ENGLISH_QUIZ_TOOL_ID,
    'Present an English vocabulary quiz to the child with an image. The child sees a picture and speaks or types the English word/sentence. Use this INSTEAD of writing English questions in plain text — plain text questions cannot grade the child\'s answer or record stars/skill progress, only this tool can. Provide a child-friendly image_prompt that clearly depicts the concept. Set difficulty based on the child\'s english_vocab/english_sentence level from child_profile. Alternate between word and sentence types.',
    parameters
  )

  return new ToolDefinition(func)
}

function createEnglishQuizToolConfig(): ToolConfig {
  return new ToolConfig(
    ENGLISH_QUIZ_TOOL_ID,
    '英语看图说话',
    '出示图片让小朋友说出对应的英语单词或句子, 通过语音或文字作答。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    ENGLISH_QUIZ_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}


// ===== number_puzzle 工具 =====
// 数字华容道游戏工具：让小星老师以互动卡片形式给小朋友出数字滑块谜题。
// 小朋友通过拖动/点击数字方块将乱序数字排列成正确顺序。
// 交互由前端 NumberPuzzleCard 组件处理（卡片按 difficulty 自行洗牌），与 math_quiz/english_quiz 模式类似。
// 历史会话里的 legacy 工具名是 huarongdao, 由 ToolExecutionService 分发层兼容。

interface NumberPuzzleArgs {
  difficulty: number
}

class NumberPuzzleExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // number_puzzle 工具的交互由前端 NumberPuzzleCard 组件处理。
    // 后端由 ToolExecutionService.handleNumberPuzzle 拦截处理。
    // 如果工具被直接调用（没有前端交互），返回提示信息。
    try {
      const params = JSON.parse(_args) as NumberPuzzleArgs
      const difficulty = Math.max(1, Math.min(5, params.difficulty ?? 1))
      // 简单预校验:返回提示让 AI 引导用户使用前端卡片
      return JSON.stringify({
        difficulty: difficulty,
        grid_size: difficulty === 1 ? '3×3' : `${difficulty}×${difficulty}`,
        answered: false,
        hint: '谜题已生成,请小朋友在卡片里拖动数字方块复原顺序。'
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`number_puzzle error: ${JSON.stringify(error)}`))
    }
  }
}

function createNumberPuzzleToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "difficulty": {
        "type": "number",
        "description": "难度等级 2-5 推荐使用(1 为兜底,实际映射到 3×3)。2 = 幼儿 · 2×2(3 数字), 3 = 简单 · 3×3(8 数字), 4 = 进阶 · 4×4(15 数字), 5 = 挑战 · 5×5(24 数字)。根据 child_profile 中 logic_thinking 和 observation 的 level 选择合适难度。",
        "enum": [1, 2, 3, 4, 5]
      }
    },
    "required": ["difficulty"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    NUMBER_PUZZLE_TOOL_ID,
    'Present a number sliding puzzle (数字华容道) to the child as an interactive game. A grid of numbered tiles is shuffled, and the child slides tiles into the empty space to arrange them in order. Difficulty directly maps to grid size: 1=3×3 (fallback, 8 numbers), 2=2×2 (toddler, 3 numbers), 3=3×3 (easy, 8 numbers), 4=4×4 (intermediate, 15 numbers), 5=5×5 (challenging, 24 numbers). Prefer difficulty 2-5 based on the child\'s logic_thinking and observation levels from child_profile. After completion or giving up, you receive result (moves, time, completed). Then call child_profile update to record logic_thinking, observation, and spatial_reasoning based on performance.',
    parameters
  )

  return new ToolDefinition(func)
}

function createNumberPuzzleToolConfig(): ToolConfig {
  return new ToolConfig(
    NUMBER_PUZZLE_TOOL_ID,
    '数字华容道',
    '以互动卡片形式给小朋友出数字滑块谜题, 小朋友拖动数字方块将乱序数字排列成正确顺序。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    NUMBER_PUZZLE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}


// ===== maze 工具 =====
// 走迷宫互动工具：让孩子在网格迷宫里点击相邻格子走出，锻炼方向感 + 路径规划 + 死胡同识别。
// 交互由前端 MazeCard 组件处理，与 number_puzzle/categorization 模式类似。
// 后端由 ToolExecutionService.handleMaze 拦截处理迷宫生成逻辑。

interface MazeArgs {
  difficulty: number
}

class MazeExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // maze 工具的交互由前端 MazeCard 组件处理。
    // 后端由 ToolExecutionService.handleMaze 拦截处理迷宫生成逻辑。
    // 如果工具被直接调用（没有前端交互），返回提示信息。
    try {
      const params = JSON.parse(_args) as MazeArgs
      const difficulty = Math.max(1, Math.min(3, params.difficulty ?? 1))
      // 简单预校验:返回提示让 AI 引导用户使用前端卡片
      return JSON.stringify({
        difficulty: difficulty,
        grid_size: difficulty === 1 ? '4×4' : (difficulty === 2 ? '6×6' : '8×8'),
        answered: false,
        hint: '迷宫已生成,请小朋友在卡片里点击相邻格子走出。'
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`maze error: ${JSON.stringify(error)}`))
    }
  }
}

function createMazeToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "difficulty": {
        "type": "integer",
        "description": "难度级别:1 = 简单 4×4(适合 5 岁,16 格,1-2 死胡同),2 = 进阶 6×6(适合 6-7 岁,36 格,3-4 死胡同),3 = 挑战 8×8(适合 7-8 岁,64 格,5-6 死胡同)。建议初次使用从 1 开始,根据 child_profile 中 spatial_reasoning 的 level 选择。",
        "enum": [1, 2, 3]
      }
    },
    "required": ["difficulty"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    MAZE_TOOL_ID,
    'Present a maze (走迷宫) to the child as an interactive game. A grid maze is generated with paths and walls; the child taps adjacent cells to move a golden star from the start (top-left) to a purple-roofed house (bottom-right). Difficulty directly maps to grid size: 1=4×4 (easy, 16 cells), 2=6×6 (intermediate, 36 cells), 3=8×8 (challenging, 64 cells). Hidden stars in dead-ends can be collected for fun (not required for completion). Prefer difficulty 1-3 based on the child\'s spatial_reasoning level from child_profile. After completion or giving up, you receive result (moves, time, stars collected, completed). Then call child_profile update to record spatial_reasoning based on performance.',
    parameters
  )

  return new ToolDefinition(func)
}

function createMazeToolConfig(): ToolConfig {
  return new ToolConfig(
    MAZE_TOOL_ID,
    '走迷宫',
    '以互动卡片形式给小朋友出网格迷宫,孩子点击相邻格子走出迷宫,锻炼方向感 + 路径规划 + 死胡同识别。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    MAZE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== sudoku 工具 =====
// 数独互动工具: 让孩子在 4×4 / 6×6 / 9×9 网格里填数字, 锻炼逻辑推理 + 空间规则意识。
// 交互由前端 SudokuCard 组件处理, 与 number_puzzle/categorization/maze 模式类似。
// 后端由 ToolExecutionService.handleSudoku 拦截, 在 pending 状态下让卡片显示「生成中」,
// 后台异步调用 utils/SudokuGenerator 生成盘面后注入 toolCall.arguments。

interface SudokuArgs {
  difficulty: number
}

class SudokuExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // sudoku 工具的交互由前端 SudokuCard 组件处理。
    // 后端由 ToolExecutionService.handleSudoku 拦截处理生成逻辑。
    // 如果工具被直接调用 (没有前端交互), 返回提示信息。
    try {
      const params = JSON.parse(_args) as SudokuArgs
      const difficulty = Math.max(1, Math.min(5, params.difficulty ?? 1))
      return JSON.stringify({
        difficulty: difficulty,
        grid_size: difficulty === 1 ? '4×4' : (difficulty === 2 ? '6×6' : '9×9'),
        answered: false,
        hint: '数独已生成,请小朋友在卡片里填满数字。'
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`sudoku error: ${JSON.stringify(error)}`))
    }
  }
}

function createSudokuToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "difficulty": {
        "type": "integer",
        "description": "难度级别:1 = 4×4 (2×2 盒, 适合 5 岁, 6-8 个已知),2 = 6×6 (2×3 盒, 适合 6 岁, 18-22 个已知),3 = 9×9 简单 (3×3 盒, 适合 7 岁+, 40-45 个已知),4 = 9×9 中等 (30-34 个已知),5 = 9×9 挑战 (24-28 个已知, 适合数独熟练的孩子)。按 child_profile 中 logic_thinking / spatial_reasoning 的 level 选难度。",
        "enum": [1, 2, 3, 4, 5]
      }
    },
    "required": ["difficulty"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    SUDOKU_TOOL_ID,
    'Present a Sudoku (数独) puzzle to the child as an interactive game. A grid of size 4×4 / 6×6 / 9×9 is generated with sub-boxes (2×2 / 2×3 / 3×3) and some cells pre-filled. The child taps an empty cell then a digit on the number pad to fill it. Soft live validation highlights row/column/box conflicts in red (rule-level, never revealing the hidden solution). Difficulty 1=4×4 (5y), 2=6×6 (6y), 3=9×9 easy (7y+), 4=9×9 medium, 5=9×9 hard. Pick by the child\'s logic_thinking / spatial_reasoning level from child_profile. After completion or giving up, you receive result (time, mistakes, completed). Then call child_profile update to record logic_thinking / spatial_reasoning based on performance.',
    parameters
  )

  return new ToolDefinition(func)
}

function createSudokuToolConfig(): ToolConfig {
  return new ToolConfig(
    SUDOKU_TOOL_ID,
    '数独',
    '以互动卡片形式给小朋友出数独,孩子在网格里填数字,每行/列/盒内数字不重复,锻炼逻辑推理 + 空间规则意识。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    SUDOKU_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== handwriting_practice 工具 =====
// 学写字互动工具：教小朋友写英文字母、数字、基础汉字，通过 Canvas 自由书写，AI 评价。

interface HandwritingPracticeArgs {
  character: string
  type: string
  strokes?: HandwritingPracticeStroke[]
}

interface HandwritingPracticePoint {
  x: number
  y: number
}

interface HandwritingPracticeStroke {
  points: HandwritingPracticePoint[]
  label: string
}

class HandwritingPracticeExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    try {
      const params = JSON.parse(_args) as HandwritingPracticeArgs
      return JSON.stringify({
        character: params.character ?? 'A',
        type: params.type ?? 'letter',
        completed: false,
        stroke_count: 0
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`handwriting_practice error: ${JSON.stringify(error)}`))
    }
  }
}

function createHandwritingPracticeToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "character": {
        "type": "string",
        "description": "The character to practice. For letters use 'A', 'a' etc. For numbers use '5'. For Chinese characters use the single character like 人, 大."
      },
      "type": {
        "type": "string",
        "description": "The type of character: letter for English letters, number for digits, chinese for Chinese characters.",
        "enum": ["letter", "number", "chinese"]
      },
      "strokes": {
        "type": "array",
        "description": "Optional. Stroke order data as array of objects. Each stroke has a points array (ordered polyline of x,y pairs in relative 0-1 coordinates; 2 points for straight strokes, 4-8 sample points for curves, 1 point for dots) and a label string (stroke direction symbol like slash, backslash, dash, pipe, arc, or dot). If omitted, the built-in stroke library will be used for common characters.",
        "items": {
          "type": "object",
          "properties": {
            "points": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "x": { "type": "number" },
                  "y": { "type": "number" }
                }
              }
            },
            "label": { "type": "string" }
          }
        }
      }
    },
    "required": ["character", "type"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    HANDWRITING_PRACTICE_TOOL_ID,
    "Launch a handwriting practice activity for the child. The child watches a stroke order demonstration of a character (letter, number, or simple Chinese character), then practices writing it on a blank canvas. After submission, AI vision evaluates the handwriting and gives encouraging feedback. Choose characters appropriate to the child's age and skill level. Start with simple letters (A, B, C) or numbers (1, 2, 3) for beginners.",
    parameters
  )

  return new ToolDefinition(func)
}

function createHandwritingPracticeToolConfig(): ToolConfig {
  return new ToolConfig(
    HANDWRITING_PRACTICE_TOOL_ID,
    '学写字',
    '学写字互动工具, 观看笔顺示范后在 Canvas 上自由书写, AI 识别评价书写成果。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    HANDWRITING_PRACTICE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// ===== categorization 工具 =====
// 分类小管家工具：让小星老师发起分类归纳互动游戏，孩子把物品拖拽/点击到对应的分类桶里，训练分类归纳能力。
// 交互由前端 CategorizationCard 组件处理，后端 ToolExecutionService.handleCategorization 拦截处理记录保存。

interface CategorizationArgs {
  theme: string
  instruction?: string
  difficulty?: number
  bins: Object[]
  items: Object[]
}

class CategorizationExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    try {
      const params = JSON.parse(_args) as CategorizationArgs
      return JSON.stringify({
        theme: params.theme ?? '',
        instruction: params.instruction ?? '',
        difficulty: params.difficulty ?? 1,
        bins: params.bins ?? [],
        items: params.items ?? [],
        completed: false,
        correct_count: 0,
        total_count: 0
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`categorization error: ${JSON.stringify(error)}`))
    }
  }
}

function createCategorizationToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "theme": {
        "type": "string",
        "description": "主题名称，2-12 字。从工具 description 的「主题库」6 大类（动物/食物/自然/生活/认知/学习）里选一个具体主题，避免连续重复同一主题。"
      },
      "instruction": {
        "type": "string",
        "description": "可选，给孩子的开场白，如「帮小动物回家吧！」"
      },
      "difficulty": {
        "type": "integer",
        "enum": [1, 2, 3],
        "description": "难度：1=4件2桶，2=6件3桶，3=9件3桶"
      },
      "bins": {
        "type": "array",
        "minItems": 2,
        "maxItems": 3,
        "items": {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "桶名（中文）" },
            "emoji": { "type": "string", "description": "桶标识 emoji，可选" }
          },
          "required": ["name"]
        }
      },
      "items": {
        "type": "array",
        "minItems": 4,
        "maxItems": 9,
        "items": {
          "type": "object",
          "properties": {
            "name": { "type": "string" },
            "emoji": { "type": "string" },
            "bin_index": { "type": "integer", "description": "所属桶的索引（从 0 开始）" }
          },
          "required": ["name", "bin_index"]
        }
      }
    },
    "required": ["theme", "bins", "items"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    CATEGORIZATION_TOOL_ID,
    'Present an interactive categorization game to the child. Use this INSTEAD of describing sorting exercises in plain text — plain-text sorting cannot grade answers or update the child\'s categorization skill level, only this tool can.\n\nDISTRIBUTION RULES (CRITICAL — violating these forces a retry and wastes the child\'s turn):\n- difficulty 1: EXACTLY 4 items, 2 bins, distribution MUST be 2/2 (each bin gets 2 items)\n- difficulty 2: EXACTLY 6 items, 3 bins, distribution MUST be 2/2/2 (each bin gets 2 items)\n- difficulty 3: EXACTLY 9 items, 3 bins, distribution MUST be 3/3/3 (each bin gets 3 items)\n- Every bin MUST receive at least 2 items. NEVER assign 0 or 1 items to any bin.\n- Every item.bin_index MUST be in [0, bins.length) and match the bin the item belongs to.\n\nWorked example (difficulty 2, 3 bins, 6 items, 2/2/2 distribution):\nbins: [{"name":"水果"},{"name":"蔬菜"},{"name":"主食"}]\nitems: [\n  {"name":"苹果","bin_index":0},{"name":"香蕉","bin_index":0},\n  {"name":"白菜","bin_index":1},{"name":"萝卜","bin_index":1},\n  {"name":"米饭","bin_index":2},{"name":"面条","bin_index":2}\n]\n\nTheme library — rotate across these 6 categories, prefer themes the child has not played recently:\n- 动物 (Animals): 动物的家 (陆地/水里/天空), 食物链 (食草/食肉/杂食), 腿数 (2/4/6+), 栖息环境 (宠物/农场/野生)\n- 食物 (Food): 水果与蔬菜 (水果/蔬菜), 三餐 (早餐/午餐/晚餐), 健康与零食 (健康/零食), 调味与主食 (调味料/主食)\n- 自然 (Nature): 天气 (晴/雨/雪), 四季 (春/夏/秋/冬), 地形 (山/河/海), 天文 (日/月/星)\n- 生活 (Daily life): 家里的房间 (厨房/卧室/浴室), 衣物 (上衣/裤子/鞋袜), 职业 (老师/医生/工人), 交通 (陆/水/空)\n- 认知 (Concepts): 颜色 (红/黄/蓝), 形状 (圆/方/三角), 冷热 (冷/热), 快慢 (快/慢)\n- 学习 (Academic): 拼音首字母 (a/b/p/m), 英文首字母 (A/B/C), 奇偶 (奇/偶), 大小写 (大写/小写)\n\nGuidance: pick a fresh theme each round, match difficulty to child_profile.categorization level (level 1-2 = difficulty 1, level 3-4 = difficulty 2, level 5 = difficulty 3), and prefer concrete recognizable items with emoji over abstract concepts.',
    parameters
  )

  return new ToolDefinition(func)
}

function createCategorizationToolConfig(): ToolConfig {
  return new ToolConfig(
    CATEGORIZATION_TOOL_ID,
    '分类小管家',
    '分类归纳互动游戏, 让孩子把物品拖拽或点击到对应的分类桶里, 训练分类与归纳能力。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    CATEGORIZATION_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}


// ===== vertical_math 工具 =====
// 小学竖式闯关工具：让小星老师发起加减乘除竖式计算互动，孩子按位填写并通过 AnimatedVerticalMathBoard 渲染。
// 交互由前端 VerticalMathCard 组件处理，后端 ToolExecutionService.handleVerticalMath 拦截处理记录保存。

interface VerticalMathArgs {
  operation?: string
  operand_a?: number
  operand_b?: number
}

class VerticalMathExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    try {
      const params = JSON.parse(_args) as VerticalMathArgs
      return JSON.stringify({
        operation: params.operation ?? '',
        operand_a: params.operand_a ?? null,
        operand_b: params.operand_b ?? null,
        completed: false,
        correct: false
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`vertical_math error: ${JSON.stringify(error)}`))
    }
  }
}

function createVerticalMathToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "operation": {
        "type": "string",
        "enum": ["add", "subtract", "multiply", "divide"],
        "description": "运算类型：add=加法、subtract=减法、multiply=乘法、divide=除法。"
      },
      "operand_a": {
        "type": "integer",
        "minimum": 0,
        "maximum": 999,
        "description": "第一个数（被加数/被减数/被乘数/被除数），0–999。允许省略让孩子自行填入。"
      },
      "operand_b": {
        "type": "integer",
        "minimum": 0,
        "maximum": 999,
        "description": "第二个数（加数/减数/乘数/除数），0–999。乘法限制 0–9、除法限制 1–9。允许省略。"
      }
    },
    "required": [],
    "additionalProperties": false
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    VERTICAL_MATH_TOOL_ID,
    '「小学竖式闯关」：输入两个 0–999 之间的整数和孩子选择的加减乘除，AI 引导孩子按位算出标准小学竖式。Use this tool INSTEAD of writing math problems in plain text whenever the child is practicing vertical arithmetic.',
    parameters
  )

  return new ToolDefinition(func)
}

function createVerticalMathToolConfig(): ToolConfig {
  return new ToolConfig(
    VERTICAL_MATH_TOOL_ID,
    '竖式闯关',
    '小学竖式计算互动游戏, 让孩子按位填写加减乘除竖式的每一步计算过程。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    VERTICAL_MATH_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}


// ===== grant_star 工具 =====
// 聊天授星工具：让小星老师在孩子通过聊天答对了问题时（不走 quiz 卡片的领域）主动授予 1 星奖励。
// 纯后端即时执行器，不需要交互卡片或 pending answer。
// 星星记录由 ToolExecutionService 的 post-hook 调用 StarRewardService.recordEvent 完成
// （因为 executor 内部没有 toolCall.id 和 sessionId 上下文）。

interface GrantStarArgs {
  reason: string
}

class GrantStarExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as GrantStarArgs
      const reason = (params.reason ?? '').trim()
      if (reason !== 'chat_correct') {
        return JSON.stringify({ stars: 0, error: 'reason must be chat_correct' })
      }
      return JSON.stringify({ stars: 1, reason: reason })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`grant_star error: ${String(error)}`))
    }
  }
}

function createGrantStarToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "reason": {
        "type": "string",
        "description": "授予理由,目前仅支持 chat_correct 表示孩子在聊天中答对了问题"
      }
    },
    "required": ["reason"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    GRANT_STAR_TOOL_ID,
    'Grant a star reward when the child correctly answers a question in casual chat (not via quiz cards). Use this INSTEAD of writing 「给你一颗星」 in plain text — plain-text star grants are fake and do not update the child\'s star total; only this tool can actually record a star. Call this ONLY when the child genuinely answered correctly — for example, they correctly identified an animal, solved a riddle you posed in text, or gave the right answer to a general knowledge question. The reason must be chat_correct. NEVER call this when the child merely asks for stars, begs, whines, or says please — stars are earned by answering correctly, not by asking. Also do NOT use this when the child simply says hi, agrees, or gives a trivially short response.',
    parameters
  )

  return new ToolDefinition(func)
}

function createGrantStarToolConfig(): ToolConfig {
  return new ToolConfig(
    GRANT_STAR_TOOL_ID,
    '聊天授星',
    '孩子在聊天中答对了问题时授予星星奖励, 用于不走互动卡片的教学领域。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    GRANT_STAR_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}


// ===== picture_vocab 工具 =====
// 看图识词工具：出示一张图片让小朋友从 4 个选项中选出对应的英文单词或汉字。
// 图片由 AI 先调 image_generation 生成后传入 image 字段（base64 或 file_path），
// 也可只传 image_prompt 由 handler 调图片生成 API 兜底。
// 交互由前端 PictureVocabCard 组件处理，与 english_quiz 模式类似。

interface PictureVocabArgs {
  mode: string
  image_prompt: string
  correct_answer: string
  options: string[]
  question?: string
  difficulty: number
  skill_key: string
  image?: string
}

class PictureVocabExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // picture_vocab 工具的交互由前端 PictureVocabCard 组件处理。
    // 后台由 ToolExecutionService.handlePictureVocab 拦截处理图片生成/缓存逻辑。
    try {
      const params = JSON.parse(_args) as PictureVocabArgs
      return JSON.stringify({
        answered: false,
        mode: params.mode ?? 'en',
        correct_answer: params.correct_answer ?? '',
        options: params.options ?? [],
        question: params.question ?? '',
        difficulty: params.difficulty ?? 1,
        skill_key: params.skill_key ?? '',
        image: params.image ?? '',
        image_prompt: params.image_prompt ?? ''
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`picture_vocab error: ${JSON.stringify(error)}`))
    }
  }
}

function createPictureVocabToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "mode": {
        "type": "string",
        "enum": ["en", "zh"],
        "description": "识词模式：en=看图选英文单词（options 为英文单词），zh=看图选汉字（options 为汉字）。根据教学目标选择，英语课用 en，识字课用 zh。"
      },
      "image_prompt": {
        "type": "string",
        "description": "Detailed English prompt for generating the image. Should be child-friendly, colorful, and clearly depict a single recognizable object/concept. e.g. 'A bright red apple on a wooden table, children illustration style, colorful, simple background'"
      },
      "image": {
        "type": "string",
        "description": "可选：若已先调 image_generation 生成了图片，直接传入返回的 base64 或 file_path，避免重复生成。未传时 handler 会用 image_prompt 兜底生成。"
      },
      "correct_answer": {
        "type": "string",
        "description": "正确答案。mode=en 时为英文单词（如 apple），mode=zh 时为汉字（如 苹）。必须出现在 options 中。"
      },
      "options": {
        "type": "array",
        "items": { "type": "string", "minLength": 1 },
        "minItems": 4,
        "maxItems": 4,
        "description": "恰好 4 个选项字符串，必须包含 correct_answer。mode=en 时为 4 个英文单词，mode=zh 时为 4 个汉字。distractor 选取同类或形近词，避免过于明显。"
      },
      "question": {
        "type": "string",
        "description": "可选：给孩子的题目提示语。未传时默认 mode=en 用「What is this?」、mode=zh 用「这是什么？」。"
      },
      "difficulty": {
        "type": "number",
        "description": "Difficulty level 1-5. 1=very easy (common objects like apple/cat), 5=harder (less common or abstract). Base on child profile."
      },
      "skill_key": {
        "type": "string",
        "description": "The child profile skill dimension: mode=en 用 english_vocab，mode=zh 用 chinese_writing。"
      }
    },
    "required": ["mode", "image_prompt", "correct_answer", "options", "difficulty", "skill_key"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    PICTURE_VOCAB_TOOL_ID,
    'Present a picture vocabulary quiz: show an image and let the child choose the correct English word or Chinese character from 4 options. Use this INSTEAD of plain-text vocabulary questions — plain-text questions cannot grade answers or record stars/skill progress, only this tool can. Recommended flow: first call image_generation with a child-friendly image_prompt, then pass the result to the image field; or just pass image_prompt and the handler will generate the image. Set mode to en for English vocabulary or zh for Chinese character recognition. Provide exactly 4 options including the correct_answer, with plausible distractors (same category or visually/semantically similar). Set difficulty based on the child\'s english_vocab or chinese_writing level from child_profile.',
    parameters
  )

  return new ToolDefinition(func)
}

function createPictureVocabToolConfig(): ToolConfig {
  return new ToolConfig(
    PICTURE_VOCAB_TOOL_ID,
    '看图识词',
    '出示图片让小朋友从 4 个选项中选出对应的英文单词或汉字, 训练词汇识记能力。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    PICTURE_VOCAB_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}


// 注册所有内置工具
export function registerBuiltinTools(): void {
  const registry = getToolRegistry()
  let registeredNow = 0

  if (!registry.isToolRegistered(LEGACY_WEB_SEARCH_TOOL_ID)) {
    const webSearchTool = new RegisteredTool(
      LEGACY_WEB_SEARCH_TOOL_ID,
      createSearchToolConfig(LEGACY_WEB_SEARCH_TOOL_ID, '联网搜索', '兼容旧版联网搜索调用'),
      createLegacyWebSearchToolDefinition(),
      new LegacyWebSearchExecutor()
    )
    registry.registerTool(webSearchTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(SEARCH_WEB_TOOL_ID)) {
    const webSearchTool = new RegisteredTool(
      SEARCH_WEB_TOOL_ID,
      createSearchToolConfig(SEARCH_WEB_TOOL_ID, '联网搜索', '搜索互联网获取最新信息'),
      createSearchWebToolDefinition(),
      new SearchWebExecutor()
    )
    registry.registerTool(webSearchTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(SCRAPE_WEB_TOOL_ID)) {
    const scrapeWebTool = new RegisteredTool(
      SCRAPE_WEB_TOOL_ID,
      createSearchToolConfig(SCRAPE_WEB_TOOL_ID, '网页读取', '读取指定网页 URL 内容'),
      createScrapeWebToolDefinition(),
      new ScrapeWebExecutor()
    )
    registry.registerTool(scrapeWebTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(ASK_USER_TOOL_ID)) {
    const askUserTool = new RegisteredTool(
      ASK_USER_TOOL_ID,
      createAskUserToolConfig(),
      createAskUserToolDefinition(),
      new AskUserExecutor()
    )
    registry.registerTool(askUserTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(GET_TIME_INFO_TOOL_ID)) {
    const getTimeInfoTool = new RegisteredTool(
      GET_TIME_INFO_TOOL_ID,
      createGetTimeInfoToolConfig(),
      createGetTimeInfoToolDefinition(),
      new GetTimeInfoExecutor()
    )
    registry.registerTool(getTimeInfoTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(IMAGE_GENERATION_TOOL_ID)) {
    const imageGenTool = new RegisteredTool(
      IMAGE_GENERATION_TOOL_ID,
      createImageGenerationToolConfig(),
      createImageGenerationToolDefinition(),
      new ImageGenerationExecutor()
    )
    registry.registerTool(imageGenTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(MUSIC_GENERATION_TOOL_ID)) {
    const musicGenTool = new RegisteredTool(
      MUSIC_GENERATION_TOOL_ID,
      createMusicGenerationToolConfig(),
      createMusicGenerationToolDefinition(),
      new MusicGenerationExecutor()
    )
    registry.registerTool(musicGenTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(CHILD_PROFILE_TOOL_ID)) {
    const childProfileTool = new RegisteredTool(
      CHILD_PROFILE_TOOL_ID,
      createChildProfileToolConfig(),
      createChildProfileToolDefinition(),
      new ChildProfileExecutor()
    )
    registry.registerTool(childProfileTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(MATH_VERIFY_TOOL_ID)) {
    const mathVerifyTool = new RegisteredTool(
      MATH_VERIFY_TOOL_ID,
      createMathVerifyToolConfig(),
      createMathVerifyToolDefinition(),
      new MathVerifyExecutor()
    )
    registry.registerTool(mathVerifyTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(MATH_QUIZ_TOOL_ID)) {
    const mathQuizTool = new RegisteredTool(
      MATH_QUIZ_TOOL_ID,
      createMathQuizToolConfig(),
      createMathQuizToolDefinition(),
      new MathQuizExecutor()
    )
    registry.registerTool(mathQuizTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(ENGLISH_QUIZ_TOOL_ID)) {
    const englishQuizTool = new RegisteredTool(
      ENGLISH_QUIZ_TOOL_ID,
      createEnglishQuizToolConfig(),
      createEnglishQuizToolDefinition(),
      new EnglishQuizExecutor()
    )
    registry.registerTool(englishQuizTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(NUMBER_PUZZLE_TOOL_ID)) {
    const numberPuzzleTool = new RegisteredTool(
      NUMBER_PUZZLE_TOOL_ID,
      createNumberPuzzleToolConfig(),
      createNumberPuzzleToolDefinition(),
      new NumberPuzzleExecutor()
    )
    registry.registerTool(numberPuzzleTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(MAZE_TOOL_ID)) {
    const mazeTool = new RegisteredTool(
      MAZE_TOOL_ID,
      createMazeToolConfig(),
      createMazeToolDefinition(),
      new MazeExecutor()
    )
    registry.registerTool(mazeTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(SUDOKU_TOOL_ID)) {
    const sudokuTool = new RegisteredTool(
      SUDOKU_TOOL_ID,
      createSudokuToolConfig(),
      createSudokuToolDefinition(),
      new SudokuExecutor()
    )
    registry.registerTool(sudokuTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(HANDWRITING_PRACTICE_TOOL_ID)) {
    const handwritingTool = new RegisteredTool(
      HANDWRITING_PRACTICE_TOOL_ID,
      createHandwritingPracticeToolConfig(),
      createHandwritingPracticeToolDefinition(),
      new HandwritingPracticeExecutor()
    )
    registry.registerTool(handwritingTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(CATEGORIZATION_TOOL_ID)) {
    const categorizationTool = new RegisteredTool(
      CATEGORIZATION_TOOL_ID,
      createCategorizationToolConfig(),
      createCategorizationToolDefinition(),
      new CategorizationExecutor()
    )
    registry.registerTool(categorizationTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(VERTICAL_MATH_TOOL_ID)) {
    const verticalMathTool = new RegisteredTool(
      VERTICAL_MATH_TOOL_ID,
      createVerticalMathToolConfig(),
      createVerticalMathToolDefinition(),
      new VerticalMathExecutor()
    )
    registry.registerTool(verticalMathTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(GRANT_STAR_TOOL_ID)) {
    const grantStarTool = new RegisteredTool(
      GRANT_STAR_TOOL_ID,
      createGrantStarToolConfig(),
      createGrantStarToolDefinition(),
      new GrantStarExecutor()
    )
    registry.registerTool(grantStarTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(PICTURE_VOCAB_TOOL_ID)) {
    const pictureVocabTool = new RegisteredTool(
      PICTURE_VOCAB_TOOL_ID,
      createPictureVocabToolConfig(),
      createPictureVocabToolDefinition(),
      new PictureVocabExecutor()
    )
    registry.registerTool(pictureVocabTool)
    registeredNow += 1
  }

  console.info(
    'BuiltinTools',
    `Builtin tools ready: total=${registry.getToolCount()}, newlyRegistered=${registeredNow}`
  )
}

// 获取所有内置工具 ID
export function getBuiltinToolIds(): string[] {
  return [LEGACY_WEB_SEARCH_TOOL_ID, SEARCH_WEB_TOOL_ID, SCRAPE_WEB_TOOL_ID, ASK_USER_TOOL_ID, GET_TIME_INFO_TOOL_ID, IMAGE_GENERATION_TOOL_ID, CHILD_PROFILE_TOOL_ID, MATH_VERIFY_TOOL_ID, MATH_QUIZ_TOOL_ID, ENGLISH_QUIZ_TOOL_ID, NUMBER_PUZZLE_TOOL_ID, HANDWRITING_PRACTICE_TOOL_ID, CATEGORIZATION_TOOL_ID, VERTICAL_MATH_TOOL_ID, MAZE_TOOL_ID, SUDOKU_TOOL_ID, PICTURE_VOCAB_TOOL_ID, GRANT_STAR_TOOL_ID]
}
