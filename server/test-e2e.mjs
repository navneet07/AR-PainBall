// End-to-end server smoke test. Reveals if server's match lifecycle works
// for a single player using force-start (solo AR mode).

import WS from 'ws';

const WS_URL = 'ws://127.0.0.1:8200/ws?role=player';
const events = [];
const log = (who, msg) => {
  const summary = msg.type
                  + (msg.state ? ' · phase=' + msg.state.phase + ' · players=' + msg.state.players.length : '')
                  + (msg.winnerId ? ' · winner=' + msg.winnerId.slice(0,8) : '')
                  + (msg.damage ? ' · dmg=' + msg.damage : '')
                  + (msg.error ? ' · ERROR=' + msg.error : '')
                  + (msg.you ? ' · you=' + msg.you.name + '/' + msg.you.bibId : '');
  events.push(`[${who}] ${summary}`);
  console.log(`[${who}] ${summary}`);
};

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

console.log('\n════ GhostPaint · end-to-end solo match test ════\n');

const p1 = new WS(WS_URL);
p1.on('message', (d) => log('P1', JSON.parse(d)));
p1.on('error', (e) => console.log('[P1] error:', e.message));
p1.on('open', () => console.log('[P1] socket open'));
p1.on('close', () => console.log('[P1] socket closed'));

// Wait for socket open
await sleep(300);

// Join
console.log('\n→ P1 sends: join');
p1.send(JSON.stringify({ type: 'join', name: 'TestA' }));
await sleep(400);

// Force start (solo)
console.log('\n→ P1 sends: force_start');
p1.send(JSON.stringify({ type: 'force_start' }));

// Wait for countdown (5s) + game_start
console.log('\n-- waiting 6s for countdown + game_start --\n');
await sleep(6200);

// Fire some shots (target null = miss, no opponent)
console.log('\n→ P1 fires 3 blanks');
for (let i = 0; i < 3; i++) {
  p1.send(JSON.stringify({ type: 'fire', targetBib: null }));
  await sleep(300);
}

await sleep(500);

console.log('\n════ FINAL EVENT SEQUENCE ════');
events.forEach(e => console.log(' ', e));

console.log('\n════ EXPECTED ════');
console.log('  joined · state:lobby · state:countdown · game_start · state:playing · shot_missed × 3 · state:playing');

const phases = events.filter(e => e.includes('phase=')).map(e => e.match(/phase=(\w+)/)[1]);
const phaseTransitions = [...new Set(phases)].join(' → ');
console.log('\n  phase transitions: ' + phaseTransitions);

const hasGameStart = events.some(e => e.includes('game_start'));
const hasPlaying = phases.includes('playing');
console.log('\n  game_start broadcast: ' + (hasGameStart ? '✓' : '✗'));
console.log('  reached phase=playing: ' + (hasPlaying ? '✓' : '✗'));

p1.close();
await sleep(200);
process.exit(hasGameStart && hasPlaying ? 0 : 1);
