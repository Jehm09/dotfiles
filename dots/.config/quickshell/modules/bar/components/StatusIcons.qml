// StatusIcons - volume + network + battery cluster.
// Click anywhere on the pill to toggle the Control Center panel.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../../components"
import "../../../services"

PillContainer {
    id: root

    signal controlCenterToggled()

    paddingH: 10

    Row {
        anchors.centerIn: parent
        spacing: 8

        // Volume icon + level
        Text {
            id: volumeIcon
            text:           volumeLevel <= 0 || volumeMuted ? "󰸈"
                          : volumeLevel < 33               ? "󰕿"
                          : volumeLevel < 66               ? "󰖀"
                          :                                  "󰕾"
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            color:          Colors.subtext0

            property int  volumeLevel: 50
            property bool volumeMuted: false

            Timer {
                interval: 2000; running: true; repeat: true
                onTriggered: volumeQuery.running = true
            }

            Process {
                id: volumeQuery
                command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        const match = data.match(/Volume:\s+([\d.]+)(\s+\[MUTED\])?/)
                        if (match) {
                            volumeIcon.volumeLevel = Math.round(parseFloat(match[1]) * 100)
                            volumeIcon.volumeMuted = !!match[2]
                        }
                    }
                }
            }
        }

        // Network icon
        Text {
            text:           "󰤨"       // default: connected; could wire up NetworkManager IPC
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            color:          Colors.subtext0
        }

        // Battery icon (hidden on desktops)
        Text {
            id: batteryIcon
            visible:        batteryLevel >= 0 && Config.bar.showBattery
            text:           batteryLevel < 10  ? "󰂎"
                          : batteryLevel < 25  ? "󰁺"
                          : batteryLevel < 50  ? "󰁼"
                          : batteryLevel < 75  ? "󰁾"
                          : batteryLevel < 90  ? "󰂀"
                          :                      "󰂂"
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            color:          batteryLevel < 20 ? Colors.error : Colors.subtext0
            Behavior on color { ColorAnimation { duration: 300 } }

            property int batteryLevel: -1  // -1 = no battery (desktop)

            Timer {
                interval: 30000; running: true; repeat: true
                onTriggered: batteryQuery.running = true
            }

            Process {
                id: batteryQuery
                command: ["bash", "-c",
                    "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 || echo -1"]
                running: true
                stdout: SplitParser {
                    onRead: data => { batteryIcon.batteryLevel = parseInt(data.trim()) || -1 }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape:  Qt.PointingHandCursor
        hoverEnabled: true
        onClicked:    root.controlCenterToggled()
        // Let child timer intervals update without stealing hover
        propagateComposedEvents: true
    }
}
