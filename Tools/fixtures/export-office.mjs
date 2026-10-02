#!/usr/bin/env node
// Regenerates Tests/AgentvilleCoreTests/Fixtures/office-vectors.json from the owner's local prototype.
//
// Runs the prototype's own `drawOffice` and `screenFor` unmodified on a real canvas in headless Chrome.
// Only two inputs are pinned, by exact text patches: the theme (`isDark()`) and the wall clock (`new Date()`).
//
// Output:
//   screens: every monitor state × 24 animation steps (t = 0, 0.25 … 5.75), 32×20 px, RLE text rows
//   frames:  whole 432×272 px office frames (2 scenes × day/night × 3 times), palette-indexed bytes,
//            raw-deflated and base64-encoded (too many colours for one character per pixel)
//
// Usage: node Tools/fixtures/export-office.mjs ["Pixel Crew.html"] [--chrome /path/to/chrome]
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { deflateRawSync } from 'node:zlib';
import { cli, line, PAGE_HELPERS, patch, repo, runInChrome, section } from './lib.mjs';

const { chrome, html } = cli();
const outPath = join(repo, 'Tests/AgentvilleCoreTests/Fixtures/office-vectors.json');

const core = section(html, '/* ---------- utils ---------- */', '/* ---------- world state ---------- */');
let office = section(html, '/* ---------- office (inside the crew window) ---------- */', '/* ---------- window list');
office = patch(office, 'const night = isDark();', 'const night = NIGHT;');
office = patch(office, 'const d = new Date()', 'const d = CLOCK');

// The office reads a few world-state globals; give it a stage of its own.
const shims = `
${line(html, 'const DESKS =')}
${line(html, 'function deskUnits(')}
${line(html, 'const CONF =')}
const $ = () => ({ hidden: true, textContent: '' });
const officeC = document.createElement('canvas'); officeC.width = 432; officeC.height = 272;
const og = officeC.getContext('2d');
let NIGHT = false, CLOCK = new Date(2026, 9, 2, 10, 8), released = false;
const ents = new Map();
const sessions = [];
`;

const harness = `
const mk = (id, name, status, act, sub) => ({ id, name, look: lookFor(name), status, act, sub: !!sub });

// --- screens: screenFor alone, drawn at (0, 0) on a 32×20 canvas ---
const SCREEN_KINDS = [
  ['away', null], ['waiting', null], ['done', null], ['idle', null],
  ['working', 'edit'], ['working', 'read'], ['working', 'bash'], ['working', 'search'], ['working', 'web'], ['working', 'think'],
];
const spal = new Map(), screens = [];
const sc = document.createElement('canvas'); sc.width = 32; sc.height = 20;
const sctx = sc.getContext('2d');
for (const [status, act] of SCREEN_KINDS){
  const s = status === 'away' ? null : mk(3, 'blog', status, act);
  const steps = [];
  for (let k = 0; k < 24; k++){
    sctx.clearRect(0, 0, 32, 20);
    // screenFor draws through U() on og; point og at the small canvas for the duration.
    const t = k / 4;
    drawScreenAt(sctx, s, t);
    steps.push(rle(encode(sc, spal)));
  }
  screens.push({ status, act, seed: 3 * 97, steps });
}
function drawScreenAt(ctx, s, t){
  const saved = ogRef.ctx; ogRef.ctx = ctx;
  try { screenFor(s, -39, 14, t); } finally { ogRef.ctx = saved; }
}
if ([...spal.values()].some(c => /[0-9]/.test(c))) throw new Error('screen palette too large for RLE');

// --- whole office frames ---
const SCENES = {
  working: [mk(1,'api-server','working','edit',true), mk(2,'agentville','working','read'), mk(3,'blog','working','bash'),
            mk(4,'ml-notebook','working','search'), mk(5,'dotfiles','working','web'), mk(6,'ios-app','working','think')],
  states:  [mk(1,'payments','waiting',null), mk(2,'docs-site','done',null), mk(3,'infra','idle',null), mk(4,'game-jam','working','edit',true)],
};
const AWAY = { states: [4] };   // game-jam is out roaming: empty chair, monitor keeps working
// Cloud x is fractional for most t (anti-aliased in the prototype); keep times where it lands on a whole pixel.
const cloudPx = t => (12 + ((30 + (t*1.2) % 30) % 34)) * 2;
const TIMES = [0, 1.25, 2.5, 3.75, 5, 6.25, 7.5, 10, 12.5].filter(t => Number.isInteger(cloudPx(t))).slice(0, 3);
if (TIMES.length < 3) throw new Error('not enough whole-pixel cloud times');
const CLOCKS = [[10, 8], [3, 47], [12, 0]];

const fpal = new Map(), frames = [];
for (const [scene, list] of Object.entries(SCENES)){
  for (const night of [false, true]){
    TIMES.forEach((t, ti) => {
      sessions.length = 0; sessions.push(...list);
      ents.clear(); for (const id of (AWAY[scene] || [])) ents.set(id, {});
      NIGHT = night; CLOCK = new Date(2026, 9, 2, CLOCKS[ti][0], CLOCKS[ti][1]);
      og.clearRect(0, 0, 432, 272);
      drawOffice(t);
      const d = og.getImageData(0, 0, 432, 272).data, idx = new Uint8Array(432 * 272);
      for (let i = 0; i < idx.length; i++){
        if (d[i*4+3] !== 255) throw new Error('office pixel not opaque at ' + i);
        const hex = toHex(d[i*4], d[i*4+1], d[i*4+2]);
        if (!fpal.has(hex)){ if (fpal.size >= 255) throw new Error('office palette overflow'); fpal.set(hex, fpal.size); }
        idx[i] = fpal.get(hex);
      }
      let bin = ''; for (let i = 0; i < idx.length; i += 0x8000) bin += String.fromCharCode.apply(null, idx.subarray(i, i + 0x8000));
      frames.push({ scene, night, t, clock: CLOCKS[ti], pixels: btoa(bin) });
    });
  }
}

emit({
  generatedFrom: 'prototype drawOffice/screenFor on a headless Chrome canvas (Tools/fixtures/export-office.mjs)',
  screens: { palette: palObj(spal), items: screens },
  scenes: Object.fromEntries(Object.entries(SCENES).map(([k, v]) => [k, v.map(s => ({ id: s.id, name: s.name, status: s.status, act: s.act, sub: s.sub, seed: s.id * 97, away: (AWAY[k] || []).includes(s.id) }))])),
  palette: [...fpal.keys()],
  frames,
});
`;

// screenFor/drawPatternU draw through U(), which closes over \`og\`. Route og through a switchable
// reference so screens can be drawn on their own small canvas.
let officeRouted = patch(office, 'function U(x, y, w, h, c){ og.fillStyle = c; og.fillRect(x*2, y*2, w*2, h*2); }',
  'function U(x, y, w, h, c){ const g = ogRef.ctx; g.fillStyle = c; g.fillRect(x*2, y*2, w*2, h*2); }');
const route = `const ogRef = { ctx: null };`;
const setRoute = `ogRef.ctx = og;`;

const data = await runInChrome(chrome, core + PAGE_HELPERS + shims + route + officeRouted + setRoute + harness);

// Frames: indices → raw deflate → base64 (Foundation's NSData zlib decompression reads raw deflate).
for (const f of data.frames) f.pixels = deflateRawSync(Buffer.from(f.pixels, 'base64'), { level: 9 }).toString('base64');

const lines = ['{', `  "generatedFrom": ${JSON.stringify(data.generatedFrom)},`,
  '  "screens": {', `    "palette": ${JSON.stringify(data.screens.palette)},`, '    "items": ['];
data.screens.items.forEach((s, i) => {
  lines.push(`      {"status": "${s.status}", "act": ${JSON.stringify(s.act)}, "seed": ${s.seed}, "steps": [`);
  s.steps.forEach((rows, k) => lines.push(`        ${JSON.stringify(rows)}${k < s.steps.length - 1 ? ',' : ''}`));
  lines.push(`      ]}${i < data.screens.items.length - 1 ? ',' : ''}`);
});
lines.push('    ]', '  },', `  "scenes": ${JSON.stringify(data.scenes)},`, `  "palette": ${JSON.stringify(data.palette)},`, '  "frames": [');
data.frames.forEach((f, i) => lines.push(`    ${JSON.stringify(f)}${i < data.frames.length - 1 ? ',' : ''}`));
lines.push('  ]', '}', '');
writeFileSync(outPath, lines.join('\n'));
console.log(`wrote ${outPath}: ${data.screens.items.length} screens × 24 steps, ${data.frames.length} frames (t = ${[...new Set(data.frames.map(f => f.t))].join(', ')}), ${data.palette.length} colours`);
