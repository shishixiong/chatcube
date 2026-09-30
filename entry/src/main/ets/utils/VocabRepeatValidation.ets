/**
 * VocabRepeatValidation - 出题重复度硬门禁的纯策略层
 *
 * 设计: docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md §7/§9
 * - evaluateRepeatPolicy: 纯函数真值表——session_gap 任何 purpose 都拦截;
 *   purpose="review" 豁免 same_mode_cooldown 与 mastered_recheck; 新词不受限。
 * - parsePurpose: LLM 未传 purpose 视为 "new" (spec §10 降级表)。
 * - buildRepeatBlockedMessage: 生成给 LLM 的 should_retry 修正提示。
 *
 * 服务层 (LearningLedgerService.checkRepeat) 负责收集 RepeatPolicyInput,
 * handler 侧 (ToolExecutionService.runVocabRepeatGate) 只消费结果。
 */
import {
  RepeatCheck,
  RepeatPolicyInput,
  SAME_MODE_COOLDOWN_MS,
  REPEAT_REASON_SESSION_GAP,
  REPEAT_REASON_SAME_MODE_COOLDOWN,
  REPEAT_REASON_MASTERED_RECHECK
} from '../models/LearningLedgerModels'

export interface VocabRepeatGateResult {
  blocked: boolean
  error: string
  message: string
}

export function parsePurpose(argsJson: string): string {
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>
    const purpose = (parsed['purpose'] as string) ?? ''
    return purpose === 'review' ? 'review' : 'new'
  } catch (_e) {
    return 'new'
  }
}

export function evaluateRepeatPolicy(input: RepeatPolicyInput): RepeatCheck {
  const result: RepeatCheck = {
    allowed: true,
    reason: '',
    itemKey: input.itemKey,
    display: input.display
  }
  if (!input.found) {
    return result
  }
  // 1. 会话间隔: 任何 purpose 都生效 (复习也不能在 5 题内刷屏)
  if (input.inSessionGap) {
    result.allowed = false
    result.reason = REPEAT_REASON_SESSION_GAP
    return result
  }
  // 2. 复习豁免: 同题型冷却 + 已掌握抽检
  if (input.purpose === 'review') {
    return result
  }
  // 3. 已掌握 30 天抽检期内, 勿当新词
  if (input.mastery >= 5 && input.nextReviewAt > input.now) {
    result.allowed = false
    result.reason = REPEAT_REASON_MASTERED_RECHECK
    return result
  }
  // 4. 同词同题型 30 分钟冷却
  if (input.lastMode !== '' && input.lastMode === input.mode
    && input.lastSeenAt > input.now - SAME_MODE_COOLDOWN_MS) {
    result.allowed = false
    result.reason = REPEAT_REASON_SAME_MODE_COOLDOWN
  }
  return result
}

export function buildRepeatBlockedMessage(reason: string, display: string): string {
  if (reason === REPEAT_REASON_SESSION_GAP) {
    return `「${display}」刚在本次对话出现过, 请隔几题或换一个词再出`
  }
  if (reason === REPEAT_REASON_MASTERED_RECHECK) {
    return `「${display}」已经掌握, 抽检期内请勿作为新词出题; 若确实要复习请传 purpose:"review"`
  }
  return `「${display}」近期已用相同题型出现过, 请换词或换题型; 若确实要复习请传 purpose:"review"`
}
