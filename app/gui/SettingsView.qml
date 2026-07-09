import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2

import StreamingProfileManager 1.0
import StreamingPreferences 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0

Item {
    id: settingsPage

    // Set by whichever screen pushed us (PcView/AppView/AppCoverflowView)
    // when a specific host is in context, so the toolbar title (bound to
    // objectName below, which main.qml's stock header displays) can read
    // "{HostName} - Host Settings" matching the mockup's Settings appbar,
    // instead of a bare "Settings" with no host context. Falls back to
    // plain "Settings" when reached with no host in context (there isn't
    // one currently, but this keeps the page usable if that ever changes).
    property string hostName: ""
    objectName: hostName !== "" ? qsTr("%1 - Host Settings").arg(hostName) : qsTr("Settings")

    signal languageChanged()

    property bool syncingStreamingProfileUi: false
    property var streamingProfileNamesModel: []
    property var streamingProfileIdsModel: []
    property int currentSectionIndex: 0
    property int initialSectionIndex: -1
    property var settingsSectionTitles: [
        qsTr("Display"),
        qsTr("Audio"),
        qsTr("Stream"),
        qsTr("Controls"),
        qsTr("Details"),
        qsTr("Personalization")
    ]

    // Streaming Profiles lives at this StackLayout index but isn't shown in the
    // visible drawer rail (settingsSectionTitles only has 6 entries) -- it's
    // reached exclusively via the floating profile button on Host Select/App
    // Grid, which pushes this page with initialSectionIndex set to this value.
    readonly property int streamingProfilesSectionIndex: 6

    function currentSectionFlickable() {
        return sectionStack.itemAt(currentSectionIndex)
    }

    function isChildOfFlickable(item, flick) {
        while (item) {
            if (item.parent === flick.contentItem) {
                return true
            }

            item = item.parent
        }
        return false
    }

    NumberAnimation {
        id: autoScrollAnimation
        property: "contentY"
        duration: 100
    }

    Window.onActiveFocusItemChanged: {
        var item = Window.activeFocusItem
        var flick = currentSectionFlickable()
        if (item && flick) {
            // Ignore non-child elements like the toolbar buttons or controls in other (hidden) sections
            if (!isChildOfFlickable(item, flick)) {
                return
            }

            // Map the focus item's position into the active section's content item coordinate space
            var pos = item.mapToItem(flick.contentItem, 0, 0)

            // Ensure some extra space is visible around the element we're scrolling to
            var scrollMargin = flick.height > 100 ? 50 : 0

            autoScrollAnimation.target = flick

            if (pos.y - scrollMargin < flick.contentY) {
                autoScrollAnimation.from = flick.contentY
                autoScrollAnimation.to = Math.max(pos.y - scrollMargin, 0)
                autoScrollAnimation.start()
            }
            else if (pos.y + item.height + scrollMargin > flick.contentY + flick.height) {
                autoScrollAnimation.from = flick.contentY
                autoScrollAnimation.to = Math.min(pos.y + item.height + scrollMargin - flick.height, flick.contentHeight - flick.height)
                autoScrollAnimation.start()
            }
        }
    }

    StackView.onActivated: {
        // This enables Tab and BackTab based navigation rather than arrow keys.
        // It is required to shift focus between controls on the settings page.
        SdlGamepadKeyNavigation.setUiNavMode(true)

        // Highlight the first item if a gamepad is connected
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            resolutionComboBox.forceActiveFocus(Qt.TabFocus)
        }
    }

    function refreshStreamingProfiles() {
        streamingProfileNamesModel = StreamingProfileManager.profileNames()
        streamingProfileIdsModel = StreamingProfileManager.profileIds()

        if (!streamingProfileComboBox) {
            return
        }

        var activeIndex = -1
        for (var i = 0; i < streamingProfileIdsModel.length; i++) {
            if (streamingProfileIdsModel[i] === StreamingProfileManager.activeProfileId) {
                activeIndex = i
                break
            }
        }
        if (activeIndex >= 0) {
            streamingProfileComboBox.currentIndex = activeIndex
        }
        else if (streamingProfileIdsModel.length > 0) {
            streamingProfileComboBox.currentIndex = 0
        }
        else {
            streamingProfileComboBox.currentIndex = -1
        }
    }

    function syncStreamingProfileControls() {
        syncingStreamingProfileUi = true
        try {
            var savedWidth = StreamingPreferences.width
            var savedHeight = StreamingPreferences.height
            var resolutionIndex = -1
            var customResolutionIndex = -1
            for (var i = 0; i < resolutionListModel.count; i++) {
                var resolutionWidth = parseInt(resolutionListModel.get(i).video_width)
                var resolutionHeight = parseInt(resolutionListModel.get(i).video_height)

                if (resolutionListModel.get(i).is_custom) {
                    customResolutionIndex = i
                }

                if (savedWidth === resolutionWidth && savedHeight === resolutionHeight) {
                    resolutionIndex = i
                }
            }

            if (resolutionIndex >= 0) {
                resolutionComboBox.currentIndex = resolutionIndex
                if (customResolutionIndex >= 0) {
                    resolutionListModel.setProperty(customResolutionIndex, "text", qsTr("Custom"))
                    resolutionListModel.setProperty(customResolutionIndex, "video_width", "")
                    resolutionListModel.setProperty(customResolutionIndex, "video_height", "")
                }
            }
            else if (customResolutionIndex >= 0) {
                resolutionListModel.setProperty(customResolutionIndex, "text", qsTr("Custom") + " (" + savedWidth + "x" + savedHeight + ")")
                resolutionListModel.setProperty(customResolutionIndex, "video_width", "" + savedWidth)
                resolutionListModel.setProperty(customResolutionIndex, "video_height", "" + savedHeight)
                resolutionComboBox.currentIndex = customResolutionIndex
            }
            resolutionComboBox.lastIndexValue = resolutionComboBox.currentIndex
            resolutionComboBox.recalculateWidth()

            var savedFps = StreamingPreferences.fps
            var fpsIndex = -1
            var customFpsIndex = -1
            for (i = 0; i < fpsListModel.count; i++) {
                var existingFps = parseInt(fpsListModel.get(i).video_fps)
                if (fpsListModel.get(i).is_custom) {
                    customFpsIndex = i
                }

                if (savedFps === existingFps) {
                    fpsIndex = i
                }
            }

            if (fpsIndex >= 0) {
                fpsComboBox.currentIndex = fpsIndex
                if (customFpsIndex >= 0) {
                    fpsListModel.setProperty(customFpsIndex, "text", qsTr("Custom"))
                    fpsListModel.setProperty(customFpsIndex, "video_fps", "")
                }
            }
            else if (customFpsIndex >= 0) {
                fpsListModel.setProperty(customFpsIndex, "text", qsTr("Custom (%1 FPS)").arg(savedFps))
                fpsListModel.setProperty(customFpsIndex, "video_fps", "" + savedFps)
                fpsComboBox.currentIndex = customFpsIndex
            }
            fpsComboBox.lastIndexValue = fpsComboBox.currentIndex
            fpsComboBox.recalculateWidth()

            if (windowModeComboBox.visible && windowModeComboBox.model) {
                for (i = 0; i < windowModeComboBox.model.count; i++) {
                    if (windowModeComboBox.model.get(i).val === StreamingPreferences.windowMode) {
                        windowModeComboBox.currentIndex = i
                        break
                    }
                }
            }

            for (i = 0; i < audioListModel.count; i++) {
                if (audioListModel.get(i).val === StreamingPreferences.audioConfig) {
                    audioComboBox.currentIndex = i
                    break
                }
            }

            for (i = 0; i < decoderListModel.count; i++) {
                if (decoderListModel.get(i).val === StreamingPreferences.videoDecoderSelection) {
                    decoderComboBox.currentIndex = i
                    break
                }
            }

            codecComboBox.currentIndex = 0
            for (i = 0; i < codecListModel.count; i++) {
                if (codecListModel.get(i).val === StreamingPreferences.videoCodecConfig) {
                    codecComboBox.currentIndex = i
                    break
                }
            }

            slider.value = Qt.binding(function() { return StreamingPreferences.bitrateKbps })
            bitrateTitle.text = qsTr("Video bitrate: %1 Mbps").arg(StreamingPreferences.bitrateKbps / 1000.0)

            vsyncCheck.checked = Qt.binding(function() { return StreamingPreferences.enableVsync })
            framePacingCheck.checked = Qt.binding(function() { return StreamingPreferences.enableVsync && StreamingPreferences.framePacing })
            enableHdr.checked = Qt.binding(function() { return enableHdr.enabled && StreamingPreferences.enableHdr })
            audioPcCheck.checked = Qt.binding(function() { return !StreamingPreferences.playAudioOnHost })
            quitAppAfter.checked = Qt.binding(function() { return StreamingPreferences.quitAppAfter })
            singleControllerCheck.checked = Qt.binding(function() { return !StreamingPreferences.multiController })
            enableYUV444.checked = Qt.binding(function() { return StreamingPreferences.enableYUV444 })
            unlockBitrate.checked = Qt.binding(function() { return StreamingPreferences.unlockBitrate })
        }
        finally {
            syncingStreamingProfileUi = false
        }
    }

    function selectedStreamingProfileId() {
        if (!streamingProfileComboBox || streamingProfileComboBox.currentIndex < 0 ||
                streamingProfileComboBox.currentIndex >= streamingProfileIdsModel.length) {
            return ""
        }

        return streamingProfileIdsModel[streamingProfileComboBox.currentIndex]
    }

    function selectedStreamingProfileName() {
        if (!streamingProfileComboBox || streamingProfileComboBox.currentIndex < 0 ||
                streamingProfileComboBox.currentIndex >= streamingProfileNamesModel.length) {
            return ""
        }

        return streamingProfileNamesModel[streamingProfileComboBox.currentIndex]
    }

    function isStreamingProfileNameAvailable(name, excludedProfileId) {
        var normalizedName = name.trim().toLowerCase()
        if (!normalizedName.length) {
            return false
        }

        for (var i = 0; i < streamingProfileNamesModel.length; i++) {
            var currentId = i < streamingProfileIdsModel.length ? streamingProfileIdsModel[i] : ""
            if (currentId !== excludedProfileId &&
                    streamingProfileNamesModel[i].trim().toLowerCase() === normalizedName) {
                return false
            }
        }

        return true
    }

    Component.onCompleted: {
        refreshStreamingProfiles()
        if (initialSectionIndex >= 0) {
            currentSectionIndex = initialSectionIndex
        }
    }

    Connections {
        target: StreamingProfileManager
        onProfileListChanged: settingsPage.refreshStreamingProfiles()
        onActiveProfileChanged: {
            settingsPage.refreshStreamingProfiles()
            settingsPage.syncStreamingProfileControls()
        }
    }

    StackView.onDeactivating: {
        SdlGamepadKeyNavigation.setUiNavMode(false)

        // Save the prefs so the Session can observe the changes
        StreamingPreferences.save()
    }

    Component.onDestruction: {
        // Also save preferences on destruction, since we won't get a
        // deactivating callback if the user just closes Moonlight
        StreamingPreferences.save()
    }

    AuroraBackground {
    }

    Rectangle {
        id: setShell
        anchors.fill: parent
        anchors.topMargin: 26
        anchors.leftMargin: 30
        anchors.rightMargin: 30
        anchors.bottomMargin: 30
        radius: 20
        color: "#8c141622"
        border.width: 1
        border.color: "#17ffffff"
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: settingsDrawer
                Layout.preferredWidth: 230
                Layout.fillHeight: true
                color: "transparent"

                Rectangle {
                    width: 1
                    color: "#17ffffff"
                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 22
                    anchors.bottomMargin: 22
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 6

                    Repeater {
                        model: settingsSectionTitles

                        delegate: Button {
                            id: sectionRow
                            Layout.fillWidth: true
                            implicitHeight: sectionLabel.implicitHeight + 26
                            flat: true
                            hoverEnabled: true
                            focusPolicy: Qt.StrongFocus
                            text: modelData
                            onClicked: settingsPage.currentSectionIndex = index

                            background: Rectangle {
                                radius: 12
                                color: index === settingsPage.currentSectionIndex ? StreamingPreferences.accentColor :
                                       sectionRow.hovered ? "#0effffff" : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: 100 }
                                }
                            }

                            contentItem: Label {
                                id: sectionLabel
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                verticalAlignment: Text.AlignVCenter
                                text: modelData
                                font.pointSize: 11
                                font.bold: index === settingsPage.currentSectionIndex
                                color: index === settingsPage.currentSectionIndex ? "#ffffff" :
                                       sectionRow.hovered ? "#eef0f6" : "#9aa0b0"
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            StackLayout {
                id: sectionStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: settingsPage.currentSectionIndex

        Flickable {
            id: basicSettingsPane
            clip: true
            contentWidth: width
            contentHeight: basicSettingsColumn.height + 56
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: basicSettingsColumn
                x: 34
                y: 28
                width: parent.width - 68
                spacing: 5

                SectionHeader {
                    width: parent.width
                    id: resFPStitle
                    text: qsTr("Resolution and FPS")
                    isFirst: true
                }

                Label {
                    width: parent.width
                    id: resFPSdesc
                    text: qsTr("Setting values too high for your PC or network connection may cause lag, stuttering, or errors.")
                    font.pointSize: 9
                    color: "#9aa0b0"
                    wrapMode: Text.Wrap
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Resolution & Frame Rate")

                Row {
                    spacing: 5

                    AutoResizingComboBox {
                        property int lastIndexValue

                        function addDetectedResolution(friendlyNamePrefix, rect) {
                            var indexToAdd = 0
                            for (var j = 0; j < resolutionComboBox.count; j++) {
                                var existing_width = parseInt(resolutionListModel.get(j).video_width);
                                var existing_height = parseInt(resolutionListModel.get(j).video_height);

                                if (rect.width === existing_width && rect.height === existing_height) {
                                    // Duplicate entry, skip
                                    indexToAdd = -1
                                    break
                                }
                                else if (rect.width * rect.height > existing_width * existing_height) {
                                    // Candidate entrypoint after this entry
                                    indexToAdd = j + 1
                                }
                            }

                            // Insert this display's resolution if it's not a duplicate
                            if (indexToAdd >= 0) {
                                resolutionListModel.insert(indexToAdd,
                                                           {
                                                               "text": friendlyNamePrefix+" ("+rect.width+"x"+rect.height+")",
                                                               "video_width": ""+rect.width,
                                                               "video_height": ""+rect.height,
                                                               "is_custom": false
                                                           })
                            }
                        }

                        // ignore setting the index at first, and actually set it when the component is loaded
                        Component.onCompleted: {
                            // Refresh display data before using it to build the list
                            SystemProperties.refreshDisplays()

                            // Add native and safe area resolutions for all attached displays
                            var done = false
                            for (var displayIndex = 0; !done; displayIndex++) {
                                var screenRect = SystemProperties.getNativeResolution(displayIndex);
                                var safeAreaRect = SystemProperties.getSafeAreaResolution(displayIndex);

                                if (screenRect.width === 0) {
                                    // Exceeded max count of displays
                                    done = true
                                    break
                                }

                                addDetectedResolution(qsTr("Native"), screenRect)
                                addDetectedResolution(qsTr("Native (Excluding Notch)"), safeAreaRect)
                            }

                            // Prune resolutions that are over the decoder's maximum
                            var max_pixels = SystemProperties.maximumResolution.width * SystemProperties.maximumResolution.height;
                            if (max_pixels > 0) {
                                for (var j = 0; j < resolutionComboBox.count; j++) {
                                    var existing_width = parseInt(resolutionListModel.get(j).video_width);
                                    var existing_height = parseInt(resolutionListModel.get(j).video_height);

                                    if (existing_width * existing_height > max_pixels) {
                                        resolutionListModel.remove(j)
                                        j--
                                    }
                                }
                            }

                            // load the saved width/height, and iterate through the ComboBox until a match is found
                            // and set it to that index.
                            var saved_width = StreamingPreferences.width
                            var saved_height = StreamingPreferences.height
                            var index_set = false
                            for (var i = 0; i < resolutionListModel.count; i++) {
                                var el_width = parseInt(resolutionListModel.get(i).video_width);
                                var el_height = parseInt(resolutionListModel.get(i).video_height);

                                if (saved_width === el_width && saved_height === el_height) {
                                    currentIndex = i
                                    index_set = true
                                    break
                                }
                            }

                            if (!index_set) {
                                // We did not find a match. This must be a custom resolution.
                                resolutionListModel.append({
                                                               "text": qsTr("Custom")+" ("+StreamingPreferences.width+"x"+StreamingPreferences.height+")",
                                                               "video_width": ""+StreamingPreferences.width,
                                                               "video_height": ""+StreamingPreferences.height,
                                                               "is_custom": true
                                                           })
                                currentIndex = resolutionListModel.count - 1
                            }
                            else {
                                resolutionListModel.append({
                                                               "text": qsTr("Custom"),
                                                               "video_width": "",
                                                               "video_height": "",
                                                               "is_custom": true
                                                           })
                            }

                            // Since we don't call activate() here, we need to trigger
                            // width calculation manually
                            recalculateWidth()

                            lastIndexValue = currentIndex
                        }

                        id: resolutionComboBox
                        maximumWidth: 180
                        textRole: "text"
                        model: ListModel {
                            id: resolutionListModel
                            // Other elements may be added at runtime
                            // based on attached display resolution
                            ListElement {
                                text: qsTr("720p")
                                video_width: "1280"
                                video_height: "720"
                                is_custom: false
                            }
                            ListElement {
                                text: qsTr("1080p")
                                video_width: "1920"
                                video_height: "1080"
                                is_custom: false
                            }
                            ListElement {
                                text: qsTr("1440p")
                                video_width: "2560"
                                video_height: "1440"
                                is_custom: false
                            }
                            ListElement {
                                text: qsTr("4K")
                                video_width: "3840"
                                video_height: "2160"
                                is_custom: false
                            }
                        }

                        function updateBitrateForSelection() {
                            var selectedWidth = parseInt(resolutionListModel.get(currentIndex).video_width)
                            var selectedHeight = parseInt(resolutionListModel.get(currentIndex).video_height)

                            // Only modify the bitrate if the values actually changed
                            if (StreamingPreferences.width !== selectedWidth || StreamingPreferences.height !== selectedHeight) {
                                StreamingPreferences.width = selectedWidth
                                StreamingPreferences.height = selectedHeight

                                if (StreamingPreferences.autoAdjustBitrate) {
                                    StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(StreamingPreferences.width,
                                                                                                              StreamingPreferences.height,
                                                                                                              StreamingPreferences.fps,
                                                                                                              StreamingPreferences.enableYUV444);
                                    slider.value = StreamingPreferences.bitrateKbps
                                }
                            }

                            lastIndexValue = currentIndex
                        }

                        // ::onActivated must be used, as it only listens for when the index is changed by a human
                        onActivated : {
                            if (resolutionListModel.get(currentIndex).is_custom) {
                                customResolutionDialog.open()
                            }
                            else {
                                updateBitrateForSelection()
                            }
                        }

                        NavigableDialog {
                            id: customResolutionDialog
                            standardButtons: Dialog.Ok | Dialog.Cancel
                            onOpened: {
                                // Force keyboard focus on the textbox so keyboard navigation works
                                widthField.forceActiveFocus()

                                // standardButton() was added in Qt 5.10, so we must check for it first
                                if (customResolutionDialog.standardButton) {
                                    customResolutionDialog.standardButton(Dialog.Ok).enabled = customResolutionDialog.isInputValid()
                                }
                            }

                            onClosed: {
                                widthField.clear()
                                heightField.clear()
                            }

                            onRejected: {
                                resolutionComboBox.currentIndex = resolutionComboBox.lastIndexValue
                            }

                            function isInputValid() {
                                // If we have text in either textbox that isn't valid,
                                // reject the input.
                                if ((!widthField.acceptableInput && widthField.text) ||
                                        (!heightField.acceptableInput && heightField.text)) {
                                    return false
                                }

                                // The textboxes need to have text or placeholder text
                                if ((!widthField.text && !widthField.placeholderText) ||
                                        (!heightField.text && !heightField.placeholderText)) {
                                    return false
                                }

                                return true
                            }

                            onAccepted: {
                                // Reject if there's invalid input
                                if (!isInputValid()) {
                                    reject()
                                    return
                                }

                                var width = widthField.text ? widthField.text : widthField.placeholderText
                                var height = heightField.text ? heightField.text : heightField.placeholderText

                                // Find and update the custom entry
                                for (var i = 0; i < resolutionListModel.count; i++) {
                                    if (resolutionListModel.get(i).is_custom) {
                                        resolutionListModel.setProperty(i, "video_width", width)
                                        resolutionListModel.setProperty(i, "video_height", height)
                                        resolutionListModel.setProperty(i, "text", "Custom ("+width+"x"+height+")")

                                        // Now update the bitrate using the custom resolution
                                        resolutionComboBox.currentIndex = i
                                        resolutionComboBox.updateBitrateForSelection()

                                        // Update the combobox width too
                                        resolutionComboBox.recalculateWidth()
                                        break
                                    }
                                }
                            }

                            ColumnLayout {
                                Label {
                                    text: qsTr("Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.") + "\n\n" +
                                          qsTr("Resolutions that are not supported by your client or host PC may cause streaming errors.") + "\n"
                                    wrapMode: Label.WordWrap
                                    Layout.maximumWidth: 300
                                }

                                Label {
                                    text: qsTr("Enter a custom resolution:")
                                    font.bold: true
                                }

                                RowLayout {
                                    TextField {
                                        id: widthField
                                        maximumLength: 5
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        placeholderText: resolutionListModel.get(resolutionComboBox.currentIndex).video_width
                                        validator: IntValidator{bottom:256; top:8192}
                                        focus: true

                                        onTextChanged: {
                                            // standardButton() was added in Qt 5.10, so we must check for it first
                                            if (customResolutionDialog.standardButton) {
                                                customResolutionDialog.standardButton(Dialog.Ok).enabled = customResolutionDialog.isInputValid()
                                            }
                                        }

                                        Keys.onReturnPressed: {
                                            customResolutionDialog.accept()
                                        }

                                        Keys.onEnterPressed: {
                                            customResolutionDialog.accept()
                                        }
                                    }

                                    Label {
                                        text: "x"
                                        font.bold: true
                                    }

                                    TextField {
                                        id: heightField
                                        maximumLength: 5
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        placeholderText: resolutionListModel.get(resolutionComboBox.currentIndex).video_height
                                        validator: IntValidator{bottom:256; top:8192}

                                        onTextChanged: {
                                            // standardButton() was added in Qt 5.10, so we must check for it first
                                            if (customResolutionDialog.standardButton) {
                                                customResolutionDialog.standardButton(Dialog.Ok).enabled = customResolutionDialog.isInputValid()
                                            }
                                        }

                                        Keys.onReturnPressed: {
                                            customResolutionDialog.accept()
                                        }

                                        Keys.onEnterPressed: {
                                            customResolutionDialog.accept()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    AutoResizingComboBox {
                        property int lastIndexValue

                        function updateBitrateForSelection() {
                            // Only modify the bitrate if the values actually changed
                            var selectedFps = parseInt(model.get(fpsComboBox.currentIndex).video_fps)
                            if (StreamingPreferences.fps !== selectedFps) {
                                StreamingPreferences.fps = selectedFps

                                if (StreamingPreferences.autoAdjustBitrate) {
                                    StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(StreamingPreferences.width,
                                                                                                              StreamingPreferences.height,
                                                                                                              StreamingPreferences.fps,
                                                                                                              StreamingPreferences.enableYUV444);
                                    slider.value = StreamingPreferences.bitrateKbps
                                }
                            }

                            lastIndexValue = currentIndex
                        }

                        NavigableDialog {
                            function isInputValid() {
                                // If we have text that isn't valid, reject the input.
                                if (!fpsField.acceptableInput && fpsField.text) {
                                    return false
                                }

                                // The textbox needs to have text or placeholder text
                                if (!fpsField.text && !fpsField.placeholderText) {
                                    return false
                                }

                                return true
                            }

                            id: customFpsDialog
                            standardButtons: Dialog.Ok | Dialog.Cancel
                            onOpened: {
                                // Force keyboard focus on the textbox so keyboard navigation works
                                fpsField.forceActiveFocus()

                                // standardButton() was added in Qt 5.10, so we must check for it first
                                if (customFpsDialog.standardButton) {
                                    customFpsDialog.standardButton(Dialog.Ok).enabled = customFpsDialog.isInputValid()
                                }
                            }

                            onClosed: {
                                fpsField.clear()
                            }

                            onRejected: {
                                fpsComboBox.currentIndex = fpsComboBox.lastIndexValue
                            }

                            onAccepted: {
                                // Reject if there's invalid input
                                if (!isInputValid()) {
                                    reject()
                                    return
                                }

                                var fps = fpsField.text ? fpsField.text : fpsField.placeholderText

                                // Find and update the custom entry
                                for (var i = 0; i < fpsListModel.count; i++) {
                                    if (fpsListModel.get(i).is_custom) {
                                        fpsListModel.setProperty(i, "video_fps", fps)
                                        fpsListModel.setProperty(i, "text", qsTr("Custom (%1 FPS)").arg(fps))

                                        // Now update the bitrate using the custom resolution
                                        fpsComboBox.currentIndex = i
                                        fpsComboBox.updateBitrateForSelection()

                                        // Update the combobox width too
                                        fpsComboBox.recalculateWidth()
                                        break
                                    }
                                }
                            }

                            ColumnLayout {
                                Label {
                                    text: qsTr("Enter a custom frame rate:")
                                    font.bold: true
                                }

                                RowLayout {
                                    TextField {
                                        id: fpsField
                                        maximumLength: 4
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        placeholderText: fpsListModel.get(fpsComboBox.currentIndex).video_fps
                                        validator: IntValidator{bottom:10; top:9999}
                                        focus: true

                                        onTextChanged: {
                                            // standardButton() was added in Qt 5.10, so we must check for it first
                                            if (customFpsDialog.standardButton) {
                                                customFpsDialog.standardButton(Dialog.Ok).enabled = customFpsDialog.isInputValid()
                                            }
                                        }

                                        Keys.onReturnPressed: {
                                            customFpsDialog.accept()
                                        }

                                        Keys.onEnterPressed: {
                                            customFpsDialog.accept()
                                        }
                                    }
                                }
                            }
                        }

                        function addRefreshRateOrdered(fpsListModel, refreshRate, description, custom) {
                            var indexToAdd = 0
                            for (var j = 0; j < fpsListModel.count; j++) {
                                var existing_fps = parseInt(fpsListModel.get(j).video_fps);

                                if (refreshRate === existing_fps || (custom && fpsListModel.get(j).is_custom)) {
                                    // Duplicate entry, skip
                                    indexToAdd = -1
                                    break
                                }
                                else if (refreshRate > existing_fps) {
                                    // Candidate entrypoint after this entry
                                    indexToAdd = j + 1
                                }
                            }

                            // Insert this frame rate if it's not a duplicate
                            if (indexToAdd >= 0) {
                                // Custom values always go at the end of the list
                                if (custom) {
                                    indexToAdd = fpsListModel.count
                                }

                                fpsListModel.insert(indexToAdd,
                                                    {
                                                        "text": description,
                                                        "video_fps": ""+refreshRate,
                                                        "is_custom": custom
                                                    })
                            }

                            return indexToAdd
                        }

                        function reinitialize() {
                            // Add native refresh rate for all attached displays
                            var done = false
                            for (var displayIndex = 0; !done; displayIndex++) {
                                var refreshRate = SystemProperties.getRefreshRate(displayIndex);
                                if (refreshRate === 0) {
                                    // Exceeded max count of displays
                                    done = true
                                    break
                                }

                                addRefreshRateOrdered(fpsListModel, refreshRate, qsTr("%1 FPS").arg(refreshRate), false)
                            }

                            var saved_fps = StreamingPreferences.fps
                            var found = false
                            for (var i = 0; i < model.count; i++) {
                                var el_fps = parseInt(model.get(i).video_fps);

                                // Look for a matching frame rate
                                if (saved_fps === el_fps) {
                                    currentIndex = i
                                    found = true
                                    break
                                }
                            }

                            // If we didn't find one, add a custom frame rate for the current value
                            if (!found) {
                                currentIndex = addRefreshRateOrdered(model, saved_fps, qsTr("Custom (%1 FPS)").arg(saved_fps), true)
                            }
                            else {
                                addRefreshRateOrdered(model, "", qsTr("Custom"), true)
                            }

                            recalculateWidth()

                            lastIndexValue = currentIndex
                        }

                        // ignore setting the index at first, and actually set it when the component is loaded
                        Component.onCompleted: {
                            reinitialize()
                            languageChanged.connect(reinitialize)
                        }

                        model: ListModel {
                            id: fpsListModel
                            // Other elements may be added at runtime
                            ListElement {
                                text: qsTr("30 FPS")
                                video_fps: "30"
                                is_custom: false
                            }
                            ListElement {
                                text: qsTr("60 FPS")
                                video_fps: "60"
                                is_custom: false
                            }
                        }

                        id: fpsComboBox
                        maximumWidth: 140
                        textRole: "text"
                        // ::onActivated must be used, as it only listens for when the index is changed by a human
                        onActivated : {
                            if (model.get(currentIndex).is_custom) {
                                customFpsDialog.open()
                            }
                            else {
                                updateBitrateForSelection()
                            }
                        }
                    }
                }
                }

                SettingRow {
                    width: parent.width
                    label: bitrateTitle.text
                    description: bitrateDesc.text

                Label {
                    width: parent.width
                    id: bitrateTitle
                    text: qsTr("Video bitrate:")
                    font.pointSize: 12
                    wrapMode: Text.Wrap
                    visible: false
                }

                Label {
                    width: parent.width
                    id: bitrateDesc
                    text: qsTr("Lower the bitrate on slower connections. Raise the bitrate to increase image quality.")
                    font.pointSize: 9
                    wrapMode: Text.Wrap
                    visible: false
                }

                Slider {
                    id: slider

                    value: StreamingPreferences.bitrateKbps

                    stepSize: 500
                    from : 500
                    to: StreamingPreferences.unlockBitrate ? 500000 : 150000

                    // SnapAlways (rather than SnapOnRelease) quantizes value to stepSize
                    // *during* the drag, not just on release. With the huge 500-150000/500000
                    // range here, SnapOnRelease let value track the mouse continuously as a
                    // raw float, so "value / 1000.0" produced a distinct new decimal string on
                    // nearly every pixel of movement -- forcing a text re-shape every tick.
                    // The other sliders (tile scale/gap) don't show this because their small
                    // ranges combined with Math.round() naturally dedupe to the same displayed
                    // integer across many consecutive drag ticks, so Qt skips the relayout.
                    snapMode: "SnapAlways"
                    width: 400

                    onValueChanged: {
                        bitrateTitle.text = qsTr("Video bitrate: %1 Mbps").arg(Math.round(value / 100) / 10)
                        if (settingsPage.syncingStreamingProfileUi) {
                            return
                        }
                        StreamingPreferences.bitrateKbps = value
                    }

                    onMoved: {
                        StreamingPreferences.autoAdjustBitrate = false
                    }

                    Component.onCompleted: {
                        // Refresh the text after translations change
                        languageChanged.connect(valueChanged)
                    }
                }
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Display mode")
                    visible: SystemProperties.hasDesktopEnvironment

                AutoResizingComboBox {
                    function createModel() {
                        var model = Qt.createQmlObject('import QtQuick 2.0; ListModel {}', parent, '')

                        model.append({
                                         text: qsTr("Fullscreen"),
                                         val: StreamingPreferences.WM_FULLSCREEN
                                     })

                        model.append({
                                         text: qsTr("Borderless windowed"),
                                         val: StreamingPreferences.WM_FULLSCREEN_DESKTOP
                                     })

                        model.append({
                                         text: qsTr("Windowed"),
                                         val: StreamingPreferences.WM_WINDOWED
                                     })


                        // Set the recommended option based on the OS
                        for (var i = 0; i < model.count; i++) {
                            var thisWm = model.get(i).val;
                            if (thisWm === StreamingPreferences.recommendedFullScreenMode) {
                                model.get(i).text += " " + qsTr("(Recommended)")
                                model.move(i, 0, 1)
                                break
                            }
                        }

                        return model
                    }


                    // This is used on initialization and upon retranslation
                    function reinitialize() {
                        if (!visible) {
                            // Do nothing if the control won't even be visible
                            return
                        }

                        model = createModel()
                        currentIndex = 0

                        // Set the current value based on the saved preferences
                        var savedWm = StreamingPreferences.windowMode
                        for (var i = 0; i < model.count; i++) {
                             var thisWm = model.get(i).val;
                             if (savedWm === thisWm) {
                                 currentIndex = i
                                 break
                             }
                        }

                        activated(currentIndex)
                    }

                    Component.onCompleted: {
                        reinitialize()
                        languageChanged.connect(reinitialize)
                    }

                    id: windowModeComboBox
                    maximumWidth: 260
                    visible: SystemProperties.hasDesktopEnvironment
                    enabled: !SystemProperties.rendererAlwaysFullScreen
                    hoverEnabled: true
                    textRole: "text"
                    onActivated: {
                        StreamingPreferences.windowMode = model.get(currentIndex).val
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Fullscreen generally provides the best performance, but borderless windowed may work better with features like macOS Spaces, Alt+Tab, screenshot tools, on-screen overlays, etc.")
                }
                }

                SectionHeader {
                    width: parent.width
                    text: qsTr("Options")
                }

                RowLayout {
                    width: parent.width
                    spacing: 24

                    Label {
                        text: qsTr("V-Sync / Frame Pacing")
                        font.pointSize: 12
                        color: "#eef0f6"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    ToggleSwitch {
                        id: vsyncCheck
                        hoverEnabled: true
                        text: qsTr("V-Sync")
                        font.pointSize:  12
                        checked: StreamingPreferences.enableVsync
                        onCheckedChanged: {
                            if (settingsPage.syncingStreamingProfileUi) {
                                return
                            }
                            StreamingPreferences.enableVsync = checked
                        }

                        ToolTip.delay: 1000
                        ToolTip.timeout: 5000
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Disabling V-Sync allows sub-frame rendering latency, but it can display visible tearing")
                    }

                    ToggleSwitch {
                        id: framePacingCheck
                        hoverEnabled: true
                        text: qsTr("Frame pacing")
                        font.pointSize:  12
                        enabled: StreamingPreferences.enableVsync
                        checked: StreamingPreferences.enableVsync && StreamingPreferences.framePacing
                        onCheckedChanged: {
                            if (settingsPage.syncingStreamingProfileUi) {
                                return
                            }
                            StreamingPreferences.framePacing = checked
                        }
                        ToolTip.delay: 1000
                        ToolTip.timeout: 5000
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Frame pacing reduces micro-stutter by delaying frames that come in too early")
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#0dffffff"
                }

                ToggleSwitch {
                    id: enableHdr
                    width: parent.width
                    divider: true
                    text: qsTr("Enable HDR")
                    font.pointSize: 12

                    enabled: SystemProperties.supportsHdr
                    checked: enabled && StreamingPreferences.enableHdr
                    onCheckedChanged: {
                        if (settingsPage.syncingStreamingProfileUi) {
                            return
                        }
                        StreamingPreferences.enableHdr = checked
                    }

                    // Updating StreamingPreferences.videoCodecConfig is handled above

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: enabled ?
                                      qsTr("The stream will be HDR-capable, but some games may require an HDR monitor on your host PC to enable HDR mode.")
                                    :
                                      qsTr("HDR streaming is not supported on this PC.")
                }
            }
        }

        Flickable {
            id: audioSettingsPane
            clip: true
            contentWidth: width
            contentHeight: audioSettingsColumn.height + 56
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: audioSettingsColumn
                x: 34
                y: 28
                width: parent.width - 68
                spacing: 5

                SectionHeader {
                    width: parent.width
                    id: resAudioTitle
                    text: qsTr("Audio configuration")
                    isFirst: true
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Audio Channels")

                AutoResizingComboBox {
                    // ignore setting the index at first, and actually set it when the component is loaded
                    Component.onCompleted: {
                        var saved_audio = StreamingPreferences.audioConfig
                        currentIndex = 0
                        for (var i = 0; i < audioListModel.count; i++) {
                            var el_audio = audioListModel.get(i).val;
                            if (saved_audio === el_audio) {
                                currentIndex = i
                                break
                            }
                        }
                        activated(currentIndex)
                    }

                    id: audioComboBox
                    maximumWidth: 260
                    textRole: "text"
                    model: ListModel {
                        id: audioListModel
                        ListElement {
                            text: qsTr("Stereo")
                            val: StreamingPreferences.AC_STEREO
                        }
                        ListElement {
                            text: qsTr("5.1 surround sound")
                            val: StreamingPreferences.AC_51_SURROUND
                        }
                        ListElement {
                            text: qsTr("7.1 surround sound")
                            val: StreamingPreferences.AC_71_SURROUND
                        }
                    }
                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated : {
                        StreamingPreferences.audioConfig = audioListModel.get(currentIndex).val
                    }
                }
                }


                ToggleSwitch {
                    id: audioPcCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Mute host PC speakers while streaming")
                    font.pointSize: 12
                    checked: !StreamingPreferences.playAudioOnHost
                    onCheckedChanged: {
                        if (settingsPage.syncingStreamingProfileUi) {
                            return
                        }
                        StreamingPreferences.playAudioOnHost = !checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("You must restart any game currently in progress for this setting to take effect")
                }

                ToggleSwitch {
                    id: muteOnFocusLossCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Mute audio stream when Moonlight is not the active window")
                    font.pointSize: 12
                    visible: SystemProperties.hasDesktopEnvironment
                    checked: StreamingPreferences.muteOnFocusLoss
                    onCheckedChanged: {
                        StreamingPreferences.muteOnFocusLoss = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Mutes Moonlight's audio when you Alt+Tab out of the stream or click on a different window.")
                }
            }
        }

        Flickable {
            id: streamSettingsPane
            clip: true
            contentWidth: width
            contentHeight: streamSettingsColumn.height + 56
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: streamSettingsColumn
                x: 34
                y: 28
                width: parent.width - 68
                spacing: 5

                SectionHeader {
                    width: parent.width
                    text: qsTr("General")
                    isFirst: true
                }

                ToggleSwitch {
                    id: optimizeGameSettingsCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Optimize game settings for streaming")
                    font.pointSize:  12
                    checked: StreamingPreferences.gameOptimizations
                    onCheckedChanged: {
                        StreamingPreferences.gameOptimizations = checked
                    }
                }

                ToggleSwitch {
                    id: quitAppAfter
                    width: parent.width
                    divider: true
                    text: qsTr("Quit app on host PC after ending stream")
                    font.pointSize: 12
                    checked: StreamingPreferences.quitAppAfter
                    onCheckedChanged: {
                        if (settingsPage.syncingStreamingProfileUi) {
                            return
                        }
                        StreamingPreferences.quitAppAfter = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("This will close the app or game you are streaming when you end your stream. You will lose any unsaved progress!")
                }


                SectionHeader {
                    width: parent.width
                    id: resVDSTitle
                    text: qsTr("Video decoder")
                    isFirst: true
                }

                AutoResizingComboBox {
                    // ignore setting the index at first, and actually set it when the component is loaded
                    Component.onCompleted: {
                        var saved_vds = StreamingPreferences.videoDecoderSelection
                        currentIndex = 0
                        for (var i = 0; i < decoderListModel.count; i++) {
                            var el_vds = decoderListModel.get(i).val;
                            if (saved_vds === el_vds) {
                                currentIndex = i
                                break
                            }
                        }
                        activated(currentIndex)
                    }

                    id: decoderComboBox
                    textRole: "text"
                    model: ListModel {
                        id: decoderListModel
                        ListElement {
                            text: qsTr("Automatic (Recommended)")
                            val: StreamingPreferences.VDS_AUTO
                        }
                        ListElement {
                            text: qsTr("Force software decoding")
                            val: StreamingPreferences.VDS_FORCE_SOFTWARE
                        }
                        ListElement {
                            text: qsTr("Force hardware decoding")
                            val: StreamingPreferences.VDS_FORCE_HARDWARE
                        }
                    }
                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated: {
                        if (enabled) {
                            StreamingPreferences.videoDecoderSelection = decoderListModel.get(currentIndex).val
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#0dffffff"
                }

                SectionHeader {
                    width: parent.width
                    id: resVCCTitle
                    text: qsTr("Video codec")
                }

                AutoResizingComboBox {
                    // ignore setting the index at first, and actually set it when the component is loaded
                    Component.onCompleted: {
                        var saved_vcc = StreamingPreferences.videoCodecConfig

                        // Default to Automatic (relevant if HDR is enabled,
                        // where we will match none of the codecs in the list)
                        currentIndex = 0

                        for(var i = 0; i < codecListModel.count; i++) {
                            var el_vcc = codecListModel.get(i).val;
                            if (saved_vcc === el_vcc) {
                                currentIndex = i
                                break
                            }
                        }

                        activated(currentIndex)
                    }

                    id: codecComboBox
                    textRole: "text"
                    model: ListModel {
                        id: codecListModel
                        ListElement {
                            text: qsTr("Automatic (Recommended)")
                            val: StreamingPreferences.VCC_AUTO
                        }
                        ListElement {
                            text: qsTr("H.264")
                            val: StreamingPreferences.VCC_FORCE_H264
                        }
                        ListElement {
                            text: qsTr("HEVC (H.265)")
                            val: StreamingPreferences.VCC_FORCE_HEVC
                        }
                        ListElement {
                            text: qsTr("AV1")
                            val: StreamingPreferences.VCC_FORCE_AV1
                        }
                    }
                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated : {
                        if (enabled) {
                            StreamingPreferences.videoCodecConfig = codecListModel.get(currentIndex).val
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#0dffffff"
                }

                ToggleSwitch {
                    id: enableYUV444
                    width: parent.width
                    divider: true
                    text: qsTr("Enable YUV 4:4:4")
                    font.pointSize: 12

                    checked: StreamingPreferences.enableYUV444
                    onCheckedChanged: {
                        if (settingsPage.syncingStreamingProfileUi) {
                            return
                        }
                        // This is called on init, so only reset to default bitrate when checked state changes.
                        if (StreamingPreferences.enableYUV444 != checked) {
                            StreamingPreferences.enableYUV444 = checked
                            if (StreamingPreferences.autoAdjustBitrate) {
                                StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(StreamingPreferences.width,
                                                                                                          StreamingPreferences.height,
                                                                                                          StreamingPreferences.fps,
                                                                                                          StreamingPreferences.enableYUV444);
                                slider.value = StreamingPreferences.bitrateKbps
                            }
                        }
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: enabled ?
                                      qsTr("Good for streaming desktop and text-heavy games, but not recommended for fast-paced games.")
                                    :
                                      qsTr("YUV 4:4:4 is not supported on this PC.")
                }

                ToggleSwitch {
                    id: unlockBitrate
                    width: parent.width
                    divider: true
                    text: qsTr("Unlock bitrate limit (Experimental)")
                    font.pointSize: 12

                    checked: StreamingPreferences.unlockBitrate
                    onCheckedChanged: {
                        if (settingsPage.syncingStreamingProfileUi) {
                            return
                        }
                        StreamingPreferences.unlockBitrate = checked
                        StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, slider.to)
                        slider.value = StreamingPreferences.bitrateKbps
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("This unlocks extremely high video bitrates for use with Sunshine hosts. It should only be used when streaming over an Ethernet LAN connection.")
                }

                ToggleSwitch {
                    id: enableMdns
                    width: parent.width
                    divider: true
                    text: qsTr("Automatically find PCs on the local network (Recommended)")
                    font.pointSize: 12
                    checked: StreamingPreferences.enableMdns
                    onCheckedChanged: {
                        // This is called on init, so only do the work if we've
                        // actually changed the value.
                        if (StreamingPreferences.enableMdns != checked) {
                            StreamingPreferences.enableMdns = checked

                            // Restart polling so the mDNS change takes effect
                            if (window.pollingActive) {
                                ComputerManager.stopPollingAsync()
                                ComputerManager.startPolling()
                            }
                        }
                    }
                }

                ToggleSwitch {
                    id: detectNetworkBlocking
                    width: parent.width
                    divider: true
                    text: qsTr("Automatically detect blocked connections (Recommended)")
                    font.pointSize: 12
                    checked: StreamingPreferences.detectNetworkBlocking
                    onCheckedChanged: {
                        StreamingPreferences.detectNetworkBlocking = checked
                    }
                }

                ToggleSwitch {
                    id: showPerformanceOverlay
                    width: parent.width
                    divider: true
                    text: qsTr("Show performance stats while streaming")
                    font.pointSize: 12
                    checked: StreamingPreferences.showPerformanceOverlay
                    onCheckedChanged: {
                        StreamingPreferences.showPerformanceOverlay = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Display real-time stream performance information while streaming.") + "\n\n" +
                                  qsTr("You can toggle it at any time while streaming using Ctrl+Alt+Shift+S or Select+L1+R1+X.") + "\n\n" +
                                  qsTr("The performance overlay is not supported on Steam Link or Raspberry Pi.")
                }

                ToggleSwitch {
                    id: statsOverlayLite
                    width: parent.width
                    divider: true
                    text: qsTr("Use compact single-line stats overlay")
                    font.pointSize: 12
                    enabled: StreamingPreferences.showPerformanceOverlay
                    checked: StreamingPreferences.statsOverlayLite
                    onCheckedChanged: {
                        StreamingPreferences.statsOverlayLite = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Collapses the performance overlay to a single line showing bitrate, latency, loss, and frame rate.")
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Stats overlay font")

                AutoResizingComboBox {
                    id: statsOverlayFontComboBox
                    maximumWidth: 260
                    textRole: "text"
                    Component.onCompleted: {
                        var saved_font = StreamingPreferences.statsOverlayFont
                        currentIndex = 0
                        for (var i = 0; i < statsOverlayFontListModel.count; i++) {
                            if (saved_font === statsOverlayFontListModel.get(i).val) {
                                currentIndex = i
                                break
                            }
                        }
                    }
                    model: ListModel {
                        id: statsOverlayFontListModel
                        ListElement {
                            text: qsTr("Retro (Mode Seven)")
                            val: StreamingPreferences.SOF_MODESEVEN
                        }
                        ListElement {
                            text: qsTr("JetBrains Mono")
                            val: StreamingPreferences.SOF_JETBRAINS_MONO
                        }
                    }
                    onActivated: {
                        StreamingPreferences.statsOverlayFont = statsOverlayFontListModel.get(currentIndex).val
                    }
                }
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Stats overlay color")

                AutoResizingComboBox {
                    id: statsOverlayColorComboBox
                    maximumWidth: 260
                    textRole: "text"
                    Component.onCompleted: {
                        var saved_color = StreamingPreferences.statsOverlayColor
                        currentIndex = 0
                        for (var i = 0; i < statsOverlayColorListModel.count; i++) {
                            if (saved_color === statsOverlayColorListModel.get(i).val) {
                                currentIndex = i
                                break
                            }
                        }
                    }
                    model: ListModel {
                        id: statsOverlayColorListModel
                        ListElement {
                            text: qsTr("Yellow")
                            val: StreamingPreferences.SOC_YELLOW
                        }
                        ListElement {
                            text: qsTr("White")
                            val: StreamingPreferences.SOC_WHITE
                        }
                        ListElement {
                            text: qsTr("Green")
                            val: StreamingPreferences.SOC_GREEN
                        }
                        ListElement {
                            text: qsTr("Cyan")
                            val: StreamingPreferences.SOC_CYAN
                        }
                    }
                    onActivated: {
                        StreamingPreferences.statsOverlayColor = statsOverlayColorListModel.get(currentIndex).val
                    }
                }
                }
            }
        }

        Flickable {
            id: controlsSettingsPane
            clip: true
            contentWidth: width
            contentHeight: controlsSettingsColumn.height + 56
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: controlsSettingsColumn
                x: 34
                y: 28
                width: parent.width - 68
                spacing: 5

                SectionHeader {
                    width: parent.width
                    text: qsTr("Mouse & Keyboard")
                    isFirst: true
                }

                ToggleSwitch {
                    id: absoluteMouseCheck
                    hoverEnabled: true
                    width: parent.width
                    divider: true
                    text: qsTr("Optimize mouse for remote desktop instead of games")
                    font.pointSize:  12
                    checked: StreamingPreferences.absoluteMouseMode
                    onCheckedChanged: {
                        StreamingPreferences.absoluteMouseMode = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 10000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("This enables seamless mouse control without capturing the client's mouse cursor. It is ideal for remote desktop usage but will not work in most games.") + " " +
                                  qsTr("You can toggle this while streaming using Ctrl+Alt+Shift+M.") + "\n\n" +
                                  qsTr("NOTE: Due to a bug in GeForce Experience, this option may not work properly if your host PC has multiple monitors.")
                }

                RowLayout {
                    width: parent.width
                    spacing: 10

                    Label {
                        text: qsTr("Capture system keyboard shortcuts")
                        font.pointSize: 12
                        color: "#eef0f6"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    ToggleSwitch {
                        id: captureSysKeysCheck
                        hoverEnabled: true
                        enabled: SystemProperties.hasDesktopEnvironment
                        checked: StreamingPreferences.captureSysKeysMode !== StreamingPreferences.CSK_OFF || !SystemProperties.hasDesktopEnvironment

                        ToolTip.delay: 1000
                        ToolTip.timeout: 10000
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("This enables the capture of system-wide keyboard shortcuts like Alt+Tab that would normally be handled by the client OS while streaming.") + "\n\n" +
                                      qsTr("NOTE: Certain keyboard shortcuts like Ctrl+Alt+Del on Windows cannot be intercepted by any application, including Moonlight.")
                    }

                    AutoResizingComboBox {
                        // ignore setting the index at first, and actually set it when the component is loaded
                        Component.onCompleted: {
                            if (!visible) {
                                // Do nothing if the control won't even be visible
                                return
                            }

                            var saved_syskeysmode = StreamingPreferences.captureSysKeysMode
                            currentIndex = 0
                            for (var i = 0; i < captureSysKeysModeListModel.count; i++) {
                                var el_syskeysmode = captureSysKeysModeListModel.get(i).val;
                                if (saved_syskeysmode === el_syskeysmode) {
                                    currentIndex = i
                                    break
                                }
                            }

                            activated(currentIndex)
                            recalculateWidth()
                        }

                        maximumWidth: 220
                        enabled: captureSysKeysCheck.checked && captureSysKeysCheck.enabled
                        textRole: "text"
                        model: ListModel {
                            id: captureSysKeysModeListModel
                            ListElement {
                                text: qsTr("in fullscreen")
                                val: StreamingPreferences.CSK_FULLSCREEN
                            }
                            ListElement {
                                text: qsTr("always")
                                val: StreamingPreferences.CSK_ALWAYS
                            }
                        }

                        function updatePref() {
                            if (!enabled) {
                                StreamingPreferences.captureSysKeysMode = StreamingPreferences.CSK_OFF
                            }
                            else {
                                StreamingPreferences.captureSysKeysMode = captureSysKeysModeListModel.get(currentIndex).val
                            }
                        }

                        // ::onActivated must be used, as it only listens for when the index is changed by a human
                        onActivated: {
                            updatePref()
                        }

                        // This handles transition of the checkbox state
                        onEnabledChanged: {
                            updatePref()
                        }

                        // Defensive fallback: recalculate width once more after layout
                        // settles (see comment on the GUI display mode combo above).
                        Timer {
                            interval: 50
                            running: true
                            onTriggered: parent.recalculateWidth()
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#0dffffff"
                }

                ToggleSwitch {
                    id: absoluteTouchCheck
                    hoverEnabled: true
                    width: parent.width
                    divider: true
                    text: qsTr("Use touchscreen as a virtual trackpad")
                    font.pointSize:  12
                    checked: !StreamingPreferences.absoluteTouchMode
                    onCheckedChanged: {
                        StreamingPreferences.absoluteTouchMode = !checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("When checked, the touchscreen acts like a trackpad. When unchecked, the touchscreen will directly control the mouse pointer.")
                }

                ToggleSwitch {
                    id: swapMouseButtonsCheck
                    hoverEnabled: true
                    width: parent.width
                    divider: true
                    text: qsTr("Swap left and right mouse buttons")
                    font.pointSize:  12
                    checked: StreamingPreferences.swapMouseButtons
                    onCheckedChanged: {
                        StreamingPreferences.swapMouseButtons = checked
                    }
                }

                ToggleSwitch {
                    id: reverseScrollButtonsCheck
                    hoverEnabled: true
                    width: parent.width
                    divider: true
                    text: qsTr("Reverse mouse scrolling direction")
                    font.pointSize: 12
                    checked: StreamingPreferences.reverseScrollDirection
                    onCheckedChanged: {
                        StreamingPreferences.reverseScrollDirection = checked
                    }
                }

                SectionHeader {
                    width: parent.width
                    text: qsTr("Gamepad")
                }

                ToggleSwitch {
                    id: swapFaceButtonsCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Swap A/B and X/Y gamepad buttons")
                    font.pointSize: 12
                    checked: StreamingPreferences.swapFaceButtons
                    onCheckedChanged: {
                        StreamingPreferences.swapFaceButtons = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("This switches gamepads into a Nintendo-style button layout")
                }

                ToggleSwitch {
                    id: singleControllerCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Force gamepad #1 always connected")
                    font.pointSize:  12
                    checked: !StreamingPreferences.multiController
                    onCheckedChanged: {
                        if (settingsPage.syncingStreamingProfileUi) {
                            return
                        }
                        StreamingPreferences.multiController = !checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Forces a single gamepad to always stay connected to the host, even if no gamepads are actually connected to this PC.") + " " +
                                  qsTr("Only enable this option when streaming a game that doesn't support gamepads being connected after startup.")
                }

                ToggleSwitch {
                    id: gamepadMouseCheck
                    hoverEnabled: true
                    width: parent.width
                    divider: true
                    text: qsTr("Enable mouse control with gamepads by holding the 'Start' button")
                    font.pointSize: 12
                    checked: StreamingPreferences.gamepadMouse
                    onCheckedChanged: {
                        StreamingPreferences.gamepadMouse = checked
                    }
                }

                ToggleSwitch {
                    id: gamepadGuideButtonChordCheck
                    hoverEnabled: true
                    width: parent.width
                    divider: true
                    text: qsTr("Send Guide button press to host on Start+Select (Steam Deck)")
                    font.pointSize: 12
                    checked: StreamingPreferences.gamepadGuideButtonChord
                    onCheckedChanged: {
                        StreamingPreferences.gamepadGuideButtonChord = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Works around Steam Deck handling the Steam/Guide button locally by sending a host-side Guide button pulse after holding Start+Select for 450 ms while streaming.")
                }

                ToggleSwitch {
                    id: backgroundGamepadCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Process gamepad input when Moonlight is in the background")
                    font.pointSize: 12
                    visible: SystemProperties.hasDesktopEnvironment
                    checked: StreamingPreferences.backgroundGamepad
                    onCheckedChanged: {
                        StreamingPreferences.backgroundGamepad = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Allows Moonlight to capture gamepad inputs even if it's not the current window in focus")
                }
            }
        }

        Flickable {
            id: uiSettingsPane
            clip: true
            contentWidth: width
            contentHeight: uiSettingsColumn.height + 56
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: uiSettingsColumn
                x: 34
                y: 28
                width: parent.width - 68
                spacing: 5

                SettingRow {
                    width: parent.width
                    label: qsTr("Language")

                AutoResizingComboBox {
                    // ignore setting the index at first, and actually set it when the component is loaded
                    Component.onCompleted: {
                        var saved_language = StreamingPreferences.language
                        currentIndex = 0
                        for (var i = 0; i < languageListModel.count; i++) {
                            var el_language = languageListModel.get(i).val;
                            if (saved_language === el_language) {
                                currentIndex = i
                                break
                            }
                        }

                        activated(currentIndex)
                    }

                    id: languageComboBox
                    maximumWidth: 260
                    textRole: "text"
                    model: ListModel {
                        id: languageListModel
                        ListElement {
                            text: qsTr("Automatic")
                            val: StreamingPreferences.LANG_AUTO
                        }
                        ListElement {
                            text: "Deutsch" // German
                            val: StreamingPreferences.LANG_DE
                        }
                        ListElement {
                            text: "English"
                            val: StreamingPreferences.LANG_EN
                        }
                        ListElement {
                            text: "Français" // French
                            val: StreamingPreferences.LANG_FR
                        }
                        ListElement {
                            text: "简体中文" // Simplified Chinese
                            val: StreamingPreferences.LANG_ZH_CN
                        }
                        ListElement {
                            text: "Norwegian Bokmål"
                            val: StreamingPreferences.LANG_NB_NO
                        }
                        ListElement {
                            text: "русский" // Russian
                            val: StreamingPreferences.LANG_RU
                        }
                        ListElement {
                            text: "Español" // Spanish
                            val: StreamingPreferences.LANG_ES
                        }
                        ListElement {
                            text: "日本語" // Japanese
                            val: StreamingPreferences.LANG_JA
                        }
                        ListElement {
                            text: "Tiếng Việt" // Vietnamese
                            val: StreamingPreferences.LANG_VI
                        }
                        ListElement {
                            text: "ภาษาไทย" // Thai
                            val: StreamingPreferences.LANG_TH
                        }
                        ListElement {
                            text: "한국어" // Korean
                            val: StreamingPreferences.LANG_KO
                        }
                        ListElement {
                            text: "Magyar" // Hungarian
                            val: StreamingPreferences.LANG_HU
                        }
                        ListElement {
                            text: "Nederlands" // Dutch
                            val: StreamingPreferences.LANG_NL
                        }
                        ListElement {
                            text: "Svenska" // Swedish
                            val: StreamingPreferences.LANG_SV
                        }
                        ListElement {
                            text: "Türkçe" // Turkish
                            val: StreamingPreferences.LANG_TR
                        }
                        /* ListElement {
                            text: "Українська" // Ukrainian
                            val: StreamingPreferences.LANG_UK
                        } */
                        ListElement {
                            text: "繁體中文" // Traditional Chinese
                            val: StreamingPreferences.LANG_ZH_TW
                        }
                        ListElement {
                            text: "Português" // Portuguese
                            val: StreamingPreferences.LANG_PT
                        }
                        ListElement {
                            text: "Português do Brasil" // Brazilian Portuguese
                            val: StreamingPreferences.LANG_PT_BR
                        }
                        ListElement {
                            text: "Ελληνικά" // Greek
                            val: StreamingPreferences.LANG_EL
                        }
                        ListElement {
                            text: "Italiano" // Italian
                            val: StreamingPreferences.LANG_IT
                        }
                        /* ListElement {
                            text: "हिन्दी, हिंदी" // Hindi
                            val: StreamingPreferences.LANG_HI
                        } */
                        ListElement {
                            text: "Język polski" // Polish
                            val: StreamingPreferences.LANG_PL
                        }
                        ListElement {
                            text: "Čeština" // Czech
                            val: StreamingPreferences.LANG_CS
                        }
                        /* ListElement {
                            text: "עִבְרִית" // Hebrew
                            val: StreamingPreferences.LANG_HE
                        } */
                        /* ListElement {
                            text: "کرمانجیی خواروو" // Central Kurdish
                            val: StreamingPreferences.LANG_CKB
                        } */
                        /* ListElement {
                            text: "Lietuvių kalba" // Lithuanian
                            val: StreamingPreferences.LANG_LT
                        } */
                        /* ListElement {
                            text: "Eesti" // Estonian
                            val: StreamingPreferences.LANG_ET
                        } */
                        ListElement {
                            text: "Български" // Bulgarian
                            val: StreamingPreferences.LANG_BG
                        }
                        /* ListElement {
                            text: "Esperanto"
                            val: StreamingPreferences.LANG_EO
                        } */
                        ListElement {
                            text: "தமிழ்" // Tamil
                            val: StreamingPreferences.LANG_TA
                        }
                    }
                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated : {
                        // Retranslating is expensive, so only do it if the language actually changed
                        var new_language = languageListModel.get(currentIndex).val
                        if (StreamingPreferences.language !== new_language) {
                            StreamingPreferences.language = languageListModel.get(currentIndex).val
                            if (!StreamingPreferences.retranslate()) {
                                ToolTip.show(qsTr("You must restart Moonlight for this change to take effect"), 5000)
                            }
                            else {
                                // Force the back operation to pop any AppView pages that exist.
                                // The AppView stops working after retranslate() for some reason.
                                window.clearOnBack = true

                                // Signal other controls to adjust their text
                                languageChanged()
                            }
                        }
                    }
                }
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("GUI display mode")
                    visible: SystemProperties.hasDesktopEnvironment

                AutoResizingComboBox {
                    // ignore setting the index at first, and actually set it when the component is loaded
                    Component.onCompleted: {
                        if (!visible) {
                            // Do nothing if the control won't even be visible
                            return
                        }

                        var saved_uidisplaymode = StreamingPreferences.uiDisplayMode
                        currentIndex = 0
                        for (var i = 0; i < uiDisplayModeListModel.count; i++) {
                            var el_uidisplaymode = uiDisplayModeListModel.get(i).val;
                            if (saved_uidisplaymode === el_uidisplaymode) {
                                currentIndex = i
                                break
                            }
                        }

                        activated(currentIndex)
                        recalculateWidth()
                    }

                    id: uiDisplayModeComboBox
                    maximumWidth: 260
                    visible: SystemProperties.hasDesktopEnvironment
                    textRole: "text"
                    model: ListModel {
                        id: uiDisplayModeListModel
                        ListElement {
                            text: qsTr("Windowed")
                            val: StreamingPreferences.UI_WINDOWED
                        }
                        ListElement {
                            text: qsTr("Maximized")
                            val: StreamingPreferences.UI_MAXIMIZED
                        }   
                        ListElement {
                            text: qsTr("Fullscreen")
                            val: StreamingPreferences.UI_FULLSCREEN
                        }
                    }
                    // ::onActivated must be used, as it only listens for when the index is changed by a human
                    onActivated : {
                        StreamingPreferences.uiDisplayMode = uiDisplayModeListModel.get(currentIndex).val
                    }

                    // Defensive fallback: some AutoResizingComboBox instances end up with
                    // a stale/zero textWidth if recalculateWidth() runs before the popup's
                    // font metrics settle during initial component construction, leaving
                    // the box rendered too narrow (truncated text) until first interaction.
                    // A single deferred recalculation after the pane finishes laying out
                    // fixes this reliably without touching the shared component itself.
                    Timer {
                        interval: 50
                        running: true
                        onTriggered: parent.recalculateWidth()
                    }
                }
                }

                SettingRow {
                    width: parent.width
                    label: appGridTileScaleTitle.text
                    description: qsTr("Adjust the size of app tiles in the grid.")

                Label {
                    width: parent.width
                    id: appGridTileScaleTitle
                    text: qsTr("Tile size: %1%").arg(Math.round(appGridTileScaleSlider.value))
                    font.pointSize: 12
                    wrapMode: Text.Wrap
                    visible: false
                }

                Slider {
                    id: appGridTileScaleSlider
                    width: 300
                    value: StreamingPreferences.appGridTileScale
                    stepSize: 5
                    from: 60
                    to: 100
                    snapMode: "SnapOnRelease"

                    onValueChanged: {
                        var roundedValue = Math.round(value)
                        appGridTileScaleTitle.text = qsTr("Tile size: %1%").arg(roundedValue)
                        StreamingPreferences.appGridTileScale = roundedValue
                    }

                    Component.onCompleted: {
                        languageChanged.connect(valueChanged)
                    }
                }
                }

                SettingRow {
                    width: parent.width
                    label: appGridTileGapTitle.text
                    description: qsTr("Adjust the spacing between app tiles in the grid.")

                Label {
                    width: parent.width
                    id: appGridTileGapTitle
                    text: qsTr("Tile gap: %1 px").arg(Math.round(appGridTileGapSlider.value))
                    font.pointSize: 12
                    wrapMode: Text.Wrap
                    visible: false
                }

                Slider {
                    id: appGridTileGapSlider
                    width: 300
                    value: StreamingPreferences.appGridTileGap
                    stepSize: 1
                    from: 4
                    to: 24
                    snapMode: "SnapOnRelease"

                    onValueChanged: {
                        var roundedValue = Math.round(value)
                        appGridTileGapTitle.text = qsTr("Tile gap: %1 px").arg(roundedValue)
                        StreamingPreferences.appGridTileGap = roundedValue
                    }

                    Component.onCompleted: {
                        languageChanged.connect(valueChanged)
                    }
                }
                }

                ToggleSwitch {
                    id: connectionWarningsCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Show connection quality warnings")
                    font.pointSize: 12
                    checked: StreamingPreferences.connectionWarnings
                    onCheckedChanged: {
                        StreamingPreferences.connectionWarnings = checked
                    }
                }

                ToggleSwitch {
                    id: configurationWarningsCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Show configuration warnings")
                    font.pointSize: 12
                    checked: StreamingPreferences.configurationWarnings
                    onCheckedChanged: {
                        StreamingPreferences.configurationWarnings = checked
                    }
                }

                ToggleSwitch {
                    visible: SystemProperties.hasDiscordIntegration
                    id: discordPresenceCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Discord Rich Presence integration")
                    font.pointSize: 12
                    checked: StreamingPreferences.richPresence
                    onCheckedChanged: {
                        StreamingPreferences.richPresence = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Updates your Discord status to display the name of the game you're streaming.")
                }

                ToggleSwitch {
                    id: keepAwakeCheck
                    width: parent.width
                    divider: true
                    text: qsTr("Keep the display awake while streaming")
                    font.pointSize: 12
                    checked: StreamingPreferences.keepAwake
                    onCheckedChanged: {
                        StreamingPreferences.keepAwake = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Prevents the screensaver from starting or the display from going to sleep while streaming.")
                }
            }
        }

        Flickable {
            id: personalizationPane
            clip: true
            contentWidth: width
            contentHeight: personalizationColumn.height + 56
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: personalizationColumn
                x: 34
                y: 28
                width: parent.width - 68
                spacing: 8

                SectionHeader {
                    width: parent.width
                    text: qsTr("Background")
                    isFirst: true
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Background")

                AutoResizingComboBox {
                    id: backgroundStyleComboBox
                    maximumWidth: 220
                    textRole: "text"
                    Component.onCompleted: {
                        var saved_style = StreamingPreferences.backgroundStyle
                        currentIndex = 0
                        for (var i = 0; i < backgroundStyleListModel.count; i++) {
                            if (saved_style === backgroundStyleListModel.get(i).val) {
                                currentIndex = i
                                break
                            }
                        }
                        recalculateWidth()
                    }
                    model: ListModel {
                        id: backgroundStyleListModel
                        ListElement {
                            text: qsTr("Solid Color")
                            val: StreamingPreferences.BackgroundSolid
                        }
                        ListElement {
                            text: qsTr("Gradient")
                            val: StreamingPreferences.BackgroundGradient
                        }
                        ListElement {
                            text: qsTr("App Cover Art")
                            val: StreamingPreferences.BackgroundAppArt
                        }
                    }
                    onActivated: {
                        StreamingPreferences.backgroundStyle = backgroundStyleListModel.get(currentIndex).val
                        StreamingPreferences.save()
                    }
                }
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Motion")

                AutoResizingComboBox {
                    id: backgroundMotionComboBox
                    maximumWidth: 220
                    textRole: "text"
                    Component.onCompleted: {
                        var saved_motion = StreamingPreferences.backgroundMotionTier
                        currentIndex = 0
                        for (var i = 0; i < backgroundMotionListModel.count; i++) {
                            if (saved_motion === backgroundMotionListModel.get(i).val) {
                                currentIndex = i
                                break
                            }
                        }
                        recalculateWidth()
                    }
                    model: ListModel {
                        id: backgroundMotionListModel
                        ListElement {
                            text: qsTr("Off")
                            val: StreamingPreferences.MotionOff
                        }
                        ListElement {
                            text: qsTr("Static")
                            val: StreamingPreferences.MotionStatic
                        }
                        ListElement {
                            text: qsTr("Subtle")
                            val: StreamingPreferences.MotionSubtle
                        }
                    }
                    onActivated: {
                        StreamingPreferences.backgroundMotionTier = backgroundMotionListModel.get(currentIndex).val
                        StreamingPreferences.save()
                    }
                }
                }

                SectionHeader {
                    width: parent.width
                    text: qsTr("Accent Color")
                }

                Label {
                    width: parent.width
                    text: qsTr("Choose a highlight color used for selection and accents throughout the UI.")
                    font.pointSize: 9
                    color: "#9aa0b0"
                    wrapMode: Text.Wrap
                }

                Grid {
                    id: accentColorSwatchGrid
                    columns: 5
                    spacing: 12
                    function applyAccentColor(accentColor) {
                        StreamingPreferences.accentColor = accentColor
                        StreamingPreferences.save()
                    }

                    Repeater {
                        id: accentColorSwatchRepeater
                        model: [
                            "#c93bd6", "#f5c518", "#f58220", "#e0501b", "#f5455c",
                            "#f13b90", "#c23b6d", "#b47fe0", "#9b5de0", "#8a8ae8",
                            "#3a7fe8", "#2fb6d9", "#2fa98f", "#7cb342", "#4caf50",
                            "#a8afc0", "#6b7280"
                        ]

                        Button {
                            id: accentSwatchButton
                            readonly property bool isSelected: StreamingPreferences.accentColor === modelData
                            width: 52
                            height: 52
                            padding: 0
                            flat: true
                            hoverEnabled: true
                            focusPolicy: Qt.StrongFocus
                            activeFocusOnTab: true
                            text: qsTr("Accent color %1").arg(modelData)
                            onClicked: accentColorSwatchGrid.applyAccentColor(modelData)
                            KeyNavigation.left: index % accentColorSwatchGrid.columns !== 0 ?
                                                    accentColorSwatchRepeater.itemAt(index - 1) : null
                            KeyNavigation.right: index + 1 < accentColorSwatchRepeater.count &&
                                                 index % accentColorSwatchGrid.columns !== accentColorSwatchGrid.columns - 1 ?
                                                    accentColorSwatchRepeater.itemAt(index + 1) : null
                            KeyNavigation.up: index >= accentColorSwatchGrid.columns ?
                                                  accentColorSwatchRepeater.itemAt(index - accentColorSwatchGrid.columns) : null
                            KeyNavigation.down: index + accentColorSwatchGrid.columns < accentColorSwatchRepeater.count ?
                                                    accentColorSwatchRepeater.itemAt(index + accentColorSwatchGrid.columns) : null

                            background: Rectangle {
                                radius: 14
                                color: modelData
                                border.width: accentSwatchButton.isSelected ? 3 :
                                              accentSwatchButton.activeFocus ? 2 : 0
                                border.color: accentSwatchButton.isSelected ? "white" : "#CCFFFFFF"

                                Behavior on border.width {
                                    NumberAnimation { duration: 100 }
                                }
                            }

                            contentItem: Text {
                                text: "\u2713"
                                visible: accentSwatchButton.isSelected
                                color: "white"
                                font.pixelSize: 22
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                style: Text.Outline
                                styleColor: "#40000000"
                            }

                            ToolTip.delay: 1000
                            ToolTip.timeout: 5000
                            ToolTip.visible: hovered || activeFocus
                            ToolTip.text: text
                        }
                    }
                }
            }
        }

        Flickable {
            id: streamingProfilesPane
            clip: true
            contentWidth: width
            contentHeight: streamingProfilesColumn.height + 56
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: streamingProfilesColumn
                x: 34
                y: 28
                width: parent.width - 68
                spacing: 8

                SettingRow {
                    width: parent.width
                    label: qsTr("Active Profile")
                    description: qsTr("Switch named streaming presets without changing the rest of the app settings.")

                    ComboBox {
                        id: streamingProfileComboBox
                        width: 220
                        model: streamingProfileNamesModel

                        onActivated: {
                            var profileId = settingsPage.selectedStreamingProfileId()
                            if (profileId.length > 0) {
                                StreamingProfileManager.setActiveProfile(profileId)
                            }
                        }
                    }
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Create or Update")
                    description: qsTr("Capture the current streaming settings as a new profile or rename/duplicate the selected one.")

                    Column {
                        width: 220
                        spacing: 6

                        Button {
                            width: parent.width
                            text: qsTr("Create from Current")
                            onClicked: {
                                profileNameDialog.mode = "create"
                                profileNameDialog.targetProfileId = ""
                                profileNameDialog.title = qsTr("Create Streaming Profile")
                                profileNameField.text = ""
                                profileNameDialog.open()
                            }
                        }

                        Button {
                            width: parent.width
                            enabled: streamingProfileComboBox.currentIndex >= 0
                            text: qsTr("Duplicate")
                            onClicked: {
                                profileNameDialog.mode = "duplicate"
                                profileNameDialog.targetProfileId = settingsPage.selectedStreamingProfileId()
                                profileNameDialog.title = qsTr("Duplicate Streaming Profile")
                                profileNameField.text = qsTr("%1 Copy").arg(settingsPage.selectedStreamingProfileName())
                                profileNameDialog.open()
                            }
                        }

                        Button {
                            width: parent.width
                            enabled: streamingProfileComboBox.currentIndex >= 0
                            text: qsTr("Rename")
                            onClicked: {
                                profileNameDialog.mode = "rename"
                                profileNameDialog.targetProfileId = settingsPage.selectedStreamingProfileId()
                                profileNameDialog.title = qsTr("Rename Streaming Profile")
                                profileNameField.text = settingsPage.selectedStreamingProfileName()
                                profileNameDialog.open()
                            }
                        }
                    }
                }

                SettingRow {
                    width: parent.width
                    label: qsTr("Maintenance")
                    description: qsTr("Delete the selected profile or restore its streaming values to the default preset.")

                    Column {
                        width: 220
                        spacing: 6

                        Button {
                            width: parent.width
                            enabled: streamingProfileComboBox.currentIndex >= 0 && streamingProfileNamesModel.length > 1
                            text: qsTr("Delete")
                            onClicked: {
                                deleteProfileDialog.profileId = settingsPage.selectedStreamingProfileId()
                                deleteProfileDialog.profileName = settingsPage.selectedStreamingProfileName()
                                deleteProfileDialog.open()
                            }
                        }

                        Button {
                            width: parent.width
                            enabled: streamingProfileComboBox.currentIndex >= 0
                            text: qsTr("Reset to Defaults")
                            onClicked: StreamingProfileManager.resetProfileToDefaults(settingsPage.selectedStreamingProfileId())
                        }
                    }
                }
            }
        }

                } // sectionStack (StackLayout)
            } // RowLayout
        } // setShell

        NavigableDialog {
            id: profileNameDialog
            property string mode: ""
            property string targetProfileId: ""
            standardButtons: Dialog.Ok | Dialog.Cancel

            function isInputValid() {
                return settingsPage.isStreamingProfileNameAvailable(profileNameField.text, mode === "rename" ? targetProfileId : "")
            }

            onOpened: {
                profileNameField.forceActiveFocus()
                profileNameField.selectAll()

                if (profileNameDialog.standardButton) {
                    profileNameDialog.standardButton(Dialog.Ok).enabled = profileNameDialog.isInputValid()
                }
            }

            onClosed: {
                mode = ""
                targetProfileId = ""
                title = ""
                profileNameField.clear()
            }

            onAccepted: {
                var trimmedName = profileNameField.text.trim()
                if (!trimmedName.length) {
                    reject()
                    return
                }

                if (mode === "create") {
                    StreamingProfileManager.createProfileFromCurrent(trimmedName)
                }
                else if (mode === "duplicate") {
                    StreamingProfileManager.duplicateProfile(targetProfileId, trimmedName)
                }
                else if (mode === "rename") {
                    StreamingProfileManager.renameProfile(targetProfileId, trimmedName)
                }
            }

            ColumnLayout {
                Label {
                    text: qsTr("Profile name")
                    font.bold: true
                }

                TextField {
                    id: profileNameField
                    Layout.minimumWidth: 280

                    onTextChanged: {
                        if (profileNameDialog.standardButton) {
                            profileNameDialog.standardButton(Dialog.Ok).enabled = profileNameDialog.isInputValid()
                        }
                    }

                    Keys.onReturnPressed: profileNameDialog.accept()
                    Keys.onEnterPressed: profileNameDialog.accept()
                }
            }
        }

        NavigableMessageDialog {
            id: deleteProfileDialog
            property string profileId: ""
            property string profileName: ""
            text: qsTr("Delete the \"%1\" streaming profile?").arg(profileName)
            standardButtons: Dialog.Yes | Dialog.No

            onAccepted: StreamingProfileManager.deleteProfile(profileId)

            onClosed: {
                profileId = ""
                profileName = ""
            }
        }
}
