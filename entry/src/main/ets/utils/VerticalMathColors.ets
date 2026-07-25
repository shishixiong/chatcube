// utils/VerticalMathColors.ets
export const VERTICAL_MATH_BOARD_TEXT: string = '#3a3320'
export const VERTICAL_MATH_BOARD_LINE: string = 'rgba(58, 51, 32, 0.55)'

export const VERTICAL_MATH_ACTIVE_BG: string = '#ffe66d'
export const VERTICAL_MATH_ACTIVE_TEXT: string = '#3a2d0c'

export const VERTICAL_MATH_DONE_TEXT: string = '#15803d'
export const VERTICAL_MATH_DONE_BG: string = 'rgba(185, 242, 208, 0.18)'

export const VERTICAL_MATH_CARRY_TEXT: string = '#dc2626'
export const VERTICAL_MATH_BORROW_TEXT: string = '#7c3aed'

export const VERTICAL_MATH_ERROR_BG: string = '#ffe3dc'
export const VERTICAL_MATH_ERROR_TEXT: string = '#89564b'

export const VERTICAL_MATH_NARRATOR_BG: string = 'rgba(255, 250, 240, 0.86)'
export const VERTICAL_MATH_NARRATOR_ACTIVE_BG: string = '#fff1a5'
export const VERTICAL_MATH_NARRATOR_ACTIVE_TEXT: string = '#5b4811'
export const VERTICAL_MATH_NARRATOR_DONE_BG: string = '#e2f8e9'
export const VERTICAL_MATH_NARRATOR_DONE_TEXT: string = '#27764b'

export interface VerticalMathPalette {
  shell: string
  paper: string
  ink: string
  focus: string
  focusText: string
  success: string
  successBackground: string
  carry: string
  borrow: string
  divider: string
  secondaryText: string
}

const LIGHT_VERTICAL_MATH_PALETTE: VerticalMathPalette = {
  shell: '#F2EEFB',
  paper: '#FFFDF7',
  ink: '#352E24',
  focus: '#FFE15A',
  focusText: '#3A2D0C',
  success: '#56A779',
  successBackground: 'rgba(86, 167, 121, 0.18)',
  carry: '#FF6B57',
  borrow: '#7C5BB8',
  divider: '#DED8CC',
  secondaryText: '#6F675C'
}

const DARK_VERTICAL_MATH_PALETTE: VerticalMathPalette = {
  shell: '#272238',
  paper: '#302C27',
  ink: '#F7F1E4',
  focus: '#E7C74E',
  focusText: '#352A00',
  success: '#6FC294',
  successBackground: 'rgba(111, 194, 148, 0.18)',
  carry: '#FF7C6D',
  borrow: '#A88BD8',
  divider: '#5B554C',
  secondaryText: '#C4BAAB'
}

export function resolveVerticalMathPalette(isDarkMode: boolean): VerticalMathPalette {
  return isDarkMode ? DARK_VERTICAL_MATH_PALETTE : LIGHT_VERTICAL_MATH_PALETTE
}