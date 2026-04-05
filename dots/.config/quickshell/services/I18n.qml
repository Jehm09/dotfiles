// I18n - singleton for UI string translations.
// Reads ~/.config/settings/i18n/en.json (or the active locale file).
// Usage: I18n.t("launcher.placeholder")  or  I18n.t("session.logout")

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Active locale - change to "es" to load es.json etc.
    property string locale: "en"

    readonly property string i18nDir: Quickshell.env("HOME") + "/.config/settings/i18n/"
    readonly property string filePath: i18nDir + locale + ".json"

    // Raw translation strings object
    property var strings: ({})

    FileView {
        id: localeFile
        path: root.filePath
        watchChanges: true
        onTextChanged: root._parse(text)
    }

    // Resolve a dot-notation key like "launcher.tabs.apps"
    function t(key) {
        const parts = key.split(".")
        let node = root.strings
        for (const part of parts) {
            if (node === undefined || node === null) return key
            node = node[part]
        }
        return (typeof node === "string") ? node : key
    }

    function _parse(text) {
        try {
            root.strings = JSON.parse(text)
        } catch (e) {
            console.warn("I18n: failed to parse", root.filePath, "-", e)
        }
    }

    Component.onCompleted: {
        if (localeFile.text.length > 0) root._parse(localeFile.text)
    }
}
