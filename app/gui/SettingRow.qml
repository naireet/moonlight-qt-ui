import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

// Matches the mockup's .row CSS: label left, control right, space-between,
// 14px vertical padding, thin bottom divider at 5% white.
Item {
    id: root

    property string label: ""
    property string description: ""
    property bool inherited: false
    property bool overridden: false

    signal resetRequested()

    default property alias content: contentSlot.data

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: rowLayout.implicitHeight + 28
    width: parent ? parent.width : implicitWidth

    Rectangle {
        id: divider
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: "#0dffffff"
    }

    RowLayout {
        id: rowLayout
        y: 14
        width: root.width
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Label {
                text: root.label
                font.pointSize: 12
                font.italic: root.inherited && !root.overridden
                font.bold: root.overridden
                color: root.overridden ? "#66CCFF" : (root.inherited ? "#B0FFFFFF" : "#eef0f6")
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Label {
                visible: root.description.length > 0
                text: root.description
                font.pointSize: 9
                color: "#9aa0b0"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Item {
            id: contentSlot
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
        }

        Button {
            visible: root.overridden
            text: qsTr("Reset")
            flat: true
            focusPolicy: Qt.NoFocus
            Layout.alignment: Qt.AlignVCenter
            onClicked: root.resetRequested()

            ToolTip.delay: 800
            ToolTip.timeout: 4000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Reset to inherited value")
        }
    }
}

