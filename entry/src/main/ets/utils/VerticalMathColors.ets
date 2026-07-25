// utils/VerticalMathColors.ets

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