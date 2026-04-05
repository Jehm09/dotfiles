pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// I18n — loads translation strings from i18n/<lang>.json.
//
// Usage:
//   import qs.services
//   text: I18n.s("bar.clock")
//
// Translations live in dots/.config/quickshell/i18n/<lang>.json.
// Only "en" is shipped; the file is resolved relative to shell.qml at startup.
//
Singleton {
    id: root

    // Flat key→string map built from the JSON tree.
    property var _strings: ({})

    // Returns the translation for a dotted key, e.g. "settings.appearance.darkMode".
    // Falls back to the key itself if not found.
    function s(key: string): string {
        return root._strings[key] ?? key
    }

    // Resolve path relative to the QML component file location.
    readonly property string _filePath: Qt.resolvedUrl("../i18n/en.json")
        .toString().replace(/^file:\/\//, "")

    function _flatten(obj, prefix) {
        for (const [k, v] of Object.entries(obj)) {
            const full = prefix ? prefix + "." + k : k
            if (typeof v === "object" && v !== null)
                _flatten(v, full)
            else
                root._strings[full] = v
        }
    }

    FileView {
        id: langFile
        path: root._filePath
        onLoaded: {
            try {
                const flat = {}
                root._strings = flat
                root._flatten(JSON.parse(langFile.text()), "")
            } catch (e) {
                console.warn("[I18n] Failed to parse translation file:", e.toString())
            }
        }
        onLoadFailed: console.warn("[I18n] Translation file not found:", root._filePath)
    }
}
