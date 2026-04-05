// CalculatorTab - evaluate math expressions with bc, show result live.

import QtQuick
import Quickshell.Io
import "../../../services"

Item {
    id: root

    property string query:  ""
    property string result: ""
    property bool   hasError: false

    onQueryChanged: {
        if (query.trim().length === 0) { result = ""; return }
        // Sanitize: only allow math-safe characters
        const safe = query.replace(/[^0-9+\-*/().^%, ]/g, "")
        if (safe !== query || safe.length === 0) { result = ""; return }
        bcProcess.command = ["bash", "-c", `echo 'scale=10; ${safe}' | bc -l 2>/dev/null`]
        bcProcess.running = true
    }

    Process {
        id: bcProcess
        command: []
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                root.hasError  = trimmed.length === 0
                root.result    = trimmed.length > 0 ? trimmed : ""
            }
        }
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 12

        // Result display
        Rectangle {
            width:  parent.width
            height: 72
            radius: Config.theme.borderRadius
            color:  Colors.surface0
            visible: root.query.length > 0

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:           root.query
                    font.family:    Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    color:          Colors.subtext0
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:           root.result.length > 0 ? "= " + root.result : (root.hasError ? "…" : "")
                    font.family:    Config.theme.font
                    font.pixelSize: Config.theme.fontSize + 8
                    font.weight:    Font.Bold
                    color:          Colors.accent
                }
            }

            // Copy result on click
            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                visible:      root.result.length > 0
                onClicked: {
                    Process { command: ["bash", "-c", `echo -n ${JSON.stringify(root.result)} | wl-copy`]; running: true }
                    launcher.isOpen = false
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.query.length === 0
            text:   "Type a math expression\n2 + 2, sqrt(16), 10 % 3, ..."
            color:  Colors.overlay0
            font.family:    Config.theme.font
            font.pixelSize: Config.theme.fontSize
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
