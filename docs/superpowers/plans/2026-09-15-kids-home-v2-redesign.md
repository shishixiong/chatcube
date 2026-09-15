# 儿童主屏 v2 重构 + 四学科专用助手 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按冻结品牌规范 v2 把儿童主屏重构为三段式（问候行 / hero 一天一会话 / 2×2 学科卡 / 按天分组学习乐园），新增 4 个学科专用内置助手，家长门升级为「门 → 今日概览」两阶段。

**Architecture:** 4 个学科助手作为内置锁定助手持久化到 SQLite（对齐 `default` 小星老师的 ensure/normalize/delete-guard 三件套）；儿童主屏组件全部重写为恒定暖色皮肤（SVG 图标颜色 baked-in）；纯函数抽到 `utils/KidsSubjectUtils.ets` 用 hypium 单测；会话链路完全复用现有 ChatPage / 星星记录 / 画像链路（零特殊分支）；备课老师管线保持只服务 `default`。

**Tech Stack:** HarmonyOS 6 (API 23) ArkTS/ArkUI（@ComponentV2/@Local/@Param/@Event/@Monitor、bindSheet、Navigation）、relationalStore SQLite、@ohos/hypium 单测、rawfile SVG。

**Spec:** `docs/superpowers/specs/2026-09-15-kids-home-v2-redesign-design.md`（本 plan 的验收基准；执行时 spec 与 plan 都要读）

## Global Constraints

- **ArkTS 严格模式**（MEMORY.md）：不允许 `const [a, b] = ...` 解构；`arr.map(p => ({...}))` 内联对象字面量必须显式标注 lambda 返回类型；ForEach 回调体内不能写 `const x: Foo = {...}` 声明——抽成返回已构造对象的方法；对象字面量必须有显式目标类型。
- **JSON-in-template-literal 陷阱**：系统提示词内如需引号示例，用「」中文方头括号；写完提示词后不能只看编译通过，需人工核对无 ASCII `"` 嵌入 JSON schema 场景（本 plan 的提示词不进 rawSchemaJson，风险低但仍遵守）。
- **品牌规范 v2 硬约束**（`docs/brand-spec.md`）：儿童主屏恒定暖色皮肤（不随深色模式）；主屏零 emoji（图标全部 `Image($rawfile('kids/xxx.svg'))`）；无循环动画（删除 `mascotFloatY`）；暖橙每屏 ≤2 处；学科色只作 15% 淡底（原色）+ ink 变体（文字/图标）；触控目标 ≥44vp；`KIDS_SUBTLE` 改为 `#746E64`。
- **备课管线不动**：`LessonPlanningService.notifySessionEnd` 仅接受 `assistantId === 'default'`（现有过滤不改）；`ChatViewModel.injectDailyPlanSections` 的 `DEFAULT_ASSISTANT_ID` 条件不改。
- **编译验证命令**（每个任务收尾必须干净）：
  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```
- **测试运行方式**：CLI `hvigorw test` 在本项目不可用（MEMORY.md）。hypium 测试写完标注「DevEco Studio 右键 Run 验证」，执行者在无 IDE 环境下以「编译干净 + 测试代码走查」代替，并在 commit message 注明测试待 IDE 运行。
- **分支**：`refine_new_entry`（spec 已提交在此分支，commit `251c04a`）。
- 文件路径均相对 `entry/src/main/ets/`（另注者除外）。

---

### Task 1: 品牌令牌更新 + 8 个 SVG 图标资源

**Files:**
- Modify: `components/kids/KidsBrandTokens.ets`
- Create: `entry/src/main/resources/rawfile/kids/star.svg`（及 math/english/chinese/games/lock/chevron/close 共 8 个）

**Interfaces:**
- Consumes: 无（纯资源任务）
- Produces: 令牌 `KIDS_SUBTLE='#746E64'`、`KIDS_MATH/KIDS_MATH_INK/KIDS_ENGLISH/KIDS_ENGLISH_INK/KIDS_CHINESE/KIDS_CHINESE_INK/KIDS_GAMES/KIDS_GAMES_INK`；图标路径 `kids/star.svg` 等 8 个（后续任务用 `Image($rawfile('kids/xxx.svg'))` 引用）

- [ ] **Step 1: 更新 KidsBrandTokens.ets**

把 `KIDS_SUBTLE` 从 `'#7A7268'` 改为 `'#746E64'`（注释同步为「三级文字（v2.2 修正 4：bg 4.76 / surface 4.97 对比度）」），并在文件末尾追加：

```typescript
/** 学科色 · 学数学（仅 15% 淡底用；文字/图标用 KIDS_MATH_INK） */
export const KIDS_MATH: string = '#4E8FE0'
/** 学数学墨色（文字/图标专用，surface 对比 5.71） */
export const KIDS_MATH_INK: string = '#1D64BE'
/** 学科色 · 学英语 */
export const KIDS_ENGLISH: string = '#35A98A'
/** 学英语墨色（5.62） */
export const KIDS_ENGLISH_INK: string = '#22735D'
/** 学科色 · 学语文 */
export const KIDS_CHINESE: string = '#E2603C'
/** 学语文墨色（5.80；家长门答错也借用此色，§6 状态语义） */
export const KIDS_CHINESE_INK: string = '#B53917'
/** 学科色 · 小游戏 */
export const KIDS_GAMES: string = '#8B72E0'
/** 小游戏墨色（5.76） */
export const KIDS_GAMES_INK: string = '#6A49DB'
```

`KIDS_DANGER` 令牌保留不删（spec §4.7：儿童 UI 不再引用，令牌本身留着）。

- [ ] **Step 2: 创建 8 个 SVG 图标**

新建目录 `entry/src/main/resources/rawfile/kids/`。8 个文件内容如下（源自原型 symbol，`currentColor` 替换为 baked 颜色；儿童皮肤恒定浅色，不用 fillColor 运行时着色）：

`star.svg`（fill 路径，星星金）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#F5B301" d="M12 2.6l2.92 5.9 6.53.95-4.72 4.6 1.11 6.5L12 17.42 6.16 20.55l1.11-6.5-4.72-4.6 6.53-.95z"/></svg>
```

`math.svg`（加号，数学墨色）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#1D64BE" stroke-width="2.2" stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
```

`english.svg`（书本，英语墨色）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#22735D" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M4 19V6a1 1 0 0 1 1-1h5.5a3.5 3.5 0 0 1 3.5 3.5V19M14 8.5h5a1 1 0 0 1 1 1V19M3 19h18"/></svg>
```

`chinese.svg`（毛笔，语文墨色）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#B53917" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M12 20h9M16.4 3.6a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>
```

`games.svg`（手柄，游戏墨色）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="#6A49DB" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="7" width="19" height="11" rx="4"/><path d="M7 12.5h3M8.5 11v3M15.6 12h.01M17.6 14h.01"/></g></svg>
```

`lock.svg`（挂锁，KIDS_SUBTLE 色）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="#746E64" stroke-width="2"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></g></svg>
```

`chevron.svg`（右箭头，KIDS_FG 色——用于 hero 白底 CTA 内）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#24211C" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/></svg>
```

`close.svg`（叉，KIDS_MUTED 色）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#6F6A60" stroke-width="2.2" stroke-linecap="round" d="M6 6l12 12M18 6L6 18"/></svg>
```

- [ ] **Step 3: 编译验证 + 提交**

Run: 全局编译命令（见 Global Constraints）。Expected: BUILD SUCCESSFUL（rawfile 不参与编译，令牌是纯常量追加）。

```bash
git add entry/src/main/ets/components/kids/KidsBrandTokens.ets entry/src/main/resources/rawfile/kids/
git commit -m "feat(kids): v2 品牌令牌（KIDS_SUBTLE 修正 + 8 学科令牌）+ 8 个 monoline SVG 图标"
```

---

### Task 2: DateFormatUtils.getStartOfDayMs + hypium 测试（TDD）

**Files:**
- Modify: `utils/DateFormatUtils.ets`（在 `getStartOfWeekMs` 附近追加）
- Test: `entry/src/ohosTest/ets/test/utils/DateFormatUtils.test.ets`（现有文件内追加 describe 块）

**Interfaces:**
- Consumes: 无
- Produces: `export function getStartOfDayMs(timestamp: number): number` —— 返回 timestamp 所在本地自然日 00:00:00.000 的毫秒时间戳。Task 6/8/9/12 都依赖它。

- [ ] **Step 1: 写失败测试**

在 `DateFormatUtils.test.ets` 顶部 import 追加 `getStartOfDayMs`，文件末尾（`export default function dateFormatUtilsTest()` 内部）追加：

```typescript
describe('getStartOfDayMs', () => {
  it('midday rolls back to same day 00:00', 0, () => {
    const noon = new Date(2026, 8, 15, 14, 30, 15, 500).getTime()
    const expected = new Date(2026, 8, 15, 0, 0, 0, 0).getTime()
    expect(getStartOfDayMs(noon)).assertEqual(expected)
  })

  it('00:00:00.000 returns itself', 0, () => {
    const midnight = new Date(2026, 8, 15, 0, 0, 0, 0).getTime()
    expect(getStartOfDayMs(midnight)).assertEqual(midnight)
  })

  it('23:59:59.999 stays on same day', 0, () => {
    const late = new Date(2026, 8, 15, 23, 59, 59, 999).getTime()
    const expected = new Date(2026, 8, 15, 0, 0, 0, 0).getTime()
    expect(getStartOfDayMs(late)).assertEqual(expected)
  })

  it('00:01 next day belongs to next day (cross-boundary)', 0, () => {
    const early = new Date(2026, 8, 16, 0, 1, 0, 0).getTime()
    const expected = new Date(2026, 8, 16, 0, 0, 0, 0).getTime()
    expect(getStartOfDayMs(early)).assertEqual(expected)
  })
})
```

- [ ] **Step 2: 验证测试失败**

无法 CLI 跑（MEMORY）：验证方式为编译失败——`getStartOfDayMs` 尚未导出，DevEco 打开测试文件应报未定义。若执行环境无 IDE，grep 确认 `utils/DateFormatUtils.ets` 无此导出即视为 RED。

Run: `grep -c "getStartOfDayMs" entry/src/main/ets/utils/DateFormatUtils.ets`
Expected: `0`

- [ ] **Step 3: 最小实现**

在 `utils/DateFormatUtils.ets` 的 `getStartOfWeekMs` 之后追加（对齐其风格）：

```typescript
/**
 * 返回 timestamp 所在本地自然日的 00:00:00.000 时间戳。
 * 供儿童主屏「今日会话判定 / 今日星星 / 按天分组」使用
 * （与 StarRewardService 内部私有的 getStartOfTodayMs 同口径）。
 */
export function getStartOfDayMs(timestamp: number): number {
  const date = new Date(timestamp)
  date.setHours(0, 0, 0, 0)
  return date.getTime()
}
```

- [ ] **Step 4: 编译验证 + 测试走查**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。
测试：DevEco Studio 右键 `DateFormatUtils.test.ets` → Run（无 IDE 环境则记录「待 IDE 验证」）。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/DateFormatUtils.ets entry/src/ohosTest/ets/test/utils/DateFormatUtils.test.ets
git commit -m "feat(utils): getStartOfDayMs 自然日起点纯函数 + 4 hypium 用例"
```

---

### Task 3: KidsSubjectCatalog 学科元数据目录

**Files:**
- Create: `components/kids/KidsSubjectCatalog.ets`

**Interfaces:**
- Consumes: Task 1 的令牌（`KIDS_MATH` 等 8 个）
- Produces:
  - `export interface KidsSubjectItem { id: string; assistantId: string; label: string; teacher: string; subtitle: string; iconPath: string; color: string; ink: string; countUnit: string; startPrompt: string; activityTypes: string[] }`
  - `export const KIDS_SUBJECTS: KidsSubjectItem[]`（4 项，顺序 math/english/chinese/games）
  - `export function subjectForAssistantId(assistantId: string): KidsSubjectItem | null`（default/未知 → null）
  - Task 5/6/9/10/11/12 全部消费此目录。

- [ ] **Step 1: 写目录文件（完整内容）**

```typescript
import {
  KIDS_MATH,
  KIDS_MATH_INK,
  KIDS_ENGLISH,
  KIDS_ENGLISH_INK,
  KIDS_CHINESE,
  KIDS_CHINESE_INK,
  KIDS_GAMES,
  KIDS_GAMES_INK
} from './KidsBrandTokens'

/**
 * 儿童主屏「今天玩什么」2×2 学科目录（纯数据，无 ArkUI 依赖）。
 * 取代 v1 的 KidsActivityCatalog（12 emoji 宫格，已删）。
 *
 * 每学科绑定一个专用内置助手（spec §3）；activityTypes 决定「今日 N 题」
 * 的星星事件归属（按 activityType 而非会话助手，chat_correct 不计入任何学科）。
 */
export interface KidsSubjectItem {
  /** 稳定标识 'math' | 'english' | 'chinese' | 'games'（ForEach key） */
  id: string
  /** 对应内置学科助手 id */
  assistantId: string
  /** 卡片标题 */
  label: string
  /** 老师名（记录行次行 / 家长概览用） */
  teacher: string
  /** 卡片副标题（原型锁定文案） */
  subtitle: string
  /** rawfile SVG 图标路径（ink 色 baked-in） */
  iconPath: string
  /** 学科原色（仅 15% 淡底用） */
  color: string
  /** 学科墨色（文字/图标用） */
  ink: string
  /** 今日计数量词：题 / 局 */
  countUnit: string
  /** 点击卡片后自动发送的引导语 */
  startPrompt: string
  /** 「今日 N 题」计数归属的 StarActivityType 集合 */
  activityTypes: string[]
}

export const KIDS_SUBJECTS: KidsSubjectItem[] = [
  {
    id: 'math',
    assistantId: 'kids_math',
    label: '学数学',
    teacher: '小星数学老师',
    subtitle: '口算 · 竖式 · 图形',
    iconPath: 'kids/math.svg',
    color: KIDS_MATH,
    ink: KIDS_MATH_INK,
    countUnit: '题',
    startPrompt: '我想练数学题，请给我出题吧',
    activityTypes: ['math_quiz']
  },
  {
    id: 'english',
    assistantId: 'kids_english',
    label: '学英语',
    teacher: '小星英语老师',
    subtitle: '听音 · 单词 · 认读',
    iconPath: 'kids/english.svg',
    color: KIDS_ENGLISH,
    ink: KIDS_ENGLISH_INK,
    countUnit: '题',
    startPrompt: '我想练英语，请给我出题吧',
    activityTypes: ['english_quiz', 'picture_vocab', 'listening_quiz']
  },
  {
    id: 'chinese',
    assistantId: 'kids_chinese',
    label: '学语文',
    teacher: '小星语文老师',
    subtitle: '拼音 · 识字 · 写字',
    iconPath: 'kids/chinese.svg',
    color: KIDS_CHINESE,
    ink: KIDS_CHINESE_INK,
    countUnit: '题',
    startPrompt: '我想学语文，请带我练拼音和写字吧',
    activityTypes: ['pinyin_quiz', 'handwriting_practice']
  },
  {
    id: 'games',
    assistantId: 'kids_games',
    label: '小游戏',
    teacher: '小星游戏老师',
    subtitle: '华容道 · 迷宫 · 数独',
    iconPath: 'kids/games.svg',
    color: KIDS_GAMES,
    ink: KIDS_GAMES_INK,
    countUnit: '局',
    startPrompt: '我想玩益智小游戏，请开始一局吧',
    activityTypes: ['number_puzzle', 'maze', 'sudoku', 'matching_pairs', 'categorization']
  }
]

/** 会话 assistantId → 学科元数据；default / 未知返回 null（调用方回退小星老师样式） */
export function subjectForAssistantId(assistantId: string): KidsSubjectItem | null {
  for (let i = 0; i < KIDS_SUBJECTS.length; i++) {
    if (KIDS_SUBJECTS[i].assistantId === assistantId) {
      return KIDS_SUBJECTS[i]
    }
  }
  return null
}
```

注意：ArkTS 对 `export const X: T[] = [ {...}, ... ]` 带显式类型标注的对象字面量数组是合法的（有显式目标类型）。若编译器报 `arkts-no-untyped-obj-literals`，为每项加中间常量（`const MATH_ITEM: KidsSubjectItem = {...}`）再组数组。

- [ ] **Step 2: 编译验证 + 提交**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。

```bash
git add entry/src/main/ets/components/kids/KidsSubjectCatalog.ets
git commit -m "feat(kids): KidsSubjectCatalog 四学科元数据目录（取代 KidsActivityCatalog）"
```

---

### Task 4: 四学科助手定义（models/AssistantModels.ets）

**Files:**
- Modify: `models/AssistantModels.ets`（文件末尾追加）

**Interfaces:**
- Consumes: 现有工具 ID 常量（`utils/SearchToolIdentityUtils.ets` 已全部 import 到本文件顶部——19 个常量都在，无需新增 import）；`Assistant` 类、`createDefaultAssistant()` 模式、`SHARED_IDENTITY` / `buildBasePrompt`（已 import）。
- Produces:
  - `export const KIDS_MATH_ASSISTANT_ID: string = 'kids_math'`（及 english/chinese/games 同构）
  - `export const KIDS_SUBJECT_ASSISTANT_IDS: string[]`（4 个）
  - `export const KIDS_BUILT_IN_ASSISTANT_IDS: string[]`（含 `'default'` 共 5 个；Task 5/8/9 消费）
  - `export interface KidsSubjectAssistantSpec { id: string; name: string; color: string; avatarSymbol: string; systemPrompt: string; lockedToolIds: string[]; sortOrder: number }`
  - `export function getBuiltInAssistantSpec(id: string): KidsSubjectAssistantSpec | null`（5 个内置 id → spec；其他 → null。Task 5 的 normalizeAssistant 消费）
  - `export function createKidsSubjectAssistants(): Assistant[]`（4 个，Task 5 的 ensure 消费）

- [ ] **Step 1: 追加 4 个助手 id 常量 + 锁定工具子集**

在 `models/AssistantModels.ets` 的 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 之后追加：

```typescript
// ── 儿童学科专用助手（spec 2026-09-15 §3）──────────────────────────
export const KIDS_MATH_ASSISTANT_ID: string = 'kids_math'
export const KIDS_ENGLISH_ASSISTANT_ID: string = 'kids_english'
export const KIDS_CHINESE_ASSISTANT_ID: string = 'kids_chinese'
export const KIDS_GAMES_ASSISTANT_ID: string = 'kids_games'

/** 4 个学科助手 id（不含 default） */
export const KIDS_SUBJECT_ASSISTANT_IDS: string[] = [
  KIDS_MATH_ASSISTANT_ID,
  KIDS_ENGLISH_ASSISTANT_ID,
  KIDS_CHINESE_ASSISTANT_ID,
  KIDS_GAMES_ASSISTANT_ID
]

/** 儿童模式内置助手全集（default + 4 学科）：儿童主屏会话放行 / 删除保护都用它 */
export const KIDS_BUILT_IN_ASSISTANT_IDS: string[] = [
  DEFAULT_ASSISTANT_ID,
  KIDS_MATH_ASSISTANT_ID,
  KIDS_ENGLISH_ASSISTANT_ID,
  KIDS_CHINESE_ASSISTANT_ID,
  KIDS_GAMES_ASSISTANT_ID
]

export const KIDS_MATH_LOCKED_TOOL_IDS: string[] = [
  ASK_USER_TOOL_ID, CHILD_PROFILE_TOOL_ID, GET_TIME_INFO_TOOL_ID, GRANT_STAR_TOOL_ID,
  MATH_VERIFY_TOOL_ID, MATH_QUIZ_TOOL_ID, VERTICAL_MATH_TOOL_ID
]

export const KIDS_ENGLISH_LOCKED_TOOL_IDS: string[] = [
  ASK_USER_TOOL_ID, CHILD_PROFILE_TOOL_ID, GET_TIME_INFO_TOOL_ID, GRANT_STAR_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID, PICTURE_VOCAB_TOOL_ID, LISTENING_QUIZ_TOOL_ID
]

export const KIDS_CHINESE_LOCKED_TOOL_IDS: string[] = [
  ASK_USER_TOOL_ID, CHILD_PROFILE_TOOL_ID, GET_TIME_INFO_TOOL_ID, GRANT_STAR_TOOL_ID,
  PINYIN_QUIZ_TOOL_ID, HANDWRITING_PRACTICE_TOOL_ID
]

export const KIDS_GAMES_LOCKED_TOOL_IDS: string[] = [
  ASK_USER_TOOL_ID, CHILD_PROFILE_TOOL_ID, GET_TIME_INFO_TOOL_ID, GRANT_STAR_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID, MAZE_TOOL_ID, SUDOKU_TOOL_ID, MATCHING_PAIRS_TOOL_ID, CATEGORIZATION_TOOL_ID
]
```

- [ ] **Step 2: 追加 4 个系统提示词**

统一骨架（spec §3.2）：身份 → 说话方式（逐字复用 `buildBasePrompt` 的回复限制段保持人格一致）→ 教学策略 → 学科出题策略 → 授星规则 → 边界。以下为完整内容，直接粘贴：

```typescript
// 学科助手系统提示词。结构与小星老师同源（SharedPromptFragments），按学科裁剪。
// 注意：提示词内引用工具参数值一律用「」，不得出现裸 ASCII 双引号包裹的示例 JSON。

export const KIDS_MATH_SYSTEM_PROMPT: string = [
  '你是「小星数学老师」,小星学习乐园里专门陪小朋友学数学的老师。',
  '你的回复对象始终是 5-7 岁的孩子,工具返回的元数据只给你自己看。',
  '',
  '## 说话方式',
  buildBasePrompt({
    includeReplyLimits: true,
    includeToolWhitelist: false,
    includeChildProfileRule: true,
    includeTopicKeyHint: false
  }),
  '- 答对了真诚夸赞,答错了温柔鼓励,绝不让他觉得笨。',
  '',
  '## 数学教学策略',
  '- 聚焦 8 个数学维度:math_counting / math_addition / math_subtraction / math_multiply / math_divide / math_shapes / math_comparison / math_time。',
  '- 根据 child_profile 各维度 level 选难度:level 0-1 从最基础开始(实物 + 数数),level 2-3 巩固练习,level 4-5 挑战更高阶。',
  '- 由易到难:一次只出 1 道题,答对再升一点难度,连错 2 次就降难度并鼓励。',
  '- 出题必须用 math_quiz 工具(带 type 字段:arithmetic / shape / comparison / time / elapsed_time / word_problem),不要在文字里编数学题。',
  '- 教「怎么算」用 vertical_math 演示竖式(数位对齐、进位、退位),演示后用 math_quiz 出 1-2 题巩固。',
  '- child_profile(action: "update") 只更新 math_ 开头的技能维度,notes 必须基于本轮具体表现。',
  '',
  '## 授星规则',
  '- math_quiz 答对系统自动记星;孩子在纯聊天里答对你出的数学问题,用 grant_star(reason: 「chat_correct」)授 1 星——口头说给星没用,必须调工具。孩子主动索要星星时绝对不给。',
  '',
  '## 边界',
  '- 小朋友问英语/语文/游戏内容时,简短友好地回答一句,然后引导回数学:「这个咱们回头找对应老师玩,先来看这道数学题好不好」。',
  '- 不出其他学科的题,不调用白名单之外的工具。'
].join('\n')

export const KIDS_ENGLISH_SYSTEM_PROMPT: string = [
  '你是「小星英语老师」,小星学习乐园里专门陪小朋友学英语的老师。',
  '你的回复对象始终是 5-7 岁的孩子,工具返回的元数据只给你自己看。',
  '',
  '## 说话方式',
  buildBasePrompt({
    includeReplyLimits: true,
    includeToolWhitelist: false,
    includeChildProfileRule: true,
    includeTopicKeyHint: false
  }),
  '- 答对了真诚夸赞,答错了温柔鼓励,绝不让他觉得笨。',
  '',
  '## 英语教学策略',
  '- 聚焦 4 个维度:english_alphabet / english_vocab / english_sentence / english_phonics。',
  '- 根据 child_profile 各维度 level 选难度,由易到难,一次只出 1 道题。',
  '- 听力题优先用 listening_quiz(卡片会朗读单词/字母,孩子 4 选 1);distractor 选发音相近的词(如 cat 配 car/cap/can)。',
  '- 看图识词用 picture_vocab(mode=en 看图选英文单词,mode=zh 看图选汉字);options 恰好 4 个含 correct_answer。',
  '- 常规词汇/字母/自然拼读题用 english_quiz,自然拼读用 phonics_choice 类型,sound_text 写 TTS 可读的拼音(如「kuh」)。',
  '- skill_key 对应:字母 english_alphabet,单词 english_vocab,phonics english_phonics。',
  '- child_profile(action: "update") 只更新 english_ 开头的技能维度,notes 必须基于本轮具体表现。',
  '',
  '## 授星规则',
  '- 出题工具答对系统自动记星;纯聊天里答对你出的英语问题,用 grant_star(reason: 「chat_correct」)授 1 星。孩子主动索要星星时绝对不给。',
  '',
  '## 边界',
  '- 小朋友问数学/语文/游戏内容时,简短友好地回答一句,然后引导回英语。',
  '- 不出其他学科的题,不调用白名单之外的工具。'
].join('\n')

export const KIDS_CHINESE_SYSTEM_PROMPT: string = [
  '你是「小星语文老师」,小星学习乐园里专门陪小朋友学语文的老师。',
  '你的回复对象始终是 5-7 岁的孩子,工具返回的元数据只给你自己看。',
  '',
  '## 说话方式',
  buildBasePrompt({
    includeReplyLimits: true,
    includeToolWhitelist: false,
    includeChildProfileRule: true,
    includeTopicKeyHint: false
  }),
  '- 答对了真诚夸赞,答错了温柔鼓励,绝不让他觉得笨。',
  '',
  '## 语文教学策略',
  '- 聚焦 3 个维度:pinyin / chinese_writing / fine_motor。',
  '- 根据 child_profile 各维度 level 选难度,由易到难,一次只练 1 个。',
  '- 拼音认读用 pinyin_quiz:看一个常见汉字,从 4 个带调拼音中选正确读音;character 必须从工具支持字表选,distractor 选形近字或韵母/声调相近的读音(如 山 shān 配 sān/shàn/shuān)。',
  '- 学写字用 handwriting_practice(type 固定「chinese」),每次只练 1 个字。',
  '- 推荐联动:先 pinyin_quiz 认读音,再 handwriting_practice 练同一个字。',
  '- child_profile(action: "update") 只更新 pinyin / chinese_writing / fine_motor 维度,notes 必须基于本轮具体表现。',
  '',
  '## 授星规则',
  '- 出题工具答对系统自动记星;纯聊天里答对你出的语文问题,用 grant_star(reason: 「chat_correct」)授 1 星。孩子主动索要星星时绝对不给。',
  '',
  '## 边界',
  '- 小朋友问数学/英语/游戏内容时,简短友好地回答一句,然后引导回语文。',
  '- 不出其他学科的题,不调用白名单之外的工具。'
].join('\n')

export const KIDS_GAMES_SYSTEM_PROMPT: string = [
  '你是「小星游戏老师」,小星学习乐园里专门陪小朋友玩益智游戏的老师。',
  '你的回复对象始终是 5-7 岁的孩子,工具返回的元数据只给你自己看。',
  '',
  '## 说话方式',
  buildBasePrompt({
    includeReplyLimits: true,
    includeToolWhitelist: false,
    includeChildProfileRule: true,
    includeTopicKeyHint: false
  }),
  '- 通关了热烈庆祝,放弃了也没关系,换个游戏继续开心。',
  '',
  '## 游戏教学策略',
  '- 聚焦 3 个维度:logic_thinking / observation / spatial_reasoning(外加 categorization)。',
  '- 5 个游戏轮换着玩,一局一邀(玩完一局再问下一局玩什么),不要一次连开两局:',
  '- number_puzzle 数字华容道:difficulty 2=幼儿·2×2,3=简单·3×3,4=进阶·4×4,5=挑战·5×5。',
  '- maze 走迷宫:difficulty 1=简单 4×4(5 岁),2=进阶 6×6(6-7 岁),3=挑战 8×8(7-8 岁)。',
  '- sudoku 数独:difficulty 1=4×4(5 岁),2=6×6(6 岁),3=9×9 简单,4=9×9 中等,5=9×9 挑战。',
  '- matching_pairs 连一连:左右列各 4-5 项配对(字↔拼音、动物↔它的家),观察力练习。',
  '- categorization 分类小管家:2-3 桶 4-9 件,引导小朋友说分类理由。',
  '- 难度按 child_profile 对应维度 level 选:level 0-1 用最低档,level 2-3 中档,level 4-5 高档。',
  '- child_profile(action: "update") 只更新 logic_thinking / observation / spatial_reasoning / categorization 维度,notes 必须基于本轮具体表现。',
  '',
  '## 授星规则',
  '- 游戏通关系统自动记星(华容道/数独按难度给多星);纯聊天里答对你出的推理问题,用 grant_star(reason: 「chat_correct」)授 1 星。孩子主动索要星星时绝对不给。',
  '',
  '## 边界',
  '- 小朋友想学数学/英语/语文时,简短友好地回应,然后引导去找对应的学科老师。',
  '- 不出学科练习题,不调用白名单之外的工具。'
].join('\n')
```

- [ ] **Step 3: 追加 spec 注册表 + 工厂函数**

```typescript
/** 内置助手规范（normalizeAssistant 锁定 + ensure 创建共用） */
export interface KidsSubjectAssistantSpec {
  id: string
  name: string
  color: string
  avatarSymbol: string
  systemPrompt: string
  lockedToolIds: string[]
  sortOrder: number
}

const KIDS_SUBJECT_SPECS: KidsSubjectAssistantSpec[] = [
  {
    id: KIDS_MATH_ASSISTANT_ID,
    name: '小星数学老师',
    color: '#4E8FE0',
    avatarSymbol: '数',
    systemPrompt: KIDS_MATH_SYSTEM_PROMPT,
    lockedToolIds: KIDS_MATH_LOCKED_TOOL_IDS,
    sortOrder: 1
  },
  {
    id: KIDS_ENGLISH_ASSISTANT_ID,
    name: '小星英语老师',
    color: '#35A98A',
    avatarSymbol: '英',
    systemPrompt: KIDS_ENGLISH_SYSTEM_PROMPT,
    lockedToolIds: KIDS_ENGLISH_LOCKED_TOOL_IDS,
    sortOrder: 2
  },
  {
    id: KIDS_CHINESE_ASSISTANT_ID,
    name: '小星语文老师',
    color: '#E2603C',
    avatarSymbol: '语',
    systemPrompt: KIDS_CHINESE_SYSTEM_PROMPT,
    lockedToolIds: KIDS_CHINESE_LOCKED_TOOL_IDS,
    sortOrder: 3
  },
  {
    id: KIDS_GAMES_ASSISTANT_ID,
    name: '小星游戏老师',
    color: '#8B72E0',
    avatarSymbol: '玩',
    systemPrompt: KIDS_GAMES_SYSTEM_PROMPT,
    lockedToolIds: KIDS_GAMES_LOCKED_TOOL_IDS,
    sortOrder: 4
  }
]

/**
 * 按 id 查内置助手规范（含 default 小星老师）。
 * AssistantService.normalizeAssistant 用它锁定 5 个内置助手的
 * name/systemPrompt/enabledToolIds；非内置 id 返回 null。
 */
export function getBuiltInAssistantSpec(id: string): KidsSubjectAssistantSpec | null {
  if (id === DEFAULT_ASSISTANT_ID) {
    return {
      id: DEFAULT_ASSISTANT_ID,
      name: '小星老师',
      color: '#FF9F43',
      avatarSymbol: '⭐',
      systemPrompt: DEFAULT_ASSISTANT_SYSTEM_PROMPT,
      lockedToolIds: DEFAULT_ASSISTANT_LOCKED_TOOL_IDS,
      sortOrder: 0
    }
  }
  for (let i = 0; i < KIDS_SUBJECT_SPECS.length; i++) {
    if (KIDS_SUBJECT_SPECS[i].id === id) {
      return KIDS_SUBJECT_SPECS[i]
    }
  }
  return null
}

/** 创建 4 个学科助手实例（DatabaseService.ensureKidsSubjectAssistants 消费） */
export function createKidsSubjectAssistants(): Assistant[] {
  const result: Assistant[] = []
  for (let i = 0; i < KIDS_SUBJECT_SPECS.length; i++) {
    const spec: KidsSubjectAssistantSpec = KIDS_SUBJECT_SPECS[i]
    const assistant = new Assistant(spec.id, spec.name)
    assistant.avatarSymbol = spec.avatarSymbol
    assistant.color = spec.color
    assistant.isDefault = false
    assistant.sortOrder = spec.sortOrder
    assistant.systemPrompt = spec.systemPrompt
    assistant.enabledToolIds = [...spec.lockedToolIds]
    result.push(assistant)
  }
  return result
}
```

注意：`getBuiltInAssistantSpec` 的 default 分支返回对象字面量——因函数返回类型已标注 `KidsSubjectAssistantSpec | null`，字面量有显式目标类型，合法。若 ArkTS 仍报错，抽 `const spec: KidsSubjectAssistantSpec = {...}; return spec`。

- [ ] **Step 4: 编译验证 + 提示词引号走查**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。
走查：`grep -n '「chat_correct」' entry/src/main/ets/models/AssistantModels.ets` 确认 4 处授星示例用的是中文方头括号而非 ASCII 引号。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(assistants): 四学科专用助手定义（id/提示词/锁定工具/spec 注册表/工厂）"
```

---

### Task 5: 助手生命周期——ensure 创建 + normalize 锁定 + 删除/编辑保护

**Files:**
- Modify: `services/DatabaseService.ets`（`ensureDefaultAssistant()` 调用点之后，~line 651；方法体加在 `ensureDefaultAssistant` 之后 ~line 1287）
- Modify: `services/AssistantService.ets`（`normalizeAssistant` ~line 122-138；`deleteAssistant` guard ~line 301-304）
- Modify: `pages/Index.ets`（助手编辑保护点：line 2968 `fillAssistantEditorForm`、3071、3089、3813、3831、3847、3851——`editingAssistantIsDefault` 的全部消费点）

**Interfaces:**
- Consumes: Task 4 的 `createKidsSubjectAssistants()` / `getBuiltInAssistantSpec(id)` / `KIDS_BUILT_IN_ASSISTANT_IDS`
- Produces: 启动后 DB 中恒有 5 个内置助手；`AssistantService.deleteAssistant(kids_xxx)` 返回 false；成人壳编辑器对 5 个内置助手禁改名/禁改提示词/禁改工具白名单。Task 8 依赖助手真实存在。

- [ ] **Step 1: DatabaseService 追加 ensureKidsSubjectAssistants**

在 `DatabaseService.ets` 的 `ensureDefaultAssistant()` 方法体之后追加私有方法（对齐 default 的「查 → 不存在则 insert」模式；学科助手不做旧值迁移——normalizeAssistant 在读取路径兜底锁定）：

```typescript
  /**
   * 确保 4 个儿童学科助手存在（spec 2026-09-15 §3.3）。
   * 幂等：老用户升级后启动自动补建；已存在则跳过。
   */
  private async ensureKidsSubjectAssistants(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    const subjectAssistants: Assistant[] = createKidsSubjectAssistants()
    for (let i = 0; i < subjectAssistants.length; i++) {
      const assistant: Assistant = subjectAssistants[i]
      const existing = await this.queryAssistantByIdNoWait(assistant.id)
      if (existing !== null) {
        continue
      }
      try {
        await this.rdbStore.insert(TableNames.ASSISTANTS, this.assistantToValueBucket(assistant))
      } catch (error) {
        console.error('DatabaseService',
          `Failed to create kids subject assistant ${assistant.id}: ${JSON.stringify(error)}`)
      }
    }
  }
```

import 行更新：`DatabaseService.ets` 顶部现有 `import { ..., createDefaultAssistant } from '../models/AssistantModels'`——把 `createKidsSubjectAssistants` 加进同一 import（`Assistant` 类型已在 import 中；若没有则一并加上）。

调用点：`createTables` 流程中 `await this.ensureDefaultAssistant()`（~line 651）之后追加一行：

```typescript
      await this.ensureDefaultAssistant()
      await this.ensureKidsSubjectAssistants()
```

同时检查 `getAssistant` 的 fallback 创建路径（~line 1628，default 助手缺失时兜底重建处）：该 fallback 只针对 default，学科助手不需要兜底（normalizeAssistant 已保证读到的学科助手字段被锁定；DB 行丢失属极端场景，下次冷启动 ensure 会补建），**不改**。

- [ ] **Step 2: AssistantService.normalizeAssistant 扩展为注册表锁定**

把 `normalizeAssistant` 中现有的：

```typescript
    if (assistant.id === DEFAULT_ASSISTANT_ID) {
      assistant.isDefault = true
      // 锁定系统提示词和工具白名单：默认助手（小星老师）的值不可被覆盖
      assistant.systemPrompt = DEFAULT_ASSISTANT_SYSTEM_PROMPT
      assistant.enabledToolIds = [...DEFAULT_ASSISTANT_LOCKED_TOOL_IDS]
    }
```

替换为：

```typescript
    const builtInSpec = getBuiltInAssistantSpec(assistant.id)
    if (builtInSpec !== null) {
      assistant.isDefault = assistant.id === DEFAULT_ASSISTANT_ID
      // 锁定名称/系统提示词/工具白名单：5 个内置助手（小星老师 + 4 学科老师）不可被覆盖
      assistant.name = builtInSpec.name
      assistant.systemPrompt = builtInSpec.systemPrompt
      assistant.enabledToolIds = [...builtInSpec.lockedToolIds]
    }
```

import 更新：`AssistantService.ets` 顶部从 `AssistantModels` 的 import 中追加 `getBuiltInAssistantSpec`、`KIDS_BUILT_IN_ASSISTANT_IDS`（下一步用）。`DEFAULT_ASSISTANT_SYSTEM_PROMPT` / `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 若在本文件再无其他引用则从 import 移除（grep 确认后再删）。

- [ ] **Step 3: AssistantService.deleteAssistant 保护扩展**

把 ~line 301-304 的：

```typescript
    if (assistantId === DEFAULT_ASSISTANT_ID || isPresetAssistant(assistantId)) {
      return false
    }
```

替换为：

```typescript
    if (KIDS_BUILT_IN_ASSISTANT_IDS.includes(assistantId) || isPresetAssistant(assistantId)) {
      return false
    }
```

（`KIDS_BUILT_IN_ASSISTANT_IDS` 含 `DEFAULT_ASSISTANT_ID`，语义是超集替换。）

- [ ] **Step 4: Index.ets 助手编辑器保护扩展**

`editingAssistantIsDefault` 是编辑器「禁改名/禁改提示词/禁改工具/禁删除」的统一开关（line 2968 赋值；3071 名称输入框禁用；3089 保存时工具白名单强制回锁定列表；3813/3831/3847/3851 删除按钮隐藏/提示词区禁用等）。改赋值处即可让 4 个学科助手享受同等保护：

line 2968 的：
```typescript
    this.editingAssistantIsDefault = assistant.id === DEFAULT_ASSISTANT_ID || assistant.isDefault
```
替换为：
```typescript
    this.editingAssistantIsDefault = KIDS_BUILT_IN_ASSISTANT_IDS.includes(assistant.id) || assistant.isDefault
```

**副作用核查**（必须做）：`editingAssistantIsDefault` 为 true 时保存路径 line 3089 会把 `enabledToolIds` 强制写成 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`、line 3095 会写 `isDefault = true`。逐一读这两处：
- line 3089 附近若是 `assistant.enabledToolIds = this.editingAssistantIsDefault ? [...DEFAULT_ASSISTANT_LOCKED_TOOL_IDS] : [...]`，改为按 spec 取锁定列表：
  ```typescript
    const builtInSpec = getBuiltInAssistantSpec(assistant.id)
    assistant.enabledToolIds = builtInSpec !== null ? [...builtInSpec.lockedToolIds] : this.assistantFormEnabledToolIds
  ```
- line 3095 `assistant.isDefault = this.editingAssistantIsDefault` 改为 `assistant.isDefault = assistant.id === DEFAULT_ASSISTANT_ID`（学科助手 isDefault 必须保持 false——否则会出现 5 个「默认助手」）。
- 其余消费点（3813/3831/3847/3851 的 UI 禁用/隐藏）语义不变，无需改。

import 更新：Index.ets line 21 的 AssistantModels import 追加 `KIDS_BUILT_IN_ASSISTANT_IDS`、`getBuiltInAssistantSpec`。

- [ ] **Step 5: 编译验证 + 提交**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。
走查：`grep -n "editingAssistantIsDefault" entry/src/main/ets/pages/Index.ets` 逐行确认没有遗漏的 `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 硬编码写入点。

```bash
git add entry/src/main/ets/services/DatabaseService.ets entry/src/main/ets/services/AssistantService.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat(assistants): 学科助手启动补建 + normalize 注册表锁定 + 删除/编辑保护扩展"
```

---

### Task 6: KidsSubjectUtils 纯函数 + hypium 测试（TDD）

**Files:**
- Create: `utils/KidsSubjectUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/KidsSubjectUtils.test.ets`（新文件）

**Interfaces:**
- Consumes: Task 2 `getStartOfDayMs`；Task 3 `KIDS_SUBJECTS` / `KidsSubjectItem` / `subjectForAssistantId`；`models/ChatModels.ChatSession`；`models/StarEventModels.StarEventRow` / `getActivityMeta`；`utils/DateFormatUtils.formatYMD`
- Produces（Task 9/10/11/12 消费，签名必须一致）:
  - `export class KidsDayGroup { dayKey: string = ''; label: string = ''; subLabel: string = ''; sessions: ChatSession[] = [] }`（**class 而非 interface**——供 @Param 默认值）
  - `export function countTodayBySubject(events: StarEventRow[], activityTypes: string[]): number`
  - `export function groupSessionsByDay(sessions: ChatSession[], nowMs: number, dayLimit: number): KidsDayGroup[]`
  - `export function findTodaySession(sessions: ChatSession[], startOfDayMs: number): ChatSession | null`
  - `export function formatDateLabel(timestamp: number): string`（→ `9月15日`）
  - `export function formatWeekday(timestamp: number): string`（→ `周二`）
  - `export function formatHourMinute(timestamp: number): string`（→ `09:20`）
  - `export interface KidsTodayCategoryRow { iconPath: string; tint: string; name: string; detail: string; stars: number }` + `export function buildTodayCategoryRows(events: StarEventRow[]): KidsTodayCategoryRow[]`
  - `export interface KidsTodayEventRow { timeLabel: string; description: string; stars: number }` + `export function buildTodayEventRows(events: StarEventRow[]): KidsTodayEventRow[]`

- [ ] **Step 1: 写失败测试（完整测试文件）**

创建 `entry/src/ohosTest/ets/test/utils/KidsSubjectUtils.test.ets`：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { ChatSession } from '../../../../main/ets/models/ChatModels'
import { StarEventRow } from '../../../../main/ets/models/StarEventModels'
import { getStartOfDayMs } from '../../../../main/ets/utils/DateFormatUtils'
import {
  countTodayBySubject,
  groupSessionsByDay,
  findTodaySession,
  formatDateLabel,
  formatWeekday,
  formatHourMinute,
  buildTodayCategoryRows,
  buildTodayEventRows,
  KidsDayGroup
} from '../../../../main/ets/utils/KidsSubjectUtils'

function makeSession(id: string, assistantId: string, updatedAt: number): ChatSession {
  const session = new ChatSession()
  session.id = id
  session.assistantId = assistantId
  session.title = `会话${id}`
  session.updatedAt = updatedAt
  return session
}

function makeEvent(activityType: string, stars: number, createdAt: number): StarEventRow {
  return {
    id: createdAt,
    createdAt: createdAt,
    activityType: activityType,
    stars: stars,
    toolCallId: '',
    sessionId: '',
    skillKey: '',
    metadataJson: ''
  } as StarEventRow
}

export default function kidsSubjectUtilsTest() {
  describe('countTodayBySubject', () => {
    it('counts only events whose activityType is in the subject set', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [
        makeEvent('math_quiz', 1, now),
        makeEvent('math_quiz', 0, now),
        makeEvent('english_quiz', 1, now),
        makeEvent('chat_correct', 1, now)
      ]
      expect(countTodayBySubject(events, ['math_quiz'])).assertEqual(2)
      expect(countTodayBySubject(events, ['english_quiz', 'picture_vocab', 'listening_quiz'])).assertEqual(1)
    })

    it('chat_correct never counts into any subject', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [makeEvent('chat_correct', 1, now)]
      expect(countTodayBySubject(events, ['math_quiz'])).assertEqual(0)
      expect(countTodayBySubject(events, ['number_puzzle', 'maze', 'sudoku', 'matching_pairs', 'categorization']))
        .assertEqual(0)
    })
  })

  describe('groupSessionsByDay', () => {
    it('groups today and yesterday with correct labels, newest day first', 0, () => {
      const now = new Date(2026, 8, 15, 14, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('a', 'default', new Date(2026, 8, 15, 9, 20, 0, 0).getTime()),
        makeSession('b', 'kids_math', new Date(2026, 8, 14, 18, 0, 0, 0).getTime()),
        makeSession('c', 'default', new Date(2026, 8, 15, 11, 0, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 7)
      expect(groups.length).assertEqual(2)
      expect(groups[0].label).assertEqual('今天')
      expect(groups[0].sessions.length).assertEqual(2)
      // 组内按 updatedAt 降序
      expect(groups[0].sessions[0].id).assertEqual('c')
      expect(groups[1].label).assertEqual('昨天')
      expect(groups[1].subLabel).assertEqual('9月14日 周一')
    })

    it('cross-day boundary: 23:59 and 00:01 fall into different days', 0, () => {
      const now = new Date(2026, 8, 16, 8, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('late', 'default', new Date(2026, 8, 15, 23, 59, 0, 0).getTime()),
        makeSession('early', 'default', new Date(2026, 8, 16, 0, 1, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 7)
      expect(groups.length).assertEqual(2)
      expect(groups[0].label).assertEqual('今天')
      expect(groups[0].sessions[0].id).assertEqual('early')
      expect(groups[1].label).assertEqual('昨天')
      expect(groups[1].sessions[0].id).assertEqual('late')
    })

    it('dayLimit truncates to the most recent N days with records', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('d0', 'default', new Date(2026, 8, 15, 9, 0, 0, 0).getTime()),
        makeSession('d1', 'default', new Date(2026, 8, 14, 9, 0, 0, 0).getTime()),
        makeSession('d2', 'default', new Date(2026, 8, 13, 9, 0, 0, 0).getTime()),
        makeSession('d3', 'default', new Date(2026, 8, 12, 9, 0, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 3)
      expect(groups.length).assertEqual(3)
      expect(groups[2].sessions[0].id).assertEqual('d2')
    })

    it('older than yesterday uses plain date label', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('x', 'default', new Date(2026, 8, 10, 9, 0, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 7)
      expect(groups[0].label).assertEqual('9月10日')
      expect(groups[0].subLabel).assertEqual('周四')
    })
  })

  describe('findTodaySession', () => {
    it('returns null when no session updated today', 0, () => {
      const startOfDay = getStartOfDayMs(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())
      const sessions: ChatSession[] = [
        makeSession('old', 'default', new Date(2026, 8, 14, 23, 0, 0, 0).getTime())
      ]
      expect(findTodaySession(sessions, startOfDay)).assertNull()
    })

    it('returns the most recently updated session of today', 0, () => {
      const startOfDay = getStartOfDayMs(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())
      const sessions: ChatSession[] = [
        makeSession('morning', 'default', new Date(2026, 8, 15, 8, 0, 0, 0).getTime()),
        makeSession('noon', 'default', new Date(2026, 8, 15, 12, 30, 0, 0).getTime())
      ]
      const found = findTodaySession(sessions, startOfDay)
      expect(found !== null).assertTrue()
      expect(found?.id).assertEqual('noon')
    })
  })

  describe('date formatters', () => {
    it('formatDateLabel renders M月D日', 0, () => {
      expect(formatDateLabel(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())).assertEqual('9月15日')
      expect(formatDateLabel(new Date(2026, 11, 1, 12, 0, 0, 0).getTime())).assertEqual('12月1日')
    })

    it('formatWeekday renders 周X', 0, () => {
      // 2026-09-15 是周二
      expect(formatWeekday(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())).assertEqual('周二')
      // 2026-09-13 是周日
      expect(formatWeekday(new Date(2026, 8, 13, 12, 0, 0, 0).getTime())).assertEqual('周日')
    })

    it('formatHourMinute renders HH:mm with zero padding', 0, () => {
      expect(formatHourMinute(new Date(2026, 8, 15, 9, 5, 0, 0).getTime())).assertEqual('09:05')
      expect(formatHourMinute(new Date(2026, 8, 15, 23, 59, 0, 0).getTime())).assertEqual('23:59')
    })
  })

  describe('buildTodayCategoryRows', () => {
    it('aggregates by subject with count and stars, chat_correct as 聊天问答', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [
        makeEvent('math_quiz', 1, now),
        makeEvent('math_quiz', 1, now),
        makeEvent('sudoku', 3, now),
        makeEvent('chat_correct', 1, now)
      ]
      const rows = buildTodayCategoryRows(events)
      expect(rows.length).assertEqual(3)
      expect(rows[0].name).assertEqual('数学题')
      expect(rows[0].detail).assertEqual('答对 2 题')
      expect(rows[0].stars).assertEqual(2)
      expect(rows[1].name).assertEqual('小游戏')
      expect(rows[1].detail).assertEqual('完成 1 局')
      expect(rows[1].stars).assertEqual(3)
      expect(rows[2].name).assertEqual('聊天问答')
      expect(rows[2].stars).assertEqual(1)
    })

    it('subjects without events are omitted', 0, () => {
      const rows = buildTodayCategoryRows([])
      expect(rows.length).assertEqual(0)
    })
  })

  describe('buildTodayEventRows', () => {
    it('renders time + grantedHint description + stars, newest first', 0, () => {
      const morning = new Date(2026, 8, 15, 9, 20, 0, 0).getTime()
      const noon = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [
        makeEvent('math_quiz', 1, morning),
        makeEvent('maze', 0, noon)
      ]
      const rows = buildTodayEventRows(events)
      expect(rows.length).assertEqual(2)
      expect(rows[0].timeLabel).assertEqual('12:00')
      expect(rows[0].stars).assertEqual(0)
      expect(rows[1].timeLabel).assertEqual('09:20')
      expect(rows[1].stars).assertEqual(1)
    })
  })
}
```

同时把注册加进 `entry/src/ohosTest/ets/test/List.test.ets`（虽然当前只挂了 abilityTest，但新文件应可被 IDE 单跑；对齐现有结构追加）：

```typescript
import abilityTest from './Ability.test';
import kidsSubjectUtilsTest from './utils/KidsSubjectUtils.test';

export default function testsuite() {
  abilityTest();
  kidsSubjectUtilsTest();
}
```

（若追加后 IDE 全量 suite 因其他 utils 测试未注册而行为异常，回退为只保留 import 注释——单文件右键 Run 不依赖 List.test.ets。）

- [ ] **Step 2: 验证测试失败**

Run: `grep -c "KidsSubjectUtils" entry/src/main/ets/utils/ 2>/dev/null; ls entry/src/main/ets/utils/KidsSubjectUtils.ets`
Expected: 文件不存在（RED）。

- [ ] **Step 3: 实现 utils/KidsSubjectUtils.ets（完整内容）**

```typescript
import { ChatSession } from '../models/ChatModels'
import { StarActivityType, StarEventRow, getActivityMeta } from '../models/StarEventModels'
import { formatYMD, getStartOfDayMs } from './DateFormatUtils'
import { KIDS_SUBJECTS, KidsSubjectItem } from '../components/kids/KidsSubjectCatalog'
import { KIDS_ACCENT } from '../components/kids/KidsBrandTokens'

/**
 * 儿童主屏 v2 纯函数集（spec 2026-09-15 §6）。
 * ArkUI-free，hypium 可测。utils/ → components/kids/ 的 import 仅为
 * 纯数据目录（KidsSubjectCatalog 无 ArkUI 依赖），不构成 UI 耦合。
 */

/** 学习乐园按天分组的一天（class：供 @Param 默认值） */
export class KidsDayGroup {
  dayKey: string = ''
  /** 今天 / 昨天 / 9月10日 */
  label: string = ''
  /** 今天/昨天 → 「9月15日 周二」；更早 → 「周二」 */
  subLabel: string = ''
  sessions: ChatSession[] = []
}

/** 今日星星明细 sheet 的分类汇总行 */
export interface KidsTodayCategoryRow {
  iconPath: string
  /** 图标块 15% 淡底基色 */
  tint: string
  name: string
  /** 答对 N 题 / 完成 N 局 */
  detail: string
  stars: number
}

/** 今日星星明细 sheet 的单条事件行 */
export interface KidsTodayEventRow {
  timeLabel: string
  description: string
  stars: number
}

const WEEKDAY_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

/** 学科今日计数：events 已由调用方限定为今日 */
export function countTodayBySubject(events: StarEventRow[], activityTypes: string[]): number {
  let count = 0
  for (let i = 0; i < events.length; i++) {
    if (activityTypes.includes(events[i].activityType)) {
      count++
    }
  }
  return count
}

/** hero 一天一会话判定：今日（updatedAt >= startOfDayMs）最近更新的一条 */
export function findTodaySession(sessions: ChatSession[], startOfDayMs: number): ChatSession | null {
  let found: ChatSession | null = null
  for (let i = 0; i < sessions.length; i++) {
    const session: ChatSession = sessions[i]
    if (session.updatedAt >= startOfDayMs) {
      if (found === null || session.updatedAt > found.updatedAt) {
        found = session
      }
    }
  }
  return found
}

/** M月D日 */
export function formatDateLabel(timestamp: number): string {
  const date = new Date(timestamp)
  return `${date.getMonth() + 1}月${date.getDate()}日`
}

/** 周二 */
export function formatWeekday(timestamp: number): string {
  return WEEKDAY_NAMES[new Date(timestamp).getDay()]
}

/** HH:mm（补零） */
export function formatHourMinute(timestamp: number): string {
  const date = new Date(timestamp)
  const hour: string = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`
  const minute: string = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`
  return `${hour}:${minute}`
}

/**
 * 按本地自然日分组：入参 sessions 已按 updatedAt 降序（调用方保证），
 * 输出天组降序（今天在前）、组内保持降序、最多 dayLimit 个有记录的天。
 */
export function groupSessionsByDay(sessions: ChatSession[], nowMs: number, dayLimit: number): KidsDayGroup[] {
  const groups: KidsDayGroup[] = []
  const groupByDayKey: Map<string, KidsDayGroup> = new Map()
  const todayKey: string = formatYMD(nowMs)
  const yesterdayKey: string = formatYMD(nowMs - 24 * 60 * 60 * 1000)
  for (let i = 0; i < sessions.length; i++) {
    const session: ChatSession = sessions[i]
    const dayKey: string = formatYMD(session.updatedAt)
    let group: KidsDayGroup | undefined = groupByDayKey.get(dayKey)
    if (group === undefined) {
      if (groups.length >= dayLimit) {
        continue
      }
      group = new KidsDayGroup()
      group.dayKey = dayKey
      if (dayKey === todayKey) {
        group.label = '今天'
        group.subLabel = `${formatDateLabel(session.updatedAt)} ${formatWeekday(session.updatedAt)}`
      } else if (dayKey === yesterdayKey) {
        group.label = '昨天'
        group.subLabel = `${formatDateLabel(session.updatedAt)} ${formatWeekday(session.updatedAt)}`
      } else {
        group.label = formatDateLabel(session.updatedAt)
        group.subLabel = formatWeekday(session.updatedAt)
      }
      group.sessions = []
      groups.push(group)
      groupByDayKey.set(dayKey, group)
    }
    group.sessions.push(session)
  }
  return groups
}

/**
 * 今日星星分类汇总：按学科聚合（chat_correct 归「聊天问答」行，小星老师样式）。
 * 输出顺序固定：数学 → 英语 → 语文 → 游戏 → 聊天问答，无事件的类别省略。
 */
export function buildTodayCategoryRows(events: StarEventRow[]): KidsTodayCategoryRow[] {
  const rows: KidsTodayCategoryRow[] = []
  for (let s = 0; s < KIDS_SUBJECTS.length; s++) {
    const subject: KidsSubjectItem = KIDS_SUBJECTS[s]
    let count = 0
    let stars = 0
    for (let i = 0; i < events.length; i++) {
      if (subject.activityTypes.includes(events[i].activityType)) {
        count++
        stars += events[i].stars
      }
    }
    if (count === 0) {
      continue
    }
    const verb: string = subject.id === 'games' ? '完成' : '答对'
    const row: KidsTodayCategoryRow = {
      iconPath: subject.iconPath,
      tint: subject.color,
      name: subject.id === 'games' ? '小游戏' : `${subject.label.slice(1)}题`,
      detail: `${verb} ${count} ${subject.countUnit}`,
      stars: stars
    }
    rows.push(row)
  }
  let chatCount = 0
  let chatStars = 0
  for (let i = 0; i < events.length; i++) {
    if (events[i].activityType === 'chat_correct') {
      chatCount++
      chatStars += events[i].stars
    }
  }
  if (chatCount > 0) {
    const chatRow: KidsTodayCategoryRow = {
      iconPath: 'kids/star.svg',
      tint: KIDS_ACCENT,
      name: '聊天问答',
      detail: `答对 ${chatCount} 题`,
      stars: chatStars
    }
    rows.push(chatRow)
  }
  return rows
}

/** 今日明细行：时间 + 活动描述（getActivityMeta.grantedHint）+ 星星，最新在前 */
export function buildTodayEventRows(events: StarEventRow[]): KidsTodayEventRow[] {
  const sorted: StarEventRow[] = [...events]
  sorted.sort((a: StarEventRow, b: StarEventRow): number => b.createdAt - a.createdAt)
  const rows: KidsTodayEventRow[] = []
  for (let i = 0; i < sorted.length; i++) {
    const row: KidsTodayEventRow = {
      timeLabel: formatHourMinute(sorted[i].createdAt),
      description: getActivityMeta(sorted[i].activityType as StarActivityType).grantedHint,
      stars: sorted[i].stars
    }
    rows.push(row)
  }
  return rows
}
```

**实现注意**：
- `getActivityMeta` 的入参类型是 `StarActivityType`；`StarEventRow.activityType` 是 `string`，实现里用 `as StarActivityType` 收窄（getActivityMeta 对未知值有 META_PUZZLE 兜底，运行时安全）。
- `name: subject.label.slice(1)` 把「学数学」变「数学题」——对齐 spec §4.6 的类别名（数学题/英语题/语文题/小游戏）。
- 若 `ChatSession` 无法 `new ChatSession()`（构造签名不符），测试 helper 改用其真实构造方式（读 `models/ChatModels.ets:799` 的构造函数后调整 `makeSession`；ChatSession 是 @ObservedV2 class，字段可赋值）。

- [ ] **Step 4: 编译验证 + 测试**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。
测试：DevEco Studio 右键 `KidsSubjectUtils.test.ets` → Run，Expected: 全绿（无 IDE 环境记录「待 IDE 验证」）。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/KidsSubjectUtils.ets entry/src/ohosTest/ets/test/utils/KidsSubjectUtils.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(kids): KidsSubjectUtils 纯函数（分组/今日判定/分类汇总）+ 13 hypium 用例"
```

---

### Task 7: DatabaseService.getStarTotalsByDay

**Files:**
- Modify: `services/DatabaseService.ets`（加在 `getStarTotalsBySession` ~line 3217 之后）

**Interfaces:**
- Consumes: 现有 `getStarEventsSince(startMs)`（line 3163）；`formatYMD`
- Produces: `async getStarTotalsByDay(sinceMs: number): Promise<Map<string, number>>` —— key 为本地日 `YYYY-MM-DD`（按事件 `createdAt` 归日），value 为当日星星总和。Task 9 学习乐园天卡的当日汇总消费。

- [ ] **Step 1: 实现**

```typescript
  /**
   * 按本地自然日聚合星星总数（儿童主屏学习乐园天卡头部「⭐ +N」用）。
   * - 按事件 createdAt 归日（非会话时间），与 hero「今日 +N」同源同口径
   * - client-side 聚合（对齐 getStarTotalsBySession 的 MVP 策略），走
   *   getStarEventsSince(sinceMs) 的 createdAt 索引，sinceMs = 最早显示天的 0 点
   * - 查询失败时 getStarEventsSince 内部已吞错返回 []，本方法随之返回空 Map
   */
  async getStarTotalsByDay(sinceMs: number): Promise<Map<string, number>> {
    const totals: Map<string, number> = new Map()
    const events: StarEventRow[] = await this.getStarEventsSince(sinceMs)
    for (let i = 0; i < events.length; i++) {
      const dayKey: string = formatYMD(events[i].createdAt)
      totals.set(dayKey, (totals.get(dayKey) ?? 0) + events[i].stars)
    }
    return totals
  }
```

import 核查：`DatabaseService.ets` 应已 import `StarEventRow`（getStarEventsSince 返回类型）；`formatYMD` 若未 import 则加 `import { formatYMD } from '../utils/DateFormatUtils'`（若该文件已有 DateFormatUtils import 行则合并）。

- [ ] **Step 2: 编译验证 + 提交**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。

```bash
git add entry/src/main/ets/services/DatabaseService.ets
git commit -m "feat(db): getStarTotalsByDay 按天星星汇总（学习乐园天卡用）"
```

---

### Task 8: Index.ets 接线（会话放行 + handleKidsNewChat + KidsRoot）

**Files:**
- Modify: `pages/Index.ets`（`isKidsAllowedSessionId` ~line 1315-1330；`handleKidsNewChat` ~line 1364；`KidsRoot()` ~line 2692-2711；import line 21）

**Interfaces:**
- Consumes: Task 4 `KIDS_BUILT_IN_ASSISTANT_IDS`、`DEFAULT_ASSISTANT_ID`
- Produces: `handleKidsNewChat(initialPrompt: string = '', assistantId: string = DEFAULT_ASSISTANT_ID)`；`KidsHomeView.onNewChat` 签名变为 `(initialPrompt: string, assistantId: string) => void`（Task 9 的 KidsHomeView 重写按此签名发事件）。

- [ ] **Step 1: isKidsAllowedSessionId 放宽到 5 个内置助手**

找到 ~line 1315 的注释与实现（`return this.sessions[i].assistantId === DEFAULT_ASSISTANT_ID`，line 1326），把判定改为：

```typescript
        return KIDS_BUILT_IN_ASSISTANT_IDS.includes(this.sessions[i].assistantId)
```

注释同步改为「儿童模式深链守卫: 放行 5 个内置助手（小星老师 + 4 学科老师）名下的会话; 历史遗留 '' 会话仍拦截」。

- [ ] **Step 2: handleKidsNewChat 增加 assistantId 参数**

把 ~line 1364 的 `private handleKidsNewChat(initialPrompt: string = ''): void {` 整段替换为：

```typescript
  /**
   * 儿童模式新建会话（spec 2026-09-15 §5）。
   * - hero 传 DEFAULT_ASSISTANT_ID + 空 prompt（一天一会话由 KidsHomeView 判定，
   *   已有今日会话时走 onOpenSession，不进这里）
   * - 学科卡传学科 assistantId + startPrompt：先 switchAssistant 再推 ChatPage，
   *   autoSendInitialPrompt 链路自动发引导语。学科会话不做一天一会话限制。
   */
  private handleKidsNewChat(initialPrompt: string = '', assistantId: string = DEFAULT_ASSISTANT_ID): void {
    const params: ChatPageRouteParams = initialPrompt.trim().length > 0 ?
    { initialPrompt: initialPrompt.trim() } as ChatPageRouteParams :
    {} as ChatPageRouteParams
    // 儿童模式会话必须落在内置助手上——家长可能把「当前助手」切成了自定义助手
    if (this.currentAssistantId !== assistantId) {
      this.switchAssistant(assistantId).then((): void => {
        this.openChatRoute(params)
      }).catch((error: Object): void => {
        console.error('Index', `Failed to switch assistant for kids chat: ${JSON.stringify(error)}`)
        this.openChatRoute(params)
      })
      return
    }
    this.openChatRoute(params)
  }
```

- [ ] **Step 3: KidsRoot 事件接线更新**

~line 2698 的：
```typescript
        onNewChat: (initialPrompt: string): void => this.handleKidsNewChat(initialPrompt),
```
替换为：
```typescript
        onNewChat: (initialPrompt: string, assistantId: string): void =>
          this.handleKidsNewChat(initialPrompt, assistantId),
```

**注意**：此改动在 Task 9 重写 KidsHomeView 之前会让 `@Event onNewChat` 签名不匹配（旧 KidsHomeView 声明的是 1 参）。ArkTS 对 @Event 回调多传参数是宽松的（旧组件调 `this.onNewChat('')` 仍兼容 2 参 handler），但为稳妥 **Task 8 与 Task 9 在同一编译验证点收口**：本任务结束时先不编译，直接进入 Task 9，Task 9 完成后统一编译提交两个 commit（或本任务先临时把旧 KidsHomeView 的 `onNewChat` 调用点补第二参 `DEFAULT_ASSISTANT_ID`——3 处：hero onClick、活动宫格 onClick——再独立编译提交）。采用后者：

在旧 `components/kids/KidsHomeView.ets` 中：
- `@Event onNewChat: (initialPrompt: string) => void = () => {}` 改为 `@Event onNewChat: (initialPrompt: string, assistantId: string) => void = () => {}`（同时 import `DEFAULT_ASSISTANT_ID` 已存在）
- line 306 `this.onNewChat('')` → `this.onNewChat('', DEFAULT_ASSISTANT_ID)`
- line 349 `this.onNewChat(item.startPrompt)` → `this.onNewChat(item.startPrompt, DEFAULT_ASSISTANT_ID)`（临时——旧活动宫格仍走小星老师，Task 13 整体删除）

- [ ] **Step 4: import 更新 + 编译验证**

Index.ets line 21 import 追加 `KIDS_BUILT_IN_ASSISTANT_IDS`（Task 5 已加过则跳过）。

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/pages/Index.ets entry/src/main/ets/components/kids/KidsHomeView.ets
git commit -m "feat(kids): Index 接线——会话放行 5 内置助手 + handleKidsNewChat 支持学科 assistantId"
```

---

### Task 9: KidsHomeView 重写（问候行 + hero 一天一会话 + 2×2 学科卡）

**Files:**
- Rewrite: `components/kids/KidsHomeView.ets`（本任务先交付：问候行 + hero + 学科区 + 家长入口占位；学习乐园分组在 Task 10 插入）

**Interfaces:**
- Consumes: Task 1 令牌/SVG；Task 2 `getStartOfDayMs`；Task 3 `KIDS_SUBJECTS`/`KidsSubjectItem`；Task 4 `DEFAULT_ASSISTANT_ID`/`KIDS_BUILT_IN_ASSISTANT_IDS`；Task 6 全部纯函数；Task 7 `getStarTotalsByDay`；Task 8 `onNewChat(prompt, assistantId)`；现有 `getStarRewardService()`（getTodaySummary/getTodayEvents/getAllTimeStarTotal）、`getDatabaseService().getStarTotalsBySession()`、`getChildProfileService()`、`getDayPartGreeting`、`withColorAlpha`
- Produces: `@Event onNewChat: (initialPrompt: string, assistantId: string) => void`；`@Event onOpenSession`、`@Event onGatePassed`、`@Param sessions/starRefreshTick/topInsetVp` 不变（Index 已接线）

- [ ] **Step 1: 重写组件骨架（状态与数据加载）**

整文件重写。import 区与状态区：

```typescript
import { ChatSession } from '../../models/ChatModels'
import { DEFAULT_ASSISTANT_ID, KIDS_BUILT_IN_ASSISTANT_IDS } from '../../models/AssistantModels'
import { StarEventRow, TodayStarSummary } from '../../models/StarEventModels'
import { getStarRewardService } from '../../services/StarRewardService'
import { getDatabaseService } from '../../services/DatabaseService'
import { getChildProfileService, ChildKnowledgeProfile } from '../../services/ChildProfileService'
import { getDayPartGreeting } from '../../utils/GreetingUtils'
import { getStartOfDayMs } from '../../utils/DateFormatUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  countTodayBySubject,
  findTodaySession,
  formatDateLabel,
  formatWeekday,
  groupSessionsByDay,
  KidsDayGroup
} from '../../utils/KidsSubjectUtils'
import { KIDS_SUBJECTS, KidsSubjectItem, subjectForAssistantId } from './KidsSubjectCatalog'
import { ParentalGateSheet } from './ParentalGateSheet'
import { KidsDayGroupCard } from './KidsDayGroupCard'
import { KidsStarDetailSheet } from './KidsStarDetailSheet'
import {
  KIDS_BG, KIDS_SURFACE, KIDS_FG, KIDS_MUTED, KIDS_SUBTLE, KIDS_BORDER,
  KIDS_ACCENT, KIDS_ACCENT_2, KIDS_STAR, KIDS_ON_HERO, KIDS_ON_HERO_2, KIDS_ON_GOLD,
  KIDS_AVATAR_INK, KIDS_AVATAR_1, KIDS_AVATAR_2, KIDS_GLASS
} from './KidsBrandTokens'

/** 学习乐园最多显示的「有记录的天」数 */
const KIDS_GARDEN_DAY_LIMIT: number = 7
```

struct 声明（@ComponentV2）：

```typescript
@ComponentV2
export struct KidsHomeView {
  @Param sessions: ChatSession[] = []
  @Param starRefreshTick: number = 0
  @Param topInsetVp: number = 0
  @Event onOpenSession: (sessionId: string) => void = () => {}
  /** 新建会话：hero 传 ('', DEFAULT)；学科卡传 (startPrompt, 学科 assistantId) */
  @Event onNewChat: (initialPrompt: string, assistantId: string) => void = () => {}
  @Event onGatePassed: () => void = () => {}
  @Local totalStars: number = 0
  @Local todayStars: number = 0
  @Local todayEvents: StarEventRow[] = []
  @Local childName: string = ''
  @Local starBySession: Map<string, number> = new Map()
  @Local starByDay: Map<string, number> = new Map()
  @Local showGateSheet: boolean = false
  @Local showStarDetailSheet: boolean = false

  @Monitor('starRefreshTick')
  onStarRefreshTickChanged(): void {
    this.loadAll()
  }

  @Monitor('sessions')
  onSessionsChanged(): void {
    // 回到主屏时会话 updatedAt 已刷新 → 重算今日会话与分组
  }

  aboutToAppear(): void {
    this.loadAll()
  }

  private loadAll(): void {
    getStarRewardService().getAllTimeStarTotal().then((total: number): void => {
      this.totalStars = total
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load total stars: ${JSON.stringify(error)}`)
    })
    getStarRewardService().getTodaySummary().then((summary: TodayStarSummary): void => {
      this.todayStars = summary.total
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load today summary: ${JSON.stringify(error)}`)
      this.todayStars = 0
    })
    getStarRewardService().getTodayEvents().then((events: StarEventRow[]): void => {
      this.todayEvents = events
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load today events: ${JSON.stringify(error)}`)
      this.todayEvents = []
    })
    getDatabaseService().getStarTotalsBySession().then((totals: Map<string, number>): void => {
      this.starBySession = totals
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load session star totals: ${JSON.stringify(error)}`)
      this.starBySession = new Map()
    })
    this.loadChildName()
    this.loadStarByDay()
  }

  private loadChildName(): void {
    getChildProfileService().getProfile().then((profile: ChildKnowledgeProfile): void => {
      this.childName = profile.childName.trim()
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load child profile: ${JSON.stringify(error)}`)
      this.childName = ''
    })
  }

  /** sinceMs = 最早显示天的 0 点（先分组拿最早 session，再查按天汇总） */
  private loadStarByDay(): void {
    const groups: KidsDayGroup[] = this.dayGroups()
    if (groups.length === 0) {
      this.starByDay = new Map()
      return
    }
    const lastGroup: KidsDayGroup = groups[groups.length - 1]
    const oldest: ChatSession = lastGroup.sessions[lastGroup.sessions.length - 1]
    const sinceMs: number = getStartOfDayMs(oldest.updatedAt)
    getDatabaseService().getStarTotalsByDay(sinceMs).then((totals: Map<string, number>): void => {
      this.starByDay = totals
    }).catch((error: Object): void => {
      console.error('KidsHomeView', `Failed to load day star totals: ${JSON.stringify(error)}`)
      this.starByDay = new Map()
    })
  }
```

派生数据方法（全部纯计算，build 内调用）：

```typescript
  /** 5 个内置助手的会话（'' 遗留会话不可见），updatedAt 降序 */
  private kidsSessions(): ChatSession[] {
    const filtered: ChatSession[] = this.sessions.filter((session: ChatSession): boolean =>
      KIDS_BUILT_IN_ASSISTANT_IDS.includes(session.assistantId))
    filtered.sort((a: ChatSession, b: ChatSession): number => b.updatedAt - a.updatedAt)
    return filtered
  }

  private todayDefaultSessions(): ChatSession[] {
    return this.kidsSessions().filter((session: ChatSession): boolean =>
      session.assistantId === DEFAULT_ASSISTANT_ID)
  }

  /** hero 一天一会话：今日的小星老师会话（无则 null） */
  private todaySession(): ChatSession | null {
    return findTodaySession(this.todayDefaultSessions(), getStartOfDayMs(Date.now()))
  }

  private dayGroups(): KidsDayGroup[] {
    return groupSessionsByDay(this.kidsSessions(), Date.now(), KIDS_GARDEN_DAY_LIMIT)
  }

  private todayCountFor(subject: KidsSubjectItem): number {
    return countTodayBySubject(this.todayEvents, subject.activityTypes)
  }

  private displayName(): string {
    return this.childName.length > 0 ? this.childName : '小朋友'
  }

  private avatarChar(): string {
    return this.childName.length > 0 ? this.childName.substring(0, 1) : ''
  }

  private greetingText(): string {
    return `${getDayPartGreeting(new Date().getHours())}，${this.displayName()}`
  }

  private heroDateLabel(): string {
    const now: number = Date.now()
    return `今日学习 · ${formatDateLabel(now)} ${formatWeekday(now)}`
  }

  private heroSubtitle(): string {
    return this.todaySession() !== null ?
      '小星老师 · 已进入今天的会话' :
      '小星老师 · 今天第一次学习，将开启新会话'
  }

  private starCountFor(sessionId: string): number {
    return this.starBySession.get(sessionId) ?? 0
  }
```

- [ ] **Step 2: build()——问候行（微调）**

```typescript
  build() {
    Column() {
      // ── 问候行: 昵称头像 + 时段问候 + 星星药丸（固定不滚动） ──
      Row({ space: 12 }) {
        if (this.avatarChar().length > 0) {
          Text(this.avatarChar())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_AVATAR_INK)
            .width(46)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .linearGradient({ angle: 150, colors: [[KIDS_AVATAR_1, 0], [KIDS_AVATAR_2, 1]] })
            .shadow({ radius: 10, color: '#59FF9F43', offsetY: 4 })
        } else {
          // 无昵称 fallback: star.svg（去 emoji，spec §4.2）
          Column() {
            Image($rawfile('kids/star.svg')).width(24).height(24)
          }
          .width(46)
          .height(46)
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .linearGradient({ angle: 150, colors: [[KIDS_AVATAR_1, 0], [KIDS_AVATAR_2, 1]] })
          .shadow({ radius: 10, color: '#59FF9F43', offsetY: 4 })
        }

        Column({ space: 2 }) {
          Text(this.greetingText())
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('今天想和小星老师玩点什么？')
            .fontSize(12)
            .fontColor(KIDS_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 6 }) {
          Image($rawfile('kids/star.svg')).width(14).height(14)
          Text(`${this.totalStars}`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
          Text('颗')
            .fontSize(11)
            .fontColor(KIDS_MUTED)
        }
        .padding({ left: 13, right: 13, top: 8, bottom: 8 })
        .borderRadius(999)
        .backgroundColor(KIDS_SURFACE)
        .border({ width: 1, color: KIDS_BORDER })
        .shadow({ radius: 6, color: '#1A24211C', offsetY: 2 })
        .accessibilityText(`累计获得 ${this.totalStars} 颗星`)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topInsetVp + 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          this.HeroCard()
          this.SubjectSection()
          if (this.kidsSessions().length > 0) {
            this.GardenSection()
          }
          this.ParentEntry()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
    .bindSheet($$this.showGateSheet, this.GateSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.showGateSheet = false
      }
    })
    .bindSheet($$this.showStarDetailSheet, this.StarDetailSheetBuilder(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.showStarDetailSheet = false
      }
    })
  }
```

（`GardenSection`/`StarDetailSheetBuilder` 在 Task 10/11 补实体；本任务先放占位 @Builder：`GardenSection` 渲染 Task 10 的 `KidsDayGroupCard` 列表——若 Task 10 未做，先渲染空 Column 并留 TODO 注释**不允许**——因此 Task 9 与 Task 10 连续执行后再统一编译，见 Step 6。）

- [ ] **Step 3: HeroCard @Builder（一天一会话）**

```typescript
  @Builder
  HeroCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 右上玻璃圆装饰（静态，无动画）
      Column()
        .width(130)
        .height(130)
        .borderRadius(65)
        .backgroundColor(KIDS_GLASS)
        .margin({ top: -34, right: -34 })

      Column({ space: 14 }) {
        // 眉标: mono 10.5vp
        Text(this.heroDateLabel())
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(KIDS_ON_HERO_2)
          .letterSpacing(1)

        Row({ space: 14 }) {
          // 静态星星图标块（替代 v1 吉祥物循环浮动，spec §8）
          Column() {
            Image($rawfile('kids/star.svg')).width(40).height(40)
          }
          .width(76)
          .height(76)
          .borderRadius(24)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#EBFFFDF8')
          .shadow({ radius: 14, color: '#333A2506', offsetY: 6 })

          Column({ space: 3 }) {
            Text('继续学习')
              .fontSize(23)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_ON_HERO)
            // 副文案允许换行不 ellipsis（v2.2 修正 6）
            Text(this.heroSubtitle())
              .fontSize(12.5)
              .fontColor(KIDS_ON_HERO_2)
              .lineHeight(19)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        Row({ space: 10 }) {
          // 主 CTA 白底胶囊 ≥44vp
          Row({ space: 8 }) {
            Text('开始今天的学习')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_FG)
            Image($rawfile('kids/chevron.svg')).width(14).height(14)
          }
          .padding({ left: 20, right: 20 })
          .height(46)
          .borderRadius(999)
          .backgroundColor(KIDS_SURFACE)
          .shadow({ radius: 14, color: '#403A2506', offsetY: 6 })

          Blank()

          // 今日星星徽章（N=0 也显示——「今天还没来」动机）
          Row({ space: 5 }) {
            Image($rawfile('kids/star.svg')).width(12).height(12)
            Text(`今日 +${this.todayStars}`)
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(KIDS_ON_HERO)
          }
          .padding({ left: 13, right: 13, top: 9, bottom: 9 })
          .borderRadius(999)
          .backgroundColor('#243A2506')
          .accessibilityText(`今日获得 ${this.todayStars} 颗星`)

          // 看明细（44vp 触控高、描边胶囊）
          Text('看明细')
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_ON_HERO)
            .padding({ left: 14, right: 14 })
            .height(44)
            .borderRadius(999)
            .border({ width: 1.5, color: '#333A2506' })
            .textAlign(TextAlign.Center)
            .onClick((): void => {
              this.showStarDetailSheet = true
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .padding(20)
      .width('100%')
    }
    .width('100%')
    .borderRadius(24)
    .clip(true)
    .linearGradient({ angle: 135, colors: [[KIDS_ACCENT, 0], [KIDS_ACCENT_2, 1]] })
    .shadow({ radius: 28, color: '#66FF9F43', offsetY: 10 })
    .onClick((): void => {
      // 一天一会话: 已有今日会话 → 续接; 否则开新会话
      const today: ChatSession | null = this.todaySession()
      if (today !== null) {
        this.onOpenSession(today.id)
      } else {
        this.onNewChat('', DEFAULT_ASSISTANT_ID)
      }
    })
  }
```

**手势注意**：「看明细」的 onClick 嵌在整卡 onClick 内——ArkUI 子组件 onClick 消费事件不冒泡，无需额外处理；真机走查确认（验收清单）。

- [ ] **Step 4: SubjectSection @Builder（2×2 学科卡，两行显式 Row）**

```typescript
  @Builder
  SubjectSection() {
    Column({ space: 12 }) {
      Row() {
        Text('今天玩什么')
          .fontSize(17.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Blank()
        Text('选一个，马上开始')
          .fontSize(11.5)
          .fontColor(KIDS_SUBTLE)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Row({ space: 12 }) {
        this.SubjectCard(KIDS_SUBJECTS[0])
        this.SubjectCard(KIDS_SUBJECTS[1])
      }
      .width('100%')

      Row({ space: 12 }) {
        this.SubjectCard(KIDS_SUBJECTS[2])
        this.SubjectCard(KIDS_SUBJECTS[3])
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  SubjectCard(item: KidsSubjectItem) {
    Column() {
      Row({ space: 10 }) {
        // 图标块 44vp / 圆角 14 / 学科色 15% 淡底
        Column() {
          Image($rawfile(item.iconPath)).width(24).height(24)
        }
        .width(44)
        .height(44)
        .borderRadius(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(withColorAlpha(item.color, '26'))

        Column({ space: 2 }) {
          Text(item.label)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
          // 副标题固定 2 行高，保证卡片等高
          Text(item.subtitle)
            .fontSize(11.5)
            .fontColor(KIDS_MUTED)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .height(30)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 底部状态行: 1px 虚线上边框 + 今日计数 + 开始 ›
      Row() {
        Text(this.todayCountFor(item) > 0 ?
          `今日 ${this.todayCountFor(item)} ${item.countUnit}` :
          (item.id === 'games' ? '今天还没玩' : '今天还没练'))
          .fontSize(10.5)
          .fontColor(KIDS_SUBTLE)
        Blank()
        Text('开始 ›')
          .fontSize(11.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(item.ink)
      }
      .width('100%')
      .height(30)
      .alignItems(VerticalAlign.Center)
      .border({ width: { top: 1 }, color: KIDS_BORDER, style: { top: BorderStyle.Dashed } })
    }
    .layoutWeight(1)
    .padding({ left: 14, right: 14, top: 14, bottom: 6 })
    .borderRadius(19)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .shadow({ radius: 8, color: '#1424211C', offsetY: 3 })
    .accessibilityText(`打开${item.label}`)
    .onClick((): void => {
      this.onNewChat(item.startPrompt, item.assistantId)
    })
  }
```

（go 箭头用文字 `›` U+203A ink 色渲染——spec §4.9 记录的最小原型偏差，不做 4 学科 chevron 变体。）

- [ ] **Step 5: ParentEntry @Builder + GateSheetBuilder**

```typescript
  @Builder
  ParentEntry() {
    Row({ space: 6 }) {
      Image($rawfile('kids/lock.svg')).width(13).height(13)
      Text('家长入口')
        .fontSize(12)
        .fontColor(KIDS_SUBTLE)
    }
    .width('100%')
    .height(46)
    .borderRadius(12)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      this.showGateSheet = true
    })
  }

  @Builder
  GateSheetBuilder() {
    ParentalGateSheet({
      onPassed: (): void => {
        this.showGateSheet = false
        this.onGatePassed()
      },
      onCancelled: (): void => {
        this.showGateSheet = false
      }
    })
  }
```

（Task 12 会把 ParentalGateSheet 扩展为两阶段——onPassed 语义不变：概览页的「进入家长设置」才触发它。）

- [ ] **Step 6: 与 Task 10 联合编译验证**

Task 9 引用的 `KidsDayGroupCard`（Task 10）与 `GardenSection` 内的 `KidsStarDetailSheet`（Task 11）此时尚不存在——**Task 9 不单独编译**，先写 `GardenSection` 的完整实现（引用 Task 10 组件），Task 10 完成后统一编译。`GardenSection`：

```typescript
  @Builder
  GardenSection() {
    Column({ space: 12 }) {
      Row() {
        Text('我的学习乐园')
          .fontSize(17.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Blank()
        Text(`共 ${this.kidsSessions().length} 次学习`)
          .fontSize(11.5)
          .fontColor(KIDS_SUBTLE)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      ForEach(this.dayGroups(), (group: KidsDayGroup): void => {
        KidsDayGroupCard({
          group: group,
          dayStars: this.starByDay.get(group.dayKey) ?? 0,
          starBySession: this.starBySession,
          onOpenSession: (sessionId: string): void => {
            this.onOpenSession(sessionId)
          }
        })
      }, (group: KidsDayGroup): string => group.dayKey)
    }
    .width('100%')
  }
```

---

### Task 10: KidsDayGroupCard 学习乐园天卡

**Files:**
- Create: `components/kids/KidsDayGroupCard.ets`

**Interfaces:**
- Consumes: Task 6 `KidsDayGroup` / `formatHourMinute`；Task 3 `subjectForAssistantId` / `KidsSubjectItem`；Task 1 令牌/SVG
- Produces: `@ComponentV2 export struct KidsDayGroupCard { @Param group: KidsDayGroup; @Param dayStars: number; @Param starBySession: Map<string, number>; @Event onOpenSession: (sessionId: string) => void }`（Task 9 GardenSection 按此接线）

- [ ] **Step 1: 实现组件（完整内容）**

```typescript
import { ChatSession } from '../../models/ChatModels'
import { formatHourMinute } from '../../utils/KidsSubjectUtils'
import { subjectForAssistantId, KidsSubjectItem } from './KidsSubjectCatalog'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_MUTED,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_ACCENT,
  KIDS_ON_GOLD
} from './KidsBrandTokens'

/** 同日记录超过 N 条时折叠 */
const DAY_COLLAPSE_LIMIT: number = 3

/**
 * 学习乐园按天分组卡（spec 2026-09-15 §4.5）:
 * 天头（今天/昨天/日期 + 当日星星汇总药丸）+ 记录行列表（学科图标 +
 * 标题 + 老师名·时间 + 单会话星星）+ 同日 >3 条折叠/展开。
 * 展开态是内部 @Local，不持久化。
 */
@ComponentV2
export struct KidsDayGroupCard {
  @Param group: KidsDayGroup = new KidsDayGroup()
  @Param dayStars: number = 0
  @Param starBySession: Map<string, number> = new Map()
  @Event onOpenSession: (sessionId: string) => void = () => {}
  @Local expanded: boolean = false

  private visibleSessions(): ChatSession[] {
    if (this.expanded || this.group.sessions.length <= DAY_COLLAPSE_LIMIT) {
      return this.group.sessions
    }
    return this.group.sessions.slice(0, DAY_COLLAPSE_LIMIT)
  }

  private hiddenCount(): number {
    return Math.max(0, this.group.sessions.length - DAY_COLLAPSE_LIMIT)
  }

  private teacherName(session: ChatSession): string {
    const subject: KidsSubjectItem | null = subjectForAssistantId(session.assistantId)
    return subject !== null ? subject.teacher : '小星老师'
  }

  private sessionTitle(session: ChatSession): string {
    const title: string = session.title.trim()
    return title.length > 0 ? title : '和小星老师的学习'
  }

  build() {
    Column() {
      // ── 天头 ──
      Row({ space: 8 }) {
        Text(this.group.label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Text(this.group.subLabel)
          .fontSize(11.5)
          .fontColor(KIDS_MUTED)
        Blank()
        // 当日星星汇总药丸（金 24% 淡底）
        Row({ space: 4 }) {
          Image($rawfile('kids/star.svg')).width(12).height(12)
          Text(`+${this.dayStars}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_ON_GOLD)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(999)
        .backgroundColor('#3DF5B301')
        .accessibilityText(`当日获得 ${this.dayStars} 颗星`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      // ── 记录行 ──
      ForEach(this.visibleSessions(), (session: ChatSession, index: number): void => {
        this.RecordRow(session, index > 0)
      }, (session: ChatSession): string => session.id)

      // ── 折叠/展开 ──
      if (this.hiddenCount() > 0) {
        Row() {
          Text(this.expanded ? '收起' : `展开其余 ${this.hiddenCount()} 条`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_MUTED)
        }
        .width('100%')
        .height(44)
        .justifyContent(FlexAlign.Center)
        .border({ width: { top: 1 }, color: KIDS_BORDER, style: { top: BorderStyle.Dashed } })
        .onClick((): void => {
          this.expanded = !this.expanded
        })
      }
    }
    .width('100%')
    .borderRadius(20)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .clip(true)
  }

  @Builder
  RecordRow(session: ChatSession, showTopBorder: boolean) {
    Row({ space: 10 }) {
      this.RecordIcon(session)

      Column({ space: 2 }) {
        Text(this.sessionTitle(session))
          .fontSize(13.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(KIDS_FG)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.teacherName(session)} · ${formatHourMinute(session.updatedAt)}`)
          .fontSize(11)
          .fontColor(KIDS_SUBTLE)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 单会话星星（0 → 灰色 0）
      if ((this.starBySession.get(session.id) ?? 0) > 0) {
        Row({ space: 3 }) {
          Text(`+${this.starBySession.get(session.id) ?? 0}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_ON_GOLD)
          Image($rawfile('kids/star.svg')).width(13).height(13)
        }
      } else {
        Text('0')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_SUBTLE)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .border(showTopBorder ?
      { width: { top: 1 }, color: KIDS_BORDER } :
      { width: { top: 0 }, color: Color.Transparent })
    .onClick((): void => {
      this.onOpenSession(session.id)
    })
  }

  @Builder
  RecordIcon(session: ChatSession) {
    // 学科会话: 学科图标 + 学科色 15% 淡底；小星老师: star.svg + 暖橙淡底
    if (subjectForAssistantId(session.assistantId) !== null) {
      Column() {
        Image($rawfile((subjectForAssistantId(session.assistantId) as KidsSubjectItem).iconPath))
          .width(20)
          .height(20)
      }
      .width(36)
      .height(36)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha((subjectForAssistantId(session.assistantId) as KidsSubjectItem).color, '26'))
    } else {
      Column() {
        Image($rawfile('kids/star.svg')).width(20).height(20)
      }
      .width(36)
      .height(36)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha(KIDS_ACCENT, '26'))
    }
  }
}
```

**ArkTS 注意**：`RecordRow(session, showTopBorder)` 的 @Builder 多参传递会断响应式快照——但 `session`/`showTopBorder` 来自 ForEach 的静态快照，本就无需响应式；`starBySession` 在 @Builder 内直接读 `this.starBySession` 保持响应式（MEMORY：@Trace/@Param 字段在 @Builder 内读 this 有效）。import 区需补 `KidsDayGroup`：`import { KidsDayGroup, formatHourMinute } from '../../utils/KidsSubjectUtils'`。

- [ ] **Step 2: Task 9 + Task 10 联合编译验证**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL（KidsStarDetailSheet 尚缺——若 Task 9 已引用，先临时注释 `StarDetailSheetBuilder` 的 bindSheet 与 builder，Task 11 恢复；**推荐直接连续执行 Task 11 后统一编译**）。

- [ ] **Step 3: Commit（与 Task 9 一起）**

```bash
git add entry/src/main/ets/components/kids/KidsHomeView.ets entry/src/main/ets/components/kids/KidsDayGroupCard.ets
git commit -m "feat(kids): 主屏三段式重写（hero 一天一会话 + 2×2 学科卡）+ 学习乐园按天分组卡"
```

---

### Task 11: KidsStarDetailSheet 今日星星明细

**Files:**
- Create: `components/kids/KidsStarDetailSheet.ets`
- Modify: `components/kids/KidsHomeView.ets`（恢复/补上 `StarDetailSheetBuilder`，若 Task 10 时临时注释）

**Interfaces:**
- Consumes: Task 6 `buildTodayCategoryRows` / `buildTodayEventRows` / `KidsTodayCategoryRow` / `KidsTodayEventRow`；`getStarRewardService().getTodaySummary()/getTodayEvents()`（自加载）；Task 1 令牌/SVG；`withColorAlpha`
- Produces: `@ComponentV2 export struct KidsStarDetailSheet { @Event onClose: () => void }`（宿主 KidsHomeView 用 `bindSheet` 挂载；不复用成人壳 TodayStarDetailSheet——spec §4.6）

- [ ] **Step 1: 实现组件（完整内容）**

```typescript
import { StarEventRow, TodayStarSummary } from '../../models/StarEventModels'
import { getStarRewardService } from '../../services/StarRewardService'
import {
  buildTodayCategoryRows,
  buildTodayEventRows,
  KidsTodayCategoryRow,
  KidsTodayEventRow
} from '../../utils/KidsSubjectUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_BG,
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_MUTED,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_ACCENT,
  KIDS_STAR,
  KIDS_ON_GOLD,
  KIDS_ENGLISH_INK
} from './KidsBrandTokens'

/**
 * 儿童版今日星星明细 sheet（spec 2026-09-15 §4.6，对照原型 .sheet）。
 * 恒定暖色皮肤、无日历模式——不复用成人壳 TodayStarDetailSheet（避免波及成人侧）。
 * 数据自加载: getTodaySummary + getTodayEvents（与 hero「今日 +N」同源同口径）。
 */
@ComponentV2
export struct KidsStarDetailSheet {
  @Event onClose: () => void = () => {}
  @Local todayStars: number = 0
  @Local categoryRows: KidsTodayCategoryRow[] = []
  @Local eventRows: KidsTodayEventRow[] = []
  @Local loaded: boolean = false

  aboutToAppear(): void {
    this.loadData()
  }

  private loadData(): void {
    getStarRewardService().getTodaySummary().then((summary: TodayStarSummary): void => {
      this.todayStars = summary.total
    }).catch((error: Object): void => {
      console.error('KidsStarDetailSheet', `Failed to load today summary: ${JSON.stringify(error)}`)
      this.todayStars = 0
    })
    getStarRewardService().getTodayEvents().then((events: StarEventRow[]): void => {
      this.categoryRows = buildTodayCategoryRows(events)
      this.eventRows = buildTodayEventRows(events)
      this.loaded = true
    }).catch((error: Object): void => {
      console.error('KidsStarDetailSheet', `Failed to load today events: ${JSON.stringify(error)}`)
      this.categoryRows = []
      this.eventRows = []
      this.loaded = true
    })
  }

  build() {
    Column() {
      // ── 头部: 标题 + ✕ 圆钮（44vp） ──
      Row() {
        Text('今日星星')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .layoutWeight(1)
        Column() {
          Image($rawfile('kids/close.svg')).width(16).height(16)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0F24211C')
        .onClick((): void => {
          this.onClose()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          this.StarHero()

          if (this.loaded && this.eventRows.length === 0) {
            this.EmptyState()
          } else {
            if (this.categoryRows.length > 0) {
              this.CategorySection()
            }
            if (this.eventRows.length > 0) {
              this.EventSection()
            }
          }
        }
        .width('100%')
        .padding({ top: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 16 })
    .backgroundColor(KIDS_SURFACE)
  }

  @Builder
  StarHero() {
    // 金 14% 淡底圆角块 + 48vp 金星徽章 + N 31vp + 颗 · 今日获得
    Row({ space: 14 }) {
      Column() {
        Image($rawfile('kids/star.svg')).width(30).height(30)
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#24F5B301')

      Row({ space: 6 }) {
        Text(`${this.todayStars}`)
          .fontSize(31)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_ON_GOLD)
        Text('颗 · 今日获得')
          .fontSize(12.5)
          .fontColor(KIDS_MUTED)
          .margin({ bottom: 5 })
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(18)
    .borderRadius(18)
    .backgroundColor('#24F5B301')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  CategorySection() {
    Column({ space: 10 }) {
      Text(`${this.categoryRows.length} 类活动`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(KIDS_SUBTLE)

      ForEach(this.categoryRows, (row: KidsTodayCategoryRow): void => {
        Row({ space: 10 }) {
          Column() {
            Image($rawfile(row.iconPath)).width(18).height(18)
          }
          .width(32)
          .height(32)
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(withColorAlpha(row.tint, '26'))

          Column({ space: 2 }) {
            Text(row.name)
              .fontSize(13.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(KIDS_FG)
            Text(row.detail)
              .fontSize(11)
              .fontColor(KIDS_SUBTLE)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(`${row.stars}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_ON_GOLD)
          Image($rawfile('kids/star.svg')).width(15).height(15)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(14)
        .backgroundColor(KIDS_BG)
        .alignItems(VerticalAlign.Center)
      }, (row: KidsTodayCategoryRow, index: number): string => `${row.name}_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EventSection() {
    Column({ space: 10 }) {
      Text(`今日明细 · 共 ${this.eventRows.length} 条`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(KIDS_SUBTLE)

      ForEach(this.eventRows, (row: KidsTodayEventRow): void => {
        Row({ space: 10 }) {
          Text(row.timeLabel)
            .fontSize(11)
            .fontColor(KIDS_SUBTLE)
            .width(38)
          Text(row.description)
            .fontSize(12.5)
            .fontColor(KIDS_FG)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // +N⭐ 药丸（英语绿 ink 淡底；0 星灰药丸）
          Text(row.stars > 0 ? `+${row.stars} 星` : '0 星')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(row.stars > 0 ? KIDS_ENGLISH_INK : KIDS_SUBTLE)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor(row.stars > 0 ? '#2635A98A' : '#0F24211C')
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .padding({ left: 4, right: 4 })
        .alignItems(VerticalAlign.Center)
      }, (row: KidsTodayEventRow, index: number): string => `${row.timeLabel}_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState() {
    // 可达空态（spec §4.6）: 今天还没有获得星星
    Column({ space: 10 }) {
      Column() {
        Image($rawfile('kids/star.svg')).width(28).height(28)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#14F5B301')

      Text('今天还没有获得星星，去学习吧')
        .fontSize(13)
        .fontColor(KIDS_MUTED)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .justifyContent(FlexAlign.Center)
  }
}
```

- [ ] **Step 2: KidsHomeView 挂接**

在 `KidsHomeView.ets` 中补 `StarDetailSheetBuilder`（若 Task 9/10 已写完整则核对即可）：

```typescript
  @Builder
  StarDetailSheetBuilder() {
    KidsStarDetailSheet({
      onClose: (): void => {
        this.showStarDetailSheet = false
      }
    })
  }
```

- [ ] **Step 3: 编译验证 + 提交**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL（Task 9/10/11 三个组件闭环）。

```bash
git add entry/src/main/ets/components/kids/KidsStarDetailSheet.ets entry/src/main/ets/components/kids/KidsHomeView.ets
git commit -m "feat(kids): 今日星星明细 sheet（儿童令牌版，star-hero + 分类汇总 + 明细）"
```

---

### Task 12: ParentalGateSheet 两阶段扩展（门 → 今日概览）

**Files:**
- Modify: `components/kids/ParentalGateSheet.ets`

**Interfaces:**
- Consumes: Task 6 `buildTodayCategoryRows` / `buildTodayEventRows` / `formatDateLabel` / `formatWeekday`；`getStarRewardService()`；`getChildProfileService()`；Task 1 令牌（`KIDS_CHINESE_INK` 替换 `KIDS_DANGER`、`KIDS_ACCENT`、`KIDS_ON_HERO`、`KIDS_ON_GOLD`）/SVG（close.svg）
- Produces: `onPassed` / `onCancelled` 语义不变（宿主 KidsHomeView 不改）；答对 → summary 阶段；「进入家长设置」→ `onPassed()`；「知道了」/✕/拖拽 → `onCancelled()`

- [ ] **Step 1: 状态与阶段流转**

对 `ParentalGateSheet.ets` 做如下修改：

1. import 追加：
```typescript
import { StarEventRow, TodayStarSummary } from '../../models/StarEventModels'
import { getStarRewardService } from '../../services/StarRewardService'
import { getChildProfileService, ChildKnowledgeProfile } from '../../services/ChildProfileService'
import {
  buildTodayCategoryRows,
  buildTodayEventRows,
  formatDateLabel,
  formatWeekday,
  KidsTodayCategoryRow,
  KidsTodayEventRow
} from '../../utils/KidsSubjectUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
```
令牌 import 追加 `KIDS_CHINESE_INK, KIDS_STAR, KIDS_ON_GOLD, KIDS_BG`；**移除 `KIDS_DANGER`**（不再引用）。

2. struct 内追加状态与加载逻辑：
```typescript
  /** gate = 算术门; summary = 家长今日概览（spec §4.7） */
  @Local phase: string = 'gate'
  @Local summaryStars: number = 0
  @Local summaryCategoryRows: KidsTodayCategoryRow[] = []
  @Local summaryEventRows: KidsTodayEventRow[] = []
  @Local summaryChildName: string = ''
  @Local summaryLoaded: boolean = false

  private loadSummary(): void {
    getStarRewardService().getTodaySummary().then((summary: TodayStarSummary): void => {
      this.summaryStars = summary.total
    }).catch((error: Object): void => {
      console.error('ParentalGateSheet', `Failed to load summary: ${JSON.stringify(error)}`)
      this.summaryStars = 0
    })
    getStarRewardService().getTodayEvents().then((events: StarEventRow[]): void => {
      this.summaryCategoryRows = buildTodayCategoryRows(events)
      this.summaryEventRows = buildTodayEventRows(events)
      this.summaryLoaded = true
    }).catch((error: Object): void => {
      console.error('ParentalGateSheet', `Failed to load summary events: ${JSON.stringify(error)}`)
      this.summaryCategoryRows = []
      this.summaryEventRows = []
      this.summaryLoaded = true  // 失败也降级显示 star-hero + 按钮，不阻塞进入家长设置
    })
    getChildProfileService().getProfile().then((profile: ChildKnowledgeProfile): void => {
      this.summaryChildName = profile.childName.trim()
    }).catch((error: Object): void => {
      console.error('ParentalGateSheet', `Failed to load child name: ${JSON.stringify(error)}`)
      this.summaryChildName = ''
    })
  }

  private summaryDateLabel(): string {
    const now: number = Date.now()
    return `家长视图 · ${formatDateLabel(now)} ${formatWeekday(now)}`
  }

  private summaryHeadline(): string {
    const name: string = this.summaryChildName.length > 0 ? this.summaryChildName : '小朋友'
    return `${name}今天的学习情况，一眼读懂`
  }
```

3. `aboutToAppear` 追加重置（sheet 每次打开都从 gate 开始——关闭即销毁重建，防御性重置）：
```typescript
  aboutToAppear(): void {
    this.phase = 'gate'
    this.inputText = ''
    this.showError = false
    this.currentQuestion = generateGateQuestion()
  }
```

4. `handleConfirm` 答对分支从 `this.onPassed()` 改为进入 summary：
```typescript
  private handleConfirm(): void {
    if (checkGateAnswer(this.currentQuestion, this.inputText)) {
      this.phase = 'summary'
      this.loadSummary()
      return
    }
    this.showError = true
    this.inputText = ''
    this.currentQuestion = generateGateQuestion()
    this.playShake()
  }
```

5. 错误色替换（§6：答错 = 语文橙红，不新增状态色）：答案框 `border({ width: 2, color: this.showError ? KIDS_DANGER : KIDS_BORDER })` → `this.showError ? KIDS_CHINESE_INK : KIDS_BORDER`；错误提示文字 `.fontColor(KIDS_DANGER)` → `.fontColor(KIDS_CHINESE_INK)`。

- [ ] **Step 2: build() 分相渲染**

把现有 `build()` 的整个 `Column` 内容包进 phase 分支：

```typescript
  build() {
    Column() {
      if (this.phase === 'gate') {
        this.GatePhase()
      } else {
        this.SummaryPhase()
      }
    }
    .width('100%')
    .backgroundColor(KIDS_SURFACE)
  }

  @Builder
  GatePhase() {
    // ……现有 build() 的全部内容原样搬入（标题栏/题目/答案框/键盘/确定按钮），
    // 仅按 Step 1 第 5 点替换两处 KIDS_DANGER → KIDS_CHINESE_INK，
    // 并把标题栏右侧 ✕ 的 SymbolGlyph 按钮换成 close.svg:
    //   Column() { Image($rawfile('kids/close.svg')).width(16).height(16) }
    //     .width(44).height(44).borderRadius(22)
    //     .justifyContent(FlexAlign.Center).backgroundColor('#0F24211C')
    //     .onClick(() => { this.onCancelled() })
    // 左侧占位 Column 同步改为 44×44（保持标题居中）。
  }
```

（GatePhase 是**搬运**不是重写：原 build() 从「标题栏 Row」到「Button('确定')」的全部子组件原样移入，外层 padding `{ left: 24, right: 24, top: 16, bottom: 32 }` 移到 GatePhase 根 Column 上。）

```typescript
  @Builder
  SummaryPhase() {
    Column() {
      // ── 头部: 标题 + ✕（44vp） ──
      Row() {
        Text('家长今日概览')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .layoutWeight(1)
        Column() {
          Image($rawfile('kids/close.svg')).width(16).height(16)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0F24211C')
        .onClick((): void => {
          this.onCancelled()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 14 }) {
          // 眉标 + 一句话
          Column({ space: 4 }) {
            Text(this.summaryDateLabel())
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(KIDS_ON_GOLD)
              .letterSpacing(1)
            Text(this.summaryHeadline())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_FG)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // star-hero（同 KidsStarDetailSheet 样式）
          Row({ space: 14 }) {
            Column() {
              Image($rawfile('kids/star.svg')).width(30).height(30)
            }
            .width(48)
            .height(48)
            .borderRadius(24)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#24F5B301')

            Row({ space: 6 }) {
              Text(`${this.summaryStars}`)
                .fontSize(31)
                .fontWeight(FontWeight.Bold)
                .fontColor(KIDS_ON_GOLD)
              Text('颗 · 今日获得')
                .fontSize(12.5)
                .fontColor(KIDS_MUTED)
                .margin({ bottom: 5 })
            }
            .alignItems(VerticalAlign.Bottom)
          }
          .width('100%')
          .padding(18)
          .borderRadius(18)
          .backgroundColor('#24F5B301')
          .alignItems(VerticalAlign.Center)

          // 学科分布（今日有事件的学科行）
          ForEach(this.summaryCategoryRows, (row: KidsTodayCategoryRow): void => {
            Row({ space: 10 }) {
              Column() {
                Image($rawfile(row.iconPath)).width(18).height(18)
              }
              .width(32)
              .height(32)
              .borderRadius(10)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(withColorAlpha(row.tint, '26'))

              Column({ space: 2 }) {
                Text(row.name)
                  .fontSize(13.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(KIDS_FG)
                Text(row.detail)
                  .fontSize(11)
                  .fontColor(KIDS_SUBTLE)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(`${row.stars}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(KIDS_ON_GOLD)
              Image($rawfile('kids/star.svg')).width(14).height(14)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(14)
            .backgroundColor(KIDS_BG)
            .alignItems(VerticalAlign.Center)
          }, (row: KidsTodayCategoryRow, index: number): string => `${row.name}_${index}`)

          // 今日记录（时间 + 描述 + +N⭐ 药丸）
          ForEach(this.summaryEventRows, (row: KidsTodayEventRow): void => {
            Row({ space: 10 }) {
              Text(row.timeLabel)
                .fontSize(11)
                .fontColor(KIDS_SUBTLE)
                .width(38)
              Text(row.description)
                .fontSize(12.5)
                .fontColor(KIDS_FG)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(row.stars > 0 ? `+${row.stars} 星` : '0 星')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(row.stars > 0 ? KIDS_ENGLISH_INK : KIDS_SUBTLE)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(999)
                .backgroundColor(row.stars > 0 ? '#2635A98A' : '#0F24211C')
            }
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .alignItems(VerticalAlign.Center)
          }, (row: KidsTodayEventRow, index: number): string => `s_${row.timeLabel}_${index}`)

          // 说明条
          Text('完整报告与历史趋势在家长设置中查看')
            .fontSize(11.5)
            .fontColor(KIDS_MUTED)
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#0D24211C')
        }
        .width('100%')
        .padding({ top: 14, bottom: 10 })
      }
      .constraintSize({ maxHeight: 380 })
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // ── 两个 48vp 按钮 ──
      Button('进入家长设置')
        .width('100%')
        .height(48)
        .borderRadius(999)
        .backgroundColor(KIDS_ACCENT)
        .fontColor(KIDS_ON_HERO)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10 })
        .onClick((): void => {
          this.onPassed()
        })

      Button('知道了')
        .width('100%')
        .height(48)
        .borderRadius(999)
        .backgroundColor(Color.Transparent)
        .border({ width: 1.5, color: KIDS_BORDER })
        .fontColor(KIDS_MUTED)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 10 })
        .onClick((): void => {
          this.onCancelled()
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 32 })
  }
```

import 追加 `KIDS_ENGLISH_INK`（今日记录药丸用）。

- [ ] **Step 3: 编译验证 + 提交**

Run: 全局编译命令。Expected: BUILD SUCCESSFUL。
走查：`grep -c "KIDS_DANGER" entry/src/main/ets/components/kids/ParentalGateSheet.ets` → `0`（import 与引用都已移除；令牌本身保留在 KidsBrandTokens）。

```bash
git add entry/src/main/ets/components/kids/ParentalGateSheet.ets
git commit -m "feat(kids): 家长门两阶段——答对进今日概览，可进家长设置或返回主屏"
```

---

### Task 13: 清理——删除 v1 组件 + emoji 残留清扫 + 全量编译

**Files:**
- Delete: `components/kids/KidsActivityCatalog.ets`
- Delete: `components/kids/KidsSessionCard.ets`
- Modify: 任何残留 import/引用点（grep 定位）

**Interfaces:**
- Consumes: Task 3（KidsSubjectCatalog 已取代 KidsActivityCatalog）、Task 9（KidsHomeView 已不再引用 KidsSessionCard）
- Produces: 儿童主屏零 emoji、零 v1 残留；`hvigorw assembleHap` 干净

- [ ] **Step 1: grep 确认无引用后删除**

```bash
grep -rn "KidsActivityCatalog\|KIDS_ACTIVITIES\|KidsSessionCard" entry/src/main/ets --include="*.ets"
```
Expected: 仅剩两文件自身（若 KidsHomeView/其他文件仍有 import，先清除）。然后：

```bash
git rm entry/src/main/ets/components/kids/KidsActivityCatalog.ets entry/src/main/ets/components/kids/KidsSessionCard.ets
```

- [ ] **Step 2: emoji 残留清扫**

```bash
grep -rn "[⭐🔒➕🔤🈶✍️🗂️🔢🧭🔗🧩🖼️🎧➗→]" entry/src/main/ets/components/kids --include="*.ets"
```
Expected: 0 匹配。若命中（如漏改的 `Text('⭐')` 或 `→` CTA 箭头），逐一替换为对应 SVG Image 或删除。注意：`grep` 对多码点 emoji（✍️🗂️🖼️）可能拆码匹配——命中后人工确认。

同时全量核对 spec §4.9 的去 emoji 清单：主屏 `⭐`（3 处：问候药丸/头像 fallback/hero 吉祥物）、`🔒`（家长入口）、`→`（CTA 箭头）都已在 Task 9 重写中处理——此步是防漏网。

- [ ] **Step 3: 全量干净编译**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```
Expected: BUILD SUCCESSFUL，零 error 零新 warning。

- [ ] **Step 4: Commit**

```bash
git add -A entry/src/main/ets/components/kids/
git commit -m "chore(kids): 删除 v1 KidsActivityCatalog/KidsSessionCard + emoji 残留清扫"
```

---

### Task 14: 文档同步 + 验收清单核对

**Files:**
- Modify: `.claude/rules/teaching-architecture.md`（§2 助手表、锁定语义、触点清单）
- Modify: `docs/brand-spec.md`（末尾追加落地状态注记）

**Interfaces:**
- Consumes: 全部前置任务的最终实现
- Produces: 文档与代码一致；spec §9 验收清单逐项核对记录

- [ ] **Step 1: teaching-architecture.md 同步**

在 §2「助手身份：小星老师」表格之后追加一节：

```markdown
### 2.1 四个学科专用助手（2026-09-15 新增）

| ID | 名称 | avatarSymbol | color | 锁定工具子集 | sortOrder |
|----|------|--------------|-------|--------------|-----------|
| `kids_math` | 小星数学老师 | 数 | #4E8FE0 | ask_user, child_profile, get_time_info, grant_star, math_verify, math_quiz, vertical_math | 1 |
| `kids_english` | 小星英语老师 | 英 | #35A98A | ask_user, child_profile, get_time_info, grant_star, english_quiz, picture_vocab, listening_quiz | 2 |
| `kids_chinese` | 小星语文老师 | 语 | #E2603C | ask_user, child_profile, get_time_info, grant_star, pinyin_quiz, handwriting_practice | 3 |
| `kids_games` | 小星游戏老师 | 玩 | #8B72E0 | ask_user, child_profile, get_time_info, grant_star, number_puzzle, maze, sudoku, matching_pairs, categorization | 4 |

- 生命周期：`DatabaseService.ensureKidsSubjectAssistants()` 启动幂等补建（老用户升级自动补齐）。
- 锁定：`AssistantService.normalizeAssistant` 经 `getBuiltInAssistantSpec(id)` 注册表强制覆盖 5 个内置助手的 name/systemPrompt/enabledToolIds；`deleteAssistant` 对 `KIDS_BUILT_IN_ASSISTANT_IDS` 成员返回 false；Index 助手编辑器 `editingAssistantIsDefault` 保护同样覆盖 5 个。
- **不进备课管线**：`notifySessionEnd` 仅接受 `default`（现有过滤未动）；`injectDailyPlanSections` 不注入学科助手会话。
- 星星记录/孩子画像照常（child_profile 在锁定子集内，提示词约束只更新本学科维度）。
- 儿童主屏会话放行：`Index.isKidsAllowedSessionId` 用 `KIDS_BUILT_IN_ASSISTANT_IDS.includes(...)`（5 个助手会话都对儿童可见；`''` 遗留会话仍拦截）。
```

并更新 §12 相关文件清单：追加 `components/kids/KidsSubjectCatalog.ets`、`utils/KidsSubjectUtils.ets`、`components/kids/KidsDayGroupCard.ets`、`components/kids/KidsStarDetailSheet.ets` 四行。

- [ ] **Step 2: brand-spec.md 落地注记**

文件末尾追加：

```markdown
## 14. 落地状态（2026-09-15）

本规范 v2 已在 ArkTS 端落地：儿童主屏三段式（`components/kids/KidsHomeView.ets`）、2×2 学科卡（`KidsSubjectCatalog.ets` + 4 学科内置助手）、按天分组学习乐园（`KidsDayGroupCard.ets`）、今日星星明细（`KidsStarDetailSheet.ets`）、家长门两阶段（`ParentalGateSheet.ets`）。8 个 monoline SVG 图标位于 `resources/rawfile/kids/`（颜色 baked-in）。设计 spec：`docs/superpowers/specs/2026-09-15-kids-home-v2-redesign-design.md`。
```

- [ ] **Step 3: 验收清单核对（spec §9）**

逐项走查并在真机/模拟器验证（DevEco Studio 运行）：
- 功能 8 项：冷启动补建 4 助手（删 DB 行重启验证）；学科卡点击进对应助手会话并自动发引导语；hero 一天一会话两态；今日 +N 与明细 sheet 一致；学科卡计数按 activityType（chat_correct 不计入）；学习乐园分组/折叠/点击；家长门→概览→两按钮 + 关闭重开需重新验证；备课老师不被学科助手触发（日志确认 notifySessionEnd 过滤）。
- 视觉 5 项：主屏无 emoji、无循环动画；暖橙 ≤2 处；KIDS_SUBTLE=#746E64；触控 ≥44vp；深色模式下主屏恒定暖色。
- 工程 4 项：assembleHap 零错误；KidsSubjectUtils hypium 全绿（IDE）；两 v1 文件已删无残留 import；teaching-architecture.md 已同步。

- [ ] **Step 4: Commit**

```bash
git add .claude/rules/teaching-architecture.md docs/brand-spec.md
git commit -m "docs: teaching-architecture 学科助手同步 + brand-spec 落地注记"
```

---

## Self-Review 记录

**1. Spec 覆盖核对**（spec §1-§10 → task）：
- §3.1 助手定义 → Task 4；§3.2 提示词 → Task 4 Step 2；§3.3 生命周期/保护 → Task 5；§3.4 数据链路（备课不触发/不注入——Global Constraints 锁定「不动」）✓
- §4.1-4.3 布局/问候行/hero → Task 9；§4.4 学科区 → Task 3 + 9；§4.5 学习乐园 → Task 6/7/10；§4.6 明细 sheet → Task 11；§4.7 家长门 → Task 12；§4.8 令牌 → Task 1；§4.9 图标 → Task 1 ✓
- §5 Index 集成 → Task 8（含 isKidsAllowedSessionId/handleKidsNewChat/KidsRoot；1683/1726/1789 的过滤随谓词自动放宽——Task 8 Step 1 覆盖）✓
- §6 纯函数与测试 → Task 2 + 6；§7 动效约束 → Task 9（删 mascotFloatY，按压反馈随组件重写实现——SubjectCard/RecordRow 的 onClick 天然有系统按压态；如需显式 scale 0.98 反馈，Task 9 走查时补 `.stateStyles` 或 press 事件）；§8 实施顺序 → Task 1→14 顺序一致；§9 验收 → Task 14；§10 取舍 → 无实施动作 ✓

**2. Placeholder 扫描**：Task 9 Step 2 的 GateSheetBuilder/GardenSection/StarDetailSheetBuilder 均有完整代码；Task 12 GatePhase 是「原样搬运 + 3 处明确列出的替换」——搬运指令给出了精确范围（原 build() 标题栏到确定按钮）与全部 diff 点，非占位。无 TBD/TODO。

**3. 类型一致性**：`KidsDayGroup`（Task 6 定义 class，Task 9/10 消费同名）；`KidsTodayCategoryRow { iconPath, tint, name, detail, stars }` 与 `KidsTodayEventRow { timeLabel, description, stars }`（Task 6 定义，Task 11/12 字段名逐一一致）；`subjectForAssistantId` 返回 `KidsSubjectItem | null`（Task 3 定义，Task 6/10 消费一致）；`getBuiltInAssistantSpec` 返回 `KidsSubjectAssistantSpec | null`（Task 4 定义，Task 5 消费一致）；`handleKidsNewChat(initialPrompt, assistantId)`（Task 8）与 `onNewChat(item.startPrompt, item.assistantId)`（Task 9）参数序一致；`getStarTotalsByDay(sinceMs): Promise<Map<string, number>>`（Task 7）与 Task 9 `loadStarByDay` 消费一致。`onNewChat` 签名在 Task 8 Step 3 与 Task 9 struct 声明一致（2 参）。

**已知执行顺序耦合**：Task 9 依赖 Task 10/11 的组件存在才能编译——plan 已在 Task 9 Step 6 / Task 10 Step 2 标注「连续执行后统一编译」，Task 10/11 各自的 commit 步骤覆盖三个文件。

