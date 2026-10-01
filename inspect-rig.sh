#!/usr/bin/env bash
# Read-only diagnostics. Output can contain MAC addresses and serial identifiers.
set -u
section() { printf '\n--- %s ---\n' "$1"; }
run() {
  if command -v "$1" >/dev/null 2>&1; then "$@" || true
  else printf 'Unavailable command: %s\n' "$1"; fi
}
section 'Kernel'; uname -sr
section 'USB devices'; run lsusb
section 'USB topology'; run lsusb -t
section 'Wi-Fi interfaces'; run iw dev
section 'Wi-Fi modes and frequencies'; run iw list
section 'Regulatory state'; run iw reg get
section 'Network driver paths'
for dev in /sys/class/net/*; do
  [ -e "$dev" ] || continue
  printf '%s: ' "${dev##*/}"
  readlink -f "$dev/device/driver" || true
done
section 'Bluetooth controllers'; run bluetoothctl list
section 'Bluetooth device paths'
for dev in /sys/class/bluetooth/hci*; do
  [ -e "$dev" ] || continue
  printf '%s: ' "${dev##*/}"
  readlink -f "$dev/device" || true
done
section 'Serial device paths'
for dev in /dev/serial/by-id/* /dev/ttyUSB* /dev/ttyACM*; do
  [ -e "$dev" ] && ls -l "$dev"
done
section 'Power status (not a PD contract measurement)'
for supply in /sys/class/power_supply/*; do
  [ -d "$supply" ] || continue
  printf '%s\n' "${supply##*/}"
  for field in type status online capacity voltage_now current_now power_now; do
    [ -r "$supply/$field" ] || continue
    printf '  %s: ' "$field"; cat "$supply/$field"
  done
done
exit 0
