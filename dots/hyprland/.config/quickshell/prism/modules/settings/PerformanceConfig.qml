import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    // ── Bar indicators ────────────────────────────────────────────────────────
    ContentSection {
        icon: "bar_chart"
        title: Translation.tr("Bar indicators")

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr("RAM")
            checked: true
            enabled: false      // RAM always shown
            StyledToolTip { text: Translation.tr("RAM is always shown in the bar") }
        }
        ConfigSwitch {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Swap")
            checked: Config.options.bar.resources.alwaysShowSwap
            onCheckedChanged: Config.options.bar.resources.alwaysShowSwap = checked
        }
        ConfigSwitch {
            buttonIcon: "planner_review"
            text: Translation.tr("CPU")
            checked: Config.options.bar.resources.alwaysShowCpu
            onCheckedChanged: Config.options.bar.resources.alwaysShowCpu = checked
        }
        ConfigSwitch {
            buttonIcon: "memory_alt"
            text: Translation.tr("GPU")
            checked: Config.options.bar.resources.alwaysShowGpu
            onCheckedChanged: Config.options.bar.resources.alwaysShowGpu = checked
            StyledToolTip { text: Translation.tr("Requires NVIDIA (nvidia-smi) or AMD GPU") }
        }
        ConfigSwitch {
            buttonIcon: "network_node"
            text: Translation.tr("Network speeds")
            checked: Config.options.bar.resources.alwaysShowNetwork
            onCheckedChanged: Config.options.bar.resources.alwaysShowNetwork = checked
        }
    }

    // ── Popup details (on hover) ──────────────────────────────────────────────
    ContentSection {
        icon: "info"
        title: Translation.tr("Hover popup details")

        ConfigSwitch {
            buttonIcon: "thermometer"
            text: Translation.tr("CPU temperature")
            checked: Config.options.bar.resources.popupCpuTemp
            onCheckedChanged: Config.options.bar.resources.popupCpuTemp = checked
        }
        ConfigSwitch {
            buttonIcon: "memory_alt"
            text: Translation.tr("GPU (load + temperature)")
            checked: Config.options.bar.resources.popupGpu
            onCheckedChanged: Config.options.bar.resources.popupGpu = checked
            StyledToolTip { text: Translation.tr("Auto-detected; hidden if no GPU found") }
        }
        ConfigSwitch {
            buttonIcon: "hard_drive"
            text: Translation.tr("Disk storage")
            checked: Config.options.bar.resources.popupStorage
            onCheckedChanged: Config.options.bar.resources.popupStorage = checked
            StyledToolTip { text: Translation.tr("Shows all mounted disks > 100 MB (excludes tmpfs/loop)") }
        }
        ConfigSwitch {
            buttonIcon: "network_node"
            text: Translation.tr("Network (speeds + totals)")
            checked: Config.options.bar.resources.popupNetwork
            onCheckedChanged: Config.options.bar.resources.popupNetwork = checked
        }
    }

    // ── Warning thresholds ────────────────────────────────────────────────────
    ContentSection {
        icon: "warning"
        title: Translation.tr("Warning thresholds (%)")

        ConfigSpinBox {
            icon: "memory"
            text: Translation.tr("RAM warning at")
            value: Config.options.bar.resources.memoryWarningThreshold
            from: 50; to: 100; stepSize: 5
            onValueChanged: Config.options.bar.resources.memoryWarningThreshold = value
        }
        ConfigSpinBox {
            icon: "swap_horiz"
            text: Translation.tr("Swap warning at")
            value: Config.options.bar.resources.swapWarningThreshold
            from: 50; to: 100; stepSize: 5
            onValueChanged: Config.options.bar.resources.swapWarningThreshold = value
        }
        ConfigSpinBox {
            icon: "planner_review"
            text: Translation.tr("CPU warning at")
            value: Config.options.bar.resources.cpuWarningThreshold
            from: 50; to: 100; stepSize: 5
            onValueChanged: Config.options.bar.resources.cpuWarningThreshold = value
        }
        ConfigSpinBox {
            icon: "memory_alt"
            text: Translation.tr("GPU warning at")
            value: Config.options.bar.resources.gpuWarningThreshold
            from: 50; to: 100; stepSize: 5
            onValueChanged: Config.options.bar.resources.gpuWarningThreshold = value
        }
    }

    // ── Polling ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "timer"
        title: Translation.tr("Polling")

        ConfigSpinBox {
            icon: "update"
            text: Translation.tr("Update interval (ms)")
            value: Config.options.resources.updateInterval
            from: 500; to: 10000; stepSize: 500
            onValueChanged: Config.options.resources.updateInterval = value
        }
    }
}
