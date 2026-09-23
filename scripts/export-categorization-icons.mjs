#!/usr/bin/env node
/**
 * export-categorization-icons.mjs — 分类小管家图标资源导出
 *
 * 从 docs/categorization-game.html（分类小管家高保真原型）导出：
 *   1. 内联 <symbol> 图标 → entry/src/main/resources/rawfile/kids/icons/<name>.svg
 *      （CSS 变量解析为具体色值，.ln/.eye class 展开为显式 stroke/fill 属性，
 *        <g> 组展平：组内属性下推、transform 串接 —— 保持 ArkUI Image 支持的保守 SVG 子集）
 *   2. 题库图标映射数据 → entry/src/main/ets/utils/CategorizationIconBankData.ets
 *      （物品名→图标 id、桶名→类别字形 id，供 CategorizationIconBank.ets 查表）
 *
 * 排除：i-letter-*（内含 <text>，ArkUI SVG 子集不支持）、i-star-gold（星星展示走 app 全局奖励浮层）。
 *
 * 用法: node scripts/export-categorization-icons.mjs
 * 仓库根目录执行。HTML 是唯一数据源，改原型后重跑本脚本。
 */
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const HTML_PATH = join(ROOT, 'docs/categorization-game.html')
const ICON_DIR = join(ROOT, 'entry/src/main/resources/rawfile/kids/icons')
const BANK_DATA_PATH = join(ROOT, 'entry/src/main/ets/utils/CategorizationIconBankData.ets')

const EXCLUDED_IDS = (id) => id.startsWith('i-letter-') || id === 'i-star-gold'

const html = readFileSync(HTML_PATH, 'utf-8')

// ── 1. 解析 :root CSS 变量 ──
const rootMatch = html.match(/:root\{([^}]*)\}/)
if (!rootMatch) throw new Error('cannot find :root block')
const vars = {}
for (const m of rootMatch[1].matchAll(/--([\w-]+)\s*:\s*([^;}]+)/g)) {
  vars[`--${m[1]}`] = m[2].trim()
}
function resolveVar(value) {
  return value.replace(/var\((--[\w-]+)\)/g, (_, name) => {
    if (!(name in vars)) throw new Error(`unknown CSS var: ${name}`)
    return vars[name]
  })
}

// ── 2. 提取 symbol 并展平为保守 SVG 子集 ──
const PRESENTATION_PROPS = ['fill', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin', 'opacity']

const CLASS_DEFAULTS = {
  // .ic .ln{fill:none;stroke:var(--c-line);stroke-width:var(--ic-line);linecap/linejoin:round}
  ln: {
    fill: 'none',
    stroke: resolveVar('var(--c-line)'),
    'stroke-width': resolveVar('var(--ic-line)'),
    'stroke-linecap': 'round',
    'stroke-linejoin': 'round'
  },
  // .ic .eye{fill:var(--c-line)}
  eye: { fill: resolveVar('var(--c-line)') }
}

function parseAttrs(attrStr) {
  const attrs = {}
  for (const m of attrStr.matchAll(/([\w-]+)\s*=\s*"([^"]*)"/g)) {
    attrs[m[1]] = m[2]
  }
  return attrs
}

function parseStyle(styleStr) {
  const out = {}
  for (const decl of styleStr.split(';')) {
    const idx = decl.indexOf(':')
    if (idx < 0) continue
    const prop = decl.slice(0, idx).trim()
    const val = decl.slice(idx + 1).trim()
    if (prop !== '' && val !== '') out[prop] = val
  }
  return out
}

// 计算一个元素解析后的展示属性：parentDefaults → classDefaults → 显式属性 → inline style
function resolvePresentation(parentDefaults, attrs) {
  let map = { ...parentDefaults }
  const cls = attrs['class'] ?? ''
  for (const c of cls.split(/\s+/)) {
    if (CLASS_DEFAULTS[c]) map = { ...map, ...CLASS_DEFAULTS[c] }
  }
  for (const p of PRESENTATION_PROPS) {
    if (attrs[p] !== undefined) map[p] = attrs[p]
  }
  if (attrs['style'] !== undefined) {
    const style = parseStyle(attrs['style'])
    for (const p of PRESENTATION_PROPS) {
      if (style[p] !== undefined) map[p] = resolveVar(style[p])
    }
  }
  return map
}

// 逐 token 扫描 symbol 内部：叶子标签自闭合；<g> 入栈，</g> 出栈
function flattenSymbolChildren(inner) {
  const out = []
  const stack = [] // 每层: { defaults, transform }
  const tagRe = /<(\/?)([\w-]+)((?:[^>"]|"[^"]*")*)>/g
  let match
  while ((match = tagRe.exec(inner)) !== null) {
    const [full, closing, tag, attrStr] = match
    if (tag === 'text' || tag === 'foreignObject') {
      throw new Error(`unsupported element <${tag}> (ArkUI SVG subset)`)
    }
    if (closing) {
      if (tag !== 'g') throw new Error(`unexpected closing </${tag}>`)
      stack.pop()
      continue
    }
    const parent = stack[stack.length - 1] ?? { defaults: {}, transform: '' }
    const attrs = parseAttrs(attrStr)
    const pres = resolvePresentation(parent.defaults, attrs)
    let transform = attrs['transform'] ?? ''
    if (parent.transform !== '') {
      transform = transform === '' ? parent.transform : `${parent.transform} ${transform}`
    }
    if (tag === 'g') {
      stack.push({ defaults: pres, transform })
      continue
    }
    // 叶子元素：几何属性按原顺序 + 解析后的展示属性
    const parts = [`<${tag}`]
    for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class' || k === 'style' || k === 'transform' || PRESENTATION_PROPS.includes(k)) continue
      parts.push(` ${k}="${v}"`)
    }
    for (const p of PRESENTATION_PROPS) {
      if (pres[p] !== undefined) parts.push(` ${p}="${pres[p]}"`)
    }
    if (transform !== '') parts.push(` transform="${transform}"`)
    parts.push('/>')
    out.push(parts.join(''))
  }
  if (stack.length !== 0) throw new Error('unclosed <g>')
  return out
}

const symbolRe = /<symbol\s+id="([^"]+)"\s+viewBox="([^"]+)"\s+class="ic">([\s\S]*?)<\/symbol>/g
const icons = {}
let match
while ((match = symbolRe.exec(html)) !== null) {
  const [, id, viewBox, inner] = match
  if (EXCLUDED_IDS(id)) continue
  icons[id] = { viewBox, body: flattenSymbolChildren(inner) }
}
if (Object.keys(icons).length === 0) throw new Error('no symbols extracted')

// ── 3. 写 SVG 文件 ──
mkdirSync(ICON_DIR, { recursive: true })
const stale = new Set(readdirSync(ICON_DIR).filter((f) => f.endsWith('.svg')))
let written = 0
for (const [id, { viewBox, body }] of Object.entries(icons)) {
  const name = id.replace(/^i-/, '')
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">\n${body.map((l) => `  ${l}`).join('\n')}\n</svg>\n`
  writeFileSync(join(ICON_DIR, `${name}.svg`), svg)
  stale.delete(`${name}.svg`)
  written++
}
for (const f of stale) {
  throw new Error(`stale icon not overwritten (id renamed in HTML?): ${f}`)
}

// ── 4. 生成题库图标映射数据 (CategorizationIconBankData.ets) ──
const themesStart = html.indexOf('var THEMES=[')
const themesEnd = html.indexOf('];', themesStart)
if (themesStart < 0 || themesEnd < 0) throw new Error('cannot find THEMES section')
const themes = html.slice(themesStart, themesEnd)
const themeCount = (themes.match(/\{id:'/g) || []).length

const itemPairs = [] // [label, iconId]
const seenItem = new Set()
for (const m of themes.matchAll(/\['([^']+)',\s*'(i-[^']+)'/g)) {
  const label = m[1]
  const id = m[2]
  if (seenItem.has(label)) continue
  seenItem.add(label)
  if (icons[id] === undefined) continue // 图标被排除 (letter-* 等) → 运行时走 emoji/文字兜底
  itemPairs.push([label, id])
}
const binPairs = []
const seenBin = new Set()
for (const m of themes.matchAll(/\{name:'([^']+)',icon:'(i-[^']+)'/g)) {
  const name = m[1]
  const id = m[2]
  if (seenBin.has(name)) continue
  seenBin.add(name)
  if (icons[id] === undefined) continue
  binPairs.push([name, id])
}
if (itemPairs.length === 0 || binPairs.length === 0) throw new Error('THEMES extraction got nothing')

function packed(pairs) {
  return pairs.map(([label, id]) => `${label}|${id.replace(/^i-/, '')}`).join('\\n')
}

const bankData = `/**
 * CategorizationIconBankData - 分类小管家图标库数据 (AUTO-GENERATED)
 *
 * 由 scripts/export-categorization-icons.mjs 从 docs/categorization-game.html 生成，
 * 数据源是原型里的 ${themeCount} 主题题库。每行一条「名称|图标 id」，
 * 图标 id 对应 rawfile/kids/icons/<id>.svg。
 * 不要手改此文件——改原型 HTML 后在仓库根目录重跑导出脚本。
 */

export const CATEGORIZATION_ITEM_ICON_DATA: string = '${packed(itemPairs)}'

export const CATEGORIZATION_BIN_GLYPH_DATA: string = '${packed(binPairs)}'
`
writeFileSync(BANK_DATA_PATH, bankData)

console.log(`icons written: ${written}`)
console.log(`item pairs: ${itemPairs.length}, bin pairs: ${binPairs.length}`)
