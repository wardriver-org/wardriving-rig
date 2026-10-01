Wardriver.org — Kali rig setup v1.0
October 1, 2026

QUICK START
1. Plug in the hub, ALFA radios, StarTech Bluetooth adapter and VFAN GPS.
2. Keep Internet access on the laptop's internal Wi-Fi or Ethernet.
3. In the directory containing the downloaded script, run:

   sudo bash setup-kali-rig.sh

4. The wizard shows USB devices, Wi-Fi interfaces and their physical paths.
   Map radio1 to your first ALFA, awus1900 to the four-antenna ALFA,
   and axml to the AWUS036AXML. Check the first ALFA's model label.
   If uncertain, unplug/replug one device and compare `iw dev` / `lsusb`.
5. Suggested bands: radio1 = 2.4, AWUS1900 = 5, AXML = 6.
   Choose auto or a supported alternate band if 6 GHz is unavailable.
   You can type skip for a device that is absent or not working yet.
6. Select the external Bluetooth controller, not Dell's internal one.
   Unplug/replug the StarTech and compare `bluetoothctl list` if unsure.
7. Select the GPS serial path. Prefer /dev/serial/by-id/...; by-path is
   next best. A /dev/ttyACM0 or /dev/ttyUSB0 path can change after reboot.
8. Start capture:

   sudo wardriver start

9. Open http://127.0.0.1:2501 on the laptop. Complete Kismet's account
   setup and inspect every source for errors and actual observations.
10. Outdoors, run `cgps -s`. Wait for a real position fix and confirm
    the location in Kismet. Connected GPS hardware alone is insufficient.

DAILY COMMANDS
sudo wardriver start       Start the manual-start systemd service
sudo wardriver stop        Stop capture and restore NetworkManager state
sudo wardriver status      Show capture and GPS service state
sudo wardriver logs        Follow Kismet output; Ctrl-C exits the viewer
sudo wardriver doctor      Show USB, radios, regulatory state, ports, disk
cgps -s                   See GPS position/fix

Files are under /var/lib/wardriver/captures, owned by your normal user.
Both .kismet databases and .wiglecsv logs are requested. WiGLE records
need a valid GPS location. Stop cleanly before copying/importing logs.
This script does not upload observations anywhere. Review a small CSV
in your installed Wardriver-local version before importing a long run.

WHAT CHANGES
- Installs tools from configured Kali apt repositories, not a full upgrade.
- Adds your chosen user to the package-created kismet group and uses the
  package's capture-helper privilege configuration. Kismet's web server
  runs as that normal user.
- Offers optional Kali Realtek DKMS packages for USB IDs 0bda:8813 and
  0bda:8812 only. Keep an existing working driver by answering no.
  If installed, reboot and rerun setup; answer no on the next run if the
  radio now works. Kernel headers must match the running kernel.
- Stores USB-port mappings in /etc/wardriver/radios.tsv. Keep each radio
  in its original hub port, and the hub in the same laptop port. Rerun
  setup if you change ports or hardware. Interface numbering can change.
- Resolves the Bluetooth controller by its address at each start.
- Builds explicit 20 MHz channel lists from each PHY on every start,
  excludes disabled frequencies and distinguishes 6 GHz channel numbers.
  Kernel regulatory settings are retained; no country override is made.
- Temporarily releases only selected Wi-Fi interfaces from NetworkManager.
  Interfaces with a global IP address are rejected to avoid disconnecting
  a working network. Original managed/unmanaged state is restored at stop.
- Adds wardriver.service, with no automatic startup or automatic restart.
  Failed sources may not terminate Kismet: check the UI, not only systemd.
- Uses a separate Kismet override, leaving existing Kismet config files
  intact. The web UI is restricted to 127.0.0.1:2501.
- If GPS is selected, replaces /etc/default/gpsd, disables USB auto-pick,
  adds a localhost-only gpsd socket override, enables the GPS socket and
  restarts gpsd. Existing GPS applications will see that restart.
  The GPS daemon is configured with read-only receiver access (-b).
- Backs up replaced configuration under /var/backups/wardriver/<timestamp>.

LIMITATIONS AND FIRST TEST
The script passed Bash syntax checks and four channel-parser tests. It has
not run on your Dell or radios. Driver-reported channels do not establish
successful capture, especially 6 GHz. Confirm tuning and observations.

If a Wi-Fi radio is missing, use lsusb, iw dev and kernel logs to identify
its chipset and driver. The first ALFA model remains unconfirmed, so the
script does not infer a driver from the marketing name. MediaTek firmware
or other missing drivers may need separate diagnosis from actual USB IDs.
If matching kernel headers are unavailable, update Kali's kernel using
its normal maintenance process, reboot and rerun; this script does not
perform a distribution upgrade or force a mismatched DKMS build.

If a capture helper lacks privilege, the wizard opens the owning package's
configuration. Enable its packaged setuid capture support when offered.
The installer stops if that support remains unavailable rather than
running the whole Kismet server as root.

Standard Linux Bluetooth HCI is active discovery of Bluetooth/BLE devices,
not passive capture of arbitrary Bluetooth connections. This script uses
that source. Wi-Fi capture uses monitor mode.

If GPS stays empty, verify you selected the VFAN port and have a sky view.
Inspect `systemctl cat gpsd.service` if the local package ignores
/etc/default/gpsd. `sudo journalctl -u gpsd.service -b` shows failures.
Replugging the GPS during capture may require restarting gpsd.

Use `sudo journalctl -k -b | tail -n 80` for USB resets and driver errors.
Test all sources for 30 minutes while parked, using the actual power setup.
The installer does not change USB autosuspend, lid/sleep policy or power
negotiation. Keep the laptop awake during collection. A reboot/power loss
cannot guarantee clean log closure or immediate restoration of interfaces.

ROLLBACK
Stop capture first: sudo wardriver stop
Remove /etc/systemd/system/wardriver.service, /usr/local/sbin/wardriver and
/etc/wardriver if they were newly created, or restore their previous copies
from the timestamped backup. Preserve /var/lib/wardriver/captures.
If GPS was configured, stop gpsd.service and gpsd.socket; restore the
previous /etc/default/gpsd and gpsd.socket.d/wardriver.conf, or remove the
new override if none existed. Run sudo systemctl daemon-reload and restore
GPS's earlier enabled/running state using the backup status notes.
Installed packages and kismet group membership are not automatically undone.
Do not blindly remove kismet membership if it predated this script.

REFERENCES
https://www.kali.org/tools/kismet/
https://pkg.kali.org/pkg/realtek-rtl8814au-dkms
https://pkg.kali.org/pkg/realtek-rtl88xxau-dkms
https://www.kismetwireless.net/docs/readme/datasources/wifi-linux/
https://www.kismetwireless.net/docs/readme/datasources/bluetooth-hci-bluetooth/
https://www.kismetwireless.net/docs/readme/gps/gps_gpsd/
https://www.kismetwireless.net/docs/readme/configuring/configfiles/
https://www.kismetwireless.net/docs/readme/logging/wiglecsv/
