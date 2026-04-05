pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// LauncherWindow — centered app search overlay.
//
// Toggle via:
//   qs ipc call launcher toggle
//
PanelWindow {
    id: root

    // Cover the full screen so clicks outside the card dismiss it.
    anchors.top:    true
    anchors.bottom: true
    anchors.left:   true
    anchors.right:  true

    exclusiveZone: 0

    WlrLayershell.namespace:     "qs-launcher"
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    color: "transparent"

    // Keep window alive for animations; restrict input via mask.
    mask: Region { item: card }

    // Darken backdrop when open.
    Rectangle {
        anchors.fill: parent
        color:   Qt.rgba(0, 0, 0, 0.45)
        opacity: Visibilities.launcherOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            enabled: Visibilities.launcherOpen
            onClicked: Visibilities.launcherOpen = false
        }
    }

    // Card
    Rectangle {
        id: card

        readonly property int cardWidth:  Config.ready ? Config.launcher.width : 680
        readonly property int cardHeight: searchBox.height
                                        + Math.min(appList.count, 8) * (appList.itemHeight + appList.spacing)
                                        + 24

        anchors.horizontalCenter: parent.horizontalCenter
        // Sit in the upper-third of the screen for a natural feel.
        y: parent.height * 0.18

        width:  cardWidth
        height: cardHeight

        radius: 16
        color:  Colors.surfaceContainerLow

        // Scale + fade in/out
        opacity: Visibilities.launcherOpen ? 1 : 0
        scale:   Visibilities.launcherOpen ? 1 : 0.94

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Reopen focus + clear search each time it opens
        onVisibleChanged: {
            if (Visibilities.launcherOpen) {
                searchInput.text = ""
                searchInput.forceActiveFocus()
            }
        }

        Connections {
            target: Visibilities
            function onLauncherOpenChanged() {
                if (Visibilities.launcherOpen) {
                    searchInput.text = ""
                    searchInput.forceActiveFocus()
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Search field
            Rectangle {
                id: searchBox
                Layout.fillWidth: true
                height: 44
                radius: 10
                color: Colors.surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "⌕"
                        color: Colors.onSurfaceVariant
                        font.pixelSize: 18
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: Colors.onSurface
                        font.pixelSize: 15
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter

                        Keys.onEscapePressed:  Visibilities.launcherOpen = false
                        Keys.onReturnPressed:  appList.launchCurrent()
                        Keys.onUpPressed:   appList.moveCurrentIndexUp()
                        Keys.onDownPressed: appList.moveCurrentIndexDown()
                        Keys.onTabPressed:  appList.moveCurrentIndexDown()
                    }

                    // Placeholder
                    Text {
                        anchors.fill: parent.parent
                        anchors.margins: parent.parent.spacing
                        text: I18n.s("launcher.placeholder")
                        color: Colors.onSurfaceVariant
                        font.pixelSize: 15
                        verticalAlignment: Text.AlignVCenter
                        visible: searchInput.text.length === 0
                    }
                }
            }

            // Results list
            ListView {
                id: appList

                readonly property int itemHeight: 52
                readonly property string query:   searchInput.text.toLowerCase()

                Layout.fillWidth: true
                implicitHeight: Math.min(count, 8) * (itemHeight + spacing) - (count > 0 ? spacing : 0)
                clip: true

                model: DesktopEntries.applications.values.filter(app => {
                    if (!query) return true
                    return app.name.toLowerCase().includes(query)
                        || (app.genericName ?? "").toLowerCase().includes(query)
                        || (app.comment    ?? "").toLowerCase().includes(query)
                })

                spacing: 2
                currentIndex: 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: Colors.outline
                        opacity: parent.active ? 0.8 : 0.3
                    }
                }

                function launchCurrent(): void {
                    const entry = model[currentIndex]
                    if (entry) {
                        entry.launch()
                        Visibilities.launcherOpen = false
                    }
                }

                delegate: Rectangle {
                    id: appRow

                    required property var modelData
                    required property int index

                    width: appList.width
                    height: appList.itemHeight
                    radius: 8
                    color:  appList.currentIndex === index
                            ? Colors.primaryContainer
                            : rowArea.containsMouse
                              ? Colors.surfaceContainerHigh
                              : "transparent"

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill:    parent
                        anchors.margins: 8
                        spacing: 10

                        // App icon
                        Image {
                            width:  32; height: 32
                            source: appRow.modelData.icon
                                    ? `image://icon/${appRow.modelData.icon}`
                                    : ""
                            smooth: true
                            mipmap: true
                            fillMode: Image.PreserveAspectFit
                            Layout.alignment: Qt.AlignVCenter

                            // Fallback placeholder
                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: Colors.surfaceContainerHigh
                                visible: parent.status !== Image.Ready
                                Text {
                                    anchors.centerIn: parent
                                    text: (appRow.modelData.name ?? "?")[0]
                                    color: Colors.primary
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        // Name + description
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text:  appRow.modelData.name ?? ""
                                color: appList.currentIndex === appRow.index
                                       ? Colors.onPrimaryContainer : Colors.onSurface
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text:  appRow.modelData.comment ?? appRow.modelData.genericName ?? ""
                                color: Colors.onSurfaceVariant
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            appRow.modelData.launch()
                            Visibilities.launcherOpen = false
                        }
                        onEntered: appList.currentIndex = appRow.index
                    }
                }

                // "No results" placeholder
                Text {
                    anchors.centerIn: parent
                    text: I18n.s("launcher.noResults")
                    color: Colors.onSurfaceVariant
                    font.pixelSize: 14
                    visible: appList.count === 0
                }
            }
        }
    }
}
