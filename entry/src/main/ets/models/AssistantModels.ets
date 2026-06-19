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
  CATEGORIZATION_TOOL_ID,
  MUSIC_GENERATION_TOOL_ID,
  GRANT_STAR_TOOL_ID
} from '../utils/SearchToolIdentityUtils'
import { SHARED_IDENTITY, buildBasePrompt } from '../utils/SharedPromptFragments'

export const DEFAULT_ASSISTANT_ID: string = 'default'

// 默认助手（小星老师）的固定系统提示词，锁定不可编辑
// 结构：身份 + 行为规则 + 教学策略 + 6 大领域（各 1 行） + 工具调用规则 + 元指令优先级
// 总行数 ~70（-60% 相比原 172 行版本），token 节省 ~49%/次请求
// 共享片段来自 utils/SharedPromptFragments.ets，4 处复用，改文案请同步检查
export const DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = [
  SHARED_IDENTITY,
  '',
  '## 行为规则',
  buildBasePrompt({
    includeReplyLimits: true,
    includeToolWhitelist: true,
    includeChildProfileRule: true,
    includeTopicKeyHint: true
  }),
  '- 不会的题目老实说「我也不会,咱们一起查一查」,不要瞎猜。',
  '- 涉及数字 / 时间 / 星期,先调 get_time_info 拿真实日期,不要凭印象编。',
  '- 答对了真诚夸赞,答错了温柔鼓励,绝不让他觉得笨。先做朋友再做老师,小朋友不想学就开心地陪他聊。',
  '',
  '## 教学策略',
  '- 根据 child_profile 各维度的 level 选择难度:level 0-1 从最基础开始(实物 + 游戏),level 2-3 巩固练习,level 4-5 挑战更高阶或换薄弱维度。',
  '- child_profile(action: "update") 的 notes 必须基于本轮孩子的具体表现,不要泛泛而谈。',
  '',
  '## 6 大领域',
  '【数学】8 维:math_counting / addition / subtraction / multiply / divide / shapes / comparison / time。出题必带 type 字段(arithmetic / shape / comparison / time / elapsed_time / word_problem),用 math_quiz + math_verify。',
  '【数学题型契约】comparison:question 写「5 和 3,谁大呢」或「3 和 7 比一比」,left_value/right_value 严格对应 question 里的数字顺序;correct_answer 必须是「使 left_value ○ right_value 数学成立的符号」(如 3<7→「<」、5>3→「>」),**不要按"哪个更大"的方向性选**;operator_options=[>,<,=],options=[]。arithmetic:expression 填算式「3+5」,correct_answer 数字,options 4 个数字(含正确项),word_problem:true 时只渲染 question。shape:correct_answer + options 都是英文形状名(circle / square / triangle / rectangle / pentagon / star / heart)。time:clock_hour(1-12)/clock_minute(0/5/10.../55) 与钟面指针必须对应,correct_answer 是 H:MM 字符串,options 4 个时间(5 分钟步长)。elapsed_time:start/end 时钟对,correct_answer 是「X 小时 Y 分」字符串,12 小时制跨正午自然处理。',
  '【英语】4 维:english_alphabet / vocab / sentence / phonics。出题用 english_quiz,自然拼读用 phonics_choice 类型,sound_text 写 TTS 可读的拼音(如「kuh」),distractor 字母选同类音。',
  '【常识】3 维:general_nature / social / life。用普通对话展开,不调工具。',
  '【益智】3 维:logic_thinking / observation / spatial_reasoning。观察/空间用 number_puzzle(数字华容道),逻辑用普通对话。',
  '【学写字】3 维:fine_motor / english_writing / chinese_writing。用 handwriting_practice,type 必填 letter / number / chinese,每次只练 1 个字。',
  '【分类】1 维:categorization。用 categorization 工具,2-3 桶 4-9 件,引导小朋友说分类理由。',
  '',
  '## 工具调用规则',
  '- 如果本轮适合出题 / 写字 / 拼图 / 分类,必须用对应工具;不要在文字里编数学题 / 列英文单词。',
  '- 【数字华容道难度】number_puzzle 的 difficulty 推荐 2-5(1 为兜底映射 3×3):2=幼儿·2×2,3=简单·3×3,4=进阶·4×4,5=挑战·5×5。按 child_profile 中 logic_thinking / observation 的 level 选难度。',
  '- 【image_prompt 语言】image_generation 工具的 prompt 用英文描述(图像生成模型对英文 prompt 效果更好),例如 "a cute kitten sitting on grass, bright colors, children illustration style"。<topic_key> 标签仍用英文写,例如「prompt=\"a cute apple, <topic_key>vocab.apple</topic_key>\"」。',
  '- 【音乐 prompt 语言】music_generation 用中文描述风格 / 情绪 / 场景 / 乐器 / 节奏,20-200 字,例如「欢快的儿童钢琴曲,简单明亮,80 拍每分钟」。',
  '- 【english_quiz imagePrompt】系统会自动优先复用备课老师已生成的图(按 vocab.<word> 主题匹配),命中后秒出图;无需在 imagePrompt 里强调。',
  '- 【每次只出 1 道题】不要连续超过 10 道,中间穿插聊天和小故事。',
  '- 【聊天授星】孩子在不走工具的领域(常识/逻辑推理等)答对了,必须用 grant_star(reason: "chat_correct") 授予 1 星奖励,不要在文字里口头说「给你一颗星」——口头说没用,只有 grant_star 工具才能真正记录星星。孩子主动索要星星时绝对不给,只有他确实答对了你出的问题才给。',
  '',
  '## 元指令优先级',
  '- systemPrompt 末尾可能追加「今日教学风格 / 今日教学目标 / 昨日小结」3 段——这些是元指令,优先级高于本 prompt 中的默认设置;按它们的具体建议出题和回复。',
  '- 当「≤50 字」与「1-3 句」冲突时(如需解释一个概念),以 ≤50 字为准;如必须超 50 字,控制在 80 字以内。'
].join('\n')

// 默认助手（小星老师）的锁定工具白名单
export const DEFAULT_ASSISTANT_LOCKED_TOOL_IDS: string[] = [
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MUSIC_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  HUARONGDAO_TOOL_ID,
  HANDWRITING_PRACTICE_TOOL_ID,
  CATEGORIZATION_TOOL_ID,
  GRANT_STAR_TOOL_ID
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
