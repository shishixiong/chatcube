# Chat 模型选择器 — 推理能力过滤

**日期：** 2026-06-12
**版本：** v1
**范围：** 让所有"聊天相关"的模型选择器在展示模型时硬过滤掉无推理能力的模型；chat 页面在 `validateAndSetCurrentModel` 阶段自动把非推理模型切到首个推理模型（**只写 session，不动全局**）。
**前置文档：** 无

---

## 1. 概述

### 1.1 目标

1. chat 页面 titlebar 弹出的 `ChatModelSelectorSheetContent`、设置页 `DefaultModelSelectSheetContent`、Index 页 `AssistantModelSheetBuilder` 这 3 个聊天相关选择器，列表里**只**显示 `supportsReasoning === true` 的模型。
2. chat 页面在 `validateAndSetCurrentModel` 时：若 current model 不具备推理能力且存在可用推理模型，自动切到**第一个**推理模型；切换时**只**写当前 session 的 `modelSelection`，**不**触碰全局 `currentModelId` / `currentProviderId`。
3. 图片生成选择器（`ImageGenerationModelSheet`）行为不变——它不显示文本模型，过滤对它无影响。
4. 当过滤后无任何模型可显示时，给出明确空状态文案，不强制切换任何东西。

### 1.2 为什么做

小星老师（默认 assistant）系统提示词引导 AI 大量使用推理能力。允许用户在 chat 流程里选一个不推理的模型，会让 AI 在 reasoning 工具调用上要么静默失败要么幻觉——产品上不可接受。让选择器从源头限定推理模型是最直接的"防呆"。

### 1.3 不做什么（YAGNI）

- **不**给选择器加 "显示全部" 开关。硬过滤就是硬过滤；想用非推理模型请到 model edit sheet 里调 `capabilitiesUserModified`。
- **不**改 `ModelAbilityRegistry` 或 `deriveModelCapabilities` 的判定逻辑。沿用现有 `getEffectiveCapabilities(model).supportsReasoning`。
- **不**做按 assistant 维度的过滤配置。统一一个开关，简洁优先。
- **不**做迁移工具或数据回填。`modelSelection` schema 不变；下次进入 chat 页面会自动再切一次，这是想要的行为。
- **不**改 image gen 选择器。图片模型不在"推理"语义范畴。

---

## 2. 架构与数据流

```
┌──────────────────────────────────────────────────────────┐
│  ChatModelSelectorSheetContent  (titlebar)               │
│  DefaultModelSelectSheetContent   (settings)            │
│  AssistantModelSheetBuilder  (Index.ets:4303)            │
│        ↓  reasoningOnly: true 传参                       │
│  ModelSelectorContent (新增 @Param reasoningOnly)         │
│        ↓  rebuildRows() 透传                            │
│  buildModelSelectorRowsWithOutputMode(..., reasoningOnly)│
│        ↓                                               │
│  buildModelSelectorRowsInternal(...)                     │
│    新过滤点: supportsReasoning === true 否则 skip         │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  ChatPage.validateAndSetCurrentModel                     │
│    新增: 若 current 不支持推理 → 选首个推理模型          │
│    applyModelSelection(..., syncGlobalModel=false)       │
│       ↓                                                 │
│  chatViewModel.updateCurrentSessionModelSelection(...)   │
│       ↓                                                 │
│  session.modelId 写库 (不写 appStateManager)              │
└──────────────────────────────────────────────────────────┘
```

**关键不变量**：
- `ModelSelectorContent` 是 4 个选择器共享的核心组件；新增 `reasoningOnly` 是**默认 false** 的扩展参数——已存在调用方零行为变化。
- 自动切换只走 session 写库路径；`appStateManager.setCurrentModel` 不被触发，全局 `currentModelId` 在 `AppSettingsStore` 里的值不变。
- 判定始终走 `getEffectiveCapabilities(model).supportsReasoning`，自动尊重用户在 model edit sheet 里手动覆盖的 capabilities。

---

## 3. 数据 Schema

### 3.1 `components/ModelSelector.ets` 新增 `@Param`

```typescript
@Param reasoningOnly: boolean = false
```

**位置**：紧跟 `outputModeFilter` 之后（行 31 后），与现有 `hasOutputModeFilter` / `outputModeFilter` 同区域。

### 3.2 `config/ModelListProjection.ets` 函数签名扩展

```typescript
export function buildModelSelectorRows(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean
): ModelSelectorBuildResult
// ↑ 旧函数, 改为薄包装, 默认 reasoningOnly=false

export function buildModelSelectorRowsWithOutputMode(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean,
  hasOutputModeFilter: boolean,
  outputModeFilter: OutputMode,
  reasoningOnly: boolean  // ← 新增
): ModelSelectorBuildResult

// 内部函数:
function buildModelSelectorRowsInternal(
  ...原有 7 个参数,
  reasoningOnly: boolean  // ← 新增
): ModelSelectorBuildResult
```

**过滤点插入位置**：`buildModelSelectorRowsInternal` 内层 `for j` 循环，行 113 `hasOutputModeFilter` 判断之后立即插入：

```typescript
if (reasoningOnly && !getEffectiveCapabilities(model).supportsReasoning) {
  continue
}
```

`enabledModelCount++` **不**递增被过滤掉的模型——保持 `hasEnabledModels` 反映"该列表里有可选的"，避免空状态文案出现错配。

### 3.3 字符串资源

`resources/base/element/string.json` 新增 2 条：

| key | zh | en |
|---|---|---|
| `no_reasoning_model_title` | 暂无可用推理模型 | No reasoning models available |
| `no_reasoning_model_hint` | 请到服务商设置中启用具有推理能力的模型 | Enable a model with reasoning capability in provider settings |

（实际值由 i18n 文件决定；本设计只约束 key 名和语义）

---

## 4. 详细设计

### 4.1 `ModelSelectorContent.rebuildRows` 透传

`components/ModelSelector.ets:134-153` `rebuildRows()` 内：

```typescript
const result: ModelSelectorBuildResult = buildModelSelectorRowsWithOutputMode(
  this.providers,
  this.searchKeywords,
  this.favoriteKeySet,
  this.showFavoritesOnly,
  this.includeModelIdInSearch,
  this.hasOutputModeFilter,
  this.outputModeFilter,
  this.reasoningOnly  // ← 新增
)
```

### 4.2 三个调用方传 `reasoningOnly: true`

| 文件:行 | 改动 |
|---|---|
| `components/chat/ChatModelSelectorSheetContent.ets:68-78` | 在 `ModelSelectorContent({...})` 字段中加 `reasoningOnly: true` |
| `components/defaultmodel/DefaultModelSelectSheetContent.ets:59-81` | 同上 |
| `pages/Index.ets:4303-4320 AssistantModelSheetBuilder` | 同上 |

`ImageGenerationModelSheet.ets:28-44` **不**改——保持默认 false。

### 4.3 `ChatPage.validateAndSetCurrentModel` 自动切换

**位置**：`pages/ChatPage.ets:2003-2023`

**当前逻辑**：
1. session 模型有 → 用 session
2. 否则 saved（appStateManager）模型有 → 用 saved
3. 否则 `selectFirstAvailableModel` 兜底

**新逻辑**：
1. session 模型有 → **校验推理能力**：
   - 若 session 模型有推理能力：用 session（applyModelSelection, syncGlobalModel = !isNewEmptySession）
   - 若 session 模型**无**推理能力 → 不直接 reject，落到第 2 步（可能 saved 是有推理的）
2. saved 模型有 → 同 1 的推理能力校验
3. `selectFirstAvailableModel` 内部追加"优先选首个推理模型"分支：
   - 扫 providers 找 `isEnabled && supportsReasoning` 的第一个 → 命中则 `applyModelSelection(p, m, '', false)`（syncGlobalModel=false）
   - 没命中 → 走原 fallback（第一个 isEnabled 模型，syncGlobalModel 行为不变）
4. 仍无可用 → 维持原 "currentProvider = null" 路径

**新增私有方法**（薄包装，调用 §6.4 的 utils 纯函数做选择 + 自己负责 apply）：

```typescript
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

**整合**：`selectFirstAvailableModel` 行 2026 开头加：

```typescript
const switched = await this.selectFirstReasoningModel()
if (switched) return
// ↓ 后面是原 fallback 逻辑
```

`validateAndSetCurrentModel` 中 session/saved 命中但**无推理能力**时，直接跳到下一步（不返回）。具体写法：

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

**副作用精确说明**：
- `applyModelSelection(provider, model, '', false)` 第 4 参 `syncGlobalModel=false` ⇒ **不**调 `appStateManager.setCurrentModel` ⇒ 全局 `currentModelId` / `currentProviderId` 在 `AppSettingsStore` 的值不变
- `applyModelSelection` 内部仍调 `chatViewModel.updateCurrentSessionModelSelection` ⇒ session 表写新 modelId
- `applyModelSelection` 内部仍调 `refreshAvailableSearchEngines` ⇒ 联网菜单按新模型刷新（这是正确行为）

### 4.4 空状态文案

3 个聊天选择器在 `ModelSelectorContent` 的 `EmptyState` (`ModelSelector.ets:493-512`) 走现有 `getEmptyTitle()` / `getEmptyDescription()` 路径。

**`ModelSelectorContent` 已有的 `@Param`**（行 32-33）：
```typescript
@Param emptyTitle: string | Resource = ''
@Param emptyDescription: string | Resource = ''
```

**`DefaultModelSelectSheetContent`**（行 73-74）**已**透传 `emptyTitle` / `emptyDescription`，本次只把字面量替换成新 string key。

**`ChatModelSelectorSheetContent` 和 `AssistantModelSheetBuilder` 当前未透传这两个 prop**。本次需要：

- `components/chat/ChatModelSelectorSheetContent.ets`：
  - 加 `@Param emptyTitle: string | Resource = ''` 和 `@Param emptyDescription: string | Resource = ''`
  - 透传给 `ModelSelectorContent({...})`
- `pages/Index.ets:4303 AssistantModelSheetBuilder`：
  - 同上

调用方传值（**3 处一致**）：
```typescript
emptyTitle: $r('app.string.no_reasoning_model_title'),
emptyDescription: $r('app.string.no_reasoning_model_hint')
```

**简化决策**（spec 锁定）：
- 复用现有 `emptyTitle` / `emptyDescription` props，**不**在 `EmptyState` 内嵌判断是否由 reasoning 过滤触发
- 3 个聊天选择器统一用同一对文案——空状态对用户语义等价
- `ImageGenerationModelSheet` 不动（它有自己的 image-gen 专属文案）

### 4.5 助手默认模型选择器（AssistantModelSheetBuilder）的行为边界

`AssistantModelSheetBuilder` 接受**列表过滤**（§4.2）但**不**接 `validateAndSetCurrentModel` 自动切换（§4.3 是 `ChatPage` 的逻辑）：

- **列表过滤生效**：assistant 配置面板里只看到推理模型，无法再"新选"非推理模型作为 assistant 默认
- **存量非推理模型保留**：数据库里 assistant 之前已存的非推理 modelId **不**清空；前端仍显示该 assistant 的旧 modelId（直到用户在面板里手动改）
- **运行时兜底**：assistant 真正被加载进 chat 页面时，**仍**走 `ChatPage.validateAndSetCurrentModel` 的"自动切到首个推理模型"分支——这等价于"assistant 配置层说 A，但 runtime 实际用 B"，session 写 B、全局不变
- **设计意图**：assistant 配置面板 = 用户对"我想要什么助手"的表达（被新过滤约束）；chat 进入 = runtime 对"现在能用什么模型"的兜底（auto-switch）。两阶段解耦：面板不强行清旧值、不预览切换；runtime 兜底所有 assistant

**澄清常见误解**：
- 不是"在 assistant 面板里把用户的非推理选择改了"
- 是"在 runtime 兜底层处理"

---

## 5. 边界与失败模式

| 场景 | 行为 |
|------|------|
| 当前 session 模型有推理能力 | 用 session 模型，行为不变 |
| 当前 session 模型无推理能力，saved 模型有 | 用 saved 模型（沿用原 saved 路径） |
| session 和 saved 都无推理能力，有别的推理模型 | `selectFirstReasoningModel` 切到首个，**只写 session** |
| 完全没有任何推理模型 | `selectFirstReasoningModel` 返回 false → 走原 fallback 选首个 isEnabled 模型 |
| 完全没有 isEnabled 模型 | 原行为：currentProvider = null |
| 用户在 titlebar 打开选择器时无推理模型 | 列表区显示新空状态文案，"清空选择"按钮（如有）仍可点 |
| 用户在 model edit sheet 手动给非推理模型开 `supportsReasoning=true` | 该模型**会**进入列表——尊重 `capabilitiesUserModified` |
| Provider 内所有模型都被推理过滤掉 | 该 provider 在列表里**不**显示（沿用现有 `matchedModels.length === 0` 跳过 header 逻辑，行 140-142） |
| `outputModeFilter=IMAGE` 同时 `reasoningOnly=true` | 同时生效，匹配必须 `outputMode === IMAGE && supportsReasoning`——但 image gen 调用方不传 reasoningOnly，所以实际不会发生 |

---

## 6. 验证

### 6.1 编译验证

- `hvigorw assembleHap --mode module -p product=default -p buildMode=debug` 跑通
- 预期无 ArkTS 严格模式错误（无新增内联对象字面量、无解构、无 `bind().map`）

### 6.2 string.json 解析验证

按 MEMORY.md 的 JSON 模板字面量陷阱规则，新增 string 资源如使用模板字面量，跑：

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/...','utf-8'); ... JSON.parse ..."
```

或直接看 string.json 文件不在模板字面量内——走 element/string.json 添加不需要此校验（仅在 `rawSchemaJson` 模板字面量场景触发）。

### 6.3 手动场景清单

| # | 场景 | 期望 |
|---|------|------|
| 1 | chat titlebar 打开选择器，列表里有 reasoning + 非 reasoning 模型 | 列表只显示 reasoning 模型 |
| 2 | chat titlebar 选择器无 reasoning 模型 | 列表显示新空状态文案 |
| 3 | 当前 session 模型无 reasoning，有其他 reasoning 模型 | 进 chat 页面自动切到首个 reasoning；reload 仍为 reasoning |
| 4 | 当前 session 模型无 reasoning，无其他 reasoning 模型 | 切到首个 isEnabled 模型（原 fallback） |
| 5 | image gen 选择器 | 行为不变，仍显示图像模型 |
| 6 | AssistantModelSheet 选 assistant 默认模型 | 列表只显示 reasoning 模型；选完不自动切换 |
| 7 | DefaultModelSelectSheetContent 选全局默认模型 | 列表只显示 reasoning 模型 |
| 8 | 用户在 model edit sheet 改 `capabilitiesUserModified=true` 并设 `supportsReasoning=true` | 该模型进入列表 |
| 9 | 全局 currentModelId 持久化值 | 自动切换时**不**变（用 `adb shell` 或 `AppStorage` dump 验证） |
| 10 | Provider 内无 reasoning 模型 | provider header 不显示（与现有空 provider 行为一致） |

### 6.4 单元测试

按 CLAUDE.md "新增业务逻辑时**优先在 `utils/` 抽出纯函数并补 hypium 单元测试**" 的指引：

抽出 `utils/ReasoningModelFilter.ets`：

```typescript
import { ModelInfo, ModelProvider } from '../models/ChatModels'
import { getEffectiveCapabilities } from './ModelCapabilityDeriver'

export interface ReasoningModelPick {
  provider: ModelProvider
  reasoningModel: ModelInfo
}

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

`ChatPage.selectFirstReasoningModel` 调它（§4.3 展示了集成点）；在 `entry/src/ohosTest/ets/test/` 加 `ReasoningModelFilter.test.ets` 覆盖：
- 空 providers → null
- 全是 disabled → null
- 第一个 provider 第一个 model 是 disabled，第二个是 enabled + reasoning → 返回它
- 全是 enabled 但无 reasoning → null
- `capabilitiesUserModified=true` 且 `supportsReasoning=true` → 命中
- provider 顺序：返回的总是**最靠前**的 provider/model 组合

---

## 7. 风险

| 风险 | 缓解 |
|------|------|
| `ModelAbilityRegistry` 未覆盖的模型被判为无推理 | 现有行为；用户可去 model edit sheet 手动开 |
| `capabilitiesUserModified` 路径下用户改了 supportsReasoning=true | 这是用户显式意图，过滤会尊重它——已在 `getEffectiveCapabilities` 路径覆盖 |
| 自动切换写 session 后 reload 又触发同样自动切换 | 是想要的行为；幂等且最终态稳定（切到 reasoning 模型后下次进页面校验通过） |
| `outputModeFilter=IMAGE` 调用方意外传 reasoningOnly=true | 物理上不会发生——image gen 调用方独立于本次改动 |
| 新增 string 资源后其它语言文件（`en_US` 等）未补齐 | 走现有 i18n fallback，未补齐的语言走 `values` 默认；与项目其他资源变更风险一致 |
| 4 个调用方中 `AssistantModelSheetBuilder` 选 assistant 默认模型也被过滤 | 这是用户接受的（"所有聊天相关选择器都过滤"），文档已说明 |
| 现有用户在 `capabilitiesUserModified` 把 supportsReasoning 改 false 的推理模型 | 会从列表消失，与"用户显式说它没推理"一致 |

---

## 8. 文件改动清单

| 路径 | 类型 | 行数估计 |
|------|------|----------|
| `entry/src/main/ets/components/ModelSelector.ets` | 改 | +3 行（@Param + rebuildRows 透传） |
| `entry/src/main/ets/config/ModelListProjection.ets` | 改 | +12 行（3 个函数签名 + 1 个判断 + 包装旧函数） |
| `entry/src/main/ets/components/chat/ChatModelSelectorSheetContent.ets` | 改 | +1 行 |
| `entry/src/main/ets/components/defaultmodel/DefaultModelSelectSheetContent.ets` | 改 | +1 行 |
| `entry/src/main/ets/pages/Index.ets` (`AssistantModelSheetBuilder`) | 改 | +1 行 |
| `entry/src/main/ets/pages/ChatPage.ets` | 改 | +35 行（`selectFirstReasoningModel` + `validateAndSetCurrentModel` 分支） |
| `entry/src/main/ets/utils/ReasoningModelFilter.ets` | 新建 | +15 行 |
| `entry/src/ohosTest/ets/test/ReasoningModelFilter.test.ets` | 新建 | +60 行 |
| `entry/src/main/resources/base/element/string.json` | 改 | +2 条 |
| `docs/superpowers/specs/2026-06-12-chat-model-picker-reasoning-filter-design.md` | 新建 | 本文件 |

**Image gen 调用方 0 改动**。

---

## 9. 验收清单

- [ ] 4 个 `ModelSelectorContent` 调用方中，3 个传 `reasoningOnly: true`，1 个（image gen）不传
- [ ] `buildModelSelectorRowsInternal` 在 `hasOutputModeFilter` 之后插入 reasoning 过滤
- [ ] `validateAndSetCurrentModel` 在 session/saved 命中时**也**校验 reasoning；不通过则落到下一步
- [ ] `selectFirstReasoningModel` 用 `getEffectiveCapabilities` 而非直接读 `model.capabilities`
- [ ] 自动切换时 `applyModelSelection` 第 4 参为 `false`
- [ ] `appStateManager.setCurrentModel` 在自动切换路径**不**触发
- [ ] string.json 新增 2 条 key
- [ ] 新建 `utils/ReasoningModelFilter.ets` + 对应 hypium 测试
- [ ] `hvigorw assembleHap` 跑通
- [ ] 手动场景 §6.3 全部通过
