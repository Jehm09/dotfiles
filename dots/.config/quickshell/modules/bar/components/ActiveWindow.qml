// ActiveWindow - shows the focused window title, truncated if too long.

import QtQuick
import Quickshell.Hyprland
import "../../../components"
import "../../../services"

PillContainer {
    id: root

    readonly property string title: HyprlandInfo.focusedClient?.title ?? ""
    readonly property int    maxLen: 40

    visible:  title.length > 0
    paddingH: 12

    Text {
        anchors.centerIn: parent
        text:       root.title.length > root.maxLen
                  ? root.title.slice(0, root.maxLen) + "…"
                  : root.title
        color:      Colors.subtext0
        font.family: Config.theme.font
        font.pixelSize: Config.theme.fontSize
        elide:      Text.ElideRight
        maximumLineCount: 1
    }
}
