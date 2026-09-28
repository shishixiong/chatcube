# 小星老师教学体系架构

**日期：** 2026-09-15
**版本：** v2
**范围：** chatcube 项目内 "小星老师" 默认助手 + 4 个学科专用助手的整体教学架构——AI 助手、教学工具、教学数据三者如何协作
**状态：** 取代仓库根 `teacher.md`（已过期，使用"小鹿老师"并引用不存在的 `update_progress` 工具）。代码内一律使用"小星老师"。

> **v2 变更（2026-09-15）**：儿童主屏 v2 重设计落地——新增 4 个学科专用助手（`kids_math` / `kids_english` / `kids_chinese` / `kids_games`，见 §2.1），内置助手锁定改为注册表驱动（`getBuiltInAssistantSpec`，覆盖全部 5 个内置助手），`DatabaseService.ensureKidsSubjectAssistants()` 启动幂等补建，儿童主屏放行谓词扩到 `KIDS_BUILT_IN_ASSISTANT_IDS`。同步修正若干过期的代码行号/方法名引用（`injectDailyPlanSections` → `injectTeachingSections`；小星老师提示词已经 `SharedPromptFragments` 重构；`ask_user` 已并入锁定白名单）。备课老师管线（§7）本次**未动**。设计 spec：`docs/superpowers/specs/2026-09-15-kids-home-v2-redesign-design.md`。

---

## 1. 总览

教学体系分三层：**教学策略**（AI 助手 + 系统提示词；v2 起为 1 个全科小星老师 + 4 个学科专用助手）→ **教学工具**（AI 调用的 19 个锁定工具 + 13 张互动卡片，学科助手各锁子集）→ **教学数据**（孩子画像 26 维技能 + 每日备课 + 星星奖励）。这三层通过 `ChatViewModel` 串成闭环：会话开始时注入今日教学目标（仅小星老师），AI 据孩子表现出题并更新画像，小星老师会话结束后 5 分钟防抖触发"备课老师"自动生成次日计划。

---

## 2. 助手身份：5 个内置助手

### 2.0 默认助手：小星老师

| 字段 | 值 | 位置 |
|------|------|------|
| ID | `default` | `models/AssistantModels.ets:26`（`DEFAULT_ASSISTANT_ID`） |
| 名称 | `小星老师` | `createDefaultAssistant()` / `getBuiltInAssistantSpec('default')` |
| 头像 | `⭐` | 同上 |
| 主题色 | `#FF9F43` | 同上 |
| `isDefault` | `true` | `Assistant` 构造函数按 id 判定 |
| `sortOrder` | `0` | `createDefaultAssistant()` |
| 系统提示词 | `DEFAULT_ASSISTANT_SYSTEM_PROMPT`（经 `utils/SharedPromptFragments.ets` 共享片段拼装，~60 行） | `models/AssistantModels.ets:32-95` |
| 锁定工具 | 19 个（见 §4） | `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` |

**锁定语义（v2 · 注册表驱动）**：`services/AssistantService.ets` 的 `normalizeAssistant()` 对**全部 5 个内置助手**（default + 4 学科）经 `getBuiltInAssistantSpec(id)`（`models/AssistantModels.ets:418`）查注册表，命中即强制覆盖 `name` / `systemPrompt` / `enabledToolIds`（取 `lockedToolIds` 副本）——用户在前端编辑时无法修改内置助手的名称、提示词与工具白名单。非内置 id 返回 `null`，仅做 trim/兜底规整。

**生命周期与保护**：
- `DatabaseService.ensureKidsSubjectAssistants()`（`services/DatabaseService.ets:1294`，紧随 `ensureDefaultAssistant()` 在 createTables 流程中调用）幂等补建缺失的学科助手——老用户升级自动补齐。
- `AssistantService.deleteAssistant()` 对 `KIDS_BUILT_IN_ASSISTANT_IDS` 成员直接返回 false（不可删除）。
- Index 助手编辑 UI 的 `editingAssistantIsDefault` 保护已放宽为 `KIDS_BUILT_IN_ASSISTANT_IDS.includes(...)`，5 个内置助手的名称/提示词/工具编辑同样被锁定。

### 2.1 四个学科专用助手（2026-09-15 新增）

| ID | 名称 | avatarSymbol | color | 锁定工具子集 | sortOrder |
|----|------|--------------|-------|--------------|-----------|
| `kids_math` | 小星数学老师 | 数 | #4E8FE0 | ask_user, child_profile, get_time_info, grant_star, math_verify, math_quiz, vertical_math, math_teach, matching_pairs | 1 |
| `kids_english` | 小星英语老师 | 英 | #35A98A | ask_user, child_profile, get_time_info, grant_star, english_quiz, picture_vocab, listening_quiz | 2 |
| `kids_chinese` | 小星语文老师 | 语 | #E2603C | ask_user, child_profile, get_time_info, grant_star, pinyin_quiz, handwriting_practice | 3 |
| `kids_games` | 小星游戏老师 | 玩 | #8B72E0 | ask_user, child_profile, get_time_info, grant_star, number_puzzle, maze, sudoku, matching_pairs, categorization | 4 |

- 定义：`models/AssistantModels.ets` 的 `KIDS_SUBJECT_SPECS`（行 374-411）+ `createKidsSubjectAssistants()`（行 439）。系统提示词与小星老师同源（共用 `SharedPromptFragments.buildBasePrompt`），按学科裁剪；每科提示词约束 `child_profile(action:"update")` 只更新本学科维度。
- **不含** `image_generation` / `music_generation`（学科助手不出图不出乐）。
- 生命周期：`DatabaseService.ensureKidsSubjectAssistants()` 启动幂等补建（老用户升级自动补齐）。
- 锁定：`AssistantService.normalizeAssistant` 经 `getBuiltInAssistantSpec(id)` 注册表强制覆盖 5 个内置助手的 name/systemPrompt/enabledToolIds；`deleteAssistant` 对 `KIDS_BUILT_IN_ASSISTANT_IDS` 成员返回 false；Index 助手编辑器 `editingAssistantIsDefault` 保护同样覆盖 5 个。
- **不进备课管线**：`notifySessionEnd` 仅接受 `default`（现有过滤未动，`LessonPlanningService.ets:266`）；`injectTeachingSections` 的教学段不注入学科助手会话（`ChatViewModel.buildRequestSystemPrompt` 对非 default 助手提前 return）。
- 星星记录/孩子画像照常（child_profile 在锁定子集内，提示词约束只更新本学科维度）。
- 儿童主屏会话放行：`Index.isKidsAllowedSessionId` 用 `KIDS_BUILT_IN_ASSISTANT_IDS.includes(...)`（5 个助手会话都对儿童可见；`''` 遗留会话仍拦截）。

### 2.2 儿童主屏触点（kids home v2）

- `components/kids/KidsHomeView.ets`：三段式（问候行 → 「继续学习」hero → 2×2 学科卡 → 按天分组学习乐园）。hero 一天一会话：`utils/KidsSubjectUtils.findTodaySession` 命中今日会话则显示"继续"，否则开新会话。
- `components/kids/KidsHomeView.ets`：三段式（问候行 → 「继续学习」hero → 2×2 学科卡 → 按天分组学习乐园）。hero 一天一会话：`utils/KidsSubjectUtils.findTodaySession` 命中今日会话则显示"继续"，否则开新会话。
- 学科卡数据源：`components/kids/KidsSubjectCatalog.ets`（4 科目录，含 startPrompt / assistantId / 图标路径 / 色令牌）。**学科会话同为一天一会话**（2026-09-25 起，按学科 assistantId 过滤后复用 `findTodaySession`，`KidsHomeView.todaySessionFor`）：命中今日会话 → `onOpenSession` 续接（CTA 显示「继续 ›」），否则 `Index.handleKidsNewChat(item.startPrompt, item.assistantId)` 开新会话。`startPrompt` **不再作为孩子消息自动发送**——新会话时由 `ChatPage.autoGreetSubjectAssistant` 经 `GreetingUtils.buildSubjectGreetingHint` 转成开场元指令走 `sendAutoGreet` 通道（无孩子气泡），**学科老师先开口打招呼**；per-day 粒度由一天一会话保证，不读写 `LAST_GREET_DATE`（与 hero 招呼互不干扰）。达 `dailyLimit` 上限仍整卡禁用（含进入会话）。前提：`ChatViewModel.buildRequestSystemPrompt` 对非 default 助手也拼 `greetingHint`（仅招呼元指令，不注入教学段）。
- 学科卡「今日 N 题」计数按 `star_events.activityType` 映射到学科（`utils/KidsSubjectUtils.countTodayBySubject`），**不按会话 assistantId**——`chat_correct` 不计入任何学科。
- 学习乐园：`KidsDayGroupCard.ets` 按天分组（`groupSessionsByDay`，同日超 3 条折叠），每日星数来自 `DatabaseService.getStarTotalsByDay(sinceMs)`；今日星星明细 → `KidsStarDetailSheet.ets`（`buildTodayCategoryRows` / `buildTodayEventRows`）。
- 家长门：`ParentalGateSheet.ets` 两阶段——算术验证门（`phase='gate'`）答对进今日概览（`phase='summary'`，可进家长设置或返回主屏）；关闭重开需重新验证。
- 品牌令牌：`KidsBrandTokens.ets`（`KIDS_SUBTLE=#746E64`、8 个学科色令牌 `KIDS_MATH/_INK` 等）；8 个 monoline SVG 图标在 `resources/rawfile/kids/`（star/math/english/chinese/games/lock/chevron/close，颜色 baked-in）。视觉契约见 `docs/brand-spec.md`。
- 已删除的 v1 组件：`KidsActivityCatalog.ets` / `KidsSessionCard.ets`（2026-09-15，无残留 import）。

**系统提示词覆盖的教学领域**（小星老师 default；行号已随 SharedPromptFragments 重构失效，按段落标题定位）：

1. **说话方式**：1-3 句、≤50 字、禁 emoji、禁 markdown（`SharedPromptFragments.buildBasePrompt`）
2. **教学策略**：每轮开始调 `child_profile(action:"read")`；有真凭实据才 `update`
3. **数学**：10 维目标（`math_counting/number_sense/addition/subtraction/multiply/divide/shapes/comparison/time/word_problem`）
4. **英语**：4 维目标（`alphabet/vocab/sentence/phonics`）
5. **常识**：3 维目标（`general_nature/social/life`）
6. **益智**：3 维目标（`logic_thinking/observation/spatial_reasoning`）
7. **学写字**：3 维目标（`fine_motor/english_writing/chinese_writing`）
8. **分类小管家**：1 维目标（`categorization`），2-3 桶 4-9 项

> **过期提示**：仓库根的 `teacher.md` 写的是"小鹿老师" + 不存在的 `update_progress` 工具 + 未实现的 `{progressText}` 占位符——**全部不要信**。

---

## 3. 系统提示词运行时构造

入口：`viewmodels/ChatViewModel.ets:311-324` 的 `buildRequestSystemPrompt(extraPrompt, greetingHint)` + `injectTeachingSections(basePrompt)`（行 337-383；v1 文档中的方法名 `injectDailyPlanSections` 已重构更名）。

**注入条件**：仅当 `assistantId === DEFAULT_ASSISTANT_ID`（即小星老师）时追加教学上下文；其他助手（**含 4 个学科助手**）拿到的是干净的 `combineSystemPrompts(...)` 合并结果并提前 return。

**注入内容**（按顺序）：

1. **全局 prompt**（AppStorageV2 连接的基础；仅非 default 助手叠加全局 prompt，小星老师跳过）
2. **小星老师 systemPrompt**（`DEFAULT_ASSISTANT_SYSTEM_PROMPT`）
3. **`extraPrompt`**（外部传入的临时上下文）
4. **昨日小结** —— `LessonPlanPromptUtils` 的 `renderYesterdaySummarySection(plan, planDate)`
5. **教学风格调整** —— `TeachingStyleAdjustmentService.renderForPrompt(styleAdj)`（v1 文档未覆盖此段）
6. **今日教学目标** —— 渲染器 `utils/LessonPlanPromptUtils.ets` 的 `renderDailyPlanSection(plan, planDate, weekday)`，主题 + 4 模块条目 + 教学提示 + 使用建议（含 `<topic_key>` 标签语法）
7. **主动招呼元指令**（`greetingHint`，仅主动招呼时非空，置于末尾最高优先级）

**数据源**：
- 今日计划：`LessonPlanningService.getTodayPlan()`（注：方法名是"Today"，实际返回 `planDate === 明天` 的记录——即"昨天生成、今早用的"）
- 昨日小结：`LessonPlanningService.getYesterdaySummary()`（`planDate === 昨天` 的记录）

**刷新触发**：`config/AppStorageKeys.ets:80-82` 的 `LESSON_PLAN_REFRESH_TICK` AppStorage 计数器。`LessonPlanningService` 在计划写回后增 1（`LessonPlanningService.ets:642`），ChatViewModel 监听后重新拉取。失败路径：异常被吞，回退到无计划注入（`injectTeachingSections` 的 catch 返回 `basePrompt`）——优雅降级，不阻塞对话。

---

## 4. 教学工具生态

小星老师 **锁定 19 个工具**（§2 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`），其中 13 个有 UI 互动卡片（含 `ask_user`，已并入锁定白名单），3 个纯后端（`child_profile`、`math_verify`、`grant_star`），2 个非互动生成类（`image_generation`、`music_generation`），外加 `get_time_info`。4 个学科助手各锁定其中一个子集（见 §2.1，均不含 image_generation / music_generation）。

| 工具 ID | UI 卡片 | 是否锁定 | 备注 |
|---------|---------|----------|------|
| `child_profile` | （无，纯后端） | ✓ | 画像读写 |
| `math_verify` | （无） | ✓ | 竖式答案验证 |
| `grant_star` | （无） | ✓ | 聊天答对授星 |
| `get_time_info` | （无） | ✓ | 日期/星期注入 |
| `image_generation` | ImageGenerationToolResult | ✓ | 走 `image_index` 预生成图命中 |
| `music_generation` | MusicGenerationToolResult | ✓ | 音乐生成 |
| `math_quiz` | `MathQuizCard.ets` | ✓ | 预校验 + should_retry |
| `english_quiz` | `EnglishQuizCard.ets` | ✓ | 六 mode（v2） |
| `vertical_math` | `VerticalMathCard.ets` | ✓ | 竖式演示 |
| `math_teach` | `MathTeachCard.ets` | ✓ | kids_math 专用五步课讲解板，预校验 + should_retry；8 mode |
| `number_puzzle` | `NumberPuzzleCard.ets` | ✓ | 2026-09 由 `huarongdao` 规范化而来；历史会话旧名仍可渲染 |
| `handwriting_practice` | `HandwritingCard.ets` | ✓ | 学写字 |
| `categorization` | `CategorizationCard.ets` | ✓ | 分类小管家 |
| `maze` | `MazeCard.ets` | ✓ | 走迷宫 |
| `sudoku` | `SudokuCard.ets` | ✓ | 数独 5 难度 |
| `picture_vocab` | `PictureVocabCard.ets` | ✓ | 看图识词 (en/zh)，预校验 |
| `listening_quiz` | `ListeningQuizCard.ets` | ✓ | 听力辨音，TTS + 预校验 |
| `pinyin_quiz` | `PinyinQuizCard.ets` | ✓ | 拼音认读，内置 72 字表 + 预校验 |
| `matching_pairs` | `MatchingPairsCard.ets` | ✓ | 连一连观察配对，预校验 |
| `ask_user` | `AskUserCard.ets` | ✓（v2 已并入锁定列表） | AI 反问 |

**预校验 + should_retry**：`math_quiz` / `english_quiz` / `picture_vocab` / `listening_quiz` / `pinyin_quiz` / `matching_pairs` / `categorization` 的参数在进入 pending 前先经 `utils/*Validation.ets` 校验；坏题返回 `{error: 'validation_failed', should_retry: true}` 让 LLM 自行修正，不会渲染不可玩的卡片。

**`largeSize` 模式**：部分较复杂的卡片（数字华容道、学写字、分类等）支持双视图——内联（MessageBubble 内带气泡外壳）vs 全屏 sheet（ChatPage 大尺寸容器，透明背景让 sheet 接管）。其余卡片仅内联。

**非锁定但 AI 可调用**（走 `webSearch` 独立通道，不受白名单影响）：
- 联网搜索 `search_web` / `scrape_web`（`SearchToolIdentityUtils.ets`）

---

## 5. 教学数据模型

### 5.1 孩子画像（`ChildProfileService.ets`）

| 字段 | 存储 | 备注 |
|------|------|------|
| 整条画像 | Preferences `child_profile_json` 单条 JSON | **非 SQLite** |
| SkillDimension 扩展字段 | 每维 `strategy` / `misconceptions` | 2026-09-27 新增，child_profile update 透传 |
| 缓存 | `ChildProfileService.cachedProfile` 字段 | 启动加载一次 |
| 更新入口 | `child_profile(action:"update")` 工具 | AI 调用 → `ChildProfileExecutor.handleUpdate` (BuiltinTools.ets:817-870) |

**26 维技能**（`ChildProfileService.ets` 的 `SKILL_DEFINITIONS`）：

- **数学 10**：`math_counting` / `math_number_sense` / `math_addition` / `math_subtraction` / `math_multiply` / `math_divide` / `math_shapes` / `math_comparison` / `math_time` / `math_word_problem`
- **英语 5**：`english_alphabet` / `english_vocab` / `english_sentence` / `english_phonics` / `english_reading`
- **常识 3**：`general_nature` / `general_social` / `general_life`
- **认知 3**：`logic_thinking` / `observation` / `spatial_reasoning`
- **书写/小肌肉 4**：`fine_motor` / `english_writing` / `chinese_writing` / `categorization`
- **语文 1**：`pinyin`（2026-09 新增，画像页归入「语文」分组，与 chinese_writing 同组）

每维 `level: 0-5`（0=未评估 1=入门 2=初步 3=中等 4=良好 5=精通），外加 `lastAssessed` 时间戳和 `notes` 观察备注。

### 5.2 教学计划（`LessonPlanModels.ets`）

`LessonPlan`（行 69-85）含 **4 个强类型模块数组** + 1 个扩展位：

| 字段 | 类型 | 用途 |
|------|------|------|
| `vocab` | `LessonPlanVocabItem[]` | 英语词汇（默认模块） |
| `math` | `LessonPlanMathItem[]` | 数学点 |
| `writing` | `LessonPlanWritingItem[]` | 写字（字母/数字/中文） |
| `generalKnowledge` | `LessonPlanGeneralItem[]` | 常识（自然/社会/生活） |
| `freeform` | `Record<string, Object>` | 未来扩展位（阅读/音乐/科学） |

每个 item 继承 `LessonPlanItemBase`（行 13-16）：`topicKey`（如 `vocab.apple`）+ `imagePrompt`（英文图像描述）。

**严格校验**：`LessonPlanningService.ets:612-627` 强制 **4 个模块数组至少一个有内容**——若 LLM 把所有内容塞到 `themeDescription`/`teacherNotes` 而模块全空，视为输出不符合 schema 拒绝写入。

DB 行 `DailyLessonPlanRow`（行 248-263）→ 表 `daily_lesson_plans`，状态机：`pending` → `running` → `done` / `failed`。

### 5.3 预生成图（统一 `image_index` 表）

所有图片索引都走单张 `image_index` SQLite 表 + `ImageSource` 枚举区分来源（替代了原 `prepared_media` 表 + `EnglishQuizImageIndex` Preferences 双轨存储，启动时由 `DatabaseService` 一次性迁移合并）：

| `ImageSource` 值 | TTL | Key 形式 | 用途 |
|--------|-----|---------|------|
| `LESSON_PLAN` | **7 天** | 语义 `topicKey`（如 `vocab.apple`） | 备课老师预生成 |
| `ENGLISH_QUIZ` | **永不过期**（`expires_at = 0`） | 字面 `w:<word>` / `s:<sentence>` | 英语题出题 |

数据模型：`models/ImageIndexModels.ets:50`（`ImageIndexRow`），单例服务：`services/ImageIndexService.ets`（`getImageIndexService()`）。TTL 常量 `LESSON_PLAN_TTL_MS = 7*24*60*60*1000` 在 `ImageIndexService.ets:35` 定义；`ENGLISH_QUIZ` 写 `expires_at=0` 表示永不过期。消费路径：`image_generation` 工具通过 prompt 中的 `<topic_key>` 标签触发 `ImageIndexService.findByKey(ImageSource.LESSON_PLAN, topicKey)` 命中预生成图，大幅降低首字延迟；命中后 `markConsumed` 递增 `consumed_count` 用于 LRU 风格回收提示。可视化管理入口：`pages/LearningEnglishImagesPage.ets`，按 `ALL / QUIZ / PLAN` 过滤浏览+删除。

---

## 6. 星星奖励系统

**入口**：`ToolExecutionService.ets` 的私有 `recordStarEvent(activityType, toolCall, context, answerJson)`。在各互动工具处理器末尾调用：
- `handleMathQuiz` → `math_quiz`
- `handleEnglishQuiz` → `english_quiz`
- `handleNumberPuzzle` → `number_puzzle`
- `handleCategorization` → `categorization`
- `handleHandwriting` → `handwriting_practice`
- `handleMaze` → `maze`、`handleSudoku` → `sudoku`
- `handlePictureVocab` → `picture_vocab`
- `handleListeningQuiz` → `listening_quiz`
- `handlePinyinQuiz` → `pinyin_quiz`
- `handleMatchingPairs` → `matching_pairs`
- 聊天答对（不走卡片）→ `chat_correct`（`grant_star` 工具）

**纯函数计算**：`StarRewardService.ets` 的 `computeStars(type, payload)`：

| 活动类型 | 条件 | 星星数 |
|---------|------|--------|
| `math_quiz` / `english_quiz` / `picture_vocab` / `listening_quiz` / `pinyin_quiz` | `correct === true` | 1 |
| 上述题型 | 答错 | 0 |
| `number_puzzle` | `completed === true` | `DIFFICULTY_STARS[difficulty]` (1/2/3/5) |
| `handwriting_practice` | `completed === true` | 1 |
| `categorization` | 全对 / 部分对 | `DIFFICULTY_STARS[difficulty] ?? 1` / 1 |
| `maze` | `completed === true` | 1 + 收集星数 |
| `sudoku` | `completed === true` | 按难度 1/2/3/5/7 |
| `matching_pairs` | 全对 0 失误 / 有失误 / 放弃 | 难度 1/2/3 / 1 / 0 |
| `chat_correct` | 聊天答对 | 1 |

**副作用**（`StarRewardService.ets:119-164` 的 `recordEvent`）：
1. INSERT `star_events` 表
2. 刷 `AppUiState.todayStarSummary`（JSON 字符串）
3. 设 `AppUiState.lastStarGrant`（浮层用）
4. 增 `starEarnedTick`（触发 `TodayStarDetailSheet` 重渲染）

**⚠ 10 处联合漂移点**（添加新活动类型时必须同步，否则 TS 编译过但运行时静默错——见 MEMORY.md）：

`models/StarEventModels.ets` 内：

1. `StarActivityType` 联合（行 10）
2. `TodayStarSummaryByType` 接口字段（行 39-43）
3. `createEmptyTodayStarSummary()` 函数体（行 67-71）
4. `StarActivityMetaMap` 接口字段（行 85-89）
5. `META_XXX` 常量（行 92-126，逐类型）
6. `metaRecord` 初始化条目（行 129-133）
7. `activityTypes` 数组（行 137）
8. `getBucketFromSummary` if 分支（行 142-153）
9. `getActivityMeta` if 分支（行 158-169）
10. `getActivitySymbol` if 分支（行 178-190）

完整配方见 `.claude/skills/adding-mini-game-tool/SKILL.md` 的 4-grep 校验。

---

## 7. 备课老师：后台教学规划服务

服务：`services/LessonPlanningService.ets`（单例，约 1170 行）。**"备课老师"是一个独立的 AI 流水线**，不是用户可见的工具——它在会话结束后自动为小星老师准备明天的教学计划。

### 7.1 触发链

```
ChatViewModel（会话结束路径）调 getLessonPlanningService().notifySessionEnd(sessionId, assistantId)  // ChatViewModel.ets:2743
  └─ LessonPlanningService.notifySessionEnd(...)        // LessonPlanningService.ets:265
       └─ 仅 assistantId === 'default' 时才接受（4 个学科助手会话被过滤，不触发备课）
       └─ 5 分钟防抖（DEBOUNCE_MS = 5*60*1000）合并多次结束
       └─ schedulePlanning() → runPlanningPipeline(planDate=明天)
```

### 7.2 状态机与幂等

| 条件 | 动作 |
|------|------|
| 计划已 `done` | 跳过 |
| `pending`/`running` 且 < 30 分钟 | 跳过 |
| `failed` 且今日失败 ≥ 3 次 | 跳过 |
| 其他 | 写 `running` 行 → 调 LLM |

跨天容错：失败计数按 `planner_fail_count_YYYYMMDD` 键存 Preferences（行 1154-1171），自然日切时归零。

### 7.3 LLM 调用

- 模型：默认对话模型（`ModelRole.CHAT`）
- 参数：`temperature=0.4`，`maxTokens=4096`，**关 reasoning**（避免 `<think>` 污染 JSON）
- 提示词：`utils/LessonPlanPromptUtils.ets:27-93` 的 `PLANNER_SYSTEM_PROMPT`，以"经验丰富的 6-7 岁教学专家"人设
- 输入 JSON：今日小星老师会话总结 + 26 维孩子画像弱项 + 昨日计划 + `planDate`（明天）
- 输出清洗：`cleanPlannerJsonOutput()`（行 279-299）剥 `<think>` / 围栏 / 提取 `{...}` → `JSON.parse` → `parseLessonPlan` 带 fallback 水合

### 7.4 图片预生成（prefetchImages，行 955-1116）

成功写 plan 后，3 并发 worker 调 `ImageGenerationService.generateImage`，存沙盒 → 调 `ImageIndexService.putEntry(ImageSource.LESSON_PLAN, topicKey, ...)` 写入 `image_index` 表（**7 天 TTL**，由 `LESSON_PLAN_TTL_MS` 自动写入 `expires_at`，见 §5.3）。后续 `image_generation` 工具可通过 prompt 中的 `<topic_key>` 标签经 `ImageIndexService.findByKey` 命中。老 `prepared_media` 表已**停止接收新写入**——仅保留给 `LessonPlanningService.getPlannerStats` 兜底读取历史统计；新写入与查询统一走 `image_index`。

### 7.5 关键参数

| 常量 | 值 | 位置 |
|------|------|------|
| `DEBOUNCE_MS` | 5 分钟 | 行 85 |
| `RETRY_MIN_INTERVAL_MS` | 30 分钟 | 行 90 |
| `MAX_FAILS_PER_DAY` | 3 | 行 105 |
| `PREFETCH_CONCURRENCY` | 3 | 行 110 |
| `PREFETCH_TTL_MS` | 7 天 | 行 115 |

---

## 8. 持久化

6 张教学相关表（`services/DatabaseService.ets:185-420` 的 `createTables`）：

| 表 | 用途 | 关键列 |
|---|---|---|
| `puzzle_records` | 华容道游戏记录 | `difficulty, time_seconds, move_count, completed, session_id` |
| `star_events` | 星星事件流水 | `activity_type, stars, tool_call_id, session_id, skill_key, metadata_json` |
| `daily_lesson_plans` | 每日教学计划 | `plan_date, plan_json, status, planner_provider_id/model_id, session_ids_json` |
| `image_index` | 统一图片索引（替代原 prepared_media 表 + EnglishQuizImageIndex Preferences） | `source, key, file_path, expires_at, consumed_count, status` + 索引 `(source,key)` |
| `prepared_media` | **已废弃**——保留表结构仅给 `getPlannerStats` 兜底读取历史统计 | `topic_key, file_path, consumed_count, expires_at, plan_id` (FK CASCADE) |
| (Preferences) `child_profile_json` | 孩子画像 | 单条 JSON，26 维技能 + 强项/弱项标签 |

### 8.1 统一图片索引管线（`image_index` 单表 + `ImageSource` 枚举）

历史上有两套并存的图片索引（`prepared_media` 表 + `EnglishQuizImageIndex` Preferences JSON），现已合并为单张 `image_index` SQLite 表，通过 `ImageSource` 枚举区分来源，TTL 差异化由 `ImageIndexService.putEntry` 内部按 source 决定：

| Source 值 | 写入入口 | Key | TTL | 用途 |
|-----------|---------|-----|-----|------|
| `LESSON_PLAN` | `LessonPlanningService.prefetchImages`（prefetchOne → persistPrefetchResult） | 语义 `topicKey`（如 `vocab.apple`） | 7 天（`LESSON_PLAN_TTL_MS`，到期后由 `LessonPlanningService.initialize` 调 `ImageIndexService.cleanupExpired` 删行 + 删沙箱文件） | 备课老师批量预生成，按主题复用 |
| `ENGLISH_QUIZ` | `ToolExecutionService.handleEnglishQuiz` 走 `ImageIndexService.generateAndStore` | 字面 `w:<word>` / `s:<sentence>` | 永不过期（`expires_at=0`，`cleanupExpired` 不删） | 英语题出题时按题字面键复用 |

**迁移路径**：`DatabaseService.initialize` 启动时一次性把老 `prepared_media` 表 + `EnglishQuizImageIndex` Preferences JSON 迁移到 `image_index`，老 key/id 保留（`prepared_media` 行的 `id` 沿用为 `pm_xxx`，避免引用 `generated_media.prepared_media_id` 的历史数据断链）。迁移完成后新写入只走 `image_index`，老 `prepared_media` 表停止接收写入（仅历史兜底统计可读）。

---

## 9. 端到端教学流（8 步）

```
1. 应用启动
   EntryAbility.onCreate → 初始化 services
   → DatabaseService.createTables 流程内 ensureDefaultAssistant + ensureKidsSubjectAssistants（幂等补建 5 个内置助手）
   → LessonPlanningService.initialize(context)  // 清理过期图 + 重触发今日计划

2. 用户开启新对话
   ChatViewModel.buildRequestSystemPrompt(extraPrompt)  // 行 311
   → injectTeachingSections(basePrompt)  // 仅小星老师；学科助手提前 return
   → 拼出完整 system prompt（基础 + 教学策略 + 昨日小结 + 风格调整 + 今日目标）

3. AI 读取孩子画像
   AI 第一动作：child_profile(action:"read")
   → ChildProfileExecutor.execute 同步返回 ChildKnowledgeProfile JSON

4. AI 出题
   AI 调用 math_quiz / english_quiz / categorization / number_puzzle / handwriting_practice
   → ToolExecutionService.executeToolCall 分发到 handleXxx 特殊路径
   → toolCall.approvalState = 'pending'
   → 挂 Promise<answerJson> 到 pendingAnswers map
   → publishPendingInteractionChanged() 通知 UI

5. 卡片渲染 + 孩子作答
   MessageBubble 渲染对应 *Card.ets (inline / largeSize)
   → 孩子点击/滑动/手写
   → onAnswer(toolCallId, answerJson)  // @Event
   → ToolExecutionService.resolvePendingAnswer()
   → Promise 解决
   → recordStarEvent(...) → StarRewardService.recordEvent → 写 star_events + 浮层脉冲

6. AI 据结果更新画像
   AI 评估 → child_profile(action:"update")
   → ChildProfileExecutor.handleUpdate → ChildProfileService.saveProfile → 写 Preferences

7. 会话成功结束
   ChatViewModel 调 LessonPlanningService.notifySessionEnd
   → 5 分钟防抖合并
   → runPlanningPipeline(planDate=明天)
   → 调 LLM 备课
   → 4 模块非空校验
   → 写 daily_lesson_plans (status='done')
   → 3 并发预生成图 → 写 image_index (source=LESSON_PLAN)
   → 增 LESSON_PLAN_REFRESH_TICK

8. 下次开聊
   ChatViewModel 监听到 LESSON_PLAN_REFRESH_TICK 变化
   → 下次 buildRequestSystemPrompt 拉到新计划
   → AI 据新计划出题
```

---

## 10. 触点文件（修改时同步）

添加新互动小游戏工具时**必须同步修改 8 处**（完整配方见 `.claude/skills/adding-mini-game-tool/SKILL.md`）：

| 触点 | 文件 |
|------|------|
| 工具 ID 常量 | `utils/SearchToolIdentityUtils.ets` |
| 工具注册（schema + executor + register） | `config/BuiltinTools.ets` |
| 工具分发（在 `resolveToolId` 兜底之前） | `services/ToolExecutionService.ets` |
| 星星事件联合（10 处漂移点） | `models/StarEventModels.ets` |
| 星星计算分支 | `services/StarRewardService.ets` |
| 助手配置（import + locked list + system prompt 段；v2 起还需评估是否加入某学科助手的 `KIDS_*_LOCKED_TOOL_IDS` + 对应学科提示词段） | `models/AssistantModels.ets` |
| 卡片组件（新建） | `components/*Card.ets` |
| 气泡挂载（7 处：内联渲染 + 3 or 链 + 助手 + 点击 + 步骤切换 + 步骤内容） | `components/MessageBubble.ets` |

---

## 11. 关键设计观察

1. **教学是"两层 AI"协作**：用户面对的"小星老师"是实时对话；"备课老师"是夜间批量规划。两者通过 `daily_lesson_plans` 表 + `LESSON_PLAN_REFRESH_TICK` 解耦——小星老师可独立工作，即使备课失败也不阻塞对话。

2. **数据持久化按"热/冷"分层**：孩子画像（小、频繁读写）走 Preferences JSON 缓存；星星事件、备课、预生成图（量大、需历史查询）走 SQLite。预生成图又用 `consumed_count` 字段做 LRU 风格的回收提示。

3. **统一图片索引（`image_index` 单表 + `ImageSource` 枚举）**反映了两种使用模式：备课老师"主题驱动"（一个 apple 多次用，按 `topicKey` 复用，7 天过期，`source=LESSON_PLAN`）vs 英语题"题驱动"（一个 apple 只问一次，按字面 `word` 缓存，无过期，`source=ENGLISH_QUIZ`）。**两种模式共存于同一张表**，靠 `source` 字段和 TTL 区分——混淆会让 `expires_at=0` 的英语题图被误清理或反过来撑爆 `image_index`。

4. **4 模块非空校验**是抵御 LLM 自由发挥的关键防线——若不校验，模型倾向把内容堆到 `themeDescription`/`teacherNotes` 而 4 个模块全空，导致小星老师拿着空计划上课。

5. **26 维技能 = 26 个枚举值**散落在多份 schema 定义中（`ChildProfileService.SKILL_DEFINITIONS`、`BuiltinTools.ets` 的 child_profile schema、`AssistantModels.ets` 的 5 份系统提示词——default + 4 学科各自引用维度子集）。**修改维度时必须多处同步**——不像 10 处漂移点有专门技能提醒，这个目前是 naked 风险（v2 起提示词从 1 份变 5 份，漂移面扩大）。

6. **锁定工具 + 锁定系统提示词**是产品级硬约束：5 个内置助手（小星老师 + 4 学科老师）永远是它们自己，用户无法在前端"改个名字"破坏体验。这对面向低龄儿童的产品是正确取舍（避免家长/孩子误操作导致人格漂移），但也意味着任何"让内置助手更灵活"的尝试必须改注册表实现（`getBuiltInAssistantSpec` / `KIDS_SUBJECT_SPECS`）而非放开权限。

7. **`teacher.md` 已过期**——本文档取代它。任何提到"小鹿老师"或 `update_progress` 工具的代码注释/PR 描述/历史文档都应被视作噪音。

---

## 12. 相关文件清单

| 路径 | 角色 |
|------|------|
| `models/AssistantModels.ets:26-453` | 小星老师 + 4 学科助手定义（`KIDS_SUBJECT_SPECS` / `getBuiltInAssistantSpec` / `createKidsSubjectAssistants` / `KIDS_BUILT_IN_ASSISTANT_IDS`） |
| `services/AssistantService.ets:122-140, 303-304` | 内置助手规范化（注册表锁字段）+ 删除保护 |
| `services/DatabaseService.ets:1294-1312` | `ensureKidsSubjectAssistants()` 启动幂等补建 |
| `viewmodels/ChatViewModel.ets:311-383, 2743` | 提示词注入（`injectTeachingSections`）+ 会话结束通知 |
| `services/LessonPlanningService.ets` | 备课老师完整管线 |
| `utils/LessonPlanPromptUtils.ets` | 备课系统提示词 + 渲染 |
| `services/ChildProfileService.ets` | 26 维技能定义 |
| `services/StarRewardService.ets` | 星星计算 + 副作用 |
| `models/StarEventModels.ets` | 10 处联合漂移点 |
| `services/ToolExecutionService.ets` | 工具分发 + 星星事件 + 互动工具特殊处理器 |
| `config/BuiltinTools.ets` | 工具注册中心 |
| `services/DatabaseService.ets` | 表结构（含 image_index + 已废弃 prepared_media 兜底）+ 教学数据 CRUD + `getStarTotalsByDay(sinceMs)`（儿童主屏每日星数） |
| `services/ImageIndexService.ets` + `models/ImageIndexModels.ets` | 统一图片索引（替代原 EnglishQuizImageIndex + prepared_media 双轨） |
| `components/kids/KidsHomeView.ets` | 儿童主屏三段式（hero + 学科卡 + 学习乐园） |
| `components/kids/KidsSubjectCatalog.ets` | 4 学科卡目录（startPrompt / assistantId / 图标 / 色令牌） |
| `components/kids/KidsDayGroupCard.ets` | 学习乐园按天分组卡 |
| `components/kids/KidsStarDetailSheet.ets` | 今日星星明细 sheet |
| `components/kids/ParentalGateSheet.ets` | 家长门两阶段（算术验证 → 今日概览） |
| `utils/KidsSubjectUtils.ets` | 儿童主屏纯函数（countTodayBySubject / groupSessionsByDay / findTodaySession / buildToday*Rows 等） |
| `pages/Index.ets` | `isKidsAllowedSessionId`（KIDS_BUILT_IN_ASSISTANT_IDS 放行）+ `handleKidsNewChat(initialPrompt, assistantId)` |
| `pages/LearningProfilePage.ets` | 孩子画像查看页 |
| `pages/LearningTomorrowPlanPage.ets` | 备课计划查看页 |
| `components/chat/TodayStarDetailSheet.ets` | 星星详情 sheet（成人聊天侧） |
| `components/AskUserCard.ets` 等 *Card.ets | 互动卡片组件 |
| `docs/superpowers/specs/2026-09-15-kids-home-v2-redesign-design.md` | 儿童主屏 v2 + 学科助手设计 spec |
| `docs/brand-spec.md` | 儿童端品牌规范（色彩/字体/审美契约，v2 已落地） |
| `.claude/skills/adding-mini-game-tool/SKILL.md` | 新增互动工具的 10 步配方 |
| `teacher.md` (仓库根) | **已过期**，忽略 |

---

**前置文档**：本文档 v1（2026-06-10，已被本 v2 取代）
**相关文档**：`.claude/rules/number-puzzle-card.md`（组件级设计范例，与本文档平级）、`docs/brand-spec.md`（儿童端品牌规范）、`docs/superpowers/specs/2026-09-15-kids-home-v2-redesign-design.md`（v2 设计 spec）
