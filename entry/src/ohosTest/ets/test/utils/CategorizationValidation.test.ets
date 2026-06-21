import { describe, it, expect } from '@ohos/hypium'
import { validateAndNormalizeCategorization } from '../../../../main/ets/utils/CategorizationValidation'

/**
 * CategorizationValidation 单元测试
 *
 * 覆盖 validateAndNormalizeCategorization 的合法路径、自动推断路径、以及
 * 13 种校验失败路径。对照 spec docs/superpowers/specs/2026-06-06-categorization-helper-design.md §10。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

// 构造合法的工具调用 JSON 字符串
function buildArgs(overrides: Record<string, Object>): string {
  return JSON.stringify(overrides)
}

export default function categorizationValidationTest() {
  describe('validateAndNormalizeCategorization - 合法路径', () => {
    it('difficulty=1: 2 桶 4 物品, bin 分布 [2,2] 合法', 0, () => {
      const args = buildArgs({
        theme: '水果与蔬菜',
        difficulty: 1,
        bins: [
          { name: '水果', emoji: '🍎' },
          { name: '蔬菜', emoji: '🥕' }
        ],
        items: [
          { name: '苹果', emoji: '🍎', bin_index: 0 },
          { name: '香蕉', emoji: '🍌', bin_index: 0 },
          { name: '胡萝卜', emoji: '🥕', bin_index: 1 },
          { name: '青菜', emoji: '🥬', bin_index: 1 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.difficulty).assertEqual(1)
      expect(r.theme).assertEqual('水果与蔬菜')
      expect(r.bins.length).assertEqual(2)
      expect(r.items.length).assertEqual(4)
    })

    it('difficulty=2: 3 桶 6 物品, bin 分布 [2,2,2] 合法', 0, () => {
      const args = buildArgs({
        theme: '动物的家',
        difficulty: 2,
        bins: [
          { name: '陆地', emoji: '🦁' },
          { name: '水里', emoji: '🐟' },
          { name: '天空', emoji: '🦅' }
        ],
        items: [
          { name: '狮子', emoji: '🦁', bin_index: 0 },
          { name: '老虎', emoji: '🐯', bin_index: 0 },
          { name: '鱼', emoji: '🐟', bin_index: 1 },
          { name: '海豚', emoji: '🐬', bin_index: 1 },
          { name: '鸟', emoji: '🐦', bin_index: 2 },
          { name: '鹰', emoji: '🦅', bin_index: 2 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.difficulty).assertEqual(2)
    })

    it('difficulty=3: 3 桶 9 物品, bin 分布 [3,3,3] 合法', 0, () => {
      const items: Record<string, Object>[] = []
      for (let i = 0; i < 9; i++) {
        items.push({ name: `物${i}`, emoji: '🍎', bin_index: i % 3 })
      }
      const args = buildArgs({
        theme: '复杂分类',
        difficulty: 3,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' },
          { name: 'C', emoji: '' }
        ],
        items
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.items.length).assertEqual(9)
    })

    it('difficulty 缺失: items.length=4 自动推断 difficulty=1', 0, () => {
      const args = buildArgs({
        theme: '水果',
        bins: [
          { name: '水果', emoji: '' },
          { name: '蔬菜', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 },
          { name: 'c', emoji: '', bin_index: 1 },
          { name: 'd', emoji: '', bin_index: 1 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.difficulty).assertEqual(1)
    })

    it('difficulty 非法值 5 + items.length=6: fallback 推断 difficulty=2', 0, () => {
      const args = buildArgs({
        theme: '水果',
        difficulty: 5,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' },
          { name: 'C', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 },
          { name: 'c', emoji: '', bin_index: 1 },
          { name: 'd', emoji: '', bin_index: 1 },
          { name: 'e', emoji: '', bin_index: 2 },
          { name: 'f', emoji: '', bin_index: 2 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.difficulty).assertEqual(2)
    })

    it('LLM 错配 difficulty=3 但 items.length=6: 自动纠正为 difficulty=2', 0, () => {
      // 实战常见: LLM 把 difficulty 写成 3 (挑战档) 但只配 6 件物品
      const args = buildArgs({
        theme: '动物',
        difficulty: 3,
        bins: [
          { name: '陆地', emoji: '🦁' },
          { name: '水里', emoji: '🐟' },
          { name: '天空', emoji: '🦅' }
        ],
        items: [
          { name: '狮子', emoji: '🦁', bin_index: 0 },
          { name: '老虎', emoji: '🐯', bin_index: 0 },
          { name: '鱼', emoji: '🐟', bin_index: 1 },
          { name: '海豚', emoji: '🐬', bin_index: 1 },
          { name: '鸟', emoji: '🐦', bin_index: 2 },
          { name: '鹰', emoji: '🦅', bin_index: 2 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.difficulty).assertEqual(2)
    })

    it('LLM 错配 difficulty=1 但 items.length=9: 自动提升为 difficulty=3', 0, () => {
      const items: Record<string, Object>[] = []
      for (let i = 0; i < 9; i++) {
        items.push({ name: `物${i}`, emoji: '🍎', bin_index: i % 3 })
      }
      const args = buildArgs({
        theme: '复杂分类',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' },
          { name: 'C', emoji: '' }
        ],
        items
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.difficulty).assertEqual(3)
    })

    it('instruction 缺失时不报错 (可选字段)', 0, () => {
      const args = buildArgs({
        theme: '水果',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 },
          { name: 'c', emoji: '', bin_index: 1 },
          { name: 'd', emoji: '', bin_index: 1 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
      expect(r.instruction).assertEqual('')
    })

    it('所有 emoji 为空字符串时不报错 (视觉降级在组件层处理)', 0, () => {
      const args = buildArgs({
        theme: '纯文字',
        difficulty: 1,
        bins: [
          { name: '水果', emoji: '' },
          { name: '蔬菜', emoji: '' }
        ],
        items: [
          { name: '苹果', emoji: '', bin_index: 0 },
          { name: '香蕉', emoji: '', bin_index: 0 },
          { name: '萝卜', emoji: '', bin_index: 1 },
          { name: '青菜', emoji: '', bin_index: 1 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertTrue()
    })
  })

  describe('validateAndNormalizeCategorization - 失败路径', () => {
    it('JSON 解析失败: 返回 ok=false 且 error 含「格式错误」', 0, () => {
      const r = validateAndNormalizeCategorization('not-json{')
      expect(r.ok).assertFalse()
      expect(r.error.includes('格式错误')).assertTrue()
    })

    it('theme 为空: 返回 ok=false', 0, () => {
      const args = buildArgs({
        theme: '   ',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 },
          { name: 'c', emoji: '', bin_index: 1 },
          { name: 'd', emoji: '', bin_index: 1 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
      expect(r.error.includes('主题')).assertTrue()
    })

    it('bins.length=1 (越界): 返回 ok=false', 0, () => {
      const args = buildArgs({
        theme: 'x',
        difficulty: 1,
        bins: [{ name: 'A', emoji: '' }],
        items: []
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
      expect(r.error.includes('分类桶')).assertTrue()
    })

    it('bins.length=4 (越界): 返回 ok=false', 0, () => {
      const args = buildArgs({
        theme: 'x',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' },
          { name: 'C', emoji: '' },
          { name: 'D', emoji: '' }
        ],
        items: []
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
    })

    it('第 2 个桶 name 为空: error 含「第 2 个」', 0, () => {
      const args = buildArgs({
        theme: 'x',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: '', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
      expect(r.error.includes('第 2 个')).assertTrue()
    })

    it('items.length=7 (非 4/6/9): 返回 ok=false, 提示不在标准范围', 0, () => {
      // LLM 发了 7 件物品, 没法对应任何标准难度 → 让 AI 重试
      const items: Record<string, Object>[] = []
      for (let i = 0; i < 7; i++) {
        items.push({ name: `x${i}`, emoji: '', bin_index: i % 3 })
      }
      const args = buildArgs({
        theme: 'x',
        difficulty: 2,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' },
          { name: 'C', emoji: '' }
        ],
        items
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在标准范围')).assertTrue()
    })

    it('item.bin_index 越界 (5 on 3 桶): 返回 ok=false', 0, () => {
      const args = buildArgs({
        theme: 'x',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 },
          { name: 'c', emoji: '', bin_index: 1 },
          { name: 'd', emoji: '', bin_index: 5 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
      expect(r.error.includes('bin_index')).assertTrue()
    })

    it('第 3 个物品 name 为空: error 含「第 3 个」', 0, () => {
      const args = buildArgs({
        theme: 'x',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 },
          { name: '', emoji: '', bin_index: 1 },
          { name: 'd', emoji: '', bin_index: 1 }
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
      expect(r.error.includes('第 3 个')).assertTrue()
    })

    it('某桶物品 <2: 返回 ok=false 且 error 提示桶序号', 0, () => {
      const args = buildArgs({
        theme: 'x',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' }
        ],
        items: [
          { name: 'a', emoji: '', bin_index: 0 },
          { name: 'b', emoji: '', bin_index: 0 },
          { name: 'c', emoji: '', bin_index: 0 },
          { name: 'd', emoji: '', bin_index: 1 } // 桶 B 只有 1 件
        ]
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
      expect(r.error.includes('第 2 个')).assertTrue()
    })

    it('items 为空数组: 返回 ok=false', 0, () => {
      const args = buildArgs({
        theme: 'x',
        difficulty: 1,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' }
        ],
        items: []
      })
      const r = validateAndNormalizeCategorization(args)
      expect(r.ok).assertFalse()
    })

    it('items.length=7 (非 4/6/9) + difficulty 非法: 失败', 0, () => {
      // difficulty=99 + 7 物品 (非 4/6/9) → 直接拒绝
      const items: Record<string, Object>[] = []
      for (let i = 0; i < 7; i++) {
        items.push({ name: `n${i}`, emoji: '', bin_index: i % 2 })
      }
      const fixedArgs = buildArgs({
        theme: 'x',
        difficulty: 99,
        bins: [
          { name: 'A', emoji: '' },
          { name: 'B', emoji: '' }
        ],
        items
      })
      const r = validateAndNormalizeCategorization(fixedArgs)
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在标准范围')).assertTrue()
    })
  })
}
