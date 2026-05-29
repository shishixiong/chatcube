import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { inputMethod } from '@kit.IMEKit'
import {
  DefaultMediaModel,
  DefaultMediaType,
  MediaPreview,
  MediaPreviewOptions,
  PromptActionTool
} from '@lyb/media-preview'
import { ModelProvider } from '../models/ChatModels'
import {
  GeneratedMedia,
  ImageAspectRatio,
  ImageGenerationOutputFormat,
  ImageGenerationQuality
} from '../models/ImageGenerationModels'
import { ImageGenerationViewModel } from '../viewmodels/ImageGenerationViewModel'
import { ImagePromptBar } from '../components/imagegen/ImagePromptBar'
import { ImageResultGrid } from '../components/imagegen/ImageResultGrid'
import { ImageGalleryGrid } from '../components/imagegen/ImageGalleryGrid'
import { ImageGenerationSettingsSheet } from '../components/imagegen/ImageGenerationSettingsSheet'
import { ImageGenerationModelSheet } from '../components/imagegen/ImageGenerationModelSheet'
import {
  createImageGenerationPreviewModel,
  getImageGenerationPreviewFallbackId,
  getImageGenerationPreviewId,
  hasGeneratedMediaImage
} from '../components/imagegen/ImageGenerationPreviewUtil'
import { getAppUiState } from '../state/AppUiState'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { saveFileImageToAlbum } from '../utils/RawfileImageSaveUtil'
import { savePreviewImageToAlbumAuthorized } from '../utils/ImagePreviewSaveUtil'
import { getShareService } from '../services/ShareService'
import { showToast } from '../utils/ToastUtil'

let imageGenerationPagePathStack: NavPathStack | null = null
let imageGenerationBackHandler: (() => boolean) | null = null
const IMAGE_PROMPT_TEMPLATE_MANAGER_ROUTE = 'ImagePromptTemplateManagerPage'

@Entry
@ComponentV2
struct ImageGenerationPage {
  @Local viewModel: ImageGenerationViewModel = ImageGenerationViewModel.getInstance()
  @Local currentTabIndex: number = 0
  @Local showSettingsSheet: boolean = false
  @Local showModelSheet: boolean = false
  @Local showDeleteSheet: boolean = false
  @Local showCancelSheet: boolean = false
  @Local pendingDeleteId: string = ''
  @Local isPreviewOpen: boolean = false
  @Local previewCurrentIndex: number = 0
  @Local isPreviewSaving: boolean = false
  @Local isPreviewSharing: boolean = false
  @Local isPreviewPreparingEdit: boolean = false
  private previewDialogId: string = ''
  private previewOptions: MediaPreviewOptions<DefaultMediaModel> | null = null
  private previewSourceItems: GeneratedMedia[] = []
  private swiperController: SwiperController = new SwiperController()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }

  aboutToAppear(): void {
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_IMAGE_GENERATION_PAGE, true)
    imageGenerationBackHandler = (): boolean => {
      return this.handleBack()
    }
    this.viewModel.loadInitialState().catch((error: Object): void => {
      console.error('ImageGenerationPage', `Load initial state failed: ${JSON.stringify(error)}`)
      this.viewModel.errorMessage = '图像生成页面初始化失败'
    })
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_IMAGE_GENERATION_PAGE, false)
    if (!this.isPreviewSharing) {
      this.closeActivePreviewWithoutAnimation()
    }
    if (imageGenerationBackHandler !== null) {
      imageGenerationBackHandler = null
    }
    imageGenerationPagePathStack = null
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private getTopPadding(): number {
    return this.px2vp(getAppUiState().topAvoidHeight)
  }

  private getBottomPadding(): number {
    return Math.max(this.px2vp(getAppUiState().bottomAvoidHeight), 8)
  }

  private getGalleryColumns(): number {
    return this.windowWidthVp >= 720 ? 3 : 2
  }

  private getSelectedProvider(): ModelProvider | null {
    for (let i = 0; i < this.viewModel.providers.length; i++) {
      const provider = this.viewModel.providers[i]
      if (provider.id === this.viewModel.selectedProviderId) {
        return provider
      }
    }
    return null
  }

  private getSelectedProviderIconType(): string {
    const provider = this.getSelectedProvider()
    return provider !== null ? provider.iconType : 'svg'
  }

  private getSelectedProviderIconPath(): string {
    const provider = this.getSelectedProvider()
    return provider !== null ? provider.iconPath : ''
  }

  private getSelectedProviderTextIcon(): string {
    const provider = this.getSelectedProvider()
    return provider !== null ? provider.textIcon : ''
  }

  private getSelectedProviderTextIconBgColor(): string {
    const provider = this.getSelectedProvider()
    return provider !== null ? provider.textIconBgColor : ''
  }

  private getSelectedProviderCustomImagePath(): string {
    const provider = this.getSelectedProvider()
    return provider !== null ? provider.customImagePath : ''
  }

  private getSelectedProviderBrandColor(): ResourceColor {
    const provider = this.getSelectedProvider()
    return provider !== null ? provider.brandColor : ''
  }

  private async safeStopPromptInputSession(): Promise<void> {
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (error) {
      console.error('ImageGenerationPage', `Clear prompt focus failed: ${JSON.stringify(error)}`)
    }
    try {
      await inputMethod.getController().stopInputSession()
    } catch (error) {
      console.error('ImageGenerationPage', `Stop prompt input session failed: ${JSON.stringify(error)}`)
    }
  }

  private async handleOptimizePrompt(): Promise<void> {
    try {
      await this.safeStopPromptInputSession()
      const success = await this.viewModel.optimizePrompt()
      if (success) {
        await this.safeStopPromptInputSession()
        showToast(this.getUIContext(), $r('app.string.image_generation_optimize_prompt_success'))
      } else {
        this.showImageGenerationErrorToast()
      }
    } catch (error) {
      console.error('ImageGenerationPage', `Optimize prompt failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), $r('app.string.image_generation_optimize_prompt_failed'))
    }
  }

  private async handleGenerate(): Promise<void> {
    try {
      await this.safeStopPromptInputSession()
      await this.viewModel.generate()
      this.showImageGenerationErrorToast()
    } catch (error) {
      console.error('ImageGenerationPage', `Generate image failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), '图片生成失败')
    }
  }

  private isEditingMode(): boolean {
    return this.viewModel.isCurrentRequestEditing()
  }

  private showImageGenerationErrorToast(): void {
    if (this.viewModel.generationErrorMessage !== '') {
      showToast(this.getUIContext(), this.viewModel.generationErrorMessage)
    }
  }

  private handleBackNavigation(): boolean {
    if (imageGenerationPagePathStack !== null && imageGenerationPagePathStack.size() > 0) {
      imageGenerationPagePathStack.pop()
      return true
    }
    return false
  }

  private handleBack(): boolean {
    if (this.isPreviewOpen && this.previewDialogId !== '') {
      MediaPreview.close({ dialogId: this.previewDialogId, animated: true })
      return true
    }
    // 允许用户离开页面，任务在后台继续运行（ViewModel 是单例）
    // 想真正取消任务，请使用 prompt bar 上的取消按钮
    if (this.viewModel.isGenerating) {
      showToast(this.getUIContext(), this.isEditingMode() ?
        $r('app.string.image_generation_editing_in_background') :
        $r('app.string.image_generation_running_in_background'))
    }
    return this.handleBackNavigation()
  }

  private async pickReferenceImages(): Promise<void> {
    try {
      const remaining = this.viewModel.getMaxReferenceImages() - this.viewModel.referenceImages.length
      if (remaining <= 0) {
        showToast(this.getUIContext(), this.getReferenceLimitMessage())
        return
      }
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = remaining
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const result = await photoPicker.select(photoSelectOptions)
      if (result.photoUris.length > 0) {
        await this.viewModel.addReferenceImageUris(result.photoUris)
      }
    } catch (error) {
      console.error('ImageGenerationPage', `Pick reference failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), $r('app.string.image_generation_reference_failed'))
    }
  }

  private openPreview(items: GeneratedMedia[], index: number): void {
    const mediaModels: DefaultMediaModel[] = []
    const previewSourceIds: string[] = []
    const sourceItems: GeneratedMedia[] = []
    let previewIndex = 0
    let clickedItemHasImage = false
    for (let i = 0; i < items.length; i++) {
      if (hasGeneratedMediaImage(items[i])) {
        if (i === index) {
          previewIndex = mediaModels.length
          clickedItemHasImage = true
        }
        mediaModels.push(createImageGenerationPreviewModel(items[i]))
        previewSourceIds.push(getImageGenerationPreviewId(items[i]))
        sourceItems.push(items[i])
      }
    }
    if (mediaModels.length === 0 ||
      (index >= 0 && index < items.length && !clickedItemHasImage)) {
      return
    }

    const previewOptions = new MediaPreviewOptions<DefaultMediaModel>()
      .setMedias(mediaModels)
      .setInitIndex(previewIndex)
      .setIdBuilder((_item: DefaultMediaModel, mediaIndex: number): string => {
        return this.getPreviewDialogSourceId(previewSourceIds, mediaIndex)
      })
      .setThumbBuilder((item: DefaultMediaModel, mediaIndex: number): void => {
        this.PreviewThumbBuilder(item, mediaIndex)
      })
      .setPageChangedListener((_item: DefaultMediaModel, mediaIndex: number): void => {
        this.previewCurrentIndex = mediaIndex
      })
      .setBackListener((): void => {
        this.handlePreviewClosed()
      })
      .setToolBuilder((): void => {
        this.PreviewToolBuilder()
      })
      .setShowPageText(mediaModels.length > 1)
      .setIndicator(false)
      .setBackgroundColor(Color.Black)
      .setDismissOnTap(true)
      .setDismissOnDrag(true)
      .setMaxScale(4)
      .setDuration(260)

    this.previewSourceItems = sourceItems
    this.previewCurrentIndex = previewIndex
    this.isPreviewOpen = true
    this.previewDialogId = MediaPreview.open(this.getUIContext(), previewOptions)
    previewOptions.dialogId = this.previewDialogId
    this.previewOptions = previewOptions
  }

  private openReferenceImagePreview(index: number): void {
    const mediaModels: DefaultMediaModel[] = []
    const previewSourceIds: string[] = []
    let previewIndex = 0
    let clickedImageFound = false

    for (let i = 0; i < this.viewModel.referenceImages.length; i++) {
      const path = this.viewModel.referenceImages[i]
      if (path === '') {
        continue
      }
      if (i === index) {
        previewIndex = mediaModels.length
        clickedImageFound = true
      }
      const imageUri = 'file://' + path
      mediaModels.push(new DefaultMediaModel(imageUri, imageUri, DefaultMediaType.IMAGE))
      previewSourceIds.push(this.getReferencePreviewId(path, i))
    }

    if (mediaModels.length === 0 ||
      (index >= 0 && index < this.viewModel.referenceImages.length && !clickedImageFound)) {
      return
    }

    const previewOptions = new MediaPreviewOptions<DefaultMediaModel>()
      .setMedias(mediaModels)
      .setInitIndex(previewIndex)
      .setIdBuilder((_item: DefaultMediaModel, mediaIndex: number): string => {
        return this.getPreviewDialogSourceId(previewSourceIds, mediaIndex)
      })
      .setThumbBuilder((item: DefaultMediaModel, mediaIndex: number): void => {
        this.PreviewThumbBuilder(item, mediaIndex)
      })
      .setBackListener((): void => {
        this.handlePreviewClosed()
      })
      .setShowPageText(mediaModels.length > 1)
      .setIndicator(false)
      .setBackgroundColor(Color.Black)
      .setDismissOnTap(true)
      .setDismissOnDrag(true)
      .setMaxScale(4)
      .setDuration(260)

    this.previewSourceItems = []
    this.previewCurrentIndex = previewIndex
    this.isPreviewOpen = true
    this.previewDialogId = MediaPreview.open(this.getUIContext(), previewOptions)
    previewOptions.dialogId = this.previewDialogId
    this.previewOptions = previewOptions
  }

  private handlePreviewClosed(): void {
    this.isPreviewOpen = false
    this.previewDialogId = ''
    this.previewOptions = null
    this.isPreviewSaving = false
    this.isPreviewSharing = false
    this.isPreviewPreparingEdit = false
    this.previewCurrentIndex = 0
    this.previewSourceItems = []
  }

  private closeActivePreviewWithoutAnimation(): void {
    if (this.previewDialogId !== '') {
      MediaPreview.close({ dialogId: this.previewDialogId, animated: false })
    }
    this.previewDialogId = ''
    this.previewOptions = null
    this.isPreviewOpen = false
    this.previewCurrentIndex = 0
    this.previewSourceItems = []
    this.isPreviewSaving = false
    this.isPreviewSharing = false
    this.isPreviewPreparingEdit = false
  }

  private hasCurrentPreviewMedia(): boolean {
    return this.previewCurrentIndex >= 0 && this.previewCurrentIndex < this.previewSourceItems.length
  }

  private async saveCurrentPreviewMedia(authorized: boolean): Promise<void> {
    if (this.isPreviewSaving || !this.hasCurrentPreviewMedia()) {
      return
    }
    this.isPreviewSaving = true
    try {
      if (authorized) {
        await this.savePreviewMediaAuthorized(this.previewSourceItems[this.previewCurrentIndex])
      } else {
        await this.saveMedia(this.previewSourceItems[this.previewCurrentIndex])
      }
    } finally {
      this.isPreviewSaving = false
    }
  }

  private async continueEditCurrentPreviewMedia(): Promise<void> {
    if (this.isPreviewPreparingEdit || !this.hasCurrentPreviewMedia()) {
      return
    }
    this.isPreviewPreparingEdit = true
    try {
      await this.continueEditMedia(this.previewSourceItems[this.previewCurrentIndex])
    } finally {
      this.isPreviewPreparingEdit = false
    }
  }

  private async shareCurrentPreviewMedia(): Promise<void> {
    if (this.isPreviewSharing || !this.hasCurrentPreviewMedia()) {
      return
    }
    this.isPreviewSharing = true
    this.setPreviewSystemBackEnabled(false)
    try {
      await this.shareMedia(this.previewSourceItems[this.previewCurrentIndex])
    } finally {
      this.setPreviewSystemBackEnabled(true)
      this.isPreviewSharing = false
    }
  }

  private setPreviewSystemBackEnabled(enabled: boolean): void {
    if (this.previewOptions === null || this.previewDialogId === '') {
      return
    }
    try {
      this.previewOptions.dialogId = this.previewDialogId
      this.previewOptions.setDismissOnSystemBack(enabled)
      PromptActionTool.updateCustomDialog(this.previewOptions)
    } catch (error) {
      console.warn('ImageGenerationPage', `Update preview system back failed: ${JSON.stringify(error)}`)
    }
  }

  private getPreviewDialogSourceId(previewSourceIds: string[], mediaIndex: number): string {
    if (mediaIndex >= 0 && mediaIndex < previewSourceIds.length && previewSourceIds[mediaIndex] !== '') {
      return previewSourceIds[mediaIndex]
    }
    return getImageGenerationPreviewFallbackId(mediaIndex)
  }

  private getReferencePreviewId(path: string, index: number): string {
    if (path !== '') {
      return 'image_generation_reference_' + path
    }
    return `image_generation_reference_${index}`
  }

  private getReferenceLimitMessage(): ResourceStr {
    const maxReferenceImages = this.viewModel.getMaxReferenceImages()
    if (maxReferenceImages <= 0) {
      return $r('app.string.image_generation_reference_unsupported')
    }
    if (maxReferenceImages === 1) {
      return $r('app.string.image_generation_reference_limit_one')
    }
    return $r('app.string.image_generation_reference_limit_count', maxReferenceImages)
  }

  private getPreviewModelImageSrc(item: DefaultMediaModel): ResourceStr {
    if (item.thumbSrc !== undefined) {
      return item.thumbSrc
    }
    if (item.sourceSrc !== undefined) {
      return item.sourceSrc
    }
    return ''
  }

  private async saveMedia(media: GeneratedMedia): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await saveFileImageToAlbum(context, media.filePath, 'IMG')
      showToast(this.getUIContext(), $r('app.string.image_generation_save_success'))
    } catch (error) {
      console.error('ImageGenerationPage', `Save image failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), $r('app.string.image_generation_save_failed'))
    }
  }

  private async savePreviewMediaAuthorized(media: GeneratedMedia): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await savePreviewImageToAlbumAuthorized(context, media.filePath)
      showToast(this.getUIContext(), $r('app.string.image_generation_save_success'))
    } catch (error) {
      console.error('ImageGenerationPage', `Save preview image failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), $r('app.string.image_generation_save_failed'))
    }
  }

  private async shareMedia(media: GeneratedMedia): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const shareService = getShareService()
      shareService.init(context)
      const result = await shareService.shareImage(media.filePath, 'generated-image')
      if (!result.success) {
        showToast(this.getUIContext(), $r('app.string.share_failed'))
      }
    } catch (error) {
      console.error('ImageGenerationPage', `Share image failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), $r('app.string.share_failed'))
    }
  }

  private copyPrompt(media: GeneratedMedia): void {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, media.prompt)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setData(pasteboardData)
        .then((): void => {
          showToast(this.getUIContext(), $r('app.string.image_generation_copy_prompt_success'))
        })
        .catch((error: Error): void => {
          console.error('ImageGenerationPage', `Copy prompt failed: ${JSON.stringify(error)}`)
        })
    } catch (error) {
      console.error('ImageGenerationPage', `Copy prompt failed: ${JSON.stringify(error)}`)
    }
  }

  private async continueEditMedia(media: GeneratedMedia): Promise<void> {
    if (this.viewModel.isGenerating) {
      return
    }
    if (!this.viewModel.canAddReferenceImages()) {
      showToast(this.getUIContext(), this.getReferenceLimitMessage())
      return
    }
    const added = await this.viewModel.addGeneratedMediaAsReference(media)
    if (!added) {
      showToast(this.getUIContext(), $r('app.string.image_generation_reference_failed'))
      return
    }
    if (media.prompt !== '') {
      this.viewModel.updatePrompt(media.prompt)
    }
    this.switchTab(0)
    if (this.isPreviewOpen && this.previewDialogId !== '') {
      MediaPreview.close({ dialogId: this.previewDialogId, animated: true })
    }
    showToast(this.getUIContext(), $r('app.string.image_generation_continue_edit_ready'))
  }

  private confirmDelete(media: GeneratedMedia): void {
    this.pendingDeleteId = media.id
    this.showDeleteSheet = true
  }

  private async deletePendingMedia(): Promise<void> {
    const id = this.pendingDeleteId
    this.pendingDeleteId = ''
    this.showDeleteSheet = false
    if (id !== '') {
      await this.viewModel.deleteMedia(id)
    }
  }

  // 加号按钮语义: 新建会话
  // - 在生成中 → disable (避免静默清 currentImages 但任务仍在跑的状态错位)
  // - 在生成 Tab 且业务状态全空 → disable (没东西可清, 避免"点了没反应")
  // - 在图库 Tab 点 → 允许 (顺带切回生成 Tab 有可见反馈)
  private canStartNewSession(): boolean {
    if (this.viewModel.isGenerating) {
      return false
    }
    return this.viewModel.prompt !== ''
      || this.viewModel.currentImages.length > 0
      || this.viewModel.referenceImages.length > 0
      || this.currentTabIndex !== 0
  }

  private startNewSession(): void {
    // 二次防御: 不能打断生成中的请求
    // (按钮 enabled 状态是顶层拦截, 这里防点击瞬间状态变化的竞态)
    if (this.viewModel.isGenerating) {
      return
    }
    const hasContent: boolean = this.viewModel.prompt !== ''
      || this.viewModel.currentImages.length > 0
      || this.viewModel.referenceImages.length > 0
    const needSwitchTab: boolean = this.currentTabIndex !== 0

    if (needSwitchTab) {
      try {
        this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, (): void => {
          this.currentTabIndex = 0
        })
      } catch (_error) {
        this.currentTabIndex = 0
      }
    }

    if (hasContent) {
      this.viewModel.clearSession().catch((error: Object): void => {
        console.error('ImageGenerationPage', `clearSession failed: ${JSON.stringify(error)}`)
      })
    }
  }

  private openPromptTemplateManager(): void {
    if (imageGenerationPagePathStack !== null) {
      imageGenerationPagePathStack.pushPath({ name: IMAGE_PROMPT_TEMPLATE_MANAGER_ROUTE })
    }
  }

  private switchTab(index: number): void {
    if (this.currentTabIndex === index) {
      return
    }
    try {
      this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, (): void => {
        this.currentTabIndex = index
      })
    } catch (_error) {
      this.currentTabIndex = index
    }
  }

  // 一键复用图库 prompt: 填入输入框 + 切回生成 Tab + toast 反馈
  // 不清空 referenceImages, 用户可能在已有参考图基础上想换 prompt 重生成
  private reuseGalleryPrompt(item: GeneratedMedia): void {
    if (item.prompt === '') {
      return
    }
    this.viewModel.updatePrompt(item.prompt)
    this.switchTab(0)
    showToast(this.getUIContext(), $r('app.string.image_generation_prompt_reused'))
  }

  build() {
    Stack() {
      Column() {
        this.Header()
        this.TabBar()

        // Swiper 提供横向滑动切换 + 原生动画;index 与 currentTabIndex 双向同步
        // (点击 Segment / 滑动手势 / startNewSession 都能正确触发对方)
        Swiper(this.swiperController) {
          Column() {
            this.GenerateTab()
          }
          .width('100%')
          .height('100%')

          Column() {
            this.GalleryTab()
          }
          .width('100%')
          .height('100%')
        }
        .index(this.currentTabIndex)
        .loop(false)
        .indicator(false)
        .duration(280)
        .curve(Curve.Friction)
        .cachedCount(1)
        .width('100%')
        .layoutWeight(1)
        .onChange((index: number): void => {
          if (index !== this.currentTabIndex) {
            this.currentTabIndex = index
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBackground)

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSettingsSheet, this.SettingsSheet(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: true,
          title: { title: $r('app.string.image_generation_settings') }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showModelSheet, this.ModelSheet(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: true,
          title: { title: $r('app.string.image_generation_model') }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showDeleteSheet, this.DeleteConfirmSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showCancelSheet, this.CancelConfirmSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Header() {
    Row() {
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('app.color.text_primary')])
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.handleBack()
        })

        Blank()
          .width(40)
          .height(40)
      }
      .width(88)
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.image_generation_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.AI_word_suggest'))
            .fontSize(19)
            .fontColor([this.themePrimary])
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .accessibilityText($r('app.string.image_prompt_template_manage'))
        .onClick(() => {
          this.openPromptTemplateManager()
        })

        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([this.canStartNewSession() ? this.themePrimary : $r('app.color.text_tertiary')])
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .enabled(this.canStartNewSession())
        .onClick(() => {
          this.startNewSession()
        })
      }
      .width(88)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56 + this.getTopPadding())
    .padding({ left: 12, right: 12, top: this.getTopPadding() })
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private PreviewThumbBuilder(item: DefaultMediaModel, _index: number) {
    Image(this.getPreviewModelImageSrc(item))
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Contain)
      .borderRadius(8)
      .clip(true)
      .draggable(false)
  }

  @Builder
  private PreviewToolBuilder() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          if (this.isPreviewPreparingEdit) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('rgba(255, 255, 255, 0.86)')
          } else {
            SymbolGlyph($r('sys.symbol.ai_edit'))
              .fontSize(20)
              .fontColor(['rgba(255, 255, 255, 0.9)'])
          }
        }
        .width(48)
        .height(48)
        .backgroundColor('rgba(8, 12, 18, 0.62)')
        .accessibilityText($r('app.string.image_generation_continue_edit'))
        .enabled(!this.isPreviewPreparingEdit && !this.viewModel.isGenerating && this.hasCurrentPreviewMedia())
        .onClick(() => {
          this.continueEditCurrentPreviewMedia()
        })

        Button({ type: ButtonType.Circle, stateEffect: false }) {
          if (this.isPreviewSharing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('rgba(255, 255, 255, 0.86)')
          } else {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(20)
              .fontColor(['rgba(255, 255, 255, 0.9)'])
          }
        }
        .width(48)
        .height(48)
        .backgroundColor('rgba(8, 12, 18, 0.62)')
        .accessibilityText($r('app.string.menu_share'))
        .enabled(!this.isPreviewSharing && this.hasCurrentPreviewMedia())
        .onClick(() => {
          this.shareCurrentPreviewMedia()
        })

        if (this.isPreviewSaving) {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('rgba(255, 255, 255, 0.86)')
          }
          .width(48)
          .height(48)
          .backgroundColor('rgba(8, 12, 18, 0.62)')
        } else {
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, buttonType: ButtonType.Circle })
            .width(48)
            .height(48)
            .backgroundColor('rgba(8, 12, 18, 0.62)')
            .onClick((_event: ClickEvent, result: SaveButtonOnClickResult): void => {
              if (result !== SaveButtonOnClickResult.SUCCESS) {
                showToast(this.getUIContext(), $r('app.string.image_generation_save_failed'))
                return
              }
              this.saveCurrentPreviewMedia(true)
            })
        }
      }
      .margin({ bottom: 24 + this.px2vp(getAppUiState().bottomAvoidHeight) })
      .hitTestBehavior(HitTestMode.Default)
      .onTouch((event: TouchEvent): void => {
        event.stopPropagation()
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // Segmented control 风格: 单个圆角胶囊外壳 + 浮动主题色指示器 + 双 cell 文字
  // currentTabIndex 变化被 animateTo 包裹, 指示器 translate + 文字 fontColor + 内容区 opacity/translate 全部插值过渡
  @Builder
  private TabBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. 浮动指示器 (背景层)
      Column()
        .width('50%')
        .height('100%')
        .borderRadius(9)
        .backgroundColor(this.themePrimary)
        .translate({ x: this.currentTabIndex === 0 ? 0 : '100%' })

      // 2. 双 cell 文字层 (前景, 透明背景)
      Row() {
        this.SegmentCell(0, $r('app.string.image_generation_tab_generate'))
        this.SegmentCell(1, $r('app.string.image_generation_tab_gallery'))
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(34)
    .borderRadius(11)
    .backgroundColor(this.themeSurface)
    .clip(true)
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  private SegmentCell(index: number, label: Resource) {
    Stack() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentTabIndex === index ? Color.White : $r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .height('100%')
    .onClick(() => {
      this.switchTab(index)
    })
  }

  @Builder
  private GenerateTab() {
    Column() {
      if (this.viewModel.errorMessage !== '') {
        Text(this.viewModel.errorMessage)
          .fontSize(13)
          .fontColor($r('app.color.status_error'))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 6 })
      }

      ImageResultGrid({
        isGenerating: this.viewModel.isGenerating,
        isEditing: this.isEditingMode(),
        items: this.viewModel.currentImages,
        requestedCount: this.viewModel.numberOfImages,
        promptTemplates: this.viewModel.visiblePromptTemplates,
        hasPromptTemplates: this.viewModel.promptTemplates.length > 0,
        canRotatePromptTemplates: this.viewModel.promptTemplates.length > this.viewModel.visiblePromptTemplates.length,
        promptTemplatesVisible: this.viewModel.promptTemplateRecommendationsVisible,
        onPreview: (index: number): void => {
          this.openPreview(this.viewModel.currentImages, index)
        },
        onSave: (item: GeneratedMedia): void => {
          this.saveMedia(item)
        },
        onCopyPrompt: (item: GeneratedMedia): void => {
          this.copyPrompt(item)
        },
        onContinueEdit: (item: GeneratedMedia): void => {
          this.continueEditMedia(item)
        },
        onDelete: (item: GeneratedMedia): void => {
          this.confirmDelete(item)
        },
        onUseTemplate: (prompt: string): void => {
          this.viewModel.updatePrompt(prompt)
        },
        onRotateTemplates: (): void => {
          this.viewModel.showNextPromptTemplateBatch()
        },
        onToggleTemplateVisibility: (): void => {
          this.viewModel.setPromptTemplateRecommendationsVisible(!this.viewModel.promptTemplateRecommendationsVisible).catch((error: Object): void => {
            console.error('ImageGenerationPage', `Toggle prompt template recommendation visibility failed: ${JSON.stringify(error)}`)
          })
        },
        onManageTemplates: (): void => {
          this.openPromptTemplateManager()
        }
      })

      ImagePromptBar({
        prompt: this.viewModel.prompt,
        isGenerating: this.viewModel.isGenerating,
        isEditing: this.isEditingMode(),
        canGenerate: this.viewModel.canGenerate(),
        selectedModelId: this.viewModel.selectedModelId,
        selectedModelName: this.viewModel.getSelectedModelLabel(),
        selectedProviderId: this.viewModel.selectedProviderId,
        selectedProviderIconType: this.getSelectedProviderIconType(),
        selectedProviderIconPath: this.getSelectedProviderIconPath(),
        selectedProviderTextIcon: this.getSelectedProviderTextIcon(),
        selectedProviderTextIconBgColor: this.getSelectedProviderTextIconBgColor(),
        selectedProviderCustomImagePath: this.getSelectedProviderCustomImagePath(),
        selectedProviderBrandColor: this.getSelectedProviderBrandColor(),
        referenceImages: this.viewModel.referenceImages,
        selectedAspectRatio: this.viewModel.aspectRatio,
        canAddReferenceImages: this.viewModel.canAddReferenceImages(),
        canOptimizePrompt: this.viewModel.canOptimizePrompt(),
        isOptimizingPrompt: this.viewModel.isOptimizingPrompt,
        bottomAvoidHeight: this.getBottomPadding(),
        onPromptChange: (value: string): void => {
          this.viewModel.updatePrompt(value)
        },
        onOpenModelSheet: (): void => {
          this.showModelSheet = true
        },
        onOpenSettings: (): void => {
          this.showSettingsSheet = true
        },
        onPickReferenceImages: (): void => {
          this.pickReferenceImages()
        },
        onOptimizePrompt: (): void => {
          this.handleOptimizePrompt()
        },
        onGenerate: (): void => {
          this.handleGenerate()
        },
        onCancel: (): void => {
          this.showCancelSheet = true
        },
        onRemoveReferenceImage: (path: string): void => {
          this.viewModel.removeReferenceImage(path)
        },
        onPreviewReferenceImage: (index: number): void => {
          this.openReferenceImagePreview(index)
        },
        onAspectRatioChange: (value: ImageAspectRatio): void => {
          this.viewModel.updateAspectRatio(value)
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private GalleryTab() {
    Column() {
      ImageGalleryGrid({
        items: this.viewModel.galleryItems,
        columns: this.getGalleryColumns(),
        onPreview: (index: number): void => {
          this.openPreview(this.viewModel.galleryItems, index)
        },
        onSave: (item: GeneratedMedia): void => {
          this.saveMedia(item)
        },
        onCopyPrompt: (item: GeneratedMedia): void => {
          this.copyPrompt(item)
        },
        onContinueEdit: (item: GeneratedMedia): void => {
          this.continueEditMedia(item)
        },
        onDelete: (item: GeneratedMedia): void => {
          this.confirmDelete(item)
        },
        onReusePrompt: (item: GeneratedMedia): void => {
          this.reuseGalleryPrompt(item)
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private SettingsSheet() {
    ImageGenerationSettingsSheet({
      numberOfImages: this.viewModel.numberOfImages,
      selectedAspectRatio: this.viewModel.aspectRatio,
      quality: this.viewModel.quality,
      outputFormat: this.viewModel.outputFormat,
      outputCompression: this.viewModel.outputCompression,
      promptOptimizer: this.viewModel.promptOptimizer,
      seed: this.viewModel.seed,
      styleType: this.viewModel.styleType,
      styleWeight: this.viewModel.styleWeight,
      capabilities: this.viewModel.getCurrentRouteCapabilities(),
      onNumberChange: (value: number): void => {
        this.viewModel.updateNumberOfImages(value)
      },
      onAspectRatioChange: (value: ImageAspectRatio): void => {
        this.viewModel.updateAspectRatio(value)
      },
      onQualityChange: (value: ImageGenerationQuality): void => {
        this.viewModel.updateQuality(value)
      },
      onOutputFormatChange: (value: ImageGenerationOutputFormat): void => {
        this.viewModel.updateOutputFormat(value)
      },
      onOutputCompressionChange: (value: number): void => {
        this.viewModel.updateOutputCompression(value)
      },
      onPromptOptimizerChange: (value: boolean): void => {
        this.viewModel.promptOptimizer = value
      },
      onSeedChange: (value: number): void => {
        this.viewModel.seed = value
      },
      onStyleTypeChange: (value: string): void => {
        this.viewModel.styleType = value
      },
      onStyleWeightChange: (value: number): void => {
        this.viewModel.styleWeight = value
      }
    })
  }

  @Builder
  private ModelSheet() {
    ImageGenerationModelSheet({
      providers: this.viewModel.providers,
      isProvidersLoaded: this.viewModel.isProvidersLoaded,
      currentModelId: this.viewModel.selectedModelId,
      currentProviderId: this.viewModel.selectedProviderId,
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.viewModel.selectModel(providerId, modelId, modelName)
        this.showModelSheet = false
      }
    })
  }

  @Builder
  private DeleteConfirmSheet() {
    this.ConfirmSheet(
      $r('app.string.image_generation_delete_title'),
      $r('app.string.image_generation_delete_message'),
      $r('app.string.delete'),
      (): void => {
        this.deletePendingMedia()
      },
      (): void => {
        this.showDeleteSheet = false
        this.pendingDeleteId = ''
      }
    )
  }

  @Builder
  private CancelConfirmSheet() {
    this.ConfirmSheet(
      this.isEditingMode() ?
        $r('app.string.image_generation_cancel_edit_title') :
        $r('app.string.image_generation_cancel_title'),
      this.isEditingMode() ?
        $r('app.string.image_generation_cancel_edit_message') :
        $r('app.string.image_generation_cancel_message'),
      this.isEditingMode() ?
        $r('app.string.image_generation_cancel_edit') :
        $r('app.string.image_generation_cancel'),
      (): void => {
        this.showCancelSheet = false
        this.viewModel.cancelGeneration()
      },
      (): void => {
        this.showCancelSheet = false
      }
    )
  }

  @Builder
  private ConfirmSheet(
    title: Resource,
    message: Resource,
    confirmText: Resource,
    onConfirm: () => void,
    onCancel: () => void
  ) {
    Column({ space: 16 }) {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(message)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .height(44)
          .layoutWeight(1)
          .backgroundColor(this.themeSurface)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            onCancel()
          })

        Button(confirmText)
          .height(44)
          .layoutWeight(1)
          .backgroundColor($r('app.color.status_error'))
          .fontColor(Color.White)
          .onClick(() => {
            onConfirm()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 28 })
  }
}

@Builder
export function ImageGenerationPageBuilder(_name: string, _param: Object) {
  NavDestination() {
    ImageGenerationPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    imageGenerationPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (imageGenerationBackHandler !== null) {
      return imageGenerationBackHandler()
    }
    return false
  })
}
