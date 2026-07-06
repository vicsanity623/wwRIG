# WWRIG — World Wide Rig v0.1
### *The distributed computing network that lets anyone access a supercomputer from a browser.*

```
www   = world wide web    → anyone can host a webpage
wwrig = world wide rig    → anyone can contribute compute
```

---

## What This Is

WWRIG is a peer-to-peer distributed computing network. Every machine that runs the node daemon donates a small fraction of its CPU, GPU, and RAM to the WWRIG pool — just like how servers around the world host websites for the WWW. That pooled horsepower is then assembled into a temporary OS session that any user can access from their browser, running faster than any single machine they could own.

**This prototype** runs the full stack on your local network: your iMac as the coordinator + primary node, and your Android phone as a second node. The dashboard shows live combined specs. You can launch a temporary Linux session and access it in your browser via noVNC.

---

## Quick Start (iMac)

```bash
# 1. Clone / unzip the project
cd wwrig

# 2. Check your system
bash scripts/check_system.sh

# 3. Start everything
bash setup.sh

# 4. Open the dashboard
open http://localhost:8081
```

That's it. The coordinator starts, your iMac registers as a node, and the dashboard goes live.

---

## Adding Your Android Phone as a Second Node

1. Make sure your phone is on the **same Wi-Fi** as your iMac.
2. Find your iMac's local IP (shown in the setup output, or run `ipconfig getifaddr en0`).
3. On your phone, open a browser and go to:
   ```
   http://YOUR_IMAC_IP:8081/mobile.html
   ```
4. Enter the coordinator URL (`http://YOUR_IMAC_IP:8081`) and tap **Connect to WWRIG**.
5. Your phone appears as a node in the dashboard immediately.

---

## Launching a wwrig.linux Session

1. With at least one node online, go to the dashboard.
2. Click **▶ Launch** under `wwrig.linux`.
3. The modal shows the allocated vCPU and RAM drawn from the wwrig pool.
4. Click **CONFIRM LAUNCH**.
5. After ~15 seconds, an **OPEN DISPLAY →** link appears. Click it.
6. The Alpine Linux OS loads in your browser — fully interactive, keyboard and mouse, no install.

> **QEMU required for real sessions.**  
> Install with: `brew install qemu`  
> Without QEMU, the session launches in *demo mode* (specs display only, no OS window).

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   WWRIG COORDINATOR                          │
│              FastAPI  ·  port 8081                           │
│                                                              │
│  /api/nodes/register   ← nodes announce themselves          │
│  /api/nodes/heartbeat  ← nodes send live usage every 5s     │
│  /api/stats            ← aggregate pool specs (polled by UI) │
│  /api/vm/launch        ← provision a temp OS session         │
│  /api/vm/sessions      ← list active sessions                │
│  /api/log              ← live event stream                   │
│  /                     ← serves dashboard (static HTML)      │
└──────┬───────────────────────────────────────┬───────────────┘
       │                                       │
  ┌────▼──────────────┐               ┌────────▼───────────────┐
  │   iMAC NODE       │               │   ANDROID NODE         │
  │   node/daemon.py  │               │   android-node/        │
  │                   │               │   index.html           │
  │  CPU: 6c/12t      │               │                        │
  │  RAM: 40GB        │               │  CPU: reported cores   │
  │  GPU: RX 5300 4GB │               │  RAM: deviceMemory API │
  │  Share: 10%       │               │  Share: configurable   │
  └───────────────────┘               └────────────────────────┘
                          ↓
               ┌──────────────────────┐
               │   VM SESSION         │
               │   QEMU + Alpine Linux│
               │   noVNC → browser    │
               │   http://localhost:  │
               │   6000/vnc.html      │
               └──────────────────────┘
```

---

## File Structure

```
wwrig/
├── setup.sh                    ← one-command launcher
├── coordinator/
│   ├── server.py               ← FastAPI coordinator (the brain)
│   ├── requirements.txt
│   └── static/
│       ├── index.html          ← command center dashboard
│       └── mobile.html         ← auto-copied from android-node/
├── node/
│   ├── daemon.py               ← node reporter (run on any machine)
│   ├── requirements.txt
│   └── node_config.json        ← auto-created, stores node ID
├── android-node/
│   └── index.html              ← mobile node (open in phone browser)
├── vm/
│   ├── launch.sh               ← QEMU + noVNC launcher
│   ├── setup_novnc.sh          ← WebSocket proxy for browser VNC
│   ├── images/                 ← ISOs and disk images (auto-downloaded)
│   └── logs/                   ← VM and noVNC logs
└── scripts/
    └── check_system.sh         ← pre-flight system check
```

---

## Adding More Nodes

Any machine on your LAN (or the internet with port forwarding):

```bash
# On another Mac
python3 node/daemon.py --coordinator http://YOUR_IMAC_IP:8081 --contribution 15

# On a Linux box
python3 node/daemon.py --coordinator http://YOUR_IMAC_IP:8081 --contribution 20

# On Windows (PowerShell)
python node\daemon.py --coordinator http://YOUR_IMAC_IP:8081 --contribution 10
```

Each new node appears on the dashboard instantly. The aggregate specs update in real time.

---

## Contribution Percentage

The node daemon shares a configurable fraction of your machine's resources with the WWRIG pool. The default is **10%** — imperceptible to the user, meaningful to the pool.

| Setting | CPU contributed | RAM contributed (40GB host) |
|---------|----------------|------------------------------|
| 5%      | ~1 core        | ~2 GB                        |
| 10%     | ~1 core        | ~4 GB                        |
| 25%     | ~1–2 cores     | ~10 GB                       |
| 50%     | ~3 cores       | ~20 GB                       |

The dashboard displays both the **total pool** (all nodes combined) and the **contributed fraction** available for sessions.

---

## Manual Commands

```bash
# Start only the coordinator
bash setup.sh coordinator

# Start only the node daemon
bash setup.sh node

# Stop everything
bash setup.sh stop

# View live coordinator logs
tail -f coordinator.log

# View live node daemon logs
tail -f node.log

# Manually launch a Linux VM (4 cores, 4GB RAM, VNC port 5900)
bash vm/launch.sh linux 4 4096 5900

# Run a node with custom settings
python3 node/daemon.py \
  --coordinator http://localhost:8081 \
  --contribution 20 \
  --heartbeat 3
```

---

## Roadmap: From Prototype to wwrig.com

| Phase | Feature |
|-------|---------|
| v0.1 (now) | Local network prototype, node dashboard, Linux session via QEMU + noVNC |
| v0.2 | Persistent node IDs, contribution leaderboard, session history |
| v0.3 | Internet-facing coordinator, node authentication, encrypted tunnels |
| v0.4 | Windows sessions (VirtIO + licence injection), macOS sessions (UTM) |
| v0.5 | GPU passthrough for AI/compute workloads |
| v1.0 | Public wwrig.io domain, node registry, open contributor network |

---

## Dependencies

| Package | Purpose | Install |
|---------|---------|---------|
| Python 3.10+ | Runtime | `brew install python3` |
| fastapi | Coordinator API | `pip3 install fastapi` |
| uvicorn | ASGI server | `pip3 install uvicorn` |
| psutil | System stats | `pip3 install psutil` |
| requests | HTTP client | `pip3 install requests` |
| qemu | VM runtime | `brew install qemu` |
| websockify | VNC→WebSocket | `pip3 install websockify` |
| noVNC | Browser VNC UI | auto-downloaded by launch.sh |

All Python deps install automatically via `bash setup.sh`.

---

## Troubleshooting

**Dashboard shows no nodes**  
→ Make sure `node/daemon.py` is running. Check `node.log`.

**"Coordinator offline" in dashboard**  
→ Make sure `coordinator/server.py` is running. Check `coordinator.log`.

**VM session launches but OPEN DISPLAY link does nothing**  
→ QEMU is not installed. Run `brew install qemu` then retry.

**Android phone can't connect**  
→ Confirm phone is on same Wi-Fi. Use your iMac's actual LAN IP, not `localhost`.

**Port 8081 already in use**  
→ `lsof -ti:8081 | xargs kill -9`, then re-run `bash setup.sh`.

---

*WWRIG — the internet is a library. The rig is the computer.*
