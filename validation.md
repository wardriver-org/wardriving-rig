# Hardware validation

Status: **not yet run on the Dell**. Record actual results here after testing.

| Check | Pass condition | Result |
| --- | --- | --- |
| Identity | First ALFA label, hub model, power cable rating recorded | Pending |
| USB | All five devices enumerate consistently | Pending |
| Wi-Fi | Each PHY supports monitor mode and its assigned channels tune | Pending |
| 6 GHz | AXML captures on an available 6 GHz channel | Pending |
| Bluetooth | External HCI opens and discovers a test device | Pending |
| GPS | Outdoor fix in cgps and position appears in Kismet | Pending |
| Full load | 30-minute test with all sources, no repeated disconnects | Pending |
| Power | Battery does not trend downward under sustained load | Pending |
| Vehicle | Repeat using actual car supply while parked | Pending |

Run `sudo dmesg -w` during testing. USB resets can indicate power, cable, hub, driver, firmware, or thermal problems; they are not proof of a power fault by themselves. Test one device directly, then add devices incrementally.

`bash inspect-rig.sh` includes battery/AC status when exposed by the kernel. Battery current/power readings describe battery activity; they do **not** reliably report the negotiated USB-PD contract. Check BIOS adapter information if available, or use a suitable USB-C PD meter for the contract.

Record Kali version, kernel, Kismet version, per-radio driver, successful channels, power source, and test duration. Keep serials, MAC addresses, routes, and raw reports private unless deliberately redacted.
