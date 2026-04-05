// NotificationPopup - toast notification in the top-right corner.
// Uses Quickshell's built-in Notifications service.
// Auto-dismisses after timeout. Click to dismiss early.

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../../components"
import "../../services"

PanelWindow {
    id: root

    anchors { top: true; right: true }
    width:  360
    height: notifColumn.implicitHeight + 16
    color:  "transparent"
    exclusiveZone: 0

    NotificationServer {
        id:      notifServer
        keepOnReload: true
    }

    Column {
        id:      notifColumn
        anchors { top: parent.top; right: parent.right; topMargin: 48; rightMargin: 8 }
        spacing: 6
        width:   344

        Repeater {
            model: notifServer.trackedNotifications

            delegate: Rectangle {
                required property Notification modelData

                id:     notifItem
                width:  parent.width
                height: notifContent.implicitHeight + 24
                radius: Config.theme.borderRadius
                color:  Colors.panel
                border.color: Colors.surface1
                border.width: Config.theme.borderWidth
                clip:   true

                // Slide in from right
                x: notifItem.visible ? 0 : 360
                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                // Auto-dismiss timer
                Timer {
                    interval: modelData.expireTimeout > 0 ? modelData.expireTimeout : 5000
                    running:  true
                    onTriggered: modelData.dismiss()
                }

                Column {
                    id:      notifContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 4

                    Row {
                        width: parent.width
                        spacing: 8

                        // App icon
                        Image {
                            width:    24; height: 24
                            source:   modelData.appIcon ? "image://icon/" + modelData.appIcon : ""
                            fillMode: Image.PreserveAspectFit
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text:           modelData.appName
                            font.family:    Config.theme.font
                            font.pixelSize: Config.theme.fontSize - 1
                            font.weight:    Font.Medium
                            color:          Colors.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item { width: 1; Layout.fillWidth: true }

                        // Close button
                        Text {
                            text:           "󰅖"
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            color:          Colors.subtext0
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                anchors.fill: parent
                                onClicked:    modelData.dismiss()
                            }
                        }
                    }

                    Text {
                        visible:        modelData.summary.length > 0
                        text:           modelData.summary
                        font.family:    Config.theme.font
                        font.pixelSize: Config.theme.fontSize
                        font.weight:    Font.Medium
                        color:          Colors.text
                        width:          parent.width
                        wrapMode:       Text.WordWrap
                    }

                    Text {
                        visible:        modelData.body.length > 0
                        text:           modelData.body
                        font.family:    Config.theme.font
                        font.pixelSize: Config.theme.fontSize - 1
                        color:          Colors.subtext0
                        width:          parent.width
                        wrapMode:       Text.WordWrap
                        maximumLineCount: 3
                        elide:          Text.ElideRight
                    }
                }

                // Accent bar on left edge
                Rectangle {
                    width:  3
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    color:  Colors.accent
                    radius: parent.radius
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked:    modelData.dismiss()
                }
            }
        }
    }
}
