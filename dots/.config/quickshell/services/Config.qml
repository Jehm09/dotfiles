// Config - singleton that reads ~/.config/settings/config.json at runtime.
// All QML components consume values through this singleton.
// The file is watched for changes: editing config.json hot-reloads the shell.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Resolved path to the config file
    readonly property string configPath: Quickshell.env("HOME") + "/.config/settings/config.json"

    // Parsed config object - access as Config.theme.accent, Config.bar.height, etc.
    property var data: ({
        theme: {
            colorScheme: "dark",
            accent: "#cba6f7",
            font: "JetBrainsMono Nerd Font",
            fontSize: 13,
            borderRadius: 12,
            borderWidth: 2,
            opacity: 0.85
        },
        bar: {
            height: 36,
            position: "top",
            showClock: true,
            clockFormat: "HH:mm",
            showBattery: true,
            showTray: true,
            showWorkspaces: true,
            workspaceCount: 10
        },
        launcher: { width: 680, maxResults: 8 },
        wallpaper: { path: "~/Pictures/wallpaper.jpg" },
        monitor: { primary: "DP-1" }
    })

    // Convenience accessors
    readonly property var theme:    data.theme
    readonly property var bar:      data.bar
    readonly property var launcher: data.launcher
    readonly property var wallpaper: data.wallpaper
    readonly property var monitor:  data.monitor

    // Watch the config file and reload when it changes
    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        onTextChanged: root._parse(text)
    }

    function _parse(text) {
        try {
            const parsed = JSON.parse(text)
            // Deep merge: keep defaults for any missing keys
            root.data = Object.assign({}, root.data, parsed)
        } catch (e) {
            console.warn("Config: failed to parse", root.configPath, "-", e)
        }
    }

    Component.onCompleted: {
        if (configFile.text.length > 0) root._parse(configFile.text)
    }
}
