pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// Config — persistent user settings backed by ~/.config/settings/config.json
//
// Usage:
//   import qs.services
//   Config.appearance.dark          // read
//   Config.appearance.dark = false  // write (auto-saved with debounce)
//
Singleton {
    id: root

    // Path to the user settings file (kept separate from the shell so it survives
    // shell updates without losing preferences).
    readonly property string filePath: {
        const home = StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
            .toString().replace(/^file:\/\//, "")
        return home + "/.config/settings/config.json"
    }

    // Shorthand aliases — access as Config.appearance, Config.bar, etc.
    property alias appearance : cfg.appearance
    property alias profile     : cfg.profile
    property alias bar         : cfg.bar
    property alias launcher    : cfg.launcher
    property alias osd         : cfg.osd

    // True once the config file has been loaded at least once.
    property bool ready: false

    // Guards against reload loops: we set this when WE write the file so the
    // onFileChanged signal is ignored for that one cycle.
    property bool _saving: false

    // Debounce: wait 300 ms after the last external file change before reloading.
    Timer {
        id: reloadTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root._saving) view.reload()
            root._saving = false
        }
    }

    // Debounce: wait 300 ms after the last property change before writing.
    Timer {
        id: writeTimer
        interval: 300
        repeat: false
        onTriggered: {
            root._saving = true
            view.writeAdapter()
        }
    }

    FileView {
        id: view
        path: root.filePath
        watchChanges: true
        onFileChanged:    reloadTimer.restart()
        onAdapterUpdated: writeTimer.restart()
        onLoaded:         root.ready = true
        onLoadFailed: error => {
            // File doesn't exist yet — write defaults so it gets created.
            if (error === FileViewError.FileNotFound) writeAdapter()
        }

        JsonAdapter {
            id: cfg

            // ---------------------------------------------------------------
            // Appearance
            // ---------------------------------------------------------------
            property JsonObject appearance: JsonObject {
                // Dark mode. Switching this live updates the entire color palette.
                property bool   dark     : true
                // Absolute path to the current wallpaper.
                // Updated by the Wallpaper service when the user picks a new one.
                property string wallpaper: ""
            }

            // ---------------------------------------------------------------
            // Profile
            // ---------------------------------------------------------------
            property JsonObject profile: JsonObject {
                // Path to the user avatar image shown in the control center.
                property string picture: ""
            }

            // ---------------------------------------------------------------
            // Bar
            // ---------------------------------------------------------------
            property JsonObject bar: JsonObject {
                property int height: 36

                property JsonObject workspaces: JsonObject {
                    property int  count: 10
                    property bool show : true
                }

                property JsonObject clock: JsonObject {
                    property bool   show  : true
                    // Qt time format string — https://doc.qt.io/qt-6/qtime.html#toString
                    property string format: "HH:mm"
                }

                property JsonObject systray: JsonObject {
                    property bool show: true
                }

                property JsonObject battery: JsonObject {
                    property bool show: true
                }
            }

            // ---------------------------------------------------------------
            // Launcher
            // ---------------------------------------------------------------
            property JsonObject launcher: JsonObject {
                property int width: 680
            }

            // ---------------------------------------------------------------
            // OSD (on-screen display — volume / brightness)
            // ---------------------------------------------------------------
            property JsonObject osd: JsonObject {
                // How long (ms) the OSD stays visible after the last change.
                property int timeout: 2000
            }
        }
    }
}
