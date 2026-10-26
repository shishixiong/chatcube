import { describe, it, expect } from '@ohos/hypium'
import { ChinaProvince } from '../../../../main/ets/utils/ChinaMapData'
import {
  PUZZLE_REGIONS,
  parseMapPuzzleArgs,
  provincesInRegion,
  resolvePuzzleProvinces,
  validateMapPuzzleArgs
} from '../../../../main/ets/utils/MapPuzzleValidation'
import { BEIJING_PATH, GUANGDONG_PATH, HEBEI_PATH, SHANXI_PATH } from './ChinaMapFixture'

/**
 * MapPuzzleValidation 单元测试（中国地图拼图, spec 2026-10-26 §7 / plan Task 4）
 *
 * 覆盖七条规则 + 边界（1 项 / 9 项 / 重复 / 未知名 / 非法 region），
 * 断言文案与 node 原型逐字对齐（2026-10-26）。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function makeProvince(id: string, short: string, region: string, path: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id,
    name: `${short}省`,
    short: short,
    abbr: 'X',
    capital: '某市',
    region: region,
    path: path
  }
  return p
}

const PROVINCES: ChinaProvince[] = [
  makeProvince('110000', '北京', '华北', BEIJING_PATH),
  makeProvince('130000', '河北', '华北', HEBEI_PATH),
  makeProvince('140000', '山西', '华北', SHANXI_PATH),
  makeProvince('210000', '辽宁', '东北', ''),
  makeProvince('220000', '吉林', '东北', ''),
  makeProvince('230000', '黑龙江', '东北', ''),
  makeProvince('330000', '浙江', '华东', ''),
  makeProvince('440000', '广东', '华南', GUANGDONG_PATH)
]

interface PuzzleArgsPayload {
  mode: string
  region: string
  provinces: string[]
  skill_key: string
}

interface PuzzleArgsNoListPayload {
  mode: string
  skill_key: string
}

function json(mode: string, region: string, provinces: string[], skillKey: string): string {
  const o: PuzzleArgsPayload = {
    mode: mode, region: region, provinces: provinces, skill_key: skillKey
  }
  return JSON.stringify(o)
}

const SK = 'general_social'

export default function mapPuzzleValidationTest() {
  describe('validateMapPuzzleArgs', () => {
    it('accepts a district round', 0, () => {
      const r = validateMapPuzzleArgs(json('district', '华北', [], SK), PROVINCES)
      expect(r.ok).assertTrue()
    })

    it('rejects a missing skill_key', 0, () => {
      const r = validateMapPuzzleArgs(json('district', '华北', [], ''), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('skill_key') >= 0).assertTrue()
    })

    it('rejects a wrong skill_key', 0, () => {
      const r = validateMapPuzzleArgs(json('district', '华北', [], 'math_calc'), PROVINCES)
      expect(r.ok).assertFalse()
    })

    it('rejects an unknown mode', 0, () => {
      const r = validateMapPuzzleArgs(json('region', '华北', [], SK), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('mode') >= 0).assertTrue()
    })

    it('rejects a bad region name', 0, () => {
      const r = validateMapPuzzleArgs(json('district', '华北大区', [], SK), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('region') >= 0).assertTrue()
    })

    it('rejects malformed json', 0, () => {
      const r = validateMapPuzzleArgs('{not json', PROVINCES)
      expect(r.ok).assertFalse()
    })

    it('rejects when the map data is not loaded', 0, () => {
      const r = validateMapPuzzleArgs(json('district', '华北', [], SK), null)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('地图数据') >= 0).assertTrue()
    })

    it('accepts 2 custom provinces', 0, () => {
      const r = validateMapPuzzleArgs(json('custom', '', ['山西', '河北'], SK), PROVINCES)
      expect(r.ok).assertTrue()
    })

    it('accepts 8 distinct custom provinces (the cap)', 0, () => {
      const eight: string[] = ['北京', '河北', '山西', '辽宁', '吉林', '黑龙江', '浙江', '广东']
      const r = validateMapPuzzleArgs(json('custom', '', eight, SK), PROVINCES)
      expect(r.ok).assertTrue()
    })

    it('rejects 9 custom provinces', 0, () => {
      const nine: string[] = ['北京', '河北', '山西', '辽宁', '吉林', '黑龙江', '浙江', '广东', '山西']
      const r = validateMapPuzzleArgs(json('custom', '', nine, SK), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('2-8') >= 0).assertTrue()
    })

    it('rejects a single custom province', 0, () => {
      const r = validateMapPuzzleArgs(json('custom', '', ['山西'], SK), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('2-8') >= 0).assertTrue()
    })

    it('rejects duplicated custom provinces', 0, () => {
      const r = validateMapPuzzleArgs(json('custom', '', ['山西', '山西'], SK), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('重复') >= 0).assertTrue()
    })

    it('rejects an unknown province name', 0, () => {
      const r = validateMapPuzzleArgs(json('custom', '', ['山西', '火星省'], SK), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('火星省') >= 0).assertTrue()
    })

    it('rejects a custom round without a provinces array', 0, () => {
      const noList: PuzzleArgsNoListPayload = { mode: 'custom', skill_key: SK }
      const r = validateMapPuzzleArgs(JSON.stringify(noList), PROVINCES)
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('provinces') >= 0).assertTrue()
    })
  })

  describe('parseMapPuzzleArgs', () => {
    it('parses a district round', 0, () => {
      const v = parseMapPuzzleArgs(json('district', '华北', [], SK))
      expect(v.valid).assertTrue()
      expect(v.mode).assertEqual('district')
      expect(v.region).assertEqual('华北')
      expect(v.skillKey).assertEqual(SK)
    })

    it('parses a custom round and keeps order', 0, () => {
      const v = parseMapPuzzleArgs(json('custom', '', ['广东', '山西'], SK))
      expect(v.valid).assertTrue()
      expect(v.provinceRefs.length).assertEqual(2)
      expect(v.provinceRefs[0]).assertEqual('广东')
    })

    it('falls back to invalid on broken json', 0, () => {
      const v = parseMapPuzzleArgs('not json at all')
      expect(v.valid).assertFalse()
      expect(v.mode).assertEqual('district')
      expect(v.skillKey).assertEqual(SK)
    })

    it('falls back to invalid on an unknown region', 0, () => {
      const v = parseMapPuzzleArgs(json('district', '火星', [], SK))
      expect(v.valid).assertFalse()
    })
  })

  describe('resolvePuzzleProvinces', () => {
    it('returns every province of the region', 0, () => {
      const v = parseMapPuzzleArgs(json('district', '华北', [], SK))
      const picked = resolvePuzzleProvinces(PROVINCES, v)
      expect(picked.length).assertEqual(3)
      expect(picked[0].short).assertEqual('北京')
    })

    it('dedupes custom refs and keeps the requested order', 0, () => {
      const v = parseMapPuzzleArgs(json('custom', '', ['广东', '山西', '广东'], SK))
      const picked = resolvePuzzleProvinces(PROVINCES, v)
      expect(picked.length).assertEqual(2)
      expect(picked[0].short).assertEqual('广东')
      expect(picked[1].short).assertEqual('山西')
    })

    it('skips unknown refs instead of throwing', 0, () => {
      const v = parseMapPuzzleArgs(json('custom', '', ['山西', '火星省'], SK))
      const picked = resolvePuzzleProvinces(PROVINCES, v)
      expect(picked.length).assertEqual(1)
    })

    it('returns an empty list for an unknown region', 0, () => {
      expect(provincesInRegion(PROVINCES, '火星').length).assertEqual(0)
    })
  })

  describe('PUZZLE_REGIONS', () => {
    it('lists the seven regions in order', 0, () => {
      expect(PUZZLE_REGIONS.length).assertEqual(7)
      expect(PUZZLE_REGIONS[0]).assertEqual('华北')
      expect(PUZZLE_REGIONS[6]).assertEqual('西北')
    })
  })
}
