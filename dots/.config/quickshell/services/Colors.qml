pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.services

// Colors — Material 3 palette driven by matugen + dark/light mode.
//
// Usage:
//   import qs.services
//   color: Colors.primary
//   color: Colors.surface
//   color: Colors.on(someBackgroundColor)
//
// To generate the colors.json run once after picking a wallpaper:
//   matugen image <path> --json hex > ~/.config/settings/colors.json
//
// Switching dark ↔ light is instant (both schemes are loaded in memory).
// Change Config.appearance.dark and every binding updates automatically.
//
Singleton {
    id: root

    // Path where matugen writes both schemes.
    // Lives next to config.json so all settings are in one place.
    readonly property string filePath: {
        const home = StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
            .toString().replace(/^file:\/\//, "")
        return home + "/.config/settings/colors.json"
    }

    // Mirrors Config.appearance.dark.
    // Changing this re-applies the matching scheme without re-running matugen.
    readonly property bool dark: Config.ready ? Config.appearance.dark : true
    onDarkChanged: _applyScheme()

    // -----------------------------------------------------------------------
    // M3 palette — Catppuccin Mocha dark as fallback until matugen runs.
    // All colors are replaced on load.
    // -----------------------------------------------------------------------
    property color primary:                 "#cba6f7"
    property color onPrimary:               "#1e0a4a"
    property color primaryContainer:        "#4b3272"
    property color onPrimaryContainer:      "#e9ddff"

    property color secondary:               "#cba6f7"
    property color onSecondary:             "#332941"
    property color secondaryContainer:      "#4a3f5c"
    property color onSecondaryContainer:    "#e8def8"

    property color tertiary:                "#f38ba8"
    property color onTertiary:              "#4a0e22"
    property color tertiaryContainer:       "#633038"
    property color onTertiaryContainer:     "#ffd9e3"

    property color error:                   "#f38ba8"
    property color onError:                 "#601410"
    property color errorContainer:          "#8c1d18"
    property color onErrorContainer:        "#ffdad6"

    property color background:              "#1e1e2e"
    property color onBackground:            "#cdd6f4"

    property color surface:                 "#1e1e2e"
    property color onSurface:               "#cdd6f4"
    property color surfaceVariant:          "#313244"
    property color onSurfaceVariant:        "#a6adc8"
    property color surfaceDim:              "#11111b"
    property color surfaceBright:           "#313244"
    property color surfaceContainerLowest:  "#11111b"
    property color surfaceContainerLow:     "#181825"
    property color surfaceContainer:        "#1e1e2e"
    property color surfaceContainerHigh:    "#313244"
    property color surfaceContainerHighest: "#45475a"

    property color outline:                 "#6c7086"
    property color outlineVariant:          "#45475a"

    property color inverseSurface:          "#cdd6f4"
    property color inverseOnSurface:        "#1e1e2e"
    property color inversePrimary:          "#6750a4"

    property color shadow:                  "#000000"
    property color scrim:                   "#000000"

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    // Returns a legible text color for any background color.
    // Picks a light tint for dark backgrounds and a dark tint for light ones.
    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, Math.min(c.hslSaturation * 0.3, 0.15), 0.93, 1)
        return Qt.hsla(c.hslHue, Math.min(c.hslSaturation * 0.3, 0.15), 0.07, 1)
    }

    // Applies transparency to a color based on surface depth (0 = base background).
    // Placeholder — transparency support will be wired to Config settings in a
    // future step. Currently returns the color unchanged.
    function layer(c: color, n: int): color {
        return c
    }

    // -----------------------------------------------------------------------
    // Internal: scheme loading
    // -----------------------------------------------------------------------

    // Both dark and light schemes are kept in memory after parsing so that
    // toggling dark mode costs zero I/O.
    property var _rawDark:  ({})
    property var _rawLight: ({})

    // matugen snake_case token → our camelCase property name
    readonly property var _tokenMap: ({
        "primary":                   "primary",
        "on_primary":                "onPrimary",
        "primary_container":         "primaryContainer",
        "on_primary_container":      "onPrimaryContainer",
        "secondary":                 "secondary",
        "on_secondary":              "onSecondary",
        "secondary_container":       "secondaryContainer",
        "on_secondary_container":    "onSecondaryContainer",
        "tertiary":                  "tertiary",
        "on_tertiary":               "onTertiary",
        "tertiary_container":        "tertiaryContainer",
        "on_tertiary_container":     "onTertiaryContainer",
        "error":                     "error",
        "on_error":                  "onError",
        "error_container":           "errorContainer",
        "on_error_container":        "onErrorContainer",
        "background":                "background",
        "on_background":             "onBackground",
        "surface":                   "surface",
        "on_surface":                "onSurface",
        "surface_variant":           "surfaceVariant",
        "on_surface_variant":        "onSurfaceVariant",
        "surface_dim":               "surfaceDim",
        "surface_bright":            "surfaceBright",
        "surface_container_lowest":  "surfaceContainerLowest",
        "surface_container_low":     "surfaceContainerLow",
        "surface_container":         "surfaceContainer",
        "surface_container_high":    "surfaceContainerHigh",
        "surface_container_highest": "surfaceContainerHighest",
        "outline":                   "outline",
        "outline_variant":           "outlineVariant",
        "inverse_surface":           "inverseSurface",
        "inverse_on_surface":        "inverseOnSurface",
        "inverse_primary":           "inversePrimary",
        "shadow":                    "shadow",
        "scrim":                     "scrim",
    })

    function _applyScheme() {
        const scheme = root.dark ? root._rawDark : root._rawLight
        if (!scheme || Object.keys(scheme).length === 0) return
        for (const [snake, camel] of Object.entries(root._tokenMap)) {
            if (scheme[snake] !== undefined)
                root[camel] = scheme[snake]
        }
    }

    function _parseAndLoad(text) {
        try {
            const json = JSON.parse(text)
            // Handle matugen's nested format: { "colors": { "dark": {...}, "light": {...} } }
            // Also accept a flat format:                { "dark": {...}, "light": {...} }
            const schemes = json.colors ?? json
            root._rawDark  = schemes.dark  ?? {}
            root._rawLight = schemes.light ?? {}
            root._applyScheme()
        } catch (e) {
            console.warn("[Colors] Failed to parse color scheme:", e.toString())
        }
    }

    FileView {
        id: colorsFile
        path: root.filePath
        watchChanges: true
        onLoaded:      root._parseAndLoad(colorsFile.text())
        onFileChanged: reload()
        onLoadFailed: {
            // File doesn't exist yet (matugen hasn't run). Fallback palette stays.
            console.info("[Colors] No colors.json found — using Catppuccin Mocha fallback.")
        }
    }
}
