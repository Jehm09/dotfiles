# Peripherals

Hardware that needs a change on the Linux side before its own configuration
software will talk to it: keyboards, mice, and anything else that is configured
over raw HID.

None of this is run by `setup`. It is per-machine, it depends on which devices
are actually plugged in, and it is a one-off — so it lives here as a recipe
rather than as a step in the installer. Read it when a new keyboard or mouse
will not talk to its configurator.

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

[via/70-via.rules](via/70-via.rules) is the rule as it runs on this machine:

```bash
sudo install -m 0644 docs/via/70-via.rules /etc/udev/rules.d/
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

The permission problem above is not specific to keyboards: anything configured
over raw HID hits it. The difference is that mouse tooling is usually packaged,
and packaged tools ship their own udev rules in `/usr/lib/udev/rules.d/` with
correct numbering, so there is normally nothing to do by hand.

| Hardware | Tool | Package |
|---|---|---|
| Logitech Unifying / Bolt | Solaar | `solaar` |
| Logitech, Roccat, SteelSeries, some Razer | Piper (libratbag) | `piper` |
| Razer | OpenRazer + Polychromatic | `openrazer-daemon`, `polychromatic` |

None of these are installed here yet. If one of them cannot see a device,
diagnose it the same way: find the vendor ID with `lsusb`, check whether the
tool's own rule file exists and how it is numbered, and add a `uaccess` rule
below 73 if it does not.

## Keeping this machine's rules

Rules written by hand live in `/etc/udev/rules.d/` and are outside this repo,
because which ones you need depends on what is plugged into that particular
machine. On a new install, re-read this page and recreate only the ones that
apply.
