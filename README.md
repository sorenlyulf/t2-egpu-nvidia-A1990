# t2-egpu-nvidia-A1990
**NVIDIA eGPU enablement on Apple T2 Intel Macs under Linux — Resizable BAR windowing method**

I recently received an RTX 3080 from a friend who upgraded. However I run CachyOS on my T2 MacBook Pro, so I ran into the issue that is described in Antonio Telesca's paper and repo. After using his instructions exactly as described below, I was able to get my RTX 3080 working. Afterward I wasn't quite satisfied so I read everything again and did a little research of my own. I noticed when changing the windowbase in the script that my prefetchable window address started way sooner than what was cited, allowing me to run my card with a 128MB aperture instead of 64MB, and it was stable. After some testing I found that not only was it very usable for an agentic work flow, but I can use it for some gaming tasks as well. To go along with the changes to the original script I wrote a script and service file to bind audio to the card as a oneshot service after startup. I did this to prevent any hang ups that may happen if the audio was bound at boot with the GPU itself. Every important step is the same. **FOLLOW THEM TO THE LETTER**. The only changes are in the egpu-attach.sh script to resize BAR1 to 128MB instead of 64MB, and the terminal commands to install the egpu-audio.sh and the 99-egpu-audio.service.
As far as I'm aware this will only work if you have a model A1990 MacBook Pro (15-inch, 2018/2019) and the address for the prefetchable window is cf700000-dd6fffff. The prefetchable window is very important because if it starts after cf700000, this specific script file will not work and you should use the script from [TelescaAntonio/t2-egpu-nvidia](https://github.com/TelescaAntonio/t2-egpu-nvidia).

# Installation guide

Reference system: CachyOS (Arch-based), kernel linux-cachyos, Apple T2 MacBook Pro
with base T2 Linux setup already done (separate prerequisites. see the [t2linux wiki](https://wiki.t2linux.org)).

## The two rules that keep your machine alive

1. **The NVIDIA driver must NEVER bind before the BARs are fixed.** The blacklist
   in `nvidia-egpu.conf` + explicit bind in the script enforce this. Install the
   blacklist FIRST, regenerate the initramfs, and only then enroll/connect the eGPU.
2. **GSP must stay off** (`NVreg_EnableGpuFirmware=0`) and use a proprietary
   driver branch that supports it. `nvidia-open` will hang the machine.

## Steps

### 1. Install Packages

```bash
sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils opencl-nvidia-580xx bolt
# optional, only for 32-bit apps/Steam:
sudo pacman -S lib32-nvidia-580xx-utils lib32-opencl-nvidia-580xx
```

Validated version: **580.196.07**. Any branch must support `NVreg_EnableGpuFirmware=0`.

### 2. Kernel cmdline

Add `intel_iommu=on` to your bootloader if you haven't already from the [t2linux wiki](https://wiki.t2linux.org) (Limine: `/boot/limine.conf`), reboot, verify:

```bash
cat /proc/cmdline | grep intel_iommu
```

### 3. Install config files (BEFORE connecting the eGPU)

```bash
sudo cp config/nvidia-egpu.conf /etc/modprobe.d/
sudo mkinitcpio -P        # or: sudo dracut --regenerate-all --force
```

### 4. Thunderbolt authorization (once, eGPU connected)

```bash
boltctl list
sudo boltctl enroll --policy auto <UUID>
```

### 5. Identify YOUR PCI addresses

```bash
lspci -tv                                  # find GPU + upstream bridge
lspci -vv -s 00:01.2 | grep Prefetchable   # root port window (try 00:01.0/1/2...)
```

Edit the variables at the top of `scripts/egpu-attach.sh` (GPU, AUD, BRIDGE,
ROOTPORT, WINDOW_BASE) to match.

### 6. Install script + service

```bash
sudo install -m 755 scripts/egpu-attach.sh /usr/local/sbin/
sudo install -m 755 scripts/egpu-audio.sh /usr/local/bin/
sudo cp config/egpu.service /etc/systemd/system/
sudo cp config/99-egpu-audio.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable egpu.service && sudo systemctl enable 99-egpu-audio.service
sudo reboot
```

### 7. Verify (all must pass)

```bash
systemctl status egpu.service          # active (exited), success
nvidia-smi                             # GPU visible
lspci -vs <GPU> | grep 'Memory at'     # ALL addresses < 0x100000000
grep -i gsp /proc/driver/nvidia/gpus/*/information   # N/A or absent
journalctl -b -p err                   # no nvidia/pci errors
tail -50 /var/log/egpu-attach.log      # "===== eGPU ready ====="
```

## Troubleshooting

- **Guard "unexpected firmware window" trips** → your root port/window differ;
  re-check step 5. Do NOT bypass the guard.
- **BARs above 4G after rescan** → do not load the driver; repeat remove+rescan
  or reboot.
- **Machine hangs** → power off completely (not reboot), disconnect eGPU, boot,
  check `/var/log/egpu-attach.log` (written synchronously exactly for this).
- Keep the nvidia package pinned; a silent upgrade to a GSP-only branch will
  hang the machine at next attach.


## Validated configuration

- MacBookPro 15,1 (Intel i7-9750H, Apple T2), CachyOS Linux, kernel 7.3.4-1-cachyos, Limine, btrfs
- NVIDIA GeForce RTX 3080 Lite Hash Rate (GA102, VBIOS 94.02.71.40.AA), Thunderbolt 3 eGPU dock (Intel JHL7540 Titan Ridge 4C 2018)
- Driver Version: 580.196.07, CUDA 13.0, bolt 0.9.11


## Citation

Author: **Antonio Telesca** — IRST Institute ([irst-institute.eu](https://irst-institute.eu))
ORCID: [0009-0003-3048-1044](https://orcid.org/0009-0003-3048-1044) · Web of Science ResearcherID: PKR-6753-2026 · Registered Expert, European Commission (ID: EX2026D1365471)

Companion repository for the paper: *"Circumventing Apple T2 Thunderbolt MMIO Restrictions: Enabling Large-BAR NVIDIA GPUs on Intel Macs via Resizable BAR Windowing"* (2026). DOI: [10.5281/zenodo.22011607](https://doi.org/10.5281/zenodo.22011607)

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

**GNU AGPL-3.0** — see [LICENSE](LICENSE).

- You may use, study, modify and redistribute this software, but **any derivative — including software offered as a network service — must remain open source under the same license**, retaining the copyright notice of Antonio Telesca / IRST Institute. See [NOTICE](NOTICE) for details.
- **Citation**: if you use this software in academic work, please cite the paper — A. Telesca, *"Circumventing Apple T2 Thunderbolt MMIO Restrictions"*, 2026, DOI [10.5281/zenodo.22011607](https://doi.org/10.5281/zenodo.22011607) (machine-readable form in [CITATION.cff](CITATION.cff)).
- **Commercial / closed-source licensing** is available separately: contact antonio.telesca@irst-institute.eu.
