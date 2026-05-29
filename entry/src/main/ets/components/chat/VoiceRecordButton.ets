@ComponentV2
export struct VoiceRecordButton {
  @Param themePrimary: ResourceColor = '#007AFF'
  @Param themeUserBubble: ResourceColor = '#007AFF'
  @Param disabled: boolean = false
  @Event onRecordStart: () => void = () => {}
  @Event onRecordCancel: () => void = () => {}
  @Event onRecordFinish: () => void = () => {}
  @Event onCancelZoneChange: (isCancel: boolean) => void = (_isCancel: boolean): void => {}
  @Local isPressing: boolean = false
  @Local isCancelZone: boolean = false
  private touchStartY: number = 0
  private readonly cancelThreshold: number = 80

  private get buttonText(): Resource {
    if (this.isCancelZone) {
      return $r('app.string.voice_release_cancel')
    }
    if (this.isPressing) {
      return $r('app.string.voice_release_to_send')
    }
    return $r('app.string.voice_hold_to_speak')
  }

  private get buttonBackground(): ResourceColor {
    if (this.isCancelZone) {
      return '#E03030'
    }
    if (this.isPressing) {
      return this.themeUserBubble
    }
    if (this.disabled) {
      return '#E0E0E0'
    }
    return '#F0F0F0'
  }

  private get buttonTextColor(): ResourceColor {
    if (this.isCancelZone || this.isPressing) {
      return Color.White
    }
    if (this.disabled) {
      return '#BBBBBB'
    }
    return '#555555'
  }

  build() {
    Button(this.buttonText)
      .type(ButtonType.Normal)
      .fontSize(16)
      .fontColor(this.buttonTextColor)
      .backgroundColor(this.buttonBackground)
      .borderRadius(20)
      .layoutWeight(1)
      .height(40)
      .enabled(!this.disabled)
      .scale({
        x: this.isPressing && !this.isCancelZone ? 0.97 : 1,
        y: this.isPressing && !this.isCancelZone ? 0.97 : 1
      })
      .animation({ duration: 150, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        if (this.disabled) {
          return
        }
        if (event.type === TouchType.Down) {
          this.isPressing = true
          this.touchStartY = event.touches[0].y
          this.onRecordStart()
        } else if (event.type === TouchType.Move) {
          if (this.isPressing) {
            const deltaY = this.touchStartY - event.touches[0].y
            this.isCancelZone = deltaY > this.cancelThreshold
            this.onCancelZoneChange(this.isCancelZone)
          }
        } else if (event.type === TouchType.Up) {
          if (this.isPressing) {
            if (this.isCancelZone) {
              this.onRecordCancel()
            } else {
              this.onRecordFinish()
            }
          }
          this.isPressing = false
          this.isCancelZone = false
          this.onCancelZoneChange(false)
        } else if (event.type === TouchType.Cancel) {
          if (this.isPressing) {
            this.onRecordCancel()
          }
          this.isPressing = false
          this.isCancelZone = false
          this.onCancelZoneChange(false)
        }
      })
  }
}
