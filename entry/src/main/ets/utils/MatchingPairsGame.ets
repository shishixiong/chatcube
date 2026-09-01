/**
 * MatchingPairsGame - 连一连 (matching_pairs) 纯逻辑层
 *
 * 与 MatchingPairsCard 解耦: 只做 AI 工具调用参数的解析与校验 + 右列洗牌,
 * 组件聚焦 UI 渲染, 也方便 .ets 单测。
 *
 * 设计参考 utils/CategorizationValidation.ets (校验+normalize 范式)。
 *
 * 校验规则:
 *   - pairs 数量必须 ∈ [4, 5]
 *   - 每对 left / right 非空
 *   - left 无重复且 right 无重复 (重复使配对歧义)
 *   - theme 非空
 *   - difficulty 与对数不符时宽松推断 (4 对→1, 5 对→2), 语义距离大→3
 */

export interface MatchingPair {
  left: string
  right: string
  leftEmoji: string
  rightEmoji: string
}

// 校验 / 解析后的标准化数据。ok=false 时其他字段为空占位。
export interface NormalizedMatchingPairsData {
  ok: boolean
  error: string
  theme: string
  instruction: string
  leftLabel: string
  rightLabel: string
  pairs: MatchingPair[]
  difficulty: number
  skillKey: string
}

// 构造失败结果 (ok=false)。抽成模块级顶层函数, 避免组件内闭包。
function fail(msg: string): NormalizedMatchingPairsData {
  return {
    ok: false,
    error: msg,
    theme: '',
    instruction: '',
    leftLabel: '',
    rightLabel: '',
    pairs: [],
    difficulty: 1,
    skillKey: 'observation'
  }
}

/**
 * 解析并校验 AI 传来的 matching_pairs 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validateAndNormalizeMatchingPairs(args: string): NormalizedMatchingPairsData {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('matching_pairs 参数不是合法 JSON, 请检查后重新出题')
  }

  const theme = ((parsed['theme'] as string) ?? '').trim()
  if (theme === '') {
    return fail('matching_pairs 题缺少 theme (配对主题)')
  }
  const instruction = ((parsed['instruction'] as string) ?? '').trim()
  const leftLabel = ((parsed['left_label'] as string) ?? '').trim()
  const rightLabel = ((parsed['right_label'] as string) ?? '').trim()

  const pairsRaw = parsed['pairs'] as Array<Record<string, Object>> | undefined
  if (!pairsRaw) {
    return fail('matching_pairs 题必须提供 pairs 配对数组 (4-5 对)')
  }
  if (pairsRaw.length !== 4 && pairsRaw.length !== 5) {
    return fail(`matching_pairs 题的配对数量是 ${pairsRaw.length}, 必须是 4 或 5 对, 请修正后重新出题`)
  }

  // 难度以 pairs.length 为准 (LLM 常会把 difficulty 和实际对数错配),
  // 仅当 difficulty 明确传了 3 且对数为 5 时按 3 (语义距离大), 否则按对数推断。
  const declaredDifficulty = parsed['difficulty'] as number
  const difficulty: number = (pairsRaw.length === 4) ? 1
    : ((declaredDifficulty === 3) ? 3 : 2)

  const pairs: MatchingPair[] = []
  const leftSet = new Set<string>()
  const rightSet = new Set<string>()
  for (let i = 0; i < pairsRaw.length; i++) {
    const raw = pairsRaw[i]
    const left = ((raw['left'] as string) ?? '').trim()
    const right = ((raw['right'] as string) ?? '').trim()
    if (left === '') {
      return fail(`第 ${i + 1} 对的 left 为空`)
    }
    if (right === '') {
      return fail(`第 ${i + 1} 对的 right 为空`)
    }
    if (leftSet.has(left)) {
      return fail(`left 项「${left}」重复, 左列各项必须互不相同`)
    }
    if (rightSet.has(right)) {
      return fail(`right 项「${right}」重复, 右列各项必须互不相同`)
    }
    leftSet.add(left)
    rightSet.add(right)
    pairs.push({
      left: left,
      right: right,
      leftEmoji: ((raw['left_emoji'] as string) ?? '').trim(),
      rightEmoji: ((raw['right_emoji'] as string) ?? '').trim()
    })
  }

  const skillKey = ((parsed['skill_key'] as string) ?? '').trim()
  return {
    ok: true,
    error: '',
    theme,
    instruction,
    leftLabel,
    rightLabel,
    pairs,
    difficulty,
    skillKey: skillKey !== '' ? skillKey : 'observation'
  }
}

/**
 * 种子化洗牌右列 (Fisher-Yates)。
 * 同一 seed 产出确定序列, 便于单测; 洗牌结果保证是一个排列 (不会碰巧等于原序时也接受,
 * 概率 1/n! 可忽略; 若等于原序会破坏游戏性, 强制交换前两个)。
 */
export function shuffleRightColumn(pairs: MatchingPair[], seed: number): MatchingPair[] {
  const arr: MatchingPair[] = []
  for (let i = 0; i < pairs.length; i++) {
    arr.push(pairs[i])
  }
  let state = seed >>> 0
  if (state === 0) {
    state = 1
  }
  for (let i = arr.length - 1; i > 0; i--) {
    // xorshift32: 确定性伪随机
    state ^= state << 13
    state >>>= 0
    state ^= state >>> 17
    state ^= state << 5
    state >>>= 0
    const j = state % (i + 1)
    const tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
  // 防退化: 若洗牌结果与原序完全相同, 强制交换前两项
  let identical = true
  for (let i = 0; i < arr.length; i++) {
    if (arr[i].right !== pairs[i].right) {
      identical = false
      break
    }
  }
  if (identical && arr.length >= 2) {
    const tmp = arr[0]
    arr[0] = arr[1]
    arr[1] = tmp
  }
  return arr
}
