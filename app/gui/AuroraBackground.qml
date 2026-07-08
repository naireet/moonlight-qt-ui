import QtQuick 2.15
import QtQuick.Effects

import StreamingPreferences 1.0

// Shared aurora background treatment: three softly-blurred, slowly-drifting
// radial-gradient blobs (violet, teal, magenta) layered over a near-black base.
// This mirrors the implementation used on PcView (Host Select) and AppView
// (App Grid) so all chrome-free full-bleed screens share the same visual
// identity. Falls back to the plain solid/gradient treatments shared with
// the other screens when the user has picked a different background style.
Item {
    id: root
    anchors.fill: parent
    z: -1
    clip: true

    readonly property bool showSolidBackground: StreamingPreferences.backgroundStyle == StreamingPreferences.BackgroundSolid
    readonly property bool subtleBackgroundMotion: StreamingPreferences.backgroundMotionTier == StreamingPreferences.MotionSubtle

    Rectangle {
        anchors.fill: parent
        color: Qt.darker(StreamingPreferences.accentColor, 6)
        visible: root.showSolidBackground
    }

    Item {
        anchors.fill: parent
        clip: true
        visible: !root.showSolidBackground

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
                running: root.subtleBackgroundMotion && !root.showSolidBackground
                loops: Animation.Infinite
                NumberAnimation { to: 40; duration: 20000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -40; duration: 20000; easing.type: Easing.InOutSine }
            }

            SequentialAnimation on driftY {
                running: root.subtleBackgroundMotion && !root.showSolidBackground
                loops: Animation.Infinite
                NumberAnimation { to: 30; duration: 26000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -30; duration: 26000; easing.type: Easing.InOutSine }
            }

            SequentialAnimation on driftRotation {
                running: root.subtleBackgroundMotion && !root.showSolidBackground
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
