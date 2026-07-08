import QtQuick 2.9
import StreamingPreferences 1.0

// Matches the mockup's .pane h4: small, uppercase, letter-spaced, accent-colored
// sub-group label used within a settings pane (e.g. "Resolution and FPS").
// isFirst controls the top margin (mockup: 6px for the first header in a pane,
// 30px for any subsequent ones) -- callers position this manually via Column
// spacing, so this just exposes the text styling.
Text {
    id: root

    property bool isFirst: false

    text: ""
    font.pointSize: 9
    font.bold: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1.4
    color: StreamingPreferences.accentColor
    wrapMode: Text.Wrap
}
