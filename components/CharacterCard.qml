import QtQuick
import qs.Commons

// The card for one character. Every field is optional: an older game version
// may not report bags, and a character at max level reports no XP.
Column {
  id: root

  property var character: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool hasXp: character !== null && character.xpPercent !== null
    && character.xpPercent !== undefined

  function text(value) {
    return value === undefined || value === null ? "" : String(value)
  }

  spacing: Style.space(6)

  Item {
    width: parent.width
    height: Math.max(nameText.implicitHeight, levelText.implicitHeight)

    Text {
      id: nameText
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: levelText.left
      anchors.rightMargin: Style.space(8)
      elide: Text.ElideRight
      text: root.character ? root.text(root.character.name) : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      id: levelText
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.baseline: nameText.baseline
      text: root.character
        ? ("Level " + root.text(root.character.level) + " " + root.text(root.character["class"])).trim()
        : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    elide: Text.ElideRight
    text: {
      if (!root.character) return ""
      var parts = []
      if (root.character.label) parts.push(root.text(root.character.label))
      if (root.character.realm) parts.push(root.text(root.character.realm))
      return parts.join(" \u00b7 ")
    }
    visible: text !== ""
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Item {
    width: parent.width
    height: Style.space(2)
  }

  XpBar {
    width: parent.width
    height: Style.space(8)
    visible: root.hasXp
    percent: root.hasXp ? Number(root.character.xpPercent) : 0
    restedPercent: root.hasXp ? Number(root.character.restedPercent || 0) : 0
    foreground: root.foreground
  }

  StatRow {
    label: "XP"
    value: root.hasXp ? root.character.xpPercent + "%" : ""
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  StatRow {
    label: "Rested"
    value: root.hasXp && Number(root.character.restedPercent || 0) > 0
      ? "+" + root.character.restedPercent + "%" : ""
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  StatRow {
    label: "Level"
    value: root.character && !root.hasXp && root.character.atMaxLevel === true ? "Max" : ""
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  StatRow {
    label: "Gold"
    value: root.character ? root.text(root.character.moneyText) : ""
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  StatRow {
    label: "Bags"
    value: root.character && root.character.bagsTotal
      ? root.text(root.character.bagsUsed) + " / " + root.text(root.character.bagsTotal) : ""
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
}
