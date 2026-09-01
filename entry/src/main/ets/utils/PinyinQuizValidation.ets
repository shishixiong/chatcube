/**
 * PinyinQuizValidation - pinyin_quiz 出题参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handlePinyinQuiz 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/ListeningQuizValidation.ets (预校验 + should_retry 范式)。
 *
 * 校验规则 (对照 config/BuiltinTools.ets 的 pinyin_quiz schema):
 *  - character 是单个汉字且在 PinyinData 字典内 (字典外字符无标准答案键)
 *  - options 恰好 4 个非空互异的带调拼音
 *  - correct_answer 非空且等于字典读音 (AI 的答案与字典不一致 → 拒绝重出,
 *    不做静默修复——让 AI 学会正确读音)
 *  - correct_answer 在 options 里
 */

import { getPinyin } from '../config/PinyinData'

export interface PinyinQuizValidationResult {
  ok: boolean
  error: string
}

function fail(msg: string): PinyinQuizValidationResult {
  return { ok: false, error: msg }
}

function pass(): PinyinQuizValidationResult {
  return { ok: true, error: '' }
}

/**
 * 解析并校验 AI 传来的 pinyin_quiz 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validatePinyinQuizArgs(args: string): PinyinQuizValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('pinyin_quiz 参数不是合法 JSON, 请检查后重新出题')
  }

  const character = ((parsed['character'] as string) ?? '').trim()
  if (character === '') {
    return fail('pinyin_quiz 题缺少 character (要考的汉字)')
  }
  if (character.length !== 1) {
    return fail(`pinyin_quiz 的 character 必须是单个汉字, 收到「${character}」, 请只传一个字`)
  }
  const dictPinyin = getPinyin(character)
  if (dictPinyin === null) {
    return fail(`pinyin_quiz 的 character「${character}」不在支持的汉字字表内, 请从字表里重新选字出题`)
  }

  const correct = ((parsed['correct_answer'] as string) ?? '').trim()
  if (correct === '') {
    return fail(`pinyin_quiz 题缺少 correct_answer,「${character}」的正确拼音是「${dictPinyin}」`)
  }
  if (correct !== dictPinyin) {
    return fail(`pinyin_quiz 题的 correct_answer「${correct}」与字典读音不符,「${character}」的正确拼音是「${dictPinyin}」, 请修正后重新出题`)
  }

  const optionsRaw = parsed['options']
  if (!Array.isArray(optionsRaw)) {
    return fail('pinyin_quiz 题必须提供 options 选项数组 (恰好 4 个带调拼音, 含正确答案)')
  }
  const arr = optionsRaw as Object[]
  if (arr.length !== 4) {
    return fail(`pinyin_quiz 题的选项数量是 ${arr.length}, 必须恰好 4 个 (含正确答案), 请修正后重新出题`)
  }
  const options: string[] = []
  for (let i = 0; i < arr.length; i++) {
    const v = arr[i]
    if (typeof v !== 'string') {
      return fail(`pinyin_quiz 题的第 ${i + 1} 个选项不是字符串`)
    }
    const s = (v as string).trim()
    if (s === '') {
      return fail(`pinyin_quiz 题的第 ${i + 1} 个选项为空`)
    }
    if (options.indexOf(s) >= 0) {
      return fail(`pinyin_quiz 题的选项「${s}」重复, 4 个选项必须互不相同`)
    }
    options.push(s)
  }

  if (options.indexOf(correct) < 0) {
    return fail(`pinyin_quiz 题的正确答案「${correct}」不在选项里, 请把正确答案放进 options 后重新出题`)
  }
  return pass()
}
