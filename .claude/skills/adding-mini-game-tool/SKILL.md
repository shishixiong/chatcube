---
name: adding-mini-game-tool
description: Use when adding a new interactive mini-game tool to the chatcube project (小星老师 AI assistant) that the AI can invoke mid-conversation via function calling. Triggers: "add a new mini-game", "implement a new tool", "create a new interactive card/game", "扩展小游戏", "新加个 XXX 工具". Do NOT use for modifying existing tools, fixing bugs in existing tools, or UI-only changes — those use systematic-debugging or simplify.
---

# Adding a Mini-Game Tool to chatcube

## Overview

All 5 existing tools (`math_quiz`, `english_quiz`, `number_puzzle`, `handwriting_practice`, `categorization`) follow a strict 8-file integration pattern. **A new tool is an extension of the existing data model, not a new architecture.** There is no design freedom in the integration — only the game logic itself varies. Cutting corners in the integration causes silent runtime bugs (wrong tool names in AI summaries, blank tool centers, app crashes at startup) that build success does not catch.

**Skill loading**: This file lives at `.claude/skills/adding-mini-game-tool/SKILL.md`. If you arrived via a slash command or the user's message matched the trigger phrase, the skill is loaded. Otherwise — for example, fresh session where the user says "加个新迷宫" or "新加个拼音接龙工具" — **invoke this skill explicitly before starting work**. The skill's value is the gauntlet, not the recipe; skipping the gauntlet is the regression.

## When to Use

- ✅ Adding a new game type with function-call invocation + inline card render + answered timeline state
- ✅ Adding a new `StarActivityType` (new bucket in star dashboard)
- ❌ Modifying existing tools → `systematic-debugging`
- ❌ Bug fixes in existing tools → `systematic-debugging`
- ❌ UI-only changes to existing cards → `simplify`

## Pre-Step Audit (mandatory, before step 1)

For each OPTIONAL step (8, 9), write a `Decision: yes/no + reason` line in your working notes **before** starting step 1. Silent deferral is a category-1 failure — the integration is allowed to ship with optional paths skipped, but only if the decision is on paper. Format:

```
Decision step 8 (largeSize sheet): YES, because maze needs full-screen swipe real-estate
Decision step 9a (PreferencesService best-score): YES, mirror NumberPuzzleCard
Decision step 9b (DatabaseService records table): NO, star_events already carries payload
```

## Args Validation Decision

Validate AI-provided args in the **card's `aboutToAppear`** (defensive, matches `CategorizationCard` pattern at L148-248). The handler can also validate for early-fail JSON response, but the card is the renderer's source of truth — if validation lives only in the handler, malformed args still flow to the card and crash the build. **Default: card-side.**

## The 10-Step Recipe (strict dependency order)

**Execute steps in this order. Skipping order = silent breakage.**

| # | File | What to change | Verify after |
|---|------|---------------|--------------|
| 1 | `utils/SearchToolIdentityUtils.ets` (L13, L91) | Add `XXX_TOOL_ID` constant + `isXxxFunctionName()` function | `grep -c "XXX_TOOL_ID\|isXxxFunctionName" SearchToolIdentityUtils.ets` ≥ 2 |
| 2 | `config/BuiltinTools.ets` (L30, ~1498-1602, L1741-1750, L1760) | Add import, `XxxArgs`, `XxxExecutor` (stub), `createXxxToolDefinition` (rawSchemaJson), `createXxxToolConfig`, `registerBuiltinTools` block, append to `getBuiltinToolIds()` | **JSON.parse gauntlet** (see below) |
| 3 | `services/ToolExecutionService.ets` (L21, L27, ~825-893, L1126-1130) | Import, `handleXxx()` (mirror `handleCategorization`), dispatch branch **placed BEFORE `resolveToolId` fallback at ~L1138** | `grep -c "handleXxx\|isXxxFunctionName"` ≥ 3; branch before L1140 |
| 4a | `models/StarEventModels.ets` | **10 drift locations** — see StarEventModels Gauntlet below | **4-grep gauntlet** |
| 4b | `services/StarRewardService.ets` (L76-107) | Add `if (activityType === 'xxx')` branch in `computeStars` | `grep -c "activityType === 'xxx'"` ≥ 1 |
| 5 | `models/AssistantModels.ets` (L11, L99-109, L17-96) | Add import, append `XXX_TOOL_ID` to `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`, add system-prompt paragraph | `grep -c "XXX_TOOL_ID" AssistantModels.ets` ≥ 3 |
| 6 | `components/XxxCard.ets` (NEW) | Define `XxxResult` interface, `@ComponentV2 struct XxxCard` with `@Param toolCall/isAnswered/answeredPayload/largeSize`, `@Event onAnswer`. **CRITICAL reactivity rule**: in `StatsGrid` and any other `@Builder`, read state fields directly via `this.elapsedSeconds` / `this.moveCount` — do NOT pass formatted strings as `@Builder` parameters. This is the ArkUI V2 reactivity rule from `.claude/rules/number-puzzle-card.md` §6.3; violating it compiles fine but breaks live updates. If the card needs new third-party deps, also update `entry/oh-package.json5` and run `ohpm install` before `hvigorw assembleHap`. | Build succeeds |
| 7 | `components/MessageBubble.ets` (L20, L39, ~L2140, L2580, L2632, L2642, ~L2747, L3102, L3531, ~L3967) | Import, inline render, 3 or-chain extensions, helper, click dispatch, step switch, step content builder | **Exact-line check** — see gauntlet below |
| 8 (OPT) | `pages/ChatPage.ets` (L278, L2431, L2797, L3342) | Add largeSize sheet — only if game benefits from full-screen | Decide upfront |
| 9 (OPT) | `services/PreferencesService.ets` (L53-55) + `services/DatabaseService.ets` (L40) | Best-score persistence + records table — only if applicable | Decide upfront |
| 10 | All | Run full gauntlet + `hvigorw assembleHap` + **device install** | All green |

## Step 4a: StarEventModels.ets Gauntlet (THE high-drift file)

10 drift locations for every new `StarActivityType`. The 4 if/else chains fall through to `META_PUZZLE` if you miss any. **Silent failure: build passes, runtime says "数字华容道" when kid played your new game.** (See commit `a391ead` for the original instance.)

| # | Line | Change |
|---|------|--------|
| 1 | L10 | `StarActivityType` union: add `'xxx'` |
| 2 | L38-44 | `TodayStarSummaryByType`: add `xxx: StarTypeBucket` |
| 3 | L65-74 | `createEmptyTodayStarSummary()`: add `xxx: createEmptyBucket()` |
| 4 | L84-90 | `StarActivityMetaMap`: add `xxx: StarActivityMeta` |
| 5 | after L119 | Add `META_XXX` constant (emoji, shortLabel, longLabel, grantedHint, unit) |
| 6 | L128-134 | `metaRecord`: add `xxx: META_XXX` |
| 7 | L137 | `activityTypes` array: add `'xxx'` |
| 8 | L140-155 | `getBucketFromSummary`: `if (type === 'xxx') return byType.xxx` BEFORE fallthrough |
| 9 | L157-171 | `getActivityMeta`: `if (type === 'xxx') return META_XXX` BEFORE fallthrough |
| 10 | L177-191 | `getActivitySymbol`: `if (type === 'xxx') return $r('sys.symbol.X')` BEFORE fallthrough (X from whitelist) |

**Run all 4 greps after step 4a — exact counts:**

```bash
grep -n "META_XXX\|META_PUZZLE\|META_MATH\|META_ENGLISH\|META_HANDWRITING" entry/src/main/ets/models/StarEventModels.ets
# Expect: META_XXX appearing in 2 lines (declaration + metaRecord init)
# Plus the existing 4 META_* references unchanged

grep -n "byType\." entry/src/main/ets/models/StarEventModels.ets
# Expect: byType.xxx appearing in exactly 3 lines:
#   - L38-44 interface field declaration
#   - L65-74 createEmptyTodayStarSummary body
#   - L140-155 getBucketFromSummary branch
# A 4th byType.xxx is a typo (e.g. byType.maze1).

grep -n "return META_" entry/src/main/ets/models/StarEventModels.ets
# Expect: return META_XXX appearing in exactly 1 line (getActivityMeta)
# Plus existing return META_PUZZLE / META_MATH / META_ENGLISH / META_HANDWRITING

grep -n "return byType\." entry/src/main/ets/models/StarEventModels.ets
# Expect: return byType.xxx appearing in exactly 1 line (getBucketFromSummary)
# Plus existing returns to other types
```

A count higher than expected is a red flag (typo or duplicate insertion). A count lower means you skipped a location — re-check the 10-row drift table above.

## Mandatory Verification Gauntlet

**JSON.parse gauntlet** (after step 2) — validates the AI-facing schema:

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const m=s.match(/const rawSchemaJson: string = \`([\s\S]*?)\`/);JSON.parse(m[1])"
```

Use `「」` (or `""`) for any quoted examples in description values. **No ASCII `"` inside JSON string values** — even one breaks `JSON.parse` at app startup.

**sys.symbol whitelist** (any time you use `$r('sys.symbol.X')`):

Known-good: `plus`, `doc_plaintext`, `AI_pencil`, `folder`, `lightbulb`, `wand_and_stars`, `checkmark_circle`, `xmark_circle`, `chevron_down`, `pause`, `speaker_wave_2`, `translate`, `dot_grid_2x2`, `arrow_clockwise`, `checkmark_square_on_square`. Fabricated names → `'Unknown resource name <X>'` build error. (See commit `57ea04a`.)

**4-grep StarEventModels gauntlet** (after step 4a) — see above.

**Exact-line MessageBubble check** (after step 7) — lower-bound `grep -c ≥ 6` is too lax (typos pass). Inspect each occurrence and verify it matches one of these expected sites:

```bash
grep -n "isXxxFunctionName" entry/src/main/ets/components/MessageBubble.ets
```

Expected 7 sites (line numbers from categorization as reference; yours will match if you mirrored correctly):
1. L39 — import added to the function-name-check import block
2. L~2140 — inline render guard inside the ForEach
3. L2580 — added to `isToolStepClickable` or-chain
4. L2632 — added to `isDefaultExpanded` or-chain
5. L2642 — added to `isAutoExpandable` or-chain
6. L3102 — added to `handleToolStepClick` switch
7. L3531 — added to step-content switch (the `else if` cascade)

An 8th occurrence is a typo (e.g. `isXxxFunctionnName` misspelled) or a stale fragment from copy-paste. Inspect any unexpected line.

**Device install** (after step 10) — `hvigorw assembleHap` green is necessary but NOT sufficient. Install, start chat, have AI call the tool, verify: card renders inline, answer submission reaches AI, star count increments, daily summary shows the right label (not a fallthrough), tool appears in 工具中心.

## Common Mistakes (anti-rationalization table)

| Rationalization | Why it's wrong | What to do |
|-----------------|---------------|------------|
| "Build passed, integration is fine" | `hvigorw assembleHap` does NOT run `JSON.parse`, does NOT exercise if/else fallthrough, does NOT call `registerBuiltinTools` | Run full gauntlet + device test |
| "Added to the union, that's the main thing" | Union is 1 of 10 locations in `StarEventModels.ets` | Run the 4-grep gauntlet |
| "Categorization didn't need X, so my tool doesn't either" | Each optional path is a deliberate decision, not a precedent | Decide optional steps upfront; don't skip by analogy |
| "MessageBubble.ets is 4000+ lines, I'll just grep" | Grep misses wiring contracts (`isAskUserToolCallAnswered` field, `@Builder` reactivity rule from `.claude/rules/number-puzzle-card.md` §6.3) | Read in 500-line sections |
| "Schema is fine, I used full-width quotes" | Bug is at the boundary — one ASCII `"` in a description value breaks JSON.parse | Run JSON.parse gauntlet |
| "Copy-paste dispatch from categorization" | Branch placement matters: AFTER `resolveToolId` (~L1140) goes through generic executor, never reaches the card | Verify branch is BEFORE the generic fallback |
| "I'll add system prompt paragraph later" | Tool description = schema (what args to pass). System prompt = trigger (when to invoke). AI won't call without it | Add the paragraph in step 5 |
| "Emoji doesn't matter, reuse 🎮" | Same icon for two activities confuses kids in the dashboard | Pick semantically appropriate emoji |
| "Skip `getActivitySymbol` — build will catch it" | Function returns `Resource` checked at first render, not build. Latent runtime bug | Use a whitelist symbol |
| "Skip `getBuiltinToolIds()` — tool center just won't show it" | True but breaks the 工具中心 surface. Silent miss | `grep -c "XXX_TOOL_ID" BuiltinTools.ets` ≥ 1 in the return array |
| "Replay the categorization commit diff" | Categorization fix commit `a391ead` is the *fix*, not the implementation. Replaying misses the 791-line card | Walk the 10-step recipe end-to-end |
| "Skip `recordStarEvent` since persistence is v2" | `recordStarEvent` is the UI star trigger, not persistence. Skipping = no star on completion | Verify call in `handleXxx` |
| "Drag/gesture works in dev" | Gestures that worked in isolation can conflict with parent List scrolling | Prototype gestures before committing; ship click-only v1 if uncertain |

## Quick Reference: 8 Required Files

```
utils/SearchToolIdentityUtils.ets      + 2 edits: constant + identity fn
config/BuiltinTools.ets                + 5 edits: import, args, executor, def, config, register, getIds
services/ToolExecutionService.ets      + 3 edits: import, handler, dispatch
models/StarEventModels.ets             + 10 edits: union, 2 interfaces, init, META, record, array, 3 fns
services/StarRewardService.ets         + 1 edit: computeStars branch
models/AssistantModels.ets             + 3 edits: import, locked list, system prompt
components/XxxCard.ets                 NEW ~600-800 lines
components/MessageBubble.ets           + ~7 edits
```

## Red Flags — STOP and restart

- New type added to union but 4-grep gauntlet not run
- Build green but device install skipped
- JSON.parse gauntlet skipped because schema "looks fine"
- Dispatch branch in `executeToolCall` placed after `resolveToolId` fallback
- `sys.symbol.*` value not in the whitelist
- `META_XXX` constant added but `metaRecord` initialization entry missing
- `getBuiltinToolIds()` array not updated
- System prompt paragraph in `AssistantModels.ets` missing
- `recordStarEvent('xxx', ...)` call missing in `handleXxx`

## Why this skill exists

Without this checklist, three bug classes recur every new tool:
1. `StarEventModels.ets` 4 if/else chains fall through to `META_PUZZLE` → AI mis-labels activities (commit `a391ead`, 2026-06-06)
2. ASCII `"` in JSON schema description strings → `JSON.parse` crashes `registerBuiltinTools` at app startup (commit `f81b48a`)
3. Fabricated `sys.symbol.X` → `'Unknown resource name'` build error (commit `57ea04a`)

All three: build passes, runtime breaks in a way that doesn't surface until production. The pattern is "no escape at compile time, full escape at deploy time."
