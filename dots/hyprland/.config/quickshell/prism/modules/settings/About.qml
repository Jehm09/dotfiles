import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "box"
        title: Translation.tr("Distro")

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                source: Quickshell.iconPath(SystemInfo.logo)
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                StyledText {
                    text: SystemInfo.distroName
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    text: SystemInfo.homeUrl
                    textFormat: Text.MarkdownText
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                    }
                    PointingHandLinkHover {}
                }
            }
        }
    }

    ContentSection {
        icon: "computer"
        title: Translation.tr("Hardware")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: [
                    { icon: "terminal",        label: Translation.tr("Kernel"), value: SystemInfo.kernelVersion },
                    { icon: "memory",          label: Translation.tr("CPU"),    value: SystemInfo.cpuModel },
                    { icon: "display_settings",label: Translation.tr("GPU"),    value: SystemInfo.gpuModel },
                    { icon: "memory_alt",      label: Translation.tr("RAM"),    value: SystemInfo.ramTotal },
                    { icon: "hard_drive",      label: Translation.tr("Disk"),   value: SystemInfo.diskInfo },
                ]

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialSymbol {
                        text: modelData.icon
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: modelData.label
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        Layout.minimumWidth: 50
                    }
                    StyledText {
                        text: modelData.value !== "" ? modelData.value : "…"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.75
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
