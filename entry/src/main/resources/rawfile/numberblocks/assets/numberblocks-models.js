/* ================= 工具函数 ================= */
function el(tag, cls, parent, css){
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (css) e.style.cssText = css;
  if (parent) parent.appendChild(e);
  return e;
}

/* 立方体：返回正面。c.side 侧面单独上色；c.line 正面细边 */
function cube(parent, s, c, cx, cy){
  const cu = el('div','cube',parent,`width:${s}px;height:${s}px;left:${cx-s/2}px;top:${cy-s/2}px`);
  const h = s/2, sd = c.side;
  const tf = {
    ft:`translateZ(${h}px)`, bk:`rotateY(180deg) translateZ(${h}px)`,
    rt:`rotateY(90deg) translateZ(${h}px)`, lf:`rotateY(-90deg) translateZ(${h}px)`,
    tp:`rotateX(90deg) translateZ(${h}px)`, bt:`rotateX(-90deg) translateZ(${h}px)`
  };
  const bg = sd ? {
    ft:`linear-gradient(150deg,${c.light},${c.base} 55%)`, bk:sd.dark,
    rt:`linear-gradient(150deg,${sd.base},${sd.dark})`, lf:`linear-gradient(210deg,${sd.base},${sd.dark})`,
    tp:sd.base, bt:sd.dark
  } : {
    ft:`linear-gradient(150deg,${c.light},${c.base} 55%)`, bk:c.dark,
    rt:`linear-gradient(150deg,${c.base},${c.dark})`, lf:`linear-gradient(210deg,${c.base},${c.dark})`,
    tp:c.light, bt:c.dark
  };
  let front;
  for (const k in tf){
    const extra = (k === 'ft' && c.line) ? `;border:1px solid ${c.line}` : '';
    const f = el('div','face',cu,`transform:${tf[k]};background:${bg[k]}${extra}`);
    if (k === 'ft') front = f;
  }
  return front;
}

/* 长方体（宽 w × 高 h × 深 d） */
function box(parent, w, h, d, c, cx, cy, r = 6){
  const bx = el('div','cube',parent,`width:${w}px;height:${h}px;left:${cx-w/2}px;top:${cy-h/2}px`);
  const sides = `linear-gradient(150deg,${c.base},${c.dark})`;
  const rad = typeof r === 'number' ? r + 'px' : r;
  const F = [
    [w, h, `translateZ(${d/2}px)`,                 c.front || `linear-gradient(150deg,${c.light},${c.base} 55%)`],
    [w, h, `rotateY(180deg) translateZ(${d/2}px)`, c.dark],
    [d, h, `rotateY(90deg) translateZ(${w/2}px)`,  c.sides || sides],
    [d, h, `rotateY(-90deg) translateZ(${w/2}px)`, c.sides || sides],
    [w, d, `rotateX(90deg) translateZ(${h/2}px)`,  c.top || c.light],
    [w, d, `rotateX(-90deg) translateZ(${h/2}px)`, c.dark],
  ];
  let front;
  F.forEach(([fw, fh, tf, bg], i) => {
    const f = el('div','face',bx,`left:${(w-fw)/2}px;top:${(h-fh)/2}px;width:${fw}px;height:${fh}px;right:auto;bottom:auto;
      transform:${tf};background:${bg};border-radius:${rad}`);
    if (!i) front = f;
  });
  return front;
}

/* 多行多列方块 */
function grid(parent, cols, rows, s, c, cy = 0, cx = 0){
  const faces = [];
  for (let r = 0; r < rows; r++)
    for (let k = 0; k < cols; k++)
      faces.push(cube(parent, s, c, cx + (k - (cols-1)/2) * s, cy + (r - (rows-1)/2) * s));
  return faces;
}

/* 字符画排方块：字母对应调色板颜色，'.' 为空；带 outline 的颜色只在外圈画边框 */
function blocks(parent, rows, s, pal, cx = 0, cy = 0){
  const R = rows.length, C = Math.max(...rows.map(r => r.length));
  const at = (r, k) => (rows[r] || '')[k];
  const out = {};
  rows.forEach((row, r) => [...row].forEach((ch, k) => {
    if (ch === '.') return;
    const c = pal[ch];
    const f = cube(parent, s, c, cx + (k - (C-1)/2) * s, cy + (r - (R-1)/2) * s);
    if (c.outline){
      const bd = (rr, kk) => at(rr, kk) === ch ? `1px solid ${c.line}` : `3px solid ${c.outline}`;
      f.style.borderTop = bd(r-1, k);  f.style.borderBottom = bd(r+1, k);
      f.style.borderLeft = bd(r, k-1); f.style.borderRight = bd(r, k+1);
    }
    if (c.dot) f.innerHTML = '<div class="dot"></div>';
    (out[ch] = out[ch] || []).push(f);
  }));
  return out;
}

/* 四肢 */
function planes(node, w, o){
  for (const r of [0,90])
    el('div','plane',node,`transform:rotateY(${r}deg);border-radius:${w/2}px;
      background:linear-gradient(90deg,${o.dark},${o.color} 45%,${o.dark})`);
}
function limb(parent, o){
  const w = o.w || 18, rot = o.rot || 0;
  const l = el('div','limb',parent,
    `left:${o.x-w/2}px;top:${o.y}px;width:${w}px;height:${o.len}px;transform:rotateZ(${rot}deg)`);
  planes(l, w, o);
  let end = l, endLen = o.len, absRot = rot;
  if (o.fore){
    end = el('div','limb',l,
      `left:0;top:${o.len - w/2}px;width:${w}px;height:${o.fore.len}px;transform:rotateZ(${o.fore.rot}deg)`);
    planes(end, w, o);
    endLen = o.fore.len; absRot += o.fore.rot;
  }
  if (o.foot){
    const f = o.foot;
    const ft = el('div','limb',end,
      `left:${w/2-f.w/2}px;top:${endLen-f.h*0.6}px;width:${f.w}px;height:${f.h}px;transform:rotateZ(${-absRot}deg)`);
    const sole = f.sole ? `linear-gradient(0deg,${f.sole} 0 24%,rgba(255,255,255,0) 24%),` : '';
    for (const r of [0,90])
      el('div','plane',ft,`transform:rotateY(${r}deg);border-radius:50%;
        background:${sole}radial-gradient(circle at 40% 35%,${f.light},${f.color} 70%)`);
  }
  if (o.hand){
    const h = el('div','hand' + (o.still ? ' still' : ''),end,
      `left:${w/2-26}px;top:${endLen-26}px;--r:${-absRot + (o.handRot || 0)}`);
    h.innerHTML = o.hand;
  }
}

function crossed(parent, x, y, w, h, html){
  const c = el('div','cube',parent,`left:${x-w/2}px;top:${y}px;width:${w}px;height:${h}px`);
  for (const r of [0,90]) el('div','plane',c,`transform:rotateY(${r}deg)`).innerHTML = html;
}

function ball(parent, x, y, r, delay){
  const w = el('div','juggle',parent,
    `left:${x-r}px;top:${y-r}px;width:${2*r}px;height:${2*r}px;animation-delay:${delay}s`);
  for (const a of [0,60,120])
    el('div','plane',w,`transform:rotateY(${a}deg);border-radius:50%;
      background:radial-gradient(circle at 35% 30%,#ff7a7a,#e01b24 60%,#a0121a)`);
}

function decal(parent, x, y, w, h, z, html){
  el('div','decal',parent,`left:${x}px;top:${y}px;width:${w}px;height:${h}px;transform:translateZ(${z}px)`).innerHTML = html;
}

function num(parent, t, x, y, rot = 0, w = 40){
  el('div','num',parent,`left:${x}px;top:${y}px;width:${w}px;transform:rotateZ(${rot}deg)`).textContent = t;
}

/* 触手 */
const TENT = (flip, fy) => {
  const d = 'M0 12 C30 0 55 15 50 40 C46 58 26 60 24 46 C22 36 34 34 36 42';
  const suckers = [[27,11],[44,21],[50,36],[44,50],[33,53]]
    .map(([x,y]) => `<circle cx="${x}" cy="${y}" r="2.6" fill="#f4a6c8"/>`).join('');
  return `<svg viewBox="0 0 60 70"><g transform="translate(${flip?60:0} ${fy?70:0}) scale(${flip?-1:1} ${fy?-1:1})">
    <path d="${d}" fill="none" stroke="#5a1a3a" stroke-width="12" stroke-linecap="round"/>
    <path d="${d}" fill="none" stroke="#8a3462" stroke-width="8" stroke-linecap="round"/>${suckers}</g></svg>`;
};
function tentacle(parent, x, y, rot, flip, fy = false, delay = 0){
  const w = 60, h = 70, ay = fy ? h - 12 : 12;
  el('div','tent',parent,
    `left:${flip ? x-w : x}px;top:${y-ay}px;width:${w}px;height:${h}px;
     transform-origin:${flip ? w : 0}px ${ay}px;--r:${rot};animation-delay:${delay}s`).innerHTML = TENT(flip, fy);
}

function spiky(cx, cy, ro, ri, n){
  const p = [];
  for (let i = 0; i < n*2; i++){
    const r = i % 2 ? ri : ro, a = Math.PI * i / n - Math.PI / 2;
    p.push((cx + r*Math.cos(a)).toFixed(1) + ',' + (cy + r*Math.sin(a)).toFixed(1));
  }
  return p.join(' ');
}

const lens = o => `<div class="lens ${o.sq ? 'sq' : ''}" style="left:${o.x}px;top:${o.y}px;width:${o.w}px;height:${o.h || o.w}px;
  ${o.r != null ? `border-radius:${o.r}px;` : ''}--rim:${o.rim};--bw:${o.bw}px;--lid:${o.lid};--m:${o.m ?? 1}">
  <div class="pupil"></div>${o.half ? '<div class="half"></div>' : ''}<div class="lid"></div></div>`;
/* 嘴巴：x 不填则水平居中 */
const mouth = o => `<div class="mouth" style="${o.x != null ? `left:${o.x}px;` : ''}top:${o.top}px;width:${o.w}px;height:${o.h}px;--lip:${o.lip};border-width:${o.bw}px;
  transform:translateX(-50%) rotate(${o.rot || 0}deg)">${o.tongue ? '<i class="tongue"></i>' : ''}</div>`;
const bridge = (x, y, w, c) => `<div class="bridge" style="left:${x}px;top:${y}px;width:${w}px;background:${c}"></div>`;

const STAR = '50,3 62,36 97,38 69,59 79,94 50,74 21,94 31,59 3,38 38,36';

const starEye = (x, y, sz, fill, line, lid) => `<div style="position:absolute;left:${x}px;top:${y}px;width:${sz}px;height:${sz}px">
  <svg viewBox="0 0 100 100" style="position:absolute;inset:0;overflow:visible">
    <polygon points="${STAR}" fill="${fill}" stroke="${line}" stroke-width="5" stroke-linejoin="round"/></svg>
  ${lens({x:sz*.28, y:sz*.32, w:sz*.42, rim:'#fff', bw:0, lid, m:.35})}</div>`;

const FINGERS = `<line x1="30" y1="38" x2="15" y2="12"/><line x1="30" y1="38" x2="26" y2="5"/>
  <line x1="30" y1="38" x2="39" y2="7"/><line x1="30" y1="38" x2="50" y2="15"/><line x1="30" y1="42" x2="7" y2="35"/>`;
const glove = (fill, line, star, cuff) => `<svg viewBox="0 0 60 60" width="52" height="52" style="overflow:visible">
  <g stroke-linecap="round"><g stroke="${line}" stroke-width="12">${FINGERS}</g><g stroke="${fill}" stroke-width="8">${FINGERS}</g></g>
  <circle cx="30" cy="40" r="16" fill="${line}"/><circle cx="30" cy="40" r="14" fill="${fill}"/>
  <polygon points="${STAR}" transform="translate(21,31) scale(.18)" fill="${star}"/>
  ${cuff ? `<rect x="19" y="52" width="22" height="7" rx="3.5" fill="${cuff}"/>` : ''}</svg>`;

/* ===== 可复用的角色部件 ===== */
const CROWN = `<svg viewBox="0 0 80 58">
  <path d="M6 58 L6 22 L24 42 L40 10 L56 42 L74 22 L74 58 Z" fill="#e8262b" stroke="#b5161c" stroke-width="3" stroke-linejoin="round"/>
  <circle cx="6" cy="16" r="6" fill="#f5d01e"/><circle cx="40" cy="6" r="6" fill="#f5d01e"/><circle cx="74" cy="16" r="6" fill="#f5d01e"/></svg>`;

const HAIR = ['#e8262b','#f7941d','#f5d01e','#58bf45','#3fa9f5','#8e5bb8'];
const HAIR_SVG = `<svg viewBox="0 0 60 48">${HAIR.map((c, i) =>
  `<rect x="${3+i*9}" y="4" width="9" height="44" rx="4.5" fill="${c}" transform="rotate(${(i-2.5)*7} ${7.5+i*9} 48)"/>`).join('')}</svg>`;

const rbrow = (x, y) => `<svg width="26" height="12" viewBox="0 0 26 12" style="position:absolute;left:${x}px;top:${y}px;overflow:visible">${
  HAIR.map((c, i) => { const lift = Math.sin(i/5*Math.PI) * 3;
    return `<line x1="${3+i*4}" y1="${10-lift}" x2="${3+i*4}" y2="${4-lift}" stroke="${c}" stroke-width="3" stroke-linecap="round"/>`; }).join('')}</svg>`;

const RAINBOW_STRIPE = 'linear-gradient(90deg,#e8262b 0 17%,#f7941d 17% 33%,#f5d01e 33% 50%,#58bf45 50% 67%,#3fa9f5 67% 83%,#8e5bb8 83%)';

/* 颜料斑点（17） */
const splat = (x, y, c) => `<svg width="14" height="14" viewBox="0 0 14 14" style="position:absolute;left:${x}px;top:${y}px">
  <circle cx="7" cy="7" r="4" fill="${c}"/><circle cx="2" cy="3" r="1.6" fill="${c}"/>
  <circle cx="12" cy="4" r="1.3" fill="${c}"/><circle cx="11" cy="12" r="1.5" fill="${c}"/></svg>`;

/* 调色板 + 画笔（17） */
const PALETTE = `<svg viewBox="0 0 60 60" width="52" height="52" style="overflow:visible">
  <line x1="40" y1="54" x2="58" y2="4" stroke="#8a5a2a" stroke-width="4" stroke-linecap="round"/>
  <line x1="57" y1="6" x2="61" y2="-4" stroke="#e8262b" stroke-width="5" stroke-linecap="round"/>
  <path d="M30 8 C48 8 58 20 56 33 C54 44 45 46 41 42 C37 38 31 44 35 50 C37 56 26 58 18 54 C6 48 3 34 7 23 C11 13 20 8 30 8Z"
        fill="#ecc99a" stroke="#b5874f" stroke-width="2"/>
  ${[[18,22,'#e8262b'],[30,16,'#f5d01e'],[42,19,'#58bf45'],[48,31,'#3fa9f5'],[14,36,'#8e5bb8'],[22,47,'#f7941d']]
    .map(([x,y,c]) => `<circle cx="${x}" cy="${y}" r="4" fill="${c}"/>`).join('')}</svg>`;

/* 由深到浅的灰色（19） */
const mix = (a, b, t) => '#' + a.map((v, i) => Math.round(v + (b[i]-v)*t).toString(16).padStart(2,'0')).join('');
const greyRamp = n => Array.from({length:n}, (_, i) => { const t = i / (n-1); return {
  base:mix([138,142,146],[214,216,218],t), light:mix([165,169,173],[236,238,240],t), dark:mix([100,104,108],[170,173,176],t)}; });

const RAIN = [
  {base:'#9467c4', light:'#b892e0', dark:'#6f469c'},  // 紫
  {base:'#5f4fb5', light:'#8476d6', dark:'#40338a'},  // 靛
  {base:'#4cc3ec', light:'#8adcf5', dark:'#2a9bc4'},  // 蓝
  {base:'#58bf45', light:'#8bd877', dark:'#3b9430'},  // 绿
  {base:'#f2df1f', light:'#fff067', dark:'#c9b400'},  // 黄
  {base:'#f7941d', light:'#ffb352', dark:'#cf7410'},  // 橙
  {base:'#e8262b', light:'#ff5252', dark:'#b5161c'},  // 红
];

const GREYS = [
  {base:'#9aa0a6', light:'#b7bcc1', dark:'#757b81'},
  {base:'#b4b9bd', light:'#cfd3d6', dark:'#8d9297'},
  {base:'#cfd2d5', light:'#e6e8ea', dark:'#a6aaae'},
];

const eye6 = (x, y) => `<div style="position:absolute;left:${x}px;top:${y}px;width:40px;height:40px">
  <svg viewBox="0 0 40 24" style="position:absolute;left:0;top:-20px;width:40px;height:24px;overflow:visible">
    <g fill="none" stroke="#e0262b" stroke-width="5" stroke-linecap="round">
      <path d="M13 23 C8 15 6 6 11 4 C15 3 16 8 13 9"/>
      <path d="M20 23 C19 14 18 6 22 3 C26 1 28 6 24 8"/>
      <path d="M27 23 C32 15 34 6 29 4 C25 3 24 8 27 9"/></g></svg>
  ${lens({x:0, y:0, w:40, rim:'#e0262b', bw:7, lid:'#e0262b', m:.6})}</div>`;

const MASK8 = (dx = 0) => `<svg viewBox="0 0 112 70" width="112" height="70" style="position:absolute;left:${dx}px;top:0;overflow:visible">
  <g fill="#9c1f63" stroke="#7a1446" stroke-width="2" stroke-linejoin="round">
    <polygon points="${spiky(34,30,27,19,11)}"/>
    <polygon points="${spiky(78,30,27,19,11)}"/>
    <rect x="40" y="24" width="32" height="12" stroke="none"/></g></svg>`;

/* 十几的调色板：W = 10 的白块红边 */
const PAL = {
  W:{base:'#f2f3f5', light:'#ffffff', line:'#d6d9de', outline:'#d9232e', side:{base:'#e0262b', dark:'#a8141f'}},
  O:{base:'#f7941d', light:'#ffb352', dark:'#cf7410'},
  Y:{base:'#f5d01e', light:'#ffe566', dark:'#c9a400'},
  G:{base:'#5cbf4a', light:'#86d873', dark:'#3d9530'},
  B:{base:'#29b8d8', light:'#6fd6ec', dark:'#1a8fac'},
  P:{base:'#5b4bb0', light:'#7f70d0', dark:'#3d3088', dot:true},
  K:{base:'#e8409a', light:'#ff7dc2', dark:'#b51f76'},
};
