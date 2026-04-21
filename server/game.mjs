// ═══════════════════════════════════════════════════════════
//  GhostPaint · game state machine + hit arbitration
// ═══════════════════════════════════════════════════════════
//
//  Phases:  lobby → countdown → playing → ended → (reset → lobby)
//
//  State is server-authoritative. Clients never mutate player
//  stats directly — they send intent (fire, position, ready)
//  and the server decides the outcome.

import crypto from 'crypto';

// ─── config ────────────────────────────────────────────────
export const CONFIG = {
  maxPlayers: 8,
  magazineSize: 15,
  reloadMs: 2000,
  damagePerHit: 25,
  maxHp: 100,
  fireCooldownMs: 250,   // 4 shots/sec cap
  respawnMs: 5000,
  countdownSec: 5,
  killsToWin: 10,
  matchDurationMs: 5 * 60 * 1000,  // 5 min
};

// Bib palette — every new player gets the next color in line
const BIB_PALETTE = [
  { id: 'bib-01', name: 'Red Ghost',    color: '#ff3040' },
  { id: 'bib-02', name: 'Blue Ghost',   color: '#3080ff' },
  { id: 'bib-03', name: 'Green Ghost',  color: '#30d060' },
  { id: 'bib-04', name: 'Amber Ghost',  color: '#ffc030' },
  { id: 'bib-05', name: 'Cyan Ghost',   color: '#30d0d0' },
  { id: 'bib-06', name: 'Magenta Ghost',color: '#d030d0' },
  { id: 'bib-07', name: 'White Ghost',  color: '#f0f0f0' },
  { id: 'bib-08', name: 'Orange Ghost', color: '#ff7030' },
];

// ─── state ──────────────────────────────────────────────────
export function newState() {
  return {
    phase: 'lobby',                  // lobby | countdown | playing | ended
    players: new Map(),              // id → Player
    availableBibs: [...BIB_PALETTE],
    matchStartedAt: null,
    matchEndsAt: null,
    countdownEndsAt: null,
    killFeed: [],                    // last 20 kills, FIFO
    shots: [],                       // for paint trail (post-match)
    winner: null,
  };
}

// ─── player helpers ─────────────────────────────────────────
export function addPlayer(state, ws, name) {
  if (state.players.size >= CONFIG.maxPlayers) {
    return { ok: false, error: 'server full' };
  }
  if (state.phase === 'playing') {
    return { ok: false, error: 'match in progress — wait for next round' };
  }
  if (state.availableBibs.length === 0) {
    return { ok: false, error: 'no bibs left' };
  }
  const id = crypto.randomUUID();
  const bib = state.availableBibs.shift();
  const player = {
    id,
    ws,
    name: String(name || 'Ghost').slice(0, 12),
    bibId: bib.id,
    bibName: bib.name,
    color: bib.color,
    hp: CONFIG.maxHp,
    ammo: CONFIG.magazineSize,
    reloading: false,
    lastFireAt: 0,
    kills: 0,
    deaths: 0,
    hits: 0,
    shots: 0,
    ready: false,
    alive: true,
    joinedAt: Date.now(),
  };
  state.players.set(id, player);
  return { ok: true, player };
}

export function removePlayer(state, id) {
  const p = state.players.get(id);
  if (!p) return false;
  const bib = BIB_PALETTE.find(b => b.id === p.bibId);
  if (bib) state.availableBibs.push(bib);
  state.players.delete(id);
  return true;
}

// ─── phase transitions ──────────────────────────────────────
export function allReady(state) {
  if (state.players.size < 2) return false;
  return [...state.players.values()].every(p => p.ready);
}

// Solo / test mode: any player in the lobby can request a force-start
// (bypasses the min-2 rule so you can see AR alone). Returns true if
// transition was applied.
export function forceStart(state) {
  if (state.phase !== 'lobby') return false;
  if (state.players.size < 1) return false;
  return true;  // caller should kick off countdown then startMatch
}

export function startCountdown(state) {
  state.phase = 'countdown';
  state.countdownEndsAt = Date.now() + CONFIG.countdownSec * 1000;
}

export function startMatch(state) {
  state.phase = 'playing';
  state.matchStartedAt = Date.now();
  state.matchEndsAt = state.matchStartedAt + CONFIG.matchDurationMs;
  state.killFeed = [];
  state.shots = [];
  for (const p of state.players.values()) {
    p.hp = CONFIG.maxHp;
    p.ammo = CONFIG.magazineSize;
    p.reloading = false;
    p.kills = 0;
    p.deaths = 0;
    p.hits = 0;
    p.shots = 0;
    p.alive = true;
    p.ready = false;
  }
}

export function endMatch(state, winnerId = null) {
  state.phase = 'ended';
  state.winner = winnerId;
}

export function resetToLobby(state) {
  state.phase = 'lobby';
  state.winner = null;
  state.matchStartedAt = null;
  state.matchEndsAt = null;
  state.killFeed = [];
  state.shots = [];
  for (const p of state.players.values()) {
    p.ready = false;
    p.hp = CONFIG.maxHp;
    p.ammo = CONFIG.magazineSize;
    p.alive = true;
  }
}

// ─── fire / hit arbitration ─────────────────────────────────
// Returns an array of messages to broadcast. Server decides everything.
export function handleFire(state, shooterId, { targetBib, worldPos }) {
  const out = [];
  const shooter = state.players.get(shooterId);
  if (!shooter || state.phase !== 'playing') return out;
  if (!shooter.alive) return out;
  if (shooter.reloading) return out;

  const now = Date.now();
  if (now - shooter.lastFireAt < CONFIG.fireCooldownMs) return out;
  if (shooter.ammo <= 0) {
    out.push({ scope: 'self', playerId: shooterId, msg: { type: 'dry_fire' } });
    return out;
  }

  shooter.ammo--;
  shooter.lastFireAt = now;
  shooter.shots++;

  // Record the shot for post-match paint trail (with or without target)
  const shot = {
    shooterId,
    color: shooter.color,
    worldPos: worldPos || null,     // ARWorldMap transform (opt-in)
    timestamp: now,
    hit: false,
  };

  // Auto-reload when empty
  if (shooter.ammo === 0) {
    shooter.reloading = true;
    setTimeout(() => {
      shooter.ammo = CONFIG.magazineSize;
      shooter.reloading = false;
      out.push({ scope: 'self', playerId: shooterId, msg: { type: 'reload_complete', ammo: shooter.ammo } });
    }, CONFIG.reloadMs);
  }

  // No target in reticle → broadcast shot_missed + save to trail
  if (!targetBib) {
    state.shots.push(shot);
    out.push({ scope: 'all', msg: { type: 'shot_missed', shooterId } });
    return out;
  }

  // Find victim by bib
  const victim = [...state.players.values()].find(p => p.bibId === targetBib);
  if (!victim || victim.id === shooterId || !victim.alive) {
    state.shots.push(shot);
    out.push({ scope: 'all', msg: { type: 'shot_missed', shooterId } });
    return out;
  }

  // Apply damage
  shot.hit = true;
  shot.victimId = victim.id;
  state.shots.push(shot);
  shooter.hits++;
  victim.hp = Math.max(0, victim.hp - CONFIG.damagePerHit);

  // Tell the victim they took damage (for red-edge pulse)
  out.push({
    scope: 'self',
    playerId: victim.id,
    msg: { type: 'damage', shooterId, amount: CONFIG.damagePerHit, hp: victim.hp },
  });

  // Tell everyone a hit landed
  out.push({
    scope: 'all',
    msg: { type: 'hit', shooterId, victimId: victim.id, damage: CONFIG.damagePerHit, hp: victim.hp },
  });

  // Kill handling
  if (victim.hp <= 0) {
    victim.alive = false;
    victim.deaths++;
    shooter.kills++;
    const kill = { shooterId, victimId: victim.id, at: now };
    state.killFeed.unshift(kill);
    if (state.killFeed.length > 20) state.killFeed.pop();

    out.push({ scope: 'all', msg: { type: 'kill', ...kill } });

    // Win condition
    if (shooter.kills >= CONFIG.killsToWin) {
      endMatch(state, shooter.id);
      out.push({ scope: 'all', msg: { type: 'game_end', reason: 'kills_reached', winnerId: shooter.id } });
    } else {
      // Schedule respawn
      setTimeout(() => {
        if (state.phase !== 'playing') return;
        victim.hp = CONFIG.maxHp;
        victim.ammo = CONFIG.magazineSize;
        victim.reloading = false;
        victim.alive = true;
        out.push({ scope: 'all', msg: { type: 'respawn', playerId: victim.id } });
      }, CONFIG.respawnMs);
    }
  }

  return out;
}

// ─── serialization for clients ──────────────────────────────
export function publicState(state) {
  return {
    phase: state.phase,
    countdownEndsAt: state.countdownEndsAt,
    matchStartedAt: state.matchStartedAt,
    matchEndsAt: state.matchEndsAt,
    winner: state.winner,
    players: [...state.players.values()].map(publicPlayer),
    killFeed: state.killFeed.slice(0, 8),
  };
}

export function publicPlayer(p) {
  return {
    id: p.id,
    name: p.name,
    bibId: p.bibId,
    bibName: p.bibName,
    color: p.color,
    hp: p.hp,
    ammo: p.ammo,
    reloading: p.reloading,
    kills: p.kills,
    deaths: p.deaths,
    hits: p.hits,
    shots: p.shots,
    ready: p.ready,
    alive: p.alive,
  };
}
