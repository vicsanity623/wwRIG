#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG noVNC Setup — proxies VNC → WebSocket via noVNC's bundled websockify.
# Usage: bash setup_novnc.sh <vnc_port> <ws_port>
# ═══════════════════════════════════════════════════════════════════════════════

VNC_PORT="${1:-5900}"
WS_PORT="${2:-6000}"
WWRIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOVNC_DIR="$WWRIG_DIR/vm/novnc"
LOG_DIR="$WWRIG_DIR/vm/logs"
mkdir -p "$LOG_DIR"

echo "  [NOVNC] Setting up WebSocket proxy..."
echo "          VNC  : localhost:${VNC_PORT}"
echo "          HTTP : http://localhost:${WS_PORT}"
echo ""

# ── Download noVNC if missing ──────────────────────────────────────────────────
if [ ! -d "$NOVNC_DIR" ] || [ ! -f "$NOVNC_DIR/vnc.html" ]; then
  echo "  Downloading noVNC..."
  mkdir -p "$NOVNC_DIR"
  if command -v curl &>/dev/null; then
    curl -sL "https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz" \
      | tar -xz --strip-components=1 -C "$NOVNC_DIR" 2>/dev/null
  elif command -v wget &>/dev/null; then
    wget -qO- "https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz" \
      | tar -xz --strip-components=1 -C "$NOVNC_DIR" 2>/dev/null
  fi
  if [ ! -f "$NOVNC_DIR/vnc.html" ]; then
    echo "  [!!] Failed to download noVNC."
    exit 1
  fi
  echo "  [OK] noVNC downloaded"
fi

# ── Use bundled websockify (no pip install needed) ─────────────────────────────
WEBSOCKIFY_DIR="$NOVNC_DIR/utils/websockify"
WEBSOCKIFY_RUN="$WEBSOCKIFY_DIR/run"

if [ ! -f "$WEBSOCKIFY_RUN" ]; then
  echo "  Cloning websockify into noVNC utils..."
  (cd "$NOVNC_DIR/utils" && git clone --depth=1 https://github.com/novnc/websockify.git 2>/dev/null) || {
    echo "  [!!] Could not clone websockify."
    exit 1
  }
fi

# ── Kill existing proxy on this port ────────────────────────────────────────────
pkill -f "websockify.*${WS_PORT}" 2>/dev/null || true
sleep 0.5

# ── Start websockify ──────────────────────────────────────────────────────────
LOGFILE="$LOG_DIR/novnc-${WS_PORT}.log"

PYTHONPATH="$WEBSOCKIFY_DIR" nohup python3 -m websockify \
  --web "$NOVNC_DIR" \
  --log-file "$LOGFILE" \
  "$WS_PORT" "localhost:${VNC_PORT}" \
  > /dev/null 2>&1 &

echo $! > "$LOG_DIR/novnc-${WS_PORT}.pid"
sleep 2

# Verify it started
if nc -z localhost "$WS_PORT" 2>/dev/null; then
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
else
  echo "  [!!] WebSocket proxy failed to start. Check $LOGFILE"
  cat "$LOGFILE" 2>/dev/null
  exit 1
fi
echo ""
