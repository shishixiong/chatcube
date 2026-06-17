/**
 * WorkSchedulerExtensionAbility 容器
 *
 * 系统级 21:00 教学评估触发入口
 *
 * 触发流程:
 * 1. WorkSchedulerExtensionAbility.onWorkStart 被系统唤醒
 * 2. 调 EvaluationService.triggerEvaluationForToday(false, 'workScheduler')
 * 3. EvaluationService 内部 pipeline: 周级趋势 → 调 LLM → 写 tsa → 同步触发备课
 *
 * 失败容忍: WorkScheduler 不可用时 (模拟器), EvaluationService.startIntervalCheck
 * 走 setInterval 降级 (每分钟一次, 21:00~21:30 之间检测 + 去重)
 */

import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit'
import { getEvaluationService } from '../services/EvaluationService'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'EntryWorkPlannerAbility'

export default class EntryWorkPlannerAbility extends WorkSchedulerExtensionAbility {
  /**
   * 系统 21:00 闹钟唤醒本 Ability 时调
   * - 走 EvaluationService 9 步 pipeline
   * - 完成后由 EvaluationService 内部处理, 本 Ability 直接结束
   */
  async onWorkStart(workInfo: workScheduler.WorkInfo): Promise<void> {
    hilog.info(DOMAIN, TAG, `onWorkStart triggered. workId=${workInfo.workId}`)
    try {
      // 触发评估 → 内部会同步触发备课
      await getEvaluationService().triggerEvaluationForToday(false, 'workScheduler')
    } catch (e) {
      hilog.error(DOMAIN, TAG, `triggerEvaluationForToday failed: ${JSON.stringify(e)}`)
    }
    // WorkSchedulerExtensionAbility onWorkStart 返回后, 系统自动结束本 work
  }

  /**
   * 系统级网络/存储条件变化时回调 (本应用未订阅, no-op)
   */
  onWorkStop(workInfo: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, `onWorkStop. workId=${workInfo.workId}`)
  }
}
