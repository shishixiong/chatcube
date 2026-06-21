# 每日评估页 — 展示上次完成的评估 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `LearningDailyEvaluationPage` 今日态下方追加"上次评估" section, 仅在今日未完成时显示, 点击头部可跳转到该日期。

**Architecture:** 复用 `TeachingStyleAdjustmentService.getCurrentAdjustment(yesterday, now)` 已有查询, 0 改动 service 层; 在 page 内新增 3 个 `@Local` 字段 + 1 个 `loadLastCompleted` 方法; 改造 3 个现有 builder 为参数化以支持复用渲染; 新增 `LastCompletedSection` + `LastCompletedHeader` 两个 builder。

**Tech Stack:** HarmonyOS ArkTS strict mode, `@ObservedV2` + `@Local`, `AppStorageV2`, hypium + hamock for unit tests.

---

## File Structure

### Modify (3 files)

| Path | Change |
|------|--------|
| `entry/src/main/ets/utils/DateRangeUtils.ets` | + `daysBetween(fromYMD, toYMD): number` (~7 行, 复用现有 `ymdToMs` + `MS_PER_DAY`) |
| `entry/src/main/resources/base/element/string.json` | + 2 个 string key (`learning_daily_evaluation_last_completed_title` / `_subtitle_format`) |
| `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets` | + 3 个 @Local + 1 token + 1 谓词 + 1 loadLastCompleted + 1 clearLastCompleted + 2 新 builder + 3 builder 参数化 + 1 处 import |

### Test (1 file, modify existing)

| Path | Change |
|------|--------|
| `entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets` | + 1 个 describe 块 (`daysBetween` 9 个 case, 复用现有 `NOW_MS`/`TODAY` 常量) |

### Not Modified

- `services/TeachingStyleAdjustmentService.ets` (复用 `getCurrentAdjustment`)
- `services/WeeklyTrendService.ets` (复用 `getTrendById`)
- `services/DatabaseService.ets` (无新查询)
- `config/AppStorageKeys.ets` (无新 key)
- `router_map.json` / `SettingsRouteName.ets` (无新路由)

---

## Task 1: 新增 `daysBetween` 工具函数 (TDD)

**Files:**
- Modify: `entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets`
- Modify: `entry/src/main/ets/utils/DateRangeUtils.ets`

- [ ] **Step 1: 在 DateRangeUtils.test.ets 末尾添加 9 个 `daysBetween` 测试 case**

在 `describe('shiftYMD', ...)` 之后追加:

```typescript
import { describe, it, expect } from '@ohos/hypium'
import {
  isWithinHistoryRange,
  canGoBack,
  canGoForward,
  todayYMD,
  shiftYMD,
  daysBetween
} from '../../../../main/ets/utils/DateRangeUtils'

// ... 现有 NOW_MS / TODAY 常量保持不变

export default function dateRangeUtilsTest() {
  // ... 现有 describe 块保持不变

  describe('daysBetween', () => {
    it('returns 0 for the same day', 0, () => {
      expect(daysBetween(TODAY, TODAY)).assertEqual(0)
    })
    it('returns 1 for adjacent days', 0, () => {
      expect(daysBetween('2026-06-16', TODAY)).assertEqual(1)
    })
    it('returns 14 for 14-day boundary', 0, () => {
      expect(daysBetween('2026-06-03', TODAY)).assertEqual(14)
    })
    it('crosses month boundary', 0, () => {
      expect(daysBetween('2026-05-31', '2026-06-02')).assertEqual(2)
    })
    it('crosses year boundary', 0, () => {
      expect(daysBetween('2025-12-31', '2026-01-01')).assertEqual(1)
    })
    it('returns negative for reverse order', 0, () => {
      expect(daysBetween(TODAY, '2026-06-16')).assertEqual(-1)
    })
    it('returns 0 for empty fromYMD', 0, () => {
      expect(daysBetween('', TODAY)).assertEqual(0)
    })
    it('returns 0 for invalid format', 0, () => {
      expect(daysBetween('invalid', TODAY)).assertEqual(0)
    })
    it('returns 0 for invalid toYMD', 0, () => {
      expect(daysBetween(TODAY, 'bad')).assertEqual(0)
    })
  })
}
```

- [ ] **Step 2: 在 DevEco Studio 中运行测试, 确认 fail**

- 在 IDE 中右键 `DateRangeUtils.test.ets` → Run 'hypium test'
- 期望: `daysBetween` 相关 9 个 case **全部 fail**, 错误信息含 `daysBetween` 未定义

- [ ] **Step 3: 在 DateRangeUtils.ets 末尾添加 `daysBetween` 实现**

在 `shiftYMD` 函数 (行 71-77) 之后追加:

```typescript
/**
 * 计算两个 YMD 日期相差的天数 (toYMD - fromYMD)
 * - 同日: 0
 * - 反向: 负数
 * - 任意一端为空或格式错误: 0
 * - 跨月/跨年正确处理 (走 Date 构造 + epoch ms)
 */
export function daysBetween(fromYMD: string, toYMD: string): number {
  if (fromYMD === '' || toYMD === '') {
    return 0
  }
  const fromMs: number = ymdToMs(fromYMD)
  const toMs: number = ymdToMs(toYMD)
  if (isNaN(fromMs) || isNaN(toMs)) {
    return 0
  }
  return Math.round((toMs - fromMs) / MS_PER_DAY)
}
```

- [ ] **Step 4: 重跑测试, 确认 pass**

- 右键 `DateRangeUtils.test.ets` → Run 'hypium test'
- 期望: `daysBetween` 9 个 case **全部 pass**, 现有 18 个 case 仍 pass (总数 27)

- [ ] **Step 5: 提交**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/utils/DateRangeUtils.ets entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets
git commit -m "feat(eval-page): 新增 daysBetween 工具 + 9 个 hypium 测试"
```

---

## Task 2: 新增 2 个 string 资源

**Files:**
- Modify: `entry/src/main/resources/base/element/string.json`

- [ ] **Step 1: 在 string.json 末尾 (line 3718 之前) 追加 2 个 key**

找到 `"learning_daily_evaluation_failed_no_detail"` 块, 在其 `}` 之后 (即 line 3717 后), `]` 之前插入:

```json
    {
      "name": "learning_daily_evaluation_last_completed_title",
      "value": "上次评估"
    },
    {
      "name": "learning_daily_evaluation_last_completed_subtitle_format",
      "value": "距今 %d 天"
    }
```

- [ ] **Step 2: 验证 JSON 合法**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "const j = JSON.parse(require('fs').readFileSync('entry/src/main/resources/base/element/string.json', 'utf-8')); const arr = j.string || j; const found = arr.filter(s => s.name && s.name.startsWith('learning_daily_evaluation_last_completed')); console.log(JSON.stringify(found, null, 2))"
```

期望输出: 包含 2 个对象的 JSON, 名称分别为 `_title` 和 `_subtitle_format`

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/resources/base/element/string.json
git commit -m "feat(eval-page): 新增 last_completed section 用的 2 个 string key"
```

---

## Task 3: 重构 3 个现有 builder 为参数化

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 重构 `SummaryCard()` 接受 `adj: TeachingStyleAdjustment` 形参**

定位: `pages/LearningDailyEvaluationPage.ets` 行 383-423 (SummaryCard builder)

将:
```typescript
@Builder
private SummaryCard() {
  if (this.adjustment === null) {
    Column() {}
  } else {
    Column({ space: 6 }) {
      Row() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(13)
            .fontColor([this.themePrimary])
          Text(this.formatDateDisplay(this.adjustment.effectiveDate))
            ...
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
```

替换为:
```typescript
@Builder
private SummaryCard(adj: TeachingStyleAdjustment) {
  Column({ space: 6 }) {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(13)
          .fontColor([this.themePrimary])
        Text(this.formatDateDisplay(adj.effectiveDate))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .layoutWeight(1)

      this.StatusPill(adj.status)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    Text(`生成于 ${formatRelativeTime(adj.createdAt)} · 来自 ${adj.sourceSessionCount} 次对话`)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))

    Text(`置信度 ${this.formatConfidence(adj.confidence)} · 模型 ${adj.evaluatorModelName !== '' ? adj.evaluatorModelName : '—'}`)
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
```

- [ ] **Step 2: 重构 `DimensionsBlock()` 接受 `adj: TeachingStyleAdjustment` 形参**

定位: 行 425-476 (DimensionsBlock builder)

将:
```typescript
@Builder
private DimensionsBlock() {
  if (this.adjustment === null) {
    Column() {}
  } else {
    Column({ space: 10 }) {
      Text($r('app.string.learning_daily_evaluation_dimensions'))
        ...
      Column() {
        this.DimensionRow(
          $r('app.string.learning_daily_evaluation_dim_difficulty'),
          'difficultyTendency',
          this.adjustment.difficultyTendency,
          this.adjustment.difficultyRationale
        )
        Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
        this.DimensionRow(
          $r('app.string.learning_daily_evaluation_dim_feedback'),
          'feedbackTone',
          this.adjustment.feedbackTone,
          this.adjustment.feedbackRationale
        )
        Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
        this.DimensionRow(
          $r('app.string.learning_daily_evaluation_dim_balance'),
          'weakStrongBalance',
          this.adjustment.weakStrongBalance,
          this.adjustment.balanceRationale
        )
        Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
        this.DimensionRow(
          $r('app.string.learning_daily_evaluation_dim_pace'),
          'learningPace',
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
```

替换为:
```typescript
@Builder
private DimensionsBlock(adj: TeachingStyleAdjustment) {
  Column({ space: 10 }) {
    Text($r('app.string.learning_daily_evaluation_dimensions'))
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 4 })

    Column() {
      this.DimensionRow(
        $r('app.string.learning_daily_evaluation_dim_difficulty'),
        'difficultyTendency',
        adj.difficultyTendency,
        adj.difficultyRationale
      )
      Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
      this.DimensionRow(
        $r('app.string.learning_daily_evaluation_dim_feedback'),
        'feedbackTone',
        adj.feedbackTone,
        adj.feedbackRationale
      )
      Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
      this.DimensionRow(
        $r('app.string.learning_daily_evaluation_dim_balance'),
        'weakStrongBalance',
        adj.weakStrongBalance,
        adj.balanceRationale
      )
      Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
      this.DimensionRow(
        $r('app.string.learning_daily_evaluation_dim_pace'),
        'learningPace',
        adj.learningPace,
        adj.paceRationale
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
```

- [ ] **Step 3: 重构 `WeeklyTrendBlock()` 接受 `trend: WeeklyTrend | null` 形参**

定位: 行 534-579 (WeeklyTrendBlock builder)

将 (整段替换):
```typescript
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
      Text($r('app.string.learning_daily_evaluation_trend_expired'))
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
```

替换为:
```typescript
@Builder
private WeeklyTrendBlock(trend: WeeklyTrend | null) {
  if (trend === null) {
    // 降级态
    Column({ space: 6 }) {
      Text($r('app.string.learning_daily_evaluation_trend'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 4 })
      Text($r('app.string.learning_daily_evaluation_trend_expired'))
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
        this.TrendRowProgress('技能速度', this.computeSkillVelocityProgressForTrend(trend))
        Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
        this.TrendRowProgress('反复出错', this.computeStrugglingProgressForTrend(trend))
        Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })
        this.TrendRowChips('兴趣主题', trend.topicInterests.map((t): string => t.topicLabel))
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
```

- [ ] **Step 4: 重构 `computeSkillVelocityProgress()` 和 `computeStrugglingProgress()` 接受 trend 形参**

定位: 行 632-645

将:
```typescript
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

替换为:
```typescript
private computeSkillVelocityProgressForTrend(trend: WeeklyTrend): number {
  return computeTrendProgress(trend.topImprovements.length, trend.topRegressions.length)
}

private computeStrugglingProgressForTrend(trend: WeeklyTrend): number {
  // 反复出错越多进度越低 (反向)
  return computeTrendProgress(0, trend.topStruggling.length)
}
```

- [ ] **Step 5: 更新 PageContent 中 done 分支的 builder 调用**

定位: `PageContent()` builder, 行 860-867

将:
```typescript
} else if (this.adjustment !== null &&
           this.adjustment.status !== TeachingStyleAdjustmentStatus.FAILED &&
           this.adjustment.status !== 'pending' &&
           this.adjustment.status !== 'running') {
  // done
  this.SummaryCard()
  this.DimensionsBlock()
  this.WeeklyTrendBlock()
}
```

替换为:
```typescript
} else if (this.adjustment !== null &&
           this.adjustment.status !== TeachingStyleAdjustmentStatus.FAILED &&
           this.adjustment.status !== 'pending' &&
           this.adjustment.status !== 'running') {
  // done
  this.SummaryCard(this.adjustment)
  this.DimensionsBlock(this.adjustment)
  this.WeeklyTrendBlock(this.trend)
}
```

- [ ] **Step 6: 编译验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -20
```

期望: `BUILD SUCCESSFUL` 且无 ArkTS 严格模式错误 (重点关注 `10605038`/`10605040` — 对象字面量类型,以及 `10505001` — 找不到 name)

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "refactor(eval-page): SummaryCard/DimensionsBlock/WeeklyTrendBlock 参数化"
```

---

## Task 4: 新增 @Local 字段 + 谓词 + 加载方法

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 添加 3 个 @Local 字段 + 1 token 字段**

定位: 行 76-89 (现有 @Local + private 字段)

将:
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

替换为:
```typescript
@Local adjustment: TeachingStyleAdjustment | null = null
@Local trend: WeeklyTrend | null = null
@Local selectedDate: string = ''
@Local isLoading: boolean = true
@Local isTriggering: boolean = false
@Local isErrorSheetVisible: boolean = false
@Local loadError: string = ''

// 上次完成的评估 (今日未完成时在下方追加展示)
@Local lastCompletedAdj: TeachingStyleAdjustment | null = null
@Local lastCompletedTrend: WeeklyTrend | null = null
@Local lastCompletedLoadError: string = ''

private loadToken: number = 0
private lastCompletedToken: number = 0
private pollTimerId: number = -1
private pollCount: number = 0
private readonly POLL_INTERVAL_MS: number = 2000
private readonly POLL_MAX_COUNT: number = 60
private appStorageDisposer: (() => void) | null = null
```

- [ ] **Step 2: 在 `aboutToAppear` 之后添加 `shouldFetchLastCompleted` 谓词**

定位: 在 `aboutToAppear` (行 95-99) 之后, `aboutToDisappear` (行 101-107) 之前插入

或放在 `loadPage` 之后 (更聚合)。两种位置都可, **选**: 放在 `loadPage` 之前 (行 109 之前)

插入:
```typescript
/**
 * 是否需要拉取"上次完成的评估"。
 * 层 A 触发条件: selectedDate 必须是今天 + 今日未 done (null/pending/running/failed)。
 * 切到过去日期时不拉 (避免与 DatePickerBar 冲突); 今日 done 时不拉 (section 自动隐藏)。
 */
private shouldFetchLastCompleted(): boolean {
  if (this.selectedDate !== todayYMD()) {
    return false
  }
  if (this.adjustment === null) {
    return true
  }
  if (this.adjustment.status === TeachingStyleAdjustmentStatus.DONE) {
    return false
  }
  return true
}
```

- [ ] **Step 3: 在 `loadPage` 的 finally 块之后添加 `loadLastCompleted` 方法**

定位: 行 142 (`this.maybeStartPolling()` 调用之后), 之后插入新方法

实际上, **要修改 `loadPage` 末尾** 调用新方法, 然后再定义新方法. 顺序:
1. 先修改 `loadPage` 调用点 (Step 3.1)
2. 再定义新方法 (Step 3.2)

**Step 3.1**: 定位 `loadPage` 的最后一行 `this.maybeStartPolling()` (行 142), 改为:

```typescript
    this.maybeStartPolling()

    // 上次完成的评估 (仅 selectedDate === today && 今日未 done 时拉取)
    if (this.shouldFetchLastCompleted()) {
      await this.loadLastCompleted()
    } else {
      this.clearLastCompleted()
    }
```

**Step 3.2**: 在 `loadPage` 之后 (行 144 之后, 在 `maybeStartPolling` 之前) 插入:

```typescript
/**
 * 拉取最近一次已完成的评估。
 * 用 asOfYMD=yesterday 调 getCurrentAdjustment, 严格排除今天, 只取 status='done' 的最近一条。
 * service 已自动过滤 failed 行 (TeachingStyleAdjustmentService 行 107-109)。
 */
private async loadLastCompleted(): Promise<void> {
  const token: number = ++this.lastCompletedToken
  this.lastCompletedLoadError = ''
  try {
    const yesterdayYMD: string = shiftYMD(todayYMD(), -1)
    const adj: TeachingStyleAdjustment | null =
      await ServiceRegistry.teachingStyle().getCurrentAdjustment(yesterdayYMD, Date.now())
    if (token !== this.lastCompletedToken) {
      return
    }
    this.lastCompletedAdj = adj
    if (adj !== null && adj.sourceWeeklyTrendId !== '') {
      try {
        const trend: WeeklyTrend | null =
          await ServiceRegistry.weeklyTrend().getTrendById(adj.sourceWeeklyTrendId)
        if (token !== this.lastCompletedToken) {
          return
        }
        this.lastCompletedTrend = trend
      } catch (e) {
        console.error(TAG, `lastCompleted getTrendById failed: ${(e as BusinessError).message ?? String(e)}`)
        this.lastCompletedTrend = null
      }
    } else {
      this.lastCompletedTrend = null
    }
  } catch (e) {
    console.error(TAG, `loadLastCompleted failed: ${(e as BusinessError).message ?? String(e)}`)
    if (token === this.lastCompletedToken) {
      this.lastCompletedLoadError = (e as BusinessError).message ?? String(e)
      this.lastCompletedAdj = null
      this.lastCompletedTrend = null
    }
  }
}

/**
 * 清空 last completed 状态。切到过去日期 / 今日 done 时调用。
 * 内部 ++lastCompletedToken 丢弃任何 in-flight 的 loadLastCompleted 结果。
 */
private clearLastCompleted(): void {
  this.lastCompletedAdj = null
  this.lastCompletedTrend = null
  this.lastCompletedLoadError = ''
  this.lastCompletedToken++
}
```

- [ ] **Step 4: 编译验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -20
```

期望: `BUILD SUCCESSFUL` 无新错误

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): 3 个 lastCompleted 字段 + shouldFetchLastCompleted 谓词 + load/clear 方法"
```

---

## Task 5: 新增 `LastCompletedHeader` + `LastCompletedSection` builder

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 在 `EmptyState` builder 之后 (行 835 之后) 添加 `LastCompletedHeader`**

定位: `EmptyState` builder 结束位置 (`@Builder private EmptyState() { ... }` 在行 776-835 范围)

在 `EmptyState` 之后 (大约行 835 之后, `formatConfidence` 之前) 插入:

```typescript
/**
 * "上次评估" section 的可点击 header。
 * 显示 "上次评估" 标题 + " · YYYY-MM-DD (距今 N 天)" 副标题 + 右侧 chevron。
 * 点击: 跳转到该日期 (同步 DatePickerBar, 走 loadPage)。
 */
@Builder
private LastCompletedHeader(adj: TeachingStyleAdjustment) {
  Row() {
    Column({ space: 2 }) {
      Text($r('app.string.learning_daily_evaluation_last_completed_title'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      Text(` · ${adj.effectiveDate} (${String($r('app.string.learning_daily_evaluation_last_completed_subtitle_format')).replace('%d', String(daysBetween(adj.effectiveDate, todayYMD())))})`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(14)
      .fontColor([$r('app.color.text_tertiary')])
  }
  .width('100%')
  .height(44)
  .padding({ left: 4, right: 4 })
  .alignItems(VerticalAlign.Center)
  .onClick((): void => {
    this.selectedDate = adj.effectiveDate
    this.loadPage()
  })
}

/**
 * "上次评估" section 容器。条件渲染:
 * - lastCompletedAdj === null → 空占位
 * - effectiveDate === today → 防御性空占位
 * - 否则: header + SummaryCard + DimensionsBlock + WeeklyTrendBlock
 */
@Builder
private LastCompletedSection() {
  if (this.lastCompletedAdj === null) {
    Column() {}
    return
  }
  if (this.lastCompletedAdj.effectiveDate === todayYMD()) {
    Column() {}
    return
  }

  Column({ space: 12 }) {
    this.LastCompletedHeader(this.lastCompletedAdj)
    this.SummaryCard(this.lastCompletedAdj)
    this.DimensionsBlock(this.lastCompletedAdj)
    this.WeeklyTrendBlock(this.lastCompletedTrend)
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
}
```

**重要**: `LastCompletedSection` 必须在 3 个已参数化的 builder 之后定义 (ArkTS 类内 @Builder 顺序无关, 但读起来更清晰)。位置可以选 EmptyState 之后。

- [ ] **Step 2: 在 import 块添加 `daysBetween` import**

定位: 行 20-26 (现有 `import { ... } from '../utils/DateRangeUtils'`)

将:
```typescript
import {
  todayYMD,
  shiftYMD,
  canGoBack as utilCanGoBack,
  canGoForward as utilCanGoForward,
  isWithinHistoryRange
} from '../utils/DateRangeUtils'
```

替换为:
```typescript
import {
  todayYMD,
  shiftYMD,
  canGoBack as utilCanGoBack,
  canGoForward as utilCanGoForward,
  isWithinHistoryRange,
  daysBetween
} from '../utils/DateRangeUtils'
```

- [ ] **Step 3: 编译验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -25
```

期望: `BUILD SUCCESSFUL` 无新错误

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): LastCompletedHeader + LastCompletedSection builders"
```

---

## Task 6: 在 PageContent 末尾追加 LastCompletedSection 调用

**Files:**
- Modify: `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets`

- [ ] **Step 1: 在 `PageContent` 的最外层 Column 末尾追加 `this.LastCompletedSection()`**

定位: `PageContent()` builder, 行 844-889

将 (行 845-888 整段):
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
          .color(this.themePrimary)
      }
      .width('100%')
      .padding({ top: 64 })
      .alignItems(HorizontalAlign.Center)
    } else if (this.adjustment !== null &&
               this.adjustment.status !== TeachingStyleAdjustmentStatus.FAILED &&
               this.adjustment.status !== 'pending' &&
               this.adjustment.status !== 'running') {
      // done
      this.SummaryCard(this.adjustment)
      this.DimensionsBlock(this.adjustment)
      this.WeeklyTrendBlock(this.trend)
    } else if (this.adjustment !== null && this.adjustment.status === 'pending') {
      this.PendingState()
    } else if (this.adjustment !== null && this.adjustment.status === 'running') {
      this.RunningState()
    } else if (this.adjustment !== null && this.adjustment.status === TeachingStyleAdjustmentStatus.FAILED) {
      this.FailedState()
    } else {
      // null
      this.EmptyState()
    }
  }
  .width('100%')
  .layoutWeight(1)
  .padding({ left: 16, right: 16 })
  .bindSheet($$this.isErrorSheetVisible, this.ErrorDetailSheet(), {
    height: SheetSize.FIT_CONTENT,
    showClose: false,
    onDisappear: (): void => {
      this.isErrorSheetVisible = false
    }
  })
}
```

替换为 (在 Column 的 `else` 分支后追加 `this.LastCompletedSection()`, 并在 Column 上方加一个分隔 Divider):

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
          .color(this.themePrimary)
      }
      .width('100%')
      .padding({ top: 64 })
      .alignItems(HorizontalAlign.Center)
    } else if (this.adjustment !== null &&
               this.adjustment.status !== TeachingStyleAdjustmentStatus.FAILED &&
               this.adjustment.status !== 'pending' &&
               this.adjustment.status !== 'running') {
      // done
      this.SummaryCard(this.adjustment)
      this.DimensionsBlock(this.adjustment)
      this.WeeklyTrendBlock(this.trend)
    } else if (this.adjustment !== null && this.adjustment.status === 'pending') {
      this.PendingState()
    } else if (this.adjustment !== null && this.adjustment.status === 'running') {
      this.RunningState()
    } else if (this.adjustment !== null && this.adjustment.status === TeachingStyleAdjustmentStatus.FAILED) {
      this.FailedState()
    } else {
      // null
      this.EmptyState()
    }

    // 上次完成的评估 (条件渲染: 内部已 null 短路)
    this.LastCompletedSection()
  }
  .width('100%')
  .layoutWeight(1)
  .padding({ left: 16, right: 16 })
  .bindSheet($$this.isErrorSheetVisible, this.ErrorDetailSheet(), {
    height: SheetSize.FIT_CONTENT,
    showClose: false,
    onDisappear: (): void => {
      this.isErrorSheetVisible = false
    }
  })
}
```

**注意**: `LastCompletedSection` 放在 `if-else` 之外, 这样 done 状态下也会调用 (内部会因 `lastCompletedAdj === null` 短路)。这与"今日 done 时自动隐藏"的需求一致。

- [ ] **Step 2: 编译验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -25
```

期望: `BUILD SUCCESSFUL` 无新错误

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/pages/LearningDailyEvaluationPage.ets
git commit -m "feat(eval-page): PageContent 末尾追加 LastCompletedSection"
```

---

## Task 7: 完整 build + 手动验证

**Files:**
- (none, verification only)

- [ ] **Step 1: 完整 assembleHap**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p buildMode=debug
```

期望: `BUILD SUCCESSFUL`, 产物在 `entry/build/default/outputs/default/entry-default-signed.hap`

- [ ] **Step 2: 验证产物存在**

```bash
ls -la entry/build/default/outputs/default/entry-default-signed.hap
```

期望: 文件存在, 大小 > 1MB

- [ ] **Step 3: 手动验证 (M1-M14, S1-S4)**

打开 DevEco Studio, 在真机/模拟器上运行, 验证 spec §11.2 和 §11.3 的场景:

| # | 场景 | 期望 | 通过? |
|---|------|------|-------|
| M1 | 全新用户, 今日 21:00 前 | EmptyState "今日评估即将生成", 无 section | [ ] |
| M2 | 全新用户, 今日 21:00 后 | EmptyState "今日评估未生成" + "立即生成", 无 section | [ ] |
| M3 | 有 1 天历史, 今日空 | section header "上次评估 · 昨天 (距今 1 天)" + 完整 3 块 | [ ] |
| M4 | 有 3 天历史, 今日空 | section 显示最近一天 | [ ] |
| M5 | 今日 pending | PendingState + section 仍显示 | [ ] |
| M6 | 今日 running | RunningState + section 仍显示 | [ ] |
| M7 | 今日 done | 完整 3 块内容, section **自动消失** | [ ] |
| M8 | 今日 failed | FailedState + section 仍显示 | [ ] |
| M9 | 点 section header | 跳到该日期, section 消失 | [ ] |
| M10 | 切日期 today → yesterday | 主区变成昨天视图, section 消失 | [ ] |
| M11 | 切回 today | section 重新出现 | [ ] |
| M12 | 趋势数据缺失 | section 仍渲染, WeeklyTrendBlock 降级态 | [ ] |
| M13 | 14 天前完成 | section header "(距今 14 天)" | [ ] |
| M14 | EmptyState + section 共存 | 视觉上垂直堆叠、明确分隔 | [ ] |
| S1 | 新装 app + 0 历史 | 任何状态都不出现 section | [ ] |
| S2 | 有 3 天历史 + 今日 done | section 不出现 | [ ] |
| S3 | 有 3 天历史 + 今日 null | section 出现, 正确显示 | [ ] |
| S4 | 切日期时 section 状态 | 来回切 3 次, 出现/消失正确 | [ ] |

- [ ] **Step 4: 回归验证 — 其他学习中心页面**

打开 `LearningProfilePage`, `LearningTomorrowPlanPage` 各点一下, 确认入口可点, 页面正常打开, 无控制台错误。

- [ ] **Step 5: 全部通过则无需额外提交; 如有发现新问题, 记录后单独修复提交**

---

## Self-Review

**1. Spec coverage:**
- §3 触发条件 → Task 4 Step 2 (谓词) + Task 5 Step 1 (render 守卫)
- §4 数据获取 → Task 4 Step 3 (`loadLastCompleted` 用 yesterday)
- §5 状态字段 → Task 4 Step 1
- §6 加载流程 → Task 4 Step 3 (修改 loadPage 末尾 + 新方法定义)
- §7.1 builder 参数化 → Task 3
- §7.2 LastCompletedSection → Task 5 Step 1
- §7.3 PageContent 末尾追加 → Task 6 Step 1
- §7.4 daysBetween 工具 → Task 1
- §8 资源键 → Task 2
- §9 错误处理 → Task 4 Step 3 (catch + token 守卫) + Task 5 Step 1 (render 守卫)
- §10 轮询/订阅 → 无需新代码, 现有 `subscribeRefreshTick` 触发 `loadPage` 时自动覆盖
- §11 测试 → Task 1 (TDD) + Task 7 Step 3 (手动)

**2. Placeholder scan:** 0 个 TBD/TODO. 所有代码块完整.

**3. Type consistency:** 全部 `TeachingStyleAdjustment` / `WeeklyTrend | null` 与 spec §5 一致. `TeachingStyleAdjustmentStatus.DONE` / `.FAILED` 来自模型, 与现有 page 一致. `lastCompletedToken` / `lastCompletedAdj` / `lastCompletedTrend` / `lastCompletedLoadError` 命名与 spec §5 一致. `shouldFetchLastCompleted` / `loadLastCompleted` / `clearLastCompleted` 命名与 spec §6 一致. `LastCompletedHeader` / `LastCompletedSection` 与 spec §7.2 一致. `daysBetween(fromYMD, toYMD)` 签名与 spec §7.4 一致. ✓

**潜在风险**: Task 5 Step 1 的 builder 顺序 (LastCompletedHeader 必须早于 LastCompletedSection) 已通过 @Builder 顺序保证 (ArkUI 不要求 @Builder 顺序, 但代码内联写法让 LastCompletedHeader 在 LastCompletedSection 之前定义, 读起来清晰).

**Spec requirement with no task**: 无遗漏. 全部 spec 章节都有 task 覆盖.
