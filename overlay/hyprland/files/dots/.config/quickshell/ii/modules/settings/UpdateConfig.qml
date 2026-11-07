import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Paquetes del sistema (`setup update system`, vía SystemUpdates) y end-4
// (`setup update shell`: merge + commit + runtime + push). Ambos corren en kitty
// para que sudo pida la contraseña; esta página muestra el estado y la última corrida.
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

    property bool showPackages: false
    property bool askingSudoPassword: false

    Connections {
        target: SystemUpdates
        function onLaunched() {
            page.askingSudoPassword = false;
        }
    }

    function packageLine(pkg) {
        return `${pkg.name}  ${pkg.from} → ${pkg.to}`;
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

    // quickshell es el único paquete que end-4 fija a un commit; el resto va por pacman/yay.
    readonly property string runtimeText: {
        if (!status?.ok) return "…";
        const installed = `${shortSha(status.installedPin)} (${status.installedVersion})`;
        switch (status.runtime) {
        case "ok": return installed;
        case "stale": return Translation.tr("%1 — rebuild needed, your merged end-4 pins %2").arg(installed).arg(shortSha(status.pinned));
        case "abi": return Translation.tr("%1 — rebuild needed, it no longer loads with the installed Qt").arg(installed);
        default: return Translation.tr("Installed build is not tracked — Update will rebuild it");
        }
    }

    readonly property string upstreamPinText: {
        if (!status?.ok || !status.upstreamPin) return "…";
        const pin = shortSha(status.upstreamPin);
        const suffix = status.fetched ? "" : ` ${Translation.tr("(last known)")}`;
        if (status.upstreamPin === status.installedPin) return Translation.tr("%1 — same as installed").arg(pin) + suffix;
        return Translation.tr("%1 — different from installed, Update installs it").arg(pin) + suffix;
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

    component LastRunRows: ColumnLayout {
        id: lastRunRows
        property var run: null
        property bool alive: false
        Layout.fillWidth: true
        spacing: 4

        function formatTime(iso) {
            return iso ? new Date(iso).toLocaleString(Qt.locale(), Locale.ShortFormat) : "";
        }

        StyledText {
            visible: !lastRunRows.run
            text: Translation.tr("No update has run from here yet.")
            color: Appearance.colors.colSubtext
        }
        InfoRow {
            visible: !!lastRunRows.run
            icon: {
                switch (lastRunRows.run?.state) {
                case "ok": return "check_circle";
                case "warning": return "warning";
                case "conflict": return "merge";
                case "running": return lastRunRows.alive ? "hourglass_top" : "cancel";
                default: return "error";
                }
            }
            label: {
                switch (lastRunRows.run?.state) {
                case "ok": return Translation.tr("Finished");
                case "warning": return Translation.tr("With warnings");
                case "conflict": return Translation.tr("Conflicts");
                case "running": return lastRunRows.alive ? Translation.tr("Running") : Translation.tr("Interrupted");
                default: return Translation.tr("Failed");
                }
            }
            value: lastRunRows.run?.state === "running"
                ? (lastRunRows.alive ? Translation.tr("Step: %1").arg(lastRunRows.run.step) : Translation.tr("The terminal was closed during: %1").arg(lastRunRows.run.step))
                : (lastRunRows.run?.message ?? "")
        }
        InfoRow {
            visible: !!lastRunRows.run
            icon: "schedule"
            label: Translation.tr("When")
            value: lastRunRows.run?.finished
                ? Translation.tr("%1 → %2").arg(lastRunRows.formatTime(lastRunRows.run.started)).arg(lastRunRows.formatTime(lastRunRows.run.finished))
                : lastRunRows.formatTime(lastRunRows.run?.started)
        }
    }

    ContentSection {
        icon: "inventory_2"
        title: Translation.tr("System packages")

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemUpdates.error !== ""
            materialIcon: "error"
            text: SystemUpdates.error
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: SystemUpdates.checking || SystemUpdates.running
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemUpdates.rebootNeeded
            materialIcon: "restart_alt"
            text: Translation.tr("Reboot to finish the last update:") + "\n" + SystemUpdates.rebootReasons.join("\n")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemUpdates.news.length > 0
            materialIcon: "newspaper"
            text: Translation.tr("Arch news newer than your packages — some ask for manual steps before updating:") + "\n" + SystemUpdates.news.join("\n")

            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.small
                materialIcon: "open_in_new"
                mainText: Translation.tr("Read")
                onClicked: Qt.openUrlExternally("https://archlinux.org/news/")
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemUpdates.packageManagerRunning && !SystemUpdates.running
            materialIcon: "lock"
            text: Translation.tr("pacman is running (or left /var/lib/pacman/db.lck behind) — Update is disabled until it finishes.")
        }

        InfoRow {
            icon: "deployed_code"
            label: Translation.tr("Repos")
            value: {
                const repo = SystemUpdates.status?.repo;
                if (!repo) return "…";
                if (!repo.checked) return repo.error;
                return repo.packages.length > 0 ? Translation.tr("%1 update(s)").arg(repo.packages.length) : Translation.tr("Up to date");
            }
        }
        InfoRow {
            icon: "package_2"
            label: SystemUpdates.status?.helper ? Translation.tr("AUR (%1)").arg(SystemUpdates.status.helper) : Translation.tr("AUR")
            value: {
                const aur = SystemUpdates.status?.aur;
                if (!aur) return "…";
                if (!aur.checked) return aur.error;
                return aur.packages.length > 0 ? Translation.tr("%1 update(s)").arg(aur.packages.length) : Translation.tr("Up to date");
            }
        }
        InfoRow {
            icon: "difference"
            label: Translation.tr(".pacnew")
            value: SystemUpdates.pacnew.length > 0
                ? Translation.tr("%1 config file(s) to merge:").arg(SystemUpdates.pacnew.length) + "\n" + SystemUpdates.pacnew.join("\n")
                : Translation.tr("None")
        }
        // IgnorePkg de /etc/pacman.conf: a la vista para acordarse de sacarlos.
        InfoRow {
            visible: SystemUpdates.ignored.length > 0
            icon: "block"
            label: Translation.tr("Ignored")
            value: SystemUpdates.ignored.join("\n") + "\n" + Translation.tr("(IgnorePkg in /etc/pacman.conf)")
        }
        InfoRow {
            icon: "update"
            label: Translation.tr("Checked")
            value: SystemUpdates.status?.checkedAt ? page.formatTime(SystemUpdates.status.checkedAt) : "…"
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: page.showPackages && SystemUpdates.count > 0
            spacing: 2

            Repeater {
                model: [
                    ...SystemUpdates.repoPackages.map(pkg => page.packageLine(pkg)),
                    ...SystemUpdates.aurPackages.map(pkg => `${page.packageLine(pkg)}  (AUR)`)
                ]
                StyledText {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    text: modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8

            RippleButtonWithIcon {
                implicitWidth: 120
                buttonRadius: Appearance.rounding.small
                materialIcon: "refresh"
                mainText: Translation.tr("Check")
                enabled: SystemUpdates.setupPath !== "" && !SystemUpdates.checking
                onClicked: SystemUpdates.refresh()
            }
            RippleButtonWithIcon {
                implicitWidth: 140
                buttonRadius: Appearance.rounding.small
                materialIcon: SystemUpdates.running ? "hourglass_top" : "system_update_alt"
                mainText: SystemUpdates.running ? Translation.tr("Running…")
                    : SystemUpdates.upToDate ? Translation.tr("Up to date") : Translation.tr("Update")
                enabled: SystemUpdates.setupPath !== "" && !SystemUpdates.running && !SystemUpdates.packageManagerRunning
                    && !SystemUpdates.upToDate && !SystemUpdates.checking
                colBackground: SystemUpdates.count > 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                onClicked: {
                    SystemUpdates.resetAuth();
                    page.askingSudoPassword = true;
                    sudoPrompt.focusField();
                }
                StyledToolTip {
                    text: SystemUpdates.upToDate ? Translation.tr("Nothing to update")
                        : Translation.tr("Opens a terminal and runs the update without questions; rebuilds quickshell if the new Qt broke it")
                }
            }
            RippleButtonWithIcon {
                visible: SystemUpdates.count > 0
                implicitWidth: 170
                buttonRadius: Appearance.rounding.small
                materialIcon: page.showPackages ? "expand_less" : "expand_more"
                mainText: page.showPackages ? Translation.tr("Hide packages") : Translation.tr("Show %1 package(s)").arg(SystemUpdates.count)
                onClicked: page.showPackages = !page.showPackages
            }
            RippleButtonWithIcon {
                visible: SystemUpdates.pacnew.length > 0
                implicitWidth: 170
                buttonRadius: Appearance.rounding.small
                materialIcon: "merge"
                mainText: Translation.tr("Merge .pacnew")
                onClicked: SystemUpdates.mergePacnew()
                StyledToolTip {
                    text: Translation.tr("Opens `sudo pacdiff` in a terminal (needs pacman-contrib)")
                }
            }
        }

        SudoPasswordPrompt {
            id: sudoPrompt
            visible: page.askingSudoPassword && !SystemUpdates.upToDate
            Layout.topMargin: 4
            confirmText: Translation.tr("Update")
            busy: SystemUpdates.authState === "checking"
            errorText: SystemUpdates.authState === "wrong" ? Translation.tr("Wrong password")
                : SystemUpdates.authState === "failed" ? Translation.tr("Could not check the password")
                : ""
            onSubmitted: password => SystemUpdates.startUpdate("", password)
            onCancelled: page.askingSudoPassword = false
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: Translation.tr("Update asks for your password here and answers nothing else in the terminal: if something needs a decision (a file conflict, a package replacement) it fails and is logged instead of waiting. To answer by hand, run `setup update system` in a terminal.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }

    ContentSection {
        icon: "history"
        title: Translation.tr("Last system update")

        LastRunRows {
            run: SystemUpdates.lastRun
            alive: SystemUpdates.running
        }
        InfoRow {
            visible: !!SystemUpdates.lastRun?.then
            icon: SystemUpdates.lastRun?.then === "reboot" ? "restart_alt" : "power_settings_new"
            label: Translation.tr("Then")
            value: {
                const run = SystemUpdates.lastRun;
                const action = run?.then === "reboot" ? Translation.tr("reboot") : Translation.tr("shut down");
                if (run?.state === "ok" || run?.state === "warning") return Translation.tr("Started from the session screen to %1 afterwards").arg(action);
                if (run?.state === "running") return Translation.tr("Will %1 when it finishes").arg(action);
                return Translation.tr("Did not %1 because the update failed").arg(action);
            }
        }
        RippleButtonWithIcon {
            visible: !!SystemUpdates.lastRun?.log
            Layout.topMargin: 6
            implicitWidth: 140
            buttonRadius: Appearance.rounding.small
            materialIcon: "description"
            mainText: Translation.tr("Open log")
            onClicked: SystemUpdates.openLog()
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
            icon: "push_pin"
            label: Translation.tr("end-4 pins")
            value: page.upstreamPinText
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
        title: Translation.tr("Last end-4 update")

        LastRunRows {
            run: page.lastRun
            alive: page.running
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
