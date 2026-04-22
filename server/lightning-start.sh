#!/usr/bin/env bash
# GhostPaint · Lightning Studio start script
# Run: bash lightning-start.sh
#   Starts the Node server + Cloudflare quick tunnel
#   Prints the public URL. Both processes log to /tmp/.

set -e

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

# ─── 3. start the game server ────────────────────────────────
cd "$(dirname "$0")"
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
else
  echo "  ⚠ tunnel URL not ready yet — check /tmp/cloudflared.log"
fi
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "  Server log :  tail -f /tmp/ghostpaint.log"
echo "  Tunnel log :  tail -f /tmp/cloudflared.log"
echo ""
