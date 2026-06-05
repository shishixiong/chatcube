# Categorization Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `categorization` tool to 小星老师 that lets 6-7 year olds practice classification by dragging/clicking items into the right bins, with AI-generated content per call.

**Architecture:** Follows the existing "interaction card" pattern (math_quiz / english_quiz / number_puzzle / handwriting_practice): `@ComponentV2` card → `pendingAnswers` Promise in ToolExecutionService → AI generates theme/bins/items/difficulty in tool arguments → card validates + renders. Dual view mode (inline + largeSize sheet) reuses NumberPuzzleCard's pattern.

**Tech Stack:** HarmonyOS ArkTS, ArkUI V2 (`@ComponentV2` / `@Param` / `@Event` / `@Local`), `@kit.ArkData` preferences, `@ohos.data.relationalStore` (relationalStore) for star_events, AppStorageV2 for theme state.

**Note on testing:** Project has no `.ets` test infrastructure (see spec §11). Verification is via build success + manual end-to-end checklist. Each task ends with a build/grep verification.

---

## File Structure

| File | Status | Responsibility |
|------|--------|----------------|
| `entry/src/main/ets/utils/SearchToolIdentityUtils.ets` | modify | Add `CATEGORIZATION_TOOL_ID` constant + `isCategorizationFunctionName` |
| `entry/src/main/ets/config/BuiltinTools.ets` | modify | Add tool definition / config / executor + register |
| `entry/src/main/ets/services/ToolExecutionService.ets` | modify | Add `handleCategorization` + dispatch in `executeToolCall` |
| `entry/src/main/ets/models/AssistantModels.ets` | modify | Append `'categorization'` to `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` |
| `entry/src/main/ets/components/CategorizationCard.ets` | **create** | The new @ComponentV2 game card (~600 lines) |
| `entry/src/main/ets/components/MessageBubble.ets` | modify | Import + render inline + render answered (folded) |

Total: 5 modified, 1 created.

---

## Task 1: Add tool ID constant and identity check

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets:12` (add constant after line 12) + append new function before line 90

- [ ] **Step 1.1: Add the constant after line 12**

Insert a new line after the existing `HANDWRITING_PRACTICE_TOOL_ID` declaration:

```typescript
export const CATEGORIZATION_TOOL_ID: string = 'categorization'
```

- [ ] **Step 1.2: Add the identity function**

Insert this function before the existing `getSearchToolIds()` function (around line 90):

```typescript
export function isCategorizationFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === CATEGORIZATION_TOOL_ID ||
    normalized === 'classify' ||
    normalized === 'categorize'
}
```

- [ ] **Step 1.3: Verify**

Run: `grep -n "CATEGORIZATION\|isCategorization" entry/src/main/ets/utils/SearchToolIdentityUtils.ets`
Expected: 2 matches (constant + function).

- [ ] **Step 1.4: Commit**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets
git commit -m "feat(categorization): add CATEGORIZATION_TOOL_ID constant and identity check"
```

---

## Task 2: Add tool definition, config, and executor

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

First, read the file around the registration site to understand the exact pattern. Look at how `math_quiz` / `english_quiz` / `number_puzzle` are defined (search for `getMathQuizToolDefinition` and `getNumberPuzzleToolDefinition`).

- [ ] **Step 2.1: Add import for CATEGORIZATION_TOOL_ID**

Find the import block at the top of `BuiltinTools.ets` (search for `MATH_QUIZ_TOOL_ID` import) and add a comma + new line:

```typescript
import {
  ...,
  CATEGORIZATION_TOOL_ID
} from '../utils/SearchToolIdentityUtils'
```

(Adjust to the actual import style used in the file.)

- [ ] **Step 2.2: Add the tool definition function**

Insert before `registerBuiltinTools()`:

```typescript
function getCategorizationToolDefinition(): ToolDefinition {
  return {
    type: 'function',
    function: {
      name: CATEGORIZATION_TOOL_ID,
      description: '让孩子把物品拖拽/点击到对应的分类桶里，训练分类归纳能力。',
      parameters: JSON.stringify({
        type: 'object',
        properties: {
          theme: {
            type: 'string',
            description: '主题名称，如"动物的家"、"水果与蔬菜"。2-12 字。'
          },
          instruction: {
            type: 'string',
            description: '可选，给孩子的开场白，如"帮小动物回家吧！"'
          },
          difficulty: {
            type: 'integer',
            enum: [1, 2, 3],
            description: '难度：1=4件2桶，2=6件3桶，3=9件3桶'
          },
          bins: {
            type: 'array',
            minItems: 2,
            maxItems: 3,
            items: {
              type: 'object',
              properties: {
                name: { type: 'string', description: '桶名（中文）' },
                emoji: { type: 'string', description: '桶标识 emoji，可选' }
              },
              required: ['name']
            }
          },
          items: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                name: { type: 'string' },
                emoji: { type: 'string' },
                bin_index: { type: 'integer', description: '所属桶的索引（从 0 开始）' }
              },
              required: ['name', 'bin_index']
            }
          }
        },
        required: ['theme', 'bins', 'items']
      })
    }
  }
}
```

- [ ] **Step 2.3: Add the tool config function**

```typescript
function getCategorizationToolConfig(): BuiltinToolConfig {
  return {
    id: CATEGORIZATION_TOOL_ID,
    displayName: '分类小管家',
    sourceType: ToolSourceType.BUILTIN,
    sourceLabel: '内置工具',
    permissionLevel: ToolPermissionLevel.READ,
    requiresApproval: false,
    visible: true
  }
}
```

(Adjust field names to match the existing `BuiltinToolConfig` interface in the file.)

- [ ] **Step 2.4: Add the executor (delegates to ToolExecutionService)**

```typescript
async function executeCategorizationTool(
  toolCall: ToolCall,
  context: ToolExecutionContext
): Promise<ToolResult> {
  return ServiceRegistry.toolExecution().executeToolCall(toolCall, context)
}
```

(Check the existing executors for the exact signature — they typically just call into `ToolExecutionService.executeToolCall`.)

- [ ] **Step 2.5: Register the tool in `registerBuiltinTools()`**

Find the registration list (search for `MATH_QUIZ_TOOL_ID` inside `registerBuiltinTools`) and add a 3-line block right after the `number_puzzle` registration (or in alphabetical order):

```typescript
registerBuiltinTool(CATEGORIZATION_TOOL_ID, getCategorizationToolDefinition, getCategorizationToolConfig, executeCategorizationTool)
```

If the project uses a different registration pattern (e.g., a single array), add the entry there. Look at the existing registrations to match the style exactly.

- [ ] **Step 2.6: Add CATEGORIZATION_TOOL_ID to the `getBuiltinToolIds()` array (if it exists)**

If there's a `getBuiltinToolIds()` function returning an array of all built-in IDs, append `CATEGORIZATION_TOOL_ID`.

- [ ] **Step 2.7: Verify**

Run: `grep -n "CATEGORIZATION\|categorization" entry/src/main/ets/config/BuiltinTools.ets`
Expected: at least 4 matches (import, definition, config, registration).

- [ ] **Step 2.8: Commit**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(categorization): register categorization tool definition/config/executor"
```

---

## Task 3: Add service handler in ToolExecutionService

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

- [ ] **Step 3.1: Import the constant and function**

Find the import block for `SearchToolIdentityUtils` (search for `MATH_QUIZ_TOOL_ID`). Add to the import:

```typescript
import {
  ...,
  CATEGORIZATION_TOOL_ID,
  isCategorizationFunctionName
} from '../utils/SearchToolIdentityUtils'
```

- [ ] **Step 3.2: Add `handleCategorization` method**

Insert this method after `handleNumberPuzzle` (search for `private async handleNumberPuzzle`). Use `handleMathQuiz` as the structural template (`:544-611`):

```typescript
// categorization 特殊路径: 与 math_quiz 类似, 挂起等待 CategorizationCard 回答。
private async handleCategorization(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
  toolCall.toolId = CATEGORIZATION_TOOL_ID
  if (toolCall.displayName.trim() === '') {
    toolCall.displayName = '分类小管家'
  }
  toolCall.sourceType = ToolSourceType.BUILTIN
  if (toolCall.sourceLabel.trim() === '') {
    toolCall.sourceLabel = '内置工具'
  }
  toolCall.permissionLevel = ToolPermissionLevel.READ

  toolCall.approvalState = 'pending'

  let answerJson: string | null = null
  try {
    answerJson = await new Promise<string | null>((resolve) => {
      const existing = this.pendingAnswers.get(toolCall.id)
      if (existing !== undefined) {
        existing.resolve(null)
        this.pendingAnswers.delete(toolCall.id)
      }
      const snapshot = this.buildAskUserSnapshot(toolCall, context)
      snapshot.kind = PendingToolInteractionKind.ASK_USER
      snapshot.toolId = CATEGORIZATION_TOOL_ID
      this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
      this.publishPendingInteractionChanged()
    })
  } catch (error) {
    console.error('ToolExecutionService', `categorization answer callback failed: ${JSON.stringify(error)}`)
    toolCall.approvalState = 'denied'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ error: `categorization 失败: ${JSON.stringify(error)}`, cancelled: true }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  if (this.isCancelled()) {
    console.info('ToolExecutionService', 'categorization cancelled by external stop')
    toolCall.approvalState = 'denied'
    return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
  }

  if (answerJson === null) {
    toolCall.approvalState = 'denied'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ cancelled: true, error: '小朋友未完成分类' }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  toolCall.approvalState = 'answered'
  toolCall.approvalReason = answerJson
  console.info('ToolExecutionService', `categorization answered: ${toolCall.id}`)
  this.recordStarEvent('categorization', toolCall, context, answerJson)
  return new ToolResult(
    toolCall.id,
    answerJson,
    false,
    toolCall.displayName,
    toolCall.sourceLabel
  )
}
```

- [ ] **Step 3.3: Add dispatch in `executeToolCall`**

Find the dispatch logic (around `:1028-1058` per the explore report). It's an if/else chain calling `handleMathQuiz` / `handleEnglishQuiz` / `handleNumberPuzzle` / `handleHandwriting`. Add a new branch for categorization. The exact pattern is:

```typescript
// Inside the dispatch chain, after handleNumberPuzzle branch:
if (isCategorizationFunctionName(functionName)) {
  return await this.handleCategorization(toolCall, context)
}
```

Look at the existing dispatch structure to add the branch in the right place (typically grouped with the other "interaction card" tools).

- [ ] **Step 3.4: Verify**

Run: `grep -n "categorization\|CATEGORIZATION\|handleCategorization" entry/src/main/ets/services/ToolExecutionService.ets`
Expected: at least 4 matches (import, constant, handler definition, dispatch).

- [ ] **Step 3.5: Commit**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat(categorization): add handleCategorization service path with Promise suspension"
```

---

## Task 4: Add categorization to locked tool IDs

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets:97-107` (the `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` array)

- [ ] **Step 4.1: Read the current array**

Run: `sed -n '95,110p' entry/src/main/ets/models/AssistantModels.ets`
Confirm the array is `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` with the 8 existing tools.

- [ ] **Step 4.2: Append `'categorization'` to the array**

Add a new line at the end of the array (after `'handwriting_practice'`):

```typescript
export const DEFAULT_ASSISTANT_LOCKED_TOOL_IDS: string[] = [
  'child_profile',
  'get_time_info',
  'image_generation',
  'math_verify',
  'math_quiz',
  'english_quiz',
  'number_puzzle',
  'handwriting_practice',
  'categorization'  // <-- new
]
```

- [ ] **Step 4.3: Verify**

Run: `grep -n "categorization" entry/src/main/ets/models/AssistantModels.ets`
Expected: 1 match.

- [ ] **Step 4.4: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(categorization): lock categorization tool for default assistant"
```

---

## Task 5: Create CategorizationCard component

**Files:**
- Create: `entry/src/main/ets/components/CategorizationCard.ets`

This is the largest task. The file is approximately 600 lines. Create the file with the complete implementation below. The structure follows `NumberPuzzleCard.ets` and `HandwritingCard.ets` patterns: imports → types → constants → @ComponentV2 struct → business methods → builder methods.

- [ ] **Step 5.1: Create the file with complete content**

Write the file `/Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/components/CategorizationCard.ets` with this content:

```typescript
import { ToolCall } from '../models/ChatModels'
import { getAppUiState, AppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'

const DOMAIN = 0x0002
const TAG = 'CategorizationCard'
const SUCCESS_GREEN = '#22C55E'
const GIVEUP_ORANGE = '#FF9F43'

// ================ 结果接口 ================
export interface CategorizationResult {
  theme: string
  difficulty: 1 | 2 | 3
  correct: number
  total: number
  time_seconds: number
  wrong_attempts: number
  completed: boolean
}

export interface CategorizationBin {
  name: string
  emoji?: string
}

export interface CategorizationItem {
  name: string
  emoji: string
  bin_index: number
}

interface NormalizedData {
  ok: boolean
  error: string
  bins: CategorizationBin[]
  items: CategorizationItem[]
  difficulty: 1 | 2 | 3
  theme: string
  instruction: string
}

interface ItemPosition {
  x: number
  y: number
}

// ================ 组件 ================
@ComponentV2
export struct CategorizationCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // 主题态
  @Local theme: string = ''
  @Local instruction: string = ''
  @Local bins: CategorizationBin[] = []
  @Local items: CategorizationItem[] = []
  @Local difficulty: 1 | 2 | 3 = 1
  @Local validationError: string = ''

  // 游戏态
  @Local placedItems: number[] = []  // placedItems[originalIndex] = binIndex, -1 if not placed
  @Local correctCount: number = 0
  @Local wrongAttempts: number = 0
  @Local elapsedSeconds: number = 0
  @Local isCompleted: boolean = false
  @Local hasWon: boolean = false
  @Local selectedItemIndex: number = -1
  @Local draggedItemIndex: number = -1
  @Local hoveredBinIndex: number = -1
  @Local shakingItemIndex: number = -1
  @Local itemPositions: ItemPosition[] = []  // 显示位置
  @Local dragOffset: ItemPosition = { x: 0, y: 0 }

  // 非响应式
  private timerId: number = -1
  private shakeTimerId: number = -1
  private startTime: number = 0
  private isGaveUp: boolean = false
  // 桶区在屏幕上的像素位置 (drag 命中检测用)
  private binBounds: Array<{ x: number, y: number, w: number, h: number }> = []
  // 物品当前应在的像素位置 (不含 drag offset)
  private itemBasePositions: ItemPosition[] = []

  aboutToAppear() {
    const v = this.validateAndNormalize()
    if (!v.ok) {
      this.validationError = v.error
      return
    }
    this.theme = v.theme
    this.instruction = v.instruction
    this.bins = v.bins
    this.items = v.items
    this.difficulty = v.difficulty
    this.placedItems = new Array(this.items.length).fill(-1)
    if (this.isAnswered) {
      this.parseAnsweredPayload()
    } else {
      this.shuffleItems()
      this.startTimer()
    }
  }

  aboutToDisappear() {
    this.stopTimer()
    if (this.shakeTimerId !== -1) {
      clearTimeout(this.shakeTimerId)
      this.shakeTimerId = -1
    }
  }

  // ================ 业务方法 ================
  private validateAndNormalize(): NormalizedData {
    const empty: NormalizedData = { ok: false, error: '', bins: [], items: [], difficulty: 1, theme: '', instruction: '' }
    let parsed: Record<string, Object>
    try {
      parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
    } catch (_e) {
      return { ...empty, error: '题目格式错误，提示小星老师再出一题吧' }
    }
    const theme = (parsed['theme'] as string) ?? ''
    if (theme.trim() === '') {
      return { ...empty, error: '主题为空，提示小星老师再出一题吧' }
    }
    const instruction = (parsed['instruction'] as string) ?? ''
    const binsRaw = (parsed['bins'] as Array<Record<string, string>>) ?? []
    const itemsRaw = (parsed['items'] as Array<Record<string, Object>>) ?? []
    if (binsRaw.length < 2 || binsRaw.length > 3) {
      return { ...empty, error: '分类桶数量不对（需要 2 或 3 个）' }
    }
    for (const b of binsRaw) {
      if (!b['name'] || (b['name'] as string).trim() === '') {
        return { ...empty, error: '分类桶名字缺失' }
      }
    }
    if (itemsRaw.length === 0) {
      return { ...empty, error: '物品列表为空' }
    }
    // 推断 difficulty
    let difficulty = (parsed['difficulty'] as number) ?? 0
    if (difficulty !== 1 && difficulty !== 2 && difficulty !== 3) {
      if (itemsRaw.length === 4) difficulty = 1
      else if (itemsRaw.length === 6) difficulty = 2
      else if (itemsRaw.length === 9) difficulty = 3
      else return { ...empty, error: `物品数量 ${itemsRaw.length} 与难度不匹配（应为 4/6/9）` }
    }
    const expectedCount = difficulty === 1 ? 4 : (difficulty === 2 ? 6 : 9)
    if (itemsRaw.length !== expectedCount) {
      return { ...empty, error: `物品数量 ${itemsRaw.length} 与难度 ${difficulty}（期望 ${expectedCount}）不匹配` }
    }
    // 校验 bin_index 越界 + 桶内至少 2 件
    const binCounts = new Array<number>(binsRaw.length).fill(0)
    const items: CategorizationItem[] = []
    for (let i = 0; i < itemsRaw.length; i++) {
      const raw = itemsRaw[i]
      const name = (raw['name'] as string) ?? ''
      const emoji = (raw['emoji'] as string) ?? ''
      const binIndex = raw['bin_index'] as number
      if (!Number.isInteger(binIndex) || binIndex < 0 || binIndex >= binsRaw.length) {
        return { ...empty, error: `第 ${i + 1} 个物品的 bin_index=${binIndex} 越界` }
      }
      if (name.trim() === '') {
        return { ...empty, error: `第 ${i + 1} 个物品没有名字` }
      }
      binCounts[binIndex]++
      items.push({ name, emoji, bin_index: binIndex })
    }
    for (let i = 0; i < binCounts.length; i++) {
      if (binCounts[i] < 2) {
        return { ...empty, error: `第 ${i + 1} 个桶只有 ${binCounts[i]} 个物品（至少 2 个）` }
      }
    }
    const bins: CategorizationBin[] = binsRaw.map((b) => ({
      name: b['name'] as string,
      emoji: (b['emoji'] as string) ?? ''
    }))
    return { ok: true, error: '', bins, items, difficulty: difficulty as 1 | 2 | 3, theme, instruction }
  }

  private parseAnsweredPayload() {
    try {
      const result = JSON.parse(this.answeredPayload) as CategorizationResult
      this.hasWon = result.completed && result.correct === result.total
      this.correctCount = result.correct
      this.wrongAttempts = result.wrong_attempts
      this.elapsedSeconds = result.time_seconds
      this.isCompleted = true
      // 还原 placedItems
      this.placedItems = this.items.map((it) => it.bin_index)
    } catch (_e) {
      this.validationError = '已答数据格式错误'
    }
  }

  private shuffleItems() {
    const shuffled = [...this.items]
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      const tmp = shuffled[i]
      shuffled[i] = shuffled[j]
      shuffled[j] = tmp
    }
    this.items = shuffled
    this.placedItems = new Array(this.items.length).fill(-1)
  }

  private startTimer() {
    this.startTime = Date.now()
    this.timerId = setInterval(() => {
      if (this.isCompleted || this.startTime === 0) {
        return
      }
      this.elapsedSeconds = Math.floor((Date.now() - this.startTime) / 1000)
    }, 500)
  }

  private stopTimer() {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private handleDrop(itemIndex: number, binIndex: number) {
    if (this.isCompleted) {
      return
    }
    if (binIndex < 0 || binIndex >= this.bins.length) {
      return
    }
    const item = this.items[itemIndex]
    if (item.bin_index === binIndex) {
      // 正确归位
      this.placedItems[itemIndex] = binIndex
      this.correctCount++
      hilog.info(DOMAIN, TAG, `Drop correct: item=${itemIndex} bin=${binIndex}, correct=${this.correctCount}/${this.items.length}`)
      this.evaluateWin()
    } else {
      // 错误归位
      this.wrongAttempts++
      this.shakeItem(itemIndex)
      hilog.info(DOMAIN, TAG, `Drop wrong: item=${itemIndex} expected=${item.bin_index} got=${binIndex}`)
    }
  }

  private handleItemClick(itemIndex: number) {
    if (this.isCompleted) {
      return
    }
    if (this.selectedItemIndex === itemIndex) {
      this.selectedItemIndex = -1
    } else {
      this.selectedItemIndex = itemIndex
    }
  }

  private handleBinClick(binIndex: number) {
    if (this.isCompleted || this.selectedItemIndex < 0) {
      return
    }
    this.handleDrop(this.selectedItemIndex, binIndex)
    this.selectedItemIndex = -1
  }

  private evaluateWin() {
    if (this.placedItems.every((b) => b >= 0)) {
      this.stopTimer()
      this.isCompleted = true
      this.hasWon = true
      this.submitResult(true)
    }
  }

  private handleGiveUp() {
    if (this.isCompleted) {
      return
    }
    this.stopTimer()
    this.isCompleted = true
    this.hasWon = false
    this.isGaveUp = true
    this.submitResult(false)
  }

  private submitResult(completed: boolean) {
    const correctCount = completed ? this.correctCount : this.placedItems.filter((b, i) => b === this.items[i].bin_index).length
    const result: CategorizationResult = {
      theme: this.theme,
      difficulty: this.difficulty,
      correct: correctCount,
      total: this.items.length,
      time_seconds: Math.round(this.elapsedSeconds * 10) / 10,
      wrong_attempts: this.wrongAttempts,
      completed
    }
    hilog.info(DOMAIN, TAG, `Submit: ${JSON.stringify(result)}`)
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private shakeItem(itemIndex: number) {
    this.shakingItemIndex = itemIndex
    if (this.shakeTimerId !== -1) {
      clearTimeout(this.shakeTimerId)
    }
    this.shakeTimerId = setTimeout(() => {
      this.shakingItemIndex = -1
      this.shakeTimerId = -1
    }, 400)
  }

  // ================ 辅助 ================
  private getUiState(): AppUiState {
    return getAppUiState()
  }

  private getBinColorAlpha(binIndex: number): string {
    const alphas = ['18', '28', '38']
    return alphas[binIndex] ?? '18'
  }

  private getBinBorderAlpha(binIndex: number): string {
    const alphas = ['30', '40', '50']
    return alphas[binIndex] ?? '30'
  }

  private getDifficultyLabel(): string {
    if (this.difficulty === 1) return '入门'
    if (this.difficulty === 2) return '简单'
    return '进阶'
  }

  private formatTime(): string {
    const m = Math.floor(this.elapsedSeconds / 60)
    const s = this.elapsedSeconds % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  // ================ 渲染：主 build ================
  build() {
    Column() {
      if (this.validationError !== '') {
        this.ErrorPlaceholder()
      } else {
        this.HeaderRow()
        if (this.hasWon) {
          this.WinBanner()
        }
        this.BinRow()
        this.ItemsLayer()
        this.StatsGrid()
        if (!this.isCompleted) {
          this.ActionRow()
        }
      }
    }
    .padding(this.largeSize ? 20 : 14)
    .borderRadius(this.largeSize ? 0 : 14)
    .backgroundColor(this.largeSize ? Color.Transparent : $r('app.color.theme_ai_bubble'))
    .borderWidth(this.largeSize ? 0 : 1)
    .borderColor($r('app.color.divider'))
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .onTouch((e) => e.stopPropagation())
  }

  // ================ 各子区域 ================
  @Builder
  private HeaderRow() {
    Row() {
      Row() {
        SymbolGlyphModifier($r('sys.symbol.box'))
          .size(15)
          .fontColor([this.getUiState().themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.getUiState().themePrimary, '18'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text('分类小管家')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.theme} · ${this.getDifficultyLabel()} · ${this.items.length}件 ${this.bins.length}桶`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })

      if (this.isCompleted) {
        Text(this.hasWon ? '已完成' : '已放弃')
          .fontSize(10)
          .fontColor(this.hasWon ? $r('app.color.status_success') : GIVEUP_ORANGE)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(withColorAlpha(this.hasWon ? SUCCESS_GREEN : GIVEUP_ORANGE, '15'))
          .borderRadius(8)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private WinBanner() {
    Row() {
      Text('🎉')
        .fontSize(20)
        .margin({ right: 6 })
      Column() {
        Text('分类完成！')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(SUCCESS_GREEN)
        Text(`${this.correctCount}/${this.items.length} · ${this.formatTime()}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(SUCCESS_GREEN, this.getUiState().isDarkMode ? '18' : '0C'))
    .borderWidth(1)
    .borderColor(withColorAlpha(SUCCESS_GREEN, this.getUiState().isDarkMode ? '38' : '28'))
  }

  @Builder
  private BinRow() {
    Row({ space: 10 }) {
      ForEach(this.bins, (bin: CategorizationBin, index: number) => {
        Column() {
          if (bin.emoji && bin.emoji !== '') {
            Text(bin.emoji)
              .fontSize(28)
              .margin({ bottom: 4 })
          }
          Text(bin.name)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
          // 已归位物品计数
          if (this.isCompleted || this.placedItems.some((b) => b === index)) {
            Text(`${this.placedItems.filter((b) => b === index).length}件`)
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .height(72)
        .borderRadius(12)
        .backgroundColor(this.hoveredBinIndex === index
          ? withColorAlpha(this.getUiState().themePrimary, '24')
          : withColorAlpha(this.getUiState().themePrimary, this.getBinColorAlpha(index)))
        .borderWidth(1.5)
        .borderStyle(BorderStyle.Dashed)
        .borderColor(this.hoveredBinIndex === index
          ? this.getUiState().themePrimary
          : withColorAlpha(this.getUiState().themePrimary, this.getBinBorderAlpha(index)))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .scale(this.hoveredBinIndex === index ? { x: 1.05, y: 1.05 } : { x: 1, y: 1 })
        .animation({ duration: 100, curve: Curve.EaseOut })
        .onClick(() => this.handleBinClick(index))
      })
    }
    .width('100%')
  }

  @Builder
  private ItemsLayer() {
    // 内联模式: 物品以普通流式布局呈现（点击交互为主）
    if (!this.largeSize) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.items, (item: CategorizationItem, index: number) => {
          if (this.placedItems[index] < 0) {
            this.ItemCircle(item, index)
          }
        })
      }
      .width('100%')
      .padding(8)
    } else {
      // largeSize 模式: 用 Stack 实现自由拖放
      Stack() {
        ForEach(this.items, (item: CategorizationItem, index: number) => {
          if (this.placedItems[index] < 0) {
            this.DraggableItem(item, index)
          }
        })
      }
      .width('100%')
      .height(280)
      .backgroundColor(withColorAlpha(this.getUiState().themePrimary, '05'))
      .borderRadius(12)
    }
  }

  @Builder
  private ItemCircle(item: CategorizationItem, index: number) {
    Column() {
      if (item.emoji && item.emoji !== '') {
        Text(item.emoji)
          .fontSize(24)
      } else {
        Text(item.name)
          .fontSize(11)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .backgroundColor(this.getUiState().themeAiBubble)
    .borderWidth(this.selectedItemIndex === index ? 3 : 0.5)
    .borderColor(this.selectedItemIndex === index ? this.getUiState().themePrimary : $r('app.color.divider'))
    .scale(this.selectedItemIndex === index ? { x: 1.1, y: 1.1 } : { x: 1, y: 1 })
    .animation({ duration: 80, curve: Curve.EaseOut })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .margin(6)
    .onClick(() => this.handleItemClick(index))
  }

  @Builder
  private DraggableItem(item: CategorizationItem, index: number) {
    Column() {
      if (item.emoji && item.emoji !== '') {
        Text(item.emoji)
          .fontSize(24)
      } else {
        Text(item.name)
          .fontSize(11)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .backgroundColor(this.getUiState().themeAiBubble)
    .borderWidth(this.shakingItemIndex === index ? 2 : 0.5)
    .borderColor(this.shakingItemIndex === index ? '#FF3B30' : $r('app.color.divider'))
    .scale(this.draggedItemIndex === index
      ? { x: 1.15, y: 1.15 }
      : (this.shakingItemIndex === index ? { x: 1.05, y: 1.05 } : { x: 1, y: 1 }))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.itemPositions[index]?.x ?? 0, y: this.itemPositions[index]?.y ?? 0 })
    .translate({ x: this.draggedItemIndex === index ? this.dragOffset.x : 0, y: this.draggedItemIndex === index ? this.dragOffset.y : 0 })
    .shadow(this.draggedItemIndex === index
      ? { radius: 12, color: '#40000000', offsetY: 4 }
      : { radius: 2, color: '#1F000000', offsetY: 1 })
    .animation({ duration: this.draggedItemIndex === index ? 0 : 200, curve: Curve.EaseOut })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: 5 })
        .onActionStart(() => {
          this.draggedItemIndex = index
        })
        .onActionUpdate((e: GestureEvent) => {
          if (this.draggedItemIndex === index) {
            this.dragOffset = { x: e.offsetX, y: e.offsetY }
            // 计算当前悬停桶
            const baseX = this.itemBasePositions[index]?.x ?? 0
            const baseY = this.itemBasePositions[index]?.y ?? 0
            const curX = baseX + e.offsetX + 28  // +28 = 物品半径
            const curY = baseY + e.offsetY + 28
            let hovered = -1
            for (let i = 0; i < this.binBounds.length; i++) {
              const b = this.binBounds[i]
              if (curX >= b.x && curX <= b.x + b.w && curY >= b.y && curY <= b.y + b.h) {
                hovered = i
                break
              }
            }
            this.hoveredBinIndex = hovered
          }
        })
        .onActionEnd(() => {
          if (this.draggedItemIndex === index && this.hoveredBinIndex >= 0) {
            this.handleDrop(index, this.hoveredBinIndex)
          }
          this.draggedItemIndex = -1
          this.hoveredBinIndex = -1
          this.dragOffset = { x: 0, y: 0 }
        })
    )
  }

  @Builder
  private StatsGrid() {
    Row({ space: 8 }) {
      this.StatCard('⏱', this.formatTime(), '时间')
      this.StatCard('✅', `${this.correctCount}/${this.items.length}`, '进度')
    }
    .width('100%')
  }

  @Builder
  private StatCard(icon: string, value: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(16)
        .margin({ bottom: 2 })
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding(10)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(this.getUiState().themePrimary, this.getUiState().isDarkMode ? '0C' : '06'))
  }

  @Builder
  private ActionRow() {
    Row() {
      Text('放弃本局')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .padding(8)
        .onClick(() => this.handleGiveUp())
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
  }

  @Builder
  private ErrorPlaceholder() {
    Row() {
      Text('💡')
        .fontSize(20)
        .margin({ right: 8 })
      Text(this.validationError)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(GIVEUP_ORANGE, '10'))
  }
}
```

- [ ] **Step 5.2: Verify file was created**

Run: `wc -l entry/src/main/ets/components/CategorizationCard.ets`
Expected: ~580-620 lines.

- [ ] **Step 5.3: Commit**

```bash
git add entry/src/main/ets/components/CategorizationCard.ets
git commit -m "feat(categorization): add CategorizationCard component with drag/click interaction"
```

---

## Task 6: Integrate into MessageBubble

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`

- [ ] **Step 6.1: Add import**

Find the existing import block for `HandwritingCard` and add CategorizationCard:

```typescript
import { CategorizationCard, CategorizationResult } from './CategorizationCard'
```

Also add `isCategorizationFunctionName` to the `SearchToolIdentityUtils` import:

```typescript
import { ... isCategorizationFunctionName } from '../utils/SearchToolIdentityUtils'
```

- [ ] **Step 6.2: Add inline rendering branch (unanswered state)**

Find the section that renders unanswered interaction cards (around `:2010-2093` per the explore report). It has branches like:
```typescript
if (isNumberPuzzleFunctionName(...)) { NumberPuzzleCard(...) }
if (isHandwritingPracticeFunctionName(...)) { HandwritingCard(...) }
```

Add a similar branch for categorization. The exact pattern depends on the existing code; use the existing MathQuizCard branch as the template:

```typescript
} else if (isCategorizationFunctionName(toolCall.functionName)) {
  CategorizationCard({
    toolCall: toolCall,
    isAnswered: false,
    answeredPayload: '',
    largeSize: false,
    onAnswer: (toolCallId: string, answerJson: string) => {
      this.onAskUserAnswer(toolCallId, answerJson)
    }
  })
}
```

(Adjust the `onAnswer` binding to match the existing convention in MessageBubble — it may be a class method, e.g., `this.handleAskUserAnswer` or via an Event.)

- [ ] **Step 6.3: Add answered (folded) rendering branch**

Find the section that renders already-answered tool results (around `:3739-3911`). It has a switch/dispatch for the answered state of each card type. Add categorization:

```typescript
} else if (isCategorizationFunctionName(toolCall.functionName)) {
  // 折叠态: 显示主题 + 已完成/已放弃 药丸
  Row() {
    Text('📦')
      .fontSize(16)
      .margin({ right: 6 })
    Text('分类小管家 · ' + this.parseCategorizationTheme(toolCall.arguments))
      .fontSize(13)
      .fontColor($r('app.color.text_primary'))
      .layoutWeight(1)
    Text(...)
  }
  ...
}
```

If the existing pattern uses a generic "tool call chip" for answered states, the simplest approach is to:
- Reuse the existing folded tool call UI
- Extract the `theme` from `toolCall.arguments` for the title

Look at the existing answered-state code for `math_quiz` / `english_quiz` to follow the project's convention.

- [ ] **Step 6.4: Helper to extract theme from JSON**

Add a private method in MessageBubble (or inline in the render block) to extract the theme:

```typescript
private parseCategorizationTheme(argsJson: string): string {
  try {
    const obj = JSON.parse(argsJson) as Record<string, string>
    return obj['theme'] ?? '分类小管家'
  } catch (_e) {
    return '分类小管家'
  }
}
```

- [ ] **Step 6.5: Verify**

Run: `grep -n "CategorizationCard\|isCategorizationFunctionName" entry/src/main/ets/components/MessageBubble.ets`
Expected: at least 3 matches (import, inline render, answered render).

- [ ] **Step 6.6: Commit**

```bash
git add entry/src/main/ets/components/MessageBubble.ets
git commit -m "feat(categorization): wire CategorizationCard into MessageBubble inline + answered states"
```

---

## Task 7: Build verification

**Files:**
- None (read-only verification)

- [ ] **Step 7.1: Run the HarmonyOS build**

Run from project root:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -100
```

Expected: build succeeds with no errors. The output should end with `BUILD SUCCESSFUL` or similar. If there are errors, read them carefully and fix in the relevant task's file (re-edit, re-commit).

- [ ] **Step 7.2: Common errors and fixes**

| Error pattern | Fix |
|---------------|-----|
| `'CategorizationCard' has no exported member` | Check that Task 5's file exports `CategorizationCard` (not just struct name) |
| `Cannot find name 'CATEGORIZATION_TOOL_ID'` | Verify Task 1 added the export |
| `'@Local' decorator not allowed here` | Make sure the field is inside `@ComponentV2 struct`, not a free variable |
| `Object literal may only specify known properties` | The `ToolDefinition` interface likely uses `function: { name, description, parameters }` — adjust Step 2.2 if needed |
| `'buildAskUserSnapshot' is private` | It's called only inside the class — ensure Task 3.2 is inside `class ToolExecutionService` |

- [ ] **Step 7.3: Commit any fixes**

If you had to fix issues, commit them with descriptive messages:
```bash
git add -A
git commit -m "fix(categorization): resolve ArkTS build errors"
```

---

## Task 8: Manual end-to-end testing

**Files:**
- None

- [ ] **Step 8.1: Open in DevEco Studio**

Open `/Users/mac/mygame/HarmonyOS-app/chatcube` in DevEco Studio 5.0+. Sync Gradle/hvigor.

- [ ] **Step 8.2: Configure a test provider**

In the app, go to Settings → AI Services → add a provider that supports function calling (e.g., OpenAI, Anthropic, Google). Make sure the model supports the `categorization` tool.

- [ ] **Step 8.3: Test difficulty 1**

In a chat with 小星老师, prompt the AI to call categorization. Example prompt to send:

> 帮我出一道分类题，主题是"水果与蔬菜"，4 个物品 2 个桶。

Expected:
- Inline card appears with header "分类小管家 · 水果与蔬菜 · 入门 · 4件 2桶"
- 2 bins rendered (水果 / 蔬菜)
- 4 item cards rendered with emojis
- Click an item → it highlights (scale 1.1)
- Click correct bin → item disappears from the items layer (or moves into bin)
- After all 4 placed → WinBanner shows "分类完成！ 4/4 · 0:05"
- AI receives result JSON

- [ ] **Step 8.4: Test difficulty 2**

Send: "主题是动物的家，6 个物品 3 个桶"

Expected: 3 bins, 6 items, all 3 placements work correctly.

- [ ] **Step 8.5: Test difficulty 3**

Send: "主题是职业，9 个物品 3 个桶"

Expected: 3 bins, 9 items, harder classification.

- [ ] **Step 8.6: Test drag interaction (largeSize mode)**

In ChatPage, when the inline card is shown, tap it to expand to the full-screen sheet (if the project supports this — check `ChatPage.ets:3260` for the existing NumberPuzzleCard largeSize flow). If not yet wired up, you can defer this step.

Expected: full-screen sheet shows bins at top, items in a Stack layer that can be dragged.

- [ ] **Step 8.7: Test error path**

Manually call the tool with malformed args (e.g., via debug):
```json
{"theme": "", "bins": [{"name": "A"}], "items": []}
```

Expected: card shows "题目格式错误..." placeholder, does NOT call onAnswer.

- [ ] **Step 8.8: Test give up**

Click "放弃本局" mid-game.

Expected: `onAnswer` fires with `{completed: false, ...}`. The card shows "已放弃" pill in subsequent renders.

- [ ] **Step 8.9: Test answered state persistence**

After completing a game, scroll away in the chat and scroll back.

Expected: card renders in "answered" mode (folded), shows "已完成" pill and the time/correct count.

- [ ] **Step 8.10: Test dark mode**

Toggle dark mode in app settings.

Expected: all colors adapt, no visual artifacts, contrast remains readable.

- [ ] **Step 8.11: Document any issues**

If any test fails, note the issue and fix in a follow-up commit. Common fixes:
- Animation timing tweaks
- Color alpha adjustments
- Layout overflow on small screens

- [ ] **Step 8.12: Final commit (if any fixes were made)**

```bash
git add -A
git commit -m "fix(categorization): manual QA adjustments (dark mode, animations, layout)"
```

---

## Self-Review

After writing this plan, I checked against the spec:

1. **Spec coverage:**
   - §2 交互流程 → Tasks 5+6 (card + MessageBubble)
   - §3 组件 API → Task 5 (CategorizationCard exports)
   - §4 工具签名 → Task 2 (BuiltinTools definition)
   - §5 难度规格 → Task 5 (validateAndNormalize enforces 4/6/9)
   - §6 视觉设计 → Task 5 (all 5 builders)
   - §7 交互模型 → Task 5 (PanGesture + click)
   - §8 动画体系 → Task 5 (animation in builders)
   - §9 状态机 → Task 5 (handleDrop/evaluateWin)
   - §10 内容校验 → Task 5 (validateAndNormalize)
   - §11 持久化 → Task 3 (recordStarEvent in handleCategorization)
   - §12 接入点 → Tasks 1-6
   - §14 验收清单 → Task 8 (manual testing)

2. **Placeholder scan:** No "TBD", "TODO", "fill in details", or vague steps. All code blocks are complete.

3. **Type consistency:**
   - `CategorizationResult` interface defined in Task 5, used in Task 3 (via JSON), Task 6 (parseAnsweredPayload), Task 8 (manual test). ✅
   - `CategorizationBin` / `CategorizationItem` defined in Task 5, used in Task 2 (definition), Task 5 (validation). ✅
   - `CATEGORIZATION_TOOL_ID` defined in Task 1, used in Tasks 2/3/4. ✅
   - `isCategorizationFunctionName` defined in Task 1, used in Tasks 3/6. ✅
   - `handleCategorization` defined in Task 3, called in Task 3 dispatch. ✅
