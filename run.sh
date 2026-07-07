#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG Run Script — World Wide Rig v0.2.2
# One-command kill-all + restart with two terminals (coordinator + GUI).
# ═══════════════════════════════════════════════════════════════════════════════

WWRIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        WWRIG  —  World Wide Rig  —  v0.2.2            ║${NC}"
echo -e "${GREEN}║        Run Script (kill + restart)                     ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Kill everything ────────────────────────────────────────────────────────────
echo -e "${YELLOW}  Killing all WWRIG processes...${NC}"
pkill -f "qemu-system"         2>/dev/null || true
pkill -f websockify            2>/dev/null || true
pkill -f refresh_display       2>/dev/null || true
pkill -f "coordinator/server"  2>/dev/null || true
pkill -f "node/daemon"         2>/dev/null || true
pkill -f "gui.py"              2>/dev/null || true
pkill -f "server.py"           2>/dev/null || true
# Stop Fusion VM if running
FUSION_SCRIPT="$WWRIG_DIR/vm/fusion.sh"
[ -f "$FUSION_SCRIPT" ] && bash "$FUSION_SCRIPT" stop > /dev/null 2>&1 || true
# Also kill by port in case process names don't match
lsof -ti:8081,6000,6001,5900,5901,5902 | xargs kill -9 2>/dev/null || true
echo -e "  ${DIM}[OK] All processes terminated${NC}"

# ── Clean up stale files ──────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}  Cleaning up...${NC}"
rm -f "$WWRIG_DIR"/vm/logs/*.pid "$WWRIG_DIR"/vm/logs/*.log 2>/dev/null
rm -f /tmp/wwrig_vm_*.log /tmp/wwrig_*.png 2>/dev/null
echo -e "  ${DIM}[OK] Logs, PIDs, temp files cleaned${NC}"

sleep 2

# ── Start coordinator ─────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}  Opening terminal: Coordinator...${NC}"
osascript -e "
tell application \"Terminal\"
  activate
  set newTab to do script \"cd '$WWRIG_DIR/coordinator' && python3 server.py\"
  set custom title of newTab to \"wwRIG Coordinator\"
end tell
"
sleep 3

# ── Start node daemon (background) ────────────────────────────────────────────
# Read token from config if available
TOKEN=""
if [ -f "$WWRIG_DIR/wwrig_config.json" ]; then
  TOKEN=$(python3 -c "import json; print(json.load(open('$WWRIG_DIR/wwrig_config.json')).get('auth_token', ''))" 2>/dev/null || true)
fi
if [ -z "$TOKEN" ]; then
  TOKEN="be4a2fc9512d4089"
fi

python3 "$WWRIG_DIR/node/daemon.py" \
  --coordinator "http://localhost:8081" \
  --token "$TOKEN" \
  --contribution 75 > /dev/null 2>&1 &
echo -e "  ${CYAN}[OK]${NC} Node daemon started"

# Wait for coordinator
for i in $(seq 1 10); do
  if curl -s "http://localhost:8081/api/stats" &>/dev/null; then
    echo -e "  ${CYAN}[OK]${NC} Coordinator online"
    break
  fi
  sleep 1
done

# ── Start GUI ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}  Opening terminal: Native GUI...${NC}"
osascript -e "
tell application \"Terminal\"
  activate
  set newTab to do script \"cd '$WWRIG_DIR' && python3 coordinator/gui.py\"
  set custom title of newTab to \"wwRIG GUI\"
end tell
"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  WWRIG running — two Terminal tabs opened            ║${NC}"
echo -e "${GREEN}║  1. Coordinator  (background: node daemon)           ║${NC}"
echo -e "${GREEN}║  2. Native GUI                                       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
