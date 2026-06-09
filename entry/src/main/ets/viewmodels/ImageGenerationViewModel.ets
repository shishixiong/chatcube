import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import {
  AttachmentType,
  DefaultModelConfig,
  MessageAttachment,
  ModelInfo,
  ModelProvider,
  ModelRole,
  OutputMode,
  ApiStyle
} from '../models/ChatModels'
import {
  GeneratedMedia,
  GeneratedMediaType,
  ImageAspectRatio,
  ImageGenerationApiRoute,
  ImageGenerationItem,
  ImageGenerationModeration,
  ImageGenerationOutputFormat,
  ImageGenerationQuality,
  ImageGenerationRequest
} from '../models/ImageGenerationModels'
import { ImagePromptTemplate } from '../models/ImagePromptTemplateModels'
import { getDefaultModelService, DefaultModelService } from '../services/DefaultModelService'
import { getImageGenerationService, ImageGenerationService } from '../services/ImageGenerationService'
import { getGeneratedMediaRepository, GeneratedMediaRepository } from '../services/GeneratedMediaRepository'
import { getAttachmentStorageService, AttachmentStorageService } from '../services/AttachmentStorageService'
import { getBackgroundRunGuardService, BackgroundRunGuardService } from '../services/BackgroundRunGuardService'
import { getChatNotificationService, ChatNotificationService } from '../services/ChatNotificationService'
import { HttpRequestController } from '../services/HttpService'
import { getPreferencesService, PreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { getAITaskService, AITaskService } from '../services/AITaskService'
import { validateProviderConfig } from '../utils/ProviderValidationUtils'
import { ProviderViewModel } from './ProviderViewModel'
import { getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'
import { getSettingsManager, SettingsManager } from './SettingsManager'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'
import { ImageGenerationAlertPayloadData } from '../models/TaskAlertModels'
import {
  ImageGenerationActualOptionsSnapshot,
  ImageGenerationCapabilityResolver,
  ImageGenerationRequestOptionsSnapshot,
  ImageGenerationRouteCapabilities
} from '../services/ImageGenerationCapabilityResolver'
import { getImagePromptTemplateService, ImagePromptTemplateService } from '../services/ImagePromptTemplateService'

// 图片生成 ViewModel 设计为单例：
// 1. 用户进入图片生成页 → 离开（任务可能仍在进行）→ 重新进入 → 仍能看到任务进度和结果
// 2. 任务在 ViewModel 单例上运行，page 销毁不影响任务执行
// 3. 只要 app 进程存活，任务就不会因为页面切换而被打断
@ObservedV2
export class ImageGenerationViewModel {
  private static instance: ImageGenerationViewModel | null = null

  static getInstance(): ImageGenerationViewModel {
    if (ImageGenerationViewModel.instance === null) {
      ImageGenerationViewModel.instance = new ImageGenerationViewModel()
    }
    return ImageGenerationViewModel.instance
  }

  @Trace prompt: string = ''
  @Trace numberOfImages: number = 1
  @Trace aspectRatio: ImageAspectRatio = ImageAspectRatio.SQUARE
  @Trace quality: ImageGenerationQuality = ImageGenerationQuality.AUTO
  @Trace outputFormat: ImageGenerationOutputFormat = ImageGenerationOutputFormat.PNG
  @Trace outputCompression: number = -1
  @Trace moderation: ImageGenerationModeration = ImageGenerationModeration.LOW
  @Trace isGenerating: boolean = false
  @Trace errorMessage: string = ''
  @Trace generationErrorMessage: string = ''
  @Trace currentImages: GeneratedMedia[] = []
  @Trace referenceImages: string[] = []
  @Trace activeTaskType: GeneratedMediaType = GeneratedMediaType.IMAGE_GENERATION
  @Trace galleryItems: GeneratedMedia[] = []
  @Trace selectedProviderId: string = ''
  @Trace selectedModelId: string = ''
  @Trace selectedModelName: string = ''
  @Trace selectedProviderName: string = ''
  @Trace providers: ModelProvider[] = []
  @Trace isProvidersLoaded: boolean = false
  @Trace isOptimizingPrompt: boolean = false
  @Trace promptOptimizer: boolean = false
  @Trace seed: number = -1
  @Trace styleType: string = ''
  @Trace styleWeight: number = -1
  @Trace promptTemplates: ImagePromptTemplate[] = []
  @Trace visiblePromptTemplates: ImagePromptTemplate[] = []
  @Trace promptTemplateRecommendationsVisible: boolean = true

  private defaultModelService: DefaultModelService = getDefaultModelService()
  private providerViewModel: ProviderViewModel = ProviderViewModel.getInstance()
  private imageGenerationService: ImageGenerationService = getImageGenerationService()
  private repository: GeneratedMediaRepository = getGeneratedMediaRepository()
  private attachmentStorageService: AttachmentStorageService = getAttachmentStorageService()
  private settingsManager: SettingsManager = getSettingsManager()
  private backgroundGuard: BackgroundRunGuardService = getBackgroundRunGuardService()
  private notificationService: ChatNotificationService = getChatNotificationService()
  private promptTemplateService: ImagePromptTemplateService = getImagePromptTemplateService()
  private preferencesService: PreferencesService = getPreferencesService()
  private aiTaskService: AITaskService = getAITaskService()
  private activeController: HttpRequestController | null = null
  private generationToken: number = 0
  private readonly promptTemplateBatchSize: number = 5

  // 重入安全：第二次进入页面时只刷新外部数据（providers/gallery），保留任务相关状态
  // （prompt / referenceImages / isGenerating / currentImages 等不动）
  async loadInitialState(): Promise<void> {
    await this.defaultModelService.loadConfig()
    this.providers = await this.providerViewModel.loadProviders()
    this.isProvidersLoaded = true
    // 只有还没选择模型时才应用默认值，避免覆盖用户上次的选择
    if (this.selectedProviderId === '' || this.selectedModelId === '') {
      this.applyDefaultImageModel()
    } else if (!this.isImageModelAvailable(this.selectedProviderId, this.selectedModelId)) {
      // 之前选的模型已被禁用/删除，回退到默认
      this.applyDefaultImageModel()
    }
    this.normalizeOptionsForCurrentRoute()
    await this.trimReferenceImagesForCurrentRoute()
    this.promptTemplateRecommendationsVisible = await this.preferencesService.getBoolean(
      PreferenceKeys.IMAGE_PROMPT_TEMPLATE_RECOMMENDATIONS_VISIBLE,
      true
    )
    await this.refreshPromptTemplates()
    await this.refreshGallery()
  }

  updatePrompt(value: string): void {
    this.prompt = value
  }

  async selectModel(providerId: string, modelId: string, modelName: string): Promise<void> {
    const provider = this.findProvider(providerId)
    if (provider === null) {
      return
    }
    const displayName = modelName !== '' ? modelName : modelId
    this.selectedProviderId = providerId
    this.selectedProviderName = provider.name
    this.selectedModelId = modelId
    this.selectedModelName = displayName
    this.normalizeOptionsForCurrentRoute()
    await this.trimReferenceImagesForCurrentRoute()
    await this.defaultModelService.setModel(
      ModelRole.IMAGE,
      new DefaultModelConfig(modelId, providerId, displayName, provider.name)
    )
  }

  updateNumberOfImages(value: number): void {
    const maxCount = this.getCurrentRouteCapabilities().maxImageCount
    if (value < 1) {
      this.numberOfImages = 1
    } else if (value > maxCount) {
      this.numberOfImages = maxCount
    } else {
      this.numberOfImages = Math.floor(value)
    }
  }

  updateAspectRatio(value: ImageAspectRatio): void {
    this.aspectRatio = value
  }

  updateQuality(value: ImageGenerationQuality): void {
    this.quality = ImageGenerationCapabilityResolver.normalizeQuality(value, this.getCurrentRouteCapabilities())
  }

  updateOutputFormat(value: ImageGenerationOutputFormat): void {
    const capabilities = this.getCurrentRouteCapabilities()
    this.outputFormat = ImageGenerationCapabilityResolver.normalizeOutputFormat(value, capabilities)
    this.outputCompression = ImageGenerationCapabilityResolver.normalizeOutputCompression(
      this.outputCompression,
      this.outputFormat,
      capabilities
    )
  }

  updateOutputCompression(value: number): void {
    this.outputCompression = ImageGenerationCapabilityResolver.normalizeOutputCompression(
      value,
      this.outputFormat,
      this.getCurrentRouteCapabilities()
    )
  }

  updateModeration(value: ImageGenerationModeration): void {
    this.moderation = ImageGenerationCapabilityResolver.normalizeModeration(value, this.getCurrentRouteCapabilities())
  }

  getCurrentRouteCapabilities(): ImageGenerationRouteCapabilities {
    const provider = this.findProvider(this.selectedProviderId)
    return ImageGenerationCapabilityResolver.resolve(provider, this.findModel(provider, this.selectedModelId))
  }

  getMaxReferenceImages(): number {
    return this.getCurrentRouteCapabilities().maxReferenceImages
  }

  canAddReferenceImages(): boolean {
    return !this.isGenerating && this.referenceImages.length < this.getMaxReferenceImages()
  }

  async addReferenceImageUris(uris: string[]): Promise<void> {
    const maxReferenceImages = this.getMaxReferenceImages()
    const next: string[] = this.referenceImages.slice(0, maxReferenceImages)
    for (let i = 0; i < uris.length && next.length < maxReferenceImages; i++) {
      const savedPath = await this.importReferenceImageUri(uris[i], i)
      if (savedPath !== '' && !next.includes(savedPath)) {
        next.push(savedPath)
      }
    }
    this.referenceImages = next
  }

  async addGeneratedMediaAsReference(media: GeneratedMedia): Promise<boolean> {
    if (!this.canAddReferenceImages() || media.filePath === '' || !this.attachmentStorageService.fileExists(media.filePath)) {
      return false
    }
    const savedPath = await this.copyGeneratedMediaToReference(media)
    if (savedPath === '') {
      this.errorMessage = '参考图添加失败'
      return false
    }
    const next: string[] = this.referenceImages.slice(0, this.getMaxReferenceImages())
    next.push(savedPath)
    this.referenceImages = next
    return true
  }

  async removeReferenceImage(path: string): Promise<void> {
    const next = this.referenceImages.filter((item: string): boolean => item !== path)
    this.referenceImages = next
    await this.attachmentStorageService.deleteAttachment(path)
  }

  async clearSession(): Promise<void> {
    const referencePaths = this.referenceImages.slice()
    this.prompt = ''
    this.errorMessage = ''
    this.generationErrorMessage = ''
    this.currentImages = []
    this.referenceImages = []
    for (let i = 0; i < referencePaths.length; i++) {
      await this.attachmentStorageService.deleteAttachment(referencePaths[i])
    }
  }

  canGenerate(): boolean {
    return !this.isGenerating && !this.isOptimizingPrompt && this.prompt.trim() !== '' && this.selectedProviderId !== '' && this.selectedModelId !== ''
  }

  canOptimizePrompt(): boolean {
    return !this.isGenerating && !this.isOptimizingPrompt && this.prompt.trim() !== ''
  }

  isCurrentRequestEditing(): boolean {
    if (this.isGenerating) {
      return this.activeTaskType === GeneratedMediaType.IMAGE_EDIT
    }
    return this.referenceImages.length > 0
  }

  async generate(): Promise<void> {
    if (this.isGenerating) {
      return
    }
    if (this.prompt.trim() === '') {
      return
    }
    this.generationErrorMessage = ''
    const provider = this.findProvider(this.selectedProviderId)
    const model = this.findModel(provider, this.selectedModelId)
    if (provider === null || model === null) {
      this.errorMessage = '请先选择图像生成模型'
      this.generationErrorMessage = this.errorMessage
      return
    }
    if (getEffectiveOutputMode(model) !== OutputMode.IMAGE) {
      this.errorMessage = '当前模型未标记为图片生成模型'
      this.generationErrorMessage = this.errorMessage
      return
    }
    const providerValidation = validateProviderConfig(provider)
    if (!providerValidation.isValid) {
      this.errorMessage = providerValidation.errorMessage
      this.generationErrorMessage = this.errorMessage
      return
    }

    const request = this.buildGenerationRequest()
    const type = request.referenceImagePaths.length > 0 ?
      GeneratedMediaType.IMAGE_EDIT :
      GeneratedMediaType.IMAGE_GENERATION
    const token = this.generationToken + 1
    this.generationToken = token
    this.activeTaskType = type
    const taskId = this.buildGenerationTaskId()
    const controller = new HttpRequestController()
    this.activeController = controller
    this.isGenerating = true
    this.errorMessage = ''
    this.generationErrorMessage = ''
    this.currentImages = []
    this.backgroundGuard.updateImageGenerationRunningTaskCount(1)

    try {
      const result = type === GeneratedMediaType.IMAGE_EDIT
        ? await this.imageGenerationService.editImage(provider, model, request, controller)
        : await this.imageGenerationService.generateImage(provider, model, request, controller)

      if (token !== this.generationToken || controller.isCancelled()) {
        return
      }

      const generated: GeneratedMedia[] = []
      for (let i = 0; i < result.items.length; i++) {
        const media = await this.persistGeneratedItem(result.items[i], provider, model, type, request, i)
        generated.push(media)
      }
      if (token !== this.generationToken || controller.isCancelled()) {
        return
      }
      this.currentImages = generated
      this.errorMessage = this.buildPartialResultMessage(request.numberOfImages, generated.length)
      await this.refreshGallery()
      await this.publishGenerationResult(taskId, type, false, generated.length, '')
    } catch (error) {
      if (token === this.generationToken && !controller.isCancelled()) {
        const message = this.formatError(error)
        this.errorMessage = message
        this.generationErrorMessage = message
        await this.publishGenerationResult(taskId, type, true, 0, message)
      }
    } finally {
      if (token === this.generationToken) {
        this.isGenerating = false
        this.activeController = null
        this.backgroundGuard.updateImageGenerationRunningTaskCount(0)
      }
    }
  }

  async optimizePrompt(): Promise<boolean> {
    if (!this.canOptimizePrompt()) {
      return false
    }
    this.isOptimizingPrompt = true
    this.errorMessage = ''
    this.generationErrorMessage = ''
    try {
      const result = await this.aiTaskService.optimizeImagePrompt(
        this.prompt,
        this.isCurrentRequestEditing(),
        this.referenceImages.length
      )
      if (!result.success) {
        this.errorMessage = result.errorMessage
        this.generationErrorMessage = result.errorMessage
        return false
      }
      this.prompt = result.content
      return true
    } catch (error) {
      console.error('ImageGenerationViewModel', `Optimize prompt failed: ${JSON.stringify(error)}`)
      this.errorMessage = '提示词优化失败'
      this.generationErrorMessage = this.errorMessage
      return false
    } finally {
      this.isOptimizingPrompt = false
    }
  }

  cancelGeneration(): void {
    this.generationToken = this.generationToken + 1
    if (this.activeController !== null) {
      this.activeController.cancelAll()
      this.activeController = null
    }
    this.isGenerating = false
    this.errorMessage = ''
    this.backgroundGuard.updateImageGenerationRunningTaskCount(0)
  }

  async deleteMedia(id: string): Promise<void> {
    const media = this.findMediaById(id)
    if (media !== null) {
      await this.attachmentStorageService.deleteAttachment(media.filePath)
    }
    await this.repository.delete(id)
    this.currentImages = this.currentImages.filter((item: GeneratedMedia): boolean => item.id !== id)
    await this.refreshGallery()
  }

  async refreshGallery(): Promise<void> {
    this.galleryItems = await this.repository.listRecent(200)
  }

  async refreshPromptTemplates(): Promise<void> {
    this.promptTemplates = await this.promptTemplateService.listTemplates()
    this.updateVisiblePromptTemplates()
  }

  async savePromptTemplate(template: ImagePromptTemplate): Promise<void> {
    this.promptTemplates = await this.promptTemplateService.saveTemplate(template)
    this.updateVisiblePromptTemplates()
  }

  async deletePromptTemplate(id: string): Promise<void> {
    this.promptTemplates = await this.promptTemplateService.deleteTemplate(id)
    this.updateVisiblePromptTemplates()
  }

  async resetBuiltinPromptTemplates(): Promise<void> {
    this.promptTemplates = await this.promptTemplateService.resetBuiltins()
    this.updateVisiblePromptTemplates()
  }

  async syncRemotePromptTemplates(): Promise<void> {
    this.promptTemplates = await this.promptTemplateService.syncRemoteBuiltins()
    this.updateVisiblePromptTemplates()
  }

  async setPromptTemplateRecommendationsVisible(visible: boolean): Promise<void> {
    this.promptTemplateRecommendationsVisible = visible
    await this.preferencesService.setBoolean(PreferenceKeys.IMAGE_PROMPT_TEMPLATE_RECOMMENDATIONS_VISIBLE, visible)
    this.updateVisiblePromptTemplates()
  }

  showNextPromptTemplateBatch(): void {
    const availableTemplates = this.getAvailablePromptTemplates()
    if (availableTemplates.length <= this.promptTemplateBatchSize) {
      this.visiblePromptTemplates = this.promptTemplateRecommendationsVisible ? availableTemplates : []
      return
    }
    this.visiblePromptTemplates = this.pickPromptTemplateBatch(availableTemplates)
  }

  private updateVisiblePromptTemplates(): void {
    if (!this.promptTemplateRecommendationsVisible) {
      this.visiblePromptTemplates = []
      return
    }
    const availableTemplates = this.getAvailablePromptTemplates()
    if (availableTemplates.length <= this.promptTemplateBatchSize) {
      this.visiblePromptTemplates = availableTemplates
      return
    }
    this.visiblePromptTemplates = this.pickPromptTemplateBatch(availableTemplates)
  }

  private getAvailablePromptTemplates(): ImagePromptTemplate[] {
    const available: ImagePromptTemplate[] = []
    for (let i = 0; i < this.promptTemplates.length; i++) {
      if (this.promptTemplates[i].prompt.trim() !== '') {
        available.push(this.promptTemplates[i])
      }
    }
    return available
  }

  private pickPromptTemplateBatch(templates: ImagePromptTemplate[]): ImagePromptTemplate[] {
    const pool = templates.slice()
    const selected: ImagePromptTemplate[] = []
    while (pool.length > 0 && selected.length < this.promptTemplateBatchSize) {
      const index = Math.floor(Math.random() * pool.length)
      selected.push(pool[index])
      pool.splice(index, 1)
    }
    return selected
  }

  getSelectedModelLabel(): string {
    if (this.selectedModelName !== '') {
      return this.selectedModelName
    }
    return ''
  }

  private applyDefaultImageModel(): void {
    const config = this.defaultModelService.getModel(ModelRole.IMAGE)
    if (config.isConfigured() && this.isImageModelAvailable(config.providerId, config.modelId)) {
      this.selectedProviderId = config.providerId
      this.selectedProviderName = config.providerName
      this.selectedModelId = config.modelId
      this.selectedModelName = config.getDisplayName()
      return
    }
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      for (let j = 0; j < provider.models.length; j++) {
        const model = provider.models[j]
        if (model.isEnabled && getEffectiveOutputMode(model) === OutputMode.IMAGE) {
          this.selectedProviderId = provider.id
          this.selectedProviderName = provider.name
          this.selectedModelId = model.id
          this.selectedModelName = model.name !== '' ? model.name : model.id
          return
        }
      }
    }
    this.selectedProviderId = ''
    this.selectedProviderName = ''
    this.selectedModelId = ''
    this.selectedModelName = ''
  }

  private isImageModelAvailable(providerId: string, modelId: string): boolean {
    const provider = this.findProvider(providerId)
    const model = this.findModel(provider, modelId)
    return model !== null && model.isEnabled && getEffectiveOutputMode(model) === OutputMode.IMAGE
  }

  private findProvider(providerId: string): ModelProvider | null {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === providerId) {
        return this.providers[i]
      }
    }
    return null
  }

  private findModel(provider: ModelProvider | null, modelId: string): ModelInfo | null {
    if (provider === null) {
      return null
    }
    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        return provider.models[i]
      }
    }
    return null
  }

  private buildGenerationRequest(): ImageGenerationRequest {
    const request = new ImageGenerationRequest()
    request.providerId = this.selectedProviderId
    request.modelId = this.selectedModelId
    request.prompt = this.prompt.trim()
    request.numberOfImages = this.numberOfImages
    request.aspectRatio = this.aspectRatio
    request.referenceImagePaths = this.referenceImages.slice()
    request.quality = this.quality
    request.outputFormat = this.outputFormat
    request.outputCompression = this.outputCompression
    request.moderation = this.moderation
    request.promptOptimizer = this.promptOptimizer
    request.seed = this.seed
    request.styleType = this.styleType
    request.styleWeight = this.styleWeight
    return request
  }

  private async persistGeneratedItem(
    item: ImageGenerationItem,
    provider: ModelProvider,
    model: ModelInfo,
    type: GeneratedMediaType,
    request: ImageGenerationRequest,
    index: number = 0
  ): Promise<GeneratedMedia> {
    const id = `gen_${Date.now()}_${index}_${Math.floor(Math.random() * 100000)}`
    const attachment = new MessageAttachment(
      id,
      AttachmentType.IMAGE,
      `${id}${this.resolveExtension(item.mimeType)}`,
      '',
      item.mimeType,
      0
    )
    attachment.base64Data = item.base64Data
    const filePath = await this.attachmentStorageService.saveAttachment(attachment)
    attachment.base64Data = ''
    if (filePath === '') {
      throw new Error('图片保存失败')
    }

    const media = new GeneratedMedia()
    media.id = id
    media.type = type
    media.prompt = request.prompt
    media.providerId = provider.id
    media.providerName = provider.name
    media.modelId = model.id
    media.modelName = model.name !== '' ? model.name : model.id
    media.filePath = filePath
    media.mimeType = item.mimeType
    media.aspectRatio = request.aspectRatio
    media.sourcePathsJson = JSON.stringify(request.referenceImagePaths)
    media.requestOptionsJson = JSON.stringify(this.buildRequestOptionsSnapshot(provider, model, request))
    media.actualOptionsJson = JSON.stringify(this.buildActualOptionsSnapshot(item))
    media.revisedPrompt = item.revisedPrompt
    media.createdAt = Date.now()
    await this.repository.insert(media)
    return media
  }

  private async importReferenceImageUri(uri: string, index: number): Promise<string> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      let base64Data = ''
      let size = 0
      try {
        const stat = fileIo.statSync(file.fd)
        size = stat.size
        const buffer = new ArrayBuffer(stat.size)
        fileIo.readSync(file.fd, buffer)
        const base64Helper = new util.Base64Helper()
        base64Data = base64Helper.encodeToStringSync(new Uint8Array(buffer))
      } finally {
        fileIo.closeSync(file)
      }
      if (base64Data === '') {
        return ''
      }
      const mimeType = this.resolveMimeTypeFromUri(uri)
      const id = `ref_${Date.now()}_${index}`
      const attachment = new MessageAttachment(
        id,
        AttachmentType.IMAGE,
        `${id}${this.resolveExtension(mimeType)}`,
        '',
        mimeType,
        size
      )
      attachment.base64Data = base64Data
      const filePath = await this.attachmentStorageService.saveAttachment(attachment)
      attachment.base64Data = ''
      if (filePath === '') {
        return ''
      }
      return filePath
    } catch (error) {
      console.error('ImageGenerationViewModel', `Failed to import reference image: ${JSON.stringify(error)}`)
      this.errorMessage = '参考图添加失败'
      return ''
    }
  }

  private async copyGeneratedMediaToReference(media: GeneratedMedia): Promise<string> {
    try {
      const id = `ref_${Date.now()}_${Math.floor(Math.random() * 100000)}`
      const attachment = new MessageAttachment(
        id,
        AttachmentType.IMAGE,
        `${id}${this.resolveExtension(media.mimeType)}`,
        '',
        media.mimeType,
        0
      )
      return await this.attachmentStorageService.importExistingAttachment(media.filePath, attachment)
    } catch (error) {
      console.error('ImageGenerationViewModel', `Failed to copy generated media as reference: ${JSON.stringify(error)}`)
      this.errorMessage = '参考图添加失败'
      return ''
    }
  }

  private resolveMimeTypeFromUri(uri: string): string {
    const lower = uri.toLowerCase()
    if (lower.endsWith('.png')) {
      return 'image/png'
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp'
    }
    return 'image/jpeg'
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

  private findMediaById(id: string): GeneratedMedia | null {
    for (let i = 0; i < this.galleryItems.length; i++) {
      if (this.galleryItems[i].id === id) {
        return this.galleryItems[i]
      }
    }
    for (let i = 0; i < this.currentImages.length; i++) {
      if (this.currentImages[i].id === id) {
        return this.currentImages[i]
      }
    }
    return null
  }

  private formatError(error: Object): string {
    if (error instanceof Error && error.message !== '') {
      return error.message
    }
    return '图片生成失败'
  }

  private buildPartialResultMessage(requestedCount: number, actualCount: number): string {
    if (actualCount >= requestedCount) {
      return ''
    }
    if (actualCount <= 0) {
      return ''
    }
    return `服务商实际只返回 ${actualCount}/${requestedCount} 张图片`
  }

  private normalizeOptionsForCurrentRoute(): void {
    const capabilities = this.getCurrentRouteCapabilities()
    this.quality = ImageGenerationCapabilityResolver.normalizeQuality(this.quality, capabilities)
    this.outputFormat = ImageGenerationCapabilityResolver.normalizeOutputFormat(this.outputFormat, capabilities)
    this.outputCompression = ImageGenerationCapabilityResolver.normalizeOutputCompression(
      this.outputCompression,
      this.outputFormat,
      capabilities
    )
    this.moderation = ImageGenerationCapabilityResolver.normalizeModeration(this.moderation, capabilities)
    this.seed = ImageGenerationCapabilityResolver.normalizeSeed(this.seed!, capabilities)
    this.styleWeight = ImageGenerationCapabilityResolver.normalizeStyleWeight(this.styleWeight!, capabilities)
    this.styleType = ImageGenerationCapabilityResolver.normalizeStyleType(this.styleType!, capabilities)
    if (!capabilities.supportsPromptOptimizer) {
      this.promptOptimizer = false
    }
  }

  private async trimReferenceImagesForCurrentRoute(): Promise<void> {
    const maxReferenceImages = this.getMaxReferenceImages()
    if (this.referenceImages.length <= maxReferenceImages) {
      return
    }
    const removed = this.referenceImages.slice(maxReferenceImages)
    this.referenceImages = this.referenceImages.slice(0, maxReferenceImages)
    for (let i = 0; i < removed.length; i++) {
      await this.attachmentStorageService.deleteAttachment(removed[i])
    }
  }

  private buildRequestOptionsSnapshot(
    provider: ModelProvider,
    model: ModelInfo,
    request: ImageGenerationRequest
  ): ImageGenerationRequestOptionsSnapshot {
    const capabilities = ImageGenerationCapabilityResolver.resolve(provider, model)
    return ImageGenerationCapabilityResolver.buildRequestOptionsSnapshot(
      capabilities.route,
      this.getRouteSize(provider, model, request),
      request.quality,
      request.outputFormat,
      request.outputCompression,
      request.moderation,
      request.promptOptimizer,
      request.seed,
      request.styleType,
      request.styleWeight
    )
  }

  private buildActualOptionsSnapshot(item: ImageGenerationItem): ImageGenerationActualOptionsSnapshot {
    const snapshot = new ImageGenerationActualOptionsSnapshot()
    snapshot.size = item.actualSize
    snapshot.quality = item.actualQuality
    snapshot.outputFormat = item.actualOutputFormat
    snapshot.outputCompression = item.actualOutputCompression
    snapshot.moderation = item.actualModeration
    return snapshot
  }

  private getRouteSize(provider: ModelProvider, model: ModelInfo, request: ImageGenerationRequest): string {
    const capabilities = ImageGenerationCapabilityResolver.resolve(provider, model)
    const route = capabilities.route.toString()
    if (route.startsWith('openai')) {
      return ImageGenerationCapabilityResolver.getOpenAIImageSize(request.aspectRatio)
    }
    if (provider.apiStyle === ApiStyle.GOOGLE || route === ImageGenerationApiRoute.MINIMAX_IMAGE) {
      if (request.aspectRatio === ImageAspectRatio.LANDSCAPE) {
        return '16:9'
      }
      if (request.aspectRatio === ImageAspectRatio.PORTRAIT) {
        return '9:16'
      }
      return '1:1'
    }
    if (request.aspectRatio === ImageAspectRatio.LANDSCAPE) {
      return '3:2'
    }
    if (request.aspectRatio === ImageAspectRatio.PORTRAIT) {
      return '2:3'
    }
    return '1:1'
  }

  private buildGenerationTaskId(): string {
    return `image_task_${Date.now()}_${Math.floor(Math.random() * 10000)}`
  }

  private async publishGenerationResult(
    taskId: string,
    type: GeneratedMediaType,
    failed: boolean,
    imageCount: number,
    errorMessage: string
  ): Promise<void> {
    if (!this.shouldNotifyGenerationResult(failed)) {
      return
    }
    if (this.getAppInBackground()) {
      await this.notificationService.publishImageGenerationResult({
        taskId: taskId,
        failed: failed,
        imageCount: imageCount,
        isEdit: type === GeneratedMediaType.IMAGE_EDIT
      })
      return
    }
    if (this.isImageGenerationPageActive()) {
      return
    }
    this.publishInAppGenerationAlert(taskId, type, failed, imageCount, errorMessage)
  }

  private shouldNotifyGenerationResult(failed: boolean): boolean {
    if (!this.settingsManager.getNotificationEnabled()) {
      return false
    }
    if (failed) {
      return this.settingsManager.getNotifyOnFailedEnabled()
    }
    return this.settingsManager.getNotifyOnCompleteEnabled()
  }

  private publishInAppGenerationAlert(
    taskId: string,
    type: GeneratedMediaType,
    failed: boolean,
    imageCount: number,
    errorMessage: string
  ): void {
    const payload: ImageGenerationAlertPayloadData = {
      id: taskId,
      status: failed ? 'failed' : 'completed',
      message: this.buildGenerationAlertMessage(type, failed, imageCount, errorMessage),
      timestamp: Date.now()
    }
    setAppUiStateValue(AppStorageKeys.IN_APP_IMAGE_GENERATION_ALERT_PAYLOAD, JSON.stringify(payload))
  }

  private buildGenerationAlertMessage(
    type: GeneratedMediaType,
    failed: boolean,
    imageCount: number,
    errorMessage: string
  ): string {
    const isEdit = type === GeneratedMediaType.IMAGE_EDIT
    if (failed) {
      if (errorMessage !== '') {
        return `${isEdit ? '图片编辑' : '图片生成'}失败：${errorMessage}`
      }
      return isEdit ? '图片编辑失败' : '图片生成失败'
    }
    if (isEdit) {
      if (imageCount <= 1) {
        return '图片已编辑，点击查看'
      }
      return `${imageCount} 张图片已编辑，点击查看`
    }
    if (imageCount <= 1) {
      return '图片已生成，点击查看'
    }
    return `${imageCount} 张图片已生成，点击查看`
  }

  private getAppInBackground(): boolean {
    const value = AppStorage.get<boolean>(AppStorageKeys.APP_IN_BACKGROUND)
    return value === true
  }

  private isImageGenerationPageActive(): boolean {
    const value = AppStorage.get<boolean>(AppStorageKeys.ACTIVE_IMAGE_GENERATION_PAGE)
    return value === true
  }
}
