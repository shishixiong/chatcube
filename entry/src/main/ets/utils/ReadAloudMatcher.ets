/**
 * ReadAloudMatcher - english_quiz read_aloud 跟读评分纯逻辑层
 *
 * 归一化: 小写 → 非字母数字(保留撇号)替换为空格 → 折叠空格 → trim。
 * 命中: 归一化后全等, 或转写包含目标句(ASR 常在前后粘词, 如 "Well, I like apples")。
 * 设计见 docs/superpowers/specs/2026-09-24-english-quiz-v2-design.md §6.4。
 */

export function normalizeEnglishText(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9\s']/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

export function isReadAloudMatch(transcript: string, target: string): boolean {
  const said = normalizeEnglishText(transcript)
  const want = normalizeEnglishText(target)
  if (said === '' || want === '') {
    return false
  }
  return said === want || said.includes(want)
}
