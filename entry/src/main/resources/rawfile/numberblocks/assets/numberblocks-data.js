/* ================= 角色定义 ================= */
const CHARS = [
  /* ---------- 1 ---------- */
  { n:1, color:'#e8323f', top:250, sh:120, shw:150, build(b){
    const red  = {base:'#e8262b', light:'#ff5252', dark:'#b5161c'};
    const lc   = {color:'#b3141c', dark:'#7d0b10'};
    const foot = {w:28, h:16, color:'#b3141c', light:'#d8333b'};
    num(b,'1',-20,-150,12);
    limb(b,{x:-60, y:-8, len:58, w:20, rot:122, ...lc});
    limb(b,{x: 60, y: 5, len:55, w:20, rot:-25, ...lc});
    limb(b,{x:-28, y:58, len:62, w:20, rot: 6, ...lc, foot});
    limb(b,{x: 28, y:58, len:62, w:20, rot:-6, ...lc, foot});
    const f = cube(b, 130, red, 0, 0);
    f.innerHTML = `<div class="eye1"><div class="white"><div class="pupil"></div><div class="lid"></div></div></div>
                   <div class="mouth1"></div>`;
  }},

  /* ---------- 2 ---------- */
  { n:2, color:'#f28c28', top:250, sh:146, shw:150, build(b){
    const org  = {base:'#f7941d', light:'#ffb352', dark:'#cf7410'};
    const lc   = {color:'#8a3b80', dark:'#5e2457'};
    const shoe = {w:38, h:20, color:'#f7941d', light:'#ffc070'};
    num(b,'2',-20,-170);
    limb(b,{x:-46, y:-58, len:62, w:18, rot: 125, ...lc});
    limb(b,{x: 46, y:-58, len:62, w:18, rot:-125, ...lc});
    limb(b,{x:-22, y:92, len:48, w:18, rot: 4, ...lc, foot:shoe});
    limb(b,{x: 22, y:92, len:48, w:18, rot:-4, ...lc, foot:shoe});
    const t = cube(b, 100, org, 0, -50);
    cube(b, 100, org, 0, 50);
    t.innerHTML =
      lens({x:3,  y:12, w:44, rim:'#8e3e91', bw:6, lid:org.base, m:.7}) +
      lens({x:53, y:12, w:44, rim:'#8e3e91', bw:6, lid:org.base, m:.7}) +
      bridge(44, 31, 12, '#8e3e91') +
      mouth({top:64, w:36, h:20, lip:'#f06a95', bw:4});
  }},

  /* ---------- 3 ---------- */
  { n:3, color:'#ecd61f', top:255, sh:170, shw:130, build(b){
    const yel  = {base:'#f5d01e', light:'#ffe566', dark:'#c9a400'};
    const lc   = {color:'#e0352f', dark:'#a8201c'};
    const foot = {w:24, h:14, color:'#e0352f', light:'#ff6a5e'};
    num(b,'3',-95,-205);
    crossed(b, 0, -170, 64, 46, CROWN);
    limb(b,{x:-42, y:-20, len:32, w:16, rot: 55, ...lc, fore:{len:30, rot:-105}});
    limb(b,{x: 42, y:-85, len:34, w:16, rot:-70, ...lc, fore:{len:30, rot:-80}});
    ball(b,  62, -150, 9, 0);
    ball(b,  96, -178, 9, -0.37);
    ball(b, 112, -128, 9, -0.73);
    limb(b,{x:-16, y:120, len:42, w:16, rot: 4, ...lc, foot});
    limb(b,{x: 16, y:120, len:42, w:16, rot:-4, ...lc, foot});
    const t = cube(b, 84, yel, 0, -84);
    cube(b, 84, yel, 0, 0);
    cube(b, 84, yel, 0, 84);
    t.innerHTML =
      lens({x:7,  y:12, w:32, rim:'#f28c28', bw:5, lid:yel.base, m:.5}) +
      lens({x:45, y:12, w:32, rim:'#f28c28', bw:5, lid:yel.base, m:.5}) +
      bridge(37, 26, 10, '#f28c28') +
      mouth({top:52, w:34, h:18, lip:'#e0262b', bw:4});
  }},

  /* ---------- 4 ---------- */
  { n:4, color:'#3fae49', top:240, sh:138, shw:190, build(b){
    const grn  = {base:'#5cbf4a', light:'#86d873', dark:'#3d9530'};
    const lc   = {color:'#2f7d2a', dark:'#1d5419'};
    const foot = {w:26, h:14, color:'#2f7d2a', light:'#4a9c42'};
    num(b,'4',40,-165,8);
    limb(b,{x:-90, y:0, len:30, w:18, rot: 60, ...lc, fore:{len:28, rot:-115}});
    limb(b,{x: 90, y:0, len:30, w:18, rot:-60, ...lc, fore:{len:28, rot: 115}});
    limb(b,{x:-30, y:85, len:46, w:18, rot: 3, ...lc, foot});
    limb(b,{x: 30, y:85, len:46, w:18, rot:-3, ...lc, foot});
    grid(b, 2, 2, 90, grn);
    decal(b, -90, -90, 180, 180, 46,
      `<div class="brow" style="left:42px;top:2px;width:40px;height:16px;transform:rotate(-6deg)"></div>
       <div class="brow" style="left:100px;top:-2px;width:40px;height:16px;transform:rotate(14deg)"></div>` +
      lens({x:50, y:26, w:34, h:40, sq:true, rim:'#2a6b25', bw:4, lid:grn.base, m:.6}) +
      lens({x:96, y:26, w:34, h:40, sq:true, rim:'#2a6b25', bw:4, lid:grn.base, m:.6}) +
      `<div class="mouth4" style="left:66px;top:86px;width:48px;height:18px"></div>`);
  }},

  /* ---------- 5 ---------- */
  { n:5, color:'#20b8d4', top:245, sh:178, shw:100, build(b){
    const blu  = {base:'#29b8d8', light:'#6fd6ec', dark:'#1a8fac'};
    const lc   = {color:'#1f3f8a', dark:'#13275a'};
    const foot = {w:20, h:12, color:'#1f3f8a', light:'#3555a8'};
    num(b,'5',-20,-215);
    limb(b,{x:-30, y:-95,  len:52, w:14, rot: 12,  ...lc});
    limb(b,{x: 30, y:-110, len:40, w:14, rot:-140, ...lc, hand:glove('#2f8fe0','#2f8fe0','#1d5fb8')});
    limb(b,{x:-12, y:145, len:30, w:14, rot: 2, ...lc, foot});
    limb(b,{x: 12, y:145, len:30, w:14, rot:-2, ...lc, foot});
    const top = grid(b, 1, 5, 60, blu)[0];
    top.style.overflow = 'visible';
    top.innerHTML =
      `<div style="position:absolute;left:-12px;top:5px;width:34px;height:34px">
         <svg viewBox="0 0 100 100" style="position:absolute;inset:0">
           <polygon points="${STAR}" fill="#2563c9" stroke="#1d3f8f" stroke-width="5" stroke-linejoin="round"/></svg>
         ${lens({x:9, y:10, w:16, rim:'#fff', bw:0, lid:blu.base, m:.3})}
       </div>` +
      lens({x:32, y:9, w:22, rim:'#1d3f8f', bw:3, lid:blu.base, m:.35}) +
      mouth({top:38, w:22, h:14, lip:'#f0506e', bw:3});
  }},

  /* ---------- 6（骰子） ---------- */
  { n:6, color:'#4a4589', top:230, sh:148, shw:170, build(b){
    const pur  = {base:'#5b4bb0', light:'#7f70d0', dark:'#3d3088'};
    const lc   = {color:'#8a1f3c', dark:'#5e1028'};
    const foot = {w:24, h:14, color:'#8a1f3c', light:'#b0344f'};
    num(b,'6',-20,-170);
    limb(b,{x:-64, y:0, len:32, w:18, rot: 60, ...lc, fore:{len:30, rot:-115}});
    limb(b,{x: 64, y:0, len:32, w:18, rot:-60, ...lc, fore:{len:30, rot: 115}});
    limb(b,{x:-28, y:88, len:44, w:18, rot: 3, ...lc, foot});
    limb(b,{x: 28, y:88, len:44, w:18, rot:-3, ...lc, foot});
    grid(b, 2, 3, 64, pur).forEach(f => f.innerHTML = '<div class="dot"></div>');
    decal(b, -64, -96, 128, 192, 33,
      eye6(-18, 44) + eye6(106, 44) +
      mouth({top:104, w:50, h:22, lip:'#e8559a', bw:5}));
  }},

  /* ---------- 7（彩虹） ---------- */
  { n:7, color:'#4a4589', top:262, sh:172, shw:90,
    bg:'linear-gradient(180deg,#9a72a0 0 50px,#4a4589 50px 125px,#22b8d4 125px 220px,#4cb648 220px 315px,#f2e11c 315px 410px,#f7941d 410px 505px,#e8323f 505px)',
    build(b){
    const lc   = {color:'#7a4fb0', dark:'#523380'};
    const legc = {color:'#3b3a8f', dark:'#25245e'};
    const foot = {w:18, h:11, color:'#3b3a8f', light:'#5554b0'};
    num(b,'7',-20,-234);
    crossed(b, 0, -168, 44, 36, HAIR_SVG);
    limb(b,{x:-20, y:-122, len:64, w:12, rot: 8, ...lc});
    limb(b,{x: 20, y:-122, len:64, w:12, rot:-8, ...lc});
    limb(b,{x:-9, y:134, len:24, w:12, rot: 2, ...legc, foot});
    limb(b,{x: 9, y:134, len:24, w:12, rot:-2, ...legc, foot});
    let top;
    RAIN.forEach((c, i) => { const f = cube(b, 40, c, 0, (i-3)*40); if (i === 0) top = f; });
    top.style.overflow = 'visible';
    top.innerHTML =
      lens({x:-3, y:6, w:22, h:15, r:4, rim:'#f5d01e', bw:3, lid:RAIN[0].base, m:.25}) +
      lens({x:21, y:6, w:22, h:15, r:4, rim:'#f5d01e', bw:3, lid:RAIN[0].base, m:.25}) +
      bridge(17, 11, 6, '#f5d01e') +
      mouth({top:25, w:18, h:9, lip:'#f5d01e', bw:2});
  }},

  /* ---------- 8（章鱼） ---------- */
  { n:8, color:'#e8457f', top:235, sh:165, shw:180, build(b){
    const pnk = {base:'#e8409a', light:'#ff7dc2', dark:'#b51f76'};
    num(b,'8',-20,-178);
    [[-70,-40,false],[-15,5,true],[40,30,true]].forEach(([y, r, fy], i) => {
      tentacle(b,  56, y,  r, false, fy, -i*0.3);
      tentacle(b, -56, y, -r, true,  fy, -i*0.3 - 0.9);
    });
    tentacle(b,  24, 108,  75, false, true, -0.4);
    tentacle(b, -24, 108, -75, true,  true, -1.2);
    grid(b, 2, 4, 56, pnk);
    decal(b, -56, -112, 112, 90, 29,
      MASK8(0) +
      lens({x:19, y:15, w:30, rim:'#5a1038', bw:4, lid:'#c2307e', m:.5, half:true}) +
      lens({x:63, y:15, w:30, rim:'#5a1038', bw:4, lid:'#c2307e', m:.5, half:true}) +
      mouth({top:60, w:34, h:14, lip:'#7a1446', bw:3, rot:-6}));
  }},

  /* ---------- 9（3×3 灰色） ---------- */
  { n:9, color:'#9da3a6', top:250, sh:150, shw:210, build(b){
    const lc   = {color:'#4a5a75', dark:'#323f55'};
    const foot = {w:26, h:14, color:'#4a5a75', light:'#6b7c98'};
    num(b,'9',70,-180);
    limb(b,{x:-96, y:-24, len:62, w:18, rot:100, ...lc});
    limb(b,{x: 96, y: 10, len:32, w:18, rot:-60, ...lc, fore:{len:30, rot:115}});
    limb(b,{x:-34, y:96, len:42, w:18, rot: 3, ...lc, foot});
    limb(b,{x: 34, y:96, len:42, w:18, rot:-3, ...lc, foot});
    GREYS.forEach((c, r) => grid(b, 3, 1, 64, c, (r-1)*64));
    decal(b, -96, -96, 192, 192, 33,
      `<svg viewBox="0 0 192 30" width="192" height="30" style="position:absolute;left:0;top:-18px;overflow:visible">
         <g fill="none" stroke-linecap="round">
           <path d="M30 22 Q56 2 86 14" stroke="#4a5a75" stroke-width="15"/>
           <path d="M106 12 Q134 -8 162 16" stroke="#4a5a75" stroke-width="15"/>
           <path d="M38 15 Q56 4 78 10" stroke="#6b7c98" stroke-width="4"/>
           <path d="M114 6 Q134 -4 152 8" stroke="#6b7c98" stroke-width="4"/></g></svg>` +
      lens({x:38,  y:26, w:46, h:42, r:14, rim:'#3d4a66', bw:6, lid:GREYS[0].base, m:.6}) +
      lens({x:104, y:22, w:48, h:46, r:14, rim:'#3d4a66', bw:6, lid:GREYS[0].base, m:.6}) +
      bridge(82, 42, 24, '#3d4a66') +
      mouth({top:112, w:66, h:38, lip:'#3d4a66', bw:5, tongue:true}));
  }},

  /* ---------- 10 ---------- */
  { n:10, color:'#d9232e', head:'#ffffff', top:245, sh:160, shw:140, build(b){
    const wht  = {base:'#f2f3f5', light:'#ffffff', line:'#d6d9de', side:{base:'#e0262b', dark:'#a8141f'}};
    const lc   = {color:'#d9232e', dark:'#9e1420'};
    const legc = {color:'#5a1622', dark:'#3a0c14'};
    const foot = {w:20, h:12, color:'#5a1622', light:'#7a2a36'};
    const G = glove('#ffffff','#e05a5a','#e0262b','#e0262b');
    num(b,'10',-10,-192,0,80);
    limb(b,{x:-50, y:-78, len:38, w:14, rot:120, ...lc, hand:G});
    limb(b,{x: 50, y:-20, len:34, w:14, rot:-30, ...lc, hand:G, still:true, handRot:180});
    limb(b,{x:-16, y:125, len:28, w:13, rot: 2, ...legc, foot});
    limb(b,{x: 16, y:125, len:28, w:13, rot:-2, ...legc, foot});
    grid(b, 2, 5, 50, wht);
    decal(b, -50, -125, 100, 250, 26,
      `<div class="frame"></div>` +
      starEye(2,  1, 46, '#e8262b', '#b5161c', '#e8262b') +
      starEye(52, 1, 46, '#e8262b', '#b5161c', '#e8262b') +
      mouth({top:46, w:28, h:14, lip:'#f2a58a', bw:3}));
  }},

  /* ---------- 11 ---------- */
  { n:11, color:'#d0202e', top:262, sh:178, shw:120, build(b){
    const wht  = {base:'#f2f3f5', light:'#ffffff', line:'#d6d9de', side:{base:'#e0262b', dark:'#a8141f'}};
    const red  = {base:'#e8262b', light:'#ff5252', dark:'#b5161c'};
    const arm  = {color:'#8cc63f', dark:'#5e9a1e'};
    const hand = {w:16, h:16, color:'#8cc63f', light:'#b5e070'};
    const legc = {color:'#45b38a', dark:'#2b8263'};
    const shoe = {w:22, h:12, color:'#c9ced4', light:'#ffffff'};
    num(b,'11',-64,-206,0,80);
    cube(b, 48, red, -24, -120);
    limb(b,{x:-48, y:102, len:30, w:12, rot: 45, ...arm, foot:hand});
    limb(b,{x: 48, y:102, len:30, w:12, rot:-45, ...arm, foot:hand});
    limb(b,{x:-14, y:144, len:26, w:12, rot: 2, ...legc, foot:shoe});
    limb(b,{x: 14, y:144, len:26, w:12, rot:-2, ...legc, foot:shoe});
    grid(b, 2, 5, 48, wht, 24);
    decal(b, -48, -96, 96, 240, 25,
      `<div class="frame"></div>` +
      lens({x:5,  y:198, w:32, h:22, r:11, rim:'#e8262b', bw:5, lid:'#f2f3f5', m:.35}) +
      lens({x:60, y:201, w:18, h:16, rim:'#e8262b', bw:3, lid:'#f2f3f5', m:.25}) +
      mouth({top:224, w:16, h:8, lip:'#e8262b', bw:2}));
  }},

  /* ---------- 12【按截图】 ---------- */
  { n:12, color:'#d0202e', split:'#f28c28', top:250, sh:140, shw:170, build(b){
    const lc   = {color:'#9a2a3a', dark:'#6a1626'};
    const hand = {w:16, h:16, color:'#9a2a3a', light:'#c04a5a'};
    const foot = {w:22, h:12, color:'#9a2a3a', light:'#c04a5a'};
    num(b,'12',-40,-170,0,80);
    limb(b,{x:-75, y:20, len:34, w:14, rot: 80, ...lc, fore:{len:28, rot:-45}, foot:hand});
    limb(b,{x: 75, y:50, len:30, w:14, rot:-50, ...lc, fore:{len:26, rot: 30}, foot:hand});
    limb(b,{x:-22, y:96, len:30, w:14, rot: 3, ...lc, foot});
    limb(b,{x: 22, y:96, len:30, w:14, rot:-3, ...lc, foot});
    blocks(b, ['WWW','WOW','WOW','WWW'], 50, PAL);
    decal(b, -75, -100, 150, 200, 26,
      `<div style="position:absolute;left:50px;top:86px;width:20px;height:6px;border-radius:3px;background:#e8407a;transform:rotate(14deg)"></div>
       <div style="position:absolute;left:80px;top:86px;width:20px;height:6px;border-radius:3px;background:#e8407a;transform:rotate(-14deg)"></div>` +
      lens({x:48, y:104, w:27, h:34, r:10, rim:'#e8407a', bw:5, lid:PAL.O.base, m:.4}) +
      lens({x:75, y:104, w:27, h:34, r:10, rim:'#e8407a', bw:5, lid:PAL.O.base, m:.4}) +
      `<svg width="28" height="16" viewBox="0 0 28 16" style="position:absolute;left:74px;top:158px;overflow:visible">
         <path d="M3 4 Q14 16 25 4" fill="none" stroke="#f0b48c" stroke-width="5" stroke-linecap="round"/></svg>`);
  }},

  /* ---------- 13【按截图】 ---------- */
  { n:13, color:'#d0202e', split:'#ecd61f', top:245, sh:134, shw:110, build(b){
    const lc   = {color:'#7c2a63', dark:'#541a42'};
    const hand = {w:15, h:15, color:'#7c2a63', light:'#a04888'};
    const foot = {w:20, h:11, color:'#7c2a63', light:'#a04888'};
    num(b,'13',-80,-205,0,80);
    const back = el('div','cube',b,'left:0;top:0;transform:translateZ(-44px)');
    const y3 = el('div','cube drift',back,'left:0;top:0;transform-origin:50px -100px');
    [[30,-120],[70,-120],[70,-80]].forEach(([x, y]) => cube(y3, 40, PAL.Y, x, y));
    const g = el('div','cube',b,'left:0;top:0;transform:rotateZ(-5deg)');
    limb(g,{x:-40, y:52, len:24, w:12, rot: 50, ...lc, fore:{len:22, rot:-105}, foot:hand});
    limb(g,{x: 40, y:52, len:24, w:12, rot:-50, ...lc, fore:{len:22, rot: 105}, foot:hand});
    limb(g,{x:-16, y:96, len:26, w:12, rot: 2, ...lc, foot});
    limb(g,{x: 16, y:96, len:26, w:12, rot:-2, ...lc, foot});
    blocks(g, ['WW','WW','WW','WW','WW'], 40, PAL);
    decal(g, -40, -100, 80, 200, 21,
      `<div style="position:absolute;left:8px;top:146px;width:24px;height:5px;border-radius:3px;background:#a0307e;transform:rotate(-14deg)"></div>
       <div style="position:absolute;left:48px;top:146px;width:24px;height:5px;border-radius:3px;background:#a0307e;transform:rotate(14deg)"></div>` +
      lens({x:8,  y:156, w:28, h:24, r:9, rim:'#c03a96', bw:4, lid:'#f2f3f5', m:.35}) +
      lens({x:44, y:156, w:28, h:24, r:9, rim:'#c03a96', bw:4, lid:'#f2f3f5', m:.35}) +
      mouth({top:184, w:18, h:10, lip:'#a0307e', bw:2}));
  }},

  /* ---------- 14【按截图】 ---------- */
  { n:14, color:'#d0202e', split:'#3fae49', top:250, sh:198, shw:130, build(b){
    const lc   = {color:'#3f9a37', dark:'#24631f'};
    const hand = {w:14, h:14, color:'#3f9a37', light:'#6cc25e'};
    const foot = {w:20, h:11, color:'#1d5419', light:'#3f7a37'};
    num(b,'14',-40,-212,0,80);
    const g = el('div','cube',b,'left:0;top:0;transform:rotateZ(5deg)');
    box(g, 78, 20, 42, {base:'#2a6b25', light:'#3f8c36', dark:'#1a4a16'}, 0, -130, '12px 12px 6px 6px');
    limb(g,{x:-36, y:34, len:26, w:12, rot: 100, ...lc, fore:{len:20, rot: 30}, foot:hand});
    limb(g,{x: 36, y:34, len:26, w:12, rot:-100, ...lc, fore:{len:20, rot:-30}, foot:hand});
    limb(g,{x:-14, y:122, len:28, w:12, rot: 8, ...lc, foot});
    limb(g,{x: 14, y:122, len:28, w:12, rot:-8, ...lc, foot});
    blocks(g, ['GG','GG','WW','WW','WW','WW','WW'], 36, PAL);
    decal(g, -36, -54, 72, 180, 19,
      rbrow(7, 96) + rbrow(39, 96) +
      lens({x:7,  y:108, w:26, rim:'#3fae49', bw:4, lid:'#f2f3f5', m:.4}) +
      lens({x:39, y:108, w:26, rim:'#3fae49', bw:4, lid:'#f2f3f5', m:.4}) +
      bridge(31, 119, 10, '#3fae49') +
      mouth({top:140, w:34, h:18, lip:'#2f7d2a', bw:3, tongue:true}));
    const sk = el('div','cube board',b,'left:0;top:174px');
    box(sk, 116, 8, 34, {front:RAINBOW_STRIPE, top:RAINBOW_STRIPE, sides:'#e8262b',
                         base:'#d9dde3', light:'#ffffff', dark:'#8a8f98'}, 0, 0, 4);
    for (const x of [-38, 38]) for (const z of [-12, 12]){
      const wz = el('div','cube',sk,`left:0;top:0;transform:translateZ(${z}px)`);
      box(wz, 11, 11, 7, {base:'#e6e9ee', light:'#ffffff', dark:'#a9b0ba'}, x, 10, 5);
    }
  }},

  /* ---------- 15（10 排成台阶 + 5 块蓝色竖列）【按截图】 ---------- */
  { n:15, color:'#d0202e', split:'#22b8d4', top:260, sh:136, shw:200, build(b){
    const lc   = {color:'#26357a', dark:'#161f52'};
    const hand = {w:15, h:15, color:'#26357a', light:'#3f52a0'};
    const foot = {w:20, h:11, color:'#26357a', light:'#3f52a0'};
    num(b,'15',40,-168,0,80);
    limb(b,{x:-100, y:66, len:24, w:13, rot: 75, ...lc, fore:{len:20, rot:-80}, foot:hand});  // 左端往下勾
    limb(b,{x: 100, y:58, len:24, w:13, rot:-70, ...lc, fore:{len:20, rot: 50}, foot:hand});  // 蓝列右侧
    limb(b,{x: 30, y:96, len:24, w:13, rot: 3, ...lc, foot});
    limb(b,{x: 64, y:96, len:24, w:13, rot:-3, ...lc, foot});
    blocks(b, ['....B','...WB','..WWB','.WWWB','WWWWB'], 40, PAL);
    decal(b, -100, -100, 200, 200, 21,
      // 深蓝尖刺面罩
      `<svg viewBox="0 0 46 30" width="46" height="30" style="position:absolute;left:117px;top:142px;overflow:visible">
         <path d="M2 28 L2 8 L8 14 L12 2 L17 11 L23 5 L29 11 L34 2 L38 14 L44 8 L44 28 Q23 22 2 28 Z"
               fill="#2a2f7a" stroke="#181c55" stroke-width="2" stroke-linejoin="round"/></svg>` +
      lens({x:122, y:153, w:15, rim:'#181c55', bw:2, lid:'#2a2f7a', m:.25}) +
      lens({x:143, y:153, w:15, rim:'#181c55', bw:2, lid:'#2a2f7a', m:.25}) +
      mouth({x:140, top:180, w:20, h:13, lip:'#f0506e', bw:3, tongue:true}));
  }},

  /* ---------- 16（4×4，底部 6 块紫色）【按截图】 ---------- */
  { n:16, color:'#d0202e', split:'#4a4589', top:255, sh:140, shw:210, build(b){
    const pur  = {base:'#5b4bb0', light:'#7f70d0', dark:'#3d3088'};
    const lc   = {color:'#2e2a6a', dark:'#1a1745'};
    const hand = {w:15, h:15, color:'#2e2a6a', light:'#4a4590'};
    const foot = {w:20, h:11, color:'#2e2a6a', light:'#4a4590'};
    num(b,'16',-20,-168,8,80);
    const g = el('div','cube',b,'left:0;top:0;transform:rotateZ(4deg)');
    limb(g,{x:-100, y:58, len:26, w:13, rot: 80, ...lc, fore:{len:22, rot:-40}, foot:hand});
    limb(g,{x: 100, y:58, len:26, w:13, rot:-80, ...lc, fore:{len:22, rot: 40}, foot:hand});
    limb(g,{x:-24, y:96, len:34, w:13, rot: 6, ...lc, foot});
    limb(g,{x: 24, y:96, len:34, w:13, rot:-6, ...lc, foot});
    blocks(g, ['WWWW','WWWW','WPPW','PPPP'], 50, {W:PAL.W, P:pur});
    decal(g, -100, -100, 200, 200, 26,
      lens({x:56,  y:106, w:38, h:36, r:10, rim:'#2e2470', bw:5, lid:pur.base, m:.45}) +
      lens({x:106, y:106, w:38, h:36, r:10, rim:'#2e2470', bw:5, lid:pur.base, m:.45}) +
      mouth({x:112, top:162, w:44, h:16, lip:'#b9a8f0', bw:3, rot:-6}));
  }},

  /* ---------- 17（彩虹 7 字形 + 10，画家）【按截图】 ---------- */
  { n:17, color:'#d0202e', top:270, sh:152, shw:110,
    split:'linear-gradient(180deg,#9a72a0 0 13px,#4a4589 13px 26px,#22b8d4 26px 39px,#4cb648 39px 52px,#f2e11c 52px 65px,#f7941d 65px 78px,#e8323f 78px)',
    build(b){
    const lc   = {color:'#6a3a9a', dark:'#45226a'};
    const hand = {w:14, h:14, color:'#6a3a9a', light:'#8a5aba'};
    const foot = {w:18, h:11, color:'#6a3a9a', light:'#8a5aba'};
    num(b,'17',-92,-192,0,80);
    limb(b,{x:-36, y:84, len:22, w:12, rot:  50, ...lc, fore:{len:20, rot:-100}, foot:hand});
    limb(b,{x: 36, y:56, len:30, w:12, rot:-105, ...lc, hand:PALETTE, still:true});   // 拿调色板
    limb(b,{x:-12, y:122, len:26, w:12, rot: 3, ...lc, foot});
    limb(b,{x: 12, y:122, len:26, w:12, rot:-3, ...lc, foot});
    blocks(b, ['...V','YGBI','OWW.','RWW.','.WW.','.WW.','.WW.'], 36,
      {W:PAL.W, V:RAIN[0], I:RAIN[1], B:RAIN[2], G:RAIN[3], Y:RAIN[4], O:RAIN[5], R:RAIN[6]});
    decal(b, -36, -54, 72, 180, 19,
      [[8,6,'#3fa9f5'],[48,8,'#58bf45'],[46,44,'#7a3fb0'],[46,80,'#e8262b'],[8,84,'#7a3fb0'],[48,96,'#58bf45'],[6,164,'#f7941d']]
        .map(([x, y, c]) => splat(x, y, c)).join('') +
      lens({x:6,  y:116, w:26, rim:'#7a3fb0', bw:4, lid:'#f2f3f5', m:.35}) +
      lens({x:40, y:116, w:26, rim:'#7a3fb0', bw:4, lid:'#f2f3f5', m:.35}) +
      bridge(30, 127, 12, '#7a3fb0') +
      mouth({top:148, w:28, h:12, lip:'#7a3fb0', bw:2}));
  }},

  /* ---------- 18（10 + 右列 5 粉 + 底排 3 粉）【按截图】 ---------- */
  { n:18, color:'#d0202e', split:'#e8457f', top:262, sh:158, shw:150, build(b){
    const lc   = {color:'#7a2a7a', dark:'#521a52'};
    const hand = {w:14, h:14, color:'#7a2a7a', light:'#9a4a9a'};
    const shoe = {w:22, h:12, color:'#e8409a', light:'#ff7dc2'};
    num(b,'18',-10,-205,10,80);
    const g = el('div','cube',b,'left:0;top:0;transform:rotateZ(6deg)');
    limb(g,{x:-66, y:20, len:28, w:12, rot:130, ...lc, fore:{len:22, rot:70}, foot:hand});   // 往上弯
    limb(g,{x: 66, y:50, len:30, w:12, rot:-30, ...lc, foot:hand});
    limb(g,{x:-22, y:128, len:24, w:12, rot: 8, ...lc, foot:shoe});
    limb(g,{x: 22, y:128, len:24, w:12, rot:-8, ...lc, foot:shoe});
    blocks(g, ['WWK','WWK','WWK','WWK','WWK','KKK'], 44, PAL);
    decal(g, -66, -132, 88, 220, 23,
      `<div style="position:absolute;left:36px;top:157px;width:18px;height:4px;border-radius:2px;background:#5a1f5a;transform:rotate(-12deg)"></div>
       <div style="position:absolute;left:62px;top:157px;width:18px;height:4px;border-radius:2px;background:#5a1f5a;transform:rotate(12deg)"></div>` +
      lens({x:34, y:166, w:22, h:24, r:6, rim:'#5a1f5a', bw:4, lid:'#7a2a7a', m:.3, half:true}) +
      lens({x:60, y:166, w:22, h:24, r:6, rim:'#5a1f5a', bw:4, lid:'#7a2a7a', m:.3, half:true}) +
      mouth({x:22, top:194, w:18, h:12, lip:'#f08aa8', bw:3, rot:12}));
  }},

  /* ---------- 19（1×10 白 + 1×9 灰）【按截图】 ---------- */
  { n:19, color:'#d0202e', top:265, sh:176, shw:90,
    split:'linear-gradient(180deg,#d4d6d5 0 30px,#b0b3b2 30px 60px,#8e9291 60px)',
    build(b){
    const lc   = {color:'#2a2a2a', dark:'#111111'};
    const hand = {w:11, h:11, color:'#2a2a2a', light:'#555555'};
    const foot = {w:16, h:9,  color:'#2a2a2a', light:'#555555'};
    num(b,'19',-55,-212,0,80);
    limb(b,{x:-30, y:104, len:32, w:8, rot: 18, ...lc, foot:hand});
    limb(b,{x: 30, y:104, len:32, w:8, rot:-18, ...lc, foot:hand});
    limb(b,{x:-12, y:148, len:22, w:9, rot: 2, ...lc, foot});
    limb(b,{x: 12, y:148, len:22, w:9, rot:-2, ...lc, foot});
    const pal = {W:PAL.W};
    greyRamp(9).forEach((c, i) => pal[i+1] = c);
    blocks(b, ['W.', ...Array.from({length:9}, (_, i) => 'W' + (i+1))], 30, pal);
    decal(b, -30, -150, 60, 300, 16,
      `<svg width="60" height="8" viewBox="0 0 60 8" style="position:absolute;left:0;top:240px;overflow:visible">
         <g fill="none" stroke="#777" stroke-width="2" stroke-linecap="round">
           <path d="M7 6 q3 -4 6 0 t6 0"/><path d="M37 6 q3 -4 6 0 t6 0"/></g></svg>` +
      lens({x:5,  y:249, w:20, rim:'#222', bw:3, lid:'#f2f3f5', m:.3}) +
      lens({x:35, y:249, w:20, rim:'#222', bw:3, lid:'#d8dadc', m:.3}) +
      mouth({x:30, top:276, w:18, h:9, lip:'#333', bw:2}));
  }},

  /* ---------- 20（2×10 浅橙，礼帽 + 拐杖）【按截图】 ---------- */
  { n:20, color:'#f28c28', split:'#ecc283', top:265, sh:170, shw:100, build(b){
    const T    = {base:'#fcdcab', light:'#fff0d6', line:'#f2c48a', outline:'#f28c28', side:{base:'#f6b766', dark:'#d98a30'}};
    const lc   = {color:'#c0601e', dark:'#8a3e0e'};
    const hand = {w:12, h:12, color:'#c0601e', light:'#e08a4a'};
    const shoe = {w:20, h:10, color:'#4a2a1a', light:'#7a4a2a'};
    const hat  = {base:'#7a3f9a', light:'#9a5aba', dark:'#4f2468'};
    num(b,'20',0,-208,0,80);
    const g = el('div','cube',b,'left:0;top:0;transform:rotateZ(-5deg)');
    // 歪戴的紫色礼帽
    const h = el('div','cube',g,'left:-14px;top:-140px;transform:rotateZ(-15deg)');
    box(h, 46, 5, 34, hat, 0, -2, 3);                                                  // 帽檐
    box(h, 28, 26, 22, hat, 0, -17, '4px 4px 2px 2px');                                // 帽身
    box(h, 29, 5, 23, {base:'#3a1a50', light:'#4a2a60', dark:'#2a0f3a'}, 0, -7, 1);   // 帽带
    // 手 + 拐杖
    limb(g,{x:-28, y:70, len:28, w:9, rot: 25, ...lc, foot:hand});
    limb(g,{x: 28, y:70, len:28, w:9, rot:-25, ...lc, foot:hand});
    limb(g,{x:-40, y:95, len:76, w:4, rot:-4, color:'#3a3a3a', dark:'#111111'});
    crossed(g, -40, 86, 10, 10, `<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="5" fill="#cfd4da"/></svg>`);
    limb(g,{x:-10, y:138, len:24, w:9, rot: 3, ...lc, foot:shoe});
    limb(g,{x: 10, y:138, len:24, w:9, rot:-3, ...lc, foot:shoe});
    blocks(g, Array(10).fill('TU'), 28, {T, U:T});
    decal(g, -28, -140, 56, 280, 15,
      `<div style="position:absolute;left:5px;top:197px;width:18px;height:4px;border-radius:2px;background:#8e3e91;transform:rotate(-10deg)"></div>
       <div style="position:absolute;left:33px;top:197px;width:18px;height:4px;border-radius:2px;background:#8e3e91;transform:rotate(10deg)"></div>` +
      lens({x:5,  y:206, w:20, rim:'#8e3e91', bw:2, lid:'#c88ad0', m:.25, half:true}) +
      lens({x:31, y:206, w:20, rim:'#8e3e91', bw:2, lid:'#c88ad0', m:.25, half:true}) +
      mouth({x:28, top:232, w:14, h:7, lip:'#c0507e', bw:2}) +
      `<svg width="20" height="10" viewBox="0 0 20 10" style="position:absolute;left:18px;top:248px;overflow:visible">
         <path d="M0 0 L9 4 L0 10 Z M20 0 L11 4 L20 10 Z" fill="#fff" stroke="#d9a060" stroke-width="1"/>
         <circle cx="10" cy="5" r="2.2" fill="#fff" stroke="#d9a060" stroke-width="1"/></svg>`);
  }},
];

/* ================= 数字词表（原生 TTS 用：先中文后英文） ================= */
const NUM_EN = ['one','two','three','four','five','six','seven','eight','nine','ten',
  'eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen','twenty']
const NUM_ZH = ['一','二','三','四','五','六','七','八','九','十',
  '十一','十二','十三','十四','十五','十六','十七','十八','十九','二十']
