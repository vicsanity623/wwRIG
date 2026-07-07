# WWRIG — World Wide Rig v0.2.2

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
- **Kill button** per running session (also kills QEMU + websockify)
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

### Windows 10/11:
1. Download a Windows 10/11 ISO from Microsoft
2. Place it in `vm/images/windows.iso` (or symlink to your downloaded file)
3. The VirtIO drivers ISO is auto-downloaded on first launch
4. From the GUI: click **Launch wwrig.win64**
5. A native QEMU window appears — click inside and press any key to boot from DVD
6. At the "Where to install Windows" screen, click **Load driver → Browse**
7. Select the VirtIO CD-ROM → `viostor\w10\amd64` → OK (disk appears)
8. Select the disk and install

> **Mouse capture**: Click inside the QEMU window to capture the mouse.
> **Release mouse**: Press **Control + Option** (both keys together).
> **Note**: macOS QEMU has a known VGA display refresh bug. wwRIG auto-starts a
> helper script (`vm/refresh_display.py`) that clicks View→VGA every 0.5s to
> keep the display up to date.

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
