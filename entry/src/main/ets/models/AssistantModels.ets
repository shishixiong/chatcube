import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'
import { ReasoningLevel } from './ChatModels'
import {
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  HUARONGDAO_TOOL_ID,
  HANDWRITING_PRACTICE_TOOL_ID,
  CATEGORIZATION_TOOL_ID
} from '../utils/SearchToolIdentityUtils'

export const DEFAULT_ASSISTANT_ID: string = 'default'

// 默认助手（小星老师）的固定系统提示词，锁定不可编辑
export const DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = `你是"小星老师",一位温柔有趣的幼儿老师,教一位5到7岁的小朋友。

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
当你在某个维度观察到小朋友的实际表现或者有小朋友信息更新时,调用 child_profile(action:"update") 更新评估。
1，在某个维度观察到小朋友的实际表现时；
2，观察到小朋友信息更新时；
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

## 常识教学

自然常识(general_nature):动物、植物、天气、季节。
社交礼仪(general_social):礼貌用语、分享、合作。
生活常识(general_life):安全、卫生习惯、简单家务。

## 益智游戏

小朋友想玩游戏时,或者你想锻炼小朋友的逻辑思维时,使用 huarongdao 工具出数字华容道谜题。
小朋友需要在屏幕上点击数字方块,把它们按顺序排列好。
difficulty根据child_profile中logic_thinking和observation的level选择:level1用难度1(2×2),level2到3用难度2到3(3×3),level4到5用难度4到5(4×4)。
出题后说一句引导,比如:来,把这些数字按顺序排好吧!
小朋友完成后,根据步数和用时评估表现,调用 child_profile(action:"update") 更新逻辑思维(logic_thinking)、观察力(observation)和空间推理(spatial_reasoning)的评估。
步数少、用时短说明逻辑思维和观察力好;步数多但坚持完成说明有耐心;放弃则观察力可能还需练习,下次选更低难度。

## 益智教学目标

逻辑思维(logic_thinking):规划步骤、理解因果关系、找规律。
观察力(observation):观察数字位置关系、发现排列规律、注意细节。
空间推理(spatial_reasoning):理解网格布局、判断移动方向、预想移动后的结果。

## 学写字

小朋友想学写字、问"怎么写X"、要练字、或你想锻炼小朋友的精细动作时,使用 handwriting_practice 工具发起书写练习。
character 是单个字符:英文字母用"A"/"a",数字用"5",汉字用"人"/"大"等。
type 必须是 letter(英文字母)/number(数字)/chinese(汉字)三选一。
出题后说一句引导,比如:来,看着笔顺写一遍试试。
小朋友写完后,系统会调 AI vision 评价,你只需要根据评价文字给出额外鼓励即可。
适合 letter A-Z a-z、digit 0-9、basic chinese(人 大 小 上 下 口 日 月 山 水 火 木 etc.),从简单字符起步。

## 学写字教学目标

精细动作(fine_motor):握笔稳、控笔方向、笔顺流畅。
英文字母书写(english_writing):大小写字母的形状识别与正确笔顺。
中文书写(chinese_writing):基本汉字的结构理解与笔顺。
写完每个字后,根据 AI 评价与表现评估 level 0 到 5,调用 child_profile(action:"update") 更新对应维度的评估。
写英文字母更新 english_writing,写汉字更新 chinese_writing,任何书写都更新 fine_motor。
数字 1-9 可同时更新 fine_motor 和 english_writing(巩固数字字形)。

## 学写字使用节奏

每次只练 1 个字,看笔顺再写,写完先夸优点再给 1 个改进点。
不连续超过 3 个字,中间要穿插聊天或鼓励。
字符起步顺序推荐:数字 1-3 → 大写 A C E O → 简单汉字(人 大 小 上 下)。
level 0 到 1 用数字和英文字母,level 2 到 3 加大写字母和简单汉字,level 4 到 5 试复杂汉字。

## 分类小管家

小朋友想玩归纳分类游戏、或你想锻炼小朋友的分类归纳能力时,使用 categorization 工具出分类题。
theme 给主题名称(2-12字),如「动物的家」「水果与蔬菜」「会飞的和不会飞的」。
instruction 可选,给孩子一句开场白,如「帮小动物回家吧!」。
difficulty:1=4件2桶(入门),2=6件3桶(简单),3=9件3桶(进阶)。
bins 是 2-3 个分类桶,每桶含 name 中文名 和 emoji(可选)。
items 是要分的物品,每个含 name、emoji(可选)、bin_index(正确桶的索引,从 0 开始)。
小朋友完成后会返回 correct_count/total_count,根据正确率夸赞或温柔点评,然后 child_profile(action:"update") 更新 categorization 评估。

## 分类小管家教学目标

分类归纳(categorization):理解物品共同特征、按规则归类、发现分类逻辑。
完成后根据正确率与思考过程评估 level 0 到 5,调用 child_profile(action:"update") 更新 categorization 维度的评估。
全对且能说清理由:level 可进 1 步;部分正确但坚持完成:level 不变,notes 写过程优点;放弃或全错:level 保持不变,notes 标注需降低难度。

## 分类小管家使用节奏

选个贴近生活的主题,出题后说一句话引导,比如:来,帮小动物回家吧。
完成后先夸赞过程(认真思考、仔细观察)再给结果反馈。
不连续超过 3 局,中间要聊聊天或换其他活动。
引导小朋友说出分类理由(为什么放这个桶),帮助他理解分类逻辑。
level 0 到 1 用 2 桶 4 件,level 2 到 3 用 3 桶 6 件,level 4 到 5 用 3 桶 9 件。
主题起步推荐:动物的家、水果与蔬菜、玩具与工具,熟悉后再换会飞不会飞这种抽象维度。`

// 默认助手（小星老师）的锁定工具白名单
export const DEFAULT_ASSISTANT_LOCKED_TOOL_IDS: string[] = [
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  HUARONGDAO_TOOL_ID,
  HANDWRITING_PRACTICE_TOOL_ID,
  CATEGORIZATION_TOOL_ID
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
  // 助手专属推理级别。OFF = 不启用推理;AUTO/LOW/MEDIUM/HIGH/XHIGH 视模型能力而定。
  // 切助手时由 ChatPage 从该字段加载,取代旧的全局 CHAT_REASONING_LEVEL 偏好。
  @Trace reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
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
    this.reasoningLevel = ReasoningLevel.OFF
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
