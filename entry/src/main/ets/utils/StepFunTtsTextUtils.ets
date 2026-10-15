// StepFun TTS 文本切片纯函数
// StepFun /v1/audio/speech 的 input 上限 1000 字符, 超长文本需按句切分后逐段"合成→播放"

// 句末标点 (切句边界, 标点归属前句); \n 也作为边界
function isSentenceEnder(ch: string): boolean {
  return ch === '。' || ch === '！' || ch === '？' || ch === '!'
    || ch === '?' || ch === '；' || ch === ';' || ch === '\n'
}

// 按句切分; 单句超长时在 maxChars 处硬切, 不切断 UTF-16 代理对 (emoji 等)
function splitIntoSentences(text: string, maxChars: number): string[] {
  const sentences: string[] = []
  let start = 0
  for (let i = 0; i < text.length; i++) {
    if (isSentenceEnder(text.charAt(i))) {
      sentences.push(text.substring(start, i + 1))
      start = i + 1
    }
  }
  if (start < text.length) {
    sentences.push(text.substring(start))
  }

  const result: string[] = []
  for (let i = 0; i < sentences.length; i++) {
    const s = sentences[i]
    if (s.length <= maxChars) {
      result.push(s)
      continue
    }
    let pos = 0
    while (pos < s.length) {
      let end = Math.min(pos + maxChars, s.length)
      // 末位是高代理则回退 1, 避免把代理对切成两半
      if (end > pos && end < s.length) {
        const lastCode = s.charCodeAt(end - 1)
        if (lastCode >= 0xD800 && lastCode <= 0xDBFF) {
          end--
        }
      }
      if (end === pos) {
        end = pos + 1
      }
      result.push(s.substring(pos, end))
      pos = end
    }
  }
  return result
}

// 把文本切分为每段 ≤ maxChars 的数组:
// 1. 短文本原样返回单元素数组; 空文本返回 []
// 2. 先按句末标点切句, 再贪心打包相邻句子进同一段
// 3. 无标点的超长文本退化为 maxChars 硬切
export function splitTextForStepFun(text: string, maxChars: number): string[] {
  const trimmed = text.trim()
  if (trimmed === '') {
    return []
  }
  if (maxChars <= 0) {
    return [trimmed]
  }
  if (trimmed.length <= maxChars) {
    return [trimmed]
  }

  const sentences = splitIntoSentences(trimmed, maxChars)
  const chunks: string[] = []
  let current = ''
  for (let i = 0; i < sentences.length; i++) {
    const s = sentences[i]
    if (current === '') {
      current = s
    } else if (current.length + s.length <= maxChars) {
      current = current + s
    } else {
      chunks.push(current.trim())
      current = s
    }
  }
  if (current.trim() !== '') {
    chunks.push(current.trim())
  }
  return chunks
}
