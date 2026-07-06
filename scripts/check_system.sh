#!/bin/bash
# WWRIG System Check — shows what this machine will contribute

echo ""
echo "══════════════════════════════════════════════"
echo "  WWRIG System Check — World Wide Rig v0.1"
echo "══════════════════════════════════════════════"
echo ""

# CPU
if [[ "$(uname)" == "Darwin" ]]; then
  CPU_BRAND=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  CPU_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "?")
  CPU_THREADS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo "?")
  CPU_FREQ=$(sysctl -n hw.cpufrequency 2>/dev/null || echo "0")
  CPU_GHZ=$(echo "scale=2; $CPU_FREQ / 1000000000" | bc 2>/dev/null || echo "?")
  RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  RAM_GB=$(echo "scale=1; $RAM_BYTES / 1073741824" | bc 2>/dev/null || echo "?")
  GPU=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model:" | head -1 | sed 's/.*: //')
  VRAM=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "VRAM" | head -1 | sed 's/.*: //')
else
  CPU_BRAND=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "Unknown")
  CPU_CORES=$(nproc --all 2>/dev/null || echo "?")
  CPU_THREADS="$CPU_CORES"
  RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "?")
  GPU=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1 | sed 's/.*: //' || echo "N/A")
  VRAM="N/A"
fi

echo "  CPU    : $CPU_BRAND"
echo "  Cores  : ${CPU_CORES}c / ${CPU_THREADS}t"
echo "  RAM    : ${RAM_GB} GB"
echo "  GPU    : ${GPU:-N/A}"
echo "  VRAM   : ${VRAM:-N/A}"
echo ""

# Network
LOCAL_IP=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -1 || echo "unknown")
echo "  Local IP : $LOCAL_IP"
echo ""

# Dependencies
echo "  Dependencies:"
python3 --version 2>/dev/null && echo "  [OK] Python 3" || echo "  [!!] Python 3 missing"
pip3 --version &>/dev/null && echo "  [OK] pip3"     || echo "  [!!] pip3 missing"
qemu-system-x86_64 --version 2>/dev/null | head -1 | sed 's/^/  [OK] /' || echo "  [--] QEMU (optional)"
curl --version &>/dev/null && echo "  [OK] curl"     || echo "  [--] curl missing"

echo ""
echo "  At 10% contribution, this machine provides:"
RAM_10=$(echo "scale=1; $RAM_GB * 0.10" | bc 2>/dev/null || echo "?")
CORES_10=$(echo "$CPU_CORES * 10 / 100" | awk '{printf "%d", $0}' 2>/dev/null || echo "?")
echo "    ${CORES_10:-1}+ CPU cores | ${RAM_10}+ GB RAM"
echo ""
echo "══════════════════════════════════════════════"
echo ""

