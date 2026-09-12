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
