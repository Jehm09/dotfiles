import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Actualiza end-4 con `setup update shell` (merge + commit + runtime + push).
// Corre en kitty para que sudo pueda pedir la contraseña; esta página solo
// muestra el estado (`--status`) y el resultado de la última ejecución.
ContentPage {
    id: page
    forceWidth: true

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || `${homeDir}/.local/share`
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || `${homeDir}/.local/state`
    // Lo escribe cmd/lib/upstream.sh, así la ruta del repo no queda fija acá.
    readonly property string repoDirFile: `${dataHome}/dotfiles/upstream/.git/dotfiles-repo-dir`
    readonly property string lastRunFile: `${stateHome}/dotfiles/shell-update.json`

    property string repoDir: ""
    readonly property string setupPath: repoDir ? `${repoDir}/setup` : ""
    property var status: null
    property string statusError: ""
    property var lastRun: null

    readonly property bool running: status?.running ?? false
    readonly property bool checking: statusProc.running

    function refresh() {
        if (!page.setupPath || statusProc.running) return;
        page.statusError = "";
        statusProc.running = true;
    }

    function startUpdate() {
        if (!page.setupPath || page.running) return;
        Quickshell.execDetached(["kitty", "-1", "--hold=yes", "--title", "Update end-4",
            page.setupPath, "update", "shell"]);
        runningPoll.start();
    }

    function openLog() {
        if (!page.lastRun?.log) return;
        Quickshell.execDetached(["kitty", "-1", "--title", "end-4 update log",
            "less", "-R", "+G", page.lastRun.log]);
    }

    function shortSha(sha) {
        return sha ? sha.substring(0, 7) : "…";
    }

    function formatTime(iso) {
        if (!iso) return "";
        return new Date(iso).toLocaleString(Qt.locale(), Locale.ShortFormat);
    }

    readonly property string upstreamText: {
        if (!status?.ok) return "…";
        if (!status.fetched) return Translation.tr("Could not reach end-4 (offline?)");
        if (status.behind > 0) return Translation.tr("%1 new commit(s) available (%2)").arg(status.behind).arg(status.upstreamHead);
        return Translation.tr("Up to date (%1)").arg(status.upstreamHead);
    }

    readonly property string runtimeText: {
        if (!status?.ok) return "…";
        switch (status.runtime) {
        case "ok": return Translation.tr("Current: %1 (%2)").arg(shortSha(status.installedPin)).arg(status.installedVersion);
        case "stale": return Translation.tr("Rebuild needed: pinned %1, installed %2").arg(shortSha(status.pinned)).arg(shortSha(status.installedPin));
        case "abi": return Translation.tr("Rebuild needed: it no longer loads with the installed Qt");
        default: return Translation.tr("Installed build is not tracked — Update will rebuild it");
        }
    }

    readonly property bool updateAdvised: (status?.ok ?? false)
        && (status.behind > 0 || status.runtime !== "ok" || status.dirty)

    Component.onCompleted: repoDirView.reload()

    FileView {
        id: repoDirView
        path: page.repoDirFile
        onLoaded: {
            page.repoDir = text().trim();
            page.refresh();
        }
        onLoadFailed: page.repoDir = ""
    }

    FileView {
        id: lastRunView
        path: page.lastRunFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const previous = page.lastRun?.state;
                page.lastRun = JSON.parse(text());
                // Al terminar una ejecución, el estado (versiones, pin) cambió.
                if (previous === "running" && page.lastRun.state !== "running") page.refresh();
            } catch (e) {
                page.lastRun = null;
            }
        }
        onLoadFailed: page.lastRun = null
    }

    Process {
        id: statusProc
        command: [page.setupPath, "update", "shell", "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.status = JSON.parse(text);
                } catch (e) {
                    page.statusError = Translation.tr("Could not read the update status");
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) page.statusError = Translation.tr("Status check failed (exit code %1)").arg(exitCode);
        }
    }

    // Mientras kitty corre, el lock dice si sigue vivo: refresca hasta que termine.
    Timer {
        id: runningPoll
        interval: 3000
        repeat: true
        onTriggered: {
            if (!page.running && !page.checking && (page.lastRun?.state ?? "running") !== "running") stop();
            else page.refresh();
        }
    }

    component InfoRow: RowLayout {
        property string icon
        property string label
        property string value
        Layout.fillWidth: true
        spacing: 10

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: parent.icon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: 110
            text: parent.label
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            text: parent.value
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        icon: "system_update_alt"
        title: Translation.tr("end-4 shell")

        NoticeBox {
            Layout.fillWidth: true
            visible: !page.repoDir
            materialIcon: "warning"
            text: Translation.tr("The dotfiles repo was not found. Run `setup upstream status` once from the repo so this page can find it.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: page.statusError !== ""
            materialIcon: "error"
            text: page.statusError
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: page.checking || page.running
        }

        InfoRow {
            icon: "folder"
            label: Translation.tr("Repository")
            value: page.repoDir || "…"
        }
        InfoRow {
            icon: "lock"
            label: Translation.tr("Installed")
            value: page.status?.ok ? Translation.tr("end-4 %1").arg(page.shortSha(page.status.locked)) : "…"
        }
        InfoRow {
            icon: "cloud_download"
            label: Translation.tr("end-4")
            value: page.upstreamText
        }
        InfoRow {
            icon: "memory"
            label: Translation.tr("quickshell")
            value: page.runtimeText
        }
        InfoRow {
            visible: page.status?.dirty || page.status?.merging || false
            icon: "edit_note"
            label: Translation.tr("Local edits")
            value: page.status?.merging
                ? Translation.tr("A merge is in progress in the clone — finish or abort it before updating")
                : Translation.tr("Unsaved edits in the clone — Update commits them first")
        }

        RowLayout {
            Layout.topMargin: 6
            spacing: 8

            RippleButtonWithIcon {
                implicitWidth: 120
                buttonRadius: Appearance.rounding.small
                materialIcon: "refresh"
                mainText: Translation.tr("Check")
                enabled: page.setupPath !== "" && !page.checking
                onClicked: page.refresh()
            }
            RippleButtonWithIcon {
                implicitWidth: 140
                buttonRadius: Appearance.rounding.small
                materialIcon: page.running ? "hourglass_top" : "system_update_alt"
                mainText: page.running ? Translation.tr("Running…") : Translation.tr("Update")
                enabled: page.setupPath !== "" && !page.running && !(page.status?.merging ?? false)
                colBackground: page.updateAdvised ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                onClicked: page.startUpdate()
                StyledToolTip {
                    text: Translation.tr("Opens a terminal: merges end-4, commits overlay/, rebuilds quickshell if needed, restarts the bar and pushes")
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: Translation.tr("If end-4 changed a file you also customized, the merge is aborted and nothing changes; the clashing files are listed below so you can merge them by hand.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }

    ContentSection {
        icon: "history"
        title: Translation.tr("Last run")

        StyledText {
            visible: !page.lastRun
            text: Translation.tr("No update has run from here yet.")
            color: Appearance.colors.colSubtext
        }

        InfoRow {
            visible: !!page.lastRun
            icon: {
                switch (page.lastRun?.state) {
                case "ok": return "check_circle";
                case "conflict": return "merge";
                case "running": return page.running ? "hourglass_top" : "cancel";
                default: return "error";
                }
            }
            label: {
                switch (page.lastRun?.state) {
                case "ok": return Translation.tr("Finished");
                case "conflict": return Translation.tr("Conflicts");
                case "running": return page.running ? Translation.tr("Running") : Translation.tr("Interrupted");
                default: return Translation.tr("Failed");
                }
            }
            value: page.lastRun?.state === "running"
                ? (page.running ? Translation.tr("Step: %1").arg(page.lastRun.step) : Translation.tr("The terminal was closed during: %1").arg(page.lastRun.step))
                : (page.lastRun?.message ?? "")
        }
        InfoRow {
            visible: !!page.lastRun
            icon: "schedule"
            label: Translation.tr("When")
            value: page.lastRun?.finished
                ? Translation.tr("%1 → %2").arg(page.formatTime(page.lastRun.started)).arg(page.formatTime(page.lastRun.finished))
                : page.formatTime(page.lastRun?.started)
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: (page.lastRun?.files?.length ?? 0) > 0
            spacing: 2

            StyledText {
                text: Translation.tr("Files that clash with your changes:")
                color: Appearance.colors.colOnLayer1
            }
            Repeater {
                model: page.lastRun?.files ?? []
                StyledText {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    text: modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: Translation.tr("To merge by hand: run `setup upstream update` in the repo, fix the conflict markers, `git merge --continue` in the clone, then `setup upstream export`.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        RippleButtonWithIcon {
            visible: !!page.lastRun?.log
            Layout.topMargin: 6
            implicitWidth: 140
            buttonRadius: Appearance.rounding.small
            materialIcon: "description"
            mainText: Translation.tr("Open log")
            onClicked: page.openLog()
        }
    }
}
