import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.2
import QtQuick.Effects

import AppModel 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import StreamingPreferences 1.0
import StreamingProfileManager 1.0

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

        // Same three soft, slowly-drifting radial-gradient blobs (violet,
        // teal, magenta) used on the Host Select and App Grid screens --
        // this replaces the old flat single-gradient fallback so Coverflow
        // shares the same aurora visual identity instead of the
        // pre-redesign gradient treatment.
        Item {
            anchors.fill: parent
            clip: true
            visible: appBackgroundLayer.showGradientBackground

            Rectangle {
                anchors.fill: parent
                color: "#07080d"
            }

            Item {
                id: coverAuroraLayer
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
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showGradientBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 40; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -40; duration: 20000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftY {
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showGradientBackground
                    loops: Animation.Infinite
                    NumberAnimation { to: 30; duration: 26000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -30; duration: 26000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on driftRotation {
                    running: coverflowView.subtleBackgroundMotion && appBackgroundLayer.showGradientBackground
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

    // Custom header row replacing the stock toolbar for this screen, matching
    // the pill-based appbar AppView.qml uses for App Grid: an accent
    // host-name pill on the left, a search pill in the center (UI-only for
    // now, same precedent this screen already had with its old plain
    // TextField), and small circular icon buttons on the right for the
    // grid-view toggle, streaming profile, settings, and going back.
    Item {
        id: coverflowHeaderBar
        parent: coverflowView
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        height: 56
        z: 10

        // Dark glass status chip -- same recipe as PcView's/AppView's
        // status pill, not a solid/gradient accent fill.
        Rectangle {
            id: hostPill
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: height / 2
            color: "#141620"
            border.width: 1
            border.color: "#17ffffff"
            width: hostPillContent.width + 36
            height: hostPillContent.height + 20

            Row {
                id: hostPillContent
                anchors.centerIn: parent
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 4.5
                    color: "#39d353"
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: coverflowView.objectName
                    color: "#eef0f6"
                    font.pointSize: 11
                }
            }
        }

        Rectangle {
            id: searchPill
            anchors.centerIn: parent
            width: 260
            height: 36
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.09)

            TextInput {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                verticalAlignment: Text.AlignVCenter
                color: "white"
                font.pointSize: 10
                clip: true
                text: searchText

                // v1 is UI-only. No filtering is applied to the model yet.
                onTextChanged: searchText = text

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Search apps…")
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pointSize: 10
                    visible: !searchField.text.length && !searchField.activeFocus
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            RoundButton {
                id: gridToggleButton
                focusPolicy: Qt.NoFocus
                icon.source: "qrc:/res/ic_grid_view.svg"

                ToolTip.text: qsTr("Switch to Grid View")
                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered

                Material.background: Qt.rgba(1, 1, 1, 0.06)

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

            RoundButton {
                id: coverflowProfileButton
                focusPolicy: Qt.NoFocus
                implicitHeight: 36
                flat: true
                text: StreamingProfileManager.activeProfileName
                font.pointSize: 9
                icon.source: "qrc:/res/person.svg"
                icon.width: 16
                icon.height: 16

                ToolTip.text: qsTr("Streaming Profile")
                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered

                Material.background: Qt.rgba(1, 1, 1, 0.06)
                Material.foreground: "white"

                onClicked: {
                    var existingItem = stackView.find(function(item, index) {
                        return item instanceof SettingsView
                    })

                    if (existingItem !== null) {
                        existingItem.currentSectionIndex = existingItem.streamingProfilesSectionIndex
                    }
                    else {
                        stackView.push("qrc:/gui/SettingsView.qml", {"initialSectionIndex": 6})
                    }
                }
            }

            RoundButton {
                id: coverflowSettingsButton
                focusPolicy: Qt.NoFocus
                icon.source: "qrc:/res/settings.svg"

                ToolTip.text: qsTr("Settings")
                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered

                Material.background: Qt.rgba(1, 1, 1, 0.06)

                onClicked: {
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
            }

            RoundButton {
                id: coverflowBackButton
                focusPolicy: Qt.NoFocus
                icon.source: "qrc:/res/arrow_left.svg"

                ToolTip.text: qsTr("Back to Host Select")
                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered

                Material.background: Qt.rgba(1, 1, 1, 0.06)

                onClicked: stackView.pop()
            }
        }
    }

    ListView {
        id: coverList
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 24
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
            // Open the current tile's context menu, mirroring AppView's
            // gamepad/keyboard Menu-button handling.
            if (coverList.currentItem) {
                coverList.currentItem.openContextMenu()
            }
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
            property alias appContextMenu: appContextMenuLoader.item

            // Brings this tile to center (if it isn't already) and opens its
            // context menu. Shared by right-click, press-and-hold, and the
            // Menu key so all three input methods behave identically.
            function openContextMenu() {
                if (coverList.currentIndex !== index) {
                    coverList.currentIndex = index

                    // Setting currentIndex alone doesn't reliably kick off
                    // the highlight-range scroll when driven from outside
                    // normal keyboard/mouse-drag interaction (e.g. from a
                    // right-click or press-and-hold on a non-centered tile),
                    // so explicitly ask the view to scroll this index into
                    // its centered highlight position.
                    coverList.positionViewAtIndex(index, ListView.Center)
                }

                var menu = coverDelegate.appContextMenu

                // Explicitly parent the popup to the window's Overlay layer
                // before positioning it. Menu's implicit parent (whatever it
                // inherited from the Loader it was instantiated under) is
                // the delegate item itself, which lives inside a scrolling,
                // scaled ListView -- x/y set relative to THAT parent do not
                // correspond to the coordinates mapToItem(null, ...) below
                // produces (which are window/scene-relative), so the menu
                // was landing far from the tile (reproduced consistently at
                // the same spot regardless of which tile was right-clicked,
                // confirming it wasn't reading our x/y at all). Reparenting
                // to Overlay.overlay first makes the popup's coordinate
                // space match the scene coordinates we compute here.
                menu.parent = Overlay.overlay

                // Anchor the menu just below the (now possibly re-centered)
                // cover frame instead of relying on popup()'s cursor-based
                // positioning. Since opening the menu on a non-centered
                // tile slides that tile into the center first, the cursor
                // position at click-time no longer lines up with the
                // tile's on-screen position by the time the menu actually
                // opens -- popup() would anchor the menu to the stale
                // cursor spot, visibly detached from the tile it's for.
                var framePos = coverFrame.mapToItem(menu.parent, 0, coverFrame.height)
                menu.x = framePos.x + (coverFrame.width - menu.width) / 2
                menu.y = framePos.y + 8
                menu.open()
            }

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

            // Whether this tile is the centered/selected one -- drives the
            // stronger drop shadow + white ring called out in the mockup's
            // `.cover.center` styling, vs. the flatter shadow on neighbors.
            property bool isCentered: coverList.currentIndex === index
            property real tileScaleFactor: StreamingPreferences.appGridTileScale / 100.0

            // Rounded, drop-shadowed card framing the box art, matching the
            // same "card" treatment AppView.qml's appIconFrame uses for App
            // Grid tiles -- 16px corner radius, real drop shadow (stronger +
            // a subtle white ring when centered, matching the mockup's
            // `.cover.center` box-shadow + rgba(255,255,255,.15) ring).
            Rectangle {
                id: coverFrame
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(10 * StreamingPreferences.appGridTileScale / 100)
                width: Math.round(200 * StreamingPreferences.appGridTileScale / 100)
                height: Math.round(267 * StreamingPreferences.appGridTileScale / 100)
                radius: Math.round(16 * tileScaleFactor)
                clip: true
                color: "#11131a"
                border.width: isCentered ? 2 : 0
                border.color: Qt.rgba(1, 1, 1, 0.15)

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#B3000000"
                    shadowBlur: isCentered ? 0.9 : 0.6
                    shadowVerticalOffset: Math.round((isCentered ? 18 : 10) * tileScaleFactor)
                    shadowHorizontalOffset: 0
                }

                Image {
                    id: coverArt
                    property bool isPlaceholder: false
                    anchors.fill: parent
                    source: model.boxart

                    onSourceSizeChanged: {
                        isPlaceholder = coverflowView.isPlaceholderBoxArt(sourceSize.width, sourceSize.height, model.appCollectorGame)
                    }
                }

                // Dim non-centered items so the current item stands out.
                // Opacity scales with distance from center; fully
                // transparent (no dimming) for the centered item.
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: distance * 0.5
                }
            }

            // Game name label below the cover, matching the mockup's
            // `.cover .name` -- only shown (faded in) for the centered tile.
            Text {
                anchors.top: coverFrame.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: coverFrame.width + 20
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: appName
                color: "#eef0f6"
                font.pointSize: 11
                opacity: isCentered ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        coverDelegate.openContextMenu()
                        return
                    }

                    if (coverList.currentIndex === index) {
                        launchOrResumeSelectedApp(true)
                    }
                    else {
                        coverList.currentIndex = index
                    }
                }

                // Native MouseArea long-press support -- no bridging MouseArea
                // needed here (unlike AppView's ItemDelegate-based tiles)
                // since we're driving pressAndHold directly off this
                // MouseArea rather than an AbstractButton.
                onPressAndHold: {
                    coverDelegate.openContextMenu()
                }
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
