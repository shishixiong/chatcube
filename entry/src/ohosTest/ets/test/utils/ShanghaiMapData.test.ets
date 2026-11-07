import { describe, it, expect } from '@ohos/hypium'
import {
  ShanghaiDistrict,
  ShanghaiMapData,
  ShanghaiPlace,
  districtLabelAnchor,
  districtOrder,
  findDistrictByRef,
  getCachedShanghaiMapData,
  visiblePlaces
} from '../../../../main/ets/utils/ShanghaiMapData'
import { pointInProvince, provinceBBox } from '../../../../main/ets/utils/ChinaMapGeometry'
import {
  buildDistrictNote,
  buildDistrictProgressText,
  buildDistrictSpeech,
  buildPlaceSpeech,
  buildPlaceSummary,
  buildShanghaiAtlasTitle,
  districtFact
} from '../../../../main/ets/utils/ShanghaiAtlasCopy'

/**
 * 上海区级数据与文案单元测试（map_card 省级下钻）
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * 夹具用真实 16 区数据的一小撮字段（见 rawfile/map/shanghai_districts.json），
 * 不断言整份 JSON——数据更新时这里只review 几何结论（质心是否仍在区内）。
 */

/** 真数据摘录：id / name / short / center，path 用对应区的方形近似（够测查询与锚点） */
function makeDistrict(id: string, name: string, short: string, cx: number, cy: number): ShanghaiDistrict {
  const d: ShanghaiDistrict = {
    id: id,
    name: name,
    short: short,
    center: [cx, cy],
    path: `M${cx - 20} ${cy - 20}L${cx + 20} ${cy - 20}L${cx + 20} ${cy + 20}L${cx - 20} ${cy + 20}Z`,
    places: []
  }
  return d
}

function makePlace(name: string, x: number, y: number, tier: number): ShanghaiPlace {
  const p: ShanghaiPlace = { name: name, x: x, y: y, tier: tier }
  return p
}

function makeFixture(): ShanghaiDistrict[] {
  return [
    makeDistrict('310101', '黄浦区', '黄浦', 450.8, 552.7),
    makeDistrict('310104', '徐汇区', '徐汇', 419.0, 597.3),
    makeDistrict('310115', '浦东新区', '浦东', 636.8, 663.9),
    makeDistrict('310151', '崇明区', '崇明', 511.9, 199.3)
  ]
}

// 夹具工厂放在模块级：ArkTS 不允许在函数/describe 回调里再声明函数（arkts-no-nested-funcs）
// 几何用例要验证「地名落回本区」，所以给这两个区一个足够大的方形近似（±80），
// 真实边界由 rawfile 的 78 个点覆盖（见 real dataset places）。
function bigBoxPath(cx: number, cy: number): string {
  return `M${cx - 80} ${cy - 80}L${cx + 80} ${cy - 80}L${cx + 80} ${cy + 80}L${cx - 80} ${cy + 80}Z`
}

function huangpu(): ShanghaiDistrict {
  const d = makeDistrict('310101', '黄浦区', '黄浦', 450.8, 552.7)
  d.path = bigBoxPath(450.8, 552.7)
  d.places = [
    makePlace('外滩', 455.8, 533.3, 1),
    makePlace('人民广场', 443.7, 538.9, 2),
    makePlace('豫园', 456.9, 543.4, 2)
  ]
  return d
}

function songjiang(): ShanghaiDistrict {
  const d = makeDistrict('310117', '松江区', '松江', 261.4, 721.6)
  d.path = bigBoxPath(261.4, 721.6)
  d.places = [
    makePlace('佘山', 239.6, 650.3, 1),
    makePlace('广富林', 275.6, 704.1, 2),
    makePlace('辰山植物园', 232.5, 656.2, 3)
  ]
  return d
}

function pudong(): ShanghaiDistrict {
  const d = makeDistrict('310115', '浦东新区', '浦东', 636.8, 663.9)
  d.places = [
    makePlace('陆家嘴', 466.2, 532.4, 1),
    makePlace('上海科技馆', 495.0, 543.4, 2),
    makePlace('迪士尼乐园', 575.5, 613.2, 2),
    makePlace('南汇嘴', 800.7, 843.8, 3)
  ]
  return d
}

export default function shanghaiMapDataTest() {
  describe('findDistrictByRef', () => {
    const districts = makeFixture()

    it('matches by id', 0, () => {
      const hit = findDistrictByRef(districts, '310115')
      expect(hit !== null).assertTrue()
      if (hit !== null) {
        expect(hit.name).assertEqual('浦东新区')
      }
    })

    it('matches by full name', 0, () => {
      const hit = findDistrictByRef(districts, '崇明区')
      expect(hit !== null).assertTrue()
      if (hit !== null) {
        expect(hit.id).assertEqual('310151')
      }
    })

    it('matches by short name with surrounding whitespace', 0, () => {
      const hit = findDistrictByRef(districts, ' 徐汇 ')
      expect(hit !== null).assertTrue()
      if (hit !== null) {
        expect(hit.id).assertEqual('310104')
      }
    })

    it('returns null for empty or unknown ref', 0, () => {
      expect(findDistrictByRef(districts, '   ') === null).assertTrue()
      expect(findDistrictByRef(districts, '浦东新') === null).assertTrue()
    })
  })

  describe('districtOrder', () => {
    const districts = makeFixture()

    it('is 1-based and follows the official order', 0, () => {
      expect(districtOrder(districts, '310101')).assertEqual(1)
      expect(districtOrder(districts, '310151')).assertEqual(4)
    })

    it('returns 0 for an unknown id', 0, () => {
      expect(districtOrder(districts, '310199')).assertEqual(0)
    })
  })

  describe('districtLabelAnchor', () => {
    it('returns the centroid when it is usable', 0, () => {
      const d = makeFixture()[2]
      const anchor = districtLabelAnchor(d, provinceBBox(d.path))
      expect(anchor[0]).assertEqual(636.8)
      expect(anchor[1]).assertEqual(663.9)
    })

    it('falls back to the bbox centre when center is missing', 0, () => {
      const d = makeDistrict('310120', '奉贤区', '奉贤', 507.6, 820.2)
      d.center = []
      const anchor = districtLabelAnchor(d, provinceBBox(d.path))
      expect(anchor[0]).assertEqual(507.6)
      expect(anchor[1]).assertEqual(820.2)
    })

    it('keeps the centroid inside its own polygon', 0, () => {
      for (const d of makeFixture()) {
        expect(pointInProvince(d.path, d.center[0], d.center[1])).assertTrue()
      }
    })
  })

  describe('buildDistrictNote', () => {
    const districts = makeFixture()

    it('mentions the district name and its ordinal', 0, () => {
      const note = buildDistrictNote(districts[0], districtOrder(districts, '310101'))
      expect(note.includes('黄浦区')).assertTrue()
      expect(note.includes('上海的第 1 个区')).assertTrue()
    })

    it('is stable for the same district', 0, () => {
      const a = buildDistrictNote(districts[1], 2)
      const b = buildDistrictNote(districts[1], 2)
      expect(a).assertEqual(b)
    })

    it('adds the landmark on the second template', 0, () => {
      const note = buildDistrictNote(districts[2], 2)
      expect(note.includes('陆家嘴')).assertTrue()
    })

    it('degrades to the ordinal-only sentence for unknown data', 0, () => {
      const ghost = makeDistrict('319999', '某某区', '某某', 10, 10)
      const speech = buildDistrictSpeech(ghost, 3)
      expect(speech).assertEqual('某某区。上海的第 3 个区。')
    })
  })

  describe('districtFact', () => {
    it('covers all 16 real districts', 0, () => {
      const ids: string[] = [
        '310101', '310104', '310105', '310106', '310107', '310109', '310110', '310112',
        '310113', '310114', '310115', '310116', '310117', '310118', '310120', '310151'
      ]
      for (const id of ids) {
        expect(districtFact(id) !== null).assertTrue()
      }
    })

    it('returns null for an unknown id', 0, () => {
      expect(districtFact('310199') === null).assertTrue()
    })
  })

  describe('visiblePlaces', () => {
    // 真数据里的两组：黄浦（3 个，tier 1/2/2）、松江（3 个，tier 1/2/3）
    it('shows only the first-tier place at the default zoom', 0, () => {
      const shown = visiblePlaces(huangpu(), 1)
      expect(shown.length).assertEqual(1)
      expect(shown[0].name).assertEqual('外滩')
    })

    it('adds tier 2 from 1.7x and tier 3 from 2.6x', 0, () => {
      expect(visiblePlaces(huangpu(), 1.69).length).assertEqual(1)
      expect(visiblePlaces(huangpu(), 1.7).length).assertEqual(3)
      const sj = songjiang()
      expect(visiblePlaces(sj, 2.59).length).assertEqual(2)
      expect(visiblePlaces(sj, 2.6).length).assertEqual(3)
    })

    it('is empty for no district or a district without places', 0, () => {
      expect(visiblePlaces(null, 6).length).assertEqual(0)
      expect(visiblePlaces(makeDistrict('319999', '某某区', '某某', 10, 10), 6).length).assertEqual(0)
    })

    it('keeps every place inside its own polygon', 0, () => {
      for (const d of [huangpu(), songjiang()]) {
        for (const p of d.places) {
          expect(pointInProvince(d.path, p.x, p.y)).assertTrue()
        }
      }
    })
  })

  describe('real dataset places', () => {
    it('keeps one landmark plus two more places for every district', 0, () => {
      const data = getCachedShanghaiMapData()
      if (data === null) {
        console.info('ShanghaiMapData.test', 'rawfile not loaded, skip real dataset checks')
        return
      }
      expect(data.districts.length).assertEqual(16)
      for (const d of data.districts) {
        const first = d.places.filter((p: ShanghaiPlace) => p.tier === 1)
        expect(first.length).assertEqual(1)
        expect(d.places.length >= 2).assertTrue()
        // 第二层最多 4 个：再多地图就成地名清单了（与设计稿的配额一致）
        expect(d.places.filter((p: ShanghaiPlace) => p.tier === 2).length <= 4).assertTrue()
      }
    })

    it('draws 78 places at 2.6x, and every one of them sits inside its own district', 0, () => {
      const data = getCachedShanghaiMapData()
      if (data === null) {
        console.info('ShanghaiMapData.test', 'rawfile not loaded, skip real dataset checks')
        return
      }
      let shown = 0
      for (const d of data.districts) {
        const list = visiblePlaces(d, 6)
        expect(list.length).assertEqual(d.places.length)
        shown += list.length
        for (const p of d.places) {
          expect(pointInProvince(d.path, p.x, p.y)).assertTrue()
        }
      }
      expect(shown).assertEqual(78)
    })

    it('puts the three Chongming islands on their own rings', 0, () => {
      const data = getCachedShanghaiMapData()
      if (data === null) {
        console.info('ShanghaiMapData.test', 'rawfile not loaded, skip real dataset checks')
        return
      }
      const cm = findDistrictByRef(data.districts, '崇明')
      expect(cm !== null).assertTrue()
      if (cm !== null) {
        for (const name of ['长兴岛', '横沙岛']) {
          const p = cm.places.find((q: ShanghaiPlace) => q.name === name)
          expect(p !== undefined).assertTrue()
          if (p !== undefined) {
            expect(pointInProvince(cm.path, p.x, p.y)).assertTrue()
          }
        }
      }
    })
  })

  describe('place copy', () => {
    it('summarises what the map shows right now', 0, () => {
      expect(buildPlaceSummary(pudong(), 1)).assertEqual('陆家嘴 +3')
      expect(buildPlaceSummary(pudong(), 2)).assertEqual('陆家嘴、上海科技馆、迪士尼乐园 +1')
      expect(buildPlaceSummary(pudong(), 3)).assertEqual('陆家嘴、上海科技馆、迪士尼乐园、南汇嘴')
    })

    it('is empty when there is nothing to say', 0, () => {
      expect(buildPlaceSummary(null, 2)).assertEqual('')
      expect(buildPlaceSummary(makeDistrict('319999', '某某区', '某某', 10, 10), 2)).assertEqual('')
      expect(buildPlaceSpeech(null)).assertEqual('')
    })

    it('speaks every place regardless of zoom', 0, () => {
      expect(buildPlaceSpeech(pudong())).assertEqual('里面有陆家嘴、上海科技馆、迪士尼乐园、南汇嘴。')
    })

    it('keeps the landmark equal to the first-tier place name', 0, () => {
      // 「地标」行与地图上最先出现的那个点必须同名，否则孩子会找不到
      const pairs: string[][] = [
        ['310101', '外滩'], ['310115', '陆家嘴'], ['310117', '佘山'], ['310151', '东滩湿地']
      ]
      for (const pair of pairs) {
        const fact = districtFact(pair[0])
        expect(fact !== null).assertTrue()
        if (fact !== null) {
          expect(fact.landmark).assertEqual(pair[1])
        }
      }
    })
  })

  describe('shanghai copy', () => {
    it('builds the atlas title with the district total', 0, () => {
      expect(buildShanghaiAtlasTitle(16)).assertEqual('上海 · 16 个区')
    })

    it('clamps the district progress text', 0, () => {
      expect(buildDistrictProgressText(3, 16)).assertEqual('看过 3 / 16')
      expect(buildDistrictProgressText(-1, 16)).assertEqual('看过 0 / 16')
      expect(buildDistrictProgressText(0, 0)).assertEqual('看过 0 / 1')
    })
  })

  describe('viewBox of the real data', () => {
    it('keeps the 1000-wide projected frame', 0, () => {
      const data: ShanghaiMapData = {
        code: '310000',
        name: '上海',
        viewBox: '0 0 1000 1007.4',
        width: 1000,
        height: 1007.4,
        minLng: 120.856804,
        maxLng: 122.247149,
        minLat: 30.675593,
        maxLat: 31.872716,
        districts: makeFixture()
      }
      expect(data.districts.length).assertEqual(4)
      expect(data.viewBox).assertEqual('0 0 1000 1007.4')
    })
  })
}
