// entry/src/main/ets/components/map/ChinaMapStageController.ets
/**
 * ChinaMapStageController - 地图舞台的对外遥控器
 *
 * 缩放/复位本来长在 ChinaMapStage 内部（右下角竖排三键），地图册改版后
 * 控件移到卡片页脚的横向缩放簇——那是 MapCard 的 UI，拿不到舞台实例，
 * 于是用一个 @ObservedV2 遥控器：舞台在 aboutToAppear 里挂上动作并同步
 * zoom 状态，外部只读 @Trace 字段、只调动作，不碰舞台内部手势状态。
 */

@ObservedV2
export class ChinaMapStageController {
  /** 当前缩放倍率（1-4），舞台每次 applyView 后回写 */
  @Trace zoomLevel: number = 1
  @Trace canZoomIn: boolean = true
  @Trace canZoomOut: boolean = false

  /** 由舞台注入 */
  zoomInAction: () => void = () => {}
  zoomOutAction: () => void = () => {}
  resetAction: () => void = () => {}

  zoomIn(): void {
    this.zoomInAction()
  }

  zoomOut(): void {
    this.zoomOutAction()
  }

  reset(): void {
    this.resetAction()
  }
}
