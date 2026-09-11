/**
 * 儿童主屏「今天想玩什么」活动目录（纯数据，无 ArkUI 依赖）。
 *
 * 12 项活动与小星老师已锁定的出题工具一一对应（13 张互动卡片中除 vertical_math
 * 外的出题类 + 竖式课堂本身）；点击后以 startPrompt 作为新会话 initialPrompt
 * 自动发送，AI 收到后调用对应工具出题。
 * 分类色取自 docs/kids-home-prototype.html 的低饱和暖调色板
 * （非并列强调色，仅用于图标块底色区分）。
 */

export interface KidsActivityItem {
  /** 稳定标识（ForEach key / 埋点用） */
  id: string
  /** 图标 emoji */
  emoji: string
  /** 显示标签 */
  label: string
  /** 分类色（图标块底色基色，渲染时用 withColorAlpha 淡化） */
  color: string
  /** 点击后自动发送给小星老师的引导语 */
  startPrompt: string
}

export const KIDS_ACTIVITIES: KidsActivityItem[] = [
  {
    id: 'math',
    emoji: '➕',
    label: '数学题',
    color: '#FF9F43',
    startPrompt: '我想玩数学题，请给我出题吧'
  },
  {
    id: 'english',
    emoji: '🔤',
    label: '英语题',
    color: '#4F9CF0',
    startPrompt: '我想玩英语题，请给我出题吧'
  },
  {
    id: 'pinyin',
    emoji: '🈶',
    label: '拼音认读',
    color: '#38B48B',
    startPrompt: '我想玩拼音认读，请给我出题吧'
  },
  {
    id: 'writing',
    emoji: '✍️',
    label: '学写字',
    color: '#F06E9C',
    startPrompt: '我想学写字，请带我练习吧'
  },
  {
    id: 'categorization',
    emoji: '🗂️',
    label: '分类小管家',
    color: '#E8A72C',
    startPrompt: '我想玩分类小管家，请开始吧'
  },
  {
    id: 'puzzle',
    emoji: '🔢',
    label: '数字华容道',
    color: '#58BFC4',
    startPrompt: '我想玩数字华容道，请开始一局吧'
  },
  {
    id: 'maze',
    emoji: '🧭',
    label: '走迷宫',
    color: '#8A7DF0',
    startPrompt: '我想走迷宫，请开始一局吧'
  },
  {
    id: 'matching',
    emoji: '🔗',
    label: '连一连',
    color: '#F07A6A',
    startPrompt: '我想玩连一连，请开始吧'
  },
  {
    id: 'sudoku',
    emoji: '🧩',
    label: '数独',
    color: '#67B16D',
    startPrompt: '我想玩数独，请开始一局吧'
  },
  {
    id: 'picture_vocab',
    emoji: '🖼️',
    label: '看图识词',
    color: '#D67BB8',
    startPrompt: '我想玩看图识词，请给我出题吧'
  },
  {
    id: 'listening',
    emoji: '🎧',
    label: '听力辨音',
    color: '#4E8FE0',
    startPrompt: '我想玩听力辨音，请给我出题吧'
  },
  {
    id: 'vertical_math',
    emoji: '➗',
    label: '竖式课堂',
    color: '#8D6E63',
    startPrompt: '我想学竖式计算，请演示一题吧'
  }
]
