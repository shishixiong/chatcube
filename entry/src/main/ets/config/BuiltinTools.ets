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
  LEGACY_WEB_SEARCH_TOOL_ID,
  SCRAPE_WEB_TOOL_ID,
  SEARCH_WEB_TOOL_ID,
  CHILD_PROFILE_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID
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
import { getAttachmentStorageService } from '../services/AttachmentStorageService'
import { getGeneratedMediaRepository } from '../services/GeneratedMediaRepository'
import { getAppSettingsState } from '../state/AppSettingsState'
import { getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'
import { getChildProfileService, ChildProfileService, ChildKnowledgeProfile } from '../services/ChildProfileService'
import { evaluateMathExpression } from '../utils/MathExpressionParser'
import { getEnglishQuizImageIndex } from '../services/EnglishQuizImageIndex'


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
    'Ask the user clarifying questions before proceeding. Use this ONLY when the request is genuinely ambiguous and choosing a default would lead to significant rework. Do NOT use it for trivial details you can infer. Batch 1-3 related questions in a single call to avoid multiple back-and-forth rounds. Each question needs a unique id, concise question text, selection_type (single|multi|text), and options[] when selection_type is single or multi. The tool result will be a JSON object of the user answers keyed by question id; use those answers to continue your reply.',
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
      console.error('ImageGenerationExecutor', `Image generation error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ImageGenErrorOutput(`图片生成失败: ${JSON.stringify(error)}`))
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
    'Optional style description for the image, e.g. "photorealistic", "oil painting", "anime", "watercolor".'
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
              "description": "Skill dimension key: math_counting, math_addition, math_subtraction, math_multiply, math_divide, math_shapes, math_comparison, math_time, english_alphabet, english_vocab, english_sentence, english_phonics, general_nature, general_social, general_life"
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
    'Read or update the child\'s learning profile. Call \'read\' at the START of each conversation to understand the child\'s current level across math, English, and general knowledge dimensions. Call \'update\' after observing the child\'s actual performance on a topic to track their progress. Levels are 0-5 (0=unassessed, 5=mastery). Always update based on demonstrated ability, not guesses. Available skill keys: math_counting, math_addition, math_subtraction, math_multiply, math_divide, math_shapes, math_comparison, math_time, english_alphabet, english_vocab, english_sentence, english_phonics, general_nature, general_social, general_life.',
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
    'Verify the child\'s answer to a math problem. Submit the arithmetic expression and the child\'s answer. Returns whether the answer is correct and the correct answer. Use this AFTER the child answers a math_quiz question or a verbal math question.',
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
  question: string
  expression: string
  correct_answer: number
  options: number[]
  skill_key?: string
}

class MathQuizResult {
  answered: boolean = false
  child_answer: number = 0
  child_answer_valid: boolean = false
  correct: boolean = false
  correct_answer: number = 0
  expression: string = ''

  constructor(answered: boolean, childAnswer: number, childAnswerValid: boolean,
    correct: boolean, correctAnswer: number, expression: string) {
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
      return JSON.stringify(new MathQuizResult(
        false, 0, false, false, params.correct_answer ?? 0, params.expression ?? ''
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
      "question": {
        "type": "string",
        "description": "The quiz question in natural spoken language, e.g. '桌上有 3 个苹果, 再放 2 个, 一共几个呀'."
      },
      "expression": {
        "type": "string",
        "description": "The arithmetic expression, e.g. '3 + 2'. Will be displayed as '3 + 2 = ?'."
      },
      "correct_answer": {
        "type": "number",
        "description": "The correct answer to the expression."
      },
      "options": {
        "type": "array",
        "items": { "type": "number" },
        "description": "3-4 answer options as numbers. Must include the correct answer. Shuffle the order."
      },
      "skill_key": {
        "type": "string",
        "description": "Optional. The child profile skill dimension key this quiz targets, e.g. 'math_addition'. Used for updating the child's profile after answering."
      }
    },
    "required": ["question", "expression", "correct_answer", "options"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    MATH_QUIZ_TOOL_ID,
    'Present a math quiz to the child as an interactive game card on screen. Use this INSTEAD of writing math problems in plain text. The child will see the question, the expression, and clickable number buttons to select their answer. Provide 3-4 options including the correct answer.',
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
// 图片优先从本地缓存加载（EnglishQuizImageIndex），缓存未命中时调用图片生成 API。
// 交互由前端 EnglishQuizCard 组件处理，与 math_quiz 模式类似。

interface EnglishQuizArgs {
  word: string
  sentence: string
  image_prompt: string
  correct_answer: string
  question_type: string
  difficulty: number
  skill_key: string
}

class EnglishQuizExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // english_quiz 工具的交互由前端 EnglishQuizCard 组件处理。
    // 后端由 ToolExecutionService.handleEnglishQuiz 拦截处理图片生成/缓存逻辑。
    // 如果工具被直接调用（没有前端交互），返回提示信息。
    try {
      const params = JSON.parse(_args) as EnglishQuizArgs
      return JSON.stringify({
        answered: false,
        correct_answer: params.correct_answer ?? '',
        word: params.word ?? '',
        sentence: params.sentence ?? ''
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
      "word": {
        "type": "string",
        "description": "The Chinese word/concept to show as an image. Used for word-level quiz. e.g. '苹果', '小狗', '太阳'"
      },
      "sentence": {
        "type": "string",
        "description": "The Chinese sentence to translate. Used for sentence-level quiz. e.g. '我喜欢吃苹果'"
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
        "enum": ["word", "sentence"],
        "description": "Type of quiz: 'word' for single word, 'sentence' for full sentence"
      },
      "difficulty": {
        "type": "number",
        "description": "Difficulty level 1-5. 1=very easy (common objects), 5=harder (abstract concepts). Base on child profile."
      },
      "skill_key": {
        "type": "string",
        "description": "The child profile skill dimension this quiz targets: 'english_vocab' for words, 'english_sentence' for sentences, 'english_phonics' for phonics-related."
      }
    },
    "required": ["correct_answer", "question_type", "image_prompt"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    ENGLISH_QUIZ_TOOL_ID,
    'Present an English vocabulary quiz to the child with an image. The child sees a picture and speaks or types the English word/sentence. Use this to teach English vocabulary through visual association. Provide a child-friendly image_prompt that clearly depicts the concept. Set difficulty based on the child\'s english_vocab/english_sentence level from child_profile. Alternate between word and sentence types.',
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

  console.info(
    'BuiltinTools',
    `Builtin tools ready: total=${registry.getToolCount()}, newlyRegistered=${registeredNow}`
  )
}

// 获取所有内置工具 ID
export function getBuiltinToolIds(): string[] {
  return [LEGACY_WEB_SEARCH_TOOL_ID, SEARCH_WEB_TOOL_ID, SCRAPE_WEB_TOOL_ID, ASK_USER_TOOL_ID, GET_TIME_INFO_TOOL_ID, IMAGE_GENERATION_TOOL_ID, CHILD_PROFILE_TOOL_ID, MATH_VERIFY_TOOL_ID, MATH_QUIZ_TOOL_ID, ENGLISH_QUIZ_TOOL_ID]
}
