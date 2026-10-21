/**
 * pickMapChoiceOptions - map_quiz choice 题型选项生成纯函数（spec 2026-10-21 §5.2）
 *
 * 策略复刻原型 docs/map-learning/app.js buildOptions：
 *  1. 干扰池 = 全部省份 - 正确省
 *  2. 同大区随机取 2 个（同大区不足则取全部）
 *  3. 其余池随机补 1 个；不足 4 个时跨大区继续补满（能补则补）
 *  4. 正确项 + 干扰项整体 Fisher-Yates 洗牌（rng 注入，hypium 定策测试）
 *
 * 选项合法性由构造保证（消掉 AI 传选项的整类校验失败面）。
 */

import { ChinaProvince } from './ChinaMapData'

function shuffleIds(ids: string[], rng: () => number): string[] {
  const arr = ids.slice()
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    const tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
  return arr
}

export function pickMapChoiceOptions(provinces: ChinaProvince[], targetId: string, rng: () => number): string[] {
  const target = provinces.find((p: ChinaProvince): boolean => p.id === targetId)
  if (target === undefined) {
    return []
  }

  const pool: ChinaProvince[] = []
  for (const p of provinces) {
    if (p.id !== targetId) {
      pool.push(p)
    }
  }

  const sameRegion = shuffleIds(
    pool.filter((p: ChinaProvince): boolean => p.region === target.region).map((p: ChinaProvince): string => p.id),
    rng
  ).slice(0, 2)

  const chosen = new Set<string>(sameRegion)

  const others = shuffleIds(
    pool.filter((p: ChinaProvince): boolean => !chosen.has(p.id)).map((p: ChinaProvince): string => p.id),
    rng
  )

  // 先按原型取 1 个其余池干扰项，不足 4 个继续从 others 补
  const distractors = sameRegion.slice()
  const extra = others.slice(0, Math.max(1, 4 - 1 - distractors.length))
  for (const id of extra) {
    distractors.push(id)
  }

  const all = [targetId]
  for (const id of distractors) {
    if (id !== targetId && all.indexOf(id) < 0) {
      all.push(id)
    }
  }
  return shuffleIds(all, rng)
}
