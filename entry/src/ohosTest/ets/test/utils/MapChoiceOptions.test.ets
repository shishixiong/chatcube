import { describe, it, expect } from '@ohos/hypium'
import { ChinaProvince } from '../../../../main/ets/utils/ChinaMapData'
import { pickMapChoiceOptions } from '../../../../main/ets/utils/MapChoiceOptions'

/**
 * pickMapChoiceOptions 单元测试（中国地图教学工具, plan Task 4 / spec §5.2）
 *
 * 策略复刻原型 buildOptions：同大区优先取 2 + 其余池补 1 + 正确项，
 * Fisher-Yates 洗牌（rng 注入定策）。池不足时跨大区补满至 4。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function makeProvince(id: string, name: string, short: string, region: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id,
    name: name,
    short: short,
    abbr: 'X',
    capital: '某市',
    region: region,
    path: 'M0 0L1 0L1 1Z'
  }
  return p
}

function makeFixture(): ChinaProvince[] {
  return [
    makeProvince('140000', '山西省', '山西', '华北'),
    makeProvince('110000', '北京市', '北京', '华北'),
    makeProvince('120000', '天津市', '天津', '华北'),
    makeProvince('130000', '河北省', '河北', '华北'),
    makeProvince('150000', '内蒙古', '内蒙古', '华北'),
    makeProvince('440000', '广东省', '广东', '华南'),
    makeProvince('450000', '广西', '广西', '华南'),
    makeProvince('350000', '福建省', '福建', '华东')
  ]
}

// 确定性 rng：返回固定序列，便于断言同大区优先
function sequenceRng(values: number[]): () => number {
  let idx = 0
  return (): number => {
    const v = values[idx % values.length]
    idx++
    return v
  }
}

export default function mapChoiceOptionsTest() {
  describe('pickMapChoiceOptions', () => {
    it('returns exactly 4 distinct ids', 0, () => {
      const provinces = makeFixture()
      const options = pickMapChoiceOptions(provinces, '140000', Math.random)
      expect(options.length).assertEqual(4)
      const seen = new Set<string>()
      for (const id of options) {
        seen.add(id)
      }
      expect(seen.size).assertEqual(4)
    })

    it('contains the target id', 0, () => {
      const provinces = makeFixture()
      const options = pickMapChoiceOptions(provinces, '440000', Math.random)
      expect(options.indexOf('440000') >= 0).assertTrue()
    })

    it('never duplicates the target in distractors', 0, () => {
      const provinces = makeFixture()
      // 多跑几次随机，确保目标只出现一次
      for (let i = 0; i < 20; i++) {
        const options = pickMapChoiceOptions(provinces, '140000', Math.random)
        let count = 0
        for (const id of options) {
          if (id === '140000') {
            count++
          }
        }
        expect(count).assertEqual(1)
      }
    })

    it('pads from other regions when target region is small', 0, () => {
      // 目标所在大区只有 1 省（华东），仍须凑齐 4 个互异
      const small: ChinaProvince[] = [
        makeProvince('350000', '福建省', '福建', '华东'),
        makeProvince('140000', '山西省', '山西', '华北'),
        makeProvince('440000', '广东省', '广东', '华南'),
        makeProvince('450000', '广西', '广西', '华南')
      ]
      const options = pickMapChoiceOptions(small, '350000', Math.random)
      expect(options.length).assertEqual(4)
      const seen = new Set<string>()
      for (const id of options) {
        seen.add(id)
      }
      expect(seen.size).assertEqual(4)
    })

    it('deterministic with fixed rng', 0, () => {
      const provinces = makeFixture()
      const a = pickMapChoiceOptions(provinces, '140000', sequenceRng([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]))
      const b = pickMapChoiceOptions(provinces, '140000', sequenceRng([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]))
      expect(JSON.stringify(a)).assertEqual(JSON.stringify(b))
    })

    it('prefers same-region distractors (exactly 2 when available)', 0, () => {
      const provinces = makeFixture()
      const target = provinces.find((p: ChinaProvince): boolean => p.id === '140000')
      if (target === undefined) {
        expect(false).assertTrue()
        return
      }
      // 华北其余 4 省 → 同大区优先策略下每次恰好取 2 个
      for (let i = 0; i < 20; i++) {
        const options = pickMapChoiceOptions(provinces, '140000', Math.random)
        let sameRegionCount = 0
        for (const id of options) {
          if (id !== '140000') {
            const p = provinces.find((q: ChinaProvince): boolean => q.id === id)
            if (p !== undefined && p.region === target.region) {
              sameRegionCount++
            }
          }
        }
        expect(sameRegionCount).assertEqual(2)
      }
    })

    it('returns fewer than 4 when total provinces fewer than 4', 0, () => {
      const tiny: ChinaProvince[] = [
        makeProvince('140000', '山西省', '山西', '华北'),
        makeProvince('440000', '广东省', '广东', '华南')
      ]
      const options = pickMapChoiceOptions(tiny, '140000', Math.random)
      expect(options.length).assertEqual(2)
    })
  })
}
