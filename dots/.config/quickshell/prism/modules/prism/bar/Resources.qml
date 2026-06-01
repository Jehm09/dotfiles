import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    RowLayout {
        id: rowLayout
        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        // RAM
        Resource {
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }

        // Swap
        Resource {
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            shown: root.alwaysShowAllResources ||
                Config.options.bar.resources.alwaysShowSwap
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
        }

        // CPU
        Resource {
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            shown: root.alwaysShowAllResources ||
                Config.options.bar.resources.alwaysShowCpu
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }

        // GPU
        Resource {
            iconName: "memory_alt"
            percentage: ResourceUsage.gpuUsage
            shown: (Config.options.bar.resources.alwaysShowGpu && ResourceUsage.gpuAvailable) ||
                root.alwaysShowAllResources
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.gpuWarningThreshold
        }

        // Network ↓/↑
        Item {
            id: netIndicator
            property bool shown: Config.options.bar.resources.alwaysShowNetwork || root.alwaysShowAllResources
            clip: true
            implicitWidth: shown ? netCol.implicitWidth : 0
            implicitHeight: Appearance.sizes.barHeight
            visible: implicitWidth > 0

            Layout.leftMargin: shown ? 6 : 0

            ColumnLayout {
                id: netCol
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.tiny ?? 9
                    color: Appearance.colors.colOnLayer1
                    text: "↓ " + ResourceUsage.bytesToHuman(ResourceUsage.netDown)
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.tiny ?? 9
                    color: Appearance.colors.colSubtext
                    text: "↑ " + ResourceUsage.bytesToHuman(ResourceUsage.netUp)
                }
            }

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
        }
    }

    ResourcesPopup {
        hoverTarget: root
    }
}
