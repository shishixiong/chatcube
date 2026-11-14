# DeepSeek TTS 引擎接入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 TTS 引擎注册表中新增 `deepseek` 引擎，用 HTTP 整段合成（`POST /v1/tools/tts`，`wav`）朗读文本，复用 `deepseek` 预设服务商的 API Key。

**Architecture:** 沿用 `StepFunTtsEngine` 的「REST 取完整音频 → `AudioPlayerHelper` 临时文件 → AVPlayer」模型：按句切段，逐段「合成→播放」串联，第一段起播上报一次 `onStart`、最后一段播完才 `onComplete`。配置集中在 `config/TtsConfig.ets`，设置页 UI 由 `TtsEngineRegistry` 驱动，无需改动。

**Tech Stack:** ArkTS (HarmonyOS 6 / API 23)、`@kit.NetworkKit` http、`@kit.MediaKit` AVPlayer（经 `AudioPlayerHelper`）、`@ohos/hypium` 测试。

**Spec:** `docs/superpowers/specs/2026-11-14-deepseek-tts-engine-design.md`

## Global Constraints

- 单次请求文本上限 **2000 个 UTF-16 单元**（`DEEPSEEK_MAX_INPUT_CHARS = 2000`）；全中文最坏 4000 计费字符，低于 DeepSeek 的 10,000 上限。
- 请求 `format` 固定 `'wav'`；播放用 `AudioPlayerHelper.playFromBuffer(buffer, cb, 'wav')`。
- 固定 URL `https://api.deepseek.com/v1/tools/tts`，不读服务商 `baseUrl`。
- API Key 只从 `deepseek` 服务商读取；**禁止**硬编码 fallback key。
- `speak(text, callback, speed?)` 的 `speed` 忽略（接口不支持）。
- 所有用户可见错误信息用中文。
- 不新增第三方依赖；不做 WebSocket / 增量播放。
- 不允许解构赋值、对象字面量必须显式标注类型（ArkTS 严格模式）。
- 测试运行：hypium 测试在 DevEco Studio 右键 → Run（`hvigorw test` 在本仓库已知不可用）。CLI 编译门禁是干净 `assembleHap`。
- 未在 `EntryAbility` 等处被引用的新 `.ets` 文件不会被 hvigor 编译——新引擎必须在同一任务内完成注册。

## Review Focus

- **长文本跨段**：>2000 字符的回答必须切成每段 ≤2000、顺序不丢字，逐段播放且不触发 400；由 Task 1 切分测试 + Task 3 手测长文本固定。
- **停止后迟到回调**：用户中途停止后到达的 HTTP 响应 / AVPlayer 回调不得再调用旧 callback；由 Task 3 代码路径 + 手测固定。
- **缺少 API Key**：未配置或空 Key 时引擎列表标不可用并显示原因；强行朗读给中文错误而非 401；由 Task 2 可用性测试 + Task 3 手测固定。
- **多段生命周期**：`onStart` 只触发一次，`onComplete` 只在最后一段播放完成后触发；由 Task 3 手测长文本固定。
- **空文本**：全空白 / 预处理后为空的文本不发起网络请求，直接回调「没有可朗读的内容」；由 Task 1 空文本测试 + Task 3 代码路径固定。
- **代理对安全**：无标点超长文本硬切时不得把 emoji 的 UTF-16 代理对拆成两半；由 Task 1 emoji 测试固定。

---

## File Structure

| 文件 | 责任 |
|------|------|
| `entry/src/main/ets/utils/TtsTextChunkUtils.ets`（新建） | 通用按句切段纯函数 `splitTextForTts` |
| `entry/src/main/ets/utils/StepFunTtsTextUtils.ets`（修改） | 保留 `splitTextForStepFun` 薄包装，委托通用函数 |
| `entry/src/main/ets/config/TtsConfig.ets`（修改） | `deepseek` 引擎 id、provider id、音色、URL、切段上限 |
| `entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets`（修改） | DeepSeek Key 可用性判断 |
| `entry/src/main/ets/services/tts/DeepSeekTtsEngine.ets`（新建） | HTTP 整段合成 + 分段播放引擎 |
| `entry/src/main/ets/entryability/EntryAbility.ets`（修改） | 注册引擎 profile 与工厂 |
| `entry/src/ohosTest/ets/test/utils/TtsTextChunkUtils.test.ets`（新建） | 通用切段测试 |
| `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`（修改） | DeepSeek 可用性用例 |

---

### Task 1: 通用文本切段工具

**Files:**
- Create: `entry/src/main/ets/utils/TtsTextChunkUtils.ets`
- Modify: `entry/src/main/ets/utils/StepFunTtsTextUtils.ets`（整文件改为薄包装）
- Test: `entry/src/ohosTest/ets/test/utils/TtsTextChunkUtils.test.ets`

**Interfaces:**
- Produces: `export function splitTextForTts(text: string, maxChars: number): string[]`
- Keeps: `export function splitTextForStepFun(text: string, maxChars: number): string[]`（委托给 `splitTextForTts`）

- [ ] **Step 1: 写失败测试**

创建 `entry/src/ohosTest/ets/test/utils/TtsTextChunkUtils.test.ets`：

```ts
import { describe, it, expect } from '@ohos/hypium'
import { splitTextForTts } from '../../../../main/ets/utils/TtsTextChunkUtils'
import { splitTextForStepFun } from '../../../../main/ets/utils/StepFunTtsTextUtils'

// 与 DEEPSEEK_MAX_INPUT_CHARS 一致
const MAX: number = 2000

export default function ttsTextChunkUtilsTest() {
  describe('splitTextForTts', () => {
    it('empty string returns empty array', 0, () => {
      expect(splitTextForTts('', MAX).length).assertEqual(0)
    })

    it('whitespace-only returns empty array', 0, () => {
      expect(splitTextForTts('   \n  ', MAX).length).assertEqual(0)
    })

    it('short text returns single unchanged chunk', 0, () => {
      const result = splitTextForTts('你好，小星老师。', MAX)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual('你好，小星老师。')
    })

    it('text exactly maxChars stays single chunk', 0, () => {
      const text = 'a'.repeat(MAX)
      const result = splitTextForTts(text, MAX)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual(text)
    })

    it('2001 ascii chars splits into two chunks within limit', 0, () => {
      const result = splitTextForTts('a'.repeat(2001), MAX)
      expect(result.length).assertEqual(2)
      expect(result[0].length).assertEqual(2000)
      expect(result[1].length).assertEqual(1)
    })

    it('full-width chinese respects the same limit and loses no chars', 0, () => {
      const text = '中'.repeat(2001)
      const result = splitTextForTts(text, MAX)
      expect(result.length).assertEqual(2)
      expect(result[0].length <= MAX).assertTrue()
      expect(result[1].length <= MAX).assertTrue()
      expect(result[0] + result[1]).assertEqual(text)
    })

    it('adjacent short sentences pack into one chunk', 0, () => {
      const text = '第一句。第二句。第三句。'
      const result = splitTextForTts(text, 100)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual(text)
    })

    it('oversized sentence with emoji is not split mid-surrogate', 0, () => {
      const text = 'a'.repeat(1999) + '\u{1F600}'
      const result = splitTextForTts(text, MAX)
      expect(result.length).assertEqual(2)
      expect(result[0].length).assertEqual(1999)
      expect(result[1]).assertEqual('\u{1F600}')
    })

    it('invalid maxChars returns whole text as single chunk', 0, () => {
      const result = splitTextForTts('abc', 0)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual('abc')
      const negative = splitTextForTts('abc', -5)
      expect(negative.length).assertEqual(1)
      expect(negative[0]).assertEqual('abc')
    })

    it('stepfun wrapper delegates to the generic splitter', 0, () => {
      let text = ''
      for (let i = 0; i < 100; i++) {
        text = text + `这是第${i}句测试内容，用于验证切分逻辑。`
      }
      const generic = splitTextForTts(text, 1000)
      const wrapped = splitTextForStepFun(text, 1000)
      expect(wrapped.length).assertEqual(generic.length)
      for (let i = 0; i < generic.length; i++) {
        expect(wrapped[i]).assertEqual(generic[i])
      }
    })
  })
}
```

- [ ] **Step 2: 运行测试确认失败**

在 DevEco Studio 右键该文件 → Run，或运行仓库内 node 测试垫片：

```bash
.superpowers/harness/run-test.sh \
  entry/src/ohosTest/ets/test/utils/TtsTextChunkUtils.test.ets \
  entry/src/main/ets/utils/TtsTextChunkUtils.ets \
  entry/src/main/ets/utils/StepFunTtsTextUtils.ets
```

Expected: FAIL —— 找不到 `TtsTextChunkUtils` 模块（文件尚未创建）。

- [ ] **Step 3: 创建 `utils/TtsTextChunkUtils.ets`**

把 `StepFunTtsTextUtils.ets` 的现有实现原样迁入，函数改名为 `splitTextForTts`，导出它；注释改为「云 TTS 引擎通用按句切段」。语义保持：

1. `trim()` 后为空 → `[]`
2. `maxChars <= 0` → `[trimmed]`
3. 长度 ≤ `maxChars` → `[trimmed]`
4. 按 `。！？! ?；;\n` 切句，贪心把相邻句打包进同一段
5. 单句超长时在 `maxChars` 处硬切；若切点前一位是高代理（`0xD800–0xDBFF`）则回退 1

- [ ] **Step 4: 把 `StepFunTtsTextUtils.ets` 改为薄包装**

```ts
import { splitTextForTts } from './TtsTextChunkUtils'

// StepFun /v1/audio/speech 的 input 上限 1000 字符。
// 实现已提升为通用 splitTextForTts，这里保留旧入口供现有调用方/测试使用。
export function splitTextForStepFun(text: string, maxChars: number): string[] {
  return splitTextForTts(text, maxChars)
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
.superpowers/harness/run-test.sh \
  entry/src/ohosTest/ets/test/utils/TtsTextChunkUtils.test.ets \
  entry/src/main/ets/utils/TtsTextChunkUtils.ets \
  entry/src/main/ets/utils/StepFunTtsTextUtils.ets
```

Expected: `RESULT 10 passed, 0 failed`。DevEco Studio 同样应全部 PASS。

- [ ] **Step 6: 编译主工程**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/utils/TtsTextChunkUtils.ets \
  entry/src/main/ets/utils/StepFunTtsTextUtils.ets \
  entry/src/ohosTest/ets/test/utils/TtsTextChunkUtils.test.ets
git commit -m "refactor(tts): extract generic sentence splitter for cloud TTS engines"
```

---

### Task 2: DeepSeek 配置与可用性

**Files:**
- Modify: `entry/src/main/ets/config/TtsConfig.ets`（文件末尾追加）
- Modify: `entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`

**Interfaces:**
- Produces:
  - `TtsEngineId` 联合新增 `'deepseek'`
  - `export const DEEPSEEK_TTS_PROVIDER_ID: string = 'deepseek'`
  - `export const DEEPSEEK_TTS_VOICES: TtsVoice[]`
  - `export const DEEPSEEK_TTS_CONFIG`（`apiUrl: string; voice: string; audioFormat: string`）
  - `export const DEEPSEEK_MAX_INPUT_CHARS: number = 2000`
- Availability：`profile.id === 'deepseek'` 且找不到 `id === 'deepseek'` 的非空 `apiKey` provider 时不可用。

- [ ] **Step 1: 在现有测试中加失败用例**

在 `TtsEngineAvailability.test.ets` 的 profile 常量区追加：

```ts
const deepseekProfile: TtsEngineProfile = {
  id: 'deepseek',
  displayName: 'DeepSeek 语音',
  description: '使用 DeepSeek TTS 在线朗读',
  requiresApiKey: true,
  iconSymbol: 'sys.symbol.waveform',
  voices: [],
  defaultVoiceId: 'stella'
}
```

在 `describe('evaluateTtsEngineAvailability', ...)` 内追加 4 个用例：

```ts
it('deepseek is disabled when no providers configured', 0, () => {
  const result = evaluateTtsEngineAvailability(deepseekProfile, [])
  expect(result.isEnabled).assertFalse()
  expect(result.unavailableReason).assertContain('DeepSeek')
})

it('deepseek is disabled when DeepSeek exists but no apiKey', 0, () => {
  const result = evaluateTtsEngineAvailability(deepseekProfile, [makeProvider('deepseek', '')])
  expect(result.isEnabled).assertFalse()
})

it('deepseek is enabled when DeepSeek has apiKey', 0, () => {
  const result = evaluateTtsEngineAvailability(deepseekProfile, [makeProvider('deepseek', 'sk-ds')])
  expect(result.isEnabled).assertTrue()
  expect(result.unavailableReason).assertEqual('')
})

it('deepseek is disabled when only other providers have apiKey', 0, () => {
  const result = evaluateTtsEngineAvailability(deepseekProfile, [makeProvider('openai', 'sk-ooo')])
  expect(result.isEnabled).assertFalse()
})
```

- [ ] **Step 2: 运行测试确认失败**

DevEco Studio 右键 `TtsEngineAvailability.test.ets` → Run。

Expected: FAIL —— `deepseek is disabled when no providers configured` 实际 `isEnabled === true`（可用性函数尚无 deepseek 分支）。

- [ ] **Step 3: 追加配置**

`config/TtsConfig.ets`：

```ts
// TTS 引擎 ID 联合改为:
export type TtsEngineId = 'system' | 'mimo' | 'minimax' | 'stepfun' | 'deepseek'

// 文件末尾追加:
// deepseek 引擎绑定的 provider id (复用已有的 DeepSeek 预设服务商)
export const DEEPSEEK_TTS_PROVIDER_ID: string = 'deepseek'

// DeepSeek 引擎支持的音色列表 (官方仅两种, 语种自动识别)
export const DEEPSEEK_TTS_VOICES: TtsVoice[] = [
  { id: 'stella', name: '海星', language: '中文', gender: '女性' },
  { id: 'tide', name: '暗潮', language: '中文', gender: '男性' }
]

// DeepSeek 语音合成配置 (HTTP 整段 /v1/tools/tts, 默认返回 wav)
interface DeepSeekTtsConfig {
  apiUrl: string
  voice: string
  audioFormat: string
}

export const DEEPSEEK_TTS_CONFIG: DeepSeekTtsConfig = {
  apiUrl: 'https://api.deepseek.com/v1/tools/tts',
  voice: 'stella',
  audioFormat: 'wav'
}

// 单段文本上限 (UTF-16 单元)。全中文最坏按 2 倍计费 = 4000 计费字符, 低于 10000 上限
export const DEEPSEEK_MAX_INPUT_CHARS: number = 2000
```

- [ ] **Step 4: 增加可用性分支**

`utils/TtsEngineAvailabilityUtils.ets`：import 中加 `DEEPSEEK_TTS_PROVIDER_ID`，在 `stepfun` 分支后追加：

```ts
// deepseek 复用 DeepSeek provider
if (profile.id === 'deepseek') {
  const matched = providers.find(
    (p) => p.id === DEEPSEEK_TTS_PROVIDER_ID && p.apiKey !== ''
  )
  if (matched === undefined) {
    return {
      profile,
      isEnabled: false,
      unavailableReason: '未配置 DeepSeek API Key, 不可用'
    }
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

DevEco Studio 右键 `TtsEngineAvailability.test.ets` → Run。

Expected: PASS，13 条用例全过。

- [ ] **Step 6: 编译主工程**

同 Task 1 Step 6。Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/config/TtsConfig.ets \
  entry/src/main/ets/utils/TtsEngineAvailabilityUtils.ets \
  entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets
git commit -m "feat(tts): add DeepSeek TTS config and availability check"
```

---

### Task 3: DeepSeek 引擎与注册

**Files:**
- Create: `entry/src/main/ets/services/tts/DeepSeekTtsEngine.ets`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`（import 区 + StepFun 注册块之后）

**Interfaces:**
- Consumes: `ITtsEngine` / `TTSCallback`、`AudioPlayerHelper` / `AudioPlayerCallback`、`splitTextForTts`、`DEEPSEEK_TTS_CONFIG` / `DEEPSEEK_TTS_PROVIDER_ID` / `DEEPSEEK_MAX_INPUT_CHARS` / `DEEPSEEK_TTS_VOICES`、`getAppSettingsState()`
- Produces: `export class DeepSeekTtsEngine implements ITtsEngine`

- [ ] **Step 1: 创建引擎**

新建 `services/tts/DeepSeekTtsEngine.ets`，以 `StepFunTtsEngine.ets` 为模板。必须包含的字段：

```ts
private baseUrl: string = DEEPSEEK_TTS_CONFIG.apiUrl
private speaking: boolean = false
private currentCallback: TTSCallback | null = null
private audioPlayer: AudioPlayerHelper = new AudioPlayerHelper()
private inited: boolean = false
private httpRequest: http.HttpRequest | null = null
private pendingChunks: string[] = []
private chunkIndex: number = 0
private startNotified: boolean = false
private sessionClosed: boolean = false
```

方法签名与行为：

- `async init(context: common.Context): Promise<void>`：`audioPlayer.init(context)`，`inited = true`
- `async speak(text: string, callback: TTSCallback, speed?: number): Promise<void>`：
  1. 未初始化 → `callback.onError('DeepSeek 朗读引擎未初始化')` 并 return
  2. `resolveApiKey()` 为空 → `callback.onError('DeepSeek TTS 缺少 API Key，请先在服务商中配置 DeepSeek')` 并 return
  3. `this.speaking` 为 true → 先 `this.stop()`
  4. 重置 `currentCallback` / `startNotified = false` / `sessionClosed = false` / `chunkIndex = 0`
  5. `pendingChunks = splitTextForTts(text, DEEPSEEK_MAX_INPUT_CHARS)`；长度 0 → `sessionClosed = true`，`callback.onError('没有可朗读的内容')` 并 return
  6. 调 `fetchChunkAndPlay(apiKey)`；`speed` 不使用（不声明任何 speed 相关字段）
- `private fetchChunkAndPlay(apiKey: string): void`：
  - `POST` `this.baseUrl`，header `'Content-Type': 'application/json'` + `'Authorization': \`Bearer ${apiKey}\``，`expectDataType: http.HttpDataType.ARRAY_BUFFER`
  - body 类型：
    ```ts
    interface DeepSeekTtsRequestBody {
      text: string
      voice_id: string
      format: string
      filter_markdown: boolean
    }
    ```
    值：`text = pendingChunks[chunkIndex]`、`voice_id = resolveVoice()`、`format = DEEPSEEK_TTS_CONFIG.audioFormat`、`filter_markdown = true`
  - 响应处理与 `StepFunTtsEngine.fetchChunkAndPlay` 相同：若 `this.httpRequest === httpReq` 置空；`sessionClosed` 为 true 直接丢弃；非 200 → `finishWithError(...)`；空音频 → `finishWithError('DeepSeek TTS 返回空音频数据')`；否则 `playChunk(audioBuffer)`
  - `.catch` 中同样先置空 `httpRequest`，`sessionClosed` 则丢弃，否则 `finishWithError(\`DeepSeek 朗读失败: ${error.message}\`)`
- 非 200 状态码映射（`decodeErrorBody(resp.result)` 得到 detail，非空时用 `, 响应: ${detail}` 追加）：
  - 400 → `DeepSeek TTS 返回 400：文本为空或未通过内容审核`
  - 429 → `DeepSeek TTS 并发请求超过上限，请稍后重试`
  - 503 → `DeepSeek TTS 服务繁忙，请稍后重试`
  - 504 → `DeepSeek TTS 合成超时`
  - 其他 → `DeepSeek TTS API 返回状态码: ${resp.responseCode}`
- `private playChunk(audioBuffer: ArrayBuffer): void`：回调对象 `AudioPlayerCallback`
  - `onStart`：仅 `!startNotified` 时置 true、`speaking = true`、调当前 callback 的 `onStart` 一次
  - `onComplete`：`chunkIndex++`；若未到末尾，重新 `resolveApiKey()`（空则 `finishWithError`）后 `fetchChunkAndPlay`；否则 `finishWithComplete()`
  - `onError`：`finishWithError(error)`
  - 调 `this.audioPlayer.playFromBuffer(audioBuffer, audioCallback, DEEPSEEK_TTS_CONFIG.audioFormat)`，同步异常用 try/catch 包住 → `finishWithError(\`音频播放器启动失败: ${JSON.stringify(syncErr)}\`)`
- `private finishWithComplete()`：`sessionClosed = true`、`speaking = false`、清空 `pendingChunks`、取出并清空 `currentCallback`、调 `onComplete`
- `private finishWithError(message: string)`：`sessionClosed` 已 true 则直接 return；`console.error('DeepSeekTtsEngine', message)`；置 `sessionClosed` / `speaking = false` / 清空队列；销毁 `httpRequest`；取出并清空 `currentCallback`、调 `onError(message)`
- `stop()`：`sessionClosed = true`；销毁并置空 `httpRequest`；`audioPlayer.stop()`；`speaking = false`；`currentCallback = null`；清空队列与 `chunkIndex`
- `isSpeaking(): boolean`：返回 `this.speaking`
- `destroy()`：`stop()` + `audioPlayer.destroy()` + `inited = false`
- `private resolveApiKey(): string`：`getAppSettingsState().providers.find((p) => p.id === DEEPSEEK_TTS_PROVIDER_ID && p.apiKey !== '')`，未命中返回 `''`
- `private resolveVoice(): string`：读 `getAppSettingsState().ttsVoiceByEngine['deepseek']`，非空返回；否则 `DEEPSEEK_TTS_CONFIG.voice`
- `private decodeErrorBody(result: string | Object | ArrayBuffer): string`：与 `StepFunTtsEngine` 相同（ArrayBuffer 用 `util.TextDecoder` 解 utf-8；string 原样；其他空串）

- [ ] **Step 2: 在 `EntryAbility.ets` 注册**

import 区追加：

```ts
import { DeepSeekTtsEngine } from '../services/tts/DeepSeekTtsEngine';
```

在 StepFun 的 `registerTtsEngine({...})` 之后、`hilog.info(... 'TTS engines registered successfully')` 之前追加：

```ts
registerTtsEngine({
  profile: {
    id: 'deepseek',
    displayName: 'DeepSeek 语音',
    description: 'DeepSeek TTS（海星 / 暗潮），复用 DeepSeek API Key，需要联网',
    requiresApiKey: true,
    iconSymbol: 'sys.symbol.waveform',
    voices: DEEPSEEK_TTS_VOICES,
    defaultVoiceId: 'stella'
  },
  factory: () => new DeepSeekTtsEngine()
});
```

同时把 `DEEPSEEK_TTS_VOICES` / `DEEPSEEK_TTS_CONFIG` 加进 `EntryAbility.ets` 已有的 `config/TtsConfig` import 列表（若该文件是按名 import）。

- [ ] **Step 3: 编译主工程**

同 Task 1 Step 6。

Expected: `BUILD SUCCESSFUL`。因为 `EntryAbility` 已 import 引擎，编译会真正检查新文件（避免「未引用文件不编译」的假绿）。

- [ ] **Step 4: 真机手测**

安装 debug HAP，逐项确认：

1. 设置 → 默认模型 → 朗读引擎列表出现「DeepSeek 语音」；已配 Key 时可用，未配 Key 时置灰并显示「未配置 DeepSeek API Key, 不可用」
2. 选中 DeepSeek 语音 → 音色列表「中文」分组下有「海星」「暗潮」，默认高亮「海星」
3. 短回答点朗读 → 正常出声
4. 长回答（>2000 字）→ 连续播放多段，不报错、不丢段；`onStart` 只让 UI 进入一次播放态，最后一段结束才恢复
5. 播放中切换页面 / 点停止 → 立即静音；之后不再出现旧音频或错误回调
6. 切回系统朗读再切回 DeepSeek → 正常
7. 清空 DeepSeek Key → 重新进入设置，引擎不可用且不可选中

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/services/tts/DeepSeekTtsEngine.ets \
  entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat(tts): add DeepSeek TTS engine"
```

---

## Self-Review

- **Spec coverage**：配置（Task 2）、切段（Task 1）、引擎行为/错误映射/分段生命周期（Task 3）、可用性（Task 2）、注册（Task 3）、测试与手测（各任务）均已覆盖；WS 流式明确不在范围。
- **类型一致性**：`splitTextForTts(text, maxChars)`、`DEEPSEEK_MAX_INPUT_CHARS`、`DEEPSEEK_TTS_CONFIG.apiUrl/voice/audioFormat`、`DeepSeekTtsEngine implements ITtsEngine` 在任务间一致。
- **Review Focus**：每条均指向 Task 1/2 的单元测试或 Task 3 的手测步骤。
- **比例**：计划以接口、值和行为清单为主，未转录完整引擎实现。
