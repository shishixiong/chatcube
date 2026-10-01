/**
 * 备课老师 Prompt 与教学计划 Section 渲染工具
 *
 * 包含:
 * - PLANNER_SYSTEM_PROMPT: 备课老师 AI 的 system prompt
 * - renderDailyPlanSection: 渲染"今日教学目标"section 注入小星老师 prompt
 * - renderYesterdaySummarySection: 渲染"昨日小结"section（承接昨日）
 * - cleanPlannerJsonOutput: 清理 LLM 输出,提取合法 JSON
 *
 * 全部为纯函数,不持有状态。
 */

import {
  LessonPlan,
  LessonPlanChineseItem,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem,
  LessonPlanGeneralItem
} from '../models/LessonPlanModels'
import { LedgerSummary, DueReviewHint } from '../models/LearningLedgerModels'
import { SHARED_OVERRIDE_HEADER } from './SharedPromptFragments'
import { collectPlanItemsForSubject, PlanSubject } from './LessonPlanSubjectUtils'

/**
 * 备课老师 system prompt。
 *
 * 输出契约: 严格 JSON,无 markdown 包裹,无额外字段。
 * 4 个强类型模块 (vocab/math/writing/generalKnowledge) + freeform 自由扩展槽。
 */
export const PLANNER_SYSTEM_PROMPT: string = `你是"备课老师",一位为 6-7 岁幼儿教师("小星老师")准备明日课程的教育专家。

# 你的输入
JSON 对象,包含:
- todaysSessions: 今日与小星老师的对话摘要数组,每条含 sessionId, topicSummary, keyExchanges, toolsUsed, skillsObserved
- childProfile: 小朋友的 28 维技能画像 (数学 10 维 / 英语 5 维 / 语文 3 维 / 常识 3 维 / 认知 3 维 / 书写与小肌肉 4 维),每维含 key, level(0-5), lastAssessed, notes
- yesterdayPlan: 昨日的计划 JSON (可能为空)
- recentTopics: 近 7 天已教内容摘要 (可能为空对象),包含:
  - recentVocabWords: 近 7 天教过的所有英语词汇 (小写, 去重)
  - recentWritingChars: 近 7 天教过的所有写字字/词 (去重)
  - recentThemeTitles: 近 7 天的所有 themeTitle 文本 (去重)
  - recentMathDescriptions: 近 7 天的所有 math.description 文本 (去重)
- ledger: 词级台账状态 (可能为 null), 覆盖英语词与语文项 (汉字/词/拼音/句子), 包含:
  - newCandidates: 台账中的新词候选 (mastery<=1)
  - dueReview: 到期该复习的词
  - mastered: 已掌握 (mastery=5, 勿当新词)
  - cooling: 冷却中 (30 分钟内刚出过)
- currentStyleAdjustment: **今日教学风格调整** (评估老师今晨产出),包含 4 维度:
  - difficultyTendency: easier | current | harder (出题难度倾向)
  - feedbackTone: gentle | neutral | playful (反馈语气)
  - weakStrongBalance: weak_focus | balanced | strong_focus (弱强比重)
  - learningPace: minimal | standard | extensive (学习节奏)
  - + 4 个 rationale (具体原因)
  - 可能为 null (今日无有效 tsa, 用默认值)
- planDate: 明日日期,格式 YYYY-MM-DD

# 你的任务
为明天 (planDate) 规划一份**精简、有趣、可执行**的课程计划。要求:
1. **聚焦 4-6 个核心点**。今天学太多会让孩子反感。覆盖 vocab / math / chinese / writing / generalKnowledge 中至少 4 个模块。
2. **贴合薄弱点**。从 childProfile.weakAreas 中选 1-2 个做重点,其他点为巩固/兴趣。
3. **承接昨日但主题轮换**。可选地引用昨日一个教学点作开场（例: "昨天我们认识了苹果,今天..."）,但 themeTitle 主题类别必须与近 7 天 recentTopics.recentThemeTitles 中的不同。严禁"同一主题深化或扩展"式延续——那会让 frog 之类的词连续出现多天。
3.5 **避免重复 (词级台账驱动)**。输入 JSON 的 ledger 字段给出词级状态, 硬约束:
    - vocab[].word 严禁出现在 ledger.mastered 或 ledger.cooling 中
    - 已掌握词最多 1 个仅作"复习轮"出现, 且必须换一种题型
    - 优先从 ledger.newCandidates / ledger.dueReview 中选词
    - 若 ledger 为 null 或各数组均为空 (首次使用/台账不可用), 本条硬约束自动失效
    - recentTopics 仍保留作主题类别轮换之用: themeTitle 严禁与 recentTopics.recentThemeTitles 重复;
      writing[].characterOrWord 仍避免与 recentTopics.recentWritingChars 完全相同 (台账为空的兜底)
    - chinese[].character 同样受台账约束: 严禁出现在 ledger.mastered / ledger.cooling 中; 优先取 newCandidates / dueReview 中的语文项
3.6 **主题类别轮换**。从以下类别中选近 7 天未用过的 (查 recentTopics.recentThemeTitles 推断已用类别):
    动物 / 水果 / 食物 / 交通工具 / 日常物品 / 身体部位 / 家人 / 颜色 /
    自然(天气/植物) / 衣物 / 职业 / 地点(家/学校/公园) / 节日 / 情绪 / 数字 / 形状
    若 childProfile.weakSkills 指向某维度(如 math_shapes), 可优先选对应类别(如"形状"), 但仍不得与近 7 天重复。
4. **imagePrompt 必须是英文**。描述具体、童趣、安全(无暴力/无成人元素)。例: "a cute red apple with a smile face, cartoon style, white background, soft lighting, children's book illustration"。不要出现 photo / real / realistic 这类词。
4.5 **math 模块必填字段 (硬约束)**:
- 每个 math 项的 'dimension' 字段必填, 必须是以下之一:
  math_counting / math_number_sense / math_addition / math_subtraction / math_multiply /
  math_divide / math_shapes / math_comparison / math_time / math_word_problem
- 每个 math 项的 'targetSkillLevel' 字段必填, 1-5 整数 (0 视为未填, 重试)
- 严禁 dimension 留空字符串; 严禁 targetSkillLevel 填 0 或超过 5
5. **难度匹配**。参考 childProfile 中对应 skill 的 level: 0-1 从最基础开始, 2-3 巩固, 4-5 挑战。
6. **teacherNotes 写 3-5 句**。给小星老师的人话提示,例: "上午教 2 个词,下午教形状,记得每次都先问孩子昨天学了什么"。
7. **响应教学风格调整**。若 currentStyleAdjustment 非空,需结合 4 维度调整内容侧重:
   - difficultyTendency='easier' → 计划中所有 4 模块描述要更简单, 避免"挑战"类措辞, imagePrompt 用更可爱/简化的元素
   - difficultyTendency='harder' → 计划可加 1-2 个挑战点, imagePrompt 用更丰富的元素
   - feedbackTone='gentle' → teacherNotes 强调"先鼓励再纠正"
   - feedbackTone='playful' → teacherNotes 强调"用游戏化方式", themeTitle 更活泼
   - weakStrongBalance='weak_focus' → 计划 70% 集中在 childProfile.weakAreas
   - weakStrongBalance='strong_focus' → 计划 70% 集中在 childProfile.strongSkills
   - learningPace='minimal' → 总共 2-3 个点, 不要超过 3 个
   - learningPace='extensive' → 可达 5-6 个点, 但每个点的 description 要紧凑
   - 若 currentStyleAdjustment 为 null, 用默认风格 (current/gentle/balanced/standard)

# 输出格式
**仅返回合法 JSON**,不要任何解释、不要 markdown 代码块、不要反引号。

**5 个模块数组的强约束 (重要!)**:
- vocab / math / writing / generalKnowledge / chinese **每个数组都必须填入至少 1 个具体教学点**
- 禁止把内容写在 themeTitle/themeDescription/teacherNotes 里, 然后 5 个数组留空
- themeTitle 是 1 句话主题, 它**不替代** 5 个模块里的具体内容
- **数量硬下限**（系统会拒绝重试）:
  - vocab: 至少 4 个, 建议 5 个
  - math: 至少 4 个, 建议 5 个
  - chinese: 至少 2 个, 建议 3 个
  - writing: 至少 2 个, 建议 3 个
  - generalKnowledge: 至少 2 个, 建议 3 个
  - 合计 14-19 个项目。低于下限视为不符合 schema, 调度会重试

结构必须严格遵守:

{
  "schemaVersion": 2,
  "planDate": "YYYY-MM-DD",
  "themeTitle": "...",
  "themeDescription": "...",
  "vocab": [
    {"topicKey": "vocab.<word>", "word": "...", "translation": "...", "exampleSentence": "...", "imagePrompt": "...", "difficultyHint": "入门"}
  ],
  "math": [
    {"topicKey": "math.<dim>.<topic>", "dimension": "<skill_key>", "description": "...", "targetSkillLevel": N, "imagePrompt": "..."}
  ],
  "chinese": [
    {"topicKey": "chinese.pinyin.shan", "dimension": "pinyin", "character": "shān", "description": "拼读 sh—ān→shān", "targetSkillLevel": 2, "imagePrompt": ""}
  ],
  "writing": [
    {"topicKey": "writing.<char>", "characterOrWord": "...", "subject": "chinese", "description": "...", "imagePrompt": "..."}
  ],
  "generalKnowledge": [
    {"topicKey": "general_<dim>.<topic>", "dimension": "<skill_key>", "description": "...", "imagePrompt": "..."}
  ],
  "teacherNotes": "..."
}

# 严禁
- **严禁**把教学点全写在 themeTitle 里, 然后 5 个模块数组留空 (系统会检测并视为失败)
- 不要返回任何额外字段 (themeTitle/themeDescription/teacherNotes/5 个模块 (vocab/math/chinese/writing/generalKnowledge) 是上限)
- 不要给 markdown / \`\`\`json
- 不要编造 childProfile 里不存在的 skill_key
- 词汇、句子的中文必须地道、6-7 岁孩子能懂
- imagePrompt 不要出现 "photo, real, realistic, 真人, 写实" 等可能让 API 误生成的词
- topicKey 必须全局唯一,推荐格式: "vocab.<word>" / "math.<dim>.<topic>" / "writing.<char>" / "general_<dim>.<topic>"
- 严禁 math 项的 dimension 留空字符串; 严禁 targetSkillLevel 填 0 (系统会拒绝重试)
- 严禁 chinese 项的 dimension 留空或填白名单外的值; 严禁 targetSkillLevel 填 0 (系统会拒绝重试)
- 严禁 writing 项的 subject 留空或填 english/chinese/math 之外的值 (系统会拒绝重试)
- 严禁 5 个模块任一少于下限 (vocab<4 / math<4 / chinese<2 / writing<2 / generalKnowledge<2)

# 语文模块要求 (chinese[])

- dimension 必填, 只能是以下之一: pinyin / chinese_vocab / chinese_reading
  - pinyin: 拼音认读 (character 填带调音节, 如 "shān"), 可配合 pinyin_quiz / pinyin_card 出题
  - chinese_vocab: 识字组词 (character 填单字或词, 如 "山" / "高山"), 可配合 hanzi_card / chinese_quiz 出题
  - chinese_reading: 阅读表达 (character 填短句), 可配合 picture_talk / chinese_quiz sentence_order 出题
- targetSkillLevel 必填 1-5, 参考 childProfile 中对应 skill (pinyin / chinese_vocab / chinese_reading) 的 level
- imagePrompt 一律留空 (语文卡片自带笔画数据 / 运行时生图, 无需预生成图)
- topicKey 推荐格式: "chinese.<dimension>.<topic>", 全局唯一
- 中文内容必须地道、6-7 岁孩子能懂; 拼音音节必须带声调符号

# math 题目难度 rubric (必须按 child skill level 查表出题)

| skill_key            | Lv0 入门 | Lv1 入门 | Lv2 初步 | Lv3 中等 | Lv4 良好 | Lv5 精通 |
|----------------------|---------|---------|---------|---------|---------|---------|
| math_counting        | 数字认读 1-5 | 数 1-10 | 数 1-20 + 倒数 5-1 | 数列 2,4,6... | 100 内数数 | 凑十/破十计数 |
| math_number_sense    | 10 以内认数 | 分与合 | 凑十朋友 | 拆 10 | 灵活拆 | 多种拆法 |
| math_addition        | 0+0 概念 | 个位数 (3+5) | 两位无进位 (23+14) | 两位进位 (27+18) | 三位数 (123+234) | 多步/应用题 |
| math_subtraction     | 0-0 概念 | 个位数 (8-3) | 两位无退位 (35-12) | 两位退位 (42-17) | 三位数 (532-218) | 多步/应用题 |
| math_multiply        | 0×0 概念 | 1-5 表 | 1-9 表完整 | 多位数×1 位 | 多位数×2 位 | 应用题 |
| math_divide          | 平均分概念 | 表内除法 | 有余数除法 | 多位数÷1 位 | 多位数÷2 位 | 应用题 |
| math_shapes          | 圆形/方形识别 | 基本图形 | 组合形状 | 立体形状 | 周长/面积 | 体积/对称 |
| math_comparison      | 大小/长短 | 多少比较 | 3 项排序 | 多条件排序 | 应用题比较 | 复合比较 |
| math_time            | 整点认读 | 半点 | 5 分钟间隔 | 分钟精确 | 时间计算 | 日历/星期 |
| math_word_problem    | 看图说一句话 | 听题摆图 | 看图列式 | 加减应用题 | 两步题 | 自编题 |

# 出题规则
- 查 childProfile 中该 skill 的 level, 按上表对应行的内容出题
- 例: child math_addition.level=3 → 出 27+18 类型的两位数进位加法
- 如果 child level=0 但 difficultyTendency='harder', 可上跳一级 (取 Lv1 内容)
- description 字段必须描述具体题型 (如「两位数加两位数, 含进位」), 不要写"出加法题"这种模糊描述

# Fallback 逻辑 (用于无历史数据/无昨日计划时)
如果 childProfile 全 level=0 且 yesterdayPlan 为空:
- 输出一份"入门引导"计划: 自我介绍 + 认识颜色 + 数字 1-5
- themeTitle: "小星老师和你做朋友"
- 5 个模块数组**仍然必须填**, 例如 vocab: 颜色词, math: 数字 1-5, writing: "一/二", generalKnowledge: 自我介绍话术
- 不需要 imagePrompt (用户首次进入,允许空白图像)

如果 LLM 实在无法生成 plan, 返回最小合法 JSON (**5 个数组也不能空**, 至少各填 1 个占位项):
{"schemaVersion": 2, "planDate": "<planDate>", "themeTitle": "和老师一起玩游戏", "themeDescription": "今天一起聊聊", "vocab": [{"topicKey": "vocab.friend", "word": "friend", "translation": "朋友", "imagePrompt": ""}], "math": [{"topicKey": "math.count.basic", "dimension": "math_counting", "description": "数 1 到 5", "targetSkillLevel": 1, "imagePrompt": ""}], "chinese": [{"topicKey": "chinese.chinese_vocab.shan", "dimension": "chinese_vocab", "character": "山", "description": "认读汉字山，并组词", "targetSkillLevel": 1, "imagePrompt": ""}, {"topicKey": "chinese.pinyin.shan", "dimension": "pinyin", "character": "shān", "description": "拼读第一声", "targetSkillLevel": 1, "imagePrompt": ""}], "writing": [{"topicKey": "writing.一", "characterOrWord": "一", "subject": "chinese", "description": "横画入门", "imagePrompt": ""}], "generalKnowledge": [{"topicKey": "general_intro.first", "dimension": "social_skills", "description": "向老师问好", "imagePrompt": ""}], "teacherNotes": "自由发挥,先和孩子聊聊他/她喜欢什么"}`

/**
 * 渲染"今日教学目标"section 注入小星老师 system prompt。
 * 若 plan 完全为空 (无任何教学点),返回空字符串 (降级)。
 */
export function renderDailyPlanSection(plan: LessonPlan, planDate: string, weekday: string): string {
  const hasAnyItem =
    plan.vocab.length > 0 ||
    plan.math.length > 0 ||
    plan.chinese.length > 0 ||
    plan.writing.length > 0 ||
    plan.generalKnowledge.length > 0 ||
    Object.keys(plan.freeform).length > 0
  if (!hasAnyItem && plan.themeTitle === '') {
    return ''
  }

  const lines: string[] = []
  lines.push(`## 今日教学目标 (${planDate}, 星期${weekday})`)
  lines.push('')
  lines.push(SHARED_OVERRIDE_HEADER)
  if (plan.themeTitle !== '') {
    lines.push(`主题: ${plan.themeTitle}`)
  }
  if (plan.themeDescription !== '') {
    lines.push(`简介: ${plan.themeDescription}`)
  }
  lines.push('')
  lines.push('### 推荐教学点')
  lines.push('')
  // 四学科分组 (2026-10-01 学科拆分): 未打标签 writing 归常识组 (防御性, 校验器使其实际不出现)
  appendSubjectGroup(lines, '语文', collectGroupLines(plan, 'chinese'))
  appendSubjectGroup(lines, '数学', collectGroupLines(plan, 'math'))
  appendSubjectGroup(lines, '英语', collectGroupLines(plan, 'english'))
  appendSubjectGroup(lines, '常识', collectGeneralGroupLines(plan))
  // freeform 扩展模块
  const freeformKeys = Object.keys(plan.freeform)
  for (let i = 0; i < freeformKeys.length; i++) {
    const k = freeformKeys[i]
    const v = plan.freeform[k]
    if (Array.isArray(v)) {
      for (let j = 0; j < v.length; j++) {
        const entry = v[j] as Record<string, Object>
        lines.push(`- [${k}] ${formatFreeformEntry(entry)}`)
      }
    }
  }
  lines.push('')
  if (plan.teacherNotes !== '') {
    lines.push('### 教学提示')
    lines.push(plan.teacherNotes)
    lines.push('')
  }
  lines.push('### 使用建议')
  lines.push('- 不要一次教完所有点,每次聚焦 1-2 个,先聊后教')
  lines.push('- 教新点前调用 child_profile(action:"read") 确认小朋友当前水平')
  lines.push('- 教词汇/数学图形/写字插图时,优先用 image_generation 工具')
  lines.push('  提示词: 直接使用本计划中给出的 imagePrompt, 并在末尾追加 `<topic_key><该条目的topicKey></topic_key>`')
  lines.push('  (例: image_generation prompt="a cute apple, <topic_key>vocab.apple</topic_key>")')
  lines.push('  系统会优先返回备课老师昨晚预生成的图,大幅降低等待时间')
  lines.push('- 已教过的点不要重复出题;可围绕主题变体出题巩固')
  return lines.join('\n')
}

/** 单学科分组行 (chinese: chinese 模块 + writing[chinese]; math/english 同理) */
function collectGroupLines(plan: LessonPlan, subject: PlanSubject): string[] {
  const items = collectPlanItemsForSubject(plan, subject)
  const out: string[] = []
  for (let i = 0; i < items.chinese.length; i++) {
    out.push(formatChineseLine(items.chinese[i]))
  }
  for (let i = 0; i < items.vocab.length; i++) {
    out.push(formatVocabLine(items.vocab[i]))
  }
  for (let i = 0; i < items.math.length; i++) {
    out.push(formatMathLine(items.math[i]))
  }
  for (let i = 0; i < items.writing.length; i++) {
    out.push(formatWritingLine(items.writing[i]))
  }
  return out
}

/** 常识组行: generalKnowledge 模块 + 未打标签 writing (防御性兜底) */
function collectGeneralGroupLines(plan: LessonPlan): string[] {
  const out: string[] = []
  for (let i = 0; i < plan.generalKnowledge.length; i++) {
    out.push(formatGeneralLine(plan.generalKnowledge[i]))
  }
  for (let i = 0; i < plan.writing.length; i++) {
    const w = plan.writing[i]
    if (w.subject === '') {
      out.push(formatWritingLine(w))
    }
  }
  return out
}

/** 非空组才输出标题 (避免空节) */
function appendSubjectGroup(lines: string[], title: string, groupLines: string[]): void {
  if (groupLines.length === 0) {
    return
  }
  lines.push(`### ${title}`)
  lines.push('')
  for (let i = 0; i < groupLines.length; i++) {
    lines.push(groupLines[i])
  }
  lines.push('')
}

/**
 * 渲染"本学科教学目标"section 注入学科老师 system prompt (spec §6.2)。
 * - 本学科 0 条 → 返回 '' (调用方整段省略; v1 旧计划自然静默)
 * - 给主题句, 不给 teacherNotes; 不含 image_generation 指引 (学科助手锁定工具无此工具)
 */
export function renderDailyPlanSectionForSubject(plan: LessonPlan, planDate: string, weekday: string,
  subject: PlanSubject): string {
  const items = collectPlanItemsForSubject(plan, subject)
  const hasItems = items.chinese.length > 0 || items.vocab.length > 0 ||
    items.math.length > 0 || items.writing.length > 0
  if (!hasItems) {
    return ''
  }
  const title = subject === 'math' ? '数学' : (subject === 'english' ? '英语' : '语文')
  const lines: string[] = []
  lines.push(`## ${title}教学目标 (${planDate}, 星期${weekday})`)
  lines.push('')
  lines.push(SHARED_OVERRIDE_HEADER)
  if (plan.themeTitle !== '') {
    lines.push(`主题: ${plan.themeTitle}`)
    lines.push('')
  }
  lines.push('### 推荐教学点')
  lines.push('')
  for (let i = 0; i < items.chinese.length; i++) {
    lines.push(formatChineseLine(items.chinese[i]))
  }
  for (let i = 0; i < items.vocab.length; i++) {
    lines.push(formatVocabLine(items.vocab[i]))
  }
  for (let i = 0; i < items.math.length; i++) {
    lines.push(formatMathLine(items.math[i]))
  }
  for (let i = 0; i < items.writing.length; i++) {
    lines.push(formatWritingLine(items.writing[i]))
  }
  lines.push('')
  lines.push('### 使用建议')
  lines.push('- 不要一次教完所有点,每次聚焦 1-2 个,先聊后教')
  lines.push('- 教新点前调用 child_profile(action:"read") 确认小朋友当前水平')
  lines.push('- 已教过的点不要重复出题;可围绕主题变体出题巩固')
  return lines.join('\n')
}

/**
 * 渲染"昨日小结"section 注入小星老师 system prompt。
 * 用于承接昨日,帮助小星老师自然引用昨日成果。
 */
export function renderYesterdaySummarySection(plan: LessonPlan, planDate: string): string {
  const hasAnyItem =
    plan.vocab.length > 0 ||
    plan.math.length > 0 ||
    plan.writing.length > 0 ||
    plan.generalKnowledge.length > 0
  if (!hasAnyItem && plan.themeTitle === '') {
    return ''
  }
  const lines: string[] = []
  lines.push(`## 昨日 (${planDate}) 教学小结`)
  lines.push('')
  lines.push(SHARED_OVERRIDE_HEADER)
  if (plan.themeTitle !== '') {
    lines.push(`主题: ${plan.themeTitle}`)
  }
  if (plan.vocab.length > 0) {
    const words = plan.vocab.map(v => v.word).filter(w => w !== '').slice(0, 6)
    if (words.length > 0) {
      lines.push(`- 已教词汇: ${words.join(', ')}`)
    }
  }
  if (plan.math.length > 0) {
    const descs = plan.math.map(m => m.description).filter(d => d !== '').slice(0, 4)
    if (descs.length > 0) {
      lines.push(`- 已教数学: ${descs.join('; ')}`)
    }
  }
  if (plan.writing.length > 0) {
    const chars = plan.writing.map(w => w.characterOrWord).filter(c => c !== '').slice(0, 4)
    if (chars.length > 0) {
      lines.push(`- 已教写字: ${chars.join(', ')}`)
    }
  }
  if (plan.generalKnowledge.length > 0) {
    const descs = plan.generalKnowledge.map(g => g.description).filter(d => d !== '').slice(0, 4)
    if (descs.length > 0) {
      lines.push(`- 已教常识: ${descs.join('; ')}`)
    }
  }
  lines.push('')
  lines.push('今天可以自然引用昨日的成果,例如"昨天我们一起认识了苹果,今天...怎么样?"')
  return lines.join('\n')
}

function formatVocabLine(item: LessonPlanVocabItem): string {
  const parts: string[] = []
  parts.push(`- 英语词汇 (vocab): ${item.word}`)
  if (item.translation !== '') {
    parts.push(`(${item.translation})`)
  }
  if (item.exampleSentence !== '') {
    parts.push(`— 例句: ${item.exampleSentence}`)
  }
  return parts.join(' ')
}

function formatMathLine(item: LessonPlanMathItem): string {
  const parts: string[] = []
  parts.push(`- 数学 (math): ${item.description}`)
  if (item.dimension !== '') {
    parts.push(`[${item.dimension}]`)
  }
  parts.push(`(目标 level ${item.targetSkillLevel})`)
  return parts.join(' ')
}

function formatWritingLine(item: LessonPlanWritingItem): string {
  const parts: string[] = []
  parts.push(`- 写字 (writing): ${item.characterOrWord}`)
  if (item.description !== '') {
    parts.push(`— ${item.description}`)
  }
  return parts.join(' ')
}

function formatGeneralLine(item: LessonPlanGeneralItem): string {
  const parts: string[] = []
  parts.push(`- 常识 (generalKnowledge): ${item.description}`)
  if (item.dimension !== '') {
    parts.push(`[${item.dimension}]`)
  }
  return parts.join(' ')
}

function formatChineseLine(item: LessonPlanChineseItem): string {
  const parts: string[] = []
  parts.push(`- [${item.dimension}] ${item.character}`)
  if (item.description !== '') {
    parts.push(`— ${item.description}`)
  }
  if (item.targetSkillLevel > 0) {
    parts.push(`(目标 level ${item.targetSkillLevel})`)
  }
  return parts.join(' ')
}

function formatFreeformEntry(entry: Record<string, Object>): string {
  // 通用兜底: 把所有字符串字段拼成可读行
  const keys = Object.keys(entry)
  if (keys.length === 0) {
    return ''
  }
  const parts: string[] = []
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i]
    const v = entry[k]
    if (typeof v === 'string' && v !== '') {
      parts.push(`${k}=${v}`)
    } else if (typeof v === 'number') {
      parts.push(`${k}=${v}`)
    }
  }
  return parts.join(' ')
}

/**
 * 清理备课老师 LLM 输出,提取合法 JSON 字符串。
 *
 * 容错策略 (按顺序):
 * 1. 去 <think>...</think> (Qwen3 等推理模型)
 * 2. 去首尾 ```json / ``` 包裹
 * 3. 截取第一个 { 到最后一个 } 之间的内容
 * 4. 返回清理后的字符串;若清理后非 JSON,返回空字符串
 */
export function cleanPlannerJsonOutput(rawContent: string): string {
  if (rawContent === '') {
    return ''
  }
  let s = rawContent.trim()

  // 1. 去思考标签
  s = s.replace(/<think>[\s\S]*?<\/think>/g, '').trim()

  // 2. 去首尾 markdown 代码块
  s = s.replace(/^```[a-zA-Z]*\s*/g, '').replace(/```\s*$/g, '').trim()

  // 3. 截取 {...} 区间
  const firstBrace = s.indexOf('{')
  const lastBrace = s.lastIndexOf('}')
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    s = s.substring(firstBrace, lastBrace + 1)
  }

  return s.trim()
}

/**
 * 验证清理后的字符串是否是合法 JSON。
 * 返回 true 表示可解析。
 */
export function isValidJson(s: string): boolean {
  if (s === '') {
    return false
  }
  try {
    JSON.parse(s)
    return true
  } catch (_e) {
    return false
  }
}

// ============================================================
// 近 N 天已教内容摘要 (供备课老师 LLM 输入, 防止跨日重复)
// ============================================================

/** 近期已教内容摘要 (4 个去重数组)。各数组为空表示无历史约束。 */
export interface RecentTopicsSummary {
  recentVocabWords: string[]
  recentWritingChars: string[]
  recentThemeTitles: string[]
  recentMathDescriptions: string[]
}

/**
 * 从近 N 天 (已 done) 的 LessonPlan 数组中提取去重的已教内容摘要。
 *
 * - 输入: LessonPlan 数组 (按日期升序或倒序均可, 本函数仅做去重收集)
 * - 输出: 4 个去重数组
 *   - recentVocabWords: vocab.word 全部转小写
 *   - recentWritingChars: writing.characterOrWord 原样 (含中文, 不转大小写)
 *   - recentThemeTitles: themeTitle 原样
 *   - recentMathDescriptions: math.description 原样
 * - 纯函数, 无副作用, 无 IO
 *
 * 供 LessonPlanningService.runPlanningPipeline 注入 LLM 输入 JSON 的 recentTopics 字段。
 */
export function extractRecentTopics(plans: LessonPlan[]): RecentTopicsSummary {
  const summary: RecentTopicsSummary = {
    recentVocabWords: [],
    recentWritingChars: [],
    recentThemeTitles: [],
    recentMathDescriptions: []
  }
  for (let i = 0; i < plans.length; i++) {
    const plan = plans[i]
    if (plan.themeTitle !== '') {
      pushUnique(summary.recentThemeTitles, plan.themeTitle)
    }
    for (let j = 0; j < plan.vocab.length; j++) {
      const word = plan.vocab[j].word
      if (word !== '') {
        pushUnique(summary.recentVocabWords, word.toLowerCase())
      }
    }
    for (let j = 0; j < plan.writing.length; j++) {
      const ch = plan.writing[j].characterOrWord
      if (ch !== '') {
        pushUnique(summary.recentWritingChars, ch)
      }
    }
    for (let j = 0; j < plan.math.length; j++) {
      const desc = plan.math[j].description
      if (desc !== '') {
        pushUnique(summary.recentMathDescriptions, desc)
      }
    }
  }
  return summary
}

/** 数组尾部追加去重 (区分大小写敏感, 由调用方决定是否预先 toLowerCase)。 */
function pushUnique(arr: string[], value: string): void {
  if (arr.indexOf(value) < 0) {
    arr.push(value)
  }
}

function ledgerSectionHasContent(summary: LedgerSummary): boolean {
  return summary.newPool.length > 0 || summary.dueReview.length > 0
    || summary.mastered.length > 0 || summary.cooling.length > 0
}

function appendLedgerSubjectLines(lines: string[], label: string, summary: LedgerSummary): void {
  if (summary.mastered.length > 0) {
    lines.push(`- ${label}已掌握(勿当新词考, 只在复习轮抽检): ${summary.mastered.join(', ')}`)
  }
  if (summary.newPool.length > 0) {
    lines.push(`- ${label}今日新词: ${summary.newPool.join(', ')}`)
  }
  if (summary.dueReview.length > 0) {
    const parts: string[] = []
    for (let i = 0; i < summary.dueReview.length; i++) {
      const hint = summary.dueReview[i]
      if (hint.lastMode !== '') {
        parts.push(`${hint.display}(上次 ${hint.lastMode})`)
      } else {
        parts.push(hint.display)
      }
    }
    lines.push(`- ${label}待复习(请换题型巩固): ${parts.join(' / ')}`)
  }
  if (summary.cooling.length > 0) {
    lines.push(`- ${label}冷却中(本轮勿出): ${summary.cooling.join(', ')}`)
  }
}

/**
 * 小星老师 prompt 的【词汇台账】段 (spec §8.1)。
 * 两科摘要都为 null 或四名单全空时返回 '' (调用方整段省略, 避免 prompt 出现空节)。
 */
export function renderVocabLedgerSection(en: LedgerSummary | null, zh: LedgerSummary | null): string {
  if (en === null && zh === null) {
    return ''
  }
  const hasEn = en !== null && ledgerSectionHasContent(en)
  const hasZh = zh !== null && ledgerSectionHasContent(zh)
  if (!hasEn && !hasZh) {
    return ''
  }
  const lines: string[] = []
  lines.push('【词汇台账】')
  if (en !== null && ledgerSectionHasContent(en)) {
    appendLedgerSubjectLines(lines, '英语', en)
  }
  if (zh !== null && ledgerSectionHasContent(zh)) {
    appendLedgerSubjectLines(lines, '语文', zh)
  }
  lines.push('出题规则: 新词优先; 复习词必须换一种题型复现, 不要同一题型连出同一词; ' +
    '同一词一节课最多出现 2 次(不同题型), 不要连续 5 题内重复。')
  return lines.join('\n')
}
