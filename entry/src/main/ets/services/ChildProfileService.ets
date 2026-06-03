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

  constructor(key: string = '', label: string = '') {
    this.key = key
    this.label = label
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
  ['math_addition', '加法'],
  ['math_subtraction', '减法'],
  ['math_multiply', '乘法'],
  ['math_divide', '除法'],
  ['math_shapes', '图形认知'],
  ['math_comparison', '比较排序'],
  ['math_time', '时间认知'],
  ['english_alphabet', '英语字母'],
  ['english_vocab', '英语词汇'],
  ['english_sentence', '英语句子'],
  ['english_phonics', '自然拼读'],
  ['general_nature', '自然常识'],
  ['general_social', '社交礼仪'],
  ['general_life', '生活常识'],
  ['logic_puzzle', '逻辑思维'],
  ['observation', '观察力']
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
        const parsed = JSON.parse(json) as Object
        this.cachedProfile = this.parseProfile(parsed)
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

  private parseProfile(obj: Object): ChildKnowledgeProfile {
    const record = obj as Record<string, Object>
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
      }
    }

    profile.strengths = this.parseStringArray(record['strengths'])
    profile.weakAreas = this.parseStringArray(record['weakAreas'])

    return profile
  }

  private parseStringArray(value: Object | undefined): string[] {
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
}

export function getChildProfileService(): ChildProfileService {
  return ChildProfileService.getInstance()
}
