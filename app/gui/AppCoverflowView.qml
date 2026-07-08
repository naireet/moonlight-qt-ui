import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Controls.Material 2.2

import AppModel 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import StreamingPreferences 1.0

Item {
    property int computerIndex
    property AppModel appModel : createModel()
    property bool activated
    property bool showHiddenGames
    property bool showGames
    property string searchText
    property int tileWidth: Math.round(220 * StreamingPreferences.appGridTileScale / 100)
    property int tileHeight: Math.round(287 * StreamingPreferences.appGridTileScale / 100)
    property int tileGap: StreamingPreferences.appGridTileGap
    property bool subtleBackgroundMotion: StreamingPreferences.backgroundMotionTier == StreamingPreferences.MotionSubtle
    property string focusedBackgroundArtSource: coverList.currentItem && coverList.currentItem.hasUsableBackgroundArt ? coverList.currentItem.boxArtSource : ""

    id: coverflowView
    focus: true
    activeFocusOnTab: true

    function computerLost()
    {
        // Go back to the PC view on PC loss
        stackView.pop()
    }

    Component.onCompleted: {
        coverList.currentIndex = coverList.count > 0 ? 0 : -1
    }

    StackView.onActivated: {
        appModel.computerLost.connect(computerLost)
        activated = true

        coverList.forceActiveFocus()
    }

    StackView.onDeactivating: {
        appModel.computerLost.disconnect(computerLost)
        activated = false
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import AppModel 1.0; AppModel {}', coverflowView, '')
        model.initialize(ComputerManager, computerIndex, showHiddenGames)
        return model
    }

    function isPlaceholderBoxArt(sourceWidth, sourceHeight, isAppCollectorGame)
    {
        return !isAppCollectorGame &&
                ((sourceWidth === 130 && sourceHeight === 180) ||
                 (sourceWidth === 628 && sourceHeight === 888) ||
                 (sourceWidth === 200 && sourceHeight === 266))
    }

    function launchOrResumeSelectedApp(quitExistingApp)
    {
        if (!coverList.currentItem) {
            return
        }

        var currentAppId = coverList.currentItem.appid
        var currentAppIndex = coverList.currentIndex
        var currentAppName = coverList.currentItem.appName

        var runningId = appModel.getRunningAppId()
        if (runningId !== 0 && runningId !== currentAppId) {
            if (quitExistingApp) {
                quitAppDialog.appName = appModel.getRunningAppName()
                quitAppDialog.segueToStream = true
                quitAppDialog.nextAppName = currentAppName
                quitAppDialog.nextAppIndex = currentAppIndex
                quitAppDialog.nextBoxArtImageUrl = coverList.currentItem.segueBoxArtImageUrl
                quitAppDialog.open()
            }

            return
        }

        var component = Qt.createComponent("StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": currentAppName,
                                               "session": appModel.createSessionForApp(currentAppIndex),
                                               "boxArtImageUrl": coverList.currentItem.segueBoxArtImageUrl,
                                               "isResume": runningId === currentAppId
                                           })
        stackView.push(segue)
    }

    function doQuitGame() {
        quitAppDialog.appName = appModel.getRunningAppName()
        quitAppDialog.segueToStream = false
        quitAppDialog.open()
    }

    Item {
        id: appBackgroundLayer
        anchors.fill: parent
        z: -1
        clip: true

        readonly property bool showSolidBackground: StreamingPreferences.backgroundStyle == StreamingPreferences.BackgroundSolid
        readonly property bool showAppArtBackground: StreamingPreferences.backgroundStyle == StreamingPreferences.BackgroundAppArt &&
                                                     coverflowView.focusedBackgroundArtSource !== ""
        readonly property bool showGradientBackground: !showSolidBackground && !showAppArtBackground

        Rectangle {
            anchors.fill: parent
            color: Qt.darker(StreamingPreferences.accentColor, 6)
            visible: appBackgroundLayer.showSolidBackground
        }

        Item {
            anchors.fill: parent
            clip: true
            visible: appBackgroundLayer.showGradientBackground

            Rectangle {
                id: appGradientFill
                property real driftX: 0
                property real driftY: 0
                x: -40 + driftX
                y: -30 + driftY
                width: parent.width + 80
                height: parent.height + 60
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#090A0C" }
                    GradientStop { position: 0.5; color: Qt.darker(StreamingPreferences.accentColor, 4.8) }
                    GradientStop { position: 1.0; color: "#090A0C" }
                }

                SequentialAnimation on driftX {
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showGradientBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 18; duration: 18000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -18; duration: 18000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftY {
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showGradientBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 12; duration: 22000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -12; duration: 22000; easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.22
            }
        }

        Item {
            anchors.fill: parent
            clip: true
            visible: appBackgroundLayer.showAppArtBackground

            Image {
                id: focusedAppBackgroundArt
                property real driftX: 0
                property real driftY: 0
                property real ambientOpacity: 0.92
                x: Math.round((parent.width - width) / 2 + driftX)
                y: Math.round((parent.height - height) / 2 + driftY)
                width: Math.round(parent.width * 1.18)
                height: Math.round(parent.height * 1.18)
                source: coverflowView.focusedBackgroundArtSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: ambientOpacity

                SequentialAnimation on driftX {
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showAppArtBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 10; duration: 24000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -10; duration: 24000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftY {
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showAppArtBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 8; duration: 28000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -8; duration: 28000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on ambientOpacity {
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showAppArtBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.86; duration: 16000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.92; duration: 16000; easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.82
            }
        }
    }

    // Toggle button back to the grid view. Mirrors the toggle button added
    // to AppView.qml and uses the same StackView.replace() pattern that
    // StreamSegue.qml already uses to swap the current item without an
    // animation.
    RoundButton {
        id: gridToggleButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        z: 10

        // Don't let this button steal focus from the cover list
        focusPolicy: Qt.NoFocus

        icon.source: "qrc:/res/ic_add_to_queue_white_48px.svg"

        ToolTip.text: qsTr("Switch to Grid View")
        ToolTip.delay: 1000
        ToolTip.timeout: 3000
        ToolTip.visible: hovered

        Material.background: "#D0808080"

        onClicked: {
            var component = Qt.createComponent("AppView.qml")
            var gridView = component.createObject(stackView, {
                                                       "objectName": coverflowView.objectName,
                                                       "computerIndex": computerIndex,
                                                       "showHiddenGames": showHiddenGames,
                                                       "showGames": showGames
                                                   })
            stackView.replace(coverflowView, gridView, StackView.Immediate)
        }
    }

    TextField {
        id: searchField
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 10
        width: 220
        placeholderText: qsTr("Search")
        text: searchText

        // v1 is UI-only. No filtering is applied to the model yet.
        onTextChanged: searchText = text
    }

    ListView {
        id: coverList
        anchors.centerIn: parent
        width: parent.width
        height: tileHeight + tileGap
        orientation: ListView.Horizontal
        focus: true

        model: appModel

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - (tileWidth + tileGap)) / 2
        preferredHighlightEnd: (width - (tileWidth + tileGap)) / 2
        highlightMoveDuration: 200

        Keys.onLeftPressed: {
            if (coverList.currentIndex > 0) {
                coverList.decrementCurrentIndex()
            }
            event.accepted = true
        }

        Keys.onRightPressed: {
            if (coverList.currentIndex < coverList.count - 1) {
                coverList.incrementCurrentIndex()
            }
            event.accepted = true
        }

        Keys.onReturnPressed: {
            launchOrResumeSelectedApp(true)
            event.accepted = true
        }

        Keys.onEnterPressed: {
            launchOrResumeSelectedApp(true)
            event.accepted = true
        }

        Keys.onMenuPressed: {
            // v1: no-op. Quitting via the Menu button is too risky to trigger
            // from the coverflow view, so just accept the event and do nothing.
            event.accepted = true
        }

        delegate: Item {
            id: coverDelegate
            width: tileWidth + tileGap
            height: tileHeight

            property string appName: model.name
            property int appid: model.appid
            property bool running: model.running
            property bool hidden: model.hidden
            property string boxArtSource: model.boxart
            property bool hasUsableBackgroundArt: boxArtSource !== "" && coverArt.status === Image.Ready && !coverArt.isPlaceholder
            property string segueBoxArtImageUrl: hasUsableBackgroundArt ? boxArtSource : ""

            // Distance (in item widths) from the centered/current item. Used
            // to shrink and fade neighbors so the current item is visually
            // emphasized, similar to a coverflow effect.
            property real distance: {
                var itemCenter = x + width / 2
                var viewCenter = coverList.contentX + coverList.width / 2
                return width > 0 ? Math.min(1.5, Math.abs(itemCenter - viewCenter) / width) : 0
            }

            scale: 1.0 - (distance * 0.35)
            opacity: (1.0 - (distance * 0.45)) * (hidden ? 0.4 : 1.0)
            z: coverList.currentIndex === index ? 100 : (90 - distance * 10)
            transformOrigin: Item.Center

            Behavior on scale {
                NumberAnimation {
                    duration: 120
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }

            Rectangle {
                anchors.fill: coverArt
                anchors.margins: -3
                color: "transparent"
                border.width: 3
                border.color: StreamingPreferences.accentColor
                visible: coverList.currentIndex === index
            }

            Image {
                id: coverArt
                property bool isPlaceholder: false
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(10 * StreamingPreferences.appGridTileScale / 100)
                source: model.boxart
                width: Math.round(200 * StreamingPreferences.appGridTileScale / 100)
                height: Math.round(267 * StreamingPreferences.appGridTileScale / 100)
                fillMode: Image.PreserveAspectFit

                onSourceSizeChanged: {
                    isPlaceholder = coverflowView.isPlaceholderBoxArt(sourceSize.width, sourceSize.height, model.appCollectorGame)
                }
            }

            // Dim non-centered items so the current item stands out. Opacity
            // scales with distance from center; fully transparent (no dimming)
            // for the centered item.
            Rectangle {
                anchors.fill: coverArt
                color: "black"
                opacity: distance * 0.5
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (coverList.currentIndex === index) {
                        launchOrResumeSelectedApp(true)
                    }
                    else {
                        coverList.currentIndex = index
                    }
                }
            }
        }
    }

    Label {
        id: currentAppLabel
        anchors.top: coverList.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        font.pointSize: 20
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: coverList.currentItem ? coverList.currentItem.appName : ""
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: coverList.count === 0

        Label {
            text: qsTr("This computer doesn't seem to have any applications or some applications are hidden")
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    NavigableMessageDialog {
        id: quitAppDialog
        property string appName : ""
        property bool segueToStream : false
        property string nextAppName: ""
        property int nextAppIndex: 0
        property string nextBoxArtImageUrl: ""
        text:qsTr("Are you sure you want to quit %1? Any unsaved progress will be lost.").arg(appName)
        standardButtons: Dialog.Yes | Dialog.No

        function quitApp() {
            var component = Qt.createComponent("QuitSegue.qml")
            var params = {"appName": appName, "quitRunningAppFn": function() { appModel.quitRunningApp() }}
            if (segueToStream) {
                // Store the session and app name if we're going to stream after
                // successfully quitting the old app.
                params.nextAppName = nextAppName
                params.nextSession = appModel.createSessionForApp(nextAppIndex)
                params.nextBoxArtImageUrl = nextBoxArtImageUrl
            }
            else {
                params.nextAppName = null
                params.nextSession = null
            }

            stackView.push(component.createObject(stackView, params))
        }

        onAccepted: quitApp()
    }
}
