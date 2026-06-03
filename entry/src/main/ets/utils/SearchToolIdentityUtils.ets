export const LEGACY_WEB_SEARCH_TOOL_ID: string = 'web_search'
export const SEARCH_WEB_TOOL_ID: string = 'search_web'
export const SCRAPE_WEB_TOOL_ID: string = 'scrape_web'
export const ASK_USER_TOOL_ID: string = 'ask_user'
export const GET_TIME_INFO_TOOL_ID: string = 'get_time_info'
export const NUMBER_PUZZLE_TOOL_ID: string = 'number_puzzle'
export const IMAGE_GENERATION_TOOL_ID: string = 'image_generation'
export const CHILD_PROFILE_TOOL_ID: string = 'child_profile'
export const MATH_VERIFY_TOOL_ID: string = 'math_verify'
export const MATH_QUIZ_TOOL_ID: string = 'math_quiz'
export const ENGLISH_QUIZ_TOOL_ID: string = 'english_quiz'

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


export function getSearchToolIds(): string[] {
  return [LEGACY_WEB_SEARCH_TOOL_ID, SEARCH_WEB_TOOL_ID, SCRAPE_WEB_TOOL_ID]
}

export function isNumberPuzzleFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === NUMBER_PUZZLE_TOOL_ID
}
