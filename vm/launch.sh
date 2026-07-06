#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG VM Launcher — World Wide Rig v0.1
# Launches a QEMU virtual machine and exposes it via noVNC in the browser.
#
# Usage: bash launch.sh <os_type> <vcpus> <ram_mb> <vnc_port>
#   os_type  : linux | windows | macos
#   vcpus    : number of virtual CPU cores
#   ram_mb   : RAM in MB (e.g. 4096)
#   vnc_port : VNC display port (e.g. 5900)
#
# Called automatically by the coordinator when a session is requested.
# You can also run it manually for testing:
#   bash vm/launch.sh linux 4 4096 5900
# ═══════════════════════════════════════════════════════════════════════════════

set -e

OS_TYPE="${1:-linux}"
VCPUS="${2:-4}"
RAM_MB="${3:-4096}"
VNC_PORT="${4:-5900}"
WS_PORT=$((VNC_PORT + 100))   # noVNC WebSocket port

WWRIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$WWRIG_DIR/vm/images"
NOVNC_DIR="$WWRIG_DIR/vm/novnc"
LOG_DIR="$WWRIG_DIR/vm/logs"
DISPLAY_NUM=$((VNC_PORT - 5900))  # QEMU display :N

mkdir -p "$VM_DIR" "$LOG_DIR"

echo "╔═══════════════════════════════════════════════════╗"
echo "║      WWRIG VM Launcher — World Wide Rig v0.1      ║"
echo "╚═══════════════════════════════════════════════════╝"
echo "  OS Type    : wwrig.${OS_TYPE}"
echo "  vCPUs      : ${VCPUS}"
echo "  RAM        : ${RAM_MB}MB"
echo "  VNC Port   : :${DISPLAY_NUM} (port ${VNC_PORT})"
echo "  noVNC Port : ${WS_PORT}"
echo ""

# ── Detect Accelerator ────────────────────────────────────────────────────────
QEMU_ACCEL=""
if [[ "$(uname)" == "Darwin" ]]; then
  # Intel Mac: use HVF (Apple Hypervisor Framework) — native speed
  QEMU_ACCEL="-accel hvf"
  echo "  Accelerator: HVF (Apple Hypervisor Framework)"
elif command -v kvm-ok &>/dev/null && kvm-ok &>/dev/null; then
  QEMU_ACCEL="-accel kvm"
  echo "  Accelerator: KVM (Linux)"
else
  QEMU_ACCEL="-accel tcg,thread=multi"
  echo "  Accelerator: TCG (software, slower)"
fi

# ── QEMU Binary ───────────────────────────────────────────────────────────────
if command -v qemu-system-x86_64 &>/dev/null; then
  QEMU="qemu-system-x86_64"
else
  echo ""
  echo "  [!!] QEMU not found. Install with:"
  echo "       brew install qemu        (macOS)"
  echo "       sudo apt install qemu-kvm (Linux)"
  echo ""
  exit 1
fi

# ── ISO / Image Setup ─────────────────────────────────────────────────────────
case "$OS_TYPE" in
  linux)
    ISO_NAME="alpine-virt-3.19.1-x86_64.iso"
    ISO_PATH="$VM_DIR/$ISO_NAME"
    ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.1-x86_64.iso"
    DISK_IMG="$VM_DIR/wwrig-linux.qcow2"

    # Download Alpine if needed (tiny: ~60MB)
    if [ ! -f "$ISO_PATH" ]; then
      echo "  Downloading Alpine Linux 3.19 (~60MB)..."
      if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$ISO_PATH" "$ISO_URL" || { echo "Download failed"; exit 1; }
      elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$ISO_PATH" "$ISO_URL" || { echo "Download failed"; exit 1; }
      else
        echo "  [!!] curl or wget required. Install with: brew install curl"
        exit 1
      fi
    fi

    # Create persistent disk if it doesn't exist
    if [ ! -f "$DISK_IMG" ]; then
      echo "  Creating 20GB persistent disk..."
      qemu-img create -f qcow2 "$DISK_IMG" 20G
    fi

    echo ""
    echo "  ──────────────────────────────────────────────────"
    echo "  [OK] wwrig.linux is starting..."
    echo "       OS: Alpine Linux 3.19"
    echo "       Login: root (no password by default)"
    echo "  ──────────────────────────────────────────────────"
    echo ""
    echo "  noVNC will be available at:"
    echo "  → http://localhost:${WS_PORT}/vnc.html"
    echo ""

    # Launch QEMU
    "$QEMU" \
      -name "wwrig.linux" \
      -m "${RAM_MB}M" \
      -smp "${VCPUS}" \
      $QEMU_ACCEL \
      -cpu host \
      -drive file="$DISK_IMG",format=qcow2,if=virtio \
      -cdrom "$ISO_PATH" \
      -boot order=cd,once=d \
      -vga std \
      -vnc ":${DISPLAY_NUM}" \
      -device virtio-net-pci,netdev=net0 \
      -netdev user,id=net0 \
      -usb -device usb-tablet \
      -daemonize \
      -pidfile "$LOG_DIR/wwrig-linux-${VNC_PORT}.pid" &

    ;;

  windows)
    echo "  [!!] Windows session requires:"
    echo "       1. A Windows 11 ISO in vm/images/"
    echo "       2. VirtIO drivers ISO"
    echo "       3. A valid Windows licence from your host node"
    echo ""
    echo "  Once you have the ISO:"
    echo "    1. Place it at: vm/images/windows11.iso"
    echo "    2. Re-run this script"
    exit 0
    ;;

  macos)
    echo "  [!!] macOS virtualization requires:"
    echo "       - Apple Silicon host (for native speed)"
    echo "       - UTM or Tart on macOS 13+ hosts"
    echo ""
    echo "  Install UTM: https://mac.getutm.app/"
    exit 0
    ;;

  *)
    echo "  [!!] Unknown OS type: $OS_TYPE"
    echo "       Supported: linux | windows | macos"
    exit 1
    ;;
esac

# ── Wait for QEMU VNC ─────────────────────────────────────────────────────────
echo "  Waiting for QEMU VNC server on port ${VNC_PORT}..."
for i in $(seq 1 20); do
  if nc -z localhost "$VNC_PORT" 2>/dev/null; then
    echo "  [OK] VNC server ready"
    break
  fi
  sleep 1
done

# ── noVNC ─────────────────────────────────────────────────────────────────────
bash "$WWRIG_DIR/vm/setup_novnc.sh" "$VNC_PORT" "$WS_PORT"
