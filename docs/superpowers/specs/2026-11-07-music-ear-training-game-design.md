# 音符小耳朵 · 音乐听觉小游戏设计

**日期：** 2026-11-07
**版本：** v1
**状态：** 待评审
**参考设计：** `/Users/mac/Library/Application Support/Open Design/namespaces/release-stable-intel/data/projects/eaffedd6-2b2e-4986-8450-f6ba70f76dc0/index.html`（《音符小精灵回家啦 · 糖果音乐森林》）
**范围：** 给小星游戏老师（`kids_games`）新增一个音乐小游戏工具 `music_ear`，包含原生音频合成、互动卡片、三种耳朵练习、星星与 AI 集成

---

## 1. 背景与目标

参考设计是一个面向低龄儿童的网页音乐游戏：6 个彩色琴键（C D E F G A）、糖果森林视觉、5 种玩法（跟弹 / 节奏接音符 / 音乐小路 / 记忆小旋律 / 双人合作）+ 自由敲琴。它的核心是「看谱跟弹」，声音用 Web Audio 现场合成。

本项目要做的不是照搬，而是把它改造成**耳朵训练**：孩子通过听声音作答，而不是看音符下落跟弹。

**目标**

1. 孩子第一次打开时可以先自由敲 6 个琴键，熟悉每个键的声音和颜色。
2. 三种由浅入深的听觉练习：
   - `high_low` 听两个音，判断谁更高；
   - `echo` 听 3~5 个音，按顺序复述；
   - `guess_song` 听一小段旋律，猜是哪首儿歌。
3. 声音是现场合成、按键即响，不是播放录音；三种音色（钢琴 / 木琴 / 八音盒）可切换。
4. 全程单人、不催不罚不排名；答错可以再听一遍、再试一次。
5. 完成一轮练习后按表现授星，接入现有星星体系；AI 收到结果后可更新 `observation` 维度并邀请下一轮。

**成功标准**

- 孩子能在没有成人解释的情况下，从「自由敲琴」自然进入第一关。
- 听两个音的高低、听 4 个音复述、听 6 个音猜歌，三条路径都能独立完成一轮。
- 音准正确、按键无感知延迟（目标 < 80ms），连续弹奏不爆音、不卡顿。
- 老师能根据返回结果说出「你听对了几个」，并据此决定下一轮难度。

---

## 2. 用户与场景

- **使用者**：5~7 岁儿童，独自在小星游戏老师会话里玩。
- **陪伴者**：无。卡片不假设有第二个玩家，因此参考里的「双人合作」不实现。
- **场景**：孩子点开老师发来的工具卡片，进入全屏游戏；一轮 5 题，约 2~4 分钟；可随时退出。
- **设备**：HarmonyOS 手机为主，外放或耳机；音量由系统控制。

---

## 3. 整体体验流程

```
老师发起 music_ear（drill + difficulty）
  ↓
卡片打开：自由敲琴页（6 个彩色键 + 3 种音色 + 「开始练习」）
  ↓ 孩子按「开始练习」
第 1 题 → 第 2 题 → … → 第 5 题
  ↓ 每题：听 → 作答 → 即时反馈（答错可重听/重试，但首答计入准确率）
结算页：答对 N / 5、首答正确数、星星、歌曲回顾
  ├─ 「再来一轮」→ 本地重开，不提交
  ↓ 「回消息」或关闭 sheet（提交最好的一轮）
结果 JSON 回传 → 老师回应 → 星星入账
```

- 卡片有三个内部页面：`free`（自由敲琴）→ `round`（正式练习）→ `summary`（结算）。
- 老师发起的 `drill` 决定「开始练习」进入哪种练习。**练习中途不能切换 drill**；切换入口只出现在自由页和结算页，切换即开始新一轮（当前轮作废，不计入提交）。
- **一次工具调用只提交一次结果**：一轮结束后进入结算页，但此时还**不**调用 `onAnswer`。孩子在结算页可以点「再来一轮」本地重开（不提交、不重复记星）；只有点「回消息」或关闭 sheet 时才提交。
- 提交规则：报告**本次工具调用中表现最好的一轮**（按 `first_try_correct` 取最高，平手取先完成的那轮），并附带 `rounds_played`。这样重复练习不会重复刷星，也不会因为最后一轮手感差而抹掉最好成绩。
- 如果孩子在一轮中途关闭 sheet 或退出：回传 `completed: false`、`cancelled: true`，0 星，老师安慰并邀请下次再玩。
- 该生命周期同时避免了「第一轮已 `resolvePendingAnswer`、第二轮静默无结果」的二次提交问题。

---

## 4. 三种练习规则

### 4.1 `high_low` 听两个音谁高

- 连续播放两个音（间隔约 650ms，第二个音稍短）。
- 三个选项：**第一个高 ⬆️** / **第二个高 ⬇️** / **一样高 ＝**；图标在上、短文字在下，照顾还不识字的孩子。
- 难度决定两个音的距离：
  - 1 级：音程 ≥ 3 个键（如 C 与 A）；
  - 2 级：音程 2 个键；
  - 3 级：音程 1 个键，并且有约 25% 概率出现「一样高」。
- 作答后：正确 → 小精灵飞起 + 星星音效；错误 → 琴键轻晃，提示「再听一次」，可重听并可重选，但该题首答记为错误。
- 每题只记录一次首答结果；重试直到答对才进入下一题（避免挫败感）。

### 4.2 `echo` 听 3~5 个音复述

- 播放一段无节奏压力的音序列（每音约 550ms，间隔 120ms）。
- **播放时不高亮任何琴键**，也不按音高映射颜色：舞台上只出现中性的金色音符精灵，逐个浮现后消失。否则孩子会直接照着灯抄答案，耳朵练习失效。
- 孩子按下的琴键才高亮；点错时该键晃动并播放错误音。
- 孩子按顺序点琴键复述。
- 难度决定序列长度：1 级 3 个音，2 级 4 个音，3 级 5 个音；音域始终取 6 键。
- 点错时：该键晃动、播放错误音，整段序列重新播放，孩子从第 1 个音重新按；该题首答记为错误。
- 提供「再听一遍」按钮（不消耗次数）。
- 全部按对后进入下一题。

### 4.3 `guess_song` 听旋律猜儿歌

- 播放一首儿歌的前 6~8 个音（取自内置歌单）。
- 选项卡片显示「图标 + 歌名」：1 级 3 个选项，2 级 4 个，3 级 5 个；干扰项优先选音符走向相近的曲子。每首歌配一个固定 emoji/图形（小星星 ⭐、两只老虎 🐯、小蜜蜂 🐝、划小船 ⛵、小羊羔 🐑、欢乐颂 🎵），孩子可以靠图形辨认。
- 老师发起工具前会用一句话说明「听完选一个」，卡片内不依赖孩子读长句。
- 作答后：正确 → 显示歌名并再播一遍**同一段**旋律（题面用的 6~8 个音，不另找副歌边界）；错误 → 允许重听并重选，首答记错。
- 歌单复用参考设计的 6 首：小星星、两只老虎、欢乐颂、小羊羔、划小船、小蜜蜂。

### 4.4 题库与随机性

- 所有题目由卡片本地生成，AI 只传 `drill` 与 `difficulty`，不传具体音符。
- 随机数通过可注入的 seed / RNG 接口生成，保证纯函数可测。
- 同一轮内不重复出现同一道 `high_low` 题；`guess_song` 同一轮内不重复同一首歌。

---

## 5. 自由敲琴（开场页）

- 6 个彩色琴键始终可点，按下立即出声并被按压缩放；音符精灵从键上飞起。
- 顶部音色切换：钢琴 / 木琴 / 八音盒。
- 页面文案：「先随便按按，听听每个小音符的声音」。
- 右下角主按钮：「我准备好啦 · 开始练习」。
- 首次进入默认落在自由敲琴页；从结果页「再玩一次」回到本轮练习第一题，不强制再自由敲琴。
- 音量：跟随系统；卡片右上角提供静音开关（只静音本卡片，不改系统音量）。

---

## 6. 音频引擎设计

### 6.1 技术选型

**原生 PCM 合成 + `@ohos.multimedia.audio` AudioRenderer**，不采用 WebView / Web Audio。

理由：

- 项目现有 Web 容器（`room3d` / `city3d` / `farm3d`）均为 three.js 视觉页，发音一律走原生 TTS 桥；ArkWeb 的 Web Audio 支持没有可靠验证，且当前无设备可实测。
- 原生合成音准、延迟、音量包络完全可控；按键到发声目标 < 80ms。
- 卡片走现有 pending answer / 星星 / MessageBubble 流程，不需要额外的 JS 桥。

### 6.2 服务接口

新文件：`services/MusicToneService.ets`，单例。

```ts
type MusicTimbre = 'piano' | 'xylophone' | 'musicbox'
type MusicNote = 'C' | 'D' | 'E' | 'F' | 'G' | 'A'

interface MusicToneServiceLike {
  ensureStarted(): Promise<boolean>   // 懒创建 AudioRenderer，失败返回 false
  playNote(note: MusicNote, timbre: MusicTimbre): void
  playSequence(notes: MusicNote[], timbre: MusicTimbre, noteMs: number, gapMs: number,
               onNote?: (index: number) => void): number  // 返回播放 token，用于取消
  stopAll(): void
  release(): void
  setMuted(muted: boolean): void
}
```

- 采样率 48000Hz、双声道、S16LE、`StreamUsage.STREAM_USAGE_GAME`。
- 音频线程用 `on('writeData')` 回调填 PCM；UI 线程只把「待播放音符」压入队列，不在回调里做重活。
- 音色通过谐波叠加实现（复用参考工程的配方）：
  - 钢琴：三角波基音 + 2×、3× 正弦泛音；
  - 木琴：正弦基音 + 3×、4.2× 短泛音；
  - 八音盒：正弦基音 + 2.76×、5.4× 长泛音 + 三角波 2×。
- 每个音有 5~6ms attack、按音色 0.45~1.2s 指数衰减；多音重叠时混音并做软限幅，避免爆音。
- `playSequence` 在音频引擎内按采样点排期，保证节奏稳定；视觉高亮通过 `onNote` 回调（UI 定时器）近似同步，允许 ±30ms 偏差。
- `release()` 在卡片 `aboutToDisappear` 调用；再次进入时重新创建。
- **音频初始化失败时不允许开始练习**：`high_low` 和 `guess_song` 没有任何视觉刺激，静音「作答」等于瞎猜；`echo` 听不到序列也无法完成。卡片显示「声音没打开」面板，提供「重试」和「先回去」，不生成 `completed: true` 的结果。关闭时仍回传 `cancelled: true`。自由页可以进入，但顶部常驻提示，琴键按下只有按压动效、不出声。

### 6.3 频率表

| 键 | 音名 | 频率 |
|---|---|---|
| C | C4 | 261.63 |
| D | D4 | 293.66 |
| E | E4 | 329.63 |
| F | F4 | 349.23 |
| G | G4 | 392.00 |
| A | A4 | 440.00 |

---

## 7. 卡片组件设计

新文件：`components/MusicEarCard.ets`。

### 7.1 公开 API

```ts
interface MusicEarResult {
  drill: string            // 'high_low' | 'echo' | 'guess_song'
  difficulty: number       // 1 | 2 | 3
  total: number            // 最好那轮的题数，固定 5
  correct: number          // 最好那轮最终答对题数（重试后答对也算）
  first_try_correct: number
  completed: boolean
  stars: number
  songs: string[]          // guess_song 最好那轮出现的歌名，其他 drill 为空数组
  rounds_played: number    // 本次工具调用内完整玩完的轮数
  cancelled?: boolean
}

@ComponentV2
export struct MusicEarCard {
  @Param toolCall: ToolCall
  @Param isAnswered: boolean
  @Param answeredPayload: string
  @Param largeSize: boolean
  @Param onRequestClose?: () => void   // 参考 MazeCard；由 ChatPage 传入
  @Event onAnswer: (toolCallId: string, answerJson: string) => void
}
```

### 7.2 页面结构

```
┌──────────────────────────────────────┐
│  🎵 音符小耳朵        [🔊] [✕]        │  标题栏（sheet 模式）
├──────────────────────────────────────┤
│  小精灵舞台（播放时音符精灵飞起）       │
│                                      │
│  进度 2 / 5   ▓▓▓▓░░░░░░              │
├──────────────────────────────────────┤
│  C    D    E    F    G    A          │  6 个彩色琴键
│ 🍎   🍊   ☀️   🍃   💧   🍇          │
├──────────────────────────────────────┤
│  题目区 / 选项 / 「再听一遍」          │
└──────────────────────────────────────┘
```

- **自由页**：舞台 + 6 键 + 音色切换 + 三种 drill 切换 + 开始按钮。
- **练习页**：舞台 + 进度 + 6 键 + 题干与选项（`high_low` 三个图标按钮、`echo` 只显示「请按顺序弹出来」、`guess_song` 图标 + 歌名卡片网格）。练习页不提供 drill 切换。
- **结算页**：答对题数、首答正确数、星星、歌名回顾、drill 切换、「再来一轮」「回到自由敲琴」「回消息」。
- 键盘是唯一的声音输入，也是 `echo` 的作答方式；`high_low` / `guess_song` 的作答按钮在键盘上方。

### 7.3 视觉

- 跟随 `docs/brand-spec.md` 的儿童端暖色绘本皮肤：暖米白底、暖黑字、大圆角、≥44vp 触控目标。
- 6 个键沿用参考设计的水果角色与色相（苹果红 / 橘子橙 / 太阳黄 / 叶子绿 / 水滴蓝 / 葡萄紫），每键配 `--x-ink` 同级深色文字，保证对比度。
- 保留「小精灵」意象：每个音符是一个有眼睛的小圆角色；播放/答对时向上飞并淡出。
- 不使用参考工程的整页糖果森林背景图；用一个轻量舞台（渐变天空 + 云 + 小山坡）即可，控制实现量。
- 深色模式下游戏面板仍保持暖色绘本皮肤（与儿童主屏一致），外围聊天 chrome 跟随主题。

### 7.4 交互与状态

- `aboutToAppear`：解析参数、clamp 难度、初始化 `MusicToneService`、生成第一轮题目。
- 键盘按压：立即 `playNote`；`echo` 模式下同时作为答案输入。
- 答错不弹失败弹窗，只在题内提示「再听一次」；答对不弹窗，音符飞起 + 轻量音效。
- 一轮结束时只在本地生成结果快照，**不调用** `onAnswer`；结算页的「再来一轮」只做本地重置。点「回消息」或 sheet 关闭（含拖拽）时才提交，并用 `submitted` 标志保证一次工具调用只提交一次。
- 结算页与自由页提供 drill 切换；练习页不提供。
- 所有计时器 / 播放 token 在 `aboutToDisappear` 清理；未提交时按中途退出回传 `cancelled`。

### 7.5 小屏与全屏

- 卡片以全屏 sheet 为主（参考 maze / handwriting 模式）；气泡内只显示「待答横幅」与「已答结果摘要」，不渲染完整键盘。
- `largeSize === true` 时去掉卡片外壳（透明背景、无内边距），由 sheet 提供 chrome。

---

## 8. 工具契约与 AI 集成

### 8.1 工具定义

```json
{
  "name": "music_ear",
  "description": "给 5-7 岁孩子播放声音并让他用耳朵作答的音乐练习。drill 三选一：high_low 听两个音判断谁更高；echo 听 3-5 个音按顺序弹出来；guess_song 听一小段旋律猜是哪首儿歌。卡片内自带自由敲琴热身页，不要在本工具之外再描述题目内容。",
  "parameters": {
    "drill": { "type": "string", "enum": ["high_low", "echo", "guess_song"] },
    "difficulty": { "type": "number", "enum": [1, 2, 3] }
  },
  "required": ["drill", "difficulty"]
}
```

- `difficulty`：1 = 5 岁 / 2 = 6 岁 / 3 = 7 岁，与 `child_profile.observation` 的 level 对应。
- 参数在进入 pending 前经 `utils/MusicEarValidation.ets` 校验：`drill` 必须命中三值、`difficulty` 必须是 1~3 的整数。非法值返回 `{ error: 'validation_failed', should_retry: true }`，让 LLM 自行修正。
- 卡片侧再做一次 clamp 兜底（防御 AI 直接传坏值）。

### 8.2 挂起与回传

- 走 `ToolExecutionService.handleMusicEar`，镜像 `handleMemoryMatch`：设 `toolId` / `displayName` / `sourceType` / `permissionLevel=READ`，`approvalState='pending'`，挂 `pendingAnswers` Promise。
- 卡片 `onAnswer` → `resolvePendingAnswer` → 结果 JSON 回传 LLM。
- 关闭 sheet 未作答：回传 `{ completed: false, cancelled: true, drill, difficulty }`。
- 外部停止 / 取消：走 `buildCancelledResult`。

### 8.3 归属

- **只锁进 `kids_games`**（`KIDS_GAMES_LOCKED_TOOL_IDS`），不进小星老师 default，也不进数学 / 英语 / 语文老师。与 `memory_match` 的专属先例一致。
- 老师系统提示词新增一段：说明三种 drill、难度映射、以及「先让孩子自由敲琴再开始」的开场话术。
- 画像：结果回传后只允许更新 `observation`（听辨观察）；不新增画像维度。

---

## 9. 星星与结算

- 新增 `StarActivityType = 'music_ear'`，元数据：
  - emoji `🎵`，shortLabel `音乐`，longLabel `音符小耳朵`，grantedHint `音符小耳朵完成`，unit `局`。
- `computeStars`：

```ts
if (activityType === 'music_ear') {
  if (payload['completed'] !== true) return 0
  return computeMusicEarStars(
    (payload['difficulty'] as number) ?? 1,
    (payload['total'] as number) ?? 5,
    (payload['first_try_correct'] as number) ?? 0
  )
}
```

- 含义：完成一轮至少 1 星；首答正确率 ≥ 80% 时按难度给 2~3 星。中途退出 0 星。
- 结算页显示最好一轮的星数；星星实际入账仍由 `StarRewardService.recordEvent` 统一处理。

---

## 10. 数据与纯函数

新文件 `utils/MusicEarData.ets`：

- `MUSIC_NOTE_ORDER: MusicNote[]`、`MUSIC_NOTE_FREQ: Record<MusicNote, number>`
- `MUSIC_KEYS`：每键的角色名、颜色、深色、图标 id
- `MUSIC_SONGS`：6 首儿歌的 `{ key, name, notes: MusicNote[] }`
- `MUSIC_TIMBRES`：三种音色元数据

新文件 `utils/MusicEarLogic.ets`（纯函数，可测）：

- `buildHighLowQuestion(difficulty, rng)` → `{ first, second, answer }`
- `buildEchoSequence(difficulty, rng)` → `MusicNote[]`
- `buildGuessSongQuestion(difficulty, rng, usedSongs)` → `{ songKey, options, answer }`
- `evaluateEcho(expected, pressed)` → `{ correct: boolean, firstWrongIndex: number }`
- `computeMusicEarStars(difficulty, total, firstTryCorrect)` → `number`；**卡片结算页与 `StarRewardService` 共用这一个纯函数**，避免两套公式漂移。
- `scoreRound(questionResults)` → `{ correct, firstTryCorrect }`（只算计数，不算星）
- `clampDifficulty(value)`、`normalizeDrill(value)`

新文件 `utils/MusicEarValidation.ets`：

- `validateMusicEarArgs(argsJson)` → `{ ok, drill, difficulty, error? }`，供 `handleMusicEar` 在 pending 前使用。

测试：`entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets`，覆盖三题型的边界（难度 1/3、同音、选项去重、序列长度、计分与星级），使用固定 seed 的伪随机数。

---

## 11. 集成触点（10 步配方）

按 `.claude/skills/adding-mini-game-tool/SKILL.md` 执行，新增第 9 个文件 `services/MusicToneService.ets`。

| # | 文件 | 改动 |
|---|------|------|
| 1 | `utils/SearchToolIdentityUtils.ets` | `MUSIC_EAR_TOOL_ID` + `isMusicEarFunctionName()` |
| 2 | `config/BuiltinTools.ets` | import、`MusicEarArgs`、executor、`createMusicEarToolDefinition`、config、register、`getBuiltinToolIds()` |
| 3 | `services/ToolExecutionService.ets` | import、`handleMusicEar`、dispatch（放在 `resolveToolId` 兜底之前） |
| 4a | `models/StarEventModels.ets` | 10 处漂移点加 `music_ear` |
| 4b | `services/StarRewardService.ets` | `computeStars` 加 `music_ear` 分支 |
| 5 | `models/AssistantModels.ets` | import、`KIDS_GAMES_LOCKED_TOOL_IDS`、游戏老师提示词段 |
| 6 | `components/MusicEarCard.ets` | 新卡片（见 §7） |
| 7 | `components/MessageBubble.ets` | import、待答横幅、已答摘要、3 个 or 链、点击分发、step 内容（7 处） |
| 8 | `pages/ChatPage.ets` | `showMusicEarSheet` + `bindSheet` + `MusicEarSheetBuilder` + 关闭时回传 cancelled |
| 9 | `services/MusicToneService.ets` | 新音频服务（见 §6） |
| 10 | 校验 | JSON.parse gauntlet、4-grep、MessageBubble 7 处、`assembleHap`、真机验收 |

**可选步骤决策（开工前记录）**

- Step 8 largeSize sheet：**YES**，键盘 + 舞台 + 选项需要全屏；气泡内只放横幅。
- Step 9a PreferencesService 最佳成绩：**NO**，听觉训练没有单一「最好成绩」语义，`star_events` 已保留历史。
- Step 9b DatabaseService 记录表：**NO**，结果 JSON 已随 `star_events.metadata_json` 持久化。

---

## 12. 非目标

- 不做双人合作（孩子独自玩）。
- 不做看谱跟弹、音符下落、节奏判定——参考工程的这三块核心引擎不复用。
- 不做家长音量 / 时长 / 每日次数设置页——沿用 App 现有儿童时长与每日配额控制，卡片只提供静音。
- 不做录音、麦克风输入、音准打分。
- 不做自由作曲 / 乐谱编辑 / 五线谱教学。
- 不引入 WebView 或新的第三方依赖。
- 不新增加画像维度；`observation` 复用。

---

## 13. 验收标准

- [ ] 第一次打开停在自由敲琴页，6 个键都能立即发声，三种音色可切换。
- [ ] `high_low` 1/2/3 级的音程分别符合 ≥3 / 2 / 1 键；3 级会出现「一样高」。
- [ ] `echo` 按难度播放 3/4/5 个音，点错整段重播并要求从头按；首答错误被正确记录。
- [ ] `guess_song` 每轮不重复同一首歌，选项数随难度为 3/4/5。
- [ ] `echo` 播放序列时不高亮任何琴键、不按音高映射颜色；只有孩子自己按下时才亮。
- [ ] 一轮 5 题结束后停留在结算页、**不立即回传**；点「再来一轮」本地重开不会产生第二次提交或星星；点「回消息」/关闭时才回传一次，字段与 §7.1 一致。
- [ ] 玩过多轮时回传的是首答正确数最高的那一轮，且 `rounds_played` 正确。
- [ ] 中途关闭回传 `completed: false` + `cancelled: true`；音频初始化失败时无法开始练习，关闭同样回传 `cancelled`。
- [ ] `high_low` 三个选项、`guess_song` 的歌曲选项都带图标，5 岁孩子在老师一句口头说明后能选。
- [ ] 结算星星符合 §9；`star_events` 显示「音乐 / 音符小耳朵」而不是回落到别的标签。
- [ ] 工具只出现在 `kids_games` 的工具中心，小星老师与其他学科老师不可调用。
- [ ] 连续快速点键不爆音、不卡顿；离开卡片后音频资源释放，无残留播放。
- [ ] 纯函数测试全绿；`assembleHap` 通过；真机安装后完整玩一轮。
- [ ] 深色模式下游戏面板仍是暖色绘本皮肤，文字对比度 ≥ 4.5:1。

---

## 14. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| AudioRenderer 在某些设备初始化失败 | 没声音，游戏不可玩 | `ensureStarted()` 返回 false 时显示「声音没打开」提示；仍可视觉作答；不崩溃 |
| 低端机 PCM 混音卡顿 | 按键延迟 | 限制同时发声数（≤8 个 voice），单次缓冲只做乘法累加；预计算每音波形缓存 |
| 孩子分不清「一样高」 | 挫败 | 仅在难度 3 出现；答错时先重播两个音并高亮相同键 |
| 全屏 sheet 与聊天滚动/手势冲突 | 误触 | 键盘区域 `priorityGesture` 拦截；沿用 maze sheet 的打开/关闭模式 |
| 参考工程视觉资产版权 | 无 | 参考工程为用户自有设计稿；仅复用配色与水果角色意象，图标在项目内重绘为 SVG |

---

## 15. 留给实现者的决定

- 6 个水果图标的最终 SVG 形状与尺寸。
- 舞台背景的具体渐变与云/山比例。
- 音符飞起动画的时长与曲线（建议 400~600ms，EaseOut）。
- `playSequence` 的 noteMs / gapMs 微调（建议 550 / 120，`high_low` 用 650 / 300）。
- 结算页文案的具体措辞（保持 1~2 句、无 emoji、无 markdown 的老师口吻）。

---

**相关文档：** `.claude/skills/adding-mini-game-tool/SKILL.md`（10 步配方）、`.claude/rules/teaching-architecture.md`（工具生态与星星体系）、`docs/brand-spec.md`（儿童端视觉契约）
