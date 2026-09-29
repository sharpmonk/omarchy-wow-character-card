import QtQuick
import qs.Commons

// One line of the card: what it is on the left, the figure on the right.
Item {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: Color.foreground
  property color valueColor: foreground
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  implicitWidth: labelText.implicitWidth + valueText.implicitWidth + Style.space(12)
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)
  visible: value !== ""

  Text {
    id: labelText
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    id: valueText
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.value
    color: root.valueColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
