# 音符小耳朵（music_ear）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给小星游戏老师（`kids_games`）新增 `music_ear` 音乐听觉小游戏：原生 PCM 合音、自由敲琴热身、三种耳朵练习（高低 / 复述 / 猜歌）、星星结算与 AI 集成。

**Architecture:** 纯逻辑（题目生成、计分、PCM 波形、混音）放在 `utils/` 下可单测的纯函数里；`services/MusicToneService.ets` 只做 AudioRenderer 薄封装；`components/MusicEarCard.ets` 负责三页状态机（free / round / summary）；工具走现有 pending-answer 流程，只锁进 `kids_games`。

**Tech Stack:** ArkTS / ArkUI V2（`@ComponentV2`）、`@ohos.multimedia.audio` AudioRenderer（48kHz / 双声道 / S16LE / `STREAM_USAGE_GAME`）、SQLite `star_events`、hypium。

**Spec:** `docs/superpowers/specs/2026-11-07-music-ear-training-game-design.md`

## Global Constraints

- HarmonyOS 6 / API 23；不新增第三方依赖，不使用 WebView。
- 工具名固定 `music_ear`；常量 `MUSIC_EAR_TOOL_ID`；卡片 `MusicEarCard`；结果 `MusicEarResult`；音频服务 `MusicToneService`。
- 只加入 `KIDS_GAMES_LOCKED_TOOL_IDS`，不加入 default / 数学 / 英语 / 语文老师。
- ArkTS 严格模式：禁止解构（10605074）；`arr.map(p => ({...}))` 内联对象字面量必须显式标注返回类型（10605038）；ForEach 回调体内不得声明 `const`（10905209）；`Record<MusicNote, number>` 的键必须加引号（`'C': 261.63`）。
- 工具 schema 的 `rawSchemaJson` 模板字符串内，描述文字一律用 `「」`，禁止 ASCII 双引号；改完必须跑 JSON.parse gauntlet。
- `sys.symbol` 只用白名单；本功能用 `speaker_wave_2`。
- 音频参数固定：采样率 48000、双声道、`SAMPLE_FORMAT_S16LE`、`ENCODING_TYPE_RAW`、`StreamUsage.STREAM_USAGE_GAME`、最多 8 个同时发声 voice。
- 儿童端视觉固定暖色绘本皮肤（`docs/brand-spec.md`），不随深色模式反转；触控目标 ≥ 44vp。
- 测试在 DevEco Studio 中右键测试文件运行（`hvigorw test` 在本仓库不可用）；编译门禁为 `hvigorw assembleHap`。
- 提交信息用 `feat(kids): ...` / `test(kids): ...` 前缀。

## Review Focus

1. **关闭 sheet 未作答**：工具必须回传 `cancelled` 并 resolve pending Promise，否则整段对话卡死。提交权归卡片：Task 11 的 `aboutToDisappear` 是唯一兜底，Task 12 的 ChatPage **不得**再提交一次。
2. **重复提交**：结算页「再来一轮」后再次关闭，不能出现第二次 `onAnswer`。由 Task 11 的 `submitted` 标志覆盖（同一组件实例存活期间闸门不失效）。
3. **PCM 字节布局**：回调写错帧数/声道/字节序会变成噪音或静音。由 Task 3 的混音单测 + 真机试听覆盖。
4. **星星标签回落**：漏改 `StarEventModels.ets` 任一漂移点，今日星星会显示成别的活动。由 Task 7 的 4-grep + 元数据单测覆盖。
5. **出题边界**：`high_low` 同音、`guess_song` 选项重复或缺答案、`echo` 长度越界。由 Task 1 的单测覆盖。
6. **低龄可读性**：选项只有文字时 5 岁孩子无法作答。由 Task 9 的图标布局清单覆盖。

---

## File Structure

**新建**

| 文件 | 职责 |
|------|------|
| `entry/src/main/ets/utils/MusicEarData.ets` | 音符/频率/琴键/歌单/音色常量 |
| `entry/src/main/ets/utils/MusicEarLogic.ets` | SeededRng、三种题目生成、判分、星级、最好一轮选择 |
| `entry/src/main/ets/utils/MusicEarValidation.ets` | 工具参数预校验 |
| `entry/src/main/ets/utils/MusicToneSynth.ets` | 纯 PCM 波形/包络渲染 |
| `entry/src/main/ets/utils/MusicVoiceMixer.ets` | 纯排期与混音 |
| `entry/src/main/ets/services/MusicToneService.ets` | AudioRenderer 薄封装 + 静音/释放 |
| `entry/src/main/ets/components/MusicEarCard.ets` | 三页游戏卡片 |
| `entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets` | 题目/计分单测 |
| `entry/src/ohosTest/ets/test/utils/MusicEarValidation.test.ets` | 参数校验单测 |
| `entry/src/ohosTest/ets/test/utils/MusicToneSynth.test.ets` | 波形单测 |
| `entry/src/ohosTest/ets/test/utils/MusicVoiceMixer.test.ets` | 混音单测 |

**修改**

`utils/SearchToolIdentityUtils.ets`、`config/BuiltinTools.ets`、`services/ToolExecutionService.ets`、`models/StarEventModels.ets`、`services/StarRewardService.ets`、`models/AssistantModels.ets`、`components/MessageBubble.ets`、`pages/ChatPage.ets`、`entry/src/ohosTest/ets/test/List.test.ets`、`CLAUDE.md`、`.claude/rules/teaching-architecture.md`。

---

### Task 1: 音高数据与纯逻辑

**Files:**
- Create: `entry/src/main/ets/utils/MusicEarData.ets`
- Create: `entry/src/main/ets/utils/MusicEarLogic.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: 无
- Produces:
  - `type MusicNote = 'C' | 'D' | 'E' | 'F' | 'G' | 'A'`
  - `type MusicTimbre = 'piano' | 'xylophone' | 'musicbox'`
  - `type MusicDrill = 'high_low' | 'echo' | 'guess_song'`
  - `MUSIC_NOTE_ORDER: MusicNote[]`、`MUSIC_NOTE_FREQ: Record<MusicNote, number>`、`MUSIC_KEYS: MusicKeyDef[]`、`MUSIC_SONGS: MusicSongDef[]`、`MUSIC_TIMBRES: MusicTimbreDef[]`、`MUSIC_QUESTIONS_PER_ROUND = 5`
  - `class SeededRng { constructor(seed: number); next(): number; nextInt(maxExclusive: number): number }`
  - `interface HighLowQuestion { first: MusicNote; second: MusicNote; answer: 'first' | 'second' | 'same'; pairKey: string }`（`pairKey` 为两音排序后的 `'C|E'` 形式）
  - `interface GuessSongQuestion { songKey: string; optionSongKeys: string[]; answerSongKey: string; noteCount: number }`
  - `interface EchoEvaluation { correct: boolean; firstWrongIndex: number }`
  - `interface RoundScore { correct: number; firstTryCorrect: number }`
  - `interface RoundSnapshot { drill: MusicDrill; difficulty: number; total: number; correct: number; firstTryCorrect: number; songs: string[] }`
  - `buildHighLowQuestion(difficulty: number, rng: SeededRng, usedPairKeys?: string[]): HighLowQuestion`
  - `buildEchoSequence(difficulty: number, rng: SeededRng): MusicNote[]`
  - `buildGuessSongQuestion(difficulty: number, rng: SeededRng, usedSongKeys: string[]): GuessSongQuestion`
  - `evaluateEcho(expected: MusicNote[], pressed: MusicNote[]): EchoEvaluation`
  - `noteProfileDistance(a: MusicNote[], b: MusicNote[]): number`
  - `scoreRound(firstTryResults: boolean[]): RoundScore`
  - `computeMusicEarStars(difficulty: number, total: number, firstTryCorrect: number): number`
  - `pickBestRound(rounds: RoundSnapshot[]): RoundSnapshot | null`
  - `clampDifficulty(value: number): number`、`normalizeDrill(value: string): MusicDrill`

- [ ] **Step 1: 写失败测试**

`entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets`：

```ts
import { describe, it, expect } from '@ohos/hypium'
import {
  SeededRng, buildHighLowQuestion, buildEchoSequence, buildGuessSongQuestion,
  evaluateEcho, scoreRound, computeMusicEarStars, pickBestRound, noteProfileDistance,
  RoundSnapshot
} from '../../../../main/ets/utils/MusicEarLogic'
import { MUSIC_NOTE_ORDER, MUSIC_SONGS, MusicNote } from '../../../../main/ets/utils/MusicEarData'

function indexOf(note: string): number {
  return MUSIC_NOTE_ORDER.indexOf(note as MusicNote)
}

function notes(values: string[]): MusicNote[] {
  const out: MusicNote[] = []
  for (let i = 0; i < values.length; i++) {
    out.push(values[i] as MusicNote)
  }
  return out
}

export default function musicEarLogicTest() {
  describe('MusicEarLogic', () => {
    it('high_low_difficulty_1_uses_wide_interval', 0, () => {
      for (let seed = 1; seed <= 30; seed++) {
        const q = buildHighLowQuestion(1, new SeededRng(seed))
        expect(Math.abs(indexOf(q.first) - indexOf(q.second)) >= 3).assertTrue()
        expect(q.answer === 'same').assertFalse()
      }
    })

    it('high_low_difficulty_3_can_be_same_note', 0, () => {
      let sawSame = false
      for (let seed = 1; seed <= 200; seed++) {
        const q = buildHighLowQuestion(3, new SeededRng(seed))
        const distance = Math.abs(indexOf(q.first) - indexOf(q.second))
        if (q.answer === 'same') {
          sawSame = true
          expect(distance).assertEqual(0)
        } else {
          expect(distance).assertEqual(1)
        }
      }
      expect(sawSame).assertTrue()
    })

    it('high_low_round_has_no_repeated_pair', 0, () => {
      const used: string[] = []
      for (let i = 0; i < 5; i++) {
        const q = buildHighLowQuestion(1, new SeededRng(100 + i), used)
        expect(used.indexOf(q.pairKey)).assertEqual(-1)
        used.push(q.pairKey)
      }
    })

    it('echo_lengths_follow_difficulty', 0, () => {
      expect(buildEchoSequence(1, new SeededRng(7)).length).assertEqual(3)
      expect(buildEchoSequence(2, new SeededRng(7)).length).assertEqual(4)
      expect(buildEchoSequence(3, new SeededRng(7)).length).assertEqual(5)
    })

    it('guess_song_options_are_unique_and_contain_answer', 0, () => {
      for (let difficulty = 1; difficulty <= 3; difficulty++) {
        const q = buildGuessSongQuestion(difficulty, new SeededRng(11 + difficulty), [])
        expect(q.optionSongKeys.length).assertEqual(difficulty + 2)
        for (let i = 0; i < q.optionSongKeys.length; i++) {
          expect(q.optionSongKeys.indexOf(q.optionSongKeys[i])).assertEqual(i)
        }
        expect(q.optionSongKeys.indexOf(q.answerSongKey) >= 0).assertTrue()
      }
    })

    it('guess_song_avoids_used_songs', 0, () => {
      const used: string[] = ['twinkle', 'tigers']
      const q = buildGuessSongQuestion(1, new SeededRng(3), used)
      expect(used.indexOf(q.answerSongKey)).assertEqual(-1)
    })

    it('evaluate_echo_reports_first_wrong_index', 0, () => {
      const result = evaluateEcho(notes(['C', 'D', 'E']), notes(['C', 'E', 'E']))
      expect(result.correct).assertFalse()
      expect(result.firstWrongIndex).assertEqual(1)
      expect(evaluateEcho(notes(['C', 'D']), notes(['C', 'D'])).correct).assertTrue()
    })

    it('note_profile_distance_rewards_similar_contours', 0, () => {
      const song = MUSIC_SONGS[0]
      expect(noteProfileDistance(song.notes, song.notes)).assertEqual(0)
      expect(noteProfileDistance(notes(['C', 'C']), notes(['A', 'A']))).assertEqual(10)
    })

    it('score_round_counts_first_try', 0, () => {
      const score = scoreRound([true, false, true, true, true])
      expect(score.correct).assertEqual(5)
      expect(score.firstTryCorrect).assertEqual(4)
    })

    it('star_rules_follow_difficulty_and_accuracy', 0, () => {
      expect(computeMusicEarStars(1, 5, 5)).assertEqual(2)
      expect(computeMusicEarStars(2, 5, 5)).assertEqual(3)
      expect(computeMusicEarStars(3, 5, 4)).assertEqual(3)
      expect(computeMusicEarStars(2, 5, 3)).assertEqual(1)
      expect(computeMusicEarStars(2, 0, 0)).assertEqual(0)
    })

    it('pick_best_round_prefers_highest_first_try', 0, () => {
      const a: RoundSnapshot = { drill: 'echo', difficulty: 2, total: 5, correct: 5, firstTryCorrect: 3, songs: [] }
      const b: RoundSnapshot = { drill: 'echo', difficulty: 2, total: 5, correct: 5, firstTryCorrect: 5, songs: [] }
      expect(pickBestRound([a, b])?.firstTryCorrect).assertEqual(5)
      expect(pickBestRound([])).assertNull()
    })

    it('song_table_is_complete', 0, () => {
      expect(MUSIC_SONGS.length).assertEqual(6)
    })
  })
}
```

- [ ] **Step 2: 注册测试并确认失败**

在 `List.test.ets` 顶部加 `import musicEarLogicTest from './utils/MusicEarLogic.test'`，在 `testsuite()` 末尾加 `musicEarLogicTest();`。DevEco Studio 右键 `MusicEarLogic.test.ets` → Run。预期：编译失败，提示找不到 `MusicEarLogic`。

- [ ] **Step 3: 实现数据表**

`MusicEarData.ets`：

- 类型：`MusicKeyDef { note: MusicNote; fruit: string; emoji: string; color: string; ink: string; pale: string }`；`MusicSongDef { key: string; name: string; emoji: string; notes: MusicNote[] }`；`MusicTimbreDef { id: MusicTimbre; name: string }`。全部 `export`。
- `MUSIC_NOTE_ORDER = ['C','D','E','F','G','A']`（标注 `: MusicNote[]`）
- `MUSIC_NOTE_FREQ` 用带引号键：`'C': 261.63, 'D': 293.66, 'E': 329.63, 'F': 349.23, 'G': 392.00, 'A': 440.00`
- `MUSIC_KEYS` 六项（`color / ink / pale`）：C 小苹果 🍎 `#FF9A9A / #E24A4A / #FFC9C9`；D 小橘子 🍊 `#FFC078 / #DE7A22 / #FFE0B8`；E 小太阳 ☀️ `#FFE066 / #C99A00 / #FFF3B8`；F 小叶子 🍃 `#9BE9A8 / #2F9550 / #CFF5D6`；G 小水滴 💧 `#8FD3FF / #2A82C9 / #C9EBFF`；A 小葡萄 🍇 `#C3A6FF / #7150CE / #E2D5FF`
- `MUSIC_SONGS` 六首，**音符逐字照抄参考工程**（`key / name / emoji / notes`）：
  - `twinkle` 小星星 ⭐ `['C','C','G','G','A','A','G','F','F','E','E','D','D','C']`
  - `tigers` 两只老虎 🐯 `['C','D','E','C','C','D','E','C','E','F','G','E','F','G']`
  - `ode` 欢乐颂 🎵 `['E','E','F','G','G','F','E','D','C','C','D','E','E','D','D']`
  - `mary` 小羊羔 🐑 `['E','D','C','D','E','E','E','D','D','D','E','G','G']`
  - `row` 划小船 ⛵ `['C','C','C','D','E','E','D','E','F','G']`
  - `bee` 小蜜蜂 🐝 `['G','E','E','F','D','D','C','D','E','F','G','G','G']`
- `MUSIC_TIMBRES = [{ id: 'piano', name: '钢琴' }, { id: 'xylophone', name: '木琴' }, { id: 'musicbox', name: '八音盒' }]`
- `MUSIC_QUESTIONS_PER_ROUND = 5`

`MusicSongDef.notes` 是 `MusicNote[]`，上面的字面量数组要显式标注类型再赋值，否则 ArkTS 推开成 `string[]`。

- [ ] **Step 4: 实现纯逻辑**

`MusicEarLogic.ets`：

- `SeededRng` 用 LCG：`state = (state * 1664525 + 1013904223) % 4294967296`，`next()` 返回 `state / 4294967296`。
- `clampDifficulty`：非有限数或非整数取 1，再 clamp 到 1~3。
- `normalizeDrill`：`high_low` / `highlow` / `high-low` / `pitch` → `high_low`；`echo` / `repeat` / `memory` → `echo`；`guess_song` / `guess` / `song` → `guess_song`；其他 → `high_low`。
- `buildHighLowQuestion`：难度 1 选距离 ≥3 的两键；难度 2 距离 2；难度 3 距离 1，且 `rng.nextInt(100) < 25` 时两音相同、`answer='same'`。`answer` 由索引比较得出。`pairKey` 为两音按 `MUSIC_NOTE_ORDER` 排序后 `'C|E'`；若 `usedPairKeys` 非空，最多重试 40 次避开其中已有的 `pairKey`，40 次仍命中则放行（6 个音只有 21 个无序对，难度 1 只有 6 个，必须允许放行而非死循环）。
- `buildEchoSequence`：长度 `difficulty + 2`；相邻音不重复；音符随机取自六键。
- `noteProfileDistance(a, b)`：取 `min(a.length, b.length)` 个音，累加两两 `Math.abs(indexOf(a[i]) - indexOf(b[i]))`，返回整数和。
- `buildGuessSongQuestion`：可用歌单 = 未出现在 `usedSongKeys` 里的歌，若为空则用全部；答案从可用歌单随机；选项数 `difficulty + 2`，其余候选从**全部 6 首**里按 `noteProfileDistance(答案, 候选)` 升序取前 `difficulty + 1` 首（干扰项优先音符走向相近，规格 §4.3），保证去重且一定凑得满；答案 + 干扰项拼好后用 rng 做一次 Fisher–Yates 洗牌（答案位置不能固定）；`noteCount = Math.min(5 + difficulty, answerSong.notes.length)`。
- `evaluateEcho`：逐位比较，返回首个不匹配索引；长度不同时以较短为准，且 `correct=false`。
- `scoreRound`：`correct = firstTryResults.length`（每道题最终都必须答对才前进），`firstTryCorrect = true 的个数`。
- `computeMusicEarStars`：`total <= 0` → 0；`firstTryCorrect >= Math.ceil(total * 0.8)` → `Math.min(3, difficulty + 1)`；否则 1。
- `pickBestRound`：按 `firstTryCorrect` 取最大，平手保留先出现的那轮；空数组返回 `null`。

- [ ] **Step 5: 跑测试**

DevEco Studio 右键 `MusicEarLogic.test.ets` → Run。预期：全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/utils/MusicEarData.ets entry/src/main/ets/utils/MusicEarLogic.ets entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(kids): add music ear game data and pure logic"
```

---

### Task 2: PCM 波形合成

**Files:**
- Create: `entry/src/main/ets/utils/MusicToneSynth.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MusicToneSynth.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: `MusicTimbre` from `MusicEarData`
- Produces:
  - `type OscillatorWave = 'sine' | 'triangle'`
  - `interface VoiceSpec { freq: number; gain: number; durationSec: number; attackSec: number; wave: OscillatorWave }`
  - `buildTimbreVoices(timbre: MusicTimbre, baseFreq: number): VoiceSpec[]`
  - `renderVoiceInto(out: Float32Array, startSample: number, spec: VoiceSpec, sampleRate: number): number` — 把波形**叠加**进 `out`；`startSample` 可为负（窗口从音中途开始），返回写入的采样数。

- [ ] **Step 1: 写失败测试**

```ts
import { describe, it, expect } from '@ohos/hypium'
import { buildTimbreVoices, renderVoiceInto, VoiceSpec } from '../../../../main/ets/utils/MusicToneSynth'

function peak(out: Float32Array): number {
  let max = 0
  for (let i = 0; i < out.length; i++) {
    const v = Math.abs(out[i])
    if (v > max) max = v
  }
  return max
}

export default function musicToneSynthTest() {
  describe('MusicToneSynth', () => {
    it('timbre_voice_counts', 0, () => {
      expect(buildTimbreVoices('piano', 440).length).assertEqual(3)
      expect(buildTimbreVoices('xylophone', 440).length).assertEqual(3)
      expect(buildTimbreVoices('musicbox', 440).length).assertEqual(4)
    })

    it('harmonics_scale_with_base_frequency', 0, () => {
      const voices = buildTimbreVoices('musicbox', 440)
      expect(Math.abs(voices[0].freq - 440) < 0.01).assertTrue()
      expect(Math.abs(voices[1].freq - 440 * 2.76) < 0.01).assertTrue()
    })

    it('renders_non_silent_audio_without_clipping', 0, () => {
      const out = new Float32Array(48000)
      const voices = buildTimbreVoices('piano', 440)
      for (let i = 0; i < voices.length; i++) {
        renderVoiceInto(out, 0, voices[i], 48000)
      }
      const p = peak(out)
      expect(p > 0.05).assertTrue()
      expect(p < 1.0).assertTrue()
      for (let i = 0; i < out.length; i++) {
        expect(Number.isNaN(out[i])).assertFalse()
      }
    })

    it('handles_negative_start_offset', 0, () => {
      const out = new Float32Array(480)
      const spec: VoiceSpec = { freq: 440, gain: 0.2, durationSec: 1, attackSec: 0.005, wave: 'sine' }
      renderVoiceInto(out, -240, spec, 48000)
      expect(peak(out) > 0).assertTrue()
    })
  })
}
```

- [ ] **Step 2: 注册并确认失败**

`List.test.ets` 加 import 与调用；DevEco 运行。预期：找不到 `MusicToneSynth`。

- [ ] **Step 3: 实现**

- `buildTimbreVoices` 严格按规格 §6.2 的谐波配方返回数组，**gain 写死为下列值**（三音色各自总和都 < 0.92，保证单音不削顶）：piano `[0.55 三角 1×, 0.22 正弦 2×, 0.12 正弦 3×]`；xylophone `[0.60 正弦 1×, 0.20 正弦 3×, 0.10 正弦 4.2×]`；musicbox `[0.45 正弦 1×, 0.20 正弦 2.76×, 0.14 正弦 5.4×, 0.12 三角 2×]`。`durationSec`：piano 1.2、xylophone 0.5、musicbox 0.9；`attackSec` 统一 0.005。
- `renderVoiceInto`：对每个绝对采样位置 `abs = startSample + i`；若 `abs < 0` 或 `abs >= out.length` 跳过；`t = i / sampleRate`；超过 `durationSec` 停止。包络 `env = t < attackSec ? t / attackSec : Math.exp(-5 * (t - attackSec) / durationSec)`，末尾 10ms 线性归零。波形 `sine = Math.sin(2πft)`，`triangle = 2/π * Math.asin(Math.sin(2πft))`。累加 `out[abs] += wave * gain * env`。
- 不使用 `any`；所有函数参数与返回类型显式标注。

- [ ] **Step 4: 跑测试**

DevEco 运行 `MusicToneSynth.test.ets`。预期：PASS。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/utils/MusicToneSynth.ets entry/src/ohosTest/ets/test/utils/MusicToneSynth.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(kids): add pure PCM tone synthesis"
```

---

### Task 3: 混音器与 AudioRenderer 服务

**Files:**
- Create: `entry/src/main/ets/utils/MusicVoiceMixer.ets`
- Create: `entry/src/main/ets/services/MusicToneService.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MusicVoiceMixer.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: `MusicToneSynth`、`MusicEarData`
- Produces:
  - `class MusicVoiceMixer { scheduleNote(freq: number, timbre: MusicTimbre, delaySamples: number): void; scheduleSequence(freqs: number[], timbre: MusicTimbre, noteSamples: number, gapSamples: number): void; fillBuffer(out: Float32Array, sampleRate: number): void; clear(): void; getActiveVoiceCount(): number; getCursor(): number }`
  - `class MusicToneService { static getInstance(): MusicToneService; ensureStarted(): Promise<boolean>; playNote(note: MusicNote, timbre: MusicTimbre): void; playSequence(notes: MusicNote[], timbre: MusicTimbre, noteMs: number, gapMs: number, onNote?: (index: number) => void): number; cancelSequence(token: number): void; stopAll(): void; setMuted(muted: boolean): void; release(): void }`

- [ ] **Step 1: 写失败测试**

```ts
import { describe, it, expect } from '@ohos/hypium'
import { MusicVoiceMixer } from '../../../../main/ets/utils/MusicVoiceMixer'

function hasNonZero(out: Float32Array): boolean {
  for (let i = 0; i < out.length; i++) {
    if (out[i] !== 0) return true
  }
  return false
}

export default function musicVoiceMixerTest() {
  describe('MusicVoiceMixer', () => {
    it('renders_scheduled_note', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleNote(440, 'piano', 0)
      const out = new Float32Array(480)
      mixer.fillBuffer(out, 48000)
      expect(hasNonZero(out)).assertTrue()
    })

    it('keeps_silence_before_future_note', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleNote(440, 'piano', 4800)
      const out = new Float32Array(480)
      mixer.fillBuffer(out, 48000)
      expect(hasNonZero(out)).assertFalse()
    })

    it('caps_active_voices_at_eight', 0, () => {
      const mixer = new MusicVoiceMixer()
      for (let i = 0; i < 12; i++) {
        mixer.scheduleNote(200 + i * 20, 'piano', 0)
      }
      expect(mixer.getActiveVoiceCount() <= 8).assertTrue()
    })

    it('clear_drops_all_voices', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleNote(440, 'piano', 0)
      const out = new Float32Array(480)
      mixer.fillBuffer(out, 48000)
      mixer.clear()
      expect(mixer.getActiveVoiceCount()).assertEqual(0)
      expect(hasNonZero(out)).assertTrue()
      const silent = new Float32Array(480)
      mixer.fillBuffer(silent, 48000)
      expect(hasNonZero(silent)).assertFalse()
    })

    it('schedules_sequence_with_spacing', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleSequence([261.63, 329.63, 392.0], 'xylophone', 2400, 480)
      expect(mixer.getActiveVoiceCount()).assertEqual(3)
    })
  })
}
```

- [ ] **Step 2: 注册并确认失败**

加 import/调用；DevEco 运行，预期找不到模块。

- [ ] **Step 3: 实现混音器**

- `voices: ScheduledVoice[]`，`cursor: number = 0`。
- `scheduleNote`：若 `voices.length >= 8` 删除最早一项；`startSample = cursor + delaySamples`。
- `scheduleSequence`：第 i 个音 `startSample = cursor + i * (noteSamples + gapSamples)`。
- `fillBuffer`：先 `out.fill(0)`；对每个 voice 计算 `offset = voice.startSample - cursor`，调用 `renderVoiceInto(out, offset, spec, sampleRate)`；`cursor += out.length`；移除已经结束的 voice（`startSample + durationSamples <= cursor`）。
- `getActiveVoiceCount` 返回 `voices.length`；`clear` 清空并保留 cursor（或归零，测试只要 voices=0）。

- [ ] **Step 4: 实现 AudioRenderer 服务**

`MusicToneService.ets`：

- 常量 `SAMPLE_RATE = 48000`、`CHANNELS = 2`、`MAX_VOICES = 8`、`MASTER_GAIN = 0.8`。
- 单例 + `renderer: audio.AudioRenderer | null`、`mixer: MusicVoiceMixer`、`muted: boolean`、`starting: Promise<boolean> | null`。
- `ensureStarted()`：已启动返回 true；创建 `AudioRendererOptions`（`samplingRate: SAMPLE_RATE_48000`、`channels: CHANNEL_2`、`sampleFormat: SAMPLE_FORMAT_S16LE`、`encodingType: ENCODING_TYPE_RAW`、`usage: STREAM_USAGE_GAME`、`rendererFlags: 0`）；`await audio.createAudioRenderer(options)`；`on('writeData', cb)`；`await renderer.start()`；任何异常返回 false 并清空 renderer。
- `writeData` 回调：`frameCount = Math.floor(data.byteLength / 4)`（每帧 2 声道 × 2 字节）；`mix = new Float32Array(frameCount)`；`mixer.fillBuffer(mix, SAMPLE_RATE)`；`const pcm = new Int16Array(data)`；`muted` 时全写 0，否则逐帧写 `pcm[2i] = pcm[2i+1] = Math.max(-1, Math.min(1, mix[i] * MASTER_GAIN)) * 32767`。回调末尾 `return audio.AudioDataCallbackResult.VALID`；若该 API 版本的返回类型不接受，改成无返回值（`on('writeData')` 两种都支持）。
- `playSequence`：`const noteSamples = Math.floor(noteMs * SAMPLE_RATE / 1000)`、`const gapSamples = Math.floor(gapMs * SAMPLE_RATE / 1000)`；先 `mixer.scheduleSequence(freqs, timbre, noteSamples, gapSamples)` 一次排期，再为每个音 `setTimeout(() => onNote(i), i * (noteMs + gapMs))`；返回递增 token，`cancelSequence(token)` 清除该 token 的全部 timer。
- `playNote`：映射 `MUSIC_NOTE_FREQ[note]`，`mixer.scheduleNote(freq, timbre, 0)`；若 renderer 未启动则静默返回。
- `stopAll`：`mixer.clear()` + 清除所有 sequence timer。
- `setMuted`；`release`：清除 timer、`renderer.stop()`、`off('writeData')`、`renderer.release()`、置空。
- ArkTS 注意：`audio.AudioRenderer` 类型、所有对象字面量显式接口标注。

- [ ] **Step 5: 跑混音测试与编译**

DevEco 运行 `MusicVoiceMixer.test.ets`（预期 PASS），再跑：

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

预期：BUILD SUCCESSFUL。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/utils/MusicVoiceMixer.ets entry/src/main/ets/services/MusicToneService.ets entry/src/ohosTest/ets/test/utils/MusicVoiceMixer.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(kids): add voice mixer and AudioRenderer tone service"
```

---

### Task 4: 参数校验与工具身份

**Files:**
- Create: `entry/src/main/ets/utils/MusicEarValidation.ets`
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MusicEarValidation.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: `normalizeDrill`、`clampDifficulty`
- Produces:
  - `interface MusicEarArgsValidation { ok: boolean; drill: string; difficulty: number; error: string }`
  - `validateMusicEarArgs(argsJson: string): MusicEarArgsValidation`
  - `MUSIC_EAR_TOOL_ID: string = 'music_ear'`
  - `isMusicEarFunctionName(functionName: string): boolean`（兼容 `music_ear` / `music-ear` / `ear_training`）

- [ ] **Step 1: 写失败测试**

```ts
import { describe, it, expect } from '@ohos/hypium'
import { validateMusicEarArgs } from '../../../../main/ets/utils/MusicEarValidation'
import { isMusicEarFunctionName, MUSIC_EAR_TOOL_ID } from '../../../../main/ets/utils/SearchToolIdentityUtils'

export default function musicEarValidationTest() {
  describe('MusicEarValidation', () => {
    it('accepts_valid_args', 0, () => {
      const r = validateMusicEarArgs('{"drill":"echo","difficulty":2}')
      expect(r.ok).assertTrue()
      expect(r.drill).assertEqual('echo')
      expect(r.difficulty).assertEqual(2)
    })

    it('normalizes_aliases', 0, () => {
      expect(validateMusicEarArgs('{"drill":"high-low","difficulty":1}').drill).assertEqual('high_low')
      expect(validateMusicEarArgs('{"drill":"song","difficulty":3}').drill).assertEqual('guess_song')
    })

    it('rejects_bad_drill', 0, () => {
      const r = validateMusicEarArgs('{"drill":"piano","difficulty":1}')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('rejects_out_of_range_difficulty', 0, () => {
      expect(validateMusicEarArgs('{"drill":"echo","difficulty":0}').ok).assertFalse()
      expect(validateMusicEarArgs('{"drill":"echo","difficulty":4}').ok).assertFalse()
      expect(validateMusicEarArgs('{"drill":"echo","difficulty":1.5}').ok).assertFalse()
    })

    it('rejects_malformed_json', 0, () => {
      expect(validateMusicEarArgs('not json').ok).assertFalse()
    })

    it('identifies_music_ear_names', 0, () => {
      expect(MUSIC_EAR_TOOL_ID).assertEqual('music_ear')
      expect(isMusicEarFunctionName('music_ear')).assertTrue()
      expect(isMusicEarFunctionName('music-ear')).assertTrue()
      expect(isMusicEarFunctionName('ear_training')).assertTrue()
      expect(isMusicEarFunctionName('math_quiz')).assertFalse()
    })
  })
}
```

- [ ] **Step 2: 注册并确认失败**

`List.test.ets` 加 import/调用；运行，预期找不到模块。

- [ ] **Step 3: 实现校验与身份**

- `MusicEarValidation.ets`：`JSON.parse` 包 try/catch；`drill` 必须 normalize 后的值属于三值（用 `normalizeDrill` 后判断，alias 放行）；`difficulty` 必须是整数 1~3；失败时 `ok=false`、`error` 用中文说明、`drill=''`、`difficulty=1`。成功时返回 normalize 后的值。
- `SearchToolIdentityUtils.ets`：
  - 在 `SNAKE_GAME_TOOL_ID`（第 31 行）之后加 `export const MUSIC_EAR_TOOL_ID: string = 'music_ear'`（不要放在 `MUSIC_GENERATION_TOOL_ID` 旁边，两者语义无关）。
  - 在 `isSnakeGameFunctionName`（第 163 行）之后加 `isMusicEarFunctionName`，用 `normalizeToolFunctionName` 后匹配 `MUSIC_EAR_TOOL_ID`、`'ear_training'`。
  - 在 `isInteractiveQuizFunctionName`（第 268 行）的 or 链末尾加 `isMusicEarFunctionName(functionName)`——该函数控制 ChatViewModel 单回合出题数上限，`music_ear` 同样是挂起等孩子作答的卡片工具。

- [ ] **Step 4: 跑测试**

DevEco 运行。预期：PASS。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/utils/MusicEarValidation.ets entry/src/main/ets/utils/SearchToolIdentityUtils.ets entry/src/ohosTest/ets/test/utils/MusicEarValidation.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat(kids): add music_ear arg validation and tool identity"
```

---

### Task 5: BuiltinTools 注册

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

**Interfaces:**
- Consumes: `MUSIC_EAR_TOOL_ID`、`MUSIC_EAR_TOOL_ID` 的 import
- Produces: `music_ear` 工具 schema / config / executor，出现在 `getBuiltinToolIds()`

- [ ] **Step 1: 加 import**

在 `SearchToolIdentityUtils` 的大 import 块加入 `MUSIC_EAR_TOOL_ID`。

- [ ] **Step 2: 加 Args / Executor / Definition / Config**

在 `snake_game` 工具块之后追加：

```ts
interface MusicEarArgs {
  drill: string
  difficulty: number
}

class MusicEarExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    try {
      const params = JSON.parse(_args) as MusicEarArgs
      return JSON.stringify({
        drill: params.drill ?? 'high_low',
        difficulty: params.difficulty ?? 1,
        answered: false,
        hint: '音符小耳朵已准备好,请小朋友先在自由敲琴里按一按,再开始听音练习。'
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`music_ear error: ${JSON.stringify(error)}`))
    }
  }
}
```

`createMusicEarToolDefinition()` 的 `rawSchemaJson`：

```json
{
  "type": "object",
  "properties": {
    "drill": {
      "type": "string",
      "description": "练习类型:high_low = 听两个音判断谁更高(3 级会出现「一样高」);echo = 听 3-5 个音按顺序弹出来;guess_song = 听一小段旋律猜是哪首儿歌。",
      "enum": ["high_low", "echo", "guess_song"]
    },
    "difficulty": {
      "type": "integer",
      "description": "难度:1 = 5 岁(高音程 / 3 音复述 / 3 选 1),2 = 6 岁(2 度音程 / 4 音复述 / 4 选 1),3 = 7 岁(相邻音与同音 / 5 音复述 / 5 选 1)。按 child_profile 的 observation level 选择,初次从 1 开始。",
      "enum": [1, 2, 3]
    }
  },
  "required": ["drill", "difficulty"]
}
```

`ToolFunction` 描述写明：卡片自带自由敲琴热身；结果包含 drill / difficulty / total / correct / first_try_correct / completed / stars / songs / rounds_played；完成后调用 `child_profile` 更新 `observation`。

`createMusicEarToolConfig()` 用 `(MUSIC_EAR_TOOL_ID, '音符小耳朵', '听音辨高低、复述旋律、猜儿歌,练耳朵的音乐小游戏。', null, true, false, ToolSourceType.BUILTIN, 'builtin', MUSIC_EAR_TOOL_ID, '内置工具', ToolPermissionLevel.READ)`。

- [ ] **Step 3: 注册并补 getBuiltinToolIds**

在 `registerBuiltinTools()` 的 snake_game 注册块之后加 `if (!registry.isToolRegistered(MUSIC_EAR_TOOL_ID)) { ... }`；`getBuiltinToolIds()` 数组末尾加 `MUSIC_EAR_TOOL_ID`。

- [ ] **Step 4: JSON.parse gauntlet**

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const m=s.match(/const rawSchemaJson: string = \`([\s\S]*?)\`/g);if(!m)throw new Error('no schema');m.forEach((b,i)=>{const j=b.replace(/const rawSchemaJson: string = \`/,'').replace(/\`$/,'');JSON.parse(j);console.log('schema',i,'ok')})"
```

预期：每个 schema 都打印 `ok`，无异常。

- [ ] **Step 5: 编译**

运行 Global Constraints 里的 `assembleHap`。预期 BUILD SUCCESSFUL。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(kids): register music_ear builtin tool"
```

---

### Task 6: ToolExecutionService 处理器与分发

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

**Interfaces:**
- Consumes: `MUSIC_EAR_TOOL_ID`、`isMusicEarFunctionName`、`validateMusicEarArgs`
- Produces: `handleMusicEar(toolCall, context): Promise<ToolResult>`；`executeToolCall` 在 `resolveToolId` 兜底之前分发到它

- [ ] **Step 1: 加 import**

在 `SearchToolIdentityUtils` import 块加 `MUSIC_EAR_TOOL_ID, isMusicEarFunctionName`；在 validation import 区加 `validateMusicEarArgs`。

- [ ] **Step 2: 实现 handler**

镜像 `handleMemoryMatch`（`entry/src/main/ets/services/ToolExecutionService.ets` 的 memory_match 段）：

1. `toolCall.toolId = MUSIC_EAR_TOOL_ID`；`displayName` 空则 `音符小耳朵`；`sourceType = BUILTIN`；`sourceLabel` 空则 `内置工具`；`permissionLevel = READ`。
2. `const validation = validateMusicEarArgs(toolCall.arguments)`；`!ok` 时 `approvalState='denied'`，返回 `ToolResult(JSON.stringify({ error: 'validation_failed', message: validation.error, should_retry: true }), true, ...)`。
3. 成功后把规范化结果写回 `toolCall.arguments = JSON.stringify({ drill: validation.drill, difficulty: validation.difficulty })`。
4. `approvalState='pending'`；`recordLedgerServed('music_ear', toolCall, context)`；挂 `pendingAnswers` Promise（复制 memory_match 的 Promise 构造，`snapshot.toolId = MUSIC_EAR_TOOL_ID`）。
5. resolve 后：外部取消走 `buildCancelledResult`；`answerJson === null` 返回 `{ cancelled: true, error: '小朋友未完成音符小耳朵' }`；否则 `approvalState='answered'`、`approvalReason=answerJson`、`recordStarEvent('music_ear', ...)`、返回 `ToolResult(answerJson, false, ...)`。

- [ ] **Step 3: 加分发分支**

在 `executeToolCall` 中，放在 `snake_game` 特殊路径之后、`resolveToolId` 兜底之前：

```ts
if (isMusicEarFunctionName(normalizedFunctionName)) {
  return await this.handleMusicEar(toolCall, context)
}
```

- [ ] **Step 4: 验证**

```bash
grep -c "handleMusicEar\|isMusicEarFunctionName" entry/src/main/ets/services/ToolExecutionService.ets
```

预期 ≥ 3（import、分支、方法定义）。再跑 `assembleHap`，预期 BUILD SUCCESSFUL。

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat(kids): handle music_ear pending interaction"
```

---

### Task 7: 星星事件与奖励

**Files:**
- Modify: `entry/src/main/ets/models/StarEventModels.ets`
- Modify: `entry/src/main/ets/services/StarRewardService.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets`（追加元数据用例）
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: `computeMusicEarStars`
- Produces: `StarActivityType` 含 `'music_ear'`；`getActivityMeta('music_ear')` 返回 `音符小耳朵`；`computeStars('music_ear', payload)` 走新分支

- [ ] **Step 1: 10 处漂移点**

按 `.claude/skills/adding-mini-game-tool/SKILL.md` 的表格逐项加 `music_ear`：

1. `StarActivityType` 联合
2. `TodayStarSummaryByType` 字段
3. `createEmptyTodayStarSummary()` 初始化
4. `StarActivityMetaMap` 字段
5. `META_MUSIC` 常量
6. `metaRecord` 条目
7. `activityTypes` 数组
8. `getBucketFromSummary` 分支
9. `getActivityMeta` 分支
10. `getActivitySymbol` 分支（用 `$r('sys.symbol.speaker_wave_2')`）

`META_MUSIC`：`{ emoji: '🎵', shortLabel: '音乐', longLabel: '音符小耳朵', grantedHint: '音符小耳朵完成', unit: '局' }`。

- [ ] **Step 2: 4-grep gauntlet**

```bash
grep -n "META_MUSIC\|META_PUZZLE\|META_MATH\|META_ENGLISH\|META_HANDWRITING" entry/src/main/ets/models/StarEventModels.ets
grep -n "byType\." entry/src/main/ets/models/StarEventModels.ets
grep -n "return META_" entry/src/main/ets/models/StarEventModels.ets
grep -n "return byType\." entry/src/main/ets/models/StarEventModels.ets
```

预期：`META_MUSIC` 出现在声明 + `metaRecord` 两行；`byType.music_ear` 恰好 3 行（接口 / 初始化 / 分支）；`return META_MUSIC` 1 行；`return byType.music_ear` 1 行。

- [ ] **Step 3: 星星计算**

`StarRewardService.ets` 顶部 import `computeMusicEarStars`，在 `computeStars` 末尾加：

```ts
if (activityType === 'music_ear') {
  if (payload['completed'] !== true) {
    return 0
  }
  return computeMusicEarStars(
    (payload['difficulty'] as number) ?? 1,
    (payload['total'] as number) ?? 5,
    (payload['first_try_correct'] as number) ?? 0
  )
}
```

- [ ] **Step 4: 追加元数据测试**

在 `MusicEarLogic.test.ets` 的 describe 中加：

```ts
it('music_ear_meta_is_registered', 0, () => {
  const meta = getActivityMeta('music_ear')
  expect(meta.longLabel).assertEqual('音符小耳朵')
  expect(meta.shortLabel).assertEqual('音乐')
})
```

并在 `MusicEarLogic.test.ets` 顶部加 `import { getActivityMeta } from '../../../../main/ets/models/StarEventModels'`。

- [ ] **Step 5: 跑测试与编译**

DevEco 运行 `MusicEarLogic.test.ets` → PASS；再跑 `assembleHap` → BUILD SUCCESSFUL。

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/models/StarEventModels.ets entry/src/main/ets/services/StarRewardService.ets entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets
git commit -m "feat(kids): add music_ear star activity"
```

---

### Task 8: 游戏老师锁定与提示词

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`

**Interfaces:**
- Consumes: `MUSIC_EAR_TOOL_ID`
- Produces: `KIDS_GAMES_LOCKED_TOOL_IDS` 含 `MUSIC_EAR_TOOL_ID`；`KIDS_GAMES_SYSTEM_PROMPT` 含 music_ear 段

- [ ] **Step 1: 锁定工具**

在 `AssistantModels.ets` 的 `SearchToolIdentityUtils` import 块加 `MUSIC_EAR_TOOL_ID`；在 `KIDS_GAMES_LOCKED_TOOL_IDS` 末尾加 `MUSIC_EAR_TOOL_ID`。

- [ ] **Step 2: 提示词**

在 `KIDS_GAMES_SYSTEM_PROMPT` 中：

- 把「7 个游戏轮换着玩」改为「8 个游戏轮换着玩」。
- 在 `snake_game` 行后加：

```
'- music_ear 音符小耳朵:drill 三选一——high_low 听两个音判断谁更高(1 级音程大,3 级只差一个音且会出现「一样高」);echo 听 3-5 个音按顺序弹出来;guess_song 听一小段旋律猜儿歌。difficulty 1=5 岁,2=6 岁,3=7 岁。开场先让孩子在自由敲琴里随便按按,再点开始。',
```

- 授星规则行补一句「音符小耳朵完成一轮系统自动记星」。

- [ ] **Step 3: 验证**

```bash
grep -c "MUSIC_EAR_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets
grep -c "music_ear" entry/src/main/ets/models/AssistantModels.ets
```

预期：第一条 ≥ 3（import、锁定数组、提示词），第二条 ≥ 2。再跑 `assembleHap` → BUILD SUCCESSFUL。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(kids): lock music_ear to games teacher"
```

---

### Task 9: 卡片外壳与自由敲琴

**Files:**
- Create: `entry/src/main/ets/components/MusicEarCard.ets`

**Interfaces:**
- Consumes: `MusicEarData`、`MusicEarLogic`、`MusicToneService`、`ToolCall`
- Produces: `export interface MusicEarResult`（字段见规格 §7.1）、`@ComponentV2 export struct MusicEarCard`

**卡片 API（后续任务沿用）**

```ts
export interface MusicEarResult {
  drill: string
  difficulty: number
  total: number
  correct: number
  first_try_correct: number
  completed: boolean
  stars: number
  songs: string[]
  rounds_played: number
  cancelled?: boolean
}

@ComponentV2
export struct MusicEarCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}
}
```

**@Local 状态**

`page: string = 'free'`、`drill: MusicDrill`、`difficulty: number`、`timbre: MusicTimbre`、`muted: boolean`、`audioReady: boolean`、`audioFailed: boolean`、`questionIndex: number`、`firstTryResults: boolean[]`、`roundUsedPairKeys: string[]`、`roundUsedSongKeys: string[]`、`roundSongNames: string[]`、`currentHighLow: HighLowQuestion | null`、`currentEcho: MusicNote[]`、`pressedEcho: MusicNote[]`、`currentGuess: GuessSongQuestion | null`、`feedback: string`、`completedRounds: RoundSnapshot[]`、`submitted: boolean`。

- [ ] **Step 1: 写卡片外壳**

`build()` 按 `page` 分发到三个 `@Builder`：`FreePage()`、`RoundPage()`、`SummaryPage()`（后两个先留占位）。本轮只实现：

- 外层容器：`largeSize ? padding 0 + Transparent : padding 14 + themeAiBubble + 14vp 圆角 + 1px divider`。
- 标题栏：🎵 音符小耳朵 + 静音按钮 + 关闭按钮（调 `onRequestClose`）。
- `Stage()`：暖米白到浅蓝的 `linearGradient` 舞台 + 两朵云 + 两个小山坡（用 `Circle`/`Ellipse` 近似）；不画音符精灵（Task 10 再加）。
- `Keyboard()`：`ForEach(MUSIC_KEYS, ...)` 6 个键，每键 1:1 宽高、≥48vp，显示 emoji + 音名 + 角色名；`onClick` 调 `pressKey(note)`；`pressKey` 里 `MusicToneService.getInstance().playNote(note, this.timbre)` 并触发按压动效。
- 音色切换：三个胶囊按钮，读 `this.timbre`，点击直接赋值。
- drill 切换：三个胶囊按钮（高低 / 复述 / 猜歌），只在 `free` 页显示。
- 主按钮「我准备好啦 · 开始练习」：`startRound()`（Task 10 实现；本轮先切成 `round` 页并显示占位文案）。
- `aboutToAppear`：解析 `toolCall.arguments`，用 `normalizeDrill` / `clampDifficulty` 兜底（SKILL.md「Args Validation Decision」：卡片侧是渲染的 source of truth，handler 校验只是早失败）；`MusicToneService.getInstance().ensureStarted().then((ok) => { this.audioReady = ok; this.audioFailed = !ok })`。
- `aboutToDisappear`：`MusicToneService.getInstance().stopAll(); release()`。
- 音频失败面板：`audioFailed === true` 时在自由页顶部显示「声音没打开」+「重试」（重新 `ensureStarted`）+「先回去」（调 `onRequestClose`）两个按钮，并禁用开始按钮。

**ArkUI 注意**：`@Builder` 内部直接读 `this.xxx`；不要把格式化后的字符串当参数传入；`ForEach` 回调体内不要声明 `const`。

- [ ] **Step 2: 编译**

`assembleHap` → BUILD SUCCESSFUL。hvigor 会编译 `entry/src/main/ets/` 下所有 `.ets`，本文件无需先被 MessageBubble 引用；若报「声明但未使用」，确认没有把 `MusicEarCard` 写成非 export。

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/components/MusicEarCard.ets
git commit -m "feat(kids): add music ear card shell and free play"
```

---

### Task 10: 三种练习与判分交互

**Files:**
- Modify: `entry/src/main/ets/components/MusicEarCard.ets`
- Modify: `entry/src/main/ets/utils/MusicEarLogic.ets`（仅当需要补 helper）

**Interfaces:**
- Consumes: `buildHighLowQuestion`、`buildEchoSequence`、`buildGuessSongQuestion`、`evaluateEcho`、`scoreRound`
- Produces: `startRound()`、`nextQuestion()`、`submitHighLow(answer)`、`pressEchoKey(note)`、`submitGuess(songKey)`、`replayCurrent()`

- [ ] **Step 1: 实现轮次状态机**

- `startRound()`：`questionIndex=0`、`firstTryResults=[]`、`roundUsedPairKeys=[]`、`roundUsedSongKeys=[]`、`roundSongNames=[]`、`completedRounds` 保留、`page='round'`、调用 `nextQuestion()`。
- `nextQuestion()`：**先**判断 `questionIndex >= MUSIC_QUESTIONS_PER_ROUND` → 调 `finishRound()` 并返回；否则按 `drill` 生成第 `questionIndex` 题（`high_low` 传 `roundUsedPairKeys` 且把返回的 `pairKey` 推入，`guess_song` 传 `roundUsedSongKeys`）。
- `answerCurrentQuestion(firstTryCorrect: boolean)`：只在 `firstTryResults[questionIndex]` 尚未赋值时写入；随后延迟 400ms（给答对动效留时间）执行 `questionIndex += 1` 与 `nextQuestion()`。定时器句柄存字段并在 `aboutToDisappear` 清理。三种 drill 答对后都走这一个汇合点。
- `guess_song` 生成题目时把 `songKey` 推入 `roundUsedSongKeys`，把歌名推入 `roundSongNames`；其他 drill 两个数组保持空。
- `finishRound()`：用 `scoreRound(this.firstTryResults)` 算出 `correct` / `firstTryCorrect`，把 `RoundSnapshot`（含 `songs: this.roundSongNames`）push 进 `completedRounds`，`page='summary'`。

- [ ] **Step 2: `high_low` UI**

- 题干：「听一听，哪个音更高？」
- 三个图标按钮：⬆️ 第一个高 / ⬇️ 第二个高 / ＝ 一样高。
- 进入题目时播放两个音（`playSequence([first, second], timbre, 650, 300)`）。
- 作答：正确 → `answerCurrentQuestion(true)` + 音符精灵飞起；错误 → `answerCurrentQuestion(false)`，`feedback='再听一次'`，播放错误音并重播两音，留在本题允许重选（`questionIndex` 未推进，重试不会再写 `firstTryResults`）。
- 「再听一遍」按钮始终可用。

- [ ] **Step 3: `echo` UI**

- 题干：「听一听，按顺序弹出来」。
- 进入题目时播放序列（`playSequence(currentEcho, timbre, 550, 120)`），**不**高亮任何琴键。
- `pressEchoKey(note)`：先把音加进 `pressedEcho` 并播放；与 `currentEcho[pressedEcho.length-1]` 比较：
  - 错：`answerCurrentQuestion(false)`、琴键晃动、播放错误音、清空 `pressedEcho`、重播整段、`feedback='再听一次，从头来'`。
  - 对且未完成：继续。
  - 对且完成：`answerCurrentQuestion(true)`。
- 「再听一遍」按钮重播并清空输入。

- [ ] **Step 4: `guess_song` UI**

- 题干：「听一听，这是哪首歌？」
- 进入题目时播放 `answerSong.notes.slice(0, currentGuess.noteCount)`。
- 选项网格：`ForEach(currentGuess.optionSongKeys, ...)`，每项 emoji + 歌名，3/4/5 列自适应。
- 作答：正确 → `answerCurrentQuestion(true)`、显示歌名、重播同一段；错误 → `answerCurrentQuestion(false)`、重播、留在本题允许重选。
- 「再听一遍」按钮。

- [ ] **Step 5: 进度与反馈**

- 顶部进度条 `questionIndex / 5`。
- `feedback` 文案用 1 行显示，2.6 秒后自动清空（`setTimeout`，在 `aboutToDisappear` 清理）。
- 答对播放 `playNote('A', 'musicbox')`，答错播放 `playNote('C', 'piano')`——不新增服务方法，两个音都在既有琴键范围内。

- [ ] **Step 6: 编译**

`assembleHap` → BUILD SUCCESSFUL。三种练习的 UI 与听觉验收统一放到 Task 12 接线后与 Task 13 真机清单，本任务不临时加调试入口。

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/components/MusicEarCard.ets entry/src/main/ets/utils/MusicEarLogic.ets
git commit -m "feat(kids): implement music ear drills"
```

---

### Task 11: 结算页与提交生命周期

**Files:**
- Modify: `entry/src/main/ets/components/MusicEarCard.ets`
- Modify: `entry/src/main/ets/utils/MusicEarLogic.ets`（若 `pickBestRound` 尚未实现）
- Modify: `entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets`（若补充 `pickBestRound` 用例）

**Interfaces:**
- Consumes: `pickBestRound`、`computeMusicEarStars`
- Produces: `finishRound()`、`buildResult(): MusicEarResult`、`submitOnce()`、`SummaryPage()`

- [ ] **Step 1: 结算页**

- 显示：答对 `total / total`、首答正确 `firstTryCorrect / total`、星星（`computeMusicEarStars(...)`）、`guess_song` 的歌名回顾。
- 按钮：「再来一轮」→ `startRound()`（不提交）；「回到自由敲琴」→ `page='free'`；「回消息」→ `submitOnce()` 后 `onRequestClose()`。
- drill 切换在结算页可用；切换后回到 `free` 页（不自动开新轮）。

- [ ] **Step 2: 提交逻辑**

- `buildResult(): MusicEarResult`：先 `const best = pickBestRound(this.completedRounds)`。
  - `best === null`：返回 `{ drill: this.drill, difficulty: this.difficulty, total: MUSIC_QUESTIONS_PER_ROUND, correct: 0, first_try_correct: 0, completed: false, stars: 0, songs: [], rounds_played: this.completedRounds.length, cancelled: true }`。
  - 否则：`drill / difficulty / total / correct / first_try_correct / songs` 全部取自 `best`（不要用卡片当前 drill，结算页允许切换 drill），`completed: true`，`stars: computeMusicEarStars(best.difficulty, best.total, best.firstTryCorrect)`，`rounds_played: this.completedRounds.length`，`cancelled: false`。
- `submitOnce()`：`if (this.submitted) return; this.submitted = true; this.onAnswer(this.toolCall.id, JSON.stringify(this.buildResult()))`。
- `aboutToDisappear` 按固定顺序执行：① 若 `!submitted` 调 `submitOnce()`（有完整轮次提交最好一轮，否则提交 `completed:false, cancelled:true`）；② `clearFeedbackTimer()`；③ `MusicToneService.getInstance().stopAll()` 再 `release()`。
- **提交权唯一**：卡片是本次工具调用唯一的 `onAnswer` 调用方。「回消息」按钮先 `submitOnce()` 再 `onRequestClose()`；拖拽关闭、系统返回、ChatPage 关闭按钮都只会销毁卡片，由 `aboutToDisappear` 兜底提交。ChatPage 侧**不写**任何提交逻辑（Task 12 明确）。

- [ ] **Step 3: 编译**

`assembleHap` → BUILD SUCCESSFUL。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/components/MusicEarCard.ets entry/src/main/ets/utils/MusicEarLogic.ets entry/src/ohosTest/ets/test/utils/MusicEarLogic.test.ets
git commit -m "feat(kids): add music ear summary and single submission"
```

---

### Task 12: MessageBubble 与 ChatPage 接线

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`
- Modify: `entry/src/main/ets/pages/ChatPage.ets`

**Interfaces:**
- Consumes: `MusicEarCard`（Task 9–11）、`isMusicEarFunctionName`、`resolveStepAnswerPayload`
- Produces: 待答横幅、已答摘要、全屏 sheet（卡片自己提交结果，ChatPage 不参与提交）

- [ ] **Step 1: MessageBubble 7 处**

按 `.claude/skills/adding-mini-game-tool/SKILL.md` 的 exact-line 清单：

1. `SearchToolIdentityUtils` import 块加 `isMusicEarFunctionName`。
2. 在 `farm_english` 的待答横幅之后，加 `music_ear` 待答横幅（由 `shouldRenderMusicEarInteractionCard` 守卫，该函数内含本文件的 `isMusicEarFunctionName` 调用）：🎵 图标 + `音符小耳朵 · ${this.getMusicEarDrillText(toolCall)}` + 「去听一听 ›」，`onClick` 调 `this.onOpenMusicEarSheet(toolCall)`。
3. `isToolStepClickable` 的 or 链加 `isMusicEarFunctionName(part.toolName)`。
4. `isDefaultExpanded` 的 or 链加同一判断。
5. `isAutoExpandable` 的 or 链加同一判断。
6. `handleToolStepClick` 的 switch 加 `music_ear` 分支。
7. step-content 的 `else if` 级联加 `isMusicEarFunctionName(step.toolName)` → `this.MusicEarStepContent(step)`。

新增（镜像 `MessageBubble.ets:3360` 附近的 `shouldRenderAskUserInteractionCard`）：

```ts
@Event onOpenMusicEarSheet: (toolCall: ToolCall) => void = () => {}

private getMusicEarDrillText(toolCall: ToolCall): string {
  try {
    const parsed = JSON.parse(toolCall.arguments) as Record<string, Object>
    const drill = (parsed['drill'] as string) ?? 'high_low'
    if (drill === 'echo') return '听音复述'
    if (drill === 'guess_song') return '听旋律猜歌'
    return '听音辨高低'
  } catch (_e) {
    return '听音练习'
  }
}

private shouldRenderMusicEarInteractionCard(toolCall: ToolCall, index: number): boolean {
  if (!isMusicEarFunctionName(toolCall.functionName) || this.shouldHideToolCallCard(toolCall)) return false
  return toolCall.approvalState === 'pending' && !isAskUserToolCallAnswered(toolCall, index)
}
```

`MusicEarStepContent(step)`：已答时读 `resolveStepAnswerPayload(step.toolResult, step.toolApprovalReason)`，显示「音符小耳朵 · 首答正确 N/5 · ⭐X」；不渲染完整键盘。

- [ ] **Step 2: ChatPage 状态与回调**

- 状态：`@Local showMusicEarSheet: boolean = false`、`@Local musicEarSheetToolCall: ToolCall = new ToolCall()`。
- 在 MessageBubble 实例化处加 `onOpenMusicEarSheet: (toolCall: ToolCall): void => { this.musicEarSheetToolCall = toolCall; this.showMusicEarSheet = true }`。
- 在 maze 的 `bindSheet` 附近加：

```ts
Column()
  .width(0)
  .height(0)
  .bindSheet($$this.showMusicEarSheet, this.MusicEarSheetBuilder(), {
    height: SheetSize.LARGE,
    dragBar: true,
    showClose: true,
    blurStyle: BlurStyle.Thick,
    backgroundColor: this.themeBackground,
    preferType: SheetType.BOTTOM,
    onDisappear: () => {
      this.showMusicEarSheet = false
    }
  })
```

- `MusicEarSheetBuilder()`：

```ts
@Builder
MusicEarSheetBuilder() {
  MusicEarCard({
    toolCall: this.musicEarSheetToolCall,
    isAnswered: false,
    answeredPayload: '',
    largeSize: true,
    onAnswer: (toolCallId: string, answerJson: string): void => {
      this.handleAskUserAnswer(toolCallId, answerJson)
    },
    onRequestClose: (): void => {
      this.showMusicEarSheet = false
    }
  })
}
```

- **`onDisappear` 只复位 UI，不提交**：sheet 关闭（拖拽 / ✕ / 返回）销毁卡片，由卡片的 `aboutToDisappear` 唯一提交一次；这里再调 `handleAskUserAnswer` 会导致两次 resolve。

- [ ] **Step 3: 验证**

```bash
grep -n "isMusicEarFunctionName" entry/src/main/ets/components/MessageBubble.ets
```

预期恰好 7 处（import + 横幅守卫 + 3 个 or 链 + 点击分发 + step 内容）。

再检查新增 builder 没有吃掉相邻的 `@Builder`（SKILL.md 反模式表最后一行：被摘掉装饰器的方法编译不报错、真机一点就崩）：

```bash
grep -c "@Builder" entry/src/main/ets/components/MessageBubble.ets  # 前后对比 +1（MusicEarStepContent）
grep -c "@Builder" entry/src/main/ets/pages/ChatPage.ets            # 前后对比 +1（MusicEarSheetBuilder）
```

再跑 `assembleHap` → BUILD SUCCESSFUL。

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/components/MessageBubble.ets entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(kids): wire music_ear into message bubble and chat sheet"
```

---

### Task 13: 文档、全量校验与真机验收

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/rules/teaching-architecture.md`

- [ ] **Step 1: 更新文档**

- `CLAUDE.md` 的互动卡片表加一行：`MusicEarCard | music_ear | 音符小耳朵（听音辨高低 / 复述 / 猜歌，原生 PCM 合音，kids_games 专属）`。
- `.claude/rules/teaching-architecture.md`：
  - §2.1 的 `kids_games` 锁定工具子集加 `music_ear`；
  - §4 工具表加 `music_ear` 行；
  - §6 星星活动表加 `music_ear`；
  - 把「7 个游戏」改为「8 个游戏」。

- [ ] **Step 2: 全量 gauntlet**

```bash
# 1. JSON schema
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const m=s.match(/const rawSchemaJson: string = \`([\s\S]*?)\`/g);m.forEach((b,i)=>{const j=b.replace(/const rawSchemaJson: string = \`/,'').replace(/\`$/,'');JSON.parse(j);console.log('schema',i,'ok')})"

# 2. StarEventModels 4-grep（按 Task 7 的四条命令执行并人工核对）

# 3. MessageBubble 精确 7 处
grep -c "isMusicEarFunctionName" entry/src/main/ets/components/MessageBubble.ets

# 4. 工具 ID 覆盖
grep -c "MUSIC_EAR_TOOL_ID" entry/src/main/ets/config/BuiltinTools.ets   # import + 定义/注册多处，≥ 4
grep -c "MUSIC_EAR_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets  # ≥ 3（import + 锁定数组 + 提示词）

# 5. 编译
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

- [ ] **Step 3: 真机验收清单**

- 打开 `kids_games` 会话，说「我想玩听声音的游戏」，老师调用 `music_ear`。
- 气泡出现「音符小耳朵」待答横幅，点击进入全屏 sheet。
- 自由敲琴：6 个键都能响，三种音色可切换，静音有效。
- `high_low`：三个图标选项可点；答错能重听重试；5 题后进结算。
- `echo`：播放时琴键不亮；点错整段重播；点对推进。
- `guess_song`：每题选项数随难度；答对后重播同一段。
- 结算页「再来一轮」不立即产生新消息；关闭后只出现一次工具结果。
- 星星浮层出现；今日星星明细显示「音乐 / 音符小耳朵」。
- 中途关闭 sheet：老师收到取消结果，对话不卡住。
- 小星老师 / 数学 / 英语 / 语文老师的工具中心里看不到 `music_ear`。

- [ ] **Step 4: 提交**

```bash
git add CLAUDE.md .claude/rules/teaching-architecture.md
git commit -m "docs(kids): document music_ear game"
```

---

## Self-Review Notes

- 规格 §1–§14 全部有对应任务（§4.4 的题库去重 / 干扰项近邻 → Task 1；§6.2 音频失败双出口 → Task 9；§7.4 单次提交 → Task 11 + Task 12；§15 的视觉细节留给实现者）。
- 纯逻辑、波形、混音、校验均有 hypium 测试；AudioRenderer 与 UI 以编译 + 真机验收覆盖。
- 所有跨任务签名在 Interfaces 中固定：`MusicEarResult`、`RoundSnapshot`、`HighLowQuestion.pairKey`、`MusicToneService`、`validateMusicEarArgs`。
- 提交权单点：卡片 `aboutToDisappear` 是唯一兜底，ChatPage 只复位 UI——这是本计划里最容易写错的一处。
- 已知风险：`MusicToneService` 的 `writeData` 回调在音频线程执行，避免在其中分配大对象；若真机爆音，先降 `MASTER_GAIN` 再查帧数计算（`byteLength / 4`）。
