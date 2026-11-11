# 儿童动画片播放工具（play_cartoon）设计

**日期**：2026-11-10
**版本**：v2（2026-11-11 真机反馈修订）
**范围**：小星游戏老师（`kids_games`）可调用的本地动画片播放工具 + 家长端「动画片管理」页 + 单次/每日观看时长硬闸
**相关文档**：`.claude/rules/teaching-architecture.md`（教学体系）、`.claude/skills/adding-mini-game-tool/SKILL.md`（新工具触点配方）

> **v2 变更（2026-11-11，真机验收后）**：
> 1. **真全屏**：宽屏下对话区是 `NavigationMode.Split`，push 路由只会渲染在右分栏。改为在 `Index` 根节点挂 `bindContentCover` 全屏模态（`ModalTransition.NONE`），覆盖分栏、底部 Tab 与待答浮条；`pages/CartoonPlayerPage.ets` 已删除，播放逻辑迁到 `components/cartoon/CartoonPlayerCover.ets`。
> 2. **季集索引**：`CartoonEntry` 新增 `seriesTitle` / `season` / `episode` / `lastWatchedAt`；导入时解析文件名 `SxxEyy` 或 `第N季第M集`，动画片名优先取父文件夹名；提示词按系列分组并给出「上一集 / 下一集 → id」，孩子没指定时播下一集，也可点名第几季第几集；只有完整看完才推进下一集。
> 3. **进度条**：播放器底部新增 Slider，可拖动/点击跳转；跳转本身不计观看时长（时间统计忽略 >1.5 秒的跳变）。
> 4. **原始比例**：AVPlayer 默认的 `VIDEO_SCALE_TYPE_FIT` 会拉伸画面，改为 `VIDEO_SCALE_TYPE_SCALED_ASPECT`（等比缩放 + 居中留边），并按 `player.width/height` 把 XComponent 调成视频原始宽高比，彻底避免横拉/竖拉。
>
> 下文 §10.4 / §10.5 / §15 的「全屏页面」「无进度条」等描述以本 v2 说明为准。

---

## 1. 意图与理由

小星游戏老师陪 5-7 岁孩子玩益智游戏。孩子玩了一阵后会说「我想看动画片」。目前老师没有可用的看片出口，只能口头拒绝。

要做的不是"视频播放器"，而是一个**有边界的看片出口**：

- 孩子主动提出，老师从家长预先配置好的本地片库里挑一集；
- 老师**不主动**提议看动画；
- 单次连续观看 ≤ 20 分钟、每天 ≤ 60 分钟，由 app 硬性限制；
- 到点只在上限处"集与集之间"拦截，**绝不从一集中间切断**；
- 不授星，不计入任何学科练习。

核心判断：**限时不能靠提示词自觉**。LLM 很容易被孩子软磨硬泡说服（"再看一集嘛"），所以额度判断必须在服务层做，提示词只负责让老师知道"现在还能看多久"以及对孩子怎么说。

---

## 2. 已确定的需求（来自需求方）

| # | 决策 | 说明 |
|---|------|------|
| D1 | 只给「小星游戏老师」（`kids_games`） | 不加入小星老师主助手，也不加入其他学科助手 |
| D2 | 老师不主动提，只响应孩子 | 孩子说「我想看动画」「我想看佩奇」才走这条路径 |
| D3 | 片源先做**本地文件** | NFS / 网络路径本期明确不做 |
| D4 | 家长通过「动画片管理」页配置片源 | 不复制文件，用鸿蒙持久授权关联原文件（`fileshare.persistPermission`） |
| D5 | 单次连续观看 ≤ 20 分钟 | 20 分钟是"能否开下一集"的闸门，不是剪刀 |
| D6 | 每天 ≤ 60 分钟 | 同上，只在集间拦截 |
| D7 | 不中途切断 | 已开始播放的一集一定让它自然播完 |
| D8 | "一次" = 一段连续观看 | 首次开播开始计时；闲置 30 分钟无播放则本次结束、下次重新计 |
| D9 | 一集一次工具调用 | 孩子看完一集说"再看一集"，老师再调一次工具；不做连播 |

> D5+D7 的直接结果：6 分钟一集时，第 18 分钟仍可开第 4 集，实际单次最长约 24 分钟。这是需求方明确认可的边界（"一集 6 分钟，可以看 4 集"）。

---

## 3. 目标 / 非目标 / 反目标

### 3.1 目标

- G1 孩子说想看动画时，老师能从片库挑一集并播放。
- G2 单次 20 分钟 / 每日 60 分钟在服务层强制执行，LLM 无法绕过。
- G3 家长可以在设置里导入、命名、打标签、删除本地视频，并看到文件是否失效。
- G4 老师能感知"剩余额度"，用孩子能听懂的话收尾（"今天这次看够啦，明天再看"）。
- G5 播完后对话自然继续，老师拿到实际观看时长。

### 3.2 非目标

- N1 NFS / SMB / HTTP 网络片源（后续可扩展，本期不做）。
- N2 在线流媒体、投屏、倍速、弹幕、选集/自动连播。
- N3 家长自定义时长（20/60 固定）。
- N4 观看历史页、观看报告。
- N5 视频转码、缩略图生成、字幕。
- N6 星星奖励 / 计入学科统计。
- N7 儿童主屏新增入口（孩子只能通过对话请求）。

### 3.3 反目标（即使"技术上能用"也算失败）

- A1 靠 system prompt 限时，服务层不拦。
- A2 播放中途因为到 20 分钟被暂停/关闭。
- A3 把视频复制进沙盒（需求方明确选择不复制，避免双份存储）。
- A4 引入新的 `StarActivityType`（看动画不授星）。
- A5 孩子能自己进片库管理页增删片源。

---

## 4. 用户流程

```
孩子在 kids_games 会话：「我想看动画片」
        │
        ▼
小星游戏老师读到 system prompt 末尾的「本地动画片库」段
  （片库列表 + 今日剩余 + 本次已看）
        │
        ├─ 片库为空 → 直接口头拒绝并让孩子找家长添加（不调用工具）
        ├─ 额度不足 → 直接口头拒绝（不调用工具）
        │
        ▼ 有片、有额度
调用 play_cartoon(video_id)
        │
        ▼
ToolExecutionService.handlePlayCartoon
  ├─ 参数校验失败 / 视频不可读 / 额度不足 / 视频过长
  │     → 立即返回错误 JSON，老师温和地跟孩子解释
  │
  └─ 允许播放
        → 生成 pending 卡片（MessageBubble 横幅）
        → ChatPage 展示横幅：「🐷 小猪佩奇 第1集 · 06:12 · ▶ 播放」
        │
        ▼ 孩子点击
全屏横屏播放页（AVPlayer + XComponent）
  · 播放中每秒累计观看时长（每 10 秒落盘）
  · 顶部显示「本次还剩 X 分钟 · 今天还剩 Y 分钟」
        │
        ├─ 自然播完 → 恢复竖屏、自动返回对话 → resolve 工具（completed=true）
        ├─ 孩子点 ✕ → 确认弹窗 → resolve（completed=false, ended_by='closed'）
        └─ 出现错误 → resolve（ended_by='error'）
        │
        ▼
老师收到结果：「看完啦，还想看吗？」/「这次看得差不多啦，明天再看。」
        │
        ▼
孩子说「再看一集」→ 再调一次 play_cartoon（额度不足则被拒）
```

---

## 5. 时间管理规则（核心）

### 5.1 常量

| 常量 | 值 | 位置 |
|------|-----|------|
| `CARTOON_SESSION_LIMIT_MS` | 20 × 60 × 1000 | `models/CartoonModels.ets` |
| `CARTOON_DAILY_LIMIT_MS` | 60 × 60 × 1000 | 同上 |
| `CARTOON_SESSION_IDLE_RESET_MS` | 30 × 60 × 1000 | 同上 |
| `CARTOON_PERSIST_INTERVAL_MS` | 10 × 1000 | 同上 |

全部为 `export const`，管理页与提示词渲染共用，避免多处写死。

### 5.2 状态

持久化到 Preferences（键定义在 `PreferencesService.PreferenceKeys`）：

| Key | 类型 | 含义 |
|-----|------|------|
| `cartoon_watch_day` | string | 本地日期键 `YYYY-MM-DD` |
| `cartoon_watch_day_ms` | number | 当日累计观看毫秒 |
| `cartoon_watch_session_ms` | number | 本次连续观看毫秒 |
| `cartoon_watch_last_activity_ms` | number | 最后一次"实际播放"的时间戳（0 = 无） |
| `cartoon_library_json` | string | 片库条目 JSON 数组 |

### 5.3 归一化（每次读/写前先执行）

```
refresh(now):
  today = localDateKey(now)                    // YYYY-MM-DD，本地时区
  if day !== today:
      day = today
      dayMs = 0
      sessionMs = 0
      lastActivityMs = 0
  if lastActivityMs > 0 && now - lastActivityMs > IDLE_RESET:
      sessionMs = 0
      lastActivityMs = 0
```

- 跨天：当天与本次同时清零。
- 闲置：只清"本次"，不清"今日"。
- 只要不在播放，就不更新 `lastActivityMs`（暂停 31 分钟再回来 → 算新的一次）。

### 5.4 开播判定（`decideStart`）

按顺序判断，命中即拒绝：

| 顺序 | 条件 | 错误码 | 说明 |
|------|------|--------|------|
| 1 | 条目不存在 / URI 打不开 | `video_unavailable` | 文件被移动、删除或授权失效 |
| 2 | `durationMs <= 0` | `video_unavailable` | 元数据缺失 |
| 3 | `durationMs > SESSION_LIMIT_MS` | `video_too_long` | 超过 20 分钟的片子既不切断又必然超时，只能拒绝 |
| 4 | `dayMs >= DAILY_LIMIT_MS` | `daily_limit_reached` | 今天已经看满 |
| 5 | `sessionMs >= SESSION_LIMIT_MS` | `session_limit_reached` | 这一次已经看满 |
| 6 | 其他 | — | 允许播放 |

**注意判定用 `>=` 而不是 `dayMs + duration > limit`**：后者会让"6 分钟 × 4 集"变成 3 集，与 D5/D7/D8 冲突。

### 5.5 计时

- 只统计 `AVPlayer` 处于 `playing` 状态的时间；暂停、缓冲、切后台都不计。
- 播放器每 1 秒回调一次 `playedDeltaMs`，`CartoonWatchService.addWatched(delta)` 累加 `dayMs` / `sessionMs`，并更新 `lastActivityMs = now`。
- 每 `CARTOON_PERSIST_INTERVAL_MS`（10 秒）落盘一次；暂停/关闭/播完时立即落盘。
- 进程被杀最多丢 10 秒，接受。

### 5.6 边界场景表

| 场景 | 结果 |
|------|------|
| 6 分钟一集，从 0 开始 | 0 / 6 / 12 / 18 分各开一集，24 分播完；第 5 集被 `session_limit_reached` 拒绝 |
| 单集 25 分钟 | `video_too_long`，不可播放 |
| 今天已看 58 分钟，再开 6 分钟一集 | 允许（58 < 60），播完 64 分钟；下一集被 `daily_limit_reached` 拒绝 |
| 本次看了 10 分钟，关闭对话 31 分钟后再看 | 本次从 0 重新计（今日仍累计） |
| 跨过零点 | 今日与本次都清零 |
| 孩子播到一半关掉 | 已看部分照常计入；`completed=false`，老师知道没看完 |
| 播放中途到 20 分钟 | **不暂停**，继续播完；播完后下一次调用被拒 |
| 播放中途到 60 分钟 | 同上 |
| 片库为空 | 提示词标注"片库为空"，老师不调用工具 |
| 文件失效 | 管理页标「失效」；工具返回 `video_unavailable` |

---

## 6. 数据模型

`models/CartoonModels.ets`：

```ts
/** 片库条目（持久化到 Preferences JSON） */
export interface CartoonEntry {
  id: string              // 'ct_<timestamp>_<rand>'
  uri: string             // 文件选择器返回的 URI（持久授权）
  title: string           // 必填，默认文件名去扩展名，家长可改
  tags: string            // 可选，逗号分隔，如「佩奇,小猪,家庭」
  durationMs: number      // 添加时从元数据读取
  addedAt: number
  status: string          // 'ok' | 'unavailable'
}

/** 额度快照（提示词渲染 / 管理页 / 判定共用） */
export interface CartoonQuotaSnapshot {
  dayKey: string
  dayMs: number
  sessionMs: number
  lastActivityMs: number
  dayLimitMs: number
  sessionLimitMs: number
}

/** 开播判定 */
export interface CartoonStartDecision {
  allowed: boolean
  errorCode: string       // '' | 'video_unavailable' | 'video_too_long' | 'daily_limit_reached' | 'session_limit_reached'
}

/** 播放结束回传给 LLM 的结果 */
export interface CartoonPlaybackResult {
  video_id: string
  title: string
  duration_seconds: number
  watched_seconds: number
  completed: boolean
  ended_by: string        // 'finished' | 'closed' | 'error'
  session_watched_seconds: number
  session_limit_seconds: number
  session_budget_left_seconds: number
  today_watched_seconds: number
  daily_limit_seconds: number
  daily_budget_left_seconds: number
}
```

片库条目与额度快照都通过纯函数在 `utils/CartoonQuotaMath.ets` 中处理，便于 hypium 单测。

---

## 7. 工具定义

### 7.1 工具 ID

`utils/SearchToolIdentityUtils.ets`：

```ts
export const PLAY_CARTOON_TOOL_ID: string = 'play_cartoon'
export function isPlayCartoonFunctionName(functionName: string): boolean
```

### 7.2 Schema（`config/BuiltinTools.ets`）

```json
{
  "type": "function",
  "function": {
    "name": "play_cartoon",
    "description": "播放本地动画片库中的一集给孩子看。仅当孩子明确说想看动画片或点名想看某部动画时调用；不要主动建议看动画。一次只播一集，播完后等孩子说「还想看」再调用下一集。video_id 必须精确取自 system prompt 末尾「本地动画片库」段。",
    "parameters": {
      "type": "object",
      "properties": {
        "video_id": {
          "type": "string",
          "description": "动画片 id，必须精确取自本地动画片库段（形如 ct_xxx）。不要自己编。"
        }
      },
      "required": ["video_id"]
    }
  }
}
```

> `rawSchemaJson` 模板字符串内**禁止 ASCII 双引号**（JSON-in-template-literal 陷阱），示例与强调一律用 `「」`。

### 7.3 执行路径

`services/ToolExecutionService.ets`：

```
executeToolCall
  └─ isPlayCartoonFunctionName(name) 分支（必须放在 resolveToolId 兜底之前）
       └─ handlePlayCartoon(toolCall, args)
            ├─ 参数校验（utils/CartoonToolValidation.ets）
            ├─ CartoonLibraryService.findById(video_id)
            ├─ CartoonWatchService.decideStart(entry)
            ├─ 拒绝 → 立即 resolve，返回错误 JSON
            └─ 允许 → pendingAnswers.set(...)，等 UI resolve
```

拒绝结果示例：

```json
{ "error": "daily_limit_reached", "today_watched_seconds": 3612, "daily_limit_seconds": 3600 }
```

- `video_id` 不存在或文件失效时，带上 `should_retry: true` 和 `available` 列表（最多 10 条 `ok` 条目），避免 LLM 反复重试同一个坏 id。
- **并发保护**：`CartoonWatchService` 记录当前 pending 的 `toolCallId`；已有播放待处理时，第二次 `play_cartoon` 立即返回 `{ "error": "already_playing" }`（不 retry）。工具调用虽然是顺序执行，但 LLM 可能在一轮里发两个调用，第一个播完后第二个会立刻自动开播，违反"一集一邀"。
- **不加入** `isInteractiveQuizFunctionName`（`ChatViewModel` 每轮 3 张互动卡的上限谓词）：看动画不是出题，既不该占题目配额，也不该套用"这一轮已经出够题了"的拒绝文案。并发由上面的 `already_playing` 兜底。

### 7.4 播放结束结果

```json
{
  "video_id": "ct_1720000000_ab12",
  "title": "小猪佩奇 第1集",
  "duration_seconds": 372,
  "watched_seconds": 372,
  "completed": true,
  "ended_by": "finished",
  "session_watched_seconds": 744,
  "session_limit_seconds": 1200,
  "session_budget_left_seconds": 456,
  "today_watched_seconds": 1116,
  "daily_limit_seconds": 3600,
  "daily_budget_left_seconds": 2484
}
```

- 工具在**播放器关闭/播完**时才 resolve；播放期间 pending。
- 关闭时 `completed=false`，`watched_seconds` 是已看部分。
- 不做 `recordStarEvent`，不写 `star_events`。

---

## 8. 提示词与片库注入

### 8.1 静态段（`models/AssistantModels.ets` 的 `KIDS_GAMES_SYSTEM_PROMPT`）

在「## 边界」之前新增一节：

```
## 看动画片
- 只有孩子主动说想看动画片/点名某部动画时，才从「本地动画片库」里挑一集，调用 play_cartoon。
- 绝对不要主动提议看动画，也不要在孩子没提的时候列举片库。
- 一次只播一集。播完等孩子说「还想看」，再放下一集。
- 单次连续看最多 20 分钟，每天最多 60 分钟；额度不够就温和拒绝，不要答应「再看一集」。
- 看动画不授星。本节的额度以 system prompt 末尾的实时数字为准。
```

### 8.2 动态段（`viewmodels/ChatViewModel.ets`）

仅当 `assistantId === 'kids_games'` 时，在 system prompt 末尾追加（`utils/CartoonPromptUtils.ets` 纯函数渲染）：

```
【本地动画片库】仅在孩子主动提出看动画时使用。
可用：
- ct_xxx｜小猪佩奇 第1集｜06:12｜标签：佩奇,小猪,家庭
- ct_yyy｜海底小纵队 第3集｜11:40｜标签：海洋,动物
时间：本次已看 12 分钟（单次上限 20 分钟，还剩 8 分钟）；今天已看 34 分钟（每天上限 60 分钟，还剩 26 分钟）。
一次只播一集。额度到上限时不要调用工具，直接告诉孩子今天先看到这里。
```

- 片库为空 → `【本地动画片库】当前没有动画片。孩子想看时，告诉他请爸爸妈妈在设置里的「动画片管理」添加。`
- **只列出 `status === 'ok'` 的条目**，失效条目不进提示词（模型不会挑到打不开的片子）；失效信息只出现在管理页。
- **注入上限 60 条**，按 `addedAt` 倒序取最近添加的 60 条；超出时在段尾追加 `（片库共 N 部，这里只列最近 60 部）`。孩子点名的片子不在列表里时，老师诚实说"老师这里没找到"。
- 拉取失败 → 静默跳过（不阻塞对话），与 `injectSubjectPlanSection` 同款容错。
- 注入位置：`buildRequestSystemPrompt` 中 `kids_games` 分支，在 `greetingHint` 之前。

> 额度数字是"请求构造时"的快照。孩子观看期间数字会变，但下一轮请求会重新渲染，不影响实际判定（服务层仍会二次校验）。

---

## 9. 片库管理页（`pages/CartoonLibraryPage.ets`）

### 9.1 入口

设置 → 学习中心 → 「动画片管理」，作为学习中心的**顶层条目**（与「学习画像」「明日计划」「英语图片库」「每日评估」「礼物管理」并列）。

> 注意：「英语单词库」实际上是从「学习画像」页里再进一层，并不在设置面板里。本页不做成那种二级入口，家长要好找。

- `config/SettingsRouteName.ets` 增加 `CARTOON_LIBRARY`
- `components/index/IndexSettingsPanel.ets` 增加列表项（icon 用白名单符号，如 `sys.symbol.play_circle` 需先验证；否则用 `sys.symbol.picture`）
- `pages/Index.ets` 增加 `onOpenCartoonLibrary` 事件 → `openSettingsDestination`
- `resources/base/profile/router_map.json` 注册页面 + Builder

设置页本身已在家长门之后，**不再单独加 `ParentalGateSheet`**（与 `LearningWordLibraryPage` 一致）。

### 9.2 页面结构

```
┌────────────────────────────────────┐
│ 动画片管理                          │
│ 只有小星游戏老师能播放。            │
│ 单次最多 20 分钟，每天最多 60 分钟。│
├────────────────────────────────────┤
│ 今天已看 34 分钟 / 60 分钟          │
├────────────────────────────────────┤
│ 🎬 小猪佩奇 第1集      06:12  [正常]│
│    标签：佩奇,小猪,家庭             │
│    添加于 11-10        [编辑] [删除]│
├────────────────────────────────────┤
│ 🎬 海底小纵队 第3集    11:40 [失效] │
│    文件已移动或删除  [重新关联][删除]│
├────────────────────────────────────┤
│            ＋ 添加动画片            │
└────────────────────────────────────┘
```

空状态：`还没有动画片。点击下方按钮，从手机里选择视频文件。`

### 9.3 添加流程

1. `picker.DocumentViewPicker().select({ maxSelectNumber: 20, fileSuffixFilters: ['视频|.mp4,.mkv,.mov,.webm,.avi,.ts'] })`
2. 对每个 URI：
   - `fileshare.persistPermission([{ uri, operationMode: fileshare.OperationMode.READ_MODE }])`
   - `fileIo.openSync(uri, READ_ONLY)` → fd
   - `media.createAVMetadataExtractor()` → `fdSrc = { fd, offset: 0, length: 0 }` → `fetchMetadata()`
   - 取完元数据后 `release()` 提取器并 `fileIo.close(fd)`——**同一个 fd 不能同时交给提取器与播放器**（SDK 明确要求），播放时重新 open
   - `duration` 字符串按毫秒解析；异常时回落到 `AVPlayer.prepare()` 读 `duration`
   - **超过 20 分钟的文件直接拒绝导入**（`durationMs > CARTOON_SESSION_LIMIT_MS`）：既不切断又必然超时，导进来也永远播不了，不如在导入时就说清楚
   - 生成条目：`title = 文件名去扩展名`，`tags = ''`，`status = 'ok'`
   - 重复 URI 跳过
3. 元数据读取失败 → 该文件不加入，页面提示「无法读取 xxx，可能格式不支持」。
4. 时长超过 20 分钟 → 不加入，页面提示「xxx 超过 20 分钟，暂时不能放」。
5. 全部完成后再统一写 `cartoon_library_json`。

### 9.4 编辑 / 删除 / 状态刷新

- 编辑：弹出 sheet 修改标题（必填，trim 后非空）与标签（逗号分隔）。
- 删除：确认后从 JSON 移除；可选调用 `fileshare.revokePermission`（失败忽略）。
- 状态刷新：`aboutToAppear` 时逐个 `fileIo.openSync(uri)` 试探，失败标 `unavailable`，成功恢复 `ok` 并回写。
- 「重新关联」：对该条目重新打开文件选择器，替换 URI 并重读时长。

### 9.5 启动期授权激活

`EntryAbility.initializeServices` 中 `CartoonLibraryService.initialize(context)`：

1. 读取片库 JSON。
2. 对每个 `status === 'ok'` 的条目调用 `fileshare.activatePermission([{ uri, operationMode: READ_MODE }])`。
3. 单个失败只记日志，不阻塞启动。

---

## 10. 播放器

### 10.1 组件拆分

| 组件 / 页面 | 职责 |
|------|------|
| `components/cartoon/CartoonCard.ets` | 气泡内横幅（标题、时长、▶ 播放、已看状态） |
| `pages/CartoonPlayerPage.ets` | 全屏横屏页面：顶部信息 + 关闭确认 + 编排计时与结算 |
| `components/cartoon/CartoonPlayerView.ets` | `XComponent` + `AVPlayer` 状态机 + 播放/暂停控件 + 每秒回调 |

### 10.2 为什么用 AVPlayer 而不是 ArkUI `Video`

- 片源是文件选择器返回的 URI，最可靠的播放方式是 `fileIo.openSync(uri)` 拿 fd → `player.url = 'fd://<fd>'`（项目已有 `MusicAudioPlayer` 先例）。
- `Video` 组件对 picker URI 的支持不可控，且自带进度条（孩子可拖拽跳过）。
- AVPlayer 能精确统计"实际播放时间"，并在 `endOfStream` 精确收尾。

### 10.3 状态机

```
idle → opening(fd) → initialized → prepared → playing ⇄ paused
                                              │
                                              └→ completed → released
任意状态 → error → released
```

- `stateChange('initialized')` → 设置 `surfaceId` → `prepare()`
- `stateChange('prepared')` → **以播放器报告的 `duration` 为准**：
  - 若实际时长 > 20 分钟（导入时元数据读短了）→ 不 `play()`，直接 resolve `{ error: 'video_too_long' }` 并回写条目时长；
  - 若与条目时长差 > 2 秒 → 回写条目时长（下次判定用新值）；
  - 否则 `play()`
- `timeUpdate` → 计算 `currentTime` 增量（忽略 > 1.5s 的跳变），每累计 1000ms 发一次 `playedDeltaMs`
- `endOfStream` → 停止计时 → `onFinished()`
- `error` → `onError(message)`
- `aboutToDisappear` → `release()` + `fileIo.close(fd)`

### 10.4 呈现方式：全屏页面 + 自动横屏

- 新增 `pages/CartoonPlayerPage.ets`（NavDestination，`router_map.json` 注册），从 ChatPage 用同一个 `NavPathStack` push，参数 `{ toolCallId, videoId }`。
- 进入时：先 `window.getLastWindow(context)` 读 `getPreferredOrientation()` 并保存 → `setPreferredOrientation(window.Orientation.LANDSCAPE)`。
- 退出/销毁时：恢复进入前的 orientation（通常是 `PORTRAIT` 或 `UNSPECIFIED`）。
- 页面隐藏标题栏、黑色背景、`Contain` 居中，尽量吃满安全区（状态栏/导航条沉浸式）。
- **不用 `bindSheet`**：底部 sheet 在横屏下的高度、拖拽手势与旋转配合不可控，且没有真正的全屏感。

### 10.5 退出路径与结算矩阵

| 路径 | 行为 | 工具结算 |
|------|------|----------|
| 自然播完 | 「看完啦」遮罩 1 秒 → 恢复竖屏 → pop 回对话 | `finished` / `completed=true` |
| 点 ✕（未播完） | 确认弹窗「还没看完，要关掉吗？」；取消则继续播 | 确认后 `closed` / `completed=false` |
| 系统返回键 / 侧滑返回 | `NavDestination.onBackPressed` 返回 `true`，走同一个确认流程 | 同上 |
| 页面被外部 pop / 导航栈销毁 | `aboutToDisappear` 兜底 | `closed`，只结算一次 |
| 应用切后台 | 暂停播放、暂停计时；回前台不自动续播，显示 ▶ | 不结算 |
| 播放器错误 | 页面显示「这集打不开了」+ 关闭 | `error` |
| 卡片横幅一直没点 | 不结算（与所有待答卡一致） | 无 |

- `settled` 布尔守卫保证只 resolve 一次。
- 切后台的暂停信号：`EntryAbility.onBackground` → `this.context.eventHub.emit('app_background')`；播放器 `eventHub.on('app_background', ...)` 收到后 `pause()`，计时同步停止。
- 结算直接调 `ServiceRegistry.toolExecution().resolvePendingAnswer(toolCallId, json)`（与 `ChatPage.handleAskUserAnswer` 同一条路径），随后 pop。

---

## 11. 卡片（气泡内）

`CartoonCard` 在待答态显示紧凑横幅（参考 Maze/Map 的 banner 模式，而不是内联播放器）：

```
┌─────────────────────────────────────┐
│ 🎬 小猪佩奇 第1集                    │
│    06:12 · 点一下就能看              │
│                        [ ▶ 播放 ]    │
└─────────────────────────────────────┘
```

已答态（时间线 step 内）：

```
🎬 小猪佩奇 第1集 · 已看完 06:12
🎬 小猪佩奇 第1集 · 看到 02:31 关掉了
```

- 点击横幅 → MessageBubble 触发 `onOpenCartoonPlayer(toolCall)` → ChatPage 用 `this.navPathStack.pushPath({ name: 'CartoonPlayerPage', param: { toolCallId, videoId } })` 打开全屏播放页。
- 卡片只负责横幅；播放页是独立 NavDestination，不引入 `largeSize` 双视图模式。
- 已答态 payload 从 `toolApprovalReason` 解析（`resolveStepAnswerPayload`），**不要** `JSON.parse(toolResult)`（见 MEMORY：toolresult-dual-consumer-pollution）。

### 11.1 MessageBubble 触点（7 处）

按 `.claude/skills/adding-mini-game-tool/SKILL.md` 的精确清单：

1. import 函数名判定
2. 待答态横幅渲染（ForEach 内）
3. `isToolStepClickable` or 链
4. `isDefaultExpanded` or 链
5. `isAutoExpandable` or 链
6. `handleToolStepClick` switch
7. step-content switch

> 不新增 `StarActivityType`，因此 **不需要** 动 `models/StarEventModels.ets` 与 `services/StarRewardService.ets`。这是有意省略。

---

## 12. 触点文件清单

| # | 文件 | 改动 |
|---|------|------|
| 1 | `utils/SearchToolIdentityUtils.ets` | `PLAY_CARTOON_TOOL_ID` + `isPlayCartoonFunctionName` |
| 2 | `models/CartoonModels.ets` | **新建**：条目/额度/判定/结果类型 + 常量 |
| 3 | `utils/CartoonQuotaMath.ets` | **新建**：`refreshQuota` / `decideCartoonStart` / `buildPlaybackResult` 纯函数 |
| 4 | `utils/CartoonPromptUtils.ets` | **新建**：渲染片库段 + 时长格式化 |
| 5 | `utils/CartoonToolValidation.ets` | **新建**：参数校验（video_id 非空字符串） |
| 6 | `services/CartoonLibraryService.ets` | **新建**：片库 CRUD + Preferences + 元数据 + 授权激活 + 状态刷新 |
| 7 | `services/CartoonWatchService.ets` | **新建**：额度读写 + 节流落盘 + 判定 |
| 8 | `config/BuiltinTools.ets` | import / args / executor / definition / config / register / `getBuiltinToolIds()` |
| 9 | `services/ToolExecutionService.ets` | import / `handlePlayCartoon` / dispatch（在 `resolveToolId` 兜底之前） |
| 10 | `models/AssistantModels.ets` | import / `KIDS_GAMES_LOCKED_TOOL_IDS` 加入 / 系统提示词新增「看动画片」段 |
| 11 | `viewmodels/ChatViewModel.ets` | `kids_games` 分支注入片库段 |
| 12 | `components/cartoon/CartoonCard.ets` | **新建**：横幅 + 已答态 |
| 13 | `components/cartoon/CartoonPlayerView.ets` | **新建**：AVPlayer 播放器 |
| 14 | `pages/CartoonPlayerPage.ets` | **新建**：全屏横屏播放页 + 退出确认 + 结算矩阵 |
| 15 | `components/MessageBubble.ets` | 7 处触点 + `@Event onOpenCartoonPlayer` |
| 16 | `pages/ChatPage.ets` | `onOpenCartoonPlayer` 回调 → `navPathStack.pushPath`（不挂 bindSheet） |
| 17 | `pages/CartoonLibraryPage.ets` | **新建**：片库管理页 |
| 18 | `config/SettingsRouteName.ets` | `CARTOON_LIBRARY` |
| 19 | `components/index/IndexSettingsPanel.ets` | 设置项 + `@Event` |
| 20 | `pages/Index.ets` | `onOpenCartoonLibrary` → `openSettingsDestination` |
| 21 | `resources/base/profile/router_map.json` | 注册 `CartoonLibraryPage` + `CartoonPlayerPage` 两个页面 |
| 22 | `entry/src/main/module.json5` | `ohos.permission.FILE_ACCESS_PERSIST` |
| 23 | `services/PreferencesService.ets` | 5 个 `PreferenceKeys` |
| 24 | `services/ServiceRegistry.ets` | 注册两个新服务（若沿用单例门面） |
| 25 | `entryability/EntryAbility.ets` | 初始化片库服务 + `onBackground` 事件 |
| 26 | `resources/base/element/string.json` | 页面标题/描述/按钮文案 |

---

## 13. 错误与降级

| 场景 | 行为 |
|------|------|
| 片库为空 | 提示词明确告知；老师口头让孩子找家长 |
| URI 失效 | 工具返回 `video_unavailable`；老师换一集或说"这集打不开了" |
| 格式不支持 | 添加时拒绝并提示 |
| 授权失效 | 启动时 `activatePermission` 失败 → 标记 `unavailable`；管理页可重新关联 |
| 播放器初始化失败 | 播放页显示「这集打不开了」+ 关闭；resolve `ended_by='error'` |
| Preferences 读写失败 | 内存里继续计时，记日志；不阻塞播放 |
| 提示词注入失败 | 静默降级，工具仍在；LLM 可能因为没有片库信息而拒绝，可接受 |
| 进程被杀 | pending 工具调用丢失（与既有卡片一致）；已观看时长最多丢 10 秒 |

---

## 14. 测试计划

### 14.1 纯函数单测（hypium，`entry/src/ohosTest/ets/test/utils/`）

`CartoonQuotaMath.test.ets`：

- 同日、无闲置：额度原样返回
- 跨天：`dayMs` / `sessionMs` 归零
- 闲置 30 分钟：`sessionMs` 归零、`dayMs` 保留
- 闲置 29 分钟：不清零
- `decideStart`：六种分支逐一覆盖
- "6 分钟 × 4 集"通过、"第 5 集"拒绝
- 25 分钟视频拒绝
- 日额度 58 分钟时仍允许开 6 分钟一集
- `buildPlaybackResult` 的剩余额度不为负

`CartoonPromptUtils.test.ets`：

- 空片库文案
- 非空片库渲染 id/标题/时长/标签
- 额度剩余为 0 时的文案
- 标题中的特殊字符不破坏格式

### 14.2 手工验收（真机）

- [ ] 设置里能添加 2 个视频，显示正确时长
- [ ] 文件被移动后管理页显示「失效」
- [ ] 孩子说「我想看动画」，老师只在该情况下调用工具
- [ ] 孩子没提时老师不主动提
- [ ] 卡片点击能全屏播放
- [ ] 播完自动关闭并接话
- [ ] 播放 6 分钟后关闭，管理页今日分钟数增加
- [ ] 连续放到 24 分钟后第 5 集被拒
- [ ] 播到一半切后台，计时停止
- [ ] 杀进程重进，已看过的时间仍在
- [ ] 不产生星星事件（今日星星明细无变化）

---

## 15. 已知限制与后续

| 限制 | 原因 | 后续 |
|------|------|------|
| 单个视频 > 20 分钟无法导入/播放 | 不能切断 + 不能超时 | 若需要，可做"分段观看"（记住进度） |
| 片库超过 60 条时，老师只看得见最近 60 条 | 控制提示词体积 | 后续可加 `list_cartoons` 检索工具 |
| 不复制文件 | 需求方选择省空间 | 文件被移动/删除会失效，管理页可重新关联 |
| 不支持网络片源 | 本期范围 | NFS/SMB/HTTP 可扩展 `CartoonEntry.uri` 的协议分支 |
| 无缩略图 | 需要 `AVImageGenerator` + 缓存 | 后续加 |
| 无进度记忆 | 一集一次，从头播 | 后续可在条目里存 `lastPositionMs` |
| 应用被杀导致 pending 丢失 | 既有工具调用机制的限制 | 与所有互动卡片同款 |
| 时长上限写死 | 需求方明确 20/60 | 后续可做成家长可配置 |
| 自动横屏依赖系统窗口旋转 | `setPreferredOrientation` 在部分折叠屏/Pad 分屏下可能不生效 | 横屏失败时退化为竖屏全屏（视频上下留黑边），不影响播放与计时 |

---

## 16. 评审记录（builder check，2026-11-10）

builder 提出的 8 个问题与结论：

| # | 问题 | 结论 |
|---|------|------|
| 1 | 播放呈现方式 | **需求方已定：全屏页面 + 自动横屏**（§10.4） |
| 2 | 退出路径 / pending 结算 | 已定：`settled` 单次守卫 + 退出矩阵（§10.5）；返回键拦截为确认流程 |
| 3 | 片库注入体积 | 已定：只列 `ok` 条目、最多 60 条、按添加时间倒序（§8.2） |
| 4 | 超长视频导入行为 | 已定：导入时直接拒绝并提示（§9.3），不引入第三种 status |
| 5 | 每轮互动工具上限 / 并发 | 已定：不加入 `isInteractiveQuizFunctionName`；服务层用 `already_playing` 拒绝第二次调用（§7.3） |
| 6 | 失效条目与备选 | 已定：失效条目不进提示词；`video_unavailable` / 未知 id 都返回 `available` 备选（§7.3、§8.2） |
| 7 | 时长的权威来源 | 已定：以播放器 `prepared` 的实际时长为准，超 20 分钟直接中止并回写条目（§10.3） |
| 8 | 管理页入口位置 | 已定：设置 → 学习中心顶层条目；「英语单词库」的二级入口先例不采用（§9.1） |

仍然保留的三个设计口径：

1. 「一次 20 分钟」在**暂停 31 分钟**后重置——按 D8 是，符合需求方原话"闲置 30 分钟重新算"。
2. 视频文件被删除后，已观看时长仍保留在当天累计中（不回溯扣除）——时间确实看过了。
3. 管理页不在儿童主屏给入口——家长端配置，孩子只能通过对话请求。
