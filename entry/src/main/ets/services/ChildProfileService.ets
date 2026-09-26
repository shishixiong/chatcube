import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'

/**
 * 单个技能维度
 */
export class SkillDimension {
  key: string = ''
  label: string = ''
  level: number = 0       // 0=未评估, 1=入门, 2=初步, 3=中等, 4=良好, 5=精通
  lastAssessed: number = 0
  notes: string = ''
  strategy: string = ''          // 孩子解题用的方法（凑十/数数/掰手指）
  misconceptions: string = ''    // 常错点（忘记进位/方向反/数位没对齐）

  constructor(key: string = '', label: string = '', level: number = 0, lastAssessed: number = 0,
              notes: string = '', strategy: string = '', misconceptions: string = '') {
    this.key = key
    this.label = label
    this.level = level
    this.lastAssessed = lastAssessed
    this.notes = notes
    this.strategy = strategy
    this.misconceptions = misconceptions
  }
}

/**
 * 儿童知识画像
 */
export class ChildKnowledgeProfile {
  childName: string = ''
  ageYears: number = 0
  skills: Record<string, SkillDimension> = {}
  overallNote: string = ''
  sessionCount: number = 0
  lastInteraction: number = 0
  strengths: string[] = []
  weakAreas: string[] = []
}

/**
 * 6-7 岁儿童技能维度定义
 */
const SKILL_DEFINITIONS: [string, string][] = [
  ['math_counting', '数数'],
  ['math_number_sense', '数感与数的组成'],
  ['math_addition', '加法'],
  ['math_subtraction', '减法'],
  ['math_multiply', '乘法'],
  ['math_divide', '除法'],
  ['math_shapes', '图形认知'],
  ['math_comparison', '比较排序'],
  ['math_time', '时间认知'],
  ['math_word_problem', '解决问题'],
  ['english_alphabet', '英语字母'],
  ['english_vocab', '英语词汇'],
  ['english_sentence', '英语句子'],
  ['english_phonics', '自然拼读'],
  ['english_reading', '英语跟读'],
  ['general_nature', '自然常识'],
  ['general_social', '社交礼仪'],
  ['general_life', '生活常识'],
  ['logic_thinking', '逻辑思维'],
  ['observation', '观察力'],
  ['spatial_reasoning', '空间推理'],
  ['fine_motor', '精细动作'],
  ['english_writing', '英文书写'],
  ['chinese_writing', '中文书写'],
  ['pinyin', '拼音认读'],
  ['categorization', '分类归纳']
]

/**
 * 儿童学习画像服务
 *
 * 为小星老师助手提供"因材施教"的能力:
 * - 在对话开始时 read 画像, 了解小朋友当前水平
 * - 在教学过程中 update 画像, 记录小朋友的表现
 * - 通过 PreferencesService JSON 持久化, 跨会话保留
 */
export class ChildProfileService {
  private static instance: ChildProfileService | null = null
  private preferences: PreferencesService
  private cachedProfile: ChildKnowledgeProfile | null = null

  private constructor() {
    this.preferences = getPreferencesService()
  }

  static getInstance(): ChildProfileService {
    if (ChildProfileService.instance === null) {
      ChildProfileService.instance = new ChildProfileService()
    }
    return ChildProfileService.instance
  }

  /**
   * 获取当前知识画像。首次加载后缓存在内存中。
   */
  async getProfile(): Promise<ChildKnowledgeProfile> {
    if (this.cachedProfile !== null) {
      return this.cachedProfile
    }
    const json = await this.preferences.getString(PreferenceKeys.CHILD_PROFILE_JSON, '')
    if (json !== '') {
      try {
        this.cachedProfile = parseProfileJson(json)
        return this.cachedProfile
      } catch (error) {
        console.error('ChildProfileService', `Failed to parse profile JSON: ${JSON.stringify(error)}`)
      }
    }
    this.cachedProfile = this.createDefaultProfile()
    return this.cachedProfile
  }

  /**
   * 保存知识画像到持久化存储
   */
  async saveProfile(profile: ChildKnowledgeProfile): Promise<void> {
    this.cachedProfile = profile
    const json = JSON.stringify(profile)
    await this.preferences.setString(PreferenceKeys.CHILD_PROFILE_JSON, json)
  }

  /**
   * 创建默认空画像（所有维度 level=0 即"未评估"）
   */
  createDefaultProfile(): ChildKnowledgeProfile {
    const profile = new ChildKnowledgeProfile()
    profile.skills = {}
    for (let i = 0; i < SKILL_DEFINITIONS.length; i++) {
      const def = SKILL_DEFINITIONS[i]
      const dim = new SkillDimension(def[0], def[1])
      profile.skills[def[0]] = dim
    }
    return profile
  }

  /**
   * 获取所有技能维度的定义（供工具返回给 AI 参考）
   */
  getSkillDefinitions(): SkillDimension[] {
    const result: SkillDimension[] = []
    for (let i = 0; i < SKILL_DEFINITIONS.length; i++) {
      const def = SKILL_DEFINITIONS[i]
      result.push(new SkillDimension(def[0], def[1]))
    }
    return result
  }
}

/**
 * 解析画像 JSON 字符串为 ChildKnowledgeProfile（模块级纯函数, 便于单测覆盖兼容性）。
 * 旧版本 JSON 缺少 strategy / misconceptions 字段或新增技能维度时, 补默认值（26 维齐全）。
 */
export function parseProfileJson(json: string): ChildKnowledgeProfile {
  const parsed = JSON.parse(json) as Object
  const record = parsed as Record<string, Object>
  const profile = new ChildKnowledgeProfile()
  profile.childName = (record['childName'] as string) ?? ''
  profile.ageYears = (record['ageYears'] as number) ?? 0
  profile.overallNote = (record['overallNote'] as string) ?? ''
  profile.sessionCount = (record['sessionCount'] as number) ?? 0
  profile.lastInteraction = (record['lastInteraction'] as number) ?? 0

  // 初始化所有维度
  profile.skills = {}
  for (let i = 0; i < SKILL_DEFINITIONS.length; i++) {
    const def = SKILL_DEFINITIONS[i]
    profile.skills[def[0]] = new SkillDimension(def[0], def[1])
  }

  // 解析已有技能数据
  if (record['skills'] !== undefined && record['skills'] !== null) {
    const skillsRecord = record['skills'] as Record<string, Object>
    const keys = Object.keys(skillsRecord)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      if (profile.skills[key] === undefined) {
        continue
      }
      const skillObj = skillsRecord[key] as Record<string, Object>
      profile.skills[key].level = (skillObj['level'] as number) ?? 0
      profile.skills[key].lastAssessed = (skillObj['lastAssessed'] as number) ?? 0
      profile.skills[key].notes = (skillObj['notes'] as string) ?? ''
      profile.skills[key].strategy = typeof skillObj['strategy'] === 'string' ? skillObj['strategy'] as string : ''
      profile.skills[key].misconceptions = typeof skillObj['misconceptions'] === 'string' ? skillObj['misconceptions'] as string : ''
    }
  }

  profile.strengths = parseStringArray(record['strengths'])
  profile.weakAreas = parseStringArray(record['weakAreas'])

  return profile
}

function parseStringArray(value: Object | undefined): string[] {
  if (value === undefined || value === null || !Array.isArray(value)) {
    return []
  }
  const result: string[] = []
  const arr = value as Object[]
  for (let i = 0; i < arr.length; i++) {
    if (typeof arr[i] === 'string') {
      result.push(arr[i] as string)
    }
  }
  return result
}

export function getChildProfileService(): ChildProfileService {
  return ChildProfileService.getInstance()
}
