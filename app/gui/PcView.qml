import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

CenteredGridView {
    property ComputerModel computerModel : createModel()
    property bool subtleBackgroundMotion: StreamingPreferences.backgroundMotionTier == StreamingPreferences.MotionSubtle

    id: pcGrid
    focus: true
    activeFocusOnTab: true
    topMargin: 20
    bottomMargin: 5
    cellWidth: 310; cellHeight: 330;
    objectName: qsTr("Computers")

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
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

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: pcGrid.count === 0

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
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    model: computerModel

    Item {
        id: pcBackgroundLayer
        parent: pcGrid
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
                id: pcGradientFill
                property real driftX: 0
                property real driftY: 0
                x: -40 + driftX
                y: -30 + driftY
                width: parent.width + 80
                height: parent.height + 60
                // Banding trade-off is accepted and deferred for this pass.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#090A0C" }
                    GradientStop { position: 0.5; color: Qt.darker(StreamingPreferences.accentColor, 4.8) }
                    GradientStop { position: 1.0; color: "#090A0C" }
                }

                SequentialAnimation on driftX {
                    running: pcGrid.subtleBackgroundMotion && !pcBackgroundLayer.showSolidBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 18; duration: 18000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -18; duration: 18000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftY {
                    running: pcGrid.subtleBackgroundMotion && !pcBackgroundLayer.showSolidBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 12; duration: 22000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -12; duration: 22000; easing.type: Easing.InOutSine }
                }
            }

            // App art backgrounds intentionally fall back to the gradient on the PC view.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.22
            }
        }
    }

    delegate: NavigableItemDelegate {
        width: 300; height: 320;
        grid: pcGrid

        property alias pcContextMenu : pcContextMenuLoader.item

        Rectangle {
            anchors.fill: parent
            anchors.margins: -6
            z: 2
            color: "transparent"
            border.width: 3
            border.color: StreamingPreferences.accentColor
            opacity: parent.highlighted ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        Image {
            id: pcIcon
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/res/desktop_windows-48px.svg"
            sourceSize {
                width: 200
                height: 200
            }
        }

        Image {
            // TODO: Tooltip
            id: stateIcon
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: !model.online ? -18 : -16
            visible: !model.statusUnknown && (!model.online || !model.paired)
            source: !model.online ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-lock-24px.svg"
            sourceSize {
                width: !model.online ? 75 : 70
                height: !model.online ? 75 : 70
            }
        }

        BusyIndicator {
            id: statusUnknownSpinner
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: -15
            width: 75
            height: 75
            visible: model.statusUnknown
            running: visible
        }

        Label {
            id: pcNameText
            text: model.name

            width: parent.width
            anchors.top: pcIcon.bottom
            anchors.bottom: parent.bottom
            font.pointSize: 36
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideRight
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 24
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            visible: parent.highlighted
            z: 1
            text: qsTr("Back: Options")
            font.pixelSize: 10
            color: "#CCFFFFFF"
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

        onClicked: {
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
            } else if (!model.online) {
                // Using open() here because it may be activated by keyboard
                pcContextMenu.open()
            }
        }

        onPressAndHold: {
            pcContextMenu.open()
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton;
            onClicked: {
                parent.pressAndHold()
            }
        }

        Keys.onMenuPressed: {
            // Host actions are presented as a centered dialog rather than a cursor popup.
            pcContextMenu.open()
        }

        Keys.onDeletePressed: {
            deletePcDialog.pcIndex = index
            deletePcDialog.pcName = model.name
            deletePcDialog.open()
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

    ScrollBar.vertical: ScrollBar {}
}
