import { AttachmentProcessState, MessageAttachment, AttachmentType } from '../models/ChatModels'
import {
  BaseItemInfo,
  PhotoSource,
  RecentPhotoComponent,
  RecentPhotoOptions,
  photoAccessHelper
} from '@kit.MediaLibraryKit'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { AdaptiveImageThumbnail } from './AdaptiveImageThumbnail'
import { VoiceRecordButton } from './chat/VoiceRecordButton'

@ComponentV2
export struct ChatInputBar {
  // 图标动画触发器
  @Local iconTrigger: number = 0
  @Local attachIconTrigger: number = 0
  // pause 呼吸动效透明度
  @Local breathOpacity: number = 1
  // 按钮按下状态
  @Local sendBtnPressed: boolean = false
  @Local sendBtnScale: number = 1
  @Local sendBtnRotation: number = 0
  @Local controlsSwapScale: number = 1
  @Local controlsSwapOpacity: number = 1
  @Local modelBtnPressed: boolean = false
  @Param inputText: string = ''
  @Event onInputTextChange: (value: string) => void = (_value: string): void => {}
  @Param attachments: MessageAttachment[] = []
  @Event onAttachmentsChange: (value: MessageAttachment[]) => void = (_value: MessageAttachment[]): void => {}
  @Event onImageClick: (images: Array<string>, imageIndex: number, sourceIds: Array<string>) => void =
    (_images: Array<string>, _imageIndex: number, _sourceIds: Array<string>): void => {}
  @Param isSending: boolean = false
  @Param isVoiceMode: boolean = false
  @Event onVoiceModeToggle: () => void = () => {
  }
  @Event onVoiceRecordStart: () => void = () => {
  }
  @Event onVoiceRecordCancel: () => void = () => {
  }
  @Event onVoiceRecordFinish: () => void = () => {
  }
  @Event onVoiceCancelZoneChange: (isCancel: boolean) => void = (_isCancel: boolean): void => {
  }
  // isSending 为 true 时，pause 在整个发送期都保留轻微呼吸感
  @Param isAwaitingResponse: boolean = false
  // voice mode params
  // 是否自动聚焦输入框
  @Param autoFocus: boolean = false
  @Param sendButtonOnLeft: boolean = false
  // 主题颜色（从 ThemeService 同步）
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeDivider(): string {
    return getAppUiState().themeDivider
  }
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get chatInputEnterKeySend(): boolean {
    return getAppUiState().chatInputEnterKeySend
  }
  // ========== 最近截图相关 ==========
  private recentPhotoOptions: RecentPhotoOptions = new RecentPhotoOptions()
  @Local hasRecentPhoto: boolean = false // 当前是否存在符合时间条件的截图
  // ========== 编辑模式相关属性 ==========
  @Param isEditing: boolean = false // 是否编辑模式
  @Event onCancelEdit: () => void = () => {
  } // 取消编辑回调
  @Event onSend: () => void = () => {
  }
  @Event onStop: () => void = () => {
  }
  @Param isAttachmentPanelOpen: boolean = false
  @Event onAttachmentClick: () => void = () => {
  }
  @Event onInputFocus: () => void = () => {
  } // 输入框获得焦点回调
  @Event onInputBlur: () => void = () => {
  } // 输入框失去焦点回调
  @Event onComposerContentChanged: () => void = () => {
  }
  // 最近截图检测回调（通知父组件渲染 banner）
  @Event onRecentPhotoDetected: (detected: boolean) => void = () => {
  }
  private lastHasContent: boolean = false
  private breatheTimerId: number = -1
  private controlsSwapTimerId: number = -1
  // 焦点控制器

  aboutToAppear(): void {
    this.lastHasContent = this.computeHasContent()
    this.updateBreathing()
    this.initRecentPhotoOptions()
  }

  aboutToDisappear(): void {
    this.stopBreathing()
    this.stopControlsSwapAnimation()
  }

  // 监听 autoFocus 变化
  @Monitor('autoFocus')
  onAutoFocusChanged(): void {
    if (this.autoFocus) {
      // 延迟聚焦，确保组件已渲染
      setTimeout(() => {
        focusControl.requestFocus('chatInputTextArea')
      }, 50)
    }
  }

  @Builder
  private VoiceToggleButton() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.isVoiceMode ? $r('sys.symbol.keyboard') : $r('sys.symbol.mic'))
        .fontSize(20)
        .fontColor([this.isVoiceMode ? this.themePrimary : $r('app.color.text_secondary')])
    }
    .width(40)
    .height(40)
    .enabled(!this.isEditing)
    .opacity(this.isEditing ? 0.4 : 1)
    .backgroundColor(this.modelBtnPressed ? this.themeDivider : this.themeAiBubble)
    .scale({ x: this.modelBtnPressed ? 0.95 : 1, y: this.modelBtnPressed ? 0.95 : 1 })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.modelBtnPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.modelBtnPressed = false
      }
    })
    .onClick(() => {
      if (!this.isSending) {
        this.onVoiceModeToggle()
      }
    })
  }

  @Builder
  private InputTextArea() {
    TextArea({ text: this.inputText, placeholder: $r('app.string.input_placeholder') })
      .id('chatInputTextArea')
      .placeholderColor($r('app.color.text_tertiary'))
      .placeholderFont({ size: 16 })
      .enterKeyType(this.chatInputEnterKeySend ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
      .fontSize(16)
      .fontColor($r('app.color.text_primary'))
      .backgroundColor(Color.Transparent)
      .layoutWeight(1)
      .constraintSize({ minHeight: 40, maxHeight: 120 })
      .padding({
        left: 12,
        right: 12,
        top: 10,
        bottom: 10
      })
      .onChange((value: string) => {
        this.onInputTextChange(value)
      })
      .onSubmit(() => {
        if (!this.chatInputEnterKeySend) {
          return
        }
        if (!this.isSending && this.computeHasContent()) {
          this.onSend()
        }
      })
      .onFocus(() => {
        this.onInputFocus()
      })
      .onBlur(() => {
        this.onInputBlur()
      })
  }

  @Builder
  private AttachmentButton() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(this.getAttachmentButtonSymbol())
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
        .symbolEffect(
          new ReplaceSymbolEffect(EffectScope.WHOLE),
          this.attachIconTrigger
        )
    }
    .width(40)
    .height(40)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      this.onAttachmentClick()
    })
  }

  @Builder
  private SendButton() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(this.getSendButtonSymbol())
        .fontSize(this.isSending ? 20 : 22)
        .fontColor([Color.White])
        .symbolEffect(
          new ReplaceSymbolEffect(EffectScope.WHOLE),
          this.iconTrigger
        )
        .opacity(this.breathOpacity)
        .animation({ duration: 850, curve: Curve.EaseInOut })
    }
    .width(40)
    .height(40)
    .backgroundColor(this.themeUserBubble)
    .opacity(this.getSendButtonOpacity())
    .shadow({
      radius: this.sendBtnPressed ? 24 : 16,
      color: this.themeUserBubble + (this.sendBtnPressed ? '66' : '40'),
      offsetX: 0,
      offsetY: this.sendBtnPressed ? 6 : 4
    })
    .scale({
      x: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale,
      y: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale
    })
    .rotate({ angle: this.sendBtnRotation })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.sendBtnPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.sendBtnPressed = false
      }
    })
    .onClick(() => {
      if (this.isSending && !this.isEditing) {
        this.onStop()
      } else {
        if (!this.computeHasContent()) {
          return
        }
        this.onSend()
      }
    })
  }

  @Builder
  private InputBarRow() {
    Row() {
      // 左侧按钮区: 随握姿翻转
      if (this.sendButtonOnLeft) {
        this.SendButton()
        this.AttachmentButton()
      } else {
        this.VoiceToggleButton()
      }
      // 中间输入区: 固定位置, 不在 if/else 内, 切换握姿时 TextArea 实例保留,
      // 焦点和 input method 会话跨切换不丢失, 键盘不会闪烁收起再弹起
      if (this.isVoiceMode) {
        VoiceRecordButton({
          themePrimary: this.themePrimary,
          themeUserBubble: this.themeUserBubble,
          disabled: this.isSending,
          onRecordStart: (): void => {
            this.onVoiceRecordStart()
          },
          onRecordCancel: (): void => {
            this.onVoiceRecordCancel()
          },
          onRecordFinish: (): void => {
            this.onVoiceRecordFinish()
          },
          onCancelZoneChange: (isCancel: boolean): void => {
            this.onVoiceCancelZoneChange(isCancel)
          }
        })
      } else {
        this.InputTextArea()
      }
      // 右侧按钮区: 随握姿翻转
      if (this.sendButtonOnLeft) {
        this.VoiceToggleButton()
      } else {
        this.AttachmentButton()
        this.SendButton()
      }
    }
      .width('100%')
      .padding({
        left: 6,
        right: 6,
        top: 6,
        bottom: 6
      })
      .opacity(this.controlsSwapOpacity)
      .scale({ x: this.controlsSwapScale, y: this.controlsSwapScale })
      .animation({ duration: 220, curve: Curve.EaseInOut })
  }

  build() {
    Column() {
      // 隐藏的 RecentPhotoComponent 用于检测截图
      this.HiddenRecentPhotoDetector()

      // 编辑模式提示条
      if (this.isEditing) {
        Row() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(12)
            .fontColor([this.themePrimary])

          Text($r('app.string.editing_message'))
            .fontSize(12)
            .fontColor(this.themePrimary)
            .margin({ left: 4 })
        }
        .width('100%')
        .height(28)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.themeAiBubble)
        .borderRadius(8)
        .margin({ bottom: 8 })
      }

      // 附件预览区域
      this.AttachmentPreview()

      this.InputBarRow()
    }
    .width('100%')
    .borderRadius(24)
    .backgroundColor(this.themeAiBubble)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .border({
      width: this.isEditing ? 2 : 0.5,
      color: this.isEditing ? this.themePrimary : this.themeDivider
    })
    .shadow({
      radius: this.isEditing ? 16 : 32,
      color: this.isEditing ? withColorAlpha(this.themePrimary, '26') : 'rgba(0, 0, 0, 0.1)',
      offsetX: 0,
      offsetY: this.isEditing ? -4 : 8
    })
    .animation({ duration: 200 })
    .width('100%')
    .clip(false)
  }

  @Builder
  AttachmentPreview() {
    Scroll() {
      Row() {
        ForEach(this.attachments, (attachment: MessageAttachment, index: number) => {
          this.AttachmentItem(attachment, index)
        })
      }
      .justifyContent(FlexAlign.Start)
      .padding({
        left: 8,
        right: 8,
        top: this.attachments.length > 0 ? 8 : 0,
        bottom: this.attachments.length > 0 ? 4 : 0
      })
      .height(this.attachments.length > 0 ? 'auto' : 0)
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
    .height(this.attachments.length > 0 ? 'auto' : 0)
  }

  // 隐藏的 RecentPhotoComponent 用于检测截图
  @Builder
  HiddenRecentPhotoDetector() {
    RecentPhotoComponent({
      recentPhotoOptions: this.recentPhotoOptions,
      onRecentPhotoClick: (_info: BaseItemInfo): boolean => {
        // 无需处理，我们使用自定义UI
        return true
      },
      onRecentPhotoCheckResult: (exists: boolean): void => this.onReceiveCheckResult(exists)
    })
      .width(0)
      .height(0)
      .opacity(0)
  }

  @Builder
  AttachmentItem(attachment: MessageAttachment, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (attachment.type === AttachmentType.IMAGE) {
        if (this.getAttachmentImageSource(attachment) !== '') {
          AdaptiveImageThumbnail({
            src: this.getAttachmentImageSource(attachment),
            previewId: this.getAttachmentImagePreviewId(attachment, index),
            maxWidth: 72,
            maxHeight: 72,
            radius: 8,
            onPreview: () => {
              this.handleImagePreview(index)
            }
          })
        }
      } else {
        // 文件预览
        Column() {
          SymbolGlyph($r('sys.symbol.doc'))
            .fontSize(22)
            .fontColor([$r('app.color.text_secondary')])

          Text(attachment.name)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 58 })

          if (this.getAttachmentStatusText(attachment) !== '') {
            Text(this.getAttachmentStatusText(attachment))
              .fontSize(9)
              .fontColor(this.getAttachmentStatusColor(attachment))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
              .constraintSize({ maxWidth: 58 })
          }
        }
        .width(72)
        .height(72)
        .borderRadius(8)
        .backgroundColor(this.themeBackground)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 删除按钮
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(10)
          .fontColor([Color.White])
      }
      .width(18)
      .height(18)
      .backgroundColor('rgba(0, 0, 0, 0.6)')
      .margin({ top: -4, right: -4 })
      .onClick(() => {
        this.removeAttachment(index)
      })
    }
    .margin({ right: 8 })
  }

  private getAttachmentImageSource(attachment: MessageAttachment): string {
    if (attachment.filePath !== '') {
      return 'file://' + attachment.filePath
    }
    if (attachment.base64Data !== '') {
      return `data:${attachment.mimeType};base64,${attachment.base64Data}`
    }
    return ''
  }

  private getAttachmentImagePreviewId(attachment: MessageAttachment, originalIndex: number): string {
    if (attachment.id !== '') {
      return 'composer_img_' + attachment.id
    }
    if (attachment.filePath !== '') {
      return 'composer_img_' + attachment.filePath
    }
    return `composer_img_${originalIndex}`
  }

  private handleImagePreview(clickedIndex: number): void {
    const imagePaths: Array<string> = []
    const imageSourceIds: Array<string> = []
    let imageIndex = 0
    let clickedImageFound = false

    for (let i = 0; i < this.attachments.length; i++) {
      const attachment = this.attachments[i]
      if (attachment.type !== AttachmentType.IMAGE) {
        continue
      }
      const imageSource = this.getAttachmentImageSource(attachment)
      if (imageSource === '') {
        continue
      }
      if (i === clickedIndex) {
        imageIndex = imagePaths.length
        clickedImageFound = true
      }
      imagePaths.push(imageSource)
      imageSourceIds.push(this.getAttachmentImagePreviewId(attachment, i))
    }

    if (imagePaths.length > 0 && clickedImageFound) {
      this.onImageClick(imagePaths, imageIndex, imageSourceIds)
    }
  }

  private removeAttachment(index: number): void {
    const newAttachments = [...this.attachments]
    newAttachments.splice(index, 1)
    this.onAttachmentsChange([...newAttachments])
  }

  // ========== 最近截图相关方法 ==========

  // 初始化最近截图组件配置
  private initRecentPhotoOptions(): void {
    // 只监听图片类型
    this.recentPhotoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    // 时间范围：1分钟（60秒），适合刚截图的场景
    this.recentPhotoOptions.period = 60
    // 只监听截图来源
    this.recentPhotoOptions.photoSource = PhotoSource.SCREENSHOT
    console.info('ChatInputBar', 'RecentPhoto options initialized')
  }

  // 最近截图检查结果回调
  private onReceiveCheckResult(exists: boolean): void {
    console.info('ChatInputBar', `RecentPhoto check result: exists=${exists}`)
    this.hasRecentPhoto = exists
    // 通知父组件
    this.onRecentPhotoDetected(exists)
  }

  private computeHasContent(): boolean {
    return this.inputText.trim() !== '' || this.attachments.length > 0
  }

  private computeHasBlockingAttachments(): boolean {
    for (let i = 0; i < this.attachments.length; i++) {
      if (this.isAttachmentBlocking(this.attachments[i])) {
        return true
      }
    }
    return false
  }

  private isAttachmentBlocking(attachment: MessageAttachment): boolean {
    return attachment.processState === AttachmentProcessState.COPYING ||
      attachment.processState === AttachmentProcessState.QUEUED ||
      attachment.processState === AttachmentProcessState.PARSING ||
      attachment.processState === AttachmentProcessState.PARSE_FAILED ||
      attachment.processState === AttachmentProcessState.TOO_LARGE ||
      attachment.processState === AttachmentProcessState.PASSWORD_REQUIRED
  }

  private getAttachmentStatusText(attachment: MessageAttachment): string {
    if (attachment.processState === AttachmentProcessState.QUEUED ||
      attachment.processState === AttachmentProcessState.PARSING ||
      attachment.processState === AttachmentProcessState.COPYING) {
      return '解析中'
    }
    if (attachment.processState === AttachmentProcessState.PARSED) {
      return '已解析'
    }
    if (attachment.processState === AttachmentProcessState.PARSE_FAILED) {
      return '解析失败'
    }
    if (attachment.processState === AttachmentProcessState.TOO_LARGE) {
      return '过大'
    }
    if (attachment.processState === AttachmentProcessState.PASSWORD_REQUIRED) {
      return '加密'
    }
    return ''
  }

  private getAttachmentStatusColor(attachment: MessageAttachment): ResourceColor {
    if (attachment.processState === AttachmentProcessState.PARSED) {
      return '#2E7D32'
    }
    if (attachment.processState === AttachmentProcessState.QUEUED ||
      attachment.processState === AttachmentProcessState.PARSING ||
      attachment.processState === AttachmentProcessState.COPYING) {
      return this.themePrimary
    }
    return '#C62828'
  }

  private getSendButtonOpacity(): number {
    if (!this.isSending && this.computeHasBlockingAttachments()) {
      return 0.45
    }
    return 1
  }

  private getSendButtonSymbol(): Resource {
    if (this.isSending && !this.isEditing) {
      return $r('sys.symbol.pause')
    }

    if (this.computeHasContent()) {
      return $r('sys.symbol.paperplane_right_fill')
    }

    return $r('sys.symbol.paperplane')
  }

  private getAttachmentButtonSymbol(): Resource {
    return this.isAttachmentPanelOpen ? $r('sys.symbol.xmark') : $r('sys.symbol.plus')
  }

  @Monitor('inputText', 'attachments')
  onInputOrAttachmentsChanged(): void {
    if (!this.isSending) {
      this.onComposerContentChanged()
    }
    if (this.isSending) {
      return
    }

    const hasContent = this.computeHasContent()
    if (hasContent === this.lastHasContent) {
      return
    }

    this.lastHasContent = hasContent
    this.iconTrigger++
  }

  @Monitor('isSending')
  onSendingChanged(): void {
    this.iconTrigger++
    this.lastHasContent = this.computeHasContent()
    this.updateBreathing()
    // 发送按钮状态切换动画
    this.animateSendButton()
  }

  @Monitor('isAttachmentPanelOpen')
  onAttachmentPanelOpenChanged(): void {
    this.attachIconTrigger++
  }

  @Monitor('sendButtonOnLeft')
  onSendButtonSideChanged(): void {
    // 注: InputTextArea 已移出 if/else 块, 握姿切换时 TextArea 实例保留,
    // 焦点和键盘会话不丢失, 这里只负责左右按钮区翻转的 swap 动画
    this.stopControlsSwapAnimation()
    this.getUIContext().animateTo({
      duration: 90,
      curve: Curve.EaseOut
    }, () => {
      this.controlsSwapScale = 0.98
      this.controlsSwapOpacity = 0.88
    })
    this.controlsSwapTimerId = setTimeout(() => {
      this.controlsSwapTimerId = -1
      this.getUIContext().animateTo({
        duration: 160,
        curve: Curve.EaseInOut
      }, () => {
        this.controlsSwapScale = 1
        this.controlsSwapOpacity = 1
      })
    }, 90)
  }

  // 发送按钮状态切换动画
  private animateSendButton(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.sendBtnScale = this.isSending ? 0.9 : 1
      this.sendBtnRotation = 0
    })
  }


  @Monitor('isAwaitingResponse')
  onAwaitingChanged(): void {
    this.updateBreathing()
  }

  private updateBreathing(): void {
    if (this.isSending) {
      this.startBreathing()
      return
    }

    this.stopBreathing()
  }

  private startBreathing(): void {
    if (this.breatheTimerId >= 0) {
      return
    }

    this.breathOpacity = 1
    this.breatheTimerId = setInterval(() => {
      this.breathOpacity = this.breathOpacity > 0.8 ? 0.35 : 1
    }, 850)
  }

  private stopBreathing(): void {
    if (this.breatheTimerId < 0) {
      this.breathOpacity = 1
      return
    }

    clearInterval(this.breatheTimerId)
    this.breatheTimerId = -1
    this.breathOpacity = 1
  }

  private stopControlsSwapAnimation(): void {
    if (this.controlsSwapTimerId >= 0) {
      clearTimeout(this.controlsSwapTimerId)
      this.controlsSwapTimerId = -1
    }
    this.controlsSwapScale = 1
    this.controlsSwapOpacity = 1
  }
}
