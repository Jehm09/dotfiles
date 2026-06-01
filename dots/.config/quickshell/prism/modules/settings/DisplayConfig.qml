import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Ordered monitor list: saved order first (still-detected), then any
    // newly-detected monitor not yet in the saved order.
    property var orderedMonitors: {
        const detected = HyprlandData.allMonitors || [];
        const saved = Config.options.display.order || [];
        const result = [];
        const seen = {};
        for (let i = 0; i < saved.length; i++) {
            const m = detected.find(d => d.name === saved[i]);
            if (m) { result.push(m); seen[m.name] = true; }
        }
        for (let i = 0; i < detected.length; i++) {
            const m = detected[i];
            if (!seen[m.name]) result.push(m);
        }
        return result;
    }

    function monitorConfig(name) {
        const list = Config.options.display.monitors || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === name) return list[i];
        }
        return null;
    }

    function upsertMonitor(name, patch) {
        const list = (Config.options.display.monitors || []).slice();
        const idx = list.findIndex(m => m && m.name === name);
        if (idx >= 0) {
            list[idx] = Object.assign({}, list[idx], patch);
        } else {
            list.push(Object.assign({ name: name }, patch));
        }
        Config.options.display.monitors = list;
    }

    function moveInOrder(name, delta) {
        const detectedNames = (HyprlandData.allMonitors || []).map(m => m.name);
        let arr = (Config.options.display.order || []).slice().filter(n => detectedNames.indexOf(n) >= 0);
        for (let i = 0; i < detectedNames.length; i++) {
            if (arr.indexOf(detectedNames[i]) < 0) arr.push(detectedNames[i]);
        }
        const idx = arr.indexOf(name);
        if (idx < 0) return;
        const j = idx + delta;
        if (j < 0 || j >= arr.length) return;
        const tmp = arr[idx];
        arr[idx] = arr[j];
        arr[j] = tmp;
        Config.options.display.order = arr;
    }

    function parseModeString(modeStr) {
        const m = String(modeStr).match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
        if (!m) return null;
        return {
            width: parseInt(m[1]),
            height: parseInt(m[2]),
            refreshRate: parseFloat(m[3])
        };
    }

    function modeKeyFor(width, height, refreshRate) {
        return `${width}x${height}@${Number(refreshRate).toFixed(3)}`;
    }

    function formatHz(rate) {
        // Up to 3 decimals, strip trailing zeros: 144.00 → 144, 74.991 → 74.991, 59.940 → 59.94
        return parseFloat(Number(rate).toFixed(3)).toString();
    }

    function currentModeKey(monitor) {
        const cfg = root.monitorConfig(monitor.name);
        const w = (cfg && cfg.width) || monitor.width;
        const h = (cfg && cfg.height) || monitor.height;
        const r = (cfg && cfg.refreshRate) || monitor.refreshRate;
        return root.modeKeyFor(w, h, r);
    }

    function monitorEnabled(monitor) {
        const cfg = root.monitorConfig(monitor.name);
        if (cfg && cfg.enabled !== undefined) return cfg.enabled;
        return !monitor.disabled;
    }

    function monitorPosition(monitor) {
        const cfg = root.monitorConfig(monitor.name);
        const x = (cfg && cfg.x !== undefined) ? cfg.x : monitor.x;
        const y = (cfg && cfg.y !== undefined) ? cfg.y : monitor.y;
        return { x: x, y: y };
    }

    function monitorScale(monitor) {
        const cfg = root.monitorConfig(monitor.name);
        if (cfg && cfg.scale !== undefined) return cfg.scale;
        if (cfg && cfg.scalePercent !== undefined) return cfg.scalePercent / 100;
        return monitor.scale || 1.0;
    }

    function formatScale(s) {
        const pct = s * 100;
        const pctStr = (Math.abs(pct - Math.round(pct)) < 0.05) ? Math.round(pct) : pct.toFixed(1);
        const factor = (Math.abs(s - Math.round(s)) < 0.0001) ? s.toFixed(1) : s.toFixed(4).replace(/0+$/, "");
        return `${pctStr}%  (×${factor})`;
    }

    function gcd(a, b) {
        a = Math.abs(Math.round(a));
        b = Math.abs(Math.round(b));
        while (b !== 0) { const t = b; b = a % b; a = t; }
        return a;
    }

    // Hyprland accepts a scale only if width/scale and height/scale are both
    // (approximately) integers. The valid scales for a W×H monitor are
    // gcd(W,H)/m for any positive integer m. We further filter to multiples of
    // 1/120 — the grid Hyprland snaps to internally — and clamp to the user
    // range [1.0, 3.0].
    function validScalesFor(monitor) {
        const W = monitor.width, H = monitor.height;
        if (!W || !H) return [1.0];
        const g = root.gcd(W, H);
        const grid = g * 120; // m must divide this for s = g/m to land on the 1/120 grid
        const minS = 1.0, maxS = 3.0;
        // m range from ceil(g/maxS) to floor(g/minS)
        const mMin = Math.max(1, Math.ceil(g / maxS));
        const mMax = Math.floor(g / minS);
        const scales = [];
        for (let m = mMin; m <= mMax; m++) {
            if (grid % m !== 0) continue;
            scales.push(g / m);
        }
        // gcd/mMax may overshoot 1.0 slightly due to flooring; ensure 1.0 is present
        if (scales.indexOf(1.0) === -1) scales.push(1.0);
        scales.sort((a, b) => a - b);
        // Dedupe (shouldn't happen but safe).
        const seen = {};
        return scales.filter(s => {
            const k = s.toFixed(6);
            if (seen[k]) return false;
            seen[k] = true;
            return true;
        });
    }

    function nearestValidScale(monitor, desired) {
        const valid = root.validScalesFor(monitor);
        let best = valid[0], bestD = Math.abs(valid[0] - desired);
        for (let i = 1; i < valid.length; i++) {
            const d = Math.abs(valid[i] - desired);
            if (d < bestD) { best = valid[i]; bestD = d; }
        }
        return best;
    }

    property bool layoutEditorOpen: false

    ContentSection {
        icon: "monitor"
        title: Translation.tr("Monitors")

        StyledText {
            visible: root.orderedMonitors.length === 0
            Layout.fillWidth: true
            Layout.leftMargin: 8
            color: Appearance.colors.colSubtext
            text: Translation.tr("No monitors detected. Make sure Hyprland is running.")
        }

        RippleButtonWithIcon {
            visible: root.orderedMonitors.length > 0
            Layout.fillWidth: false
            implicitWidth: 220
            Layout.leftMargin: 8
            buttonRadius: Appearance.rounding.small
            materialIcon: "open_with"
            mainText: Translation.tr("Arrange layout")
            onClicked: root.layoutEditorOpen = true
            StyledToolTip {
                text: Translation.tr("Open a window to drag monitors and set their positions")
            }
        }

        Repeater {
            model: root.orderedMonitors

            delegate: Rectangle {
                id: monitorCard
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: cardColumn.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: cardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "monitor"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: `${monitorCard.index + 1}. ${monitorCard.modelData.name}`
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                visible: text.length > 0
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: monitorCard.modelData.description || ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            enabled: monitorCard.index > 0
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_upward"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            onClicked: root.moveInOrder(monitorCard.modelData.name, -1)
                            StyledToolTip { text: Translation.tr("Move up") }
                        }
                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            enabled: monitorCard.index < root.orderedMonitors.length - 1
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_downward"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            onClicked: root.moveInOrder(monitorCard.modelData.name, 1)
                            StyledToolTip { text: Translation.tr("Move down") }
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "power_settings_new"
                        text: Translation.tr("Enabled")
                        checked: root.monitorEnabled(monitorCard.modelData)
                        onCheckedChanged: {
                            if (checked === root.monitorEnabled(monitorCard.modelData)) return;
                            root.upsertMonitor(monitorCard.modelData.name, { enabled: checked });
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 10

                        MaterialSymbol {
                            text: "aspect_ratio"
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: Translation.tr("Resolution & refresh rate")
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        Item { Layout.fillWidth: true }
                        StyledComboBox {
                            id: modeCombo
                            implicitWidth: 260
                            Layout.fillWidth: false
                            textRole: "displayName"

                            property var modeModel: {
                                const modes = monitorCard.modelData.availableModes || [];
                                const seen = {};
                                const result = [];
                                for (let i = 0; i < modes.length; i++) {
                                    const parsed = root.parseModeString(modes[i]);
                                    if (!parsed) continue;
                                    const key = root.modeKeyFor(parsed.width, parsed.height, parsed.refreshRate);
                                    if (seen[key]) continue;
                                    seen[key] = true;
                                    result.push({
                                        displayName: `${parsed.width}×${parsed.height} @ ${root.formatHz(parsed.refreshRate)}Hz`,
                                        value: key,
                                        width: parsed.width,
                                        height: parsed.height,
                                        refreshRate: parsed.refreshRate
                                    });
                                }
                                if (result.length === 0) {
                                    const w = monitorCard.modelData.width;
                                    const h = monitorCard.modelData.height;
                                    const r = monitorCard.modelData.refreshRate;
                                    result.push({
                                        displayName: `${w}×${h} @ ${root.formatHz(r)}Hz`,
                                        value: root.modeKeyFor(w, h, r),
                                        width: w, height: h, refreshRate: r
                                    });
                                }
                                return result;
                            }

                            model: modeModel
                            currentIndex: {
                                const key = root.currentModeKey(monitorCard.modelData);
                                const idx = modeModel.findIndex(item => item.value === key);
                                return idx !== -1 ? idx : 0;
                            }
                            onActivated: index => {
                                const item = modeModel[index];
                                if (!item) return;
                                root.upsertMonitor(monitorCard.modelData.name, {
                                    width: item.width,
                                    height: item.height,
                                    refreshRate: item.refreshRate
                                });
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 10

                        MaterialSymbol {
                            text: "zoom_in"
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: Translation.tr("Scale")
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        Item { Layout.fillWidth: true }
                        StyledComboBox {
                            id: scaleCombo
                            implicitWidth: 220
                            Layout.fillWidth: false
                            textRole: "displayName"

                            property var scaleModel: {
                                const scales = root.validScalesFor(monitorCard.modelData);
                                return scales.map(s => ({
                                    displayName: root.formatScale(s),
                                    value: s
                                }));
                            }

                            model: scaleModel
                            currentIndex: {
                                const current = root.monitorScale(monitorCard.modelData);
                                let bestIdx = 0, bestD = Infinity;
                                for (let i = 0; i < scaleModel.length; i++) {
                                    const d = Math.abs(scaleModel[i].value - current);
                                    if (d < bestD) { bestD = d; bestIdx = i; }
                                }
                                return bestIdx;
                            }
                            onActivated: index => {
                                const item = scaleModel[index];
                                if (!item) return;
                                root.upsertMonitor(monitorCard.modelData.name, { scale: item.value });
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "workspaces"
        title: Translation.tr("Workspaces")

        ConfigSpinBox {
            icon: "view_column"
            text: Translation.tr("Workspaces per monitor")
            value: Config.options.display.workspaces.perMonitor
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.display.workspaces.perMonitor = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "loop"
            text: Translation.tr("Cycle workspaces")
            checked: Config.options.display.workspaces.cycle
            onCheckedChanged: {
                Config.options.display.workspaces.cycle = checked;
            }
            StyledToolTip {
                text: Translation.tr("If enabled, navigating past the last workspace wraps to the first.\nIf disabled, a new workspace is created.")
            }
        }
    }

    ContentSection {
        icon: "info"
        title: Translation.tr("Detected monitor info")

        Repeater {
            model: HyprlandData.allMonitors || []

            delegate: RowLayout {
                id: infoRow
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 8
                spacing: 12

                MaterialSymbol {
                    text: "monitor"
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: infoRow.modelData.name + (infoRow.modelData.disabled ? Translation.tr(" (disabled)") : "")
                    font.weight: Font.Medium
                    color: infoRow.modelData.disabled ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: `${infoRow.modelData.width}×${infoRow.modelData.height} @ ${root.formatHz(infoRow.modelData.refreshRate)}Hz · ${infoRow.modelData.x},${infoRow.modelData.y} · ${Translation.tr("scale")} ${infoRow.modelData.scale}`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: false
            Layout.topMargin: 6
            Layout.leftMargin: 8
            implicitWidth: 200
            buttonRadius: Appearance.rounding.small
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh monitor list")
            onClicked: HyprlandData.updateMonitors()
        }
    }

    ApplicationWindow {
        id: editor
        title: Translation.tr("Monitor layout")
        visible: root.layoutEditorOpen
        width: 880
        height: 620
        minimumWidth: 600
        minimumHeight: 460
        color: Appearance.m3colors.m3surfaceContainerLow
        onClosing: root.layoutEditorOpen = false

        readonly property int canvasWidth: Math.max(600, width - 80)
        readonly property int canvasHeight: Math.max(360, height - 260)
        readonly property int snapThresholdPx: 30
        readonly property real minZoom: 0.25
        readonly property real maxZoom: 4.0
        property real zoomMultiplier: 1.0
        property string selectedMonitorName: ""
        property int positionsRevision: 0
        property var pendingPositions: ({})

        function effectiveSize(monitor) {
            const s = Math.max(0.0001, root.monitorScale(monitor));
            return { w: monitor.width / s, h: monitor.height / s };
        }

        function zoomIn() {
            editor.zoomMultiplier = Math.min(editor.maxZoom, editor.zoomMultiplier * 1.25);
        }
        function zoomOut() {
            editor.zoomMultiplier = Math.max(editor.minZoom, editor.zoomMultiplier / 1.25);
        }
        function zoomReset() {
            editor.zoomMultiplier = 1.0;
        }

            function activeMonitors() {
                const list = [];
                const detected = HyprlandData.allMonitors || [];
                for (let i = 0; i < detected.length; i++) {
                    if (root.monitorEnabled(detected[i])) list.push(detected[i]);
                }
                return list;
            }

            function getPos(name) {
                if (editor.pendingPositions[name]) return editor.pendingPositions[name];
                const detected = (HyprlandData.allMonitors || []).find(m => m.name === name);
                if (!detected) return { x: 0, y: 0 };
                const p = root.monitorPosition(detected);
                // Clamp existing saved values to the (0, 0) walls.
                return { x: Math.max(0, p.x), y: Math.max(0, p.y) };
            }

            function setPos(name, x, y) {
                // Hard walls: never allow negative coordinates.
                const clampedX = Math.max(0, Math.round(x));
                const clampedY = Math.max(0, Math.round(y));
                const next = Object.assign({}, editor.pendingPositions);
                next[name] = { x: clampedX, y: clampedY };
                editor.pendingPositions = next;
                editor.positionsRevision++;
            }

            function boundsOf(monitors) {
                // Always include the origin (0, 0) so the origin walls stay visible
                // and snappable even when all monitors have been dragged away from it.
                let minX = 0, minY = 0, maxX = 0, maxY = 0;
                for (let i = 0; i < monitors.length; i++) {
                    const m = monitors[i];
                    const p = editor.getPos(m.name);
                    const s = editor.effectiveSize(m);
                    minX = Math.min(minX, p.x);
                    minY = Math.min(minY, p.y);
                    maxX = Math.max(maxX, p.x + s.w);
                    maxY = Math.max(maxY, p.y + s.h);
                }
                if (maxX === minX) maxX = minX + 1;
                if (maxY === minY) maxY = minY + 1;
                return { minX, minY, maxX, maxY };
            }

            function computeScale() {
                const monitors = editor.activeMonitors();
                if (monitors.length === 0) return editor.zoomMultiplier * 0.05;
                const b = editor.boundsOf(monitors);
                const w = b.maxX - b.minX;
                const h = b.maxY - b.minY;
                if (w === 0 || h === 0) return editor.zoomMultiplier * 0.05;
                // Base auto-fit: monitors fill ~40% of the canvas so there is room
                // to drag. zoomMultiplier lets the user zoom in/out on top of that.
                const usable = 0.4;
                const autoScale = Math.min((editor.canvasWidth * usable) / w, (editor.canvasHeight * usable) / h);
                return autoScale * editor.zoomMultiplier;
            }

            function snapToNeighbors(name, x, y) {
                const monitors = editor.activeMonitors();
                const self = monitors.find(m => m.name === name);
                if (!self) return { x: x, y: y };
                const scale = editor.computeScale();
                const threshold = editor.snapThresholdPx / Math.max(scale, 0.0001);

                let bestDx = null, bestDy = null;
                function considerX(d, target) {
                    if (Math.abs(d) < threshold && (bestDx === null || Math.abs(d) < Math.abs(bestDx.d))) {
                        bestDx = { d: d, target: target };
                    }
                }
                function considerY(d, target) {
                    if (Math.abs(d) < threshold && (bestDy === null || Math.abs(d) < Math.abs(bestDy.d))) {
                        bestDy = { d: d, target: target };
                    }
                }

                const ss = editor.effectiveSize(self);
                const myLeft = x, myRight = x + ss.w;
                const myTop = y, myBottom = y + ss.h;

                // Origin walls: snap to x=0 and y=0 (left and top edges of the origin).
                considerX(0 - myLeft, 0);
                considerY(0 - myTop, 0);

                for (let i = 0; i < monitors.length; i++) {
                    const other = monitors[i];
                    if (other.name === name) continue;
                    const op = editor.getPos(other.name);
                    const os = editor.effectiveSize(other);
                    const oLeft = op.x, oRight = op.x + os.w;
                    const oTop = op.y, oBottom = op.y + os.h;

                    considerX(oRight - myLeft, oRight);                     // my-left to other-right
                    considerX(oLeft - myRight, oLeft - ss.w);                // my-right to other-left
                    considerX(oLeft - myLeft, oLeft);                        // align lefts
                    considerX(oRight - myRight, oRight - ss.w);              // align rights

                    considerY(oBottom - myTop, oBottom);
                    considerY(oTop - myBottom, oTop - ss.h);
                    considerY(oTop - myTop, oTop);
                    considerY(oBottom - myBottom, oBottom - ss.h);
                }

                return {
                    x: bestDx !== null ? bestDx.target : x,
                    y: bestDy !== null ? bestDy.target : y
                };
            }

            function applyLayout() {
                const monitors = editor.activeMonitors();
                if (monitors.length === 0) return;
                // Persist exactly what the user set — the origin walls (0, 0) act as
                // the fixed reference, so we do NOT normalize the bounding box here.
                for (let i = 0; i < monitors.length; i++) {
                    const m = monitors[i];
                    const p = editor.getPos(m.name);
                    root.upsertMonitor(m.name, {
                        x: Math.round(p.x),
                        y: Math.round(p.y)
                    });
                }
                editor.pendingPositions = ({});
                editor.positionsRevision++;
            }

            function resetLayout() {
                editor.pendingPositions = ({});
                editor.positionsRevision++;
            }

            ColumnLayout {
                id: editorColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: "open_with"
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Drag monitors to arrange. Edges snap to neighbors.")
                        color: Appearance.colors.colOnSecondaryContainer
                        font.weight: Font.Medium
                    }

                    // Zoom controls
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        enabled: editor.zoomMultiplier > editor.minZoom + 0.001
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "remove"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        onClicked: editor.zoomOut()
                        StyledToolTip { text: Translation.tr("Zoom out") }
                    }
                    StyledText {
                        Layout.minimumWidth: 56
                        horizontalAlignment: Text.AlignHCenter
                        text: `${Math.round(editor.zoomMultiplier * 100)}%`
                        color: Appearance.colors.colOnSecondaryContainer
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editor.zoomReset()
                            StyledToolTip { text: Translation.tr("Reset zoom") }
                        }
                    }
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        enabled: editor.zoomMultiplier < editor.maxZoom - 0.001
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        onClicked: editor.zoomIn()
                        StyledToolTip { text: Translation.tr("Zoom in") }
                    }

                    Item { implicitWidth: 8 }

                    RippleButtonWithIcon {
                        implicitWidth: 100
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Reset")
                        onClicked: editor.resetLayout()
                    }
                    RippleButtonWithIcon {
                        implicitWidth: 110
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "check"
                        mainText: Translation.tr("Apply")
                        onClicked: {
                            editor.applyLayout();
                            root.layoutEditorOpen = false;
                        }
                    }
                    RippleButtonWithIcon {
                        implicitWidth: 100
                        buttonRadius: Appearance.rounding.small
                        materialIcon: "close"
                        mainText: Translation.tr("Close")
                        onClicked: root.layoutEditorOpen = false
                    }
                }

                Rectangle {
                    id: canvas
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: editor.canvasWidth
                    implicitHeight: editor.canvasHeight
                    radius: Appearance.rounding.small
                    color: Appearance.m3colors.m3surfaceContainerLow
                    border.color: Appearance.m3colors.m3outline
                    border.width: 1

                    readonly property var monitors: {
                        editor.positionsRevision;
                        return editor.activeMonitors();
                    }
                    readonly property var bounds: {
                        editor.positionsRevision;
                        return editor.boundsOf(monitors);
                    }
                    readonly property real layoutScale: {
                        editor.positionsRevision;
                        return editor.computeScale();
                    }
                    readonly property real offsetX: (width - (bounds.maxX - bounds.minX) * layoutScale) / 2
                    readonly property real offsetY: (height - (bounds.maxY - bounds.minY) * layoutScale) / 2

                    // Origin "walls" — visualize x=0 and y=0 as snappable reference lines.
                    Rectangle {
                        id: originVertical
                        x: canvas.offsetX + (0 - canvas.bounds.minX) * canvas.layoutScale
                        width: 2
                        y: 0
                        height: canvas.height
                        color: Appearance.colors.colPrimary
                        opacity: 0.45
                        visible: x >= 0 && x <= canvas.width
                    }
                    Rectangle {
                        id: originHorizontal
                        y: canvas.offsetY + (0 - canvas.bounds.minY) * canvas.layoutScale
                        height: 2
                        x: 0
                        width: canvas.width
                        color: Appearance.colors.colPrimary
                        opacity: 0.45
                        visible: y >= 0 && y <= canvas.height
                    }
                    StyledText {
                        anchors.left: originVertical.right
                        anchors.top: originHorizontal.bottom
                        anchors.leftMargin: 4
                        anchors.topMargin: 2
                        visible: originVertical.visible && originHorizontal.visible
                        text: "(0, 0)"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colPrimary
                        opacity: 0.8
                    }

                    Repeater {
                        model: canvas.monitors

                        delegate: Rectangle {
                            id: monitorRect
                            required property var modelData
                            required property int index

                            readonly property var pos: {
                                editor.positionsRevision;
                                return editor.getPos(modelData.name);
                            }
                            readonly property var effSize: {
                                editor.positionsRevision;
                                return editor.effectiveSize(modelData);
                            }
                            readonly property real scaleFactor: {
                                editor.positionsRevision;
                                return root.monitorScale(modelData);
                            }
                            readonly property bool selected: editor.selectedMonitorName === modelData.name

                            x: canvas.offsetX + (pos.x - canvas.bounds.minX) * canvas.layoutScale
                            y: canvas.offsetY + (pos.y - canvas.bounds.minY) * canvas.layoutScale
                            width: effSize.w * canvas.layoutScale
                            height: effSize.h * canvas.layoutScale
                            radius: 4
                            color: dragArea.drag.active
                                ? Appearance.colors.colPrimaryHover
                                : (selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer)
                            border.color: Appearance.colors.colPrimary
                            border.width: (dragArea.drag.active || selected) ? 3 : 1
                            z: dragArea.drag.active ? 10 : (selected ? 5 : 1)

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                            Behavior on width {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on height {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: monitorRect.modelData.name
                                    color: Appearance.colors.colOnSecondaryContainer
                                    font.weight: Font.Medium
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: `${monitorRect.modelData.width}×${monitorRect.modelData.height}`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: `(${monitorRect.pos.x}, ${monitorRect.pos.y}) · ${Math.round(monitorRect.scaleFactor * 1000) / 10}%`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                cursorShape: Qt.SizeAllCursor
                                drag.target: monitorRect
                                drag.axis: Drag.XAndYAxis
                                // Hard walls: the origin lines (x=0, y=0) act as the left/top
                                // boundary the monitor rectangle cannot cross.
                                drag.minimumX: canvas.offsetX + (0 - canvas.bounds.minX) * canvas.layoutScale
                                drag.maximumX: canvas.width - monitorRect.width
                                drag.minimumY: canvas.offsetY + (0 - canvas.bounds.minY) * canvas.layoutScale
                                drag.maximumY: canvas.height - monitorRect.height
                                onPressed: editor.selectedMonitorName = monitorRect.modelData.name
                                onReleased: {
                                    const scale = canvas.layoutScale;
                                    if (scale <= 0) return;
                                    const screenX = (monitorRect.x - canvas.offsetX) / scale + canvas.bounds.minX;
                                    const screenY = (monitorRect.y - canvas.offsetY) / scale + canvas.bounds.minY;
                                    const snapped = editor.snapToNeighbors(monitorRect.modelData.name, screenX, screenY);
                                    editor.setPos(monitorRect.modelData.name, Math.max(0, snapped.x), Math.max(0, snapped.y));
                                }
                            }
                        }
                    }
                }

                // Selection panel — shows scale spinbox for the selected monitor.
                Rectangle {
                    id: selectionPanel
                    Layout.fillWidth: true
                    implicitHeight: selectionRow.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    readonly property var selected: {
                        editor.positionsRevision;
                        const name = editor.selectedMonitorName;
                        if (!name) return null;
                        return (HyprlandData.allMonitors || []).find(m => m.name === name) || null;
                    }

                    RowLayout {
                        id: selectionRow
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        MaterialSymbol {
                            text: "ads_click"
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: selectionPanel.selected
                                ? Translation.tr("Selected: %1 (%2×%3)").arg(selectionPanel.selected.name).arg(selectionPanel.selected.width).arg(selectionPanel.selected.height)
                                : Translation.tr("Click a monitor to select it and adjust its scale")
                            color: Appearance.colors.colOnSecondaryContainer
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: selectionPanel.selected !== null
                            text: Translation.tr("Scale")
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledComboBox {
                            id: editorScaleCombo
                            visible: selectionPanel.selected !== null
                            implicitWidth: 220
                            Layout.fillWidth: false
                            textRole: "displayName"

                            property var scaleModel: {
                                if (!selectionPanel.selected) return [];
                                const scales = root.validScalesFor(selectionPanel.selected);
                                return scales.map(s => ({
                                    displayName: root.formatScale(s),
                                    value: s
                                }));
                            }

                            model: scaleModel
                            currentIndex: {
                                if (!selectionPanel.selected || scaleModel.length === 0) return 0;
                                const current = root.monitorScale(selectionPanel.selected);
                                let bestIdx = 0, bestD = Infinity;
                                for (let i = 0; i < scaleModel.length; i++) {
                                    const d = Math.abs(scaleModel[i].value - current);
                                    if (d < bestD) { bestD = d; bestIdx = i; }
                                }
                                return bestIdx;
                            }
                            onActivated: index => {
                                const sel = selectionPanel.selected;
                                const item = scaleModel[index];
                                if (!sel || !item) return;
                                root.upsertMonitor(sel.name, { scale: item.value });
                                editor.positionsRevision++;
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: Translation.tr("Drag against the (0, 0) walls or other monitors — edges snap automatically. Use +/- to zoom the editor. Click a monitor to change its scale: higher scale = smaller virtual size.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
    }
}
