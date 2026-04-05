// ControlCenter - slide-in panel from the top-right corner.
// Opened/closed by clicking the StatusIcons cluster in the bar.
// Contains: quick toggles, volume, brightness, session buttons.
// NO gestures - click only.

import QtQuick
import Quickshell
import Quickshell.Io
import "./panels"
import "../../services"

PanelWindow {
    id: root

    property bool isOpen: false

    anchors { top: true; right: true }
    width:  360
    height: panelContent.implicitHeight + 32
    color:  "transparent"
    exclusiveZone: 0   // don't push other windows - float over them

    // Slide in/out from the top
    transform: Translate {
        y: root.isOpen ? 0 : -(root.height + 8)
        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    }
    opacity: root.isOpen ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    // Dismiss when clicking outside the panel
    MouseArea {
        anchors.fill: parent
        z:            -1
        onClicked:    root.isOpen = false
    }

    Rectangle {
        id:      panelContent
        anchors { top: parent.top; right: parent.right; topMargin: Config.bar.height + 6; rightMargin: 8 }
        width:   340
        color:   Colors.panel
        radius:  Config.theme.borderRadius
        border.color: Colors.surface1
        border.width: Config.theme.borderWidth

        // Implicit height from content
        implicitHeight: contentColumn.implicitHeight + 24

        Column {
            id:      contentColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 16

            // Quick toggles row
            QuickToggles {
                width: parent.width
            }

            // Divider
            Rectangle { width: parent.width; height: 1; color: Colors.surface1 }

            // Volume
            AudioPanel {
                id:    audioPanel
                width: parent.width
            }

            // Brightness (only shown if /sys/class/backlight exists)
            Column {
                id:      brightnessSection
                width:   parent.width
                spacing: 8
                visible: brightnessAvailable

                property bool brightnessAvailable: false
                property real brightnessValue: 0.8

                Component.onCompleted: {
                    // Check if backlight exists
                    Process {
                        command: ["bash", "-c", "ls /sys/class/backlight/ 2>/dev/null | head -1"]
                        running: true
                        stdout: SplitParser {
                            onRead: data => {
                                brightnessSection.brightnessAvailable = data.trim().length > 0
                                if (brightnessSection.brightnessAvailable) brightnessQuery.running = true
                            }
                        }
                    }
                }

                Process {
                    id: brightnessQuery
                    command: ["bash", "-c",
                        "brightnessctl -m | awk -F, '{print $4}' | tr -d '%'"]
                    stdout: SplitParser {
                        onRead: data => {
                            const pct = parseInt(data.trim())
                            if (!isNaN(pct)) brightnessSection.brightnessValue = pct / 100
                        }
                    }
                }

                Row {
                    width: parent.width
                    Text {
                        text:           "󰃟"
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 18
                        color:          Colors.subtext0
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 8 }
                    Text {
                        text:           I18n.t("controlcenter.brightness")
                        font.family:    Config.theme.font
                        font.pixelSize: Config.theme.fontSize
                        color:          Colors.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Slider {
                    width: parent.width
                    value: brightnessSection.brightnessValue
                    onMoved: val => {
                        brightnessSection.brightnessValue = val
                        Process {
                            command: ["brightnessctl", "set", Math.round(val * 100) + "%"]
                            running: true
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Colors.surface1 }
            }

            // Session buttons
            SessionPanel {
                width: parent.width
            }

            Item { height: 4 }
        }
    }

    // Load volume on open
    onIsOpenChanged: if (isOpen) audioPanel.refresh()
}
