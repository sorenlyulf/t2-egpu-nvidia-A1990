# Installation guide

Reference system: CachyOS (Arch-based), kernel linux-cachyos-lts, Apple T2 Mac
with base T2 Linux setup already done (t2linux kernel/firmware — separate prerequisite,
see [t2linux wiki](https://wiki.t2linux.org)).

## The two rules that keep your machine alive

1. **The NVIDIA driver must NEVER bind before the BARs are fixed.** The blacklist
   in `nvidia-egpu.conf` + explicit bind in the script enforce this. Install the
   blacklist FIRST, regenerate the initramfs, and only then enroll/connect the eGPU.
2. **GSP must stay off** (`NVreg_EnableGpuFirmware=0`) and use a proprietary
   driver branch that supports it. `nvidia-open` will hang the machine.

## Steps

### 1. Packages

```bash
sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils opencl-nvidia-580xx bolt
# optional, only for 32-bit apps/Steam:
sudo pacman -S lib32-nvidia-580xx-utils lib32-opencl-nvidia-580xx
```

Validated version: **580.173.02**. Any branch must support `NVreg_EnableGpuFirmware=0`.

### 2. Kernel cmdline

Add `intel_iommu=on` to your bootloader (Limine: `/boot/limine.conf`), reboot, verify:

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
lspci -vv -s 00:01.1 | grep Prefetchable   # root port window (try 00:01.0/1/2...)
```

Edit the variables at the top of `scripts/egpu-attach.sh` (GPU, AUD, BRIDGE,
ROOTPORT, WINDOW_BASE) to match.

### 6. Install script + service

```bash
sudo install -m 755 scripts/egpu-attach.sh /usr/local/sbin/
sudo cp config/egpu.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable egpu.service
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
