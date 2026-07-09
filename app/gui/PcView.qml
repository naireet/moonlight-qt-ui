import QtQuick 2.15
import QtQuick.Controls 2.5
import QtQuick.Controls.Material 2.2
import QtQuick.Layouts 1.3
import QtQuick.Effects

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import StreamingProfileManager 1.0
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

    // Host Actions dialog context. The dialog itself (and its scrim) live
    // once at this root level, not per-delegate inside the ListView --
    // see openHostActions() below and the dialog declaration after the
    // ListView for why. These properties carry the data for whichever
    // host the dialog is currently open for.
    property int hostActionsIndex: -1
    property string hostActionsName: ""
    property bool hostActionsOnline: false
    property bool hostActionsPaired: false
    property bool hostActionsWakeable: false
    property string hostActionsDetails: ""

    function openHostActions(idx, name, online, paired, wakeable, details) {
        // Grab a single clean snapshot of the screen for the dialog's
        // blurred backdrop *before* the scrim/dialog become visible. This
        // must happen exactly once per open, not continuously ("live"):
        // hostActionsBackdropSource's sourceItem is pcView itself (an
        // ancestor), so if it kept re-capturing every frame while the
        // scrim/blur were already visible, each new snapshot would
        // include the previous frame's blur+tint, compounding into a
        // flat grey wash within a few frames -- which is exactly what
        // happened before this fix.
        hostActionsBackdropSource.scheduleUpdate()
        hostActionsIndex = idx
        hostActionsName = name
        hostActionsOnline = online
        hostActionsPaired = paired
        hostActionsWakeable = wakeable
        hostActionsDetails = details
        pcContextMenuLoader.item.open()
    }

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

    // Jumps straight to the Streaming Profiles page inside Settings -- used by
    // the floating profile chip so switching/managing profiles doesn't require
    // digging through the full Settings navigation rail first.
    function openStreamingProfiles()
    {
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

    // Navigates to the App Grid/Coverflow view for a given host.
    //
    // Qt.createComponent() does NOT guarantee the component is Ready by the
    // very next line -- for a component as large as AppView.qml (aurora
    // background, pill header, themed context menu, etc.) the engine can
    // still be compiling it asynchronously on the first load in a session,
    // which made component.createObject() silently return null and made
    // stackView.push(null) a no-op ("StackView: push: nothing to push"),
    // i.e. clicking a host appeared to do nothing. Handle both the
    // already-ready (common, cached) case and the not-yet-ready (first
    // load) case explicitly instead of assuming synchronous completion.
    function pushAppView(properties) {
        var component = Qt.createComponent("AppView.qml")

        function finishPush() {
            if (component.status === Component.Ready) {
                var appView = component.createObject(stackView, properties)
                stackView.push(appView)
            }
            else if (component.status === Component.Error) {
                console.log("Failed to load AppView.qml: " + component.errorString())
            }
        }

        if (component.status === Component.Ready || component.status === Component.Error) {
            finishPush()
        }
        else {
            component.statusChanged.connect(finishPush)
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
                // mockup's always-spinning logo icon (.wordmark .spinner,
                // "animation: spin 3.5s linear infinite").
                RotationAnimation on rotation {
                    running: true
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 3500
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
                pcList.currentItem.openContextMenu()
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

            // Opens the shared, root-level Host Actions dialog for THIS
            // host, passing its data in explicitly via pcView's
            // hostActionsXxx properties. The dialog itself is not
            // instantiated per-delegate (see the single Loader declared
            // after the ListView, outside of any delegate) -- an earlier
            // per-delegate Loader caused both a broken partial-screen
            // scrim and an off-center/clipped dialog, root-caused to the
            // dialog's and scrim's anchors.fill/centerIn resolving against
            // this delegate's small per-host bounding box instead of the
            // full window.
            function openContextMenu() {
                pcView.openHostActions(index, model.name, model.online, model.paired, model.wakeable, model.details)
            }

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
                        pushAppView({"computerIndex": index, "objectName": model.name})
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
                    pcDelegate.openContextMenu()
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

                // Generic computer glyph so the node isn't a bare gradient
                // circle when there's no real per-host art to show. Hidden
                // whenever a status glyph (offline/unpaired/unknown) already
                // occupies this same centered spot.
                Image {
                    anchors.centerIn: parent
                    visible: !model.statusUnknown && model.online && model.paired
                    source: "qrc:/res/desktop_windows-48px.svg"
                    opacity: 0.9
                    sourceSize {
                        width: pcDelegate.isSelected ? 64 : 40
                        height: pcDelegate.isSelected ? 64 : 40
                    }
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
                            pcDelegate.openContextMenu()
                        } else {
                            pcDelegate.activate()
                        }
                    }
                    onPressAndHold: {
                        pcDelegate.openContextMenu()
                    }
                }
            }
        }
    }

    // Scrim behind the Host Actions dialog -- covers the FULL pcView
    // screen, matching the mockup's ".overlay" (rgba(4,5,9,.55) +
    // backdrop-filter:blur(4px)). This MUST live here, as a sibling of
    // pcList at the pcView root level -- it previously lived per-delegate
    // inside the ListView's delegate Item, where "anchors.fill: parent"
    // resolved to that single host's small per-slot bounding box instead
    // of the full screen, which is why the dim only covered part of the
    // window.
    //
    // The blur is a snapshot of pcView itself (aurora background,
    // carousel, wordmark, status pill, etc.) fed through MultiEffect.
    // "recursive: true" is required because the ShaderEffectSource's own
    // sourceItem (pcView) is an ancestor of the ShaderEffectSource -- this
    // is QtQuick's documented, supported pattern for "blur everything
    // behind me" rather than infinite recursion. The actual Dialog
    // content itself is never part of this snapshot (Popups render into
    // the ApplicationWindow's Overlay layer, not inside pcView's own item
    // tree), so there's no risk of the card blurring itself.
    //
    // "live" is deliberately false, with a single explicit
    // scheduleUpdate() call in openHostActions() right before the dialog
    // opens (see above) instead of continuous updates. Because
    // sourceItem is an ancestor, a live/continuous capture would each
    // frame re-snapshot pcView *including this very blur+scrim's own
    // output from the previous frame* -- compounding the blur and tint
    // together every frame until the whole backdrop washed out to flat
    // grey within a few frames. A one-time snapshot taken before the
    // scrim/blur ever become visible avoids that feedback loop entirely
    // and is indistinguishable in practice since the backdrop is static
    // for the duration of a modal dialog anyway.
    ShaderEffectSource {
        id: hostActionsBackdropSource
        anchors.fill: parent
        sourceItem: pcView
        recursive: true
        live: false
        visible: false
        z: 8
    }

    MultiEffect {
        anchors.fill: parent
        source: hostActionsBackdropSource
        z: 8
        blurEnabled: true
        blur: 0.4
        blurMax: 48
        visible: pcContextMenuLoader.item !== null && pcContextMenuLoader.item.visible
    }

    Rectangle {
        anchors.fill: parent
        z: 8
        color: Qt.rgba(4/255, 5/255, 9/255, 0.55)
        visible: pcContextMenuLoader.item !== null && pcContextMenuLoader.item.visible
    }

    // Host Actions dialog -- a SINGLE shared instance at the pcView root
    // level (not one per host delegate), for the same reason as the scrim
    // above (per-delegate "anchors.fill: parent" only covering one host's
    // small slot). All content below reads from pcView's hostActionsXxx
    // properties (set by openHostActions()) rather than delegate-local
    // "model"/"index" bindings, since there is no longer a per-host
    // "model" context available at this scope.
    //
    // Note: moving this dialog to the root level did NOT, on its own, fix
    // the separate card-rendered-off-center-and-clipped symptom seen in
    // an earlier pass -- that had a distinct root cause (see the
    // ColumnLayout below) unrelated to per-delegate nesting or to
    // "anchors.centerIn: Overlay.overlay" itself. A control-group test
    // against deletePcDialog (a pre-existing, unrelated NavigableDialog
    // elsewhere in this file) confirmed it centers correctly, ruling out
    // any shared/pre-existing Overlay centering bug.
    Loader {
        id: pcContextMenuLoader
        asynchronous: true
        sourceComponent: NavigableDialog {
            id: pcContextMenu
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            padding: 18

            // Note: 'dim' is not a real Popup property (verified
            // against Qt's own Popup.qml sources for both the
            // Basic and Material styles -- neither defines one).
            // The app's inherited Material-style default dim
            // (T.Overlay.modal, set inside the style's own
            // Popup.qml) will still render underneath/alongside
            // the custom scrim above. Suppressing it would require
            // overriding Overlay.modal per-instance, which throws
            // "Non-existent attached object" in this Loader-based
            // deferred-construction context (see below) --
            // deliberately not re-attempted this pass given that
            // already broke the whole screen once. Reported to the
            // parent session as an open question / known gap
            // rather than silently declared fixed.

            // Fade + scale-in/out. The mockup's CSS only toggles
            // "display:none" <-> "display:flex" with no transition
            // defined, so this isn't a literal mockup requirement --
            // it's a small, standard modal-UX polish addition.
            enter: Transition {
                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.92; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
            }
            exit: Transition {
                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 120; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1.0; to: 0.92; duration: 120; easing.type: Easing.InCubic }
            }

            // Dark glass card matching the mockup's ".actions-card"
            // (rgba(24,26,34,.92), 1px border, 22px radius, soft
            // drop shadow). autoPaddingEnabled avoids the shadow
            // being asymmetrically clipped at the layer bounds.
            background: Rectangle {
                color: Qt.rgba(24/255, 26/255, 34/255, 0.92)
                radius: 22
                border.width: 1
                border.color: "#17ffffff"

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.6)
                    shadowBlur: 1.0
                    shadowVerticalOffset: 12
                    shadowHorizontalOffset: 0
                    autoPaddingEnabled: true
                }
            }

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
                // implicitWidth (not just "width") is required here: a
                // Popup sizes itself (and its background/anchors.centerIn
                // math) from its content's *implicitWidth*, which Layouts
                // compute independently of an explicitly-assigned "width".
                // With only "width: 330" set, this ColumnLayout rendered
                // its rows at 330px as told, but the Popup itself (and its
                // background Rectangle, which auto-fills to the Popup's
                // own size) still computed a much narrower implicit width
                // from the layout's default implicit-size logic. The
                // narrower Popup centered correctly, but the 330px-wide
                // rows inside it overflowed past its right edge -- this
                // was the actual root cause of the "shifted right and
                // clipped" symptom, not a per-delegate/Overlay issue.
                implicitWidth: 330
                spacing: 16

                // Host name row -- NOT a separate title banner (the
                // mockup's actual markup is just
                // '<div class="act primary">Living Room PC</div>',
                // the first row in the list, same compact size as
                // every other row, just accent-colored). No
                // separate "PC Status" text either -- that's not
                // in the mockup, removed entirely. Implemented as
                // a real (non-interactive) Button using the exact
                // same padding/background/contentItem pattern as
                // every other row below, rather than a bespoke
                // Rectangle+Label -- a hand-rolled implicitHeight
                // calc rendered visibly taller than the Button-
                // driven rows and looked inconsistent (caught via
                // screenshot comparison), so this guarantees
                // pixel-identical row height instead.
                Button {
                    id: hostTitleButton
                    Layout.fillWidth: true
                    text: pcView.hostActionsName
                    padding: 14
                    enabled: false

                    background: Rectangle {
                        radius: 14
                        color: StreamingPreferences.accentColor
                    }
                    contentItem: Text {
                        text: hostTitleButton.text
                        color: "white"
                        font.bold: true
                        font.pointSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

                Button {
                    id: testConnectionButton
                    Layout.fillWidth: true
                    text: qsTr("Test Connection")
                    padding: 14

                    background: Rectangle {
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.09)
                        border.width: 1
                        border.color: "#17ffffff"
                    }
                    contentItem: Text {
                        text: testConnectionButton.text
                        color: "#eef0f6"
                        font.pointSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        pcContextMenu.close()
                        computerModel.testConnectionForComputer(pcView.hostActionsIndex)
                        testConnectionDialog.open()
                    }
                }

                Button {
                    id: renamePcButton
                    Layout.fillWidth: true
                    text: qsTr("Rename PC")
                    padding: 14

                    background: Rectangle {
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.09)
                        border.width: 1
                        border.color: "#17ffffff"
                    }
                    contentItem: Text {
                        text: renamePcButton.text
                        color: "#eef0f6"
                        font.pointSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        pcContextMenu.close()
                        renamePcDialog.pcIndex = pcView.hostActionsIndex
                        renamePcDialog.originalName = pcView.hostActionsName
                        renamePcDialog.open()
                    }
                }

                Button {
                    id: removeHostButton
                    Layout.fillWidth: true
                    text: qsTr("Remove Host")
                    padding: 14

                    background: Rectangle {
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.09)
                        border.width: 1
                        border.color: "#17ffffff"
                    }
                    contentItem: Text {
                        text: removeHostButton.text
                        color: "#eef0f6"
                        font.pointSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        pcContextMenu.close()
                        deletePcDialog.pcIndex = pcView.hostActionsIndex
                        deletePcDialog.pcName = pcView.hostActionsName
                        deletePcDialog.open()
                    }
                }

                Button {
                    id: viewDetailsButton
                    Layout.fillWidth: true
                    text: qsTr("View Details")
                    padding: 14

                    background: Rectangle {
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.09)
                        border.width: 1
                        border.color: "#17ffffff"
                    }
                    contentItem: Text {
                        text: viewDetailsButton.text
                        color: "#eef0f6"
                        font.pointSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        pcContextMenu.close()
                        showPcDetailsDialog.pcDetails = pcView.hostActionsDetails
                        showPcDetailsDialog.open()
                    }
                }

                // Bottom two-column row, matching the mockup's
                // '.act-row' pairing of the primary/accent action
                // with "Moonlight Settings". "View All Apps" and
                // "Wake PC" are mutually exclusive (online+paired
                // vs. !online+wakeable) so only one ever occupies
                // the primary/left slot.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Button {
                        id: viewAllAppsButton
                        Layout.fillWidth: true
                        text: qsTr("View All Apps")
                        visible: pcView.hostActionsOnline && pcView.hostActionsPaired
                        leftPadding: 10
                        rightPadding: 10
                        topPadding: 18
                        bottomPadding: 18

                        // Primary/accent-filled action -- maps to
                        // the mockup's accent-filled "Host Apps"
                        // row (.act.on).
                        background: Rectangle {
                            radius: 14
                            color: StreamingPreferences.accentColor
                            border.width: 1
                            border.color: StreamingPreferences.accentColor
                        }
                        contentItem: Text {
                            text: viewAllAppsButton.text
                            color: "white"
                            font.bold: true
                            font.pointSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            pcContextMenu.close()
                            pushAppView({"computerIndex": pcView.hostActionsIndex, "objectName": pcView.hostActionsName, "showHiddenGames": true})
                        }
                    }

                    Button {
                        id: wakePcButton
                        Layout.fillWidth: true
                        text: qsTr("Wake PC")
                        visible: !pcView.hostActionsOnline && pcView.hostActionsWakeable
                        leftPadding: 10
                        rightPadding: 10
                        topPadding: 18
                        bottomPadding: 18

                        // Same primary/accent slot as View All Apps
                        // above -- mutually exclusive visibility.
                        background: Rectangle {
                            radius: 14
                            color: StreamingPreferences.accentColor
                            border.width: 1
                            border.color: StreamingPreferences.accentColor
                        }
                        contentItem: Text {
                            text: wakePcButton.text
                            color: "white"
                            font.bold: true
                            font.pointSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            pcContextMenu.close()
                            computerModel.wakeComputer(pcView.hostActionsIndex)
                        }
                    }

                    Button {
                        id: moonlightSettingsButton
                        Layout.fillWidth: true
                        text: qsTr("Moonlight Settings")
                        leftPadding: 10
                        rightPadding: 10
                        topPadding: 18
                        bottomPadding: 18

                        background: Rectangle {
                            radius: 14
                            color: Qt.rgba(1, 1, 1, 0.09)
                            border.width: 1
                            border.color: "#17ffffff"
                        }
                        contentItem: Text {
                            text: moonlightSettingsButton.text
                            color: "#eef0f6"
                            font.pointSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

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
            pcList.forceActiveFocus()
        }
    }

    // Floating settings icon button -- restores access to Settings on this
    // screen now that the stock toolbar (which normally hosts the gear
    // icon) is hidden here entirely. Positioned as a small corner icon
    // rather than reviving the full toolbar, consistent with this screen's
    // otherwise chrome-free full-bleed layout.
    RoundButton {
        id: pcSettingsButton
        parent: pcView
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 14
        z: 10

        focusPolicy: Qt.NoFocus
        icon.source: "qrc:/res/settings.svg"

        ToolTip.text: qsTr("Settings")
        ToolTip.delay: 1000
        ToolTip.timeout: 3000
        ToolTip.visible: hovered

        Material.background: Qt.rgba(1, 1, 1, 0.09)

        onClicked: openMoonlightSettings()
    }

    // Floating streaming-profile chip -- always shows the active profile name
    // and jumps directly to the Streaming Profiles page in Settings on click,
    // so switching/managing profiles doesn't require digging through the
    // full Settings navigation rail. Sits just to the left of the gear icon.
    RoundButton {
        id: pcProfileButton
        parent: pcView
        anchors.top: parent.top
        anchors.right: pcSettingsButton.left
        anchors.rightMargin: 10
        anchors.topMargin: 14
        z: 10

        focusPolicy: Qt.NoFocus
        flat: true
        text: StreamingProfileManager.activeProfileName
        padding: 12
        icon.source: "qrc:/res/person.svg"
        icon.width: 16
        icon.height: 16

        ToolTip.text: qsTr("Streaming Profile")
        ToolTip.delay: 1000
        ToolTip.timeout: 3000
        ToolTip.visible: hovered

        Material.background: Qt.rgba(1, 1, 1, 0.09)
        Material.foreground: "white"

        onClicked: openStreamingProfiles()
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
