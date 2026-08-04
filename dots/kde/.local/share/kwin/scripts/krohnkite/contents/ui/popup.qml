// Copyright (c) 2018 Eon S. Jeon <esjeon@hyunmu.am>
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

import QtQuick 2.15
import QtQuick.Controls 2.15
import org.kde.plasma.core as PlasmaCore;

/*
 * Component Documentation
 *  - PlasmaCore global `theme` object:
 *      https://techbase.kde.org/Development/Tutorials/Plasma2/QML2/API#Plasma_Themes
 *  - PlasmaCore.Dialog:
 *      https://techbase.kde.org/Development/Tutorials/Plasma2/QML2/API#Top_Level_windows
 */

PlasmaCore.Dialog {
    id: popupDialog
    type: PlasmaCore.Dialog.OnScreenDisplay
    flags: Qt.Popup | Qt.WindowStaysOnTopHint
    location: PlasmaCore.Types.Floating
    outputOnly: true

    visible: false

    mainItem: Item {
        width: messageLabel.implicitWidth
        height: messageLabel.implicitHeight

        Label {
            id: messageLabel
            padding: 10

            font.pointSize: Math.round(10)
            font.weight: Font.Bold
        }

        /* hides the popup window when triggered */
        Timer {
            id: hideTimer
            repeat: false

            onTriggered: {
                popupDialog.visible = false;
            }
        }
    }


    // PATCHED (dotfiles): OSD desactivado por completo.
    //
    // Krohnkite muestra una notificación en pantalla en cada acción — entre ellas
    // una flecha con la dirección — centrada en el área de la ventana, o sea justo
    // donde acaba el cursor tras un Super+flecha. Resultaba muy molesto.
    //
    // `notificationDuration=0` en kwinrc NO basta: el show() original ponía
    // visible=true ANTES de arrancar hideTimer, así que con intervalo 0 el popup
    // seguía dibujándose al menos un fotograma. Aquí se corta de raíz.
    //
    // Para recuperar el OSD, restaurar el cuerpo original (ver git log) y poner
    // notificationDuration a un valor en ms.
    function show(text, area, duration) {
        return;
    }
}
