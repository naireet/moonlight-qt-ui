import QtQuick 2.15
import QtQuick.Controls 2.2
import QtQuick.Window 2.2

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0

Item {
    property Session session
    property string appName
    property string boxArtImageUrl: ""
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false

    // Auto-reconnect state. When a stream that was actually working drops
    // (see Session::isConnectionLost()), this segue stays on screen in a
    // "reconnecting" mode driven by a StreamReconnector, then swaps in a
    // fresh Session and runs the normal start path again to resume.
    // reconnectDeadline is non-zero from the drop until a resumed stream has
    // stayed up for healthyStreamTimer's interval, so attempts that fail in
    // between (host hasn't dropped the old session yet, no video, etc.) keep
    // retrying against the same deadline instead of restarting it.
    property bool reconnecting : false
    property bool reconnectQuitting : false
    property var reconnector : null
    property double reconnectDeadline : 0
    property string reconnectHostName : ""
    property string lostErrorText : ""
    property bool connected : false
    property bool streamHealthy : false

    // The finished Session is parked here until its cleanup emits
    // readyForDeletion, since it must not be garbage collected before then
    property var retiredSession : null

    Item {
        anchors.fill: parent
        clip: true
        visible: boxArtImageUrl !== ""

        Image {
            anchors.centerIn: parent
            width: Math.round(parent.width * 1.18)
            height: Math.round(parent.height * 1.18)
            source: boxArtImageUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            opacity: 0.92
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.82
        }
    }

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)

        if (failingPorts) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function connectionStarted()
    {
        // Only a stream that stays up past the initial video timeouts counts
        // as working (see healthyStreamTimer)
        connected = true
        healthyStreamTimer.restart()

        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        stageSpinner.visible = false
        stageLabel.visible = false
        hintText.visible = false

        // Keep a mapped surface under gamescope so focus doesn't fall back to Steam
        // between destruction of the SDL window and sessionFinished().
        if (SystemProperties.hasDesktopEnvironment) {
            window.visible = false
        }
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        stackView.replace(stackView.currentItem, component.createObject(stackView, {"appName": appName}), StackView.Immediate)

        // Show the Qt window again to show quit segue
        window.visible = true
    }

    function sessionFinished(portTestResult)
    {
        if (tryStartReconnect()) {
            return
        }

        finishStream(portTestResult)
    }

    function finishStream(portTestResult)
    {
        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Pop the StreamSegue off the stack if this is a GUI-based app launch
        if (!quitAfter) {
            stackView.pop()
        }

        if (quitAfter && !streamSegueErrorDialog.text) {
            // If this was a CLI launch without errors, exit now
            Qt.quit()
        }
        else {
            // Show the Qt window again after streaming
            window.visible = true

            // Display any launch errors. We do this after
            // the Qt UI is visible again to prevent losing
            // focus on the dialog which would impact gamepad
            // users.
            if (streamSegueErrorDialog.text) {
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
        }
    }

    function sessionReadyForDeletion()
    {
        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        // During auto-reconnect the finished session is the retired one, and
        // `session` may already be the next attempt.
        if (retiredSession) {
            retiredSession = null
        }
        else {
            session = null
        }
        gc()
    }

    function connectSession()
    {
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.readyForDeletion.connect(sessionReadyForDeletion)
    }

    function startSession()
    {
        // Hook up our signals
        connectSession()
        connected = false

        // Ensure the SystemProperties async thread is finished,
        // since it may currently be using the SDL video subsystem
        SystemProperties.waitForAsyncLoad()

        // Kick off the stream. Toggling the loader re-runs onLoaded
        // for a reconnect attempt. The spinner is hidden until onLoaded
        // has finished session.initialize() (see the comment there).
        stageSpinner.visible = false
        streamLoader.active = false
        streamLoader.active = true
    }

    function formatReconnectTime(seconds)
    {
        var secs = seconds % 60
        return Math.floor(seconds / 60) + ":" + (secs < 10 ? "0" : "") + secs
    }

    function updateReconnectCountdown()
    {
        var left = Math.max(0, Math.ceil((reconnectDeadline - Date.now()) / 1000))
        stageText = qsTr("Connection lost - reconnecting to %1... %2").arg(reconnectHostName).arg(formatReconnectTime(left))
        if (left <= 0) {
            giveUpReconnect()
        }
    }

    // Called from sessionFinished(). Returns true if we entered (or stayed
    // in) reconnect mode instead of finishing the stream.
    function tryStartReconnect()
    {
        var wasHealthy = streamHealthy
        healthyStreamTimer.stop()
        streamHealthy = false

        if (!session || StreamingPreferences.autoReconnectTimeout <= 0) {
            return false
        }

        if (reconnectDeadline <= 0) {
            // Only a network drop of a stream that was actually working
            // starts reconnecting. Failures right after starting (e.g. no
            // video because of a firewall) show their error as before.
            if (!wasHealthy || !session.isConnectionLost()) {
                return false
            }

            // Keep the error to show if we end up giving up
            lostErrorText = streamSegueErrorDialog.text
            reconnectDeadline = Date.now() + StreamingPreferences.autoReconnectTimeout * 1000
        }
        else if (connected && !session.isConnectionLost()) {
            // A resume attempt was ended on purpose (disconnect combo)
            reconnectDeadline = 0
            return false
        }
        else if (Date.now() >= reconnectDeadline) {
            // A resume attempt failed after the countdown ran out
            reconnectDeadline = 0
            streamSegueErrorDialog.text = lostErrorText
            return false
        }

        // Null if we're exiting (e.g. SIGTERM from Steam's "Exit game")
        var r = session.createReconnector()
        if (!r) {
            reconnectDeadline = 0
            return false
        }

        // Stop listening to the finished session except for its cleanup
        session.stageStarting.disconnect(stageStarting)
        session.stageFailed.disconnect(stageFailed)
        session.connectionStarted.disconnect(connectionStarted)
        session.displayLaunchError.disconnect(displayLaunchError)
        session.quitStarting.disconnect(quitStarting)
        session.sessionFinished.disconnect(sessionFinished)
        retiredSession = session
        session = null

        reconnector = r
        reconnectHostName = r.hostName()
        reconnectQuitting = false
        reconnecting = true
        if (boxArtImageUrl === "") {
            // CLI launches don't pass box art, so use the cached copy
            boxArtImageUrl = r.boxArtUrl()
        }
        r.hostReady.connect(reconnectHostReady)
        r.appNotRunning.connect(reconnectAppNotRunning)
        r.quitFinished.connect(reconnectQuitFinished)
        r.start()

        // Errors from failed attempts are not interesting while retrying
        streamSegueErrorDialog.text = ""

        updateReconnectCountdown()
        reconnectTimer.start()
        stageSpinner.visible = true
        stageLabel.visible = true
        hintText.visible = true
        hintText.text = qsTr("Press %1 to stop reconnecting or %2 to quit the game").arg(
                    SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ? qsTr("B") : qsTr("Esc")).arg(qsTr("Y"))

        // Show the Qt window again and take input for B/Y
        window.visible = true
        SdlGamepadKeyNavigation.enable()
        forceActiveFocus()
        return true
    }

    function endReconnect()
    {
        reconnectTimer.stop()
        reconnecting = false
        reconnectQuitting = false
        reconnectDeadline = 0
        if (reconnector) {
            reconnector.stop()
            reconnector.hostReady.disconnect(reconnectHostReady)
            reconnector.appNotRunning.disconnect(reconnectAppNotRunning)
            reconnector.quitFinished.disconnect(reconnectQuitFinished)
            reconnector = null
        }
    }

    function reconnectHostReady()
    {
        // Resume through the normal start path with a fresh Session, keeping
        // the countdown running in case this attempt fails too
        reconnectTimer.stop()
        reconnecting = false
        session = reconnector.createSession()
        reconnector.hostReady.disconnect(reconnectHostReady)
        reconnector.appNotRunning.disconnect(reconnectAppNotRunning)
        reconnector.quitFinished.disconnect(reconnectQuitFinished)
        reconnector = null

        isResume = true
        stageText = qsTr("Resuming %1...").arg(appName)
        startSession()
    }

    function reconnectAppNotRunning()
    {
        endReconnect()
        streamSegueErrorDialog.text = qsTr("%1 is no longer running on %2.").arg(appName).arg(reconnectHostName)
        finishStream(0)
    }

    // B / Esc: stop trying and leave like a normal disconnect (the app
    // keeps running on the host)
    function stopReconnect()
    {
        endReconnect()
        streamSegueErrorDialog.text = ""
        finishStream(0)
    }

    function giveUpReconnect()
    {
        endReconnect()
        streamSegueErrorDialog.text = lostErrorText
        finishStream(0)
    }

    // Y: quit the game on the host, then leave
    function quitFromReconnect()
    {
        reconnectQuitting = true
        reconnectTimer.stop()
        stageText = qsTr("Quitting %1...").arg(appName)
        reconnector.quitHostApp()
    }

    function reconnectQuitFinished(error)
    {
        endReconnect()
        streamSegueErrorDialog.text = error
        finishStream(0)
    }

    // Swallow every key while reconnecting so nothing reaches main.qml's
    // StackView navigation (settings, back) underneath this screen
    Keys.onPressed: {
        if (!reconnecting && !reconnectQuitting) {
            return
        }

        event.accepted = true
        if (reconnectQuitting) {
            return
        }

        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            stopReconnect()
        }
        // Gamepad Y arrives as Key_Call (see SdlGamepadKeyNavigation)
        else if (event.key === Qt.Key_Call || event.key === Qt.Key_Y) {
            quitFromReconnect()
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        repeat: true
        onTriggered: updateReconnectCountdown()
    }

    Timer {
        id: healthyStreamTimer
        // Comfortably past moonlight-common-c's initial no-video timeouts
        interval: 15000
        onTriggered: {
            streamHealthy = true
            reconnectDeadline = 0
        }
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack (see the
        // comment in QuitSegue.qml's StackView.onActivated for why this
        // goes through window.streamActive rather than a direct
        // toolBar.visible assignment)
        window.streamActive = false

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()
    }

    StackView.onActivated: {
        // Hide the toolbar before we start loading
        window.streamActive = true

        // Only start once, in case this segue is ever re-activated
        if (!streamLoader.active) {
            startSession()
        }
    }

    Timer {
        id: startSessionTimer
        onTriggered: {
            // Garbage collect QML stuff before we start streaming,
            // since we'll probably be streaming for a while and we
            // won't be able to GC during the stream.
            gc()

            // Run the streaming session to completion
            session.start()
        }
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            // Set the hint text. We do this here rather than
            // in the hintText control itself to synchronize
            // with Session.exec() which requires no concurrent
            // gamepad usage.
            hintText.text = qsTr("Tip:") + " " + qsTr("Press %1 to disconnect your session").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ?
                                                  qsTr("Start+Select+L1+R1") : qsTr("Ctrl+Alt+Shift+Q"))

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // This spinner is shown only after session.initialize() has completed
            // to prevent active animations from running during decoder probing,
            // which causes re-entrant event loop livelocks with libdecor-gtk.
            stageSpinner.visible = true

            // Don't wait unless we have toasts to display
            startSessionTimer.interval = 0

            // Display the toasts together in a vertical centered arrangement
            var yOffset = 0
            for (var i = 0; i < session.launchWarnings.length; i++) {
                var text = session.launchWarnings[i]
                console.warn(text)

                // Show the tooltip for 3 seconds
                var toast = Qt.createQmlObject('import QtQuick.Controls 2.2; ToolTip {}', parent, '')
                toast.timeout = 3000
                toast.text = text
                toast.y += yOffset
                toast.visible = true

                // Offset the next toast below the previous one
                yOffset = toast.y + toast.padding + toast.height

                // Allow an extra 500 ms for the tooltip's fade-out animation to finish
                startSessionTimer.interval = toast.timeout + 500;
            }

            // Start the timer to wait for toasts (or start the session immediately)
            startSessionTimer.start()
        }

        sourceComponent: Item {}
    }

    Column {
        anchors.centerIn: parent
        spacing: 14

        // Continuously-spinning ring, matching the mockup's `.load-spin`
        // spec: a 52px ring built from a conic gradient sweeping from
        // transparent to the app's text color, masked down to a ring via a
        // transparent center -- drawn once into a Canvas (cheap, since the
        // sweep itself never changes) then spun via RotationAnimation on
        // the wrapping Item's rotation, the exact same "draw once, rotate
        // the Item" technique already used for the smaller 26px half-moon
        // wordmark spinner on Host Select/App Grid (PcView.qml's moonIcon),
        // just bigger (52px vs 26px) and faster (1400ms vs 3500ms) per the
        // mockup's `animation: spin 1.4s linear infinite`. Replaces the
        // stock Material BusyIndicator, which rendered as a plain spinning
        // dashed circle with no visual relation to the rest of the redesign
        // and was only ever shown after a 100ms delay via spinnerTimer.
        Item {
            id: stageSpinner
            width: 52
            height: 52
            visible: false
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                id: spinnerCanvas
                anchors.fill: parent

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()

                    var cx = width / 2
                    var cy = height / 2
                    var outerRadius = width / 2
                    var innerRadius = 15
                    var ringRadius = (outerRadius + innerRadius) / 2

                    var gradient = ctx.createConicalGradient(cx, cy, 0)
                    gradient.addColorStop(0.0, "transparent")
                    gradient.addColorStop(1.0, "#eef0f6")

                    ctx.lineWidth = outerRadius - innerRadius
                    ctx.strokeStyle = gradient
                    ctx.beginPath()
                    ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2)
                    ctx.stroke()
                }
            }

            RotationAnimation on rotation {
                running: stageSpinner.visible
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1400
            }
        }

        // Big static title + smaller dim stage subtitle, matching the
        // mockup's two-line `.loading .big` / `.loading .sub` layout,
        // replacing the old single combined "Starting GameName..." label.
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: stageLabel.visible
            text: reconnecting ? appName : qsTr("Initializing Moonlight…")
            color: "#eef0f6"
            font.pointSize: 20
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            id: stageLabel
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, 500)
            text: stageText
            color: "#9aa0b0"
            font.pointSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    Label {
        id: hintText
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        font.pointSize: 18
        verticalAlignment: Text.AlignVCenter

        wrapMode: Text.Wrap
    }
}
