#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG Setup Script — World Wide Rig v0.2
# Installs dependencies and starts the full WWRIG stack on this machine.
#
# Usage:
#   bash setup.sh              # Start everything (coordinator + node daemon)
#   bash setup.sh coordinator  # Start coordinator only
#   bash setup.sh node         # Start node daemon only
#   bash setup.sh stop         # Stop all WWRIG processes
#   bash setup.sh token        # Show the current auth token
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

# Load .env if present
ENV_FILE="$WWRIG_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        WWRIG  —  World Wide Rig  —  v0.2              ║${NC}"
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

# ── Token mode ────────────────────────────────────────────────────────────────
if [ "$MODE" = "token" ]; then
  if [ -f "$WWRIG_DIR/wwrig_config.json" ]; then
    TOKEN=$(python3 -c "import json; print(json.load(open('$WWRIG_DIR/wwrig_config.json')).get('auth_token', 'none'))")
    echo "  WWRIG Auth Token: $TOKEN"
  else
    echo "  Coordinator has not been started yet — no token generated."
  fi
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

  echo -e "${CYAN}  Starting WWRIG Coordinator on port 8081...${NC}"
  cd "$WWRIG_DIR/coordinator"
  nohup python3 server.py > "$WWRIG_DIR/coordinator.log" 2>&1 &
  COORD_PID=$!
  echo $COORD_PID > "$WWRIG_DIR/.coordinator.pid"

  # Wait for coordinator to be ready
  for i in $(seq 1 15); do
    if curl -s "http://localhost:8081/api/stats" &>/dev/null; then
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
    --coordinator "http://localhost:8081" \
    --contribution 10 \
    > "$WWRIG_DIR/node.log" 2>&1 &
  NODE_PID=$!
  echo $NODE_PID > "$WWRIG_DIR/.node.pid"
  sleep 2
  echo "  [OK] Node daemon running (PID $NODE_PID)"
fi

# ── Serve android node page ───────────────────────────────────────────────────
cp "$WWRIG_DIR/android-node/index.html" "$WWRIG_DIR/coordinator/static/mobile.html"

# ── Install SwiftBar / xBar menu bar plugin ───────────────────────────────────
SWIFTBAR_DIR="$HOME/Library/Application Support/com.ameba.SwiftBar/plugins"
XBAR_DIR="$HOME/Library/Application Support/xbar/plugins"
if [ -d "$SWIFTBAR_DIR" ]; then
  cp "$WWRIG_DIR/scripts/wwrig.10s.py" "$SWIFTBAR_DIR/wwrig.10s.py"
  echo "  [OK] SwiftBar plugin installed"
elif [ -d "$XBAR_DIR" ]; then
  cp "$WWRIG_DIR/scripts/wwrig.10s.py" "$XBAR_DIR/wwrig.10s.py"
  echo "  [OK] xBar plugin installed"
fi

# ── Read auth token for display ────────────────────────────────────────────────
AUTH_TOKEN_DISPLAY=""
if [ -f "$WWRIG_DIR/wwrig_config.json" ]; then
  AUTH_TOKEN_DISPLAY=$(python3 -c "import json; print(json.load(open('$WWRIG_DIR/wwrig_config.json')).get('auth_token', ''))" 2>/dev/null || true)
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 WWRIG IS LIVE                         ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║  Dashboard   : http://localhost:8081                  ║${NC}"
echo -e "${GREEN}║  Native GUI  : python3 coordinator/gui.py            ║${NC}"
echo -e "${GREEN}║  On your LAN : http://${LOCAL_IP}:8081           ║${NC}"
echo -e "${GREEN}║  Mobile Node : http://${LOCAL_IP}:8081/mobile.html ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
if [ -n "$AUTH_TOKEN_DISPLAY" ]; then
echo -e "${GREEN}║  Auth Token  : ${AUTH_TOKEN_DISPLAY}              ║${NC}"
echo -e "${GREEN}║  (required by nodes to join this coordinator)        ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
fi
echo -e "${GREEN}║  Add more nodes (other machines):                    ║${NC}"
echo -e "${GREEN}║  python3 node/daemon.py \\                            ║${NC}"
echo -e "${GREEN}║    --coordinator http://${LOCAL_IP}:8081 \\      ║${NC}"
if [ -n "$AUTH_TOKEN_DISPLAY" ]; then
echo -e "${GREEN}║    --token ${AUTH_TOKEN_DISPLAY}               ║${NC}"
else
echo -e "${GREEN}║    --contribution 10                             ║${NC}"
fi
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║  Docker deploy: docker compose up -d                  ║${NC}"
echo -e "${GREEN}║  Stop all:      bash setup.sh stop                    ║${NC}"
echo -e "${GREEN}║  Show token:    bash setup.sh token                   ║${NC}"
echo -e "${GREEN}║  Logs:          tail -f coordinator.log               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
