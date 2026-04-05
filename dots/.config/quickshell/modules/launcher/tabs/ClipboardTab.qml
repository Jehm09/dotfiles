// ClipboardTab - browse and paste clipboard history via cliphist.

import QtQuick
import "../../../services"

Item {
    id: root

    property string query: ""

    onVisibleChanged: if (visible) Clipboard.refresh()

    ListView {
        id:           list
        anchors.fill: parent
        clip:         true
        spacing:      4

        model: Clipboard.entries.filter(e =>
            root.query.length === 0 || e.toLowerCase().includes(root.query.toLowerCase())
        ).slice(0, Config.launcher.maxResults)

        delegate: Rectangle {
            required property string modelData
            required property int    index

            width:  list.width
            height: 52
            radius: Config.theme.borderRadius
            color:  hoverArea.containsMouse ? Colors.accentSubtle : Colors.surface0

            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
                anchors { left: parent.left; leftMargin: 12; right: deleteBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 12

                Text {
                    text:           "󰅇"
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                    color:          Colors.subtext0
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    // Show first line only, truncated
                    text:  {
                        const firstLine = modelData.split("\t").pop().split("\n")[0]
                        return firstLine.length > 60 ? firstLine.slice(0, 60) + "…" : firstLine
                    }
                    font.family:    Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    color:          Colors.text
                    elide:          Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Delete button (shown on hover)
            Text {
                id:             deleteBtn
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                visible:        hoverArea.containsMouse
                text:           "󰅖"
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 16
                color:          Colors.error

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        Clipboard.deleteEntry(modelData)
                        Clipboard.refresh()
                    }
                }
            }

            MouseArea {
                id:           hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked: {
                    Clipboard.selectEntry(modelData)
                    launcher.isOpen = false
                }
            }
        }
    }
}
