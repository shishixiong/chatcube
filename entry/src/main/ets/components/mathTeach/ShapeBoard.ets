import { KIDS_MATH_INK, KIDS_MUTED, KIDS_BORDER } from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

interface ShapeTileInfo {
  key: string
  name: string
  sides: number
  corners: number
}

const SHAPE_TILES: ShapeTileInfo[] = [
  { key: 'circle', name: '圆形', sides: 0, corners: 0 },
  { key: 'square', name: '正方形', sides: 4, corners: 4 },
  { key: 'triangle', name: '三角形', sides: 3, corners: 3 },
  { key: 'rectangle', name: '长方形', sides: 4, corners: 4 }
]

@ComponentV2
export struct ShapeBoard {
  @Param focus: string = 'circle'
  @Param readonly: boolean = false
  @Local selectedKey: string = ''
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.selectedKey = this.focus
  }

  private infoOf(key: string): ShapeTileInfo {
    for (let i = 0; i < SHAPE_TILES.length; i++) {
      if (SHAPE_TILES[i].key === key) { return SHAPE_TILES[i] }
    }
    return SHAPE_TILES[0]
  }

  private statText(): string {
    const info: ShapeTileInfo = this.infoOf(this.selectedKey)
    return info.name + '：' + info.sides + ' 条边、' + info.corners + ' 个角'
  }

  private isCircleSelected(): boolean {
    return this.selectedKey === 'circle'
  }

  @Builder
  Tile(info: ShapeTileInfo) {
    Column({ space: 6 }) {
      if (info.key === 'circle') {
        Circle().width(46).height(46)
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2)
      } else if (info.key === 'square') {
        Rect().width(42).height(42)
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2).radius(4)
      } else if (info.key === 'triangle') {
        Polygon().width(48).height(44).points([[24, 2], [46, 42], [2, 42]])
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2)
      } else {
        Rect().width(56).height(34)
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2).radius(4)
      }
      Text(info.name).fontSize(12).fontColor(KIDS_MATH_INK)
    }
    .width(84).height(84)
    .justifyContent(FlexAlign.Center)
    .border({
      width: this.selectedKey === info.key ? 2.5 : 1.5,
      style: BorderStyle.Dashed,
      color: this.selectedKey === info.key ? KIDS_MATH_INK : KIDS_BORDER,
      radius: 12
    })
    .accessibilityText('选择' + info.name)
    .onClick(() => {
      if (this.readonly || this.selectedKey === info.key) { return }
      this.selectedKey = info.key
      this.onInteract()
    })
  }

  build() {
    Column({ space: 12 }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(SHAPE_TILES, (info: ShapeTileInfo) => {
          this.Tile(info)
        }, (info: ShapeTileInfo) => info.key)
      }.width('100%')

      Text(this.statText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)

      if (this.isCircleSelected()) {
        Text('圆形没有直边和角，这是它和方、三角最大的不同')
          .fontSize(13).fontColor(KIDS_MUTED)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
