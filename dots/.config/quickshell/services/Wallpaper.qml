pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.services

// Wallpaper — applies wallpapers and drives the color pipeline.
//
// Setting a wallpaper triggers two things in parallel:
//   1. swww applies the image with a fade transition.
//   2. matugen generates ~/.config/settings/colors.json from the image.
//      Colors.qml detects the file change via watchChanges and reloads automatically.
//
// IPC:
//   qs ipc call wallpaper set <path>   — set a new wallpaper
//   qs ipc call wallpaper get          — print the current wallpaper path
//
Singleton {
    id: root

    // Current wallpaper — read from Config so it survives restarts.
    // Empty string means no wallpaper has been set yet.
    readonly property string current: Config.ready ? Config.appearance.wallpaper : ""

    // Destination for the matugen JSON output.
    // Must match Colors.filePath.
    readonly property string _colorsPath: {
        const home = StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
            .toString().replace(/^file:\/\//, "")
        return home + "/.config/settings/colors.json"
    }

    // Set a new wallpaper.
    // Persists to config, applies visually, and regenerates the color palette.
    function set(path: string): void {
        if (!path || path === root.current) return
        Config.appearance.wallpaper = path   // saved to config.json by Config's debounce
        _apply(path)
    }

    // Internal: run swww + matugen for a given path.
    function _apply(path: string): void {
        if (!path || path.length === 0) return

        // 1. Apply wallpaper with a smooth fade transition.
        Quickshell.execDetached([
            "swww", "img", path,
            "--transition-type", "fade",
            "--transition-duration", "1",
        ])

        // 2. Regenerate M3 palette. Colors.qml reloads automatically.
        matugenProc.running = false
        matugenProc.command = [
            "bash", "-c",
            `matugen image "${path}" --json hex > "${root._colorsPath}"`,
        ]
        matugenProc.running = true
    }

    // Apply the saved wallpaper on startup once the config has loaded.
    onCurrentChanged: {
        if (Config.ready && root.current.length > 0)
            _apply(root.current)
    }

    // matugen process — one-shot, restarted each time a wallpaper is set.
    Process {
        id: matugenProc
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("[Wallpaper] matugen exited with code", code,
                    "— is matugen-bin installed?")
        }
    }

    // IPC handler — allows setting wallpapers from keybinds or scripts.
    IpcHandler {
        target: "wallpaper"

        function set(path: string): void {
            root.set(path)
        }

        function get(): string {
            return root.current
        }
    }
}
