// Clipboard - wraps cliphist for clipboard history access.
// Call refresh() to load the current history list.
// Call selectEntry(entry) to paste a clipboard item.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Clipboard history entries as array of strings
    property var entries: []

    // Run cliphist list and populate entries
    function refresh() {
        listProcess.running = true
    }

    // Decode and wl-copy a selected entry string
    function selectEntry(entry) {
        decodeProcess.command = ["bash", "-c",
            `echo ${JSON.stringify(entry)} | cliphist decode | wl-copy`]
        decodeProcess.running = true
    }

    // Delete a single entry from history
    function deleteEntry(entry) {
        Process {
            command: ["bash", "-c", `echo ${JSON.stringify(entry)} | cliphist delete`]
            running: true
        }
    }

    Process {
        id: listProcess
        command: ["cliphist", "list"]
        stdout: SplitParser {
            onRead: data => root.entries = data.trim().split("\n").filter(l => l.length > 0)
        }
    }

    Process {
        id: decodeProcess
        command: []
    }
}
