pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    function reapplyTheme() {
        // Re-apply already-loaded content directly — reload() alone doesn't re-trigger
        // onLoadedChanged when the file on disk hasn't changed (e.g. slider move).
        try {
            const content = themeFileView.text()
            if (content && content.length > 2) {
                root.applyColors(content)
                return
            }
        } catch(e) {}
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        const json = JSON.parse(fileContent)
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                Appearance.m3colors[m3Key] = json[key]
            }
        }

        Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)

        // Darken all surface colors in dark mode.
        // Affects every quickshell component regardless of whether it reads m3colors.* directly
        // or via the derived Appearance.colors.col* properties.
        if (Appearance.m3colors.darkmode) {
            const factor = 1.0 + (Config?.options.appearance.darkModeSurfaces ?? 0) * 0.5
            if (factor > 1.001) {
                const surfaces = [
                    'm3background', 'm3surface', 'm3surfaceDim', 'm3surfaceBright',
                    'm3surfaceContainerLowest', 'm3surfaceContainerLow',
                    'm3surfaceContainer', 'm3surfaceContainerHigh', 'm3surfaceContainerHighest'
                ]
                for (const key of surfaces) {
                    Appearance.m3colors[key] = Qt.darker(Appearance.m3colors[key], factor)
                }
            }
        }
    }

    // Re-apply when the user adjusts the dark surfaces slider in Settings
    Connections {
        target: Config.options.appearance
        function onDarkModeSurfacesChanged() { root.reapplyTheme() }
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }

    function toggleLightDark() {
        const currentlyDark = Appearance.m3colors.darkmode;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", currentlyDark ? "light" : "dark", "--noswitch"]);
    }

    GlobalShortcut {
        name: "toggleLightDark"
        description: "Toggles between dark theme and light theme"

        onPressed: {
            root.toggleLightDark();
        }
    }

    IpcHandler {
        target: "theme"

        function toggleLightDark(): void {
            root.toggleLightDark();
        }
    }
}
