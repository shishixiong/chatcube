# CardShell 统一卡片交互外壳 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 7 张选择题类互动卡片的外壳（标题/题干/重听/反馈/确认按钮/外层样式）收进一个统一的 CardShell 组件，卡片只声明配置 + 自绘 slot。

**Architecture:** 新建 `components/cardshell/`（CardShell @ComponentV2 + CardShellConfig 接口 + CardShellState @ObservedV2 状态对象）。卡片持有 state 并保留全部游戏逻辑，CardShell 只读 state 渲染 7 区，通过 @Event 回抛确认/重试/重听。判定逻辑、payload 结构、MessageBubble 挂载全部不动。

**Tech Stack:** ArkTS（HarmonyOS 6 / API 23，@ComponentV2 / @ObservedV2 / @BuilderParam）

**Spec:** `docs/superpowers/specs/2026-09-12-cardshell-design.md`（本计划从 spec 出发，执行者需同时阅读 spec）

## Global Constraints

- **构建验证命令**（每个任务都要跑，CLI 无 lint/test 可用，assembleHap 干净通过 = 验证通过）：
  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```
- **禁止修改**：`components/MessageBubble.ets`、任何 `onAnswer` payload 结构、`ToolExecutionService` / `BuiltinTools` / `StarEventModels`。
- **统一文案**（来自 spec §6，集中定义在 `CardShellCopy`，卡片内不得再出现旧文案）：`确认` / `再试一次` / `重听` / `播放中…` / 答对默认 `答对啦！真棒！`。
- **外层样式基准**（spec §4）：`padding(12) + backgroundColor(themeAiBubble) + borderRadius(12) + border({width:1, color: app.color.divider})`；largeSize 时透明无边框。
- **ArkTS 严格模式陷阱**（详见项目 MEMORY.md）：@Builder 体内不能写 `const`、不能提前 `return`；对象字面量必须显式类型标注；`Row.alignItems` 用 `VerticalAlign`、`Column.alignItems` 用 `HorizontalAlign`。
- **每个任务一个 commit**，消息格式 `feat(cardshell): ...` / `refactor(cardshell): ...`。
- 图标只用代码库已验证的 `sys.symbol.*` 名（本计划用到的：`character_textbox` / `speaker_wave_2` / `translate` / `checkmark` / `square_and_pencil` / `folder` / `link`，均已在现有代码中出现）。

---

### Task 1: CardShell 契约文件（Types + State）

**Files:**
- Create: `entry/src/main/ets/components/cardshell/CardShellTypes.ets`
- Create: `entry/src/main/ets/components/cardshell/CardShellState.ets`

**Interfaces:**
- Produces（Task 2/3 起依赖）:
  - `interface CardShellConfig { title: string; subtitle: string; icon: Resource; stem: string; hasAudio: boolean; usesConfirm: boolean; feedbackTitleCorrect: string; correctAnswerLabel: string }`
  - `class CardShellCopy { static readonly CONFIRM/RETRY/REPLAY/PLAYING/REPLAY_HINT/PLAYING_HINT/FEEDBACK_CORRECT: string }`
  - `class CardShellState`（@ObservedV2，@Trace 字段：hasSelection / submitted / isCorrect / isPlaying / feedbackTitle / feedbackDetail / headBadge / headPill / headPillColor）

- [ ] **Step 1: 写 CardShellTypes.ets**

```typescript
/**
 * CardShellTypes - 统一卡片外壳的配置契约与文案常量
 *
 * 设计见 docs/superpowers/specs/2026-09-12-cardshell-design.md
 * 卡片只声明本配置 + 自绘 slot; 外壳 7 区由 CardShell 统一渲染。
 * 所有交互文案集中在此, 卡片内不得再散落旧文案。
 */

export interface CardShellConfig {
  /** 头部标题, 如 '拼音题' */
  title: string
  /** 头部副标题(11vp 灰), 如 '分类 · 简单 · 6件 2桶'; 无则传 '' */
  subtitle: string
  /** 头部图标(32vp 圆形徽章内), 如 $r('sys.symbol.character_textbox') */
  icon: Resource
  /** 题干一行; 传 '' 则不渲染题干区(MathQuiz/EnglishQuiz 题面在 slot 内) */
  stem: string
  /** true 时渲染重听区(试点仅 ListeningQuizCard) */
  hasAudio: boolean
  /** true 时渲染确认按钮动作区; 直接操作类卡片传 false */
  usesConfirm: boolean
  /** 答对反馈标题, 默认 CardShellCopy.FEEDBACK_CORRECT */
  feedbackTitleCorrect: string
  /** 答错反馈的正确答案前缀, 如 '正确答案' / '正确读音' */
  correctAnswerLabel: string
}

/** 统一交互文案 — spec §6 文案表的唯一落地处 */
export class CardShellCopy {
  static readonly CONFIRM: string = '确认'
  static readonly RETRY: string = '再试一次'
  static readonly REPLAY: string = '重听'
  static readonly PLAYING: string = '播放中…'
  static readonly REPLAY_HINT: string = '点一下，再听一遍'
  static readonly PLAYING_HINT: string = '正在播放题目音频'
  static readonly FEEDBACK_CORRECT: string = '答对啦！真棒！'
}
```

- [ ] **Step 2: 写 CardShellState.ets**

```typescript
/**
 * CardShellState - 外壳共享响应式状态
 *
 * 卡片持有本实例并在游戏逻辑中写入; CardShell 通过 @Param 接收后
 * 只读渲染。@ObservedV2 + @Trace 保证跨组件响应式(与 AppUiState 同模式)。
 * 判定逻辑留在卡片 — 本类只是状态容器, 不含游戏规则。
 */

@ObservedV2
export class CardShellState {
  /** 已选中有效作答(选项/输入非空), 控制确认按钮显隐 */
  @Trace hasSelection: boolean = false
  /** 本地已判定(原各卡 showResult), 控制反馈横幅显隐 */
  @Trace submitted: boolean = false
  /** 判定结果 */
  @Trace isCorrect: boolean = false
  /** 音频播放中(重听区波形/文案) */
  @Trace isPlaying: boolean = false
  /** 反馈横幅标题覆写; '' 时用 config.feedbackTitleCorrect(对)/'再试一次'(错) */
  @Trace feedbackTitle: string = ''
  /** 反馈横幅副行, 如 '配对 3/3 · 失误 1 次'; '' 不渲染 */
  @Trace feedbackDetail: string = ''
  /** 头部右侧文字徽章, 如 '🔥 3' / '🏆 最佳 5'; '' 不渲染 */
  @Trace headBadge: string = ''
  /** 头部状态药丸文字, 如 '已回答'/'新纪录'/'已完成'/'已放弃'; '' 不渲染 */
  @Trace headPill: string = ''
  /** 头部状态药丸背景色(#RRGGBB) */
  @Trace headPillColor: string = '#FF6B35'
}
```

- [ ] **Step 3: 构建验证**

Run: 上述 assembleHap 命令。Expected: BUILD SUCCESSFUL（新文件无引用方，纯类型定义）。

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/components/cardshell/
git commit -m "feat(cardshell): add CardShell config contract, copy constants and reactive state"
```

---

### Task 2: CardShell 外壳组件

**Files:**
- Create: `entry/src/main/ets/components/cardshell/CardShell.ets`

**Interfaces:**
- Consumes: Task 1 的 `CardShellConfig` / `CardShellCopy` / `CardShellState`
- Produces（Task 3-9 依赖）:
  ```typescript
  @ComponentV2
  export struct CardShell {
    @Param config: CardShellConfig
    @Param state: CardShellState
    @Param isAnswered: boolean = false
    @Param correctAnswerText: string = ''
    @Param largeSize: boolean = false
    @Param blockTouch: boolean = false
    @BuilderParam slot: () => void
    @Event onConfirm: () => void = () => {}
    @Event onRetry: () => void = () => {}
    @Event onRequestReplay: () => void = () => {}
  }
  ```
  用法（尾随闭包 = slot）：`CardShell({ config: ..., state: ..., ... }) { this.OptionsArea() }`。@ComponentV2 + @BuilderParam 先例：`components/ChainOfThought.ets:23`。

- [ ] **Step 1: 写 CardShell.ets（完整文件）**

```typescript
/**
 * CardShell - 互动卡片统一外壳
 *
 * 7 区固定顺序: head → stem → replay(可选) → slot(卡片自绘) → feedback → actions。
 * 卡片通过 config 声明静态配置, 通过 CardShellState 传递响应式状态,
 * 通过 @Event 接收确认/重试/重听。外壳不含任何游戏判定逻辑。
 *
 * 视觉: 颜色从 AppUiState 的 themePrimary/themeAiBubble 派生(随主题+深色模式)。
 * 设计: docs/superpowers/specs/2026-09-12-cardshell-design.md
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { CardShellConfig, CardShellCopy } from './CardShellTypes'
import { CardShellState } from './CardShellState'

@ComponentV2
export struct CardShell {
  @Param config: CardShellConfig
  @Param state: CardShellState
  /** 历史会话只读态(payload 已回传) */
  @Param isAnswered: boolean = false
  /** 答错反馈显示的正确答案; '' 不渲染该行 */
  @Param correctAnswerText: string = ''
  /** 全屏 sheet 模式: 透明背景无边框, 由 sheet 接管外壳 */
  @Param largeSize: boolean = false
  /** true 时拦截触摸事件冒泡(CategorizationCard 的拖拽隔离需要) */
  @Param blockTouch: boolean = false
  /** 卡片自绘插槽: 选项组/棋盘/连线层等 */
  @BuilderParam slot: () => void
  @Event onConfirm: () => void = () => {}
  @Event onRetry: () => void = () => {}
  @Event onRequestReplay: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  build() {
    Column({ space: 10 }) {
      this.HeadRegion()
      this.StemRegion()
      this.ReplayRegion()
      this.slot()
      this.FeedbackRegion()
      this.ActionsRegion()
    }
    .width('100%')
    .padding(this.largeSize ? 24 : 12)
    .backgroundColor(this.largeSize ? Color.Transparent : this.themeAiBubble)
    .borderRadius(this.largeSize ? 0 : 12)
    .border(this.largeSize
      ? { width: 0, color: Color.Transparent, style: BorderStyle.Solid }
      : { width: 1, color: $r('app.color.divider'), style: BorderStyle.Solid })
    .alignItems(HorizontalAlign.Start)
    .onTouch((e: TouchEvent) => {
      if (this.blockTouch) {
        e.stopPropagation()
      }
    })
  }

  // ================ head: 图标徽章 + 标题/副标题 + 徽章/状态药丸 ================
  @Builder
  HeadRegion() {
    Row() {
      Column() {
        SymbolGlyph(this.config.icon)
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(this.config.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.config.subtitle !== '') {
          Text(this.config.subtitle)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
      .layoutWeight(1)

      if (this.state.headBadge !== '') {
        Text(this.state.headBadge)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .margin({ right: 6 })
      }
      if (this.state.headPill !== '') {
        Text(this.state.headPill)
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(this.state.headPillColor)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ================ stem: 题干一行 ================================
  @Builder
  StemRegion() {
    if (this.config.stem !== '') {
      Text(this.config.stem)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
  }

  // ================ replay: 重听音轨(仅 hasAudio) ==================
  @Builder
  ReplayRegion() {
    if (this.config.hasAudio) {
      Row({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.speaker_wave_2'))
            .fontSize(16)
            .fontColor([Color.White])
          Text(this.state.isPlaying ? CardShellCopy.PLAYING : CardShellCopy.REPLAY)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .height(40)
        .padding({ left: 16, right: 16 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.state.isPlaying ? withColorAlpha(this.themePrimary, '59') : this.themePrimary)
        .borderRadius(20)
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.onRequestReplay()
        })

        if (this.state.isPlaying) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.text_tertiary'))
        }

        Text(this.state.isPlaying ? CardShellCopy.PLAYING_HINT : CardShellCopy.REPLAY_HINT)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  // ================ feedback: 对/错统一横幅 ========================
  @Builder
  FeedbackRegion() {
    if (this.state.submitted || this.isAnswered) {
      Column({ space: 8 }) {
        if (this.state.isCorrect) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('🌟')
                .fontSize(22)
              Text(this.state.feedbackTitle !== '' ? this.state.feedbackTitle : this.config.feedbackTitleCorrect)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.Green)
            }
            .width('100%')

            if (this.state.feedbackDetail !== '') {
              Text(this.state.feedbackDetail)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          }
          .width('100%')
        } else {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('💪')
                .fontSize(20)
              Text(this.state.feedbackTitle !== '' ? this.state.feedbackTitle : CardShellCopy.RETRY)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')

            if (this.correctAnswerText !== '') {
              Row({ space: 4 }) {
                Text(`${this.config.correctAnswerLabel}：`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Text(this.correctAnswerText)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.Green)
              }
              .width('100%')
            }

            if (this.config.usesConfirm && !this.isAnswered) {
              Row() {
                Text(CardShellCopy.RETRY)
                  .fontSize(14)
                  .fontColor(this.themePrimary)
              }
              .width('100%')
              .height(38)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(withColorAlpha(this.themePrimary, '1F'))
              .borderRadius(8)
              .onClick(() => {
                this.onRetry()
              })
            }
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(10)
      .backgroundColor(withColorAlpha(this.state.isCorrect ? '#22C55E' : '#FF6B6B', '1A'))
      .borderRadius(8)
      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    }
  }

  // ================ actions: 确认主按钮(usesConfirm) ===============
  @Builder
  ActionsRegion() {
    if (this.config.usesConfirm && this.state.hasSelection && !this.state.submitted && !this.isAnswered) {
      Row() {
        Text(CardShellCopy.CONFIRM)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.themePrimary)
      .borderRadius(10)
      .animation({ duration: 150, curve: Curve.EaseOut })
      .onClick(() => {
        this.onConfirm()
      })
    }
  }
}
```

- [ ] **Step 2: 构建验证**

Run: assembleHap。Expected: BUILD SUCCESSFUL（组件尚无调用方）。

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/components/cardshell/CardShell.ets
git commit -m "feat(cardshell): add CardShell component with head/stem/replay/slot/feedback/actions regions"
```

---

### Task 3: PinyinQuizCard 试点迁移（样板卡）

**Files:**
- Modify: `entry/src/main/ets/components/PinyinQuizCard.ets`

**Interfaces:**
- Consumes: Task 1/2 的 CardShell / CardShellConfig / CardShellState

这是 7 张卡的迁移样板——后面 6 个任务是同一模式的复制。**确认 @BuilderParam + @ComponentV2 组合在此卡真实可用；若编译或运行异常，停下上报，退回方案 B（全局 @Builder 库），不要自行变通。**

- [ ] **Step 1: 加 import（文件头部 import 区）**

```typescript
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
```

- [ ] **Step 2: 加字段（`@Local quiz` 声明之后）**

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '拼音题',
    subtitle: '',
    icon: $r('sys.symbol.character_textbox'),
    stem: '',
    hasAudio: false,
    usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！',
    correctAnswerLabel: '正确读音'
  }
  private shellState: CardShellState = new CardShellState()
```

- [ ] **Step 3: aboutToAppear 末尾追加（stem 依赖 parseQuiz 后的 quiz）**

```typescript
    this.shellConfig = {
      title: '拼音题',
      subtitle: '',
      icon: $r('sys.symbol.character_textbox'),
      stem: this.getQuestionText(),
      hasAudio: false,
      usesConfirm: true,
      feedbackTitleCorrect: '答对啦！真棒！',
      correctAnswerLabel: '正确读音'
    }
    if (this.showResult) {
      this.shellState.submitted = true
      this.shellState.isCorrect = this.isCorrect
    }
```

- [ ] **Step 4: 处理器同步 state（4 处小改）**

`handleSelectOption` 中 `this.selectedOption = opt` 之后加：
```typescript
    this.shellState.hasSelection = true
```

`handleConfirm` 中 `this.isCorrect = isCorrect` 之后加：
```typescript
    this.shellState.submitted = true
    this.shellState.isCorrect = isCorrect
```

`handleRetry` 中三个字段重置之后加：
```typescript
    this.shellState.hasSelection = false
    this.shellState.submitted = false
    this.shellState.isCorrect = false
```

- [ ] **Step 5: 替换 build()**

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.quiz.correctAnswer,
      onConfirm: (): void => { this.handleConfirm() },
      onRetry: (): void => { this.handleRetry() }
    }) {
      this.CharacterArea()
      this.OptionsArea()
    }
  }
```

- [ ] **Step 6: 删除死代码**

删除 `ConfirmButton`、`ResultFeedback` 两个 @Builder（外壳接管）。保留 `CharacterArea` / `OptionsArea` / `getOption*` 辅助方法（slot 渲染仍用）。若 `withColorAlpha` 仅剩 getOptionGradient 在用则保留 import。

- [ ] **Step 7: 构建验证**

Run: assembleHap。Expected: BUILD SUCCESSFUL。

- [ ] **Step 8: 人工回归（DevEco 内运行，用户验证）**

1. 小星老师出拼音题 → 大字 + 4 选项渲染正常
2. 点选项 → 确认按钮出现 → 确认 → 答对绿色横幅 / 答错显示「正确读音：X」+「再试一次」
3. 再试一次 → 回到可重选
4. 重开会话 → 已答态只读恢复
5. 深色模式 + 换主题色 → 外壳跟随

- [ ] **Step 9: Commit**

```bash
git add entry/src/main/ets/components/PinyinQuizCard.ets
git commit -m "refactor(cardshell): migrate PinyinQuizCard to CardShell"
```

---

### Task 4: ListeningQuizCard 迁移（启用重听区）

**Files:**
- Modify: `entry/src/main/ets/components/ListeningQuizCard.ets`

**Interfaces:**
- Consumes: 同 Task 3。额外：`onRequestReplay` → `handlePlaySound`；`hasAudio: true`。

- [ ] **Step 1: 加 import + 字段（同 Task 3 模式）**

import 三行同 Task 3。字段（`@Local quiz` 之后）：

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '听力题',
    subtitle: '',
    icon: $r('sys.symbol.speaker_wave_2'),
    stem: '',
    hasAudio: true,
    usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！',
    correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()
```

- [ ] **Step 2: aboutToAppear 配置（注意：此卡 isAnswered 分支有提前 `return`）**

原 aboutToAppear 结构是 `if (this.isAnswered ...) { ...恢复...; return }` → 自动播放。因此：

a) 在 `this.quiz = this.parseQuiz()` 之后**紧跟着**插入 shellConfig 赋值（保证两条路径都执行）：

```typescript
    this.shellConfig = {
      title: '听力题',
      subtitle: '',
      icon: $r('sys.symbol.speaker_wave_2'),
      stem: this.getQuestionText(),
      hasAudio: true,
      usesConfirm: true,
      feedbackTitleCorrect: '答对啦！真棒！',
      correctAnswerLabel: '正确答案'
    }
```

b) 在 isAnswered 分支的 `return` **之前**（payload 恢复赋值之后）插入：

```typescript
      this.shellState.submitted = true
      this.shellState.isCorrect = this.isCorrect
```

注意：分支后的 `this.handlePlaySound()` 自动播放**保留不动**。

- [ ] **Step 3: handlePlaySound 同步播放态**

`handlePlaySound` 开头 `this.isPlayingSound = true` 后加 `this.shellState.isPlaying = true`；`onComplete` / `onError` / `.catch` 三个回调里 `this.isPlayingSound = false` 后各加 `this.shellState.isPlaying = false`。（卡片自己的 `isPlayingSound` 保留，防重入逻辑仍用它。）

- [ ] **Step 4: 处理器同步 state（同 Task 3 Step 4 的 4 处小改）**

- [ ] **Step 5: SoundArea 拆解**

删除 `SoundArea` @Builder，新建 `TtsFallbackArea`（内容 = 原 SoundArea 中 `if (this.ttsFailed && !this.isAnswered && !this.showResult)` 块的完整搬运，样式不动）：

```typescript
  @Builder
  TtsFallbackArea() {
    if (this.ttsFailed && !this.isAnswered && !this.showResult) {
      Column({ space: 6 }) {
        Text('声音播放失败')
          .fontSize(12)
          .fontColor($r('app.color.status_error'))
        Row() {
          Text(this.showWordText ? '隐藏文字' : '显示文字')
            .fontSize(14)
            .fontColor(this.themePrimary)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(withColorAlpha(this.themePrimary, '1F'))
        .borderRadius(8)
        .onClick(() => {
          this.showWordText = !this.showWordText
        })

        if (this.showWordText) {
          Text(this.quiz.soundText)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .padding(8)
      .backgroundColor(withColorAlpha('#FF6B6B', '1A'))
      .borderRadius(8)
    }
  }
```

- [ ] **Step 6: 替换 build()**

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.quiz.correctAnswer,
      onConfirm: (): void => { this.handleConfirm() },
      onRetry: (): void => { this.handleRetry() },
      onRequestReplay: (): void => { this.handlePlaySound() }
    }) {
      this.TtsFallbackArea()
      this.OptionsArea()
    }
  }
```

- [ ] **Step 7: 删除死代码**

删除 `ConfirmButton`、`ResultFeedback` @Builder。保留 `OptionsArea` / `getOption*` / TTS 逻辑。

- [ ] **Step 8: 构建 + 人工回归（重听按钮 → 播放中态 → 完成；TTS 失败时兜底开关）+ Commit**

```bash
git add entry/src/main/ets/components/ListeningQuizCard.ets
git commit -m "refactor(cardshell): migrate ListeningQuizCard with unified replay region"
```

---

### Task 5: PictureVocabCard 迁移

**Files:**
- Modify: `entry/src/main/ets/components/PictureVocabCard.ets`

**Interfaces:**
- Consumes: 同 Task 3。无音频、usesConfirm=true。

- [ ] **Step 1: import + 字段 + aboutToAppear 配置**

同 Task 3 模式，差异点：`title: this.quiz.mode === 'zh' ? '看图识字' : '看图识词'`（原 build 标题行逻辑）、`icon: $r('sys.symbol.translate')`、`correctAnswerLabel: '正确答案'`、`stem: this.getQuestionText()`。

- [ ] **Step 2: 处理器同步 state（同 Task 3 Step 4 的 4 处小改：select/confirm/retry/aboutToAppear 恢复）**

- [ ] **Step 3: 替换 build()**

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.quiz.correctAnswer,
      onConfirm: (): void => { this.handleConfirm() },
      onRetry: (): void => { this.handleRetry() }
    }) {
      this.ImageArea()
      this.OptionsArea()
    }
  }
```

- [ ] **Step 4: 删除 `ConfirmButton` / `ResultFeedback` @Builder；构建 + 人工回归（图片加载三态/选项/反馈）+ Commit**

```bash
git add entry/src/main/ets/components/PictureVocabCard.ets
git commit -m "refactor(cardshell): migrate PictureVocabCard to CardShell"
```

---

### Task 6: MathQuizCard 迁移（连胜徽章 + 5 题型）

**Files:**
- Modify: `entry/src/main/ets/components/MathQuizCard.ets`

**Interfaces:**
- Consumes: 同 Task 3。headBadge/headPill 由连胜状态驱动。

- [ ] **Step 1: import + 字段**

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '数学小游戏',
    subtitle: '',
    icon: $r('sys.symbol.checkmark'),
    stem: '',
    hasAudio: false,
    usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！',
    correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()
```

aboutToAppear 末尾：重建同字面量（题面在 slot 内，stem 保持 `''`），并在 isAnswered 分支加 `this.shellState.headPill = '已回答'` / `this.shellState.headPillColor = '#4CAF50'`。

- [ ] **Step 2: 连胜徽章同步 helper + 调用点**

```typescript
  private syncHeadBadge(): void {
    this.shellState.headBadge = this.currentStreak > 0
      ? `🔥 ${this.currentStreak}`
      : (this.bestStreak > 0 ? `🏆 最佳 ${this.bestStreak}` : '')
  }
```

搜索 `this.currentStreak =`、`this.bestStreak =`、`this.isNewBestStreak = true` 的所有赋值点（约在连胜加载回调与 handleConfirm 内），在每个赋值点之后追加：
```typescript
    this.syncHeadBadge()
```
以及 isNewBestStreak 置 true 处追加：
```typescript
    this.shellState.headPill = '新纪录'
    this.shellState.headPillColor = '#FF6B35'
```
（原头部 `isNewBestStreak ? '新纪录' : isAnswered ? '已回答'` 的优先级由赋值顺序天然保证：新纪录在答对当下写入，覆盖已回答。）

- [ ] **Step 3: 处理器同步 state（同 Task 3 Step 4 的 4 处小改）**

- [ ] **Step 4: 删除 5 处内容 Builder 内的 `this.ConfirmButton()` 调用**

`QuizContent` 分发的 5 个题型 Builder（arithmetic/shape/comparison/time/elapsed_time，约 616/714/791/934/1005 行）里各有一处 `this.ConfirmButton()`（外层包着「选中后显示」的 if 条件），整段 if 块删除——确认按钮统一由外壳 actions 区渲染。

- [ ] **Step 5: 替换 build()**

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: String(this.correctAnswerValue),
      onConfirm: (): void => { this.handleConfirm() },
      onRetry: (): void => { this.handleRetry() }
    }) {
      this.QuizContent()
    }
  }
```

- [ ] **Step 6: 删除死代码**

删除 `ConfirmButton` / `StreakIndicator` / `ResultFeedback` @Builder 及原 build 的标题行（含新纪录/已回答药丸）。**不动**：`QuizContent` 及 5 个题型 Builder、竖式帮助 sheet（bindSheet）、钟面渲染 helpers。

- [ ] **Step 7: 构建 + 人工回归（5 题型各出一题：选择→确认→反馈；连胜徽章递增；已答会话恢复显示「已回答」）+ Commit**

```bash
git add entry/src/main/ets/components/MathQuizCard.ets
git commit -m "refactor(cardshell): migrate MathQuizCard with streak badge in shell head"
```

---

### Task 7: EnglishQuizCard 迁移（提交→确认）

**Files:**
- Modify: `entry/src/main/ets/components/EnglishQuizCard.ets`

**Interfaces:**
- Consumes: 同 Task 3。双模式（phonics_choice 字母选择 / word·sentence 语音+键盘输入）。

- [ ] **Step 1: import + 字段**

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '英语小游戏',
    subtitle: '',
    icon: $r('sys.symbol.square_and_pencil'),
    stem: '',
    hasAudio: false,
    usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！',
    correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()
```

aboutToAppear 末尾重建字面量，`title` 按题型：`this.parseQuiz().questionType === 'phonics_choice' ? '自然拼读' : '英语小游戏'`。

- [ ] **Step 2: hasSelection 同步（两个输入路径）**

- 字母选择：`LetterOptionsGrid` 的选项点击处理器里（设 `selectedLetter` 处）加 `this.shellState.hasSelection = true`
- 键盘输入：`InputArea` 里 TextInput 的 `onChange` 改为：
  ```typescript
          .onChange((value: string) => {
            this.inputText = value
            this.shellState.hasSelection = value.trim() !== ''
          })
  ```

- [ ] **Step 3: 删除 InputArea 内联「提交」按钮**

`InputArea` 中 `Button('提交')` 整个（含 `.onClick(() => { this.handleSubmit() })`）删除，只留 TextInput（`.onSubmit(() => { this.handleSubmit() })` 保留）。主提交入口变为外壳确认按钮。语音识别完成直提的既有代码路径**不动**。

- [ ] **Step 4: 处理器同步 state**

`handleSubmit`（即原确认路径）`this.isCorrect = ...` 之后加 `this.shellState.submitted = true` / `this.shellState.isCorrect = isCorrect`；`handleRetry` 加三行重置；aboutToAppear 的 isAnswered 恢复分支（用 `parsePreviousAnswer()`）加：
```typescript
      this.shellState.submitted = true
      this.shellState.isCorrect = prev.correct
      this.shellState.headPill = '已回答'
      this.shellState.headPillColor = '#4CAF50'
```

- [ ] **Step 5: 替换 build()**

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.correctAnswerText,
      onConfirm: (): void => { this.handleSubmit() },
      onRetry: (): void => { this.handleRetry() }
    }) {
      if (this.parseQuiz().questionType === 'phonics_choice') {
        this.PhonicsContent()
        if (!this.isAnswered && !this.showResult) {
          this.LetterOptionsGrid()
        }
      } else {
        this.QuizContent()
        if (!this.isAnswered && !this.showResult) {
          this.InputArea()
        }
      }
    }
  }
```

- [ ] **Step 6: 删除死代码**

删除 `ResultFeedback` @Builder。保留 `PhonicsContent` / `LetterOptionsGrid` / `QuizContent` / `InputArea` / 语音录制逻辑 / 图片加载逻辑。

- [ ] **Step 7: 构建 + 人工回归（phonics 字母选择→确认；word 模式键盘输入→确认、语音直提；已答恢复）+ Commit**

```bash
git add entry/src/main/ets/components/EnglishQuizCard.ets
git commit -m "refactor(cardshell): migrate EnglishQuizCard, unify submit copy to 确认"
```

---

### Task 8: CategorizationCard 迁移（direct 模式 + largeSize）

**Files:**
- Modify: `entry/src/main/ets/components/CategorizationCard.ets`

**Interfaces:**
- Consumes: 同 Task 3 + `largeSize` / `blockTouch: true` / `usesConfirm: false`。

- [ ] **Step 1: import + 字段 + aboutToAppear 配置**

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '分类小管家',
    subtitle: '',
    icon: $r('sys.symbol.folder'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '分类完成！',
    correctAnswerLabel: ''
  }
  private shellState: CardShellState = new CardShellState()
```

aboutToAppear 末尾重建字面量：`subtitle: `${this.theme} · ${this.getDifficultyLabel()} · ${this.items.length}件 ${this.bins.length}桶``、`stem: this.instruction`。

- [ ] **Step 2: 胜负/放弃同步 state**

- 判胜处（原触发 `hasWon = true` 的位置，即全部物品分类正确时）加：
  ```typescript
    this.shellState.submitted = true
    this.shellState.isCorrect = true
    this.shellState.feedbackTitle = '分类完成！'
    this.shellState.feedbackDetail = `${this.correctCount}/${this.items.length} · ${this.formatBestTime(this.elapsedSeconds)} · 失败 ${this.wrongAttempts} 次`
    this.shellState.headPill = this.isNewBest ? '新纪录' : '已完成'
    this.shellState.headPillColor = '#4CAF50'
  ```
- 放弃处（`handleGiveUp` 或等价处理器内）加：
  ```typescript
    this.shellState.headPill = '已放弃'
    this.shellState.headPillColor = '#FF9F43'
  ```
  （放弃不显示反馈横幅——与现行为一致：原 `WinBanner` 仅 hasWon 时渲染。）
- aboutToAppear 的 isAnswered 恢复分支：按 `hasWon` 同步上述字段（复用同一段代码，若恢复路径已给 hasWon/isCompleted 赋值，紧随其后同步）。

- [ ] **Step 3: 替换 build()**

```typescript
  build() {
    if (this.validationError !== '') {
      Column() {
        this.ErrorPlaceholder()
      }
      .width('100%')
      .padding(this.largeSize ? 24 : 14)
      .backgroundColor(this.largeSize ? Color.Transparent : this.themeAiBubble)
      .borderRadius(this.largeSize ? 0 : 14)
      .border(this.largeSize
        ? { width: 0, color: Color.Transparent, style: BorderStyle.Solid }
        : { width: 1, color: $r('app.color.divider'), style: BorderStyle.Solid })
    } else {
      CardShell({
          config: this.shellConfig,
          state: this.shellState,
          isAnswered: false,
          largeSize: this.largeSize,
          blockTouch: true
        }) {
          this.BinRow()
          this.ItemsLayer()
          this.StatsGrid()
          if (!this.isCompleted) {
            this.ActionRow()
          }
        }
    }
  }
```

（`isAnswered: false`：CategorizationCard 的完成态由 state.submitted 驱动，恢复路径已在 Step 2 同步，避免放弃态误显反馈横幅。坏题兜底分支保留原卡片底色，避免罕见路径视觉回归。）

- [ ] **Step 4: 删除死代码**

删除 `HeaderRow` / `WinBanner` / `InstructionRow` @Builder。保留 `BinRow` / `ItemsLayer` / `StatsGrid` / `ActionRow` / `ErrorPlaceholder`（进度与放弃入口留在 slot，spec §5）。

- [ ] **Step 5: 构建 + 人工回归（in拖拽分类/全对横幅/放弃药丸/largeSize sheet 模式/已答恢复）+ Commit**

```bash
git add entry/src/main/ets/components/CategorizationCard.ets
git commit -m "refactor(cardshell): migrate CategorizationCard as direct-mode shell consumer"
```

---

### Task 9: MatchingPairsCard 迁移（direct 模式收尾）

**Files:**
- Modify: `entry/src/main/ets/components/MatchingPairsCard.ets`

**Interfaces:**
- Consumes: 同 Task 3 + `usesConfirm: false`。

- [ ] **Step 1: import + 字段 + aboutToAppear 配置**

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '连一连',
    subtitle: '',
    icon: $r('sys.symbol.link'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '全部配对成功！',
    correctAnswerLabel: ''
  }
  private shellState: CardShellState = new CardShellState()
```

aboutToAppear 末尾重建字面量：`subtitle: this.getSubtitle()`、`stem: this.getInstructionText()`。

- [ ] **Step 2: 胜负同步 state**

`checkCompletion` 中 `this.isCompleted = true` 之后（`onAnswer` 前后均可）加：
```typescript
    this.shellState.submitted = true
    this.shellState.isCorrect = true
    this.shellState.feedbackTitle = this.getBannerTitle()
    this.shellState.feedbackDetail = this.getBannerSub()
    this.shellState.headPill = '已完成'
    this.shellState.headPillColor = SUCCESS_GREEN
```

`handleGiveUp` 中 `this.gaveUp = true` 之后加：
```typescript
    this.shellState.submitted = true
    this.shellState.isCorrect = false
    this.shellState.feedbackTitle = this.getBannerTitle()
    this.shellState.feedbackDetail = this.getBannerSub()
    this.shellState.headPill = '已放弃'
    this.shellState.headPillColor = GIVEUP_ORANGE
```

aboutToAppear 的 isAnswered 恢复分支（`prevCompleted` 等已赋值处之后）加：
```typescript
    this.shellState.submitted = true
    this.shellState.isCorrect = this.hasWon()
    this.shellState.feedbackTitle = this.getBannerTitle()
    this.shellState.feedbackDetail = this.getBannerSub()
    this.shellState.headPill = this.getStatusLabel()
    this.shellState.headPillColor = this.getStatusColor()
```

- [ ] **Step 3: 替换 build()**

```typescript
  build() {
    if (!this.quizOk) {
      // 坏题兜底 (handler 已预校验拦截, 极少走到); 保留原卡片底色
      Column() {
        Text(this.quizError !== '' ? this.quizError : '题目参数有误')
          .fontSize(13)
          .fontColor($r('app.color.status_error'))
          .width('100%')
          .padding(8)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.themeAiBubble)
      .borderRadius(12)
      .border({ width: 1, color: $r('app.color.divider') })
    } else {
      CardShell({
        config: this.shellConfig,
        state: this.shellState,
        isAnswered: false
      }) {
        this.BoardArea()
        if (!this.isFinished()) {
          this.ProgressRow()
        }
        if (!this.isFinished()) {
          Row() {
            Text('不玩了')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.handleGiveUp()
          })
        }
      }
    }
  }
```

- [ ] **Step 4: 删除死代码**

删除 `HeaderRow` / `ResultFeedback` @Builder 及 `getBannerEmoji`（若仅 ResultFeedback 使用）。保留 `BoardArea` / `ProgressRow` / 连线几何 / `getBannerTitle` / `getBannerSub` / `getStatusLabel` / `getStatusColor`。

- [ ] **Step 5: 构建 + 人工回归（配对全对/放弃横幅、失误抖动、进度行、已答恢复）+ Commit**

```bash
git add entry/src/main/ets/components/MatchingPairsCard.ets
git commit -m "refactor(cardshell): migrate MatchingPairsCard, unify win/give-up banner"
```

---

## 收尾核查（全部任务完成后）

- [ ] 4-grep 漂移检查（旧文案应只残留在未迁移的 6 张 direct 类卡片中，7 张试点卡为 0）：
  ```bash
  grep -rn "再试一次 ↻\|再试试看～\|换一个答案\|没关系，下次再试试～\|'提交'\|听一听\|正在播放\.\.\." \
    entry/src/main/ets/components/PinyinQuizCard.ets \
    entry/src/main/ets/components/ListeningQuizCard.ets \
    entry/src/main/ets/components/PictureVocabCard.ets \
    entry/src/main/ets/components/MathQuizCard.ets \
    entry/src/main/ets/components/EnglishQuizCard.ets \
    entry/src/main/ets/components/CategorizationCard.ets \
    entry/src/main/ets/components/MatchingPairsCard.ets
  ```
  Expected: 无输出（或仅命中与交互文案无关的注释/字符串）。
- [ ] 最终 assembleHap 构建 + 全 7 卡人工回归一遍。
- [ ] 用户在真机/模拟器确认后，更新 `docs/superpowers/specs/2026-09-12-cardshell-design.md` 状态行为「已实施 v1」。
