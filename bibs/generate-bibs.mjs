#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════
//  GhostPaint · bib generator
//
//  Outputs bibs.html — a printable page with 8 QR-coded bibs.
//  Each bib encodes "bib-01" through "bib-08" and has the
//  matching color band + name for easy player identification.
//
//  Usage:  node generate-bibs.mjs [--size 16]  (cm per bib)
//  Then:   open bibs.html in browser → print to A4/Letter → cut out → pin to shirt
// ═══════════════════════════════════════════════════════════

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BIBS = [
  { id: 'bib-01', name: 'Red Ghost',    color: '#ff3040' },
  { id: 'bib-02', name: 'Blue Ghost',   color: '#3080ff' },
  { id: 'bib-03', name: 'Green Ghost',  color: '#30d060' },
  { id: 'bib-04', name: 'Amber Ghost',  color: '#ffc030' },
  { id: 'bib-05', name: 'Cyan Ghost',   color: '#30d0d0' },
  { id: 'bib-06', name: 'Magenta Ghost',color: '#d030d0' },
  { id: 'bib-07', name: 'White Ghost',  color: '#f0f0f0' },
  { id: 'bib-08', name: 'Orange Ghost', color: '#ff7030' },
];

const sizeCm = Number(process.argv.includes('--size')
  ? process.argv[process.argv.indexOf('--size') + 1]
  : 16);

// Each bib page uses an <img> pointing at Google Chart API's QR
// service — no local QR library needed. For offline use, replace
// with a local npm qrcode render.
function qrURL(data, px) {
  return `https://api.qrserver.com/v1/create-qr-code/?size=${px}x${px}&data=${encodeURIComponent(data)}&margin=2`;
}

const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<title>GhostPaint · Bibs</title>
<style>
  @page { size: A4; margin: 10mm; }
  body { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
    background: #fff; color: #111; margin: 0; padding: 16px; }
  h1 { font-size: 16pt; color: #222; letter-spacing: 0.12em; }
  .intro { color: #555; font-size: 10pt; max-width: 700px; margin-bottom: 16px; }
  .sheet { display: grid; grid-template-columns: repeat(2, 1fr); gap: 14mm;
    page-break-inside: avoid; }
  .bib { border: 3px solid #000; padding: 10mm; text-align: center;
    page-break-inside: avoid; break-inside: avoid;
    width: ${sizeCm}cm; aspect-ratio: 1 / 1.25;
    display: flex; flex-direction: column; align-items: center; justify-content: space-between; }
  .color-band { width: 100%; height: 24mm; margin-bottom: 8mm;
    box-shadow: inset 0 0 0 3px #000; }
  .qr { width: 100%; max-width: ${sizeCm * 0.75}cm; height: auto; image-rendering: pixelated; }
  .label { margin-top: 6mm; font-weight: bold; font-size: 14pt; letter-spacing: 0.1em; }
  .id { font-size: 10pt; color: #555; margin-top: 3mm; letter-spacing: 0.14em; }
  .print-only { font-size: 9pt; color: #888; margin-top: 20px; }
  @media print { .intro, h1, .print-only { display: none; } }
</style>
</head>
<body>

<h1>GhostPaint · Player Bibs</h1>
<p class="intro">Print this on A4 or Letter. Cut each bib out. Pin to your shirt (front AND back if you want fair game).
Each bib encodes a unique ID the iOS app reads via the camera. Don't fold the QR — keep flat for reliable detection.</p>

<div class="sheet">
${BIBS.map(b => `
  <div class="bib">
    <div class="color-band" style="background:${b.color}"></div>
    <img class="qr" src="${qrURL(b.id, 400)}" alt="${b.id}"/>
    <div class="label">${b.name}</div>
    <div class="id">${b.id}</div>
  </div>
`).join('')}
</div>

<p class="print-only">${new Date().toISOString()} · GhostPaint v0.1</p>
</body>
</html>
`;

const outPath = path.join(__dirname, 'bibs.html');
fs.writeFileSync(outPath, html);
console.log(`✓ wrote ${outPath}`);
console.log(`  open bibs.html in a browser → ⌘P → print to A4`);
console.log(`  each bib: ${sizeCm} cm × ${(sizeCm * 1.25).toFixed(0)} cm`);
console.log(`  run again with --size 20 for larger bibs`);
