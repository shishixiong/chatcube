// entry/src/main/ets/components/map/MapQuizCard.ets
/**
 * MapQuizCard - 中国地图出题（map_quiz）薄路由器
 *
 * 镜像 ChineseQuizCard：按 toolCall.arguments 的 mode 分发 body，
 * 全部 @Param/@Event 透传。mode 无法解析时静默兜底到 choice body。
 */

import { ToolCall } from '../../models/ChatModels'
import { parseMapQuizArgs } from './MapQuizTypes'
import { MapChoiceBody } from './bodies/MapChoiceBody'
import { MapLocateBody } from './bodies/MapLocateBody'
import { MapWriteBody } from './bodies/MapWriteBody'

@ComponentV2
export struct MapQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  build() {
    if (this.isLocateMode()) {
      MapLocateBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isWriteMode()) {
      MapWriteBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else {
      // choice 与不可解析 mode 兜底
      MapChoiceBody({
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

  private isLocateMode(): boolean {
    return parseMapQuizArgs(this.toolCall.arguments).mode === 'locate'
  }

  private isWriteMode(): boolean {
    return parseMapQuizArgs(this.toolCall.arguments).mode === 'write'
  }
}
