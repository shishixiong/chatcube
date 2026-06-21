/**
 * CategorizationValidation - 分类小管家数据校验纯逻辑层
 *
 * 与 CategorizationCard 解耦: 只做 AI 工具调用参数的解析与校验,
 * 组件聚焦 UI 渲染, 也方便 .ets 单测。
 *
 * 设计参考 utils/MathQuizGame.ets (游戏纯逻辑抽离范式)。
 *
 * 校验规则对照 spec docs/superpowers/specs/2026-06-06-categorization-helper-design.md §10:
 *   - bins 数量必须 ∈ [2, 3]
 *   - bins[i].name 非空
 *   - items.length 必须与 difficulty 匹配 (1→4 / 2→6 / 3→9)
 *   - 任意 item.bin_index 必须 ∈ [0, bins.length)
 *   - 每个桶至少 2 件物品
 *   - theme 非空
 *   - difficulty 缺失 / 非法时, 由 items.length 自动推断 (4→1 / 6→2 / 9→3)
 */

import { CategorizationBin, CategorizationItem } from '../components/CategorizationCard'

// 校验 / 解析后的标准化数据。ok=false 时其他字段为空占位。
export interface NormalizedCategorizationData {
  ok: boolean
  error: string
  bins: CategorizationBin[]
  items: CategorizationItem[]
  difficulty: number
  theme: string
  instruction: string
}

// 构造失败结果 (ok=false)。抽成模块级顶层函数, 避免组件内闭包。
function fail(msg: string): NormalizedCategorizationData {
  return {
    ok: false,
    error: msg,
    bins: [],
    items: [],
    difficulty: 1,
    theme: '',
    instruction: ''
  }
}

/**
 * 解析并校验 AI 传来的 categorization 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含可读的中文错误描述。
 */
export function validateAndNormalizeCategorization(args: string): NormalizedCategorizationData {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('题目格式错误，请提示小星老师再出一题吧')
  }

  const theme = ((parsed['theme'] as string) ?? '').trim()
  if (theme === '') {
    return fail('主题为空，请提示小星老师再出一题吧')
  }
  const instruction = ((parsed['instruction'] as string) ?? '').trim()

  const binsRaw = parsed['bins'] as Array<Record<string, Object>> | undefined
  if (!binsRaw || binsRaw.length < 2 || binsRaw.length > 3) {
    return fail('分类桶数量不对（需要 2 或 3 个）')
  }
  const bins: CategorizationBin[] = []
  for (let i = 0; i < binsRaw.length; i++) {
    const raw = binsRaw[i]
    const name = ((raw['name'] as string) ?? '').trim()
    if (name === '') {
      return fail(`第 ${i + 1} 个分类桶缺少名字`)
    }
    bins.push({
      name: name,
      emoji: (raw['emoji'] as string) ?? ''
    })
  }

  const itemsRaw = parsed['items'] as Array<Record<string, Object>> | undefined
  if (!itemsRaw || itemsRaw.length === 0) {
    return fail('物品列表为空')
  }

  // 难度以 items.length 为准 (LLM 常会把 difficulty 和实际物品数错配,
  // 比如发 difficulty=3 但只给 6 件, 或 difficulty=1 但给 9 件)。
  // 仅当 items.length 不属于 4/6/9 这 3 个标准值时才报错让 AI 重试——
  // 这比让孩子看到"题目出错了"占位卡更友好。
  if (itemsRaw.length !== 4 && itemsRaw.length !== 6 && itemsRaw.length !== 9) {
    return fail(`物品数量 ${itemsRaw.length} 不在标准范围（应为 4/6/9），请提示小星老师再出一题`)
  }
  const difficulty: number = itemsRaw.length === 4 ? 1 : (itemsRaw.length === 6 ? 2 : 3)

  const binCounts: number[] = []
  for (let i = 0; i < bins.length; i++) {
    binCounts.push(0)
  }
  const items: CategorizationItem[] = []
  for (let i = 0; i < itemsRaw.length; i++) {
    const raw = itemsRaw[i]
    const name = ((raw['name'] as string) ?? '').trim()
    const emoji = (raw['emoji'] as string) ?? ''
    const binIndex = raw['bin_index'] as number
    if (name === '') {
      return fail(`第 ${i + 1} 个物品缺少名字`)
    }
    if (typeof binIndex !== 'number' || Math.floor(binIndex) !== binIndex
      || binIndex < 0 || binIndex >= bins.length) {
      return fail(`第 ${i + 1} 个物品的 bin_index 不合法`)
    }
    binCounts[binIndex] = binCounts[binIndex] + 1
    items.push({ name: name, emoji: emoji, bin_index: binIndex })
  }
  for (let i = 0; i < binCounts.length; i++) {
    if (binCounts[i] < 2) {
      return fail(`第 ${i + 1} 个桶只有 ${binCounts[i]} 件物品（至少 2 件）`)
    }
  }

  return {
    ok: true,
    error: '',
    bins,
    items,
    difficulty,
    theme,
    instruction
  }
}
