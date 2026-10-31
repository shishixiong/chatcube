/**
 * RoomEnglishValidation - room_english 参数预校验纯逻辑层（spec 2026-10-24 §5；
 * 引导式课程 lesson 见 spec 2026-10-30）
 *
 * 在 ToolExecutionService.handleRoomEnglish 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 设计参考 utils/MapToolValidation.ets（预校验 + should_retry 范式）。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 room_english schema）：
 *  - skill_key 必须恰为 english_vocab
 *  - focus 可选，枚举 living / dining / kitchen / child / master / balcony / all（默认 all）
 *    living / dining / kitchen 都是客餐厅这一间，页面还会把镜头对准对应分区；
 *    child / master / balcony 会直接切到对应房间
 *  - words 可选，最多 8 个，且必须命中四间房里的 76 个物品 id
 *  - lesson 可选，引导式课程：3–5 个步骤 + 一个 listen_find 任务；
 *    有 lesson 时 words 缺省按步骤 id 补齐，非空则必须与步骤集一致
 */

export interface RoomLessonStep {
  id: string
  word: string
  zh: string
  /** 归一化后的英文讲解句，缺省为 `Look! This is a/an {word}.`（冠词由 articleFor 决定） */
  say: string
  /** 中文讲解句，缺省为空串 */
  sayZh: string
}

export interface RoomLessonTask {
  /** 目前固定为 listen_find */
  type: string
  /** 步骤 id 列表 */
  targets: string[]
  /** 1–2，缺省 2 */
  maxAttempts: number
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

/** 四间房里 76 件可点击物品的 id，与 rawfile/room3d/assets/scene-data.js 一一对应
 *  （客厅 15 + 餐厅 10 + 厨房 12 + 儿童房 12 + 主卧 12 + 阳台 15）。 */
export const ROOM_OBJECT_IDS: string[] = [
  'sofa',
  'coffee_table',
  'tv',
  'tv_stand',
  'remote_control',
  'rug',
  'cushion',
  'floor_lamp',
  'bookshelf',
  'book',
  'plant',
  'curtain',
  'window',
  'picture',
  'clock',
  'air_conditioner',
  'trash_can',
  'dining_table',
  'dining_chair',
  'plate',
  'bowl',
  'cup',
  'spoon',
  'fork',
  'kettle',
  'fridge',
  'stove',
  'oven',
  'sink',
  'pot',
  'pan',
  'toaster',
  'microwave',
  'dishwasher',
  'cabinet',
  'knife',
  'stool',
  // 儿童房（12）
  'bed',
  'desk',
  'chair',
  'wardrobe',
  'toy_box',
  'round_rug',
  'bookcase',
  'shelf',
  'basket',
  'poster',
  'blanket',
  'toy_car',
  // 主卧（12）
  'double_bed',
  'nightstand',
  'lamp',
  'pillow',
  'closet',
  'dresser',
  'mirror',
  'stool_master',
  'bench',
  'rug_master',
  'heater',
  'photo_frame',
  // 阳台（15）
  'washing_machine',
  'dryer',
  'laundry_basket',
  'drying_rack',
  'clothespin',
  'laundry_sink',
  'storage_cabinet',
  'broom',
  'mop',
  'bucket',
  'balcony_plant',
  'flower_pot',
  'watering_can',
  'railing',
  'folding_stool'
]

const FOCUS_MODES: string[] = ['living', 'dining', 'kitchen', 'child', 'master', 'balcony', 'all']
const FOCUS_HINT: string = 'living / dining / kitchen / child / master / balcony / all'
const MAX_WORDS: number = 8
const MIN_STEPS: number = 3
const MAX_STEPS: number = 5
const MIN_TARGETS: number = 3
const MAX_TARGETS: number = 5
const DEFAULT_MAX_ATTEMPTS: number = 2
const MAX_WORD_LEN: number = 32
const MAX_ZH_LEN: number = 16
const MAX_SAY_LEN: number = 120
const LESSON_TASK_TYPES: string[] = ['listen_find']

/** 英文不定冠词：元音字母开头用 an，其余（含空串）用 a。 */
export function articleFor(word: string): string {
  const trimmed: string = word.trim()
  if (trimmed === '') {
    return 'a'
  }
  const first: string = trimmed.charAt(0).toLowerCase()
  if (first === 'a' || first === 'e' || first === 'i' || first === 'o' || first === 'u') {
    return 'an'
  }
  return 'a'
}

/** focus → 页面视图：三科区域归主屋，三间房各自打开，all/缺省打开全屋。 */
export function resolveRoomEnglishView(focus: string): string {
  const value: string = focus ? focus.trim() : ''
  if (value === 'child' || value === 'master' || value === 'balcony') {
    return value
  }
  if (value === 'living' || value === 'dining' || value === 'kitchen') {
    return 'main'
  }
  return 'overview'
}

/** focus → 客餐厅内部分区镜头（客厅 / 餐厅 / 厨房），其余 focus 返回空串表示不移动中心。 */
export function resolveRoomEnglishArea(focus: string): string {
  const value: string = focus ? focus.trim() : ''
  if (value === 'living' || value === 'dining' || value === 'kitchen') {
    return value
  }
  return ''
}

interface LessonParseOutcome {
  ok: boolean
  error: string
  plan: RoomEnglishLessonPlan | null
}

interface StringFieldOutcome {
  ok: boolean
  value: string
  error: string
}

function isPlainObject(value: Object): boolean {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value)
}

function lessonFail(msg: string): LessonParseOutcome {
  const r: LessonParseOutcome = { ok: false, error: msg, plan: null }
  return r
}

function lessonSucceed(plan: RoomEnglishLessonPlan): LessonParseOutcome {
  const r: LessonParseOutcome = { ok: true, error: '', plan: plan }
  return r
}

function readStringField(obj: Record<string, Object>, key: string, label: string,
  required: boolean, maxLen: number): StringFieldOutcome {
  const raw = obj[key]
  if (raw === undefined || raw === null) {
    if (required) {
      const miss: StringFieldOutcome = { ok: false, value: '', error: `room_english 的 ${label} 必须是非空字符串` }
      return miss
    }
    const empty: StringFieldOutcome = { ok: true, value: '', error: '' }
    return empty
  }
  if (typeof raw !== 'string') {
    const bad: StringFieldOutcome = { ok: false, value: '', error: `room_english 的 ${label} 必须是字符串` }
    return bad
  }
  const value: string = (raw as string).trim()
  if (required && value === '') {
    const blank: StringFieldOutcome = { ok: false, value: '', error: `room_english 的 ${label} 必须是非空字符串` }
    return blank
  }
  if (maxLen > 0 && value.length > maxLen) {
    const long: StringFieldOutcome = {
      ok: false, value: '',
      error: `room_english 的 ${label} 最多 ${maxLen} 个字符，收到 ${value.length} 个`
    }
    return long
  }
  const good: StringFieldOutcome = { ok: true, value: value, error: '' }
  return good
}

function parseLessonSteps(lessonObj: Record<string, Object>): LessonParseOutcome {
  const stepsRaw = lessonObj['steps']
  if (!Array.isArray(stepsRaw)) {
    return lessonFail(`room_english 的 lesson.steps 必须是数组，包含 ${MIN_STEPS}–${MAX_STEPS} 个单词步骤`)
  }
  const stepsList = stepsRaw as Object[]
  if (stepsList.length < MIN_STEPS || stepsList.length > MAX_STEPS) {
    return lessonFail(`room_english 的 lesson.steps 必须有 ${MIN_STEPS}–${MAX_STEPS} 步，收到 ${stepsList.length} 步`)
  }

  const steps: RoomLessonStep[] = []
  const stepIds: string[] = []
  for (let i = 0; i < stepsList.length; i++) {
    const stepRaw = stepsList[i]
    if (!isPlainObject(stepRaw)) {
      return lessonFail(`room_english 的 lesson.steps[${i}] 必须是对象`)
    }
    const stepObj = stepRaw as Record<string, Object>

    const idOut = readStringField(stepObj, 'id', `lesson.steps[${i}].id`, true, 0)
    if (!idOut.ok) {
      return lessonFail(idOut.error)
    }
    const id: string = idOut.value
    if (ROOM_OBJECT_IDS.indexOf(id) < 0) {
      return lessonFail(`room_english 的 lesson.steps[${i}].id「${id}」不是房间物品 id，合法 id：${ROOM_OBJECT_IDS.join(' ')}`)
    }
    if (stepIds.indexOf(id) >= 0) {
      return lessonFail(`room_english 的 lesson.steps[${i}].id「${id}」重复了，每一步必须是不同单词`)
    }

    const wordOut = readStringField(stepObj, 'word', `lesson.steps[${i}].word`, true, MAX_WORD_LEN)
    if (!wordOut.ok) {
      return lessonFail(wordOut.error)
    }
    const word: string = wordOut.value

    const zhOut = readStringField(stepObj, 'zh', `lesson.steps[${i}].zh`, true, MAX_ZH_LEN)
    if (!zhOut.ok) {
      return lessonFail(zhOut.error)
    }

    const sayOut = readStringField(stepObj, 'say', `lesson.steps[${i}].say`, false, MAX_SAY_LEN)
    if (!sayOut.ok) {
      return lessonFail(sayOut.error)
    }

    const sayZhOut = readStringField(stepObj, 'say_zh', `lesson.steps[${i}].say_zh`, false, MAX_SAY_LEN)
    if (!sayZhOut.ok) {
      return lessonFail(sayZhOut.error)
    }

    let say: string = sayOut.value
    if (say === '') {
      say = 'Look! This is ' + articleFor(word) + ' ' + word + '.'
    }
    const step: RoomLessonStep = {
      id: id, word: word, zh: zhOut.value, say: say, sayZh: sayZhOut.value
    }
    steps.push(step)
    stepIds.push(id)
  }

  return validateLessonTask(lessonObj, steps, stepIds)
}

function validateLessonTask(lessonObj: Record<string, Object>, steps: RoomLessonStep[],
  stepIds: string[]): LessonParseOutcome {
  const taskRaw = lessonObj['task']
  if (!isPlainObject(taskRaw)) {
    return lessonFail('room_english 的 lesson.task 必须是对象，含 type / targets / max_attempts')
  }
  const taskObj = taskRaw as Record<string, Object>

  const typeOut = readStringField(taskObj, 'type', 'lesson.task.type', true, 0)
  if (!typeOut.ok) {
    return lessonFail(typeOut.error)
  }
  if (LESSON_TASK_TYPES.indexOf(typeOut.value) < 0) {
    return lessonFail(`room_english 的 lesson.task.type 目前只支持 ${LESSON_TASK_TYPES.join(' / ')}，收到「${typeOut.value}」`)
  }

  const targetsRaw = taskObj['targets']
  if (!Array.isArray(targetsRaw)) {
    return lessonFail(`room_english 的 lesson.task.targets 必须是 ${MIN_TARGETS}–${MAX_TARGETS} 个步骤 id 的数组`)
  }
  const targetList = targetsRaw as Object[]
  if (targetList.length < MIN_TARGETS || targetList.length > MAX_TARGETS) {
    return lessonFail(`room_english 的 lesson.task.targets 必须有 ${MIN_TARGETS}–${MAX_TARGETS} 个步骤 id，收到 ${targetList.length} 个`)
  }
  const targets: string[] = []
  for (let i = 0; i < targetList.length; i++) {
    const item = targetList[i]
    if (typeof item !== 'string') {
      return lessonFail(`room_english 的 lesson.task.targets[${i}] 必须是步骤 id 字符串`)
    }
    const target: string = (item as string).trim()
    if (stepIds.indexOf(target) < 0) {
      return lessonFail(`room_english 的 lesson.task.targets 里「${target}」不是本节课的步骤 id，可选：${stepIds.join(' ')}`)
    }
    if (targets.indexOf(target) >= 0) {
      return lessonFail(`room_english 的 lesson.task.targets 里「${target}」重复了，targets 必须互不相同`)
    }
    targets.push(target)
  }

  let maxAttempts: number = DEFAULT_MAX_ATTEMPTS
  const attemptsRaw = taskObj['max_attempts']
  if (attemptsRaw !== undefined && attemptsRaw !== null) {
    if (typeof attemptsRaw !== 'number') {
      return lessonFail('room_english 的 lesson.task.max_attempts 必须是整数 1 或 2')
    }
    const attempts: number = attemptsRaw as number
    if (Math.floor(attempts) !== attempts || attempts < 1 || attempts > 2) {
      return lessonFail(`room_english 的 lesson.task.max_attempts 只能是整数 1 或 2，收到 ${attempts}`)
    }
    maxAttempts = attempts
  }

  const task: RoomLessonTask = { type: 'listen_find', targets: targets, maxAttempts: maxAttempts }
  const plan: RoomEnglishLessonPlan = { steps: steps, task: task }
  return lessonSucceed(plan)
}

function parseLesson(lessonRaw: Object): LessonParseOutcome {
  if (!isPlainObject(lessonRaw)) {
    return lessonFail('room_english 的 lesson 必须是对象（含 steps 与 task），不能是数组或字符串')
  }
  return parseLessonSteps(lessonRaw as Record<string, Object>)
}

function fail(msg: string): RoomEnglishValidationResult {
  const r: RoomEnglishValidationResult = { ok: false, error: msg, focus: 'all', words: [], lesson: null }
  return r
}

export function validateRoomEnglishArgs(args: string): RoomEnglishValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('room_english 参数不是合法 JSON, 请检查后重新开课')
  }

  const skillKey = ((parsed['skill_key'] as string) ?? '').trim()
  if (skillKey !== 'english_vocab') {
    return fail(`room_english 的 skill_key 必须固定传 english_vocab（英语词汇），收到「${skillKey}」`)
  }

  let focus = 'all'
  const focusRaw = parsed['focus']
  if (focusRaw !== undefined && focusRaw !== null) {
    if (typeof focusRaw !== 'string') {
      return fail(`room_english 的 focus 必须是字符串：${FOCUS_HINT}`)
    }
    focus = (focusRaw as string).trim()
    if (FOCUS_MODES.indexOf(focus) < 0) {
      return fail(`room_english 的 focus「${focus}」无效，只能是 ${FOCUS_HINT}`)
    }
  }

  const words: string[] = []
  const wordsRaw = parsed['words']
  if (wordsRaw !== undefined && wordsRaw !== null) {
    if (!Array.isArray(wordsRaw)) {
      return fail('room_english 的 words 必须是字符串数组，例如 ["sofa","tv","rug"]')
    }
    const list = wordsRaw as Object[]
    if (list.length > MAX_WORDS) {
      return fail(`room_english 一次最多重点讲 ${MAX_WORDS} 个单词，收到 ${list.length} 个`)
    }
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'string') {
        return fail('room_english 的 words 数组里只能放字符串 id')
      }
      const id = (item as string).trim()
      if (id === '') {
        continue
      }
      if (ROOM_OBJECT_IDS.indexOf(id) < 0) {
        return fail(`room_english 的 words 里「${id}」不是房间里的物品 id，合法 id：${ROOM_OBJECT_IDS.join(' ')}`)
      }
      if (words.indexOf(id) < 0) {
        words.push(id)
      }
    }
  }

  let lessonPlan: RoomEnglishLessonPlan | null = null
  const lessonRaw = parsed['lesson']
  if (lessonRaw !== undefined && lessonRaw !== null) {
    const lessonOut = parseLesson(lessonRaw)
    if (!lessonOut.ok) {
      return fail(lessonOut.error)
    }
    lessonPlan = lessonOut.plan
    if (lessonPlan !== null) {
      const stepIds: string[] = []
      for (let i = 0; i < lessonPlan.steps.length; i++) {
        stepIds.push(lessonPlan.steps[i].id)
      }
      if (words.length === 0) {
        // words 缺省/为空 → 按步骤顺序补齐，课程单词即步骤单词
        for (let i = 0; i < stepIds.length; i++) {
          words.push(stepIds[i])
        }
      } else {
        // words 非空 → 必须与步骤集一致（顺序不限，长度相等且每个步骤 id 都在 words 里）
        if (words.length !== stepIds.length) {
          return fail(`room_english 的 words 必须与 lesson.steps 的单词一致，课程有 ${stepIds.length} 个单词（${stepIds.join(' ')}），收到 ${words.length} 个（${words.join(' ')}）`)
        }
        for (let i = 0; i < stepIds.length; i++) {
          if (words.indexOf(stepIds[i]) < 0) {
            return fail(`room_english 的 words 必须与 lesson.steps 的单词一致，缺少步骤单词「${stepIds[i]}」，课程单词：${stepIds.join(' ')}`)
          }
        }
      }
    }
  }

  const result: RoomEnglishValidationResult = { ok: true, error: '', focus: focus, words: words, lesson: lessonPlan }
  return result
}
