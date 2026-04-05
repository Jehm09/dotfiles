pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs.services

// BarWindow — top horizontal bar, one per screen.
//
// Reactive to Config: height, show flags, clock format,
// workspace count. All change without a shell restart.
//
PanelWindow {
    id: root

    required property ShellScreen screen

    anchors.top:   true
    anchors.left:  true
    anchors.right: true

    implicitHeight: Config.ready ? Config.bar.height : 36
    exclusiveZone:  implicitHeight

    WlrLayershell.namespace: "qs-bar"
    WlrLayershell.layer:     WlrLayer.Top

    color: "transparent"

    // -----------------------------------------------------------------------
    // Bar background
    // -----------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Colors.surfaceContainer
        opacity: 0.95

        // Three-section layout
        RowLayout {
            anchors.fill:    parent
            anchors.margins: 4
            spacing:         0

            // ── Left: workspaces ─────────────────────────────────────────
            Row {
                id: workspacesRow
                visible: Config.ready ? Config.bar.workspaces.show : true
                spacing: 3
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 4

                Repeater {
                    model: Config.ready ? Config.bar.workspaces.count : 10

                    delegate: WorkspaceButton {
                        required property int index
                        wsId:   index + 1
                        screen: root.screen
                    }
                }
            }

            // ── Center: clock ─────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                visible: Config.ready ? Config.bar.clock.show : true

                Text {
                    anchors.centerIn: parent
                    text: Qt.formatTime(new Date(), Config.ready ? Config.bar.clock.format : "HH:mm")
                    color: Colors.onSurface
                    font.pixelSize: Math.round((Config.ready ? Config.bar.height : 36) * 0.38)
                    font.weight: Font.Medium

                    Timer {
                        interval: 1000
                        running:  true
                        repeat:   true
                        triggeredOnStart: true
                        onTriggered: parent.text = Qt.formatTime(
                            new Date(),
                            Config.ready ? Config.bar.clock.format : "HH:mm"
                        )
                    }
                }
            }

            // ── Right: tray + battery + settings ─────────────────────────
            Row {
                spacing: 6
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 4

                // System tray
                Row {
                    id: trayRow
                    visible: Config.ready ? Config.bar.systray.show : true
                    spacing: 4

                    Repeater {
                        model: SystemTray.items

                        delegate: TrayIcon {
                            required property SystemTrayItem modelData
                            item: modelData
                            iconSize: Math.round((Config.ready ? Config.bar.height : 36) * 0.55)
                        }
                    }
                }

                // Battery
                BatteryWidget {
                    visible: (Config.ready ? Config.bar.battery.show : true)
                        && UPower.displayDevice !== null
                    barHeight: Config.ready ? Config.bar.height : 36
                }

                // Settings toggle
                Rectangle {
                    width:  Math.round((Config.ready ? Config.bar.height : 36) * 0.72)
                    height: width
                    radius: width / 2
                    color:  settingsArea.containsMouse
                            ? Colors.surfaceContainerHigh : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: Colors.onSurfaceVariant
                        font.pixelSize: parent.width * 0.55
                    }

                    MouseArea {
                        id: settingsArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Visibilities.toggleSettings()
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Inline sub-components
    // -----------------------------------------------------------------------

    // Single workspace button.
    component WorkspaceButton: Rectangle {
        id: wsBtn

        required property int wsId
        required property ShellScreen screen

        readonly property bool isActive: {
            const mon = Hyprland.monitorFor(wsBtn.screen)
            return (mon?.activeWorkspace?.id ?? -1) === wsId
        }
        readonly property bool hasWindows: {
            for (const ws of Hyprland.workspaces.values) {
                if (ws.id === wsId && ws.lastIpcObject.windows > 0)
                    return true
            }
            return false
        }

        implicitWidth:  implicitHeight
        implicitHeight: Math.round((Config.ready ? Config.bar.height : 36) * 0.62)
        radius:         implicitHeight / 2

        color: isActive
               ? Colors.primary
               : hasWindows
                 ? Colors.surfaceContainerHigh
                 : "transparent"

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: wsBtn.wsId
            color: wsBtn.isActive ? Colors.onPrimary : Colors.onSurfaceVariant
            font.pixelSize: parent.implicitHeight * 0.52
            font.weight: wsBtn.isActive ? Font.DemiBold : Font.Normal

            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Hyprland.dispatch(`workspace ${wsBtn.wsId}`)
        }
    }

    // Tray icon — left click activates, right click opens menu.
    component TrayIcon: Rectangle {
        id: trayIcon

        required property SystemTrayItem item
        required property int iconSize

        implicitWidth:  iconSize
        implicitHeight: iconSize
        radius:         4
        color:          trayMouseArea.containsMouse
                        ? Colors.surfaceContainerHigh : "transparent"
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color { ColorAnimation { duration: 100 } }

        Image {
            anchors.centerIn: parent
            width:  parent.iconSize
            height: parent.iconSize
            source: trayIcon.item.icon
            smooth: true
            mipmap: true
        }

        MouseArea {
            id: trayMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    trayIcon.item.activate()
                else
                    trayIcon.item.secondaryActivate()
            }
        }
    }

    // Battery percentage + charging indicator.
    component BatteryWidget: Item {
        id: batt

        property int barHeight: 36

        readonly property real percentage: UPower.displayDevice?.percentage ?? 0
        readonly property bool charging:   (UPower.displayDevice?.state ?? 0) === 1 // Charging

        implicitWidth:  battText.implicitWidth + 4
        implicitHeight: barHeight
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: battText
            anchors.centerIn: parent
            text: batt.charging
                  ? "⚡ " + Math.round(batt.percentage) + "%"
                  : Math.round(batt.percentage) + "%"
            color: batt.percentage < 0.20
                   ? Colors.error
                   : Colors.onSurface
            font.pixelSize: Math.round(batt.barHeight * 0.36)

            Behavior on color { ColorAnimation { duration: 300 } }
        }
    }
}
