pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// OsdWindow — on-screen display for volume / brightness / muted changes.
//
// Trigger via:
//   qs ipc call osd show volume 0.65
//   qs ipc call osd show brightness 0.80
//   qs ipc call osd show muted 0
//
// The OSD auto-dismisses after Config.osd.timeout ms (default 2000).
// The timeout restarts on each call, so rapid changes stay visible.
//
PanelWindow {
    id: root

    // Anchor bottom-center: bottom + left + right, then center the pill.
    anchors.bottom: true
    anchors.left:   true
    anchors.right:  true

    implicitHeight: 120
    exclusiveZone:  0

    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.layer:     WlrLayer.Overlay

    color: "transparent"

    // Pill indicator
    Rectangle {
        id: pill

        readonly property string icon: {
            switch (Visibilities.osdType) {
            case "volume":     return Visibilities.osdValue > 0.5 ? "🔊"
                                    : Visibilities.osdValue > 0   ? "🔉" : "🔈"
            case "brightness": return "☀"
            case "muted":      return "🔇"
            default:           return "●"
            }
        }

        width:  260
        height: 56
        radius: 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:           parent.bottom
        anchors.bottomMargin:     32

        color: Colors.surfaceContainer

        opacity: Visibilities.osdVisible ? 1 : 0
        // Slide up from below when appearing.
        transform: Translate {
            y: Visibilities.osdVisible ? 0 : 20
            Behavior on y {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        RowLayout {
            anchors.fill:    parent
            anchors.margins: 14
            spacing: 10

            // Icon
            Text {
                text:  pill.icon
                color: Colors.primary
                font.pixelSize: 22
                Layout.alignment: Qt.AlignVCenter
            }

            // Label + progress bar
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text:  Visibilities.osdLabel
                    color: Colors.onSurface
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                // Progress track
                Rectangle {
                    Layout.fillWidth: true
                    height: 4
                    radius: 2
                    color:  Colors.surfaceContainerHigh

                    // Filled portion
                    Rectangle {
                        width:  parent.width * Math.max(0, Math.min(1, Visibilities.osdValue))
                        height: parent.height
                        radius: parent.radius
                        color:  Colors.primary

                        Behavior on width {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            // Percentage text
            Text {
                text:  Visibilities.osdType === "muted"
                       ? I18n.s("osd.muted")
                       : Math.round(Visibilities.osdValue * 100) + "%"
                color: Colors.onSurfaceVariant
                font.pixelSize: 13
                font.monospacedDigits: true
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
