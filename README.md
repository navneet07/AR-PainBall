# GHOSTPAINT

> Your phone is your scope. Your world is the arena. The paint lasts five minutes.

A local-LAN multiplayer AR paintball game. iPhone as tactical HUD, Mac as
game server, your friends in QR bibs. No cloud, no accounts, no monetization,
zero cent today.

![architecture](docs/architecture.svg)<!-- optional placeholder -->

## What this repo contains

```
GhostPaint/
├── DESIGN.md                    full game design bible — read this first
├── ASSETS.md                    curated CC0 assets (Kenney.nl, freesound.org)
├── server/
│   ├── server.mjs               Node.js WebSocket + Bonjour broadcast
│   ├── game.mjs                 state machine + server-authoritative hit arbitration
│   ├── admin.html               spectator / host control surface
│   ├── fake-client.html         browser test client — two tabs = two players
│   └── package.json
├── bibs/
│   ├── generate-bibs.mjs        node script → bibs.html (8 printable QR bibs)
│   └── bibs.html                (generated) print-and-pin, A4, 16×20 cm each
└── ios/
    ├── GhostPaint/              7 Swift files — SwiftUI + ARKit + Vision + Network
    └── README-ios.md            Xcode setup (3-min click-through)
```

## Quick start (on a laptop, no iPhone)

```bash
cd server
npm install
npm start
```

Then:
- Open `http://localhost:8200/admin.html` (Mac spectator)
- Open `http://localhost:8200/fake-client.html` in **two** browser tabs — each is a fake player
- Join each tab with a name, tap Ready in both → countdown → fight
- Tap a target card then click the reticle (or Space) to fire
- Watch the admin page live-update scoreboard, kill feed, HP, ammo

## Real iOS play (weekend 2)

1. Run the server on your Mac.
2. Follow `ios/README-ios.md` to set up the Xcode project and deploy to iPhone.
3. Generate bibs: `cd bibs && node generate-bibs.mjs`. Open `bibs.html`, print to A4, cut out.
4. Pin bibs to chest and back (front-only works, both = fair game).
5. Everyone on same WiFi. Launch GhostPaint → Bonjour finds the Mac → join lobby.
6. Play outdoor (daylight = best QR detection) or in a big indoor space.

## The signature feature · Paint Trail

Every shot anchors a virtual paint splat in AR world-space using `ARWorldMap`.
At match end, all players walk the arena — they see every shot fired during
the fight painted onto the actual walls and furniture, fading over 5 minutes.

**v1 records the shots** (the server collects them in `STATE.shots`).
**v1.1 renders them on-device** after the match.

## Locked design decisions

- iOS-only (native ARKit + Vision); no Android port planned
- Local Mac server only; no cloud
- Bibs are QR codes (Apple Vision native); not ArUco
- Server is authoritative; clients send intent, not outcomes
- FFA only in v1; TDM + Capture-the-Ghost in v1.1, v2
- Iron Man aesthetic: cyan, amethyst, blood red, SF Mono, corner brackets

## Roadmap

### v1 (this weekend · MVP)
- [x] Server + game state machine
- [x] Browser fake-client for protocol testing
- [x] Admin/spectator view
- [x] iOS skeleton (Xcode project needed)
- [x] Bib generator
- [ ] Actual iPhone deploy + live match between 2 devices
- [ ] Sound effects in iOS client

### v1.1 (weekend 2 · polish + paint trail)
- [ ] Paint trail rendering (ARWorldMap anchors)
- [ ] Team Deathmatch mode
- [ ] Shotgun weapon
- [ ] Full sound + haptics pass
- [ ] Iron Man styling pass

### v2 (weekend 3+ · expansion)
- [ ] Capture the Ghost mode
- [ ] Marker rifle (long-range)
- [ ] Persistent stats (SQLite on Mac server)
- [ ] Post-match video export

## License

MIT. See LICENSE.

---

*Built locally · played locally · zero cent today.*
