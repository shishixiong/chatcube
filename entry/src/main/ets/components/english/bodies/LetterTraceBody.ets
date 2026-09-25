// entry/src/main/ets/components/english/bodies/LetterTraceBody.ets
/**
 * LetterTraceBody - english_quiz v2 字母描红 body
 * 把 letter_trace 参数映射为 handwriting_practice(type:'letter') 契约后内嵌 HandwritingCard;
 * 回包 completed → correct 适配为 english_quiz payload v2 (描红完成 = 1 星, 与 handwriting 同语义)。
 */

import { ToolCall } from '../../../models/ChatModels'
import { HandwritingCard } from '../../HandwritingCard'
import { EnglishQuizAnswerPayload } from '../ModeTypes'

interface HandwritingResultPayload {
  character: string
  type: string
  completed: boolean
  stroke_count: number
  handwriting_base64?: string
}

@ComponentV2
export struct LetterTraceBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  private letter: string = ''
  private letterCase: string = ''
  private correctAnswer: string = ''
  private skillKey: string = 'english_writing'
  private stage: string = ''
  // 合成 ToolCall 只构造一次, 避免每次 build 重建对象
  private innerToolCall: ToolCall = new ToolCall()

  aboutToAppear(): void {
    let parsed: Record<string, Object> = {}
    try {
      parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
    } catch (_e) {}
    this.letter = ((parsed['letter'] as string) ?? 'A').trim()
    this.letterCase = ((parsed['case'] as string) ?? 'upper').trim()
    this.correctAnswer = ((parsed['correct_answer'] as string) ?? this.letter).trim()
    this.skillKey = ((parsed['skill_key'] as string) ?? '').trim() !== ''
      ? ((parsed['skill_key'] as string) ?? '').trim() : 'english_writing'
    this.stage = ((parsed['stage'] as string) ?? '').trim()
    // letter_trace → handwriting_practice 契约映射: character 传原样大小写字母
    const mappedArgs = JSON.stringify({
      type: 'letter',
      character: this.letter,
      difficulty: (parsed['difficulty'] as number) ?? 1
    } as Record<string, Object>)
    this.innerToolCall = new ToolCall(
      this.toolCall.id, 'handwriting_practice', mappedArgs,
      'handwriting_practice', '字母描红'
    )
  }

  // HandwritingCard 回包 → english_quiz payload v2 适配
  private handleInnerAnswer(_toolCallId: string, answerJson: string): void {
    let completed = true
    let childAnswer = this.letter
    try {
      const hw = JSON.parse(answerJson) as HandwritingResultPayload
      completed = hw.completed
      childAnswer = hw.character
    } catch (_e) {}
    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: childAnswer,
      correct: completed,
      correct_answer: this.correctAnswer,
      word: '',
      sentence: '',
      question_type: 'letter_trace',
      skill_key: this.skillKey,
      mode: 'letter_trace',
      stage: this.stage,
      completed: completed
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  build() {
    HandwritingCard({
      toolCall: this.innerToolCall,
      isAnswered: this.isAnswered,
      answeredPayload: this.isAnswered ? this.answeredPayload : '',
      largeSize: this.largeSize,
      onAnswer: (toolCallId: string, answerJson: string): void => {
        this.handleInnerAnswer(toolCallId, answerJson)
      }
    })
  }
}
