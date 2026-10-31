/**
 * RoomEnglishLesson - room_english 引导式课程（3–5 步讲解 + listen_find 任务）的纯状态机
 *
 * spec 2026-10-30 §5（引导式课程）；设计为无 UI / Web / service 依赖的纯函数模块，
 * 便于 hypium 单元测试。Task 4 的 RoomEnglishCard 消费这些函数驱动课程流程。
 *
 * 状态流转：
 *   createTaskState → judgeTaskTap（correct / wrong / repeat_wrong / reveal / ignore）
 *   → advanceTask → … → isTaskComplete
 */

import { articleFor } from './RoomEnglishValidation'

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

function buildState(
  targetIndex: number,
  wrongStreak: number,
  lastWrongId: string,
  attempts: number,
  correct: number,
  firstTry: number,
  revealed: number,
  resolved: boolean,
  completed: boolean
): RoomLessonTaskState {
  const state: RoomLessonTaskState = {
    targetIndex: targetIndex,
    wrongStreak: wrongStreak,
    lastWrongId: lastWrongId,
    attempts: attempts,
    correct: correct,
    firstTry: firstTry,
    revealed: revealed,
    resolved: resolved,
    completed: completed
  }
  return state
}

export function createTaskState(targets: string[]): RoomLessonTaskState {
  if (targets.length === 0) {
    return buildState(0, 0, '', 0, 0, 0, 0, false, true)
  }
  return buildState(0, 0, '', 0, 0, 0, 0, false, false)
}

export function currentTargetId(state: RoomLessonTaskState, targets: string[]): string {
  if (state.targetIndex < 0 || state.targetIndex >= targets.length) {
    return ''
  }
  return targets[state.targetIndex]
}

export function judgeTaskTap(
  state: RoomLessonTaskState,
  targets: string[],
  tappedId: string,
  maxAttempts: number
): RoomTaskTapResult {
  const targetId = currentTargetId(state, targets)
  if (state.completed || state.resolved || tappedId === '' || state.targetIndex >= targets.length) {
    const ignored: RoomTaskTapResult = {
      verdict: 'ignore',
      state: state,
      targetId: targetId,
      advanced: false
    }
    return ignored
  }

  if (tappedId === targetId) {
    const next = buildState(
      state.targetIndex,
      0,
      '',
      state.attempts + 1,
      state.correct + 1,
      state.firstTry + (state.wrongStreak === 0 ? 1 : 0),
      state.revealed,
      true,
      state.completed
    )
    const result: RoomTaskTapResult = {
      verdict: 'correct',
      state: next,
      targetId: targetId,
      advanced: true
    }
    return result
  }

  if (tappedId === state.lastWrongId) {
    const next = buildState(
      state.targetIndex,
      state.wrongStreak,
      state.lastWrongId,
      state.attempts + 1,
      state.correct,
      state.firstTry,
      state.revealed,
      state.resolved,
      state.completed
    )
    const result: RoomTaskTapResult = {
      verdict: 'repeat_wrong',
      state: next,
      targetId: targetId,
      advanced: false
    }
    return result
  }

  const newStreak = state.wrongStreak + 1
  if (newStreak >= maxAttempts) {
    const next = buildState(
      state.targetIndex,
      0,
      '',
      state.attempts + 1,
      state.correct,
      state.firstTry,
      state.revealed + 1,
      true,
      state.completed
    )
    const revealed: RoomTaskTapResult = {
      verdict: 'reveal',
      state: next,
      targetId: targetId,
      advanced: true
    }
    return revealed
  }

  const next = buildState(
    state.targetIndex,
    newStreak,
    tappedId,
    state.attempts + 1,
    state.correct,
    state.firstTry,
    state.revealed,
    state.resolved,
    state.completed
  )
  const wrong: RoomTaskTapResult = {
    verdict: 'wrong',
    state: next,
    targetId: targetId,
    advanced: false
  }
  return wrong
}

export function advanceTask(
  state: RoomLessonTaskState,
  targets: string[]
): RoomLessonTaskState {
  if (state.completed) {
    return buildState(
      state.targetIndex,
      state.wrongStreak,
      state.lastWrongId,
      state.attempts,
      state.correct,
      state.firstTry,
      state.revealed,
      state.resolved,
      state.completed
    )
  }
  const nextIndex = state.targetIndex + 1
  return buildState(
    nextIndex,
    0,
    '',
    state.attempts,
    state.correct,
    state.firstTry,
    state.revealed,
    false,
    nextIndex >= targets.length
  )
}

export function isTaskComplete(state: RoomLessonTaskState, targets: string[]): boolean {
  return state.completed || state.targetIndex >= targets.length
}

export function nextTourIndex(index: number, total: number): number {
  if (index + 1 < total) {
    return index + 1
  }
  return -1
}

export function buildTaskPrompt(word: string): string {
  return `Find the ${word}.`
}

export function buildWrongPrompt(word: string): string {
  return `That's ${articleFor(word)} ${word}. Try again.`
}

export function buildSuccessPrompt(word: string): string {
  return `Yes! This is ${articleFor(word)} ${word}.`
}

export function buildRevealPrompt(word: string): string {
  return `Here it is! This is ${articleFor(word)} ${word}.`
}
