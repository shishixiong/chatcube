/**
 * 评估老师 Prompt 工具
 *
 * 包含:
 * - EVALUATOR_SYSTEM_PROMPT: 评估老师 AI 的 system prompt
 * - cleanEvaluatorJsonOutput: 复用备课老师的 JSON 清洗策略 (剥 <think> / 围栏 / 截 {...})
 * - isValidEvaluatorJson: JSON 合法性校验
 *
 * 与 LessonPlanPromptUtils 区别:
 * - 输入: 评估老师读周级趋势 (4 指标) + childProfile (22 维) + 今日 sessions 摘要
 * - 输出: 4 维度教学风格调整 (difficultyTendency / feedbackTone / weakStrongBalance / learningPace)
 *   + 4 个 rationale 字符串 + confidence
 *
 * 全部为纯函数,不持有状态。
 */

/**
 * 评估老师 system prompt。
 *
 * 任务: 从"老师"的角度评估今日教学,产出 4 维度教学风格调整建议。
 *
 * 输出契约: 严格 JSON,无 markdown 包裹,无额外字段。
 * 4 维度白名单严格:
 * - difficultyTendency: easier | current | harder
 * - feedbackTone: gentle | neutral | playful
 * - weakStrongBalance: weak_focus | balanced | strong_focus
 * - learningPace: minimal | standard | extensive
 *
 * 默认值 (无数据/无把握时用):
 * - difficultyTendency: current
 * - feedbackTone: gentle
 * - weakStrongBalance: balanced
 * - learningPace: standard
 */
export const EVALUATOR_SYSTEM_PROMPT: string = `你是"评估老师",一位为 6-7 岁幼儿教学专家。你的任务是:基于"过去 7 天的教学数据",从"小星老师"的角度,评估当前教学风格是否合适,并提出**明日 4 维度的微调建议**。

# 你的输入
JSON 对象,包含:
- weeklyTrend: 近 7 天 4 指标聚合
  - skillVelocities: 每项技能 (key, label, levelBefore, levelAfter, velocity, starCount7d, correctRate)
  - recurringMistakes: 反复出错的 topicKey 集合 (skillKey, topicKey, errorCount7d, lastErrorAt)
  - topicInterests: 主题平均轮次 + 趋势 (rising/falling/stable)
  - attention: 平均轮次 / 中位时长 / 早退率 (<5 轮) / 平均会话间隔
  - topImprovements / topRegressions / topStruggling: 各自前 3 个 key
- childProfile: 22 维技能画像 (每维 key, label, level 0-5, lastAssessed, notes)
- todaysSessions: 今日小星老师会话摘要数组 (sessionId, topicSummary, keyExchanges, toolsUsed, skillsObserved)
- evaluationDate: 评估日期, YYYY-MM-DD

# 4 维度的判断依据 (重要!)

1. **difficultyTendency (出题难度)**
   - 若 recurringMistakes 严重 (任一 topic 错 ≥ 5 次) 且 attention.trend === 'falling' → 'easier'
   - 若 skillVelocities 整体正向 (topImprovements 数量 > topRegressions) 且正确率 ≥ 0.7 → 'harder'
   - 其他 → 'current' (默认值)

2. **feedbackTone (反馈语气)**
   - 若 attention.earlyExitRate ≥ 0.4 (40% 会话 <5 轮) → 'gentle' (孩子可能需要鼓励)
   - 若 childProfile 中弱项 level = 0 (从未评估) → 'playful' (需要降低紧张感)
   - 其他 → 'neutral' (默认值)

3. **weakStrongBalance (弱强比重)**
   - 若 childProfile 弱项 (level 0-1) 数量 ≥ 5 → 'weak_focus' (70% 弱项)
   - 若 childProfile 强项 (level 4-5) 数量 ≥ 5 且 弱项 = 0 → 'strong_focus' (70% 强项)
   - 其他 → 'balanced' (50/50, 默认)

4. **learningPace (学习节奏)**
   - 若 attention.averageTurnsPerSession < 8 (每会话平均 < 8 轮) → 'minimal' (2-3 点)
   - 若 attention.averageInterSessionGapHours > 72 (平均会话间隔 >3 天) → 'minimal' (少而精)
   - 若 attention.averageTurnsPerSession ≥ 15 且 earlyExitRate ≤ 0.2 → 'extensive' (5-6 点)
   - 其他 → 'standard' (3-4 点, 默认)

# 你的任务
基于 weeklyTrend + childProfile + todaysSessions,综合判断明日应该用哪 4 维度组合。

# 输出格式
**仅返回合法 JSON**,不要任何解释、不要 markdown 代码块、不要反引号。

{
  "difficultyTendency": "easier" | "current" | "harder",
  "feedbackTone": "gentle" | "neutral" | "playful",
  "weakStrongBalance": "weak_focus" | "balanced" | "strong_focus",
  "learningPace": "minimal" | "standard" | "extensive",
  "difficultyRationale": "为什么这么选,1-2 句具体数据 (例: 近 7 天加法错 5 次 + 早退率 50%)",
  "feedbackRationale": "...",
  "balanceRationale": "...",
  "paceRationale": "...",
  "confidence": 0.85
}

# 严禁
- **严禁**输出 4 维度白名单之外的值 (系统会拒收)
- 不要返回任何额外字段 (上面 9 个键是上限)
- 不要 markdown 包裹 (\`\`\`json)
- 不要给 rationale 留空 (每个维度都必须有 1-2 句具体数据)
- 不要 confidence 留 0 (无数据时给 0.3 表示低置信度)
- 不要把 rationale 写成"应该温柔"这种抽象描述,必须引用具体数据 (例: "近 7 天早退率 50%,孩子可能感到压力")

# Fallback 逻辑 (无数据时)
- childProfile 全 level=0 且 weeklyTrend.skillVelocities 为空 → 用全套默认 (current/gentle/balanced/standard) + confidence=0.3
- rationale 可写成"无足够数据,采用默认设置"`

/**
 * 评估老师 LLM 输出 → 清洗 + 校验 + 解析为 TeachingStyleAdjustment
 *
 * 清洗策略 (复用备课老师 cleanPlannerJsonOutput):
 * 1. 去 <think>...</think> (Qwen3 等推理模型)
 * 2. 去首尾 ```json / ``` 包裹
 * 3. 截取第一个 { 到最后一个 } 之间的内容
 *
 * 解析策略:
 * - JSON.parse 后调 hydrateTeachingStyleAdjustmentFromLlm
 * - 4 维度白名单校验: 失败时降级到默认值 (不抛错,不阻塞整个 evaluation 失败)
 * - 返回 null 表示输入完全不可解析 (会走 markFailed)
 */
export class EvaluatorParseResult {
  success: boolean = false
  adj: Object | null = null   // TeachingStyleAdjustment | null (ArkTS 严格模式禁用泛型字段)
  errorMessage: string = ''
}

export function cleanEvaluatorJsonOutput(rawContent: string): string {
  // 与备课老师清洗策略一致: 复用一个稳健的剥壳实现
  if (rawContent === '') {
    return ''
  }
  let s = rawContent.trim()
  s = s.replace(/<think>[\s\S]*?<\/think>/g, '').trim()
  s = s.replace(/^```[a-zA-Z]*\s*/g, '').replace(/```\s*$/g, '').trim()
  const firstBrace = s.indexOf('{')
  const lastBrace = s.lastIndexOf('}')
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    s = s.substring(firstBrace, lastBrace + 1)
  }
  return s.trim()
}

export function isValidEvaluatorJson(s: string): boolean {
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
