pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// SettingsWindow — layer-shell panel that slides in from the right.
//
// Toggle via:
//   qs ipc call settings toggle
//
PanelWindow {
    id: root

    // Anchor to the right edge, full height.
    anchors.right:  true
    anchors.top:    true
    anchors.bottom: true

    // Overlay — don't push other windows.
    exclusiveZone: 0

    // Fixed width; height fills the screen.
    implicitWidth: 360

    WlrLayershell.namespace: "qs-settings"
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Always visible so the slide animation can run.
    // Input is restricted to the panel card via `mask` below.
    color: "transparent"

    // Restrict input to the visible panel area only.
    // When closed the panel is translated off-screen → mask covers nothing.
    mask: Region {
        item: panel
    }

    // Semi-transparent backdrop — only shown while open.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        opacity: Visibilities.settingsOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        MouseArea {
            anchors.fill: parent
            enabled: Visibilities.settingsOpen
            onClicked: Visibilities.settingsOpen = false
        }
    }

    // Panel card — slides in from the right.
    Rectangle {
        id: panel

        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        anchors.right:  parent.right
        width: parent.implicitWidth

        color: Colors.surfaceContainerLow

        // Slide offset: 0 when open, full width when closed.
        property real slideX: Visibilities.settingsOpen ? 0 : width
        Behavior on slideX { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        transform: Translate { x: panel.slideX }

        // Title bar
        Rectangle {
            id: titleBar
            anchors.top:   parent.top
            anchors.left:  parent.left
            anchors.right: parent.right
            height: 52
            color: Colors.surfaceContainer

            Text {
                anchors.left:           parent.left
                anchors.leftMargin:     20
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.s("settings.title")
                color: Colors.onSurface
                font.pixelSize: 18
                font.weight: Font.Medium
            }

            // Close button
            Rectangle {
                anchors.right:          parent.right
                anchors.rightMargin:    12
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32; radius: 16
                color: closeArea.containsMouse ? Colors.surfaceContainerHigh : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Colors.onSurfaceVariant
                    font.pixelSize: 14
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Visibilities.settingsOpen = false
                }
            }
        }

        // Content — absorbs clicks so they don't reach the backdrop dismiss area.
        Item {
            anchors.top:    titleBar.bottom
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom

            SettingsPanel {
                anchors.fill: parent
            }
        }
    }
}
