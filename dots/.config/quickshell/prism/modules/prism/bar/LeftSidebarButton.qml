import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Static decorative icon at the start of the bar — no hover, no click.
// Shows Config.options.cheatsheet.superKey (Nerd Font glyph) when set,
// otherwise falls back to the distro icon SVG.
Item {
    id: root

    property real iconSize: 19.5
    property real padding: 5
    property bool useSuperKey: Config.options.cheatsheet.superKey !== ""

    implicitWidth: iconSize + padding * 2
    implicitHeight: iconSize + padding * 2

    // Nerd Font glyph (e.g. 󰖳) — shown when superKey is configured
    StyledText {
        anchors.centerIn: parent
        visible: root.useSuperKey
        text: Config.options.cheatsheet.superKey
        font.pixelSize: root.iconSize
        font.family: Appearance.font.family.mono
        color: Appearance.colors.colOnLayer0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Distro icon SVG — fallback when superKey is empty
    CustomIcon {
        anchors.centerIn: parent
        visible: !root.useSuperKey
        width: root.iconSize
        height: root.iconSize
        source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
        colorize: true
        color: Appearance.colors.colOnLayer0
    }

}
