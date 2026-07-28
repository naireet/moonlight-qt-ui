import QtQuick 2.15
import QtQuick.Controls 2.2

MenuItem {
    id: control

    // Ensure focus can't be given to an invisible item
    enabled: visible
    height: visible ? implicitHeight : 0
    focusPolicy: visible ? Qt.TabFocus : Qt.NoFocus

    // Rounded hover/focus highlight and app-matched text color, replacing
    // the stock Material menu item's flat full-width highlight bar so
    // this reads as part of the same dark-glass design language as the
    // rest of the redesign instead of a generic unstyled system menu.
    padding: 10
    leftPadding: 14
    rightPadding: 14

    contentItem: Text {
        leftPadding: control.indicator ? control.indicator.width + control.spacing : 0
        text: control.text
        font: control.font
        color: control.enabled ? "#eef0f6" : Qt.rgba(1, 1, 1, 0.35)
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        implicitWidth: 180
        implicitHeight: 34
        radius: 8
        color: (control.highlighted || control.hovered) ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
    }

    onTriggered: {
        // We must close the context menu first or
        // it can steal focus from any dialogs that
        // onTriggered may spawn.
        menu.close()
    }

    Keys.onReturnPressed: {
        triggered()
    }

    Keys.onEnterPressed: {
        triggered()
    }

    Keys.onEscapePressed: {
        menu.close()
    }
}
