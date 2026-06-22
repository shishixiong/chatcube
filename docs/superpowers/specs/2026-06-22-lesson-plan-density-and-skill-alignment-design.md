# 每日教学计划：扩充密度 + 技能对齐 — 设计规格

**日期：** 2026-06-22
**版本：** v2
**范围：** "备课老师"每日生成的 lesson plan 增强密度（每个模块 ≥下限）和与 child profile 技能级别对齐（math 模块必填 dimension + targetSkillLevel + 8×6 rubric 查表出题）
**前置文档：**
- `docs/superpowers/specs/2026-06-06-lesson-planning-design.md`（v1 整体架构）
- `.claude/rules/teaching-architecture.md`（教学体系）

---

## 1. Context

v1 实现中，PLANNER_SYSTEM_PROMPT 写了软范围"1～5 个 vocab + 3～5 个 math"和"参考 childProfile skill level 出题"，但实际运行有两个具体问题：

1. **数量不足**：LLM 倾向取范围下限，每天 vocab 经常只有 1 个，math 经常 1-2 个，无法支撑一天的教学菜单
2. **难度未对齐**：小朋友 `math_addition.level=3`（中等 = 两位数进位加法），但 plan 里的 math 项描述仍是"个位数加减法"。LLM 看到 level 数字但**不知道 level=3 加法具体对应什么题型**

更糟的是，v1 校验逻辑（`LessonPlanningService.ets:574-587`）只检查"任一模块 ≥1 项"——LLM 即便只填 1 个 vocab 也能通过，错误暴露不到上层。

本次要解决：
1. **密度下限**：每个模块有明确最小数量约束，LLM 不达标视为失败
2. **难度对齐**：math 模块必填 `dimension` 和 `targetSkillLevel`，且 LLM 通过 8×6 rubric 查表决定具体题目
3. **硬验证 + 内部重试**：pipeline 内部 3 次重试，3 次都不达标才记一次失败（不消耗当日 fail 计数预算）

**用户已确认的 5 个决策：**
- 每模块目标数量：vocab 5 / math 5 / writing 3 / general 3（共 16 项/天）
- level 映射策略：给 LLM 提供 level→内容 rubric 表
- rubric 范围：仅 math 模块加
- rubric 颗粒度：8 个 math 维度 × 6 个 level 详表
- 不达标处理：硬验证 + 内部 3 次重试

---

## 2. 改动范围（核心）

**只动 2 个文件：**
- `utils/LessonPlanPromptUtils.ets`：PLANNER_SYSTEM_PROMPT 三处增强
- `services/LessonPlanningService.ets`：新增 `validatePlannerOutput()` + pipeline 内 3 次重试循环

**不动：**
- 数据模型：`LessonPlanModels` 已有 `dimension` / `targetSkillLevel` 字段，无需新增
- DB schema：无新表/无新列
- UI：`LearningTomorrowPlanPage` 已支持任意长度数组
- 渲染器：`renderDailyPlanSection` / `renderYesterdaySummarySection` 已正确处理任意数量
- 画像输入：`buildChildProfileForPlanner` 已传全 22 维 skill.level

---

## 3. PLANNER_SYSTEM_PROMPT 改动（`utils/LessonPlanPromptUtils.ets`）

### 3.1 替换软约束为硬目标

把现有"典型配比"软范围（第 70 行附近）替换为带下限的硬目标：

```
# 计划数量硬约束（重要，必须遵守）
- vocab: 至少 4 个，建议 5 个
- math: 至少 4 个，建议 5 个
- writing: 至少 2 个，建议 3 个
- generalKnowledge: 至少 2 个，建议 3 个
合计 12-16 个项目。低于下限视为不符合 schema，调度会重试
```

### 3.2 math 模块必填字段

新增独立段落：

```
# math 模块必填字段（硬约束）
- 每个 math 项的 `dimension` 字段必填，必须是以下之一：
  math_counting / math_addition / math_subtraction / math_multiply / math_divide /
  math_shapes / math_comparison / math_time
- 每个 math 项的 `targetSkillLevel` 字段必填，1-5 整数（0 视为未填，重试）
- 严禁 dimension 留空字符串；严禁 targetSkillLevel 留 0 或超过 5
```

### 3.3 8×6 math rubric 详表

新增独立段落（约 60 行）：

```
# math 题目难度 rubric（必须按 child skill level 查表出题）

| skill_key            | Lv0 入门 | Lv1 入门 | Lv2 初步 | Lv3 中等 | Lv4 良好 | Lv5 精通 |
|----------------------|---------|---------|---------|---------|---------|---------|
| math_counting        | 数字认读 1-5 | 数 1-10 | 数 1-20 + 倒数 5-1 | 数列 2,4,6... | 100 内数数 | 凑十/破十计数 |
| math_addition        | 0+0 概念 | 个位数 (3+5) | 两位无进位 (23+14) | 两位进位 (27+18) | 三位数 (123+234) | 多步/应用题 |
| math_subtraction     | 0-0 概念 | 个位数 (8-3) | 两位无退位 (35-12) | 两位退位 (42-17) | 三位数 (532-218) | 多步/应用题 |
| math_multiply        | 0×0 概念 | 1-5 表 | 1-9 表完整 | 多位数×1 位 | 多位数×2 位 | 应用题 |
| math_divide          | 平均分概念 | 表内除法 | 有余数除法 | 多位数÷1 位 | 多位数÷2 位 | 应用题 |
| math_shapes          | 圆形/方形识别 | 基本图形 | 组合形状 | 立体形状 | 周长/面积 | 体积/对称 |
| math_comparison      | 大小/长短 | 多少比较 | 3 项排序 | 多条件排序 | 应用题比较 | 复合比较 |
| math_time            | 整点认读 | 半点 | 5 分钟间隔 | 分钟精确 | 时间计算 | 日历/星期 |

# 出题规则
- 查 childProfile 中该 skill 的 level，按上表对应行的内容出题
- 例: child math_addition.level=3 → 出 27+18 类型的两位数进位加法
- 如果 child level=0 但 difficultyTendency='harder'，可上跳一级（取 Lv1 内容）
- description 字段必须描述具体题型（如「两位数加两位数，含进位」），不要写"出加法题"这种模糊描述
```

### 3.4 现有"严禁"段落补充

在第 94-102 行"严禁"段落追加：

```
- 严禁 math 项的 dimension 留空字符串；严禁 targetSkillLevel 填 0（系统会拒绝重试）
- 严禁 4 个模块任一少于下限（vocab<4 / math<4 / writing<2 / generalKnowledge<2）
```

---

## 4. LessonPlanningService 改动（`services/LessonPlanningService.ets`）

### 4.1 新增 `validatePlannerOutput()` 私有方法

集中放在 `LessonPlanningService` 类内（在 `buildChildProfileForPlanner` 之后），纯函数，副作用 0：

```typescript
/**
 * 验证备课老师 LLM 输出的 plan 是否满足密度 + math 字段硬约束。
 * 返回 { ok, issues }。issues 为空表示通过。
 *
 * 不达标项:
 * - 任一模块数量低于下限（vocab<4 / math<4 / writing<2 / generalKnowledge<2）
 * - math 项 dimension 不在白名单 8 个 skill_key 内
 * - math 项 targetSkillLevel 不在 [1,5] 区间（0 = 未填，视为无效）
 */
private validatePlannerOutput(plan: LessonPlan): { ok: boolean; issues: string[] } {
  const MIN_COUNTS = { vocab: 4, math: 4, writing: 2, general: 2 }
  const VALID_MATH_DIMS = new Set<string>([
    'math_counting', 'math_addition', 'math_subtraction', 'math_multiply',
    'math_divide', 'math_shapes', 'math_comparison', 'math_time'
  ])
  const issues: string[] = []

  if (plan.vocab.length < MIN_COUNTS.vocab) {
    issues.push(`vocab=${plan.vocab.length} < min ${MIN_COUNTS.vocab}`)
  }
  if (plan.math.length < MIN_COUNTS.math) {
    issues.push(`math=${plan.math.length} < min ${MIN_COUNTS.math}`)
  }
  if (plan.writing.length < MIN_COUNTS.writing) {
    issues.push(`writing=${plan.writing.length} < min ${MIN_COUNTS.writing}`)
  }
  if (plan.generalKnowledge.length < MIN_COUNTS.general) {
    issues.push(`generalKnowledge=${plan.generalKnowledge.length} < min ${MIN_COUNTS.general}`)
  }

  for (let i = 0; i < plan.math.length; i++) {
    const item = plan.math[i]
    if (item.dimension === '' || !VALID_MATH_DIMS.has(item.dimension)) {
      issues.push(`math item "${item.topicKey}" has invalid dimension="${item.dimension}"`)
    }
    if (item.targetSkillLevel < 1 || item.targetSkillLevel > 5) {
      issues.push(`math item "${item.topicKey}" has targetSkillLevel=${item.targetSkillLevel} (out of [1,5])`)
    }
  }

  return { ok: issues.length === 0, issues }
}
```

### 4.2 替换 `runPlanningPipeline` 的解析+校验段

现有逻辑（约第 561-587 行）：

```
const cleaned = cleanPlannerJsonOutput(llmResult.content)
if (cleaned === '' || !isValidJson(cleaned)) { markFailed; return }
let plan = parseLessonPlan(cleaned)
plan.planDate = planDate
plan.childSnapshot = childSnapshot
// 4 模块全空检查
if (!hasAnyModuleItem && hasNarrative) { markFailed; return }
```

替换为 3 次内部重试循环：

```typescript
const MAX_INTERNAL_ATTEMPTS = 3
let plan: LessonPlan | null = null
let lastError = ''

for (let attempt = 1; attempt <= MAX_INTERNAL_ATTEMPTS; attempt++) {
  const llmResult = await this.callPlannerLLM(userInput)
  if (!llmResult.success) {
    lastError = `LLM call failed: ${llmResult.errorMessage}`
    break  // LLM 不可恢复,直接失败
  }

  const cleaned = cleanPlannerJsonOutput(llmResult.content)
  if (cleaned === '' || !isValidJson(cleaned)) {
    lastError = `attempt ${attempt}: LLM output is not valid JSON`
    console.warn('LessonPlanningService', `Plan ${planDate} attempt ${attempt}: invalid JSON`)
    continue
  }

  const candidate = parseLessonPlan(cleaned)
  candidate.planDate = planDate  // 强制覆盖本地日期
  candidate.childSnapshot = childSnapshot  // 强制覆盖快照

  const validation = this.validatePlannerOutput(candidate)
  if (validation.ok) {
    plan = candidate
    break
  }
  lastError = `attempt ${attempt}: ${validation.issues.join('; ')}`
  console.warn('LessonPlanningService', `Plan ${planDate} attempt ${attempt} validation failed: ${lastError}`)
}

// 全部 3 次都不达标 → 记一次失败（仅增 1 次计数）
if (plan === null) {
  await this.markFailed(planId, planDate, lastError, sessions.length, messageCount, sessionIdsJson)
  return
}
```

### 4.3 不变的关键约束

- **每次 pipeline run 只调一次 `markFailed`**，无论内部重试 1 次还是 3 次。当日 fail 计数仍由 `MAX_FAILS_PER_DAY=3` 守卫
- **不传重试反馈给 LLM**：让强化后的 system prompt 自己起作用，简化实现（保留未来加 attempt-specific hint 的扩展点）
- **保留 `markFailed` 现有签名和行为**：仅 `errorMessage` 字段从"LLM 输出非合法 JSON"改为更具体的 `lastError`
- **保留现有 `cleanPlannerJsonOutput` 三层容错**：去 `<think>`、去围栏、提取 `{...}`

---

## 5. 端到端数据流

```
ChatViewModel.finalizeAIMessage()
   ↓
LessonPlanningService.notifySessionEnd(sessionId, 'default')
   ↓ (5min debounce, 仅 assistantId='default')
runPlanningPipeline(planDate=明天)
   ├─ 状态机检查 (existing done/running/failed 守卫)
   ├─ writeRunning(planId, planDate, existing)
   ├─ 准备输入
   │    ├─ sessions = databaseService.getSessionsByAssistantAndDate(...)
   │    ├─ childProfile = buildChildProfileForPlanner(profile)   ← 已含 22 维 skill.level
   │    ├─ yesterdayPlan = databaseService.getDailyLessonPlanByDate(yesterdayYMD)
   │    └─ currentStyleAdjustment = tsaService.getCurrentAdjustment()
   ├─ 调 LLM（最多 3 次内部重试）                              ← NEW 循环
   │    └─ validatePlannerOutput(candidate)                     ← NEW 函数
   ├─ 持久化 → daily_lesson_plans.plan_json
   ├─ resetTodayFailCount() + AppStorage LESSON_PLAN_REFRESH_TICK++
   └─ 预生成图片 → prepared_media (best-effort)

ChatViewModel.buildRequestSystemPrompt()
   ↓ (assistantId='default' && plan.status='done')
renderDailyPlanSection(plan, planDate, weekday)               ← 渲染 16 项菜单
   ↓
小星老师 LLM 按"使用建议"灵活选 1-2 个点开场
```

---

## 6. 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 数量下限 | vocab 4 / math 4 / writing 2 / general 2 | 用户选"中等"目标（5/5/3/3），下限取目标 -1 留 LLM 弹性 |
| rubric 范围 | 仅 math 模块 | 用户确认仅 math 维度问题最突出；vocab/writing/general 依赖现有 difficultyHint |
| rubric 颗粒度 | 8 维 × 6 level 详表 | 用户选最完整版，确保 Lv3 加法=两位数进位等映射明确 |
| 验证严格度 | 硬验证 + 3 次内部重试 | 用户确认；软警告无效果，软补全会丢失个性化 |
| 重试是否传 LLM 反馈 | 不传 | 强化后的 system prompt 应足够；保留扩展点 |
| 失败计数策略 | 每次 pipeline 只 +1 | 3 次内部重试不消耗 fail 计数预算；MAX_FAILS_PER_DAY=3 仍能阻止无限重试 |
| 历史 plan_json 处理 | 不动 | 现有 1-vocab 计划仍可读，下次 pipeline 自然替换（24h 内） |
| 是否有迁移脚本 | 无 | 仅新生成的 plan 用新规则；旧记录保持兼容 |
| Schema 版本号 | 不改（仍 schemaVersion=1） | schema 形状没变，仅填写更严格；下位兼容 |

---

## 7. 关键文件

| 路径 | 改动 |
|------|------|
| `entry/src/main/ets/utils/LessonPlanPromptUtils.ets` | PLANNER_SYSTEM_PROMPT 三处增强（密度硬约束 + math 必填 + 8×6 rubric）+ 严禁段补充 |
| `entry/src/main/ets/services/LessonPlanningService.ets` | 新增 `validatePlannerOutput()` 私有方法；`runPlanningPipeline` 替换解析+校验段为 3 次重试循环 |
| `docs/superpowers/specs/2026-06-22-lesson-plan-density-and-skill-alignment-design.md` | 本文档 |

---

## 8. 降级路径

| 场景 | 降级行为 |
|------|----------|
| 全部 3 次内部重试仍不达标 | `markFailed` 一次，errorMessage 带具体 issues；下次会话结束触发新的 pipeline（受 MAX_FAILS_PER_DAY 守卫） |
| 当日 fail 计数 ≥ 3 | 跳过当日后续 pipeline；明日 WorkScheduler 自然重试 |
| LLM 不可用（网络/配额） | `callPlannerLLM` 返回 success=false，break 循环 → markFailed |
| 数学模块 dimension 字段被 LLM 填非白名单值（如 "math_logic"） | validatePlannerOutput 命中 issues → 重试；3 次仍错则 markFailed |
| 历史 plan_json 是 v1 风格（vocab=1） | 仍可读；下次 pipeline 触发后自然替换 |

---

## 9. 风险与缓解

| 风险 | 缓解 |
|------|------|
| rubric 详表过长挤掉其他 prompt | 详表约 60 行（1.5KB），prompt 增量 < 2KB；max_tokens=4096 余量充足 |
| 3 次重试用光 LLM 配额 | 单次 pipeline 失败只增 1 次 fail 计数；MAX_FAILS_PER_DAY=3 仍守底 |
| LLM 写出非 SKILL_DEFINITIONS 的 dimension | validatePlannerOutput 白名单 8 个值过滤，命中即失败重试 |
| 历史 plan_json 不达标 | 不动它们；下次 pipeline 自然替换 |
| 小星老师拿到 16 个点讲不完 | renderDailyPlanSection §使用建议已强调"不要一次教完所有点,每次聚焦 1-2 个"——是参考菜单非硬任务 |
| 冷启动新用户（childProfile 全 0） | fallback 逻辑（PLANNER_SYSTEM_PROMPT 末段）仍生效，但需补 vocab=4+ 等填充 |
| rubric 表 + LLM 自由发挥偶发矛盾 | validatePlannerOutput 不校验 description 与 rubric 一致性（避免过度约束）；只校验必填字段 |
| LLM 把 vocab 的 targetSkillLevel 错误套用到 math | validation 仅检查 math 项的 dimension/targetSkillLevel；vocab 不校验（按设计） |

---

## 10. 验收

按 MEMORY.md 中的 hvigor 限制（CLI 无 lint/test task），验收 = `assembleHap` 编译通过 + DevEco Studio 侧手动跑流程：

```
# 编译
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

**手动验收清单：**

1. **密度验收**：打开明日计划页面 → 看到 vocab≈5 / math≈5 / writing≈3 / general≈3
2. **math 字段验收**：点开 math 卡片 → 每条都带 `dimension`（如 `math_addition`）和 `targetSkillLevel`（如 `3`）
3. **难度对齐验收**：手动把 child_profile 的 `math_addition.level` 设为 3、`math_subtraction.level` 设为 4 → 触发 pipeline → 明日 plan 中这两个 skill 的 description 包含"两位数进位加法"/"三位数"等关键词
4. **重试验收**：临时 mock LLM 返回 vocab=1 → 日志显示 3 次 attempt + 1 次 markFailed
5. **历史兼容**：检查 DB 中历史 plan_json（如果存在）仍能正常加载并渲染
6. **fallback 验收**：清空 child_profile（全部 level=0）→ 触发 pipeline → 计划符合 PLANNER_SYSTEM_PROMPT fallback 段 + vocab≥4 等下限

---

## 附录 A：rubric 详表（设计文档引用版）

| skill_key            | Lv0 入门 | Lv1 入门 | Lv2 初步 | Lv3 中等 | Lv4 良好 | Lv5 精通 |
|----------------------|---------|---------|---------|---------|---------|---------|
| math_counting        | 数字认读 1-5 | 数 1-10 | 数 1-20 + 倒数 5-1 | 数列 2,4,6... | 100 内数数 | 凑十/破十计数 |
| math_addition        | 0+0 概念 | 个位数 (3+5) | 两位无进位 (23+14) | 两位进位 (27+18) | 三位数 (123+234) | 多步/应用题 |
| math_subtraction     | 0-0 概念 | 个位数 (8-3) | 两位无退位 (35-12) | 两位退位 (42-17) | 三位数 (532-218) | 多步/应用题 |
| math_multiply        | 0×0 概念 | 1-5 表 | 1-9 表完整 | 多位数×1 位 | 多位数×2 位 | 应用题 |
| math_divide          | 平均分概念 | 表内除法 | 有余数除法 | 多位数÷1 位 | 多位数÷2 位 | 应用题 |
| math_shapes          | 圆形/方形识别 | 基本图形 | 组合形状 | 立体形状 | 周长/面积 | 体积/对称 |
| math_comparison      | 大小/长短 | 多少比较 | 3 项排序 | 多条件排序 | 应用题比较 | 复合比较 |
| math_time            | 整点认读 | 半点 | 5 分钟间隔 | 分钟精确 | 时间计算 | 日历/星期 |

**8 个维度的来源**：`ChildProfileService.ets:36-59` 的 `SKILL_DEFINITIONS` 中 8 个 `math_*` 项。**8 个值必须与 SKILL_DEFINITIONS 完全一致**——若日后新增/重命名 math 维度，rubric 表与白名单同步更新。

---

## 附录 B：与 v1 的兼容性

| 项 | v1 行为 | v2 行为 | 兼容影响 |
|----|---------|---------|----------|
| plan_json schema | schemaVersion=1, 4 模块数组可空 | 同上 + 字段约束更严 | 旧 plan_json 仍可被 `parseLessonPlan` 加载（容错） |
| 校验逻辑 | "任一模块 ≥1 项" 通过；4 模块全空 + narrative = 失败 | "各模块下限 + math 必填字段"；任一不达标即失败 | 旧 plan_json 中 vocab=1 现在会被新版校验拒绝（但不影响已存数据） |
| LLM prompt | 软范围 + 通用 level 提示 | 硬下限 + 必填字段 + 8×6 rubric 详表 | LLM 行为变化 |
| 持久化路径 | daily_lesson_plans.plan_json | 同 | 无 |
| 渲染器 | 任意长度数组 OK | 同 | 无 |
| UI 页面 | 任意长度 OK | 同 | 无 |
| Fail 计数 | 每次 pipeline fail +1 | 同（内部 3 次重试只 +1） | 无 |