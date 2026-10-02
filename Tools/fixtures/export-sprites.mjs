#!/usr/bin/env node
// Regenerates Tests/AgentvilleCoreTests/Fixtures/sprite-vectors.json from the owner's local prototype.
//
// The prototype's own `lookFor`, `sprite`, `drawChar`, `outline` and `drawEmote` run unmodified on a
// real browser canvas (headless Chrome), so the golden frames don't depend on any reimplementation.
// Never edit the fixture by hand (docs/reference/README.md#how-to-regenerate-fixtures-from-the-prototype).
//
// Usage: node Tools/fixtures/export-sprites.mjs ["Pixel Crew.html"] [--chrome /path/to/chrome]
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { cli, PAGE_HELPERS, repo, runInChrome, section } from './lib.mjs';

const { chrome, html } = cli();
const outPath = join(repo, 'Tests/AgentvilleCoreTests/Fixtures/sprite-vectors.json');
// The prototype's utils, palettes, looks, sprites and emotes.
const protoCode = section(html, '/* ---------- utils ---------- */', '/* ---------- world state ---------- */');

// Runs inside the page, after the prototype code, in the same scope.
const harness = `
const POSES = ['idle','walk','type','deskType','read','bash','search','web','think','wave','cheer','coffee','sleep','nap','dangle','dizzy','blink'];
const frames = p => p === 'walk' ? 4 : 2;

// Looks: one per (style, accessory) the generator can produce, which also covers every pattern.
const candidates = ['api-server','agentville','blog','ml-notebook','dotfiles','ios-app','infra','docs-site','payments','game-jam'];
for (let i = 0; i < 4000; i++) candidates.push('project-' + i);
const chosen = new Map();
for (const name of candidates){
  const L = lookFor(name), k = L.style + '/' + L.acc;
  if (!chosen.has(k)) chosen.set(k, name);
}
const names = [...chosen.values()];
for (const p of ['plain','stripe','pocket','hood'])
  if (!names.some(n => lookFor(n).pattern === p)) throw new Error('no look with pattern ' + p);

const looksOut = [];
for (const name of names){
  const L = lookFor(name), pal = new Map(), sprites = [];
  for (const pose of POSES) for (let f = 0; f < frames(pose); f++)
    sprites.push({ pose, frame: f, highlight: false, rows: encode(sprite(L, pose, f, false), pal) });
  // Grab highlight (second outline) on a few poses for every look.
  for (const [pose, f] of [['idle',0],['dangle',1],['walk',2]])
    sprites.push({ pose, frame: f, highlight: true, rows: encode(sprite(L, pose, f, true), pal) });
  looksOut.push({ name, style: L.style, acc: L.acc, pattern: L.pattern, palette: palObj(pal), sprites });
}

// Emotes at scale 1: a 9x10 bubble. 'dots' at t = 0, 1/3, 2/3, 1 gives 0..3 dots.
const emotes = [], epal = new Map();
for (const [kind, t] of [['bang',0],['check',0],['heart',0],['quest',0],['dots',0],['dots',0.34],['dots',0.67],['dots',1.0]]){
  const c = document.createElement('canvas'); c.width = 9; c.height = 10;
  drawEmote(c.getContext('2d'), 4.5, 10, 1, kind, t);
  emotes.push({ kind, dots: kind === 'dots' ? Math.floor(t*3) % 4 : null, rows: encode(c, epal) });
}

const out = { generatedFrom: 'prototype lookFor/sprite/drawChar/outline/drawEmote on a headless Chrome canvas (Tools/fixtures/export-sprites.mjs)',
              poses: POSES, looks: looksOut, emotes: { palette: palObj(epal), items: emotes } };
emit(out);
`;

const page = `<!doctype html><meta charset="utf-8"><pre id="out">FAILED</pre>
<script>
window.onerror = (m) => { document.getElementById('out').textContent = 'ERROR ' + m; };
(() => { "use strict";
${protoCode}
${harness}
})();
</script>`;

const data = await runInChrome(chrome, protoCode + PAGE_HELPERS + harness);
{
  // One sprite per line, rows inline: compact, and each frame still diffs as ASCII art.
  const lines = ['{', `  "generatedFrom": ${JSON.stringify(data.generatedFrom)},`, `  "poses": ${JSON.stringify(data.poses)},`, '  "looks": ['];
  data.looks.forEach((L, li) => {
    lines.push('    {', `      "name": ${JSON.stringify(L.name)}, "style": "${L.style}", "acc": "${L.acc}", "pattern": "${L.pattern}",`,
               `      "palette": ${JSON.stringify(L.palette)},`, '      "sprites": [');
    L.sprites.forEach((s, si) => lines.push(`        {"pose": "${s.pose}", "frame": ${s.frame}, "highlight": ${s.highlight}, "rows": ${JSON.stringify(s.rows)}}${si < L.sprites.length - 1 ? ',' : ''}`));
    lines.push('      ]', `    }${li < data.looks.length - 1 ? ',' : ''}`);
  });
  lines.push('  ],', '  "emotes": {', `    "palette": ${JSON.stringify(data.emotes.palette)},`, '    "items": [');
  data.emotes.items.forEach((e, i) => lines.push(`      {"kind": "${e.kind}", "dots": ${e.dots}, "rows": ${JSON.stringify(e.rows)}}${i < data.emotes.items.length - 1 ? ',' : ''}`));
  lines.push('    ]', '  }', '}', '');
  writeFileSync(outPath, lines.join('\n'));
  const n = data.looks.reduce((a, L) => a + L.sprites.length, 0);
  console.log(`wrote ${outPath}: ${data.looks.length} looks, ${n} sprites, ${data.emotes.items.length} emotes`);
}
