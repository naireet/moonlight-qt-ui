import QtQuick 2.9
import QtQuick.Controls 2.3

// Bottom-centered confirmation toast for the "Add to Game Mode" menu items
// (AppView, AppCoverflowView, PcView). Parented to the window overlay so it
// stays put regardless of where the triggering view is scrolled.
ToolTip {
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: parent.height - height - 60
    timeout: 3000

    function show(count) {
        text = qsTr("Sent %n app(s) to Game Mode", "", count)
        open()
    }
}
