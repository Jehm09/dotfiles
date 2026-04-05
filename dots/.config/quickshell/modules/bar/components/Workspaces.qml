// Workspaces - shows workspace dots in the bar.
// Active workspace: filled accent dot. Occupied: outline dot. Empty: not shown.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../../components"
import "../../../services"

PillContainer {
    id: root

    implicitWidth: row.implicitWidth + paddingH * 2
    paddingH: 8

    Row {
        id:       row
        anchors.centerIn: parent
        spacing:  6

        Repeater {
            model: HyprlandInfo.workspaces

            delegate: Rectangle {
                required property HyprlandWorkspace modelData

                readonly property bool isActive:   modelData.id === HyprlandInfo.focusedWorkspace?.id
                readonly property bool isOccupied: modelData.windows > 0

                width:   isActive ? 20 : 8
                height:  8
                radius:  4
                color:   isActive   ? Colors.accent
                       : isOccupied ? Colors.subtext0
                       : Colors.surface1

                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation  { duration: 150 } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    Hyprland.dispatch("workspace " + modelData.id)
                }
            }
        }
    }
}
