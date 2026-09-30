// entry/src/main/ets/components/chinese/ChineseQuizCard.ets
/**
 * ChineseQuizCard - chinese_quiz 薄路由器
 *
 * 按 toolCall.arguments 的 mode 分发 body (参照 english/EnglishQuizCard):
 * - word_build / lookalike / antonym → ChineseChoiceBody
 * - sentence_order → SentenceOrderBody
 * MessageBubble 挂载签名与 english_quiz v2 完全一致:
 * toolCall / isAnswered / answeredPayload / largeSize / onAnswer。
 */

import { ToolCall } from '../../models/ChatModels'
import { parseChineseQuizModeArgs } from './ModeTypes'
import { ChineseChoiceBody } from './bodies/ChineseChoiceBody'
import { SentenceOrderBody } from './bodies/SentenceOrderBody'

@ComponentV2
export struct ChineseQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  build() {
    if (this.isChoiceMode()) {
      ChineseChoiceBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isSentenceOrderMode()) {
      SentenceOrderBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else {
      // mode 无法解析 (理论上是 should_retry 拦不住的极端情况): 静默兜底到 choice body
      ChineseChoiceBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    }
  }

  private resolveMode(): string {
    return parseChineseQuizModeArgs(this.toolCall.arguments).mode
  }

  private isChoiceMode(): boolean {
    const m = this.resolveMode()
    return m === 'word_build' || m === 'lookalike' || m === 'antonym'
  }

  private isSentenceOrderMode(): boolean {
    return this.resolveMode() === 'sentence_order'
  }
}
