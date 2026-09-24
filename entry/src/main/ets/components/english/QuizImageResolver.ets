// entry/src/main/ets/components/english/QuizImageResolver.ets
/**
 * QuizImageResolver - english_quiz 图片三层解析纯异步函数
 * (自原 EnglishQuizCard.resolveImage 抽出; 卡片侧只负责 loading 态/120s 超时/file:// 转换)
 *
 * Tier 1: ENGLISH_QUIZ 本地缓存 (含历史现生图 + 写回的备课图)
 * Tier 2: LESSON_PLAN 备课预生成图 (仅单词题有干净映射, 命中后写回 Tier1 + markConsumed)
 * Tier 3: generateAndStore 现生图兜底
 *
 * 任何一步失败都静默降级到下一层, 全失败返回 ''。
 */

import { getImageIndexService, ImageIndexService } from '../../services/ImageIndexService'
import { ImageSource } from '../../models/ImageIndexModels'

export async function resolveQuizImagePath(word: string, sentence: string, imagePrompt: string): Promise<string> {
  if (word === '' && sentence === '' && imagePrompt === '') {
    return ''
  }
  const imageIndex = getImageIndexService()
  const quizKey = ImageIndexService.buildEnglishQuizKey(word, sentence)
  try {
    // Tier 1: 英语题本地缓存
    const hit = await imageIndex.findByKey(ImageSource.ENGLISH_QUIZ, quizKey)
    if (hit !== null && hit.filePath !== '') {
      return hit.filePath
    }
    // Tier 2: 备课预生成图 (仅单词题)
    const isWordQuiz = sentence === '' && word !== ''
    if (isWordQuiz && imagePrompt !== '') {
      const topicKey = `vocab.${word.toLowerCase().trim()}`
      try {
        const planHit = await imageIndex.findByKey(ImageSource.LESSON_PLAN, topicKey)
        if (planHit !== null && planHit.filePath !== '') {
          // 写回 Tier1 + 标记消费 (best-effort; 失败不影响返回路径)
          try {
            await imageIndex.putEntry(ImageSource.ENGLISH_QUIZ, quizKey, planHit.filePath,
              planHit.prompt !== '' ? planHit.prompt : imagePrompt,
              planHit.mimeType,
              { revisedPrompt: planHit.revisedPrompt })
            imageIndex.markConsumed(planHit.id).catch((_e: Error) => {})
          } catch (_e) {}
          return planHit.filePath
        }
      } catch (_e) {}
    }
    // Tier 3: 现生图
    if (imagePrompt !== '') {
      const gen = await imageIndex.generateAndStore(ImageSource.ENGLISH_QUIZ, quizKey, imagePrompt)
      if (gen !== null) {
        return gen.filePath
      }
    }
    return ''
  } catch (_e) {
    return ''
  }
}
