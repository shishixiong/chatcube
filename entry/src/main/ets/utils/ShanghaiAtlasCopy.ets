// entry/src/main/ets/utils/ShanghaiAtlasCopy.ets
/**
 * 上海下钻页的文案（map_card 讲解型 · 省级下钻）
 *
 * 与 MapAtlasCopy 同一套写法：纯函数、稳定轮换、同一句每次说一样（可复习）。
 * 区级文案按「序号 % 3」轮换，跟 MapAtlasCopy.teacherNoteVariant 的取模思路一致，
 * 但区级不按 id 散列——区的官方排序本身就是一节小课的天然顺序，
 * 「上海的第 6 个区」这种序数更值得先说出口。
 *
 * 数据来源：DISTRICT_FACTS 只放「一句话地标」，其余句子由模板组装；
 * 新增区数据不进来时全部走兜底句，不会出现 undefined。
 */

import { ShanghaiDistrict, ShanghaiPlace, visiblePlaces } from './ShanghaiMapData'

/**
 * 16 个区的地标一句话（资料卡「地标」行 + 老师留言）。
 * landmark 一律取该区 tier 1 小地名的名字，保证「地标」与地图上那个最先出现的点同名。
 */
export interface DistrictFact {
  /** 地标名，如「外滩」「陆家嘴」 */
  landmark: string
  /** 一句能讲给孩子听的说明 */
  desc: string
}

const DISTRICT_FACTS: Record<string, DistrictFact> = {
  '310101': { landmark: '外滩', desc: '上海的市中心，外滩的老房子和豫园的园林都在这里。' },
  '310104': { landmark: '徐家汇', desc: '徐家汇以前是三条河汇在一起的地方，现在有天文台和交通大学。' },
  '310105': { landmark: '中山公园', desc: '长宁有中山公园和虹桥机场，飞机起落的时候从头顶上飞过去。' },
  '310106': { landmark: '静安寺', desc: '静安有一座金色的寺庙，四周是最热闹的马路。' },
  '310107': { landmark: '长风公园', desc: '普陀有苏州河的一个大弯，河边的公园能划船。' },
  '310109': { landmark: '鲁迅公园', desc: '虹口在黄浦江北岸，鲁迅公园里树木很多，老电影院放过最早的电影。' },
  '310110': { landmark: '共青森林公园', desc: '杨浦在上海的东北角，江边有一大片森林，还有很长的滨江步道。' },
  '310112': { landmark: '七宝老街', desc: '闵行很大，一条老街上有小桥、汤团和古寺。' },
  '310113': { landmark: '吴淞口', desc: '宝山在长江入海口，江水和海水在这里碰头。' },
  '310114': { landmark: '秋霞圃', desc: '嘉定的秋霞圃是一座几百岁的老园林，镇上还通着有轨电车。' },
  '310115': { landmark: '陆家嘴', desc: '浦东有东方明珠和高楼群，还有一座大机场。' },
  '310116': { landmark: '金山嘴渔村', desc: '金山在上海的最南边，有海边的渔村和一座小岛。' },
  '310117': { landmark: '佘山', desc: '松江的佘山是上海最高的山，山上有天文台。' },
  '310118': { landmark: '朱家角古镇', desc: '青浦有淀山湖和朱家角古镇，河多桥也多。' },
  '310120': { landmark: '上海之鱼', desc: '奉贤在上海的南边，有一个像小鱼一样的湖，再往南就是海。' },
  '310151': { landmark: '东滩湿地', desc: '崇明是一座大岛，岛上农田成片，冬天有很多候鸟。' }
}

const NOTE_VARIANT_COUNT: number = 3

export function districtFact(districtId: string): DistrictFact | null {
  const fact: DistrictFact | undefined = DISTRICT_FACTS[districtId]
  return fact === undefined ? null : fact
}

/** 「小星老师说」的区级留言：按官方序号稳定轮换三套模板 */
export function buildDistrictNote(district: ShanghaiDistrict, order: number): string {
  const fact = districtFact(district.id)
  const desc = fact === null ? '' : fact.desc
  const landmark = fact === null ? '' : fact.landmark
  const variant = order > 0 ? (order - 1) % NOTE_VARIANT_COUNT : 0
  if (variant === 1) {
    const head = landmark === '' ? '' : `${landmark}就在${district.name}。`
    return `${district.name}是上海的第 ${order} 个区。${head}${desc}`
  }
  if (variant === 2) {
    const head = landmark === '' ? '' : `听名字就知道，${district.name}的主角是${landmark}。`
    return `${head}${desc}它在上海的区里排第 ${order}。`
  }
  return `这里是${district.name}，上海的第 ${order} 个区。${desc}`
}

/** 朗读文案：全名 + 序号 + 地标，比资料卡短，读完约 6 秒 */
export function buildDistrictSpeech(district: ShanghaiDistrict, order: number): string {
  const fact = districtFact(district.id)
  if (fact === null) {
    return `${district.name}。上海的第 ${order} 个区。`
  }
  return `${district.name}。上海的第 ${order} 个区。${fact.landmark}。`
}

/**
 * 资料卡「里面还有」一行：列出此刻地图上真的看得到的小地名。
 * more > 0 表示还藏着几个，放大地图才出现——卡片和地图说的是同一句话。
 */
export function buildPlaceSummary(district: ShanghaiDistrict | null, zoom: number): string {
  if (district === null) {
    return ''
  }
  const shown = visiblePlaces(district, zoom)
  if (shown.length === 0) {
    return ''
  }
  const names: string[] = []
  for (const p of shown) {
    names.push(p.name)
  }
  const total = Array.isArray(district.places) ? district.places.length : 0
  const hidden: number = total - shown.length
  return hidden > 0 ? `${names.join('、')} +${hidden}` : names.join('、')
}

/** 朗读用：把全部小地名串起来（朗读不受地图倍率限制，孩子听完能自己去找） */
export function buildPlaceSpeech(district: ShanghaiDistrict | null): string {
  if (district === null || !Array.isArray(district.places) || district.places.length === 0) {
    return ''
  }
  const names: string[] = []
  for (const p of district.places as ShanghaiPlace[]) {
    names.push(p.name)
  }
  return `里面有${names.join('、')}。`
}

/** 上海这一页的页眉：「上海 · 16 个区」 */
export function buildShanghaiAtlasTitle(districtTotal: number): string {
  return `上海 · ${districtTotal} 个区`
}

/** 区级进度：「看过 3 / 16」 */
export function buildDistrictProgressText(visited: number, total: number): string {
  return `看过 ${Math.max(0, visited)} / ${Math.max(1, total)}`
}

/** 资料卡空态中的提示（上海页还没选区） */
export function buildDistrictEmptyHint(districtTotal: number): string {
  return `点地图上的任意一个区，看看它在上海的哪一边。一共 ${districtTotal} 个区，慢慢认。`
}

/** 全国资料卡底部的下钻入口：「再看看 16 个区」 */
export function buildDrilldownEntryLabel(districtTotal: number): string {
  return `再看看 ${districtTotal} 个区`
}

/** 无障碍朗读：面包屑与返回键 */
export function buildBackToChinaLabel(): string {
  return '返回全国地图'
}
