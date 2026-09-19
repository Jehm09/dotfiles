#!/usr/bin/env python3
"""Ask a QMK/VIA keyboard for its protocol version over raw HID.

Read-only. Tells apart the two failures that look identical in the VIA app:
no permission on the hidraw node, versus firmware that does not speak VIA.
"""
import glob
import os
import select
import sys

# Usage Page (0xFF60), Usage (0x61) — la interfaz raw HID que define QMK para VIA
VIA_USAGE = b"\x06\x60\xff\x09\x61"
REPORT_SIZE = 32

COMMANDS = {
    0x01: "protocol version",
    0x11: "dynamic keymap layer count",
}


def find_via_interfaces():
    found = []
    for device in glob.glob("/sys/bus/hid/devices/*"):
        try:
            with open(os.path.join(device, "report_descriptor"), "rb") as handle:
                descriptor = handle.read()
        except OSError:
            continue
        if VIA_USAGE not in descriptor:
            continue
        name = ""
        with open(os.path.join(device, "uevent")) as handle:
            for line in handle:
                if line.startswith("HID_NAME="):
                    name = line.strip().split("=", 1)[1]
        for node in os.listdir(os.path.join(device, "hidraw")):
            found.append(("/dev/" + node, name))
    return found


def query(fd, command):
    # hidraw espera un byte de report ID al frente; VIA no usa report IDs, va 0x00
    os.write(fd, bytes([0x00, command]) + b"\x00" * (REPORT_SIZE - 1))
    if not select.select([fd], [], [], 1.0)[0]:
        return None
    return os.read(fd, REPORT_SIZE)


def probe(node):
    try:
        fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
    except PermissionError:
        print(f"  no permission on {node}")
        print("  -> the udev rule is missing, misnumbered, or the device was not replugged")
        return False
    except OSError as error:
        print(f"  cannot open {node}: {error}")
        return False

    ok = True
    try:
        for command, label in COMMANDS.items():
            response = query(fd, command)
            if response is None:
                print(f"  0x{command:02X} {label:<28} no response (1s timeout)")
                ok = False
                continue
            if response[0] != command:
                print(f"  0x{command:02X} {label:<28} unexpected reply {response[:4].hex(' ')}")
                ok = False
                continue
            if command == 0x01:
                version = int.from_bytes(response[1:3], "big")
                kind = {9: "v2 definition", 12: "v3 definition"}.get(version, "unknown")
                print(f"  0x{command:02X} {label:<28} {version}  ({kind})")
            else:
                print(f"  0x{command:02X} {label:<28} {response[1]}")
    finally:
        os.close(fd)
    return ok


interfaces = find_via_interfaces()
if not interfaces:
    sys.exit(
        "No VIA raw HID interface (usage page 0xFF60) is connected.\n"
        "Wireless dongles usually do not expose one: connect the keyboard by cable."
    )

healthy = True
for node, name in interfaces:
    print(f"{node}  [{name}]")
    healthy &= probe(node)
sys.exit(0 if healthy else 1)
