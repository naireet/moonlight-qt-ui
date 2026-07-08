import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2

Item {
    id: root

    property string label: ""
    property string description: ""
    property bool inherited: false
    property bool overridden: false

    signal resetRequested()

    default property alias content: contentSlot.data

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: rowLayout.implicitHeight
    width: parent ? parent.width : implicitWidth

    RowLayout {
        id: rowLayout
        width: root.width
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 2

            Label {
                text: root.label
                font.pointSize: 12
                font.italic: root.inherited && !root.overridden
                font.bold: root.overridden
                color: root.overridden ? "#66CCFF" : (root.inherited ? "#B0FFFFFF" : "#FFFFFFFF")
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Label {
                visible: root.description.length > 0
                text: root.description
                font.pointSize: 9
                opacity: 0.7
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Item {
            id: contentSlot
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
        }

        Button {
            visible: root.overridden
            text: qsTr("Reset")
            flat: true
            focusPolicy: Qt.NoFocus
            Layout.alignment: Qt.AlignTop
            onClicked: root.resetRequested()

            ToolTip.delay: 800
            ToolTip.timeout: 4000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Reset to inherited value")
        }
    }
}
