// utils/TtsTextUtils.ets
// TTS 朗读文本的纯函数规范化。TTS 引擎（系统 / MiniMax）不认识数学符号,
// 会跳过或乱读 —— 这里把算式符号转成中文读法。
// 目前唯一调用方: VerticalMathCard 步进旁白朗读（屏显 StepNarrator
// 继续用符号形式, 只有送进 TTS 的文本走这个转换）。

/**
 * 数学符号 → 中文读法, 供 TTS 朗读。
 *
 * 只在"数字邻接"时转换（正则 `(\d)\s*SYM\s*(\d)`）:
 * - 保护 `T-shirt` / `well-known`（字母邻接的连字符不转）
 * - 保护 `a × b` 这类非算式用法
 *
 * 不映射 `*` 和 `/`: slash 有日期（2026/09/04）与 URL 误伤风险;
 * quiz 规范化文本用 × ÷（见 MathQuizGame.getOpDisplay）。
 *
 * 典型输入（竖式旁白, − 为 U+2212, ＝ 为全角）:
 *   '5 − 1 − 1 ＝ 3' → '5 减 1 减 1 等于 3'
 *   '14 − 7 ＝ 7'    → '14 减 7 等于 7'
 */
export function normalizeMathSymbolsForTts(text: string): string {
  if (text === '') {
    return ''
  }
  let result = text
  result = result.replace(/(\d)\s*[+＋]\s*(\d)/g, '$1 加 $2')
  result = result.replace(/(\d)\s*[-−－]\s*(\d)/g, '$1 减 $2')
  result = result.replace(/(\d)\s*×\s*(\d)/g, '$1 乘 $2')
  result = result.replace(/(\d)\s*÷\s*(\d)/g, '$1 除以 $2')
  result = result.replace(/(\d)\s*[=＝]\s*(\d)/g, '$1 等于 $2')
  return result
}
