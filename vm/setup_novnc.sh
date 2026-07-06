#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG noVNC Setup — sets up websockify to proxy VNC → WebSocket
# so the OS session can be accessed via browser.
#
# Usage: bash setup_novnc.sh <vnc_port> <ws_port>
# ═══════════════════════════════════════════════════════════════════════════════

VNC_PORT="${1:-5900}"
WS_PORT="${2:-6000}"
WWRIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOVNC_DIR="$WWRIG_DIR/vm/novnc"

echo "  [NOVNC] Setting up WebSocket proxy..."
echo "          VNC  : localhost:${VNC_PORT}"
echo "          HTTP : http://localhost:${WS_PORT}"
echo ""

# ── Install websockify ────────────────────────────────────────────────────────
if ! command -v websockify &>/dev/null; then
  echo "  Installing websockify..."
  if command -v pip3 &>/dev/null; then
    pip3 install websockify --quiet
  elif command -v pip &>/dev/null; then
    pip install websockify --quiet
  else
    echo "  [!!] pip not found. Install with: brew install python3"
    exit 1
  fi
fi

# ── Download noVNC ────────────────────────────────────────────────────────────
if [ ! -d "$NOVNC_DIR" ]; then
  echo "  Downloading noVNC..."
  mkdir -p "$NOVNC_DIR"
  if command -v curl &>/dev/null; then
    curl -sL "https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz" \
      | tar -xz --strip-components=1 -C "$NOVNC_DIR"
  elif command -v wget &>/dev/null; then
    wget -qO- "https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz" \
      | tar -xz --strip-components=1 -C "$NOVNC_DIR"
  fi
fi

# ── Start websockify ──────────────────────────────────────────────────────────
LOGFILE="$WWRIG_DIR/vm/logs/novnc-${WS_PORT}.log"

# Kill existing websockify on this port
pkill -f "websockify.*${WS_PORT}" 2>/dev/null || true
sleep 0.5

websockify \
  --web "$NOVNC_DIR" \
  --log-file "$LOGFILE" \
  "$WS_PORT" \
  "localhost:${VNC_PORT}" \
  --daemon 2>/dev/null || {
    # If --daemon fails, run in background
    nohup websockify \
      --web "$NOVNC_DIR" \
      "$WS_PORT" \
      "localhost:${VNC_PORT}" \
      > "$LOGFILE" 2>&1 &
    echo $! > "$WWRIG_DIR/vm/logs/novnc-${WS_PORT}.pid"
  }

sleep 1

echo ""
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║         wwrig OS session is LIVE                  ║"
echo "  ╠═══════════════════════════════════════════════════╣"
echo "  ║  Open in browser:                                 ║"
echo "  ║  → http://localhost:${WS_PORT}/vnc.html           ║"
echo "  ║                                                   ║"
echo "  ║  The dashboard will also show an OPEN DISPLAY     ║"
echo "  ║  button automatically.                            ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo ""
