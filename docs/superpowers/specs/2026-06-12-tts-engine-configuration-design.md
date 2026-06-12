# TTS 引擎配置 — 设计文档

**日期：** 2026-06-12
**版本：** v1
**范围：** 把硬编码的 `TTS_ENGINE` 常量替换为可配置的 TTS 引擎选择；在 `DefaultModelPage` 加 5th 区块供用户切换；引入 `TtsEngineRegistry` 让未来加新厂商 TTS 引擎的成本保持 O(1)
**前置文档：** 无

---

## 1. 概述

### 1.1 目标

1. 消除 `config/TtsConfig.ets:5` 的硬编码 `TTS_ENGINE: TtsEngineType = 'system'`，让用户能在设置里选 system 还是 mimo。
2. 在 `DefaultModelPage` 加一个"TTS 朗读"区块，与 chat/title/translate/image 共用页面、同卡片视觉。
3. 引入 `TtsEngineRegistry` 注册表，未来加新厂商（ElevenLabs、Azure Speech、Google TTS 等）只动 1 个注册调用 + 1 个 `ITtsEngine` 文件，不改 UI、Service、Store。

### 1.2 关联文档

- `entry/src/main/ets/services/tts/SystemTtsEngine.ets`（本次同 PR 修了 3 个 latent bug：speakListener 未注册、currentCallback 未存、onStop 缺 `()`）

### 1.2 为什么做

- **产品诉求**：用户希望能在 system（离线、内置、零配置）和 mimo（联网、更自然、需要 MiniMax API Key）之间切换。
- **可扩展性诉求**：mimo 是第一个云端 TTS，但不会是最后一个；硬编码 `if (engineType === 'mimo')` 的二选一模式扛不住第 3、第 4 家厂商。
- **与 defaultModel 配置对齐**：chat/title/translate/image 都已经走 `DefaultModelConfig` + `AppSettingsStore` 持久化；TTS 是最后一个硬编码的服务商。

### 1.3 不做什么（YAGNI）

- **不做** 语速/音调/语音选择 UI。TtsEngineProfile 数据模型留好扩展位（`requiresApiKey: boolean`），但不在这期加 sheets。
- **不做** 按 assistant 维度配置 TTS 引擎。TTS 是系统级服务，1 个 id 服务全 assistant 即可。
- **不做** mimo 删 key 后 TTS 自动回退到 system 的实时联动。本期 TTS engine 在 app 运行期是绑定的，删 key 影响仅在 UI 灰态（picker 不可点），下次 `speak()` 时若 engine 报错会走 fallback。

---

## 2. 架构与数据流

**单向数据流，无回环**：

```
┌──────────────────────────────────────────────────────────┐
│                        用户操作                            │
│   DefaultModelPage → TtsEnginePickerSheet                │
│   (第 5 个 section, 沿用 ModelConfigCard 视觉)            │
└────────────────────┬─────────────────────────────────────┘
                     │ onSelectEngine(id)
                     ▼
┌──────────────────────────────────────────────────────────┐
│              DefaultModelService (facade)                │
│   setTtsEngineId(id) / getTtsEngineId()                   │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────┐
│              AppSettingsStore                             │
│   SQLite 键 'tts_engine_id', 默认 'system'                │
│   写完增 ttsEngineVersion 触发 @Trace                     │
└────────────────────┬─────────────────────────────────────┘
                     │ ↑ 写
                     │ ↓ 读
┌──────────────────────────────────────────────────────────┐
│              TTSService  (运行时读 + 订阅)                 │
│   resolveAndBindEngine(id):                              │
│     1. id = AppSettingsStore.getTtsEngineId()            │
│     2. engine = TtsEngineRegistry.resolve(id)            │
│     3. engine === null → resolveAndBindEngine('system')  │
│     4. this.currentEngine = engine                        │
│   observeAppSettingsState('ttsEngineVersion', ...)        │
│     → 用户改 ttsEngineId 后自动重解析                      │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────┐
│              TtsEngineRegistry  (内存)                    │
│   Map<id, { profile: TtsEngineProfile,                   │
│             factory: () => ITtsEngine }>                 │
│   register / list / resolve / getFallbackTtsEngineId      │
└──────────────────────────────────────────────────────────┘
                     ▲
                     │ registerTtsEngine(...) at EntryAbility.onCreate
                     │
   ┌─────────────────┴──────────────┐
   │                                │
┌──────────────────┐    ┌──────────────────────┐
│ SystemTtsEngine  │    │  MiMoTtsEngine       │
│  register('system')│  register('mimo',     │
│  (无需 key)        │    需要 MiniMax key)   │
└──────────────────┘    └──────────────────────┘
```

**关键不变量**：
- `TtsEngineRegistry` 永远是单点真相源；TTSService 不持有任何硬编码引擎名。
- 写入路径只走 `AppSettingsStore`；TTSService 不直接写。
- 读取路径：UI 走 `DefaultModelService`（带缓存），TTSService 走 `AppSettingsStore`（每次实时拉 + 订阅版本号）。
- 启动顺序：`preferencesService → databaseService → appSettingsStore → registerTtsEngine ×2 → TTSService.init`。

---

## 3. 数据 Schema

### 3.1 新建 `models/TtsEngineProfile.ets`

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

### 3.2 `state/AppSettingsState.ets` 加 3 个字段

```typescript
// ===== TTS 引擎配置 =====
@Trace ttsEngineId: string = ''           // 空串 = 未配置, TTSService 解析时按 'system' 兜底
@Trace ttsEngineInitialized: boolean = false
@Trace ttsEngineVersion: number = 0
```

+ `resolveAppSettingsStatePath` switch 加 `ttsEngineId` / `ttsEngineInitialized` / `ttsEngineVersion` 3 个 case。

### 3.3 `state/AppSettingsStore.ets` 加 3 个方法 + 1 个持久化 key

```typescript
const TTS_ENGINE_ID_KEY = 'tts_engine_id'      // 默认值 'system'

async ensureTtsEngineInitialized(): Promise<void> {
  // 与 ensureDefaultModelsInitialized 共享同样的 idempotency guard 模式
  if (getAppSettingsState().ttsEngineInitialized) return
  if (this.ttsEngineInitPromise !== null) {
    await this.ttsEngineInitPromise
    return
  }
  this.ttsEngineInitPromise = (async (): Promise<void> => {
    const stored = await this.preferences.getString(TTS_ENGINE_ID_KEY, '')
    const s = getAppSettingsState()
    s.ttsEngineId = stored !== '' ? stored : TTS_FALLBACK_ENGINE_ID   // 'system'
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

### 3.4 `services/DefaultModelService.ets` 加 2 个 facade 方法

```typescript
getTtsEngineId(): string {
  return this.store.getTtsEngineId()
}

async setTtsEngineId(id: string): Promise<void> {
  await this.store.setTtsEngineId(id)
}
```

### 3.5 `config/TtsConfig.ets` 改造

```diff
- // TTS 引擎类型
- export type TtsEngineType = 'system' | 'mimo'
- // 当前使用的 TTS 引擎（改为 'mimo' 即可切换小米 MiMo 引擎）
- export const TTS_ENGINE: TtsEngineType = 'system'
+ // TTS 引擎 ID, 与 TtsEngineRegistry 共享
+ export type TtsEngineId = 'system' | 'mimo'
+
+ // 注册表都 miss 时的 fallback
+ export const TTS_FALLBACK_ENGINE_ID: TtsEngineId = 'system'
+
+ // mimo 引擎绑定的 provider id (用于查 api key)
+ export const MIMO_TTS_PROVIDER_ID = 'minimax'
```

---

## 4. TtsEngineRegistry 设计

### 4.1 新建 `services/registry/TtsEngineRegistry.ets`

模块级单例，风格与 `ProviderProfileRegistry.ets` 一致（模块状态 + 导出函数）：

```typescript
const REGISTRATIONS: Map<string, TtsEngineRegistration> = new Map()

export function registerTtsEngine(registration: TtsEngineRegistration): void {
  if (REGISTRATIONS.has(registration.profile.id)) {
    console.warn('TtsEngineRegistry', `engine '${registration.profile.id}' already registered, overwriting`)
  }
  REGISTRATIONS.set(registration.profile.id, registration)
}

export function listTtsEngines(): TtsEngineAvailability[] {
  const result: TtsEngineAvailability[] = []
  REGISTRATIONS.forEach((reg) => {
    result.push(evaluateTtsEngineAvailability(reg.profile, getAppSettingsState().providers))
  })
  return result
}

export function resolveTtsEngine(id: string): ITtsEngine | null {
  const reg = REGISTRATIONS.get(id)
  if (reg === undefined) return null
  try {
    return reg.factory()   // 工厂无参, init() 由 TTSService.resolveAndBindEngine 调用
  } catch (err) {
    console.error('TtsEngineRegistry', `factory for '${id}' threw: ${JSON.stringify(err)}`)
    return null
  }
}

export function getFallbackTtsEngineId(): string {
  return REGISTRATIONS.has(TTS_FALLBACK_ENGINE_ID) ? TTS_FALLBACK_ENGINE_ID : ''
}
```

### 4.2 注册时机：EntryAbility.onCreate

```typescript
// onCreate() 内部, 在 getTTSService() 调用前
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

### 4.3 内部: `evaluateTtsEngineAvailability` 抽到 utils

为了可单测，把可用性评估抽成纯函数 `utils/TtsEngineAvailabilityUtils.ets`（详见 §6 测试）。

---

## 5. TTSService 改造

### 5.1 重构后的 `services/TTSService.ets` 核心

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
  }

  async speak(text: string, callback: TTSCallback): Promise<void> {
    const processedText = this.preprocessTextForTTS(text)
    if (processedText === '') { callback.onError('没有可朗读的内容'); return }
    if (this.currentEngine === null) { callback.onError('朗读服务未初始化'); return }
    await this.currentEngine.speak(processedText, callback)
  }

  stop(): void { this.currentEngine?.stop() }
  isSpeaking(): boolean { return this.currentEngine !== null && this.currentEngine.isSpeaking() }
  getCurrentEngineId(): TtsEngineId { return this.currentEngineId }

  destroy(): void {
    this.currentEngine?.destroy()
    this.currentEngine = null
    this.unsubscribe?.()
    this.unsubscribe = null
    this.initContext = null
  }

  private resolveAndBindEngine(id: string): void {
    // 切前: 如在朗读, 停
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
        console.error('TTSService', `engine '${id}' init failed: ${JSON.stringify(err)}`)
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
  // preprocessTextForTTS 保持原样
}
```

### 5.2 删除的代码

- ❌ `private systemEngine: SystemTtsEngine = new SystemTtsEngine()`
- ❌ `private mimoEngine: MiMoTtsEngine = new MiMoTtsEngine()`
- ❌ `private resolveEngine(): ITtsEngine`
- ❌ `switchEngine(engineType: TtsEngineType): void`（改 store 驱动）
- ❌ `import { TTS_ENGINE, TtsEngineType } from '../config/TtsConfig'`
- ❌ `import { SystemTtsEngine }` / `import { MiMoTtsEngine }`（实例不再 new 在 TTSService）
- ❌ `getCurrentEngineType(): TtsEngineType`（改 `getCurrentEngineId(): TtsEngineId`）

### 5.3 Breaking change 影响范围（已全文搜）

`TTS_ENGINE` / `TtsEngineType` 仅在 2 个文件出现：`TtsConfig.ets` + `TTSService.ets`。无外部调用方需要修改。

### 5.4 切换时序

```
用户点 picker → DefaultModelService.setTtsEngineId('mimo')
  → AppSettingsStore.setTtsEngineId
    → 写 SQLite 'tts_engine_id' = 'mimo'
    → s.ttsEngineId = 'mimo'
    → s.ttsEngineVersion++
  → observeAppSettingsState 回调触发
    → TTSService.resolveAndBindEngine('mimo')
      → 旧 engine (system).isSpeaking() ? stop() : (skip)
      → 旧 engine.destroy()
      → resolveTtsEngine('mimo') → new MiMoTtsEngine()
      → engine.init(context)  (audioPlayer init + inited = true)
      → this.currentEngine = new engine
```

---

## 6. UI

### 6.1 新建 `components/defaultmodel/TtsEnginePickerSheetContent.ets`

参照 `DefaultModelSelectSheetContent.ets` 视觉风格，但：
- 数据源是 `listTtsEngines()` 返回的 `TtsEngineAvailability[]`
- 不可用引擎显示灰态 + "不可用"标签 + 不可点
- 选中行有 checkmark 标记

```typescript
@ComponentV2
export struct TtsEnginePickerSheetContent {
  @Param currentEngineId: string = ''
  @Param engines: TtsEngineAvailability[] = []
  private get themePrimary(): string { return getAppUiState().themePrimary }

  @Event onSelectEngine: (id: string) => void = () => {}

  build() {
    Column() {
      // Header
      Row() {
        Text($r('app.string.tts_engine_select_title'))
          .fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .height(56).width('100%').padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.engines.length === 0) {
        Text($r('app.string.tts_engine_empty'))
          .fontColor($r('app.color.text_tertiary'))
          .padding(16)
      }

      List() {
        ForEach(this.engines, (item: TtsEngineAvailability) => {
          ListItem() { this.EngineRow(item) }
        })
      }
      .listDirection(Axis.Vertical)
      .layoutWeight(1)
    }
    .width('100%').height('100%')
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
            .fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(item.isEnabled ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
          if (!item.isEnabled) {
            Text($r('app.string.tts_engine_unavailable_tag'))
              .fontSize(11).fontColor(Color.White)
              .backgroundColor($r('app.color.text_tertiary'))
              .borderRadius(4)
              .padding({ left: 6, right: 6 })
              .margin({ left: 8 })
          }
        }
        Text(item.isEnabled ? item.profile.description : item.unavailableReason)
          .fontSize(12).fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)

      if (item.profile.id === this.currentEngineId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20).fontColor([this.themePrimary])
      }
    }
    .width('100%').padding(16)
    .backgroundColor(item.profile.id === this.currentEngineId
      ? getAppUiState().themeSurface : Color.Transparent)
    .enabled(item.isEnabled)
    .onClick(() => { if (item.isEnabled) this.onSelectEngine(item.profile.id) })
  }
}
```

### 6.2 `pages/DefaultModelPage.ets` 加状态 + section

```typescript
@Local ttsEngineId: string = ''
@Local ttsEngineOptions: TtsEngineAvailability[] = []
@Local showTtsSheet: boolean = false

async loadTtsEngine(): Promise<void> {
  this.ttsEngineId = this.defaultModelService.getTtsEngineId()
  this.ttsEngineOptions = listTtsEngines()
}

private async selectTtsEngine(id: string): Promise<void> {
  await this.defaultModelService.setTtsEngineId(id)
  this.ttsEngineId = id
  this.showTtsSheet = false
}
```

### 6.3 TtsEngineSection + 两种布局

```typescript
@Builder
TtsEngineSection() {
  Column() {
    this.SectionTitle($r('app.string.tts_engine_section_title'))
    ModelConfigCard({
      roleName: $r('app.string.tts_engine_role'),
      description: $r('app.string.tts_engine_desc'),
      showPromptEdit: false,                  // TTS 无 prompt
      isDefaultPrompt: true,
      isConfigured: this.ttsEngineId !== '',
      displayName: this.ttsEngineId !== '' ? this.getTtsEngineDisplayName() : '',
      onCardClick: () => { this.showTtsSheet = true },
      onPromptClick: () => {}
    })
  }
  .width('100%')
}

// compact: 5 个 section 纵向
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
}

// expanded: 2x2 网格 + TTS 独占第 3 行
@Builder
ExpandedModelSections() {
  Column({ space: 20 }) {
    Row({ space: 16 }) {
      Column() { this.ChatModelSection() }.layoutWeight(1)
      Column() { this.TitleModelSection() }.layoutWeight(1)
    }
    Row({ space: 16 }) {
      Column() { this.ImageModelSection() }.layoutWeight(1)
      Column() { this.TranslateModelSection() }.layoutWeight(1)
    }
    this.TtsEngineSection()
    Column().height(40)
  }
}
```

### 6.4 字符串资源

新增 6 条（zh_CN / en_US 都加）：

```
tts_engine_section_title   "TTS 朗读" / "TTS"
tts_engine_role            "语音朗读" / "Voice"
tts_engine_desc            "语音模式下自动朗读使用的引擎" / "Engine used for voice-mode TTS"
tts_engine_select_title    "选择 TTS 引擎" / "Select TTS Engine"
tts_engine_empty           "暂无可用 TTS 引擎" / "No TTS engines available"
tts_engine_unavailable_tag "不可用" / "Unavailable"
```

---

## 7. 测试

### 7.1 策略

- 抽 `evaluateTtsEngineAvailability` 成纯函数 → `utils/TtsEngineAvailabilityUtils.ets`，可单测。
- TtsEngineRegistry 行为单测（register / overwrite / resolve / fallback）。
- UI 集成靠手动 checklist（ArkUI 测试基建缺）。

### 7.2 新增 `utils/TtsEngineAvailabilityUtils.ets`

```typescript
export function evaluateTtsEngineAvailability(
  profile: TtsEngineProfile,
  providers: ModelProvider[]
): TtsEngineAvailability {
  if (!profile.requiresApiKey) {
    return { profile, isEnabled: true, unavailableReason: '' }
  }
  if (profile.id === 'mimo') {
    const matched = providers.find(p => p.id === MIMO_TTS_PROVIDER_ID && p.apiKey !== '')
    if (matched === undefined) {
      return { profile, isEnabled: false, unavailableReason: '未配置 MiniMax API Key, 不可用' }
    }
  }
  return { profile, isEnabled: true, unavailableReason: '' }
}
```

### 7.3 新增 `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`

5 条 case：
1. system 引擎无 providers 也 enabled
2. mimo 无 providers 时 disabled，reason 含 "MiniMax"
3. mimo + minimax provider 无 apiKey → disabled
4. mimo + minimax provider 有 apiKey → enabled
5. mimo + 其他 provider 有 apiKey → disabled（绑错 provider）

### 7.4 新增 `entry/src/ohosTest/ets/test/registry/TtsEngineRegistry.test.ets`

4 条 case：
1. resolve 未知 id 返回 null
2. register + resolve 返回 factory 产物
3. 重复 id 注册覆盖，list 只剩 1 条
4. getFallbackTtsEngineId 在 system 已注册时返回 'system'

### 7.5 手动集成测试 Checklist

- [ ] 全新安装 + 首次启动：默认 TTS = system，语音模式朗读 1 句后按钮回到"按住说话"
- [ ] DefaultModelPage 出现 5 个 section（compact 纵向 / expanded TTS 独占第 3 行）
- [ ] 点 TTS 卡片 → 弹出 picker，列出 system + mimo
- [ ] mimo 未配 MiniMax key 时显示"不可用"灰态
- [ ] 配 MiniMax key 后 mimo 变可点
- [ ] 选 mimo → 卡片显示"MiMo 语音" → 朗读能听到 MiMo 音色
- [ ] 切回 system → 朗读音色切回系统
- [ ] 切换时如正在朗读，平滑停止（无音频残留）
- [ ] kill app 重启 → 引擎被记住
- [ ] `hvigorw lint` 通过
- [ ] `hvigorw assembleHap` 编译通过

---

## 8. 迁移与默认值

### 8.1 旧 `TTS_ENGINE` 常量迁移

- **现役用户的 SQLite `tts_engine_id` 键不存在**：首次启动时 `ensureTtsEngineInitialized()` 读不到，回退到默认 `'system'` —— 与旧 `TTS_ENGINE='system'` 行为一致，无感。
- **硬编码读取 `TTS_ENGINE` 的代码**：仅 `TtsConfig.ets` + `TTSService.ets` 两处，删除即可。

### 8.2 启动顺序（`EntryAbility.ets`）

```typescript
async onCreate(): Promise<void> {
  // 1. 现有 7 个服务初始化
  await this.preferencesService.init(context)
  await this.databaseService.init(context)
  await this.appSettingsStore.initialize()        // 加载 defaultModels / prompts / ttsEngine
  ...

  // 2. TTS 引擎注册 (新增)
  registerTtsEngine({ profile: { id: 'system', ... }, factory: () => new SystemTtsEngine() })
  registerTtsEngine({ profile: { id: 'mimo',   ... }, factory: () => new MiMoTtsEngine() })

  // 3. TTSService 初始化 (改造后自动从 store 读 + 订阅)
  await getTTSService().init(context)
  ...
}
```

### 8.3 首次启动默认值

`AppSettingsStore.ensureTtsEngineInitialized()` 读不到 SQLite 时：
```typescript
s.ttsEngineId = stored !== '' ? stored : TTS_FALLBACK_ENGINE_ID   // 'system'
```

### 8.4 卸载行为

无额外卸载逻辑：
- 引擎实例是 TTSService 私有，destroy 时自然释放。
- SQLite `tts_engine_id` 键保留，与 defaultModel 同模式。

---

## 9. 扩展点 — 新增 TTS 引擎 Checklist

**承诺：加新厂商 TTS 引擎 ≤ 5 个文件改动 + ≤ 10 行新代码。** 以 ElevenLabs 为例：

1. **`tts/ElevenLabsTtsEngine.ets`（新）** —— 实现 `ITtsEngine`，~150 行。参考 `MiMoTtsEngine.ets` 的 http + audioPlayer 模式。
2. **`config/TtsConfig.ets`** —— 加 `ELEVENLABS_TTS_PROVIDER_ID` 常量 + `TtsEngineId` union 加 `'elevenlabs'`。
3. **`utils/TtsEngineAvailabilityUtils.ets`** —— 加 1 个 case（mimo 的 if 块下面再 if 一下）。*当引擎数 ≥ 3 时升级为 `apiKeyProviderId: string` 字段，消除 if 链。*
4. **`entryability/EntryAbility.ets`** —— 加 1 段 `registerTtsEngine({ id: 'elevenlabs', ... })`。
5. **`entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`** —— 加 3 条 case。

**完成。** 无需改：
- ❌ DefaultModelPage（picker 自动列新引擎）
- ❌ TTSService（registry 驱动）
- ❌ AppSettingsStore（id 是 string）
- ❌ UI strings（displayName/description 在 profile 里内嵌）

---

## 10. 已知局限（不阻塞本期）

| 局限 | 影响 | 缓解 |
|------|------|------|
| `TtsEngineAvailabilityUtils` 用 `if (profile.id === 'mimo')` 硬编码 | 引擎 ≥ 3 时 if 链冗长 | N≥3 升级为 `apiKeyProviderId: string` 字段 |
| `TtsEngineProfile` 字段内嵌在 Registry 注册处 | displayName 改动需改 .ets + 重新构建 | 后续可抽 i18n 字符串资源 |
| TTSService 不感知 mimo 初始化需要 minimax api key 变更 | 用户中途删 key，TTS 不会自动回退到 system | 后续可订阅 providersVersion 自动重评估 |
| TTSConfig.ets 仍硬编码 1 个 `TtsEngineId` union | 未来加枚举值要改 2 个文件 | 接受此折中；动态枚举不必要 |

---

## 11. 触点文件清单

新增（6 个）：
- `entry/src/main/ets/models/TtsEngineProfile.ets`
- `entry/src/main/ets/services/registry/TtsEngineRegistry.ets`
- `entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets`
- `entry/src/main/ets/components/defaultmodel/TtsEnginePickerSheetContent.ets`
- `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`
- `entry/src/ohosTest/ets/test/registry/TtsEngineRegistry.test.ets`

修改（7 个）：
- `entry/src/main/ets/config/TtsConfig.ets`（删 TTS_ENGINE + TtsEngineType，加 3 个新常量）
- `entry/src/main/ets/state/AppSettingsState.ets`（+3 @Trace 字段 + path switch）
- `entry/src/main/ets/state/AppSettingsStore.ets`（+3 方法 + 1 key）
- `entry/src/main/ets/services/DefaultModelService.ets`（+2 facade）
- `entry/src/main/ets/services/TTSService.ets`（大改，详见 §5.2）
- `entry/src/main/ets/pages/DefaultModelPage.ets`（+1 section + 1 sheet）
- `entryability/EntryAbility.ets`（+2 registerTtsEngine）

资源（2 个）：
- `entry/src/main/resources/zh_CN/element/string.json`（+6 字符串）
- `entry/src/main/resources/en_US/element/string.json`（+6 字符串）

---

## 12. 验收清单

- [ ] `hvigorw lint` 通过
- [ ] `hvigorw assembleHap` 编译通过
- [ ] `hvigorw test` 9 条新增 case 全部通过
- [ ] 手动 checklist（§7.5）11 条全部通过
- [ ] 杀进程重启后选择的引擎被记住
- [ ] 切换时如在朗读，平滑停止无音频残留
- [ ] 未来加新 TTS 厂商只需按 §9 步骤改 5 个文件
