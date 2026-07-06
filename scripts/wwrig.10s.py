#!/usr/bin/env python3
"""
<bitbar.title>WWRIG Pool Monitor</bitbar.title>
<bitbar.version>v0.3</bitbar.version>
<bitbar.author>WWRIG</bitbar.author>
<bitbar.desc>Shows WWRIG distributed compute pool stats in your menu bar</bitbar.desc>
<bitbar.image></bitbar.image>
<bitbar.dependencies>python3</bitbar.dependencies>
<bitbar.abouturl>http://localhost:8081</bitbar.abouturl>
<bitbar.refresh>10</bitbar.refresh>
"""
import json
import urllib.request
import urllib.error
import sys

COORDINATOR = "http://localhost:8081"
PUBLIC_URL = "https://vics-imac-1.tail37b4f2.ts.net:8441"

try:
    req = urllib.request.Request(f"{COORDINATOR}/api/stats")
    resp = urllib.request.urlopen(req, timeout=5)
    s = json.loads(resp.read())

    nodes = s.get("node_count", 0)
    cores = s.get("contributed_cores", 0)
    ram = s.get("contributed_ram_gb", 0)
    threads = s.get("contributed_threads", 0)
    total_cores = s.get("total_cores", 0)
    total_ram = s.get("total_ram_gb", 0)
    platforms = s.get("platforms", [])
    vram = s.get("contributed_vram_gb", 0)

    # Menu bar line (compact)
    status_icon = "●" if nodes > 0 else "○"
    if nodes > 0:
        print(f"{status_icon} {nodes}N {cores}C {ram:.0f}G")
    else:
        print(f"{status_icon} WWRIG")

    print("---")
    print(f"font=14")

    # Header
    print(f"WWRIG Pool | font=13 color=green")
    print("---")

    # Pool Summary
    print(f"Pool Totals")
    print(f"-- Nodes Online: {nodes}")
    print(f"-- CPU Cores (shared): {cores} / {total_cores} total")
    print(f"-- CPU Threads (shared): {threads}")
    print(f"-- RAM (shared): {ram:.1f}GB / {total_ram:.1f}GB total")
    print(f"-- VRAM (shared): {vram:.1f}GB")
    print(f"-- Platforms: {', '.join(p.upper() for p in platforms) if platforms else 'none'}")

    # VM sessions
    try:
        vreq = urllib.request.Request(f"{COORDINATOR}/api/vm/sessions")
        vresp = urllib.request.urlopen(vreq, timeout=5)
        sessions = json.loads(vresp.read())
        running = [vm for vm in sessions if vm.get("status") == "running"]
        if running:
            print(f"-- VM Sessions: {len(running)} running")
            for vm in running:
                print(f"---- {vm['id']} {vm.get('os_type','?')}  {vm.get('vcpus',0)}c {vm.get('ram_mb',0)//1024}G")
    except Exception:
        pass

    print("---")

    # Nodes list
    try:
        nreq = urllib.request.Request(f"{COORDINATOR}/api/nodes")
        nresp = urllib.request.urlopen(nreq, timeout=5)
        node_list = json.loads(nresp.read())

        print(f"Connected Nodes ({len(node_list)})")
        for n in node_list:
            status = "●" if n.get("status") == "online" else "○"
            host = n.get("hostname", "unknown")
            plat = n.get("platform", "?").upper()
            cpu = n.get("cpu_cores", 0)
            ram_n = n.get("ram_total_gb", 0)
            contrib = n.get("contribution_pct", 0)
            gpu = n.get("gpu_name")
            print(f"-- {status} {host} [{plat}] {cpu}c {ram_n:.0f}GB ({contrib:.0f}%)" + (f" GPU:{gpu}" if gpu else ""))
    except Exception:
        print("-- Could not fetch node list")

    print("---")

    # Links
    print(f"Open Dashboard | href={COORDINATOR}")
    print(f"Open Mobile Node | href={COORDINATOR}/mobile.html")
    print(f"Public URL | href={PUBLIC_URL}")

    print("---")
    print(f"Coordinator: {COORDINATOR} | color=gray")
    print(f"Public: {PUBLIC_URL} | color=gray")

except urllib.error.URLError:
    print("○ WWRIG")
    print("---")
    print("Coordinator offline")
    print(f"Retry: {COORDINATOR} | href={COORDINATOR}")
except Exception as e:
    print(f"○ WWRIG")
    print("---")
    print(f"Error: {e}")
