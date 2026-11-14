/**
 * QuizOptionShuffle - 选择题选项顺序的确定性洗牌 (纯函数层)
 *
 * 背景: math_quiz / chinese_quiz 的选项由 LLM 生成, 即使 schema 要求「打乱顺序」,
 * 模型仍习惯把正确答案放在第一个。只在提示词里约束不可靠, 因此在渲染层强制洗牌。
 *
 * 约束: 必须确定性 —— 同一道题 (同一 toolCall.id) 每次渲染/重开会话时顺序一致,
 * 否则两次机会流中途选项会跳动。这里用 toolCall.id 的字符串哈希做 xorshift32 种子,
 * 与 MatchingPairsCard 的右列洗牌同一套确定性伪随机思路。
 */

/** 字符串 → 非零 32 位种子 (hash=0 时退化为 1, 避免 xorshift 卡死) */
export function hashSeedFromString(value: string): number {
  let hash = 0
  for (let i = 0; i < value.length; i++) {
    hash = (hash * 31 + value.charCodeAt(i)) >>> 0
  }
  return hash === 0 ? 1 : hash
}

/** xorshift32 单步推进 */
function nextRandomState(state: number): number {
  let s = state >>> 0
  if (s === 0) {
    s = 1
  }
  s ^= s << 13
  s >>>= 0
  s ^= s >>> 17
  s ^= s << 5
  s >>>= 0
  return s
}

/**
 * 种子化 Fisher-Yates 洗牌 (返回新数组, 不修改入参)。
 * 防退化: 洗牌结果若与原序完全相同, 左移一位强制改变顺序,
 * 保证「正确答案永远第一个」这类退化永远不会出现。
 */
export function shuffleQuizOptions(options: Array<string | number>, seed: number): Array<string | number> {
  const arr: Array<string | number> = []
  for (let i = 0; i < options.length; i++) {
    arr.push(options[i])
  }
  let state = seed >>> 0
  if (state === 0) {
    state = 1
  }
  for (let i = arr.length - 1; i > 0; i--) {
    state = nextRandomState(state)
    const j = state % (i + 1)
    const tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
  if (arr.length >= 2) {
    let identical = true
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] !== options[i]) {
        identical = false
        break
      }
    }
    if (identical) {
      const first = arr[0]
      for (let i = 0; i < arr.length - 1; i++) {
        arr[i] = arr[i + 1]
      }
      arr[arr.length - 1] = first
    }
  }
  return arr
}

/** 字符串选项的便捷包装 (chinese_quiz / comparison 运算符等) */
export function shuffleStringOptions(options: string[], seed: number): string[] {
  const mixed = shuffleQuizOptions(options, seed)
  const out: string[] = []
  for (let i = 0; i < mixed.length; i++) {
    out.push(String(mixed[i]))
  }
  return out
}
