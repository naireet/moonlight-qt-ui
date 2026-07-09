import QtQuick 2.15
import QtQuick.Controls 2.2
import QtQuick.Effects

Menu {
    property var initiator

    onOpened: {
        // If the initiating object currently has keyboard focus,
        // give focus to the first visible and enabled menu item
        if (initiator.focus) {
            for (var i = 0; i < count; i++) {
                var item = itemAt(i)
                if (item.visible && item.enabled) {
                    item.forceActiveFocus(Qt.TabFocusReason)
                    break
                }
            }
        }
    }

    // Dark glass card matching the same recipe used for the Host
    // Actions modal (pcContextMenu in PcView.qml) and the pill/frame
    // language used throughout the redesign, instead of the stock
    // unstyled Material menu panel (flat rectangle, square corners,
    // no border/shadow) every NavigableMenu previously inherited.
    background: Rectangle {
        implicitWidth: 200
        color: Qt.rgba(24/255, 26/255, 34/255, 0.94)
        radius: 14
        border.width: 1
        border.color: "#17ffffff"

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.6)
            shadowBlur: 0.8
            shadowVerticalOffset: 8
            shadowHorizontalOffset: 0
            autoPaddingEnabled: true
        }
    }
}
