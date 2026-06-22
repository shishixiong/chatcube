// gen_stroke_data.js — Batch-generate StrokeOrderData.ets entries
// Usage: node gen_stroke_data.js 汉字1汉字2... > /tmp/output.txt
// Or edit CHARS list below and run: node gen_stroke_data.js
//
// Fetches SVG path outlines from hanzi-writer-data (Y-up, 1024×1024 grid).
// For letters A-Z, generates thick-rectangle SVG paths from line segments.
// Stroke type labels: 横/竖/撇/捺/点/折 (mapped from chinese-character-strokes numeric codes).

const https = require('https')
const fs = require('fs')

// Edit this list to batch-add characters, or pass chars as CLI args
const CHARS = process.argv.slice(2).length > 0
  ? process.argv.slice(2).join('').split('')
  : '林朋友国学校明天回家中好'.split('')

// Stroke type code → label mapping (chinese-character-strokes convention)
const TYPE_LABELS = {
  1: '横',
  2: '竖',
  3: '撇',
  4: '捺/点',
  5: '折',
}

// Letter stroke data (0-1 grid, Y-down) — used only for A-Z
const LETTERS = {
  'A': [[0.3,0.85,0.5,0.1,'/'],[0.5,0.1,0.7,0.85,'\\'],[0.35,0.5,0.65,0.5,'—']],
  'B': [[0.15,0.1,0.15,0.9,'|'],[0.15,0.1,0.7,0.1,'—'],[0.7,0.1,0.7,0.45,'|'],[0.7,0.45,0.15,0.45,'—'],[0.15,0.45,0.75,0.45,'—'],[0.75,0.45,0.75,0.9,'|'],[0.75,0.9,0.15,0.9,'—']],
  'C': [[0.8,0.2,0.2,0.2,'⌒'],[0.2,0.2,0.2,0.8,'|'],[0.2,0.8,0.8,0.8,'⌒']],
  'D': [[0.15,0.1,0.15,0.9,'|'],[0.15,0.1,0.65,0.1,'—'],[0.65,0.1,0.85,0.5,'\\'],[0.85,0.5,0.65,0.9,'/'],[0.65,0.9,0.15,0.9,'—']],
  'E': [[0.2,0.1,0.8,0.1,'—'],[0.2,0.1,0.2,0.9,'|'],[0.2,0.5,0.6,0.5,'—'],[0.2,0.9,0.8,0.9,'—']],
  'F': [[0.2,0.1,0.8,0.1,'—'],[0.2,0.1,0.2,0.9,'|'],[0.2,0.5,0.6,0.5,'—']],
  'G': [[0.8,0.15,0.25,0.15,'⌒'],[0.2,0.15,0.2,0.85,'|'],[0.2,0.85,0.7,0.85,'⌒'],[0.7,0.85,0.7,0.5,'|'],[0.7,0.5,0.5,0.5,'—']],
  'H': [[0.2,0.1,0.2,0.9,'|'],[0.2,0.5,0.8,0.5,'—'],[0.8,0.1,0.8,0.9,'|']],
  'I': [[0.3,0.1,0.7,0.1,'—'],[0.5,0.1,0.5,0.9,'|'],[0.3,0.9,0.7,0.9,'—']],
  'J': [[0.3,0.1,0.8,0.1,'—'],[0.65,0.1,0.65,0.75,'|'],[0.65,0.75,0.3,0.85,'⌒']],
  'K': [[0.2,0.1,0.2,0.9,'|'],[0.2,0.5,0.75,0.1,'/'],[0.35,0.5,0.8,0.9,'\\']],
  'L': [[0.2,0.1,0.2,0.9,'|'],[0.2,0.9,0.8,0.9,'—']],
  'M': [[0.15,0.1,0.15,0.9,'|'],[0.15,0.1,0.5,0.55,'\\'],[0.5,0.55,0.85,0.1,'/'],[0.85,0.1,0.85,0.9,'|']],
  'N': [[0.15,0.1,0.15,0.9,'|'],[0.15,0.1,0.85,0.9,'\\'],[0.85,0.1,0.85,0.9,'|']],
  'O': [[0.5,0.1,0.2,0.1,'⌒'],[0.2,0.1,0.2,0.9,'|'],[0.2,0.9,0.8,0.9,'⌒'],[0.8,0.9,0.8,0.1,'|']],
  'P': [[0.2,0.1,0.2,0.9,'|'],[0.2,0.1,0.75,0.1,'—'],[0.75,0.1,0.75,0.45,'|'],[0.75,0.45,0.2,0.45,'—']],
  'Q': [[0.5,0.12,0.2,0.12,'⌒'],[0.2,0.12,0.2,0.78,'|'],[0.2,0.78,0.8,0.78,'⌒'],[0.8,0.78,0.8,0.12,'|'],[0.6,0.65,0.88,0.92,'\\']],
  'R': [[0.2,0.1,0.2,0.9,'|'],[0.2,0.1,0.75,0.1,'—'],[0.75,0.1,0.75,0.45,'|'],[0.75,0.45,0.2,0.45,'—'],[0.35,0.45,0.8,0.9,'\\']],
  'S': [[0.75,0.15,0.25,0.15,'—'],[0.2,0.15,0.2,0.45,'|'],[0.2,0.45,0.8,0.45,'—'],[0.8,0.45,0.8,0.85,'|'],[0.8,0.85,0.2,0.85,'—']],
  'T': [[0.3,0.1,0.7,0.1,'—'],[0.5,0.1,0.5,0.9,'|']],
  'U': [[0.2,0.1,0.2,0.8,'|'],[0.2,0.8,0.8,0.8,'⌒'],[0.8,0.8,0.8,0.1,'|']],
  'V': [[0.2,0.1,0.5,0.9,'\\'],[0.5,0.9,0.8,0.1,'/']],
  'W': [[0.1,0.1,0.3,0.9,'\\'],[0.3,0.9,0.5,0.5,'/'],[0.5,0.5,0.7,0.9,'\\'],[0.7,0.9,0.9,0.1,'/']],
  'X': [[0.2,0.1,0.8,0.9,'\\'],[0.8,0.1,0.2,0.9,'/']],
  'Y': [[0.2,0.1,0.5,0.5,'\\'],[0.5,0.5,0.8,0.1,'/'],[0.5,0.5,0.5,0.9,'|']],
  'Z': [[0.2,0.1,0.8,0.1,'—'],[0.8,0.1,0.2,0.9,'/'],[0.2,0.9,0.8,0.9,'—']],
}

// Convert letter line segment to thick filled rectangle SVG path (Y-flipped to Y-up)
function strokeToPath(x1, y1, x2, y2, thickness = 70) {
  const sx1 = x1 * 1024, sy1 = (1 - y1) * 1024
  const sx2 = x2 * 1024, sy2 = (1 - y2) * 1024
  const dx = sx2 - sx1, dy = sy2 - sy1
  const len = Math.sqrt(dx * dx + dy * dy)
  if (len < 1) {
    return `M ${sx1+25} ${sy1} A 25 25 0 1 0 ${sx1-25} ${sy1} A 25 25 0 1 0 ${sx1+25} ${sy1} Z`
  }
  const nx = -dy / len, ny = dx / len
  const ox = nx * thickness / 2, oy = ny * thickness / 2
  return `M ${(sx1+ox).toFixed(0)} ${(sy1+oy).toFixed(0)} L ${(sx2+ox).toFixed(0)} ${(sy2+oy).toFixed(0)} L ${(sx2-ox).toFixed(0)} ${(sy2-oy).toFixed(0)} L ${(sx1-ox).toFixed(0)} ${(sy1-oy).toFixed(0)} Z`
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        return fetchJson(res.headers.location).then(resolve, reject)
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`))
      }
      let body = ''
      res.setEncoding('utf8')
      res.on('data', (chunk) => { body += chunk })
      res.on('end', () => {
        try { resolve(JSON.parse(body)) } catch (e) { reject(e) }
      })
    }).on('error', reject)
  })
}

// Escape backslash in label string for TS single-quoted literal
function escapeLabel(label) {
  return label.replace(/\\/g, '\\\\')
}

async function fetchChineseChar(char) {
  const url = `https://cdn.jsdelivr.net/npm/hanzi-writer-data@2.0.0/${encodeURIComponent(char)}.json`
  try {
    const data = await fetchJson(url)
    if (!data.strokes || !Array.isArray(data.strokes)) {
      throw new Error(`No strokes array for ${char}`)
    }
    // Fetch stroke types from chinese-character-strokes
    // NOTE: package may be unavailable on CDN — emit ?? placeholder requiring manual fill-in
    let typeLabels = data.strokes.map(() => '??')
    try {
      const ccsUrl = `https://cdn.jsdelivr.net/npm/chinese-character-strokes@1.0.0/${encodeURIComponent(char)}.json`
      const ccsData = await fetchJson(ccsUrl)
      if (Array.isArray(ccsData.strokes)) {
        typeLabels = ccsData.strokes.map((code) => TYPE_LABELS[code] || '??')
      }
    } catch (_e) {
      console.error(`WARN: ${char} - chinese-character-strokes lookup failed. Writing '??' placeholders — you MUST replace them with proper labels (横/竖/撇/捺/点/折) before inserting into StrokeOrderData.ets`)
    }
    const strokes = data.strokes.map((path, i) => ({
      path: path,
      label: typeLabels[i] || '折',
    }))
    return strokes
  } catch (e) {
    console.error(`ERROR: ${char} - ${e.message}`)
    return null
  }
}

function generateLetter(char) {
  const letterData = LETTERS[char]
  if (!letterData) return null
  return letterData.map(([x1, y1, x2, y2, label]) => ({
    path: strokeToPath(x1, y1, x2, y2),
    label: label,
  }))
}

async function main() {
  const lines = []
  for (const char of CHARS) {
    let strokes = null
    if (/[A-Z]/.test(char)) {
      strokes = generateLetter(char)
      if (!strokes) {
        console.error(`ERROR: ${char} - no letter data`)
        continue
      }
    } else {
      strokes = await fetchChineseChar(char)
      if (!strokes) continue
    }
    lines.push(`  ['${char}', [`)
    for (const s of strokes) {
      lines.push(`    { path: '${s.path}', label: '${escapeLabel(s.label)}' },`)
    }
    lines.push(`  ]],`)
  }
  console.log(lines.join('\n'))
}

main().catch((e) => {
  console.error('Fatal:', e)
  process.exit(1)
})
