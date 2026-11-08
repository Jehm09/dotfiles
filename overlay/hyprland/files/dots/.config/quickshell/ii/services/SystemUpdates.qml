pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Paquetes por actualizar (repos + AUR), noticias de Arch, reinicio pendiente y .pacnew,
 * vía `setup update system --status`; más el resultado de la última corrida (system-update.json).
 * Lo usan el indicador de la barra, la pantalla de sesión y Settings → Update.
 */
Singleton {
    id: root

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || `${homeDir}/.local/share`
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || `${homeDir}/.local/state`
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    // Lo escribe cmd/lib/upstream.sh, así la ruta del repo no queda fija acá.
    readonly property string repoDirFile: `${dataHome}/dotfiles/upstream/.git/dotfiles-repo-dir`
    readonly property string lastRunFile: `${stateHome}/dotfiles/system-update.json`
    readonly property string runLockFile: `${runtimeDir}/dotfiles-system-update.lock`
    // system-update.sh lo busca durante la cuenta regresiva de apagado/reinicio.
    readonly property string cancelPowerFile: `${runtimeDir}/dotfiles-system-update.cancel-power`

    property string repoDir: ""
    readonly property string setupPath: repoDir ? `${repoDir}/setup` : ""
    property var status: null
    property string error: ""
    property var lastRun: null
    property bool lockAlive: false
    // idle | checking | wrong | failed — estado del cuadro de contraseña de sudo
    property string authState: "idle"
    property string pendingThen: ""
    property string passFile: ""
    property string password: ""
    // La corrida ya arrancó con la contraseña: quien mostró el cuadro lo cierra.
    signal launched

    readonly property bool checking: statusProc.running
    // Entre lanzar el script y que escriba "running" en el state file (~1 s).
    property bool starting: false
    property real launchedAt: 0
    // El state file dice "running" para siempre si el proceso murió a mitad: manda el lock.
    readonly property bool running: (lastRun?.state === "running") && lockAlive
    // Cuenta regresiva para apagar/reiniciar al terminar: epoch en segundos, 0 = no hay.
    readonly property int powerAt: lastRun?.powerAt ?? 0
    readonly property bool powerPending: powerAt > 0 && lockAlive
    property int powerSecondsLeft: 0
    // Se pidió no apagar/reiniciar: vale durante la corrida o en la cuenta regresiva.
    property bool powerCancelled: false
    // Lo que muestra el loader mientras corre: el paso y la última línea del log.
    readonly property bool busy: starting || running || powerPending
    readonly property string currentStep: lastRun?.state === "running" ? (lastRun?.step ?? "") : ""
    property string logTail: ""
    readonly property var repoPackages: status?.repo?.packages ?? []
    readonly property var aurPackages: status?.aur?.packages ?? []
    readonly property int count: repoPackages.length + aurPackages.length
    // Solo con los dos chequeos OK: si uno falló (offline) no se sabe, y se deja actualizar.
    readonly property bool upToDate: (status?.repo?.checked ?? false) && (status?.aur?.checked ?? false) && count === 0
    readonly property var news: status?.news ?? []
    readonly property var rebootReasons: status?.rebootReasons ?? []
    readonly property bool rebootNeeded: rebootReasons.length > 0
    readonly property var pacnew: status?.pacnew ?? []
    readonly property var ignored: status?.ignored ?? []
    readonly property bool packageManagerRunning: status?.packageManagerRunning ?? false

    function load() {}

    function refresh() {
        if (!root.setupPath || statusProc.running) return;
        root.error = "";
        statusProc.running = true;
    }

    function resetAuth() {
        if (!authProc.running) root.authState = "idle";
    }

    // then: "", "poweroff", "reboot" o "windows". Valida la contraseña con sudo antes de lanzar,
    // así un error se corrige en el cuadro.
    function startUpdate(then, password) {
        if (!root.setupPath || root.running || authProc.running) return false;
        root.pendingThen = then ?? "";
        root.passFile = `${root.runtimeDir}/dotfiles-sudo-${Date.now()}`;
        root.password = password;
        root.authState = "checking";
        authProc.stdinEnabled = true;
        authProc.running = true;
        return true;
    }

    // Sin terminal: la salida va solo al log y el progreso se ve en el loader (UpdateProgress).
    // Desacoplado de quickshell, así sigue aunque se cierre Settings o se reinicie la barra.
    function launchRun() {
        const args = [root.setupPath, "update", "system", "--background", "--sudo-pass-file", root.passFile];
        if (root.pendingThen) args.push("--then", root.pendingThen);
        Quickshell.execDetached(["setsid", "-f", "bash", "-c", 'exec "$@" >/dev/null 2>&1 </dev/null', "bash", ...args]);
        root.logTail = "";
        root.launchedAt = Date.now();
        root.powerCancelled = false;
        root.starting = true;
        startingTimeout.restart();
        passFileCleanup.restart();
    }

    function cancelPower() {
        if (!root.busy) return;
        Quickshell.execDetached(["touch", root.cancelPowerFile]);
        root.powerCancelled = true;
    }

    function openLog() {
        if (!root.lastRun?.log) return;
        Quickshell.execDetached(["kitty", "-1", "--title", "System update log", "less", "-R", "+G", root.lastRun.log]);
    }

    function mergePacnew() {
        Quickshell.execDetached(["kitty", "-1", "--hold=yes", "--title", "pacdiff", "sudo", "pacdiff"]);
    }

    FileView {
        path: root.repoDirFile
        onLoaded: {
            root.repoDir = text().trim();
            root.refresh();
        }
        onLoadFailed: root.repoDir = ""
    }

    // Agregar/sacar un IgnorePkg cambia los pendientes: no esperar al próximo chequeo.
    FileView {
        path: "/etc/pacman.conf"
        watchChanges: true
        onFileChanged: root.refresh()
    }

    FileView {
        path: root.lastRunFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const previous = root.lastRun?.state;
                root.lastRun = JSON.parse(text());
                // Una corrida que falla al instante (preflight) termina antes de que se vea el lock.
                if (root.starting && root.lastRun.state !== "running"
                        && Date.parse(root.lastRun.started) >= root.launchedAt - 5000) root.starting = false;
                if (root.lastRun.state === "running" || (root.lastRun.powerAt ?? 0) > 0) lockProc.running = true;
                // Al terminar una corrida cambian los paquetes pendientes.
                else if (previous === "running") root.refresh();
            } catch (e) {
                root.lastRun = null;
            }
        }
        onLoadFailed: root.lastRun = null
    }

    Process {
        id: statusProc
        command: [root.setupPath, "update", "system", "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.status = JSON.parse(text);
                } catch (e) {
                    root.error = "Could not read the update status";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.error = `Status check failed (exit code ${exitCode})`;
        }
    }

    // La contraseña entra solo por stdin: sudo -k la valida (ignora lo cacheado) y queda en un
    // archivo 0600 de $XDG_RUNTIME_DIR que el script lee y borra al arrancar. exit 3 = incorrecta.
    Process {
        id: authProc
        command: ["bash", "-c",
            'IFS= read -r pw; printf "%s\\n" "$pw" | sudo -k -S -p "" -v 2>/dev/null || exit 3; umask 077; printf "%s" "$pw" > "$1"',
            "bash", root.passFile]
        onRunningChanged: {
            if (!running) return;
            write(root.password + "\n");
            root.password = "";
            stdinEnabled = false;
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.authState = "idle";
                root.launchRun();
                root.launched();
            } else {
                root.authState = exitCode === 3 ? "wrong" : "failed";
            }
        }
    }

    // Por si el script no llegó a arrancar: el archivo con la contraseña no queda dando vueltas
    // (el script lo mueve a su propia carpeta al empezar, así que esto no le afecta).
    Timer {
        id: passFileCleanup
        interval: 60 * 1000
        onTriggered: Quickshell.execDetached(["rm", "-f", "--", root.passFile])
    }

    // flock -n falla (≠0) mientras una corrida tiene el lock tomado.
    Process {
        id: lockProc
        command: ["flock", "-n", root.runLockFile, "true"]
        onExited: (exitCode, exitStatus) => {
            root.lockAlive = exitCode !== 0;
            if (root.lockAlive) root.starting = false;
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.lastRun?.state === "running" || root.powerAt > 0
        onTriggered: lockProc.running = true
    }

    // Si el script no escribe "running" a tiempo (falló al arrancar), el loader no queda colgado.
    Timer {
        id: startingTimeout
        interval: 20 * 1000
        onTriggered: root.starting = false
    }

    Timer {
        interval: 250
        repeat: true
        running: root.powerPending
        triggeredOnStart: true
        onTriggered: root.powerSecondsLeft = Math.max(0, Math.ceil(root.powerAt - Date.now() / 1000))
    }

    // Última línea con texto del log: sin colores ni las barras de progreso de pacman (\r).
    Process {
        id: tailProc
        command: ["bash", "-c", 'tail -c 4096 -- "$1" | tr "\\r" "\\n" | sed "s/\\x1b\\[[0-9;]*[A-Za-z]//g" | grep -v "^[[:space:]]*$" | tail -n 1', "bash", root.lastRun?.log ?? ""]
        stdout: StdioCollector {
            onStreamFinished: root.logTail = text.trim()
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running && !!root.lastRun?.log
        triggeredOnStart: true
        onTriggered: if (!tailProc.running) tailProc.running = true
    }

    Timer {
        interval: Math.max(1, Config.options.updates.checkInterval) * 60 * 1000
        repeat: true
        running: Config.ready && Config.options.updates.enableCheck && root.setupPath !== ""
        onTriggered: root.refresh()
    }
}
