#!/usr/bin/env python3
"""
WWRIG Coordinator — World Wide Rig v0.2
Central registry that aggregates resources from every connected rig node
and manages temporary OS session allocation.
"""

from fastapi import FastAPI, HTTPException, BackgroundTasks, Header
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, Dict, Any, List
import uvicorn
import time
import uuid
import asyncio
import socket
import subprocess
import os
import json
from pathlib import Path


# ─── Configuration ─────────────────────────────────────────────────────────
HOST = os.getenv("WWRIG_HOST", "0.0.0.0")
PORT = int(os.getenv("WWRIG_PORT", "8081"))
AUTH_TOKEN = os.getenv("WWRIG_AUTH_TOKEN", "")

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent

if not AUTH_TOKEN:
    token_path = PROJECT_DIR / "wwrig_config.json"
    if token_path.exists():
        try:
            cfg = json.loads(token_path.read_text())
            AUTH_TOKEN = cfg.get("auth_token", "")
        except Exception:
            pass
    if not AUTH_TOKEN:
        AUTH_TOKEN = uuid.uuid4().hex[:16]
        try:
            cfg = {"auth_token": AUTH_TOKEN, "host": HOST, "port": PORT}
            token_path.write_text(json.dumps(cfg, indent=2))
        except Exception:
            pass

app = FastAPI(title="WWRIG Coordinator", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Global State ────────────────────────────────────────────────────────────
nodes: Dict[str, Any] = {}
vm_sessions: Dict[str, Any] = {}
event_log: List[Dict] = []
NODE_TIMEOUT = 30


def log(msg: str, level: str = "INFO"):
    entry = {"ts": round(time.time(), 2), "level": level, "msg": msg}
    event_log.append(entry)
    if len(event_log) > 500:
        event_log.pop(0)
    print(f"[WWRIG/{level}] {msg}")


def require_auth(x_wwrig_token: str = Header("")):
    if AUTH_TOKEN and x_wwrig_token != AUTH_TOKEN:
        raise HTTPException(
            status_code=401, detail="Invalid or missing WWRIG auth token"
        )


# ─── Pydantic Models ─────────────────────────────────────────────────────────
class NodeRegistration(BaseModel):
    node_id: str
    hostname: str
    platform: str
    cpu_brand: str
    cpu_cores: int
    cpu_threads: int
    cpu_freq_ghz: float
    ram_total_gb: float
    gpu_name: Optional[str] = "N/A"
    gpu_vram_gb: Optional[float] = 0.0
    contribution_pct: float = 10.0


class NodeHeartbeat(BaseModel):
    node_id: str
    cpu_usage_pct: float
    ram_used_gb: float
    gpu_usage_pct: Optional[float] = 0.0


class VMRequest(BaseModel):
    os_type: str


class ContributionUpdate(BaseModel):
    node_id: str
    contribution_pct: float


# ─── Health ──────────────────────────────────────────────────────────────────
@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "version": "0.2.0",
        "node_count": len(nodes),
        "auth_required": bool(AUTH_TOKEN),
    }


# ─── Node Endpoints ──────────────────────────────────────────────────────────
@app.post("/api/nodes/register")
async def register_node(reg: NodeRegistration, x_wwrig_token: str = Header("")):
    require_auth(x_wwrig_token)
    is_new = reg.node_id not in nodes
    nodes[reg.node_id] = {
        **reg.dict(),
        "first_seen": time.time(),
        "last_seen": time.time(),
        "status": "online",
        "cpu_usage_pct": 0.0,
        "ram_used_gb": 0.0,
        "gpu_usage_pct": 0.0,
    }
    action = "JOINED" if is_new else "RECONNECTED"
    log(f"NODE {action}: {reg.hostname} [{reg.platform.upper()}] — "
        f"{reg.cpu_cores}c/{reg.cpu_threads}t @ {reg.cpu_freq_ghz}GHz | "
        f"{reg.ram_total_gb:.1f}GB RAM | GPU: {reg.gpu_name} "
        f"({reg.gpu_vram_gb:.1f}GB) | Sharing: {reg.contribution_pct:.0f}%")
    return {
        "status": "registered",
        "node_id": reg.node_id,
        "auth_required": bool(AUTH_TOKEN),
    }


@app.post("/api/nodes/heartbeat")
async def heartbeat(hb: NodeHeartbeat, x_wwrig_token: str = Header("")):
    require_auth(x_wwrig_token)
    if hb.node_id not in nodes:
        raise HTTPException(
            status_code=404, detail="Node not registered. Please re-register."
        )
    nodes[hb.node_id].update({
        "last_seen": time.time(),
        "status": "online",
        "cpu_usage_pct": round(hb.cpu_usage_pct, 1),
        "ram_used_gb": round(hb.ram_used_gb, 2),
        "gpu_usage_pct": round(hb.gpu_usage_pct or 0, 1),
    })
    return {"status": "ok", "ts": time.time()}


@app.get("/api/nodes")
async def list_nodes():
    now = time.time()
    result = []
    for node in nodes.values():
        n = dict(node)
        n["status"] = "online" if (now - n["last_seen"]) < NODE_TIMEOUT else "offline"
        n["uptime_s"] = round(now - n["first_seen"])
        result.append(n)
    result.sort(key=lambda x: x["status"])
    return result


@app.post("/api/nodes/contribution")
async def update_contribution(
    update: ContributionUpdate, x_wwrig_token: str = Header("")
):
    require_auth(x_wwrig_token)
    if update.node_id not in nodes:
        raise HTTPException(status_code=404, detail="Node not found")
    old = nodes[update.node_id]["contribution_pct"]
    nodes[update.node_id]["contribution_pct"] = max(
        1.0, min(100.0, update.contribution_pct)
    )
    log(f"CONTRIBUTION UPDATED: {nodes[update.node_id]['hostname']} "
        f"{old:.0f}% → {update.contribution_pct:.0f}%")
    return {"status": "ok"}


# ─── Aggregate Stats ──────────────────────────────────────────────────────────
@app.get("/api/stats")
async def aggregate_stats():
    now = time.time()
    active = [
        n for n in nodes.values() if (now - n["last_seen"]) < NODE_TIMEOUT
    ]

    if not active:
        return {
            "node_count": 0,
            "total_cores": 0,
            "total_threads": 0,
            "max_freq_ghz": 0.0,
            "total_ram_gb": 0.0,
            "total_vram_gb": 0.0,
            "contributed_cores": 0,
            "contributed_threads": 0,
            "contributed_ram_gb": 0.0,
            "contributed_vram_gb": 0.0,
            "avg_cpu_usage_pct": 0.0,
            "platforms": [],
        }

    total_cores = sum(n["cpu_cores"] for n in active)
    total_threads = sum(n["cpu_threads"] for n in active)
    total_ram = sum(n["ram_total_gb"] for n in active)
    total_vram = sum(n.get("gpu_vram_gb") or 0 for n in active)
    max_freq = max(n["cpu_freq_ghz"] for n in active)
    avg_cpu = sum(n["cpu_usage_pct"] for n in active) / len(active)

    def contrib(n, field, is_int=False):
        pct = n["contribution_pct"] / 100
        val = n[field] * pct
        return int(val) if is_int else val

    cont_cores = sum(contrib(n, "cpu_cores", is_int=True) for n in active)
    cont_threads = sum(contrib(n, "cpu_threads", is_int=True) for n in active)
    cont_ram = sum(contrib(n, "ram_total_gb") for n in active)
    cont_vram = sum(
        (n.get("gpu_vram_gb") or 0) * n["contribution_pct"] / 100
        for n in active
    )

    return {
        "node_count": len(active),
        "total_cores": total_cores,
        "total_threads": total_threads,
        "max_freq_ghz": round(max_freq, 2),
        "total_ram_gb": round(total_ram, 1),
        "total_vram_gb": round(total_vram, 1),
        "contributed_cores": cont_cores,
        "contributed_threads": cont_threads,
        "contributed_ram_gb": round(cont_ram, 2),
        "contributed_vram_gb": round(cont_vram, 2),
        "avg_cpu_usage_pct": round(avg_cpu, 1),
        "platforms": list({n["platform"] for n in active}),
    }


# ─── VM Session Endpoints ─────────────────────────────────────────────────────
@app.post("/api/vm/launch")
async def launch_vm(req: VMRequest, background_tasks: BackgroundTasks):
    stats = await aggregate_stats()

    if stats["node_count"] == 0:
        raise HTTPException(
            status_code=503,
            detail="No WWRIG nodes online. Start a node daemon first."
        )

    vm_id = str(uuid.uuid4())[:8].upper()

    # Find free VNC port starting from 5900
    vnc_port = 5900 + len(vm_sessions)
    for _ in range(50):
        sock = socket.socket()
        try:
            sock.bind(("", vnc_port))
            sock.close()
            break
        except OSError:
            sock.close()
            vnc_port += 1
    ws_port = vnc_port + 100

    vcpus = max(2, min(stats["contributed_cores"], 8))
    ram_mb = max(2048, min(int(stats["contributed_ram_gb"] * 1024), 8192))

    vm_sessions[vm_id] = {
        "id": vm_id,
        "os_type": req.os_type,
        "vcpus": vcpus,
        "ram_mb": ram_mb,
        "vnc_port": vnc_port,
        "ws_port": ws_port,
        "status": "provisioning",
        "started": time.time(),
        "pid": None,
    }

    log(f"SESSION PROVISIONING: wwrig.{req.os_type.upper()} ID={vm_id} "
        f"— {vcpus} vCPU / {ram_mb}MB RAM / VNC:{vnc_port}", "LAUNCH")

    background_tasks.add_task(
        _start_vm, vm_id, req.os_type, vcpus, ram_mb, vnc_port
    )
    return {
        "vm_id": vm_id,
        "status": "provisioning",
        "vcpus": vcpus,
        "ram_mb": ram_mb,
        "vnc_port": vnc_port,
        "novnc_url": (
            f"http://localhost:{ws_port}/vnc.html"
            "?autoconnect=true&resize=scale"
        ),
        "message": f"wwrig.{req.os_type} session {vm_id} is provisioning...",
    }


@app.get("/api/vm/sessions")
async def list_sessions():
    return list(vm_sessions.values())


@app.delete("/api/vm/{vm_id}")
async def terminate_session(vm_id: str):
    if vm_id not in vm_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    pid = vm_sessions[vm_id].get("pid")
    if pid:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    vm_sessions[vm_id]["status"] = "terminated"
    log(f"SESSION TERMINATED: {vm_id}", "WARN")
    return {"status": "terminated"}


async def _start_vm(
    vm_id: str, os_type: str, vcpus: int, ram_mb: int, vnc_port: int
):
    """Invoke the vm/launch.sh script (QEMU + noVNC)"""
    script = PROJECT_DIR / "vm" / "launch.sh"
    if script.exists():
        try:
            proc = subprocess.Popen(
                ["bash", str(script), os_type, str(vcpus),
                 str(ram_mb), str(vnc_port)],
                stdout=open(f"/tmp/wwrig_vm_{vm_id}.log", "w"),
                stderr=subprocess.STDOUT,
            )
            vm_sessions[vm_id]["pid"] = proc.pid
            vm_sessions[vm_id]["status"] = "running"
            log(f"SESSION RUNNING: {vm_id} PID={proc.pid}")
        except Exception as e:
            vm_sessions[vm_id]["status"] = "error"
            log(f"SESSION ERROR: {vm_id} — {e}", "ERROR")
    else:
        await asyncio.sleep(3)
        vm_sessions[vm_id]["status"] = "running (demo)"
        log(f"SESSION DEMO: {vm_id} — vm/launch.sh not found, "
            "running in display-only mode", "WARN")


# ─── Log Endpoint ─────────────────────────────────────────────────────────────
@app.get("/api/log")
async def get_log(limit: int = 60):
    return event_log[-limit:]


# ─── Lifecycle ────────────────────────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    log("═══════════════════════════════════════════════")
    log("  WWRIG COORDINATOR ONLINE — World Wide Rig v0.2")
    log(f"  Listening on {HOST}:{PORT}")
    if AUTH_TOKEN:
        log(f"  Auth token: {AUTH_TOKEN}")
        log("  Nodes must provide X-WWRIG-Token header")
    else:
        log("  Auth disabled (no WWRIG_AUTH_TOKEN set)")
    log("═══════════════════════════════════════════════")
    asyncio.create_task(_node_watchdog())


async def _node_watchdog():
    while True:
        await asyncio.sleep(15)
        now = time.time()
        for node_id in list(nodes.keys()):
            last = nodes[node_id]["last_seen"]
            if ((now - last) > NODE_TIMEOUT
                    and nodes[node_id]["status"] == "online"):
                nodes[node_id]["status"] = "offline"
                log(f"NODE OFFLINE: {nodes[node_id]['hostname']} "
                    f"(no heartbeat for {int(now - last)}s)", "WARN")


# ─── Static Serve (must be last) ─────────────────────────────────────────────
static_dir = SCRIPT_DIR / "static"
static_dir.mkdir(exist_ok=True)
app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="static")

if __name__ == "__main__":
    uvicorn.run("server:app", host=HOST, port=PORT, reload=False,
                log_level="warning")
