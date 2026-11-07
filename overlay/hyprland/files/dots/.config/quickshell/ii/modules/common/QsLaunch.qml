pragma Singleton

import Quickshell

Singleton {
    id: root

    // Al reiniciar tras un crash, quickshell deja __QUICKSHELL_CRASH_* en su entorno. Un `qs`
    // hijo que las herede se cree a sí mismo un reinicio-por-crash: ignora -p y relanza
    // shell.qml, así que cada lanzamiento clonaba la barra (y ConflictKiller lo hacía en bucle).
    readonly property list<string> cleanEnv: ["env", "-u", "__QUICKSHELL_CRASH_INFO_FD", "-u", "__QUICKSHELL_CRASH_DUMP_PID", "-u", "__QUICKSHELL_CRASH_SIGNAL"]

    // Lanza `qs` con el entorno saneado. args son los argumentos que van después de `qs`.
    function detached(args) {
        Quickshell.execDetached([...root.cleanEnv, "qs", ...args]);
    }

    // Abre Settings; page = nombre del archivo de la página sin .qml (p. ej. "UpdateConfig").
    function openSettings(page) {
        const pageEnv = page ? [`QS_SETTINGS_PAGE=${page}`] : [];
        Quickshell.execDetached([...root.cleanEnv, ...pageEnv, "qs", "-p", Quickshell.shellPath("settings.qml")]);
    }
}
