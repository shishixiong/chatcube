/**
 * ChatMessage 旧字段(content/reasoningContent/toolCalls/toolResults)和新 parts 结构之间的桥接。
 *
 * 写流程保持 ChatViewModel 仍然写旧字段,这里在保存/渲染前 "按需" 合成 parts。
 * 读流程优先用 message.parts;为空时 fallback 到旧字段合成的保守顺序,
 * 以便旧会话仍能正常展示。
 */

import {
  ChatMessage,
  MessageRole,
  ToolCall,
  ToolPermissionLevel,
  ToolResult,
  ToolSourceType
} from '../models/ChatModels'
import {
  MessagePart,
  MessagePartKind,
  ToolPartStatus
} from '../models/MessageParts'
import { isSearchWebFunctionName, SEARCH_WEB_TOOL_ID } from './SearchToolIdentityUtils'

export function createToolPart(toolCall: ToolCall, result: ToolResult | null): MessagePart {
  const part = new MessagePart(MessagePartKind.TOOL)
  part.toolCallId = toolCall.id
  part.toolName = toolCall.functionName
  part.toolDisplayName = toolCall.displayName
  part.toolArguments = toolCall.arguments
  part.toolSourceType = toolCall.sourceType
  part.toolSourceLabel = toolCall.sourceLabel
  part.toolPermissionLevel = toolCall.permissionLevel
  part.toolApprovalReason = toolCall.approvalReason
  if (result !== null) {
    part.toolResult = result.content
    part.toolIsError = result.isError
    part.toolStatus = result.isError ? ToolPartStatus.FAILED : ToolPartStatus.SUCCEEDED
  } else {
    part.toolStatus = ToolPartStatus.PENDING
  }
  return part
}

/**
 * 互动卡 timeline step 展开恢复时选择答题 payload 的来源。
 *
 * 背景 bug: ChatViewModel 在本回合出题达上限时会给最后一个 toolResult.content
 * 尾部追加「[系统提示] ...」带内收尾指令 (面向 LLM, 需随历史保留), toolResult
 * 因此不再是纯 JSON——卡片 JSON.parse 失败 → 恢复静默跳过 → isCorrect 保持
 * 默认 false → 横幅误渲染成「再试一次」(孩子答对也判错)。
 * 干净 payload 一直随 part.toolApprovalReason 持久化 (toolCall.approvalReason
 * = answerJson 同步而来, 不被追加污染), 故优先采用; 非对象 JSON (审批态文本等)
 * 时回退 toolResult。
 */
export function resolveStepAnswerPayload(toolResult: string, toolApprovalReason: string): string {
  if (toolApprovalReason.trim().startsWith('{')) {
    return toolApprovalReason
  }
  return toolResult
}

export function hasLegacyMessagePartSource(message: ChatMessage): boolean {
  return message.content.trim() !== '' ||
    message.reasoningContent.trim() !== '' ||
    message.toolCalls.length > 0 ||
    message.toolResults.length > 0 ||
    message.searchReferences.length > 0
}

function createLegacySearchPart(message: ChatMessage): MessagePart {
  const part = new MessagePart(MessagePartKind.TOOL)
  part.toolCallId = 'legacy_search_' + message.id
  part.toolName = SEARCH_WEB_TOOL_ID
  part.toolDisplayName = '联网搜索'
  const query = message.searchQuery.trim()
  part.toolArguments = query !== '' ? JSON.stringify({ query: query }) : '{}'
  part.toolSourceType = ToolSourceType.BUILTIN
  part.toolSourceLabel = message.searchEngine.trim() !== '' ? message.searchEngine.trim() : 'Web'
  part.toolPermissionLevel = ToolPermissionLevel.READ
  part.toolStatus = ToolPartStatus.SUCCEEDED
  part.toolSearchReferences = message.searchReferences.slice()
  return part
}

function findSearchReferenceInsertIndex(parts: MessagePart[]): number {
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].kind !== MessagePartKind.REASONING) {
      return i
    }
  }
  return parts.length
}

function enrichLegacySearchReferences(message: ChatMessage, parts: MessagePart[]): boolean {
  if (message.role !== MessageRole.ASSISTANT || message.searchReferences.length === 0) {
    return false
  }

  let searchPartIndex = -1
  let searchPartCount = 0
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i]
    if (part.kind === MessagePartKind.TOOL && isSearchWebFunctionName(part.toolName)) {
      searchPartIndex = i
      searchPartCount += 1
    }
  }

  if (searchPartCount === 1 && searchPartIndex >= 0) {
    const part = parts[searchPartIndex]
    let changed = false
    if (part.toolSearchReferences.length === 0) {
      part.toolSearchReferences = message.searchReferences.slice()
      changed = true
    }
    if (part.toolStatus === ToolPartStatus.PENDING && part.toolResult.trim() === '') {
      part.toolStatus = ToolPartStatus.SUCCEEDED
      changed = true
    }
    return changed
  }

  if (searchPartCount === 0 && message.toolCalls.length === 0) {
    parts.splice(findSearchReferenceInsertIndex(parts), 0, createLegacySearchPart(message))
    return true
  }

  return false
}

/**
 * 消息已经有 parts 时直接返回;否则用旧字段合成一个保守的顺序 parts,
 * 可用于 UI 渲染,也可用于历史消息迁移。
 */
export function resolveMessageParts(message: ChatMessage): MessagePart[] {
  if (message.parts.length > 0) {
    return message.parts
  }
  const parts: MessagePart[] = []
  if (message.reasoningContent.trim() !== '') {
    parts.push(MessagePart.reasoning(message.reasoningContent))
  }
  for (let i = 0; i < message.toolCalls.length; i++) {
    const result = i < message.toolResults.length ? message.toolResults[i] : null
    parts.push(createToolPart(message.toolCalls[i], result))
  }
  if (message.content.trim() !== '') {
    parts.push(MessagePart.text(message.content))
  }
  return parts
}

export function buildMessagePartsFromLegacy(message: ChatMessage, finishReasoning: boolean = true): MessagePart[] {
  const parts = resolveMessageParts(message)
  enrichLegacySearchReferences(message, parts)
  if (finishReasoning) {
    const now = Date.now()
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].kind === MessagePartKind.REASONING && parts[i].reasoningFinishedAt === 0) {
        parts[i].reasoningFinishedAt = now
      }
    }
  }
  return parts
}

export function ensureMessageParts(message: ChatMessage, finishReasoning: boolean = true): boolean {
  let changed = false
  if (message.parts.length === 0 && hasLegacyMessagePartSource(message)) {
    message.parts = buildMessagePartsFromLegacy(message, finishReasoning)
    changed = message.parts.length > 0
  }
  if (enrichLegacySearchReferences(message, message.parts)) {
    changed = true
  }
  return changed
}

/**
 * 分组:连续的 reasoning 和 tool part 归到一个 "思考块",
 * 遇到 text/image 等 part 时 flush。用于时间线 UI 渲染。
 */
export enum MessagePartBlockKind {
  THINKING = 'thinking',
  CONTENT = 'content'
}

export class MessagePartBlock {
  kind: MessagePartBlockKind = MessagePartBlockKind.CONTENT
  parts: MessagePart[] = []
}

export function groupMessageParts(parts: MessagePart[]): MessagePartBlock[] {
  const blocks: MessagePartBlock[] = []
  let thinkingBuffer: MessagePart[] = []

  const flush = () => {
    if (thinkingBuffer.length > 0) {
      const block = new MessagePartBlock()
      block.kind = MessagePartBlockKind.THINKING
      block.parts = thinkingBuffer
      blocks.push(block)
      thinkingBuffer = []
    }
  }

  for (let i = 0; i < parts.length; i++) {
    const part = parts[i]
    if (part.kind === MessagePartKind.REASONING || part.kind === MessagePartKind.TOOL) {
      thinkingBuffer.push(part)
    } else {
      flush()
      const block = new MessagePartBlock()
      block.kind = MessagePartBlockKind.CONTENT
      block.parts = [part]
      blocks.push(block)
    }
  }
  flush()
  return blocks
}
