# GhostPaint · Asset curation

All assets below are **CC0** unless noted. No attribution required but nice to credit.

## 1. HUD sprites · Kenney.nl (primary source)

| Pack | What's in it · we use for | URL |
|---|---|---|
| **UI Pack: Sci-Fi** | Tactical frames, corner brackets, bezels · HUD panels (health/ammo/scoreboard) | https://kenney.nl/assets/ui-pack-sci-fi |
| **UI Pack: Space Expansion** | Hexagonal accents, radar rings, targeting reticles · minimap, reticle alternatives | https://kenney.nl/assets/ui-pack-space-expansion |
| **Game Icons** | 140 glyphs incl. crosshair, health, ammo, compass, target · HUD iconography | https://kenney.nl/assets/game-icons |
| **Game Icons Expansion** | More crosshair variants, directional arrows · damage indicator arrows | https://kenney.nl/assets/game-icons-expansion |
| **Interface Sounds** | 20+ UI beeps, clicks, confirms · button taps, lobby ready, notifications | https://kenney.nl/assets/interface-sounds |
| **Sci-Fi Sounds** | Sci-fi weapons, impacts, power-ups · could stand in for paintball gun | https://kenney.nl/assets/sci-fi-sounds |

## 2. Gameplay sounds · freesound.org (CC0 + CC-BY)

Search these queries on freesound.org, take top CC0 result:

| Need | Search query | Expected find |
|---|---|---|
| Fire | `"paintball gun"` or `"airsoft pop"` | Short pneumatic *thwack* |
| Reload | `"magazine reload click"` | Metallic click + slide |
| Hit confirm | `"paint splat"` | Wet splat |
| Damage taken | `"body impact soft"` | Low whump |
| Kill | `"shooter kill ding"` | Satisfying tone |
| Low ammo | `"empty click"` | Dry hammer fall |
| Game start | `"whistle blow"` or `"countdown beep"` | Starting signal |
| Match end | `"match horn"` or `"round end"` | Closing signal |
| Respawn | `"energy respawn"` | Sci-fi re-entry |

Alternatively grab **all** of Kenney's Sci-Fi Sounds pack and pick from there —
covers most of the above in one CC0 download.

## 3. Fonts (free, bundled with Apple)

No font downloads needed — SwiftUI uses:
- `SF Mono` (system mono) for everything
- `SF Pro` weights for any occasional display text

If you want a more tactical look later:
- **Share Tech Mono** (Google Fonts, OFL) — free tactical mono: https://fonts.google.com/specimen/Share+Tech+Mono
- **Orbitron** (Google Fonts, OFL) — sci-fi display font: https://fonts.google.com/specimen/Orbitron

## 4. 3D models (v2, when we do paint-splat anchors)

| Need | Source | License |
|---|---|---|
| Paint splat mesh (low-poly) | **Kenney 3D: Platformer Kit** or custom SCNNode | CC0 |
| Player avatar (if we add 3D) | **Quaternius - Low Poly Characters** | CC0 · https://quaternius.com |

## 5. Mapping · which pack → which HUD element

This is the spec for Weekend 2 polish. For v1, built-in SF Symbols + cyan
strokes on SwiftUI canvases is enough — the Iron Man look comes from our
styling tokens, not imported sprites.

| HUD element | Weekend 1 (v1) | Weekend 2 (v1.1) polish |
|---|---|---|
| Reticle | SwiftUI Circle + Rectangle | Kenney UI Pack: Sci-Fi → `crosshair.png` |
| Compass | Custom GeometryReader + text ticks | Kenney Game Icons → directional chevrons |
| Health bar | SwiftUI Rectangle | Kenney UI Pack: Sci-Fi → `health_01.png` frame |
| Ammo counter | Mono text | Sci-Fi → `ammo_frame.png` |
| Kill-feed skull icon | SF Symbol `xmark.circle.fill` | Game Icons → `skull.png` |
| Radar/minimap | Canvas-drawn circles | Space Expansion → `radar_ring.png` |
| Damage flash | SwiftUI Radial gradient | Game Icons Expansion → `damage_directional_arrows` |
| Winner banner | Typography only | Sci-Fi Sounds → `win_stinger.ogg` overlay |

## 6. License hygiene

- Kenney packs: **CC0**, no attribution needed (but credit "Kenney.nl" in credits screen anyway — nice)
- freesound.org assets: **check per-asset** — we only use CC0 for v1; CC-BY goes to `credits.txt`
- SF Symbols: **Apple license** — free for in-app use, no extraction/standalone distribution

## 7. Credits screen (for app)

Display in Settings / About:

```
Audio:     Kenney.nl (CC0) · freesound.org contributors (CC0)
Fonts:     Apple SF Mono · Orbitron (OFL, Google Fonts)
Icons:     SF Symbols (Apple) · Kenney Game Icons (CC0)
Code:      MIT — see LICENSE
Built by:  Nitin (2026) · zero cent today
```
