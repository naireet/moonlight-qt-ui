import QtQuick 2.15
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Effects

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

FocusScope {
    property ComputerModel computerModel : createModel()
    property bool subtleBackgroundMotion: StreamingPreferences.backgroundMotionTier == StreamingPreferences.MotionSubtle

    // Layout constants for the host carousel. The "slot" is the fixed
    // horizontal footprint reserved per host (so ListView centering math
    // stays stable); the circle drawn inside it grows/shrinks depending on
    // whether that host is the currently-centered one.
    readonly property int nodeSlotWidth: 250
    readonly property int selectedNodeSize: 180
    readonly property int sideNodeSize: 110

    id: pcView
    focus: true
    activeFocusOnTab: true
    objectName: qsTr("Computers")

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)

        // Unlike the old grid layout (where the current item was only a
        // focus/keyboard-nav concept), the carousel's centered node *is* the
        // core visual language of this screen, so we always want one host
        // highlighted -- not just when a gamepad is connected.
        if (pcList.currentIndex === -1 && pcList.count > 0) {
            pcList.currentIndex = 0
        }

        pcList.forceActiveFocus()
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    // Hosts can be discovered asynchronously after this screen is already
    // showing (mDNS discovery), so make sure the first one that shows up
    // becomes the centered/selected node.
    Connections {
        target: pcList

        function onCountChanged() {
            if (pcList.currentIndex === -1 && pcList.count > 0) {
                pcList.currentIndex = 0
            }
        }
    }

    function pairingComplete(error)
    {
        // Close the PIN dialog
        pairDialog.close()

        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.helpText = ""
            errorDialog.open()
        }
    }

    function addComplete(success, detectedPortBlocking)
    {
        if (!success) {
            errorDialog.text = qsTr("Unable to connect to the specified PC.")

            if (detectedPortBlocking) {
                errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
            }
            else {
                errorDialog.helpText = qsTr("Click the Help button for possible solutions.")
            }

            errorDialog.open()
        }
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', parent, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    function openMoonlightSettings()
    {
        var existingItem = stackView.find(function(item, index) {
            return item instanceof SettingsView
        })

        if (existingItem !== null) {
            stackView.pop(existingItem)
        }
        else {
            stackView.push("qrc:/gui/SettingsView.qml")
        }
    }

    // ===== Aurora background =====
    // Three softly-blurred, slowly-drifting radial-gradient blobs (violet,
    // teal, magenta) layered over a near-black base -- this is the visual
    // identity of the redesigned host-select screen. Falls back to the
    // plain solid/gradient treatments shared with the other screens when the
    // user has picked a different background style.
    Item {
        id: pcBackgroundLayer
        anchors.fill: parent
        z: -1
        clip: true

        readonly property bool showSolidBackground: StreamingPreferences.backgroundStyle == StreamingPreferences.BackgroundSolid

        Rectangle {
            anchors.fill: parent
            color: Qt.darker(StreamingPreferences.accentColor, 6)
            visible: pcBackgroundLayer.showSolidBackground
        }

        Item {
            anchors.fill: parent
            clip: true
            visible: !pcBackgroundLayer.showSolidBackground

            Rectangle {
                anchors.fill: parent
                color: "#07080d"
            }

            Item {
                id: auroraLayer
                property real driftX: 0
                property real driftY: 0
                property real driftRotation: 0
                x: -parent.width * 0.1 + driftX
                y: -parent.height * 0.1 + driftY
                width: parent.width * 1.2
                height: parent.height * 1.2
                rotation: driftRotation
                transformOrigin: Item.Center
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    autoPaddingEnabled: true
                }

                Rectangle {
                    width: parent.width * 0.6
                    height: parent.height * 0.6
                    x: parent.width * 0.05
                    y: parent.height * 0.05
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(90/255, 40/255, 200/255, 0.6) }
                        GradientStop { position: 0.55; color: Qt.rgba(90/255, 40/255, 200/255, 0.16) }
                        GradientStop { position: 1.0; color: Qt.rgba(90/255, 40/255, 200/255, 0.0) }
                    }
                }

                Rectangle {
                    width: parent.width * 0.62
                    height: parent.height * 0.62
                    x: parent.width * 0.42
                    y: parent.height * 0.08
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(20/255, 140/255, 190/255, 0.55) }
                        GradientStop { position: 0.55; color: Qt.rgba(20/255, 140/255, 190/255, 0.14) }
                        GradientStop { position: 1.0; color: Qt.rgba(20/255, 140/255, 190/255, 0.0) }
                    }
                }

                Rectangle {
                    width: parent.width * 0.58
                    height: parent.height * 0.58
                    x: parent.width * 0.28
                    y: parent.height * 0.52
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(200/255, 40/255, 120/255, 0.5) }
                        GradientStop { position: 0.55; color: Qt.rgba(200/255, 40/255, 120/255, 0.13) }
                        GradientStop { position: 1.0; color: Qt.rgba(200/255, 40/255, 120/255, 0.0) }
                    }
                }

                SequentialAnimation on driftX {
                    running: pcView.subtleBackgroundMotion && !pcBackgroundLayer.showSolidBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 40; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -40; duration: 20000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftY {
                    running: pcView.subtleBackgroundMotion && !pcBackgroundLayer.showSolidBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 30; duration: 26000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -30; duration: 26000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftRotation {
                    running: pcView.subtleBackgroundMotion && !pcBackgroundLayer.showSolidBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 6; duration: 32000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -6; duration: 32000; easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.12
            }
        }
    }

    // ===== Wordmark + subtitle =====
    Column {
        id: wordmark
        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        Row {
            spacing: 12
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
                id: moonIcon
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#eef0f6"
                }

                Rectangle {
                    width: parent.width * 0.6
                    height: parent.height
                    anchors.right: parent.right
                    radius: height / 2
                    color: "#07080d"
                }

                // Slow continuous rotation -- small ambient branding
                // flourish next to the wordmark, matching the coded
                // mockup's always-spinning logo icon.
                RotationAnimation on rotation {
                    running: true
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 8000
                }
            }

            Label {
                text: qsTr("MOONLIGHT")
                color: "#eef0f6"
                font.pointSize: 14
                font.bold: true
                font.letterSpacing: 6
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Label {
            text: qsTr("Select Host")
            color: "#9aa0b0"
            font.pointSize: 12
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: pcList.count === 0

        BusyIndicator {
            id: searchSpinner
            visible: StreamingPreferences.enableMdns
            running: visible
        }

        Label {
            height: searchSpinner.height
            elide: Label.ElideRight
            text: StreamingPreferences.enableMdns ? qsTr("Searching for compatible hosts on your local network...")
                                                  : qsTr("Automatic PC discovery is disabled. Add your PC manually.")
            font.pointSize: 20
            color: "#eef0f6"
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    // ===== Host carousel =====
    ListView {
        id: pcList
        model: computerModel

        anchors.top: wordmark.bottom
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 96
        anchors.left: parent.left
        anchors.right: parent.right

        orientation: ListView.Horizontal
        focus: true

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - pcView.nodeSlotWidth) / 2
        preferredHighlightEnd: (width - pcView.nodeSlotWidth) / 2
        highlightMoveDuration: 220

        Keys.onLeftPressed: {
            if (pcList.currentIndex > 0) {
                pcList.decrementCurrentIndex()
            }
            event.accepted = true
        }

        Keys.onRightPressed: {
            if (pcList.currentIndex < pcList.count - 1) {
                pcList.incrementCurrentIndex()
            }
            event.accepted = true
        }

        Keys.onUpPressed: {
            // There's no vertical dimension in the carousel -- Up escapes
            // focus back up to the toolbar, mirroring the old grid's
            // top-of-list behavior.
            nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
        }

        Keys.onReturnPressed: {
            if (pcList.currentItem) {
                pcList.currentItem.activate()
            }
        }

        Keys.onEnterPressed: {
            if (pcList.currentItem) {
                pcList.currentItem.activate()
            }
        }

        Keys.onMenuPressed: {
            // Host actions are presented as a centered dialog rather than a cursor popup.
            if (pcList.currentItem) {
                pcList.currentItem.pcContextMenu.open()
            }
        }

        Keys.onDeletePressed: {
            if (pcList.currentItem) {
                deletePcDialog.pcIndex = pcList.currentIndex
                deletePcDialog.pcName = pcList.currentItem.pcName
                deletePcDialog.open()
            }
        }

        delegate: Item {
            id: pcDelegate
            width: pcView.nodeSlotWidth
            height: pcList.height

            readonly property bool isSelected: pcList.currentIndex === index
            readonly property string pcName: model.name
            readonly property bool isOnline: model.online
            property alias pcContextMenu : pcContextMenuLoader.item

            function activate() {
                if (!pcDelegate.isSelected) {
                    pcList.currentIndex = index
                    return
                }

                if (model.online) {
                    if (!model.serverSupported) {
                        errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(model.name)
                        errorDialog.helpText = ""
                        errorDialog.open()
                    }
                    else if (model.paired) {
                        // go to game view
                        var component = Qt.createComponent("AppView.qml")
                        var appView = component.createObject(stackView, {"computerIndex": index, "objectName": model.name})
                        stackView.push(appView)
                    }
                    else {
                        var pin = computerModel.generatePinString()

                        // Kick off pairing in the background
                        computerModel.pairComputer(index, pin)

                        // Display the pairing dialog
                        pairDialog.pin = pin
                        pairDialog.open()
                    }
                } else {
                    // Using open() here because it may be activated by keyboard
                    pcContextMenu.open()
                }
            }

            Item {
                id: nodeCircle
                anchors.centerIn: parent
                width: pcDelegate.isSelected ? pcView.selectedNodeSize : pcView.sideNodeSize
                height: width
                opacity: pcDelegate.isSelected ? 1.0 : 0.6

                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 220 } }

                // Soft accent glow behind the selected node.
                Item {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    visible: pcDelegate.isSelected

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 34
                        height: width
                        radius: width / 2
                        color: StreamingPreferences.accentColor
                        opacity: 0.35
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 48
                        }
                    }
                }

                // Host "art" fill for the selected node -- real per-host box
                // art isn't available on this screen, so we use an
                // accent-tinted gradient fill matching the mockup's art tile.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 10
                    radius: width / 2
                    visible: pcDelegate.isSelected
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.lighter(StreamingPreferences.accentColor, 1.3) }
                        GradientStop { position: 1.0; color: Qt.darker(StreamingPreferences.accentColor, 1.8) }
                    }
                }

                // Half-lit "moon" glyph fill for non-selected nodes.
                Item {
                    anchors.fill: parent
                    anchors.margins: 14
                    visible: !pcDelegate.isSelected
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#141620"
                    }

                    Rectangle {
                        width: parent.width / 2
                        height: parent.height
                        anchors.right: parent.right
                        color: "#1e2130"
                    }
                }

                // Solid ring for the selected node.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: "#ffffff"
                    visible: pcDelegate.isSelected
                }

                // Dashed ring for side nodes, built from rotated segments
                // since QtQuick's Rectangle border doesn't support dash
                // patterns.
                Item {
                    id: dashedRing
                    anchors.fill: parent
                    visible: !pcDelegate.isSelected

                    readonly property int dashCount: 18
                    readonly property real ringRadius: width / 2 - 1

                    Repeater {
                        model: dashedRing.dashCount

                        Rectangle {
                            width: 3
                            height: 7
                            radius: 1.5
                            color: "#73ffffff"
                            x: dashedRing.width / 2 + dashedRing.ringRadius * Math.cos(2 * Math.PI * index / dashedRing.dashCount) - width / 2
                            y: dashedRing.height / 2 + dashedRing.ringRadius * Math.sin(2 * Math.PI * index / dashedRing.dashCount) - height / 2
                            rotation: (360 * index / dashedRing.dashCount) + 90
                        }
                    }
                }

                // Status glyphs (offline / needs pairing / unknown) drawn
                // over the node, same iconography as before.
                Image {
                    anchors.centerIn: parent
                    visible: !model.statusUnknown && (!model.online || !model.paired)
                    source: !model.online ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-lock-24px.svg"
                    sourceSize {
                        width: pcDelegate.isSelected ? 40 : 28
                        height: pcDelegate.isSelected ? 40 : 28
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    width: pcDelegate.isSelected ? 40 : 28
                    height: width
                    visible: model.statusUnknown
                    running: visible
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            pcContextMenu.open()
                        } else {
                            pcDelegate.activate()
                        }
                    }
                    onPressAndHold: {
                        pcContextMenu.open()
                    }
                }
            }

            Loader {
                id: pcContextMenuLoader
                asynchronous: true
                sourceComponent: NavigableDialog {
                    id: pcContextMenu
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    padding: 24

                    onOpened: {
                        if (viewAllAppsButton.visible) {
                            viewAllAppsButton.forceActiveFocus()
                        }
                        else if (wakePcButton.visible) {
                            wakePcButton.forceActiveFocus()
                        }
                        else {
                            testConnectionButton.forceActiveFocus()
                        }
                    }

                    ColumnLayout {
                        width: 360
                        spacing: 10

                        Label {
                            Layout.fillWidth: true
                            text: model.name
                            font.pointSize: 18
                            font.bold: true
                            color: StreamingPreferences.accentColor
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("PC Status: %1").arg(model.online ? qsTr("Online") : qsTr("Offline"))
                            color: "#CCFFFFFF"
                            opacity: 0.8
                        }

                        Button {
                            id: viewAllAppsButton
                            Layout.fillWidth: true
                            text: qsTr("View All Apps")
                            visible: model.online && model.paired
                            onClicked: {
                                pcContextMenu.close()
                                var component = Qt.createComponent("AppView.qml")
                                var appView = component.createObject(stackView, {"computerIndex": index, "objectName": model.name, "showHiddenGames": true})
                                stackView.push(appView)
                            }
                        }

                        Button {
                            id: wakePcButton
                            Layout.fillWidth: true
                            text: qsTr("Wake PC")
                            visible: !model.online && model.wakeable
                            onClicked: {
                                pcContextMenu.close()
                                computerModel.wakeComputer(index)
                            }
                        }

                        Button {
                            id: testConnectionButton
                            Layout.fillWidth: true
                            text: qsTr("Test Connection")
                            onClicked: {
                                pcContextMenu.close()
                                computerModel.testConnectionForComputer(index)
                                testConnectionDialog.open()
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: qsTr("Rename PC")
                            onClicked: {
                                pcContextMenu.close()
                                renamePcDialog.pcIndex = index
                                renamePcDialog.originalName = model.name
                                renamePcDialog.open()
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: qsTr("Remove Host")
                            onClicked: {
                                pcContextMenu.close()
                                deletePcDialog.pcIndex = index
                                deletePcDialog.pcName = model.name
                                deletePcDialog.open()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Button {
                                Layout.fillWidth: true
                                text: qsTr("View Details")
                                onClicked: {
                                    pcContextMenu.close()
                                    showPcDetailsDialog.pcDetails = model.details
                                    showPcDetailsDialog.open()
                                }
                            }

                            Button {
                                Layout.fillWidth: true
                                text: qsTr("Moonlight Settings")
                                onClicked: {
                                    pcContextMenu.close()
                                    openMoonlightSettings()
                                }
                            }
                        }
                    }
                }
            }

            Connections {
                target: pcContextMenuLoader.item

                function onClosed() {
                    pcContextMenuLoader.parent.forceActiveFocus()
                }
            }
        }
    }

    // ===== Status pill =====
    Row {
        id: statusPill
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36
        anchors.horizontalCenter: parent.horizontalCenter
        visible: pcList.currentItem !== null
        spacing: 10
        padding: 0

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            radius: height / 2
            color: "#141620"
            border.width: 1
            border.color: "#17ffffff"
            width: pillContent.width + 36
            height: pillContent.height + 20

            Row {
                id: pillContent
                anchors.centerIn: parent
                spacing: 10

                Rectangle {
                    id: statusDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 4.5
                    color: (pcList.currentItem && pcList.currentItem.isOnline) ? "#39d353" : "#6b7280"
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pcList.currentItem ? pcList.currentItem.pcName : ""
                    color: "#eef0f6"
                    font.pointSize: 11
                }
            }
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        // Using Setup-Guide here instead of Troubleshooting because it's likely that users
        // will arrive here by forgetting to enable GameStream or not forwarding ports.
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
    }

    NavigableMessageDialog {
        id: pairDialog
        closePolicy: Popup.CloseOnEscape

        // don't allow edits to the rest of the window while open
        property string pin : "0000"
        text:qsTr("Please enter %1 on your host PC. This dialog will close when pairing is completed.").arg(pin)+"\n\n"+
             qsTr("If your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
        standardButtons: Dialog.Cancel
        onRejected: {
            // FIXME: We should interrupt pairing here
        }
    }

    NavigableMessageDialog {
        id: deletePcDialog
        // don't allow edits to the rest of the window while open
        property int pcIndex : -1
        property string pcName : ""
        text: qsTr("Are you sure you want to remove '%1'?").arg(pcName)
        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            computerModel.deleteComputer(pcIndex)
        }
    }

    NavigableMessageDialog {
        id: testConnectionDialog
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok

        onAboutToShow: {
            testConnectionDialog.text = qsTr("Moonlight is testing your network connection to determine if any required ports are blocked.") + "\n\n" + qsTr("This may take a few seconds…")
            showSpinner = true
        }

        function connectionTestComplete(result, blockedPorts)
        {
            if (result === -1) {
                text = qsTr("The network test could not be performed because none of Moonlight's connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
                imageSrc = "qrc:/res/baseline-warning-24px.svg"
            }
            else if (result === 0) {
                text = qsTr("This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.") + "\n\n" + qsTr("If you are trying to stream over the Internet, install the Moonlight Internet Hosting Tool on your gaming PC and run the included Internet Streaming Tester to check your gaming PC's Internet connection.")
                imageSrc = "qrc:/res/baseline-check_circle_outline-24px.svg"
            }
            else {
                text = qsTr("Your PC's current network connection seems to be blocking Moonlight. Streaming over the Internet may not work while connected to this network.") + "\n\n" + qsTr("The following network ports were blocked:") + "\n"
                text += blockedPorts
                imageSrc = "qrc:/res/baseline-error_outline-24px.svg"
            }

            // Stop showing the spinner and show the image instead
            showSpinner = false
        }
    }

    NavigableDialog {
        id: renamePcDialog
        property string label: qsTr("Enter the new name for this PC:")
        property string originalName
        property int pcIndex : -1;

        standardButtons: Dialog.Ok | Dialog.Cancel

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text) {
                computerModel.renameComputer(pcIndex, editText.text)
            }
        }

        ColumnLayout {
            Label {
                text: renamePcDialog.label
                font.bold: true
            }

            TextField {
                id: editText
                placeholderText: renamePcDialog.originalName
                Layout.fillWidth: true
                focus: true

                Keys.onReturnPressed: {
                    renamePcDialog.accept()
                }

                Keys.onEnterPressed: {
                    renamePcDialog.accept()
                }
            }
        }
    }

    NavigableMessageDialog {
        id: showPcDetailsDialog
        property string pcDetails : "";
        text: showPcDetailsDialog.pcDetails
        imageSrc: "qrc:/res/baseline-help_outline-24px.svg"
        standardButtons: Dialog.Ok
    }
}
