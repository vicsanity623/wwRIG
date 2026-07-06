# WWRIG Roadmap — From LAN Demo to World Wide Rig

Current: **v0.2** — Local network prototype with real QEMU VM + mobile node support.

The vision is grand, but the path is grounded in real engineering constraints.
Below is the honest, step-by-step plan.

---

## v0.3 — Internet-Ready Coordinator
**Goal:** Anyone on the internet can connect a node.

- [ ] **TLS/HTTPS** — Certbot + Caddy reverse proxy for the coordinator
- [ ] **Coordinator discovery** — Public registry so nodes find coordinators
- [ ] **Persistent database** — SQLite instead of in-memory dict (survives restarts)
- [ ] **Graceful shutdown** — SIGTERM handler, save state
- [ ] **Structured logging** — JSON logs for monitoring
- [ ] **Rate limiting** — Prevent abuse of `/api/vm/launch`

*Difficulty: Moderate. Mostly plumbing and configuration.*

---

## v0.4 — Distributed Sessions (The Hard Part)
**Goal:** A VM uses CPU/RAM from *multiple physical machines* simultaneously.

This is the core technical challenge. A QEMU process runs on one host and
cannot transparently use another machine's CPU or RAM. To make this work:

### Option A: Kubernetes / KubeVirt (Recommended Path)
- [ ] Package coordinator as a Kubernetes operator
- [ ] Use **KubeVirt** to orchestrate VM pods across a cluster
- [ ] Each worker machine runs kubelet + libvirt
- [ ] KubeVirt schedules VM pods across the cluster automatically
- [ ] Add a `wwrig-node --kubernetes` mode that joins the cluster

**Why KubeVirt:**
- Mature, production-grade VM orchestration
- Handles live migration, resource scheduling, node failures
- Pods can request CPU/RAM from specific nodes via nodeSelector

**Caveats:**
- Requires a Kubernetes control plane (at least 1 dedicated machine)
- Overhead: each node needs KVM + kubelet
- Not trivial to set up (hours, not minutes)

### Option B: Proxmox VE Cluster
- [ ] Install Proxmox on each physical machine
- [ ] Cluster them together
- [ ] Use WWRIG as the frontend API that talks to Proxmox API
- [ ] Proxmox handles VM placement, live migration, HA

**Why Proxmox:**
- Easier to set up than Kubernetes for VM workloads
- Built-in web UI, backup, HA
- Well-documented API

**Caveats:**
- Requires dedicated Proxmox install (no desktop usage)
- Not ideal for casual contributors (Android phones can't run Proxmox)

### Option C: Custom MPI / Distributed QEMU
- [ ] Research QEMU's multi-process QEMU (pre-allocated backends)
- [ ] Split VM memory across machines via RDMA or shared memory
- [ ] Extremely complex — few successful implementations exist

*Not recommended. Reinventing the wheel when KubeVirt/Proxmox exist.*

*Difficulty: Hard to Very Hard. This is where most distributed computing
projects stall.*

---

## v0.5 — GPU Contribution
**Goal:** VMs can use GPUs from the pool for compute workloads.

- [ ] GPU passthrough (vfio) for dedicated GPUs
- [ ] NVIDIA MIG / AMD SR-IOV for GPU partitioning
- [ ] vGPU for shared GPU access
- [ ] WebGPU / CUDA forwarding for ML workloads

*Difficulty: Very Hard. GPU virtualization is notoriously finicky.*

---

## v0.6 — Native Mobile Nodes
**Goal:** Android/iOS devices contribute actual compute (not just stats).

- [ ] Native Android app (Kotlin) with background service
- [ ] WebAssembly micro-tasks for browser-based contribution
- [ ] BOINC-style background compute for phones
- [ ] iOS app (Swift) — limited due to App Store restrictions

*Difficulty: Moderate. The Android app is doable; iOS has sandbox limits.*

---

## v1.0 — Public Network
**Goal:** Anyone can join, anyone can launch, everything is secure.

- [ ] Public coordinator registry at wwrig.io
- [ ] Node reputation system (uptime, contribution history)
- [ ] Automatic TLS (Let's Encrypt)
- [ ] Session billing / resource accounting
- [ ] Load balancing across multiple coordinators
- [ ] WebRTC for real-time node communication
- [ ] One-click deploy (Homebrew formula, apt repo, Docker Hub)
- [ ] CI/CD, integration tests, performance benchmarks

---

## Hard Truths

1. **True distributed VMs are hard.** No magic library makes QEMU span machines.
   KubeVirt is the best existing solution, but it's infrastructure-heavy.

2. **Android phones cannot run QEMU.** They can contribute tasks (WebAssembly,
   BOINC-style), but not CPU cores to a running VM.

3. **Network latency kills distributed VM performance.** A VM running across
   machines on different continents will be unusably slow. Sub-millisecond
   latency (same rack / same building) is required.

4. **GPU passthrough requires dedicated hardware.** You can't split a consumer
   GPU across multiple VMs without SR-IOV, which only enterprise GPUs support.

5. **This is a research project.** The path from v0.2 to v1.0 involves solving
   problems that distributed systems researchers have worked on for decades.

---

## Why Bother?

Because no one has made a truly *simple* distributed computing network where:

- Anyone can contribute from any device (phone, laptop, server)
- Anyone can launch a session without cloud provider accounts
- The system "just works" — join and contribute

Even if the compute model stays single-host for now, the *network* model
(node discovery, stats aggregation, session management) is the foundation.
The distributed VM layer can be swapped in later as the infrastructure matures.

*Rome wasn't rigged in a day.*
