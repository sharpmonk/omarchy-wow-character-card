import QtQuick
import qs.Commons
import qs.Ui

// What the panel shows while there is no character to show yet. One screen
// per reason, each saying what to do next.
Column {
  id: root

  property string setup: ""          // no-install | addon-missing | no-data | hidden | error
  property string error: ""
  property var installs: []
  property bool gameRunning: false
  property bool installing: false
  property var installResults: []
  property bool searching: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal installRequested()
  signal searchRequested()

  readonly property string heading: {
    if (setup === "error") return "Something is missing"
    if (setup === "no-install") return "WoW not found yet"
    if (setup === "addon-missing") return "Install the companion addon"
    if (setup === "no-data") return "Waiting for your character"
    if (setup === "hidden") return "Every character is hidden"
    return ""
  }

  // Folders the addon could not be copied into, most often because they are
  // read-only.
  readonly property string installFailure: {
    var failed = []
    for (var i = 0; i < installResults.length; i++)
      if (installResults[i] && installResults[i].ok !== true) failed.push(String(installResults[i].path || ""))
    if (failed.length === 0) return ""
    return "The addon could not be copied into:\n" + failed.join("\n") + "\nCheck that the folder can be written to."
  }

  readonly property string body: {
    if (setup === "error") return error
    if (setup === "no-install")
      return "Launch WoW once and it will be found on its own. You can also search common folders, or set the WoW folder in this widget's settings."
    if (setup === "addon-missing")
      return "The addon records your level, XP, gold and bags. It has no in-game window and sends nothing anywhere."
    if (setup === "no-data")
      return gameRunning
        ? "If WoW was already open when the addon was installed, restart the game. Then log in, and log out or type /reload to save."
        : "Start WoW and log in to a character. The card fills in when you log out or type /reload."
    if (setup === "hidden")
      return "Remove a name from \u201cCharacters to hide\u201d in this widget's settings to show it here."
    return ""
  }

  function addonText(state) {
    if (state === "ok") return "addon installed"
    if (state === "outdated") return "addon out of date"
    return "addon missing"
  }

  spacing: Style.space(10)

  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: root.heading
    wrapMode: Text.WordWrap
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
  }

  Column {
    width: parent.width
    spacing: Style.space(4)
    visible: root.setup === "addon-missing" && root.installs.length > 0

    Repeater {
      model: root.installs

      StatRow {
        required property var modelData
        label: String(modelData.label || "")
        value: root.addonText(modelData.addon)
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: root.body
    wrapMode: Text.WordWrap
    color: root.foreground
    opacity: 0.75
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.installFailure !== ""
    text: root.installFailure
    wrapMode: Text.WrapAnywhere
    color: Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Button {
    visible: root.setup === "addon-missing"
    bordered: true
    enabled: !root.installing
    text: root.installing ? "Installing\u2026" : "Install addon"
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.installRequested()
  }

  Button {
    visible: root.setup === "no-install"
    bordered: true
    enabled: !root.searching
    text: root.searching ? "Searching\u2026" : "Search for WoW"
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.searchRequested()
  }
}
