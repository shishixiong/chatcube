# room_english 引导式小课设计（A3 带逛 + A2 听词找物）

**日期：** 2026-10-30
**状态：** 待评审（已按 builder check 修订）
**范围：** `room_english` 工具契约扩展 + `RoomEnglishCard` 状态机 + `rawfile/room3d` 静音/找物 API + 英语老师系统提示词
**目标：** 把 room_english 从“自由探索”变成「讲解 → 任务 → 检验」的闭环：
老师先带逛 3–5 个词（A3），再出一个「听词找物」任务（A2），最后由 `english_quiz` 复测并授星。

---

## 1. 背景与目标

room_english 目前是全屋 3D 自由探索：孩子点家具、听发音、看单词卡、点「我学会了」回执。它已经是英语教学里最强的“情境化”载体，但缺少教学结构：

- 老师不知道孩子先看哪个词、看了几个；
- 没有“讲完马上练”的环节；
- 回执只有 `explored_count / words`，AI 很难据此判断孩子是否真的掌握。

本设计在**不新增工具、不新增星星类型**的前提下，给 room_english 增加一个可选的 `lesson` 参数：

1. **A3 引导式参观**：AI 传 3–5 个词和每个词的一句引导语；卡片按顺序高亮物品、显示 2D 老师气泡、TTS 朗读。
2. **A2 听词找物**：带逛结束后，卡片用 TTS 说 “Find the sofa.”，孩子点房间里的物品；点对进入下一个，点错给提示，两次未对则揭示。
3. **检验闭环**：任务结束后回执里带 `task_correct / task_total / task_first_try / task_revealed`；英语老师收到回执后立刻用 `english_quiz` 复测同一组词并授星。

### 非目标

- 不做 3D 角色/NPC 建模与动画（NPC 用 2D 头像 + 语音气泡）。
- 不做摆放/介词任务（“把熊放到床上”）、颜色/数量任务（需要给 76 件物品补标签）。
- 不改 `room_english` 的授星语义：**仍然不授星**，星星由 `english_quiz` 给。
- 不新增工具 ID、不改 `StarEventModels` 的 10 处联合。
- 不替换现有自由探索模式：`lesson` 缺省时行为与今天完全一致。

---

## 2. 关键取舍（builder check 后已定）

| 问题 | 决定 | 理由 |
|---|---|---|
| 收尾用哪个 english_quiz mode | **首选 `read_aloud`**；仅当 4 个词都在本地词库时才可用 `listen_choice` | `EnglishQuizValidation` 对 `listen_choice / picture_word / phonics_blend / sentence_fill` 强制本地词库；76 个房间词里只有约 8 个在 `LocalVocabCatalog`，且没有对应 SVG。`read_aloud` 不受词库限制，正好承接“听 → 找 → 说”的输出阶段，答对同样授 1 星。**本版不扩词库、不放宽校验。** |
| sheet 关闭后是否保留进度 | **不保留**。关闭 = 退出本课，回执 `cancelled:true` | `ChatPage.bindSheet.onDisappear` 现有行为就是提交取消回执；实现 resume 需要把进度提到 ChatPage/service，超出本期。卡片内提供显式「退出本课」，sheet 的 ✕/下拉也等同退出。 |
| `task_correct` 定义 | 目标最终答对的数量（点错一次再点对也算对） | 与“是否掌握”对齐；首次就对的单独记 `task_first_try`。 |
| `task_attempts` 定义 | 任务阶段孩子点物品的总次数（含错误、含揭示前的最后一次错误） | 总交互量，不是每个目标的尝试次数；每目标的错误连击由 `max_attempts` 控制。 |
| 揭示后的目标算不算对 | 不算。`task_revealed` 单独计数 | AI 需要区分“自己找到”与“被告诉答案”。 |
| `completed` 语义 | 有 lesson 时 = `task_completed`；无 lesson 时维持现状（探索过即可提交） | 带逛可跳过，任务才是本课的核心。`tour_completed` 单独反映带逛是否走完。 |
| `tour_words` / `task_targets` 存 id 还是英文词 | **存 id**；卡片用 `steps[].word` 映射显示 | id 是稳定主键；英文词由 AI 自己在 steps 里提供，回执不必重复。 |
| targets 数量 | **3–5 个**，且必须是 steps 的子集 | 与带逛词量对齐；少于 3 个任务太短，多于 5 个超出幼儿注意力。 |
| 任务阶段是否切房间 | **每题切到目标所在房间**，并关闭单词卡 | 全屋户型里物品太小、难点击；切房间后仍是“听词找物”，但可点性更好。 |
| 程序化 select 的回传 | 带逛/揭示时用 `suppressSelectUntil` 忽略 1 秒内的 `onSelect`；任务开始用 `prepareFind`（不打开单词卡） | 避免程序化选中被当成孩子点击，也避免任务开始就泄露答案。 |
| 重复点同一个错误物品 | 不增加 `wrongStreak`，只重复提示 | 防止孩子连点同一个东西两次就触发揭示。 |

---

## 3. 用户流程

```
英语老师决定教家居词
  → 调 room_english({ focus, words, skill_key, lesson })
      → 卡片进入「带逛」：第 1 个词高亮 + 老师气泡 + TTS
      → 孩子点 [再听一次] / [下一个] 逐词走完 3–5 个词
         （可点「跳过带逛」，直接进任务；tour_completed=false）
  → 卡片进入「任务」：切到目标房间 → TTS “Find the sofa.”
      → 孩子点房间里的物品
          → 点对：老师夸一句，进入下一个目标
          → 点错：老师说出点到的词，提示再找；同一目标错满 max_attempts 则揭示
  → 卡片进入「小结」：显示找到几个词 / 任务对了几题
      → 孩子点 [去答题，赢星星]
  → 回执回给 AI
  → 英语老师调 english_quiz(mode:"read_aloud") 复测 2–3 个目标词
      → 答对授 1 星
```

**中途关闭 sheet**：sheet 的 ✕/下拉关闭由 `ChatPage.bindSheet.onDisappear` 提交
`completed:false, cancelled:true` 的取消回执（现有行为），本课结束，不保留进度、不能从横幅重开。
卡片内另提供「退出本课」文字链，提交带部分 lesson 统计的取消回执，让 AI 知道孩子走到哪一步。

---

## 4. 工具契约

### 4.1 参数扩展

`room_english` 现有参数：`focus`、`words`、`skill_key`。新增可选 `lesson`：

```json
{
  "focus": "living",
  "words": ["sofa", "coffee_table", "rug"],
  "skill_key": "english_vocab",
  "lesson": {
    "steps": [
      {
        "id": "sofa",
        "word": "sofa",
        "zh": "沙发",
        "say": "Look! This is a sofa. We sit on it.",
        "say_zh": "看，这是沙发。我们坐在上面。"
      },
      {
        "id": "coffee_table",
        "word": "coffee table",
        "zh": "茶几",
        "say": "The cup is on the coffee table.",
        "say_zh": "杯子在茶几上。"
      },
      {
        "id": "rug",
        "word": "rug",
        "zh": "地毯",
        "say": "The rug is soft. We walk on it.",
        "say_zh": "地毯软软的，我们走在上面。"
      }
    ],
    "task": {
      "type": "listen_find",
      "targets": ["sofa", "rug", "coffee_table"],
      "max_attempts": 2
    }
  }
}
```

字段说明：

| 字段 | 必填 | 规则 |
|---|---|---|
| `lesson.steps` | 是 | 3–5 个；顺序即带逛顺序 |
| `steps[].id` | 是 | 必须命中 `ROOM_OBJECT_IDS`（76 个物品 id） |
| `steps[].word` | 是 | 物品英文名，用于任务提示与气泡展示；非空、≤32 字符 |
| `steps[].zh` | 是 | 物品中文，用于气泡展示；非空、≤16 字符 |
| `steps[].say` | 否 | 老师引导句（英文），≤120 字符；缺省时卡片用 `Look! This is a {word}.` |
| `steps[].say_zh` | 否 | 引导句中文，≤120 字符；有则先读中文再读英文 |
| `lesson.task.type` | 是 | v1 只允许 `listen_find` |
| `lesson.task.targets` | 是 | 3–5 个，必须是 `steps[].id` 的子集，不能重复 |
| `lesson.task.max_attempts` | 否 | 1–2，默认 2（每个目标的错误连击上限） |

`words` 与 `lesson.steps[].id` 的关系：

- 有 `lesson` 时，`words` 可以省略；若两者都传，`words` 必须与 `steps[].id` 集合一致（顺序可变）。
- 无 `lesson` 时，`words` 维持现状：最多 8 个，只做高亮。

### 4.2 校验

在 `utils/RoomEnglishValidation.ets` 扩展，继续返回 `should_retry` 给 AI：

- `lesson` 不是对象 → fail；
- `steps` 数量不在 3–5 → fail；
- 任一步 `id` 不在 `ROOM_OBJECT_IDS` → fail，错误信息列出合法 id；
- 任一步 `word` / `zh` 为空或超长 → fail；
- `steps[].id` 重复 → fail；
- `task.type !== 'listen_find'` → fail；
- `targets` 数量不在 3–5、有重复、或不在 `steps[].id` 中 → fail；
- `max_attempts` 不在 1–2 → fail；
- 有 `lesson` 且 `words` 与 steps 的 id 集合不一致 → fail；
- 无 `lesson` 时走原校验，行为不变。

失败信息要给 LLM 可执行的修正提示（与 `MapToolValidation` / `EnglishQuizValidation` 同款）。

### 4.3 向后兼容

- 老会话的 `toolCall.arguments` 没有 `lesson` → 卡片走现有自由探索。
- 老回执没有 `lesson` 字段 → 时间线回看按现有 `SummaryView` 渲染。
- Web 侧 `WordRoomApp.select / setRoom / setArea / setLabels / ids` 全部保留。

---

## 5. 卡片状态机

### 5.1 状态

`RoomEnglishCard` 增加：

```ts
type RoomLessonMode = 'free' | 'tour' | 'task' | 'summary' | 'answered'

@Local lessonMode: RoomLessonMode = 'free'
@Local tourIndex: number = 0
@Local tourCompleted: boolean = false
@Local taskIndex: number = 0
@Local taskWrongStreak: number = 0
@Local taskAttempts: number = 0
@Local taskCorrect: number = 0
@Local taskFirstTry: number = 0
@Local taskRevealed: number = 0
@Local bubbleText: string = ''
@Local bubbleTextZh: string = ''
@Local speaking: boolean = false
```

非响应式字段：

```ts
private lesson: RoomEnglishLessonPlan | null = null
private submitted: boolean = false
private suppressSelectUntil: number = 0   // 程序化 select 的回调忽略窗口
private lessonStarted: boolean = false
```

`taskTotal` 直接取 `lesson.task.targets.length`（getter），不单独存字段。

### 5.2 状态流转

```
aboutToAppear
  ├─ 解析 lesson；无 lesson → mode='free'（现有逻辑）
  └─ 有 lesson → mode='tour'（pageReady 后启动）

pageReady
  ├─ mode='tour' → setAutoSpeak(false) → presentStep(0)
  ├─ mode='task'/'summary' → 重载后按当前索引恢复（Web 刷新不丢进度）
  └─ mode='free' → 现有 applyFocusWords()

presentStep(i)
  ├─ app.setRoom(resolveRoomEnglishView(focus))（focus 缺省 all → overview）
  ├─ app.select(id)（程序化，suppress；打开单词卡）
  ├─ 气泡显示 say / say_zh
  └─ TTS：say_zh → say（缺省 say）

[下一个] → presentStep(i+1)
  最后一步 → tourCompleted=true → startTask()

[跳过带逛] → tourCompleted=false → startTask()

startTask()
  ├─ taskIndex=0, taskWrongStreak=0, taskAttempts=0, taskCorrect=0,
  │  taskFirstTry=0, taskRevealed=0
  ├─ mode='task'
  └─ presentTaskStep()

presentTaskStep()
  ├─ app.prepareFind(targetId)（切到目标房间、关闭单词卡，不朗读、不泄露答案）
  ├─ 气泡/TTS：Find the {word}.
  └─ 等待孩子点击

onSelect(id, word)（孩子点击）
  ├─ mode='tour' → 仅记录 explored（现有 noteSelected）
  ├─ mode='task' → judgeTaskTap
  │     ├─ correct → taskCorrect++（首次则 firstTry++）；气泡夸；TTS
  │     │            1.2s 后 advanceTask()
  │     ├─ wrong → taskAttempts++；taskWrongStreak++；
  │     │          气泡 “That's a {word}. Try again.”；TTS
  │     │          若 taskWrongStreak >= maxAttempts → revealTask()
  │     ├─ repeat_wrong → 不累加；气泡重复提示
  │     └─ ignore（已揭示/已推进/空 id）→ 不处理
  └─ mode='free' → 现有 noteSelected

revealTask()
  ├─ taskRevealed++
  ├─ app.select(targetId)（程序化，suppress；打开单词卡揭示答案）
  ├─ 气泡 “Here it is! This is a {word}.”；TTS
  └─ 1.5s 后 advanceTask()

advanceTask()
  ├─ taskIndex++；taskWrongStreak=0；lastWrongId=''
  └─ 还有目标 → presentTaskStep()；否则 → mode='summary'

[去答题，赢星星] → submit()
[退出本课] → cancelLesson()
```

### 5.3 程序化 select 的回传隔离

`WordRoomApp.select(id)` 会触发 Web 的 `syncSelection`，后者通过 `RoomNativeBridge.onSelect` 回传。带逛/揭示时这是程序化选择，不应被当成孩子点击：

- 调用 `select` 前置 `suppressSelectUntil = Date.now() + 1000`；
- `selectHandler` 里 `if (Date.now() < suppressSelectUntil) return`；
- 任务阶段的 `prepareFind` 不调用 `select(id)`，所以不会产生 `onSelect`；它内部用 `chooseObject(null)` 清空选中。
- 任务阶段的孩子点击不在窗口内，正常判定。

### 5.4 语音策略

- 带逛/任务期间关闭 Web 自动朗读：新增 `WordRoomApp.setAutoSpeak(false)`，`syncSelection` 里用 `if (state.autoSpeak) speakCurrentWord()` 守卫。
- 所有课堂语音由原生 `ServiceRegistry.tts()` 负责，避免双声道：
  - 带逛：`say_zh` → `say`（有中文先中文）；
  - 任务：`Find the {word}.`；
  - 点错：`That's a {word}. Try again.`；
  - 点对：`Yes! This is a {word}.`；
  - 揭示：`Here it is! This is a {word}.`
- 单词卡里的「听发音」按钮保留，孩子可以单独点；它直接调用 `speakCurrentWord`，不受 `autoSpeak` 影响。
- TTS 失败只 log，不阻塞状态机；`speaking` 恢复 false。

### 5.5 2D 老师气泡

在 `Stack` 底部叠加一层原生 UI（不挡 3D 旋转区域）：

```
┌──────────────────────────────────┐
│  3D 房间（Web）                   │
│                                  │
│  ┌────────────────────────────┐  │
│  │ (英) 小星老师      2 / 4    │  │
│  │ Look! This is a sofa.      │  │
│  │ 看，这是沙发。我们坐在上面。 │  │
│  │ [🔊 再听一次]  [下一个 ›]   │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

任务态：

```
│ (英) 找一找：Find the sofa.      │
│ [🔊 再听一次]                    │
```

小结态：

```
│ (英) 太棒了！你找到了 3 个词     │
│ 任务答对 2 / 3 · 第一次就找到 1  │
│ [去答题，赢星星 ›]               │
```

头部栏：

- 带逛：`第 2 / 4 个词` + 「跳过带逛」文字链；
- 任务：`任务 2 / 3`；
- 小结：`本课完成`；
- 右上角保留 sheet 自带的 `✕`（关闭 = 退出本课）；卡片头部另给「退出本课」文字链。
- 自由探索模式维持现有 `HeaderBar`（已收集 N / 76 + 我学会了）。

---

## 6. 回执

### 6.1 payload

```ts
export interface RoomEnglishLessonResult {
  tour_completed: boolean
  tour_words: string[]        // id 列表
  task_type: string           // 'listen_find'
  task_targets: string[]      // id 列表
  task_correct: number        // 最终答对的目标数（含点错一次再点对）
  task_first_try: number      // 第一次点击就答对的目标数
  task_revealed: number       // 错满 max_attempts 被揭示的目标数
  task_total: number
  task_attempts: number       // 任务阶段总点击次数
  task_completed: boolean
}

export interface RoomEnglishAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  focus: string
  skill_key: string
  cancelled: boolean
  lesson: RoomEnglishLessonResult | null
}
```

- `completed`：有 lesson 时 = `task_completed`；无 lesson 时 = 探索过至少 1 个物品（现有行为）。
- `cancelled`：孩子点「退出本课」或 sheet 被外部关闭。
- `words`：孩子实际点开过的物品 id（沿用现有进度集合）；带逛的程序化选中不计入。
- `lesson.tour_words`：本课脚本里的 3–5 个词 id。
- `task_correct / task_first_try / task_revealed` 三者满足
  `task_correct + task_revealed = task_total`（每个目标要么最终答对，要么被揭示）。
- `task_attempts`：任务阶段所有点击（含错误、含揭示前最后一次错误）；重复点同一个错误物品也计入点击次数，但不增加 `taskWrongStreak`。
- 中途退出时，`lesson` 里带当前的部分统计，`task_completed=false`，`cancelled=true`。

### 6.2 时间线回看

`readAnsweredPayload` 解析 `lesson`；`SummaryView` 增加：

- `本课带逛：sofa / coffee table / rug`（id → `steps[].word` 映射）
- `听词找物：答对 2 / 3 · 第一次就找到 1`
- 没有 `lesson` 时保持现有“一共点开了 N 个物品”。

### 6.3 sheet 关闭时的回执

`ChatPage.bindSheet.onDisappear` 现有逻辑提交硬编码的取消回执（`lesson: null`）。
本版**不改 ChatPage**；sheet 的 ✕/下拉关闭走这条路径，卡片内的「退出本课」走
`onAnswer` 并带部分 lesson 统计。两条路径都让 pending 立即结束，不会挂起。

---

## 7. 提示词与工具描述

### 7.1 `KIDS_ENGLISH_SYSTEM_PROMPT`

把 ② 呈现段改为：

```
② 呈现(家居/房间/厨房/阳台词汇): room_english 传 lesson：
   steps 3-5 个 {id, word, zh, say, say_zh}，task{type:「listen_find」, targets 3-5 个}；
   卡片会自动带逛并出「听词找物」任务，回执带 task_correct / task_first_try / task_revealed。
   收到回执后立刻用 english_quiz(mode:「read_aloud」) 复测 2-3 个目标词并授星
   （read_aloud 不受本地词库限制；不要用 picture_word 考房间词，本地没有对应图片）。
   若 task_revealed > 0 或 task_first_try < task_correct，先重讲错词再出题。
   room_english 本身不授星。
```

同时保留现有 `words` / `focus` 用法说明，明确 `lesson` 是可选的高级用法。

### 7.2 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 的「全屋 3D 英语探索」段

同步改成带 `lesson` 的闭环描述，措辞比学科老师略简；收尾同样优先 `read_aloud`。

### 7.3 `BuiltinTools.ets` 的 room_english schema / description

- schema 增加 `lesson` 对象及字段说明；`steps[].id` 说明“与 words 相同的 76 个物品 id”。
- description 增加：`Use lesson for a guided mini-lesson (3-5 words + listen_find task); after the receipt, follow up with english_quiz read_aloud to check and award stars.`
- 注意 JSON-in-template-literal 陷阱：schema description 里用「」替代 ASCII 双引号；改完用 `node -e` 提取 `rawSchemaJson` 并 `JSON.parse` 验证。

---

## 8. 星星与台账

- **不新增** `StarActivityType`、不改 `StarRewardService`、不改 `StarEventModels`。
- `room_english` 仍然不调用 `recordStarEvent`。
- 学习台账：`LedgerExtractUtils` 目前对 `room_english` 返回空（no-op）。本设计不新增台账提取；任务结果通过回执给 AI，由 AI 决定 `child_profile` 更新。

---

## 9. 降级与边界

| 场景 | 行为 |
|---|---|
| `lesson` 参数非法 | 预校验失败，返回 `validation_failed + should_retry`，不进入 pending |
| Web 场景加载失败 | 沿用现有错误态 + 「重新加载」；lesson 状态保留，重载后 `onPageEnd` 按当前 `tourIndex/taskIndex` 恢复 |
| TTS 失败 | log + `speaking=false`，状态机继续；孩子可点「再听一次」 |
| 孩子点错对象 | 显示错误反馈；同一目标错满 `max_attempts` 后揭示答案并继续，不阻塞 |
| 孩子重复点同一个错误对象 | 只重复提示，不增加 `taskWrongStreak`；`task_attempts` 仍 +1 |
| 孩子中途关闭 sheet | 等同退出本课：取消回执，进度不保留 |
| 孩子点「退出本课」 | 回执 `cancelled:true` + 部分 lesson 统计；`completed` 始终等于 `task_completed`（任务完成前退出为 false，小结中退出为 true）
| 目标词跨房间 | 每道任务题切到目标房间；带逛按 `focus` 切视图 |
| 老会话无 lesson | 完全走现有自由探索 |

---

## 10. 文件与触点

| 文件 | 改动 |
|---|---|
| `utils/RoomEnglishValidation.ets` | 扩展 `lesson` 校验；新增 `RoomEnglishLessonPlan / LessonStep / LessonTask` 类型；`RoomEnglishValidationResult` 增加 `lesson` |
| `utils/RoomEnglishLesson.ets`（新建） | 纯状态机函数：`createTaskState`、`judgeTaskTap`、`advanceTask`、`currentTarget`、`isTaskComplete`、`buildTaskPrompt`（可 hypium 测试） |
| `components/room/RoomEnglishCard.ets` | 状态机、气泡 UI、TTS 编排、回执、时间线回看 |
| `resources/rawfile/room3d/assets/room-app.js` | 新增 `WordRoomApp.setAutoSpeak(false)`、`WordRoomApp.prepareFind(id)`；`syncSelection` 守卫自动朗读 |
| `config/BuiltinTools.ets` | `room_english` schema + description 增加 `lesson` |
| `models/AssistantModels.ets` | `KIDS_ENGLISH_SYSTEM_PROMPT` + `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 的 room_english 段 |
| `entry/src/ohosTest/ets/test/utils/RoomEnglishValidation.test.ets` | 补 lesson 校验用例 |
| `entry/src/ohosTest/ets/test/utils/RoomEnglishLesson.test.ets`（新建） | 纯状态机用例 |
| `docs/superpowers/specs/2026-10-30-room-english-guided-lesson-design.md` | 本文档 |

无需改动：`ToolExecutionService.handleRoomEnglish`（校验通过后原样挂起）、`StarEventModels`、`StarRewardService`、`MessageBubble` 横幅（文案可后续优化）、`ChatPage` 的 sheet 挂载与 `onDisappear` 取消逻辑。

---

## 11. 测试计划

### 11.1 单元测试（hypium）

`RoomEnglishValidation.test.ets`：

- 无 `lesson`：旧参数仍通过；
- 合法 lesson：解析出 steps/task；
- steps 数量 2 / 6 → fail；
- step id 不在 76 个物品内 → fail；
- step id 重复 → fail；
- `word` / `zh` 为空或超长 → fail；
- `task.type` 非 `listen_find` → fail；
- `targets` 不在 steps 中 / 重复 / 数量不在 3–5 → fail；
- `max_attempts` 0 / 3 → fail；
- 有 lesson 且 `words` 与 steps 不一致 → fail；
- `say` / `say_zh` 超长 → fail。

`RoomEnglishLesson.test.ets`：

- 第一次点对 → `correct`，`firstTry+1`，`correct+1`；
- 点错一次再点对 → `correct`，`firstTry` 不变，`correct+1`；
- 点错第一次 → `wrong`，`wrongStreak=1`，`attempts+1`；
- 重复点同一个错误对象 → `repeat_wrong`，`wrongStreak` 不变，`attempts+1`；
- 点错达到 maxAttempts → `reveal`，`revealed+1`；
- 已揭示的目标再次点击 → `ignore`；
- 空 id → `ignore`；
- 任务全部完成 → `isTaskComplete=true`；
- 带逛最后一步 → `next` 返回 `task`。

### 11.2 手工验收

1. 英语老师新会话，说“我想学家居单词”，应调 `room_english` 带 `lesson`；
2. 卡片按 3–5 个词依次高亮，气泡中英文正确，TTS 只响一次（Web 不抢读）；
3. 点「下一个」走到任务；TTS 说 “Find the sofa.”，且场景已切到沙发所在房间、单词卡关闭；
4. 点对：夸赞 + 进入下一个；点错：说出点到的词 + 提示；重复点同一个错误物品不会快速触发揭示；错满两次：揭示答案并继续；
5. 任务结束显示答对 N / M、第一次就找到 K；
6. 点「去答题，赢星星」→ sheet 关闭 → 老师调 `english_quiz(mode:"read_aloud")` 复测 2–3 个目标词；
7. 答对 `english_quiz` 授 1 星；
8. 中途点 sheet 的 ✕/下拉 → 回执 `cancelled:true`，对话继续；重开横幅不再出现（本课结束）；
9. 点「退出本课」→ 回执带部分 lesson 统计，`cancelled:true`，对话继续；
10. 老会话（无 lesson）仍按自由探索渲染。

---

## 12. 实施顺序

1. `utils/RoomEnglishValidation.ets` 扩展 + 单元测试；
2. 新建 `utils/RoomEnglishLesson.ets` 纯状态机 + 单元测试；
3. `room-app.js` 加 `setAutoSpeak` / `prepareFind`；
4. `RoomEnglishCard` 状态机 + 气泡 UI + 回执 + 时间线回看；
5. `BuiltinTools.ets` schema / description；
6. `AssistantModels.ets` 两份提示词；
7. 编译 + 手工验收。

---

## 13. 开放问题（实施时按默认值处理）

- 带逛是否自动进入任务：默认最后一步点「下一个」后自动进入任务，不额外加“开始任务”按钮。
- 任务目标数量：默认取 `targets` 全部（3–5 个），不随机抽取。
- 是否给带逛加“跳过”：默认加，跳过直接进入任务，`tour_completed=false`。
- 气泡位置：默认底部悬浮卡，避免遮挡顶部房间标签。
- 任务阶段是否显示英文标签：默认不主动打开；孩子自己点场景里的开关才显示。
