#!/usr/bin/env python3
"""wwRIG Native macOS GUI — World Wide Rig v0.2
Replaces the browser dashboard with a native macOS window.
QEMU VMs use -display cocoa for native window rendering.
"""
import tkinter as tk
import urllib.request
import json
import threading
import subprocess
import time
import os
import signal

API = "http://localhost:8081"
FG = "#00ff88"
BG = "#0a0a0a"
BG2 = "#111"
DIM = "#555"
RED = "#ff4444"


class WWRigGUI:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("wwRIG")
        self.root.geometry("480x560")
        self.root.configure(bg=BG)
        self.root.resizable(False, False)

        self.root.option_add("*Font", "Menlo 10")
        self.root.option_add("*Label.foreground", FG)
        self.root.option_add("*Label.background", BG)
        self.root.option_add("*Frame.background", BG)
        self.root.option_add("*Button.font", "Menlo 10")
        self.root.option_add("*Button.background", BG2)
        self.root.option_add("*Button.foreground", FG)
        self.root.option_add("*Button.activebackground", "#002200")
        self.root.option_add("*Button.activeforeground", FG)
        self.root.option_add("*Button.relief", "flat")
        self.root.option_add("*Button.highlightthickness", 0)
        self.root.option_add("*Button.bd", 1)

        self._build_ui()

        self.root.after(100, self._poll)
        self.root.mainloop()

    def _build_ui(self):
        # header
        tk.Label(self.root, text="W W W  R I G   v0.2",
                 font=("Menlo", 16, "bold")).pack(pady=(16, 2))
        tk.Label(self.root, text="World Wide Rig",
                 font=("Menlo", 8), fg=DIM).pack()

        self.coord_lbl = tk.Label(self.root, text="Coordinator: polling...", fg=DIM)
        self.coord_lbl.pack(pady=(6, 0))

        sep = tk.Frame(self.root, height=1, bg=BG2)
        sep.pack(fill="x", padx=20, pady=10)

        # stats grid
        stats = tk.Frame(self.root)
        stats.pack(padx=24, fill="x")
        stats.grid_columnconfigure(0, weight=0, minsize=80)
        stats.grid_columnconfigure(1, weight=1)

        self._stat_labels = {}
        for i, (label, key) in enumerate([
            ("NODES", "node_count"),
            ("CPU", "cpu"),
            ("RAM", "ram"),
            ("VRAM", "vram"),
        ]):
            tk.Label(stats, text=label, fg=DIM,
                     font=("Menlo", 8)).grid(row=i, column=0, sticky="w", pady=1)
            lbl = tk.Label(stats, text="...", fg=FG,
                           font=("Menlo", 10, "bold"), anchor="w")
            lbl.grid(row=i, column=1, sticky="ew", pady=1)
            self._stat_labels[key] = lbl

        sep2 = tk.Frame(self.root, height=1, bg=BG2)
        sep2.pack(fill="x", padx=20, pady=10)

        # launch buttons
        launch_frame = tk.Frame(self.root)
        launch_frame.pack(pady=4)

        for text, os_type in [("Launch wwrig.linux", "linux"),
                               ("Launch wwrig.win64", "windows")]:
            btn = tk.Button(launch_frame, text=text, padx=14, pady=4,
                            command=lambda ot=os_type: self._launch(ot))
            btn.pack(side="left", padx=4)

        sep3 = tk.Frame(self.root, height=1, bg=BG2)
        sep3.pack(fill="x", padx=20, pady=10)

        # sessions
        tk.Label(self.root, text="ACTIVE SESSIONS",
                 font=("Menlo", 8), fg=DIM).pack()

        self.sess_frame = tk.Frame(self.root)
        self.sess_frame.pack(fill="both", expand=True, padx=16, pady=(4, 12))

    def _fetch(self, path):
        try:
            r = urllib.request.urlopen(f"{API}{path}", timeout=3)
            return json.loads(r.read())
        except Exception:
            return None

    def _poll(self):
        self._update_stats()
        self._update_sessions()
        self.root.after(3000, self._poll)

    def _update_stats(self):
        stats = self._fetch("/api/stats")
        if stats:
            self.coord_lbl.config(text="Coordinator: ONLINE", fg=FG)
            self._stat_labels["node_count"].config(
                text=str(stats.get("node_count", 0)))
            self._stat_labels["cpu"].config(
                text=f"{stats.get('contributed_cores', 0)} vCPU"
                     f" ({stats.get('total_cores', 0)} cores)"
                     f" @ {stats.get('max_freq_ghz', '?')}GHz")
            self._stat_labels["ram"].config(
                text=f"{stats.get('contributed_ram_gb', 0):.1f} GB"
                     f" ({stats.get('total_ram_gb', 0):.1f} GB total)")
            self._stat_labels["vram"].config(
                text=f"{stats.get('contributed_vram_gb', 0):.1f} GB"
                     f" / {stats.get('total_vram_gb', 0):.1f} GB")
        else:
            self.coord_lbl.config(text="Coordinator: OFFLINE", fg=RED)

    def _update_sessions(self):
        sessions = self._fetch("/api/vm/sessions")
        for w in self.sess_frame.winfo_children():
            w.destroy()

        if not sessions:
            tk.Label(self.sess_frame, text="No active sessions",
                     fg=DIM, font=("Menlo", 9)).pack(pady=8)
            return

        for s in sessions:
            status = s.get("status", "")
            is_alive = status == "running"
            row = tk.Frame(self.sess_frame, bg=BG2, highlightbackground="#222",
                           highlightthickness=1)
            row.pack(fill="x", pady=2)

            color = FG if is_alive else RED
            sid = s.get("id", "?")[:8]
            os_t = s.get("os_type", "?").upper()
            vcpu = s.get("vcpus", "?")
            ram = f"{s.get('ram_mb', 0)/1024:.1f}GB"

            info = f"{os_t}  {sid}   {vcpu}vCPU  {ram}"
            tk.Label(row, text=info, fg=color, bg=BG2,
                     font=("Menlo", 9), anchor="w").pack(
                         side="left", padx=6, pady=4)

            if is_alive:
                kill_btn = tk.Button(
                    row, text="KILL", fg=RED, bg=BG2,
                    activebackground="#330000",
                    font=("Menlo", 8),
                    command=lambda vid=s["id"]: self._kill(vid))
                kill_btn.pack(side="right", padx=4)

    def _launch(self, os_type):
        threading.Thread(target=self._do_launch, args=(os_type,),
                         daemon=True).start()

    def _do_launch(self, os_type):
        try:
            data = json.dumps({"os_type": os_type}).encode()
            req = urllib.request.Request(
                f"{API}/api/vm/launch", data=data,
                headers={"Content-Type": "application/json"})
            resp = json.loads(urllib.request.urlopen(req, timeout=15).read())
            print(f"[LAUNCH] {resp.get('message', 'OK')}")
            print("  QEMU window opened. To release mouse: press Control+Option")
        except Exception as e:
            print(f"[LAUNCH ERROR] {e}")

    def _kill(self, vm_id):
        threading.Thread(target=self._do_kill, args=(vm_id,),
                         daemon=True).start()

    def _do_kill(self, vm_id):
        try:
            req = urllib.request.Request(f"{API}/api/vm/{vm_id}",
                                         method="DELETE")
            urllib.request.urlopen(req, timeout=5)
            print(f"[KILL] {vm_id}")
        except Exception as e:
            print(f"[KILL ERROR] {e}")


if __name__ == "__main__":
    print("Starting wwRIG Native GUI...")
    print(f"Coordinator API: {API}")
    print("Close this window to quit.\n")
    try:
        WWRigGUI()
    except KeyboardInterrupt:
        pass
