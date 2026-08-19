# t2-egpu-nvidia

**NVIDIA eGPU enablement on Apple T2 Intel Macs under Linux — Resizable BAR windowing method**

Author: **Antonio Telesca** — IRST Institute ([irst-institute.eu](https://irst-institute.eu))
ORCID: [0009-0003-3048-1044](https://orcid.org/0009-0003-3048-1044) · Web of Science ResearcherID: PKR-6753-2026 · Registered Expert, European Commission (ID: EX2026D1365471)

Companion repository for the paper: *"Circumventing Apple T2 Thunderbolt MMIO Restrictions: Enabling Large-BAR NVIDIA GPUs on Intel Macs via Resizable BAR Windowing"* (2026). DOI: [10.5281/zenodo.22011607](https://doi.org/10.5281/zenodo.22011607)

---

## TL;DR

T2-equipped Intel Macs hard-hang (no panic, no log) when a Thunderbolt eGPU's BARs are accessed above the 4 GiB boundary — **even when firmware declares a 64-bit window** — and, independently, when the NVIDIA GSP firmware boots. This has kept modern NVIDIA eGPUs unusable on these machines since 2019 ([t2linux issue #189](https://github.com/t2linux/T2-Debian-and-Ubuntu-Kernel/issues/189)).

**The fix (software-only):**
1. Shrink BAR1 (VRAM aperture) to 64 MiB via PCIe **Resizable BAR** (`setpci`)
2. PCI subtree **remove + rescan** → all BARs land in the firmware's 32-bit prefetchable window
3. Bind the **proprietary** NVIDIA driver (580.xx branch) with `NVreg_EnableGpuFirmware=0 NVreg_EnableMSI=0`

Validated: MacBookPro16,1 + RTX 3090 (24 GiB) — full CUDA, 352 W sustained load, Qwen3.8-27B (19.1 GiB in VRAM) at **36.3 tok/s** generation.

## ⚠️ Read before you try

- A wrong step (driver bound before BAR remediation, GSP enabled, BAR left above 4 GiB) **hard-hangs the machine instantly** with no log. The script fails closed at every guard — do not remove the guards.
- PCI addresses (`45:00.0`, bridge `06:00.0`, root port `00:01.1`, window base `c1700000`) are **specific to this machine/topology**. Identify yours with `lspci -tv` and `lspci -vv -s 00:0x.y | grep Prefetchable` and update the script before running.
- `nvidia-open` / GSP-only driver branches will **never** work on this platform (GSP boot kills the T2 fabric). Stay on a proprietary branch supporting `NVreg_EnableGpuFirmware=0` (validated: 580.173.02).
- Tested only on MacBookPro16,1 + GA102 so far. Replication reports are very welcome — please open an issue with your logs.

## Contents

| Path | Description |
|---|---|
| `scripts/egpu-attach.sh` | Boot-time attach script (guards + ReBAR shrink + rescan + controlled bind) |
| `config/nvidia-egpu.conf` | modprobe options + blacklist (`/etc/modprobe.d/`) |
| `config/egpu.service` | systemd oneshot unit (`/etc/systemd/system/`) |
| `docs/INSTALL.md` | Step-by-step installation guide |
| `docs/verification-report.txt` | Full validation evidence: nvidia-smi -q, lspci -vv, dmesg, load telemetry |
| `paper/` | Preprint (PDF on release) |

## Quick start

See [docs/INSTALL.md](docs/INSTALL.md). Summary:

```bash
# 1. Packages (CachyOS/Arch, legacy 580xx branch)
sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils opencl-nvidia-580xx bolt

# 2. Kernel cmdline: add intel_iommu=on, reboot

# 3. Authorize the enclosure (once)
boltctl list && sudo boltctl enroll --policy auto <UUID>

# 4. Install the three files (adjust PCI addresses first!)
sudo cp config/nvidia-egpu.conf /etc/modprobe.d/
sudo cp config/egpu.service /etc/systemd/system/
sudo install -m 755 scripts/egpu-attach.sh /usr/local/sbin/
sudo systemctl daemon-reload && sudo systemctl enable egpu.service
sudo mkinitcpio -P   # blacklist must reach early boot
sudo reboot
```

Verify: `systemctl status egpu.service`, `nvidia-smi`, and `lspci -vs <GPU> | grep 'Memory at'` → **all addresses must be < 0x100000000**.

## Validated configuration

- MacBookPro16,1 (Intel i9, Apple T2), CachyOS Linux, kernel 7.1.8-1-cachyos, Limine, btrfs
- RTX 3090 (GA102, VBIOS 94.02.59.00.5C), Thunderbolt enclosure (Intel JHL9480 Barlow Ridge)
- nvidia-580xx-dkms 580.173.02, CUDA 13.0, bolt 0.9.11

## Citation

```bibtex
@misc{telesca2026t2egpu,
  author = {Telesca, Antonio},
  title  = {Circumventing Apple T2 Thunderbolt MMIO Restrictions: Enabling
            Large-BAR NVIDIA GPUs on Intel Macs via Resizable BAR Windowing},
  year   = {2026},
  publisher = {Zenodo},
  doi    = {10.5281/zenodo.22011607}
}
```

## License

MIT — see [LICENSE](LICENSE).
