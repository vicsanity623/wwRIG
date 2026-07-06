#!/usr/bin/env python3
"""
WWRIG Node Daemon — World Wide Rig v0.1
Runs on each contributing machine. Reports system specs and
sends heartbeats to the WWRIG Coordinator.

Usage:
    python daemon.py                           # auto-detect coordinator on localhost
    python daemon.py --coordinator http://192.168.1.100:8081
    python daemon.py --contribution 15         # share 15% of resources (default: 10)
"""

import argparse
import json
import os
import platform
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

try:
    import psutil
    import requests
except ImportError:
    print("[WWRIG] Missing dependencies. Run: pip3 install psutil requests")
    sys.exit(1)

# ── Configuration ─────────────────────────────────────────────────────────────
CONFIG_FILE = Path(__file__).parent / "node_config.json"

def load_config():
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE) as f:
            return json.load(f)
    return {}

def save_config(cfg: dict):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)


# ── System Info ───────────────────────────────────────────────────────────────
def get_cpu_brand() -> str:
    """Best-effort CPU brand string across platforms"""
    sys_plat = platform.system()
    try:
        if sys_plat == "Darwin":
            out = subprocess.check_output(
                ["sysctl", "-n", "machdep.cpu.brand_string"],
                stderr=subprocess.DEVNULL, text=True
            ).strip()
            return out if out else platform.processor()
        elif sys_plat == "Linux":
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if "model name" in line:
                        return line.split(":")[1].strip()
        elif sys_plat == "Windows":
            out = subprocess.check_output(
                "wmic cpu get name", shell=True, text=True
            ).strip().split("\n")
            if len(out) > 1:
                return out[1].strip()
    except Exception:
        pass
    return platform.processor() or "Unknown CPU"


def get_cpu_freq_ghz() -> float:
    """Get max CPU frequency in GHz"""
    try:
        freq = psutil.cpu_freq()
        if freq:
            val = freq.max if freq.max else freq.current
            return round(val / 1000, 2)  # MHz → GHz
    except Exception:
        pass
    return 0.0


def get_gpu_info() -> tuple[str, float]:
    """Returns (gpu_name, vram_gb) — best-effort across platforms"""
    sys_plat = platform.system()
    try:
        if sys_plat == "Darwin":
            out = subprocess.check_output(
                ["system_profiler", "SPDisplaysDataType", "-json"],
                text=True, stderr=subprocess.DEVNULL, timeout=10
            )
            data = json.loads(out)
            displays = data.get("SPDisplaysDataType", [])
            for d in displays:
                name  = d.get("sppci_model", "Unknown GPU")
                vram  = d.get("spdisplays_vram", "0 MB")
                # Parse "4096 MB" or "4 GB"
                parts = vram.split()
                if len(parts) == 2:
                    num = float(parts[0].replace(",", ""))
                    if "GB" in parts[1].upper():
                        return name, round(num, 1)
                    elif "MB" in parts[1].upper():
                        return name, round(num / 1024, 2)
            return "Apple GPU (integrated)", 0.0

        elif sys_plat == "Linux":
            # Try nvidia-smi first
            try:
                out = subprocess.check_output(
                    ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
                    text=True, timeout=5
                ).strip()
                if out:
                    parts = out.split(",")
                    name  = parts[0].strip()
                    vram  = float(parts[1].strip().replace(" MiB", "")) / 1024
                    return name, round(vram, 2)
            except Exception:
                pass
            # Try AMD rocm-smi
            try:
                out = subprocess.check_output(
                    ["rocm-smi", "--showmeminfo", "vram", "--csv"],
                    text=True, timeout=5
                ).strip()
                lines = [l for l in out.split("\n") if "," in l and "GPU" not in l]
                if lines:
                    vram = float(lines[0].split(",")[1]) / (1024**3)
                    return "AMD GPU (ROCm)", round(vram, 2)
            except Exception:
                pass

        elif sys_plat == "Windows":
            try:
                out = subprocess.check_output(
                    "wmic path win32_VideoController get name,AdapterRAM /format:csv",
                    shell=True, text=True, timeout=5
                )
                lines = [l for l in out.strip().split("\n") if "," in l and "Node" not in l and l.strip()]
                if lines:
                    parts = lines[0].split(",")
                    name  = parts[2].strip() if len(parts) > 2 else "Unknown GPU"
                    vram  = int(parts[1]) / (1024**3) if len(parts) > 1 else 0
                    return name, round(vram, 2)
            except Exception:
                pass

    except Exception:
        pass
    return "N/A", 0.0


def get_platform_name() -> str:
    s = platform.system().lower()
    if s == "darwin": return "darwin"
    if s == "windows": return "windows"
    if s == "linux": return "linux"
    return s


def build_registration(node_id: str, contribution_pct: float) -> dict:
    cpu_brand = get_cpu_brand()
    cpu_cores   = psutil.cpu_count(logical=False) or 1
    cpu_threads = psutil.cpu_count(logical=True)  or cpu_cores
    cpu_freq_ghz = get_cpu_freq_ghz()
    ram_total_gb = round(psutil.virtual_memory().total / (1024**3), 2)
    gpu_name, gpu_vram_gb = get_gpu_info()

    return {
        "node_id":        node_id,
        "hostname":       socket.gethostname(),
        "platform":       get_platform_name(),
        "cpu_brand":      cpu_brand,
        "cpu_cores":      cpu_cores,
        "cpu_threads":    cpu_threads,
        "cpu_freq_ghz":   cpu_freq_ghz,
        "ram_total_gb":   ram_total_gb,
        "gpu_name":       gpu_name,
        "gpu_vram_gb":    gpu_vram_gb,
        "contribution_pct": contribution_pct,
    }


def build_heartbeat(node_id: str) -> dict:
    vm = psutil.virtual_memory()
    return {
        "node_id":       node_id,
        "cpu_usage_pct": psutil.cpu_percent(interval=1),
        "ram_used_gb":   round((vm.total - vm.available) / (1024**3), 2),
        "gpu_usage_pct": 0.0,   # Extend with nvidia-smi if available
    }


# ── Main Loop ─────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="WWRIG Node Daemon")
    parser.add_argument("--coordinator", default="http://localhost:8081",
                        help="Coordinator URL (default: http://localhost:8081)")
    parser.add_argument("--contribution", type=float, default=10.0,
                        help="Percent of resources to share (default: 10)")
    parser.add_argument("--heartbeat",   type=int,   default=5,
                        help="Heartbeat interval in seconds (default: 5)")
    args = parser.parse_args()

    # Persistent node ID
    cfg = load_config()
    if "node_id" not in cfg:
        cfg["node_id"] = str(uuid.uuid4())
        save_config(cfg)
    node_id = cfg["node_id"]

    coordinator = args.coordinator.rstrip("/")
    hb_interval = args.heartbeat

    print("╔═══════════════════════════════════════════════════╗")
    print("║       WWRIG NODE DAEMON  —  World Wide Rig v0.1   ║")
    print("╚═══════════════════════════════════════════════════╝")
    print(f"  Node ID      : {node_id}")
    print(f"  Hostname     : {socket.gethostname()}")
    print(f"  Coordinator  : {coordinator}")
    print(f"  Contribution : {args.contribution}% of resources")
    print(f"  Heartbeat    : every {hb_interval}s")
    print()

    reg = build_registration(node_id, args.contribution)

    print("  CPU     :", reg["cpu_brand"])
    print(f"  Cores   : {reg['cpu_cores']} physical / {reg['cpu_threads']} logical @ {reg['cpu_freq_ghz']} GHz")
    print(f"  RAM     : {reg['ram_total_gb']} GB")
    print(f"  GPU     : {reg['gpu_name']} ({reg['gpu_vram_gb']} GB VRAM)")
    print()

    # ── Registration loop ─────────────────────────────────────────────────────
    registered = False
    while not registered:
        try:
            r = requests.post(
                f"{coordinator}/api/nodes/register",
                json=reg, timeout=5
            )
            r.raise_for_status()
            print(f"  [OK]  Registered with coordinator at {coordinator}")
            registered = True
        except requests.exceptions.ConnectionError:
            print(f"  [--]  Coordinator not reachable at {coordinator} — retrying in 5s...")
            time.sleep(5)
        except Exception as e:
            print(f"  [!!]  Registration error: {e} — retrying in 5s...")
            time.sleep(5)

    print()
    print("  Sending heartbeats... (Ctrl+C to stop)")
    print()

    # ── Heartbeat loop ────────────────────────────────────────────────────────
    consecutive_failures = 0
    while True:
        try:
            hb = build_heartbeat(node_id)
            r  = requests.post(
                f"{coordinator}/api/nodes/heartbeat",
                json=hb, timeout=5
            )
            if r.status_code == 404:
                # Coordinator restarted — re-register
                print("  [--]  Node not found on coordinator — re-registering...")
                requests.post(f"{coordinator}/api/nodes/register", json=reg, timeout=5)
            elif r.ok:
                consecutive_failures = 0
                print(f"  [♥]  CPU {hb['cpu_usage_pct']:.1f}%  |  "
                      f"RAM {hb['ram_used_gb']:.1f}GB  |  "
                      f"Sharing {args.contribution:.0f}%",
                      end="\r", flush=True)

        except requests.exceptions.ConnectionError:
            consecutive_failures += 1
            print(f"\n  [!!]  Coordinator unreachable (attempt {consecutive_failures})", end="\r")

        except KeyboardInterrupt:
            print("\n\n  [--]  Node daemon stopped. Goodbye.")
            sys.exit(0)

        except Exception as e:
            print(f"\n  [!!]  Heartbeat error: {e}")

        time.sleep(hb_interval)


if __name__ == "__main__":
    main()
