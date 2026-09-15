# 儿童主屏 v2 重构 + 四学科专用助手 · 设计 Spec

**日期：** 2026-09-15
**版本：** v1
**状态：** 已与用户对齐（brainstorming 完成），待实施 plan
**范围：** 按冻结品牌规范 v2（`docs/brand-spec.md`）与高保真原型（`docs/kids-learning-home.html`，注意文件名带尾随空格）重构儿童主屏为三段式；新增 4 个学科专用内置助手；家长门升级为「门 → 今日概览」两阶段。
**前置文档：**
- `docs/brand-spec.md`（v2 冻结审美契约，本文的验收基准）
- `docs/superpowers/specs/2026-09-10-kids-mode-design.md`（儿童模式 v1，本文取代其 §4 主屏设计）
- `.claude/rules/teaching-architecture.md`（教学体系架构）

---

## 1. 背景与目标

儿童模式 v1 已上线：冷启动直达儿童主屏、算术家长门、图形化会话列表。但 v1 主屏基于旧原型（12 活动 emoji 宫格 + 2 列会话卡网格），与 2026-09-14 冻结的品牌规范 v2 存在系统性偏差：

| 区块 | v1 现状 | v2 目标（原型） |
|---|---|---|
| Hero | 每次点击开新会话、「本周 +N」徽章、吉祥物循环浮动动画 | 一天一会话（续接今日会话）、「今日 +N」+「看明细」、无循环动画（§8） |
| 活动区 | 12 项 emoji 八宫格（§9/§10 禁 emoji 当图标） | 2×2 学科卡（学数学/学英语/学语文/小游戏），学科专属色 + ink 变体，「今日 N 题」状态行 |
| 学习乐园 | 2 列会话卡网格（emoji 头像） | 按天分组记录列表（今天/昨天/日期 + 当日星星汇总 + 同日 >3 条折叠） |
| 家长入口 | 算术门 → 直接进成人壳 | 算术门 → 家长今日概览（10 秒读懂）→ 可选进成人壳 |
| 助手体系 | 仅小星老师一个全科助手 | 小星老师（hero/日常）+ 4 个学科专用助手（锁定学科工具子集） |

**已对齐的产品决策**（brainstorming 三问）：

| 决策点 | 结论 |
|---|---|
| 学科卡背后 | **4 个专用内置助手**（小星数学/英语/语文/游戏老师），各自锁定工具子集 + 系统提示词 |
| 家长入口 | **概览 + 可进成人壳**：过门先展示今日概览，底部「进入家长设置」再进成人壳 |
| Hero 语义 | **一天一会话**：当天首次点击开新会话，之后续接今日小星老师会话 |

**业务目标对齐**（brand-spec §2）：零迷路（三段式单一焦点）、每日回访（今日星星 + 按天记录）、四个明确入口（学科 = 专用 agent 而非工具杂货铺）、家长 10 秒读懂（今日概览）。

---

## 2. 架构总览

```
models/AssistantModels.ets
  └─ 新增 4 个内置学科助手定义（id/名称/色/头像字/系统提示词/锁定工具子集）
     + KIDS_SUBJECT_ASSISTANT_IDS 导出

services/AssistantService.ets
  └─ initialize() 确保 5 个内置助手存在（default + 4 学科）
  └─ normalizeAssistant() 锁定名单从 1 个 id 扩到 5 个
  └─ 删除保护谓词 isProtectedAssistantId(id) 覆盖 5 个内置 id

components/kids/
  ├─ KidsBrandTokens.ets     KIDS_SUBTLE 修正 + 8 个学科令牌
  ├─ KidsSubjectCatalog.ets  (新) 4 学科元数据目录（取代 KidsActivityCatalog）
  ├─ KidsHomeView.ets        (重写) 三段式主屏
  ├─ KidsDayGroupCard.ets    (新) 学习乐园按天分组卡
  ├─ KidsStarDetailSheet.ets (新) 今日星星明细 sheet（儿童令牌版）
  ├─ ParentalGateSheet.ets   (扩展) 门 → 今日概览两阶段
  ├─ KidsActivityCatalog.ets (删除)
  └─ KidsSessionCard.ets     (删除)

utils/KidsSubjectUtils.ets   (新) 纯函数：activityType→学科映射 / 按天分组 /
                             今日会话判定 / 星期标签（hypium 可测）

services/DatabaseService.ets getStarTotalsByDay(sinceMs) 按天星星汇总

pages/Index.ets              isKidsAllowedSessionId 放行 5 个助手 id；
                             handleKidsNewChat 增加 assistantId 参数

resources/rawfile/kids/      8 个 monoline SVG 图标（star/math/english/chinese/
                             games/lock/chevron/close），颜色 baked-in
```

**关键原则：**
- 儿童主屏恒定暖色皮肤（不随深色模式），SVG 图标颜色直接 baked-in，无需运行时着色。
- 学科助手会话完全复用现有 ChatPage / 星星记录 / 画像链路——会话落库带 `assistantId`，零特殊分支。
- 备课老师管线（LessonPlanningService）**保持只服务 `default`**，学科助手不触发备课、不注入今日计划（`ChatViewModel.injectDailyPlanSections` 的 `assistantId === DEFAULT_ASSISTANT_ID` 条件不动）。

---

## 3. 四学科专用助手

### 3.1 定义（models/AssistantModels.ets）

| id | 名称 | color | avatarSymbol | 锁定工具子集 |
|---|---|---|---|---|
| `kids_math` | 小星数学老师 | `#4E8FE0` | `数` | ASK_USER, CHILD_PROFILE, GET_TIME_INFO, GRANT_STAR, MATH_VERIFY, MATH_QUIZ, VERTICAL_MATH |
| `kids_english` | 小星英语老师 | `#35A98A` | `英` | ASK_USER, CHILD_PROFILE, GET_TIME_INFO, GRANT_STAR, ENGLISH_QUIZ, PICTURE_VOCAB, LISTENING_QUIZ |
| `kids_chinese` | 小星语文老师 | `#E2603C` | `语` | ASK_USER, CHILD_PROFILE, GET_TIME_INFO, GRANT_STAR, PINYIN_QUIZ, HANDWRITING_PRACTICE |
| `kids_games` | 小星游戏老师 | `#8B72E0` | `玩` | ASK_USER, CHILD_PROFILE, GET_TIME_INFO, GRANT_STAR, NUMBER_PUZZLE, MAZE, SUDOKU, MATCHING_PAIRS, CATEGORIZATION |

- `avatarSymbol` 用单汉字而非 emoji（§10 反模式 2；成人壳助手列表的字母头像渲染兼容）。
- 工具 id 全部复用 `utils/SearchToolIdentityUtils.ets` 现有常量（同 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 的引用方式）。
- **不含** `image_generation` / `music_generation`——学科老师专注出题互动，生图需求归小星老师。
- 导出 `KIDS_SUBJECT_ASSISTANT_IDS: string[]`（4 个 id）与 `KIDS_BUILT_IN_ASSISTANT_IDS: string[]`（含 `default` 共 5 个）。
- 每学科导出 `KIDS_XXX_SYSTEM_PROMPT` 与 `KIDS_XXX_LOCKED_TOOL_IDS`，并提供 `createKidsSubjectAssistants(): Assistant[]` 工厂（对齐 `createDefaultAssistant()` 模式，`sortOrder` 依次排在 default 之后）。

### 3.2 系统提示词（每个 40–60 行中文）

统一结构（复用小星老师提示词的骨架，按学科裁剪）：

1. **身份**：「你是小星XX老师，小星学习乐园里专门陪小朋友学XX的老师」
2. **说话方式**：与小星老师一致——1–3 句、≤50 字、禁 emoji、禁 markdown（逐字复用现有段落，保持人格一致性）
3. **教学策略**：每轮开始 `child_profile(action:"read")`；有真凭实据才 `update`（只更新本学科相关技能维度）
4. **学科出题策略**：
   - 数学：8 维中的 math_* 目标；由易到难；答对授星（grant_star）；竖式用 vertical_math 演示
   - 英语：alphabet/vocab/phonics 目标；听力题优先用 listening_quiz；看图识词用 picture_vocab
   - 语文：pinyin/chinese_writing/fine_motor 目标；拼音认读用 pinyin_quiz；学写字用 handwriting_practice
   - 游戏：logic_thinking/observation/spatial_reasoning 目标；轮换 number_puzzle/maze/sudoku/matching_pairs/categorization，一局一邀
5. **边界**：小朋友问其他学科内容时，简短回答并引导回本学科；不越界出其他学科的题

**JSON-in-template-literal 陷阱**（MEMORY.md）：提示词内如需引号示例，用「」中文方头括号；写完后 `node -e` 验证任何内嵌 JSON。

### 3.3 生命周期与保护（services/AssistantService.ets）

- `initialize()` 中：`ensureAssistantsInitialized` 之后逐个检查 4 个学科 id，不存在则 `store.upsertAssistant(createKidsSubjectAssistants()[i])` 创建（对齐 default 助手的启动创建路径，具体挂载点以现有 default 创建位置为准）。
- `normalizeAssistant()`：现有 `if (assistant.id === DEFAULT_ASSISTANT_ID)` 分支扩展为按 id 查内置注册表（5 个 id → 各自的 systemPrompt + lockedToolIds 强制覆盖；`isDefault` 仅 default 为 true）。
- **删除/编辑保护**：成人壳助手列表中，凡 `KIDS_BUILT_IN_ASSISTANT_IDS` 成员：禁删除、禁改名、禁改提示词、禁改工具白名单（沿用小星老师现有 UI 保护模式，保护谓词从 `id === DEFAULT_ASSISTANT_ID` 换成 `KIDS_BUILT_IN_ASSISTANT_IDS.includes(id)`；需 grep 助手编辑页所有 `DEFAULT_ASSISTANT_ID` 保护点逐一评估）。
- 已存在用户的升级路径：启动 ensure 逻辑幂等，老用户升级后自动补建 4 个助手。

### 3.4 与教学数据链路的关系

| 链路 | 学科助手行为 |
|---|---|
| 星星记录 | 照常——`recordStarEvent` 按 toolCall 类型分发，与 assistantId 无关 |
| 孩子画像 | 照常读写（child_profile 在锁定子集内），提示词约束只更新本学科维度 |
| 备课老师 | **不触发**——`notifySessionEnd` 仅接受 `assistantId === 'default'`（现有过滤不动） |
| 今日计划注入 | **不注入**——`injectDailyPlanSections` 条件不动 |
| 会话列表（儿童主屏） | 5 个助手的会话都显示（见 §4.4） |

---

## 4. 儿童主屏三段式（KidsHomeView 重写）

### 4.1 布局（对照原型 `.screen`）

```
┌────────────────────────────────────┐
│ [头像] 早上好，小明        [⭐128颗] │ ← 问候行（轻量信息条，固定不滚动）
├────────────────────────────────────┤
│ ┌────────────────────────────────┐ │
│ │ [⭐] 今日学习 · 9月15日 周二     │ │ ← Hero「继续学习」（唯一焦点）
│ │      继续学习                   │ │    暖橙渐变 + 右上玻璃圆
│ │      小星老师 · 今天第一次学习…  │ │
│ │ [开始今天的学习›] [⭐今日+6][看明细]│ │
│ └────────────────────────────────┘ │
│  今天玩什么          选一个，马上开始 │ ← 学科区 2×2
│  [学数学 今日3题] [学英语 今天还没练] │
│  [学语文 今日1题] [小游戏 今日2局]   │
│  我的学习乐园           共 N 次学习  │ ← 按天分组
│  ┌ 今天 9月15日 周二      [⭐+6] ┐  │
│  │ [icon] 20以内加法练习          │  │
│  │        小星数学老师 · 09:20 +3⭐│  │
│  │ …（>3 条折叠「展开其余 N 条」）  │  │
│  └───────────────────────────────┘  │
│  ┌ 昨天 … ┐                        │
│         [🔒 家长入口]               │ ← 居中小灰字
└────────────────────────────────────┘
```

- 问候行固定在 Scroll 外（现状保持）；Scroll 内为 hero → 学科区 → 学习乐园 → 家长入口，`space 16`。
- 首屏可点区域：hero 主 CTA、看明细、学科卡（§5 信息密度：首屏不出现第三层信息）。
- **删除**：12 活动宫格、2 列会话网格、吉祥物 `mascotFloatY` 循环浮动动画（§8 禁止持续运动；hero 内 ⭐ 改为静态 SVG）。

### 4.2 问候行（微调）

结构不变（头像 + 问候 + 累计星星药丸）。变更：
- 星星药丸的 `Text('⭐')` → `Image($rawfile('kids/star.svg'))` 14vp。
- 头像无昵称时的 fallback `'⭐'` → star.svg 图标。
- 字号对齐规范 §7：问候 17.5vp（原 19 可保留，取 ≥17 即可）、副文案 12vp。

### 4.3 Hero「继续学习」（一天一会话）

- **眉标**（mono 10.5vp `KIDS_ON_HERO_2`）：`今日学习 · M月D日 周X`（`KidsSubjectUtils.formatDateLabel`）。
- **标题**：23vp Bold `KIDS_ON_HERO`「继续学习」。
- **副文案**（12.5vp `KIDS_ON_HERO_2`，允许换行，不 ellipsis——v2.2 修正 6）：
  - 今日无小星老师会话：`小星老师 · 今天第一次学习，将开启新会话`
  - 已有：`小星老师 · 已进入今天的会话`
- **主 CTA**「开始今天的学习 ›」：白底胶囊 ≥44vp 高，点击（整卡 onClick 统一处理）：
  - 今日会话存在 → `onOpenSession(todaySessionId)`
  - 否则 → `onNewChat('', DEFAULT_ASSISTANT_ID)`
- **今日星星徽章**：`⭐ 今日 +N`（N=0 时显示 `今日 +0`，不隐藏——「今天还没来」动机的一部分）；数据 `StarRewardService.getTodaySummary()`。
- **看明细按钮**（44vp 触控高、描边胶囊）：`bindSheet` 弹 `KidsStarDetailSheet`（§4.6）。
- 「今日会话」判定：`kidsSessions()`（assistantId === default）中 `updatedAt >= getStartOfDayMs(now)` 的第一条（纯函数 `findTodaySession`，可测）。若 `utils/DateFormatUtils.ets` 无 `getStartOfDayMs` 则新增（对齐现有 `getStartOfWeekMs` 模式）。
- 刷新时机：沿用 `starRefreshTick` @Monitor + 宿主 didShow(navBar) 递增；回到主屏时重算今日会话（会话 updatedAt 已在返回时刷新）。

### 4.4 学科区「今天玩什么」（2×2）

**目录数据**（`KidsSubjectCatalog.ets`，取代 KidsActivityCatalog）：

```typescript
export interface KidsSubjectItem {
  id: string              // 'math' | 'english' | 'chinese' | 'games'
  assistantId: string     // 'kids_math' …
  label: string           // 学数学
  teacher: string         // 小星数学老师
  subtitle: string        // 口算 · 竖式 · 图形
  iconPath: string        // 'kids/math.svg'
  color: string           // KIDS_MATH（15% 淡底用）
  ink: string             // KIDS_MATH_INK（图标/文字用）
  startPrompt: string     // 点击后自动发送的引导语
  activityTypes: string[] // 今日计数归属的 StarActivityType 集合
}
```

- 副标题（原型锁定）：数学「口算 · 竖式 · 图形」/ 英语「听音 · 单词 · 认读」/ 语文「拼音 · 识字 · 写字」/ 游戏「华容道 · 迷宫 · 数独」。
- 引导语沿用 v1 措辞风格：`我想练数学题，请给我出题吧` 等（每学科一句）。
- **卡片结构**（19vp 圆角、`KIDS_SURFACE` 底、1px `KIDS_BORDER`、轻暖投影）：
  - 图标块 44×44vp / 圆角 14 / 学科色 15% 淡底（`withColorAlpha(color, '26')`）+ 24vp SVG 图标
  - 标题 17vp Bold（display 字重）`KIDS_FG`
  - 副标题 11.5vp `KIDS_MUTED`，固定 2 行高（min-height 对齐，避免卡片高度不齐）
  - 底部状态行（1px 虚线上边框分隔，mono 10.5vp `KIDS_SUBTLE`）：`今日 N 题` / `今天还没练`（games 量词用「局」）+ 右侧 `开始 ›`（ink 色 Bold）
- **今日计数**：`getTodayEvents()` 按 `activityType ∈ item.activityTypes` 计数（纯函数 `countTodayBySubject`）。归属按 activityType 而非会话助手——小星老师会话里出的数学题也计入「学数学」，语义是「今天练了几题」。`chat_correct` 不计入任何学科（它是泛聊天奖励）。映射表：
  - math: `math_quiz`
  - english: `english_quiz`, `picture_vocab`, `listening_quiz`
  - chinese: `pinyin_quiz`, `handwriting_practice`
  - games: `number_puzzle`, `maze`, `sudoku`, `matching_pairs`, `categorization`
- **点击** → `onNewChat(item.startPrompt, item.assistantId)`：Index 先 `switchAssistant(assistantId)` 再推 ChatPage（沿用现有 `handleKidsNewChat` 的切换链路），autoSendInitialPrompt 自动发引导语。学科助手会话**不做一天一会话限制**——每次点击开新会话（孩子可能一天玩多局游戏；一天一会话仅 hero 语义）。

### 4.5 学习乐园（按天分组）

**取代** 2 列 KidsSessionCard 网格（该组件删除）。

- **数据范围**：`sessions` 中 `assistantId ∈ KIDS_BUILT_IN_ASSISTANT_IDS`（5 个）的会话；按 `updatedAt` 降序；按自然日分组；最多显示最近 **7 个有记录的天**（`KIDS_GARDEN_DAY_LIMIT`），天内记录全显（受会话总量自然约束，不再需要 v1 的 20 条硬上限——若单日超多仍受折叠保护）。
- **区块头**：`我的学习乐园` 17.5vp Bold + 右侧 `共 N 次学习`（11.5vp `KIDS_SUBTLE`，N=显示的会话总数）。
- **天卡**（`KidsDayGroupCard.ets`，20vp 圆角 surface 卡）：
  - 头部：`今天` / `昨天` / `M月D日`（display 15vp Bold）+ `M月D日 周X`（11.5vp muted；今天/昨天时显示日期+周几）+ 右侧当日星星汇总药丸 `⭐ +N`（金 24% 淡底、`KIDS_ON_GOLD` 字）
  - 记录行（≥44vp 高，行间 1px `KIDS_BORDER` 分隔，首行无上边框）：
    - 学科图标块 36×36vp（学科色 15% 淡底 + 20vp SVG）；小星老师会话用 star.svg + 暖橙淡底
    - 主文案：会话标题（13.5vp Medium，单行 ellipsis）+ 次行 `老师名 · HH:mm`（11vp `KIDS_SUBTLE` mono）
    - 右侧 `+N⭐`（display 13vp Bold `KIDS_ON_GOLD`；N=0 显示灰色 `0`，对齐原型 `.rec-stars .z`）
  - 点击记录行 → `onOpenSession(session.id)`
  - **折叠**：同日 >3 条时只显示前 3 条 + 「展开其余 N 条」通栏按钮（44vp 高、虚线上边框），展开后变「收起」；展开状态是 `KidsDayGroupCard` 内部 `@Local`，不持久化
- **当日星星汇总数据**：`DatabaseService.getStarTotalsByDay(sinceMs): Promise<Map<string, number>>`（新增）——`SELECT createdAt, stars FROM star_events WHERE createdAt >= ?`，按本地日 key（`YYYY-MM-DD`）求和；`sinceMs` = 最早显示天的 0 点。按事件 `createdAt` 归日（非会话时间），与 hero「今日 +N」同源同口径。
- **老师名/图标映射**：`session.assistantId → KidsSubjectItem`（default → 小星老师 + star 图标 + accent 色）；纯函数 `subjectForAssistantId`。
- **空态**：无任何会话时整个区块不渲染（与 v1 一致；§12 结论——不编造空态界面）。

### 4.6 今日星星明细 sheet（KidsStarDetailSheet.ets 新组件）

**不复用**成人壳 `components/chat/TodayStarDetailSheet.ets`（它跟随主题色 + 含日历模式，重刷样式会波及成人侧；儿童皮肤恒定暖色）。新建轻量版，对照原型 `.sheet`：

- `bindSheet`（FIT_CONTENT 或 LARGE 视内容、dragBar、preferType BOTTOM）
- 头部：`今日星星` 18vp Bold + 右侧 ✕ 圆钮（44vp，close.svg）
- **star-hero**：金 14% 淡底圆角块 + 48vp 金星徽章 + `N` 31vp display Bold + `颗 · 今日获得` 12.5vp muted
- **分类汇总**（`N 类活动`）：按学科聚合今日事件——每行 = 学科图标块 32vp + 名称（`数学题`/`英语题`/`语文题`/`小游戏`，chat_correct 归入「聊天问答」行用 star 图标）+ 次行 `答对 N 题` / `完成 N 局` + 右侧星星数（display 20vp `KIDS_ON_GOLD`）
- **今日明细**（`共 N 条`）：时间（mono 11vp `HH:mm`）+ 描述（活动类型 → 中文文案，复用 `StarEventModels.getActivityMeta` 的 label）+ `+N⭐` 药丸（英语绿 ink 淡底）；0 星事件显示灰药丸
- 数据：`getTodaySummary()` + `getTodayEvents()`（现有 API，自加载）
- 空态：`今天还没有获得星星，去学习吧`（居中 muted + 淡金 star 图标）——此为可达状态，允许（区别于 §12「不适用」的不可达空态）

### 4.7 家长入口（ParentalGateSheet 两阶段扩展）

- 底部入口不变：lock.svg + `家长入口`（12vp `KIDS_SUBTLE`，46vp 高居中）。
- `ParentalGateSheet` 增加 `@Local phase: 'gate' | 'summary'`：
  - **gate 阶段**：现有算术门原样（数字键盘、抖动、换题）。答对 → `phase = 'summary'` 并加载数据（不再直接 `onPassed`）。错误色 `KIDS_DANGER` 改用 `KIDS_CHINESE_INK`（§6：答错 = 语文橙红，不新增状态色；`KIDS_DANGER` 令牌保留但儿童 UI 不再引用）。
  - **summary 阶段**（对照原型 `renderParentSummary`）：
    - 眉标 `家长视图 · M月D日 周X`（mono、`KIDS_ON_GOLD`）+ 一句 `XX今天的学习情况，一眼读懂`
    - star-hero（同 §4.6 样式）
    - 学科分布：今日有事件的学科行（图标 + 名称 + `答对 N 题`/`完成 N 局` + 星星数）
    - 今日记录：时间 + 描述 + `+N⭐` 药丸（同 §4.6 明细行）
    - 说明条：`完整报告与历史趋势在家长设置中查看`（11.5vp muted、fg 5% 淡底圆角条）
    - **「进入家长设置」**主按钮（48vp、暖橙底、`KIDS_ON_HERO` 字）→ `onPassed()`（Index 现有 `handleKidsGatePassed` 进成人壳，行为不变）
    - **「知道了」**次按钮（48vp、描边胶囊）→ `onCancelled()` 关 sheet 回主屏
  - sheet 关闭重置 `phase = 'gate'`（下次进入重新验证——门的语义不因看过概览而放松）
- 数据加载失败：summary 降级只显示 star-hero（0 颗）+ 两个按钮，不阻塞进入家长设置。

### 4.8 令牌更新（KidsBrandTokens.ets）

| 变更 | 值 |
|---|---|
| `KIDS_SUBTLE` 修正 | `#7A7268` → `#746E64`（v2.2 修正 4，对比度 4.76/4.97） |
| 新增 `KIDS_MATH` / `KIDS_MATH_INK` | `#4E8FE0` / `#1D64BE` |
| 新增 `KIDS_ENGLISH` / `KIDS_ENGLISH_INK` | `#35A98A` / `#22735D` |
| 新增 `KIDS_CHINESE` / `KIDS_CHINESE_INK` | `#E2603C` / `#B53917` |
| 新增 `KIDS_GAMES` / `KIDS_GAMES_INK` | `#8B72E0` / `#6A49DB` |

（`KIDS_STAR` 已存在；ink 变体专用于文字/图标，原色仅 15% 淡底——§6 锁定。）

### 4.9 图标（resources/rawfile/kids/*.svg）

原型 9 个 symbol 移植为 8 个独立 SVG 文件（sound.svg 本期用不到——听力卡的 TTS 喇叭属 ChatPage 卡片，不在主屏范围）：

| 文件 | 来源 symbol | baked 颜色 |
|---|---|---|
| `star.svg` | i-star（fill 路径） | `#F5B301` |
| `math.svg` | i-math | `#1D64BE` |
| `english.svg` | i-english | `#22735D` |
| `chinese.svg` | i-chinese | `#B53917` |
| `games.svg` | i-games | `#6A49DB` |
| `lock.svg` | i-lock | `#746E64` |
| `chevron.svg` | i-chev | `#24211C` |
| `close.svg` | i-close | `#6F6A60` |

- 渲染：`Image($rawfile('kids/xxx.svg')).width(n).height(n)`；儿童皮肤恒定浅色 → 颜色 baked-in，**不用 fillColor 运行时着色**（规避 stroke 路径对 fillColor 支持的不确定性）。
- 学科 SVG 只用 ink 色（所有出现处——学科卡、记录行、家长概览——都是同一 ink 色，符合规范）。
- hero CTA 的 `›` 用 chevron.svg（14vp）；「开始 ›」同理（12vp，但 chevron baked 为 fg 色——学科卡上的 go 箭头原型是 ink 色，**为每学科追加 chevron 变体不值得**：go 箭头改用文字 `›`（U+203A）以 ink 色渲染，仅 CTA 用 SVG。此为对原型的最小偏差，记录于此）。
- 主屏全面去 emoji：`⭐`（3 处）、`🔒`（1 处）、活动宫格 emoji（随宫格删除）、`→` CTA 箭头（换 chevron.svg）。

---

## 5. Index.ets 集成

| 触点 | 变更 |
|---|---|
| `isKidsAllowedSessionId` | `assistantId === DEFAULT_ASSISTANT_ID` → `KIDS_BUILT_IN_ASSISTANT_IDS.includes(assistantId)`（历史遗留 `''` 会话仍拦截） |
| `handleKidsNewChat` | 签名扩为 `(initialPrompt: string = '', assistantId: string = DEFAULT_ASSISTANT_ID)`；切换逻辑从硬编码 DEFAULT 改为目标 assistantId（沿用现有 switchAssistant → openChatRoute 链路） |
| `KidsRoot()` | `KidsHomeView` 事件接线：`onNewChat(prompt, assistantId)`、`onOpenSession` 不变；`starRefreshTick` / `topInsetVp` 不变 |
| ChatPage 相关拦截 | `isKidsUiActive()` 下对 pendingInteraction / 通知路由的 `isKidsAllowedSessionId` 过滤（Index.ets:1683/1726/1789 一带）自动随谓词放宽，无需逐处改 |

**已知影响**：学科卡点击会把 `currentAssistantId` 切到学科助手（持久）。成人壳「当前助手」随之变化——与现状（儿童模式强制切回 default）同类行为，可接受；成人用户手动切回即可。儿童主屏 hero 始终显式传 `DEFAULT_ASSISTANT_ID`，不受残留 currentAssistantId 影响。

---

## 6. 纯函数与测试（utils/KidsSubjectUtils.ets + ohosTest）

ArkUI-free 纯函数（对齐 `utils/MathQuizGame.ets` 抽取模式）：

| 函数 | 职责 |
|---|---|
| `countTodayBySubject(events: StarEventRow[], activityTypes: string[]): number` | 学科今日计数 |
| `groupSessionsByDay(sessions: ChatSession[], nowMs: number, dayLimit: number): KidsDayGroup[]` | 按天分组（今天/昨天/日期标签 + 组内降序 + 天数截断），`KidsDayGroup { dayKey, label, subLabel, sessions }` |
| `findTodaySession(sessions: ChatSession[], startOfDayMs: number): ChatSession \| null` | hero 一天一会话判定 |
| `formatDateLabel(date: Date): string` / `formatWeekday(date: Date): string` | `9月15日` / `周二` |
| `subjectForAssistantId(id: string): KidsSubjectItem \| null` | 会话 → 学科元数据（default 返回 null，调用方回退小星老师样式） |
| `getStartOfDayMs(nowMs: number): number` | 若 DateFormatUtils 缺则在那里新增 |

hypium 单测（`entry/src/ohosTest/ets/test/utils/KidsSubjectUtils.test.ets`）：分组跨天边界（23:59 vs 00:01）、dayLimit 截断、chat_correct 不计入学科、今天/昨天标签、今日会话判定空/非空。运行方式：DevEco Studio 右键 Run（CLI `hvigorw test` 在本项目不可用，见 MEMORY）。

---

## 7. 动效与交互约束（brand-spec §8 锁定）

- **保留**：按压反馈（学科卡/记录行 `scale 0.98` + 60–80ms）、sheet 滑入（bindSheet 默认）、星星数值变化过渡（`animateTo` 数值或透明度过渡，≤400ms）。
- **删除**：吉祥物循环浮动（`mascotFloatY` 无限动画）。
- **禁止新增**：循环动画、自动轮播、>400ms 转场。
- 触控目标：学科卡整卡 ≥44vp、记录行 ≥44vp、看明细/✕/展开按钮 ≥44vp、家长入口 46vp。
- 无障碍：学科卡 `accessibilityText('打开' + label)`；星星药丸 `accessibilityText('累计获得 N 颗星')`；今日徽章同理；SVG 图标不单独可聚焦（装饰性）。

---

## 8. 实施顺序（供 plan 拆任务参考）

1. 令牌 + SVG 图标资源 + `KidsSubjectUtils` 纯函数 + hypium 测试（无 UI 依赖，先行）
2. 助手定义 + AssistantService ensure/锁定/保护 + `DatabaseService.getStarTotalsByDay`
3. Index.ets 接线（isKidsAllowedSessionId / handleKidsNewChat / KidsRoot）
4. KidsHomeView 重写（问候行微调 + hero + 学科区）
5. KidsDayGroupCard + 学习乐园分组
6. KidsStarDetailSheet + hero 看明细
7. ParentalGateSheet 两阶段扩展
8. 删除 KidsActivityCatalog / KidsSessionCard + 全量 grep emoji 残留
9. `hvigorw assembleHap` 干净编译 + 真机走查（对照 §9 验收清单）
10. 更新 `.claude/rules/teaching-architecture.md`（助手表、锁定语义、触点清单）与 `docs/brand-spec.md` 的落地状态注记

---

## 9. 验收清单

**功能**
- [ ] 4 学科助手冷启动自动补建（老用户升级场景），成人壳不可删除/改名/改提示词/改工具
- [ ] 学科卡点击 → 进入对应学科助手新会话并自动发送引导语，AI 只用该学科工具出题
- [ ] hero：当天首次点击开新会话；再次点击续接同一今日会话；副文案两态正确
- [ ] 今日 +N 与看明细 sheet 数字一致（同 getTodaySummary 口径）
- [ ] 学科卡「今日 N 题」= 今日 star_events 按 activityType 映射计数；chat_correct 不计入
- [ ] 学习乐园按天分组、当日星星汇总正确、同日 >3 条折叠/展开、点击记录行进入对应会话（含学科助手会话）
- [ ] 家长门答对 → 今日概览（星星/学科分布/记录）→「进入家长设置」进成人壳 /「知道了」回主屏；关闭后重开需重新验证
- [ ] 备课老师仍只被小星老师会话触发；学科助手会话不注入今日计划

**视觉（brand-spec §5–§10）**
- [ ] 主屏无 emoji（图标全部 SVG）；无循环动画
- [ ] 暖橙每屏 ≤2 处（hero 渐变 + CTA 区徽章不计——按 §6 口径：眉标与主 CTA）；学科色只作 15% 淡底 + ink 图标/文字
- [ ] `KIDS_SUBTLE` = `#746E64`；ink 色文字对比度 ≥4.5:1（令牌已核验，不改值）
- [ ] 触控目标全部 ≥44vp；正文 ≥12vp（proto 11–11.5vp 的小字仅用于眉标/状态行，非正文）
- [ ] 深色模式下儿童主屏保持恒定暖色皮肤

**工程**
- [ ] `hvigorw assembleHap` 零错误
- [ ] KidsSubjectUtils hypium 用例全绿（DevEco Studio 运行）
- [ ] `KidsActivityCatalog.ets` / `KidsSessionCard.ets` 已删除且无残留 import
- [ ] teaching-architecture.md 已同步

---

## 10. 已知限制与取舍

| 限制 | 原因 | 缓解 |
|---|---|---|
| 学科助手会话切走 `currentAssistantId` | ChatPage 新会话依赖当前助手，无 route 级 assistantId | 与 v1 行为同类；hero 显式传 default 不受影响 |
| 「今日 N 题」按 activityType 归属，小星老师会话出的数学题也计入数学 | 语义是「今天练了什么」而非「跟谁练」 | 视为特性；家长概览同口径 |
| go 箭头用文字 `›` 而非 ink 色 SVG | 避免为 4 学科各做 chevron 变体 | §4.9 记录的最小原型偏差 |
| KidsStarDetailSheet 与成人 TodayStarDetailSheet 并存两套 | 儿童皮肤恒定暖色 + 无日历模式，改造共享组件回归风险大 | 数据同源（StarRewardService），仅视图分离 |
| 学科助手不进备课管线 | 备课按「全科一日计划」设计，学科助手是专项陪练 | 画像更新仍生效，备课老师次日可见学科弱项 |
