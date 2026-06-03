/**
 * 安全数学表达式解析器
 *
 * 递归下降解析，支持四则运算 + 括号 + 小数 + 一元负号。
 * 不使用 eval()，只接受纯数学字符，防止注入。
 *
 * 语法（从低到高优先级）：
 *   expr     = term ( ('+' | '-') term )*
 *   term     = unary ( ('*' | '/') unary )*
 *   unary    = '-' unary | primary
 *   primary  = NUMBER | '(' expr ')'
 */

// 词法 token 类型
const TT_NUM: number = 0
const TT_PLUS: number = 1
const TT_MINUS: number = 2
const TT_MUL: number = 3
const TT_DIV: number = 4
const TT_LPAREN: number = 5
const TT_RPAREN: number = 6
const TT_EOF: number = 7

class Token {
  type: number
  value: number

  constructor(type: number, value: number = 0) {
    this.type = type
    this.value = value
  }
}

function tokenize(input: string): Token[] {
  const tokens: Token[] = []
  const s = input.replace(/\s+/g, '')
  let i = 0
  while (i < s.length) {
    const ch = s.charAt(i)
    if (ch >= '0' && ch <= '9' || ch === '.') {
      let numStr = ''
      while (i < s.length && (s.charAt(i) >= '0' && s.charAt(i) <= '9' || s.charAt(i) === '.')) {
        numStr += s.charAt(i)
        i++
      }
      const num = parseFloat(numStr)
      if (isNaN(num)) {
        throw new Error(`Invalid number: ${numStr}`)
      }
      tokens.push(new Token(TT_NUM, num))
    } else if (ch === '+') {
      tokens.push(new Token(TT_PLUS))
      i++
    } else if (ch === '-') {
      tokens.push(new Token(TT_MINUS))
      i++
    } else if (ch === '*') {
      tokens.push(new Token(TT_MUL))
      i++
    } else if (ch === '/') {
      tokens.push(new Token(TT_DIV))
      i++
    } else if (ch === '(') {
      tokens.push(new Token(TT_LPAREN))
      i++
    } else if (ch === ')') {
      tokens.push(new Token(TT_RPAREN))
      i++
    } else {
      throw new Error(`Unexpected character: ${ch}`)
    }
  }
  tokens.push(new Token(TT_EOF))
  return tokens
}

class Parser {
  private tokens: Token[]
  private pos: number

  constructor(tokens: Token[]) {
    this.tokens = tokens
    this.pos = 0
  }

  private peek(): Token {
    return this.tokens[this.pos]
  }

  private consume(): Token {
    const t = this.tokens[this.pos]
    this.pos++
    return t
  }

  parse(): number {
    const result = this.parseExpr()
    if (this.peek().type !== TT_EOF) {
      throw new Error('Unexpected token after expression')
    }
    return result
  }

  private parseExpr(): number {
    let left = this.parseTerm()
    while (this.peek().type === TT_PLUS || this.peek().type === TT_MINUS) {
      const op = this.consume()
      const right = this.parseTerm()
      if (op.type === TT_PLUS) {
        left = left + right
      } else {
        left = left - right
      }
    }
    return left
  }

  private parseTerm(): number {
    let left = this.parseUnary()
    while (this.peek().type === TT_MUL || this.peek().type === TT_DIV) {
      const op = this.consume()
      const right = this.parseUnary()
      if (op.type === TT_MUL) {
        left = left * right
      } else {
        if (right === 0) {
          throw new Error('Division by zero')
        }
        left = left / right
      }
    }
    return left
  }

  private parseUnary(): number {
    if (this.peek().type === TT_MINUS) {
      this.consume()
      return -this.parseUnary()
    }
    return this.parsePrimary()
  }

  private parsePrimary(): number {
    const t = this.peek()
    if (t.type === TT_NUM) {
      this.consume()
      return t.value
    }
    if (t.type === TT_LPAREN) {
      this.consume()
      const result = this.parseExpr()
      if (this.peek().type !== TT_RPAREN) {
        throw new Error('Missing closing parenthesis')
      }
      this.consume()
      return result
    }
    throw new Error(`Unexpected token type: ${t.type}`)
  }
}

/**
 * 安全计算数学表达式
 *
 * @param expr 算术表达式字符串，如 "3 + 5 * 2"、"(8 - 3) / 2"
 * @returns 计算结果
 * @throws Error 当表达式包含非法字符或格式错误时
 */
export function evaluateMathExpression(expr: string): number {
  const trimmed = expr.trim()
  if (trimmed === '') {
    throw new Error('Empty expression')
  }
  // 安全校验：只允许数字、运算符、括号、小数点、空格
  const safePattern = /^[\d+\-*/ ().]+$/
  if (!safePattern.test(trimmed)) {
    throw new Error(`Invalid characters in expression: ${trimmed}`)
  }
  const tokens = tokenize(trimmed)
  const parser = new Parser(tokens)
  return parser.parse()
}
