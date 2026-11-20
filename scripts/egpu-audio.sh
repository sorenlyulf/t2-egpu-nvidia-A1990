#!/bin/bash
# egpu-audio.sh - bind eGPU audio after boot has settled
GPU=0000:b9:00.0
AUD=0000:b9:00.1
LOG=/var/log/egpu-audio.log
exec >> "$LOG" 2>&1
echo "== $(date) =="

[ -e /sys/bus/pci/devices/$GPU/driver ] || { echo "GPU not bound, skipping"; exit 0; }
[ -e /sys/bus/pci/devices/$AUD ] || { echo "audio function absent, skipping"; exit 0; }
[ -e /sys/bus/pci/devices/$AUD/driver ] && { echo "already bound"; exit 0; }

modprobe snd_hda_intel
echo snd_hda_intel > /sys/bus/pci/devices/$AUD/driver_override
echo $AUD > /sys/bus/pci/drivers/snd_hda_intel/bind \
  && echo "OK: audio bound" || echo "bind failed, check dmesg"
