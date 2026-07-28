import QtQuick 2.0
import QtQuick.Controls 2.2

import ComputerManager 1.0
import Session 1.0

Item {
    property string appName
    property var quitRunningAppFn
    property Session nextSession : null
    property string nextAppName : ""
    property string nextBoxArtImageUrl : ""

    property string stageText : qsTr("Quitting %1...").arg(appName)

    function quitAppCompleted(error)
    {
        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.open()
            console.error(error)
        }

        // If we're supposed to launch another game after this, do so now
        if (error === undefined && nextSession !== null) {
            var component = Qt.createComponent("StreamSegue.qml")
            var segue = component.createObject(stackView, {"appName": nextAppName, "session": nextSession, "boxArtImageUrl": nextBoxArtImageUrl})
            stackView.replace(segue)
        }
        else {
            // Exit this view
            stackView.pop()
        }
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading. This must go through
        // window.streamActive (a plain property folded into the header's
        // visible: binding in main.qml) rather than imperatively setting
        // toolBar.visible directly -- an imperative assignment permanently
        // destroys that binding in QML, which used to leave the stock
        // toolbar stuck visible on every page after the very first quit.
        window.streamActive = true

        // Connect the quit completion signal
        ComputerManager.quitAppCompleted.connect(quitAppCompleted)

        // Start the quit operation if requested
        if (quitRunningAppFn) {
            quitRunningAppFn()
        }
    }

    StackView.onDeactivating: {
        // Show the toolbar again (see the comment in StackView.onActivated
        // above for why this goes through window.streamActive)
        window.streamActive = false

        // Disconnect the signal
        ComputerManager.quitAppCompleted.disconnect(quitAppCompleted)
    }

    Row {
        anchors.centerIn: parent
        spacing: 5

        BusyIndicator {
            id: stageSpinner
            running: visible
        }

        Label {
            id: stageLabel
            height: stageSpinner.height
            text: stageText
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.Wrap
        }
    }

    ErrorMessageDialog {
        id: errorDialog
    }
}
