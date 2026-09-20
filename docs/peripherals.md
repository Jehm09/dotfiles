# Peripherals

Hardware that needs something done on the Linux side before it behaves:
keyboards whose configurator cannot reach them, mice whose scroll wheel breaks
after a kernel update, controllers that steer the cursor when they should not.

Most of this is not run by `setup`: it is per-machine, it depends on what is
actually plugged in, and it is a one-off, so it lives here as a recipe rather
than as a step in the installer. The one exception is the Logitech scroll wheel
fix below, which `setup post` does install — it is documented here anyway,
because the day you change mouse it is the thing to undo.

## Configurable keyboards (QMK, VIA, Vial)

A programmable keyboard is configured by writing to `/dev/hidraw*`, a character
device that is owned by root and unreadable by your user by default. Every
configurator — the VIA web app, Vial, ZSA's Keymapp, `qmk` itself — hits the
same wall, and none of them report it clearly. VIA in particular says the
keyboard *"does not appear to respond as a VIA compatible keyboard"*, which
sounds like a firmware problem and is not.

### The rule, and the trap in its filename

The fix is a udev rule that tags the device with `uaccess`, which makes systemd
grant an ACL to whoever is logged in at the seat:

```
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="19f5", TAG+="uaccess"
```

**The filename has to sort before `73-seat-late.rules`.** That is the rule in
`/usr/lib/udev/rules.d/` that actually processes the `uaccess` tag, and udev
reads rule files in lexical order, so a tag applied afterwards is simply never
seen. A rule in `92-via.rules` parses without error, matches the device, and
does nothing at all. Every system rule that uses `uaccess` is numbered 70 or
below; ours is `70-via.rules` for the same reason.

Granting a group instead (`MODE="0660", GROUP="users"`) is the other common
advice and it works, but only if you are actually in that group — `users` is
not a group Arch puts you in.

### Installing it

[udev/70-via.rules](udev/70-via.rules) is the rule as it runs on this machine:

```bash
sudo install -m 0644 docs/udev/70-via.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

Then **unplug and replug the keyboard**. Rules are applied when a device
enumerates; reloading them does not retroactively fix a device that is already
connected.

This is a one-off per machine, not something to re-run — the file stays in
`/etc` across reboots and upgrades. `setup` does not install it, so on a fresh
machine this is the step to remember.

The file carries one line per vendor, currently NuPhy (`19f5`), MonsGeek
(`3151`) and YUNZII (`056d`). To cover another keyboard, add a line with its
vendor ID — the first half of the `ID` field in `lsusb`:

```
Bus 008 Device 008: ID 19f5:3315 NuPhy NuPhy Halo65 V2
                       ^^^^
```

Keep the file in the repo in sync with what is deployed, or the next machine
will be missing a keyboard.

Matching every `hidraw*` device regardless of vendor also works and is what most
guides suggest, but it lets anything running as your user read raw input from
every HID device on the machine, which is a keylogger in all but name. Listing
vendors is a few seconds of work.

### Checking it worked

[via/via-probe.py](via/via-probe.py) asks the keyboard for its VIA protocol
version over raw HID. It is read-only, and it separates the two failures that
look identical from inside the VIA app:

```console
$ python3 docs/via/via-probe.py
/dev/hidraw21  [NuPhy NuPhy Halo65 V2]
  0x01 protocol version             12  (v3 definition)
  0x11 dynamic keymap layer count   8
```

| What it prints | What it means |
|---|---|
| A protocol version | Permissions and firmware are both fine. The problem is the definition file or the browser. |
| `no permission` | The rule is missing, misnumbered, or the device was not replugged. |
| `no response (1s timeout)` | Permissions are fine; this firmware does not speak VIA. |
| `No VIA raw HID interface` | Nothing suitable is connected — see the note on dongles below. |

### Wireless dongles usually do not work

A 2.4 GHz dongle is a separate USB device with its own product ID and its own
HID descriptors, and vendors rarely put the VIA interface on it. The probe
looks for usage page `0xFF60` / usage `0x61`, which is the raw HID interface QMK
defines for VIA; if the dongle does not expose it, no amount of permission
fixing will help. **Configure by cable, then go back to wireless** — remaps are
stored in the keyboard's own EEPROM, so they survive the switch, and they apply
on any machine you plug it into afterwards.

### The VIA client

VIA talks to the keyboard through **WebHID**, which only exists in
Chromium-based browsers. Firefox does not implement it and never shows the
device. Use <https://usevia.app> in Chrome, Chromium, Brave or Edge, or install
`via-bin` from the AUR — that package is an Electron wrapper around the same
web app, so it behaves identically.

After fixing permissions, reload the page with Ctrl+Shift+R and authorize the
device again. Chrome caches the handle of a device that failed to open, and will
keep reporting the same error against a keyboard that now works.

### Keyboard definitions

VIA only recognises a keyboard it has a definition for. The official set lives
in [the-via/keyboards](https://github.com/the-via/keyboards) and is far from
complete — NuPhy, for one, is absent entirely. For anything not in it:

1. In usevia.app, open **SETTINGS** and turn on **Show Design Tab**.
2. In **DESIGN**, load the JSON.
3. Back in **CONFIGURE**, click **Authorize Device**.

The definition format has to match what the firmware reports as its protocol
version — the first number the probe prints:

| Protocol | Format | Notable difference |
|---|---|---|
| 9 | v2 | Requires a `lighting` key. |
| 12 | v3 | Rejects `lighting`; optional `menus` and `keycodes` instead. |

Loading the wrong one fails validation with a message that does not mention the
version, so check the protocol first.

If a definition does not exist anywhere, one can be generated from the board's
QMK `keyboard.json`: its `layouts.LAYOUT` array carries the matrix coordinates
and key sizes, which is everything a VIA definition needs. Verify the result by
reading the keymap back off the keyboard (VIA command `0x04`) and checking the
legends land in a sane layout before trusting it.

### NuPhy Halo65 V2

Verified on this machine. Definition: [via/nuphy-halo65-v2.json](via/nuphy-halo65-v2.json).

| | |
|---|---|
| Vendor ID | `19f5` |
| Wired | `19f5:3315` — exposes `0xFF60`, works |
| 2.4 GHz dongle | `19f5:3247` — no `0xFF60`, only NuPhy's own `0xFF31` protocol; VIA cannot use it |
| Protocol | 12, so the definition must be v3 |
| Layers | 8 |

The shipped definition is minimal: it remaps keys, layers and macros, but
declares no lighting, so RGB stays on the keyboard's own Fn shortcuts. To try
RGB control from VIA, add these two keys to the JSON — the board does have
`rgb_matrix` in its QMK config, but whether NuPhy's stock firmware implements
the custom channel is untested:

```json
"menus": ["qmk_rgb_matrix"],
"keycodes": ["qmk_lighting"]
```

NuPhy publishes its own definitions at
<https://nuphy.com/pages/json-files-for-nuphy-keyboards>. Prefer theirs if the
Halo65 V2 appears there — it should carry proper legends and a working lighting
menu.

## Mice and other HID devices

### Logitech: the scroll wheel goes analog after a kernel update

**Symptom.** The mouse is re-detected as a brand new input device — desktop
pointer settings reset, acceleration switched back on — and the wheel stops
stepping per detent. It scrolls 1:1 with wheel movement, dropping steps or
firing two at once. Plugging the mouse in by cable makes it behave; going back
to the dongle brings it straight back. Uninstalling Solaar changes nothing,
which is the detail that sends people down the wrong path.

**Cause.** `hid_logitech_hidpp`, the driver for Logitech's HID++ protocol, and
the high-resolution scrolling it enables. Seen after the 6.19 kernel, and the
same fix has been circulating since at least 6.7.

**Fix.** Blacklist the module so the kernel falls back to generic HID. The file
is [packages/modprobe/blacklist-hid-logitech-hidpp.conf](../packages/modprobe/blacklist-hid-logitech-hidpp.conf)
and `setup post` step 9 (`hwfix`) installs it and rebuilds the initramfs. By
hand:

```bash
sudo install -Dm644 packages/modprobe/blacklist-hid-logitech-hidpp.conf \
  /etc/modprobe.d/blacklist-hid-logitech-hidpp.conf
sudo mkinitcpio -P
```

The initramfs rebuild is not optional — without it the module can still be
loaded early and the blacklist appears to do nothing. Reboot afterwards.

On the next boot the pointer settings reset one more time and the device is
renamed to something generic like `Logitech Wireless Mouse PID:4099`. That name
is how you confirm the blacklist took: with HID++ gone, the kernel no longer
knows the model, only the protocol ID.

**What it costs.** Everything HID++ provides: battery level, Solaar, on-the-fly
DPI, gestures, and high-resolution scrolling itself. For a mouse whose settings
live in onboard memory that is no loss; for one you configure from Linux, it is.

Leave `hid_logitech_dj` alone — that one multiplexes the Unifying and
Lightspeed receivers, and the mouse needs it. A few people report having to
blacklist it as well when `hidpp` alone was not enough, but it changes how the
receiver presents its devices, so treat it as a last resort.

**Undoing it**, which is the point of writing this down — if the mouse changes,
or a later kernel fixes the regression:

```bash
sudo rm /etc/modprobe.d/blacklist-hid-logitech-hidpp.conf
sudo mkinitcpio -P
```

Then reboot and check `lsmod | grep hidpp`. If the wheel steps correctly with
the module loaded, the workaround is no longer needed — and it should be
dropped, because it is costing battery reporting for nothing. Remove the step
from `setup post` too, or the next machine inherits it.

**A different problem that looks similar.** Searching for this also turns up
kernel 6.7 reports of `HID++ device connected` repeating in `dmesg` with a
sluggish pointer. That is receiver flakiness, not scrolling; it was resolved by
moving the dongle to another USB port, and blacklisting is the wrong tool for
it. Sources:
[CachyOS, 6.19, scroll wheel](https://discuss.cachyos.org/t/logitech-mouse-scrollwheel-issues-after-recent-linux-6-19-update/23110)
(this is the one that applies) and
[EndeavourOS, 6.7, reconnect spam](https://forum.endeavouros.com/t/logitech-mouse-hid-issues-with-the-6-7-kernel/50249).

### Configuration tools

The permission problem from the keyboard section is not specific to keyboards:
anything configured over raw HID hits it. The difference is that mouse tooling
is usually packaged, and packaged tools ship their own udev rules in
`/usr/lib/udev/rules.d/` with correct numbering, so there is normally nothing
to do by hand.

| Hardware | Tool | Package |
|---|---|---|
| Logitech Unifying / Bolt | Solaar | `solaar` |
| Logitech, Roccat, SteelSeries, some Razer | Piper (libratbag) | `piper` |
| Razer | OpenRazer + Polychromatic | `openrazer-daemon`, `polychromatic` |

None of these are installed here yet. If one of them cannot see a device,
diagnose it the same way: find the vendor ID with `lsusb`, check whether the
tool's own rule file exists and how it is numbered, and add a `uaccess` rule
below 73 if it does not.

## Game controllers

### DualSense: the touchpad drags the desktop cursor

**Symptom.** With a PS5 controller connected, the desktop pointer jumps
whenever a thumb brushes the pad. It is not the controller misbehaving: the
kernel exposes the touchpad as its own input device, and libinput binds it as a
pointer like any trackpad.

**Fix.** Tell libinput to skip that one device —
[udev/71-dualsense-ignore-mouse.rules](udev/71-dualsense-ignore-mouse.rules):

```bash
sudo install -m 0644 docs/udev/71-dualsense-ignore-mouse.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

Then reconnect the controller. Nothing else changes: the rule only sets a
property that libinput reads, so the kernel driver stays bound, the gamepad
keeps working, and anything reading `/dev/input/event*` or hidraw directly —
Steam, SDL — never notices.

**Both lines are needed.** The device is named differently depending on how it
is connected: over USB it is `Sony Interactive Entertainment DualSense Wireless
Controller Touchpad`, over Bluetooth just `DualSense Wireless Controller
Touchpad`. A rule with only one of them works on one transport and silently
does nothing on the other.

Unlike the VIA rule, the filename number carries no meaning here — the property
is consumed by libinput after udev has finished, not by another rule. `71-` is
only a convention.

To check the name on a controller that is not matching, connect it and run:

```bash
grep -i . /sys/class/input/input*/name | grep -i dualsense
```

The same `LIBINPUT_IGNORE_DEVICE="1"` trick applies to anything else that
should not be steering the cursor — other controllers' touchpads, IR receivers,
the HID interface some monitors expose.

## Keeping this machine's rules

Hand-written udev rules are kept in [udev/](udev/) and installed to
`/etc/udev/rules.d/` by hand — `setup` does not touch them, because which ones
a machine needs depends on what is plugged into it.

| File | For |
|---|---|
| [udev/70-via.rules](udev/70-via.rules) | hidraw access for QMK/VIA keyboards |
| [udev/71-dualsense-ignore-mouse.rules](udev/71-dualsense-ignore-mouse.rules) | stops the DualSense touchpad acting as a pointer |

On a new install, read this page and install only the ones that apply to the
hardware actually on that desk. When you add or change a rule on a machine,
copy it back here — `/etc` is not backed up anywhere, and a rule that exists
only there is lost with the install.
