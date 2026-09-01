/**
 * Session 摘要工具 (供备课老师使用)
 *
 * 备课老师需要"今日与小星老师的对话"作为上下文,但完整 message 列表太长。
 * 本工具:
 * - 截取每条 message 的关键信息 (role / content 摘要 / tool calls / image prompts)
 * - 多个 session 拼装为总长度受限的字符串
 * - 不调 LLM, 全部本地处理
 */

import { ChatMessage, MessageRole } from '../models/ChatModels'
import { ToolCall } from '../models/ChatModels'

export interface PlannerSessionSummary {
  sessionId: string
  topicSummary: string        // 截取的首尾 user/assistant 内容
  keyExchanges: string[]      // 高亮的 3 条 user 消息
  toolsUsed: string[]         // 用过的工具名 (去重)
  skillsObserved: string[]    // 推断接触的 skill_key (math_addition 等)
  messageCount: number
}

/**
 * 截取一条 message 为备课老师可见的摘要。
 * - user/assistant: 取 content 前 N 字符 (含截断标记)
 * - tool: 跳过 (信息密度低,通常很长)
 * - system: 跳过
 */
export function summarizeMessageForPlanner(message: ChatMessage, maxChars: number = 200): string {
  if (message.role === MessageRole.TOOL || message.role === MessageRole.SYSTEM) {
    return ''
  }
  const content = (message.content || '').trim()
  if (content === '') {
    return ''
  }
  if (content.length <= maxChars) {
    return content
  }
  return content.substring(0, maxChars) + '...'
}

/**
 * 提取消息中所有 tool_call 名称 (去重)
 */
export function extractToolsUsed(messages: ChatMessage[]): string[] {
  const set = new Set<string>()
  for (let i = 0; i < messages.length; i++) {
    const tcs: ToolCall[] = messages[i].toolCalls || []
    for (let j = 0; j < tcs.length; j++) {
      const name = (tcs[j].functionName || '').trim()
      if (name !== '') {
        set.add(name)
      }
    }
  }
  return Array.from(set)
}

/**
 * 从 tool_calls 推断接触的 skill_key
 * - math_quiz → 'math_addition' (按参数 difficulty 推断更具体维度,此处用通用兜底)
 * - english_quiz → 'english_vocab'
 * - number_puzzle → 'logic_puzzle'
 * - handwriting_practice → 'observation' (写字与观察力相关)
 *
 * 简化策略: 工具名 → 默认 skill 映射。后续可让小星老师在调用时显式传 skill_key。
 */
export function inferSkillsFromToolCalls(messages: ChatMessage[]): string[] {
  const set = new Set<string>()
  for (let i = 0; i < messages.length; i++) {
    const tcs: ToolCall[] = messages[i].toolCalls || []
    for (let j = 0; j < tcs.length; j++) {
      const name = (tcs[j].functionName || '').toLowerCase().trim()
      switch (name) {
        case 'math_quiz':
        case 'math_verify':
          set.add('math_addition')
          break
        case 'english_quiz':
        case 'listening_quiz':
          set.add('english_vocab')
          break
        case 'number_puzzle':
        case 'huarongdao': // legacy 历史会话工具名, 与 number_puzzle 同义
          set.add('logic_puzzle')
          break
        case 'handwriting_practice':
          set.add('observation')
          break
        default:
          break
      }
    }
  }
  return Array.from(set)
}

/**
 * 生成一个 session 的备课老师摘要。
 */
export function summarizeSessionForPlanner(
  sessionId: string,
  messages: ChatMessage[],
  maxTotalChars: number = 600
): PlannerSessionSummary {
  const summary: PlannerSessionSummary = {
    sessionId: sessionId,
    topicSummary: '',
    keyExchanges: [],
    toolsUsed: extractToolsUsed(messages),
    skillsObserved: inferSkillsFromToolCalls(messages),
    messageCount: messages.length
  }

  // 取前 1 条 user + 最后 1 条 assistant 拼成 topicSummary
  let firstUser = ''
  let lastAssistant = ''
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].role === MessageRole.USER) {
      const c = summarizeMessageForPlanner(messages[i], 100)
      if (c !== '' && firstUser === '') {
        firstUser = c
      }
    }
    if (messages[i].role === MessageRole.ASSISTANT) {
      lastAssistant = summarizeMessageForPlanner(messages[i], 100)
    }
  }
  if (firstUser !== '') {
    summary.topicSummary = `首句: ${firstUser}`
  }
  if (lastAssistant !== '') {
    summary.topicSummary += summary.topicSummary === '' ? lastAssistant : ` | 末句: ${lastAssistant}`
  }

  // 取最多 3 条 user 消息作为 keyExchanges
  const userMsgCount = Math.min(3, messages.filter(m => m.role === MessageRole.USER).length)
  let added = 0
  for (let i = 0; i < messages.length && added < userMsgCount; i++) {
    if (messages[i].role === MessageRole.USER) {
      const c = summarizeMessageForPlanner(messages[i], 120)
      if (c !== '') {
        summary.keyExchanges.push(c)
        added++
      }
    }
  }

  // 截断到 maxTotalChars (简化: 截断 keyExchanges 整体)
  let totalLen = summary.topicSummary.length
  const trimmed: string[] = []
  for (let i = 0; i < summary.keyExchanges.length; i++) {
    const k = summary.keyExchanges[i]
    if (totalLen + k.length + 1 > maxTotalChars) {
      break
    }
    trimmed.push(k)
    totalLen += k.length + 1
  }
  summary.keyExchanges = trimmed

  return summary
}

/**
 * 把 PlannerSessionSummary[] 序列化为 JSON 字符串供 LLM 输入。
 */
export function serializePlannerSessionSummaries(summaries: PlannerSessionSummary[]): string {
  try {
    return JSON.stringify(summaries)
  } catch (_e) {
    return '[]'
  }
}
