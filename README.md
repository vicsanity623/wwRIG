# WWRIG — World Wide Rig v0.2

### *Distributed computing, one node at a time.*

```
www   = world wide web    → anyone can host a webpage
wwrig = world wide rig    → anyone can contribute compute
```

---

## What This Is (Honest)

WWRIG is a **local-network distributed computing prototype**. It lets multiple devices on your LAN connect as "nodes" to pool their CPU/RAM stats into a live dashboard, and launch a real Alpine Linux VM (via QEMU + noVNC) in your browser.

### What actually works today:
- Multiple devices (Mac, Linux, Android phones) register as nodes
- Live dashboard with aggregate pool specs (cores, RAM, VRAM)
- **Real Alpine Linux VM** launched via QEMU with HVF/KVM acceleration
- Full browser-based desktop via noVNC (keyboard + mouse)
- Auth tokens to control who can join your coordinator
- Docker deployment for the coordinator
- macOS menubar plugin (SwiftBar/xBar) showing pool stats

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

# Start the full stack
bash setup.sh

# Open dashboard
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

## Project Structure

```
wwRIG/
├── setup.sh                  ← one-command launcher
├── coordinator/
│   ├── server.py             ← FastAPI coordinator (the brain)
│   └── static/
│       ├── index.html        ← dashboard
│       └── mobile.html       ← mobile node page
├── node/
│   └── daemon.py             ← node reporter (run on any machine)
├── android-node/
│   └── index.html            ← mobile node source
├── vm/
│   ├── launch.sh             ← QEMU + noVNC launcher
│   ├── setup_novnc.sh        ← WebSocket proxy
│   └── images/               ← ISOs and disk images
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
