# Kali and Kismet setup

These steps are a bring-up guide, not a report of successful hardware tests. Keep the laptop's normal network interface managed.

## Install from Kali

```bash
sudo apt update
sudo apt install -y kismet kismet-capture-linux-wifi kismet-capture-linux-bluetooth iw usbutils network-manager bluez gpsd gpsd-clients
```

Use Kali's package configuration for capture-helper privileges. Where the package creates a `kismet` group, add your login user to it and log out/in:

```bash
getent group kismet
sudo usermod -aG kismet "$USER"
```

Run Kismet as your normal user with the packaged privileged capture helpers. If access is denied, review the package's privilege setup rather than running the entire web server as root or manually changing random helper permissions.

## Identify the devices

```bash
bash inspect-rig.sh
```

Plug radios in one at a time to map interface names to physical devices. `wlan1`, `wlan2`, and `wlan3` are not reliable identities across systems. Record the USB IDs, driver, and PHY for each. Use `iw phy PHY_NAME info` to inspect that particular radio's supported modes and frequencies; verify `monitor` is present.

Confirm the first adapter model on its label. Do not install a Realtek DKMS package based only on our provisional model name. Driver choice depends on the actual chipset and installed Kali kernel; test existing drivers first.

## Bring up one Wi-Fi source

Replace `YOUR_USB_INTERFACE` with one confirmed USB radio interface:

```bash
sudo nmcli device set YOUR_USB_INTERFACE managed no
kismet -c YOUR_USB_INTERFACE
```

Open <http://localhost:2501> and set up the Kismet login when prompted. Let Kismet create the monitor interface. Inspect source status, tuning errors, and observed devices. Repeat for the other radios. To restore NetworkManager control after stopping Kismet:

```bash
sudo nmcli device set YOUR_USB_INTERFACE managed yes
```

## Split the bands

Start with Kismet's detected channel support, then select the intended band per source. Inspect `iw reg get` and each PHY's available frequencies; use the actual location's regulatory settings. Do not force disabled channels.

The example file provides a commented 2.4 GHz list, a deliberately limited 5 GHz starter list, and one 6 GHz fixed-channel test. The 5 GHz starter list is not full-band coverage. Build the final hopping lists from channels that actually tune on each source. Kismet uses `W6e` suffixes for 6 GHz channels; a bare channel number may refer to another band.

Edit the existing `/etc/kismet/kismet_site.conf` with `sudo vim`; merge the adapted settings and avoid duplicate source entries. Do not replace an existing configuration blindly.

## GPS through gpsd

Inspect `/dev/serial/by-id/` and correlate the GPS USB device with its serial port. Prefer its stable by-id path when available. First try `cgps -s`: the packaged service may already detect it.

If not, inspect the distro configuration and service before changing them:

```bash
systemctl cat gpsd.service gpsd.socket
sudo vim /etc/default/gpsd
```

For packages using `/etc/default/gpsd`, set `DEVICES` to the actual GPS path and `GPSD_OPTIONS="-n"`, retaining other required distro settings. Restart the service and check:

```bash
sudo systemctl restart gpsd.service
cgps -s
```

Do not run a second gpsd instance alongside an active service. Keep gpsd local; no remote listener is needed. Once `cgps` has a valid outdoor fix, add:

```ini
gps=gpsd:host=localhost,port=2947
```

A working serial port is not the same as a position fix. Confirm location and time in Kismet before recording a survey.

## Bluetooth

```bash
bluetoothctl list
ls -l /sys/class/bluetooth/
```

Unplug/replug the StarTech to distinguish it from the Dell's internal Bluetooth. Select the correct `hciN` and add, for example:

```ini
source=hci1:type=linuxbluetooth,name=startech
```

`hci1` is an example only. This performs Bluetooth/BLE discovery and reports advertised attributes; it is not a general packet sniffer. Confirm the source can open and detect nearby discoverable devices.

## Full rig test

Add all validated sources and launch `kismet`. Watch source status and `sudo dmesg -w`. Test at a desk first, then with the actual vehicle charger while parked. See [validation](validation.md).

Sources: [Kali packages](https://www.kali.org/tools/kismet/), [Wi-Fi](https://www.kismetwireless.net/readme/datasources/wifi-linux/), [Bluetooth HCI](https://www.kismetwireless.net/readme/datasources/bluetooth-hci-bluetooth/), [GPSD](https://www.kismetwireless.net/readme/gps/gps_gpsd/).
