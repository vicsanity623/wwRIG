#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# WWRIG Fusion Launcher — World Wide Rig v0.3
# Launches and manages a Windows VM via VMware Fusion on macOS.
# Provides native 3D GPU acceleration and rock-stable Windows operation.
#
# Why VMware Fusion over QEMU on macOS?
#   - QEMU + HVF causes IRQL_NOT_LESS_OR_EQUAL crashes under load on Intel Macs
#   - VMware has mature, stable virtualization with proper 3D GPU acceleration
#   - No display refresher hacks needed — Fusion's window updates natively
#   - Windows detects all hardware automatically (no driver ISO needed)
#   - VMware Tools post-install gives seamless mouse, clipboard, shared folders
#
# Usage: bash fusion.sh <command> [args...]
#   Command 'windows': Start a Windows VM
#     fusion.sh windows <vcpus> <ram_mb> <resume_mode>
#     resume_mode : 0=fresh install (default), 1=resume existing VM
#
#   Command 'stop':   Stop the Windows VM (soft then hard)
#     fusion.sh stop
#
#   Command 'wipe':   Delete the Windows VM entirely
#     fusion.sh wipe
#
#   Command 'status': Check if the VM is running
#     fusion.sh status   → prints "running" or "stopped"
#
# Called automatically by the coordinator when a Windows session is requested.
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ─── Paths ───────────────────────────────────────────────────────────────────
WWRIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$WWRIG_DIR/vm/images"
VMWARE_DIR="$VM_DIR/wwrig-windows.vmwarevm"
VMX_PATH="$VMWARE_DIR/wwrig-windows.vmx"
VMDK_PATH="$VMWARE_DIR/wwrig-windows.vmdk"
LOG_DIR="$WWRIG_DIR/vm/logs"

VMRUN="/Applications/VMware Fusion.app/Contents/Public/vmrun"

mkdir -p "$VMWARE_DIR" "$LOG_DIR"

# ─── Helper: ensure Fusion app is running ────────────────────────────────────
ensure_fusion_running() {
  if ! pgrep -f "VMware Fusion" > /dev/null 2>&1; then
    echo "  Launching VMware Fusion..."
    open -a "VMware Fusion"
    for i in $(seq 1 15); do
      if pgrep -f "VMware Fusion" > /dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    echo "  [OK] VMware Fusion running"
  fi
}

# ─── Generate VMX configuration ─────────────────────────────────────────────
generate_vmx() {
  local vcpus="$1"
  local ram_mb="$2"
  local iso_path="$3"

  cat > "$VMX_PATH" << VMXEOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
guestOS = "windows10-64"
displayName = "wwrig.windows"
annotation = "WWRIG Windows VM - World Wide Rig"

numvcpus = "${vcpus}"
cpuid.coresPerSocket = "1"
vcpu.hotadd = "TRUE"

memsize = "${ram_mb}"

scsi0.present = "TRUE"
scsi0.virtualDev = "lsisas1068"
scsi0.slotNumber = "0"

scsi0:0.present = "TRUE"
scsi0:0.fileName = "wwrig-windows.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"
scsi0:0.mode = "persistent"
scsi0:0.redo = ""

vhv.enable = "TRUE"

ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"
ethernet0.wakeOnPcktRcv = "TRUE"
ethernet0.addressType = "generated"

usb.present = "TRUE"
usb.generic.autoconnect = "FALSE"
ehci.present = "TRUE"
xhci.present = "TRUE"

sound.present = "TRUE"
sound.virtualDev = "hdaudio"
sound.autodetect = "TRUE"

svga.present = "TRUE"
svga.vramSize = "268435456"
mks.enable3d = "TRUE"
svga.guestBackedPrimary = "TRUE"
svga.autodetect = "TRUE"
svga.maxWidth = "3840"
svga.maxHeight = "2160"

floppy0.present = "FALSE"
pref.autoAnswer = "TRUE"
powerType.powerOff = "soft"
powerType.reset = "soft"
powerType.suspend = "soft"
isolation.tools.hgfs.disable = "FALSE"
tools.syncTime = "TRUE"
time.synchronize.continue = "TRUE"
time.synchronize.restore = "TRUE"
time.synchronize.resume.disk = "TRUE"
time.synchronize.shrink = "TRUE"
time.synchronize.tools.startup = "TRUE"
VMXEOF
}

# ─── Attach or detach CD-ROM in VMX ──────────────────────────────────────────
set_cdrom() {
  local iso_path="$1"
  if [ -n "$iso_path" ] && [ -f "$iso_path" ]; then
    echo "  Attaching ISO: $(basename "$iso_path")"
    cat >> "$VMX_PATH" << CDEOF

ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "$iso_path"
ide1:0.autodetect = "TRUE"
CDEOF
  else
    cat >> "$VMX_PATH" << CDEOF

ide1:0.present = "FALSE"
CDEOF
  fi
}

# ─── Commands ────────────────────────────────────────────────────────────────

COMMAND="${1:-windows}"

case "$COMMAND" in
  windows)
    VCPUS="${2:-4}"
    RAM_MB="${3:-8192}"
    RESUME_MODE="${4:-0}"

    echo "╔═══════════════════════════════════════════════════╗"
    echo "║   WWRIG Fusion Launcher — v0.3                    ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo "  OS   : wwrig.windows"
    echo "  CPUs : ${VCPUS} vCPU"
    echo "  RAM  : ${RAM_MB}MB"
    echo "  GPU  : AMD Radeon Pro 5300 (hardware-accelerated)"
    echo "  Mode : $([ "$RESUME_MODE" = "1" ] && echo "RESUME" || echo "INSTALL")"
    echo ""

    if [ "$RESUME_MODE" != "1" ]; then
      # ── INSTALL MODE ──
      ISO_PATH="$VM_DIR/windows.iso"

      if [ ! -f "$ISO_PATH" ]; then
        echo "  [!!] Windows ISO not found at $ISO_PATH"
        echo "       Download from: https://www.microsoft.com/software-download/windows10"
        exit 1
      fi

      # Create virtual disk
      if [ ! -f "$VMDK_PATH" ]; then
        echo "  Creating 250GB virtual disk..."
        qemu-img create -f vmdk "$VMDK_PATH" 250G > /dev/null
        echo "  [OK] Virtual disk created (250GB)"
      fi

      # Generate VMX with ISO attached
      echo "  Generating VM configuration..."
      generate_vmx "$VCPUS" "$RAM_MB"
      set_cdrom "$ISO_PATH"
      echo "  [OK] VMX ready"

      # Start Fusion and VM
      ensure_fusion_running
      echo ""
      echo "  Starting Windows installation..."
      echo ""
      "$VMRUN" -T fusion start "$VMX_PATH" gui

      echo ""
      echo "  ╔═══════════════════════════════════════════════════╗"
      echo "  ║  wwrig.windows installing in VMware Fusion        ║"
      echo "  ║                                                   ║"
      echo "  ║  ─── What to do ───                               ║"
      echo "  ║  1. The Fusion window shows Windows Setup         ║"
      echo "  ║  2. Install Windows normally                      ║"
      echo "  ║  3. After desktop appears, install VMware Tools   ║"
      echo "  ║     from Fusion menu: VM → Install VMware Tools   ║"
      echo "  ║  4. Reboot for full GPU acceleration & seamless   ║"
      echo "  ║     mouse, clipboard, shared folders              ║"
      echo "  ║                                                   ║"
      echo "  ║  When done, press RESUME in wwRIG dashboard       ║"
      echo "  ╚═══════════════════════════════════════════════════╝"
    else
      # ── RESUME MODE ──
      if [ ! -f "$VMX_PATH" ]; then
        echo "  [!!] No Windows VM found at $VMX_PATH"
        echo "       Install Windows first via the dashboard."
        exit 1
      fi

      echo "  Resuming Windows VM..."
      ensure_fusion_running
      echo ""
      "$VMRUN" -T fusion start "$VMX_PATH" gui

      echo ""
      echo "  ╔═══════════════════════════════════════════════════╗"
      echo "  ║  wwrig.windows resumed in VMware Fusion           ║"
      echo "  ║                                                   ║"
      echo "  ║  GPU acceleration : ENABLED (host AMD Radeon)     ║"
      echo "  ║  Display          : Native Fusion window          ║"
      echo "  ║  Mouse            : Seamless (no grab needed)     ║"
      echo "  ║                                                   ║"
      echo "  ║  To focus the window, click the VM in Fusion      ║"
      echo "  ╚═══════════════════════════════════════════════════╝"
    fi
    ;;

  stop)
    echo "  Stopping wwrig.windows..."
    if [ -f "$VMX_PATH" ]; then
      "$VMRUN" -T fusion stop "$VMX_PATH" soft 2>/dev/null || \
      "$VMRUN" -T fusion stop "$VMX_PATH" hard 2>/dev/null || true
      echo "  [OK] VM stopped"
    else
      echo "  [OK] No VM to stop"
    fi
    ;;

  wipe)
    echo "  ── Wiping wwrig.windows ──"
    # Force stop
    if [ -f "$VMX_PATH" ]; then
      echo "  Stopping VM..."
      "$VMRUN" -T fusion stop "$VMX_PATH" hard 2>/dev/null || true
      sleep 2
      echo "  Deleting VM..."
      "$VMRUN" -T fusion deleteVM "$VMX_PATH" 2>/dev/null || true
    fi
    # Clean up any leftover files
    rm -rf "$VMWARE_DIR" 2>/dev/null || true
    rm -f "$VM_DIR"/wwrig-windows.* 2>/dev/null || true
    echo "  [OK] Windows VM wiped"
    ;;

  status)
    if [ -f "$VMX_PATH" ]; then
      if "$VMRUN" -T fusion list 2>/dev/null | grep -qF "$VMX_PATH"; then
        echo "running"
      else
        echo "stopped"
      fi
    else
      echo "absent"
    fi
    ;;

  *)
    echo "  [!!] Unknown command: $COMMAND"
    echo "       Usage: bash fusion.sh <windows|stop|wipe|status> [args...]"
    echo ""
    echo "  Commands:"
    echo "    fusion.sh windows <vcpus> <ram_mb> <resume_mode>   Start VM"
    echo "    fusion.sh stop                                     Stop VM"
    echo "    fusion.sh wipe                                     Delete VM"
    echo "    fusion.sh status                                   Check VM state"
    exit 1
    ;;
esac
