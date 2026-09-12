# CardShell 统一卡片交互外壳 · 设计 Spec

**日期：** 2026-09-12
**版本：** v1（试点 7 卡）
**状态：** 已与用户确认（方案 A：包装组件 + @BuilderParam 插槽）
**原型：** `docs/cardshell-prototype.html`（视觉与结构提案；令牌契约取自 `docs/brand-spec.md`）
**范围：** 新建 `components/cardshell/` 外壳组件，迁移 7 张选择题类互动卡片；direct 类 6 卡（华容道/迷宫/数独/写字/竖式/AskUser）不在本期

---

## 1. 背景与问题

13 张互动卡片各自实现"外壳"（标题行、题干、确认按钮、结果反馈、外层卡片样式），产生真实的文案与结构漂移：

| 差异点 | 现状（已逐一核实） |
|---|---|
| 提交文案 | `确认`（Math/PictureVocab/Pinyin/Listening）/ `提交`（EnglishQuizCard.ets:832） |
| 重试文案 | `再试一次 ↻`（Math/English）/ `再试试看～`（PictureVocab）/ `换一个答案`（Pinyin/Listening）/ `没关系，下次再试试～`（MatchingPairs.ets:394） |
| 重听文案 | `听一听`（English）/ `点上面的按钮再听一遍`（Listening） |
| 播放态文案 | `播放中...`（English）/ `正在播放...`（Listening） |
| 反馈落点 | 各卡自写 ResultFeedback @Builder，样式接近但不完全一致 |

PinyinQuizCard 与 ListeningQuizCard 的外壳部分几乎逐行重复（~200 行/卡）。

## 2. 目标与非目标

**目标**
1. 外壳 7 区（head/stem/replay/slot/progress/feedback/actions）由 CardShell 统一渲染，卡片只声明配置与自绘 slot。
2. 统一交互文案（见 §6 文案表）。
3. 7 张试点卡的视觉与现卡一致（不趁机改样式），颜色继续从 `AppUiState` 的 themePrimary/themeAiBubble 派生（跟随 10 套主题 + 深色模式）。

**非目标（本期明确不做）**
- 不改交互行为：全部保持"选中→确认"两步流；英语题不改 instant 直提。
- 不做"不玩了/放弃/再玩一次"动作（现 quiz 卡无放弃，加按钮属行为变更）。
- 不做 progress 进度区（单题 quiz 卡无进度语义；matching/categorization 既有进度展示留在各自 slot 内）。
- 不改 `onAnswer` payload 结构、不改 MessageBubble 挂载方式。
- 不采用 brand-spec 固定暖纸色板（视觉跟 app 主题）。

## 3. 架构

```
components/cardshell/
├── CardShell.ets        # 外壳组件 @ComponentV2，持有 7 区渲染
├── CardShellTypes.ets   # CardShellConfig 接口 + 统一文案常量
└── CardShellState.ets   # @ObservedV2 共享状态对象
```

**数据流**：卡片组件持有 `CardShellState` 并负责游戏逻辑（解析 toolCall.arguments、判定对错、组 payload、调 onAnswer、恢复 answeredPayload）；CardShell 只读 state 渲染各区，通过 @Event 把确认/重试/重听回抛给卡片。**判定逻辑留在卡片，外壳不含游戏规则。**

```
MessageBubble（零改动，仍挂 XxxCard）
  └─ XxxQuizCard（@ComponentV2，游戏逻辑 + payload）
       └─ CardShell({ config, state, isAnswered, correctAnswerText,
                      onConfirm, onRetry, onRequestReplay }) {
            this.OptionsArea()      // 尾随闭包 = slot 插槽，卡片自绘
          }
```

区渲染顺序（CardShell.build 内固定）：head → stem → replay（`config.hasAudio`）→ slot（尾随闭包）→ feedback（`state.submitted || isAnswered`）→ actions（`config.usesConfirm`）。

## 4. 组件契约

```typescript
// CardShellTypes.ets
export interface CardShellConfig {
  title: string                    // '拼音题'
  icon?: Resource                  // SymbolGlyph 资源（如 sys.symbol.speaker_wave_2）
  stem: string                     // 题干/'怎么玩'一行
  hasAudio: boolean                // true 时渲染重听区（试点仅 ListeningQuiz）
  usesConfirm: boolean             // quiz 卡 true；matching/categorization false（无确认按钮）
  feedbackTitleCorrect: string     // 默认 '答对啦！真棒！'
  correctAnswerLabel: string       // '正确答案' / '正确读音'，拼进答错反馈
}

// 统一文案常量（集中定义，禁止散落各卡）
export class CardShellCopy {
  static readonly CONFIRM: string = '确认'
  static readonly RETRY: string = '再试一次'
  static readonly REPLAY: string = '重听'
  static readonly PLAYING: string = '播放中…'
  static readonly REPLAY_HINT: string = '点一下，再听一遍'
}

// CardShellState.ets
@ObservedV2
export class CardShellState {
  @Trace hasSelection: boolean = false   // 确认按钮显隐（选中且未提交）
  @Trace submitted: boolean = false      // 本地已判定（原 showResult）
  @Trace isCorrect: boolean = false
  @Trace isPlaying: boolean = false      // 重听播放态
}

// CardShell.ets
@ComponentV2
export struct CardShell {
  @Param config: CardShellConfig
  @Param state: CardShellState
  @Param isAnswered: boolean = false     // 历史会话只读态（payload 已回传）
  @Param correctAnswerText: string = ''  // 答错反馈显示的正确答案
  @BuilderParam slot: () => void         // 尾随闭包 = 插槽
  @Event onConfirm: () => void = () => {}
  @Event onRetry: () => void = () => {}
  @Event onRequestReplay: () => void = () => {}
}
```

**响应式依据**：V2 下 `@Param` 接 `@ObservedV2` 实例，CardShell 内读 `state.xxx` 即追踪 @Trace 字段（与项目 AppUiState 用法同构）；`@ComponentV2 + @BuilderParam` 有 `ChainOfThought.ets` 先例。

**外层样式**：`width('100%') + padding(12) + backgroundColor(themeAiBubble) + borderRadius(12) + border({width:1, color: app.color.divider})` —— 逐项照抄现卡，不趁机改样式。

## 5. 各区规格（试点取舍）

| 区 | 实现 | 说明 |
|---|---|---|
| head | ✅ | 图标（可选）+ 标题 15vp Bold；`isAnswered \|\| submitted` 且答对时右侧状态药丸'已完成'（沿用现'已完成/已放弃'药丸风格） |
| stem | ✅ | 16vp Medium 一行，取 quiz.question 或卡片默认题干 |
| replay | ✅ 仅 ListeningQuiz 启用 | 统一'重听/播放中…'按钮 + 播放态视觉；TTS 执行在卡片（onRequestReplay）；TTS 失败兜底（'显示文字'开关）留在 slot |
| slot | ✅ | 尾随闭包。大字区/图片/选项组/语音输入/连线层全留卡片 |
| progress | ⏸ 不实现 | 预留：state.correctCount/mistakes 字段未来可加 |
| feedback | ✅ | 对：feedbackTitleCorrect 绿色横幅；错：'再试一次' + `${correctAnswerLabel}：${correctAnswerText}` + '再试一次'按钮（触发 onRetry）。横幅样式沿用现 ResultFeedback（success/error 1A alpha 底 + 200ms OPACITY 过渡） |
| actions | ✅ 仅'确认' | `usesConfirm && state.hasSelection && !submitted && !isAnswered` 时显示；usesConfirm=false 时整行不渲染 |

**已答态恢复**：卡片 aboutToAppear 解析 answeredPayload 后写 state（submitted/isCorrect），外壳据此渲染只读视图——与现行为一致。

## 6. 统一文案表（本次落地）

| 现状 | 统一为 |
|---|---|
| 确认（Math/PictureVocab/Pinyin/Listening）、提交（English） | 确认 |
| 再试一次 ↻ / 再试试看～ / 换一个答案 / 没关系，下次再试试～ | 再试一次 |
| 听一听 / 点上面的按钮再听一遍 | 重听 |
| 播放中... / 正在播放... | 播放中… |
| 答对文案（读对了！好厉害！/ 听对了！好厉害！/ 等） | 答对啦！真棒！（config 可覆写） |

## 7. 每卡迁移映射

| 卡 | slot 内容 | 特殊处理 |
|---|---|---|
| PinyinQuiz | 大字区 + 选项 | 最简单，**第一个迁移**作样板 |
| ListeningQuiz | 选项 | 启用 replay 区（hasAudio=true）；TTS 兜底 UI 留 slot |
| PictureVocab | 图片 + 选项 | 图片区进 slot |
| MathQuiz | 5 种题型题面 + 选项 | 连胜/钟面渲染/竖式帮助 sheet 全不动，仅外壳替换 |
| EnglishQuiz | 图片 + 字母选项 + 语音输入 | '提交'改'确认'；语音识别完成直提逻辑不动；音频 UI 留 slot |
| Categorization | 物品 + 桶整局 | usesConfirm=false |
| MatchingPairs | 双列连线整局 | usesConfirm=false；胜负反馈走统一横幅 |

迁移顺序：Pinyin → Listening → PictureVocab → Math → English → Categorization → Matching。**一卡一提交**，每步独立可用，可停在任意步。

## 8. 测试与验证

- 每卡迁移后 `hvigorw assembleHap` 编译验证（CLI 无 lint/test 可用，按项目惯例，见 MEMORY.md）。
- 外壳无复杂纯逻辑（状态对象 + 文案常量），不建 hypium 测试；卡内既有逻辑不动，不新增测试面。
- 每卡人工回归清单：
  1. 选中 → 确认按钮出现 → 确认 → 对/错反馈正确
  2. 答错 → '再试一次' → 回到可重选状态 → 重答
  3. 历史会话已答态恢复（isAnswered + answeredPayload）
  4. 深色模式 + 切换主题色，外壳颜色跟随
  5. matching/categorization：整局流程 + 统一横幅落点

## 9. 风险与回滚

| 风险 | 缓解 |
|---|---|
| @BuilderParam + V2 边界问题 | ChainOfThought 同模式先例；Pinyin 卡先行验证；若失败退方案 B（全局 @Builder 库），外壳 API 不变 |
| 外壳替换导致视觉回归 | 视觉规格逐项照抄现卡，不趁机改样式 |
| 文案统一影响 LLM 看到的回传 | payload 结构完全不动，只改 UI 文案 |
| 单卡迁移引入回归 | 一卡一提交，git 可单卡 revert |

## 10. 后续方向（不阻塞本期）

- 迁移 direct 类 6 卡（华容道/迷宫/数独/写字/竖式/AskUser）
- progress 进度区（多题/整局卡）
- '不玩了/再玩一次'动作区（submitMode: none）
- 英语题/听力题 instant 直提模式
- brand-spec 暖纸色板（若儿童模式整体切换视觉语言）
