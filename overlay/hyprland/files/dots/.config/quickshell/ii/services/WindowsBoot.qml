pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Reiniciar a Windows una sola vez (UEFI BootNext; el arranque siguiente vuelve a GRUB).
 * Lo usa la pantalla de sesión; sin una entrada "Windows Boot Manager" el botón no aparece.
 */
Singleton {
    id: root

    // Número de la entrada UEFI (p. ej. "0002"); vacío si no hay dual boot.
    property string entry: ""
    readonly property bool available: entry !== ""
    // idle | checking | wrong | failed — mismo contrato que SystemUpdates.authState
    property string authState: "idle"
    property string password: ""

    function load() {}

    function resetAuth() {
        if (!rebootProc.running) root.authState = "idle";
    }

    function reboot(password) {
        if (!root.available || rebootProc.running) return;
        root.password = password;
        root.authState = "checking";
        rebootProc.stdinEnabled = true;
        rebootProc.running = true;
    }

    Process {
        running: true
        command: ["bash", "-c", "efibootmgr 2>/dev/null | sed -n 's/^Boot\\([0-9A-Fa-f]\\{4\\}\\)\\*\\{0,1\\} Windows Boot Manager.*/\\1/p' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.entry = text.trim()
        }
    }

    // La contraseña entra por stdin. exit 3 = incorrecta, 4 = efibootmgr falló.
    Process {
        id: rebootProc
        command: ["bash", "-c",
            'IFS= read -r pw; printf "%s\\n" "$pw" | sudo -k -S -p "" -v 2>/dev/null || exit 3; sudo -n efibootmgr --bootnext "$1" >/dev/null || exit 4; systemctl reboot',
            "bash", root.entry]
        onRunningChanged: {
            if (!running) return;
            write(root.password + "\n");
            root.password = "";
            stdinEnabled = false;
        }
        onExited: (exitCode, exitStatus) => {
            root.authState = exitCode === 0 ? "idle" : exitCode === 3 ? "wrong" : "failed";
        }
    }
}
