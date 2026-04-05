// Colors - singleton exposing the shell color palette.
// All colors reference Config.theme so changing the accent in config.json
// propagates everywhere without touching individual components.

pragma Singleton

import QtQuick
import "."

QtObject {
    id: root

    // Base dark palette (Catppuccin Mocha-inspired)
    readonly property color base:           "#1e1e2e"
    readonly property color mantle:         "#181825"
    readonly property color crust:          "#11111b"
    readonly property color surface0:       "#313244"
    readonly property color surface1:       "#45475a"
    readonly property color surface2:       "#585b70"
    readonly property color overlay0:       "#6c7086"
    readonly property color overlay1:       "#7f849c"
    readonly property color text:           "#cdd6f4"
    readonly property color subtext0:       "#a6adc8"
    readonly property color subtext1:       "#bac2de"

    // Accent from config (default: mauve)
    readonly property color accent:         Config.theme.accent
    readonly property color accentDim:      Qt.darker(accent, 1.4)
    readonly property color accentSubtle:   Qt.rgba(
        Qt.color(accent).r,
        Qt.color(accent).g,
        Qt.color(accent).b,
        0.2
    )

    // Semantic colors
    readonly property color error:          "#f38ba8"
    readonly property color success:        "#a6e3a1"
    readonly property color warning:        "#f9e2af"
    readonly property color info:           "#89b4fa"

    // Surface with alpha for overlays and panels
    readonly property color panel:          Qt.rgba(Qt.color(base).r,    Qt.color(base).g,    Qt.color(base).b,    Config.theme.opacity)
    readonly property color panelVariant:   Qt.rgba(Qt.color(surface0).r, Qt.color(surface0).g, Qt.color(surface0).b, Config.theme.opacity)

    // Scrim behind overlays (launcher, session menu)
    readonly property color scrim:          Qt.rgba(0, 0, 0, 0.6)
}
