import { describe, it, expect } from '@ohos/hypium'
import {
  getDimensionLabel,
  computeTrendProgress
} from '../../../../main/ets/utils/TeachingStyleAdjustmentUtils'

export default function teachingStyleAdjustmentUtilsTest() {
  describe('getDimensionLabel - difficultyTendency', () => {
    it('easier -> 偏简单', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'easier')).assertEqual('偏简单')
    })
    it('current -> 保持', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'current')).assertEqual('保持')
    })
    it('harder -> 偏难', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'harder')).assertEqual('偏难')
    })
  })

  describe('getDimensionLabel - feedbackTone', () => {
    it('gentle -> 温柔鼓励', 0, () => {
      expect(getDimensionLabel('feedbackTone', 'gentle')).assertEqual('温柔鼓励')
    })
    it('neutral -> 中性', 0, () => {
      expect(getDimensionLabel('feedbackTone', 'neutral')).assertEqual('中性')
    })
    it('playful -> 活泼', 0, () => {
      expect(getDimensionLabel('feedbackTone', 'playful')).assertEqual('活泼')
    })
  })

  describe('getDimensionLabel - weakStrongBalance', () => {
    it('weak_focus -> 弱项强化', 0, () => {
      expect(getDimensionLabel('weakStrongBalance', 'weak_focus')).assertEqual('弱项强化')
    })
    it('balanced -> 均衡', 0, () => {
      expect(getDimensionLabel('weakStrongBalance', 'balanced')).assertEqual('均衡')
    })
    it('strong_focus -> 强项深化', 0, () => {
      expect(getDimensionLabel('weakStrongBalance', 'strong_focus')).assertEqual('强项深化')
    })
  })

  describe('getDimensionLabel - learningPace', () => {
    it('minimal -> 精简', 0, () => {
      expect(getDimensionLabel('learningPace', 'minimal')).assertEqual('精简')
    })
    it('standard -> 适中', 0, () => {
      expect(getDimensionLabel('learningPace', 'standard')).assertEqual('适中')
    })
    it('extensive -> 拓展', 0, () => {
      expect(getDimensionLabel('learningPace', 'extensive')).assertEqual('拓展')
    })
  })

  describe('getDimensionLabel - fallback', () => {
    it('unknown value returns original', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'unknown')).assertEqual('unknown')
    })
    it('unknown dimension returns original', 0, () => {
      expect(getDimensionLabel('unknown', 'value')).assertEqual('value')
    })
  })

  describe('computeTrendProgress', () => {
    it('clamp to 0 when regressions dominate', 0, () => {
      expect(computeTrendProgress(0, 5)).assertEqual(0)
    })
    it('clamp to 5 when improvements dominate', 0, () => {
      expect(computeTrendProgress(10, 0)).assertEqual(5)
    })
    it('center at 2 for equal', 0, () => {
      expect(computeTrendProgress(3, 3)).assertEqual(2)
    })
    it('handles zero case', 0, () => {
      expect(computeTrendProgress(0, 0)).assertEqual(2)
    })
  })
}
