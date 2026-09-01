/**
 * SkillLevelDots 组件
 *
 * 把 0-5 的技能 level 渲染为 5 个 8vp 圆点 (实心 = 已达, 空心 = 未达)。
 *
 * 复用:
 * - pages/LearningProfilePage.ets 的 23 维技能行
 * - pages/LearningTomorrowPlanPage.ets 的 math 教学点 targetSkillLevel
 *
 * Props:
 *   - level: number (0-5, 越界时 clamp 到 [0, 5])
 *   - dotSize: number (可选, 默认 8vp)
 *   - spacing: number (可选, 默认 4vp)
 *   - activeColor: ResourceColor (可选, 默认 text_primary)
 *   - inactiveColor: ResourceColor (可选, 默认 divider)
 */

@ComponentV2
export struct SkillLevelDots {
  @Param level: number = 0
  @Param dotSize: number = 8
  @Param spacing: number = 4
  @Param activeColor: ResourceStr = $r('app.color.text_primary')
  @Param inactiveColor: ResourceStr = $r('app.color.divider')

  build() {
    Row({ space: this.spacing }) {
      ForEach([0, 1, 2, 3, 4], (_unused: number, index: number) => {
        Column()
          .width(this.dotSize)
          .height(this.dotSize)
          .borderRadius(this.dotSize / 2)
          .backgroundColor(index < this.clampLevel() ? this.activeColor : this.inactiveColor)
      }, (item: number) => `${item}`)
    }
  }

  private clampLevel(): number {
    if (this.level < 0) {
      return 0
    }
    if (this.level > 5) {
      return 5
    }
    return Math.floor(this.level)
  }
}
