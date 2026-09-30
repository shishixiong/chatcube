# 词汇重复控制与间隔巩固 — 设计规格

**日期：** 2026-09-30
**状态：** 待评审（Draft · v1.1 已核对代码）
**范围：** 为「小星老师」的英语 / 语文教学引入词级台账、三名单选词、间隔重复与冷却、Prompt 动态注入、出题硬门禁
**关联文档：** `2026-06-06-lesson-planning-design.md`、`english-teaching-prompt-v2.md`、`chinese-teaching-prompt-v2.md`

---

## 1. Context

### 1.1 问题现象

小朋友在使用中反复遇到**同一个单词 / 汉字 / 拼音音节**，即使近期已经学过、做过很多遍。教学与出题没有形成"新知 + 遗忘曲线复习"的节奏，体验退化为刷屏。

### 1.2 现状代码事实

| 层级 | 现状（代码事实） | 缺口 |
|---|---|---|
| 画像 | `ChildProfileService.ets` 仅存 28 个技能维度的 `level(0-5)` + `notes/strategy/misconceptions` 自由文本 | **没有任何"词"这一层的记录**——学过哪些词、考过几次、对几次，画像答不上来 |
| 备课 | `LessonPlanPromptUtils.extractRecentTopics()`（`:411`）取近 8 天 `daily_lesson_plans`，抽出 `recentVocabWords` / `recentWritingChars` / `recentThemeTitles` / `recentMathDescriptions` 四个去重数组，`PLANNER_SYSTEM_PROMPT`（`:28`）第 3.5 条写"vocab[].word 严禁重复" | 只覆盖**计划词**；窗口固定 7 天（`LessonPlanningService.ets:551`）；跨 7 天后失效；不含掌握度 |
| 出题 | `english_quiz` / `listening_quiz` / `picture_vocab` / `matching_pairs` / `chinese_quiz` / `pinyin_quiz` 在会话里由 LLM 即兴生成（`ToolExecutionService.ets:793` 起等 10 个 handler） | **完全不走备课链路，绕过了唯一的去重机制** |
| 约束 | Prompt 软约束 + `validatePlannerOutput` 只校验结构与数量 | 没有"重复度"硬门禁；LLM 温度 0.6 可无视 3.5 条 |

**一句话根因：** 去重作用在"计划"上，用户感受到的重复来自"题目"上，两者互不连通；且缺少词级状态，"7 天禁出"既无法科学复习、也无法跨窗口去重。

### 1.3 核心设计判断

**同一词换题型复现 = 有效巩固；同一词同题型高频复现 = 刷屏。**

因此不能简单"学过就不再出"。本方案引入**曝光状态（exposure）+ 掌握度（mastery）+ 冷却窗口（cooldown）+ 换维度复现**四要素，同时满足"重复出题巩固"与"不出现很多次"两个目标。

---

## 2. 目标与非目标

### 2.1 目标

1. 建立跨英语 / 语文统一的**词级台账**，记录每个学习项的出现次数、对错、掌握度、下次复习时间。
2. 会话内**即兴出题**与**备课计划**两条链路都写入台账，消除唯一漏洞。
3. 出题从"无状态即兴"变为**三名单选词**：新词池 / 待复习池 / 冷却禁出名册。
4. 引入**间隔重复（Leitner）**与**冷却窗口**，把"7 天一刀切"升级为"按掌握度科学复现"。
5. 把台账摘要**动态注入**小星老师与备课老师的 prompt；并在出题工具层加**硬门禁**兜底。
6. 提供**可观测性**：近 7 天高频词、已掌握词数、重复率，供家长页与调试。

### 2.2 非目标

- 不做跨设备同步（沿用本地 SQLite；未来随 WebDAV 备份一体处理）。
- 不替换 `child_profile` 的技能等级体系，两者并存：台账记"具体词"，profile 记"能力等级"。
- 不在本轮引入 SM-2 等复杂算法，先用可解释的 Leitner 箱位。
- 不改变现有卡片 UI 与授星逻辑。

---

## 3. 术语与归一化

### 3.1 学习项（learning item）

统一抽象的最小学习单位，由 `item_key` 唯一标识：

```
item_key = <subject>:<item_type>:<normalized>
```

| subject | item_type | 归一化规则 | 示例 |
|---|---|---|---|
| `en` | `vocab` | 小写、去首尾空格、去标点 | `en:vocab:apple` |
| `en` | `sentence` | 小写、按词切分、以 `\|` 连接 | `en:sentence:i\|like\|apples` |
| `zh` | `char` | 单字原样 | `zh:char:山` |
| `zh` | `phrase` | 词/词组原样 | `zh:phrase:火车` |
| `zh` | `pinyin` | 小写、声调数字化（`shān`→`shan1`） | `zh:pinyin:shan1` |

> 归一化必须放在**唯一一处** `normalizeItemKey()` 纯函数中，供写入侧与校验侧共用，避免两套规则漂移。

### 3.2 掌握度与间隔

Leitner 箱位 `mastery ∈ [0,5]`，对应复习间隔：

| mastery | 含义 | 间隔 |
|---|---|---|
| 0 | 未接触 / 新词 | 当天 |
| 1 | 入门 | 1 天 |
| 2 | 初步 | 2 天 |
| 3 | 中等 | 4 天 |
| 4 | 良好 | 7 天 |
| 5 | 精通（进入抽检） | 15 天，之后 30 天抽检 |

---

## 4. 数据模型

### 4.1 新表 DDL（追加到 `DatabaseService.createTables` 末尾）

**`learning_items`**（一行 = 一个学习项的当前状态）：

```sql
CREATE TABLE IF NOT EXISTS learning_items (
  item_key            TEXT PRIMARY KEY,          -- en:vocab:apple
  subject             TEXT NOT NULL,             -- en | zh
  item_type           TEXT NOT NULL,             -- vocab | sentence | char | phrase | pinyin
  display             TEXT NOT NULL,             -- 原始展示文本 (apple / 山 / shān)
  skill_key           TEXT DEFAULT '',           -- english_vocab / chinese_vocab / pinyin ...
  first_taught_at     INTEGER NOT NULL,          -- 首次出现时间
  last_seen_at        INTEGER NOT NULL,          -- 最近一次出题时间
  exposure_count      INTEGER NOT NULL DEFAULT 0,-- 累计出题次数
  correct_count       INTEGER NOT NULL DEFAULT 0,
  wrong_count         INTEGER NOT NULL DEFAULT 0,
  mastery             INTEGER NOT NULL DEFAULT 0,-- Leitner 箱位 0-5
  consecutive_correct INTEGER NOT NULL DEFAULT 0,-- 连续答对次数
  modes_seen_json     TEXT DEFAULT '[]',         -- 已用过的题型集合
  last_mode           TEXT DEFAULT '',           -- 最近一次题型
  last_session_id     TEXT DEFAULT '',
  next_review_at      INTEGER NOT NULL DEFAULT 0,-- 到期复习时间 (0=立即)
  mastered_at         INTEGER NOT NULL DEFAULT 0,-- 进入 mastery=5 的时间
  source              TEXT DEFAULT 'session',    -- plan | session | seed
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_li_subject   ON learning_items(subject);
CREATE INDEX IF NOT EXISTS idx_li_next_rev  ON learning_items(next_review_at);
CREATE INDEX IF NOT EXISTS idx_li_mastery   ON learning_items(mastery);
CREATE INDEX IF NOT EXISTS idx_li_last_seen ON learning_items(last_seen_at DESC);
```

**`learning_item_events`**（append-only 曝光流水，P1；支撑滑动窗口冷却统计与"近 7 天高频词"报告）：

```sql
CREATE TABLE IF NOT EXISTS learning_item_events (
  id           TEXT PRIMARY KEY,          -- 'lie_<ts>_<rand>'
  item_key     TEXT NOT NULL,
  session_id   TEXT DEFAULT '',
  mode         TEXT DEFAULT '',           -- listen_choice / picture_word / ...
  tool_id      TEXT DEFAULT '',           -- english_quiz / chinese_quiz / ...
  served_at    INTEGER NOT NULL,          -- 出题时间
  answered_at  INTEGER DEFAULT 0,         -- 作答时间 (0=未答)
  is_correct   INTEGER DEFAULT -1,        -- 1 / 0 / -1(未答)
  FOREIGN KEY (item_key) REFERENCES learning_items(item_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_lie_item    ON learning_item_events(item_key, served_at DESC);
CREATE INDEX IF NOT EXISTS idx_lie_served  ON learning_item_events(served_at DESC);
CREATE INDEX IF NOT EXISTS idx_lie_session ON learning_item_events(session_id);
```

### 4.2 `TableNames` 增量

```ts
// DatabaseService.ets:104 class TableNames 内追加
static readonly LEARNING_ITEMS: string = 'learning_items'
static readonly LEARNING_ITEM_EVENTS: string = 'learning_item_events'
```

### 4.3 迁移

两张表均为**新增**，`CREATE TABLE IF NOT EXISTS` 即可，无需 `ALTER`。事件表与主表通过 `item_key` 外键关联；`createTables` 中的建表顺序需保证 `learning_items` 先于 `learning_item_events`。若旧库外键约束不可用，降级为逻辑关联（不做级联删除，改为写库侧显式清理）。

### 4.4 数据模型类

```ts
// models/LearningLedgerModels.ets (新增)
export class LearningItem {
  itemKey: string = ''
  subject: string = ''
  itemType: string = ''
  display: string = ''
  skillKey: string = ''
  firstTaughtAt: number = 0
  lastSeenAt: number = 0
  exposureCount: number = 0
  correctCount: number = 0
  wrongCount: number = 0
  mastery: number = 0
  consecutiveCorrect: number = 0
  modesSeen: string[] = []
  lastMode: string = ''
  lastSessionId: string = ''
  nextReviewAt: number = 0
  masteredAt: number = 0
  source: string = 'session'
  createdAt: number = 0
  updatedAt: number = 0
}

/** 注入 prompt / 供校验的台账摘要 */
export class LedgerSummary {
  newPool: string[] = []       // 新词池 (display)
  dueReview: DueReviewHint[] = []  // 待复习: {display, lastMode, dueIn}
  mastered: string[] = []      // 已掌握·勿再当新词
  cooling: string[] = []       // 冷却中·本轮勿出
  topRepeated: RepeatStat[] = []   // 近 7 天高频 (display, count)
}
```

---

## 5. 服务层：`LearningLedgerService`

新增 `services/LearningLedgerService.ets`，单例 + `ServiceRegistry.learningLedger()` 门面，与 `LessonPlanningService` 同构。

### 5.1 写入 API

```ts
/** 出题时登记一次曝光（幂等：同 session 同 item 同 mode 短时内不重复计数） */
async recordServed(input: LedgerRecord): Promise<void>

/** 作答后更新对错与掌握度、推进 next_review_at */
async recordAnswer(itemKey: string, isCorrect: boolean, now: number): Promise<void>

/** 备课计划落库后批量登记 (source=plan, 不改变掌握度, 只建立台账行) */
async upsertPlanItems(items: LedgerItemSeed[], now: number): Promise<void>
```

`LedgerRecord`：`{ itemKey, subject, itemType, display, skillKey, mode, toolId, sessionId, now }`

### 5.2 读取 API

```ts
/** 三名单 + 高频统计，供 prompt 渲染与硬门禁查询 */
async buildSummary(subject: string, now: number, opts?: LedgerQueryOptions): Promise<LedgerSummary>

/** 硬门禁：返回该 item 是否处于冷却/禁出状态及原因 */
async checkRepeat(itemKey: string, mode: string, purpose: string, now: number): Promise<RepeatCheck>

/** 家长页 / 调试：近 7 天高频词 top N */
async getTopRepeated(subject: string, sinceMs: number, limit: number): Promise<RepeatStat[]>
```

### 5.3 掌握度状态机

```
recordAnswer(itemKey, isCorrect):
  if isCorrect:
    consecutiveCorrect += 1
    if consecutiveCorrect >= 2 && mastery < 5:
      mastery += 1
    nextReviewAt = now + INTERVAL[mastery]
    if mastery == 5: masteredAt = now (若尚未设置)
  else:
    consecutiveCorrect = 0
    mastery = max(0, mastery - 1)
    nextReviewAt = now + INTERVAL[mastery]   // 答错 → 提前复习
  exposureCount += 1 (在 recordServed 时累加, 此处不重复)
```

> `recordServed` 累加 `exposureCount` / 更新 `lastSeenAt` / `lastMode` / `modesSeen`；`recordAnswer` 只动对错与掌握度。

---

## 6. 写入点（两条链路，缺一不可）

### 6.1 计划侧（`source=plan`）

`LessonPlanningService.runPlanningPipeline` 在 plan 成功持久化后（无论 LLM 产物或 baseline，约 `:629` 之后、`prefetchImages` 之前）调用：

```
learningLedger.upsertPlanItems(extractLedgerSeeds(plan), now)
```

`extractLedgerSeeds`：遍历 `plan.vocab[].word`（→ `en:vocab`）、`plan.writing[].characterOrWord`（按字符集判定 `zh:char` / `en:vocab`）生成种子。**只建行、不改掌握度**（计划是"打算教"，曝光以真实出题为准）。

### 6.2 会话侧（`source=session`，关键缺口）

在 `ToolExecutionService` 的 quiz handler 中，于**题目成功进入 pending 态之后、等待作答之前**登记 `recordServed`；在收到 `answerJson` 后登记 `recordAnswer`。需改造的 handler：

| tool | handler 行号 | 目标项提取规则 |
|---|---|---|
| `english_quiz` | `:793` | 目标词统一取 `correct_answer`（六 mode 皆然；legacy `word`/`sentence` 同）；题目音源：`listen_choice`→`tts_text`，`read_aloud`→`target_text` |
| `picture_vocab` | `:977` | `correct_answer`（`mode=en` 英文词 / `mode=zh` 汉字） |
| `listening_quiz` | `:1100` | `word`（被 TTS 朗读的词/字母；`correct_answer` 为选项答案） |
| `pinyin_quiz` | `:1191` | `character`（被考汉字，字典内单字）+ `correct_answer`（带调拼音，作 `display`） |
| `hanzi_card` | `:1282` | `character`（讲解也计曝光，mastery 不变） |
| `pinyin_card` | `:1372` | `syllable`（带调音节） |
| `picture_talk` | `:1462` | 记为 `zh:sentence`（可选，P1） |
| `chinese_quiz` | `:1580` | 按 mode：`word_build`→`answer`（组词，另记 `character`）；`sentence_order`→`answer`（正确句）；`lookalike`→`answer`（填空单字）；`antonym`→`character`（被考字） |
| `matching_pairs` | `:2037` | 配对左列所有项（多个 key） |
| `handwriting_practice` | `:2127` | `character`（中文字；练写也计曝光） |

> 提取逻辑集中为一个纯函数表 `extractLedgerItemsFromTool(toolName, args)`，置于 `utils/LedgerExtractUtils.ets`，handler 只调用不内联，便于单测与新增题型扩展。写入必须 **try/catch 静默**，台账失败绝不阻断出题。

---

## 7. 三名单选词

`buildSummary(subject, now)` 从 `learning_items` 派生：

| 名单 | 谓词 | 用途 |
|---|---|---|
| **新词池** `newPool` | 不存在于台账（候选由词库/主题提供）或 `mastery ≤ 1` | 保证有新知 |
| **待复习池** `dueReview` | `next_review_at ≤ now` 且 `mastery ∈ [2,4]` | 遗忘曲线巩固 |
| **冷却禁出** `cooling` | `last_seen_at > now - SAME_MODE_COOLDOWN`，或 `mastery == 5 且 now < next_review_at` | 防刷屏 |

选词配比（注入 prompt 的建议节奏，非硬约束）：一节课 `新词 : 复习 ≈ 6 : 4`，同一 theme 内保留 2–3 个核心词反复复现（沿用英语/语文 v2 的"核心词复现"原则）。

### 7.1 冷却与批次规则

| 常量 | 默认值 | 说明 |
|---|---|---|
| `SAME_MODE_COOLDOWN_MS` | 30 分钟 | 同词同题型冷却 |
| `SESSION_GAP_ITEMS` | 5 题 | 同一会话内同词至少间隔 5 题（内存环形缓冲） |
| `BATCH_MAX_PER_ITEM` | 1（同 mode）/ 2（不同 mode） | 单轮同词上限 |
| `MASTERED_RECHECK_MS` | 30 天 | 已掌握词抽检周期 |

会话内滑动窗口用 `RecentServedWindow`（每 session 一个容量 20 的 LRU，存 `item_key + mode + servedAt`），随会话销毁；跨会话用 `learning_item_events` 表（P1）。

---

## 8. Prompt 注入（运行时软约束）

### 8.1 小星老师侧

在 `ChatViewModel.injectTeachingSections`（`:341`）现有 4 段之后追加第 5 段（`renderVocabLedgerSection`），仅在 `assistantId === DEFAULT_ASSISTANT_ID` 生效：

```text
【词汇台账】
- 已掌握(勿当新词考,只在复习轮抽检): apple, cat, red
- 今日新词: banana, dog, bus
- 待复习(请换题型巩固): banana(上次听音) / dog(上次拼写)
- 冷却中(本轮勿出): apple
出题规则: 新词优先;复习词必须换一种题型复现,不要同一题型连出同一词;
同一词一节课最多出现 2 次(不同题型),不要连续 5 题内重复。
```

渲染函数 `renderVocabLedgerSection(summary)` 放入 `LessonPlanPromptUtils.ets`（与 `renderDailyPlanSection` 同文件），复用现有 section 拼接机制。

### 8.2 备课老师侧

扩展备课输入：在 `runPlanningPipeline` 的 `userInput`（`:573`）中，与 `recentTopics` **并列**新增 `ledger`：

```ts
ledger: {
  newCandidates: string[],   // 台账未掌握 + 建议主题词
  dueReview: string[],       // 到期复习词
  mastered: string[],        // 已掌握
  cooling: string[]          // 冷却中
}
```

`PLANNER_SYSTEM_PROMPT` 第 3.5 条改写为：

```text
3.5 避免重复。输入 JSON 的 ledger 字段给出词级状态,硬约束:
    - vocab[].word 严禁出现在 ledger.mastered 或 ledger.cooling 中
    - 已掌握词最多 1 个仅作"复习轮"出现,且必须换一种题型
    - 优先从 ledger.newCandidates / ledger.dueReview 中选词
    - recentTopics 仍保留,作为主题类别轮换之用 (不再单靠 7 天窗口)
```

> `recentTopics` 保留兼容，但去重的权威来源从"近 7 天计划词"迁移到"台账"，解决跨 7 天失效问题。

---

## 9. 出题硬门禁（兜底）

在现有预校验体系（`{error, should_retry:true}` 范式）之上新增一层"重复度校验"：

- 新增 `utils/VocabRepeatValidation.ets`，导出 `checkItemRepeat(itemKey, mode, purpose, summary): RepeatCheck`。
- 各工具 schema 增加**可选**字段 `purpose: "new" | "review"`（缺省视为 `new`）；LLM 复现旧词时应显式传 `review`。
- 命中冷却且 `purpose !== "review"` → 校验失败，返回：

```json
{ "error": "repeat_blocked",
  "message": "该词近期已多次出现,请换词或换题型;若确实要复习请传 purpose:\"review\"",
  "should_retry": true }
```

- 接入点：`handleEnglishQuiz`（`:807` 现校验之后）、`handleListeningQuiz`、`handleChineseQuiz`、`handlePinyinQuiz`、`handlePictureVocab`，紧邻现有 `validateXxxArgs` 调用。
- 门禁只读 `buildSummary` 的轻量缓存（近 N 分钟内复用），避免每题查库。

---

## 10. 降级路径

| 场景 | 降级行为 |
|---|---|
| 台账库不可用 / 建表失败 | `checkRepeat` 返回 `allow`，`recordServed/Answer` no-op；**永不阻断教学** |
| 台账为空（首次使用） | `newPool` 由词库兜底，`dueReview/cooling/mastered` 为空，prompt 段自动省略 |
| 无到期复习词 | 全部走新词池 |
| 新词池枯竭（词库耗尽且均已掌握） | 退回"已掌握词抽检"，间隔按 `MASTERED_RECHECK_MS` |
| LLM 未传 `purpose` | 视为 `new`；命中冷却则门禁拦截并提示换词 |
| 题干目标项提取失败（未知 mode） | 记为 `unknown`，跳过台账写入与门禁，只打 warn |
| 事件表写入失败 | 主表状态仍更新；下次 `buildSummary` 用 `last_seen_at` 近似 |
| 同 item 并发写（多会话） | `item_key` 主键 + 读改写合并；冲突时以 `last_seen_at` 较新者为准 |

---

## 11. 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 台账 vs 扩 profile | 独立 `learning_items` 表 | profile 是"能力等级"，台账是"具体词状态"，混用会污染现有 28 维读写契约 |
| 写入策略 | 出题时写 `recordServed`，作答时写 `recordAnswer` | 覆盖"出了但没答"的曝光；掌握度只由真实作答驱动 |
| 计划侧是否改掌握度 | 不改，只建行 | 计划是"打算教"，不等于"考过" |
| 去重权威源 | 台账（mastery 驱动） | 解决"7 天窗口"跨天失效问题 |
| 复现策略 | 同词换题型放行，同题型冷却 | 区分"巩固"与"刷屏"；保留教学性重复 |
| 门禁位置 | 预校验层（软 Prompt + 硬校验双保险） | 与现有 `should_retry` 体系一致，LLM 可自纠 |
| 算法 | Leitner 箱位（非 SM-2） | 可解释、易调参、够用 |
| 事件表粒度 | 追加式流水 | 支撑滑动窗口与家长报告；主表状态可由此重建 |
| 归一化 | 单一 `normalizeItemKey` 纯函数 | 写入/校验/门禁共用，避免规则漂移 |

---

## 12. 关键文件触点

| 路径 | 改动 |
|---|---|
| `models/LearningLedgerModels.ets` | **新增**：`LearningItem` / `LedgerSummary` / `RepeatCheck` / `LedgerRecord` + 序列化 |
| `services/LearningLedgerService.ets` | **新增**：核心服务（写入/读取/掌握度状态机/高频统计） |
| `services/DatabaseService.ets` | `TableNames` 加 2 项；`createTables` 加 2 张表 + 索引；CRUD（upsert/查询/聚合） |
| `services/ServiceRegistry.ets` | 新增 `learningLedger()` 门面 |
| `entryability/EntryAbility.ets` | `initializeServices` 末尾初始化 ledger 服务 |
| `utils/LedgerExtractUtils.ets` | **新增**：`extractLedgerItemsFromTool` / `extractLedgerSeeds` / `normalizeItemKey` |
| `utils/LessonPlanPromptUtils.ets` | `renderVocabLedgerSection` 新增；`PLANNER_SYSTEM_PROMPT` 3.5 改写；`RecentTopicsSummary` 保留 |
| `services/LessonPlanningService.ets` | pipeline 写入 seeds；`userInput` 注入 `ledger` |
| `viewmodels/ChatViewModel.ets` | `injectTeachingSections` 追加台账段 |
| `utils/VocabRepeatValidation.ets` | **新增**：`checkItemRepeat` |
| `services/ToolExecutionService.ets` | 10 个 handler 接入 `recordServed/Answer`；5 个接入硬门禁；`purpose` 透传 |
| `config/BuiltinTools.ets` | 相关工具 schema 增加 `purpose` 可选字段 |
| `pages/LearningProfilePage.ets` | 家长页新增"近 7 天高频词 / 已掌握词数"区块（P2） |

---

## 13. 分 PR 实施计划

| PR | 内容 | 依赖 | 状态 |
|---|---|---|---|
| PR 1 数据层 | `LearningLedgerModels` + 2 张表 + 索引 + CRUD + `TableNames` | — | ⏳ |
| PR 2 服务核心 | `LearningLedgerService` + `LedgerExtractUtils` + `ServiceRegistry` + `EntryAbility` 初始化 | PR1 | ⏳ |
| PR 3 会话写入 | 10 个 handler 接入 `recordServed/Answer`（静默 try/catch） | PR2 | ⏳ |
| PR 4 Prompt 注入 | 小星台账段 + 备课 `ledger` 字段 + 3.5 改写 + 高亮渲染 | PR2 | ⏳ |
| PR 5 硬门禁 | `VocabRepeatValidation` + `purpose` 字段 + 5 个 handler 接入 | PR3 | ⏳ |
| PR 6 间隔重复 + 观测 | 事件表滑动窗口 + `getTopRepeated` + 家长页区块 + 日志 | PR3 | ⏳ |

**P0（PR1–PR3）：** 立刻堵住"即兴出题绕过台账"的最大漏洞。
**P1（PR4–PR5）：** 把"7 天一刀切"升级为"按掌握度科学复现" + 硬兜底。
**P2（PR6）：** 可观测、可调参。

---

## 14. 验收

1. **词级可追溯**：连续做 5 道含 `apple` 的题后，`learning_items['en:vocab:apple'].exposureCount == 5`，`lastSeenAt` 为最近一次。
2. **会话链路生效**：即使不经过备课计划，纯对话中出题也会写入台账（后台查库验证）。
3. **冷却生效**：`apple` 冷却期内再次出 `picture_word` 题，预校验返回 `repeat_blocked` / `should_retry`。
4. **换题型放行**：`apple` 换 `listen_choice` 或 `sentence_fill` 复现（`purpose:"review"`）允许通过，`modesSeen` 增加。
5. **间隔推进**：连续答对 2 次后 `mastery` 上升、`nextReviewAt` 按 `INTERVAL` 前移；答错回落并提前复习。
6. **Prompt 注入**：小星老师 system prompt 出现"词汇台账"段；备课输入出现 `ledger` 字段。
7. **已掌握抽检**：`mastery=5` 的词在 30 天内不再作为新词出现，到期进入抽检。
8. **双科统一**：语文汉字 / 拼音与英语词共用同一张表与同一套冷却逻辑（`subject` 区分）。
9. **不回归**：台账不可用时出题、授星、备课全部行为与现状一致；英语 / 语文 / 数学助手互不影响。
10. **首次使用**：台账为空时流程正常，不出现空段或异常。

---

## 15. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 台账写入阻塞出题 | 全部写入 try/catch 静默 + 异步；门禁只读轻量缓存 |
| 门禁误伤教学性重复 | `purpose:"review"` 放行；冷却只针对同题型+短窗口 |
| 词库耗尽导致新词池枯竭 | 退回已掌握词抽检；prompt 提示降低新词比例 |
| 归一化不一致致漏记 | 单一 `normalizeItemKey`，写入/校验/门禁三处共用 |
| 台账表膨胀 | 单行 < 300B；事件表按月可归档；主表仅保留有状态的项 |
| LLM 仍不遵 prompt | 硬门禁兜底，最多一次 `should_retry` 即换词 |
| 事件表与主表状态漂移 | 主表为权威；事件表仅作统计，可定期由事件重算校验 |
| 多会话并发写冲突 | 主键 + 读改写合并；以 `lastSeenAt` 较新为准 |
| 时区变化 | 全部用本地时区毫秒时间戳，与 `daily_lesson_plans` 一致 |

---

## 16. 指标与监控

| 指标 | 定义 | 目标 |
|---|---|---|
| 重复率 | 窗口内 `exposureCount > 3` 的出题占比 | 下降 |
| 去重广度 | 近 7 天 distinct `item_key` 数 | 上升 |
| 复习命中 | `dueReview` 实际被出题次数 / 到期数 | 60%–80% |
| 掌握进度 | `mastery == 5` 的词数 | 稳步上升 |
| 门禁触发 | `repeat_blocked` 次数 / 总出题 | 早期偏高、随 prompt 学习下降 |

调试日志：`Ledger stats: subject=xx, new=N, due=N, cooling=N, mastered=N, topRepeat=[...]`。

---

## 附录 A：默认参数一览

```
SAME_MODE_COOLDOWN_MS   = 30 * 60 * 1000
SESSION_GAP_ITEMS       = 5
BATCH_MAX_PER_ITEM      = 1 (同 mode) / 2 (不同 mode)
INTERVAL_DAYS           = [0, 1, 2, 4, 7, 15]      // mastery 0..5
MASTERED_RECHECK_MS     = 30 * 24 * 60 * 60 * 1000
NEW_REVIEW_RATIO        = 6 : 4
TOP_REPEATED_WINDOW_DAYS= 7
```

## 附录 B：新增的 skill_key 映射（写入台账 `skill_key`）

| item_type | 默认 skill_key |
|---|---|
| `en:vocab` | `english_vocab` |
| `en:sentence` | `english_sentence` |
| `zh:char` / `zh:phrase` | `chinese_vocab` |
| `zh:pinyin` | `pinyin` |
| `zh:sentence` | `chinese_reading` |

---

## 附录 C：变更记录

**v1.1（2026-09-30）** — 对照 `entry/src/main/ets` 只读代码逐条核对，修正 §6.2 目标项字段提取规则（此前为推测，与实际校验器不符）：

- `english_quiz`：`sentence_fill` 的目标词实际字段是 `correct_answer`（不是 `answer`）；`word` 是 legacy `question_type` 取值，不是字段名。六 mode 目标统一取 `correct_answer`，音源字段为 `tts_text` / `target_text`。来源：`utils/EnglishQuizValidation.ets:94-350`。
- `picture_vocab`：目标字段是 `correct_answer`（不是 `answer`），`mode ∈ {en, zh}` 决定中英文。来源：`utils/PictureVocabValidation.ets:42-51`。
- `listening_quiz`：朗读字段是 `word`；`correct_answer` 是选项答案。来源：`utils/ListeningQuizValidation.ets:42-55`。
- `pinyin_quiz`：考查字为 `character`，`correct_answer` 为其带调拼音（须等于 `PinyinData` 字典读音）。来源：`utils/PinyinQuizValidation.ets:46-64`。
- `chinese_quiz`：`word_build` 目标为 `answer`（另含 `character`），`antonym` 目标为 `character`，其余 mode 为 `answer`；无 `target` 字段。来源：`utils/ChineseQuizValidation.ets:96-204`。

其余行号断言（`ToolExecutionService.ets:793/977/1100/1191/1282/1372/1462/1580/2037/2127`、`LessonPlanPromptUtils.ets:28/411`、`LessonPlanningService.ets:551/573`、`ChatViewModel.ets:341`、`DatabaseService.ets:104`）经复核与代码一致。`ChildProfileService.ets:44-73` 现为 28 个技能维度，与本文档一致（旧文档"26 维"表述已过时）。
