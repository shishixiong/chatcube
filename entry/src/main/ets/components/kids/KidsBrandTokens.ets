/**
 * 儿童模式品牌令牌（docs/brand-spec.md 六色 + 原型补充色）。
 *
 * 儿童主屏是恒定暖色绘本皮肤——不随深色模式/成人主题切换，
 * 因此这里用字面色值而非 app.color 资源（brand-spec 规则 1：
 * 暖米白底 + 暖黑文字，从不使用纯白/纯黑）。
 */

/** 页面底色 · 暖米白 */
export const KIDS_BG: string = '#FAF8F3'
/** 卡片/弹层表面 */
export const KIDS_SURFACE: string = '#FFFDF8'
/** 主文字 · 暖黑 */
export const KIDS_FG: string = '#24211C'
/** 次级文字 */
export const KIDS_MUTED: string = '#6F6A60'
/** 三级文字（v2.2 修正 4：bg 4.76 / surface 4.97 对比度） */
export const KIDS_SUBTLE: string = '#746E64'
/** 分隔线/描边 */
export const KIDS_BORDER: string = '#DED8CC'
/** 儿童主题色 · 小星老师暖橙 */
export const KIDS_ACCENT: string = '#FF9F43'
/** 主卡渐变亮端 */
export const KIDS_ACCENT_2: string = '#FFC46B'
/** 星星金 */
export const KIDS_STAR: string = '#F5B301'
/** 错误红（家长门答错） */
export const KIDS_DANGER: string = '#EF4444'
/** 主卡上的深棕文字 */
export const KIDS_ON_HERO: string = '#3A2506'
/** 主卡上的次级文字 */
export const KIDS_ON_HERO_2: string = '#5A2F04'
/** 星星徽章上的文字（金底深棕） */
export const KIDS_ON_GOLD: string = '#8A5A00'
/** 昵称头像文字色 */
export const KIDS_AVATAR_INK: string = '#7A3D00'
/** 昵称头像渐变亮端 */
export const KIDS_AVATAR_1: string = '#FFD79A'
/** 昵称头像渐变暗端 */
export const KIDS_AVATAR_2: string = '#FFB45E'
/** 主卡右上玻璃圆装饰 */
export const KIDS_GLASS: string = '#38FFFFFF'
/** 正文深灰（活动标签） */
export const KIDS_INK_SOFT: string = '#4A423A'

/** 学科色 · 学数学（仅 15% 淡底用；文字/图标用 KIDS_MATH_INK） */
export const KIDS_MATH: string = '#4E8FE0'
/** 学数学墨色（文字/图标专用，surface 对比 5.71） */
export const KIDS_MATH_INK: string = '#1D64BE'
/** 学科色 · 学英语 */
export const KIDS_ENGLISH: string = '#35A98A'
/** 学英语墨色（5.62） */
export const KIDS_ENGLISH_INK: string = '#22735D'
/** 学科色 · 学语文 */
export const KIDS_CHINESE: string = '#E2603C'
/** 学语文墨色（5.80；家长门答错也借用此色，§6 状态语义） */
export const KIDS_CHINESE_INK: string = '#B53917'
/** 学科色 · 小游戏 */
export const KIDS_GAMES: string = '#8B72E0'
/** 小游戏墨色（5.76） */
export const KIDS_GAMES_INK: string = '#6A49DB'
