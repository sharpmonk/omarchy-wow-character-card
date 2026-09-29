import QtQuick
import qs.Commons

// XP bar with the rested share drawn as a second, paler stretch ahead of it,
// the way the game draws its own.
Item {
  id: root

  property real percent: 0        // 0 to 100
  property real restedPercent: 0  // 0 to 100, measured from the end of `percent`
  property color foreground: Color.foreground
  property color fill: Color.accent

  readonly property real shown: Math.max(0, Math.min(100, percent))
  readonly property real shownRested: Math.max(0, Math.min(100 - shown, restedPercent))

  implicitWidth: Style.space(44)
  implicitHeight: Style.space(5)

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
  }

  Rectangle {
    x: 0
    width: parent.width * (root.shown + root.shownRested) / 100
    height: parent.height
    radius: height / 2
    visible: root.shownRested > 0
    color: Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.4)
  }

  Rectangle {
    x: 0
    width: parent.width * root.shown / 100
    height: parent.height
    radius: height / 2
    visible: root.shown > 0
    color: root.fill
  }
}
