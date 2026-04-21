// 3-player smoke test. Verifies server handles lobby + match + hit arbitration
// with three concurrent clients.

import WS from 'ws';
const WS_URL = 'ws://127.0.0.1:8200/ws?role=player';
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const players = ['Alice', 'Bob', 'Charlie'];
const sockets = {};
const me = {};

for (const name of players) {
  const ws = new WS(WS_URL);
  sockets[name] = ws;
  ws.on('message', (d) => {
    const m = JSON.parse(d);
    if (m.type === 'joined') {
      me[name] = m.you;
      console.log(`  [${name}] joined · bib=${m.you.bibId} (${m.you.bibName})`);
    } else if (m.type === 'state') {
      // uncomment to see all state messages: console.log(`  [${name}] state phase=${m.state.phase} players=${m.state.players.length}`);
    } else if (m.type === 'game_start') {
      console.log(`  [${name}] 🟢 GAME_START`);
    } else if (m.type === 'hit') {
      const sh = players.find(n => me[n]?.id === m.shooterId);
      const vi = players.find(n => me[n]?.id === m.victimId);
      console.log(`  [${name}] 💥 ${sh}→${vi} dmg=${m.damage} hp=${m.hp}`);
    } else if (m.type === 'kill') {
      const sh = players.find(n => me[n]?.id === m.shooterId);
      const vi = players.find(n => me[n]?.id === m.victimId);
      console.log(`  [${name}] 💀 ${sh} KILLED ${vi}`);
    } else if (m.type === 'damage') {
      console.log(`  [${name}] 🩸 took dmg, hp=${m.hp}`);
    } else if (m.type === 'respawn') {
      const who = players.find(n => me[n]?.id === m.playerId);
      console.log(`  [${name}] 🔄 ${who} respawned`);
    } else if (m.type === 'game_end') {
      const winner = players.find(n => me[n]?.id === m.winnerId) || 'nobody';
      console.log(`  [${name}] 🏆 MATCH END · winner=${winner}`);
    }
  });
}

await sleep(500);  // all sockets open

console.log('\n── all 3 joining lobby ──');
for (const name of players) sockets[name].send(JSON.stringify({ type: 'join', name }));
await sleep(400);

console.log('\n── all 3 tapping Ready ──');
for (const name of players) sockets[name].send(JSON.stringify({ type: 'ready', ready: true }));
console.log('(server should detect all-ready, start 5s countdown)');
await sleep(6200);

console.log('\n── Alice fires 4× at Bob (4 hits × 25 = KILL) ──');
const bobBib = me['Bob']?.bibId;
for (let i = 0; i < 4; i++) {
  sockets['Alice'].send(JSON.stringify({ type: 'fire', targetBib: bobBib }));
  await sleep(350);
}
await sleep(800);

console.log('\n── Charlie fires 4× at Alice ──');
const aliceBib = me['Alice']?.bibId;
for (let i = 0; i < 4; i++) {
  sockets['Charlie'].send(JSON.stringify({ type: 'fire', targetBib: aliceBib }));
  await sleep(350);
}
await sleep(1000);

console.log('\n── close + report ──');
for (const name of players) sockets[name].close();
await sleep(300);
process.exit(0);
