export const LEGACY_WEB_SEARCH_TOOL_ID: string = 'web_search'
export const SEARCH_WEB_TOOL_ID: string = 'search_web'
export const SCRAPE_WEB_TOOL_ID: string = 'scrape_web'
export const ASK_USER_TOOL_ID: string = 'ask_user'
export const GET_TIME_INFO_TOOL_ID: string = 'get_time_info'
export const IMAGE_GENERATION_TOOL_ID: string = 'image_generation'
export const MUSIC_GENERATION_TOOL_ID: string = 'music_generation'
export const CHILD_PROFILE_TOOL_ID: string = 'child_profile'
export const MATH_VERIFY_TOOL_ID: string = 'math_verify'
export const MATH_QUIZ_TOOL_ID: string = 'math_quiz'
export const ENGLISH_QUIZ_TOOL_ID: string = 'english_quiz'
// 旧版数字华容道工具名。已规范化为 NUMBER_PUZZLE_TOOL_ID, 但历史会话消息里
// 持久化的 functionName 永远是 huarongdao, 渲染/分发守卫必须保留此 legacy 常量。
export const HUARONGDAO_TOOL_ID: string = 'huarongdao'
export const NUMBER_PUZZLE_TOOL_ID: string = 'number_puzzle'
export const HANDWRITING_PRACTICE_TOOL_ID: string = 'handwriting_practice'
export const CATEGORIZATION_TOOL_ID: string = 'categorization'
export const VERTICAL_MATH_TOOL_ID: string = 'vertical_math'
export const GRANT_STAR_TOOL_ID: string = 'grant_star'
export const MAZE_TOOL_ID: string = 'maze'
export const SUDOKU_TOOL_ID: string = 'sudoku'
export const PICTURE_VOCAB_TOOL_ID: string = 'picture_vocab'
export const LISTENING_QUIZ_TOOL_ID: string = 'listening_quiz'


export function normalizeToolFunctionName(raw: string): string {
  const value = raw as string | null | undefined
  if (value === undefined || value === null) {
    return ''
  }
  return value.trim().toLowerCase().replace(/[\s\-]+/g, '_')
}

export function isSearchToolId(toolId: string): boolean {
  const normalized = normalizeToolFunctionName(toolId)
  return normalized === LEGACY_WEB_SEARCH_TOOL_ID ||
    normalized === SEARCH_WEB_TOOL_ID ||
    normalized === SCRAPE_WEB_TOOL_ID
}

export function isScrapeWebFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === SCRAPE_WEB_TOOL_ID
}

export function isSearchWebFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === LEGACY_WEB_SEARCH_TOOL_ID ||
    normalized === SEARCH_WEB_TOOL_ID ||
    normalized === 'exa_search' ||
    normalized === 'websearch' ||
    normalized === 'internet_search' ||
    normalized === 'web_search_exa'
}

export function isSearchToolFunctionName(functionName: string): boolean {
  return isSearchWebFunctionName(functionName) || isScrapeWebFunctionName(functionName)
}

export function isAskUserFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === ASK_USER_TOOL_ID ||
    normalized === 'user_input' ||
    normalized === 'ask'
}

export function isImageGenerationFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === IMAGE_GENERATION_TOOL_ID ||
    normalized === 'generate_image' ||
    normalized === 'text_to_image'
}

export function isMusicGenerationFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === MUSIC_GENERATION_TOOL_ID ||
    normalized === 'generate_music' ||
    normalized === 'text_to_music' ||
    normalized === 'compose_music'
}

export function isChildProfileFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === CHILD_PROFILE_TOOL_ID
}

export function isMathVerifyFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === MATH_VERIFY_TOOL_ID
}

export function isMathQuizFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === MATH_QUIZ_TOOL_ID
}

export function isEnglishQuizFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === ENGLISH_QUIZ_TOOL_ID
}

export function isPictureVocabFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === PICTURE_VOCAB_TOOL_ID ||
    normalized === 'picture_vocabulary' ||
    normalized === 'image_vocab' ||
    normalized === 'look_and_choose'
}

export function isListeningQuizFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === LISTENING_QUIZ_TOOL_ID ||
    normalized === 'listen_and_choose'
}

export function isHuarongdaoFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === HUARONGDAO_TOOL_ID
}

// number_puzzle (数字华容道) 的函数名识别; 含历史别名。
// isHuarongdaoFunctionName 保留给历史会话的 legacy 消息渲染/分发。
export function isNumberPuzzleFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === NUMBER_PUZZLE_TOOL_ID ||
    normalized === 'number_sliding_puzzle'
}

export function isMazeFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === MAZE_TOOL_ID
}

export function isSudokuFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === SUDOKU_TOOL_ID
}

export function isHandwritingPracticeFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === HANDWRITING_PRACTICE_TOOL_ID ||
    normalized === 'handwriting' ||
    normalized === 'write_practice' ||
    normalized === 'learn_to_write'
}

export function isCategorizationFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === CATEGORIZATION_TOOL_ID ||
    normalized === 'classify' ||
    normalized === 'categorize'
}

export function isVerticalMathFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === VERTICAL_MATH_TOOL_ID
}

export function isVerticalMathToolId(toolId: string): boolean {
  const normalized = normalizeToolFunctionName(toolId)
  return normalized === VERTICAL_MATH_TOOL_ID
}

export function isGrantStarFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === GRANT_STAR_TOOL_ID
}


export function getSearchToolIds(): string[] {
  return [LEGACY_WEB_SEARCH_TOOL_ID, SEARCH_WEB_TOOL_ID, SCRAPE_WEB_TOOL_ID]
}
