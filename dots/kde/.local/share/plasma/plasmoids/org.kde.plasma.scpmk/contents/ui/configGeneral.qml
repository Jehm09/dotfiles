import QtQuick 
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_icon: icon.text
    property alias cfg_showCmd1: showCmd1.checked
    property alias cfg_showCmd2: showCmd2.checked
    property alias cfg_showCmd3: showCmd3.checked

    Kirigami.FormLayout {

        RowLayout {
            Label {
                text: i18n("Widget Icon :")
            }

            ConfigIcon {
                value: icon.text
                onValueChanged: icon.text = value
            }

            TextField {
                Kirigami.FormData.label: i18nc("@title:label", "Icon:")
                id: icon
                implicitWidth: 200
            }
        }

        RowLayout {
            CheckBox {
                id: showCmd1
            }
            Label {
                text: i18n("Show Lock / Log Out buttons")
            }
        }

        RowLayout {
            CheckBox {
                id: showCmd2
            }
            Label {
                text: i18n("Show Restart / Sleep buttons")
            }
        }

        RowLayout {
            CheckBox {
                id: showCmd3
            }
            Label {
                text: i18n("Show Power button")
            }
        }
    }
}
