import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        // ── RAM ───────────────────────────────────────────────────────────────
        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "memory"; label: "RAM" }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"; label: Translation.tr("Used:")
                    value: `${root.formatKB(ResourceUsage.memoryUsed)}  (${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%)`
                }
                StyledPopupValueRow {
                    icon: "check_circle"; label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.memoryFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"; label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.memoryTotal)
                }
            }
        }

        // ── Swap ──────────────────────────────────────────────────────────────
        Column {
            visible: ResourceUsage.swapTotal > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "swap_horiz"; label: "Swap" }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"; label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.swapUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"; label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.swapFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"; label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.swapTotal)
                }
            }
        }

        // ── CPU ───────────────────────────────────────────────────────────────
        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "planner_review"; label: "CPU" }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"; label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                }
                StyledPopupValueRow {
                    visible: Config.options.bar.resources.popupCpuTemp && ResourceUsage.cpuTemp > 0
                    icon: "thermometer"; label: Translation.tr("Temp:")
                    value: `${ResourceUsage.cpuTemp.toFixed(0)}°C`
                }
            }
        }

        // ── GPU ───────────────────────────────────────────────────────────────
        Column {
            visible: Config.options.bar.resources.popupGpu && ResourceUsage.gpuAvailable
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "memory_alt"; label: "GPU" }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"; label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.gpuUsage * 100)}%`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.gpuTemp > 0
                    icon: "thermometer"; label: Translation.tr("Temp:")
                    value: `${ResourceUsage.gpuTemp.toFixed(0)}°C`
                }
            }
        }

        // ── Network ───────────────────────────────────────────────────────────
        Column {
            visible: Config.options.bar.resources.popupNetwork
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "network_node"; label: Translation.tr("Network") }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "arrow_downward"; label: Translation.tr("Down:")
                    value: ResourceUsage.bytesToHuman(ResourceUsage.netDown)
                }
                StyledPopupValueRow {
                    icon: "arrow_upward"; label: Translation.tr("Up:")
                    value: ResourceUsage.bytesToHuman(ResourceUsage.netUp)
                }
                StyledPopupValueRow {
                    icon: "download"; label: Translation.tr("Total ↓:")
                    value: ResourceUsage.bytesToGb(ResourceUsage.netTotalDown)
                }
                StyledPopupValueRow {
                    icon: "upload"; label: Translation.tr("Total ↑:")
                    value: ResourceUsage.bytesToGb(ResourceUsage.netTotalUp)
                }
            }
        }

        // ── Storage ───────────────────────────────────────────────────────────
        Column {
            visible: Config.options.bar.resources.popupStorage && ResourceUsage.disks.length > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow { icon: "hard_drive"; label: Translation.tr("Storage") }
            Column {
                spacing: 8
                Repeater {
                    model: ResourceUsage.disks
                    delegate: Column {
                        required property var modelData
                        spacing: 2

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: modelData.target + " (" + modelData.source.replace(/^\/dev\//, "") + ")"
                        }
                        Column {
                            spacing: 4
                            StyledPopupValueRow {
                                icon: "clock_loader_60"; label: Translation.tr("Used:")
                                value: `${ResourceUsage.bytesToGb(modelData.used)}  (${modelData.usedPercent}%)`
                            }
                            StyledPopupValueRow {
                                icon: "check_circle"; label: Translation.tr("Free:")
                                value: ResourceUsage.bytesToGb(modelData.free)
                            }
                            StyledPopupValueRow {
                                icon: "empty_dashboard"; label: Translation.tr("Total:")
                                value: ResourceUsage.bytesToGb(modelData.total)
                            }
                        }
                    }
                }
            }
        }
    }
}
