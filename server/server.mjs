// ═══════════════════════════════════════════════════════════
//  GhostPaint · game server · v0.3 · room-code edition
//  Node.js · WebSocket (ws)
//  Port :8200
//
//  Protocol change vs v0.2:
//    - No more Bonjour / LAN discovery (public-internet deploy)
//    - Multi-room: every match lives in a 6-digit numeric room code
//    - Clients must send {create_room} or {join_room,code} before {ready}/{fire}
//    - Global admin at ws://.../ws?role=spectator
//    - Room-scoped admin at ws://.../ws?role=spectator&code=123456
// ═══════════════════════════════════════════════════════════

import http from 'http';
import fs from 'fs';
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

// ─── ROOMS ──────────────────────────────────────────────────
const ROOMS = new Map(); // code → Room
const ROOM_IDLE_TTL_MS = 60 * 60 * 1000; // 1h idle → GC

function genCode() {
  for (let i = 0; i < 100; i++) {
    const c = String(Math.floor(100000 + Math.random() * 900000));
    if (!ROOMS.has(c)) return c;
  }
  throw new Error('room-code exhaustion');
}

function createRoom() {
  const room = {
    code: genCode(),
    state: newState(),
    spectators: new Set(),
    createdAt: Date.now(),
    lastActiveAt: Date.now(),
    matchTimer: null,
  };
  ROOMS.set(room.code, room);
  METRICS.totalRoomsCreated++;
  return room;
}

function maybeGCRoom(room) {
  if (!room) return;
  if (room.state.players.size > 0 || room.spectators.size > 0) return;
  // grace period before removal
  setTimeout(() => {
    if (room.state.players.size === 0 && room.spectators.size === 0) {
      clearTimeout(room.matchTimer);
      ROOMS.delete(room.code);
      recordEvent('info', 'room', `room ${room.code} removed · empty`);
    }
  }, 30_000);
}

// Idle sweep every 5m
setInterval(() => {
  const cutoff = Date.now() - ROOM_IDLE_TTL_MS;
  for (const [code, room] of ROOMS) {
    if (room.lastActiveAt < cutoff && room.state.players.size === 0) {
      clearTimeout(room.matchTimer);
      ROOMS.delete(code);
      recordEvent('info', 'room', `room ${code} removed · idle`);
    }
  }
}, 5 * 60 * 1000);

// ─── GLOBAL METRICS · cross-room admin view ─────────────────
const METRICS = {
  startedAt: Date.now(),
  totalConnections: 0,
  totalRoomsCreated: 0,
  messagesReceived: 0,
  messagesPerSecond: 0,
  _recentMsgs: 0,
  lastMessageAt: 0,
  events: [],
};
function recordEvent(severity, source, text) {
  const evt = { ts: Date.now(), severity, source, text };
  METRICS.events.push(evt);
  if (METRICS.events.length > 200) METRICS.events.shift();
  for (const s of GLOBAL_SPECTATORS) send(s, { type: 'event', event: evt });
  for (const room of ROOMS.values()) {
    for (const s of room.spectators) send(s, { type: 'event', event: evt });
  }
}

setInterval(() => {
  METRICS.messagesPerSecond = Math.round(METRICS._recentMsgs / 2);
  METRICS._recentMsgs = 0;
  for (const s of GLOBAL_SPECTATORS) send(s, { type: 'metrics', metrics: publicMetrics() });
  for (const room of ROOMS.values()) {
    for (const s of room.spectators) send(s, { type: 'metrics', metrics: roomMetrics(room) });
  }
}, 2000);

function publicMetrics() {
  const currentPlayers = [...ROOMS.values()].reduce((n, r) => n + r.state.players.size, 0);
  const currentSpectators = [...ROOMS.values()].reduce((n, r) => n + r.spectators.size, 0) + GLOBAL_SPECTATORS.size;
  return {
    uptimeSec: Math.floor((Date.now() - METRICS.startedAt) / 1000),
    totalConnections: METRICS.totalConnections,
    totalRoomsCreated: METRICS.totalRoomsCreated,
    currentRooms: ROOMS.size,
    currentPlayers,
    currentSpectators,
    messagesReceived: METRICS.messagesReceived,
    messagesPerSecond: METRICS.messagesPerSecond,
    lastMessageAt: METRICS.lastMessageAt,
    events: METRICS.events.slice(-30),
    rooms: [...ROOMS.values()].map(r => ({
      code: r.code,
      phase: r.state.phase,
      playerCount: r.state.players.size,
      spectatorCount: r.spectators.size,
      createdAt: r.createdAt,
    })),
  };
}

function roomMetrics(room) {
  return {
    code: room.code,
    phase: room.state.phase,
    playerCount: room.state.players.size,
    spectatorCount: room.spectators.size,
    createdAt: room.createdAt,
    uptimeSec: Math.floor((Date.now() - METRICS.startedAt) / 1000),
  };
}

// ─── EVENT LOG · append-only JSONL for future bot training ──
const EVENTS_LOG_PATH = process.env.GHOSTPAINT_EVENTS_LOG || path.join(__dirname, 'events.jsonl');
let _eventsLogStream = null;
function logGameEvent(room, type, payload) {
  if (!_eventsLogStream) {
    _eventsLogStream = fs.createWriteStream(EVENTS_LOG_PATH, { flags: 'a' });
  }
  const rec = { ts: Date.now(), room: room.code, type, ...payload };
  try { _eventsLogStream.write(JSON.stringify(rec) + '\n'); } catch {}
}

// ─── HTTP server · static files + /health ───────────────────
const server = http.createServer((req, res) => {
  if (req.url === '/health' || req.url === '/health/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({
      ok: true,
      uptimeSec: Math.floor((Date.now() - METRICS.startedAt) / 1000),
      rooms: ROOMS.size,
      players: [...ROOMS.values()].reduce((n, r) => n + r.state.players.size, 0),
    }));
  }
  // Block direct download of event log
  if (req.url && req.url.startsWith('/events.jsonl')) {
    res.writeHead(403); return res.end('nope');
  }
  let file = req.url === '/' ? '/admin.html' : req.url;
  file = file.split('?')[0];
  const full = path.join(__dirname, file);
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
const GLOBAL_SPECTATORS = new Set(); // admin dashboards without a specific room

function send(ws, msg) {
  if (ws.readyState !== ws.OPEN) return;
  try { ws.send(JSON.stringify(msg)); } catch {}
}

function broadcastRoom(room, msg) {
  for (const p of room.state.players.values()) send(p.ws, msg);
  for (const s of room.spectators) send(s, msg);
}

function sendToPlayer(room, playerId, msg) {
  const p = room.state.players.get(playerId);
  if (p) send(p.ws, msg);
}

function publishLobby(room) {
  broadcastRoom(room, {
    type: 'state',
    state: publicState(room.state),
    roomCode: room.code,
  });
}

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, 'http://x');
  const role = url.searchParams.get('role') || 'player';
  const remote = req.socket.remoteAddress || '?';
  console.log(`[WS] ${role} connected from ${remote}`);
  METRICS.totalConnections++;

  // ─── spectator branch ────────────────────────────────────
  if (role === 'spectator') {
    const code = url.searchParams.get('code');
    if (code && ROOMS.has(code)) {
      const room = ROOMS.get(code);
      room.spectators.add(ws);
      recordEvent('info', 'spectator', `spectator joined room ${code}`);
      send(ws, { type: 'state', state: publicState(room.state), roomCode: room.code });
      send(ws, { type: 'metrics', metrics: roomMetrics(room) });
      ws.on('close', () => {
        room.spectators.delete(ws);
        maybeGCRoom(room);
      });
    } else {
      GLOBAL_SPECTATORS.add(ws);
      recordEvent('info', 'spectator', `admin dashboard connected from ${remote}`);
      send(ws, { type: 'metrics', metrics: publicMetrics() });
      ws.on('close', () => GLOBAL_SPECTATORS.delete(ws));
    }
    return;
  }

  // ─── player branch ───────────────────────────────────────
  let playerId = null;
  let room = null;
  const replyErr = (error) => send(ws, { type: 'error', error });

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch {
      recordEvent('warn', 'parse', `bad JSON from ${remote}`);
      return;
    }
    METRICS.messagesReceived++;
    METRICS._recentMsgs++;
    METRICS.lastMessageAt = Date.now();
    if (room) room.lastActiveAt = Date.now();

    switch (msg.type) {
      case 'create_room': {
        if (room) return replyErr('Already in a room');
        if (!msg.name) return replyErr('Name required');
        room = createRoom();
        const { ok, player, error } = addPlayer(room.state, ws, msg.name);
        if (!ok) { ROOMS.delete(room.code); room = null; return replyErr(error); }
        playerId = player.id;
        recordEvent('join', 'player', `${player.name} created room ${room.code}`);
        logGameEvent(room, 'room_created', { host: player.name, hostId: playerId });
        logGameEvent(room, 'player_join', { playerId, name: player.name, role: 'host' });
        send(ws, {
          type: 'room_joined',
          room: { code: room.code, isHost: true },
          you: publicPlayer(player),
        });
        publishLobby(room);
        break;
      }

      case 'join_room': {
        if (room) return replyErr('Already in a room');
        if (!msg.code) return replyErr('Room code required');
        if (!msg.name) return replyErr('Name required');
        const target = ROOMS.get(String(msg.code));
        if (!target) return replyErr('Room not found');
        if (target.state.phase === 'playing' || target.state.phase === 'ending') {
          return replyErr('Match in progress — wait for the next round');
        }
        const { ok, player, error } = addPlayer(target.state, ws, msg.name);
        if (!ok) return replyErr(error);
        room = target;
        playerId = player.id;
        recordEvent('join', 'player', `${player.name} joined room ${room.code}`);
        logGameEvent(room, 'player_join', { playerId, name: player.name, role: 'guest' });
        send(ws, {
          type: 'room_joined',
          room: { code: room.code, isHost: false },
          you: publicPlayer(player),
        });
        publishLobby(room);
        break;
      }

      case 'ready': {
        if (!room || !playerId) return;
        const p = room.state.players.get(playerId);
        if (!p) return;
        p.ready = !!msg.ready;
        publishLobby(room);
        if (room.state.phase === 'lobby' && allReady(room.state)) {
          kickoffCountdown(room);
        }
        break;
      }

      case 'force_start': {
        if (!room || !playerId) return;
        if (!forceStart(room.state)) return;
        const p = room.state.players.get(playerId);
        if (p) p.ready = true;
        kickoffCountdown(room);
        break;
      }

      case 'reset_lobby': {
        if (!room) return;
        if (room.state.phase === 'ended') {
          resetToLobby(room.state);
          publishLobby(room);
        }
        break;
      }

      case 'fire': {
        if (!room || !playerId) return;
        const msgs = handleFire(room.state, playerId, {
          targetBib: msg.targetBib || null,
          worldPos: msg.worldPos || null,
        });
        for (const { scope, playerId: pid, msg: m } of msgs) {
          if (scope === 'self') sendToPlayer(room, pid, m);
          else broadcastRoom(room, m);
          if (m.type === 'kill') {
            const sh = room.state.players.get(m.shooterId)?.name;
            const vi = room.state.players.get(m.victimId)?.name;
            recordEvent('kill', 'match', `[${room.code}] ${sh} eliminated ${vi}`);
            logGameEvent(room, 'kill', { shooter: sh, victim: vi, shooterId: m.shooterId, victimId: m.victimId });
          } else if (m.type === 'hit') {
            const sh = room.state.players.get(m.shooterId)?.name;
            const vi = room.state.players.get(m.victimId)?.name;
            recordEvent('hit', 'match', `[${room.code}] ${sh} → ${vi} · ${m.damage} dmg · hp=${m.hp}`);
            logGameEvent(room, 'hit', { shooter: sh, victim: vi, shooterId: m.shooterId, victimId: m.victimId, damage: m.damage, hp: m.hp });
          } else if (m.type === 'game_end') {
            const winner = room.state.players.get(m.winnerId)?.name || 'nobody';
            recordEvent('win', 'match', `[${room.code}] match ended · ${winner} wins (${m.reason})`);
            logGameEvent(room, 'game_end', { winner, winnerId: m.winnerId, reason: m.reason });
          }
        }
        if (msgs.length) publishLobby(room);
        break;
      }

      case 'position': {
        if (!room || !playerId) return;
        const p = room.state.players.get(playerId);
        if (!p) return;
        p.position = { lat: msg.lat, lng: msg.lng, heading: msg.heading };
        if (!p._lastPosBroadcast || Date.now() - p._lastPosBroadcast > 500) {
          p._lastPosBroadcast = Date.now();
          broadcastRoom(room, { type: 'position', playerId, ...p.position });
          logGameEvent(room, 'position', { playerId, ...p.position });
        }
        break;
      }

      case 'leave': {
        if (room && playerId) {
          removePlayer(room.state, playerId);
          logGameEvent(room, 'player_leave', { playerId, reason: 'explicit' });
          publishLobby(room);
          maybeGCRoom(room);
          playerId = null;
          room = null;
        }
        break;
      }

      case 'join': {
        // Old v0.2 protocol — tell client to upgrade
        return replyErr('Server upgraded to v0.3. Send {type:"create_room",name:"..."} or {type:"join_room",code:"123456",name:"..."} instead.');
      }
    }
  });

  ws.on('close', () => {
    console.log(`[WS] player disconnected from ${remote}${playerId ? ' (was ' + playerId.slice(0,8) + ')' : ''}`);
    if (room && playerId) {
      const p = room.state.players.get(playerId);
      const who = p?.name || remote;
      recordEvent('warn', 'player', `disconnect: ${who} left room ${room.code}`);
      logGameEvent(room, 'player_leave', { playerId, reason: 'disconnect' });
      removePlayer(room.state, playerId);
      publishLobby(room);
      maybeGCRoom(room);
    }
  });
});

function kickoffCountdown(room) {
  startCountdown(room.state);
  publishLobby(room);
  setTimeout(() => {
    startMatch(room.state);
    broadcastRoom(room, { type: 'game_start' });
    logGameEvent(room, 'game_start', {
      players: [...room.state.players.values()].map(p => ({ id: p.id, name: p.name })),
    });
    publishLobby(room);
    scheduleMatchEnd(room);
  }, CONFIG.countdownSec * 1000);
}

function scheduleMatchEnd(room) {
  clearTimeout(room.matchTimer);
  room.matchTimer = setTimeout(() => {
    if (room.state.phase !== 'playing') return;
    const players = [...room.state.players.values()];
    players.sort((a, b) => (b.kills - a.kills) || (a.deaths - b.deaths));
    const winner = players[0]?.id || null;
    endMatch(room.state, winner);
    broadcastRoom(room, { type: 'game_end', reason: 'time_up', winnerId: winner });
    logGameEvent(room, 'game_end', { winnerId: winner, reason: 'time_up' });
    publishLobby(room);
  }, CONFIG.matchDurationMs);
}

// ─── start ──────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('════════════════════════════════════════════════════════════');
  console.log('  G H O S T P A I N T · game server · v0.3 (room codes)');
  console.log('════════════════════════════════════════════════════════════');
  console.log(`  Port          :  ${PORT}`);
  console.log(`  Health check  :  /health`);
  console.log(`  Admin (web)   :  /admin.html`);
  console.log(`  Web client    :  /fake-client.html`);
  console.log(`  WebSocket     :  /ws?role=player`);
  console.log(`  Events log    :  ${EVENTS_LOG_PATH}`);
  console.log('════════════════════════════════════════════════════════════');
  console.log('');
});
