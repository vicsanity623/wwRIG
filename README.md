# WWRIG — World Wide Rig v0.3

### *Distributed computing, one node at a time.*

```
www   = world wide web    → anyone can host a webpage
wwrig = world wide rig    → anyone can contribute compute
```

---

## What This Is (Honest)

WWRIG is a **local-network distributed computing prototype**. It lets multiple devices on your LAN connect as "nodes" to pool their CPU/RAM stats into a live dashboard, and launch real VMs (Linux, Windows) on your own machine.

### What actually works today:
- Multiple devices (Mac, Linux, Android phones) register as nodes
- Live dashboard with aggregate pool specs (cores, RAM, VRAM)
- **Native macOS GUI** (`coordinator/gui.py`) — replaces browser dashboard
- **Real Alpine Linux VM** launched via QEMU with HVF/KVM acceleration
- **Real Windows 10/11 VM** (UEFI + VirtIO drivers, install via VNC)
- VMs open in **native QEMU Cocoa windows** on macOS (no browser needed)
- Built-in **display refresher** (workaround for macOS QEMU VGA update bug)
- **Kill / Resume / Wipe** buttons per session and disk
- **Display refresher** auto-starts for real-time QEMU Cocoa display
- Display refresher runs at 0.01s (100fps) for smooth real-time updates
- Auth tokens to control who can join your coordinator
- Auto-resolving VNC port conflicts
- Periodic display refresh (every 2.5s in browser)
- Docker deployment for the coordinator
- macOS menubar plugin (SwiftBar/xBar) showing pool stats + VM sessions

### What is display-only (v0.x limitations):
- The VM runs **solely on the coordinator's machine** — it cannot use other nodes' CPU/RAM
- The "pooled specs" show what every node *could* contribute, not what a VM actually uses
- Android phones contribute monitoring data, not actual compute cycles
- No distributed scheduling, no workload distribution

---

## Quick Start (Local Network)

```bash
# Prerequisites
brew install qemu            # for VM sessions
pip3 install psutil requests  # for node daemon

# Start the full stack (coordinator + node)
bash setup.sh

# Open native GUI
python3 coordinator/gui.py

# Or open browser dashboard
open http://localhost:8081
```

### Adding nodes from other machines:
```bash
python3 node/daemon.py \
  --coordinator http://YOUR_IMAC_IP:8081 \
  --token ASK_THE_COORDINATOR_OWNER_FOR_TOKEN
```

### Mobile (Android) node:
Open `http://YOUR_IMAC_IP:8081/mobile.html` on your phone browser.

### Docker deployment:
```bash
docker compose up -d
```

---

## Launching VMs

### Linux (Alpine 3.19):
```bash
# From the GUI: click "Launch wwrig.linux"
# Or manually:
bash vm/launch.sh linux 2 4096 5901
```

### Windows 10/11 — Clean Install (Stable + Smooth):

This guide installs Windows with the **stable e1000 NIC** (native driver) and optional **virtio-gpu** (smooth display). No crash-prone virtio-net drivers.

> **Before you start**: WIPE the existing disk via the GUI (WIPE button in the DISKS section) or:
> ```bash
> rm -f vm/images/wwrig-windows.qcow2
> ```

#### Step 1 — Fresh install (will use ISO + auto-detect disk):

1. Make sure `vm/images/windows.iso` exists (symlink to your Windows 10/11 ISO)
2. From the wwRIG GUI, click **Install Windows**
3. A native QEMU Cocoa window appears
4. At "Windows Setup", choose your language and click **Next → Install now**
5. When asked for a product key, click **"I don't have a product key"** (you can activate later)
6. At "Which type of installation do you want?", choose **Custom: Install Windows only (advanced)**
7. Select the **unallocated 40GB drive** and click **Next**
   - The disk (AHCI/SATA) is detected automatically — **no Load Driver step needed**
8. Windows copies files and reboots several times (automatically)

#### Step 2 — OOBE (first login):

1. After install, Windows asks for region, keyboard, and account creation
2. At the "Connect to network" screen, click **"I don't have internet"** (e1000 NIC has no driver yet — we'll install it later, or click **"Continue with limited setup"**)
3. Create a local user account and password
4. Windows prepares your desktop

#### Step 3 — Install display driver (smooth graphics, optional):

For ultra-smooth real-time display with `-vga virtio` (does NOT load virtio-net or other crash-prone drivers):

1. Open **Device Manager** (right-click Start → Device Manager)
2. Find **"Microsoft Basic Display Adapter"** under **Display adapters**
3. Right-click → **Update driver → Browse my computer for drivers**
4. Click **Browse** and navigate to `D:\` (VirtIO CD-ROM)
5. Check **"Include subfolders"** → click **Next**
6. Windows finds the **VirtIO GPU driver** and installs it
7. **Restart the VM** (from GUI, kill session → RESUME)
8. The display is now GPU-accelerated, smooth, and real-time

> **Don't** run `virtio-win-gt-x64.msi` — that installs ALL VirtIO drivers including the crash-prone netkvm and balloon drivers.

#### Step 4 — Network driver (optional):

The e1000 NIC uses Windows' built-in Intel PRO/1000 driver. It's usually installed automatically. To verify:
- Open **Device Manager** → **Network adapters**
- You should see **"Intel(R) PRO/1000 MT Network Connection"**
- If you see an unknown device, right-click → **Update driver → Search automatically**
- Or download the Intel PRO/1000 driver manually

#### Quick Reference — Disk Management:

| Action | How |
|--------|-----|
| **Install fresh** | Click **Install Windows** in the GUI |
| **Resume existing** | Click **RESUME** in the DISKS section |
| **Wipe & reinstall** | Click **WIPE** in the DISKS section, then Install |

> **Mouse & Display**: The Apple Magic Mouse right-click may not work with `usb-tablet`. Use **Shift+F10** for right-click context menu in Windows. The display refresher runs at 0.01s (100fps) for smooth real-time updates on macOS.

#### GPU Memory Notes:

Your iMac has a **Radeon Pro 5300 (4GB VRAM)**. The VM's virtio-gpu driver does **not** use your host GPU directly — it's emulated in software. The VRAM limit is irrelevant since macOS QEMU lacks OpenGL/virgl support. The `-vga virtio` is purely a paravirtualized framebuffer, not GPU passthrough.

---

## Kill Everything & Restart

### Kill all processes:

```bash
bash setup.sh stop
# or manually:
pkill -f "qemu-system"       # kill running VMs
pkill -f websockify          # kill noVNC proxies
pkill -f "coordinator/server" # kill coordinator
pkill -f "node/daemon"       # kill node daemon
pkill -f refresh_display     # kill display refresher
```

### Start fresh:

```bash
cd coordinator && nohup python3 server.py &
python3 node/daemon.py --coordinator http://localhost:8081 --token TOKEN --contribution 20
python3 coordinator/gui.py          # native GUI
# or: open http://localhost:8081    # browser dashboard
```

---

## Project Structure

```
wwRIG/
├── setup.sh                  ← one-command launcher
├── coordinator/
│   ├── server.py             ← FastAPI coordinator (the brain)
│   ├── gui.py                ← Native macOS GUI (tkinter)
│   └── static/
│       ├── index.html        ← browser dashboard
│       └── mobile.html       ← mobile node page
├── node/
│   └── daemon.py             ← node reporter (run on any machine)
├── android-node/
│   └── index.html            ← mobile node source
├── vm/
│   ├── launch.sh             ← QEMU + noVNC launcher (Linux/Windows/macOS)
│   ├── setup_novnc.sh        ← WebSocket proxy
│   ├── refresh_display.py    ← macOS QEMU display refresher workaround
│   ├── images/               ← ISOs and disk images
│   │   ├── windows.iso       ← symlink to your Windows 10/11 ISO
│   │   └── virtio-win.iso    ← VirtIO drivers for Windows (auto-downloaded)
│   ├── logs/                 ← QEMU, noVNC, and refresher logs
│   └── novnc/                ← noVNC web client (auto-installed)
├── scripts/
│   ├── check_system.sh
│   └── wwrig.10s.py          ← SwiftBar/xBar menubar plugin
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| Python 3.10+ | Runtime |
| fastapi + uvicorn | Coordinator API |
| psutil + requests | Node system stats |
| qemu | VM runtime (brew install qemu) |
| noVNC + websockify | Browser VNC (auto-installed) |
| Tailscale | Public internet access (optional) |

---

## License

MIT — see LICENSE

---

*WWRIG — the internet is a library. The rig is the computer.*
