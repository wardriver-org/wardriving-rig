#!/usr/bin/env bash
# Wardriver.org Kali rig setup v1.0 — 2026-10-01
# Run: sudo bash setup-kali-rig.sh
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
umask 022
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID == 0 ]] || fail 'Run with sudo bash setup-kali-rig.sh'
[[ -t 0 ]] || fail 'Run from an interactive terminal, not a pipe.'
. /etc/os-release
[[ ${ID:-} == kali ]] || fail 'This installer targets Kali Linux.'
[[ -d /run/systemd/system ]] || fail 'A normal systemd Kali installation is required.'
! systemctl is-active --quiet wardriver.service || fail 'Stop capture first: sudo wardriver stop'
rig_user=${SUDO_USER:-}
if [[ -z $rig_user || $rig_user == root ]]; then read -r -p 'Normal login username: ' rig_user; fi
[[ $rig_user =~ ^[a-z_][a-z0-9_-]*\$?$ ]] || fail 'Invalid username.'
[[ $(id -u "$rig_user") != 0 ]] || fail 'Choose a non-root login user.'
rig_home=$(getent passwd "$rig_user" | cut -d: -f6)
[[ -d $rig_home ]] || fail 'User home does not exist.'
printf '\nKali mobile rig setup\nThree ALFA radios, optional StarTech Bluetooth and VFAN GPS.\n'
printf 'Installs Kali packages; configures a manual-start capture service.\nSelect only survey radios. Keep your Internet adapter separate.\n\n'
apt-get update
apt-get install -y kismet kismet-capture-linux-wifi kismet-capture-linux-bluetooth \
  kismet-logtools iw usbutils ethtool network-manager bluez gpsd gpsd-clients rfkill python3
# Offer Kali-packaged Realtek drivers only for exact detected USB IDs.
# Existing working drivers can be retained by answering no.
lsusb
for usb_id in 0bda:8813 0bda:8812; do
  if lsusb -d "$usb_id" | grep -q .; then
    case $usb_id in
      0bda:8813) driver_pkg=realtek-rtl8814au-dkms;;
      0bda:8812) driver_pkg=realtek-rtl88xxau-dkms;;
    esac
    read -r -p "USB $usb_id detected. Install $driver_pkg if its radio is missing? [y/N]: " answer
    if [[ $answer == y || $answer == Y ]]; then
      [[ -d /lib/modules/$(uname -r)/build ]] || apt-get install -y "linux-headers-$(uname -r)"
      apt-get install -y dkms "$driver_pkg"
      echo 'Driver installed. Reboot, then rerun this script to map devices.'
      echo 'If Secure Boot rejects the module, complete Kali module signing/enrollment first.'
      exit 0
    fi
  fi
done
getent group kismet >/dev/null || fail 'Kismet group missing; review Kali package configuration.'
usermod -aG kismet "$rig_user"
# Use the distribution's privilege setup, never chmod capture binaries ourselves.
for helper in kismet_cap_linux_wifi kismet_cap_linux_bluetooth; do
  helper_path=$(command -v "$helper" || true)
  [[ -n $helper_path ]] || fail "Missing $helper"
  if [[ ! -u $helper_path ]]; then
    printf '\n%s is not setuid. Configure packaged capture privileges.\n' "$helper"
    owner_pkg=$(dpkg-query -S "$helper_path" | head -n1 | cut -d: -f1)
    dpkg-reconfigure "$owner_pkg"
    [[ -u $helper_path ]] || fail "Capture helper still lacks packaged setuid permission: $helper_path"
  fi
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
lsusb
printf '\nWireless devices (driver and physical USB path):\n'
for dev in /sys/class/net/*; do
  [[ -d $dev/phy80211 ]] || continue
  name=${dev##*/}
  printf '\n%s  driver=%s\n  %s\n' "$name" "$(basename "$(readlink -f "$dev/device/driver")")" "$(readlink -f "$dev/device")"
  ethtool -P "$name" || true
done
printf '\nSelect interfaces by name. Enter skip for an absent/unsupported radio.\n'
printf 'Suggested: radio 1 = 2.4; AWUS1900 = 5; AXML = 6.\n'
declare -A chosen=()
count=0
for role in radio1 awus1900 axml; do
  while true; do
    read -r -p "$role interface (or skip): " iface
    [[ $iface == skip ]] && break
    [[ $iface =~ ^[a-zA-Z0-9_.-]+$ && -d /sys/class/net/$iface/phy80211 ]] || { echo 'Not a wireless interface.'; continue; }
    physical=$(readlink -f "/sys/class/net/$iface/device")
    [[ $physical == */usb* ]] || { echo 'Select an external USB radio, not the laptop internal radio.'; continue; }
    [[ ! ${chosen[$physical]+yes} ]] || { echo 'This radio is already selected.'; continue; }
    phy=$(basename "$(readlink -f "/sys/class/net/$iface/phy80211")")
    iw phy "$phy" info > "$work/phy"
    grep -Eq '^[[:space:]]+\* monitor$' "$work/phy" || { echo 'Driver does not report monitor mode. Skip and diagnose its USB ID/driver.'; continue; }
    if ip -o addr show dev "$iface" scope global | grep -q .; then
      echo 'This interface has a network address. Disconnect its network first, or select another adapter.'
      continue
    fi
    read -r -p 'Band [2.4 / 5 / 6 / auto]: ' band
    case $band in 2.4|5|6|auto) ;; *) echo 'Invalid band.'; continue;; esac
    # Validate at least one enabled frequency in the requested band.
    if ! python3 - "$work/phy" "$band" <<'PY'
import re,sys
band=sys.argv[2]
fs=[int(m.group(1)) for l in open(sys.argv[1]) if 'disabled' not in l
    for m in [re.search(r'\*\s+(\d+) MHz \[',l)] if m]
bounds={'2.4':(2400,2500),'5':(4900,5925),'6':(5925,7125),'auto':(0,99999)}
lo,hi=bounds[band]
sys.exit(0 if any(lo <= f < hi for f in fs) else 1)
PY
    then echo 'No enabled frequencies in that band. Choose another band or skip.'; continue; fi
    chosen[$physical]=1
    printf '%s\t%s\t%s\n' "$role" "$physical" "$band" >> "$work/radios.tsv"
    count=$((count+1))
    break
  done
done
((count > 0)) || fail 'No usable Wi-Fi radios selected. Run lsusb and iw dev to diagnose drivers.'
printf '\nBluetooth controllers:\n'
bluetoothctl list || true
for dev in /sys/class/bluetooth/hci*; do
  [[ -e $dev ]] || continue
  printf '%s  %s\n' "${dev##*/}" "$(cat "$dev/address")"
done
bt_address=''
read -r -p 'StarTech hci interface (e.g. hci1), or skip: ' bt
if [[ $bt != skip ]]; then
  [[ $bt =~ ^hci[0-9]+$ && -f /sys/class/bluetooth/$bt/address ]] || fail 'Invalid Bluetooth controller.'
  bt_address=$(cat "/sys/class/bluetooth/$bt/address")
fi
printf '\nGPS serial ports (prefer /dev/serial/by-id/...):\n'
ls -l /dev/serial/by-id/ /dev/serial/by-path/ /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true
read -r -p 'VFAN GPS device path, or skip: ' gps_device
if [[ $gps_device != skip ]]; then
  [[ $gps_device =~ ^/dev/[a-zA-Z0-9_./:+-]+$ && -c $gps_device ]] || fail 'Invalid GPS character-device path.'
  case $(readlink -f "$gps_device") in /dev/ttyACM*|/dev/ttyUSB*) ;; *) fail 'Select a USB serial GPS port.';; esac
fi
backup=/var/backups/wardriver/$(date +%Y%m%d-%H%M%S)-$$
install -d -m 700 "$backup"
for path in /etc/wardriver /usr/local/sbin/wardriver /etc/systemd/system/wardriver.service /etc/default/gpsd /etc/systemd/system/gpsd.socket.d/wardriver.conf; do
  [[ ! -e $path ]] || cp -a --parents "$path" "$backup/"
done
systemctl is-enabled gpsd.socket > "$backup/gpsd-socket-enabled.txt" 2>&1 || true
systemctl is-active gpsd.service > "$backup/gpsd-active.txt" 2>&1 || true
install -d -m 755 /etc/wardriver
install -m 644 "$work/radios.tsv" /etc/wardriver/radios.tsv
# Root-owned settings: shell-escape values before storing.
{
  printf 'RIG_USER=%q\nRIG_HOME=%q\nBT_ADDRESS=%q\nGPS_DEVICE=%q\n' "$rig_user" "$rig_home" "$bt_address" "$gps_device"
} > /etc/wardriver/settings
chmod 644 /etc/wardriver/settings
install -d -o "$rig_user" -g "$(id -gn "$rig_user")" -m 700 /var/lib/wardriver
install -d -o "$rig_user" -g "$(id -gn "$rig_user")" -m 700 /var/lib/wardriver/captures
if [[ $gps_device != skip ]]; then
  printf 'START_DAEMON="true"\nUSBAUTO="false"\nDEVICES="%s"\nGPSD_OPTIONS="-n -b"\n' "$gps_device" > /etc/default/gpsd
  install -d -m 755 /etc/systemd/system/gpsd.socket.d
  cat > /etc/systemd/system/gpsd.socket.d/wardriver.conf <<'GPS'
[Socket]
ListenStream=
ListenStream=/run/gpsd.sock
ListenStream=127.0.0.1:2947
GPS
  systemctl stop gpsd.service gpsd.socket
  systemctl daemon-reload
  systemctl enable --now gpsd.socket
  systemctl start gpsd.service
fi
cat > /usr/local/sbin/wardriver <<'RUNNER'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
[[ $EUID == 0 ]] || { echo 'Use sudo wardriver start|stop|status|logs|doctor'; exit 1; }
# Root-owned, installer-generated configuration only.
source /etc/wardriver/settings
case ${1:-help} in
 start) systemctl start wardriver.service; echo 'Open http://127.0.0.1:2501 and check every source plus GPS.'; exit;;
 stop) systemctl stop wardriver.service; exit;;
 status) systemctl --no-pager --full status wardriver.service gpsd.service || true; exit;;
 logs) exec journalctl -u wardriver.service -f;;
 doctor)
   uname -r; lsusb; iw dev; iw reg get; rfkill list
   systemctl --no-pager --full status wardriver.service gpsd.service || true
   ss -ltnp | grep -E ':(2501|2947)\b' || true
   df -h /var/lib/wardriver/captures
   echo 'GPS test: cgps -s'; echo 'USB errors: sudo journalctl -k -b | tail -n 80'
   exit;;
 _run) ;;
 *) echo 'Usage: sudo wardriver {start|stop|status|logs|doctor}'; exit;;
esac
umask 077
mkdir -p /run/wardriver
chmod 755 /run/wardriver
exec 9>/run/wardriver/lock
flock -n 9 || { echo 'Capture already running'; exit 1; }
# Resolve physical USB locations each start: wlan numbers may have changed.
ifaces=(); states=(); child=''; cfg=''
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  if [[ -n $child ]] && kill -0 "$child" 2>/dev/null; then
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" || true
  fi
  for i in "${!ifaces[@]}"; do
    [[ -d /sys/class/net/${ifaces[$i]} ]] || continue
    nmcli device set "${ifaces[$i]}" managed "${states[$i]}" || true
  done
  [[ -z $cfg ]] || rm -f -- "$cfg"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cfg=$(mktemp /run/wardriver/kismet.XXXXXX.conf)
chmod 644 "$cfg"
cat > "$cfg" <<'CONF'
server_name=Wardriver-mobile
httpd_bind_address=127.0.0.1
httpd_port=2501
log_types=kismet,wiglecsv
log_prefix=/var/lib/wardriver/captures/
CONF
while IFS=$'\t' read -r role physical band; do
  iface=''
  for dev in /sys/class/net/*; do
    [[ -d $dev/phy80211 ]] || continue
    [[ $(readlink -f "$dev/device") == "$physical" ]] || continue
    name=${dev##*/}
    # Exclude monitor interfaces left over from other tools.
    type=$(iw dev "$name" info | awk '$1=="type" {print $2}')
    [[ $type == managed ]] || continue
    [[ -z $iface ]] || { echo "Multiple interfaces for $role; remove extra virtual interfaces first."; exit 1; }
    iface=$name
  done
  [[ -n $iface ]] || { echo "Missing $role. Reconnect to original USB port or rerun setup."; exit 1; }
  if ip -o addr show dev "$iface" scope global | grep -q .; then
    echo "Refusing to disconnect active network interface $iface"; exit 1
  fi
  phy=$(basename "$(readlink -f "/sys/class/net/$iface/phy80211")")
  # Rebuild 20-MHz hop lists at every start from current regulatory/driver state.
  channels=$(iw phy "$phy" info | python3 -c '
import re,sys
band=sys.argv[1]; out=[]
for l in sys.stdin:
 m=re.search(r"\*\s+(\d+) MHz \[(\d+)\]",l)
 if not m or "disabled" in l: continue
 f,c=map(int,m.groups())
 b="2.4" if 2400<=f<2500 else "5" if 4900<=f<5925 else "6" if 5925<=f<7125 else "other"
 if b=="other" or (band!="auto" and band!=b): continue
 if b=="6" and (f<5955 or (f-5955)%20): continue
 token=str(c)+("W6e" if b=="6" else "")
 if token not in out: out.append(token)
print(",".join(out))
' "$band")
  [[ -n $channels ]] || { echo "No enabled channels for $role band $band"; exit 1; }
  state=$(nmcli -g GENERAL.NM-MANAGED device show "$iface")
  [[ $state == yes || $state == no ]] || { echo "Cannot read NetworkManager state: $iface"; exit 1; }
  ifaces+=("$iface"); states+=("$state")
  nmcli device set "$iface" managed no
  printf 'source=%s:type=linuxwifi,name=%s,channel_hop=true,channels="%s"\n' "$iface" "$role" "$channels" >> "$cfg"
  echo "$role: $iface ($band GHz); channels=$channels"
done < /etc/wardriver/radios.tsv
if [[ -n $BT_ADDRESS ]]; then
  bt=''
  for dev in /sys/class/bluetooth/hci*; do
    [[ -f $dev/address ]] || continue
    [[ $(cat "$dev/address") != "$BT_ADDRESS" ]] || bt=${dev##*/}
  done
  [[ -n $bt ]] || { echo 'Selected Bluetooth adapter is missing.'; exit 1; }
  printf 'source=%s:type=linuxbluetooth,name=startech\n' "$bt" >> "$cfg"
fi
if [[ $GPS_DEVICE != skip ]]; then
  [[ -c $GPS_DEVICE ]] || { echo 'GPS device is missing.'; exit 1; }
  systemctl start gpsd.socket gpsd.service
  printf 'gps=gpsd:host=127.0.0.1,port=2947\n' >> "$cfg"
fi
# The server runs as the normal user; packaged helpers handle capture privileges.
cd /var/lib/wardriver/captures
runuser -u "$RIG_USER" -- env HOME="$RIG_HOME" \
  /usr/bin/kismet --no-ncurses --override="$cfg" &
child=$!
wait "$child"
RUNNER
chmod 755 /usr/local/sbin/wardriver
cat > /etc/systemd/system/wardriver.service <<'SERVICE'
[Unit]
Description=Wardriver mobile Kismet rig
After=NetworkManager.service bluetooth.service
Wants=NetworkManager.service bluetooth.service
[Service]
Type=simple
ExecStart=/usr/local/sbin/wardriver _run
KillMode=control-group
KillSignal=SIGINT
TimeoutStopSec=45
Restart=no
UMask=0077
[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
printf '\nSetup complete. Backups: %s\n' "$backup"
printf 'Start:  sudo wardriver start\nStop:   sudo wardriver stop\nStatus: sudo wardriver status\nLogs:   sudo wardriver logs\nCheck:  sudo wardriver doctor\n'
printf 'Web UI: http://127.0.0.1:2501\nCaptures: /var/lib/wardriver/captures\n'
printf 'Keep radios in the same USB ports. Rerun setup to change the map.\n'
printf 'Before driving, confirm GPS fix with cgps -s and verify all sources in Kismet.\n'
