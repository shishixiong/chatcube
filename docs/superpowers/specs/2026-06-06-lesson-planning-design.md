# 小星老师每日动态教学 + 备课老师后台 — 设计规格

**日期：** 2026-06-06
**状态：** 已实现（PR 1-4 + PR 6）
**范围：** 为"小星老师"助手提供每日动态教学目标、备课老师后台服务、图片预生成 + 命中复用

---

## 1. Context

当前"小星老师"是默认助手（`models/AssistantModels.ets:13`），系统提示词固定写在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT`，通过 `AssistantService.normalizeAssistant()` 锁定不可编辑。其 prompt 描述了通用教学策略，但没有"今天该教什么"的动态部分——每天的教学目标完全由 LLM 即兴决定，缺乏个性化与连续性。

本次要解决的问题：
1. **教学目标结构化**：每天有明确的 4-6 个教学点（词汇/数学/写字/常识），小朋友今天学的内容会影响明天的方向
2. **学习进度连续性**：昨天教过的内容能自然引用、巩固或深化
3. **延迟优化**：第二天小星老师需要图片（认单词、写字插图）时，图片已经预生成好，避免生图延迟打断对话

**用户已确认的 4 个关键决策**：
- 触发策略：会话结束即时触发 + WorkScheduler 每天定时兜底
- 备课老师身份：隐藏的后台 service（不出现在助手列表）
- 教学目标存储：SQLite 表（`daily_lesson_plans`），**schema 灵活可扩展**（用户原话："不要固定 vocab_json, math_plan_json, writing_json，后面能增加新的课程点"）
- 图片预生成：所有视觉内容（单词、数学图形、写字插图）

---

## 2. 架构总览

```
┌──────────────────────────────────────────────────────────────────────┐
│  小星老师会话（assistant_id = 'default'）                              │
│  ChatViewModel.finalizeAIMessage()                                    │
│       │ 仅当 assistant 消息成功完成（非中断/失败）                    │
│       ▼                                                               │
│  LessonPlanningService.notifySessionEnd(sessionId, 'default')        │
│       │ 5min 静默 debounce 合并多次会话                                │
│       ▼                                                               │
│  LessonPlanningService.triggerPlanningForToday()                      │
│       │ 幂等检查（同日已 done 跳过）                                   │
│       ├─► summarizeSessions()       → 今日所有 default session 摘要    │
│       ├─► readChildProfile()        → ChildProfileService            │
│       ├─► readYesterdayPlan()       → daily_lesson_plans             │
│       ├─► callPlannerLLM()          → AIApiService.sendChatRequest   │
│       ├─► persistPlan()             → daily_lesson_plans              │
│       └─► prefetchImages()          → prepared_media + 沙箱文件        │
└──────────────────────────────────────────────────────────────────────┘
                                ▲
                                │ 21:00 兜底（DailyLessonWorkScheduler，PR 5 待做）
                                │
┌──────────────────────────────────────────────────────────────────────┐
│  读侧：ChatViewModel.buildRequestSystemPrompt()                       │
│  若 assistantId === DEFAULT_ASSISTANT_ID 且今日 plan.status==='done'  │
│  注入"今日教学目标"section 在 system prompt 末尾                       │
└──────────────────────────────────────────────────────────────────────┘
                                ▲
┌──────────────────────────────────────────────────────────────────────┐
│  命中侧：ImageGenerationExecutor.execute()                            │
│  小星老师调 image_generation 时优先查 prepared_media.topic_key        │
│  命中 → 直接返回预生成图；未命中 → 走原 generateImage                 │
└──────────────────────────────────────────────────────────────────────┘
                                ▲
┌──────────────────────────────────────────────────────────────────────┐
│  启动清理（PR 6）：LessonPlanningService.initialize()                  │
│  1. listExpiredPreparedMedia(now) → 查过期行                          │
│  2. 逐行 deleteAttachment(filePath) → 删沙箱文件                      │
│  3. deleteExpiredPreparedMedia(now) → 删行                            │
│  4. 输出 `Expired cleanup: files=N, rows=N` 日志                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. 数据模型

### 3.1 新表 DDL（追加到 `DatabaseService.createTables` 末尾）

**`daily_lesson_plans`**（一行 = 一天的计划）：

```sql
CREATE TABLE IF NOT EXISTS daily_lesson_plans (
  id TEXT PRIMARY KEY,                -- 'plan_YYYYMMDD'
  plan_date TEXT NOT NULL,            -- 'YYYY-MM-DD'（本地时区）
  plan_json TEXT NOT NULL,            -- 完整 plan_json blob（见 §3.3）
  plan_version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending',  -- 'pending'|'running'|'done'|'failed'
  error_message TEXT DEFAULT '',
  planner_provider_id TEXT DEFAULT '',
  planner_model_id TEXT DEFAULT '',
  planner_model_name TEXT DEFAULT '',
  session_ids_json TEXT DEFAULT '[]',
  message_count INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_dlp_plan_date_unique
  ON daily_lesson_plans(plan_date);
CREATE INDEX IF NOT EXISTS idx_dlp_plan_date
  ON daily_lesson_plans(plan_date DESC);
```

**`prepared_media`**（预生成图片表，与 `generated_media` 分离）：

```sql
CREATE TABLE IF NOT EXISTS prepared_media (
  id TEXT PRIMARY KEY,                -- 'pm_YYYYMMDD_<topic_key>'
  plan_id TEXT NOT NULL,              -- FK → daily_lesson_plans.id
  topic_key TEXT NOT NULL,
  topic_module TEXT NOT NULL,
  prompt TEXT NOT NULL,
  revised_prompt TEXT DEFAULT '',
  provider_id TEXT DEFAULT '',
  provider_name TEXT DEFAULT '',
  model_id TEXT DEFAULT '',
  model_name TEXT DEFAULT '',
  file_path TEXT NOT NULL,            -- 沙箱绝对路径
  mime_type TEXT DEFAULT 'image/png',
  aspect_ratio TEXT DEFAULT 'square',
  status TEXT NOT NULL DEFAULT 'ready',-- 'pending'|'ready'|'failed'
  error_message TEXT DEFAULT '',
  consumed_count INTEGER DEFAULT 0,
  last_consumed_at INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,        -- created_at + 7d
  FOREIGN KEY (plan_id) REFERENCES daily_lesson_plans(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_pm_topic_key ON prepared_media(topic_key);
CREATE INDEX IF NOT EXISTS idx_pm_status    ON prepared_media(status);
CREATE INDEX IF NOT EXISTS idx_pm_expires   ON prepared_media(expires_at);
```

**`generated_media` 复用**（关联统计）：
```sql
ALTER TABLE generated_media ADD COLUMN prepared_media_id TEXT DEFAULT '';
ALTER TABLE generated_media ADD COLUMN topic_key TEXT DEFAULT '';
```

### 3.2 `TableNames` 增量

```ts
static readonly DAILY_LESSON_PLANS: string = 'daily_lesson_plans'
static readonly PREPARED_MEDIA: string = 'prepared_media'
```

### 3.3 灵活的 `plan_json` Schema

`plan_json` 是一个 JSON blob，根结构如下。**未来增加新课程点（如 reading / music / science）只需在此加新 key**，解析层做容错（缺字段给默认值，不抛错）：

```ts
// models/LessonPlanModels.ets
export class LessonPlan {
  schemaVersion: number = 1
  planDate: string = ''          // 'YYYY-MM-DD'
  themeTitle: string = ''        // "今天和苹果做朋友"
  themeDescription: string = ''  // 给小星老师的简短说明
  teacherNotes: string = ''      // 3-5 句人话提示

  // 4 个强类型核心模块（小星老师 system prompt 会显式引用）
  vocab: LessonPlanVocabItem[] = []
  math: LessonPlanMathItem[] = []
  writing: LessonPlanWritingItem[] = []
  generalKnowledge: LessonPlanGeneralItem[] = []

  // 自由扩展 map：未来加 'reading' / 'music' / 'science' 等直接加 key
  freeform: Record<string, Object> = {}

  // 备课时的 child_profile 快照（便于家长回看）
  childSnapshot: ChildSnapshot = new ChildSnapshot()
}
```

每项 item 都带 `topicKey`（语义键，如 `vocab.apple`）—— 这是预生成图片与第二天小星老师调用 image_generation 时的精确匹配键。**topicKey 必须在 plan 内部和 prepared_media.topic_key 之间一致**。

### 3.4 PlannerStats（PR 6 新增，调试用）

```ts
// models/LessonPlanModels.ets
export class PlannerStats {
  totalPlans: number = 0           // 历史生成的计划总数
  todayPlanStatus: string = 'none' // 今日（明日 plan_date）计划状态
  preparedCount: number = 0        // 未过期且 status='ready' 的预生成图数
  consumedCount: number = 0        // 未过期预生成图被复用总次数
  hitRate: number = 0              // consumedCount / max(preparedCount, 1)
  lastPlanAt: number = 0           // 最近一次成功 done 的完成时间
}
```

---

## 4. 核心流程

### 4.1 触发

- **即时触发**：`ChatViewModel.finalizeAIMessage()` 成功路径末尾
  → `ServiceRegistry.lessonPlanning().notifySessionEnd(sessionId, 'default')`
  → 5min 静默 debounce 合并多次会话
  → `triggerPlanningForToday(false, 'sessionEnd')`
- **WorkScheduler 兜底**（PR 5 待做）：21:00 本地时区，重复注册
- **启动补跑**：`LessonPlanningService.initialize()` 调 `triggerPlanningForToday(false, 'appStart')`，覆盖冷启动场景

### 4.2 状态机

```
IDLE ──notifySessionEnd──► PENDING ──5min 静默──► PLANNING_AI
                                                     │
                                            ┌────────┼────────┐
                                          success  失败  <3次
                                            │       │       │
                                            ▼       ▼       │
                                       PREF_IMAGES FAILED ←──┘（重试）
                                            │
                                       success / 部分失败
                                            ▼
                                          DONE
```

### 4.3 预生成（PR 4 已做）

- 触发：plan 持久化后立即执行（`runPlanningPipeline` step 11）
- 提取：遍历 4 个核心模块中 `imagePrompt` 非空的项，构造 `PrefetchRequest[]`
- 并发：`Promise.allSettled` 3 并发
- 单张：`ImageGenerationService.generateImage()` + `AttachmentStorageService.saveAttachment()`
- 持久化：每张图一行 `prepared_media`（status=ready/failed）
- 幂等：`findPreparedMediaByTopicKey` 命中则跳过

### 4.4 命中（PR 4 已做）

- `ImageGenerationExecutor.execute` 入口调 `tryConsumePreparedMedia(prompt)`
- 提取 prompt 中 `<topic_key>...</topic_key>` 标记 → 查 prepared_media
- 命中 → 返回预生成图 + 调 `markPreparedMediaConsumed` 递增 consumed_count
- 未命中 → 走原 `generateImage` 实时生图
- `generated_media.prepared_media_id` / `topic_key` 字段记录命中关联

### 4.5 注入 system prompt（PR 3 已做）

- `ChatViewModel.buildRequestSystemPrompt` 末尾
- 仅当 `assistantId === 'default'` 且今日 plan.status='done' 才注入
- "今日教学目标"section + "昨日小结"section（若昨日 plan 存在）
- 模板参见 `utils/LessonPlanPromptUtils.ets`

### 4.6 启动清理（PR 6 已做）

- `LessonPlanningService.initialize()` 内：
  1. `listExpiredPreparedMedia(now)` → 过期行
  2. 逐行 `deleteAttachment(filePath)` → best-effort，单文件失败不影响其他
  3. `deleteExpiredPreparedMedia(now)` → 删行
  4. 日志：`Expired cleanup: files=N, rows=N`
- **不**做运行时周期清理（避免 IO 抖动；启动一次足够覆盖单次会话）

### 4.7 命中统计（PR 6 已做）

- `LessonPlanningService.getPlannerStats()` → 公共 API
- `DatabaseService.getPlannerStats(now, tomorrowYMD)` → 4 个独立 RdbPredicates 查询
  - `totalPlans`: `COUNT(*)` from `daily_lesson_plans`
  - `todayPlanStatus`: 明日 plan row status
  - `preparedCount` + `consumedCount`: 单查询 status='ready' AND expires_at>now 的 consumed_count 列
  - `lastPlanAt`: `MAX(completed_at)` WHERE status='done'
  - `hitRate`: `consumedCount / max(preparedCount, 1)`
- `runPlanningPipeline` 完成后打日志：
  `Pipeline done: plan=YYYY-MM-DD, prefetched=N, ready=N, failed=N, totalHitRate=X.XX`

---

## 5. 降级路径

| 场景 | 降级行为 |
|------|----------|
| 今日 plan 不存在 / 非 done | `ChatViewModel` 跳过 dailySection 注入 |
| 昨日 plan 不存在 | 跳过 yesterdaySection 注入 |
| 非 DEFAULT_ASSISTANT_ID 助手 | 两个 section 都跳过（不影响其他助手） |
| LLM 输出非合法 JSON | 三层容错：去 `<think>`、去 ` ```json ` 包裹、提取 `{...}` 区间；markFailed + 失败计数 +1 |
| 同日失败 ≥ 3 次 | 跳过重试，明日 WorkScheduler 再试 |
| 用户关闭 PLANNER_ENABLED 偏好 | `notifySessionEnd` 仍是 no-op；`runPlanningPipeline` 入口 return |
| 预生成图无 image model | 跳过预生成，plan 仍 status='done'，运行时走实时生图 |
| 单张预生成图失败 | 该行 status='failed'，其他正常；不阻塞 pipeline |
| 预生成图未带 `<topic_key>` 标记 | 走实时生图，行为正常 |
| 删除过期文件失败 | best-effort 跳过该文件，继续删行 |
| 启动清理数据库异常 | 整个清理 try/catch；不影响启动补跑 |
| `getPlannerStats` 异常 | 单独 try/catch，仅打 warn 日志，不影响 pipeline 状态 |

---

## 6. 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 触发策略 | 会话结束即时触发 + WorkScheduler 兜底 | 即时覆盖 95% 场景，WorkScheduler 兜底离线情况 |
| 备课老师身份 | 隐藏的后台 service | 不污染助手列表；用户无感 |
| plan_json schema | 4 强类型 + 1 freeform Record | 满足"灵活可扩展"诉求，未来 reading/music/science 直接加 key |
| 备课老师模型 | `DefaultModelService.getModel(CHAT)` + 禁推理 | 复用默认模型；禁推理避免 `<think>` 污染 JSON |
| 预生成时机 | plan 持久化后立即 | 预生成是 best-effort 失败不影响 plan；立即触发 7d TTL 内可用 |
| 预生成并发 | 3（与 ChatTaskOrchestrator 一致） | 平衡速度与服务商限流 |
| 预生成 TTL | 7 天 | 7 天后清理；过期不删行 → 启动清理时统一删 |
| topicKey 匹配策略 | 仅精确匹配（`<topic_key>...</topic_key>` 标记） | 模糊匹配易误命中；标记明确无歧义 |
| 预生成图与 generated_media 关系 | 表分离 + 关联列 | 避免污染生图主表；关联列做命中统计 |
| 启动清理 vs 周期清理 | 启动一次 | 避免 IO 抖动；启动一次足够覆盖单次会话窗口 |
| 命中率 UI 暴露 | 仅日志（设置页不展示） | 调试用 hilog 足够；UI 暴露无明确需求 |
| LLM 输出容错 | 三层：去 `<think>`、去 ` ```json `、提取 `{...}` | 与 `AITaskService.cleanOptimizedImagePrompt` 模式一致 |
| 同日失败上限 | 3 次 | 避免反复重试浪费 LLM 配额；3 次后等明日 WorkScheduler |
| 备课老师 max_tokens | 4096 | 4-6 个教学点 + teacherNotes 远小于 4K；预留安全余量 |
| 备课老师 temperature | 0.4 | 略低于默认 0.7 提升 JSON 结构稳定性 |

---

## 7. 关键文件

| 路径 | 角色 |
|------|------|
| `entry/src/main/ets/models/LessonPlanModels.ets` | LessonPlan / PlannerStats / 各 Item 类 + 序列化 |
| `entry/src/main/ets/services/LessonPlanningService.ets` | 核心 service：状态机 + 触发 + plan CRUD + 预生成 + 启动清理 + 统计 |
| `entry/src/main/ets/utils/LessonPlanPromptUtils.ets` | 备课老师 system prompt + section 渲染 + JSON 清理 |
| `entry/src/main/ets/utils/SessionSummaryUtils.ets` | 摘要今日 sessions（截取 + 关键词提取） |
| `entry/src/main/ets/services/DatabaseService.ets` | 2 张新表 DDL + CRUD + `listExpiredPreparedMedia` + `getPlannerStats` |
| `entry/src/main/ets/viewmodels/ChatViewModel.ets` | `buildRequestSystemPrompt` 注入今日/昨日 section；`finalizeAIMessage` 末尾 notifySessionEnd |
| `entry/src/main/ets/config/BuiltinTools.ets` | `ImageGenerationExecutor` 预生成命中 hook + tool description 引导 |
| `entry/src/main/ets/services/ServiceRegistry.ets` | `lessonPlanning()` 静态方法门面 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `initializeServices` 末尾调 `lessonPlanning().initialize(this.context)` |
| `entry/src/main/ets/models/ImageGenerationModels.ets` | `GeneratedMedia` 加 `preparedMediaId` / `topicKey` / `revisedPrompt` 字段 |

---

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| WorkScheduler 触发误差 30min-2h | 会话结束即时触发覆盖 95% 场景，WorkScheduler 仅兜底 |
| 后台 AI 3min dataTransfer 可能不够 | Plan + 图片分阶段写库；plan 入库是硬性（必须完成），预生成是 best-effort |
| 备课老师读所有 default session 的 messages | 设置页加"AI 备课老师"开关（默认开），关闭后 `notifySessionEnd` 是 no-op + WorkScheduler 取消 |
| LLM 输出非合法 JSON | 三层容错：去 `<think>`、去 ` ```json ` 包裹、提取 `{...}` 区间；markFailed 失败计数 +1 |
| 预生成图片被小星老师调 image_generation 但 prompt 不带 topic_key | 引导语引导 LLM 带标记；未命中时降级为实时生图 |
| 时区变化（用户出差）| `plan_date` 永远用本地时区（`getFullYear/getMonth/getDate`），不混用 UTC |
| 首次使用无历史数据 | childProfile 全 0、sessions 空 → 备课老师 system prompt 内置 fallback 逻辑，输出 baseline 计划 |
| 同一 `topicKey` 跨日冲突 | 每天用 `id = 'pm_YYYYMMDD_<topic_key>'` 区分；`expires_at = created_at + 7d` |
| 沙箱文件不删累积空间 | 启动清理 best-effort 删文件 + 删行（PR 6 实施）；不删时每月约 52MB（按 3.5 张/天 × 500KB × 30d） |
| 启动清理 IO 阻塞启动 | 在 `onInitialized` 异步执行，不阻塞 `initialize()` 调用方；try/catch 异常隔离 |
| `getPlannerStats` 多查询性能 | 4 个独立 RdbPredicates 查询；调用频率低（每次 pipeline 完成一次）；单次总计 <10ms |
| 命中率分母为零 | `hitRate = consumedCount / max(preparedCount, 1)` 避免 NaN |
| 删除过期文件失败 | best-effort 跳过该文件；不阻塞行删除；下次启动继续尝试 |
| 备课老师消耗 LLM 配额 | 仅在 `default` 助手会话结束时触发；同一天只跑一次（幂等）；失败 3 次后放弃 |
| 计划 JSON 大小膨胀 | 4-6 个核心点 + themeTitle/Description/teacherNotes < 2KB；远低于 SQLite 单字段上限 |
| 用户跨夜切换导致 plan_date 错位 | `plan_date` 用 `getDate()+1` 永远 = 本地"明日"；WorkScheduler 21:00 也在本地时区 |

---

## 附录 A：已完成的 PR 范围

| PR | 内容 | 状态 |
|----|------|------|
| PR 1 数据层 | LessonPlanModels + 2 张新表 + 索引 + 迁移 + CRUD + PreferencesService 3 个键 | ✅ |
| PR 2 Service 核心 | LessonPlanningService + SessionSummaryUtils + LessonPlanPromptUtils + ServiceRegistry + EntryAbility 初始化 | ✅ |
| PR 3 动态 Prompt 注入 | ChatViewModel.buildRequestSystemPrompt 改写 + 渲染函数 + 降级路径 | ✅ |
| PR 4 图片预生成 + 命中 | prefetchImages + ImageGenerationExecutor hook + tool description 引导 + generated_media 加列迁移 | ✅ |
| PR 5 WorkScheduler 兜底 | DailyLessonWorkScheduler + 设置页 UI + 失败重试 | ⏳ 待做 |
| PR 6 清理 + 监控 + 文档 | listExpiredPreparedMedia + 启动清理删文件+删行 + PlannerStats + getPlannerStats API + pipeline 日志 + 本文档 | ✅ |

## 附录 B：验证步骤

详见 plan 文件 `/Users/mac/.claude/plans/fluttering-mixing-elephant.md` §9-§10.2。
