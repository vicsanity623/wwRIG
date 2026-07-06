#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG Setup Script — World Wide Rig v0.1
# Installs dependencies and starts the full WWRIG stack on this machine.
#
# Usage:
#   bash setup.sh              # Start everything (coordinator + node daemon)
#   bash setup.sh coordinator  # Start coordinator only
#   bash setup.sh node         # Start node daemon only
#   bash setup.sh stop         # Stop all WWRIG processes
# ═══════════════════════════════════════════════════════════════════════════════

set -e
WWRIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-all}"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        WWRIG  —  World Wide Rig  —  v0.1              ║${NC}"
echo -e "${GREEN}║        Setup & Launcher                                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Stop mode ────────────────────────────────────────────────────────────────
if [ "$MODE" = "stop" ]; then
  echo -e "${YELLOW}  Stopping WWRIG processes...${NC}"
  pkill -f "coordinator/server.py" 2>/dev/null && echo "  [OK] Coordinator stopped" || true
  pkill -f "node/daemon.py"        2>/dev/null && echo "  [OK] Node daemon stopped" || true
  pkill -f "websockify"            2>/dev/null && echo "  [OK] noVNC stopped"       || true
  pkill -f "qemu-system"           2>/dev/null && echo "  [OK] QEMU stopped"        || true
  echo ""
  exit 0
fi

# ── System checks ─────────────────────────────────────────────────────────────
echo -e "${CYAN}  Checking system...${NC}"

# Python 3
if ! command -v python3 &>/dev/null; then
  echo -e "${RED}  [!!] Python 3 not found.${NC}"
  echo "       Install with: brew install python3"
  exit 1
fi
PY_VER=$(python3 --version 2>&1 | awk '{print $2}')
echo "  [OK] Python $PY_VER"

# pip
if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null 2>&1; then
  echo -e "${RED}  [!!] pip not found.${NC}"
  echo "       Install with: brew install python3"
  exit 1
fi
echo "  [OK] pip available"

# QEMU (optional, for VM sessions)
if command -v qemu-system-x86_64 &>/dev/null; then
  QEMU_VER=$(qemu-system-x86_64 --version | head -1)
  echo "  [OK] $QEMU_VER"
else
  echo -e "${YELLOW}  [--] QEMU not installed — VM sessions will run in demo mode${NC}"
  echo "       Install with: brew install qemu"
fi

# Get local IP
LOCAL_IP=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
if [ -z "$LOCAL_IP" ]; then
  LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "unknown")
fi
echo "  [OK] Local IP: $LOCAL_IP"

echo ""

# ── Install coordinator deps ───────────────────────────────────────────────────
if [ "$MODE" = "all" ] || [ "$MODE" = "coordinator" ]; then
  echo -e "${CYAN}  Installing coordinator dependencies...${NC}"
  pip3 install -r "$WWRIG_DIR/coordinator/requirements.txt" -q --break-system-packages 2>/dev/null || \
  pip3 install -r "$WWRIG_DIR/coordinator/requirements.txt" -q || true
  echo "  [OK] Coordinator deps installed"
fi

# ── Install node deps ──────────────────────────────────────────────────────────
if [ "$MODE" = "all" ] || [ "$MODE" = "node" ]; then
  echo -e "${CYAN}  Installing node daemon dependencies...${NC}"
  pip3 install -r "$WWRIG_DIR/node/requirements.txt" -q --break-system-packages 2>/dev/null || \
  pip3 install -r "$WWRIG_DIR/node/requirements.txt" -q || true
  echo "  [OK] Node deps installed"
fi

echo ""

# ── Start coordinator ─────────────────────────────────────────────────────────
if [ "$MODE" = "all" ] || [ "$MODE" = "coordinator" ]; then
  # Kill existing
  pkill -f "coordinator/server.py" 2>/dev/null || true
  sleep 0.5

  echo -e "${CYAN}  Starting WWRIG Coordinator on port 8080...${NC}"
  cd "$WWRIG_DIR/coordinator"
  nohup python3 server.py > "$WWRIG_DIR/coordinator.log" 2>&1 &
  COORD_PID=$!
  echo $COORD_PID > "$WWRIG_DIR/.coordinator.pid"

  # Wait for coordinator to be ready
  for i in $(seq 1 15); do
    if curl -s "http://localhost:8080/api/stats" &>/dev/null; then
      echo "  [OK] Coordinator online (PID $COORD_PID)"
      break
    fi
    sleep 0.5
  done
  cd "$WWRIG_DIR"
fi

# ── Start node daemon ─────────────────────────────────────────────────────────
if [ "$MODE" = "all" ] || [ "$MODE" = "node" ]; then
  # Kill existing
  pkill -f "node/daemon.py" 2>/dev/null || true
  sleep 0.3

  echo -e "${CYAN}  Starting node daemon (this machine contributes 10%)...${NC}"
  nohup python3 "$WWRIG_DIR/node/daemon.py" \
    --coordinator "http://localhost:8080" \
    --contribution 10 \
    > "$WWRIG_DIR/node.log" 2>&1 &
  NODE_PID=$!
  echo $NODE_PID > "$WWRIG_DIR/.node.pid"
  sleep 2
  echo "  [OK] Node daemon running (PID $NODE_PID)"
fi

# ── Serve android node page ───────────────────────────────────────────────────
# The android-node/index.html is served from the coordinator's static dir via symlink
if [ ! -f "$WWRIG_DIR/coordinator/static/mobile.html" ]; then
  cp "$WWRIG_DIR/android-node/index.html" "$WWRIG_DIR/coordinator/static/mobile.html"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 WWRIG IS LIVE                         ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║  Dashboard   : http://localhost:8080                  ║${NC}"
echo -e "${GREEN}║  On your LAN : http://${LOCAL_IP}:8080           ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║  Mobile Node : http://${LOCAL_IP}:8080/mobile.html ║${NC}"
echo -e "${GREEN}║  (Open this URL on your Android phone)               ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║  Add more nodes (other machines):                    ║${NC}"
echo -e "${GREEN}║  python3 node/daemon.py \\                            ║${NC}"
echo -e "${GREEN}║    --coordinator http://${LOCAL_IP}:8080        ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║  Stop all:  bash setup.sh stop                       ║${NC}"
echo -e "${GREEN}║  Logs:      tail -f coordinator.log                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
