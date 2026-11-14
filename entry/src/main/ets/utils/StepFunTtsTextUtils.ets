import { splitTextForTts } from './TtsTextChunkUtils'

// StepFun /v1/audio/speech 的 input 上限 1000 字符。
// 实现已提升为通用 splitTextForTts，这里保留旧入口供现有调用方/测试使用。
export function splitTextForStepFun(text: string, maxChars: number): string[] {
  return splitTextForTts(text, maxChars)
}
