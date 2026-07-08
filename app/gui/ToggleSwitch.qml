import QtQuick 2.9
import QtQuick.Controls 2.2
import StreamingPreferences 1.0

// Custom pill-style toggle switch matching the mockup's .toggle/.toggle.on CSS:
// 46x26 rounded pill, background rgba(255,255,255,.15) off / accent color on,
// with a 20x20 white knob that slides from left:3px to left:23px.
// Drop-in replacement for CheckBox: exposes checked (read/write), onCheckedChanged,
// enabled, text (shown as a label to the left of the switch), and hovered.
Item {
    id: root

    property bool checked: false
    property alias text: label.text
    property alias font: label.font
    property bool hoverEnabled: true
    property bool divider: false
    readonly property bool hovered: mouseArea.containsMouse

    signal toggled()

    implicitWidth: label.text.length > 0 ? (label.implicitWidth + 10 + 46) : 46
    implicitHeight: (divider ? 28 : 0) + Math.max(26, label.implicitHeight)
    width: implicitWidth

    Rectangle {
        id: rowDivider
        visible: root.divider
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: "#0dffffff"
    }

    Label {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: pill.verticalCenter
        font.pointSize: 12
        wrapMode: Text.Wrap
        opacity: root.enabled ? 1.0 : 0.5
    }

    Rectangle {
        id: pill
        width: 46
        height: 26
        radius: height / 2
        anchors.right: parent.right
        y: root.divider ? 14 : (root.height - height) / 2
        opacity: root.enabled ? 1.0 : 0.5
        color: root.checked ? StreamingPreferences.accentColor : "#26ffffff"

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Rectangle {
            id: knob
            width: 20
            height: 20
            radius: width / 2
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? (parent.width - width - 3) : 3

            Behavior on x {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: root.hoverEnabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.enabled
        onClicked: {
            root.checked = !root.checked
            root.toggled()
        }
    }
}
