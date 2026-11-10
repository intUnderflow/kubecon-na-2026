#!/usr/bin/env node
// Regenerates the golden files for WebParityTest by running the web version's OWN routing code
// (path, route, lvStartNode, brgTo, dir8, r10, sliced verbatim out of reference/schedule.html).
// Needs a local copy of the original web version at reference/schedule.html (not in the public repo).
// Usage, from the Gradle root (android/):  node app/src/test/java/app/kcna26/route/golden/gen_web_golden.js
// Line formats:
//   web_routes.txt: from|to|totalM|levelsChanged|kinds|crc32(texts)|points
//   web_live.txt:   x|y|startNode|startKey|crc32(startText)|to|totalM|levelsChanged|kinds|crc32(texts)|points
// kinds: one letter per step (s start, w walk, u up, d down, e end); texts joined with "\n", CRC-32 of the UTF-8.
'use strict';
const fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '../../../../../../../../..'); // the repository root
const html = fs.readFileSync(path.join(root, 'reference/schedule.html'), 'utf8');
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
const app = scripts.find(s => s.includes('function lvStartNode'));
const geo = /GEO=(\{.*?\});/s.exec(scripts.find(s => s.includes('GEO=')))[1];
const cut = (from, to) => { const i = app.indexOf(from), j = app.indexOf(to, i); if (i < 0 || j < 0) throw new Error(from); return app.slice(i, j); };
// One deliberate difference: the app has no Google Maps button, so its outside-start step drops
// the web's last sentence and ends at "Head to the {entrance}, about N m {direction} of you."
const GMAPS = ' The Google Maps button above walks you there.';
const web = [cut('const R={', 'const SKIP_RE'), cut('const store=', 'window.__route=route;'), cut('const LAT0=', 'function lvStart(){'),
  cut('function lvStartNode(){', 'let lvRaf=0;')].join('\n');
if (web.split(GMAPS).length !== 2) throw new Error('Google Maps sentence not found exactly once in lvStartNode');
const src = web.replace(GMAPS, '');
const W = new Function(`"use strict"; const NATIVE=true; const GEO=${geo}; ${src}; return {route,lvStartNode,LV,GEO,AT};`)();
const crc = s => { let c = 0xFFFFFFFF; for (const b of Buffer.from(s, 'utf8')) { c ^= b; for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1; } return ((c ^ 0xFFFFFFFF) >>> 0).toString(16).padStart(8, '0'); };
const enc = r => [r.m.toFixed(3), r.dl, r.steps.map(s => s.k[0]).join(''), crc(r.steps.map(s => s.s).join('\n')), r.pts.length].join('|');
const rooms = Object.keys(W.GEO).filter(k => W.AT[k]);
const routes = [];
for (const f of ['E200S', 'EWT', 'EHY', 'E200W', ...rooms]) for (const t of rooms) routes.push(`${f}|${t}|${enc(W.route(f, t))}`);
const live = []; let i = 0;
for (let x = -480; x <= 300; x += 30) for (let y = -150; y <= 660; y += 30) {
  W.LV.pos = { x, y, acc: 10 }; const st = W.lvStartNode(), t = rooms[i++ % rooms.length];
  live.push(`${x}|${y}|${st.k}|${st.key}|${crc(st.s)}|${t}|${enc(W.route('LIVE', t))}`);
}
fs.writeFileSync(path.join(__dirname, 'web_routes.txt'), routes.join('\n') + '\n');
fs.writeFileSync(path.join(__dirname, 'web_live.txt'), live.join('\n') + '\n');
console.log(`wrote ${routes.length} routes and ${live.length} live starts`);
