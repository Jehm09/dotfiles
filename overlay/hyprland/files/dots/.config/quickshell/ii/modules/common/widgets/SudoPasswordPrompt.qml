import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Contraseña de sudo para `setup update system`: SystemUpdates la valida y se la pasa
// a la terminal, así sudo no la pide adentro. El campo se vacía apenas se envía.
ColumnLayout {
    id: root
    property string confirmText: Translation.tr("Update")
    property bool busy: false
    property string errorText: ""
    signal submitted(string password)
    signal cancelled

    spacing: 6

    function focusField() {
        field.forceActiveFocus();
    }

    function submit() {
        if (root.busy || field.text.length === 0) return;
        const password = field.text;
        field.text = "";
        root.submitted(password);
    }

    MaterialTextField {
        id: field
        Layout.fillWidth: true
        Layout.preferredWidth: 360
        enabled: !root.busy
        echoMode: TextInput.Password
        wrapMode: TextEdit.NoWrap
        placeholderText: Translation.tr("Password for sudo")
        onAccepted: root.submit()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.cancelled();
                event.accepted = true;
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.errorText !== ""
        text: root.errorText
        color: Appearance.colors.colError
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: 4

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.cancelled()
        }
        DialogButton {
            enabled: !root.busy
            buttonText: root.busy ? Translation.tr("Checking…") : root.confirmText
            onClicked: root.submit()
        }
    }
}
