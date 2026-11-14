# DeepSeek TTS 引擎接入 — 设计（短设计）

**日期：** 2026-11-14
**范围：** 在现有 TTS 引擎注册表中新增 `deepseek` 引擎（HTTP 整段合成，缓冲后播放），复用 `deepseek` 预设服务商的 API Key
**状态：** 待确认

---

## 1. 目标与理由

用户希望把 DeepSeek 的语音合成（`POST https://api.deepseek.com/v1/tools/tts`）接成应用内可选的朗读引擎，与现有的系统 / MiMo / MiniMax / StepFun 引擎并列，在「设置 → 默认模型 → 朗读引擎」里可切换。

**成功标准**：配置了 DeepSeek API Key 的用户能在朗读引擎列表里看到并选中「DeepSeek 语音」，聊天回答与卡片旁白能正常朗读；未配置 Key 时引擎显示为不可用并给出原因。

**非目标**：
- 不做 WebSocket 流式合成（`wss://.../v1/tools/tts`）。现有四个云引擎都是「整段缓冲 → AVPlayer 播放」，播放器只接受完整音频文件；WS 需要另建增量 PCM 播放链路（AudioRenderer 边收边播），成本与风险明显更高。对话回答通常很短，HTTP 整段的体验与现有引擎一致。已与用户确认按 HTTP 整段实现。
- 不支持语速调节（DeepSeek 接口无此参数），`speak()` 的 `speed` 入参忽略。
- 不新增服务商配置页（`deepseek` 预设服务商已存在，用户在其中填 Key 即可）。
- 不改设置页 UI（引擎/音色选择器完全由注册表驱动）。

---

## 2. 约束

| 约束 | 来源 | 影响 |
|------|------|------|
| 单次最多 10,000 计费字符（汉字算 2，其他算 1） | DeepSeek 文档 | 长文本必须切段；每段上限取 2000 个 UTF-16 单元（全中文最坏 4000 计费字符） |
| 请求体 ≤ 64 KiB | 同上 | 2000 个中文 UTF-8 约 6 KB，安全 |
| 单次合成音频 ≤ 30 分钟 | 同上 | 2000 汉字约 7 分钟，安全 |
| 音色仅 `stella`（女声，默认）/ `tide`（男声），语种自动识别 | 同上 | 音色列表只有两项；无语言参数 |
| `format` 支持 `wav`（默认）/ `pcm`（24 kHz、16-bit、单声道） | 同上 | 用 `wav`，`AudioPlayerHelper.playFromBuffer(..., 'wav')` 可直接播 |
| 错误码 400 / 429 / 503 / 504 | 同上 | 映射为可读中文错误信息 |
| 现有引擎均为「收集完整音频 → 临时文件 → AVPlayer」 | 项目现状 | DeepSeek 引擎沿用同一模型，不做增量播放 |

---

## 3. 方案对比（已选）

| 方案 | 做法 | 取舍 |
|------|------|------|
| **A. HTTP 整段（选中）** | POST `/v1/tools/tts` 取完整 `wav`，按句切段、逐段「合成→播放」 | 与现有引擎同构，改动小；首音延迟 = 单段合成时间，长文本段间有轻微停顿 |
| B. WebSocket 流式 | WS 收 PCM/Opus 帧，边收边播 | 首音最快；需新建流式 PCM 播放链路、会话状态机、重连/中断处理，工作量约为 A 的数倍，且与现有播放器抽象不兼容 |
| C. 只做单次请求不切段 | 一次请求全文 | 最简单；但 5000+ 汉字会超 10,000 计费字符上限，长回答直接失败 |

**选择 A**：满足需求且与项目架构一致；C 在长文本上不可靠。

---

## 4. 设计

### 4.1 配置（`config/TtsConfig.ets`）

- `TtsEngineId` 联合追加 `'deepseek'`
- 新增 `DEEPSEEK_TTS_PROVIDER_ID: string = 'deepseek'`（复用已有预设服务商，见 `config/PresetProviders.ets:45`）
- 新增 `DEEPSEEK_TTS_VOICES: TtsVoice[]`：
  - `stella` /「海星」/ 中文 / 女性
  - `tide` /「暗潮」/ 中文 / 男性
- 新增 `DEEPSEEK_TTS_CONFIG`：`apiUrl = 'https://api.deepseek.com/v1/tools/tts'`、`voice = 'stella'`、`audioFormat = 'wav'`
- 新增 `DEEPSEEK_MAX_INPUT_CHARS = 2000`（引擎切段上限）
- 固定官方 URL，不读服务商 `baseUrl` —— 与 StepFun / MiniMax 引擎一致；如需代理可后续单独加配置项

### 4.2 文本切段（`utils/TtsTextChunkUtils.ets`）

- 把 `StepFunTtsTextUtils.ets` 的实现提升为通用纯函数 `splitTextForTts(text, maxChars)`：
  按 `。！？! ?；;\n` 切句 → 贪心打包 → 单句超长时硬切且不拆 UTF-16 代理对
- `StepFunTtsTextUtils.ets` 保留为薄包装（`splitTextForStepFun` 委托给 `splitTextForTts`），现有调用方与测试零改动
- DeepSeek 引擎使用 `splitTextForTts(text, DEEPSEEK_MAX_INPUT_CHARS)`

### 4.3 引擎（`services/tts/DeepSeekTtsEngine.ets`）

结构镜像 `StepFunTtsEngine`：

- `init(context)`：初始化 `AudioPlayerHelper`
- `speak(text, callback, speed?)`：
  1. 未初始化 → `onError('DeepSeek 朗读引擎未初始化')`
  2. 从 `providers` 中找 `id === 'deepseek'` 且 `apiKey !== ''`；缺失 → `onError('DeepSeek TTS 缺少 API Key，请先在服务商中配置 DeepSeek')`
  3. 若正在朗读先 `stop()`
  4. 切段；空文本 → `onError('没有可朗读的内容')`
  5. 记录 callback，`speed` 忽略（接口不支持），逐段 `fetchChunkAndPlay`
- 请求：`POST DEEPSEEK_TTS_CONFIG.apiUrl`，头 `Content-Type: application/json` + `Authorization: Bearer <key>`，`expectDataType: ARRAY_BUFFER`
- 请求体：`{ text, voice_id, format: 'wav', filter_markdown: true }`（TTSService 已做 Markdown 预处理，保留服务端过滤作兜底）
- 响应：200 且非空 → `AudioPlayerHelper.playFromBuffer(buffer, cb, 'wav')`；非 200 → 解码错误体并按状态码给出可读信息（400 文本为空/内容审核、429 并发超限、503 繁忙、504 超时，其他附原始响应）
- 多段串联：第一段起播上报一次 `onStart`；每段播放完成取下一段；最后一段完成才 `onComplete`
- 会话守卫：`sessionClosed` 标志丢弃 `stop()` 后迟到的网络/播放回调；`stop()` 销毁 `HttpRequest`、停播放器、清空队列
- `resolveVoice()`：读 `ttsVoiceByEngine['deepseek']`，未配置回退 `DEEPSEEK_TTS_CONFIG.voice`
- `destroy()`：`stop()` + `audioPlayer.destroy()` + `inited = false`

### 4.4 可用性（`utils/TtsEngineAvailabilityUtils.ets`）

`profile.id === 'deepseek'` 时检查 `providers` 中 `id === 'deepseek'` 且 `apiKey !== ''`；未配置返回不可用，原因「未配置 DeepSeek API Key, 不可用」。

### 4.5 注册（`entryability/EntryAbility.ets`）

在 StepFun 之后追加：

```
id: 'deepseek'
displayName: 'DeepSeek 语音'
description: 'DeepSeek TTS（stella / tide），复用 DeepSeek API Key，需要联网'
requiresApiKey: true
iconSymbol: 'sys.symbol.waveform'
voices: DEEPSEEK_TTS_VOICES
defaultVoiceId: 'stella'
factory: () => new DeepSeekTtsEngine()
```

设置页引擎列表与音色选择器由注册表驱动，无需改动。

---

## 5. 测试与验证

- `entry/src/ohosTest/ets/test/utils/TtsEngineAvailability.test.ets`：新增 deepseek profile 与 4 个用例（无 provider / 有 provider 无 Key / 有 Key / 只有其他 provider 有 Key）
- `StepFunTtsTextUtils.test.ets`：补一条 `splitTextForTts` 与 `splitTextForStepFun` 结果一致的用例（通用函数复用原有 12 条切分用例的覆盖）
- 编译验证：`hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
- 真机手测：配置 DeepSeek Key → 选中 DeepSeek 语音 → 朗读短回答 / 长回答（>2000 字）→ 中途停止 → 切换引擎

---

## 6. 留给实现者的决定

- 错误信息的具体措辞、日志前缀
- 切段上限常量是否需要在实现中再下调（首音延迟 vs 请求数）
- 是否补一个引擎级单测（需要 mock HTTP，项目暂无此类基建，默认不加）
