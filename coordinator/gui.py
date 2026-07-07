#!/usr/bin/env python3
import tkinter as tk
import urllib.request
import json
import threading

API = "http://localhost:8081"
FG = "#00ff88"
BG = "#0a0a0a"
BG2 = "#111"
DIM = "#555"
RED = "#ff4444"
AMBER = "#ff9800"


class WWRigGUI:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("wwRIG")
        self.root.geometry("560x640")
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
        tk.Label(self.root, text="W W W  R I G   v0.3",
                 font=("Menlo", 16, "bold")).pack(pady=(16, 2))
        tk.Label(self.root, text="World Wide Rig",
                 font=("Menlo", 8), fg=DIM).pack()
        self.coord_lbl = tk.Label(self.root, text="Coordinator: polling...", fg=DIM)
        self.coord_lbl.pack(pady=(6, 0))

        sep = tk.Frame(self.root, height=1, bg=BG2)
        sep.pack(fill="x", padx=20, pady=8)

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
        sep2.pack(fill="x", padx=20, pady=8)

        launch_frame = tk.Frame(self.root)
        launch_frame.pack(pady=2)
        for text, os_type in [("Install Linux", "linux"),
                               ("Install Windows", "windows")]:
            btn = tk.Button(launch_frame, text=text, padx=10, pady=3,
                            command=lambda ot=os_type: self._launch(ot))
            btn.pack(side="left", padx=4)

        sep2b = tk.Frame(self.root, height=1, bg=BG2)
        sep2b.pack(fill="x", padx=20, pady=8)

        tk.Label(self.root, text="DISKS",
                 font=("Menlo", 8), fg=DIM).pack()
        self.disk_frame = tk.Frame(self.root)
        self.disk_frame.pack(fill="x", padx=24, pady=(2, 6))

        sep3 = tk.Frame(self.root, height=1, bg=BG2)
        sep3.pack(fill="x", padx=20, pady=6)

        tk.Label(self.root, text="ACTIVE SESSIONS",
                 font=("Menlo", 8), fg=DIM).pack()
        self.sess_frame = tk.Frame(self.root)
        self.sess_frame.pack(fill="both", expand=True, padx=16, pady=(2, 12))

    def _fetch(self, path):
        try:
            r = urllib.request.urlopen(f"{API}{path}", timeout=3)
            return json.loads(r.read())
        except Exception:
            return None

    def _post(self, path, data=None):
        try:
            body = json.dumps(data).encode() if data else b""
            req = urllib.request.Request(
                f"{API}{path}", data=body,
                headers={"Content-Type": "application/json"} if data else {},
                method="POST" if data else "GET")
            if not data:
                req.method = "POST"
            return json.loads(urllib.request.urlopen(req, timeout=10).read())
        except Exception as e:
            print(f"[API ERROR] {path}: {e}")
            return None

    def _delete(self, path):
        try:
            req = urllib.request.Request(f"{API}{path}", method="DELETE")
            urllib.request.urlopen(req, timeout=5)
            return True
        except Exception as e:
            print(f"[API ERROR] DELETE {path}: {e}")
            return False

    def _poll(self):
        self._update_stats()
        self._update_disks()
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

    def _update_disks(self):
        for w in self.disk_frame.winfo_children():
            w.destroy()
        disks = self._fetch("/api/vm/disks")
        if not disks:
            tk.Label(self.disk_frame, text="(coordinator offline)",
                     fg=DIM, font=("Menlo", 8)).pack()
            return
        for d in disks:
            row = tk.Frame(self.disk_frame, bg=BG2,
                           highlightbackground="#222", highlightthickness=1)
            row.pack(fill="x", pady=1)
            label = d["label"]
            if d["exists"]:
                info = f"{label}  {d['size_mb']:.0f}MB"
                lbl = tk.Label(row, text=info, fg=FG, bg=BG2,
                               font=("Menlo", 9), anchor="w")
                lbl.pack(side="left", padx=6, pady=3)
                resume_btn = tk.Button(
                    row, text="RESUME", fg="cyan", bg=BG2,
                    activebackground="#003333", font=("Menlo", 8),
                    command=lambda ot=d["os_type"]: self._resume(ot))
                resume_btn.pack(side="right", padx=2)
                wipe_btn = tk.Button(
                    row, text="WIPE", fg=RED, bg=BG2,
                    activebackground="#330000", font=("Menlo", 8),
                    command=lambda ot=d["os_type"]: self._wipe(ot))
                wipe_btn.pack(side="right", padx=2)
            else:
                lbl = tk.Label(row, text=f"{label}  (no disk)", fg=DIM, bg=BG2,
                               font=("Menlo", 9), anchor="w")
                lbl.pack(side="left", padx=6, pady=3)

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
            row = tk.Frame(self.sess_frame, bg=BG2,
                           highlightbackground="#222", highlightthickness=1)
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
                    activebackground="#330000", font=("Menlo", 8),
                    command=lambda vid=s["id"]: self._kill(vid))
                kill_btn.pack(side="right", padx=4)

    # ── Actions ──────────────────────────────────────────────────────────────
    def _launch(self, os_type):
        threading.Thread(target=self._do_action,
                         args=("launch", os_type), daemon=True).start()

    def _resume(self, os_type):
        threading.Thread(target=self._do_action,
                         args=("resume", os_type), daemon=True).start()

    def _wipe(self, os_type):
        threading.Thread(target=self._do_action,
                         args=("wipe", os_type), daemon=True).start()

    def _kill(self, vm_id):
        threading.Thread(target=self._do_action,
                         args=("kill", vm_id), daemon=True).start()

    def _do_action(self, action, arg):
        if action == "launch":
            print(f"[LAUNCH] Installing {arg}...")
            r = self._post("/api/vm/launch", {"os_type": arg})
            if r:
                print(f"  {r.get('message', 'OK')}")
        elif action == "resume":
            print(f"[RESUME] Booting {arg} from disk...")
            r = self._post(f"/api/vm/resume/{arg}")
            if r:
                print(f"  {r.get('message', 'OK')}")
            else:
                print(f"  [!!] No disk found for {arg}. Use Install instead.")
        elif action == "wipe":
            print(f"[WIPE] Deleting {arg} disk...")
            if self._delete(f"/api/vm/disk/{arg}"):
                print(f"  Disk for {arg} wiped.")
        elif action == "kill":
            print(f"[KILL] {arg}")
            self._delete(f"/api/vm/{arg}")


if __name__ == "__main__":
    print("Starting wwRIG Native GUI v0.3...")
    print(f"Coordinator API: {API}")
    print("Close this window to quit.\n")
    try:
        WWRigGUI()
    except KeyboardInterrupt:
        pass
