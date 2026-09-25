// entry/src/main/ets/components/english/EnglishQuizCard.ets
/**
 * EnglishQuizCard - english_quiz v2 薄路由器
 *
 * 按 toolCall.arguments 的 mode 选择 body; 解析失败/legacy 一律回落 LegacyBody
 * (历史会话渲染零风险)。MessageBubble 挂载签名与旧版完全一致:
 * toolCall / isAnswered / answeredPayload / largeSize / onAnswer。
 * 设计见 docs/superpowers/specs/2026-09-24-english-quiz-v2-design.md §6。
 */

import { ToolCall } from '../../models/ChatModels'
import { parseEnglishQuizModeArgs } from './ModeTypes'
import { LegacyBody } from './bodies/LegacyBody'
import { ChoiceModeBody } from './bodies/ChoiceModeBody'
import { SentenceFillBody } from './bodies/SentenceFillBody'
import { ReadAloudBody } from './bodies/ReadAloudBody'
import { LetterTraceBody } from './bodies/LetterTraceBody'

@ComponentV2
export struct EnglishQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  build() {
    if (this.isChoiceMode()) {
      ChoiceModeBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isSentenceFillMode()) {
      SentenceFillBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isReadAloudMode()) {
      ReadAloudBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isLetterTraceMode()) {
      LetterTraceBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else {
      LegacyBody({
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

  // ===== build 内不能调用带复杂逻辑的方法签名限制, 用小型判谓方法 (每次 build 解析一次 args, 开销可忽略) =====

  private resolveMode(): string {
    return parseEnglishQuizModeArgs(this.toolCall.arguments).mode
  }

  private isChoiceMode(): boolean {
    const m = this.resolveMode()
    return m === 'listen_choice' || m === 'picture_word' || m === 'phonics_blend'
  }

  private isSentenceFillMode(): boolean {
    return this.resolveMode() === 'sentence_fill'
  }

  private isReadAloudMode(): boolean {
    return this.resolveMode() === 'read_aloud'
  }

  private isLetterTraceMode(): boolean {
    return this.resolveMode() === 'letter_trace'
  }
}
