/**
 * CategorizationIconBank - 分类小管家图标解析层
 *
 * 把题库物品名解析为 rawfile 图标路径 (kids/icons/<id>.svg, 由
 * scripts/export-categorization-icons.mjs 从 docs/categorization-game.html 导出),
 * 供 CategorizationCard 渲染绘本感 SVG 物品卡与类别字形桶。
 *
 * 解析规则:
 *   1. 归一化: trim + 全角空格转半角 + 折叠连续空白
 *   2. 全称直查 ('帽子 m' / 'apple 苹果' 在数据表中有全称条目)
 *   3. 未命中再按空格拆词兜底 (LLM 只写子词 '帽子' 的情况)
 *   4. 手工别名表: LLM 常用变体名 → 视觉一致的图标 (如 萝卜→carrot)
 *   5. 未命中返回 '' —— 组件层退化 emoji → 文字, 题库外自由题不受影响
 *
 * 字母桶 (m/p/b/A/B/C) 无类别字形 (letter-* 图标内含 <text>, ArkUI SVG 子集不支持,
 * 导出脚本已排除), 返回 '' 由组件层渲染字母色块。
 */

import { CATEGORIZATION_ITEM_ICON_DATA, CATEGORIZATION_BIN_GLYPH_DATA } from './CategorizationIconBankData'

const ICON_DIR_PREFIX: string = 'kids/icons/'

// 手工别名: 仅收录与已有图标视觉一致的 LLM 常用变体名 (格式同数据文件「名称|图标id」)
const MANUAL_ITEM_ALIAS_DATA: string = '萝卜|carrot'

// 归一化查询键: trim + 全角空格转半角 + 折叠连续空白
function normalizeIconLookupKey(label: string): string {
  let key = label.trim()
  key = key.replace(/　/g, ' ')
  key = key.replace(/\s+/g, ' ')
  return key
}

// 解析「名称|图标id」数据为查表 Map。同名录先到先得 (数据顺序即主题库顺序)。
function buildIconLookup(dataEntries: string[]): Map<string, string> {
  const map = new Map<string, string>()
  for (let i = 0; i < dataEntries.length; i++) {
    const line = dataEntries[i].trim()
    if (line === '') {
      continue
    }
    const sep = line.indexOf('|')
    if (sep <= 0) {
      continue
    }
    const name = normalizeIconLookupKey(line.substring(0, sep))
    const id = line.substring(sep + 1).trim()
    if (name === '' || id === '') {
      continue
    }
    if (!map.has(name)) {
      map.set(name, id)
    }
  }
  return map
}

function toIconPath(id: string): string {
  return ICON_DIR_PREFIX + id + '.svg'
}

function lookupIconPath(map: Map<string, string>, label: string): string {
  const key = normalizeIconLookupKey(label)
  if (key === '') {
    return ''
  }
  const direct = map.get(key)
  if (direct !== undefined) {
    return toIconPath(direct)
  }
  // 拆词兜底: '帽子 m' 只写 '帽子' 也可命中 (全称已直查, 这里处理子词)
  const tokens = key.split(' ')
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i]
    if (token === '') {
      continue
    }
    const hit = map.get(token)
    if (hit !== undefined) {
      return toIconPath(hit)
    }
  }
  return ''
}

const ITEM_ICON_IDS: Map<string, string> = buildIconLookup(
  CATEGORIZATION_ITEM_ICON_DATA.split('\n').concat(MANUAL_ITEM_ALIAS_DATA.split('\n')))
const BIN_GLYPH_IDS: Map<string, string> = buildIconLookup(CATEGORIZATION_BIN_GLYPH_DATA.split('\n'))

/** 物品名 → 物品图标 rawfile 路径; 未命中返回 '' */
export function resolveItemIconPath(label: string): string {
  return lookupIconPath(ITEM_ICON_IDS, label)
}

/** 桶名 → 类别字形 rawfile 路径; 未命中返回 '' */
export function resolveBinGlyphPath(name: string): string {
  return lookupIconPath(BIN_GLYPH_IDS, name)
}
