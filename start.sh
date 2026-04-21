#!/bin/bash
# GhostPaint · one-command resume
# Starts the game server + prints all the URLs.

set -e
cd "$(dirname "$0")"

# Kill any stale server
lsof -ti:8200 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1

# Start fresh
cd server
node server.mjs > /tmp/ghostpaint-server.log 2>&1 &
sleep 3

if ! lsof -ti:8200 >/dev/null 2>&1; then
  echo "✗ server failed to start · check /tmp/ghostpaint-server.log"
  exit 1
fi

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "YOUR_MAC_IP")

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  GHOSTPAINT · server up · pid $(lsof -ti:8200 | head -1)"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Mac IP:  $IP"
echo "  Port:    8200"
echo ""
echo "  Admin (Mac):          http://localhost:8200/admin.html"
echo "  Web player (any dev): http://$IP:8200/fake-client.html"
echo "  Native app config:    host=$IP  port=8200"
echo ""
echo "  Tail log:             tail -f /tmp/ghostpaint-server.log"
echo "  Stop:                 lsof -ti:8200 | xargs kill"
echo ""
