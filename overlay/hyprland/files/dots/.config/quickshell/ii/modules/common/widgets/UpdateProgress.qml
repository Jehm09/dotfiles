import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Loader de `setup update system --background`: paso actual, última línea del log, tiempo
// y la cuenta regresiva de apagado/reinicio con su botón para cancelar. Lo usan Settings → Update
// y la pantalla de sesión. Visible solo mientras SystemUpdates.busy.
ColumnLayout {
    id: root
    visible: SystemUpdates.busy
    spacing: 8

    readonly property string then: SystemUpdates.lastRun?.state === "running" || SystemUpdates.powerPending
        ? (SystemUpdates.lastRun?.then ?? "") : SystemUpdates.pendingThen
    readonly property string powerLabel: then === "windows" ? Translation.tr("Rebooting into Windows")
        : then === "reboot" ? Translation.tr("Rebooting") : Translation.tr("Shutting down")
    readonly property string cancelLabel: then === "windows" ? Translation.tr("Don't reboot into Windows")
        : then === "reboot" ? Translation.tr("Don't reboot") : Translation.tr("Don't shut down")
    property int elapsed: 0

    function formatElapsed(seconds) {
        const m = Math.floor(seconds / 60);
        const s = seconds % 60;
        return m > 0 ? `${m} min ${s} s` : `${s} s`;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: {
            const started = Date.parse(SystemUpdates.lastRun?.started ?? "");
            root.elapsed = SystemUpdates.running && !isNaN(started) ? Math.max(0, Math.floor((Date.now() - started) / 1000)) : 0;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignVCenter
            implicitSize: 44
            loading: root.visible
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                text: SystemUpdates.powerPending
                    ? Translation.tr("%1 in %2 s").arg(root.powerLabel).arg(SystemUpdates.powerSecondsLeft)
                    : Translation.tr("Updating the system…")
            }
            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                text: {
                    if (SystemUpdates.powerPending) return SystemUpdates.lastRun?.message ?? "";
                    if (!SystemUpdates.running) return Translation.tr("Starting…");
                    let line = Translation.tr("Step: %1 · %2").arg(SystemUpdates.currentStep).arg(root.formatElapsed(root.elapsed));
                    if (root.then && !SystemUpdates.powerCancelled)
                        line += "\n" + Translation.tr("%1 when it finishes (only if it succeeds)").arg(root.powerLabel);
                    return line;
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: SystemUpdates.running && SystemUpdates.logTail !== ""
        text: SystemUpdates.logTail
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    StyledIndeterminateProgressBar {
        Layout.fillWidth: true
        visible: !SystemUpdates.powerPending
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: 8

        RippleButtonWithIcon {
            visible: !!SystemUpdates.lastRun?.log && SystemUpdates.running
            buttonRadius: Appearance.rounding.small
            materialIcon: "description"
            mainText: Translation.tr("Open log")
            onClicked: SystemUpdates.openLog()
        }
        RippleButtonWithIcon {
            visible: !!root.then && !SystemUpdates.powerCancelled
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colPrimaryContainer
            materialIcon: "cancel"
            mainText: root.cancelLabel
            onClicked: SystemUpdates.cancelPower()
        }
    }
}
