pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Festivos de la API de festivos.com.co, cacheados por año en holidays.json.
 * Cada año se vuelve a pedir solo cuando su caché supera fetchIntervalDays (la API es gratuita y con cuota).
 * La API key vive en el keyring (KeyringStorage), no en config.json, porque config.json se commitea.
 */
Singleton {
    id: root

    readonly property string defaultApiUrl: "https://www.festivos.com.co/api/v1/festivos"
    readonly property string apiUrl: Config.options.calendar.holidays.apiUrl.trim() || root.defaultApiUrl
    readonly property bool enabled: Config.options.calendar.holidays.enable
    readonly property real maxAgeMs: Math.max(1, Config.options.calendar.holidays.fetchIntervalDays) * 24 * 60 * 60 * 1000
    readonly property var keyPath: ["holidays", "apiKey"]

    // { "2026": { fetchedAt: <ms>, holidays: [ {date, name_es, name_en, ...} ] } }
    property var cache: ({})
    property bool cacheLoaded: false
    // "YYYY-MM-DD" -> [ {date, name_es, name_en, ...} ]; hay días con más de un festivo
    readonly property var byDate: {
        const result = {};
        if (!root.enabled) return result;
        for (const year of Object.keys(root.cache)) {
            for (const holiday of root.cache[year].holidays ?? []) {
                if (!result[holiday.date]) result[holiday.date] = [];
                result[holiday.date].push(holiday);
            }
        }
        return result;
    }

    property string apiKey: ""
    property var queue: []
    // Años que fallaron en esta sesión: no se reintentan hasta el próximo ciclo del timer
    property var failedYears: ({})

    function load() {}

    function holidaysOn(isoDate) {
        return root.byDate[isoDate] ?? [];
    }

    function displayName(holiday) {
        return holiday.name_es || holiday.name_en || "";
    }

    function isStale(year) {
        const entry = root.cache[year];
        return !entry || (Date.now() - entry.fetchedAt) >= root.maxAgeMs;
    }

    // Encola el año si su caché falta o venció. Llamado por el calendario al navegar y por el timer.
    function ensureYear(year) {
        if (!root.enabled || !root.cacheLoaded) return;
        if (!root.isStale(year) || root.failedYears[year] || root.queue.includes(year)) return;
        root.queue = [...root.queue, year];
        root.processQueue();
    }

    function refreshCurrentYears() {
        root.failedYears = {};
        const year = new Date().getFullYear();
        root.ensureYear(year);
        root.ensureYear(year + 1);
    }

    // Recarga todo lo cacheado (p. ej. tras cambiar la API key o la URL). Lo marca vencido en vez de
    // borrarlo, así si la petición falla se siguen mostrando los datos viejos.
    function forceRefresh() {
        if (!root.cacheLoaded) return;
        const staleCache = {};
        for (const year of Object.keys(root.cache)) staleCache[year] = Object.assign({}, root.cache[year], { fetchedAt: 0 });
        root.cache = staleCache;
        root.failedYears = {};
        const current = new Date().getFullYear();
        for (const year of new Set([current, current + 1, ...Object.keys(staleCache).map(Number)])) root.ensureYear(year);
    }

    // La key se relee del keyring antes de cada lote: el panel de ajustes corre en otro proceso
    function processQueue() {
        if (root.queue.length === 0 || keyLookup.running || fetcher.running) return;
        keyLookup.running = true;
    }

    function fetchNext() {
        if (root.queue.length === 0) return;
        if (root.apiKey.length === 0) {
            console.warn("[Holidays] No API key configured, skipping fetch.");
            root.queue = [];
            return;
        }
        const year = root.queue[0];
        const separator = root.apiUrl.includes("?") ? "&" : "?";
        fetcher.year = year;
        fetcher.environment = { "HOLIDAYS_API_KEY": root.apiKey };
        fetcher.command = ["bash", "-c", 'curl -sS --max-time 20 -w "\\n%{http_code}" -H "Authorization: Bearer $HOLIDAYS_API_KEY" "$1"', "_", `${root.apiUrl}${separator}year=${year}`];
        fetcher.running = true;
    }

    function finishYear(year, holidays) {
        root.queue = root.queue.filter(y => y !== year);
        if (holidays) {
            root.cache = Object.assign({}, root.cache, { [year]: { fetchedAt: Date.now(), holidays: holidays } });
            cacheFile.setText(JSON.stringify(root.cache, null, 2));
        } else {
            root.failedYears = Object.assign({}, root.failedYears, { [year]: true });
        }
        root.fetchNext();
    }

    // Los cambios de URL/key llegan desde el panel de ajustes vía IPC (refresh), con debounce
    onEnabledChanged: if (root.enabled) root.refreshCurrentYears()

    FileView {
        id: cacheFile
        path: Directories.holidaysPath
        onLoaded: {
            try {
                root.cache = JSON.parse(cacheFile.text()) ?? {};
            } catch (e) {
                console.error(`[Holidays] Invalid cache file, ignoring it: ${e.message}`);
                root.cache = {};
            }
            root.cacheLoaded = true;
            root.refreshCurrentYears();
        }
        onLoadFailed: error => {
            root.cache = {};
            root.cacheLoaded = true;
            root.refreshCurrentYears();
        }
    }

    Process {
        id: keyLookup
        command: ["bash", "-c", `${Directories.scriptPath}/keyring/try_lookup.sh 2> /dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = text.startsWith("{") ? JSON.parse(text) : {};
                    root.apiKey = (data?.holidays?.apiKey ?? "").trim();
                } catch (e) {
                    root.apiKey = "";
                }
                root.fetchNext();
            }
        }
    }

    Process {
        id: fetcher
        property int year
        stdout: StdioCollector {
            onStreamFinished: {
                const separatorIndex = text.lastIndexOf("\n");
                const status = parseInt(text.slice(separatorIndex + 1));
                const body = text.slice(0, separatorIndex);
                if (status === 429) {
                    console.warn("[Holidays] Rate limited (429), will retry on the next cycle.");
                    root.queue.forEach(y => root.failedYears[y] = true);
                    root.queue = [];
                    return;
                }
                try {
                    const holidays = JSON.parse(body)?.data;
                    if (status !== 200 || !Array.isArray(holidays)) throw new Error(`HTTP ${status}: ${body.slice(0, 200)}`);
                    root.finishYear(fetcher.year, holidays);
                } catch (e) {
                    console.error(`[Holidays] Failed to fetch ${fetcher.year}: ${e.message}`);
                    root.finishYear(fetcher.year, null);
                }
            }
        }
    }

    // Revisa cada hora si la caché venció: cubre sesiones largas y suspensiones sin pedir de más
    Timer {
        running: root.enabled && root.cacheLoaded
        repeat: true
        interval: 60 * 60 * 1000
        onTriggered: root.refreshCurrentYears()
    }

    IpcHandler {
        target: "holidays"

        function refresh(): void {
            root.forceRefresh();
        }
    }
}
