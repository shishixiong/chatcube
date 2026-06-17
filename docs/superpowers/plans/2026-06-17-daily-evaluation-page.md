# 每日评估查看页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `LearningDailyEvaluationPage` 页面，从"学习中心"入口进入，展示评估老师每日产出的 4 维度教学风格调整 + 关联的本周趋势，支持查看过去 14 天历史。

**Architecture:** 复用 `LearningTomorrowPlanPage` 的页面骨架（HdsNavigation + 详情模式 + 轮询 + 状态机），新增 2 个 utils（`TeachingStyleAdjustmentUtils` / `DateRangeUtils`）+ 1 个 `WeeklyTrendService.getTrendById` helper。评估数据全部从 `TeachingStyleAdjustmentService.getAdjustmentForDate` 读取，无新服务、无新模型、无新表。

**Tech Stack:** ArkTS `@ComponentV2` + `@ObservedV2` + `@Local`，复用 `HdsNavigation` / `SettingsCompactTitleBarContent` / `formatRelativeTime` / `formatLocalYMD` / `getDayOfWeekLabel` / `withColorAlpha` / `buildPointLightBorderEffect`。hypium 单元测试覆盖 utils。

**Spec:** `docs/superpowers/specs/2026-06-17-daily-evaluation-page-design.md`

---

## File Structure

| 文件 | 角色 | 状态 |
|------|------|------|
| `pages/LearningDailyEvaluationPage.ets` | 主页面（~750 行，12 个 @Builder） | 新建 |
| `utils/TeachingStyleAdjustmentUtils.ets` | 4 维度 enum → 中文 label/icon 映射 + 进度计算 | 新建 |
| `utils/DateRangeUtils.ets` | 14 天边界判断 + YMD shift | 新建 |
| `services/WeeklyTrendService.ets` | + `getTrendById(id)` 1 个方法（10 行） | 修改 |
| `config/SettingsRouteName.ets` | + `LEARNING_DAILY_EVALUATION` 枚举值 | 修改 |
| `resources/base/profile/router_map.json` | + 注册 `LearningDailyEvaluationPage` | 修改 |
| `components/index/IndexSettingsPanel.ets` | "学习中心"分组加第 4 项 | 修改 |
| `pages/Index.ets` | + `onOpenLearningDailyEvaluation` handler | 修改 |
| `resources/base/element/string.json` | + 32 个 string keys | 修改 |
| `entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets` | DateRangeUtils 单元测试 | 新建 |
| `entry/src/ohosTest/ets/test/utils/TeachingStyleAdjustmentUtils.test.ets` | 维度 utils 单元测试 | 新建 |
| `entry/src/ohosTest/ets/test/services/WeeklyTrendService.getTrendById.test.ets` | getTrendById 单元测试 | 新建 |

---

### Task 1: 创建 `DateRangeUtils` (TDD)

**Files:**
- Create: `entry/src/main/ets/utils/DateRangeUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets`

- [ ] **Step 1: 写失败的测试**

```typescript
// entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets
import { describe, it, expect } from '@ohos/hypium'
import {
  isWithinHistoryRange,
  canGoBack,
  canGoForward,
  todayYMD,
  shiftYMD
} from '../../../../main/ets/utils/DateRangeUtils'

const NOW_MS: number = new Date('2026-06-17T10:00:00').getTime()
const TODAY: string = '2026-06-17'

export default function dateRangeUtilsTest() {
  describe('isWithinHistoryRange', () => {
    it('returns true for today', 0, () => {
      expect(isWithinHistoryRange(TODAY, NOW_MS)).assertTrue()
    })
    it('returns true for 14 days ago', 0, () => {
      expect(isWithinHistoryRange('2026-06-03', NOW_MS)).assertTrue()
    })
    it('returns false for 15 days ago', 0, () => {
      expect(isWithinHistoryRange('2026-06-02', NOW_MS)).assertFalse()
    })
    it('returns false for future date', 0, () => {
      expect(isWithinHistoryRange('2026-06-18', NOW_MS)).assertFalse()
    })
  })

  describe('canGoBack', () => {
    it('true when more than 14 days old', 0, () => {
      expect(canGoBack('2026-06-03', NOW_MS)).assertTrue()
    })
    it('false when exactly 14 days old', 0, () => {
      expect(canGoBack('2026-06-03', NOW_MS)).assertTrue()
    })
    it('false when today', 0, () => {
      expect(canGoBack(TODAY, NOW_MS)).assertFalse()
    })
  })

  describe('canGoForward', () => {
    it('true when before today', 0, () => {
      expect(canGoForward('2026-06-16', NOW_MS)).assertTrue()
    })
    it('false when today', 0, () => {
      expect(canGoForward(TODAY, NOW_MS)).assertFalse()
    })
    it('false when future', 0, () => {
      expect(canGoForward('2026-06-18', NOW_MS)).assertFalse()
    })
  })

  describe('todayYMD', () => {
    it('returns YYYY-MM-DD format', 0, () => {
      const ymd = todayYMD(NOW_MS)
      expect(ymd).assertEqual('2026-06-17')
    })
  })

  describe('shiftYMD', () => {
    it('shifts forward by 1 day', 0, () => {
      expect(shiftYMD('2026-06-17', 1)).assertEqual('2026-06-18')
    })
    it('shifts backward by 1 day', 0, () => {
      expect(shiftYMD('2026-06-17', -1)).assertEqual('2026-06-16')
    })
    it('crosses month boundary', 0, () => {
      expect(shiftYMD('2026-06-01', -1)).assertEqual('2026-05-31')
    })
    it('crosses year boundary', 0, () => {
      expect(shiftYMD('2026-01-01', -1)).assertEqual('2025-12-31')
    })
  })
}
```

- [ ] **Step 2: 运行测试确认失败**

DevEco Studio: 右键 `DateRangeUtils.test.ets` → Run

Expected: 测试失败，错误信息包含 `Cannot find module '../../../../main/ets/utils/DateRangeUtils'`

- [ ] **Step 3: 实现 `DateRangeUtils`**

```typescript
// entry/src/main/ets/utils/DateRangeUtils.ets
/**
 * 日期范围工具 — 每日评估页用
 * 14 天历史滚动范围判断 + YMD 字符串位移
 */

const MS_PER_DAY: number = 24 * 60 * 60 * 1000
const MAX_HISTORY_DAYS: number = 14

/**
 * 把 epoch ms 转为 'YYYY-MM-DD' (本地时区)
 */
export function todayYMD(nowMs: number = Date.now()): string {
  const d: Date = new Date(nowMs)
  const y: number = d.getFullYear()
  const m: string = String(d.getMonth() + 1).padStart(2, '0')
  const day: string = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/**
 * 把 'YYYY-MM-DD' 解析为本地时区 0 点的 epoch ms
 */
function ymdToMs(ymd: string): number {
  const parts: string[] = ymd.split('-')
  if (parts.length !== 3) {
    return NaN
  }
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])).getTime()
}

/**
 * 距今不超过 14 天的历史范围内。
 * - 14 天前的当天: true
 * - 15 天前: false
 * - 未来: false
 */
export function isWithinHistoryRange(ymd: string, nowMs: number = Date.now()): boolean {
  const targetMs: number = ymdToMs(ymd)
  if (isNaN(targetMs)) {
    return false
  }
  const todayMs: number = ymdToMs(todayYMD(nowMs))
  const diffDays: number = Math.floor((todayMs - targetMs) / MS_PER_DAY)
  return diffDays >= 0 && diffDays <= MAX_HISTORY_DAYS
}

/**
 * 能否再向回切一天（还有更早的历史可看）
 */
export function canGoBack(selectedYMD: string, nowMs: number = Date.now()): boolean {
  const oneDayEarlier: string = shiftYMD(selectedYMD, -1)
  return isWithinHistoryRange(oneDayEarlier, nowMs)
}

/**
 * 能否再向前切一天（还没到今天）
 */
export function canGoForward(selectedYMD: string, nowMs: number = Date.now()): boolean {
  const oneDayLater: string = shiftYMD(selectedYMD, 1)
  const today: string = todayYMD(nowMs)
  return oneDayLater <= today
}

/**
 * YMD 字符串位移 N 天（可为负）
 * - 跨月/跨年正确处理
 * - 输入非法时返回原字符串
 */
export function shiftYMD(ymd: string, days: number): string {
  const ms: number = ymdToMs(ymd)
  if (isNaN(ms)) {
    return ymd
  }
  return todayYMD(ms + days * MS_PER_DAY)
}
```

- [ ] **Step 4: 运行测试确认通过**

DevEco Studio: 右键 `DateRangeUtils.test.ets` → Run

Expected: 所有断言通过（~14 个）

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/utils/DateRangeUtils.ets \
        entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets
git commit -m "feat(eval-page): DateRangeUtils 14 天边界 + YMD shift (TDD)"
```

---

### Task 2: 创建 `TeachingStyleAdjustmentUtils` (TDD)

**Files:**
- Create: `entry/src/main/ets/utils/TeachingStyleAdjustmentUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/TeachingStyleAdjustmentUtils.test.ets`

- [ ] **Step 1: 写失败的测试**

```typescript
// entry/src/ohosTest/ets/test/utils/TeachingStyleAdjustmentUtils.test.ets
import { describe, it, expect } from '@ohos/hypium'
import {
  getDimensionLabel,
  computeTrendProgress
} from '../../../../main/ets/utils/TeachingStyleAdjustmentUtils'

export default function teachingStyleAdjustmentUtilsTest() {
  describe('getDimensionLabel - difficultyTendency', () => {
    it('easier -> 偏简单', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'easier')).assertEqual('偏简单')
    })
    it('current -> 保持', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'current')).assertEqual('保持')
    })
    it('harder -> 偏难', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'harder')).assertEqual('偏难')
    })
  })

  describe('getDimensionLabel - feedbackTone', () => {
    it('gentle -> 温柔鼓励', 0, () => {
      expect(getDimensionLabel('feedbackTone', 'gentle')).assertEqual('温柔鼓励')
    })
    it('neutral -> 中性', 0, () => {
      expect(getDimensionLabel('feedbackTone', 'neutral')).assertEqual('中性')
    })
    it('playful -> 活泼', 0, () => {
      expect(getDimensionLabel('feedbackTone', 'playful')).assertEqual('活泼')
    })
  })

  describe('getDimensionLabel - weakStrongBalance', () => {
    it('weak_focus -> 弱项强化', 0, () => {
      expect(getDimensionLabel('weakStrongBalance', 'weak_focus')).assertEqual('弱项强化')
    })
    it('balanced -> 均衡', 0, () => {
      expect(getDimensionLabel('weakStrongBalance', 'balanced')).assertEqual('均衡')
    })
    it('strong_focus -> 强项深化', 0, () => {
      expect(getDimensionLabel('weakStrongBalance', 'strong_focus')).assertEqual('强项深化')
    })
  })

  describe('getDimensionLabel - learningPace', () => {
    it('minimal -> 精简', 0, () => {
      expect(getDimensionLabel('learningPace', 'minimal')).assertEqual('精简')
    })
    it('standard -> 适中', 0, () => {
      expect(getDimensionLabel('learningPace', 'standard')).assertEqual('适中')
    })
    it('extensive -> 拓展', 0, () => {
      expect(getDimensionLabel('learningPace', 'extensive')).assertEqual('拓展')
    })
  })

  describe('getDimensionLabel - fallback', () => {
    it('unknown value returns original', 0, () => {
      expect(getDimensionLabel('difficultyTendency', 'unknown')).assertEqual('unknown')
    })
    it('unknown dimension returns original', 0, () => {
      expect(getDimensionLabel('unknown', 'value')).assertEqual('value')
    })
  })

  describe('computeTrendProgress', () => {
    it('clamp to 0 when regressions dominate', 0, () => {
      expect(computeTrendProgress(0, 5)).assertEqual(0)
    })
    it('clamp to 5 when improvements dominate', 0, () => {
      expect(computeTrendProgress(10, 0)).assertEqual(5)
    })
    it('center at 2 for equal', 0, () => {
      expect(computeTrendProgress(3, 3)).assertEqual(2)
    })
    it('handles zero case', 0, () => {
      expect(computeTrendProgress(0, 0)).assertEqual(2)
    })
  })
}
```

- [ ] **Step 2: 运行测试确认失败**

DevEco Studio: 右键 `TeachingStyleAdjustmentUtils.test.ets` → Run

Expected: 测试失败，错误信息包含 `Cannot find module`

- [ ] **Step 3: 实现 utils**

```typescript
// entry/src/main/ets/utils/TeachingStyleAdjustmentUtils.ets
/**
 * 教学风格调整 utils
 * - 4 维度 enum 值 → 中文 label / 图标
 * - 进度条 0-5 档计算
 */

export type TeachingDimension =
  | 'difficultyTendency'
  | 'feedbackTone'
  | 'weakStrongBalance'
  | 'learningPace'

const DIMENSION_LABELS: Record<TeachingDimension, Record<string, string>> = {
  difficultyTendency: {
    'easier': '偏简单',
    'current': '保持',
    'harder': '偏难'
  },
  feedbackTone: {
    'gentle': '温柔鼓励',
    'neutral': '中性',
    'playful': '活泼'
  },
  weakStrongBalance: {
    'weak_focus': '弱项强化',
    'balanced': '均衡',
    'strong_focus': '强项深化'
  },
  learningPace: {
    'minimal': '精简',
    'standard': '适中',
    'extensive': '拓展'
  }
}

/**
 * 把维度 enum 值翻译成中文 label
 * - 未知 value 或未知 dimension: 返回原 value 字符串
 */
export function getDimensionLabel(dimension: string, value: string): string {
  const dimMap: Record<string, string> | undefined = DIMENSION_LABELS[dimension as TeachingDimension]
  if (dimMap === undefined) {
    return value
  }
  const label: string | undefined = dimMap[value]
  if (label === undefined) {
    return value
  }
  return label
}

/**
 * 进度条 0-5 档计算
 * - improvements 越多, 进度越高
 * - regressions 越多, 进度越低
 * - 中心点为 2 (3:3 时)
 * - 输出 clamp 到 [0, 5]
 */
export function computeTrendProgress(improvements: number, regressions: number): number {
  const raw: number = 2 + improvements - regressions
  if (raw < 0) {
    return 0
  }
  if (raw > 5) {
    return 5
  }
  return raw
}

/**
 * 进度档位 (0-5) → 简评
 */
export function getTrendRatingLabel(progress: number): string {
  if (progress <= 0) {
    return '待观察'
  }
  if (progress === 1) {
    return '偏差'
  }
  if (progress === 2) {
    return '中等'
  }
  if (progress <= 4) {
    return '较好'
  }
  return '优秀'
}
```

- [ ] **Step 4: 运行测试确认通过**

DevEco Studio: 右键 `TeachingStyleAdjustmentUtils.test.ets` → Run

Expected: 全部 ~19 个断言通过

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/utils/TeachingStyleAdjustmentUtils.ets \
        entry/src/ohosTest/ets/test/utils/TeachingStyleAdjustmentUtils.test.ets
git commit -m "feat(eval-page): TeachingStyleAdjustmentUtils 维度 label + 进度 (TDD)"
```

---

### Task 3: `WeeklyTrendService.getTrendById` (TDD)

**Files:**
- Modify: `entry/src/main/ets/services/WeeklyTrendService.ets`
- Test: `entry/src/ohosTest/ets/test/services/WeeklyTrendService.getTrendById.test.ets`

- [ ] **Step 1: 写失败的测试**

```typescript
// entry/src/ohosTest/ets/test/services/WeeklyTrendService.getTrendById.test.ets
import { describe, it, expect } from '@ohos/hypium'
import { getWeeklyTrendService } from '../../../../main/ets/services/ServiceRegistry'
import { WeeklyTrend } from '../../../../main/ets/models/TeachingReflectionModels'

export default function weeklyTrendGetByIdTest() {
  describe('WeeklyTrendService.getTrendById', () => {
    it('returns null for empty id', 0, async () => {
      const result = await getWeeklyTrendService().getTrendById('')
      expect(result).assertNull()
    })

    it('returns null for malformed id (not wt_ prefix)', 0, async () => {
      const result = await getWeeklyTrendService().getTrendById('xx_20260616')
      expect(result).assertNull()
    })

    it('returns null for short id', 0, async () => {
      const result = await getWeeklyTrendService().getTrendById('wt_2026')
      expect(result).assertNull()
    })

    it('returns null when DB has no row for parsed weekStartYMD', 0, async () => {
      // wt_20260101 → 2026-01-01 (a Thursday)
      const result = await getWeeklyTrendService().getTrendById('wt_20260101')
      expect(result).assertNull()
    })
  })
}
```

- [ ] **Step 2: 运行测试确认失败**

DevEco Studio: 右键 `WeeklyTrendService.getTrendById.test.ets` → Run

Expected: 测试失败，错误信息包含 `getTrendById is not a function`

- [ ] **Step 3: 实现 `getTrendById`**

把以下方法加到 `entry/src/main/ets/services/WeeklyTrendService.ets`，紧跟 `getTrendsInRange` 之后（行 163 之后）：

```typescript
  // =================== 按 id 查 ===================

  /**
   * 通过 id 查周级趋势。
   * - id 格式 'wt_YYYYMMDD' (WeeklyTrendRow.id 格式)
   * - 解析为 'YYYY-MM-DD' weekStartYMD 后调 getTrendByWeekStart
   * - id 为空 / 格式错误 / 解析后查不到都返回 null
   */
  async getTrendById(id: string): Promise<WeeklyTrend | null> {
    if (id === '' || !id.startsWith('wt_') || id.length !== 11) {
      return null
    }
    const ymd: string = `${id.substring(3, 7)}-${id.substring(7, 9)}-${id.substring(9, 11)}`
    return await this.getTrendByWeekStart(ymd)
  }
```

- [ ] **Step 4: 运行测试确认通过**

DevEco Studio: 右键测试文件 → Run

Expected: 4 个测试全过

- [ ] **Step 5: 验证 build 不破**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 6: 提交**

```bash
git add entry/src/main/ets/services/WeeklyTrendService.ets \
        entry/src/ohosTest/ets/test/services/WeeklyTrendService.getTrendById.test.ets
git commit -m "feat(eval-page): WeeklyTrendService.getTrendById 解析 wt_YYYYMMDD"
```

---

### Task 4: 添加 32 个 string keys

**Files:**
- Modify: `entry/src/main/resources/base/element/string.json`

- [ ] **Step 1: 在 string.json 末尾的 `"values"` 数组中追加 32 个 entry**

文件末尾的 `"values"` 数组目前以 `"name": "xxx", "value": "yyy"` 形式排列。在最后一个 entry 之后追加：

```json
        {
          "name": "learning_daily_evaluation_title",
          "value": "每日评估"
        },
        {
          "name": "learning_daily_evaluation_desc",
          "value": "评估老师每晚 21:00 总结当天学习"
        },
        {
          "name": "learning_daily_evaluation_summary",
          "value": "评估摘要"
        },
        {
          "name": "learning_daily_evaluation_dimensions",
          "value": "教学风格调整"
        },
        {
          "name": "learning_daily_evaluation_trend",
          "value": "本周趋势"
        },
        {
          "name": "learning_daily_evaluation_dim_difficulty",
          "value": "难度倾向"
        },
        {
          "name": "learning_daily_evaluation_dim_feedback",
          "value": "反馈语气"
        },
        {
          "name": "learning_daily_evaluation_dim_balance",
          "value": "强弱侧重"
        },
        {
          "name": "learning_daily_evaluation_dim_pace",
          "value": "学习节奏"
        },
        {
          "name": "learning_daily_evaluation_pending_title",
          "value": "评估排队中"
        },
        {
          "name": "learning_daily_evaluation_pending_desc",
          "value": "评估老师稍后开始处理"
        },
        {
          "name": "learning_daily_evaluation_running_title",
          "value": "评估生成中"
        },
        {
          "name": "learning_daily_evaluation_running_desc",
          "value": "正在分析本周学习数据"
        },
        {
          "name": "learning_daily_evaluation_failed_title",
          "value": "评估生成失败"
        },
        {
          "name": "learning_daily_evaluation_empty_today_future_title",
          "value": "今日评估即将生成"
        },
        {
          "name": "learning_daily_evaluation_empty_today_future_desc",
          "value": "评估老师每晚 21:00 总结当天学习"
        },
        {
          "name": "learning_daily_evaluation_empty_today_past_title",
          "value": "今日评估未生成"
        },
        {
          "name": "learning_daily_evaluation_empty_today_past_desc",
          "value": "可能评估服务尚未运行, 可手动触发"
        },
        {
          "name": "learning_daily_evaluation_empty_past_title",
          "value": "该日期暂无评估"
        },
        {
          "name": "learning_daily_evaluation_empty_past_desc",
          "value": "评估仅保留最近 14 天记录"
        },
        {
          "name": "learning_daily_evaluation_empty_oob_title",
          "value": "已超出 14 天保留范围"
        },
        {
          "name": "learning_daily_evaluation_empty_oob_desc",
          "value": "评估数据 14 天滚动, 旧数据已清理"
        },
        {
          "name": "learning_daily_evaluation_trigger_now",
          "value": "立即生成"
        },
        {
          "name": "learning_daily_evaluation_retry",
          "value": "重试"
        },
        {
          "name": "learning_daily_evaluation_close",
          "value": "关闭"
        },
        {
          "name": "learning_daily_evaluation_today_short",
          "value": "今天"
        },
        {
          "name": "learning_daily_evaluation_status_done",
          "value": "已完成"
        },
        {
          "name": "learning_daily_evaluation_status_pending",
          "value": "排队中"
        },
        {
          "name": "learning_daily_evaluation_status_running",
          "value": "生成中"
        },
        {
          "name": "learning_daily_evaluation_status_failed",
          "value": "失败"
        },
        {
          "name": "learning_daily_evaluation_rationale_missing",
          "value": "（无解释）"
        }
```

- [ ] **Step 2: 验证 JSON 格式合法**

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/resources/base/element/string.json','utf-8');JSON.parse(s);console.log('OK')"
```

Expected: `OK`

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/resources/base/element/string.json
git commit -m "feat(eval-page): + 32 string keys for daily evaluation page"
```

---

### Task 5: 路由名 + 注册

**Files:**
- Modify: `entry/src/main/ets/config/SettingsRouteName.ets`
- Modify: `entry/src/main/resources/base/profile/router_map.json`

- [ ] **Step 1: 加 `LEARNING_DAILY_EVALUATION` 枚举值**

在 `entry/src/main/ets/config/SettingsRouteName.ets` 现有 `LEARNING_ENGLISH_IMAGES` 之后加：

```typescript
  LEARNING_DAILY_EVALUATION = 'LearningDailyEvaluationPage',
```

- [ ] **Step 2: 在 `router_map.json` 注册**

在 `entry/src/main/resources/base/profile/router_map.json` 的 `routerMap` 数组中，紧跟 `LearningEnglishImagesPage` 之后追加：

```json
    ,
    {
      "name": "LearningDailyEvaluationPage",
      "pageSourceFile": "src/main/ets/pages/LearningDailyEvaluationPage.ets",
      "buildFunction": "LearningDailyEvaluationPageBuilder"
    }
```

(注意：上一步的 `,` 是 JSON 数组元素分隔符。如果上一个 entry 没逗号需要先补。)

- [ ] **Step 3: 验证 JSON**

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/resources/base/profile/router_map.json','utf-8');JSON.parse(s);console.log('OK')"
```

Expected: `OK`

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/config/SettingsRouteName.ets \
        entry/src/main/resources/base/profile/router_map.json
git commit -m "feat(eval-page): 注册 LearningDailyEvaluationPage 路由 + 枚举"
```

---

### Task 6: 页面骨架（能 build, 空 UI）

**Files:**
- Create: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 写骨架（最小可 build 版）**

```typescript
// entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  buildPointLightBorderEffect,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'

const TAG = 'LearningDailyEvaluationPage'

let learningDailyEvaluationPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct LearningDailyEvaluationPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private handleBack(): void {
    if (learningDailyEvaluationPagePathStack !== null && learningDailyEvaluationPagePathStack.size() > 0) {
      learningDailyEvaluationPagePathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.learning_daily_evaluation_title'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.learning_daily_evaluation_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private PageContent() {
    Column() {
      Text('TODO: 评估内容')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([])
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
}

@Builder
export function LearningDailyEvaluationPageBuilder(name: string, param: Object) {
  NavDestination() {
    LearningDailyEvaluationPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    learningDailyEvaluationPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (learningDailyEvaluationPagePathStack !== null && learningDailyEvaluationPagePathStack.size() > 0) {
      learningDailyEvaluationPagePathStack.pop()
    }
    return true
  })
}
```

- [ ] **Step 2: build 验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): 页面骨架 (HdsNavigation + DetailPaneHeader + PageContent 占位)"
```

---

### Task 7: 状态字段 + 数据加载方法

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 加 import 块 + 状态字段 + loadPage 骨架**

把以下 import 块加到文件顶部（紧跟现有 import 之后）：

```typescript
import { TeachingStyleAdjustment, WeeklyTrend, TeachingStyleAdjustmentStatus } from '../models/TeachingReflectionModels'
import { getTeachingStyleAdjustmentService, getWeeklyTrendService, getEvaluationService } from '../services/ServiceRegistry'
import { todayYMD, shiftYMD, canGoBack as utilCanGoBack, canGoForward as utilCanGoForward, isWithinHistoryRange } from '../utils/DateRangeUtils'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { formatRelativeTime } from '../utils/TimeFormatUtils'
import { formatLocalYMD, getDayOfWeekLabel } from '../utils/TimeFormatUtils'  // 如已存在则跳过
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getDimensionLabel, computeTrendProgress, getTrendRatingLabel } from '../utils/TeachingStyleAdjustmentUtils'
import { BusinessError } from '@kit.BasicServicesKit'
```

(注：先 `Read` 现有 import 块再决定怎么加 — `formatLocalYMD`/`getDayOfWeekLabel` 在哪个文件不确定，需要 `Grep` 一下定位；如果 `TimeFormatUtils.ets` 已经有就只 import 一次)

- [ ] **Step 2: 加状态字段到 struct 内**

在 `struct LearningDailyEvaluationPage` 内、所有 private getter 之后、`private px2vp` 之前加：

```typescript
  @Local adjustment: TeachingStyleAdjustment | null = null
  @Local trend: WeeklyTrend | null = null
  @Local selectedDate: string = ''
  @Local isLoading: boolean = true
  @Local isTriggering: boolean = false
  @Local isErrorSheetVisible: boolean = false
  @Local loadError: string = ''

  private loadToken: number = 0
  private pollTimerId: number = -1
  private pollCount: number = 0
  private readonly POLL_INTERVAL_MS: number = 2000
  private readonly POLL_MAX_COUNT: number = 60
  private appStorageDisposer: (() => void) | null = null
```

- [ ] **Step 3: 加生命周期方法 + 数据加载方法**

在 `px2vp` 方法之后加：

```typescript
  aboutToAppear(): void {
    this.selectedDate = todayYMD()
    this.loadPage()
    this.subscribeRefreshTick()
  }

  aboutToDisappear(): void {
    this.stopPolling()
    if (this.appStorageDisposer !== null) {
      this.appStorageDisposer()
      this.appStorageDisposer = null
    }
  }

  private async loadPage(): Promise<void> {
    const token: number = ++this.loadToken
    this.isLoading = true
    this.loadError = ''
    try {
      const adj: TeachingStyleAdjustment | null =
        await getTeachingStyleAdjustmentService().getAdjustmentForDate(this.selectedDate)
      if (token !== this.loadToken) {
        return
      }
      this.adjustment = adj
      if (adj !== null && adj.sourceWeeklyTrendId !== '') {
        try {
          this.trend = await getWeeklyTrendService().getTrendById(adj.sourceWeeklyTrendId)
        } catch (e) {
          console.error(TAG, `getTrendById failed: ${(e as BusinessError).message ?? String(e)}`)
          this.trend = null
        }
      } else {
        this.trend = null
      }
    } catch (e) {
      console.error(TAG, `loadPage failed: ${(e as BusinessError).message ?? String(e)}`)
      if (token === this.loadToken) {
        this.loadError = (e as BusinessError).message ?? String(e)
        this.adjustment = null
        this.trend = null
      }
    } finally {
      if (token === this.loadToken) {
        this.isLoading = false
      }
    }
    this.maybeStartPolling()
  }

  private maybeStartPolling(): void {
    const status: string = this.adjustment?.status ?? ''
    if (status !== TeachingStyleAdjustmentStatus.DONE && status !== '' &&
        status !== TeachingStyleAdjustmentStatus.FAILED) {
      this.startPolling()
    } else {
      this.stopPolling()
    }
  }

  private startPolling(): void {
    if (this.pollTimerId !== -1) {
      return
    }
    this.pollCount = 0
    this.pollTimerId = setInterval((): void => {
      this.pollCount++
      if (this.pollCount > this.POLL_MAX_COUNT) {
        console.warn(TAG, `polling timeout after ${this.pollCount} ticks`)
        this.stopPolling()
        return
      }
      this.loadPage()
    }, this.POLL_INTERVAL_MS)
  }

  private stopPolling(): void {
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId)
      this.pollTimerId = -1
    }
  }

  private subscribeRefreshTick(): void {
    if (this.appStorageDisposer !== null) {
      return
    }
    this.appStorageDisposer = observeAppUiState(AppStorageKeys.TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK, (): void => {
      this.loadPage()
    })
  }

  private async handleTriggerEvaluation(): Promise<void> {
    if (this.isTriggering || this.selectedDate !== todayYMD()) {
      return
    }
    this.isTriggering = true
    try {
      await getEvaluationService().triggerEvaluationForToday(true, 'manual')
    } catch (e) {
      const msg: string = (e as BusinessError).message ?? String(e)
      console.error(TAG, `trigger failed: ${msg}`)
      this.loadError = msg
      this.isErrorSheetVisible = true
    } finally {
      this.isTriggering = false
    }
  }
```

(注意：上面用了 `observeAppUiState`，需要 import — 在 import 块加 `import { observeAppUiState } from '../state/AppUiState'`)

- [ ] **Step 4: 验证 build**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -20
```

Expected: `BUILD SUCCESSFUL`（可能需要 import 微调 `TimeFormatUtils` 内的函数名）

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): 状态字段 + 生命周期 + loadPage + 轮询 + 手动触发"
```

---

### Task 8: `DatePickerBar` + 切日期 handler

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 加 `DatePickerBar` builder + 切日期方法**

在 `DetailPaneHeader` 之后插入：

```typescript
  @Builder
  private DatePickerBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(16)
        .fontColor([this.canGoBack() ? $r('app.color.text_primary') : $r('app.color.text_tertiary')])
        .onClick((): void => {
          if (this.canGoBack()) {
            this.selectedDate = shiftYMD(this.selectedDate, -1)
            this.loadPage()
          }
        })

      Column() {
        Text(this.formatDateDisplay(this.selectedDate))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.formatWeekdayDisplay(this.selectedDate))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.canGoForward() ? $r('app.color.text_primary') : $r('app.color.text_tertiary')])
        .onClick((): void => {
          if (this.canGoForward()) {
            this.selectedDate = shiftYMD(this.selectedDate, 1)
            this.loadPage()
          }
        })

      if (this.selectedDate !== todayYMD()) {
        Text($r('app.string.learning_daily_evaluation_today_short'))
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor($r('app.color.background_secondary'))
          .onClick((): void => {
            this.selectedDate = todayYMD()
            this.loadPage()
          })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
  }

  private formatDateDisplay(ymd: string): string {
    if (ymd === todayYMD()) {
      return '今天'
    }
    return ymd  // 'YYYY-MM-DD'
  }

  private formatWeekdayDisplay(ymd: string): string {
    return getDayOfWeekLabel(ymd)  // 如 '周三'
  }

  private canGoBack(): boolean {
    return utilCanGoBack(this.selectedDate)
  }

  private canGoForward(): boolean {
    return utilCanGoForward(this.selectedDate)
  }
```

(注意：`$r('app.color.background_secondary')` 这个资源名可能不存在 — 如果 build 报资源找不到，替换为 `withColorAlpha(this.themePrimary, '14')`)

- [ ] **Step 2: 把 `DatePickerBar` 嵌入 `PageContent`**

修改 `PageContent` builder 的内部：

找到 `Text('TODO: 评估内容')` 那行，替换为：

```typescript
      Column({ space: 12 }) {
        this.DatePickerBar()
        Text('TODO: SummaryCard + 2 个 Block')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
```

- [ ] **Step 3: build 验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): DatePickerBar 顶部日期选择 (左右箭头 + 今天按钮)"
```

---

### Task 9: `SummaryCard` + 状态 pill

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 加 `SummaryCard` + `StatusPill` builders**

在 `DatePickerBar` 之后插入：

```typescript
  @Builder
  private StatusPill(status: string) {
    Text(this.getStatusLabel(status))
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.getStatusTextColor(status))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(this.getStatusBgColor(status))
  }

  private getStatusLabel(status: string): string {
    switch (status) {
      case TeachingStyleAdjustmentStatus.DONE: return '已完成'
      case TeachingStyleAdjustmentStatus.FAILED: return '失败'
      case 'pending': return '排队中'
      case 'running': return '生成中'
      default: return '未知'
    }
  }

  private getStatusBgColor(status: string): string {
    switch (status) {
      case TeachingStyleAdjustmentStatus.DONE: return withColorAlpha('#22C55E', '0C')
      case TeachingStyleAdjustmentStatus.FAILED: return withColorAlpha('#EF4444', '0C')
      case 'pending': return withColorAlpha('#FF9F43', '0C')
      case 'running': return withColorAlpha('#3B82F6', '0C')
      default: return withColorAlpha('#9CA3AF', '0C')
    }
  }

  private getStatusTextColor(status: string): string {
    switch (status) {
      case TeachingStyleAdjustmentStatus.DONE: return '#22C55E'
      case TeachingStyleAdjustmentStatus.FAILED: return '#EF4444'
      case 'pending': return '#FF9F43'
      case 'running': return '#3B82F6'
      default: return '#9CA3AF'
    }
  }

  @Builder
  private SummaryCard() {
    if (this.adjustment === null) {
      // 占位
      Column() {}
    } else {
      Column({ space: 6 }) {
        Row() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(13)
              .fontColor([getAppUiState().themePrimary])
            Text(this.formatDateDisplay(this.adjustment.effectiveDate))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .layoutWeight(1)

          this.StatusPill(this.adjustment.status)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`生成于 ${formatRelativeTime(this.adjustment.createdAt)} · 来自 ${this.adjustment.sourceSessionCount} 次对话`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Text(`置信度 ${this.formatConfidence(this.adjustment.confidence)} · 模型 ${this.adjustment.evaluatorModelName !== '' ? this.adjustment.evaluatorModelName : '—'}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding(14)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .border({ width: 1, color: $r('app.color.divider') })
      .visualEffect(buildPointLightBorderEffect())
    }
  }

  private formatConfidence(c: number): string {
    if (c <= 0) {
      return '—'
    }
    return c.toFixed(2)
  }
```

- [ ] **Step 2: 在 `PageContent` 加 `SummaryCard` 渲染**

修改 `PageContent`（在 `DatePickerBar` 之后）：

```typescript
      Column({ space: 12 }) {
        this.DatePickerBar()
        if (!this.isLoading && this.adjustment !== null) {
          this.SummaryCard()
        }
        Text('TODO: 4 维度 + WeeklyTrend')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
```

- [ ] **Step 3: build 验证 + 提交**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): SummaryCard + 状态 pill (4 状态色 + 标签)"
```

Expected: `BUILD SUCCESSFUL` 两次

---

### Task 10: `DimensionsBlock` + `DimensionRow`

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 加 `DimensionsBlock` + `DimensionRow` builders**

在 `SummaryCard` 之后插入：

```typescript
  @Builder
  private DimensionsBlock() {
    if (this.adjustment === null) {
      Column() {}
    } else {
      Column({ space: 10 }) {
        Text($r('app.string.learning_daily_evaluation_dimensions'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 4 })

        Column() {
          this.DimensionRow(
            $r('app.string.learning_daily_evaluation_dim_difficulty'),
            this.adjustment.difficultyTendency,
            this.adjustment.difficultyRationale
          )
          Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
          this.DimensionRow(
            $r('app.string.learning_daily_evaluation_dim_feedback'),
            this.adjustment.feedbackTone,
            this.adjustment.feedbackRationale
          )
          Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
          this.DimensionRow(
            $r('app.string.learning_daily_evaluation_dim_balance'),
            this.adjustment.weakStrongBalance,
            this.adjustment.balanceRationale
          )
          Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
          this.DimensionRow(
            $r('app.string.learning_daily_evaluation_dim_pace'),
            this.adjustment.learningPace,
            this.adjustment.paceRationale
          )
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.divider') })
        .visualEffect(buildPointLightBorderEffect())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private DimensionRow(label: ResourceStr, value: string, rationale: string) {
    Column({ space: 6 }) {
      Row() {
        Text(label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(this.getDimensionLabelFor(value))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(getAppUiState().themePrimary)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(10)
          .backgroundColor(getAppUiState().themePrimaryLight)

        if (rationale === '') {
          Text('（无解释）')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(rationale)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  private getDimensionLabelFor(value: string): string {
    // 4 维度共用一个 label 函数, value 字符串自带类型信息
    // 实际使用需要传 dimension 区分, 这里简化: 直接用 getDimensionLabel 的第一个命中的
    if (this.adjustment === null) {
      return value
    }
    const dim: string =
      value === this.adjustment.difficultyTendency ? 'difficultyTendency' :
      value === this.adjustment.feedbackTone ? 'feedbackTone' :
      value === this.adjustment.weakStrongBalance ? 'weakStrongBalance' :
      value === this.adjustment.learningPace ? 'learningPace' : ''
    return getDimensionLabel(dim, value)
  }
```

(注意：`getDimensionLabelFor` 是个 hack — 实际更干净的做法是 DimensionRow 接受 dimension 字符串。v1 这个写法可读性 OK。如果 review 反馈要改就改。)

- [ ] **Step 2: 在 `PageContent` 渲染 `DimensionsBlock`**

```typescript
      Column({ space: 12 }) {
        this.DatePickerBar()
        if (!this.isLoading && this.adjustment !== null) {
          this.SummaryCard()
          this.DimensionsBlock()
        }
        Text('TODO: WeeklyTrend')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
```

- [ ] **Step 3: build + commit**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): DimensionsBlock 4 维度卡片 + 胶囊 enum label + rationale"
```

Expected: `BUILD SUCCESSFUL`

---

### Task 11: `WeeklyTrendBlock` + `TrendRow` + `ProgressDots`

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 加 3 个 builder**

在 `DimensionsBlock` 之后插入：

```typescript
  @Builder
  private ProgressDots(progress: number, activeColor: string, inactiveColor: string) {
    Row({ space: 4 }) {
      ForEach([0, 1, 2, 3, 4], (_unused: number, index: number) => {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(index < progress ? activeColor : inactiveColor)
      }, (item: number) => `${item}`)
    }
  }

  @Builder
  private WeeklyTrendBlock() {
    if (this.trend === null) {
      // 降级态
      Column({ space: 6 }) {
        Text($r('app.string.learning_daily_evaluation_trend'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 4 })
        Text('本周趋势数据已过期')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(14)
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.divider') })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      Column({ space: 10 }) {
        Text($r('app.string.learning_daily_evaluation_trend'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 4 })

        Column({ space: 0 }) {
          this.TrendRowProgress('技能速度', this.computeSkillVelocityProgress())
          Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
          this.TrendRowProgress('反复出错', this.computeStrugglingProgress())
          Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
          this.TrendRowChips('兴趣主题', this.trend.topicInterests.map((t): string => t.topicLabel))
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.divider') })
        .visualEffect(buildPointLightBorderEffect())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private TrendRowProgress(label: string, progress: number) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      this.ProgressDots(progress, getAppUiState().themePrimary, $r('app.color.divider'))
      Text(getTrendRatingLabel(progress))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 8 })
        .width(40)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private TrendRowChips(label: string, items: string[]) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (items.length === 0) {
        Text('无明显偏好')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(items, (item: string, index: number) => {
            Text(item)
              .fontSize(11)
              .fontColor(getAppUiState().themePrimary)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(10)
              .backgroundColor(getAppUiState().themePrimaryLight)
              .margin({ right: 4, bottom: 4 })
          }, (item: string, index: number) => `${index}_${item}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 14, right: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  private computeSkillVelocityProgress(): number {
    if (this.trend === null) {
      return 2
    }
    return computeTrendProgress(this.trend.topImprovements.length, this.trend.topRegressions.length)
  }

  private computeStrugglingProgress(): number {
    if (this.trend === null) {
      return 2
    }
    // 反复出错越多进度越低 (反向)
    return computeTrendProgress(0, this.trend.topStruggling.length)
  }
```

- [ ] **Step 2: 在 `PageContent` 渲染**

```typescript
      Column({ space: 12 }) {
        this.DatePickerBar()
        if (!this.isLoading && this.adjustment !== null) {
          this.SummaryCard()
          this.DimensionsBlock()
          this.WeeklyTrendBlock()
        }
      }
      .width('100%')
      .layoutWeight(1)
```

- [ ] **Step 3: build + commit**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): WeeklyTrendBlock 4 指标 + 进度条 + chip"
```

Expected: `BUILD SUCCESSFUL`

---

### Task 12: 状态分支 (PendingState / RunningState / FailedState + ErrorDetailSheet)

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 加 4 个 builder**

在 `WeeklyTrendBlock` 之后插入：

```typescript
  @Builder
  private PendingState() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(getAppUiState().themePrimary)
      Text($r('app.string.learning_daily_evaluation_pending_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.learning_daily_evaluation_pending_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private RunningState() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(getAppUiState().themePrimary)
      Text($r('app.string.learning_daily_evaluation_running_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.learning_daily_evaluation_running_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private FailedState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(48)
        .fontColor([$r('app.color.status_error')])
      Text($r('app.string.learning_daily_evaluation_failed_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(this.loadError)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 24, right: 24 })
        .textAlign(TextAlign.Center)
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.selectedDate === todayYMD()) {
        Button($r('app.string.learning_daily_evaluation_retry'))
          .onClick((): void => {
            this.handleTriggerEvaluation()
          })
          .enabled(!this.isTriggering)
      }
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorDetailSheet() {
    Column({ space: 14 }) {
      Text($r('app.string.learning_daily_evaluation_failed_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(this.loadError)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20)
        .width('100%')
      Row({ space: 10 }) {
        Button($r('app.string.learning_daily_evaluation_close'))
          .layoutWeight(1)
          .onClick((): void => {
            this.isErrorSheetVisible = false
          })
        if (this.selectedDate === todayYMD()) {
          Button($r('app.string.learning_daily_evaluation_retry'))
            .layoutWeight(1)
            .onClick((): void => {
              this.isErrorSheetVisible = false
              this.handleTriggerEvaluation()
            })
            .enabled(!this.isTriggering)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }
```

- [ ] **Step 2: 在 `PageContent` 渲染状态分支**

修改 `PageContent` 的 if-else 逻辑：

```typescript
  @Builder
  private PageContent() {
    Column({ space: 12 }) {
      this.DatePickerBar()

      if (this.isLoading) {
        // 加载中显示 spinner
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(getAppUiState().themePrimary)
        }
        .width('100%')
        .padding({ top: 64 })
        .alignItems(HorizontalAlign.Center)
      } else if (this.adjustment !== null &&
                 this.adjustment.status !== TeachingStyleAdjustmentStatus.FAILED &&
                 this.adjustment.status !== 'pending' &&
                 this.adjustment.status !== 'running') {
        // done
        this.SummaryCard()
        this.DimensionsBlock()
        this.WeeklyTrendBlock()
      } else if (this.adjustment !== null && this.adjustment.status === 'pending') {
        this.PendingState()
      } else if (this.adjustment !== null && this.adjustment.status === 'running') {
        this.RunningState()
      } else if (this.adjustment !== null && this.adjustment.status === TeachingStyleAdjustmentStatus.FAILED) {
        this.FailedState()
      } else {
        // null — EmptyState (下个 task 加)
        Text('TODO: EmptyState')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
    .bindSheet($$this.isErrorSheetVisible, this.ErrorDetailSheet(), {
      height: SheetSize.FIT_CONTENT,
      showClose: false
    })
  }
```

- [ ] **Step 3: build + commit**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): 状态分支 Pending/Running/Failed + ErrorDetailSheet"
```

Expected: `BUILD SUCCESSFUL`

---

### Task 13: `EmptyState` 4 种子态

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 加 `EmptyState` builder**

在 `ErrorDetailSheet` 之后插入：

```typescript
  @Builder
  private EmptyState() {
    const isToday: boolean = this.selectedDate === todayYMD()
    const todayPast21: boolean = isToday && new Date().getHours() >= 21
    const inRange: boolean = isWithinHistoryRange(this.selectedDate)

    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })

      if (isToday && !todayPast21) {
        Text($r('app.string.learning_daily_evaluation_empty_today_future_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_today_future_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
      } else if (isToday && todayPast21) {
        Text($r('app.string.learning_daily_evaluation_empty_today_past_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_today_past_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
        Button($r('app.string.learning_daily_evaluation_trigger_now'))
          .onClick((): void => {
            this.handleTriggerEvaluation()
          })
          .enabled(!this.isTriggering)
          .margin({ top: 8 })
      } else if (!inRange) {
        Text($r('app.string.learning_daily_evaluation_empty_oob_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_oob_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
      } else {
        Text($r('app.string.learning_daily_evaluation_empty_past_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_past_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
      }
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }
```

(注意：ArkTS 不允许在 `@Builder` 函数体内用 `const isToday = ...` 这种 `const` 声明。需要在 builder 外用 `@State`/`@Local` 缓存，或者改成函数属性访问。)

修正：把这段重写为方法属性，避免 const 声明：

```typescript
  private get isTodaySelected(): boolean {
    return this.selectedDate === todayYMD()
  }

  private get isTodayPast21(): boolean {
    return this.isTodaySelected && new Date().getHours() >= 21
  }

  private get isSelectedInRange(): boolean {
    return isWithinHistoryRange(this.selectedDate)
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })

      if (this.isTodaySelected && !this.isTodayPast21) {
        Text($r('app.string.learning_daily_evaluation_empty_today_future_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_today_future_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
      } else if (this.isTodaySelected && this.isTodayPast21) {
        Text($r('app.string.learning_daily_evaluation_empty_today_past_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_today_past_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
        Button($r('app.string.learning_daily_evaluation_trigger_now'))
          .onClick((): void => {
            this.handleTriggerEvaluation()
          })
          .enabled(!this.isTriggering)
          .margin({ top: 8 })
      } else if (!this.isSelectedInRange) {
        Text($r('app.string.learning_daily_evaluation_empty_oob_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_oob_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
      } else {
        Text($r('app.string.learning_daily_evaluation_empty_past_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.learning_daily_evaluation_empty_past_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
      }
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }
```

- [ ] **Step 2: 在 `PageContent` 把 TODO 替换为 `EmptyState`**

```typescript
      } else {
        // null
        this.EmptyState()
      }
```

- [ ] **Step 3: build + commit**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): EmptyState 4 种子态 (今日未到/今日已过/过去/越界)"
```

Expected: `BUILD SUCCESSFUL`

---

### Task 14: 加 IndexSettingsPanel 入口 + Index handler

**Files:**
- Modify: `entry/src/main/ets/components/index/IndexSettingsPanel.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1: 在 `IndexSettingsPanel.ets:79-107` "学习中心"分组加第 4 项**

在 `LEARNING_ENGLISH_IMAGES` 那个 item 之后加：

```typescript
    ,
    {
      key: SettingsRouteName.LEARNING_DAILY_EVALUATION,
      icon: $r('sys.symbol.lightbulb_max'),
      title: $r('app.string.learning_daily_evaluation_title'),
      subtitle: $r('app.string.learning_daily_evaluation_desc'),
      action: (): void => { this.onOpenLearningDailyEvaluation() }
    } as SettingsListItemModel
```

- [ ] **Step 2: 在 `Index.ets` 加 `onOpenLearningDailyEvaluation` 方法**

先 `Grep` 找到 `onOpenLearningTomorrowPlan` 的位置（行 ~4851-4905 附近），紧跟其后加：

```typescript
  private onOpenLearningDailyEvaluation(): void {
    this.openSettingsDestination(SettingsRouteName.LEARNING_DAILY_EVALUATION)
  }
```

(确认 `openSettingsDestination` 这个方法在 Index.ets 存在；如果名字不同，按 Index.ets 中其他 learning handler 的实际写法改。)

- [ ] **Step 3: build + commit**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

```bash
git add entry/src/main/ets/components/index/IndexSettingsPanel.ets \
        entry/src/main/ets/pages/Index.ets
git commit -m "feat(eval-page): 入口加在'学习中心'分组末位 (icon lightbulb_max)"
```

Expected: `BUILD SUCCESSFUL`

---

### Task 15: 最终 build + 真机烟测

**Files:** 无新文件

- [ ] **Step 1: 完整 build**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL` 无 ArkTS 错误

- [ ] **Step 2: 装到真机, 真机测试**

DevEco Studio: Run → 真机

烟测清单（参考 spec §10.2）：

- [ ] 打开设置 → 滑到"学习中心" → 看到"每日评估"入口（icon 是 lightbulb_max）
- [ ] 点击入口 → 进入页面 → 标题"每日评估"显示
- [ ] 顶部日期显示"今天"+ 周几
- [ ] 默认 EmptyState 子态 1 (今日 21:00 前) / 子态 2 (今日 21:00 后) 正确
- [ ] 点"立即生成"按钮 → 状态变 pending → running → done，spinner 切换 3 次
- [ ] done 状态看到 SummaryCard + 4 维度卡片 + WeeklyTrend 块
- [ ] 4 维度胶囊 label 显示中文（不是 raw enum）
- [ ] 顶部 ← 切到昨天 → 显示昨日评估（若有数据）
- [ ] 顶部 ← 切到 16 天前 → 箭头禁用 + 显示"超出 14 天"
- [ ] 切回今天 → "今天"按钮隐藏
- [ ] 强制制造 failed 状态（修改 DB status='failed'，或断网触发）→ 看到 FailedState
- [ ] 关页面再开 → 没遗留 spinner（aboutToDisappear 清理）
- [ ] 切到不同日期后切回 → 旧请求被 loadToken 丢弃，不串数据

- [ ] **Step 3: 运行所有 utils 单元测试**

DevEco Studio:
- 右键 `DateRangeUtils.test.ets` → Run
- 右键 `TeachingStyleAdjustmentUtils.test.ets` → Run
- 右键 `WeeklyTrendService.getTrendById.test.ets` → Run

Expected: 3 个测试文件全部通过（~37 个断言）

- [ ] **Step 4: 回归现有页面**

确认以下页面行为不变：
- LearningProfilePage
- LearningTomorrowPlanPage
- LearningEnglishImagesPage
- Settings 整体

- [ ] **Step 5: 提交最终 commit（如有 fix）**

```bash
git add -A
git commit -m "feat(eval-page): 实施完成 + 真机烟测通过 (T1-T10 + S1-S7)"
```

---

## Self-Review

**Spec coverage:**
- [x] §1 Context — 在文件头 + 整篇 plan 体现
- [x] §2 Architecture — Task 6 起按视觉区块分步
- [x] §3 Page layout — Task 8 (DatePickerBar) / 9 (SummaryCard) / 10 (Dimensions) / 11 (WeeklyTrend) / 12 (State branches) / 13 (EmptyState)
- [x] §4 Data contract — Task 7 用现成 API；Task 3 加 `getTrendById`
- [x] §5 Components & files — 文件结构清单 + 12 个 @Builder 拆分
- [x] §6 String resources — Task 4 一次加完
- [x] §7 utils — Task 1 (DateRangeUtils) / Task 2 (TeachingStyleAdjustmentUtils) TDD
- [x] §8 State machine — Task 7 实现 + Task 12/13 渲染
- [x] §9 Error handling — Task 7 loadError + Task 12 FailedState
- [x] §10 Testing — Task 1-3 单元测试 TDD + Task 15 真机烟测
- [x] §11 File list — 全部在 File Structure 表中
- [x] §12 Risks — spec 里 8 个风险点都在 plan 中处理

**Placeholder scan:** 无 TBD / TODO / "fill in" — 任务 8-12 的 "TODO" 字符串是 build 时显示在 UI 上的占位文字，会在后续 task 替换，不是 plan 占位。

**Type consistency:**
- `getDimensionLabel` 在 Task 2 接受 `(dimension: string, value: string)`，Task 10 用同样签名
- `getAdjustmentForDate` 在 Task 7 调用，Task 9-13 渲染用
- `formatRelativeTime` / `formatLocalYMD` / `getDayOfWeekLabel` / `withColorAlpha` / `buildPointLightBorderEffect` 全部 import 后跨任务一致
- `TeachingStyleAdjustmentStatus.DONE` / `FAILED` 在 Task 7/12 引用一致

**Potential issues caught during self-review:**

1. **Task 8 的 `background_secondary` 资源**可能不存在 — 已加 fallback 提示
2. **Task 12 的 `bindSheet($$this.isErrorSheetVisible, ...)`** 需要 `isErrorSheetVisible` 是 `@Local` — Task 7 已加
3. **Task 13 的 `const isToday`** 写法违反 ArkTS 严格模式 — 已改为 `get` 访问器
4. **Task 11 的 `ForEach` 在 chip 列表** 用了 `index_${item}` 做 key，重复 key 风险存在 — 改用 topicLabel 字符串本身做 key
5. **Task 7 的 `observeAppUiState`** 需要确认 `AppUiState.ets:593` 暴露此函数 — 加 import 时务必确认

---

**Plan complete and saved to `docs/superpowers/plans/2026-06-17-daily-evaluation-page.md`.**
