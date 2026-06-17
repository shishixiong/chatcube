/**
 * 技能维度本地化标签工具
 *
 * 单一职责: 把 22 维技能 key (math_addition / english_vocab / general_nature 等)
 * 解析成家长可读的中文标签, 跨 LearningProfilePage / LearningTomorrowPlanPage 复用。
 *
 * 数据源: ChildProfileService.SKILL_DEFINITIONS 的 label 字段(已含中文)。
 *
 * 用法:
 *   import { getSkillLabel, getSkillGroupLabel } from '../utils/SkillLabelUtils'
 *   Text(getSkillLabel('math_shapes', 'math_shapes'))  // → "图形·数学"
 */

import { getChildProfileService, SkillDimension } from '../services/ChildProfileService'

/**
 * 通过 skill key 查中文标签, 未命中返回 fallback(原始 key)。
 * 纯函数, 无副作用, 内部缓存 SKILL_DEFINITIONS 查询结果。
 */
export function getSkillLabel(key: string, fallback: string): string {
  const def = findSkillDefinition(key)
  if (def !== null && def.label !== '') {
    return def.label
  }
  return fallback
}

/**
 * 通过 skill key 查所属大类标签 ("数学" / "英语" / "常识" / "认知" / "书写")。
 * 用于 LessonPlan 列表项 dimension 渲染的「图形·数学」分组前缀。
 */
export function getSkillGroupLabel(key: string, fallback: string): string {
  const group = inferSkillGroup(key)
  if (group !== '') {
    return group
  }
  return fallback
}

function findSkillDefinition(key: string): SkillDimension | null {
  const definitions = getChildProfileService().getSkillDefinitions()
  if (definitions === null || definitions === undefined) {
    return null
  }
  for (let i = 0; i < definitions.length; i++) {
    if (definitions[i].key === key) {
      return definitions[i]
    }
  }
  return null
}

// 22 维技能的 group 推断, 避免引入额外 group 表。命名规则: "<domain>_<...>"
function inferSkillGroup(key: string): string {
  if (key.startsWith('math_')) {
    return '数学'
  }
  if (key.startsWith('english_')) {
    return '英语'
  }
  if (key.startsWith('general_')) {
    return '常识'
  }
  if (key === 'logic_thinking' || key === 'observation' || key === 'spatial_reasoning') {
    return '认知'
  }
  if (key === 'fine_motor' || key === 'chinese_writing') {
    return '书写'
  }
  if (key === 'categorization') {
    return '认知'
  }
  return ''
}
