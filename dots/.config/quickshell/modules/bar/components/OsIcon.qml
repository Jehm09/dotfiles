// OsIcon - Arch Linux logo in the bar. Click to toggle the launcher.

import QtQuick
import "../../../components"
import "../../../services"

PillContainer {
    id: root

    signal launcherToggled()

    paddingH: 10
    implicitWidth: 36

    Text {
        anchors.centerIn: parent
        text:           ""                // Arch Linux nerd font icon
        font.family:    "JetBrainsMono Nerd Font"
        font.pixelSize: 16
        color:          hoverArea.containsMouse ? Colors.accent : Colors.subtext0
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    scale: hoverArea.pressed ? 0.88 : 1.0
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutBack } }

    MouseArea {
        id:           hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    root.launcherToggled()
    }
}
