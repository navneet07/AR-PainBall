# GHOSTPAINT · Design Bible

*"Your phone is your scope. Your world is the arena. The paint lasts five minutes."*

---

## 1. One-paragraph pitch

GhostPaint is a real-world multiplayer AR paintball game for iOS. Your iPhone is the scope. Your friends wear QR-coded bibs. Your living room, backyard, or office is the arena. Tap-to-fire hits the player whose bib is in your reticle. Every shot anchors a virtual paint splat in 3D world-space. At match end, everyone holds up their phones and walks the arena — the whole fight painted onto the walls for five minutes before it fades. That's the moment no other AR shooter has.

## 2. What makes this different

| Every other AR shooter | GhostPaint |
|---|---|
| Synthetic enemies / goblins / aliens | **Your actual friends** |
| Pre-scanned arena or room-scale floor plan | **Anywhere** — backyard, office, park |
| Solo or co-op vs AI | **Multiplayer PvP**, 2–8 players |
| Ephemeral shots disappear instantly | **Paint trail** — shots anchor in world space, persist 5 min post-match |
| Cloud-dependent | **Zero-cloud**, all local (Mac = server, LAN = transport) |
| App Store silos | **Bonjour auto-discovery** — friends launch app, auto-join |

## 3. The signature feature · Paint Trail

Every fire event is anchored as a `ARAnchor` in the ARWorldMap of the shooter. The world anchor + player's bib color + hit/miss state form a `PaintSplat` record.

At match end:
- Server broadcasts all splats to all clients
- Each client re-renders the splats on their own camera view using relative world positioning
- Fading opacity over 5 minutes

**Why it matters:** the post-match "walk the arena" phase is the highlight reel. Players naturally replay the match by pointing at the paint. It's a shared memory object. It's the social moment that makes them open the app again next weekend.

## 4. Game modes

### v1 ships one · FFA (Free-For-All)
- 2–8 players, every player for themselves
- First to 10 kills wins, OR highest score after 5 min
- Respawn 5s after death at random origin point within match area
- Round lasts 3–5 min typical

### v1.1 · Team Deathmatch
- Players split into 2 teams by bib color (red/blue)
- 20 team kills wins
- Friendly-fire off

### v2 · Capture the Ghost
- One phantom QR bib placed somewhere at match start (or randomly respawning)
- Holder scores 1 pt / second
- Shooting the holder → they drop the ghost (anyone can pick up by walking to it)
- First to 60 pts wins

## 5. Weapons

### v1 ships one · Standard Rifle
- 15-round magazine, 2s reload
- 25 damage per hit → 4 shots to eliminate
- Detection cone: center 25% of screen
- Fire rate cap: 4 shots/sec (prevents spam)

### v1.1 · Shotgun
- 5-round magazine, 4s reload
- 80 damage per hit (one-shot close range)
- Wider detection cone: center 40% of screen
- Range penalty: bib must be large-in-frame (close range only)

### v2 · Marker Rifle
- 30-round magazine, 1s reload
- 10 damage per hit → 10 shots to eliminate
- Narrow cone: center 10% of screen, longer range (detects smaller bibs)

## 6. HUD layout

```
╔══════════════════════════════════════════════════╗
║        ↑N ····↑NE··•Alice→···↑E ···· ↑SE       ║  compass, top
║                                                    ║
║ ┌─KILL FEED──┐       ┌─SCOREBOARD──────┐         ║
║ │ You→Alice  │       │ You     ■■■■■□□ │         ║
║ │ Bob→Chad   │       │ Alice   ■■□□□□□ │         ║
║ └────────────┘       │ Bob     ■■■□□□□ │         ║
║                      │ Chad    ■□□□□□□ │         ║
║                      └─────────────────┘         ║
║                                                    ║
║                       ⊕  ← reticle               ║
║                                                    ║
║                                                    ║
║ ┌──MINI─┐    ┌─HEALTH──┐        ┌──AMMO──┐      ║
║ │  N↑   │    │ ❤ 75    │        │  12/30 │      ║
║ │  ●    │    │ ▓▓▓░░░  │        │ ▓▓▓▓░  │      ║
║ │ ·Alice│    └─────────┘        └────────┘      ║
║ └───────┘                                         ║
╚══════════════════════════════════════════════════╝
           (live camera feed behind)
```

**Aesthetic:** cyan-on-black tactical, corner-bracketed. Reuse Arky Mark 2's design tokens — `--cyan: #5cf6ff`, `--amethyst: #c8a6ff`, `--blood: #ff3040`, SF Mono, 30px corner brackets with glow.

**Never 3D on the HUD.** 2D SwiftUI only. The real world behind is the 3D.

## 7. Feel · the non-negotiable priorities

Every action has a multi-channel feedback loop. Priority 1 for demo polish.

| Event | Visual | Audio | Haptic |
|---|---|---|---|
| Fire | Muzzle flash sprite (50ms) + camera shake | Paintball "thwack" | Soft impact |
| Hit confirm | Red X flashes over reticle (200ms) | Distinct "splat" | Medium impact |
| Damage taken | Red screen-edge pulse FROM direction of shot | Low "whump" | Sharp buzz |
| Kill | 200ms slowmo freeze + kill feed entry slides in | Satisfying tone | Celebration pattern |
| Low ammo (≤3) | Ammo counter pulses red | Subtle beep | — |
| Empty + reload | Reload animation + progress bar | Click + slide sound | — |
| Respawn | Fade-in camera + "back in the fight" tone | — | — |
| Countdown | Big 3-2-1 numerals | Rising beeps | Escalating pulse |
| Match end | Scoreboard takeover | Win/lose stinger | — |

## 8. Technical architecture

```
┌─ Mac server :8200 ──────────────────┐
│  Node.js + ws WebSocket             │
│  Bonjour: _ghostpaint._tcp.local.   │
│  Server-authoritative game state    │
│  Hit arbitration + cooldowns         │
│  /admin.html spectator view         │
└──────────────────────────────────────┘
         ▲ LAN (home WiFi or Mac hotspot)
         ▼
┌─ iPhone (iOS 17+) ──────────────────┐
│  SwiftUI + ARKit + Vision + Network  │
│  ARSession for camera                │
│  VNDetectBarcodesRequest .qr         │
│  URLSessionWebSocketTask to server   │
│  CMMotionManager for compass         │
│  CLLocation (optional) for minimap   │
│  AVAudioPlayer for SFX               │
│  UIImpactFeedbackGenerator (haptics) │
└──────────────────────────────────────┘
```

### Message protocol (tiny on purpose)

**Client → Server:** `join` · `fire` · `position` · `ready` · `leave`
**Server → Client:** `lobby` · `countdown` · `game_start` · `hit` · `damage` · `kill` · `respawn` · `game_end` · `error`

10 types cover a full match. Keep small.

### Hit detection

1. ARKit delivers frame at 60fps
2. Vision framework scans for QR codes, returns bounding boxes
3. Each QR maps to a player ID (bib-01 → player A)
4. Tap-to-fire:
   - Client checks if any QR's center is within the reticle rectangle (screen-space)
   - If yes → `fire` message with `targetQR`
   - If no → `fire` message with `targetQR: null` (miss)
5. Server validates: cooldown not expired, ammo > 0, target ≠ self → applies damage, broadcasts
6. Client receives `hit`/`damage`/`kill`/`respawn` events and renders

## 9. Player identity

- **Name** (user-chosen, 3–12 chars)
- **Bib QR + color** (assigned by server on join — bib-01 red, bib-02 blue, etc.)
- **Post-match paint trail** (the signature — your shots painted in your color)

Persistent (v2):
- Career stats: kills, deaths, K/D, favorite weapon, matches played
- Cosmetics: custom bib backgrounds (CC0 patterns from Kenney)
- Leaderboard per-server

## 10. Lore (light, not-too-serious)

> In a world where the Ghost Protocol declared paint warfare the only sanctioned combat, operators tag and eliminate each other for honor, XP, and the occasional bragging right.
>
> Your phone is your scope. Your friends are marked. The paint is permanent for five minutes.
>
> *— Ghost Protocol, Manual §1*

The bib-color names in v1: **Red Ghost, Blue Ghost, Green Ghost, Amber Ghost.** Up to 8 in v1.1 with cyan, magenta, white, orange.

## 11. Roadmap

### v1 (this weekend · ~16 hr)
- [x] Design bible (this doc)
- [x] Server scaffolding
- [x] Browser test harness (fake-client for pre-iOS testing)
- [x] iOS skeleton (will need Xcode GUI to compile)
- [ ] Actual Swift dev on device (~8 hr concentrated)
- [ ] First real match between 2 phones
- FFA mode · 1 rifle · full HUD · hit arbitration · kill feed

### v1.1 (weekend 2 · ~12 hr)
- [ ] Paint trail feature (the signature — ARWorldMap anchors)
- [ ] Team deathmatch mode
- [ ] Shotgun weapon
- [ ] Sound design pass (all SFX in + haptics)
- [ ] Iron Man styling pass on HUD

### v2 (weekend 3+ · open-ended)
- [ ] Capture the Ghost mode
- [ ] Marker rifle
- [ ] Persistent stats (SQLite on Mac server)
- [ ] Post-match video export (the paint trail as MP4)
- [ ] Cross-server leaderboards (optional cloud)

## 12. Risks / honest limitations

- **Lighting** — QR detection in low light is flaky. Recommend daytime or well-lit rooms.
- **QR bib size** — must be A4 or larger at 3m range. Smaller bibs = short range only.
- **GPS minimap** — only works outdoors with GPS lock. Indoor fallback: hide minimap.
- **ARWorldMap persistence** — the paint trail requires stable tracking. Heavy motion or poor feature tracking = inconsistent splats.
- **Mac hotspot throughput** — 2 players over Mac hotspot: fine. 8 players: queue messages for bursts.
- **Safety** — friends will run around pointing phones. Recommend outdoor open space or obstacle-free rooms. DESIGN.md doesn't fix physics.

## 13. What "done" looks like for v1

1. Two iPhones connect via Bonjour, see each other in lobby.
2. Host hits "Start". 3-2-1 countdown. "FIGHT."
3. Player A points phone at Player B's bib, taps fire. Server confirms hit. Both phones show it.
4. Player B's HP drops from 100 → 75. Red edge pulse on B's screen.
5. Match ends when someone reaches 10 kills or 5 min elapses.
6. Scoreboard renders. Both players high-five. Demand a rematch.

When step 6 happens, we have a game.

---

*Built locally. Played locally. Zero cent today.*
