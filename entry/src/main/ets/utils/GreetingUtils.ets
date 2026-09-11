/**
 * 小星老师「每日首次进入 chat 主动招呼」工具函数
 *
 * 纯函数集合,无 ArkUI 依赖,可直接被 hypium 单元测试覆盖。
 * 唯一的"日期/状态"输入由调用方注入 (lastGreetDate + todayYmd),
 * 便于在测试中固定时间场景。
 */

import { DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'

export interface AutoGreetPredicateArgs {
  /** 是否新会话过渡 (ChatPage 离开已有 session 进入空 session) */
  isNewChatTransition: boolean
  /** 当前激活助手 ID, 仅 'default' (小星老师) 触发 */
  currentAssistantId: string
  /** 当前 session 消息数, 必须为 0 才触发 (避免对老会话补招呼) */
  messagesLength: number
  /** 输入框当前文本, 非空表示小朋友已开始输入 → 取消 */
  inputText: string
  /** 上次招呼日期 'YYYY-MM-DD', 空字符串表示从未招呼过 */
  lastGreetDate: string
  /** 今日 'YYYY-MM-DD' (调用方实时计算,避免函数内部依赖系统时钟) */
  todayYmd: string
}

/**
 * 判断是否应在「当前 chat 页面打开」时触发主动招呼。
 *
 * 5 个短路条件 (任一不满足即返回 false):
 *   1. 必须处于新会话过渡 (避免对老会话骚扰)
 *   2. 必须是小星老师 (其它助手不打招呼)
 *   3. 必须没有历史消息 (空 session)
 *   4. 输入框必须为空 (小朋友没在打字)
 *   5. 今天还没招呼过 (per-day 粒度)
 */
export function shouldAutoGreetToday(args: AutoGreetPredicateArgs): boolean {
  if (!args.isNewChatTransition) {
    return false
  }
  if (args.currentAssistantId !== DEFAULT_ASSISTANT_ID) {
    return false
  }
  if (args.messagesLength !== 0) {
    return false
  }
  if (args.inputText.trim() !== '') {
    return false
  }
  if (args.lastGreetDate === args.todayYmd) {
    return false
  }
  return true
}

/**
 * 主动招呼注入到 system prompt 末尾的元指令 (LLM 可见,小朋友不可见)。
 *
 * 拼接位置: ChatViewModel.injectTeachingSections 末尾, 在「昨日小结 + 教学风格调整 + 今日备课」之后。
 * LLM 注意力上, 末尾段是最近被读到的内容, 优先级最高。
 *
 * 措辞要点:
 *  - "今日与孩子的第一次对话" → 显式标注, 避免模型在多轮上下文里重复招呼
 *  - "1 句温暖的话" → 长度约束, 配合小星老师 system prompt 的 ≤50 字规则
 *  - "结合「今日教学目标」或孩子的「强项」" → 复用已注入的备课段 + child_profile
 *  - "等孩子回复" → 明确不要主动 tool_call (child_profile read 留给下一轮)
 */
export const GREETING_SYSTEM_HINT: string =
  '这是今日与孩子的第一次对话,请先用 1 句温暖的话主动打招呼,' +
  '可结合「今日教学目标」或孩子的「强项」自然切入,然后等孩子回复。'

/**
 * 按小时返回时段问候语 (儿童主屏问候行用)。
 * 分段: <12 早上好; 12-13 中午好; 14-17 下午好; ≥18 晚上好。
 * @param hour 0-23 的本地小时数 (调用方传入, 便于测试)
 */
export function getDayPartGreeting(hour: number): string {
  if (hour < 12) {
    return '早上好'
  }
  if (hour < 14) {
    return '中午好'
  }
  if (hour < 18) {
    return '下午好'
  }
  return '晚上好'
}
