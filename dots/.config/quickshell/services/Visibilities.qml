pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import qs.services

// Visibilities — global open/close state for every panel + OSD.
//
// IPC:
//   qs ipc call settings toggle
//   qs ipc call launcher toggle
//   qs ipc call osd show <type> <value>   — type: volume|brightness|muted
//
Singleton {
    id: root

    // ── Settings ─────────────────────────────────────────────────────────
    property bool settingsOpen: false

    function toggleSettings(): void {
        root.settingsOpen = !root.settingsOpen
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { root.toggleSettings() }
        function open(): void   { root.settingsOpen = true }
        function close(): void  { root.settingsOpen = false }
    }

    // ── Launcher ──────────────────────────────────────────────────────────
    property bool launcherOpen: false

    function toggleLauncher(): void {
        root.launcherOpen = !root.launcherOpen
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleLauncher() }
        function open(): void   { root.launcherOpen = true }
        function close(): void  { root.launcherOpen = false }
    }

    // ── OSD ───────────────────────────────────────────────────────────────
    property bool   osdVisible: false
    property string osdType:    "volume"    // "volume" | "brightness" | "muted"
    property real   osdValue:   0.0         // 0.0 – 1.0
    property string osdLabel:   ""

    function showOsd(type: string, value: real): void {
        root.osdType    = type
        root.osdValue   = value
        root.osdLabel   = type === "muted" ? "Muted"
                        : type === "brightness" ? "Brightness"
                        : "Volume"
        root.osdVisible = true
        osdHideTimer.restart()
    }

    // Auto-hide after Config.osd.timeout ms (falls back to 2 s).
    Timer {
        id: osdHideTimer
        interval: Config.ready ? Config.osd.timeout : 2000
        onTriggered: root.osdVisible = false
    }

    IpcHandler {
        target: "osd"
        function show(type: string, value: string): void {
            root.showOsd(type, parseFloat(value))
        }
    }
}
