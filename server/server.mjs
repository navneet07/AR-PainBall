// ═══════════════════════════════════════════════════════════
//  GhostPaint · game server
//  Node.js · WebSocket (ws) · Bonjour broadcast
//  Port :8200 (Arky owns :8090)
// ═══════════════════════════════════════════════════════════

import http from 'http';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import { WebSocketServer } from 'ws';
import {
  newState, addPlayer, removePlayer, publicState, publicPlayer,
  allReady, startCountdown, startMatch, endMatch, resetToLobby,
  handleFire, forceStart, CONFIG,
} from './game.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.GHOSTPAINT_PORT || 8200);
const STATE = newState();

// ─── HTTP server · serves admin + fake-client + static ──────
const server = http.createServer((req, res) => {
  let file = req.url === '/' ? '/admin.html' : req.url;
  // strip query string
  file = file.split('?')[0];
  const full = path.join(__dirname, file);
  // sandbox: never escape server/
  if (!full.startsWith(__dirname)) { res.writeHead(403); return res.end('nope'); }
  fs.readFile(full, (err, data) => {
    if (err) { res.writeHead(404); return res.end('not found'); }
    const ext = path.extname(file);
    const mime = {
      '.html': 'text/html; charset=utf-8',
      '.css':  'text/css',
      '.js':   'application/javascript',
      '.json': 'application/json',
      '.svg':  'image/svg+xml',
    }[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': mime, 'Cache-Control': 'no-store' });
    res.end(data);
  });
});

// ─── WebSocket ──────────────────────────────────────────────
const wss = new WebSocketServer({ server, path: '/ws' });

function send(ws, msg) {
  if (ws.readyState !== ws.OPEN) return;
  try { ws.send(JSON.stringify(msg)); } catch {}
}

function broadcast(msg) {
  for (const p of STATE.players.values()) send(p.ws, msg);
  for (const s of SPECTATORS) send(s, msg);
}

function sendTo(playerId, msg) {
  const p = STATE.players.get(playerId);
  if (p) send(p.ws, msg);
}

function publishLobby() {
  broadcast({ type: 'state', state: publicState(STATE) });
}

// Spectator connections (admin page)
const SPECTATORS = new Set();

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://x');
  const role = url.searchParams.get('role') || 'player';
  const remote = req.socket.remoteAddress || '?';
  console.log(`[WS] ${role} connected from ${remote}`);

  if (role === 'spectator') {
    SPECTATORS.add(ws);
    send(ws, { type: 'state', state: publicState(STATE) });
    ws.on('close', () => {
      SPECTATORS.delete(ws);
      console.log(`[WS] spectator disconnected from ${remote}`);
    });
    return;
  }

  // ─── player connection ──────────────────────────────────
  let playerId = null;

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch (e) {
      console.log(`[WS] ${remote} bad JSON: ${raw.toString().slice(0, 80)}`);
      return;
    }
    console.log(`[WS] ${remote} msg.type=${msg.type}${msg.name ? ' name=' + msg.name : ''}`);

    switch (msg.type) {
      case 'join': {
        const { ok, player, error } = addPlayer(STATE, ws, msg.name);
        if (!ok) return send(ws, { type: 'error', error });
        playerId = player.id;
        send(ws, { type: 'joined', you: publicPlayer(player) });
        publishLobby();
        break;
      }

      case 'ready': {
        if (!playerId) return;
        const p = STATE.players.get(playerId);
        if (!p) return;
        p.ready = !!msg.ready;
        publishLobby();
        if (STATE.phase === 'lobby' && allReady(STATE)) {
          kickoffCountdown();
        }
        break;
      }

      case 'force_start': {
        // Solo / test mode — bypass the min-2 "all ready" gate
        if (!playerId) return;
        if (!forceStart(STATE)) return;
        console.log(`[FORCE-START] by ${playerId}`);
        // mark requester as ready for stats accuracy
        const p = STATE.players.get(playerId);
        if (p) p.ready = true;
        kickoffCountdown();
        break;
      }

      case 'reset_lobby': {
        // Kick everyone out of 'ended' back to 'lobby' for another round
        if (STATE.phase === 'ended') {
          resetToLobby(STATE);
          publishLobby();
        }
        break;
      }

      case 'fire': {
        if (!playerId) return;
        const msgs = handleFire(STATE, playerId, {
          targetBib: msg.targetBib || null,
          worldPos: msg.worldPos || null,
        });
        for (const { scope, playerId: pid, msg: m } of msgs) {
          if (scope === 'self') sendTo(pid, m);
          else broadcast(m);
        }
        if (msgs.length) publishLobby();
        break;
      }

      case 'position': {
        if (!playerId) return;
        const p = STATE.players.get(playerId);
        if (!p) return;
        p.position = { lat: msg.lat, lng: msg.lng, heading: msg.heading };
        // Broadcast sparingly to avoid flooding
        if (!p._lastPosBroadcast || Date.now() - p._lastPosBroadcast > 500) {
          p._lastPosBroadcast = Date.now();
          broadcast({ type: 'position', playerId, ...p.position });
        }
        break;
      }

      case 'leave': {
        if (playerId) {
          removePlayer(STATE, playerId);
          publishLobby();
          playerId = null;
        }
        break;
      }
    }
  });

  ws.on('close', () => {
    console.log(`[WS] player disconnected from ${remote}${playerId ? ' (was player ' + playerId.slice(0,8) + ')' : ''}`);
    if (playerId) {
      removePlayer(STATE, playerId);
      publishLobby();
    }
  });
});

function kickoffCountdown() {
  startCountdown(STATE);
  publishLobby();
  setTimeout(() => {
    startMatch(STATE);
    broadcast({ type: 'game_start' });
    publishLobby();
    scheduleMatchEnd();
  }, CONFIG.countdownSec * 1000);
}

let _matchTimer = null;
function scheduleMatchEnd() {
  clearTimeout(_matchTimer);
  _matchTimer = setTimeout(() => {
    if (STATE.phase !== 'playing') return;
    // Winner = highest kill count, tie-break = fewest deaths
    const players = [...STATE.players.values()];
    players.sort((a, b) => (b.kills - a.kills) || (a.deaths - b.deaths));
    const winner = players[0]?.id || null;
    endMatch(STATE, winner);
    broadcast({ type: 'game_end', reason: 'time_up', winnerId: winner });
    publishLobby();
  }, CONFIG.matchDurationMs);
}

// ─── Bonjour · advertise to iOS clients ─────────────────────
try {
  const { Bonjour } = await import('bonjour-service');
  const bj = new Bonjour();
  bj.publish({
    name: `GhostPaint · ${os.hostname()}`,
    type: 'ghostpaint',
    port: PORT,
    txt: { version: '0.1.0' },
  });
  console.log(`[BONJOUR] advertising _ghostpaint._tcp.local. on :${PORT}`);
} catch (e) {
  console.log(`[BONJOUR] unavailable (${e.message.slice(0, 60)}) — iOS clients will need manual IP entry`);
}

// ─── start ──────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
  const ifaces = Object.entries(os.networkInterfaces())
    .flatMap(([name, addrs]) => (addrs || [])
      .filter(a => a.family === 'IPv4' && !a.internal)
      .map(a => ({ name, addr: a.address })));
  console.log('');
  console.log('════════════════════════════════════════════════════════════');
  console.log('  G H O S T P A I N T · game server');
  console.log('════════════════════════════════════════════════════════════');
  console.log(`  Listening on  :${PORT}`);
  for (const { name, addr } of ifaces) {
    console.log(`    • ${name.padEnd(8)} http://${addr}:${PORT}/admin.html`);
  }
  console.log('');
  console.log(`  Admin/spectator :  http://localhost:${PORT}/admin.html`);
  console.log(`  Fake client     :  http://localhost:${PORT}/fake-client.html`);
  console.log(`  WebSocket       :  ws://<ip>:${PORT}/ws?role=player`);
  console.log('════════════════════════════════════════════════════════════');
  console.log('');
});
