/**
 * 动画片播放启动器：ChatPage 请求打开，Index 在根节点上挂全屏 content cover。
 *
 * 为什么不在 ChatPage 里 push 路由：宽屏时对话区是 NavigationMode.Split，
 * push 出来的页面只会渲染在右分栏里，不是真全屏（2026-11-11 真机截图）。
 */

import { CartoonPlayerRouteParams } from '../models/CartoonModels'

type CartoonPlayerLaunchHandler = (params: CartoonPlayerRouteParams) => void

let launchHandler: CartoonPlayerLaunchHandler | null = null

export function registerCartoonPlayerLauncher(handler: CartoonPlayerLaunchHandler | null): void {
  launchHandler = handler
}

export function launchCartoonPlayer(params: CartoonPlayerRouteParams): boolean {
  if (launchHandler === null) {
    return false
  }
  launchHandler(params)
  return true
}
