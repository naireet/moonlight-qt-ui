import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Controls.Material 2.2

import AppModel 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import StreamingPreferences 1.0

CenteredGridView {
    property int computerIndex
    property AppModel appModel : createModel()
    property bool activated
    property bool showHiddenGames
    property bool showGames
    property int tileWidth: Math.round(220 * StreamingPreferences.appGridTileScale / 100)
    property int tileHeight: Math.round(287 * StreamingPreferences.appGridTileScale / 100)
    property int tileGap: StreamingPreferences.appGridTileGap
    property bool reorderModeActive: false
    property int reorderModeAppId: -1
    property bool subtleBackgroundMotion: StreamingPreferences.backgroundMotionTier == StreamingPreferences.MotionSubtle
    property string focusedBackgroundArtSource: currentItem && currentItem.hasUsableBackgroundArt ? currentItem.boxArtSource : ""

    id: appGrid
    focus: true
    activeFocusOnTab: true
    topMargin: 20
    bottomMargin: 5
    cellWidth: tileWidth + tileGap
    cellHeight: tileHeight + tileGap

    function isReorderTarget(appId)
    {
        return reorderModeActive && reorderModeAppId === appId
    }

    function beginReorderMode(appId)
    {
        reorderModeActive = true
        reorderModeAppId = appId
    }

    function finishReorderMode()
    {
        appModel.commitFavoriteOrder()
        reorderModeActive = false
        reorderModeAppId = -1
    }

    function computerLost()
    {
        // Go back to the PC view on PC loss
        stackView.pop()
    }

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1
    }

    StackView.onActivated: {
        appModel.computerLost.connect(computerLost)
        activated = true

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }

        if (!showGames && !showHiddenGames) {
            // Check if there's a direct launch app
            var directLaunchAppIndex = model.getDirectLaunchAppIndex();
            if (directLaunchAppIndex >= 0) {
                // Start the direct launch app if nothing else is running
                currentIndex = directLaunchAppIndex
                currentItem.launchOrResumeSelectedApp(false)

                // Set showGames so we will not loop when the stream ends
                showGames = true
            }
        }
    }

    StackView.onDeactivating: {
        if (reorderModeActive) {
            finishReorderMode()
        }

        appModel.computerLost.disconnect(computerLost)
        activated = false
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import AppModel 1.0; AppModel {}', appGrid, '')
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

    model: appModel

    Item {
        id: appBackgroundLayer
        parent: appGrid
        anchors.fill: parent
        z: -1
        clip: true

        readonly property bool showSolidBackground: StreamingPreferences.backgroundStyle == StreamingPreferences.BackgroundSolid
        readonly property bool showAppArtBackground: StreamingPreferences.backgroundStyle == StreamingPreferences.BackgroundAppArt &&
                                                      appGrid.focusedBackgroundArtSource !== ""
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
                // Banding trade-off is accepted and deferred for this pass.
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#090A0C" }
                    GradientStop { position: 0.5; color: Qt.darker(StreamingPreferences.accentColor, 4.8) }
                    GradientStop { position: 1.0; color: "#090A0C" }
                }

                SequentialAnimation on driftX {
                    running: appGrid.subtleBackgroundMotion && appBackgroundLayer.showGradientBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 18; duration: 18000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -18; duration: 18000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftY {
                    running: appGrid.subtleBackgroundMotion && appBackgroundLayer.showGradientBackground
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
                source: appGrid.focusedBackgroundArtSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: ambientOpacity

                SequentialAnimation on driftX {
                    running: appGrid.subtleBackgroundMotion && appBackgroundLayer.showAppArtBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 10; duration: 24000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -10; duration: 24000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftY {
                    running: appGrid.subtleBackgroundMotion && appBackgroundLayer.showAppArtBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 8; duration: 28000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -8; duration: 28000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on ambientOpacity {
                    running: appGrid.subtleBackgroundMotion && appBackgroundLayer.showAppArtBackground
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

    delegate: NavigableItemDelegate {
        width: appGrid.tileWidth
        height: appGrid.tileHeight
        grid: appGrid
        scale: appGrid.isReorderTarget(model.appid) ? 1.08 : 1.0
        transformOrigin: Item.Center

        leftKeyHandler: function(event) {
            if (appGrid.isReorderTarget(model.appid)) {
                appModel.moveFavorite(model.index, -1)
                event.accepted = true
                return true
            }

            return false
        }
        rightKeyHandler: function(event) {
            if (appGrid.isReorderTarget(model.appid)) {
                appModel.moveFavorite(model.index, 1)
                event.accepted = true
                return true
            }

            return false
        }
        downKeyHandler: function(event) {
            if (appGrid.isReorderTarget(model.appid)) {
                event.accepted = true
                return true
            }

            return false
        }
        upKeyHandler: function(event) {
            if (appGrid.isReorderTarget(model.appid)) {
                event.accepted = true
                return true
            }

            return false
        }
        returnKeyHandler: function(event) {
            if (appGrid.isReorderTarget(model.appid)) {
                appGrid.finishReorderMode()
                event.accepted = true
                return true
            }

            if (model.running) {
                appContextMenu.open()
                event.accepted = true
                return true
            }

            return false
        }
        enterKeyHandler: function(event) {
            if (appGrid.isReorderTarget(model.appid)) {
                appGrid.finishReorderMode()
                event.accepted = true
                return true
            }

            if (model.running) {
                appContextMenu.open()
                event.accepted = true
                return true
            }

            return false
        }
        escapeKeyHandler: function(event) {
            if (appGrid.isReorderTarget(model.appid)) {
                appGrid.finishReorderMode()
                event.accepted = true
                return true
            }

            event.accepted = false
            return false
        }

        Behavior on scale {
            NumberAnimation {
                duration: 120
            }
        }

        property alias appContextMenu: appContextMenuLoader.item
        property alias appNameText: appNameTextLoader.item
        property real tileScaleFactor: StreamingPreferences.appGridTileScale / 100.0
        property int runningActionButtonSize: Math.round(85 * tileScaleFactor)
        property int runningActionIconSize: Math.round(75 * tileScaleFactor)
        property int runningActionPlaceholderHorizontalOffset: Math.round(47 * tileScaleFactor)
        property int runningActionPlaceholderVerticalOffset: Math.round(75 * tileScaleFactor)
        property int runningActionVerticalOffset: Math.round(60 * tileScaleFactor)
        property int runningPlaceholderLabelHeight: Math.round(175 * tileScaleFactor)
        property string boxArtSource: model.boxart
        property bool hasUsableBackgroundArt: boxArtSource !== "" && appIcon.status === Image.Ready && !appIcon.isPlaceholder
        property string segueBoxArtImageUrl: hasUsableBackgroundArt ? boxArtSource : ""

        // Dim the app if it's hidden
        opacity: model.hidden ? 0.4 : 1.0

        Rectangle {
            anchors.fill: parent
            z: 2
            color: "transparent"
            border.width: 3
            border.color: StreamingPreferences.accentColor
            visible: appGrid.isReorderTarget(model.appid)
        }

        Image {
            property bool isPlaceholder: false

            id: appIcon
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(10 * StreamingPreferences.appGridTileScale / 100)
            source: model.boxart
            width: Math.round(200 * StreamingPreferences.appGridTileScale / 100)
            height: Math.round(267 * StreamingPreferences.appGridTileScale / 100)

            onSourceSizeChanged: {
                // Nearly all of Nvidia's official box art does not match the dimensions of placeholder
                // images, however the one known exception is Overcooked. Therefore, we only execute
                // the image size checks if this is not an app collector game. We know the officially
                // supported games all have box art, so this check is not required.
                isPlaceholder = appGrid.isPlaceholderBoxArt(sourceSize.width, sourceSize.height, model.appCollectorGame)
            }

            // Display a tooltip with the full name if it's truncated
            ToolTip.text: model.name
            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: (parent.hovered || parent.highlighted) && (!appNameText || appNameText.truncated)
        }

        Loader {
            active: model.running
            asynchronous: true
            anchors.fill: appIcon

            sourceComponent: Item {
                RoundButton {
                    // Don't steal focus from the toolbar buttons
                    focusPolicy: Qt.NoFocus

                    anchors.horizontalCenterOffset: appIcon.isPlaceholder ? -runningActionPlaceholderHorizontalOffset : 0
                    anchors.verticalCenterOffset: appIcon.isPlaceholder ? -runningActionPlaceholderVerticalOffset : -runningActionVerticalOffset
                    anchors.centerIn: parent
                    implicitWidth: runningActionButtonSize
                    implicitHeight: runningActionButtonSize

                    icon.source: "qrc:/res/play_arrow_FILL1_wght700_GRAD200_opsz48.svg"
                    icon.width: runningActionIconSize
                    icon.height: runningActionIconSize

                    onClicked: {
                        launchOrResumeSelectedApp(true)
                    }

                    ToolTip.text: qsTr("Resume Game")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered

                    Material.background: "#D0808080"
                }

                RoundButton {
                    // Don't steal focus from the toolbar buttons
                    focusPolicy: Qt.NoFocus

                    anchors.horizontalCenterOffset: appIcon.isPlaceholder ? runningActionPlaceholderHorizontalOffset : 0
                    anchors.verticalCenterOffset: appIcon.isPlaceholder ? -runningActionPlaceholderVerticalOffset : runningActionVerticalOffset
                    anchors.centerIn: parent
                    implicitWidth: runningActionButtonSize
                    implicitHeight: runningActionButtonSize

                    icon.source: "qrc:/res/stop_FILL1_wght700_GRAD200_opsz48.svg"
                    icon.width: runningActionIconSize
                    icon.height: runningActionIconSize

                    onClicked: {
                        doQuitGame()
                    }

                    ToolTip.text: qsTr("Quit Game")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered

                    Material.background: "#D0808080"
                }
            }
        }

        Loader {
            id: appNameTextLoader
            active: appIcon.isPlaceholder

            // This loader is not asynchronous to avoid noticeable differences
            // in the time in which the text loads for each game.

            width: appIcon.width
            height: model.running ? runningPlaceholderLabelHeight : appIcon.height

            anchors.left: appIcon.left
            anchors.right: appIcon.right
            anchors.bottom: appIcon.bottom

            sourceComponent: Label {
                id: appNameText
                text: model.name
                font.pointSize: 22
                leftPadding: 20
                rightPadding: 20
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
            }
        }

        Text {
            anchors.left: appIcon.left
            anchors.right: appIcon.right
            anchors.bottom: parent.bottom
            height: parent.height - appIcon.y - appIcon.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            visible: parent.highlighted
            z: 1
            text: qsTr("Back: Options")
            font.pixelSize: 10
            color: "#CCFFFFFF"
        }

        function launchOrResumeSelectedApp(quitExistingApp)
        {
            var runningId = appModel.getRunningAppId()
            if (runningId !== 0 && runningId !== model.appid) {
                if (quitExistingApp) {
                    quitAppDialog.appName = appModel.getRunningAppName()
                    quitAppDialog.segueToStream = true
                    quitAppDialog.nextAppName = model.name
                    quitAppDialog.nextAppIndex = index
                    quitAppDialog.nextBoxArtImageUrl = segueBoxArtImageUrl
                    quitAppDialog.open()
                }

                return
            }

            var component = Qt.createComponent("StreamSegue.qml")
            var segue = component.createObject(stackView, {
                                                   "appName": model.name,
                                                   "session": appModel.createSessionForApp(index),
                                                   "boxArtImageUrl": segueBoxArtImageUrl,
                                                   "isResume": runningId === model.appid
                                               })
            stackView.push(segue)
        }

        onClicked: {
            if (appGrid.reorderModeActive) {
                if (appGrid.isReorderTarget(model.appid)) {
                    appGrid.finishReorderMode()
                }
                return
            }

            // Only allow clicking on the box art for non-running games.
            // For running games, buttons will appear to resume or quit which
            // will handle starting the game and clicks on the box art will
            // be ignored.
            if (!model.running) {
                launchOrResumeSelectedApp(true)
            }
        }

        onPressAndHold: {
            if (appGrid.reorderModeActive) {
                return
            }

            // popup() ensures the menu appears under the mouse cursor
            if (appContextMenu.popup) {
                appContextMenu.popup()
            }
            else {
                // Qt 5.9 doesn't have popup()
                appContextMenu.open()
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton;
            onClicked: {
                parent.pressAndHold()
            }
        }

        Keys.onMenuPressed: {
            if (appGrid.isReorderTarget(model.appid)) {
                event.accepted = true
                return
            }

            // This will be keyboard/gamepad driven so use open() instead of popup()
            appContextMenu.open()
        }

        function doQuitGame() {
            quitAppDialog.appName = appModel.getRunningAppName()
            quitAppDialog.segueToStream = false
            quitAppDialog.open()
        }

        Loader {
            id: appContextMenuLoader
            asynchronous: true
            sourceComponent: NavigableMenu {
                id: appContextMenu
                initiator: appContextMenuLoader.parent
                NavigableMenuItem {
                    text: model.running ? qsTr("Resume Game") : qsTr("Launch Game")
                    onTriggered: launchOrResumeSelectedApp(true)
                }
                NavigableMenuItem {
                    text: qsTr("Quit Game")
                    onTriggered: doQuitGame()
                    visible: model.running
                }
                NavigableMenuItem {
                    text: qsTr("Favorite")
                    onTriggered: appModel.setAppFavorite(model.index, true)
                    visible: !model.favorite
                }
                NavigableMenuItem {
                    text: qsTr("Move")
                    visible: model.favorite
                    enabled: !appGrid.reorderModeActive || appGrid.reorderModeAppId === model.appid
                    onTriggered: {
                        appGrid.beginReorderMode(model.appid)
                        appContextMenu.close()
                    }
                }
                NavigableMenuItem {
                    text: qsTr("Unfavorite")
                    onTriggered: appModel.setAppFavorite(model.index, false)
                    visible: model.favorite
                }
                NavigableMenuItem {
                    checkable: true
                    checked: model.directLaunch
                    text: qsTr("Direct Launch")
                    onTriggered: appModel.setAppDirectLaunch(model.index, !model.directLaunch)
                    enabled: !model.hidden

                    ToolTip.text: qsTr("Launch this app immediately when the host is selected, bypassing the app selection grid.")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered
                }
                NavigableMenuItem {
                    checkable: true
                    checked: model.hidden
                    text: qsTr("Hide Game")
                    onTriggered: appModel.setAppHidden(model.index, !model.hidden)
                    enabled: model.hidden || (!model.running && !model.directLaunch)

                    ToolTip.text: qsTr("Hide this game from the app grid. To access hidden games, right-click on the host and choose %1.").arg(qsTr("View All Apps"))
                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                }
            }
        }
    }

    // Toggle button to switch to the coverflow view. Uses the same
    // StackView.replace() pattern StreamSegue.qml already uses so the
    // transition happens without a push/pop animation.
    RoundButton {
        id: coverflowToggleButton
        // Reparent to appGrid directly (rather than being an implicit child
        // of the Flickable's contentItem) so the button stays fixed in the
        // viewport instead of scrolling away with the grid content.
        parent: appGrid
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        z: 10

        // Don't steal focus from the grid
        focusPolicy: Qt.NoFocus

        icon.source: "qrc:/res/ic_add_to_queue_white_48px.svg"

        ToolTip.text: qsTr("Switch to Coverflow View")
        ToolTip.delay: 1000
        ToolTip.timeout: 3000
        ToolTip.visible: hovered

        Material.background: "#D0808080"

        onClicked: {
            var component = Qt.createComponent("AppCoverflowView.qml")
            var coverflowView = component.createObject(stackView, {
                                                            "objectName": appGrid.objectName,
                                                            "computerIndex": computerIndex,
                                                            "showHiddenGames": showHiddenGames,
                                                            "showGames": showGames
                                                        })
            stackView.replace(appGrid, coverflowView, StackView.Immediate)
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: appGrid.count === 0

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

    ScrollBar.vertical: ScrollBar {}
}
