// SessionPanel - lock, logout, reboot, shutdown buttons at the bottom of CC.

import QtQuick
import Quickshell.Io
import "../../../components"
import "../../../services"

Row {
    id: root

    spacing: 8

    component SessionButton: Rectangle {
        required property string icon
        required property string label
        required property color  buttonColor
        signal activated()

        width:  (root.width - root.spacing * 3) / 4
        height: 56
        radius: Config.theme.borderRadius
        color:  hoverArea.containsMouse
                  ? Qt.lighter(buttonColor, 1.3)
                  : Qt.rgba(Qt.color(buttonColor).r,
                            Qt.color(buttonColor).g,
                            Qt.color(buttonColor).b, 0.15)

        Behavior on color { ColorAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           icon
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                color:          buttonColor
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           label
                font.family:    Config.theme.font
                font.pixelSize: 10
                color:          buttonColor
            }
        }

        MouseArea {
            id:           hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked:    parent.activated()
        }
    }

    SessionButton {
        icon:        "󰌾"
        label:       I18n.t("session.lock")
        buttonColor: Colors.info
        onActivated: Process { command: ["hyprlock"]; running: true }
    }

    SessionButton {
        icon:        "󰍃"
        label:       I18n.t("session.logout")
        buttonColor: Colors.accent
        onActivated: Process { command: ["hyprctl", "dispatch", "exit"]; running: true }
    }

    SessionButton {
        icon:        "󰑓"
        label:       I18n.t("session.reboot")
        buttonColor: Colors.warning
        onActivated: Process { command: ["systemctl", "reboot"]; running: true }
    }

    SessionButton {
        icon:        "󰐥"
        label:       I18n.t("session.shutdown")
        buttonColor: Colors.error
        onActivated: Process { command: ["systemctl", "poweroff"]; running: true }
    }
}
