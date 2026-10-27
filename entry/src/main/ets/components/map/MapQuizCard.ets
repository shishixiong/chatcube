// entry/src/main/ets/components/map/MapQuizCard.ets
/**
 * MapQuizCard - 中国地图出题（map_quiz）薄路由器
 *
 * 镜像 ChineseQuizCard：按 toolCall.arguments 的 mode 分发 body，
 * 全部 @Param/@Event 透传。mode 无法解析时静默兜底到 choice body。
 *
 * 五 mode: choice（看地图选名）/ locate（按线索定位）/ write（写名字）/
 *          shape（只看轮廓猜省）/ compare（面积 or 方位比较）
 */

import { ToolCall } from '../../models/ChatModels'
import { parseMapQuizArgs } from './MapQuizTypes'
import { MapChoiceBody } from './bodies/MapChoiceBody'
import { MapShapeBody } from './bodies/MapShapeBody'
import { MapCompareBody } from './bodies/MapCompareBody'
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
    if (this.isShapeMode()) {
      MapShapeBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isCompareMode()) {
      MapCompareBody({
        toolCall: this.toolCall,
        isAnswered: this.isAnswered,
        answeredPayload: this.answeredPayload,
        largeSize: this.largeSize,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAnswer(toolCallId, answerJson)
        }
      })
    } else if (this.isLocateMode()) {
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

  private isShapeMode(): boolean {
    return parseMapQuizArgs(this.toolCall.arguments).mode === 'shape'
  }

  private isCompareMode(): boolean {
    return parseMapQuizArgs(this.toolCall.arguments).mode === 'compare'
  }

  private isLocateMode(): boolean {
    return parseMapQuizArgs(this.toolCall.arguments).mode === 'locate'
  }

  private isWriteMode(): boolean {
    return parseMapQuizArgs(this.toolCall.arguments).mode === 'write'
  }
}
