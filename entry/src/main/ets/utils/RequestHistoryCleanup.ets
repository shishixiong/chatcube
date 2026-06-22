import { RequestMessage } from '../services/AIApiService'

/**
 * 截断请求历史到最近 N 条, 并清理因截断产生的 orphan tool-result 消息。
 *
 * **背景**: buildConversationRequestHistory 会将一个 ChatMessage.parts 中
 * 多个 completed tool-call 展开成 2N 个 RequestMessage: 形如
 *   [assistant(tool_calls=[t1..tN]), tool(r1), tool(r2), ..., tool(rN)]
 * 直接对展开后的数组做 `slice(-maxHistoryMessages)` 可能在中间切断, 产生
 * `role: 'tool'` 但没有对应 assistant-with-tool_calls 的 orphan 消息。
 * OpenAI 严格校验 "Messages with role 'tool' must be a response to a
 * preceding message with 'tool_calls'", 触发 HTTP 400。
 *
 * **策略**: slice 之后做两轮清理 (迭代直到稳定):
 *  1. 丢弃开头的 tool-result (前置的 assistant 被截掉了)
 *  2. 对每个 assistant-with-tool_calls, 检查其引用的 tool_call_id 是否
 *     全部在剩余数组中能找到对应 tool-result; 若有缺失则整组丢弃
 *     (部分保留会让 OpenAI 报 "tool call ... was not found", 不如整组丢)
 *
 * @param messages 已展开的 RequestMessage 列表
 * @param maxHistoryMessages 上限; <= 0 表示不截断 (与原 ChatViewModel 行为一致)
 * @returns 截断并清理后的新数组
 */
export function truncateRequestHistory(
  messages: RequestMessage[],
  maxHistoryMessages: number
): RequestMessage[] {
  if (maxHistoryMessages <= 0 || messages.length <= maxHistoryMessages) {
    return messages
  }
  let result: RequestMessage[] = messages.slice(messages.length - maxHistoryMessages)

  // 迭代清理: 截断可能把 assistant(tool_calls)+tool(result) 组从中间切断,
  // 反复应用两条规则直到稳定。
  let changed = true
  while (changed) {
    changed = false

    // 规则 1: 丢弃开头的 tool-result (前置的 assistant 被截掉, 这条成 orphan)
    while (result.length > 0 && result[0].isToolResultMessage()) {
      result = result.slice(1)
      changed = true
    }

    // 规则 2: 对每个 assistant-with-tool_calls, 若有 tool_call_id 缺失对应 tool-result, 整组丢弃。
    // 整组丢弃是因为部分保留会让 OpenAI 报 "tool call ... was not found" (仍然 orphan,
    // 只是从另一侧), 整组丢 + 下轮规则 1 兜底更稳。
    for (let i = 0; i < result.length; i++) {
      const msg = result[i]
      if (msg.role === 'assistant' && msg.hasToolCalls()) {
        const requiredIds: Set<string> = new Set()
        for (let j = 0; j < msg.toolCalls.length; j++) {
          requiredIds.add(msg.toolCalls[j].id)
        }
        const foundIds: Set<string> = new Set()
        for (let j = i + 1; j < result.length; j++) {
          const later = result[j]
          if (later.isToolResultMessage() && requiredIds.has(later.toolCallId)) {
            foundIds.add(later.toolCallId)
          }
        }
        if (foundIds.size !== requiredIds.size) {
          result = result.slice(0, i).concat(result.slice(i + 1))
          changed = true
          break
        }
      }
    }
  }

  return result
}
