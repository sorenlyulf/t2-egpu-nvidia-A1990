#!/bin/bash
# egpu-attach-128.sh - Persistent NVIDIA eGPU setup on Apple T2 Mac (Linux)
# Method: A. Telesca, IRST Institute, 2026 - see companion paper.
# VARIANT: BAR1 = 128 MiB (paper uses 64 MiB). Fits the 224 MiB window
#          cf700000-dd6fffff on this machine: BAR1 d0000000, BAR3 d8000000.
# Sequence:
#   1. guards (firmware window at root port, GPU present, 580xx module)
#   2. autoprobe OFF, BAR1 -> 128M via Resizable BAR (setpci)
#   3. remove upstream bridge + rescan (reallocation into 32-bit window)
#   4. guard: all BARs below 4G and assigned, BAR1 is 128M, no driver bound
#   5. driver_override + modprobe nvidia (GSP OFF via modprobe.d) + nvidia-uvm
# If the eGPU is not connected, exits 0 (normal boot without eGPU).
# Any failed guard = exit != 0 WITHOUT touching the GPU.
#
# !!! ADJUST THESE ADDRESSES TO YOUR TOPOLOGY (lspci -tv) !!!
GPU=0000:b9:00.0        # GPU function
AUD=0000:b9:00.1        # GPU audio function (left unbound on purpose)
BRIDGE=0000:7a:00.0     # upstream TB bridge to remove for rescan
ROOTPORT=00:01.2        # TB root port carrying the firmware window
WINDOW_BASE=cf700000    # expected start of 32-bit prefetchable window

LOG=/var/log/egpu-attach.log
exec > >(tee -a "$LOG") 2>&1
set -x
echo "===== egpu-attach-128 $(date) ====="
sync

GPUSHORT=${GPU#0000:}

# --- 0. GPU present? (short wait: TB enumeration at boot) ---
for i in $(seq 1 15); do
  [ -e /sys/bus/pci/devices/$GPU ] && break
  sleep 2
done
if [ ! -e /sys/bus/pci/devices/$GPU ]; then
  echo "eGPU not connected: exiting without action."
  exit 0
fi

# --- 1. Preliminary guards ---
PREF=$(lspci -vv -s $ROOTPORT | grep 'Prefetchable memory behind')
echo "$PREF"
echo "$PREF" | grep -q "$WINDOW_BASE" || { echo "!!! unexpected firmware window - STOP"; exit 1; }

MODVER=$(modinfo -F version nvidia 2>/dev/null)
case "$MODVER" in
  580.*) echo "OK: nvidia module $MODVER (580xx branch)" ;;
  *) echo "!!! unexpected nvidia module ($MODVER) - STOP"; exit 1 ;;
esac

if [ -e /sys/bus/pci/devices/$GPU/driver ]; then
  echo "!!! GPU already has a driver ($(readlink /sys/bus/pci/devices/$GPU/driver)) - STOP"
  exit 1
fi
sync

# --- 2. Autoprobe OFF + ReBAR: BAR1 -> 128M (size code 7: 2^(7+20) bytes) ---
echo 0 > /sys/bus/pci/drivers_autoprobe
sync

if ! lspci -vv -s $GPUSHORT | grep -q 'BAR 1: current size: 128MB'; then
  setpci -s $GPUSHORT COMMAND=0x0000
  setpci -s ${GPUSHORT%.*}.1 COMMAND=0x0000 2>/dev/null || true
  REBAR_OFF=$(lspci -s $GPUSHORT -vv | sed -n 's/.*Capabilities: \[\([0-9a-f]\+\).*Resizable BAR.*/\1/Ip' | head -1)
  [ -n "$REBAR_OFF" ] || { echo "!!! ReBAR capability not found - STOP"; exit 1; }
  FOUND=""
  for i in 0 1 2 3; do
    CTRL_OFF=$(printf '%x' $((0x$REBAR_OFF + 8 + 8*i)))
    CTRL=$(setpci -s $GPUSHORT ${CTRL_OFF}.l) || break
    IDX=$(( 0x$CTRL & 0x7 ))
    echo "entry $i: ctrl=0x$CTRL (BAR index $IDX)"
    if [ "$IDX" -eq 1 ]; then
      NEW=$(printf '%08x' $(( (0x$CTRL & 0xFFFFC0FF) | (7 << 8) )))
      setpci -s $GPUSHORT ${CTRL_OFF}.l=$NEW
      echo "wrote 0x$NEW, readback 0x$(setpci -s $GPUSHORT ${CTRL_OFF}.l)"
      FOUND=yes; break
    fi
  done
  [ -n "$FOUND" ] || { echo "!!! BAR1 ReBAR entry not found - STOP"; exit 1; }
fi
lspci -vv -s $GPUSHORT | grep 'BAR 1: current' || true
sync

# --- 3. Remove + rescan to reallocate into the 32-bit window ---
echo 1 > /sys/bus/pci/devices/$BRIDGE/remove
sleep 5
sync
echo 1 > /sys/bus/pci/rescan
sleep 8
sync

lspci -vv -s $GPUSHORT 2>/dev/null | grep -E 'Region'

# --- 4. Post-rescan guard: BARs <4G, assigned, BAR1 = 128M, no driver ---
BAD=$(lspci -vv -s $GPUSHORT 2>/dev/null | grep -E 'Region .: Memory at [0-9a-f]{9,}')
[ -z "$BAD" ] || { echo "!!! BAR above 4G - STOP"; echo "$BAD"; sync; exit 2; }
lspci -vv -s $GPUSHORT 2>/dev/null | grep -E 'Region [013].*(unassigned|ignored)' && { echo "!!! BARs unassigned - STOP"; sync; exit 3; }
lspci -vv -s $GPUSHORT 2>/dev/null | grep -qE 'Region 1:.*size=128M' || { echo "!!! BAR1 is not 128M after rescan - STOP"; sync; exit 8; }
for f in /sys/bus/pci/devices/$GPU/driver /sys/bus/pci/devices/$AUD/driver; do
  [ -e "$f" ] && { echo "!!! driver bound: $f -> $(readlink $f) - STOP"; sync; exit 4; }
done
echo "OK: BARs in 32-bit window, BAR1 = 128M, no driver bound"
sync

# --- 5. Bind nvidia (GSP OFF + NoMSI from /etc/modprobe.d/nvidia-egpu.conf) ---
echo "nvidia" > /sys/bus/pci/devices/$GPU/driver_override
echo "none"   > /sys/bus/pci/devices/$AUD/driver_override
sync
echo 1 > /sys/bus/pci/drivers_autoprobe
sync
modprobe nvidia NVreg_EnableGpuFirmware=0 NVreg_EnableMSI=0
RC=$?
echo "modprobe exit=$RC"
sleep 3
echo 0 > /sys/bus/pci/drivers_autoprobe
sync
[ $RC -eq 0 ] || { echo "!!! modprobe failed - STOP"; exit 5; }

ls -l /sys/bus/pci/devices/$GPU/driver
[ -e /sys/bus/pci/devices/$AUD/driver ] && echo "WARNING: audio function bound!" || echo "OK: audio unbound"

# Verify GSP disabled before touching the GPU
if grep -qi "GSP Firmware:.*[0-9]" /proc/driver/nvidia/gpus/*/information 2>/dev/null && \
   ! grep -qiE "GSP Firmware:\s*N/A|GSP Firmware:\s*disabled" /proc/driver/nvidia/gpus/*/information 2>/dev/null; then
  echo "!!! GSP appears ACTIVE - STOP before init"
  exit 6
fi
sync

# --- 6. Init + uvm for CUDA ---
timeout 60 nvidia-smi
RC=$?
echo "nvidia-smi exit=$RC"
sync
[ $RC -eq 0 ] || { echo "!!! nvidia-smi failed"; exit 7; }
modprobe nvidia-uvm || echo "note: nvidia-uvm not loaded"
grep -i gsp /proc/driver/nvidia/gpus/*/information 2>/dev/null || echo "GSP: absent from /proc (OFF, as intended)"

echo "===== eGPU ready: NVIDIA GPU active, GSP OFF, BAR1 128M ====="
sync
exit 0
