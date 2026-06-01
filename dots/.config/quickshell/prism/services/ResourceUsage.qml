pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Polled resource usage: RAM, Swap, CPU, CPU temp, GPU, Network, Storage.
 */
Singleton {
    id: root

    // ── Memory ──────────────────────────────────────────────────────────────
    property real memoryTotal: 1
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal

    // ── Swap ────────────────────────────────────────────────────────────────
    property real swapTotal: 1
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0

    // ── CPU ─────────────────────────────────────────────────────────────────
    property real cpuUsage: 0
    property real cpuTemp: 0           // celsius; 0 = unavailable
    property var  previousCpuStats

    // ── GPU ─────────────────────────────────────────────────────────────────
    property real gpuUsage: 0          // 0–1
    property real gpuTemp: 0           // celsius; 0 = unavailable
    property bool gpuAvailable: false

    // ── Network ─────────────────────────────────────────────────────────────
    property real netDown: 0           // bytes/s current
    property real netUp: 0             // bytes/s current
    property real netTotalDown: 0      // cumulative bytes received
    property real netTotalUp: 0        // cumulative bytes sent
    property var  _prevNetStats: null
    property real _prevNetTime: 0

    // ── Storage ─────────────────────────────────────────────────────────────
    // Each entry: { source, target, total, used, free, usedPercent }
    property var disks: []
    property int _storageTick: 0

    // ── Info strings ────────────────────────────────────────────────────────
    property string maxAvailableMemoryString: kbToGbString(root.memoryTotal)
    property string maxAvailableSwapString:   kbToGbString(root.swapTotal)
    property string maxAvailableCpuString: "--"

    // ── History ─────────────────────────────────────────────────────────────
    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    // ── Helpers ─────────────────────────────────────────────────────────────
    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    function bytesToHuman(bytes) {
        if (bytes < 1024)              return bytes.toFixed(0) + " B/s"
        if (bytes < 1024 * 1024)       return (bytes / 1024).toFixed(1) + " KB/s"
        return (bytes / (1024 * 1024)).toFixed(1) + " MB/s"
    }

    function bytesToGb(bytes) {
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(0) + " MB"
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
    }

    function _pushHistory(list, value) {
        const next = [...list, value]
        if (next.length > historyLength) next.shift()
        return next
    }

    function updateHistories() {
        memoryUsageHistory = _pushHistory(memoryUsageHistory, memoryUsedPercentage)
        swapUsageHistory   = _pushHistory(swapUsageHistory,   swapUsedPercentage)
        cpuUsageHistory    = _pushHistory(cpuUsageHistory,    cpuUsage)
    }

    function _parseNetDev(text) {
        let rx = 0, tx = 0
        const iface = Config?.options.resources.networkInterface ?? "auto"
        for (const line of text.split('\n').slice(2)) {
            const parts = line.trim().split(/\s+/)
            if (parts.length < 10) continue
            const name = parts[0].replace(':', '')
            if (name === 'lo') continue
            if (iface !== "auto" && name !== iface) continue
            rx += parseInt(parts[1]) || 0
            tx += parseInt(parts[9]) || 0
        }
        return { rx, tx }
    }

    // ── Main poll timer ──────────────────────────────────────────────────────
    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            const interval = Config.options?.resources?.updateInterval ?? 3000
            const now = Date.now()

            fileMeminfo.reload()
            fileStat.reload()
            fileCpuTemp.reload()
            fileNetDev.reload()

            // Memory + Swap
            const memText = fileMeminfo.text()
            memoryTotal = Number(memText.match(/MemTotal:\s*(\d+)/)?.[1] ?? 1)
            memoryFree  = Number(memText.match(/MemAvailable:\s*(\d+)/)?.[1] ?? 0)
            swapTotal   = Number(memText.match(/SwapTotal:\s*(\d+)/)?.[1] ?? 1)
            swapFree    = Number(memText.match(/SwapFree:\s*(\d+)/)?.[1] ?? 0)

            // CPU usage
            const statText = fileStat.text()
            const cpuLine = statText.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle  = stats[3]
                if (root.previousCpuStats) {
                    const dt = total - root.previousCpuStats.total
                    const di = idle  - root.previousCpuStats.idle
                    cpuUsage = dt > 0 ? (1 - di / dt) : 0
                }
                root.previousCpuStats = { total, idle }
            }

            // CPU temperature
            const rawTemp = parseInt(fileCpuTemp.text().trim())
            if (!isNaN(rawTemp) && rawTemp > 0) cpuTemp = rawTemp / 1000

            // Network speed
            const net = root._parseNetDev(fileNetDev.text())
            if (root._prevNetStats && root._prevNetTime > 0) {
                const elapsed = (now - root._prevNetTime) / 1000
                if (elapsed > 0) {
                    netDown = Math.max(0, (net.rx - root._prevNetStats.rx) / elapsed)
                    netUp   = Math.max(0, (net.tx - root._prevNetStats.tx) / elapsed)
                }
            }
            netTotalDown = net.rx
            netTotalUp   = net.tx
            root._prevNetStats = net
            root._prevNetTime  = now

            // GPU poll (one-shot process restarted each interval)
            if (!gpuPollProc.running) gpuPollProc.running = true

            // Storage: poll every ~30 s (10 × default 3 s interval)
            root._storageTick++
            if (root._storageTick >= 10) {
                root._storageTick = 0
                if (!storagePollProc.running) storagePollProc.running = true
            }

            root.updateHistories()
            this.interval = interval
        }
    }

    FileView { id: fileMeminfo;  path: "/proc/meminfo" }
    FileView { id: fileStat;     path: "/proc/stat" }
    FileView { id: fileCpuTemp;  path: "/sys/class/thermal/thermal_zone0/temp" }
    FileView { id: fileNetDev;   path: "/proc/net/dev" }

    // ── GPU polling ──────────────────────────────────────────────────────────
    Process {
        id: gpuPollProc
        // Try NVIDIA first; fall back to AMD hwmon; output "load,temp" CSV
        command: ["bash", "-c", [
            "out=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu",
            "  --format=csv,noheader,nounits 2>/dev/null | head -1);",
            "if [ -n \"$out\" ]; then echo \"$out\"; exit; fi;",
            "for d in /sys/class/hwmon/hwmon*; do",
            "  name=$(cat \"$d/name\" 2>/dev/null);",
            "  if echo \"$name\" | grep -qi 'amdgpu\\|radeon'; then",
            "    busy=$(cat \"$d/device/gpu_busy_percent\" 2>/dev/null || echo 0);",
            "    temp=$(( $(cat \"$d/temp1_input\" 2>/dev/null || echo 0) / 1000 ));",
            "    echo \"$busy,$temp\"; exit;",
            "  fi;",
            "done"
        ].join(' ')]
        stdout: StdioCollector {
            id: gpuOut
            onStreamFinished: {
                const text = gpuOut.text.trim()
                if (!text) return
                const parts = text.split(',').map(s => parseFloat(s.trim()))
                if (parts.length >= 2 && !isNaN(parts[0]) && !isNaN(parts[1])) {
                    root.gpuUsage     = parts[0] / 100
                    root.gpuTemp      = parts[1]
                    root.gpuAvailable = true
                }
            }
        }
    }

    // ── Storage polling ──────────────────────────────────────────────────────
    Process {
        id: storagePollProc
        command: ["bash", "-c",
            "df -B1 --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2 | " +
            "grep -Ev '^(tmpfs|devtmpfs|udev|efivarfs|none|overlay|/dev/loop|nsfs)'"]
        stdout: StdioCollector {
            id: storageOut
            onStreamFinished: {
                const newDisks = []
                for (const line of storageOut.text.trim().split('\n')) {
                    const p = line.trim().split(/\s+/)
                    if (p.length < 6) continue
                    const total = parseInt(p[1]) || 0
                    if (total < 100 * 1024 * 1024) continue  // skip < 100 MB
                    newDisks.push({
                        source:      p[0],
                        total:       total,
                        used:        parseInt(p[2]) || 0,
                        free:        parseInt(p[3]) || 0,
                        usedPercent: parseInt(p[4]) || 0,
                        target:      p[5]
                    })
                }
                root.disks = newDisks
            }
        }
        Component.onCompleted: running = true
    }

    // ── CPU max frequency ───────────────────────────────────────────────────
    Process {
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        running: true
        stdout: StdioCollector {
            id: cpuFreqOut
            onStreamFinished: {
                const mhz = parseFloat(cpuFreqOut.text)
                if (!isNaN(mhz)) root.maxAvailableCpuString = (mhz / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
