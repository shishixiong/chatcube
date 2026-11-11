# 小星游戏老师动画片播放工具（play_cartoon）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `kids_games` 助手新增 `play_cartoon` 工具：家长在「动画片管理」页配置本地视频（持久授权、不复制），孩子主动要看时老师挑一集，全屏横屏播放，单次连续 20 分钟 / 每日 60 分钟硬闸，不中途切断。

**Architecture:** 纯逻辑（额度归一化、开播判定、结果构造、片库解析、提示词渲染）放 `utils/` 可单测；`CartoonLibraryService` 管 Preferences 片库 + 文件授权 + 元数据；`CartoonWatchService` 管计时与 pending 守卫；工具走现有 pending-answer 流程；播放器是独立 NavDestination 页面（AVPlayer + XComponent），不挂 sheet。

**Tech Stack:** ArkTS / ArkUI V2（`@ComponentV2`）、`@ohos.multimedia.media` AVPlayer + AVMetadataExtractor、`@ohos.fileshare` 持久授权、`@ohos.file.picker` 文件选择器、 Preferences、hypium。

**Spec:** `docs/superpowers/specs/2026-11-10-kids-cartoon-player-tool-design.md`

## Global Constraints

- HarmonyOS 6 / API 23；不新增第三方依赖。
- 工具名固定 `play_cartoon`；常量 `PLAY_CARTOON_TOOL_ID`；卡片 `CartoonCard`；播放页 `CartoonPlayerPage`；结果接口 `CartoonPlaybackResult`。
- 只加入 `KIDS_GAMES_LOCKED_TOOL_IDS`，不加入 default / 数学 / 英语 / 语文老师。
- 时间常量固定：单次 `20 * 60 * 1000`、每日 `60 * 60 * 1000`、闲置重置 `30 * 60 * 1000`、落盘 `10 * 1000`。
- **不新增 `StarActivityType`**，不动 `models/StarEventModels.ets` 与 `services/StarRewardService.ets`；看动画不授星。
- **不复制视频文件**；片源走 `fileshare.persistPermission` 持久授权，`module.json5` 增加 `ohos.permission.FILE_ACCESS_PERSIST`。
- ArkTS 严格模式：禁止解构（10605074）；内联对象字面量需显式类型标注（10605038）；ForEach 回调体内不得声明 `const`（10905209）。
- 工具 `rawSchemaJson` 模板字符串内描述文字一律用 `「」`，禁止 ASCII 双引号；改完必须跑 JSON.parse gauntlet。
- `sys.symbol` 只用白名单；本功能用 `sys.symbol.play_circle`（已在 SDK `sysResource.js` 中确认存在）。
- 测试在 DevEco Studio 中右键测试文件运行（`hvigorw test` 在本仓库不可用）；编译门禁为 `hvigorw assembleHap`。
- 提交信息用 `feat(kids): ...` / `test(kids): ...` / `docs(kids): ...` 前缀。

## Review Focus

1. **20 分钟边界不能切成"3 集"**：6 分钟一集时第 18 分钟必须仍允许开第 4 集，第 24 分钟后第 5 集才拒绝。由 Task 1 的 `decideCartoonStart` 单测覆盖。
2. **跨天 / 闲置重置方向错误**：跨天要同时清今日与本次，闲置 30 分钟只清本次。由 Task 1 的 `refreshQuota` 单测覆盖。
3. **pending Promise 泄漏**：孩子用返回键/侧滑/页面被 pop 离开播放页时，必须仍然 resolve 工具 promise，否则整段对话卡死。由 Task 8 的 `settled` 守卫 + 退出矩阵覆盖，手工验收。
4. **同一轮两个 `play_cartoon` 自动连播**：LLM 在一轮里发两个调用时，第一个播完第二个会立刻开始。由 Task 6 的 `too_soon` 冷却守卫 + `already_playing` 覆盖。
5. **片库 JSON 损坏 / 文件被移走**：解析失败必须降级为空库而不是崩溃；失效条目不能进提示词。由 Task 2 的解析单测 + Task 3 的状态刷新覆盖。

---

## File Structure

**新建**

| 文件 | 职责 |
|------|------|
| `entry/src/main/ets/models/CartoonModels.ets` | 条目/额度/判定/结果类型 + 全部常量 |
| `entry/src/main/ets/utils/CartoonQuotaMath.ets` | 日期键、额度归一化、开播判定、结果构造 |
| `entry/src/main/ets/utils/CartoonLibraryUtils.ets` | 片库 JSON 解析/序列化、标题提取、增删改、提示词选取、元数据时长解析 |
| `entry/src/main/ets/utils/CartoonPromptUtils.ets` | 片库段渲染 |
| `entry/src/main/ets/utils/CartoonVideoMetadata.ets` | 打开 URI 读 AVMetadata 时长 |
| `entry/src/main/ets/services/CartoonLibraryService.ets` | 片库 CRUD + Preferences + 授权激活 + 状态刷新 |
| `entry/src/main/ets/services/CartoonWatchService.ets` | 额度读写 + 节流落盘 + pending/冷却守卫 |
| `entry/src/main/ets/components/cartoon/CartoonCard.ets` | 气泡横幅 + 已答摘要 |
| `entry/src/main/ets/components/cartoon/CartoonPlayerView.ets` | XComponent + AVPlayer + 播放控件 |
| `entry/src/main/ets/pages/CartoonPlayerPage.ets` | 全屏横屏播放页 + 退出确认 + 结算 |
| `entry/src/main/ets/pages/CartoonLibraryPage.ets` | 家长端片库管理页 |
| `entry/src/ohosTest/ets/test/utils/CartoonQuotaMath.test.ets` | 额度/判定单测 |
| `entry/src/ohosTest/ets/test/utils/CartoonLibraryUtils.test.ets` | 片库解析/提示词单测 |
| `entry/src/ohosTest/ets/test/utils/CartoonPromptUtils.test.ets` | 提示词渲染单测 |

**修改**

`utils/SearchToolIdentityUtils.ets`、`config/BuiltinTools.ets`、`services/ToolExecutionService.ets`、`models/AssistantModels.ets`、`viewmodels/ChatViewModel.ets`、`components/MessageBubble.ets`、`pages/ChatPage.ets`、`config/SettingsRouteName.ets`、`components/index/IndexSettingsPanel.ets`、`pages/Index.ets`、`resources/base/profile/router_map.json`、`resources/base/element/string.json`、`entry/src/main/module.json5`、`services/PreferencesService.ets`、`services/ServiceRegistry.ets`、`entryability/EntryAbility.ets`、`entry/src/ohosTest/ets/test/List.test.ets`、`CLAUDE.md`、`.claude/rules/teaching-architecture.md`。

---

### Task 1: 数据模型与额度纯函数

**Files:**
- Create: `entry/src/main/ets/models/CartoonModels.ets`
- Create: `entry/src/main/ets/utils/CartoonQuotaMath.ets`
- Test: `entry/src/ohosTest/ets/test/utils/CartoonQuotaMath.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: 无
- Produces:
  - `CARTOON_SESSION_LIMIT_MS = 1200000`、`CARTOON_DAILY_LIMIT_MS = 3600000`、`CARTOON_SESSION_IDLE_RESET_MS = 1800000`、`CARTOON_PERSIST_INTERVAL_MS = 10000`、`CARTOON_PROMPT_MAX_ENTRIES = 60`、`CARTOON_MIN_GAP_MS = 3000`
  - `type CartoonEntryStatus = 'ok' | 'unavailable'`
  - `interface CartoonEntry { id: string; uri: string; title: string; tags: string; durationMs: number; addedAt: number; status: CartoonEntryStatus }`
  - `interface CartoonQuotaState { dayKey: string; dayMs: number; sessionMs: number; lastActivityMs: number }`
  - `interface CartoonQuotaSnapshot { dayKey: string; dayMs: number; sessionMs: number; lastActivityMs: number; dayLimitMs: number; sessionLimitMs: number }`
  - `interface CartoonStartDecision { allowed: boolean; errorCode: string }`
  - `interface CartoonPlaybackResult { video_id: string; title: string; duration_seconds: number; watched_seconds: number; completed: boolean; ended_by: string; session_watched_seconds: number; session_limit_seconds: number; session_budget_left_seconds: number; today_watched_seconds: number; daily_limit_seconds: number; daily_budget_left_seconds: number }`
  - `interface CartoonPlayerRouteParams { toolCallId: string; videoId: string; title: string; durationMs: number; uri: string }`
  - `formatDayKey(nowMs: number): string`
  - `refreshQuota(state: CartoonQuotaState, nowMs: number): CartoonQuotaState`
  - `buildQuotaSnapshot(state: CartoonQuotaState, nowMs: number): CartoonQuotaSnapshot`
  - `decideCartoonStart(durationMs: number, snapshot: CartoonQuotaSnapshot): CartoonStartDecision`
  - `buildPlaybackResult(entry: CartoonEntry, watchedMs: number, completed: boolean, endedBy: string, snapshot: CartoonQuotaSnapshot): CartoonPlaybackResult`
  - `formatDurationSeconds(totalSeconds: number): string`（`372 → '06:12'`）

- [ ] **Step 1: 写失败测试**

`entry/src/ohosTest/ets/test/utils/CartoonQuotaMath.test.ets`：

```ts
import { describe, it, expect } from '@ohos/hypium'
import {
  CARTOON_SESSION_LIMIT_MS, CARTOON_DAILY_LIMIT_MS, CARTOON_SESSION_IDLE_RESET_MS,
  CartoonEntry, CartoonQuotaState
} from '../../../../main/ets/models/CartoonModels'
import {
  formatDayKey, refreshQuota, buildQuotaSnapshot, decideCartoonStart,
  buildPlaybackResult, formatDurationSeconds
} from '../../../../main/ets/utils/CartoonQuotaMath'

const NOW = new Date(2026, 10, 10, 10, 0, 0).getTime()
const SIX_MIN = 6 * 60 * 1000

function state(dayMs: number, sessionMs: number, dayKey: string, lastActivityMs: number): CartoonQuotaState {
  const s: CartoonQuotaState = {
    dayKey: dayKey, dayMs: dayMs, sessionMs: sessionMs, lastActivityMs: lastActivityMs
  }
  return s
}

function entry(durationMs: number): CartoonEntry {
  const e: CartoonEntry = {
    id: 'ct_1', uri: 'file://docs/a.mp4', title: 'A', tags: '',
    durationMs: durationMs, addedAt: 0, status: 'ok'
  }
  return e
}

export default function cartoonQuotaMathTest() {
  describe('CartoonQuotaMath', () => {
    it('format_day_key_uses_local_date', 0, () => {
      expect(formatDayKey(NOW)).assertEqual('2026-11-10')
    })

    it('day_rollover_clears_day_and_session', 0, () => {
      const next = refreshQuota(state(600000, 300000, '2026-11-09', NOW - 60000), NOW)
      expect(next.dayKey).assertEqual('2026-11-10')
      expect(next.dayMs).assertEqual(0)
      expect(next.sessionMs).assertEqual(0)
      expect(next.lastActivityMs).assertEqual(0)
    })

    it('idle_30min_clears_session_only', 0, () => {
      const next = refreshQuota(state(600000, 300000, '2026-11-10', NOW - CARTOON_SESSION_IDLE_RESET_MS - 1), NOW)
      expect(next.dayMs).assertEqual(600000)
      expect(next.sessionMs).assertEqual(0)
    })

    it('idle_29min_keeps_session', 0, () => {
      const next = refreshQuota(state(600000, 300000, '2026-11-10', NOW - 29 * 60 * 1000), NOW)
      expect(next.sessionMs).assertEqual(300000)
    })

    it('four_six_minute_episodes_allowed_fifth_rejected', 0, () => {
      let s = state(0, 0, '2026-11-10', 0)
      for (let i = 0; i < 4; i++) {
        const snap = buildQuotaSnapshot(s, NOW + i * SIX_MIN)
        expect(decideCartoonStart(SIX_MIN, snap).allowed).assertTrue()
        s = state(snap.dayMs + SIX_MIN, snap.sessionMs + SIX_MIN, snap.dayKey, NOW + i * SIX_MIN)
      }
      const after = buildQuotaSnapshot(s, NOW + 4 * SIX_MIN)
      const decision = decideCartoonStart(SIX_MIN, after)
      expect(decision.allowed).assertFalse()
      expect(decision.errorCode).assertEqual('session_limit_reached')
    })

    it('daily_58min_still_allows_one_more_episode', 0, () => {
      const snap = buildQuotaSnapshot(state(58 * 60 * 1000, 0, '2026-11-10', 0), NOW)
      expect(decideCartoonStart(SIX_MIN, snap).allowed).assertTrue()
    })

    it('over_20min_video_is_too_long', 0, () => {
      const snap = buildQuotaSnapshot(state(0, 0, '2026-11-10', 0), NOW)
      expect(decideCartoonStart(CARTOON_SESSION_LIMIT_MS + 1, snap).errorCode).assertEqual('video_too_long')
      expect(decideCartoonStart(0, snap).errorCode).assertEqual('video_unavailable')
    })

    it('daily_limit_reached_blocks', 0, () => {
      const snap = buildQuotaSnapshot(state(CARTOON_DAILY_LIMIT_MS, 0, '2026-11-10', NOW), NOW)
      expect(decideCartoonStart(SIX_MIN, snap).errorCode).assertEqual('daily_limit_reached')
    })

    it('playback_result_clamps_and_converts', 0, () => {
      const snap = buildQuotaSnapshot(state(CARTOON_DAILY_LIMIT_MS + 5000, CARTOON_SESSION_LIMIT_MS + 5000,
        '2026-11-10', NOW), NOW)
      const result = buildPlaybackResult(entry(SIX_MIN), 372500, true, 'finished', snap)
      expect(result.duration_seconds).assertEqual(360)
      expect(result.watched_seconds).assertEqual(373)
      expect(result.session_budget_left_seconds).assertEqual(0)
      expect(result.daily_budget_left_seconds).assertEqual(0)
      expect(result.completed).assertTrue()
    })

    it('format_duration_pads', 0, () => {
      expect(formatDurationSeconds(372)).assertEqual('06:12')
      expect(formatDurationSeconds(59)).assertEqual('00:59')
    })
  })
}
```

- [ ] **Step 2: 在 DevEco Studio 运行，确认失败**

右键 `CartoonQuotaMath.test.ets` → Run。预期：模块找不到 / 函数未定义。若无法运行 IDE，先继续实现，最终在 Task 11 的真机验收前补跑。

- [ ] **Step 3: 实现 `CartoonModels.ets` 与 `CartoonQuotaMath.ets`**

`refreshQuota` 按 spec §5.3 的两条规则实现（跨天清两项；`lastActivityMs > 0 && now - lastActivityMs > IDLE_RESET` 只清 session）。`decideCartoonStart` 按 spec §5.4 的 6 行顺序，判定用 `>=`。`buildPlaybackResult` 的 `session_budget_left_seconds` / `daily_budget_left_seconds` 用 `Math.max(0, ...)`；`watched_seconds` 用 `Math.round(watchedMs / 1000)`；`duration_seconds` 用 `Math.round(durationMs / 1000)`。`formatDayKey` 用 `Date` 的本地 getFullYear/getMonth/getDate 并补零。

- [ ] **Step 4: 运行测试确认通过**

同一测试文件 → Run。预期 10 个用例全部 PASS。

- [ ] **Step 5: 注册测试并提交**

`entry/src/ohosTest/ets/test/List.test.ets` 加 `import cartoonQuotaMathTest from './utils/CartoonQuotaMath.test'` 与 `cartoonQuotaMathTest()` 调用。

```bash
git add entry/src/main/ets/models/CartoonModels.ets entry/src/main/ets/utils/CartoonQuotaMath.ets entry/src/ohosTest/ets/test/utils/CartoonQuotaMath.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(kids): add cartoon quota model and pure math"
```

---

### Task 2: 片库解析与提示词渲染纯函数

**Files:**
- Create: `entry/src/main/ets/utils/CartoonLibraryUtils.ets`
- Create: `entry/src/main/ets/utils/CartoonPromptUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/CartoonLibraryUtils.test.ets`
- Test: `entry/src/ohosTest/ets/test/utils/CartoonPromptUtils.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: `CartoonEntry`、`CartoonQuotaSnapshot`、`CARTOON_PROMPT_MAX_ENTRIES`、`formatDurationSeconds`
- Produces:
  - `parseCartoonLibrary(json: string): CartoonEntry[]`
  - `serializeCartoonLibrary(entries: CartoonEntry[]): string`
  - `titleFromUri(uri: string): string`
  - `appendCartoonEntry(entries: CartoonEntry[], entry: CartoonEntry): CartoonEntry[]`
  - `removeCartoonEntry(entries: CartoonEntry[], id: string): CartoonEntry[]`
  - `updateCartoonEntry(entries: CartoonEntry[], id: string, title: string, tags: string): CartoonEntry[]`
  - `pickPromptEntries(entries: CartoonEntry[], maxCount: number): CartoonEntry[]`
  - `parseMetadataDurationMs(raw: string): number`
  - `buildCartoonEntryId(nowMs: number, suffix: string): string`
  - `renderCartoonCatalogSection(entries: CartoonEntry[], snapshot: CartoonQuotaSnapshot): string`

- [ ] **Step 1: 写失败测试**

`CartoonLibraryUtils.test.ets`：

```ts
import { describe, it, expect } from '@ohos/hypium'
import {
  parseCartoonLibrary, serializeCartoonLibrary, titleFromUri, appendCartoonEntry,
  removeCartoonEntry, updateCartoonEntry, pickPromptEntries, parseMetadataDurationMs,
  buildCartoonEntryId
} from '../../../../main/ets/utils/CartoonLibraryUtils'
import { CartoonEntry } from '../../../../main/ets/models/CartoonModels'

function entry(id: string, addedAt: number, status: string, uri: string): CartoonEntry {
  const e: CartoonEntry = {
    id: id, uri: uri, title: id, tags: '', durationMs: 360000, addedAt: addedAt,
    status: status as CartoonEntry['status']
  }
  return e
}

export default function cartoonLibraryUtilsTest() {
  describe('CartoonLibraryUtils', () => {
    it('malformed_json_returns_empty', 0, () => {
      expect(parseCartoonLibrary('{oops').length).assertEqual(0)
      expect(parseCartoonLibrary('').length).assertEqual(0)
    })

    it('serialize_roundtrip', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', 1, 'ok', 'file://docs/a.mp4')]
      expect(parseCartoonLibrary(serializeCartoonLibrary(list)).length).assertEqual(1)
    })

    it('title_from_uri_strips_extension_and_decodes', 0, () => {
      expect(titleFromUri('file://docs/storage/Users/currentUser/Download/Peppa%20Pig.mp4'))
        .assertEqual('Peppa Pig')
      expect(titleFromUri('file://docs/a/b/c.mkv')).assertEqual('c')
    })

    it('append_dedupes_by_uri', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', 1, 'ok', 'file://docs/a.mp4')]
      const next = appendCartoonEntry(list, entry('ct_b', 2, 'ok', 'file://docs/a.mp4'))
      expect(next.length).assertEqual(1)
    })

    it('remove_and_update', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', 1, 'ok', 'file://docs/a.mp4')]
      expect(removeCartoonEntry(list, 'ct_a').length).assertEqual(0)
      const updated = updateCartoonEntry(list, 'ct_a', '  佩奇  ', '小猪,家庭')
      expect(updated[0].title).assertEqual('佩奇')
      expect(updated[0].tags).assertEqual('小猪,家庭')
    })

    it('pick_prompt_entries_filters_and_caps', 0, () => {
      const list: CartoonEntry[] = []
      for (let i = 0; i < 70; i++) {
        list.push(entry('ct_' + i, i, i === 0 ? 'unavailable' : 'ok', 'file://docs/' + i + '.mp4'))
      }
      const picked = pickPromptEntries(list, 60)
      expect(picked.length).assertEqual(60)
      expect(picked[0].id).assertEqual('ct_69')
      for (let i = 0; i < picked.length; i++) {
        expect(picked[i].status).assertEqual('ok')
      }
    })

    it('metadata_duration_parses_ms_and_rejects_junk', 0, () => {
      expect(parseMetadataDurationMs('372000')).assertEqual(372000)
      expect(parseMetadataDurationMs('')).assertEqual(0)
      expect(parseMetadataDurationMs('abc')).assertEqual(0)
      expect(parseMetadataDurationMs('-1')).assertEqual(0)
    })

    it('entry_id_is_stable_shape', 0, () => {
      expect(buildCartoonEntryId(1720000000000, 'ab12')).assertEqual('ct_1720000000000_ab12')
    })
  })
}
```

`CartoonPromptUtils.test.ets`：

```ts
import { describe, it, expect } from '@ohos/hypium'
import { renderCartoonCatalogSection } from '../../../../main/ets/utils/CartoonPromptUtils'
import { CartoonEntry, CartoonQuotaSnapshot } from '../../../../main/ets/models/CartoonModels'

function snap(dayMs: number, sessionMs: number): CartoonQuotaSnapshot {
  const s: CartoonQuotaSnapshot = {
    dayKey: '2026-11-10', dayMs: dayMs, sessionMs: sessionMs, lastActivityMs: 0,
    dayLimitMs: 3600000, sessionLimitMs: 1200000
  }
  return s
}

function entry(id: string, title: string, durationMs: number, tags: string, status: string): CartoonEntry {
  const e: CartoonEntry = {
    id: id, uri: 'file://docs/' + id + '.mp4', title: title, tags: tags,
    durationMs: durationMs, addedAt: 1, status: status as CartoonEntry['status']
  }
  return e
}

export default function cartoonPromptUtilsTest() {
  describe('CartoonPromptUtils', () => {
    it('empty_library_says_add_in_settings', 0, () => {
      const text = renderCartoonCatalogSection([], snap(0, 0))
      expect(text.indexOf('没有动画片') >= 0).assertTrue()
      expect(text.indexOf('动画片管理') >= 0).assertTrue()
    })

    it('renders_id_title_duration_and_quota', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', '小猪佩奇 第1集', 372000, '佩奇,小猪', 'ok')]
      const text = renderCartoonCatalogSection(list, snap(34 * 60 * 1000, 12 * 60 * 1000))
      expect(text.indexOf('ct_a') >= 0).assertTrue()
      expect(text.indexOf('小猪佩奇 第1集') >= 0).assertTrue()
      expect(text.indexOf('06:12') >= 0).assertTrue()
      expect(text.indexOf('标签：佩奇,小猪') >= 0).assertTrue()
      expect(text.indexOf('本次已看 12 分钟') >= 0).assertTrue()
      expect(text.indexOf('今天已看 34 分钟') >= 0).assertTrue()
    })

    it('hides_unavailable_entries', 0, () => {
      const list: CartoonEntry[] = [entry('ct_bad', '坏文件', 60000, '', 'unavailable')]
      const text = renderCartoonCatalogSection(list, snap(0, 0))
      expect(text.indexOf('ct_bad') === -1).assertTrue()
      expect(text.indexOf('没有动画片') >= 0).assertTrue()
    })

    it('notes_truncation_when_over_cap', 0, () => {
      const list: CartoonEntry[] = []
      for (let i = 0; i < 65; i++) {
        list.push(entry('ct_' + i, '片' + i, 60000, '', 'ok'))
      }
      const text = renderCartoonCatalogSection(list, snap(0, 0))
      expect(text.indexOf('片库共 65 部') >= 0).assertTrue()
    })
  })
}
```

- [ ] **Step 2: 在 DevEco Studio 运行，确认失败**

右键两个测试文件 → Run。预期模块/函数未定义。

- [ ] **Step 3: 实现两个 util**

- `parseCartoonLibrary` 用 try/catch 包 `JSON.parse(json) as CartoonEntry[]`，非数组或异常返回 `[]`；对每条补 default（`status` 非 `'ok'|'unavailable'` 视为 `'unavailable'`，`durationMs` 非正则 0）。
- `titleFromUri`：取最后一个 `/` 之后、最后一个 `.` 之前；`decodeURIComponent` 包 try/catch，失败用原串；结果 trim，空则 `'未命名动画'`。
- `updateCartoonEntry`：`title.trim()` 为空时保留原标题。
- `pickPromptEntries`：过滤 `status === 'ok'`，按 `addedAt` 倒序，`slice(0, maxCount)`。
- `parseMetadataDurationMs`：`Number(raw)`，非有限或 `<= 0` 返回 0。
- `renderCartoonCatalogSection`：过滤 + 取 60 条；空时返回 spec §8.2 的空库文案；否则按 spec 的格式逐行输出 `- id｜title｜mm:ss｜标签：...`，再输出本次/今日分钟数与上限，最后追加「一次只播一集。额度到上限时不要调用工具」；超过 60 条时追加「（片库共 N 部，这里只列最近 60 部）」。

- [ ] **Step 4: 运行测试确认通过**

两个测试文件 → Run，全部 PASS。

- [ ] **Step 5: 注册测试并提交**

`List.test.ets` 加两个 import + 调用。

```bash
git add entry/src/main/ets/utils/CartoonLibraryUtils.ets entry/src/main/ets/utils/CartoonPromptUtils.ets entry/src/ohosTest/ets/test/utils/CartoonLibraryUtils.test.ets entry/src/ohosTest/ets/test/utils/CartoonPromptUtils.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "test(kids): add cartoon library and prompt pure logic"
```

---

### Task 3: CartoonLibraryService + 持久授权 + 启动初始化

**Files:**
- Create: `entry/src/main/ets/services/CartoonLibraryService.ets`
- Create: `entry/src/main/ets/utils/CartoonVideoMetadata.ets`
- Modify: `entry/src/main/ets/services/PreferencesService.ets`（`PreferenceKeys.CARTOON_LIBRARY_JSON`）
- Modify: `entry/src/main/ets/services/ServiceRegistry.ets`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `entry/src/main/module.json5`

**Interfaces:**
- Consumes: Task 1 类型与常量；Task 2 的 `parseCartoonLibrary` / `serializeCartoonLibrary` / `appendCartoonEntry` / `titleFromUri` / `parseMetadataDurationMs` / `buildCartoonEntryId`
- Produces:
  - `interface CartoonAddOutcome { addedCount: number; rejectedMessages: string[] }`
  - `readVideoDurationMs(uri: string): Promise<number>`（`utils/CartoonVideoMetadata.ets`）
  - `class CartoonLibraryService { initialize(): Promise<void>; list(): CartoonEntry[]; findById(id: string): CartoonEntry | null; isUriReadable(uri: string): Promise<boolean>; addFromUris(uris: string[]): Promise<CartoonAddOutcome>; updateEntry(id: string, title: string, tags: string): Promise<boolean>; removeEntry(id: string): Promise<boolean>; refreshStatuses(): Promise<void>; relinkEntry(id: string, uri: string): Promise<string>; updateDuration(id: string, durationMs: number): Promise<void> }`
  - `getCartoonLibraryService(): CartoonLibraryService`
  - `ServiceRegistry.cartoonLibrary(): CartoonLibraryService`

- [ ] **Step 1: 实现 `CartoonVideoMetadata.ets`**

签名 `readVideoDurationMs(uri: string): Promise<number>`。流程：`fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)` → `media.createAVMetadataExtractor()` → `extractor.fdSrc = { fd: file.fd, offset: 0, length: 0 }` → `await extractor.fetchMetadata()` → `parseMetadataDurationMs(metadata.duration ?? '')`；`finally` 里 `await extractor.release()` 与 `fileIo.closeSync(file)`。任何异常返回 0。

- [ ] **Step 2: 实现 `CartoonLibraryService.ets`**

单例 + `getCartoonLibraryService()`。`initialize()` 幂等：从 Preferences 读 `PreferenceKeys.CARTOON_LIBRARY_JSON`，`parseCartoonLibrary`；对 `status === 'ok'` 的条目逐条 `fileshare.activatePermission([{ uri, operationMode: fileshare.OperationMode.READ_MODE }])`，单条失败只 `console.warn`。`addFromUris` 对每个 URI：`fileshare.persistPermission(...)`（失败记入 rejected）→ `readVideoDurationMs` → 0 记「无法读取 xxx」→ `> CARTOON_SESSION_LIMIT_MS` 记「xxx 超过 20 分钟」→ 构造 `CartoonEntry`（`id = buildCartoonEntryId(Date.now(), Math.random().toString(36).slice(2, 6))`，`title = titleFromUri(uri)`，`status = 'ok'`）→ `appendCartoonEntry`。最后统一写回 Preferences。`refreshStatuses` 逐条 `isUriReadable` 并回写 status；`relinkEntry` 重新 persistPermission + 读时长 + 替换 uri/duration/status，返回 `''` 或错误文案。

- [ ] **Step 3: 权限与启动接线**

- `module.json5` 的 `requestPermissions` 增加 `{"name": "ohos.permission.FILE_ACCESS_PERSIST"}`（`system_grant`，无 reason/usedScene 要求，按现有格式即可）。
- `PreferencesService.PreferenceKeys` 增加 `CARTOON_LIBRARY_JSON = 'cartoon_library_json'`。
- `ServiceRegistry` 增加 `static cartoonLibrary(): CartoonLibraryService`（模块级单例）。
- `EntryAbility.initializeServices` 在 `preferences().initialize` 之后调用 `await ServiceRegistry.cartoonLibrary().initialize()`。

- [ ] **Step 4: 编译验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

预期 BUILD SUCCESSFUL。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/services/CartoonLibraryService.ets entry/src/main/ets/utils/CartoonVideoMetadata.ets entry/src/main/ets/services/PreferencesService.ets entry/src/main/ets/services/ServiceRegistry.ets entry/src/main/ets/entryability/EntryAbility.ets entry/src/main/module.json5
git commit -m "feat(kids): add cartoon library service with persistent file grants"
```

---

### Task 4: CartoonWatchService（额度 + pending/冷却守卫）

**Files:**
- Create: `entry/src/main/ets/services/CartoonWatchService.ets`
- Modify: `entry/src/main/ets/services/PreferencesService.ets`（4 个额度键）
- Modify: `entry/src/main/ets/services/ServiceRegistry.ets`

**Interfaces:**
- Consumes: Task 1 的 `CartoonQuotaState` / `CartoonQuotaSnapshot` / `CartoonStartDecision` / `refreshQuota` / `buildQuotaSnapshot` / `decideCartoonStart`；`CARTOON_PERSIST_INTERVAL_MS` / `CARTOON_MIN_GAP_MS`
- Produces:
  - `class CartoonWatchService { initialize(): Promise<void>; snapshot(nowMs?: number): Promise<CartoonQuotaSnapshot>; decideStart(durationMs: number): Promise<CartoonStartDecision>; addWatched(deltaMs: number): Promise<void>; flush(): Promise<void>; beginPending(toolCallId: string): boolean; endPending(toolCallId: string): void; hasPendingPlayback(): boolean; canStartNewEpisode(nowMs?: number): boolean; markPlaybackEnded(nowMs?: number): void }`
  - `getCartoonWatchService(): CartoonWatchService`
  - `ServiceRegistry.cartoonWatch(): CartoonWatchService`
  - `PreferenceKeys.CARTOON_WATCH_DAY` / `CARTOON_WATCH_DAY_MS` / `CARTOON_WATCH_SESSION_MS` / `CARTOON_WATCH_LAST_ACTIVITY_MS`

- [ ] **Step 1: 实现服务**

`initialize()` 幂等读 4 个键到内存 `CartoonQuotaState`。`snapshot()` 先 `refreshQuota`，若 `dayKey` 或 `sessionMs` 被重置则回写；返回 `buildQuotaSnapshot`。`addWatched(deltaMs)`：`refreshQuota` → 累加 `dayMs` / `sessionMs` → `lastActivityMs = Date.now()` → 若距上次落盘 `>= CARTOON_PERSIST_INTERVAL_MS` 则写 4 个键。`flush()` 立即写。`beginPending(id)`：已有 pending 返回 false，否则记录并返回 true；`endPending(id)` 只在 id 匹配时清空。`canStartNewEpisode(now)`：`now - lastPlaybackEndedAtMs >= CARTOON_MIN_GAP_MS`；`markPlaybackEnded(now)` 更新该时间戳（仅内存）。

- [ ] **Step 2: 注册服务**

`ServiceRegistry.cartoonWatch()` 加单例 getter。

- [ ] **Step 3: 编译验证**

同 Task 3 Step 4。预期 BUILD SUCCESSFUL。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/services/CartoonWatchService.ets entry/src/main/ets/services/PreferencesService.ets entry/src/main/ets/services/ServiceRegistry.ets
git commit -m "feat(kids): add cartoon watch quota service"
```

---

### Task 5: 工具身份 + 注册 + Schema

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

**Interfaces:**
- Consumes: 无
- Produces: `PLAY_CARTOON_TOOL_ID = 'play_cartoon'`、`isPlayCartoonFunctionName(functionName: string): boolean`、`createPlayCartoonToolDefinition()`、`createPlayCartoonToolConfig()`、`new PlayCartoonExecutor()`

- [ ] **Step 1: 加工具 ID**

`SearchToolIdentityUtils.ets` 末尾常量区加 `export const PLAY_CARTOON_TOOL_ID: string = 'play_cartoon'`；函数区加：

```ts
export function isPlayCartoonFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === PLAY_CARTOON_TOOL_ID
}
```

**不要**把 `isPlayCartoonFunctionName` 加进 `isInteractiveQuizFunctionName`（spec §7.3：不占每轮 3 张题卡配额）。

- [ ] **Step 2: 加 schema / executor / config / 注册**

`BuiltinTools.ets`：
- import `PLAY_CARTOON_TOOL_ID`。
- `interface PlayCartoonArgs { video_id: string }`
- `PlayCartoonExecutor.execute(_args)` 解析 `video_id`，返回 `{ video_id, answered: false, hint: '请在卡片里点播放' }`（真正的交互由 `handlePlayCartoon` 拦截）。
- `createPlayCartoonToolDefinition()`：`rawSchemaJson` 按 spec §7.2 原文，只含 `video_id`（required）。
- `createPlayCartoonToolConfig()`：displayName `'看动画片'`，描述「播放本地动画片库中的一集，仅孩子主动提出时使用」，其余字段镜像 `createMazeToolConfig`（interactive `true`，`ToolSourceType.BUILTIN`，sourceId 用 `PLAY_CARTOON_TOOL_ID`，`ToolPermissionLevel.READ`）。
- `registerBuiltinTools()` 中按 maze 的 `isToolRegistered` 模式注册。
- `getBuiltinToolIds()` 追加 `PLAY_CARTOON_TOOL_ID`。

- [ ] **Step 3: JSON.parse gauntlet**

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const m=s.match(/const rawSchemaJson: string = \`([\s\S]*?)\`/);JSON.parse(m[1])"
```

注意：该正则只匹配第一个 schema；本任务新增一个 schema，需人工确认新 schema 内没有 ASCII 双引号混进描述（spec §7.2 已用 `「」`）。

- [ ] **Step 4: 编译验证**

同 Task 3 Step 4。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(kids): register play_cartoon tool schema"
```

---

### Task 6: ToolExecutionService 分发 + pending 流程

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

**Interfaces:**
- Consumes: `isPlayCartoonFunctionName`；`getCartoonLibraryService()`；`getCartoonWatchService()`；Task 1 的 `buildQuotaSnapshot` 不直接用（服务已封装）
- Produces: `private async handlePlayCartoon(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult>`

- [ ] **Step 1: 实现 handler**

按 spec §7.3：

1. 设置 `toolId = PLAY_CARTOON_TOOL_ID`、`displayName = '看动画片'`、BUILTIN 兜底、`permissionLevel = READ`。
2. 解析 `video_id`；空 → `{ error: 'validation_failed', should_retry: true }`。
3. `library = getCartoonLibraryService()`；`entry = library.findById(videoId)`；`entry === null || entry.status !== 'ok' || !(await library.isUriReadable(entry.uri))` → 标 `unavailable`，返回 `{ error: 'video_unavailable', should_retry: true, available: [...] }`（最多 10 条 `ok` 条目的 `{id,title,duration_seconds}`）。
4. `watch = getCartoonWatchService()`；`!watch.canStartNewEpisode()` → `{ error: 'too_soon' }`（不 retry）。
5. `!watch.beginPending(toolCall.id)` → `{ error: 'already_playing' }`（不 retry）。
6. `decision = await watch.decideStart(entry.durationMs)`；不允许 → 返回 `{ error, today_watched_seconds, daily_limit_seconds, session_watched_seconds, session_limit_seconds }`（`video_unavailable` 额外带 `should_retry: true` 和 `available`）。
7. 把 `toolCall.arguments` 重写为 `{ video_id, title, duration_ms, uri }`。
8. `toolCall.approvalState = 'pending'`；挂 `pendingAnswers` Promise（镜像 `handleMaze` 的 `buildAskUserSnapshot` + `PendingToolInteractionKind.ASK_USER` + `publishPendingInteractionChanged()`）。
9. `await` 结果；`finally { watch.endPending(toolCall.id) }`。
10. `answerJson === null` → `denied` + cancelled result；否则 `answered` + `approvalReason = answerJson`，返回 `ToolResult`。
11. **不调用** `recordStarEvent`。

- [ ] **Step 2: 加分发分支**

在 `executeToolCall` 中、`resolveToolId` 兜底之前（参照 `isMazeFunctionName` 分支的位置）加：

```ts
if (isPlayCartoonFunctionName(normalizedFunctionName)) {
  return await this.handlePlayCartoon(toolCall, context)
}
```

- [ ] **Step 3: 编译验证**

同 Task 3 Step 4。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat(kids): handle play_cartoon pending playback"
```

---

### Task 7: 助手锁定 + 提示词注入

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`
- Modify: `entry/src/main/ets/viewmodels/ChatViewModel.ets`

**Interfaces:**
- Consumes: `PLAY_CARTOON_TOOL_ID`；`getCartoonLibraryService()`；`getCartoonWatchService()`；Task 2 的 `renderCartoonCatalogSection`
- Produces: `private async injectCartoonCatalogSection(basePrompt: string): Promise<string>`

- [ ] **Step 1: 锁定工具 + 静态提示词**

`AssistantModels.ets`：
- import `PLAY_CARTOON_TOOL_ID`。
- `KIDS_GAMES_LOCKED_TOOL_IDS` 追加 `PLAY_CARTOON_TOOL_ID`。
- `KIDS_GAMES_SYSTEM_PROMPT` 在「## 边界」之前插入「## 看动画片」段，文案按 spec §8.1 原文。

- [ ] **Step 2: 动态片库注入**

`ChatViewModel.buildRequestSystemPrompt` 的非 default 分支里，在 `injectSubjectPlanSection` 之后、`greetingHint` 之前：

```ts
if (assistantConfig.assistantId === KIDS_GAMES_ASSISTANT_ID) {
  composed = await this.injectCartoonCatalogSection(composed)
}
```

新增私有方法：

```ts
private async injectCartoonCatalogSection(basePrompt: string): Promise<string> {
  try {
    const entries = getCartoonLibraryService().list()
    const snapshot = await getCartoonWatchService().snapshot()
    const section = renderCartoonCatalogSection(entries, snapshot)
    if (section === '') {
      return basePrompt
    }
    return this.assistantService.combineSystemPrompts(basePrompt, section)
  } catch (error) {
    console.error('ChatViewModel', `injectCartoonCatalogSection failed: ${(error as Error)?.message ?? String(error)}`)
    return basePrompt
  }
}
```

若 `KIDS_GAMES_ASSISTANT_ID` 尚未导入，从 `models/AssistantModels` 补 import。

- [ ] **Step 3: 校验**

```bash
grep -c "PLAY_CARTOON_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets   # ≥ 2（import + locked list）
grep -c "看动画片" entry/src/main/ets/models/AssistantModels.ets                # ≥ 1
grep -c "injectCartoonCatalogSection" entry/src/main/ets/viewmodels/ChatViewModel.ets  # ≥ 2（定义 + 调用）
```

- [ ] **Step 4: 编译验证**

同 Task 3 Step 4。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/models/AssistantModels.ets entry/src/main/ets/viewmodels/ChatViewModel.ets
git commit -m "feat(kids): lock play_cartoon into kids_games and inject catalog"
```

---

### Task 8: 全屏播放页 + AVPlayer

**Files:**
- Create: `entry/src/main/ets/components/cartoon/CartoonPlayerView.ets`
- Create: `entry/src/main/ets/pages/CartoonPlayerPage.ets`
- Modify: `entry/src/main/resources/base/profile/router_map.json`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`（`onBackground` 事件）

**Interfaces:**
- Consumes: `CartoonPlayerRouteParams`；`getCartoonWatchService()`；`buildPlaybackResult`；`ServiceRegistry.toolExecution().resolvePendingAnswer`
- Produces:
  - `@ComponentV2 struct CartoonPlayerView { @Param uri: string; @Param autoPlay: boolean; @Param sessionLeftMs: number; @Param dailyLeftMs: number; @Event onReady: (durationMs: number) => void; @Event onPlayedDelta: (deltaMs: number) => void; @Event onFinished: () => void; @Event onError: (message: string) => void }`
  - `CartoonPlayerPageBuilder(name: string, param: Object)`，路由名 `CartoonPlayerPage`

- [ ] **Step 1: 实现 `CartoonPlayerView`**

- `XComponent({ id: 'cartoon_video_surface', type: XComponentType.SURFACE, controller: this.xComponentController })`。
- `aboutToAppear`：`fileIo.openSync(uri, READ_ONLY)` 拿 fd → `media.createAVPlayer()` → 注册 `stateChange` / `timeUpdate` / `endOfStream` / `error`。
- `initialized` → `player.surfaceId = this.xComponentController.getXComponentSurfaceId()` → `prepare()`。
- `prepared` → `durationMs = player.duration`（>0 时）→ `onReady(durationMs)` → `autoPlay ? play()`。
- `timeUpdate(timeMs)`：`delta = timeMs - lastTimeMs`；`delta > 0 && delta <= 1500` 时累加到 `pendingDeltaMs`；每满 1000ms `onPlayedDelta(1000)`；`lastTimeMs = timeMs`。暂停/结束时把余数（`floor(pendingDeltaMs)`）emit 一次并清零。
- `endOfStream` → `onFinished()`。
- `error` → `onError(message)`。
- `aboutToDisappear` → `player.release()`、`fileIo.closeSync(file)`、清理定时器。
- 底部覆盖控件：`▶/⏸` 按钮、`currentTime / duration`、`本次还剩 X 分钟 · 今天还剩 Y 分钟`（由页面通过 `@Param` 传入 `sessionLeftMs` / `dailyLeftMs`）。
- 订阅后台事件：`getContext(this).eventHub.on('app_background', cb)`，回调里 `pause()`；`aboutToDisappear` 时 `off`。

- [ ] **Step 2: `EntryAbility.onBackground` 发事件**

```ts
onBackground(): void {
  this.context.eventHub.emit('app_background')
}
```

保留现有日志。

- [ ] **Step 3: 实现 `CartoonPlayerPage`**

- module 级：`let cartoonPlayerPathStack: NavPathStack | null = null`；`let cartoonPlayerBackHandler: (() => boolean) | null = null`。
- 读取 `context.pathInfo.param as CartoonPlayerRouteParams`；缺字段时显示错误并允许关闭。
- `@Local watchedMs = 0`、`@Local sessionLeftMs`、`@Local dailyLeftMs`、`@Local showExitConfirm = false`、`@Local settled = false`、`@Local finishedOverlay = false`。
- `aboutToAppear`：`win = await window.getLastWindow(getContext(this))`；`savedOrientation = win.getPreferredOrientation()`；`await win.setPreferredOrientation(window.Orientation.LANDSCAPE)`；读 `snapshot()` 初始化剩余时间；`cartoonPlayerBackHandler = () => { this.requestExit(); return true }`。
- `onPlayedDelta(ms)`：`this.watchedMs += ms`；本地递减 `sessionLeftMs` / `dailyLeftMs`；`getCartoonWatchService().addWatched(ms).catch(...)`。
- `onFinished()`：`finishedOverlay = true`；1 秒后 `this.settle('finished', true)`。
- `onError(msg)`：显示错误；`settle('error', false)`。
- `requestExit()`：未播完 → `showExitConfirm = true`；播完/已结算 → pop。
- `settle(endedBy, completed)`：`if (settled) return; settled = true`；`await watch.flush()`；`const snap = await watch.snapshot()`；`const result = buildPlaybackResult(entryFromParams, watchedMs, completed, endedBy, snap)`；`ServiceRegistry.toolExecution().resolvePendingAnswer(params.toolCallId, JSON.stringify(result))`；`watch.markPlaybackEnded()`；`restoreOrientation()`；`cartoonPlayerPathStack?.pop()`。
- `aboutToDisappear()`：若未结算 → `settle('closed', false)`；恢复方向；`cartoonPlayerBackHandler = null`。
- 页面内容：黑色全屏、`CartoonPlayerView`、顶部 `✕`、退出确认用 `AlertDialog.show`（或自绘遮罩）。

- [ ] **Step 4: 注册路由**

`router_map.json` 增加：

```json
{ "name": "CartoonPlayerPage", "pageSourceFile": "src/main/ets/pages/CartoonPlayerPage.ets", "buildFunction": "CartoonPlayerPageBuilder" }
```

Builder 内 `NavDestination() { CartoonPlayerPage() }.hideTitleBar(true).onReady(...).onBackPressed(() => cartoonPlayerBackHandler !== null ? cartoonPlayerBackHandler() : false)`。

- [ ] **Step 5: 编译验证**

同 Task 3 Step 4。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/components/cartoon/CartoonPlayerView.ets entry/src/main/ets/pages/CartoonPlayerPage.ets entry/src/main/resources/base/profile/router_map.json entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat(kids): add fullscreen landscape cartoon player"
```

---

### Task 9: 气泡横幅 + MessageBubble 触点 + ChatPage 跳转

**Files:**
- Create: `entry/src/main/ets/components/cartoon/CartoonCard.ets`
- Modify: `entry/src/main/ets/components/MessageBubble.ets`
- Modify: `entry/src/main/ets/pages/ChatPage.ets`

**Interfaces:**
- Consumes: `isPlayCartoonFunctionName`；`CartoonPlayerRouteParams`
- Produces: `@ComponentV2 struct CartoonCard { @Param toolCall: ToolCall; @Param isAnswered: boolean; @Param answeredPayload: string; @Event onOpen: (toolCall: ToolCall) => void }`

- [ ] **Step 1: 实现 `CartoonCard`**

- 解析 `toolCall.arguments` 为 `Record<string, Object>`，读 `title` / `duration_ms`。
- 待答态：胶囊图标 `sys.symbol.play_circle` + 标题 + `formatDurationSeconds` + 「点一下就能看」+ `onClick(() => this.onOpen(this.toolCall))`。
- 已答态：一行文字 `🎬 {title} · 已看完 06:12` 或 `🎬 {title} · 看到 02:31 关掉了`，从 `answeredPayload` 解析 `completed` / `watched_seconds`。
- 复用 `themeAiBubble` / `app.color.divider` / `withColorAlpha(this.themePrimary, '18')`，与 maze 横幅同款。

- [ ] **Step 2: MessageBubble 七处触点**

1. import `isPlayCartoonFunctionName`。
2. `@Event onOpenCartoonPlayer: (toolCall: ToolCall) => void = () => {}`。
3. 在 maze 横幅之后加一个 ForEach 块：`shouldRenderCartoonInteractionCard` 为真时渲染 `CartoonCard({ toolCall, isAnswered: false, answeredPayload: toolCall.approvalReason, onOpen: (tc) => this.onOpenCartoonPlayer(tc) })`。
4. `private shouldRenderCartoonInteractionCard(toolCall, index): boolean`：镜像 `shouldRenderMazeInteractionCard`，用 `isPlayCartoonFunctionName`。
5. `isToolStepClickable` 加分支：`if (isPlayCartoonFunctionName(part.toolName)) return this.isSuccessfulToolStep(part)`。
6. `isToolStepExpanded` 的大 or 链 + `toggleToolStep` 的 `isDefaultExpanded` 链各加 `isPlayCartoonFunctionName(part.toolName)`。
7. `handleToolStepClick` 加 `this.toggleToolStep(part); return` 分支；step-content 级联加 `else if (isPlayCartoonFunctionName(step.toolName)) { this.CartoonStepContent(step) }`，并新增 `@Builder CartoonStepContent(step: MessagePart)`，内部用 `CartoonCard({ toolCall: ..., isAnswered: true, answeredPayload: resolveStepAnswerPayload(step.toolResult, step.toolApprovalReason), ... })`。Step content 需要按 `step.toolCallId` 找到 ToolCall：在 MessageBubble 内新增私有 `findToolCallById(id: string): ToolCall | null`（遍历 `this.message.toolCalls`）。

- [ ] **Step 3: ChatPage 跳转**

- MessageBubble 参数加 `onOpenCartoonPlayer: (toolCall: ToolCall): void => { this.openCartoonPlayer(toolCall) }`。
- 新增：

```ts
private openCartoonPlayer(toolCall: ToolCall): void {
  const parsed = parseCartoonArgs(toolCall.arguments)
  const params: CartoonPlayerRouteParams = {
    toolCallId: toolCall.id,
    videoId: parsed.videoId,
    title: parsed.title,
    durationMs: parsed.durationMs,
    uri: parsed.uri
  }
  this.navPathStack.pushPath({ name: 'CartoonPlayerPage', param: params })
}
```

`parseCartoonArgs(argsJson: string): CartoonPlayerRouteParams`（`pages/chat/` 下的纯函数或 ChatPage 私有方法）：try/catch 解析 `Record<string, Object>`，读 `video_id` / `title` / `duration_ms` / `uri`，缺字段时给 `''` / `0`，**不要**用 `toolCall.toolId`（那是 `'play_cartoon'`）。

- [ ] **Step 4: 精确触点校验**

```bash
grep -n "isPlayCartoonFunctionName" entry/src/main/ets/components/MessageBubble.ets
```

预期 7 处：import、`shouldRenderCartoonInteractionCard`、`isToolStepClickable`、`isToolStepExpanded`、`toggleToolStep`、`handleToolStepClick`、step-content 级联。多一处或少一处都要逐个核对。

```bash
grep -c "@Builder" entry/src/main/ets/components/MessageBubble.ets   # 改动前后各跑一次，差值为 +1
```

- [ ] **Step 5: 编译验证**

同 Task 3 Step 4。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/components/cartoon/CartoonCard.ets entry/src/main/ets/components/MessageBubble.ets entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(kids): render cartoon banner and open player"
```

---

### Task 10: 片库管理页 + 设置入口

**Files:**
- Create: `entry/src/main/ets/pages/CartoonLibraryPage.ets`
- Modify: `entry/src/main/ets/config/SettingsRouteName.ets`
- Modify: `entry/src/main/ets/components/index/IndexSettingsPanel.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/resources/base/profile/router_map.json`
- Modify: `entry/src/main/resources/base/element/string.json`

**Interfaces:**
- Consumes: `getCartoonLibraryService()` / `getCartoonWatchService()`；`parseCartoonLibrary` 不直接用
- Produces: 路由 `CartoonLibraryPage`；`SettingsRouteName.CARTOON_LIBRARY`

- [ ] **Step 1: 页面骨架**

镜像 `LearningWordLibraryPage` 的 HdsNavigation 结构（`@Entry @ComponentV2 struct` + Builder + `NavDestination` + `.onReady` 存 pathStack + `.onBackPressed` pop）。

`@Local` 状态：`entries: CartoonEntry[]`、`todayUsedMs: number`、`editingId: string`、`editingTitle: string`、`editingTags: string`、`showEditSheet: boolean`、`loadError: string`。

`aboutToAppear`：`await getCartoonLibraryService().initialize()` → `refreshStatuses()` → `this.entries = list()` → `todayUsedMs = (await getCartoonWatchService().snapshot()).dayMs`。

- [ ] **Step 2: 列表与操作**

- 顶部说明卡：`单次最多 20 分钟，每天最多 60 分钟` + `今天已看 X 分钟 / 60 分钟`。
- 每行：`play_circle` 图标 + 标题（`TextInput` 编辑态用 sheet）+ `formatDurationSeconds(durationMs/1000)` + 状态药丸（`正常` / `失效`）+ `编辑` / `删除`（失效行额外 `重新关联`）。
- 添加按钮：`new picker.DocumentViewPicker(getContext(this))`，`select({ maxSelectNumber: 20, fileSuffixFilters: ['视频|.mp4,.mkv,.mov,.webm,.avi,.ts'] })` → `addFromUris(result)` → 展示 `rejectedMessages`（`getUIContext().getPromptAction().showToast` 或页面内提示）→ 刷新列表。
- 编辑：`bindSheet($$this.showEditSheet, this.EditSheet(), { height: SheetSize.FIT_CONTENT })`，两个 `TextInput`（标题必填、标签可选），保存调 `updateEntry`。
- 删除：`AlertDialog.show({ message: '删除后小星游戏老师就找不到这一集了，确定吗？', primaryButton: ..., secondaryButton: ... })`。
- 重新关联：单文件 picker → `relinkEntry(id, uri)`，失败显示返回文案。
- 空状态文案：`还没有动画片。点击下方按钮，从手机里选择视频文件。`

- [ ] **Step 3: 设置入口**

- `SettingsRouteName` 加 `CARTOON_LIBRARY = 'CartoonLibraryPage'`。
- `IndexSettingsPanel` 加 `@Event onOpenCartoonLibrary`，在 `learningItems` 的 `LEARNING_TOMORROW_PLAN` 之后插入一项：`icon: $r('sys.symbol.play_circle')`、`title: $r('app.string.cartoon_library_title')`、`subtitle: $r('app.string.cartoon_library_desc')`。
- `Index.ets` 的 IndexSettingsPanel 调用处加 `onOpenCartoonLibrary: () => { this.openSettingsDestination(SettingsRouteName.CARTOON_LIBRARY) }`。
- `string.json` 加 `cartoon_library_title` = `动画片管理`、`cartoon_library_desc` = `配置小星游戏老师能播放的本地动画片`。
- `router_map.json` 注册 `CartoonLibraryPage`。

- [ ] **Step 4: 编译验证**

同 Task 3 Step 4。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/pages/CartoonLibraryPage.ets entry/src/main/ets/config/SettingsRouteName.ets entry/src/main/ets/components/index/IndexSettingsPanel.ets entry/src/main/ets/pages/Index.ets entry/src/main/resources/base/profile/router_map.json entry/src/main/resources/base/element/string.json
git commit -m "feat(kids): add cartoon library management page"
```

---

### Task 11: 文档 + 全量回归

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/rules/teaching-architecture.md`

- [ ] **Step 1: 更新文档**

- `CLAUDE.md` 的互动卡片表格加一行 `CartoonCard | play_cartoon | 本地动画片播放（全屏横屏，单次 20 分钟 / 每日 60 分钟硬闸）`。
- `.claude/rules/teaching-architecture.md` §4 工具表加 `play_cartoon` 行，并注明「不授星、只进 kids_games、片源家长端配置」。

- [ ] **Step 2: 全量 gauntlet**

```bash
grep -n "isPlayCartoonFunctionName" entry/src/main/ets/components/MessageBubble.ets   # 7 处
grep -c "PLAY_CARTOON_TOOL_ID" entry/src/main/ets/config/BuiltinTools.ets            # ≥ 2
grep -c "PLAY_CARTOON_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets          # ≥ 2
grep -c "isPlayCartoonFunctionName" entry/src/main/ets/services/ToolExecutionService.ets  # ≥ 2
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const m=s.match(/const rawSchemaJson: string = \`([\s\S]*?)\`/);JSON.parse(m[1])"
```

- [ ] **Step 3: 干净编译**

```bash
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

预期 BUILD SUCCESSFUL，产物 `entry/build/default/outputs/default/entry-default-signed.hap`。

- [ ] **Step 4: 真机手工验收（spec §14.2）**

逐条勾：添加 2 个视频 / 文件移走后显示失效 / 老师说片库为空 / 孩子没提时老师不主动提 / 播完自动返回 / 20 分钟边界（可用 1 分钟短片 × 21 集或临时把常量调小验证）/ 切后台暂停计时 / 杀进程重进时长仍在 / 星星明细无变化。

- [ ] **Step 5: 提交**

```bash
git add CLAUDE.md .claude/rules/teaching-architecture.md
git commit -m "docs(kids): document play_cartoon tool"
```

---

## Self-Review

**Spec coverage：**
- §2 已定需求 D1-D9 → Tasks 5/7（只锁 kids_games、老师不主动提）、Task 3（本地片源/配置页）、Tasks 1/4（20/60/闲置）、Task 6（一集一调用）。
- §5 时间规则 → Task 1 全部纯函数 + Task 4 服务。
- §7 工具 → Tasks 5/6。
- §8 提示词 → Tasks 2/7。
- §9 管理页 → Tasks 3/10。
- §10 播放器 → Task 8。
- §11 卡片 → Task 9。
- §12 触点 → Tasks 3-10 全覆盖；无 StarEventModels 改动（有意省略）。
- §14 测试 → Tasks 1/2 单测 + Task 11 手工验收。

**类型一致性：** `CartoonEntry` / `CartoonQuotaSnapshot` / `CartoonPlaybackResult` / `CartoonPlayerRouteParams` 名称在 Tasks 1→10 一致；服务 getter 统一 `getCartoonLibraryService()` / `getCartoonWatchService()` 与 `ServiceRegistry.cartoonLibrary()/cartoonWatch()` 双入口（服务内部各自返回同一单例）。

**遗留风险：** `hvigorw test` 不可用；Task 1/2 的测试需要在 DevEco Studio 里跑。若执行环境没有 IDE，把测试留到 Task 11 手工验收时补跑，但不得跳过。
