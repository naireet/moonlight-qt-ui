import QtQuick 2.0
import QtQuick.Controls 2.2

ItemDelegate {
    property GridView grid
    property var leftKeyHandler
    property var rightKeyHandler
    property var downKeyHandler
    property var upKeyHandler
    property var returnKeyHandler
    property var enterKeyHandler
    property var escapeKeyHandler

    highlighted: grid.activeFocus && grid.currentItem === this

    Keys.onLeftPressed: {
        if (leftKeyHandler && leftKeyHandler(event)) {
            return
        }
        grid.moveCurrentIndexLeft()
    }
    Keys.onRightPressed: {
        if (rightKeyHandler && rightKeyHandler(event)) {
            return
        }
        grid.moveCurrentIndexRight()
    }
    Keys.onDownPressed: {
        if (downKeyHandler && downKeyHandler(event)) {
            return
        }
        grid.moveCurrentIndexDown()
    }
    Keys.onUpPressed: {
        if (upKeyHandler && upKeyHandler(event)) {
            return
        }
        grid.moveCurrentIndexUp()

        // If we've reached the top of the grid, move focus to the toolbar
        if (grid.currentItem === this) {
            nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
        }
    }
    Keys.onReturnPressed: {
        if (returnKeyHandler && returnKeyHandler(event)) {
            return
        }
        clicked()
    }
    Keys.onEnterPressed: {
        if (enterKeyHandler && enterKeyHandler(event)) {
            return
        }
        clicked()
    }
    Keys.onEscapePressed: {
        if (escapeKeyHandler && escapeKeyHandler(event)) {
            return
        }

        event.accepted = false
    }
}
