#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG VM Launcher — World Wide Rig v0.2.1
# Launches a QEMU virtual machine and exposes it via noVNC in the browser.
#
# Usage: bash launch.sh <os_type> <vcpus> <ram_mb> <vnc_port>
#   os_type  : linux | windows | macos
#   vcpus    : number of virtual CPU cores
#   ram_mb   : RAM in MB (e.g. 4096)
#   vnc_port : VNC display port (e.g. 5900)
#
# Called automatically by the coordinator when a session is requested.
# ═══════════════════════════════════════════════════════════════════════════════

OS_TYPE="${1:-linux}"
VCPUS="${2:-4}"
RAM_MB="${3:-4096}"
VNC_PORT="${4:-5900}"
WS_PORT=$((VNC_PORT + 100))

WWRIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$WWRIG_DIR/vm/images"
NOVNC_DIR="$WWRIG_DIR/vm/novnc"
LOG_DIR="$WWRIG_DIR/vm/logs"
DISPLAY_NUM=$((VNC_PORT - 5900))

mkdir -p "$VM_DIR" "$LOG_DIR"

echo "╔═══════════════════════════════════════════════════╗"
echo "║      WWRIG VM Launcher — World Wide Rig v0.2      ║"
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
if ! command -v qemu-system-x86_64 &>/dev/null; then
  echo "  [!!] QEMU not found. Install with: brew install qemu"
  exit 1
fi
QEMU="qemu-system-x86_64"

# ── Platform-specific flags ──────────────────────────────────────────────────
IS_MACOS=false
if [[ "$(uname)" == "Darwin" ]]; then
  IS_MACOS=true
fi

# Helper: run QEMU with proper daemonization.
# On macOS with Cocoa display we cannot use -daemonize (breaks window creation),
# so we run in background via nohup instead.
run_qemu() {
  local pidfile="$1"; shift
  if $IS_MACOS; then
    nohup "$QEMU" "$@" > "$LOG_DIR/qemu-stdout.log" 2> "$LOG_DIR/qemu-stderr.log" &
    local pid=$!
    echo $pid > "$pidfile"
    disown $pid 2>/dev/null
  else
    "$QEMU" "$@" -daemonize -pidfile "$pidfile"
  fi
}

# ── Check VNC port availability ────────────────────────────────────────────────
if nc -z localhost "$VNC_PORT" 2>/dev/null; then
  echo "  [!!] Port ${VNC_PORT} is already in use. Choose a different port."
  exit 1
fi

# ── ISO / Image Setup ─────────────────────────────────────────────────────────
case "$OS_TYPE" in
  linux)
    ISO_NAME="alpine-virt-3.19.1-x86_64.iso"
    ISO_PATH="$VM_DIR/$ISO_NAME"
    ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.1-x86_64.iso"
    DISK_IMG="$VM_DIR/wwrig-linux.qcow2"

    if [ ! -f "$ISO_PATH" ]; then
      echo "  Downloading Alpine Linux 3.19 (~60MB)..."
      if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$ISO_PATH" "$ISO_URL" || { echo "Download failed"; exit 1; }
      elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$ISO_PATH" "$ISO_URL" || { echo "Download failed"; exit 1; }
      else
        echo "  [!!] curl or wget required."
        exit 1
      fi
    fi

    if [ ! -f "$DISK_IMG" ]; then
      echo "  Creating 20GB persistent disk..."
      qemu-img create -f qcow2 "$DISK_IMG" 20G
    fi

    # Extract kernel + initrd from ISO for direct boot (console=tty0 fixes VNC display updates)
    KERNEL="$VM_DIR/vmlinuz"
    INITRD="$VM_DIR/initramfs"
    if [ ! -f "$KERNEL" ] || [ ! -f "$INITRD" ]; then
      echo "  Extracting kernel from ISO..."
      TMPMNT="/tmp/alpine-mnt-$$"
      mkdir -p "$TMPMNT"
      bsdtar xf "$ISO_PATH" -C "$TMPMNT" 2>/dev/null
      cp "$TMPMNT"/boot/vmlinuz-virt "$KERNEL" 2>/dev/null
      cp "$TMPMNT"/boot/initramfs-virt "$INITRD" 2>/dev/null
      rm -rf "$TMPMNT"
    fi

    echo ""
    echo "  ──────────────────────────────────────────────────"
    echo "  [OK] wwrig.linux is starting..."
    echo "       OS: Alpine Linux 3.19"
    echo "       Login: root (no password by default)"
    echo "  ──────────────────────────────────────────────────"
    echo ""
    echo "  noVNC will be available at:"
    echo "  → http://localhost:${WS_PORT}/wwrig.html"
    echo ""

    # Launch QEMU (direct kernel boot with console=tty0 for proper VNC updates)
    run_qemu "$LOG_DIR/wwrig-linux-${VNC_PORT}.pid" \
      -name "wwrig.linux" \
      -m "${RAM_MB}M" \
      -smp "${VCPUS}" \
      $QEMU_ACCEL \
      -cpu host \
      -kernel "$KERNEL" \
      -initrd "$INITRD" \
      -append "console=tty0 console=ttyS0 alpine_dev=/dev/sr0:iso9660 modloop=/boot/modloop-virt modules=loop,squashfs,sd-mod,usb-storage quiet" \
      -drive file="$DISK_IMG",format=qcow2,if=virtio \
      -cdrom "$ISO_PATH" \
      -vga std \
      -vnc ":${DISPLAY_NUM}" \
      $([ "$IS_MACOS" = true ] && echo "-display cocoa") \
      -k en-us \
      -device virtio-net-pci,netdev=net0 \
      -netdev user,id=net0 \
      -usb -device usb-tablet -device usb-kbd

    # On macOS, start periodic display refresher (Cocoa VGA bug workaround)
    if $IS_MACOS; then
      REFRESHER_PIDFILE="$LOG_DIR/wwrig-refresh-${VNC_PORT}.pid"
      nohup python3 "$WWRIG_DIR/vm/refresh_display.py" 0.5 \
        > "$LOG_DIR/refresh.log" 2>&1 &
      echo $! > "$REFRESHER_PIDFILE"
      echo "  [OK] Display refresher started (PID $!)"
    fi

    # Check if QEMU started
    sleep 1
    if ! nc -z localhost "$VNC_PORT" 2>/dev/null; then
      echo "  [!!] QEMU failed to start. Check logs."
      exit 1
    fi
    ;;

  windows)
    ISO_NAME="windows.iso"
    ISO_PATH="$VM_DIR/$ISO_NAME"
    DISK_IMG="$VM_DIR/wwrig-windows.qcow2"
    VIRTIO_ISO="$VM_DIR/virtio-win.iso"

    if [ ! -f "$ISO_PATH" ]; then
      echo "  [!!] Windows ISO not found at $ISO_PATH"
      echo "       Download from: https://www.microsoft.com/software-download/windows11"
      exit 1
    fi
    if [ ! -f "$VIRTIO_ISO" ]; then
      echo "  [!!] VirtIO drivers ISO not found at $VIRTIO_ISO"
      echo "       Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/"
      exit 1
    fi
    [ ! -f "$DISK_IMG" ] && qemu-img create -f qcow2 "$DISK_IMG" 40G

    echo ""
    echo "  ──────────────────────────────────────────────────"
    echo "  [OK] wwrig.windows is starting..."
    echo "  ──────────────────────────────────────────────────"
    echo ""
    echo "  → http://localhost:${WS_PORT}/wwrig.html"
    echo ""

    run_qemu "$LOG_DIR/wwrig-windows-${VNC_PORT}.pid" \
      -name "wwrig.windows" \
      -m "${RAM_MB}M" \
      -smp "${VCPUS}" \
      $QEMU_ACCEL \
      -cpu host \
      -drive file="$DISK_IMG",format=qcow2,if=virtio \
      -cdrom "$ISO_PATH" \
      -drive file="$VIRTIO_ISO",index=1,media=cdrom \
      -boot order=d \
      -vga std \
      -vnc ":${DISPLAY_NUM}" \
      -display cocoa \
      -k en-us \
      -global PIIX4_PM.disable_s3=1 \
      -global PIIX4_PM.disable_s4=1 \
      -device virtio-net-pci,netdev=net0 \
      -netdev user,id=net0 \
      -usb -device usb-mouse -device usb-kbd
    ;;

  macos)
    echo "  [!!] macOS on Intel QEMU requires a macOS installer ISO."
    echo ""
    echo "  Create one:"
    echo "    Download macOS from App Store, then:"
    echo "    hdiutil create -o /tmp/macOS.iso -size 16G -layout SPUD -fs HFS+J"
    echo "    hdiutil attach /tmp/macOS.iso -noverify -mountpoint /tmp/macos_mount"
    echo "    sudo /Applications/Install\\ macOS.app/Contents/Resources/createinstallmedia --volume /tmp/macos_mount --nointeraction"
    echo "    hdiutil detach /tmp/macos_mount"
    echo "    mv /tmp/macOS.iso vm/images/macos.iso"
    echo ""
    echo "  Note: macOS VMs on Intel QEMU require macOS Monterey or older"
    echo "  (Ventura+ requires Apple Silicon / Virtualization.framework)"
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
