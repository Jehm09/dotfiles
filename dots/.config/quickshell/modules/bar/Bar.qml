// Bar - top bar for a single monitor.
// Layout: [OsIcon][Workspaces]  [Clock]  [ActiveWindow][StatusIcons]

import QtQuick
import Quickshell
import "./components"
import "../../services"

PanelWindow {
    id: root

    property bool controlCenterOpen: false
    property bool launcherOpen:      false

    // Signals forwarded to ShellRoot to coordinate overlays
    signal controlCenterToggled()
    signal launcherToggled()

    anchors {
        top:   true
        left:  true
        right: true
    }
    height: Config.bar.height
    color:  "transparent"
    exclusiveZone: height

    Item {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }

        // --- Left section ---
        Row {
            id: leftSection
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            spacing: 6

            OsIcon {
                anchors.verticalCenter: parent.verticalCenter
                onLauncherToggled: root.launcherToggled()
            }

            Workspaces {
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.bar.showWorkspaces
            }
        }

        // --- Center: clock ---
        Clock {
            anchors.centerIn: parent
            visible: Config.bar.showClock
        }

        // --- Right section ---
        Row {
            id: rightSection
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6

            ActiveWindow {
                anchors.verticalCenter: parent.verticalCenter
            }

            StatusIcons {
                anchors.verticalCenter: parent.verticalCenter
                onControlCenterToggled: root.controlCenterToggled()
            }
        }
    }
}
