import QtQuick
import qs.Commons

// One line in the list of other characters. Click to show its card.
Rectangle {
  id: root

  property var character: null
  property bool selected: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal clicked()

  width: parent ? parent.width : implicitWidth
  implicitHeight: nameText.implicitHeight + Style.space(8)
  radius: Style.space(4)
  color: selected || area.containsMouse
    ? Qt.rgba(foreground.r, foreground.g, foreground.b, selected ? 0.12 : 0.07)
    : "transparent"

  Text {
    id: nameText
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.right: detailText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: root.character ? String(root.character.name || "") : ""
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    id: detailText
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    text: root.character
      ? "Lv " + String(root.character.level || "") + "  " + String(root.character.label || "")
      : ""
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
