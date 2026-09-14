/**
 * CardShellState - 外壳共享响应式状态
 *
 * 卡片持有本实例并在游戏逻辑中写入; CardShell 通过 @Param 接收后
 * 只读渲染。@ObservedV2 + @Trace 保证跨组件响应式(与 AppUiState 同模式)。
 * 判定逻辑留在卡片 — 本类只是状态容器, 不含游戏规则。
 */

@ObservedV2
export class CardShellState {
  /** 已选中有效作答(选项/输入非空), 控制确认按钮显隐 */
  @Trace hasSelection: boolean = false
  /** 本地已判定(原各卡 showResult), 控制反馈横幅显隐 */
  @Trace submitted: boolean = false
  /** 判定结果 */
  @Trace isCorrect: boolean = false
  /** 音频播放中(重听区波形/文案) */
  @Trace isPlaying: boolean = false
  /** 反馈横幅标题覆写; '' 时用 config.feedbackTitleCorrect(对)/'再试一次'(错) */
  @Trace feedbackTitle: string = ''
  /** 反馈横幅副行, 如 '配对 3/3 · 失误 1 次'; '' 不渲染 */
  @Trace feedbackDetail: string = ''
  /** 头部右侧文字徽章, 如 '🔥 3' / '🏆 最佳 5'; '' 不渲染 */
  @Trace headBadge: string = ''
  /** 头部状态药丸文字, 如 '已回答'/'新纪录'/'已完成'/'已放弃'; '' 不渲染 */
  @Trace headPill: string = ''
  /** 头部状态药丸背景色(#RRGGBB) */
  @Trace headPillColor: string = '#FF6B35'
  /** 反馈横幅右侧徽章, 如 '新纪录'; '' 不渲染 */
  @Trace feedbackBadge: string = ''
  /** 整局结束(胜或弃), 驱动放弃动作隐藏; 与 submitted 分离——放弃时不显示横幅 */
  @Trace isFinished: boolean = false
}
