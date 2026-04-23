#!/usr/bin/env bash
# GhostPaint · Lightning Studio start script
# Run: bash lightning-start.sh
#   Starts the Node server + Cloudflare quick tunnel
#   Prints the public URL. Both processes log to /tmp/.

set -e

# Resolve absolute script dir so the repo-path logic below is correct
# regardless of which cwd the user launched from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── 0. load Node from nvm ────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh"; fi

# ─── 1. download cloudflared if missing ───────────────────────
mkdir -p "$HOME/bin"
if [ ! -x "$HOME/bin/cloudflared" ]; then
  echo "[+] installing cloudflared..."
  curl -sL -o "$HOME/bin/cloudflared" \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x "$HOME/bin/cloudflared"
fi

# ─── 2. kill any prior instances ─────────────────────────────
pkill -f "node server.mjs" 2>/dev/null || true
pkill -f "cloudflared tunnel" 2>/dev/null || true
sleep 1

# ─── 3. install deps if missing ──────────────────────────────
cd "$SCRIPT_DIR"
if [ ! -d node_modules ] || [ ! -d node_modules/ws ]; then
  echo "[+] installing npm deps..."
  npm install --no-audit --no-fund 2>&1 | tail -3
fi

# ─── 4. start the game server ────────────────────────────────
nohup node server.mjs > /tmp/ghostpaint.log 2>&1 &
SERVER_PID=$!
echo "[+] server PID=$SERVER_PID"
sleep 2

# ─── 4. start cloudflare quick tunnel ────────────────────────
nohup "$HOME/bin/cloudflared" tunnel --url http://localhost:8200 --no-autoupdate \
  > /tmp/cloudflared.log 2>&1 &
TUNNEL_PID=$!
echo "[+] tunnel PID=$TUNNEL_PID"

# ─── 5. wait for the tunnel URL ──────────────────────────────
echo "[+] waiting for tunnel URL..."
for i in $(seq 1 20); do
  URL=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" /tmp/cloudflared.log | head -1 || true)
  if [ -n "$URL" ]; then break; fi
  sleep 1
done

echo ""
echo "══════════════════════════════════════════════════════════════════════"
if [ -n "$URL" ]; then
  echo "  ✅ GhostPaint is LIVE"
  echo ""
  echo "  Public URL    :  $URL"
  echo "  Web client    :  $URL/fake-client.html"
  echo "  Admin         :  $URL/admin.html"
  echo "  Health check  :  $URL/health"
  echo ""
  # write url to a file for downstream scripts
  echo "$URL" > /tmp/ghostpaint-url.txt

  # ─── 6. publish URL to BOTH locations ──────────────────────────
  # server/current-url.txt   → iOS native client reads this via raw.github
  # docs/current-url.txt     → PWA reads this same-origin (fast CDN, <1 min)
  SRV_FILE="$REPO_DIR/server/current-url.txt"
  DOCS_FILE="$REPO_DIR/docs/current-url.txt"
  CURRENT="$(cat "$DOCS_FILE" 2>/dev/null || true)"
  if [ "$CURRENT" != "$URL" ]; then
    echo "$URL" > "$SRV_FILE"
    echo "$URL" > "$DOCS_FILE"
    cd "$REPO_DIR"
    git add server/current-url.txt docs/current-url.txt
    if git -c user.name=GhostPaintStudio -c user.email=studio@ghostpaint.local \
         commit -m "chore: publish new tunnel URL ($URL)" > /dev/null 2>&1; then
      if git push origin main > /dev/null 2>&1; then
        echo "  📡 URL published to GitHub (PWA + iOS + keep-alive will pick it up)"
      else
        echo "  ⚠ git push failed — check PAT config in ~/.git-credentials"
      fi
    fi
  else
    echo "  📡 URL unchanged (already published)"
  fi
else
  echo "  ⚠ tunnel URL not ready yet — check /tmp/cloudflared.log"
fi
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "  Server log :  tail -f /tmp/ghostpaint.log"
echo "  Tunnel log :  tail -f /tmp/cloudflared.log"
echo ""
