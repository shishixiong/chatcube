/**
 * ImportEnglishImageSheet — 手动导入本地图片到 ENGLISH_QUIZ 缓存
 *
 * 用途：教师/家长在为孩子准备英语词汇图时，可绕过生图模型，从相册选择一张图
 * 并手动指定单词/句子元数据。图片落入 image_index 表的 source='english_quiz'
 * 行；下次小星老师出对应单词/句子的题时，ToolExecutionService.handleEnglishQuiz
 * 的 Tier 1 命中（imageIndex.findByKey(ENGLISH_QUIZ, quizKey)）会优先复用。
 *
 * 约束：
 * - 仅 ENGLISH_QUIZ；LESSON_PLAN 手动导入不在本期范围。
 * - 单张导入 + 单条元数据；批量不在本期范围。
 * - UNIQUE(source, key) 冲突时拒绝写入（不覆盖、不弹确认），通过预检 findByKey
 *   让 UI 区分「成功」与「目标已被占用」。
 */

import { fileIo } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { util } from '@kit.ArkTS'
import { AttachmentType, MessageAttachment } from '../models/ChatModels'
import { ImageSource } from '../models/ImageIndexModels'
import { getAttachmentStorageService } from '../services/AttachmentStorageService'
import { getImageIndexService, ImageIndexService } from '../services/ImageIndexService'
import { AdaptiveImageThumbnail } from './AdaptiveImageThumbnail'
import { showToast } from '../utils/ToastUtil'
import { getAppUiState } from '../state/AppUiState'

const KEY_TYPE_WORD: string = 'word'
const KEY_TYPE_SENTENCE: string = 'sentence'

const STATUS_READY: string = 'ready'

interface PickError extends Error {
  message: string
}

@ComponentV2
export struct ImportEnglishImageSheet {
  @Event onDismiss: () => void = () => {
  }
  @Event onSaved: () => void = () => {
  }

  @Local pickedUri: string = ''
  @Local pickedMime: string = 'image/jpeg'
  @Local pickedBase64: string = ''
  @Local keyType: string = KEY_TYPE_WORD
  @Local textValue: string = ''
  @Local saving: boolean = false
  @Local isPicking: boolean = false
  @Local conflictHint: ResourceStr = ''

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private canSave(): boolean {
    return this.pickedUri !== '' && this.textValue.trim() !== '' && !this.saving && !this.isPicking
  }

  private detectMime(uri: string): string {
    const lower = uri.toLowerCase().split('?')[0]
    if (lower.endsWith('.png')) {
      return 'image/png'
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp'
    }
    return 'image/jpeg'
  }

  private resolveExtension(mimeType: string): string {
    if (mimeType === 'image/png') {
      return '.png'
    }
    if (mimeType === 'image/webp') {
      return '.webp'
    }
    return '.jpg'
  }

  private async pickImage(): Promise<void> {
    if (this.isPicking) {
      return
    }
    this.isPicking = true
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 1
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const photoSelectResult = await photoPicker.select(photoSelectOptions)
      if (photoSelectResult.photoUris.length === 0) {
        return
      }
      const uri = photoSelectResult.photoUris[0]
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const stat = fileIo.statSync(file.fd)
        const buffer = new ArrayBuffer(stat.size)
        fileIo.readSync(file.fd, buffer)
        const base64Helper = new util.Base64Helper()
        const uint8Array = new Uint8Array(buffer)
        const base64Data = base64Helper.encodeToStringSync(uint8Array)
        this.pickedUri = uri
        this.pickedBase64 = base64Data
        this.pickedMime = this.detectMime(uri)
        this.conflictHint = ''
      } finally {
        fileIo.closeSync(file)
      }
    } catch (error) {
      const message = (error as PickError).message ?? String(error)
      console.error('ImportEnglishImageSheet', `pickImage failed: ${message}`)
      showToast(this.getUIContext(), $r('app.string.english_image_import_pick_failed'), 2000)
    } finally {
      this.isPicking = false
    }
  }

  private async handleSave(): Promise<void> {
    if (!this.canSave()) {
      return
    }
    const trimmed = this.textValue.trim()
    const key = ImageIndexService.buildEnglishQuizKey(
      this.keyType === KEY_TYPE_WORD ? trimmed : '',
      this.keyType === KEY_TYPE_SENTENCE ? trimmed : ''
    )
    if (key === '') {
      this.conflictHint = $r('app.string.english_image_import_invalid_input')
      return
    }
    const imageIndex = getImageIndexService()
    // 预检：putEntry 在 UNIQUE 冲突时返回已存在行而非 null，
    // 这里先用 findByKey 让 UI 区分「成功」与「目标已被占用」。
    const existing = await imageIndex.findByKey(ImageSource.ENGLISH_QUIZ, key)
    if (existing !== null) {
      this.conflictHint = $r('app.string.english_image_import_conflict')
      return
    }
    this.saving = true
    try {
      const safeKey = key.replace(/[^a-z0-9_]/gi, '_').substring(0, 60)
      const id = `manual_${Date.now()}_${safeKey}`
      const ext = this.resolveExtension(this.pickedMime)
      const attachment = new MessageAttachment(
        id,
        AttachmentType.IMAGE,
        `${id}${ext}`,
        '',
        this.pickedMime,
        0
      )
      attachment.base64Data = this.pickedBase64
      const filePath = await getAttachmentStorageService().saveAttachment(attachment)
      if (filePath === '') {
        showToast(this.getUIContext(), $r('app.string.english_image_import_save_failed'), 2000)
        return
      }
      const row = await imageIndex.putEntry(
        ImageSource.ENGLISH_QUIZ,
        key,
        filePath,
        '',
        this.pickedMime
      )
      // 并发场景下 putEntry 仍可能返回 existing row；用 createdAt 判定是否本次新建
      if (row === null || row.status !== STATUS_READY || (Date.now() - row.createdAt > 5000)) {
        this.conflictHint = $r('app.string.english_image_import_conflict')
        return
      }
      this.onSaved()
    } catch (error) {
      const message = (error as PickError).message ?? String(error)
      console.error('ImportEnglishImageSheet', `save failed: ${message}`)
      showToast(this.getUIContext(), $r('app.string.english_image_import_save_failed'), 2000)
    } finally {
      this.saving = false
    }
  }

  private getPreviewSrc(): string {
    if (this.pickedUri === '') {
      return ''
    }
    if (this.pickedUri.startsWith('file://')) {
      return this.pickedUri
    }
    return `file://${this.pickedUri}`
  }

  @Builder
  private PickerEmptyZone() {
    Column() {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(36)
        .fontColor([$r('app.color.text_tertiary')])
      Text($r('app.string.english_image_import_pick'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .height(160)
    .border({
      width: 1,
      style: BorderStyle.Dashed,
      color: $r('app.color.divider')
    })
    .borderRadius(12)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.pickImage()
    })
  }

  @Builder
  private PickerFilledZone() {
    Column({ space: 8 }) {
      AdaptiveImageThumbnail({
        src: this.getPreviewSrc(),
        maxWidth: 320,
        maxHeight: 200,
        radius: 10,
        fallbackAspectRatio: 1,
        fillWidth: true,
        clickable: false
      })

      Text($r('app.string.english_image_import_repick'))
        .fontSize(12)
        .fontColor(this.themePrimary)
        .onClick(() => {
          this.pickImage()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private KeyTypeRadio(value: string, label: Resource) {
    Row() {
      Radio({ value: value, group: 'importEnglishImageKeyType' })
        .checked(this.keyType === value)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.keyType = value
            this.conflictHint = ''
          }
        })
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 6 })
    }
    .onClick(() => {
      this.keyType = value
      this.conflictHint = ''
    })
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text($r('app.string.english_image_import_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.divider'))
        .onClick(() => {
          this.onDismiss()
        })
      }
      .width('100%')

      if (this.pickedUri === '') {
        this.PickerEmptyZone()
      } else {
        this.PickerFilledZone()
      }

      Row({ space: 24 }) {
        this.KeyTypeRadio(KEY_TYPE_WORD, $r('app.string.english_image_import_word'))
        this.KeyTypeRadio(KEY_TYPE_SENTENCE, $r('app.string.english_image_import_sentence'))
      }
      .width('100%')

      TextInput({
        placeholder: this.keyType === KEY_TYPE_WORD
          ? $r('app.string.english_image_import_word_hint')
          : $r('app.string.english_image_import_sentence_hint'),
        text: this.textValue
      })
        .width('100%')
        .onChange((value: string) => {
          this.textValue = value
          if (this.conflictHint !== '') {
            this.conflictHint = ''
          }
        })

      if (this.conflictHint !== '') {
        Text(this.conflictHint)
          .fontSize(12)
          .fontColor('#FF6B6B')
          .width('100%')
      }

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.themeSurface)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.onDismiss()
          })

        Button(this.saving ? $r('app.string.learning_plan_generating') : $r('app.string.save'))
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.canSave() ? this.themePrimary : $r('app.color.divider'))
          .fontColor(Color.White)
          .enabled(this.canSave())
          .onClick(() => {
            this.handleSave()
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 20 })
    .backgroundColor(this.themeBackground)
  }
}