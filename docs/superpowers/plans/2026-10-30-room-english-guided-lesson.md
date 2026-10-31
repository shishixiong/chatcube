# room_english 引导式小课 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional `lesson` script to `room_english` so the card runs a guided 3–5 word tour, a `listen_find` task, and returns task stats for a follow-up `english_quiz(read_aloud)`.

**Architecture:** Validation and task judging live in pure ArkTS utils (`RoomEnglishValidation.ets`, new `RoomEnglishLesson.ets`) so they are hypium-testable. `RoomEnglishCard` owns the UI state machine and TTS. The Web scene gets two small APIs (`setAutoSpeak`, `prepareFind`). The tool schema and the two English prompts advertise the loop. Stars stay with `english_quiz`; `room_english` remains non-starring.

**Tech Stack:** HarmonyOS 6 / API 23, ArkTS strict mode, ArkUI `@ComponentV2`, ArkWeb, hypium, three.js scene in `rawfile/room3d/`.

**Spec:** `docs/superpowers/specs/2026-10-30-room-english-guided-lesson-design.md`

## Global Constraints

- Do **not** add a tool ID, `StarActivityType`, `StarEventModels` entry, or `StarRewardService` branch. `room_english` never calls `recordStarEvent`; the follow-up `english_quiz` awards the star.
- `lesson` is optional. Without it, `room_english` behavior must stay byte-for-byte equivalent to today (free exploration + “我学会了”).
- `lesson.steps`: 3–5 items. `lesson.task.type`: exactly `listen_find`. `lesson.task.targets`: 3–5 unique ids, subset of step ids. `lesson.task.max_attempts`: integer 1–2, default 2.
- Step ids must be in `ROOM_OBJECT_IDS` (76 ids). Step `word` ≤32 chars, `zh` ≤16 chars, `say` / `say_zh` ≤120 chars.
- Follow-up quiz is `english_quiz(mode:"read_aloud")` for 2–3 target words. Do **not** use `picture_word` for room words: `EnglishQuizValidation` requires `LocalVocabCatalog`, which has only ~8 of the 76 room words and no room SVGs.
- ArkTS strict mode: no destructuring, no object spread, explicit types for inline object literals, no `const` inside `@Builder` bodies. Use explicit full object construction when copying state.
- JSON-in-template-literal trap: schema descriptions must use 「」 instead of ASCII `"`; after editing `rawSchemaJson`, extract it with `node -e` and `JSON.parse` it.
- Hypium tests run in DevEco Studio (right-click file → Run); the CLI test runner is known-broken in this repo. Compile verification is the hvigor command below.
- Compile command:
  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```
- Commit after each task.

## Review Focus

- **Sheet dismissed mid-lesson** — the pending tool must resolve exactly once (`cancelled:true`), never hang or double-submit.
- **Programmatic selection during tour/reveal** — a script-driven `select(id)` must not be judged as a child tap or advance the task.
- **Repeated wrong tap / tap after reveal** — the same wrong object must not burn two attempts; a tap during the 1.5s reveal window must not double-count.
- **Web scene reload mid-lesson** — `onPageEnd` fires again; the card must resume the current tour/task step, not restart at step 0 or speak twice.
- **Room words outside the local vocab bank** — the follow-up must use `read_aloud`; a model that tries `listen_choice` / `picture_word` must be rejected by the existing validator (`should_retry`) rather than render a broken card. Pinned by the existing `EnglishQuizValidation.test.ets` case “correct_answer 不在本地词库, 拒绝”; this plan does not widen the catalog.

---

### Task 1: Lesson validation and normalized types

**Files:**
- Modify: `entry/src/main/ets/utils/RoomEnglishValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/RoomEnglishValidation.test.ets`

**Interfaces:**
- Consumes: existing `ROOM_OBJECT_IDS`, `validateRoomEnglishArgs(args: string)`.
- Produces:
  ```ts
  export interface RoomLessonStep {
    id: string
    word: string
    zh: string
    say: string      // normalized; defaults to `Look! This is a ${word}.`
    sayZh: string    // '' when omitted
  }
  export interface RoomLessonTask {
    type: string        // 'listen_find'
    targets: string[]   // step ids
    maxAttempts: number // 1–2
  }
  export interface RoomEnglishLessonPlan {
    steps: RoomLessonStep[]
    task: RoomLessonTask
  }
  export interface RoomEnglishValidationResult {
    ok: boolean
    error: string
    focus: string
    words: string[]
    lesson: RoomEnglishLessonPlan | null
  }
  ```

- [ ] **Step 1: Write failing tests**

Add these cases to `RoomEnglishValidation.test.ets`. Put `VALID_LESSON` at the top of the exported function and the `it(...)` blocks inside the existing `describe('validateRoomEnglishArgs', ...)` block:

```ts
const VALID_LESSON = '{"skill_key":"english_vocab","lesson":{"steps":[' +
  '{"id":"sofa","word":"sofa","zh":"沙发","say":"Look! This is a sofa.","say_zh":"看，这是沙发。"},' +
  '{"id":"rug","word":"rug","zh":"地毯"},' +
  '{"id":"tv","word":"TV","zh":"电视"}],' +
  '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}'

it('accepts a valid lesson and normalizes it', 0, () => {
  const r = validateRoomEnglishArgs(VALID_LESSON)
  expect(r.ok).assertTrue()
  expect(r.lesson !== null).assertTrue()
  expect(r.lesson!.steps.length).assertEqual(3)
  expect(r.lesson!.steps[1].say).assertEqual('Look! This is a rug.')
  expect(r.lesson!.steps[1].sayZh).assertEqual('')
  expect(r.lesson!.task.maxAttempts).assertEqual(2)
  expect(r.words.length).assertEqual(3)
  expect(r.words[2]).assertEqual('tv')
})

it('rejects a lesson with only two steps', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","lesson":{"steps":[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"rug","word":"rug","zh":"地毯"}],' +
    '"task":{"type":"listen_find","targets":["sofa","rug"]}}}')
  expect(r.ok).assertFalse()
})

it('rejects a step id outside the 76 room ids', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","lesson":{"steps":[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"bathtub","word":"bathtub","zh":"浴缸"},' +
    '{"id":"rug","word":"rug","zh":"地毯"}],' +
    '"task":{"type":"listen_find","targets":["sofa","rug","bathtub"]}}}')
  expect(r.ok).assertFalse()
  expect(r.error.indexOf('bathtub') >= 0).assertTrue()
})

it('rejects duplicate step ids', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","lesson":{"steps":[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"sofa","word":"sofa","zh":"沙发"},' +
    '{"id":"rug","word":"rug","zh":"地毯"},{"id":"tv","word":"TV","zh":"电视"}],' +
    '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}')
  expect(r.ok).assertFalse()
})

it('rejects targets outside the step ids', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","lesson":{"steps":[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"rug","word":"rug","zh":"地毯"},' +
    '{"id":"tv","word":"TV","zh":"电视"}],' +
    '"task":{"type":"listen_find","targets":["sofa","rug","bed"]}}}')
  expect(r.ok).assertFalse()
})

it('rejects max_attempts outside 1-2', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","lesson":{"steps":[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"rug","word":"rug","zh":"地毯"},' +
    '{"id":"tv","word":"TV","zh":"电视"}],' +
    '"task":{"type":"listen_find","targets":["sofa","rug","tv"],"max_attempts":3}}}')
  expect(r.ok).assertFalse()
})

it('rejects words that disagree with the lesson steps', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","words":["sofa","rug"],"lesson":{"steps":[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"rug","word":"rug","zh":"地毯"},' +
    '{"id":"tv","word":"TV","zh":"电视"}],' +
    '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}')
  expect(r.ok).assertFalse()
})

it('rejects an unknown task type', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","lesson":{"steps":[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"rug","word":"rug","zh":"地毯"},' +
    '{"id":"tv","word":"TV","zh":"电视"}],' +
    '"task":{"type":"color_find","targets":["sofa","rug","tv"]}}}')
  expect(r.ok).assertFalse()
})

it('rejects a non-object lesson', 0, () => {
  const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","lesson":"sofa"}')
  expect(r.ok).assertFalse()
})

it('rejects the remaining invalid lesson shapes', 0, () => {
  const sixSteps = '[' +
    '{"id":"sofa","word":"sofa","zh":"沙发"},{"id":"rug","word":"rug","zh":"地毯"},' +
    '{"id":"tv","word":"TV","zh":"电视"},{"id":"bed","word":"bed","zh":"床"},' +
    '{"id":"desk","word":"desk","zh":"书桌"},{"id":"chair","word":"chair","zh":"椅子"}]'
  const threeSteps = '[{"id":"sofa","word":"sofa","zh":"沙发"},' +
    '{"id":"rug","word":"rug","zh":"地毯"},{"id":"tv","word":"TV","zh":"电视"}]'
  const bad: string[] = [
    '{"skill_key":"english_vocab","lesson":{"steps":' + sixSteps +
      ',"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":[{"id":"sofa","word":"","zh":"沙发"},' +
      '{"id":"rug","word":"rug","zh":"地毯"},{"id":"tv","word":"TV","zh":"电视"}],' +
      '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":[{"id":"sofa","word":"' + 'w'.repeat(33) + '","zh":"沙发"},' +
      '{"id":"rug","word":"rug","zh":"地毯"},{"id":"tv","word":"TV","zh":"电视"}],' +
      '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":[{"id":"sofa","word":"sofa","zh":"' + '中'.repeat(17) + '"},' +
      '{"id":"rug","word":"rug","zh":"地毯"},{"id":"tv","word":"TV","zh":"电视"}],' +
      '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":[{"id":"sofa","word":"sofa","zh":"沙发",' +
      '"say":"' + 'a'.repeat(121) + '"},{"id":"rug","word":"rug","zh":"地毯"},' +
      '{"id":"tv","word":"TV","zh":"电视"}],' +
      '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":[{"id":"sofa","word":"sofa","zh":"沙发",' +
      '"say_zh":"' + '中'.repeat(121) + '"},{"id":"rug","word":"rug","zh":"地毯"},' +
      '{"id":"tv","word":"TV","zh":"电视"}],' +
      '"task":{"type":"listen_find","targets":["sofa","rug","tv"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":' + threeSteps +
      ',"task":{"type":"listen_find","targets":["sofa","sofa","rug"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":' + threeSteps +
      ',"task":{"type":"listen_find","targets":["sofa","rug"]}}}',
    '{"skill_key":"english_vocab","lesson":{"steps":' + threeSteps +
      ',"task":{"type":"listen_find","targets":["sofa","rug","tv"],"max_attempts":0}}}'
  ]
  for (let i = 0; i < bad.length; i++) {
    expect(validateRoomEnglishArgs(bad[i]).ok).assertFalse()
  }
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run each new test in DevEco Studio (right-click `RoomEnglishValidation.test.ets` → Run).
Expected: compile error or FAIL because `lesson` is not yet on `RoomEnglishValidationResult`.

- [ ] **Step 3: Implement the types and validation**

In `RoomEnglishValidation.ets`:

- Add the three interfaces and the `lesson` field shown in **Interfaces**.
- Update every `RoomEnglishValidationResult` construction (`fail()` and the success return) to include `lesson: null` or the parsed plan.
- Add constants:
  ```ts
  const MIN_STEPS: number = 3
  const MAX_STEPS: number = 5
  const MIN_TARGETS: number = 3
  const MAX_TARGETS: number = 5
  const DEFAULT_MAX_ATTEMPTS: number = 2
  const MAX_WORD_LEN: number = 32
  const MAX_ZH_LEN: number = 16
  const MAX_SAY_LEN: number = 120
  ```
- Treat `parsed['lesson']` as follows: `undefined` or `null` → no lesson (`null`); otherwise it must be a non-array object, or fail. Parse `steps` as an array; enforce 3–5. For each step, require an object; `id` / `word` / `zh` are trimmed strings; `say` / `say_zh` are optional trimmed strings. Reject empty `id` / `word` / `zh`, over-length values, unknown ids, and duplicate ids. Normalize `say` to `Look! This is a ${word}.` when empty.
- Parse `task` as an object; `type` must be `listen_find`; `targets` is an array of 3–5 unique trimmed strings, each a step id; `max_attempts` is optional, integer 1–2, default 2.
- If `lesson` is present:
  - `words` omitted/empty → set `words` to the step ids in step order.
  - `words` non-empty → require the same set as step ids (order irrelevant; length equal, every step id present in `words`).
- Error messages must name the offending value and the allowed rule (match the existing style, e.g. `` `room_english 的 lesson.steps[${i}].id「${id}」不是房间物品 id` ``).

- [ ] **Step 4: Run tests to verify they pass**

Run the same hypium file in DevEco Studio.
Expected: all old + new cases PASS.

- [ ] **Step 5: Compile**

Run the hvigor command from **Global Constraints**.
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/RoomEnglishValidation.ets \
  entry/src/ohosTest/ets/test/utils/RoomEnglishValidation.test.ets
git commit -m "feat: validate room_english lesson scripts"
```

---

### Task 2: Pure lesson task state machine

**Files:**
- Create: `entry/src/main/ets/utils/RoomEnglishLesson.ets`
- Test: `entry/src/ohosTest/ets/test/utils/RoomEnglishLesson.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets` (register the new suite)

**Interfaces:**
- Consumes: none (pure ArkTS, no UI/Web imports).
- Produces:
  ```ts
  export interface RoomLessonTaskState {
    targetIndex: number
    wrongStreak: number
    lastWrongId: string
    attempts: number
    correct: number
    firstTry: number
    revealed: number
    resolved: boolean
    completed: boolean
  }

  export type RoomTaskVerdict =
    'correct' | 'wrong' | 'repeat_wrong' | 'reveal' | 'ignore'

  export interface RoomTaskTapResult {
    verdict: RoomTaskVerdict
    state: RoomLessonTaskState
    targetId: string
    advanced: boolean
  }

  export function createTaskState(targets: string[]): RoomLessonTaskState
  export function currentTargetId(state: RoomLessonTaskState, targets: string[]): string
  export function judgeTaskTap(
    state: RoomLessonTaskState,
    targets: string[],
    tappedId: string,
    maxAttempts: number
  ): RoomTaskTapResult
  export function advanceTask(
    state: RoomLessonTaskState,
    targets: string[]
  ): RoomLessonTaskState
  export function isTaskComplete(state: RoomLessonTaskState, targets: string[]): boolean
  export function nextTourIndex(index: number, total: number): number
  export function buildTaskPrompt(word: string): string
  export function buildWrongPrompt(word: string): string
  export function buildSuccessPrompt(word: string): string
  export function buildRevealPrompt(word: string): string
  ```

  Prompt builders return exactly:
  - `buildTaskPrompt(word)` → `Find the ${word}.`
  - `buildWrongPrompt(word)` → `That's a ${word}. Try again.`
  - `buildSuccessPrompt(word)` → `Yes! This is a ${word}.`
  - `buildRevealPrompt(word)` → `Here it is! This is a ${word}.`

- [ ] **Step 1: Write failing tests**

Create `RoomEnglishLesson.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium'
import {
  advanceTask,
  buildRevealPrompt,
  buildSuccessPrompt,
  buildTaskPrompt,
  buildWrongPrompt,
  createTaskState,
  currentTargetId,
  isTaskComplete,
  judgeTaskTap,
  nextTourIndex
} from '../../../../main/ets/utils/RoomEnglishLesson'

const TARGETS: string[] = ['sofa', 'rug', 'tv']

export default function roomEnglishLessonTest() {
  describe('createTaskState', () => {
    it('starts at the first target', 0, () => {
      const s = createTaskState(TARGETS)
      expect(s.targetIndex).assertEqual(0)
      expect(s.correct).assertEqual(0)
      expect(s.completed).assertFalse()
      expect(s.resolved).assertFalse()
      expect(currentTargetId(s, TARGETS)).assertEqual('sofa')
    })
  })

  describe('judgeTaskTap', () => {
    it('accepts a first-try correct tap', 0, () => {
      const r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'sofa', 2)
      expect(r.verdict).assertEqual('correct')
      expect(r.targetId).assertEqual('sofa')
      expect(r.advanced).assertTrue()
      expect(r.state.correct).assertEqual(1)
      expect(r.state.firstTry).assertEqual(1)
      expect(r.state.attempts).assertEqual(1)
      expect(r.state.resolved).assertTrue()
    })

    it('counts a wrong-then-correct tap as correct but not first-try', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'rug', 2)
      expect(r.verdict).assertEqual('wrong')
      r = judgeTaskTap(r.state, TARGETS, 'sofa', 2)
      expect(r.verdict).assertEqual('correct')
      expect(r.state.correct).assertEqual(1)
      expect(r.state.firstTry).assertEqual(0)
      expect(r.state.attempts).assertEqual(2)
    })

    it('does not burn a second attempt on the same wrong object', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'tv', 2)
      expect(r.verdict).assertEqual('wrong')
      expect(r.state.wrongStreak).assertEqual(1)
      r = judgeTaskTap(r.state, TARGETS, 'tv', 2)
      expect(r.verdict).assertEqual('repeat_wrong')
      expect(r.state.wrongStreak).assertEqual(1)
      expect(r.state.attempts).assertEqual(2)
    })

    it('reveals after max_attempts different wrong taps', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'rug', 2)
      r = judgeTaskTap(r.state, TARGETS, 'tv', 2)
      expect(r.verdict).assertEqual('reveal')
      expect(r.targetId).assertEqual('sofa')
      expect(r.advanced).assertTrue()
      expect(r.state.revealed).assertEqual(1)
      expect(r.state.attempts).assertEqual(2)
      expect(r.state.resolved).assertTrue()
    })

    it('ignores taps after a target is resolved', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'sofa', 2)
      r = judgeTaskTap(r.state, TARGETS, 'rug', 2)
      expect(r.verdict).assertEqual('ignore')
      expect(r.advanced).assertFalse()
    })

    it('ignores an empty id', 0, () => {
      const r = judgeTaskTap(createTaskState(TARGETS), TARGETS, '', 2)
      expect(r.verdict).assertEqual('ignore')
    })
  })

  describe('advanceTask', () => {
    it('moves to the next target and clears the per-target counters', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'sofa', 2)
      let s = advanceTask(r.state, TARGETS)
      expect(s.targetIndex).assertEqual(1)
      expect(s.wrongStreak).assertEqual(0)
      expect(s.lastWrongId).assertEqual('')
      expect(s.resolved).assertFalse()
      expect(currentTargetId(s, TARGETS)).assertEqual('rug')
    })

    it('completes after the last target', 0, () => {
      let s = createTaskState(TARGETS)
      let r = judgeTaskTap(s, TARGETS, 'sofa', 2)
      s = advanceTask(r.state, TARGETS)
      r = judgeTaskTap(s, TARGETS, 'rug', 2)
      s = advanceTask(r.state, TARGETS)
      r = judgeTaskTap(s, TARGETS, 'tv', 2)
      s = advanceTask(r.state, TARGETS)
      expect(s.completed).assertTrue()
      expect(s.targetIndex).assertEqual(3)
      expect(isTaskComplete(s, TARGETS)).assertTrue()
    })
  })

  describe('nextTourIndex', () => {
    it('advances until the last tour step', 0, () => {
      expect(nextTourIndex(0, 3)).assertEqual(1)
      expect(nextTourIndex(1, 3)).assertEqual(2)
      expect(nextTourIndex(2, 3)).assertEqual(-1)
    })
  })

  describe('prompt copy', () => {
    it('builds the exact task and feedback sentences', 0, () => {
      expect(buildTaskPrompt('coffee table')).assertEqual('Find the coffee table.')
      expect(buildWrongPrompt('rug')).assertEqual("That's a rug. Try again.")
      expect(buildSuccessPrompt('sofa')).assertEqual('Yes! This is a sofa.')
      expect(buildRevealPrompt('sofa')).assertEqual('Here it is! This is a sofa.')
    })
  })
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the new test file in DevEco Studio.
Expected: module-not-found / compile error because `RoomEnglishLesson.ets` does not exist.

- [ ] **Step 3: Implement `RoomEnglishLesson.ets`**

Rules:

- `createTaskState(targets)`: if `targets.length === 0`, return `completed: true, targetIndex: 0`; otherwise all counters 0, `resolved: false`, `completed: false`.
- `judgeTaskTap`:
  - Return `ignore` with the input state when `state.completed`, `state.resolved`, `tappedId === ''`, or `state.targetIndex >= targets.length`.
  - `targetId = targets[state.targetIndex]`.
  - If `tappedId === targetId`: `verdict='correct'`, `attempts+1`, `correct+1`, `firstTry + (state.wrongStreak === 0 ? 1 : 0)`, `wrongStreak=0`, `lastWrongId=''`, `resolved=true`, `advanced=true`.
  - If `tappedId === state.lastWrongId`: `verdict='repeat_wrong'`, `attempts+1` only; `wrongStreak` and `lastWrongId` unchanged; `advanced=false`.
  - Otherwise: `attempts+1`, `wrongStreak+1`. If the new `wrongStreak >= maxAttempts`: `verdict='reveal'`, `revealed+1`, `wrongStreak=0`, `lastWrongId=''`, `resolved=true`, `advanced=true`. Else `verdict='wrong'`, `lastWrongId=tappedId`, `advanced=false`.
- `advanceTask`: if `state.completed`, return an explicit copy; otherwise `targetIndex+1`, `wrongStreak=0`, `lastWrongId=''`, `resolved=false`, `completed = nextIndex >= targets.length`.
- `isTaskComplete`: `state.completed || state.targetIndex >= targets.length`.
- `nextTourIndex`: return `index + 1` when `index + 1 < total`, otherwise `-1`.
- `currentTargetId`: `targets[state.targetIndex]` or `''`.
- Build every returned state as a **full explicit object** (all fields). Do not use object spread; ArkTS strict mode rejects it.
- No imports needed.

- [ ] **Step 4: Register and run the tests**

In `entry/src/ohosTest/ets/test/List.test.ets`, add `import roomEnglishLessonTest from './utils/RoomEnglishLesson.test';` next to the `RoomEnglishValidation` import, and `roomEnglishLessonTest();` next to its call in `testsuite()`.

Run `RoomEnglishLesson.test.ets` in DevEco Studio.
Expected: all cases PASS.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/RoomEnglishLesson.ets \
  entry/src/ohosTest/ets/test/utils/RoomEnglishLesson.test.ets \
  entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat: add room_english lesson task state machine"
```

---

### Task 3: Web scene auto-speak switch and find-task preparation

**Files:**
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-app.js`

**Interfaces:**
- Consumes: existing `state`, `syncSelection(id)`, `setActiveRoom(roomId)`, `setActiveArea(areaId)`, `hasArea(areaId)`, `chooseObject(id)`, `window.WordRoomApp`.
- Produces:
  - `WordRoomApp.setAutoSpeak(enabled: boolean): void`
  - `WordRoomApp.prepareFind(id: string): boolean` — switches to the object’s room (and living/dining/kitchen camera area when applicable), closes the word card, does **not** select the object or speak.
  - `state.autoSpeak: boolean` (default `true`).

- [ ] **Step 1: Add `autoSpeak` to state**

In the `state` object literal, add `autoSpeak: true,` next to `labelsVisible`.

- [ ] **Step 2: Guard automatic speech**

In `syncSelection(id)`, replace the unconditional `speakCurrentWord();` with:

```js
if (state.autoSpeak) speakCurrentWord();
```

Leave the pronounce button handler (`dom.pronounceButton.addEventListener('click', () => speakCurrentWord())`) unchanged so the child can always replay.

- [ ] **Step 3: Add `prepareFind(id)`**

Place it next to `chooseObject`:

```js
function prepareFind(id) {
  const meta = byId.get(id);
  if (!meta) return false;
  setActiveRoom(meta.room);
  if (meta.room === 'main' && hasArea(meta.category)) {
    setActiveArea(meta.category);
  }
  chooseObject(null);
  return true;
}
```

`chooseObject(null)` is required when `setActiveRoom` short-circuits on the same room; it closes an open word card without selecting the target.

- [ ] **Step 4: Expose the two APIs**

Extend `window.WordRoomApp`:

```js
setAutoSpeak: function (enabled) { state.autoSpeak = !!enabled; },
prepareFind: function (id) { return prepareFind(id); },
```

Keep all existing methods (`select`, `setLabels`, `setRoom`, `setArea`, `ids`).

- [ ] **Step 5: Verify syntax and API presence**

```bash
node --check entry/src/main/resources/rawfile/room3d/assets/room-app.js
grep -n "setAutoSpeak\|prepareFind\|autoSpeak" entry/src/main/resources/rawfile/room3d/assets/room-app.js
```

Expected: `node --check` exits 0; grep shows the state flag, the `syncSelection` guard, the function, and both API methods.

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/resources/rawfile/room3d/assets/room-app.js
git commit -m "feat: add room scene auto-speak switch and prepareFind"
```

---

### Task 4: RoomEnglishCard lesson state machine and bubble UI

**Files:**
- Modify: `entry/src/main/ets/components/room/RoomEnglishCard.ets`
- Modify: `entry/src/main/ets/pages/ChatPage.ets` (add `lesson: null` to the sheet-close cancel payload; no behavior change)

**Interfaces:**
- Consumes:
  - From Task 1: `RoomEnglishLessonPlan`, `RoomLessonStep`, `RoomEnglishValidationResult`, `validateRoomEnglishArgs`, `resolveRoomEnglishView`, `resolveRoomEnglishArea` (the last two are already imported by the card’s free-mode focus logic; extend the import).
  - From Task 2: `RoomLessonTaskState`, `RoomTaskTapResult`, `createTaskState`, `currentTargetId`, `judgeTaskTap`, `advanceTask`, `isTaskComplete`, `nextTourIndex`, `buildTaskPrompt`, `buildWrongPrompt`, `buildSuccessPrompt`, `buildRevealPrompt`.
  - From Task 3: `WordRoomApp.setAutoSpeak(false)` and `WordRoomApp.prepareFind(id)`.
- Produces:
  ```ts
  export interface RoomEnglishLessonResult {
    tour_completed: boolean
    tour_words: string[]
    task_type: string
    task_targets: string[]
    task_correct: number
    task_first_try: number
    task_revealed: number
    task_total: number
    task_attempts: number
    task_completed: boolean
  }
  export interface RoomEnglishAnswerPayload {
    completed: boolean
    explored_count: number
    words: string[]
    focus: string
    skill_key: string
    cancelled: boolean
    lesson: RoomEnglishLessonResult | null
  }
  export interface RoomEnglishArgsView {
    valid: boolean
    focus: string
    words: string[]
    lesson: RoomEnglishLessonPlan | null
  }
  ```

- [ ] **Step 1: Add types and state**

- Extend `RoomEnglishAnswerPayload` with `lesson: RoomEnglishLessonResult | null`.
- Add `RoomEnglishLessonResult` (exported) exactly as above.
- Extend `RoomEnglishArgsView` with `lesson`; initialize `null` in `createArgsView()`; set `view.lesson = result.lesson` in `parseRoomEnglishArgs`.
- Add the local UI mode type:
  ```ts
  type RoomLessonMode = 'free' | 'tour' | 'task' | 'summary' | 'answered'
  ```
- Add state:
  ```ts
  @Local lessonMode: RoomLessonMode = 'free'
  @Local tourIndex: number = 0
  @Local tourCompleted: boolean = false
  @Local taskState: RoomLessonTaskState = createTaskState([])
  @Local bubbleText: string = ''
  @Local bubbleTextZh: string = ''
  @Local speaking: boolean = false
  @Local answeredLesson: RoomEnglishLessonResult | null = null

  private lesson: RoomEnglishLessonPlan | null = null
  private suppressSelectUntil: number = 0
  private advanceTimer: number = -1
  ```
  `taskState` is a single `@Local` object reassigned on every tap; that is the reactive trigger. Do not mutate its fields in place. `speaking` already exists on the card; keep the existing declaration instead of adding a second one.

- [ ] **Step 2: Wire lifecycle and bridge**

- In `aboutToAppear`, after `this.argsView = parseRoomEnglishArgs(...)`, set `this.lesson = this.argsView.lesson`. If `this.isAnswered`, call `readAnsweredPayload()` and set `lessonMode='answered'`; otherwise if `this.lesson !== null`, set `lessonMode='tour'` and `this.taskState = createTaskState(this.lesson.task.targets)`. The pre-seeded task state keeps a mid-tour cancel honest (`task_completed=false`, zero counters).
- In `selectHandler`, before `noteSelected`:
  ```ts
  if (Date.now() < this.suppressSelectUntil) {
    return;
  }
  if (this.lessonMode === 'task') {
    this.handleTaskTap(id, word);
    return;
  }
  this.noteSelected(id, word);
  ```
- In `progressHandler`, skip `applyProgress` when `this.lesson !== null`. The Web’s `syncSelection` adds every selected id to `discovered`; in lesson mode that includes programmatic tour/reveal selections and `prepareFind` targets. Lesson mode tracks child taps through `noteSelected` only, so `payload.words` stays honest.
- In `onPageEnd`, replace the `applyFocusWords()` call with:
  ```ts
  if (this.lesson !== null && !this.isAnswered) {
    this.startOrResumeLesson();
  } else {
    this.applyFocusWords();
  }
  ```
- Add `startOrResumeLesson()`:
  ```ts
  private startOrResumeLesson(): void {
    if (this.lesson === null) {
      return;
    }
    this.runWeb('(function(){try{var app=window.WordRoomApp;if(app){app.setAutoSpeak(false);}}catch(e){}})();')
    if (this.lessonMode === 'tour') {
      this.presentStep(this.tourIndex);
    } else if (this.lessonMode === 'task') {
      this.presentTaskStep();
    }
  }
  ```
  `tourIndex`/`taskState` survive a Web reload, so re-presenting the current step is correct.
- Add `runWeb(script: string): Promise<string>` wrapping `this.controller.runJavaScript(script)`.
- In `aboutToDisappear`, clear the advance timer:
  ```ts
  if (this.advanceTimer >= 0) {
    clearTimeout(this.advanceTimer);
    this.advanceTimer = -1;
  }
  this.stopSpeak();
  ```

- [ ] **Step 3: Implement tour**

Add:

```ts
private get lessonTargets(): string[] {
  return this.lesson !== null ? this.lesson.task.targets : []
}
private get tourStepCount(): number {
  return this.lesson !== null ? this.lesson.steps.length : 0
}
private stepForId(id: string): RoomLessonStep | null {
  if (this.lesson === null) {
    return null
  }
  for (let i = 0; i < this.lesson.steps.length; i++) {
    if (this.lesson.steps[i].id === id) {
      return this.lesson.steps[i]
    }
  }
  return null
}

private presentStep(index: number): void {
  const lesson = this.lesson;
  if (lesson === null || index < 0 || index >= lesson.steps.length) {
    this.tourCompleted = true;
    this.startTask();
    return;
  }
  const step = lesson.steps[index];
  this.tourIndex = index;
  this.bubbleText = step.say;
  this.bubbleTextZh = step.sayZh;
  const view = resolveRoomEnglishView(this.argsView.focus)
  const area = resolveRoomEnglishArea(this.argsView.focus)
  let script = '(function(){try{var app=window.WordRoomApp;if(!app){return;}app.setAutoSpeak(false);app.setRoom(\'' + view + '\');'
  if (area !== '') {
    script += 'app.setArea(\'' + area + '\');'
  }
  script += 'app.select(\'' + step.id + '\');}catch(e){}})();'
  this.suppressSelectUntil = Date.now() + 1000;
  this.runWeb(script).catch((e: Error): void => {
    console.error('RoomEnglishCard', `present step failed: ${e.message}`)
  });
  this.speakWord(step.say, step.sayZh);
}

private nextTourStep(): void {
  const next = nextTourIndex(this.tourIndex, this.tourStepCount)
  if (next < 0) {
    this.tourCompleted = true
    this.startTask()
  } else {
    this.presentStep(next)
  }
}

private skipTour(): void {
  this.tourCompleted = false
  this.startTask()
}
```

Getters must return full values; do not use `const` in `@Builder` methods.

- [ ] **Step 4: Implement task**

Add:

```ts
private startTask(): void {
  if (this.lesson === null) { return; }
  this.lessonMode = 'task';
  this.taskState = createTaskState(this.lessonTargets);
  this.presentTaskStep();
}

private presentTaskStep(): void {
  const targets = this.lessonTargets;
  if (targets.length === 0 || isTaskComplete(this.taskState, targets)) {
    this.finishTask();
    return;
  }
  const targetId = currentTargetId(this.taskState, targets);
  const step = this.stepForId(targetId);
  if (step === null) { this.finishTask(); return; }
  this.bubbleText = buildTaskPrompt(step.word);
  this.bubbleTextZh = '';
  this.runWeb('(function(){try{var app=window.WordRoomApp;if(!app){return false;}app.setAutoSpeak(false);return app.prepareFind(\'' + step.id + '\');}catch(e){return false;}})();')
    .then((_result: string): void => { this.speakBubble(); })
    .catch((e: Error): void => { console.error('RoomEnglishCard', 'prepareFind failed: ' + e.message); });
}

private handleTaskTap(id: string, word: string): void {
  // ignore empty; judgeTaskTap; reassign this.taskState
  // noteSelected(id, word) for explored tracking
  // switch verdict:
  //   correct -> bubbleText=buildSuccessPrompt(targetWord); speakBubble(); scheduleAdvance(1200)
  //   wrong   -> bubbleText=buildWrongPrompt(tappedWord); speakBubble()
  //   repeat_wrong -> speakBubble() (same hint)
  //   reveal  -> bubbleText=buildRevealPrompt(targetWord); select target with suppression; speakBubble(); scheduleAdvance(1500)
  //   ignore  -> return
}

private scheduleAdvance(delayMs: number): void {
  if (this.advanceTimer >= 0) { clearTimeout(this.advanceTimer); }
  this.advanceTimer = setTimeout((): void => {
    this.advanceTimer = -1;
    this.advanceTaskStep();
  }, delayMs);
}

private advanceTaskStep(): void {
  const targets = this.lessonTargets;
  this.taskState = advanceTask(this.taskState, targets);
  if (this.taskState.completed) { this.finishTask(); } else { this.presentTaskStep(); }
}

private finishTask(): void {
  this.lessonMode = 'summary';
  this.bubbleText = '太棒了！';
  this.bubbleTextZh = '';
  this.stopSpeak();
}
```

Rules:
- `tappedWord`: look up the tapped id via `stepForId`; fall back to the bridge `word`, then the id.
- In `handleTaskTap`, call `noteSelected(id, word)` for every non-ignore verdict (child-initiated tap).
- `reveal`: set `suppressSelectUntil = Date.now() + 1000` before `app.select(targetId)`.
- Never advance on `wrong`/`repeat_wrong`; only `correct` and `reveal` schedule an advance.
- `scheduleAdvance` must clear any previous timer.

- [ ] **Step 5: Implement payload, submit, cancel, timeline**

Add:

```ts
private buildLessonResult(): RoomEnglishLessonResult | null {
  // null when this.lesson === null
  // tour_words = step ids in order; task_targets = this.lessonTargets
  // task_total = task_targets.length
  // copy taskState.correct/firstTry/revealed/attempts/completed
}

private buildPayload(completed: boolean, cancelled: boolean): RoomEnglishAnswerPayload {
  // completed: caller supplies (lesson: taskState.completed; free: true)
  // lesson: this.buildLessonResult()
}

private cancelLesson(): void {
  // guard submitted/isAnswered
  // submitted=true; stopSpeak(); onAnswer(toolCall.id, JSON.stringify(buildPayload(false, true)))
}

private speakBubble(): void {
  this.speakWord(this.bubbleText, this.bubbleTextZh);
}
```

- `canSubmit()`:
  - lesson mode: `lessonMode === 'summary' && taskState.completed && !isAnswered`
  - free mode: existing `exploredCount > 0`
- `submit()`:
  - lesson mode: guard `canSubmit()`; `completed = taskState.completed`; `cancelled=false`.
  - free mode: existing behavior; payload `lesson: null`.
- `readAnsweredPayload()`: after parsing `completed` and `words`, parse `prev['lesson']` when it is a non-null object into `answeredLesson`. Parse arrays with a file-level `readStringArray(value: Object): string[]`, numbers with `readNumber(value: Object): number` (default 0), booleans with `=== true`. Do not throw if fields are missing.
- `SummaryView`:
  - If `answeredLesson !== null`, show `本课带逛：` + `tourWordsLabel()` and `听词找物：答对 X / Y · 第一次就找到 Z`; if `task_revealed > 0`, append ` · 老师指了 N 个`.
  - `tourWordsLabel()` maps `answeredLesson.tour_words` ids through `stepForId` to `word`, falling back to the id, joined by ` / `.
  - Keep the existing free-mode lines when `answeredLesson === null`.
- `tourCompleted` is set `true` only when the child taps “下一个” on the last step; “跳过带逛” sets it `false`.
- `cancelLesson()` and `submit()` must clear `advanceTimer` before calling `onAnswer`, so a pending praise/advance timer cannot fire after the sheet closes.
- In `ChatPage.ets` `RoomEnglishSheetBuilder`, add `lesson: null` to the `cancelResult` object literal in `bindSheet.onDisappear`. This is the only change needed there; the sheet-close path still exits the lesson without partial stats. Without it, the now-required `lesson` field breaks the ArkTS build.

- [ ] **Step 6: Add the bubble UI and header**

Add getters (no `const` inside builders):

```ts
private get headerTitle(): string
private get headerSubtitle(): string
private get headerActionLabel(): string
private get headerActionEnabled(): boolean
private get bubbleTitle(): string
private get summaryLine(): string
private get summarySubline(): string
```

`HeaderBar`:
- Free mode: existing title/subtitle/button.
- Lesson mode:
  - title `3D 房间英语课`
  - tour subtitle `第 ${tourIndex + 1} / ${tourStepCount} 个词`
  - task subtitle `任务 ${taskState.targetIndex + 1} / ${lessonTargets.length}`
  - summary subtitle `本课完成`
  - action label `跳过带逛` (tour) or `退出本课` (task/summary)
  - action: `skipTour()` / `cancelLesson()`
  - keep the right padding of 44 so the button does not collide with the sheet’s ✕.

`LessonBubble` (`@Builder`, rendered only when `lessonMode !== 'free'`):
```
Column (surface, radius 16, border, padding 14, width 100%)
  Row
    circle 30vp with Text('英') in themePrimary on themePrimary/18
    Column
      Text(bubbleTitle) 13vp medium
      Text(bubbleText) 15vp text_primary
      if bubbleTextZh !== '': Text(bubbleTextZh) 12vp text_secondary
      if summary: Text(summaryLine) 14vp text_primary; Text(summarySubline) 12vp text_secondary
  Row (buttons)
    Button('🔊 再听一次') -> speakBubble()
    if tour: Button('下一个 ›') -> nextTourStep()
    if summary: Button('去答题，赢星星 ›') -> submit()
```
Summary bubble:
- `summaryLine` = `任务答对 ${taskState.correct} / ${lessonTargets.length}`
- `summarySubline` = `第一次就找到 ${taskState.firstTry} 个` + (` · 老师指了 ${taskState.revealed} 个` when `revealed > 0`)

`build()` layout:
- In the non-answered branch, after the existing `Stack(...).layoutWeight(1)` and before closing the `Column`, add:
  ```ts
  if (this.lessonMode !== 'free') {
    this.LessonBubble()
  }
  ```
  The Stack’s `layoutWeight(1)` leaves the bubble its natural height; the bubble is a sibling, not an overlay, so it cannot swallow 3D scene touches.

- [ ] **Step 7: Compile**

Run the hvigor command.
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/ets/components/room/RoomEnglishCard.ets \
  entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat: add guided lesson flow to room_english card"
```

---

### Task 5: Tool schema and description

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets` (`createRoomEnglishToolDefinition`, around lines 3881–3913)

**Interfaces:**
- Consumes: existing `createRoomEnglishToolDefinition()` and `rawSchemaJson`.
- Produces: an optional `lesson` object in the tool schema, matching Task 1’s validation.

- [ ] **Step 1: Add the `lesson` property**

Insert after the `words` property and before `skill_key`:

```json
"lesson": {
  "type": "object",
  "description": "可选。引导式小课脚本：先带逛 3-5 个词，再出一个听词找物任务。不传时保持自由探索。",
  "properties": {
    "steps": {
      "type": "array",
      "minItems": 3,
      "maxItems": 5,
      "description": "3-5 个带逛步骤，顺序即带逛顺序。",
      "items": {
        "type": "object",
        "properties": {
          "id": { "type": "string", "description": "房间物品 id，必须与 words 使用同一套 76 个 id。" },
          "word": { "type": "string", "description": "英文词，如 sofa / coffee table。" },
          "zh": { "type": "string", "description": "中文，如 沙发。" },
          "say": { "type": "string", "description": "英文引导句，最多 120 字；缺省用 Look! This is a {word}." },
          "say_zh": { "type": "string", "description": "中文引导句，最多 120 字；有则先读中文再读英文。" }
        },
        "required": ["id", "word", "zh"]
      }
    },
    "task": {
      "type": "object",
      "properties": {
        "type": { "type": "string", "enum": ["listen_find"], "description": "任务类型，v1 只支持听词找物。" },
        "targets": {
          "type": "array",
          "items": { "type": "string" },
          "minItems": 3,
          "maxItems": 5,
          "description": "3-5 个目标物品 id，必须是 steps 的子集。"
        },
        "max_attempts": { "type": "integer", "minimum": 1, "maximum": 2, "description": "每个目标允许点错的次数，默认 2。" }
      },
      "required": ["type", "targets"]
    }
  },
  "required": ["steps", "task"]
}
```

Remember the JSON-in-template-literal trap: descriptions use 「」 or no ASCII quotes. `Look! This is a {word}.` is safe (no quotes).

- [ ] **Step 2: Update the tool description**

Replace the final sentence `After exploring, follow up with english_quiz or matching_pairs to check the words and award stars.` with:

`Use lesson for a guided mini-lesson (3-5 words + listen_find task); after the receipt, follow up with english_quiz read_aloud to check and award stars.`

Keep the existing “INSTEAD of describing furniture in plain text” sentence.

- [ ] **Step 3: Verify the raw schema parses**

```bash
node -e 'const fs=require("fs");const s=fs.readFileSync("entry/src/main/ets/config/BuiltinTools.ets","utf8");const f=s.slice(s.indexOf("function createRoomEnglishToolDefinition"));const m=f.match(/const rawSchemaJson: string = `([\s\S]*?)`\n/);if(!m)throw new Error("room_english rawSchemaJson not found");JSON.parse(m[1]);console.log("room_english schema ok")'
```

Expected: `room_english schema ok`.

- [ ] **Step 4: Compile**

Run the hvigor command.
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat: add lesson schema to room_english tool"
```

---

### Task 6: English prompts advertise the loop

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`
  - `DEFAULT_ASSISTANT_SYSTEM_PROMPT` “## 全屋 3D 英语探索” line (around line 70)
  - `KIDS_ENGLISH_SYSTEM_PROMPT` ② / new ②-1 / ⑤ (around lines 331–338)

**Interfaces:**
- Consumes: the `lesson` schema from Task 5.
- Produces: prompt text only; no code interface.

- [ ] **Step 1: Replace the default assistant section**

Replace the existing `## 全屋 3D 英语探索` line with:

```
'## 全屋 3D 英语探索\n孩子学家居/房间/厨房/阳台类词汇(sofa、TV、rug、plate、fridge、stove、washing_machine、railing…)时,先开 room_english 走进 3D 全屋:用 lesson 传 3-5 个词的带逛脚本(steps 含 id/word/zh/say/say_zh)和一个 listen_find 任务(targets 3-5 个,必须是 steps 的子集),卡片会自动「讲解→听词找物」;也可只用 words 传目标词做自由探索。回执带 task_correct / task_first_try / task_revealed;讲解完立刻用 english_quiz(mode:「read_aloud」)复测 2-3 个目标词并授星(房间词不要用 picture_word,本地没有对应图片)——room_english 本身不授星。一次课不要点开超过 8 个词,聚焦比刷量重要。\n',
```

- [ ] **Step 2: Replace the kids_english presentation step and add the check step**

Replace ② with:

```
'  ② 呈现:picture_vocab(mode:"en") 看图选词(卡片自动出图),再用 english_quiz(mode:"read_aloud") 跟读;学房间/家居/厨房/阳台词汇时改用 room_english 传 lesson:steps 3-5 个 {id, word, zh, say, say_zh},task{type:"listen_find", targets 3-5 个}(可用 focus 指定 living / dining / kitchen / child / master / balcony),卡片自动带逛并出「听词找物」任务;',
'  ②-1 检验:收到 room_english 回执后,用 english_quiz(mode:"read_aloud") 复测 2-3 个目标词并授星;以回执的 task_correct / task_first_try / task_revealed 为准(不要用 words 判分);task_revealed > 0 或 task_first_try < task_correct 时先重讲错词。房间/家居词不要用 picture_word(本地词库没有对应图片)。',
```

Update ⑤ to:

```
'  ⑤ 复习:english_quiz(mode:"listen_choice" 或 "picture_word") 换个形式重考本课核心词(房间/家居词改用 read_aloud,本地词库没有对应图片);',
```

- [ ] **Step 3: Verify the prompt text**

```bash
grep -n "room_english 传 lesson\|②-1 检验\|task_revealed" entry/src/main/ets/models/AssistantModels.ets
grep -n "picture_word.*房间\|房间.*picture_word" entry/src/main/ets/models/AssistantModels.ets
```

Expected: the first grep finds the new lines. The second grep must find the “do not use picture_word for room words” warning (not a remaining instruction to use it).

- [ ] **Step 4: Compile**

Run the hvigor command.
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "docs: teach english prompts the room_english lesson loop"
```

---

### Task 7: End-to-end build and acceptance

**Files:**
- No code changes expected.

- [ ] **Step 1: Compile the app**

Run the hvigor command from **Global Constraints**.
Expected: `BUILD SUCCESSFUL`; artifact at `entry/build/default/outputs/default/entry-default-signed.hap`.

- [ ] **Step 2: Run the two hypium files in DevEco Studio**

- `RoomEnglishValidation.test.ets`
- `RoomEnglishLesson.test.ets`

Expected: all cases PASS.

- [ ] **Step 3: Manual acceptance**

1. Open a new `kids_english` conversation, say “我想学家居单词”. The teacher calls `room_english` with `lesson`.
2. The card opens the lesson: 3–5 words highlighted in order, bubble shows English + Chinese, and only one voice is heard (native TTS; the Web does not double-speak).
3. Tap “下一个” through the tour. The last step enters the task; TTS says “Find the sofa.”
4. At task start, the scene has switched to the target’s room and the word card is closed (no answer leak).
5. Tap a wrong object: the teacher says the tapped word and “Try again.” Tap the same wrong object again: it repeats the hint without revealing immediately. Tap a different wrong object: it reveals and advances.
6. Tap a correct object: praise, then the next target after ~1.2s.
7. At the summary: correct / first-try / revealed counts match the taps.
8. Tap “去答题，赢星星”: the sheet closes, the teacher calls `english_quiz(mode:"read_aloud")` on 2–3 target words, and a correct read awards 1 star.
9. Close the sheet mid-lesson with the ✕/drag: the tool resolves with `cancelled:true`, the conversation continues, and the pending banner does not reappear.
10. Open an old `room_english` call without `lesson`: free exploration still works, and “我学会了” submits the old payload shape (`lesson:null`).
11. Reload the Web scene mid-task (`scene error → 重新加载`): the card resumes the current target, not step 0.

- [ ] **Step 4: Report**

Report: build result, hypium result, and which manual steps passed/failed. Do not claim a manual step passed if it was not run.
