import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { rcp } from '@kit.RemoteCommunicationKit'
import { ApiStyle, ModelInfo, ModelProvider, ProviderType } from '../models/ChatModels'
import {
  ImageAspectRatio,
  ImageGenerationItem,
  ImageGenerationOutputFormat,
  ImageGenerationRequest,
  ImageGenerationResult
} from '../models/ImageGenerationModels'
import { HttpRequestController, HttpResponse } from './HttpService'
import { getImageGenerationRcpClient, ImageGenerationRcpClient } from './ImageGenerationRcpClient'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { normalizeCustomHeaderName, parseCustomHeadersMap } from '../utils/CustomHeaderUtils'
import {
  ImageGenerationCapabilityResolver,
  ImageGenerationRouteCapabilities
} from './ImageGenerationCapabilityResolver'

interface OpenAIImageResponseItem {
  b64_json?: string
  url?: string
  revised_prompt?: string
  size?: string
  quality?: string
  output_format?: string
  output_compression?: number
  moderation?: string
}

interface OpenAIImageResponse {
  data?: OpenAIImageResponseItem[]
  error?: OpenAIImageError
}

interface OpenAIImageError {
  message?: string
  code?: string
  param?: string
  type?: string
}

interface OpenAIImageGenerationBody {
  model: string
  prompt: string
  n: number
  size: string
  response_format: string
  quality?: string
  output_format?: string
  output_compression?: number
  moderation?: string
}

interface GoogleImagenInstance {
  prompt: string
}

interface GoogleImagenParameters {
  sampleCount: number
  aspectRatio: string
}

interface GoogleImagenBody {
  instances: GoogleImagenInstance[]
  parameters: GoogleImagenParameters
}

interface GoogleInlinePromptPart {
  text?: string
  inline_data?: GoogleInlineData
  inlineData?: GoogleInlineData
}

interface GoogleInlineContent {
  role: string
  parts: GoogleInlinePromptPart[]
}

interface GoogleInlineGenerationConfig {
  responseModalities: string[]
  candidateCount: number
  imageConfig?: GoogleInlineImageConfig
}

interface GoogleInlineImageConfig {
  aspectRatio: string
}

interface GoogleInlineBody {
  contents: GoogleInlineContent[]
  generationConfig: GoogleInlineGenerationConfig
}

interface GoogleImagePrediction {
  bytesBase64Encoded?: string
  mimeType?: string
}

interface GoogleImagePredictResponse {
  predictions?: GoogleImagePrediction[]
}

interface GoogleInlineData {
  mime_type?: string
  mimeType?: string
  data?: string
}

interface GoogleContentPart {
  text?: string
  inline_data?: GoogleInlineData
  inlineData?: GoogleInlineData
}

interface GoogleContent {
  parts?: GoogleContentPart[]
}

interface GoogleCandidate {
  content?: GoogleContent
}

interface GoogleGenerateContentResponse {
  candidates?: GoogleCandidate[]
}

interface XAIImageGenerationBody {
  model: string
  prompt: string
  n: number
  response_format: string
  aspect_ratio: string
}

interface XAIImageInput {
  type: string
  url: string
}

interface XAIImageEditBody {
  model: string
  prompt: string
  n: number
  response_format: string
  aspect_ratio: string
  image?: XAIImageInput
}

interface MinimaxSubjectReference {
  type: string
  image_file: string
}

interface MinimaxImageStyle {
  style_type: string
  style_weight: number
}

interface MinimaxImageGenerationBody {
  model: string
  prompt: string
  aspect_ratio: string
  n: number
  response_format: string
  prompt_optimizer?: boolean
  seed?: number
  subject_reference?: MinimaxSubjectReference[]
  style?: MinimaxImageStyle
}

interface MinimaxImageData {
  image_urls: string[]
}

interface MinimaxBaseResp {
  status_code: number
  status_msg: string
}

interface MinimaxImageResponse {
  data?: MinimaxImageData
  base_resp?: MinimaxBaseResp
}

class ImageApiUrlResolver {
  static buildUrl(baseUrl: string, path: string): string {
    let url = ImageApiUrlResolver.normalizeImageBaseUrl(baseUrl)
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

  private static normalizeImageBaseUrl(baseUrl: string): string {
    let normalized = baseUrl.trim()
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1)
    }
    const lower = normalized.toLowerCase()
    const endpointSuffixes: string[] = [
      '/chat/completions',
      '/responses',
      '/images/generations',
      '/images/edits'
    ]
    for (let i = 0; i < endpointSuffixes.length; i++) {
      const suffix = endpointSuffixes[i]
      if (lower.endsWith(suffix)) {
        return normalized.substring(0, normalized.length - suffix.length)
      }
    }
    return normalized
  }
}

export class ImageGenerationService {
  private static instance: ImageGenerationService | null = null
  private rcpClient: ImageGenerationRcpClient = getImageGenerationRcpClient()

  static getInstance(): ImageGenerationService {
    if (ImageGenerationService.instance === null) {
      ImageGenerationService.instance = new ImageGenerationService()
    }
    return ImageGenerationService.instance
  }

  async generateImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const result = await this.generateImageOnce(provider, model, request, controller)
    return await this.fillMissingImages(false, provider, model, request, result, controller)
  }

  async editImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const result = await this.editImageOnce(provider, model, request, controller)
    return await this.fillMissingImages(true, provider, model, request, result, controller)
  }

  private async generateImageOnce(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    if (provider.apiStyle === ApiStyle.GOOGLE) {
      return await this.generateGoogleImage(provider, model, request, controller)
    }
    if (this.isMinimaxProvider(provider)) {
      return await this.generateMinimaxImage(provider, model, request, controller)
    }
    if (this.isXAIProvider(provider)) {
      return await this.generateXAIImage(provider, model, request, controller)
    }
    if (provider.apiStyle !== ApiStyle.OPENAI) {
      throw new Error('当前模型或服务商不支持图片生成接口')
    }
    return await this.generateOpenAIImage(provider, model, request, controller)
  }

  private async editImageOnce(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    if (provider.apiStyle === ApiStyle.GOOGLE) {
      return await this.editGoogleImage(provider, model, request, controller)
    }
    if (this.isMinimaxProvider(provider)) {
      return await this.editMinimaxImage(provider, model, request, controller)
    }
    if (this.isXAIProvider(provider)) {
      return await this.editXAIImage(provider, model, request, controller)
    }
    if (provider.apiStyle !== ApiStyle.OPENAI) {
      throw new Error('当前模型暂不支持参考图编辑,请移除参考图或切换模型')
    }
    return await this.editOpenAIImage(provider, model, request, controller)
  }

  private async fillMissingImages(
    editMode: boolean,
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    initialResult: ImageGenerationResult,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const targetCount = this.normalizeCount(request.numberOfImages)
    this.logImageCount('initial', provider, model, targetCount, initialResult.items.length)
    if (initialResult.items.length >= targetCount) {
      this.trimResultItems(initialResult, targetCount)
      return initialResult
    }

    let attempt = 0
    while (initialResult.items.length < targetCount && attempt < targetCount - 1) {
      if (controller !== undefined && controller.isCancelled()) {
        return initialResult
      }
      attempt += 1
      const remaining = targetCount - initialResult.items.length
      const retryRequest = this.copyRequestWithCount(request, remaining)
      console.warn('ImageGenerationService',
        `Provider returned fewer images than requested; retrying missing images ` +
        `provider=${provider.id} model=${model.id} missing=${remaining} attempt=${attempt}`)
      try {
        const retryResult = editMode
          ? await this.editImageOnce(provider, model, retryRequest, controller)
          : await this.generateImageOnce(provider, model, retryRequest, controller)
        this.logImageCount('retry', provider, model, remaining, retryResult.items.length)
        this.appendResultItems(initialResult, retryResult, targetCount)
        if (retryResult.items.length === 0) {
          break
        }
      } catch (error) {
        console.warn('ImageGenerationService', `Retry missing images failed: ${JSON.stringify(error)}`)
        break
      }
    }
    this.logImageCount('final', provider, model, targetCount, initialResult.items.length)
    return initialResult
  }

  private copyRequestWithCount(request: ImageGenerationRequest, count: number): ImageGenerationRequest {
    const next = new ImageGenerationRequest()
    next.providerId = request.providerId
    next.modelId = request.modelId
    next.prompt = request.prompt
    next.numberOfImages = Math.floor(count > 0 ? count : 1)
    next.aspectRatio = request.aspectRatio
    next.referenceImagePaths = request.referenceImagePaths.slice()
    next.quality = request.quality
    next.outputFormat = request.outputFormat
    next.outputCompression = request.outputCompression
    next.moderation = request.moderation
    next.promptOptimizer = request.promptOptimizer
    next.seed = request.seed
    next.styleType = request.styleType
    next.styleWeight = request.styleWeight
    return next
  }

  private appendResultItems(target: ImageGenerationResult, source: ImageGenerationResult, maxCount: number): void {
    for (let i = 0; i < source.items.length && target.items.length < maxCount; i++) {
      target.items.push(source.items[i])
    }
  }

  private trimResultItems(result: ImageGenerationResult, maxCount: number): void {
    if (result.items.length > maxCount) {
      result.items = result.items.slice(0, maxCount)
    }
  }

  private logImageCount(
    stage: string,
    provider: ModelProvider,
    model: ModelInfo,
    requested: number,
    received: number
  ): void {
    console.info('ImageGenerationService',
      `count stage=${stage} provider=${provider.id} model=${model.id} requested=${requested} received=${received}`)
  }

  private async generateOpenAIImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const capabilities = ImageGenerationCapabilityResolver.resolve(provider, model)
    const body: OpenAIImageGenerationBody = {
      model: model.id,
      prompt: request.prompt,
      n: this.normalizeCount(request.numberOfImages),
      size: this.getOpenAIImageSize(request.aspectRatio),
      response_format: 'b64_json'
    }
    this.applyOpenAIGptImageOptions(body, request, capabilities)
    const response = await this.rcpClient.postJson(
      this.buildOpenAIImageUrl(provider, '/images/generations'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return await this.parseOpenAIImageResponse(response, provider, controller, this.getRequestOutputMimeType(request, capabilities))
  }

  private async editOpenAIImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    this.validateReferenceImages(request.referenceImagePaths)
    const capabilities = ImageGenerationCapabilityResolver.resolve(provider, model)
    const url = this.buildOpenAIImageUrl(provider, '/images/edits')
    const headers = this.buildBaseHeaders(provider)
    const multipart = this.buildOpenAIEditMultipartForm(model.id, request, capabilities)
    const response = await this.rcpClient.postMultipart(url, headers, multipart, controller)
    return await this.parseOpenAIImageResponse(response, provider, controller, this.getRequestOutputMimeType(request, capabilities))
  }

  private async generateMinimaxImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const body: MinimaxImageGenerationBody = {
      model: model.id,
      prompt: request.prompt,
      aspect_ratio: this.getGoogleAspectRatio(request.aspectRatio),
      n: this.normalizeCount(request.numberOfImages, 9),
      response_format: 'url'
    }
    if (request.promptOptimizer) {
      body.prompt_optimizer = true
    }
    if (request.seed >= 0) {
      body.seed = request.seed
    }
    if (request.styleType.trim() !== '') {
      const style: MinimaxImageStyle = {
        style_type: request.styleType.trim(),
        style_weight: request.styleWeight > 0 ? request.styleWeight : 50
      }
      body.style = style
    }
    const response = await this.rcpClient.postJson(
      this.buildOpenAIImageUrl(provider, '/image_generation'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return await this.parseMinimaxResponse(response, controller)
  }

  private async editMinimaxImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    this.validateReferenceImages(request.referenceImagePaths)
    const subjectReferences: MinimaxSubjectReference[] = []
    for (let i = 0; i < request.referenceImagePaths.length; i++) {
      subjectReferences.push({
        type: 'character',
        image_file: `data:${this.resolveMimeType(request.referenceImagePaths[i])};base64,${this.encodeFileBase64(request.referenceImagePaths[i])}`
      })
    }
    const body: MinimaxImageGenerationBody = {
      model: model.id,
      prompt: request.prompt,
      aspect_ratio: this.getGoogleAspectRatio(request.aspectRatio),
      n: this.normalizeCount(request.numberOfImages, 9),
      response_format: 'url',
      subject_reference: subjectReferences
    }
    if (request.promptOptimizer) {
      body.prompt_optimizer = true
    }
    if (request.seed >= 0) {
      body.seed = request.seed
    }
    if (request.styleType.trim() !== '') {
      const style: MinimaxImageStyle = {
        style_type: request.styleType.trim(),
        style_weight: request.styleWeight > 0 ? request.styleWeight : 50
      }
      body.style = style
    }
    const response = await this.rcpClient.postJson(
      this.buildOpenAIImageUrl(provider, '/image_generation'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return await this.parseMinimaxResponse(response, controller)
  }

  private async generateXAIImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const body: XAIImageGenerationBody = {
      model: model.id,
      prompt: request.prompt,
      n: this.normalizeCount(request.numberOfImages),
      response_format: 'b64_json',
      aspect_ratio: this.getXAIAspectRatio(request.aspectRatio)
    }
    const response = await this.rcpClient.postJson(
      this.buildOpenAIImageUrl(provider, '/images/generations'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return await this.parseOpenAIImageResponse(response, provider, controller)
  }

  private async editXAIImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    this.validateReferenceImages(request.referenceImagePaths)
    if (request.referenceImagePaths.length > 1) {
      throw new Error('Grok 图片编辑目前只支持 1 张参考图')
    }
    const imageInputs = this.buildXAIImageInputs(request.referenceImagePaths)
    const body: XAIImageEditBody = {
      model: model.id,
      prompt: request.prompt,
      n: this.normalizeCount(request.numberOfImages),
      response_format: 'b64_json',
      aspect_ratio: this.getXAIAspectRatio(request.aspectRatio)
    }
    body.image = imageInputs[0]
    const response = await this.rcpClient.postJson(
      this.buildOpenAIImageUrl(provider, '/images/edits'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return await this.parseOpenAIImageResponse(response, provider, controller)
  }

  private async generateGoogleImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const normalizedModelId = model.id.toLowerCase()
    if (normalizedModelId.includes('imagen')) {
      return await this.generateGoogleImagen(provider, model, request, controller)
    }
    return await this.generateGoogleInlineImage(provider, model, request, controller)
  }

  private async generateGoogleImagen(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const instance: GoogleImagenInstance = { prompt: request.prompt }
    const parameters: GoogleImagenParameters = {
        sampleCount: this.normalizeCount(request.numberOfImages),
        aspectRatio: this.getGoogleAspectRatio(request.aspectRatio)
    }
    const body: GoogleImagenBody = {
      instances: [instance],
      parameters: parameters
    }
    const response = await this.rcpClient.postJson(
      this.buildGoogleModelUrl(provider, model.id, 'predict'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return this.parseGooglePredictResponse(response)
  }

  private async generateGoogleInlineImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const promptPart: GoogleInlinePromptPart = { text: request.prompt }
    const content: GoogleInlineContent = {
        role: 'user',
        parts: [promptPart]
    }
    const generationConfig: GoogleInlineGenerationConfig = {
        responseModalities: ['TEXT', 'IMAGE'],
        candidateCount: this.normalizeCount(request.numberOfImages),
        imageConfig: {
          aspectRatio: this.getGoogleAspectRatio(request.aspectRatio)
        }
    }
    const body: GoogleInlineBody = {
      contents: [content],
      generationConfig: generationConfig
    }
    const response = await this.rcpClient.postJson(
      this.buildGoogleModelUrl(provider, model.id, 'generateContent'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return this.parseGoogleInlineResponse(response)
  }

  private async editGoogleImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    this.validateReferenceImages(request.referenceImagePaths)
    const normalizedModelId = model.id.toLowerCase()
    if (normalizedModelId.includes('imagen')) {
      throw new Error('Imagen 模型暂不支持参考图编辑,请切换 Gemini 图像模型')
    }
    return await this.editGoogleInlineImage(provider, model, request, controller)
  }

  private async editGoogleInlineImage(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    const parts: GoogleInlinePromptPart[] = []
    parts.push({ text: request.prompt })
    for (let i = 0; i < request.referenceImagePaths.length; i++) {
      parts.push({
        inline_data: {
          mime_type: this.resolveMimeType(request.referenceImagePaths[i]),
          data: this.encodeFileBase64(request.referenceImagePaths[i])
        }
      })
    }
    const content: GoogleInlineContent = {
      role: 'user',
      parts: parts
    }
    const generationConfig: GoogleInlineGenerationConfig = {
      responseModalities: ['TEXT', 'IMAGE'],
      candidateCount: this.normalizeCount(request.numberOfImages),
      imageConfig: {
        aspectRatio: this.getGoogleAspectRatio(request.aspectRatio)
      }
    }
    const body: GoogleInlineBody = {
      contents: [content],
      generationConfig: generationConfig
    }
    const response = await this.rcpClient.postJson(
      this.buildGoogleModelUrl(provider, model.id, 'generateContent'),
      this.buildJsonHeaders(provider),
      JSON.stringify(body),
      controller
    )
    return this.parseGoogleInlineResponse(response)
  }

  private isMinimaxProvider(provider: ModelProvider): boolean {
    return ImageGenerationCapabilityResolver.isMinimaxProvider(provider)
  }

  private isXAIProvider(provider: ModelProvider): boolean {
    const id = provider.id.toLowerCase()
    const name = provider.name.toLowerCase()
    const baseUrl = provider.baseUrl.toLowerCase()
    return id.includes('grok') || id.includes('xai') ||
      name.includes('grok') || name.includes('xai') ||
      baseUrl.includes('api.x.ai')
  }

  private buildOpenAIImageUrl(provider: ModelProvider, path: string): string {
    const baseUrl = provider.baseUrl.trim()
    if (baseUrl === '') {
      throw new Error('当前模型所属服务商地址为空')
    }
    if (/\/v\d+\w*/.test(baseUrl)) {
      return ImageApiUrlResolver.buildUrl(baseUrl, path)
    }
    return ImageApiUrlResolver.buildUrl(baseUrl, `/v1${path}`)
  }

  private buildGoogleModelUrl(provider: ModelProvider, modelId: string, method: string): string {
    let baseUrl = provider.baseUrl.trim()
    if (baseUrl === '') {
      throw new Error('当前模型所属服务商地址为空')
    }
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.slice(0, -1)
    }
    const versionPrefix = /\/v\d+\w*/.test(baseUrl) ? '' : '/v1beta'
    return `${baseUrl}${versionPrefix}/models/${modelId}:${method}`
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

  private getOpenAIImageSize(aspectRatio: ImageAspectRatio): string {
    return ImageGenerationCapabilityResolver.getOpenAIImageSize(aspectRatio)
  }

  private getGoogleAspectRatio(aspectRatio: ImageAspectRatio): string {
    if (aspectRatio === ImageAspectRatio.LANDSCAPE) {
      return '16:9'
    }
    if (aspectRatio === ImageAspectRatio.PORTRAIT) {
      return '9:16'
    }
    return '1:1'
  }

  private getXAIAspectRatio(aspectRatio: ImageAspectRatio): string {
    if (aspectRatio === ImageAspectRatio.LANDSCAPE) {
      return '3:2'
    }
    if (aspectRatio === ImageAspectRatio.PORTRAIT) {
      return '2:3'
    }
    return '1:1'
  }

  private applyOpenAIGptImageOptions(
    body: OpenAIImageGenerationBody,
    request: ImageGenerationRequest,
    capabilities: ImageGenerationRouteCapabilities
  ): void {
    if (!ImageGenerationCapabilityResolver.isOpenAIGptImageRoute(capabilities.route)) {
      return
    }
    const quality = ImageGenerationCapabilityResolver.normalizeQuality(request.quality, capabilities)
    const outputFormat = ImageGenerationCapabilityResolver.normalizeOutputFormat(request.outputFormat, capabilities)
    const moderation = ImageGenerationCapabilityResolver.normalizeModeration(request.moderation, capabilities)
    const compression = ImageGenerationCapabilityResolver.normalizeOutputCompression(
      request.outputCompression,
      outputFormat,
      capabilities
    )
    body.quality = quality
    body.output_format = outputFormat
    body.moderation = moderation
    if (compression >= 0) {
      body.output_compression = compression
    }
  }

  private applyOpenAIGptImageMultipartOptions(
    fields: rcp.MultipartFormFields,
    request: ImageGenerationRequest,
    capabilities: ImageGenerationRouteCapabilities
  ): void {
    if (!ImageGenerationCapabilityResolver.isOpenAIGptImageRoute(capabilities.route)) {
      return
    }
    const quality = ImageGenerationCapabilityResolver.normalizeQuality(request.quality, capabilities)
    const outputFormat = ImageGenerationCapabilityResolver.normalizeOutputFormat(request.outputFormat, capabilities)
    const moderation = ImageGenerationCapabilityResolver.normalizeModeration(request.moderation, capabilities)
    const compression = ImageGenerationCapabilityResolver.normalizeOutputCompression(
      request.outputCompression,
      outputFormat,
      capabilities
    )
    fields['quality'] = quality
    fields['output_format'] = outputFormat
    fields['moderation'] = moderation
    fields['response_format'] = 'b64_json'
    if (compression >= 0) {
      fields['output_compression'] = compression.toString()
    }
  }

  private getRequestOutputMimeType(
    request: ImageGenerationRequest,
    capabilities: ImageGenerationRouteCapabilities
  ): string {
    if (!ImageGenerationCapabilityResolver.isOpenAIGptImageRoute(capabilities.route)) {
      return 'image/png'
    }
    const outputFormat = ImageGenerationCapabilityResolver.normalizeOutputFormat(request.outputFormat, capabilities)
    if (outputFormat === ImageGenerationOutputFormat.JPEG) {
      return 'image/jpeg'
    }
    if (outputFormat === ImageGenerationOutputFormat.WEBP) {
      return 'image/webp'
    }
    return 'image/png'
  }

  private normalizeCount(value: number, max: number = 4): number {
    if (value < 1) {
      return 1
    }
    if (value > max) {
      return max
    }
    return Math.floor(value)
  }

  private async parseOpenAIImageResponse(
    response: HttpResponse,
    _provider: ModelProvider,
    controller?: HttpRequestController,
    fallbackMimeType: string = 'image/png'
  ): Promise<ImageGenerationResult> {
    if (!response.success) {
      throw new Error(this.formatImageHttpError(response))
    }
    const parsed = JSON.parse(response.data) as OpenAIImageResponse
    if (parsed.error !== undefined && parsed.error.message !== undefined && parsed.error.message !== '') {
      throw new Error(parsed.error.message)
    }
    const result = new ImageGenerationResult()
    if (parsed.data === undefined || parsed.data.length === 0) {
      throw new Error('图片生成接口未返回图片')
    }
    for (let i = 0; i < parsed.data.length; i++) {
      const item = parsed.data[i]
      if (item.b64_json !== undefined && item.b64_json !== '') {
        result.items.push(this.createOpenAIImageItem(item, fallbackMimeType))
      } else if (item.url !== undefined && item.url !== '') {
        const imageItem = await this.downloadImageAsItem(item.url, controller)
        this.applyOpenAIItemMetadata(imageItem, item)
        result.items.push(imageItem)
      }
    }
    if (result.items.length === 0) {
      throw new Error('图片生成接口未返回可用图片')
    }
    return result
  }

  private parseGooglePredictResponse(response: HttpResponse): ImageGenerationResult {
    if (!response.success) {
      throw new Error(this.formatImageHttpError(response))
    }
    const parsed = JSON.parse(response.data) as GoogleImagePredictResponse
    const result = new ImageGenerationResult()
    if (parsed.predictions !== undefined) {
      for (let i = 0; i < parsed.predictions.length; i++) {
        const prediction = parsed.predictions[i]
        if (prediction.bytesBase64Encoded !== undefined && prediction.bytesBase64Encoded !== '') {
          result.items.push(this.createImageItem(
            prediction.bytesBase64Encoded,
            prediction.mimeType !== undefined && prediction.mimeType !== '' ? prediction.mimeType : 'image/png'
          ))
        }
      }
    }
    if (result.items.length === 0) {
      throw new Error('图片生成接口未返回图片')
    }
    return result
  }

  private async parseMinimaxResponse(
    response: HttpResponse,
    controller?: HttpRequestController
  ): Promise<ImageGenerationResult> {
    if (!response.success) {
      throw new Error(this.formatImageHttpError(response))
    }
    const parsed = JSON.parse(response.data) as MinimaxImageResponse
    if (parsed.base_resp !== undefined && parsed.base_resp.status_code !== 0) {
      throw new Error(parsed.base_resp.status_msg !== undefined && parsed.base_resp.status_msg !== '' ? parsed.base_resp.status_msg : `MiniMax 图片生成失败 (${parsed.base_resp.status_code})`)
    }
    const result = new ImageGenerationResult()
    if (parsed.data === undefined || parsed.data.image_urls === undefined || parsed.data.image_urls.length === 0) {
      throw new Error('图片生成接口未返回图片')
    }
    for (let i = 0; i < parsed.data.image_urls.length; i++) {
      const url = parsed.data.image_urls[i]
      if (url !== '') {
        const imageItem = await this.downloadImageAsItem(url, controller)
        result.items.push(imageItem)
      }
    }
    if (result.items.length === 0) {
      throw new Error('图片生成接口未返回可用图片')
    }
    return result
  }

  private parseGoogleInlineResponse(response: HttpResponse): ImageGenerationResult {
    if (!response.success) {
      throw new Error(this.formatImageHttpError(response))
    }
    const parsed = JSON.parse(response.data) as GoogleGenerateContentResponse
    const result = new ImageGenerationResult()
    if (parsed.candidates !== undefined) {
      for (let i = 0; i < parsed.candidates.length; i++) {
        const parts = parsed.candidates[i].content?.parts
        if (parts === undefined) {
          continue
        }
        for (let j = 0; j < parts.length; j++) {
          const inlineData = parts[j].inline_data !== undefined ? parts[j].inline_data : parts[j].inlineData
          if (inlineData !== undefined && inlineData.data !== undefined && inlineData.data !== '') {
            const mimeType = inlineData.mime_type !== undefined && inlineData.mime_type !== ''
              ? inlineData.mime_type
              : (inlineData.mimeType !== undefined && inlineData.mimeType !== '' ? inlineData.mimeType : 'image/png')
            result.items.push(this.createImageItem(
              inlineData.data,
              mimeType
            ))
          }
        }
      }
    }
    if (result.items.length === 0) {
      throw new Error('图片生成接口未返回图片')
    }
    return result
  }

  private createImageItem(base64Data: string, mimeType: string): ImageGenerationItem {
    const item = new ImageGenerationItem()
    item.base64Data = this.stripDataUrlPrefix(base64Data)
    const dataUrlMimeType = this.resolveDataUrlMimeType(base64Data)
    if (dataUrlMimeType !== '') {
      item.mimeType = dataUrlMimeType
    } else {
      item.mimeType = this.detectMimeTypeFromBase64(item.base64Data, mimeType)
    }
    return item
  }

  private createOpenAIImageItem(item: OpenAIImageResponseItem, fallbackMimeType: string): ImageGenerationItem {
    const imageItem = this.createImageItem(item.b64_json !== undefined ? item.b64_json : '', fallbackMimeType)
    this.applyOpenAIItemMetadata(imageItem, item)
    return imageItem
  }

  private applyOpenAIItemMetadata(imageItem: ImageGenerationItem, item: OpenAIImageResponseItem): void {
    imageItem.revisedPrompt = item.revised_prompt !== undefined ? item.revised_prompt : ''
    imageItem.actualSize = item.size !== undefined ? item.size : ''
    imageItem.actualQuality = item.quality !== undefined ? item.quality : ''
    imageItem.actualOutputFormat = item.output_format !== undefined ? item.output_format : ''
    imageItem.actualOutputCompression = item.output_compression !== undefined ? item.output_compression : -1
    imageItem.actualModeration = item.moderation !== undefined ? item.moderation : ''
  }

  private stripDataUrlPrefix(value: string): string {
    const marker = ';base64,'
    const index = value.indexOf(marker)
    if (value.startsWith('data:') && index !== -1) {
      return value.substring(index + marker.length)
    }
    return value
  }

  private resolveDataUrlMimeType(value: string): string {
    if (!value.startsWith('data:')) {
      return ''
    }
    const end = value.indexOf(';base64,')
    if (end <= 5) {
      return ''
    }
    return value.substring(5, end)
  }

  private detectMimeTypeFromBase64(base64Data: string, fallback: string): string {
    if (base64Data.startsWith('/9j/')) {
      return 'image/jpeg'
    }
    if (base64Data.startsWith('iVBOR')) {
      return 'image/png'
    }
    if (base64Data.startsWith('UklGR')) {
      return 'image/webp'
    }
    return fallback
  }

  private async downloadImageAsItem(url: string, controller?: HttpRequestController): Promise<ImageGenerationItem> {
    const buffer = await this.rcpClient.getBinary(url, {}, controller)
    const base64Helper = new util.Base64Helper()
    const bytes = new Uint8Array(buffer)
    const item = new ImageGenerationItem()
    item.base64Data = base64Helper.encodeToStringSync(bytes)
    item.mimeType = this.guessMimeTypeFromUrl(url)
    return item
  }

  private guessMimeTypeFromUrl(url: string): string {
    const lower = url.toLowerCase()
    if (lower.includes('.jpg') || lower.includes('.jpeg')) {
      return 'image/jpeg'
    }
    if (lower.includes('.webp')) {
      return 'image/webp'
    }
    return 'image/png'
  }

  private validateReferenceImages(paths: string[]): void {
    if (paths.length === 0) {
      throw new Error('请先添加参考图')
    }
    for (let i = 0; i < paths.length; i++) {
      const lower = paths[i].toLowerCase()
      if (!(lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.webp'))) {
        throw new Error('参考图格式不支持,请使用 PNG、JPG 或 WEBP')
      }
      try {
        if (!fileIo.accessSync(paths[i])) {
          throw new Error('not exists')
        }
      } catch (_error) {
        throw new Error('参考图文件不存在')
      }
    }
  }

  private buildXAIImageInputs(paths: string[]): XAIImageInput[] {
    const images: XAIImageInput[] = []
    for (let i = 0; i < paths.length; i++) {
      images.push({
        type: 'image_url',
        url: `data:${this.resolveMimeType(paths[i])};base64,${this.encodeFileBase64(paths[i])}`
      })
    }
    return images
  }

  private encodeFileBase64(path: string): string {
    const base64Helper = new util.Base64Helper()
    return base64Helper.encodeToStringSync(this.readFileBytes(path))
  }

  private buildOpenAIEditMultipartForm(
    modelId: string,
    request: ImageGenerationRequest,
    capabilities: ImageGenerationRouteCapabilities
  ): rcp.MultipartForm {
    const fields: rcp.MultipartFormFields = {
      'model': modelId,
      'prompt': request.prompt,
      'n': this.normalizeCount(request.numberOfImages).toString(),
      'size': this.getOpenAIImageSize(request.aspectRatio)
    }
    this.applyOpenAIGptImageMultipartOptions(fields, request, capabilities)
    if (request.referenceImagePaths.length === 1) {
      fields['image'] = this.toFormFieldFile(request.referenceImagePaths[0], 0)
    } else if (request.referenceImagePaths.length > 1) {
      fields['image[]'] = this.buildOpenAIImageFiles(request.referenceImagePaths)
    }
    return new rcp.MultipartForm(fields)
  }

  private buildOpenAIImageFiles(paths: string[]): rcp.FormFieldFileValue[] {
    const files: rcp.FormFieldFileValue[] = []
    for (let i = 0; i < paths.length; i++) {
      files.push(this.toFormFieldFile(paths[i], i))
    }
    return files
  }

  private toFormFieldFile(path: string, index: number): rcp.FormFieldFileValue {
    return {
      contentType: this.resolveMimeType(path),
      remoteFileName: this.resolveFileName(path, index),
      contentOrPath: path
    }
  }

  private readFileBytes(path: string): Uint8Array {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      return new Uint8Array(buffer)
    } catch (error) {
      console.error('ImageGenerationService', `Read reference image failed: ${JSON.stringify(error)}`)
      throw new Error(`Read reference image failed: ${JSON.stringify(error)}`)
    } finally {
      if (file !== null) {
        try {
          fileIo.closeSync(file)
        } catch (error) {
          console.error('ImageGenerationService', `Close reference image failed: ${JSON.stringify(error)}`)
        }
      }
    }
  }

  private resolveFileName(path: string, index: number): string {
    const parts = path.split('/')
    const name = parts.length > 0 ? parts[parts.length - 1] : ''
    if (name !== '') {
      return name
    }
    return `reference_${index + 1}.png`
  }

  private resolveMimeType(path: string): string {
    const lower = path.toLowerCase()
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg'
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp'
    }
    return 'image/png'
  }

  private formatImageHttpError(response: HttpResponse): string {
    const apiMessage = this.extractImageApiErrorMessage(response.data)
    if (apiMessage !== '') {
      return apiMessage
    }
    if (response.statusCode === 401 || response.statusCode === 403) {
      return '认证失败,请检查 API Key'
    }
    if (response.statusCode === 404) {
      return '当前模型或服务商不支持图片生成接口'
    }
    if (response.statusCode === 429) {
      return '请求过于频繁,请稍后重试'
    }
    if (response.errorMessage !== '') {
      return response.errorMessage
    }
    return `图片生成失败 (${response.statusCode})`
  }

  private extractImageApiErrorMessage(data: string): string {
    const trimmed = data.trim()
    if (trimmed === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object>
      const errorObj = parsed['error'] as Record<string, string> | undefined
      if (errorObj !== undefined) {
        const error = errorObj
        if (error['message'] !== undefined && error['message'] !== '') {
          if (error['param'] !== undefined && error['param'] !== '') {
            return `${error['message']} (${error['param']})`
          }
          return error['message']
        }
      }
      const baseRespObj = parsed['base_resp'] as Record<string, Object> | undefined
      if (baseRespObj !== undefined) {
        const statusCode = baseRespObj['status_code'] as number | undefined
        const statusMsg = baseRespObj['status_msg'] as string | undefined
        if (statusCode !== undefined && statusCode !== 0 && statusMsg !== undefined && statusMsg !== '') {
          return statusMsg
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

export function getImageGenerationService(): ImageGenerationService {
  return ImageGenerationService.getInstance()
}
