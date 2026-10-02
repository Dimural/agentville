// Shared plumbing for the golden-fixture exporters: pull code out of the owner's local prototype,
// run it unmodified on a real canvas in headless Chrome, and read the result back.
// See docs/reference/README.md#how-to-regenerate-fixtures-from-the-prototype.
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

/** Parses `[prototype.html] [--chrome path]`. */
export function cli(argv = process.argv.slice(2)) {
  const args = [...argv];
  const at = args.indexOf('--chrome');
  const chrome = at >= 0 ? args.splice(at, 2)[1] : '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const html = readFileSync(resolve(args[0] ?? join(repo, 'Pixel Crew.html')), 'utf8');
  return { chrome, html };
}

/** The prototype's source between two comment markers (start inclusive, end exclusive). */
export function section(html, startMarker, endMarker) {
  const start = html.indexOf(startMarker), end = html.indexOf(endMarker, start);
  if (start < 0 || end < 0) throw new Error(`prototype markers not found: ${startMarker} … ${endMarker}`);
  return html.slice(start, end);
}

/** One whole line of the prototype, found by its start (e.g. "function deskUnits("). */
export function line(html, prefix) {
  const i = html.indexOf('\n' + prefix);
  if (i < 0) throw new Error(`prototype line not found: ${prefix}`);
  return html.slice(i + 1, html.indexOf('\n', i + 1));
}

/** Replaces exactly one occurrence, so a changed prototype fails loudly instead of silently. */
export function patch(code, from, to) {
  if (code.split(from).length !== 2) throw new Error(`patch target not found exactly once: ${from}`);
  return code.replace(from, to);
}

/**
 * In-page helpers. `encode(canvas, pal)` → rows of palette characters ('.' = transparent), growing
 * `pal` (Map hex → char). `rle(rows)` → each row as char+count runs, e.g. "a12.3b1".
 */
export const PAGE_HELPERS = `
const CHARS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!$%&*+-/:;<=>?@^_~';
function encode(canvas, pal, x = 0, y = 0, w = canvas.width, h = canvas.height){
  const d = canvas.getContext('2d').getImageData(x, y, w, h).data, rows = [];
  for (let yy = 0; yy < h; yy++){
    let row = '';
    for (let xx = 0; xx < w; xx++){
      const i = (yy*w + xx) * 4;
      if (d[i+3] === 0){ row += '.'; continue; }
      if (d[i+3] !== 255) throw new Error('partially transparent pixel at ' + xx + ',' + yy);
      const hex = toHex(d[i], d[i+1], d[i+2]);
      if (!pal.has(hex)){ if (pal.size >= CHARS.length) throw new Error('palette overflow'); pal.set(hex, CHARS[pal.size]); }
      row += pal.get(hex);
    }
    rows.push(row);
  }
  return rows;
}
function rle(rows){
  return rows.map(r => { let out = ''; for (let i = 0; i < r.length;){ let j = i; while (j < r.length && r[j] === r[i]) j++; out += r[i] + (j - i); i = j; } return out; });
}
const palObj = pal => Object.fromEntries([...pal].map(([hex, ch]) => [ch, hex]));
`;

// Headless Chrome prints the DOM promptly but can linger afterwards (updater, crashpad), so stop it
// as soon as the document is complete. Fail after 60 s.
function dumpDom(chrome, file, profile) {
  return new Promise((ok, fail) => {
    const p = spawn(chrome, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
                             `--user-data-dir=${profile}`, '--dump-dom', `file://${file}`], { stdio: ['ignore', 'pipe', 'ignore'] });
    let out = '', settled = false;
    const done = (err) => {
      if (settled) return;
      settled = true; clearTimeout(timer); p.kill('SIGKILL');
      err ? fail(err) : ok(out);
    };
    const timer = setTimeout(() => done(new Error('headless Chrome timed out')), 60000);
    p.stdout.setEncoding('utf8');
    p.stdout.on('data', d => { out += d; if (out.includes('</html>')) done(); });
    p.on('error', done);
    p.on('exit', () => out.includes('</html>') ? done() : done(new Error('Chrome exited without output')));
  });
}

/** Runs `code` in a page (strict-mode function scope). The code must call `emit(object)` once. */
export async function runInChrome(chrome, code) {
  const page = `<!doctype html><meta charset="utf-8"><pre id="out">FAILED</pre>
<script>
window.onerror = (m) => { document.getElementById('out').textContent = 'ERROR ' + m; };
(() => { "use strict";
const emit = o => { document.getElementById('out').textContent = btoa(JSON.stringify(o)); };
${code}
})();
</script>`;
  const dir = mkdtempSync(join(tmpdir(), 'agentville-fixtures-'));
  try {
    const file = join(dir, 'harness.html');
    writeFileSync(file, page);
    const dom = await dumpDom(chrome, file, join(dir, 'profile'));
    const m = dom.match(/<pre id="out">([^<]*)<\/pre>/);
    if (!m || !/^[A-Za-z0-9+/=]+$/.test(m[1])) throw new Error('harness failed: ' + (m ? m[1].slice(0, 300) : dom.slice(0, 300)));
    return JSON.parse(Buffer.from(m[1], 'base64').toString('utf8'));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
