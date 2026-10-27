import { describe, it, expect } from '@ohos/hypium'
import { ChinaProvince } from '../../../../main/ets/utils/ChinaMapData'
import { validateMapCardArgs, validateMapQuizArgs } from '../../../../main/ets/utils/MapToolValidation'

/**
 * MapToolValidation 单元测试（中国地图教学工具, plan Task 4 / spec §6）
 *
 * fixture 为内联假省份数据（含一条 capital === short 的自答省），
 * 不依赖 rawfile 加载。真实 6 省（北京/天津/上海/重庆/香港/澳门）的
 * capital === short 守卫在 validateMapQuizArgs 内部按数据判定。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function makeProvince(id: string, name: string, short: string, capital: string, region: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id,
    name: name,
    short: short,
    abbr: 'X',
    capital: capital,
    region: region,
    path: 'M0 0L1 0L1 1Z'
  }
  return p
}

function makeFixture(): ChinaProvince[] {
  return [
    makeProvince('140000', '山西省', '山西', '太原', '华北'),
    makeProvince('110000', '北京市', '北京', '北京', '华北'),
    makeProvince('440000', '广东省', '广东', '广州', '华南'),
    makeProvince('450000', '广西壮族自治区', '广西', '南宁', '华南'),
    makeProvince('350000', '福建省', '福建', '福州', '华东')
  ]
}


/** compare 用例专用：真实几何路径（正方形），面积/中心点都可手算 */
function makeGeoProvince(id: string, short: string, path: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id, name: short, short: short, abbr: 'X', capital: short + '市', region: '华北', path: path
  }
  return p
}

/**
 * big  100×100 = 10000，中心 (50,50)
 * small 20×20 = 400，中心 (210,10)      → big/small 面积比 25，方位：big 看 small 是「东」
 * near 9.6×10 = 96 / near2 10×10 = 100 → 面积比 1.04，面积题应被拒
 * diag 10×10，中心 (155,155)            → 与 big 夹角 45°，方位题应被拒
 */
function makeCompareFixture(): ChinaProvince[] {
  return [
    makeGeoProvince('900001', '大省', 'M0 0L100 0L100 100L0 100Z'),
    makeGeoProvince('900002', '小省', 'M200 0L220 0L220 20L200 20Z'),
    makeGeoProvince('900003', '近省', 'M300 0L309.6 0L309.6 10L300 10Z'),
    makeGeoProvince('900004', '近省二', 'M400 0L410 0L410 10L400 10Z'),
    makeGeoProvince('900005', '斜省', 'M150 150L160 150L160 160L150 160Z')
  ]
}

export default function mapToolValidationTest() {
  describe('validateMapCardArgs', () => {
    it('accepts minimal valid args', 0, () => {
      const r = validateMapCardArgs('{"skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertTrue()
    })

    it('accepts valid focus_province by short name', 0, () => {
      const r = validateMapCardArgs('{"skill_key":"general_social","focus_province":"山西"}', makeFixture())
      expect(r.ok).assertTrue()
    })

    it('accepts valid focus_province by full name', 0, () => {
      const r = validateMapCardArgs('{"skill_key":"general_social","focus_province":"山西省"}', makeFixture())
      expect(r.ok).assertTrue()
    })

    it('rejects unknown focus_province', 0, () => {
      const r = validateMapCardArgs('{"skill_key":"general_social","focus_province":"东德"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects wrong skill_key', 0, () => {
      const r = validateMapCardArgs('{"skill_key":"math_addition"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects bad JSON', 0, () => {
      const r = validateMapCardArgs('{not json', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects null provinces (data not ready)', 0, () => {
      const r = validateMapCardArgs('{"skill_key":"general_social"}', null)
      expect(r.ok).assertFalse()
    })
  })

  describe('validateMapQuizArgs', () => {
    it('accepts valid choice args', 0, () => {
      const r = validateMapQuizArgs('{"mode":"choice","province":"广东","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertTrue()
    })

    it('accepts valid locate with clue name', 0, () => {
      const r = validateMapQuizArgs('{"mode":"locate","province":"广东","clue":"name","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertTrue()
    })

    it('accepts valid locate with clue capital when capital differs from short', 0, () => {
      const r = validateMapQuizArgs('{"mode":"locate","province":"广东","clue":"capital","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertTrue()
    })

    it('accepts valid write args', 0, () => {
      const r = validateMapQuizArgs('{"mode":"write","province":"山西","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertTrue()
    })

    it('rejects unknown mode', 0, () => {
      const r = validateMapQuizArgs('{"mode":"draw","province":"广东","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects unknown province', 0, () => {
      const r = validateMapQuizArgs('{"mode":"choice","province":"东德","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects clue on choice', 0, () => {
      const r = validateMapQuizArgs('{"mode":"choice","province":"广东","clue":"name","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects clue on write', 0, () => {
      const r = validateMapQuizArgs('{"mode":"write","province":"广东","clue":"capital","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects locate capital self-answer province (fixture capital === short)', 0, () => {
      const r = validateMapQuizArgs('{"mode":"locate","province":"北京","clue":"capital","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects missing province', 0, () => {
      const r = validateMapQuizArgs('{"mode":"choice","skill_key":"general_social"}', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects bad JSON', 0, () => {
      const r = validateMapQuizArgs('nope', makeFixture())
      expect(r.ok).assertFalse()
    })

    it('rejects null provinces (data not ready)', 0, () => {
      const r = validateMapQuizArgs('{"mode":"choice","province":"广东","skill_key":"general_social"}', null)
      expect(r.ok).assertFalse()
    })
  })

  describe('capital self-answer guard against real data', () => {
    it('all 6 real capital===short provinces rejected with clue capital', 0, () => {
      // 真实 6 省硬拒——数据逐字与 rawfile 一致（id/short/capital），不加载 rawfile
      const real: ChinaProvince[] = [
        makeProvince('110000', '北京市', '北京', '北京', '华北'),
        makeProvince('120000', '天津市', '天津', '天津', '华北'),
        makeProvince('310000', '上海市', '上海', '上海', '华东'),
        makeProvince('500000', '重庆市', '重庆', '重庆', '西南'),
        makeProvince('810000', '香港特别行政区', '香港', '香港', '华南'),
        makeProvince('820000', '澳门特别行政区', '澳门', '澳门', '华南')
      ]
      for (const p of real) {
        const args = `{"mode":"locate","province":"${p.short}","clue":"capital","skill_key":"general_social"}`
        const r = validateMapQuizArgs(args, real)
        expect(r.ok).assertFalse()
      }
    })

    it('error message suggests clue name for self-answer province', 0, () => {
      const real: ChinaProvince[] = [
        makeProvince('110000', '北京市', '北京', '北京', '华北')
      ]
      const r = validateMapQuizArgs('{"mode":"locate","province":"北京","clue":"capital","skill_key":"general_social"}', real)
      expect(r.error.indexOf('name') >= 0).assertTrue()
    })
  })

  describe('validateMapQuizArgs_shape_compare', () => {
    const fixture = makeCompareFixture()

    it('accepts shape mode', 0, () => {
      const args = '{"mode":"shape","province":"大省","skill_key":"general_social"}'
      expect(validateMapQuizArgs(args, fixture).ok).assertTrue()
    })

    it('shape mode rejects clue', 0, () => {
      const args = '{"mode":"shape","province":"大省","clue":"name","skill_key":"general_social"}'
      const result = validateMapQuizArgs(args, fixture)
      expect(result.ok).assertFalse()
      expect(result.error.indexOf('clue') >= 0).assertTrue()
    })

    it('compare requires province_b', 0, () => {
      const args = '{"mode":"compare","compare":"area","province":"大省","skill_key":"general_social"}'
      const result = validateMapQuizArgs(args, fixture)
      expect(result.ok).assertFalse()
      expect(result.error.indexOf('province_b') >= 0).assertTrue()
    })

    it('compare requires compare kind', 0, () => {
      const args = '{"mode":"compare","province":"大省","province_b":"小省","skill_key":"general_social"}'
      const result = validateMapQuizArgs(args, fixture)
      expect(result.ok).assertFalse()
      expect(result.error.indexOf('compare') >= 0).assertTrue()
    })

    it('compare rejects same province twice', 0, () => {
      const args = '{"mode":"compare","compare":"area","province":"大省","province_b":"大省","skill_key":"general_social"}'
      const result = validateMapQuizArgs(args, fixture)
      expect(result.ok).assertFalse()
      expect(result.error.indexOf('不能是同一个省') >= 0).assertTrue()
    })

    it('compare area accepts a clearly different pair', 0, () => {
      const args = '{"mode":"compare","compare":"area","province":"大省","province_b":"小省","skill_key":"general_social"}'
      const result = validateMapQuizArgs(args, fixture)
      expect(result.ok).assertTrue()
    })

    it('compare area rejects a near-tie pair', 0, () => {
      const args = '{"mode":"compare","compare":"area","province":"近省","province_b":"近省二","skill_key":"general_social"}'
      const result = validateMapQuizArgs(args, fixture)
      expect(result.ok).assertFalse()
      expect(result.error.indexOf('面积太接近') >= 0).assertTrue()
    })

    it('compare direction accepts a clean east relation', 0, () => {
      const args = '{"mode":"compare","compare":"direction","province":"大省","province_b":"小省","skill_key":"general_social"}'
      expect(validateMapQuizArgs(args, fixture).ok).assertTrue()
    })

    it('compare direction rejects a diagonal relation', 0, () => {
      const args = '{"mode":"compare","compare":"direction","province":"大省","province_b":"斜省","skill_key":"general_social"}'
      const result = validateMapQuizArgs(args, fixture)
      expect(result.ok).assertFalse()
      expect(result.error.indexOf('正南正北正东正西') >= 0).assertTrue()
    })
  })
}
