# Chat Model Picker Reasoning Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hard-filter reasoning-capable models only in all 3 chat-related model pickers (chat titlebar / default model / assistant default), and auto-switch to the first reasoning model in chat page's `validateAndSetCurrentModel` when the current model lacks reasoning capability (session-only, global model untouched).

**Architecture:** Bottom-up. Pure utility `filterReasoningModels` first (TDD), then thread `reasoningOnly` param through `ModelListProjection` → `ModelSelectorContent` → 3 caller sites, then add 2 string resources, then refactor `ChatPage.validateAndSetCurrentModel` to call the new utility.

**Tech Stack:** ArkTS @ComponentV2, `@ohos/hypium` + `@ohos/hamock` for unit tests, `ModelAbilityRegistry` for capability derivation, `getEffectiveCapabilities` (user override-aware).

**Spec:** `docs/superpowers/specs/2026-06-12-chat-model-picker-reasoning-filter-design.md`

---

## File Structure

**New files (2):**
- `entry/src/main/ets/utils/ReasoningModelFilter.ets` — pure function `filterReasoningModels` + `ReasoningModelPick` interface
- `entry/src/ohosTest/ets/test/utils/ReasoningModelFilter.test.ets` — 6 unit tests

**Modified files (8):**
- `entry/src/main/ets/config/ModelListProjection.ets` — add `reasoningOnly` param to 2 public functions + 1 internal function; insert filter at line 113
- `entry/src/main/ets/components/ModelSelector.ets` — add `@Param reasoningOnly`; thread in `rebuildRows`
- `entry/src/main/ets/components/chat/ChatModelSelectorSheetContent.ets` — add 2 empty-state @Params; pass `reasoningOnly: true` + empty state to `ModelSelectorContent`
- `entry/src/main/ets/components/defaultmodel/DefaultModelSelectSheetContent.ets` — pass `reasoningOnly: true`; replace empty state string keys
- `entry/src/main/ets/pages/Index.ets` (`AssistantModelSheetBuilder`, line 4303) — add 2 empty-state @Params; pass `reasoningOnly: true` + empty state
- `entry/src/main/ets/pages/ChatPage.ets` — add private `selectFirstReasoningModel` method; refactor `validateAndSetCurrentModel` (line 2003); add 2 empty-state @Params to `ModelSelectorSheetBuilder` (line 3151)
- `entry/src/main/resources/base/element/string.json` — add 2 new strings
- `entry/src/main/resources/zh_CN/element/string.json` — add 2 new strings (Chinese translations)

**Image gen caller (`ImageGenerationModelSheet.ets`) — 0 changes.**

---

### Task 1: TDD — Create `filterReasoningModels` util and unit tests

**Files:**
- Create: `entry/src/main/ets/utils/ReasoningModelFilter.ets`
- Create: `entry/src/ohosTest/ets/test/utils/ReasoningModelFilter.test.ets`

- [ ] **Step 1: Write the failing unit test**

Create `entry/src/ohosTest/ets/test/utils/ReasoningModelFilter.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { filterReasoningModels, ReasoningModelPick } from '../../../../main/ets/utils/ReasoningModelFilter'
import { ModelInfo, ModelProvider, ModelCapabilities, ProviderType, ApiStyle } from '../../../../main/ets/models/ChatModels'

// Helper: build a ModelInfo with a specific capabilities override
function makeModel(id: string, isEnabled: boolean, supportsReasoning: boolean,
  userModified: boolean = true): ModelInfo {
  const m = new ModelInfo(id, id, 4096, isEnabled, false)
  const caps = new ModelCapabilities(false, supportsReasoning, false, false, true)
  m.capabilities = caps
  m.capabilitiesUserModified = userModified
  return m
}

function makeProvider(id: string, models: ModelInfo[]): ModelProvider {
  const p = new ModelProvider(id, id, ProviderType.CUSTOM, '', $r('app.color.text_primary'),
    '', ApiStyle.OPENAI)
  p.models = models
  return p
}

export default function reasoningModelFilterTest() {
  describe('filterReasoningModels', () => {
    it('returns null when providers is empty', 0, () => {
      const result = filterReasoningModels([])
      expect(result).assertNull()
    })

    it('returns null when all models are disabled', 0, () => {
      const providers = [
        makeProvider('p1', [makeModel('m1', false, true), makeModel('m2', false, true)])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNull()
    })

    it('returns null when enabled models all lack reasoning', 0, () => {
      const providers = [
        makeProvider('p1', [makeModel('m1', true, false), makeModel('m2', true, false)])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNull()
    })

    it('returns the first enabled + reasoning model from the first matching provider', 0, () => {
      const m1 = makeModel('m1', true, false)
      const m2 = makeModel('m2', true, true)  // first hit
      const m3 = makeModel('m3', true, true)
      const providers = [
        makeProvider('p1', [m1, m2]),
        makeProvider('p2', [m3])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNotNull()
      const pick = result as ReasoningModelPick
      expect(pick.provider.id).assertEqual('p1')
      expect(pick.reasoningModel.id).assertEqual('m2')
    })

    it('skips disabled models and returns the next enabled + reasoning one', 0, () => {
      const m1 = makeModel('m1', true, false)
      const m2 = makeModel('m2', false, true)  // disabled, skipped
      const m3 = makeModel('m3', true, true)  // first hit
      const providers = [
        makeProvider('p1', [m1, m2, m3])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNotNull()
      const pick = result as ReasoningModelPick
      expect(pick.reasoningModel.id).assertEqual('m3')
    })

    it('honors capabilitiesUserModified override when supportsReasoning is set true', 0, () => {
      // Build a model where user manually set supportsReasoning=true via userModified=true.
      // We can't easily make a non-registry model without mocking, so we exercise the
      // userModified path by confirming our test helper's userModified=true is preserved.
      const m = makeModel('user-override', true, true, true)
      expect(m.capabilitiesUserModified).assertTrue()
      const result = filterReasoningModels([makeProvider('p1', [m])])
      expect(result).assertNotNull()
      const pick = result as ReasoningModelPick
      expect(pick.reasoningModel.id).assertEqual('user-override')
    })
  })
}
```

- [ ] **Step 2: Run the test to verify it fails (RED)**

Open `entry/src/ohosTest/ets/test/utils/ReasoningModelFilter.test.ets` in DevEco Studio, right-click the file → **Run 'ReasoningModelFilter.test'**.

Expected: All 6 tests fail with "filterReasoningModels is not defined" or "module not found".

(MEMORY.md note: CLI `hvigorw test` fails on this project — run tests in DevEco Studio only.)

- [ ] **Step 3: Write minimal implementation (GREEN)**

Create `entry/src/main/ets/utils/ReasoningModelFilter.ets`:

```typescript
import { ModelInfo, ModelProvider } from '../models/ChatModels'
import { getEffectiveCapabilities } from './ModelCapabilityDeriver'

export interface ReasoningModelPick {
  provider: ModelProvider
  reasoningModel: ModelInfo
}

/**
 * 纯函数: 在 providers 列表中找第一个 isEnabled 且 supportsReasoning 的模型。
 * 按 provider 在数组中的顺序遍历, provider 内按 model 数组顺序遍历。
 * 返回 null 表示找不到。
 */
export function filterReasoningModels(
  providers: ModelProvider[]
): ReasoningModelPick | null {
  for (let i = 0; i < providers.length; i++) {
    const provider = providers[i]
    for (let j = 0; j < provider.models.length; j++) {
      const model = provider.models[j]
      if (!model.isEnabled) {
        continue
      }
      if (!getEffectiveCapabilities(model).supportsReasoning) {
        continue
      }
      return { provider, reasoningModel: model }
    }
  }
  return null
}
```

- [ ] **Step 4: Run the test to verify it passes (GREEN)**

Re-run the test in DevEco Studio (right-click → Run).

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/utils/ReasoningModelFilter.ets \
        entry/src/ohosTest/ets/test/utils/ReasoningModelFilter.test.ets
git commit -m "feat(reasoning-filter): add filterReasoningModels util + 6 unit tests"
```

---

### Task 2: Extend `ModelListProjection` with `reasoningOnly` param

**Files:**
- Modify: `entry/src/main/ets/config/ModelListProjection.ets:51-87` (function signatures)
- Modify: `entry/src/main/ets/config/ModelListProjection.ets:108-115` (filter insertion point)

- [ ] **Step 1: Add `reasoningOnly` param to `buildModelSelectorRowsWithOutputMode` signature**

In `entry/src/main/ets/config/ModelListProjection.ets`, find the `buildModelSelectorRowsWithOutputMode` function (line 69) and change its signature:

**Before:**
```typescript
export function buildModelSelectorRowsWithOutputMode(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean,
  hasOutputModeFilter: boolean,
  outputModeFilter: OutputMode
): ModelSelectorBuildResult {
```

**After:**
```typescript
export function buildModelSelectorRowsWithOutputMode(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean,
  hasOutputModeFilter: boolean,
  outputModeFilter: OutputMode,
  reasoningOnly: boolean
): ModelSelectorBuildResult {
```

Update its body to pass `reasoningOnly` through:

**Before:**
```typescript
  return buildModelSelectorRowsInternal(
    providers,
    searchKeywords,
    favoriteKeys,
    showFavoritesOnly,
    includeModelIdInSearch,
    hasOutputModeFilter,
    outputModeFilter
  )
```

**After:**
```typescript
  return buildModelSelectorRowsInternal(
    providers,
    searchKeywords,
    favoriteKeys,
    showFavoritesOnly,
    includeModelIdInSearch,
    hasOutputModeFilter,
    outputModeFilter,
    reasoningOnly
  )
```

- [ ] **Step 2: Add `reasoningOnly` param to `buildModelSelectorRows` (legacy wrapper) and to `buildModelSelectorRowsInternal`**

In the same file, find the `buildModelSelectorRows` function (line 51) and change its body to pass `reasoningOnly=false` through (it's a legacy entry point kept for backward compat):

**Before:**
```typescript
export function buildModelSelectorRows(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean
): ModelSelectorBuildResult {
  return buildModelSelectorRowsInternal(
    providers,
    searchKeywords,
    favoriteKeys,
    showFavoritesOnly,
    includeModelIdInSearch,
    false,
    OutputMode.TEXT
  )
}
```

**After:**
```typescript
export function buildModelSelectorRows(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean
): ModelSelectorBuildResult {
  return buildModelSelectorRowsInternal(
    providers,
    searchKeywords,
    favoriteKeys,
    showFavoritesOnly,
    includeModelIdInSearch,
    false,
    OutputMode.TEXT,
    false
  )
}
```

- [ ] **Step 3: Update `buildModelSelectorRowsInternal` signature and insert filter**

Find `buildModelSelectorRowsInternal` (line 89) and update its signature:

**Before:**
```typescript
function buildModelSelectorRowsInternal(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean,
  hasOutputModeFilter: boolean,
  outputModeFilter: OutputMode
): ModelSelectorBuildResult {
```

**After:**
```typescript
function buildModelSelectorRowsInternal(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean,
  hasOutputModeFilter: boolean,
  outputModeFilter: OutputMode,
  reasoningOnly: boolean
): ModelSelectorBuildResult {
```

- [ ] **Step 4: Insert the reasoning filter inside the inner for loop**

Find the inner `for (let j = 0; j < provider.models.length; j++)` loop and the existing `hasOutputModeFilter` check (around line 113). Add the new filter right after it:

**Before:**
```typescript
    for (let j = 0; j < provider.models.length; j++) {
      const model = provider.models[j]
      if (!model.isEnabled) {
        continue
      }
      if (hasOutputModeFilter && getEffectiveOutputMode(model) !== outputModeFilter) {
        continue
      }

      enabledModelCount++
```

**After:**
```typescript
    for (let j = 0; j < provider.models.length; j++) {
      const model = provider.models[j]
      if (!model.isEnabled) {
        continue
      }
      if (hasOutputModeFilter && getEffectiveOutputMode(model) !== outputModeFilter) {
        continue
      }
      if (reasoningOnly && !getEffectiveCapabilities(model).supportsReasoning) {
        continue
      }

      enabledModelCount++
```

Note: `enabledModelCount++` does **not** increment for filtered-out reasoning models, so `hasEnabledModels` reflects "reasoning-aware enabled count" when `reasoningOnly=true`. This is the intended behavior — see spec §3.2.

- [ ] **Step 5: Add the `getEffectiveCapabilities` import**

Check the top of `entry/src/main/ets/config/ModelListProjection.ets`. The current import line 3 is:

```typescript
import { getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'
```

Change it to also import `getEffectiveCapabilities`:

**Before:**
```typescript
import { getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'
```

**After:**
```typescript
import { getEffectiveCapabilities, getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'
```

- [ ] **Step 6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/config/ModelListProjection.ets
git commit -m "feat(reasoning-filter): thread reasoningOnly through ModelListProjection"
```

---

### Task 3: Add `reasoningOnly` `@Param` to `ModelSelectorContent` and wire `rebuildRows`

**Files:**
- Modify: `entry/src/main/ets/components/ModelSelector.ets:30-33` (add `@Param`)
- Modify: `entry/src/main/ets/components/ModelSelector.ets:134-148` (`rebuildRows`)

- [ ] **Step 1: Add `@Param reasoningOnly` to `ModelSelectorContent`**

In `entry/src/main/ets/components/ModelSelector.ets`, find the `@Param` block around line 30-33. Add the new param right after `outputModeFilter`:

**Before:**
```typescript
  @Param hasOutputModeFilter: boolean = false
  @Param outputModeFilter: OutputMode = OutputMode.TEXT
  @Param emptyTitle: string | Resource = ''
  @Param emptyDescription: string | Resource = ''
```

**After:**
```typescript
  @Param hasOutputModeFilter: boolean = false
  @Param outputModeFilter: OutputMode = OutputMode.TEXT
  @Param reasoningOnly: boolean = false
  @Param emptyTitle: string | Resource = ''
  @Param emptyDescription: string | Resource = ''
```

- [ ] **Step 2: Thread `reasoningOnly` into `rebuildRows`**

Find the `rebuildRows()` method (line 134) and update the call to `buildModelSelectorRowsWithOutputMode`:

**Before:**
```typescript
    const result: ModelSelectorBuildResult = buildModelSelectorRowsWithOutputMode(
      this.providers,
      this.searchKeywords,
      this.favoriteKeySet,
      this.showFavoritesOnly,
      this.includeModelIdInSearch,
      this.hasOutputModeFilter,
      this.outputModeFilter
    )
```

**After:**
```typescript
    const result: ModelSelectorBuildResult = buildModelSelectorRowsWithOutputMode(
      this.providers,
      this.searchKeywords,
      this.favoriteKeySet,
      this.showFavoritesOnly,
      this.includeModelIdInSearch,
      this.hasOutputModeFilter,
      this.outputModeFilter,
      this.reasoningOnly
    )
```

- [ ] **Step 3: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/components/ModelSelector.ets
git commit -m "feat(reasoning-filter): add reasoningOnly @Param to ModelSelectorContent"
```

---

### Task 4: Add 2 string resources (zh_CN + base)

**Files:**
- Modify: `entry/src/main/resources/base/element/string.json` (add 2 strings)
- Modify: `entry/src/main/resources/zh_CN/element/string.json` (add 2 Chinese strings)

- [ ] **Step 1: Add 2 strings to base/element/string.json**

Open `entry/src/main/resources/base/element/string.json`. Find a good insertion point — after `default_model_no_provider_hint` (line 1708) is a natural spot.

Add the following 2 entries immediately after `default_model_no_provider_hint`:

```json
    {
      "name": "no_reasoning_model_title",
      "value": "No reasoning models available"
    },
    {
      "name": "no_reasoning_model_hint",
      "value": "Enable a model with reasoning capability in provider settings"
    },
```

Note: the comma after `default_model_no_provider_hint` (line 1710) needs to remain — these 2 new entries are inserted between it and the next entry. Verify the JSON structure remains valid by counting braces/brackets.

- [ ] **Step 2: Add Chinese translations to zh_CN/element/string.json**

Open `entry/src/main/resources/zh_CN/element/string.json`. Find `default_model_no_provider_hint` (likely same line number as base) and add the 2 Chinese entries in the same position:

```json
    {
      "name": "no_reasoning_model_title",
      "value": "暂无可用推理模型"
    },
    {
      "name": "no_reasoning_model_hint",
      "value": "请到服务商设置中启用具有推理能力的模型"
    },
```

- [ ] **Step 3: Verify both JSON files parse**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "const a=require('./entry/src/main/resources/base/element/string.json'); const b=require('./entry/src/main/resources/zh_CN/element/string.json'); const aMatch=a.string.find(s=>s.name==='no_reasoning_model_title'); const bMatch=b.string.find(s=>s.name==='no_reasoning_model_title'); console.log('base:', aMatch.value, '| zh_CN:', bMatch.value);"
```

Expected output (key text):
```
base: No reasoning models available | zh_CN: 暂无可用推理模型
```

- [ ] **Step 4: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/resources/base/element/string.json \
        entry/src/main/resources/zh_CN/element/string.json
git commit -m "feat(reasoning-filter): add no_reasoning_model strings (zh + en)"
```

---

### Task 5: Wire `ChatModelSelectorSheetContent` to pass `reasoningOnly: true` + new empty state

**Files:**
- Modify: `entry/src/main/ets/components/chat/ChatModelSelectorSheetContent.ets:6-21` (add @Params)
- Modify: `entry/src/main/ets/components/chat/ChatModelSelectorSheetContent.ets:68-78` (thread props)

- [ ] **Step 1: Add `emptyTitle` and `emptyDescription` `@Param` to `ChatModelSelectorSheetContent`**

Open `entry/src/main/ets/components/chat/ChatModelSelectorSheetContent.ets`. Find the `@Param` block (lines 8-13) and add 2 new params right after `editingModel`:

**Before:**
```typescript
export struct ChatModelSelectorSheetContent {
  @Param providers: ModelProvider[] = []
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param activePanel: string = 'selector'
  @Param editingModel: ModelInfo | null = null
  @Event $editingModel: (value: ModelInfo | null) => void = (_value: ModelInfo | null) => {}
```

**After:**
```typescript
export struct ChatModelSelectorSheetContent {
  @Param providers: ModelProvider[] = []
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param activePanel: string = 'selector'
  @Param editingModel: ModelInfo | null = null
  @Param emptyTitle: string | Resource = ''
  @Param emptyDescription: string | Resource = ''
  @Event $editingModel: (value: ModelInfo | null) => void = (_value: ModelInfo | null) => {}
```

- [ ] **Step 2: Pass `reasoningOnly: true` + new empty state into `ModelSelectorContent`**

Find the `ModelSelectorContent({...})` call (line 68-78). Update it to add 3 props:

**Before:**
```typescript
        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onLongPressModel: (model: ModelInfo, provider: ModelProvider): void => {
            this.onStartEdit(model, provider)
          }
        })
```

**After:**
```typescript
        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          reasoningOnly: true,
          emptyTitle: this.emptyTitle,
          emptyDescription: this.emptyDescription,
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onLongPressModel: (model: ModelInfo, provider: ModelProvider): void => {
            this.onStartEdit(model, provider)
          }
        })
```

- [ ] **Step 3: Update `ChatPage.ModelSelectorSheetBuilder` to pass empty state strings**

Open `entry/src/main/ets/pages/ChatPage.ets` and find `ModelSelectorSheetBuilder` (line 3151). Add 2 new props to the `ChatModelSelectorSheetContent({...})` call:

**Before:**
```typescript
  @Builder
  ModelSelectorSheetBuilder() {
    ChatModelSelectorSheetContent({
      providers: this.providers,
      currentModelId: this.currentModelId,
      currentProviderId: this.currentProvider?.id ?? '',
      activePanel: this.modelSheetActivePanel,
      editingModel: this.editingModel!!,
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.handleModelSelect(providerId, modelId, modelName)
        this.isModelSelectorVisible = false
      },
      onStartEdit: (model: ModelInfo, provider: ModelProvider): void => {
        this.editingModel = model
        this.editingModelProvider = provider
        this.modelSheetActivePanel = 'edit'
      },
      onSaveEdit: async (draft: ModelInfoExtendedJson): Promise<void> => {
        await this.saveModelEdit(draft)
      },
      onCancelEdit: (): void => {
        this.modelSheetActivePanel = 'selector'
        this.editingModel = null
        this.editingModelProvider = null
      }
    })
  }
```

**After:**
```typescript
  @Builder
  ModelSelectorSheetBuilder() {
    ChatModelSelectorSheetContent({
      providers: this.providers,
      currentModelId: this.currentModelId,
      currentProviderId: this.currentProvider?.id ?? '',
      activePanel: this.modelSheetActivePanel,
      editingModel: this.editingModel!!,
      emptyTitle: $r('app.string.no_reasoning_model_title'),
      emptyDescription: $r('app.string.no_reasoning_model_hint'),
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.handleModelSelect(providerId, modelId, modelName)
        this.isModelSelectorVisible = false
      },
      onStartEdit: (model: ModelInfo, provider: ModelProvider): void => {
        this.editingModel = model
        this.editingModelProvider = provider
        this.modelSheetActivePanel = 'edit'
      },
      onSaveEdit: async (draft: ModelInfoExtendedJson): Promise<void> => {
        await this.saveModelEdit(draft)
      },
      onCancelEdit: (): void => {
        this.modelSheetActivePanel = 'selector'
        this.editingModel = null
        this.editingModelProvider = null
      }
    })
  }
```

- [ ] **Step 4: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/components/chat/ChatModelSelectorSheetContent.ets \
        entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(reasoning-filter): wire chat titlebar picker with reasoningOnly + new empty state"
```

---

### Task 6: Wire `DefaultModelSelectSheetContent` to pass `reasoningOnly: true` + new empty state

**Files:**
- Modify: `entry/src/main/ets/components/defaultmodel/DefaultModelSelectSheetContent.ets:59-81`

- [ ] **Step 1: Add `reasoningOnly: true` and replace empty state string keys**

Open `entry/src/main/ets/components/defaultmodel/DefaultModelSelectSheetContent.ets`. Find the `ModelSelectorContent({...})` call (line 59-81).

**Before:**
```typescript
        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          showEditEntry: false,
          showFavoriteActions: false,
          showFavoriteFilter: false,
          showClearSelectionOption: true,
          clearSelectionText: $r('app.string.default_model_clear_selection'),
          searchPlaceholder: $r('app.string.filter_models_placeholder'),
          includeModelIdInSearch: true,
          emptyStateMode: 'default',
          hasOutputModeFilter: this.hasOutputModeFilter,
          outputModeFilter: this.outputModeFilter,
          emptyTitle: this.emptyTitle,
          emptyDescription: this.emptyDescription,
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onClearSelection: () => {
            this.onClearSelection()
          }
        })
```

**After:**
```typescript
        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          showEditEntry: false,
          showFavoriteActions: false,
          showFavoriteFilter: false,
          showClearSelectionOption: true,
          clearSelectionText: $r('app.string.default_model_clear_selection'),
          searchPlaceholder: $r('app.string.filter_models_placeholder'),
          includeModelIdInSearch: true,
          emptyStateMode: 'default',
          hasOutputModeFilter: this.hasOutputModeFilter,
          outputModeFilter: this.outputModeFilter,
          reasoningOnly: true,
          emptyTitle: $r('app.string.no_reasoning_model_title'),
          emptyDescription: $r('app.string.no_reasoning_model_hint'),
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onClearSelection: () => {
            this.onClearSelection()
          }
        })
```

Note: this **changes the existing behavior** — `emptyTitle: this.emptyTitle` (which was a parent prop forwarded) is replaced with the new hardcoded reasoning-empty state. Per spec §4.4, all 3 chat-related selectors share the same empty state.

- [ ] **Step 2: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/components/defaultmodel/DefaultModelSelectSheetContent.ets
git commit -m "feat(reasoning-filter): wire default model picker with reasoningOnly + new empty state"
```

---

### Task 7: Wire `AssistantModelSheetBuilder` in `Index.ets` with `reasoningOnly: true` + new empty state

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets:4303-4320` (`AssistantModelSheetBuilder`)

- [ ] **Step 1: Add `reasoningOnly: true` and new empty state to `ModelSelectorContent` call**

Open `entry/src/main/ets/pages/Index.ets` and find `AssistantModelSheetBuilder` (line 4303-4320).

**Before:**
```typescript
  @Builder
  private AssistantModelSheetBuilder() {
    Column() {
      ModelSelectorContent({
        currentModelId: this.assistantFormDefaultModelId,
        currentProviderId: this.assistantFormDefaultProviderId,
        providers: this.assistantProviders,
        showEditEntry: false,
        showFavoriteActions: false,
        showFavoriteFilter: false,
        showClearSelectionOption: true,
        clearSelectionText: $r('app.string.assistant_model_follow_global'),
        emptyStateMode: 'settings',
        onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
          this.selectAssistantDefaultModel(providerId, modelId, modelName)
        },
        onClearSelection: (): void => {
          this.clearAssistantDefaultModel()
          this.showAssistantModelSheet = false
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
```

**After:**
```typescript
  @Builder
  private AssistantModelSheetBuilder() {
    Column() {
      ModelSelectorContent({
        currentModelId: this.assistantFormDefaultModelId,
        currentProviderId: this.assistantFormDefaultProviderId,
        providers: this.assistantProviders,
        showEditEntry: false,
        showFavoriteActions: false,
        showFavoriteFilter: false,
        showClearSelectionOption: true,
        clearSelectionText: $r('app.string.assistant_model_follow_global'),
        emptyStateMode: 'settings',
        reasoningOnly: true,
        emptyTitle: $r('app.string.no_reasoning_model_title'),
        emptyDescription: $r('app.string.no_reasoning_model_hint'),
        onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
          this.selectAssistantDefaultModel(providerId, modelId, modelName)
        },
        onClearSelection: (): void => {
          this.clearAssistantDefaultModel()
          this.showAssistantModelSheet = false
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
```

- [ ] **Step 2: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/pages/Index.ets
git commit -m "feat(reasoning-filter): wire assistant model picker with reasoningOnly + new empty state"
```

---

### Task 8: Add `selectFirstReasoningModel` to `ChatPage` and refactor `validateAndSetCurrentModel`

**Files:**
- Modify: `entry/src/main/ets/pages/ChatPage.ets:1-30` (add import for `filterReasoningModels`)
- Modify: `entry/src/main/ets/pages/ChatPage.ets:2003-2023` (refactor `validateAndSetCurrentModel`)
- Modify: `entry/src/main/ets/pages/ChatPage.ets:2026-2070` (add `selectFirstReasoningModel`)

- [ ] **Step 1: Add import for `filterReasoningModels`**

Open `entry/src/main/ets/pages/ChatPage.ets` and find the import block near the top. The current import for `getEffectiveCapabilities` is at line 66:

```typescript
import { getEffectiveCapabilities } from '../utils/ModelCapabilityDeriver'
```

Add the new import adjacent to it (alphabetical or logical grouping is fine; place after the existing one):

**Before:**
```typescript
import { getEffectiveCapabilities } from '../utils/ModelCapabilityDeriver'
```

**After:**
```typescript
import { getEffectiveCapabilities } from '../utils/ModelCapabilityDeriver'
import { filterReasoningModels } from '../utils/ReasoningModelFilter'
```

- [ ] **Step 2: Refactor `validateAndSetCurrentModel` to validate reasoning on session/saved hits**

Find `validateAndSetCurrentModel` (line 2003) and replace its body:

**Before:**
```typescript
  private async validateAndSetCurrentModel(): Promise<void> {
    const currentSession = this.chatViewModel.getCurrentSession()
    if (currentSession !== null && currentSession.id === this.sessionId) {
      const sessionSelection = this.findEnabledProviderModelSelection(currentSession.providerId, currentSession.modelId)
      if (sessionSelection !== null) {
        await this.applyModelSelection(sessionSelection.provider, sessionSelection.model, '', !this.isNewEmptySession)
        return
      }
    }

    const savedSelection = this.findEnabledProviderModelSelection(
      this.appStateManager.getCurrentProviderId(),
      this.appStateManager.getCurrentModelId()
    )
    if (savedSelection !== null) {
      await this.applyModelSelection(savedSelection.provider, savedSelection.model)
      return
    }

    await this.selectFirstAvailableModel()
  }
```

**After:**
```typescript
  private async validateAndSetCurrentModel(): Promise<void> {
    const currentSession = this.chatViewModel.getCurrentSession()
    if (currentSession !== null && currentSession.id === this.sessionId) {
      const sessionSelection = this.findEnabledProviderModelSelection(currentSession.providerId, currentSession.modelId)
      if (sessionSelection !== null) {
        if (getEffectiveCapabilities(sessionSelection.model).supportsReasoning) {
          await this.applyModelSelection(sessionSelection.provider, sessionSelection.model, '', !this.isNewEmptySession)
          return
        }
        // session 模型无推理能力 → 落到 saved 校验
      }
    }

    const savedSelection = this.findEnabledProviderModelSelection(
      this.appStateManager.getCurrentProviderId(),
      this.appStateManager.getCurrentModelId()
    )
    if (savedSelection !== null) {
      if (getEffectiveCapabilities(savedSelection.model).supportsReasoning) {
        await this.applyModelSelection(savedSelection.provider, savedSelection.model)
        return
      }
      // saved 也无推理能力 → 落到 selectFirstAvailableModel
    }

    await this.selectFirstAvailableModel()
  }
```

- [ ] **Step 3: Insert reasoning-first branch at top of `selectFirstAvailableModel`**

Find `selectFirstAvailableModel` (line 2026). Insert the new branch at the very top, before any existing logic:

**Before:**
```typescript
  private async selectFirstAvailableModel(): Promise<void> {
    // 先尝试使用默认聊天模型配置
    await this.defaultModelService.initialize()
    const defaultChatModel = this.defaultModelService.getModel(ModelRole.CHAT)
```

**After:**
```typescript
  private async selectFirstAvailableModel(): Promise<void> {
    // 优先选第一个有推理能力的模型 (auto-switch from non-reasoning current model)
    const switched = await this.selectFirstReasoningModel()
    if (switched) {
      return
    }

    // 先尝试使用默认聊天模型配置
    await this.defaultModelService.initialize()
    const defaultChatModel = this.defaultModelService.getModel(ModelRole.CHAT)
```

- [ ] **Step 4: Add new private method `selectFirstReasoningModel` immediately after `selectFirstAvailableModel`**

Find the closing brace of `selectFirstAvailableModel` (around line 2070). Add the new method right after:

**After:**
```typescript
  // 选第一个有推理能力的模型。仅写 session, 不动全局 currentModelId
  private async selectFirstReasoningModel(): Promise<boolean> {
    const found = filterReasoningModels(this.providers)
    if (found === null) {
      return false
    }
    await this.applyModelSelection(found.provider, found.reasoningModel, '', false)
    console.info('ChatPage',
      `Auto-selected first reasoning model: ${found.reasoningModel.name} from ${found.provider.name}`)
    return true
  }
```

- [ ] **Step 5: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(reasoning-filter): auto-switch to first reasoning model in validateAndSetCurrentModel"
```

---

### Task 9: Build verification + manual smoke test

**Files:**
- Build: `hvigorw assembleHap` (CLI)
- Manual: visual + interaction in DevEco Studio

- [ ] **Step 1: Build the project to verify ArkTS strict-mode compile passes**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -50
```

Expected: build succeeds. Per MEMORY.md, the `code-linter` task is not available on CLI — `@CompileArkTS` strict mode is the real verification.

Look for any errors like:
- `arkts-no-untyped-obj-literals` (10605038) — should not appear (we use named interfaces)
- `arkts-no-obj-literals-as-types` (10605040) — should not appear
- `arkts-no-destruct-decls` (10605074) — should not appear
- Type errors in `applyModelSelection` call sites — should not appear (4th param is boolean, we pass `false`)

- [ ] **Step 2: Re-run the unit test in DevEco Studio**

Open `entry/src/ohosTest/ets/test/utils/ReasoningModelFilter.test.ets` in DevEco Studio, right-click → Run.

Expected: All 6 tests pass.

- [ ] **Step 3: Manual smoke test — chat titlebar picker**

In DevEco Studio simulator or device:

1. Open a chat session
2. Tap the model name in the title bar to open the picker
3. **Expected:** Only models with the reasoning capability icon visible (or fewer models than before)
4. **Expected:** The `lightbulb` / deep-thinking icon (which we use at `sys.symbol.AI_deep_thinking` per `ModelSelector.ets:407`) appears on every visible model

- [ ] **Step 4: Manual smoke test — empty state**

To force the empty state, temporarily disable all reasoning-capable models in providers (or use a fresh user with only non-reasoning models), then open the chat titlebar picker.

**Expected:** Empty state shows "暂无可用推理模型" / "请到服务商设置中启用具有推理能力的模型".

- [ ] **Step 5: Manual smoke test — auto-switch on enter**

In DevEco Studio simulator:

1. Configure a non-reasoning model as current (via default model settings or a saved session model)
2. Open the chat page
3. **Expected:** Console log "ChatPage Auto-selected first reasoning model: ..." (visible in HiLog)
4. **Expected:** Title bar shows a reasoning-capable model name
5. **Expected:** Global current model (DefaultModelPage) is **unchanged** — verify by going to settings, the default model is still your non-reasoning one

- [ ] **Step 6: Manual smoke test — image gen picker is unchanged**

Open the image generation feature, open its model picker.

**Expected:** All image-capable models are still listed (not filtered by reasoning). Behavior is identical to before this change.

- [ ] **Step 7: Manual smoke test — default model settings**

Open Settings → Default Model. Open the chat model picker.

**Expected:** Only reasoning-capable models listed.

- [ ] **Step 8: Manual smoke test — assistant default model**

In any assistant configuration, open the default model picker.

**Expected:** Only reasoning-capable models listed. Selecting one updates the assistant's default. Selecting does NOT trigger any auto-switch (no console log).

- [ ] **Step 9: Manual smoke test — assistant model in DB stays untouched**

In an assistant's stored config that already has a non-reasoning modelId (e.g., from a previous install), the assistant's stored modelId is preserved (not auto-cleared by the new code path). The auto-switch only happens at chat-page entry time.

Verify by: setting a non-reasoning modelId on an assistant (via DB inspection or pre-existing data), opening that assistant, then re-opening the assistant config — modelId should still be the non-reasoning one.

- [ ] **Step 10: Final commit (if any uncommitted changes)**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git status
```

If clean, skip. Otherwise commit any remaining changes (e.g., debug logs, scratch fixes):

```bash
git add -A
git commit -m "chore(reasoning-filter): post-smoke-test fixes"
```

---

## Verification Checklist (cross-reference to spec §9)

- [ ] 3 of 4 `ModelSelectorContent` callers pass `reasoningOnly: true`; image gen does not
- [ ] `buildModelSelectorRowsInternal` inserts reasoning filter at the right position (after outputModeFilter)
- [ ] `validateAndSetCurrentModel` validates reasoning on session and saved hits
- [ ] `selectFirstReasoningModel` uses `filterReasoningModels` util
- [ ] Auto-switch `applyModelSelection` 4th arg is `false`
- [ ] `appStateManager.setCurrentModel` is **not** triggered on auto-switch
- [ ] 2 new string resources present in base + zh_CN
- [ ] 6 unit tests in `ReasoningModelFilter.test.ets` pass
- [ ] `hvigorw assembleHap` clean
- [ ] Manual smoke tests (Steps 3-9) all pass
