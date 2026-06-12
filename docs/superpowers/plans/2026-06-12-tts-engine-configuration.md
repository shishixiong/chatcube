# TTS Engine Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded `TTS_ENGINE` constant with a user-selectable TTS engine in `DefaultModelPage`, using a registry-based architecture that makes adding new TTS providers an O(1) change.

**Architecture:** Bottom-up TDD. Pure-function `evaluateTtsEngineAvailability` first (testable in isolation), then in-memory `TtsEngineRegistry` (TDD), then persistence layer (`AppSettingsStore`), then service refactor (`TTSService` subscribes to `ttsEngineVersion`), then UI (`DefaultModelPage` 5th section + picker sheet), then registration wiring in `EntryAbility`.

**Tech Stack:** ArkTS @ComponentV2, `@kit.CoreSpeechKit` textToSpeech, existing `AppSettingsStore` + `AppStorageV2` patterns, `@ohos/hypium` + `@ohos/hamock` for unit tests.

**Spec:** `docs/superpowers/specs/2026-06-12-tts-engine-configuration-design.md`

---

## File Structure

**New files (6):**
- `entry/src/main/ets/models/TtsEngineProfile.ets` — `TtsEngineProfile` / `TtsEngineRegistration` / `TtsEngineAvailability` interfaces
- `entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets` — pure function `evaluateTtsEngineAvailability`
- `entry/src/main/ets/services/registry/TtsEngineRegistry.ets` — module-level registry with `register` / `list` / `resolve` / `getFallbackTtsEngineId`
- `entry/src/main/ets/components/defaultmodel/TtsEnginePickerSheetContent.ets` — picker sheet UI
- `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets` — 5 unit tests
- `entry/src/ohosTest/ets/test/registry/TtsEngineRegistry.test.ets` — 4 unit tests

**Modified files (7):**
- `entry/src/main/ets/config/TtsConfig.ets` — delete `TTS_ENGINE` + `TtsEngineType`, add `TtsEngineId` / `TTS_FALLBACK_ENGINE_ID` / `MIMO_TTS_PROVIDER_ID`
- `entry/src/main/ets/state/AppSettingsState.ets` — add `@Trace ttsEngineId` / `ttsEngineInitialized` / `ttsEngineVersion` + path switch cases
- `entry/src/main/ets/state/AppSettingsStore.ets` — add `ensureTtsEngineInitialized` / `getTtsEngineId` / `setTtsEngineId` + `TTS_ENGINE_ID_KEY`
- `entry/src/main/ets/services/DefaultModelService.ets` — add `getTtsEngineId` / `setTtsEngineId` facade
- `entry/src/main/ets/services/TTSService.ets` — drop hardcoded engines + `switchEngine`, add `resolveAndBindEngine` + store subscription
- `entry/src/main/ets/pages/DefaultModelPage.ets` — add TtsEngineSection + sheet binding
- `entryability/EntryAbility.ets` — call `registerTtsEngine` for system + mimo before `TTSService.init`

**Resource files (2):**
- `entry/src/main/resources/zh_CN/element/string.json` — 6 new strings
- `entry/src/main/resources/en_US/element/string.json` — 6 new strings

---

### Task 1: Create TtsEngineProfile model and pure availability utility

**Files:**
- Create: `entry/src/main/ets/models/TtsEngineProfile.ets`
- Create: `entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets`
- Create: `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`

- [ ] **Step 1: Create the model file**

Write `entry/src/main/ets/models/TtsEngineProfile.ets`:

```typescript
// TTS 引擎的元数据, 用于 TtsEngineRegistry 和 UI 列表
export interface TtsEngineProfile {
  id: string                    // 'system' | 'mimo' | 未来 'elevenlabs' ...
  displayName: string           // '系统朗读' / 'MiMo 语音'
  description: string           // 长描述, 1-2 句
  requiresApiKey: boolean       // 标识是否需要外部 API key
  iconSymbol: string            // sys.symbol.* 名称
}

// 运行时注册的完整条目, profile + 工厂闭包
// factory 不接受 context: 引擎的 init() 由 TTSService 显式调用, 这样 registry
// 不依赖全局 context, 也避免 TtsEngineRegistration 在不同注册时机拿不到 context
export interface TtsEngineRegistration {
  profile: TtsEngineProfile
  factory: () => ITtsEngine
}

// 引擎当前是否在当前环境下可用 (例如 mimo 缺 api key 时 isEnabled: false)
export interface TtsEngineAvailability {
  profile: TtsEngineProfile
  isEnabled: boolean
  unavailableReason: string    // 空串 = 可用; 非空 = 原因
}
```

> Note: `ITtsEngine` import is intentionally omitted from this snippet. The compiler
> will require an import. Use: `import { ITtsEngine } from '../services/tts/ITtsEngine'`
> at the top of the file when writing.

- [ ] **Step 2: Add the missing import for ITtsEngine**

The TtsEngineRegistration.factory references `ITtsEngine` which must be imported. Update
the top of `entry/src/main/ets/models/TtsEngineProfile.ets` to add:

```typescript
import { ITtsEngine } from '../services/tts/ITtsEngine'
```

- [ ] **Step 3: Create the pure utility file**

Write `entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets`:

```typescript
import { TtsEngineProfile, TtsEngineAvailability } from '../models/TtsEngineProfile'
import { ModelProvider } from '../models/ChatModels'
import { MIMO_TTS_PROVIDER_ID } from '../config/TtsConfig'

// 纯函数: 给一个 profile + 当前 providers, 评估运行时可用性
export function evaluateTtsEngineAvailability(
  profile: TtsEngineProfile,
  providers: ModelProvider[]
): TtsEngineAvailability {
  if (!profile.requiresApiKey) {
    return { profile, isEnabled: true, unavailableReason: '' }
  }

  // 当前唯一需要 key 的引擎是 mimo, 复用 MiniMax provider
  // 未来若需绑其他 provider, 在这里加 case
  if (profile.id === 'mimo') {
    const matched = providers.find(
      (p) => p.id === MIMO_TTS_PROVIDER_ID && p.apiKey !== ''
    )
    if (matched === undefined) {
      return {
        profile,
        isEnabled: false,
        unavailableReason: '未配置 MiniMax API Key, 不可用'
      }
    }
  }

  return { profile, isEnabled: true, unavailableReason: '' }
}
```

- [ ] **Step 4: Write the failing test**

Write `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { evaluateTtsEngineAvailability } from '../../../../main/ets/utils/TtsEngineAvailabilityUtils'
import { TtsEngineProfile } from '../../../../main/ets/models/TtsEngineProfile'
import { ModelProvider, ProviderType, ApiStyle } from '../../../../main/ets/models/ChatModels'

const systemProfile: TtsEngineProfile = {
  id: 'system',
  displayName: '系统朗读',
  description: '...',
  requiresApiKey: false,
  iconSymbol: 'sys.symbol.speaker_wave_2_fill'
}
const mimoProfile: TtsEngineProfile = {
  id: 'mimo',
  displayName: 'MiMo 语音',
  description: '...',
  requiresApiKey: true,
  iconSymbol: 'sys.symbol.waveform'
}

function makeProvider(id: string, apiKey: string): ModelProvider {
  const p = new ModelProvider(id, id, ProviderType.CUSTOM, '', $r('app.color.text_primary'))
  p.apiKey = apiKey
  return p
}

export default function ttsEngineAvailabilityTest() {
  describe('evaluateTtsEngineAvailability', () => {
    it('system engine is always enabled', 0, () => {
      const result = evaluateTtsEngineAvailability(systemProfile, [])
      expect(result.isEnabled).assertTrue()
      expect(result.unavailableReason).assertEqual('')
    })

    it('mimo is disabled when no providers configured', 0, () => {
      const result = evaluateTtsEngineAvailability(mimoProfile, [])
      expect(result.isEnabled).assertFalse()
      expect(result.unavailableReason).assertContain('MiniMax')
    })

    it('mimo is disabled when MiniMax exists but no apiKey', 0, () => {
      const result = evaluateTtsEngineAvailability(mimoProfile, [makeProvider('minimax', '')])
      expect(result.isEnabled).assertFalse()
    })

    it('mimo is enabled when MiniMax has apiKey', 0, () => {
      const result = evaluateTtsEngineAvailability(mimoProfile, [makeProvider('minimax', 'sk-xxx')])
      expect(result.isEnabled).assertTrue()
      expect(result.unavailableReason).assertEqual('')
    })

    it('mimo is disabled when only other providers have apiKey', 0, () => {
      const result = evaluateTtsEngineAvailability(
        mimoProfile, [makeProvider('openai', 'sk-ooo')]
      )
      expect(result.isEnabled).assertFalse()
    })
  })
}
```

- [ ] **Step 5: Run the test to verify it compiles (it should fail or pass — TDD requires the impl exists first)**

The implementation was created in Step 3, so the test should pass. Run:

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw test \
  --mode module -p product=default \
  --test-class entry.ohosTest.ets.test.utils.TtsEngineAvailability.test.ets 2>&1 | tail -20
```

Expected: 5 tests pass. (If tests are not runnable individually, run the full
`hvigorw test --mode module` and grep for `ttsEngineAvailabilityTest` in the output.)

- [ ] **Step 6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add \
  entry/src/main/ets/models/TtsEngineProfile.ets \
  entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets \
  entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets
git commit -m "feat(tts): add TtsEngineProfile model + pure availability utility"
```

---

### Task 2: Add ttsEngineId fields to AppSettingsState

**Files:**
- Modify: `entry/src/main/ets/state/AppSettingsState.ets`

- [ ] **Step 1: Add the three @Trace fields**

In `entry/src/main/ets/state/AppSettingsState.ets`, after the `defaultModels*` block
(line 35-36 in the current file) and before the `===== 生成类 Prompt 模板` block, add:

```typescript
  // ===== TTS 引擎配置 =====
  @Trace ttsEngineId: string = ''           // 空串 = 未配置, TTSService 解析时按 'system' 兜底
  @Trace ttsEngineInitialized: boolean = false
  @Trace ttsEngineVersion: number = 0
```

- [ ] **Step 2: Add the path resolver cases**

In the same file, in `resolveAppSettingsStatePath`, add 3 cases to the `switch` statement
(after the `defaultModelsVersion` case around line 89, before `titlePromptTemplate`):

```typescript
    case 'ttsEngineId':
      return 'ttsEngineId'
    case 'ttsEngineInitialized':
      return 'ttsEngineInitialized'
    case 'ttsEngineVersion':
      return 'ttsEngineVersion'
```

- [ ] **Step 3: Verify build compiles**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/state/AppSettingsState.ets
git commit -m "feat(state): add ttsEngineId @Trace fields to AppSettingsState"
```

---

### Task 3: Add TTS persistence methods to AppSettingsStore

**Files:**
- Modify: `entry/src/main/ets/state/AppSettingsStore.ets`

- [ ] **Step 1: Find the existing `ensureDefaultModelsInitialized` to mirror its idempotency pattern**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -n "ensureDefaultModelsInitialized\|defaultModelsInitPromise" \
  entry/src/main/ets/state/AppSettingsStore.ets
```

Expected: 2-3 hits. Note the field name pattern (e.g., `defaultModelsInitPromise`).

- [ ] **Step 2: Add the persistence key constant**

At the top of `entry/src/main/ets/state/AppSettingsStore.ets` (or near other key constants
if they exist there), add:

```typescript
const TTS_ENGINE_ID_KEY = 'tts_engine_id'
```

- [ ] **Step 3: Add the `ttsEngineInitPromise` private field**

In the `AppSettingsStore` class, near the other `*InitPromise` fields (e.g., the one
discovered in Step 1), add:

```typescript
  private ttsEngineInitPromise: Promise<void> | null = null
```

- [ ] **Step 4: Add the three new methods**

Place the new methods in the same class, after the `setDefaultModel` method block.
Add a new section:

```typescript
  // ============================================================================
  // TTS 引擎配置
  // ============================================================================

  async ensureTtsEngineInitialized(): Promise<void> {
    if (getAppSettingsState().ttsEngineInitialized) {
      return
    }
    if (this.ttsEngineInitPromise !== null) {
      await this.ttsEngineInitPromise
      return
    }
    this.ttsEngineInitPromise = (async (): Promise<void> => {
      const stored = await this.preferences.getString(TTS_ENGINE_ID_KEY, '')
      const s = getAppSettingsState()
      s.ttsEngineId = stored !== ''
        ? stored
        : (await import('../config/TtsConfig')).TTS_FALLBACK_ENGINE_ID
      s.ttsEngineInitialized = true
      s.ttsEngineVersion++
    })()
    await this.ttsEngineInitPromise
    this.ttsEngineInitPromise = null
  }

  getTtsEngineId(): string {
    return getAppSettingsState().ttsEngineId
  }

  async setTtsEngineId(id: string): Promise<void> {
    await this.preferences.setString(TTS_ENGINE_ID_KEY, id)
    const s = getAppSettingsState()
    s.ttsEngineId = id
    s.ttsEngineVersion++
  }
```

> Note: `TTS_FALLBACK_ENGINE_ID` is imported dynamically here because it's defined
> in a later task (Task 4). If implementing in order, the `import` statement at the
> top of `AppSettingsStore.ets` may not have it yet. Using `await import()` keeps
> this task self-contained. After Task 4 adds the static export, you may refactor
> this back to a top-level import.

- [ ] **Step 5: Verify build**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/state/AppSettingsStore.ets
git commit -m "feat(state): add tts engine persistence to AppSettingsStore"
```

---

### Task 4: Refactor TtsConfig.ets — drop TTS_ENGINE, add new constants

**Files:**
- Modify: `entry/src/main/ets/config/TtsConfig.ets`

- [ ] **Step 1: Replace the entire file content**

Write the new content of `entry/src/main/ets/config/TtsConfig.ets`:

```typescript
// TTS 引擎 ID 联合, 与 TtsEngineRegistry 共享
export type TtsEngineId = 'system' | 'mimo'

// 注册表都 miss 时的 fallback 引擎
export const TTS_FALLBACK_ENGINE_ID: TtsEngineId = 'system'

// mimo 引擎绑定的 provider id (用于 evaluateTtsEngineAvailability 查 api key)
export const MIMO_TTS_PROVIDER_ID: string = 'minimax'

// MiMo 流式 TTS 配置（Chat Completions 格式）
interface MiMoTtsConfig {
  apiUrl: string
  model: string
  voice: string
  audioFormat: string
}

export const MIMO_TTS_CONFIG: MiMoTtsConfig = {
  apiUrl: 'https://api.xiaomimimo.com/v1/chat/completions',
  model: 'mimo-v2.5-tts',
  voice: '冰糖',
  audioFormat: 'mp3'
}
```

- [ ] **Step 2: Verify no other file still references the old `TTS_ENGINE` / `TtsEngineType` exports**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -rn "TTS_ENGINE\|TtsEngineType" entry/src/main/ets 2>&1
```

Expected output should show **only** references in `TTSService.ets` (which will be
fixed in Task 7). If anything else shows up, do not proceed — investigate.

- [ ] **Step 3: Verify build (compile errors expected; TTSService.ets still imports old symbols)**

This step intentionally produces compile errors. The errors are in `TTSService.ets`
and will be fixed in Task 7. Continue.

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -20
```

Expected: `BUILD FAILED` with errors mentioning `TTSService.ets`. This is OK.

- [ ] **Step 4: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/config/TtsConfig.ets
git commit -m "refactor(tts-config): drop TTS_ENGINE constant, add engine id + provider id exports"
```

---

### Task 5: Create TtsEngineRegistry module

**Files:**
- Create: `entry/src/main/ets/services/registry/TtsEngineRegistry.ets`
- Create: `entry/src/ohosTest/ets/test/registry/TtsEngineRegistry.test.ets`

- [ ] **Step 1: Write the registry file**

Write `entry/src/main/ets/services/registry/TtsEngineRegistry.ets`:

```typescript
import { ITtsEngine } from '../tts/ITtsEngine'
import {
  TtsEngineRegistration,
  TtsEngineAvailability
} from '../../models/TtsEngineProfile'
import { evaluateTtsEngineAvailability } from '../../utils/TtsEngineAvailabilityUtils'
import { getAppSettingsState } from '../../state/AppSettingsState'
import { TTS_FALLBACK_ENGINE_ID } from '../../config/TtsConfig'

// ============ 注册表状态 ============
const REGISTRATIONS: Map<string, TtsEngineRegistration> = new Map()

// ============ 注册 API ============
export function registerTtsEngine(registration: TtsEngineRegistration): void {
  if (REGISTRATIONS.has(registration.profile.id)) {
    console.warn('TtsEngineRegistry',
      `engine '${registration.profile.id}' already registered, overwriting`)
  }
  REGISTRATIONS.set(registration.profile.id, registration)
}

// ============ 查询 API ============

// 列出所有已注册引擎, 附带运行时可用性
export function listTtsEngines(): TtsEngineAvailability[] {
  const result: TtsEngineAvailability[] = []
  const providers = getAppSettingsState().providers
  REGISTRATIONS.forEach((reg) => {
    result.push(evaluateTtsEngineAvailability(reg.profile, providers))
  })
  return result
}

// 按 id 取一个引擎实例, 不存在或工厂抛错时返回 null
export function resolveTtsEngine(id: string): ITtsEngine | null {
  const reg = REGISTRATIONS.get(id)
  if (reg === undefined) {
    return null
  }
  try {
    return reg.factory()
  } catch (err) {
    console.error('TtsEngineRegistry',
      `factory for '${id}' threw: ${JSON.stringify(err)}`)
    return null
  }
}

// 仅用于 TTSService 的 fallback 链
export function getFallbackTtsEngineId(): string {
  return REGISTRATIONS.has(TTS_FALLBACK_ENGINE_ID) ? TTS_FALLBACK_ENGINE_ID : ''
}
```

- [ ] **Step 2: Write the failing test (test will fail to compile until TtsEngineRegistration in model is correct — it already is from Task 1)**

Write `entry/src/ohosTest/ets/test/registry/TtsEngineRegistry.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium'
import {
  registerTtsEngine,
  listTtsEngines,
  resolveTtsEngine,
  getFallbackTtsEngineId
} from '../../../../main/ets/services/registry/TtsEngineRegistry'
import { ITtsEngine } from '../../../../main/ets/services/tts/ITtsEngine'

class StubEngine implements ITtsEngine {
  init(_context: any): Promise<void> { return Promise.resolve() }
  speak(_text: string, _callback: any): Promise<void> { return Promise.resolve() }
  stop(): void {}
  isSpeaking(): boolean { return false }
  destroy(): void {}
}

function makeRegistration(id: string, displayName: string) {
  return {
    profile: {
      id,
      displayName,
      description: '...',
      requiresApiKey: false,
      iconSymbol: 'sys.symbol.speaker_wave_2_fill'
    },
    factory: (): ITtsEngine => new StubEngine()
  }
}

export default function ttsEngineRegistryTest() {
  describe('TtsEngineRegistry', () => {
    it('resolve returns null for unknown id', 0, () => {
      const engine = resolveTtsEngine('does-not-exist-xyz')
      expect(engine === null).assertTrue()
    })

    it('register + resolve returns factory output', 0, () => {
      registerTtsEngine(makeRegistration('stub-a', 'Stub A'))
      const engine = resolveTtsEngine('stub-a')
      expect(engine !== null).assertTrue()
    })

    it('register overwrites duplicate id', 0, () => {
      registerTtsEngine(makeRegistration('dup', 'First'))
      registerTtsEngine(makeRegistration('dup', 'Second'))
      const list = listTtsEngines()
      const dupMatches = list.filter((e) => e.profile.id === 'dup')
      expect(dupMatches.length).assertEqual(1)
      expect(dupMatches[0].profile.displayName).assertEqual('Second')
    })

    it('getFallbackTtsEngineId returns "system" when system registered', 0, () => {
      registerTtsEngine(makeRegistration('system', 'System'))
      expect(getFallbackTtsEngineId()).assertEqual('system')
    })
  })
}
```

- [ ] **Step 3: Run the test**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw test \
  --mode module -p product=default 2>&1 | tail -30
```

Expected: 4 tests pass for `TtsEngineRegistry`.

If your harness doesn't surface the test results easily, run the full assembleHap
to confirm the test file at least compiles:

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL` (TTSService.ets still broken from Task 4, but the
test file uses the registry directly, not TTSService).

- [ ] **Step 4: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add \
  entry/src/main/ets/services/registry/TtsEngineRegistry.ets \
  entry/src/ohosTest/ets/test/registry/TtsEngineRegistry.test.ets
git commit -m "feat(tts): add TtsEngineRegistry with register/list/resolve + unit tests"
```

---

### Task 6: Add TTS facade methods to DefaultModelService

**Files:**
- Modify: `entry/src/main/ets/services/DefaultModelService.ets`

- [ ] **Step 1: Add the two facade methods**

In `entry/src/main/ets/services/DefaultModelService.ets`, add a new section after
the `setModel` method (around line 53) and before the "纯派生 Prompt" section:

```typescript
  // ============================================================================
  // TTS 引擎配置（委托 Store）
  // ============================================================================

  getTtsEngineId(): string {
    return this.store.getTtsEngineId()
  }

  async setTtsEngineId(id: string): Promise<void> {
    await this.store.setTtsEngineId(id)
  }
```

- [ ] **Step 2: Verify build (still expected to fail because of TTSService.ets)**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
```

Expected: `BUILD FAILED` (TTSService.ets still broken). Continue.

- [ ] **Step 3: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/services/DefaultModelService.ets
git commit -m "feat(service): add getTtsEngineId/setTtsEngineId facade to DefaultModelService"
```

---

### Task 7: Refactor TTSService to use registry + store

**Files:**
- Modify: `entry/src/main/ets/services/TTSService.ets`

- [ ] **Step 1: Read the current TTSService.ets to know exact line content for the Edit**

Open `entry/src/main/ets/services/TTSService.ets` and verify the imports and class
structure match what you'll replace.

- [ ] **Step 2: Replace the imports block (top of file)**

Replace the existing imports:

```typescript
import { common } from '@kit.AbilityKit'
import { ITtsEngine, TTSCallback } from './tts/ITtsEngine'
import { SystemTtsEngine } from './tts/SystemTtsEngine'
import { MiMoTtsEngine } from './tts/MiMoTtsEngine'
import { TTS_ENGINE, TtsEngineType } from '../config/TtsConfig'
import { getAppSettingsState } from '../state/AppSettingsState'
import { ModelProvider } from '../models/ChatModels'
```

With:

```typescript
import { common } from '@kit.AbilityKit'
import { ITtsEngine, TTSCallback } from './tts/ITtsEngine'
import {
  resolveTtsEngine,
  getFallbackTtsEngineId
} from './registry/TtsEngineRegistry'
import { TtsEngineId, TTS_FALLBACK_ENGINE_ID } from '../config/TtsConfig'
import { getAppSettingsStore } from '../state/AppSettingsStore'
import { observeAppSettingsState } from '../state/AppSettingsState'
```

- [ ] **Step 3: Replace the class body**

Replace the class body (the entire `export class TTSService { ... }`) with:

```typescript
export class TTSService {
  private currentEngine: ITtsEngine | null = null
  private currentEngineId: TtsEngineId = TTS_FALLBACK_ENGINE_ID
  private initContext: common.Context | null = null
  private unsubscribe: (() => void) | null = null

  async init(context: common.Context): Promise<void> {
    this.initContext = context
    this.resolveAndBindEngine(getAppSettingsStore().getTtsEngineId())

    this.unsubscribe = observeAppSettingsState('ttsEngineVersion', () => {
      this.resolveAndBindEngine(getAppSettingsStore().getTtsEngineId())
    })
    console.info('TTSService', `init done, current engine: ${this.currentEngineId}`)
  }

  async speak(text: string, callback: TTSCallback): Promise<void> {
    const processedText = this.preprocessTextForTTS(text)
    if (processedText === '') {
      callback.onError('没有可朗读的内容')
      return
    }
    if (this.currentEngine === null) {
      callback.onError('朗读服务未初始化')
      return
    }
    await this.currentEngine.speak(processedText, callback)
  }

  stop(): void {
    this.currentEngine?.stop()
  }

  isSpeaking(): boolean {
    return this.currentEngine !== null && this.currentEngine.isSpeaking()
  }

  getCurrentEngineId(): TtsEngineId {
    return this.currentEngineId
  }

  destroy(): void {
    this.currentEngine?.destroy()
    this.currentEngine = null
    this.unsubscribe?.()
    this.unsubscribe = null
    this.initContext = null
  }

  private resolveAndBindEngine(id: string): void {
    // 切换前: 如在朗读, 先停
    if (this.currentEngine !== null && this.currentEngine.isSpeaking()) {
      this.currentEngine.stop()
    }
    this.currentEngine?.destroy()

    const engine = resolveTtsEngine(id)
    if (engine !== null && this.initContext !== null) {
      try {
        engine.init(this.initContext)
        this.currentEngine = engine
        this.currentEngineId = id as TtsEngineId
        return
      } catch (err) {
        console.error('TTSService',
          `engine '${id}' init failed: ${JSON.stringify(err)}`)
      }
    }
    // fallback
    if (id !== TTS_FALLBACK_ENGINE_ID) {
      this.resolveAndBindEngine(TTS_FALLBACK_ENGINE_ID)
    } else {
      this.currentEngine = null
      this.currentEngineId = TTS_FALLBACK_ENGINE_ID
    }
  }

  // 文本预处理：移除代码块、清理Markdown符号等
  private preprocessTextForTTS(markdown: string): string {
    // 保留原 preprocessTextForTTS 实现, 与 master 完全一致
    if (markdown === '') {
      return ''
    }

    let text = markdown

    // 移除代码块（```code```）
    text = text.replace(/```[\s\S]*?```/g, '')

    // 移除行内代码（`code`）
    text = text.replace(/`[^`]*`/g, '')

    // 清理Markdown符号
    text = text.replace(/\*\*\*([^*]+)\*\*\*/g, '$1')  // ***bold italic***
    text = text.replace(/\*\*([^*]+)\*\*/g, '$1')     // **bold**
    text = text.replace(/\*([^*]+)\*/g, '$1')         // *italic*
    text = text.replace(/___([^_]+)___/g, '$1')      // ___bold italic___
    text = text.replace(/__([^_]+)__/g, '$1')        // __bold__
    text = text.replace(/_([^_]+)_/g, '$1')          // _italic_
    text = text.replace(/~~([^~]+)~~/g, '')          // ~~strikethrough~~

    // 清理标题符号
    text = text.replace(/^#{1,6}\s+/gm, '')

    // 清理引用符号
    text = text.replace(/^>\s+/gm, '')

    // 清理链接语法 [text](url) -> text
    text = text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')

    // 清理图片语法 ![alt](url)
    text = text.replace(/!\[[^\]]*\]\([^)]+\)/g, '')

    // 清理无序列表符号
    text = text.replace(/^[-*+]\s+/gm, '')

    // 清理有序列表符号
    text = text.replace(/^\d+\.\s+/gm, '')

    // 清理水平线
    text = text.replace(/^[-*_]{3,}\s*$/gm, '')

    // 清理LaTeX公式（简单处理）
    text = text.replace(/\$\$[\s\S]*?\$\$/g, '公式')
    text = text.replace(/\$[^$]*\$/g, '公式')

    // 清理多余空行
    text = text.replace(/\n{3,}/g, '\n\n')

    // 限制长度
    if (text.length > 50000) {
      text = text.substring(0, 50000) + '...'
    }

    return text.trim()
  }
}
```

> Note: `preprocessTextForTTS` is preserved verbatim from the original. To avoid
> duplication risk, this method is the same as in master — the engine does NOT
> need to change it. The snippet above is a verbatim copy of the original.

- [ ] **Step 4: Verify build compiles**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`. If `EntryAbility.ets` is calling
`getTTSService().switchEngine(...)` somewhere, that will break. Run:

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -rn "switchEngine\|getCurrentEngineType" entry/src 2>&1
```

Expected: no hits. If you find any, fix the caller to use
`DefaultModelService.setTtsEngineId(...)` instead.

- [ ] **Step 5: Verify the test suite still passes**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw test \
  --mode module -p product=default 2>&1 | tail -10
```

Expected: existing tests still pass (no regressions).

- [ ] **Step 6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/services/TTSService.ets
git commit -m "refactor(tts): replace hardcoded engines with TtsEngineRegistry + store subscription"
```

---

### Task 8: Add TTS string resources (zh_CN)

**Files:**
- Modify: `entry/src/main/resources/zh_CN/element/string.json`

- [ ] **Step 1: Locate the end of the string array**

The file is large. Find the closing `]` to know where to append.

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
tail -5 entry/src/main/resources/zh_CN/element/string.json
```

- [ ] **Step 2: Append 6 new strings before the closing `]`**

The last object in the array is followed by `]` and possibly a newline. Insert
6 new objects just before the closing `]`. Make sure to add a comma after the
last existing object if it doesn't have one.

Insert (before the closing `]`):

```json
    {
      "name": "tts_engine_section_title",
      "value": "TTS 朗读"
    },
    {
      "name": "tts_engine_role",
      "value": "语音朗读"
    },
    {
      "name": "tts_engine_desc",
      "value": "语音模式下自动朗读使用的引擎"
    },
    {
      "name": "tts_engine_select_title",
      "value": "选择 TTS 引擎"
    },
    {
      "name": "tts_engine_empty",
      "value": "暂无可用 TTS 引擎"
    },
    {
      "name": "tts_engine_unavailable_tag",
      "value": "不可用"
    }
```

- [ ] **Step 3: Validate JSON**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "JSON.parse(require('fs').readFileSync('entry/src/main/resources/zh_CN/element/string.json', 'utf-8'))" && echo OK
```

Expected: `OK` (silent exit, prints OK). If it errors, fix the JSON syntax.

- [ ] **Step 4: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/resources/zh_CN/element/string.json
git commit -m "feat(i18n): add 6 TTS engine strings (zh_CN)"
```

---

### Task 9: Add TTS string resources (en_US)

**Files:**
- Modify: `entry/src/main/resources/en_US/element/string.json`

- [ ] **Step 1: Verify the file exists and find the closing `]`**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
ls entry/src/main/resources/en_US/element/string.json && tail -5 entry/src/main/resources/en_US/element/string.json
```

- [ ] **Step 2: Append 6 new strings before the closing `]`**

Insert:

```json
    {
      "name": "tts_engine_section_title",
      "value": "TTS"
    },
    {
      "name": "tts_engine_role",
      "value": "Voice"
    },
    {
      "name": "tts_engine_desc",
      "value": "Engine used for voice-mode TTS"
    },
    {
      "name": "tts_engine_select_title",
      "value": "Select TTS Engine"
    },
    {
      "name": "tts_engine_empty",
      "value": "No TTS engines available"
    },
    {
      "name": "tts_engine_unavailable_tag",
      "value": "Unavailable"
    }
```

- [ ] **Step 3: Validate JSON**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "JSON.parse(require('fs').readFileSync('entry/src/main/resources/en_US/element/string.json', 'utf-8'))" && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/resources/en_US/element/string.json
git commit -m "feat(i18n): add 6 TTS engine strings (en_US)"
```

---

### Task 10: Create TtsEnginePickerSheetContent component

**Files:**
- Create: `entry/src/main/ets/components/defaultmodel/TtsEnginePickerSheetContent.ets`

- [ ] **Step 1: Create the component file**

Write `entry/src/main/ets/components/defaultmodel/TtsEnginePickerSheetContent.ets`:

```typescript
import { TtsEngineAvailability } from '../../models/TtsEngineProfile'
import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct TtsEnginePickerSheetContent {
  @Param currentEngineId: string = ''
  @Param engines: TtsEngineAvailability[] = []

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  @Event onSelectEngine: (id: string) => void = () => {}

  build() {
    Column() {
      // Header
      Row() {
        Text($r('app.string.tts_engine_select_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .height(56)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.engines.length === 0) {
        Text($r('app.string.tts_engine_empty'))
          .fontColor($r('app.color.text_tertiary'))
          .padding(16)
      }

      List() {
        ForEach(this.engines, (item: TtsEngineAvailability) => {
          ListItem() {
            this.EngineRow(item)
          }
        })
      }
      .listDirection(Axis.Vertical)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private EngineRow(item: TtsEngineAvailability) {
    Row() {
      SymbolGlyph($r(`sys.symbol.${item.profile.iconSymbol}`))
        .fontSize(24)
        .fontColor([item.isEnabled ? this.themePrimary : $r('app.color.text_tertiary')])
        .width(40)

      Column() {
        Row() {
          Text(item.profile.displayName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.isEnabled
              ? $r('app.color.text_primary')
              : $r('app.color.text_tertiary'))

          if (!item.isEnabled) {
            Text($r('app.string.tts_engine_unavailable_tag'))
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.text_tertiary'))
              .borderRadius(4)
              .padding({ left: 6, right: 6 })
              .margin({ left: 8 })
          }
        }

        Text(item.isEnabled
          ? item.profile.description
          : item.unavailableReason)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.profile.id === this.currentEngineId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(item.profile.id === this.currentEngineId
      ? getAppUiState().themeSurface
      : Color.Transparent)
    .enabled(item.isEnabled)
    .onClick(() => {
      if (item.isEnabled) {
        this.onSelectEngine(item.profile.id)
      }
    })
  }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/components/defaultmodel/TtsEnginePickerSheetContent.ets
git commit -m "feat(tts-ui): add TtsEnginePickerSheetContent component"
```

---

### Task 11: Integrate TtsEngineSection into DefaultModelPage

**Files:**
- Modify: `entry/src/main/ets/pages/DefaultModelPage.ets`

- [ ] **Step 1: Add new imports at the top of the file**

After the existing imports (after line 19, before `let defaultModelPagePathStack` on
line 21), add:

```typescript
import { listTtsEngines } from '../services/registry/TtsEngineRegistry'
import { TtsEngineAvailability } from '../models/TtsEngineProfile'
import { TtsEnginePickerSheetContent } from '../components/defaultmodel/TtsEnginePickerSheetContent'
```

- [ ] **Step 2: Add new @Local state fields**

After the `currentPrompt: string = ''` field (line 63), add:

```typescript
  @Local ttsEngineId: string = ''
  @Local ttsEngineOptions: TtsEngineAvailability[] = []
  @Local showTtsSheet: boolean = false
```

- [ ] **Step 3: Add new method `loadTtsEngine`**

After the `loadProviders` method (around line 120), add:

```typescript
  async loadTtsEngine(): Promise<void> {
    this.ttsEngineId = this.defaultModelService.getTtsEngineId()
    this.ttsEngineOptions = listTtsEngines()
    console.info(`[DefaultModelPage] Loaded TTS engine: ${this.ttsEngineId}`)
  }
```

- [ ] **Step 4: Call `loadTtsEngine` in `aboutToAppear`**

Modify the `aboutToAppear` method (around line 102) to also load TTS:

```typescript
  aboutToAppear(): void {
    this.loadConfig()
    this.loadProviders()
    this.loadTtsEngine()
  }
```

- [ ] **Step 5: Add the TtsEngineSection builder**

After the `TranslateModelSection` builder (around line 380), add:

```typescript
  @Builder
  TtsEngineSection() {
    Column() {
      this.SectionTitle($r('app.string.tts_engine_section_title'))
      ModelConfigCard({
        roleName: $r('app.string.tts_engine_role'),
        description: $r('app.string.tts_engine_desc'),
        showPromptEdit: false,
        isDefaultPrompt: true,
        isConfigured: this.ttsEngineId !== '',
        displayName: this.ttsEngineId !== '' ? this.getTtsEngineDisplayName() : '',
        onCardClick: () => {
          this.showModelSheet = false
          this.showPromptSheet = false
          this.showTtsSheet = true
        },
        onPromptClick: () => {}
      })
    }
    .width('100%')
  }

  private getTtsEngineDisplayName(): string {
    const hit = this.ttsEngineOptions.find((e) => e.profile.id === this.ttsEngineId)
    return hit !== undefined ? hit.profile.displayName : this.ttsEngineId
  }

  private async selectTtsEngine(id: string): Promise<void> {
    await this.defaultModelService.setTtsEngineId(id)
    this.ttsEngineId = id
    this.showTtsSheet = false
  }

  @Builder
  TtsEngineSelectSheet() {
    TtsEnginePickerSheetContent({
      currentEngineId: this.ttsEngineId,
      engines: this.ttsEngineOptions,
      onSelectEngine: (id: string): void => {
        this.selectTtsEngine(id)
      }
    })
  }
```

- [ ] **Step 6: Add TtsEngineSection to compact layout**

In `CompactModelSections` (around line 237), add `this.TtsEngineSection()` after
`this.TranslateModelSection()`:

```typescript
  @Builder
  CompactModelSections() {
    Column() {
      this.ChatModelSection()
      this.ImageModelSection()
      this.TitleModelSection()
      this.TranslateModelSection()
      this.TtsEngineSection()           // ← 5th
      Column().height(40)
    }
    .width('100%')
  }
```

- [ ] **Step 7: Add TtsEngineSection to expanded layout**

In `ExpandedModelSections` (around line 248), add `this.TtsEngineSection()` after
the second `Row`:

```typescript
  @Builder
  ExpandedModelSections() {
    Column({ space: 20 }) {
      Row({ space: 16 }) {
        Column() { this.ChatModelSection() }.layoutWeight(1)
        Column() { this.TitleModelSection() }.layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: 16 }) {
        Column() { this.ImageModelSection() }.layoutWeight(1)
        Column() { this.TranslateModelSection() }.layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.TtsEngineSection()           // ← 独占第 3 行
      Column().height(40)
    }
    .width('100%')
  }
```

- [ ] **Step 8: Bind the TTS sheet in `build()`**

In the `build()` method (around line 222), add a new `bindSheet` for `showTtsSheet`
after the existing `showPromptSheet` binding:

```typescript
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showTtsSheet, this.TtsEngineSelectSheet(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: true,
          title: { title: $r('app.string.tts_engine_select_title') }
        })
```

- [ ] **Step 9: Verify build**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 10: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/pages/DefaultModelPage.ets
git commit -m "feat(ui): add TtsEngineSection as 5th section in DefaultModelPage"
```

---

### Task 12: Register TTS engines in EntryAbility.onCreate

**Files:**
- Modify: `entryability/EntryAbility.ets`

- [ ] **Step 1: Read EntryAbility.ets to know exactly where to insert**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -n "TTSService\|registerTtsEngine\|appSettingsStore" entryability/EntryAbility.ets | head -20
```

- [ ] **Step 2: Add imports**

At the top of `entryability/EntryAbility.ets`, add:

```typescript
import { registerTtsEngine } from '../entry/src/main/ets/services/registry/TtsEngineRegistry'
```

> Note: adjust the relative path based on where the import lands — if `EntryAbility.ets`
> is at the project root under `entryability/`, the import is `./entry/src/main/ets/...`
> OR it could be at `entry/src/main/ets/entryability/`. Verify with the existing imports
> in the file before adjusting.

- [ ] **Step 3: Add the two `registerTtsEngine` calls in `onCreate`**

Locate where the existing services are initialized (e.g., `await getTTSService().init(context)`).
Add the two `registerTtsEngine` calls BEFORE that init call:

```typescript
    registerTtsEngine({
      profile: {
        id: 'system',
        displayName: '系统朗读',
        description: 'HarmonyOS 系统内置 TTS 引擎, 无需联网, 离线可用',
        requiresApiKey: false,
        iconSymbol: 'sys.symbol.speaker_wave_2_fill'
      },
      factory: () => new SystemTtsEngine()
    })

    registerTtsEngine({
      profile: {
        id: 'mimo',
        displayName: 'MiMo 语音',
        description: `小米 MiMo TTS (${MIMO_TTS_CONFIG.voice}), 复用 MiniMax API Key, 需要联网`,
        requiresApiKey: true,
        iconSymbol: 'sys.symbol.waveform'
      },
      factory: () => new MiMoTtsEngine()
    })
```

- [ ] **Step 4: Add the missing imports for the new types**

Add to the imports at the top of `EntryAbility.ets`:

```typescript
import { SystemTtsEngine } from '../entry/src/main/ets/services/tts/SystemTtsEngine'
import { MiMoTtsEngine } from '../entry/src/main/ets/services/tts/MiMoTtsEngine'
import { MIMO_TTS_CONFIG } from '../entry/src/main/ets/config/TtsConfig'
```

> Adjust the relative path prefix (`../entry/src/main/ets/...`) to match the actual
> layout of the existing imports in `EntryAbility.ets`.

- [ ] **Step 5: Verify build**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entryability/EntryAbility.ets
git commit -m "feat(boot): register system + mimo TTS engines in EntryAbility"
```

---

### Task 13: Final verification — lint, build, test, manual checklist

**Files:** (no changes; verification only)

- [ ] **Step 1: Run lint**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw lint \
  --mode module -p product=default 2>&1 | tail -20
```

Expected: no NEW errors. (Pre-existing warnings about `motion` / `sourceMapsPath` are OK.)

- [ ] **Step 2: Run full build**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Run unit tests**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw test \
  --mode module -p product=default 2>&1 | tail -30
```

Expected: 9 new tests pass (5 in `TtsEngineAvailability.test.ets` + 4 in `TtsEngineRegistry.test.ets`).

- [ ] **Step 4: Manual integration test checklist**

Run the app and verify each item:

- [ ] 全新安装 + 首次启动：默认 TTS = system，语音模式朗读 1 句后按钮回到"按住说话"
- [ ] DefaultModelPage 出现 5 个 section（compact 纵向 / expanded TTS 独占第 3 行）
- [ ] 点 TTS 卡片 → 弹出 picker，列出 system + mimo
- [ ] mimo 未配 MiniMax key 时显示"不可用"灰态
- [ ] 配 MiniMax key 后 mimo 变可点
- [ ] 选 mimo → 卡片显示"MiMo 语音" → 朗读能听到 MiMo 音色
- [ ] 切回 system → 朗读音色切回系统
- [ ] 切换时如正在朗读，平滑停止（无音频残留）
- [ ] kill app 重启 → 引擎被记住

- [ ] **Step 5: Final commit (if any post-checklist fixes)**

If Steps 1-4 surfaced issues, fix them in separate commits. If all passes, no
commit needed.

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|--------------|------|
| §1.1 目标 1 (删 TTS_ENGINE) | Task 4 |
| §1.1 目标 2 (5th 区块) | Task 11 |
| §1.1 目标 3 (registry) | Task 5 |
| §3.1 TtsEngineProfile | Task 1 |
| §3.2 AppSettingsState fields | Task 2 |
| §3.3 AppSettingsStore methods | Task 3 |
| §3.4 DefaultModelService facade | Task 6 |
| §3.5 TtsConfig refactor | Task 4 |
| §4 TtsEngineRegistry | Task 5 |
| §5 TTSService refactor | Task 7 |
| §6 UI (picker + section) | Tasks 10, 11 |
| §6.4 string resources | Tasks 8, 9 |
| §7 testing | Tasks 1, 5 (tests written alongside impls) |
| §7.5 manual checklist | Task 13 |
| §8 迁移 (EntryAbility registration) | Task 12 |
| §9 扩展点 (registry pattern) | Task 5 (registry itself) |

All spec sections covered.

**2. Placeholder scan:** No "TBD", "TODO", "fill in", "implement later", "similar to Task N", or "appropriate error handling" appear. Every code block is complete.

**3. Type consistency:**
- `TtsEngineProfile`, `TtsEngineRegistration`, `TtsEngineAvailability` defined in Task 1, used in Tasks 5, 6, 10, 11 — names match.
- `TtsEngineId` defined in Task 4, used in Tasks 6, 7 — names match.
- `MIMO_TTS_PROVIDER_ID` defined in Task 4, used in Task 1 (via dynamic import), Tasks 12 (via import) — names match.
- `ttsEngineId` / `ttsEngineInitialized` / `ttsEngineVersion` defined in Task 2, written in Task 3, read in Task 7, path-resolved in Task 2 — names match.
- `getTtsEngineId` / `setTtsEngineId` / `ensureTtsEngineInitialized` defined in Task 3, called in Task 7, facade in Task 6 — names match.
- `TtsEnginePickerSheetContent` defined in Task 10, instantiated in Task 11 — names match.

**4. Dynamic import edge case (Task 3):** The `await import('../config/TtsConfig')` in `ensureTtsEngineInitialized` is a workaround because TtsConfig.ets (Task 4) hasn't been updated yet at Task 3's write time. After Task 4, this should be refactored to a top-level `import { TTS_FALLBACK_ENGINE_ID } from '../config/TtsConfig'`. **Add a follow-up note to Task 4 step 4** to make this cleanup explicit. (See step below.)

- [ ] **Follow-up: Refactor Task 3's dynamic import to a static import**

After Task 4's commit lands, the dynamic import in `AppSettingsStore.ets` should
be replaced with a top-level import for cleanliness. Edit
`entry/src/main/ets/state/AppSettingsStore.ets`:

1. Replace the dynamic import line in `ensureTtsEngineInitialized`:
   ```typescript
   s.ttsEngineId = stored !== ''
     ? stored
     : (await import('../config/TtsConfig')).TTS_FALLBACK_ENGINE_ID
   ```
   with:
   ```typescript
   s.ttsEngineId = stored !== '' ? stored : TTS_FALLBACK_ENGINE_ID
   ```

2. Add to the top of the file (with other imports):
   ```typescript
   import { TTS_FALLBACK_ENGINE_ID } from '../config/TtsConfig'
   ```

3. Verify build:
   ```bash
   cd /Users/mac/mygame/HarmonyOS-app/chatcube
   /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
     --mode module -p product=default -p buildMode=debug 2>&1 | tail -5
   ```
   Expected: `BUILD SUCCESSFUL`.

4. Amend Task 4's commit (or add a follow-up commit if Task 4 was already pushed):
   ```bash
   cd /Users/mac/mygame/HarmonyOS-app/chatcube
   git add entry/src/main/ets/state/AppSettingsStore.ets
   git commit --amend --no-edit    # if Task 4's commit is the most recent
   # OR
   git commit -m "refactor(state): static import for TTS_FALLBACK_ENGINE_ID"
   ```

This is a code-quality cleanup, not a functional change. Safe to defer to merge time.

---

## Acceptance Checklist (from spec §12)

- [ ] `hvigorw lint` 通过 (Task 13)
- [ ] `hvigorw assembleHap` 编译通过 (Tasks 1-12, verified at each step)
- [ ] `hvigorw test` 9 条新增 case 全部通过 (Tasks 1, 5, 13)
- [ ] 手动 checklist（spec §7.5）11 条全部通过 (Task 13)
- [ ] 杀进程重启后选择的引擎被记住 (Task 13)
- [ ] 切换时如在朗读，平滑停止无音频残留 (Task 13)
- [ ] 未来加新 TTS 厂商只需按 spec §9 步骤改 5 个文件 (validated by Task 5 + Task 12 pattern)
