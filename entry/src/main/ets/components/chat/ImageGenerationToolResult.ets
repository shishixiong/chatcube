/**
 * 图片生成工具结果展示组件
 *
 * 在消息气泡的 ToolStepContent 展开区域中渲染, 解析 toolResult JSON
 * 并展示生成的图片缩略图, 点击可放大预览。
 */

// 轻量输出项类型 (只关心 UI 需要展示的字段)
class ImageGenDisplayItem {
  filePath: string = ''
  prompt: string = ''

  constructor(filePath: string, prompt: string) {
    this.filePath = filePath
    this.prompt = prompt
  }
}

function parseOutput(raw: string): ImageGenDisplayItem[] {
  const trimmed = raw.trim()
  if (trimmed === '') {
    return []
  }
  try {
    const obj = JSON.parse(trimmed) as Record<string, Object>
    // ImageGenerationOutput format: { images: [{ filePath, mimeType, prompt, revisedPrompt }] }
    const imagesArr = obj['images'] as Object[] | undefined
    if (imagesArr === undefined || imagesArr === null) {
      return []
    }
    const items: ImageGenDisplayItem[] = []
    for (let i = 0; i < imagesArr.length; i++) {
      const img = imagesArr[i] as Record<string, string>
      const fp = img['filePath'] as string
      const p = img['prompt'] as string
      if (fp !== undefined && fp.trim() !== '') {
        items.push(new ImageGenDisplayItem(fp.trim(), (p !== undefined ? p : '')))
      }
    }
    return items
  } catch (_e) {
    return []
  }
}

@ComponentV2
export struct ImageGenerationToolResult {
  @Param toolResult: string = ''
  @Event onImageClick: (images: Array<string>, index: number) => void =
    (_images: Array<string>, _index: number): void => {}

  @Computed
  get items(): ImageGenDisplayItem[] {
    return parseOutput(this.toolResult)
  }

  @Computed
  get hasItems(): boolean {
    return this.items.length > 0
  }

  build() {
    if (this.hasItems) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.items, (item: ImageGenDisplayItem, index: number) => {
          Image('file://' + item.filePath)
            .width(120)
            .height(120)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .margin({ right: 6, bottom: 6 })
            .onClick(() => {
              const paths: Array<string> = []
              for (let i = 0; i < this.items.length; i++) {
                paths.push('file://' + this.items[i].filePath)
              }
              this.onImageClick(paths, index)
            })
        }, (item: ImageGenDisplayItem, index: number) => `${item.filePath}_${index}`)
      }
      .margin({ top: 6 })
    }
  }
}
