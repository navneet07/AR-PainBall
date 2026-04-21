# GhostPaint · Session log · 2026-04-21

Checkpoint save. Resume from here in the next session.

---

## ✅ What works (verified)

| Component | Status | Evidence |
|---|---|---|
| Server (Node + ws + Bonjour) | ✅ Production quality | 3-player smoke test passed · full match lifecycle |
| Manager Dashboard (admin.html) | ✅ v2 shipped | 4-zone ops view with scoreboard / insights / event log / health metrics |
| Fake-client.html | ✅ Full game | Multi-browser tabs work · verified 2-player kill flow |
| Bib generator | ✅ | `bibs/bibs.html` renders 8 QR bibs, print-ready A4 |
| iOS Xcode project | ✅ Compiles clean | 0 errors, 0 warnings · verified on `iphoneos` |
| iOS build installed on Dabba | ✅ | App installed, ATS + orientation + ATS + debug overlay all working |
| Git + GitHub | ✅ | All work pushed to https://github.com/navneet07/AR-PainBall |

## ❌ What's broken (known issues)

### 1. Native iOS app · Dabba packets not reaching server
Symptom: app pill stays 🟡 CONNECTING forever, server log shows zero connections from Dabba's IP (`192.168.110.x`).

**Not ruled out:**
- Local Network permission may still be denied in iPhone Settings → GhostPaint
- Mac firewall may be blocking inbound (`System Settings → Network → Firewall`)
- Home router may have AP isolation enabled
- Bonjour discovery was broken (fixed in `115f48c`, needs rebuild on Dabba)

**Diagnostic not completed:** single-URL Safari reachability test (`http://<mac-ip>:8200/admin.html` from Dabba Safari) would have bifurcated network vs app issues. User didn't complete this test.

### 2. JJ's phone · never reached server once
Same symptom as Dabba. Same unknowns.

### 3. Alan's phone (Waliphone) · not tested live
Device registered in Xcode's team list · app installed but connect attempt not observed.

### 4. Apple Developer team device limit was hit
User resolved this session by clearing old devices from paid Apple Developer portal. All 3 phones now use `com.nitin.ghostpaint` / Nitin's team. ✅ no longer blocking.

## 🎯 Recommended next-session path

**Do these in order:**

1. **Sanity-check network** — all devices on same home WiFi. Confirm with `ipconfig getifaddr en0` on Mac. Share WiFi name.

2. **Safari reachability test on each phone** — open `http://<mac-ip>:8200/admin.html` in Safari on each of Nitin/Alan/JJ's phone. Record which loads / which times out.

3. **If Safari loads but native app doesn't:** phone-side Local Network permission (iPhone Settings → GhostPaint → Local Network ON).

4. **If Safari times out:** Mac firewall OR router client-isolation. Fix firewall first (System Settings → Network → Firewall → allow node), or switch to Mac-as-hotspot (Internet Sharing).

5. **Fallback for any persistent failure:** Safari web client on all 3 phones at `http://<mac-ip>:8200/fake-client.html`. Full game, simulated camera.

## 🔌 Environment snapshot (at time of save)

- Mac IP: `192.168.110.20` (home WiFi subnet)
- Server: was running on :8200 (stopped at checkpoint)
- All 3 iPhones paired in Xcode: Dabba, JJ's Toy, Waliphone
- Latest builds preserved in DerivedData (don't delete)

## ⚡ Resume command (one-liner to bring server back up)

```bash
cd "/Users/ai/Documents/2026/April/AR Games/GhostPaint/server" && node server.mjs > /tmp/ghostpaint-server.log 2>&1 &
```

Then:
- Admin: `http://localhost:8200/admin.html`
- Players (web): `http://<mac-current-ip>:8200/fake-client.html`
- Native: Xcode ⌘R on selected phone · host = Mac IP · port 8200

## 📁 What's preserved on disk (do not delete)

- `/Users/ai/Documents/2026/April/AR Games/GhostPaint/` — full source tree, committed to git
- `~/Library/Developer/Xcode/DerivedData/GhostPaint-*` — compiled `.app` bundles for Dabba
- Apps installed on phones — 7-day expiry on personal team (paid team: 90-day)
- `https://github.com/navneet07/AR-PainBall` — durable remote backup

## 🏷 Git history at checkpoint

```
115f48c fix(ios): Bonjour discovery resolves real IP instead of bogus hostname
d5db689 fix(ios): all Xcode warnings resolved · clean compile
43ebdb1 fix(ios): countdown-stuck bug + visible debug overlay + ATS fix
3fxxxxx (earlier ATS + orientation work)
5a95f00 feat(ghostpaint): v0.1 initial local backup
```

---

*Session paused cleanly. All work durable. Resume by reading this file + running the one-liner above.*
