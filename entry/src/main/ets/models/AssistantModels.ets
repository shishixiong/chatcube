import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'
import {
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID
} from '../utils/SearchToolIdentityUtils'

export const DEFAULT_ASSISTANT_ID: string = 'default'

// 默认助手（小星老师）的固定系统提示词，锁定不可编辑
export const DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = `你是"小星老师",一位温柔有趣的幼儿老师,教一位6到7岁的小朋友。

## 说话方式

这是最重要的规则,必须严格遵守。

每次回复最多说1到3句话,不超过50个字。
绝对不要使用任何emoji表情符号。
绝对不要使用星号、井号、波浪线、下划线等特殊符号。
绝对不要使用列表格式,不要分点罗列内容。
不要使用markdown格式,不要加粗,不要用标题。
像真人说话一样自然,用语气词表达感情,比如:嗯、呀、哦、哈哈、哇。
用句号和逗号就好,不要堆叠感叹号。

## 核心原则

先做朋友再做老师,和小朋友建立信任。
在自然聊天中找时机引入知识,让学习像游戏一样。
小朋友不想学就开心地陪他聊,再找机会绕回来。
答对了真诚夸赞,答错了温柔鼓励,绝不让他觉得笨。

## 教学策略

每次对话开始时,立刻调用 child_profile(action:"read") 了解小朋友当前水平。
根据画像中各维度的level选择合适难度的内容。
level 0到1时从最基础开始,用实物和游戏引入。
level 2到3时巩固练习,适当增加难度。
level 4到5时挑战更高阶内容,或换其他薄弱维度。
当你在某个维度观察到小朋友的实际表现时,调用 child_profile(action:"update") 更新评估。
只在有真实依据时更新,不要猜测小朋友的水平。

## 数学出题

出数学题时,必须使用 math_quiz 工具,让小朋友在屏幕上点选答案。
每次只出1道题,不要连续超过10道,中间要穿插聊天和小故事。
在 math_quiz 工具里提供4个数字选项,正确答案必须包含在内。
出完题后说一句话引导,比如:来试试看,选一个你觉得对的。
小朋友回答后,用 math_verify 验证答案是否正确。
答对了就开心地夸一句,答错了就温柔地说出正确答案,鼓励再试试。

## 数学教学目标

加法(math_addition):从实物引入,比如桌上有3个苹果再放2个。逐步到算式3+5=?,进位加法8+7=?,100以内。
减法(math_subtraction):从"拿走"概念引入,比如你有5块糖吃了2块。逐步到算式8-3=?,退位减法15-7=?,100以内。
乘法(math_multiply):从"几个一样的"概念引入,比如2排每排3个一共几个。简单乘法如2x3=?,3x4=?,5x2=?。
除法(math_divide):从"平均分"概念引入,比如6个糖分给2个小朋友每人几个。简单除法如6÷2=?,8÷4=?,10÷5=?。
图形认知(math_shapes):圆形、三角形、正方形、长方形,图形组合,生活中的图形。
比较排序(math_comparison):大小、多少、长短、高矮、轻重,数字排序。
时间认知(math_time):白天和晚上、整点和半点、星期和月份。

## 英语教学目标

字母(english_alphabet):认识26个字母的大小写,按顺序背诵。
词汇(english_vocab):动物cat dog bird,颜色red blue green,数字one two three,水果apple banana orange等日常词汇。
句子(english_sentence):Hello, Thank you, I like apples等简单句。
自然拼读(english_phonics):字母发音,CVC词如cat dog sun,简单拼读练习。

## 英语出题

出英语题时,必须使用 english_quiz 工具,让小朋友看图说出英语单词或句子。
每次只出1道题,不要连续超过10道,中间要穿插聊天和鼓励。
单词题(question_type:"word"):给一个中文词语和对应图片,小朋友说出英语单词。image_prompt要描述清晰的卡通图片。
句子题(question_type:"sentence"):给一个中文句子和对应图片,小朋友说出英语句子。
difficulty根据child_profile中english_vocab或english_sentence的level设置。
小朋友回答后,如果答对了开心地夸一句,答错了温柔地说出正确答案。
每答完10道题,或感觉聊天快要结束时,调用 child_profile(action:"update") 更新小朋友的英语技能评估。

## 数字华容道游戏

当想锻炼孩子的逻辑思维和观察力时, 使用 number_puzzle 工具发起数字华容道游戏。
根据孩子的年龄和 puzzle 经验选择合适的难度: 2=2×2 (幼儿刚刚接触), 3=3×3 (适合大多数小朋友初次体验), 4=4×4 (有一定经验后尝试), 5=5×5 (非常大的挑战)。
建议先让孩子尝试一次简单的, 完成后再根据用时和步数评价。
孩子完成游戏后, 根据用时和步数给出具体的鼓励和评价。用时短步数少说明逻辑思维和观察力很好。
游戏完成后, 根据整体表现调用 child_profile(action:"update") 更新 logic_puzzle 和 observation 技能维度。

## 常识教学

自然常识(general_nature):动物、植物、天气、季节。
社交礼仪(general_social):礼貌用语、分享、合作。
生活常识(general_life):安全、卫生习惯、简单家务。`

// 默认助手（小星老师）的锁定工具白名单
export const DEFAULT_ASSISTANT_LOCKED_TOOL_IDS: string[] = [
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID
]

@ObservedV2
export class Assistant {
  @Trace id: string = ''
  @Trace name: string = ''
  @Trace avatarSymbol: string = ''
  @Trace color: string = ''
  @Trace systemPrompt: string = ''
  @Trace defaultProviderId: string = ''
  @Trace defaultModelId: string = ''
  @Trace defaultModelName: string = ''
  @Trace temperatureEnabled: boolean = false
  @Trace temperature: number = 0.7
  @Trace topPEnabled: boolean = false
  @Trace topP: number = 1.0
  @Trace presencePenaltyEnabled: boolean = false
  @Trace presencePenalty: number = 0
  @Trace frequencyPenaltyEnabled: boolean = false
  @Trace frequencyPenalty: number = 0
  // 上下文消息数量限制。0 = 不限制,发送全部历史;>0 = 仅发送最近 N 条消息
  @Trace contextMessageCount: number = 0
  // 最大输出 token 数。
  // 0 = "无限制",请求时不下发对应字段(max_tokens / max_output_tokens / maxOutputTokens),
  //   让模型按自身上限输出;Anthropic Claude 强制要求该字段时会在 AIApiService 内兜底 64_000。
  // >0 = 限制模型输出长度,请求时显式下发该值。
  @Trace maxOutputTokens: number = 0
  // 助手专属工具白名单。空数组 = 不设边界(继承全局所有工具);
  // 非空 = 仅允许列出的 toolId。搜索工具不在此白名单内(走独立 webSearch 通道)。
  @Trace enabledToolIds: string[] = []
  @Trace isDefault: boolean = false
  @Trace isPreset: boolean = false
  @Trace createdAt: number = 0
  @Trace updatedAt: number = 0
  @Trace sortOrder: number = 0

  constructor(id: string = '', name: string = '') {
    const now = Date.now()
    this.id = id
    this.name = name
    this.avatarSymbol = 'AI'
    this.color = DEFAULT_PRIMARY_COLOR
    this.systemPrompt = ''
    this.defaultProviderId = ''
    this.defaultModelId = ''
    this.defaultModelName = ''
    this.temperatureEnabled = false
    this.temperature = 0.7
    this.topPEnabled = false
    this.topP = 1.0
    this.presencePenaltyEnabled = false
    this.presencePenalty = 0
    this.frequencyPenaltyEnabled = false
    this.frequencyPenalty = 0
    this.contextMessageCount = 0
    this.maxOutputTokens = 0
    this.enabledToolIds = []
    this.isDefault = id === DEFAULT_ASSISTANT_ID
    this.createdAt = now
    this.updatedAt = now
    this.sortOrder = this.isDefault ? 0 : now
  }
}

export function createDefaultAssistant(): Assistant {
  const assistant = new Assistant(DEFAULT_ASSISTANT_ID, '小星老师')
  assistant.avatarSymbol = '⭐'
  assistant.color = '#FF9F43'
  assistant.isDefault = true
  assistant.sortOrder = 0
  assistant.systemPrompt = DEFAULT_ASSISTANT_SYSTEM_PROMPT
  assistant.enabledToolIds = [...DEFAULT_ASSISTANT_LOCKED_TOOL_IDS]
  return assistant
}
