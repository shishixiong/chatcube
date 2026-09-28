/**
 * ten_frame 凑十引导课纯函数（ArkUI-free，hypium 全覆盖）。
 * 参考 docs/cou-shi-fa-lesson.html（9+5 八步凑十深度课原型），按 ten_frame
 * 工具参数 a/b 泛化。八步：看一看 → 找朋友 → 拆一拆 → 凑成十 → 十加几 →
 * 写算式 → 讲一讲 → 练一练。
 *
 * 记号：a = 框内大数（校验层保证 5-9），b = 框外小数（1-10），a+b > 10 且 ≤ 20。
 * friend = 10 - a（a 的凑十朋友），rest = b - friend（凑十后框外剩的数，恒 ≥ 1）。
 * 所有返回值强制类型注解（ArkTS 10605038）；防御性输入取界，不抛异常。
 */

export interface MakeTenScaffoldLine {
  eq: string
  label: string
}

export interface MakeTenChainLine {
  tag: string
  eq: string
  note: string
}

export interface MakeTenChips {
  canonical: string[]   // 正确顺序 4 句（讲一讲的判定基准）
  display: string[]     // 展示用乱序（固定置换，可测不随机）
}

export interface MakeTenPractice {
  big: number       // 练习题大数（看大数）
  small: number     // 练习题小数（拆小数）
  answer: number    // 应拆出的数 = 10 - big
  choices: number[] // 3 个唯一选项，含 answer，顺序由 big 决定（确定性）
}

export function makeTenFriend(a: number): number {
  const v: number = 10 - a
  if (v < 1) { return 1 }
  if (v > 5) { return 5 }
  return v
}

export function makeTenRemain(b: number, friend: number): number {
  const r: number = b - friend
  if (r < 0) { return 0 }
  return r
}

/** 「凑十记录」脚手架 5 行：题目 → 找朋友 → 拆小数 → 十加几 → 答案。 */
export function makeTenScaffold(a: number, b: number): MakeTenScaffoldLine[] {
  const friend: number = makeTenFriend(a)
  const rest: number = makeTenRemain(b, friend)
  const sum: number = a + b
  const lines: MakeTenScaffoldLine[] = [
    { eq: `${a} + ${b} = ?`, label: '题目' },
    { eq: `${a} + ${friend} = 10`, label: '找朋友' },
    { eq: `${b} = ${friend} + ${rest}`, label: '拆小数' },
    { eq: `10 + ${rest} = ${sum}`, label: '十加几' },
    { eq: `${a} + ${b} = ${sum}`, label: '答案' }
  ]
  return lines
}

/** 「写算式」步骤的 4 行算式链（逐行点亮）。 */
export function makeTenChain(a: number, b: number): MakeTenChainLine[] {
  const friend: number = makeTenFriend(a)
  const rest: number = makeTenRemain(b, friend)
  const sum: number = a + b
  const lines: MakeTenChainLine[] = [
    { tag: '第 1 步', eq: `${a} + ${b} = ${a} + ${friend} + ${rest}`, note: `拆出 ${friend}` },
    { tag: '第 2 步', eq: `${a} + ${friend} + ${rest} = 10 + ${rest}`, note: '先凑十' },
    { tag: '第 3 步', eq: `10 + ${rest} = ${sum}`, note: '再加余' },
    { tag: '答案', eq: `所以 ${a} + ${b} = ${sum}`, note: '完成' }
  ]
  return lines
}

/** 「讲一讲」4 句话（孩子按顺序点出）+ 固定乱序展示序。 */
export function makeTenChips(a: number, b: number): MakeTenChips {
  const friend: number = makeTenFriend(a)
  const rest: number = makeTenRemain(b, friend)
  const sum: number = a + b
  const canonical: string[] = [
    `${a} 差 ${friend} 凑成 10`,
    `把 ${b} 拆成 ${friend} 和 ${rest}`,
    `${a} + ${friend} = 10`,
    `10 + ${rest} = ${sum}`
  ]
  // 与原型一致的固定置换 [1,3,0,2]——不引入随机，保证测试可断言。
  const order: number[] = [1, 3, 0, 2]
  const display: string[] = []
  for (let i = 0; i < order.length; i++) {
    display.push(canonical[order[i]])
  }
  const chips: MakeTenChips = { canonical: canonical, display: display }
  return chips
}

/**
 * 「练一练」迁移题：换个数字方法不变。
 * 和不变换大数会在 b=10 / 小数反超等边界出 11+ 的坏参数，改用原型策略——
 * 从固定小题库取一个与本题大数不同的题（9+5 的课练 8+7，与 HTML 原型一致）。
 */
export function makeTenPractice(a: number, _b: number): MakeTenPractice {
  // 题库两项均满足：big ∈ [7,8]、answer = 10-big ∈ [2,3]、rest = small-answer ≥ 2、
  // 三选项互异（answer < rest < small）。
  let big: number = 8
  let small: number = 7
  if (a === 8) {
    big = 7
    small = 5
  }
  const answer: number = 10 - big
  const rest: number = small - answer
  // 展示顺序由 big 决定（确定性轮转），避免正确项总在第一位。
  const base: number[] = [answer, rest, small]
  const offset: number = big % 3
  const choices: number[] = []
  for (let i = 0; i < base.length; i++) {
    choices.push(base[(i + offset) % 3])
  }
  const p: MakeTenPractice = { big: big, small: small, answer: answer, choices: choices }
  return p
}

/** 8 步屏显标题（板内步骤头）。 */
export function makeTenStepTitles(a: number, b: number): string[] {
  const friend: number = makeTenFriend(a)
  const rest: number = makeTenRemain(b, friend)
  const titles: string[] = [
    '一共有多少个？',
    `${a} 的好朋友是谁？`,
    `把 ${b} 拆成 ${friend} 和 ${rest}`,
    `把 ${friend} 送进十格阵`,
    '十加几，得十几',
    '把过程连成算式',
    '你来当小老师',
    '换个数字，你还会吗？'
  ]
  return titles
}

/** 8 步 TTS 口播稿（进入该步时朗读；屏显文字另行渲染）。 */
export function makeTenStepNarrations(a: number, b: number): string[] {
  const friend: number = makeTenFriend(a)
  const rest: number = makeTenRemain(b, friend)
  const practice: MakeTenPractice = makeTenPractice(a, b)
  const narrations: string[] = [
    '先看清两个数，不用一个一个数。我们学一个三步的好办法：凑十法。',
    `十格阵里已经有 ${a} 个，还差几个才满十？点一点那个空格，找出 ${a} 的好朋友。`,
    `${a} 差 ${friend} 就满十。想一想，为什么拆 ${b}，不拆 ${a}？看大数，拆小数。`,
    `把 ${friend} 送进十格阵，看看会发生什么。`,
    `框里凑满了十，外面还剩 ${rest} 个。十加几，得十几。`,
    '一步一步，把刚才的过程连成算式。',
    '你来当小老师，按顺序点出凑十的三句话。先找朋友，再拆数，最后加。',
    `换个数字，方法还是一样。看大数 ${practice.big}，它差几满十？要从 ${practice.small} 里拆出几给 ${practice.big}？`
  ]
  return narrations
}
