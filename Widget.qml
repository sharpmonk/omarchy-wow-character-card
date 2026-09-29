import QtQuick
import qs.Commons
import qs.Ui

import "components"

// WoW Character Card: the bar face and its panel.
//
// Draws what the service last heard from bin/wcc and nothing else. Character
// data is a snapshot from the last logout or /reload; only the session clock
// moves on its own.
//
// Glyphs are \u escapes rather than literal characters, so the source survives
// editors that mangle private-use codepoints.
Panel {
  id: root

  moduleName: "sharpmonk.wow-character-card"
  ipcTarget: "sharpmonk.wow-character-card"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool vertical: bar ? bar.vertical : false

  // U+F0787 nf-md-sword_cross, U+F0450 nf-md-refresh.
  readonly property string glyph: "\uDB81\uDF87"
  readonly property string refreshGlyph: "\uDB81\uDC50"

  // ----------------------------------------------------------------- settings

  readonly property string wowFolder: String(setting("wowFolder", ""))
  readonly property bool showClock: setting("showClock", true) === true
  readonly property bool showPercent: setting("showPercent", true) === true
  readonly property var hiddenNames: {
    var names = String(setting("hiddenCharacters", "")).split(",")
    var out = []
    for (var i = 0; i < names.length; i++) {
      var name = names[i].trim().toLowerCase()
      if (name !== "") out.push(name)
    }
    return out
  }

  // ------------------------------------------------------------------ service

  property var service: null

  function bindService() {
    if (service) {
      pushSettings()
      return
    }
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return
    var s = host.serviceFor("sharpmonk.wow-character-card")
    if (!s) return
    service = s
    pushSettings()
  }

  function pushSettings() {
    if (service) service.wowFolder = wowFolder
  }

  onBarChanged: bindService()
  onWowFolderChanged: pushSettings()
  Component.onCompleted: bindService()

  Timer {
    interval: 200
    running: root.service === null
    repeat: true
    onTriggered: root.bindService()
  }

  // -------------------------------------------------------------------- state

  readonly property var status: service && service.status ? service.status : ({})
  readonly property bool loaded: service ? service.loaded : false
  readonly property string error: service ? service.error : ""
  readonly property string helperSetup: String(status.setup || "")
  readonly property string setup: {
    if (error !== "") return "error"
    // The helper found characters, but the settings hide all of them.
    if ((status.characters || []).length > 0 && characters.length === 0) return "hidden"
    return helperSetup
  }
  readonly property var installs: status.installs || []
  readonly property var running: status.running || null
  readonly property var session: status.session || null
  readonly property var playtime: status.playtime || ({ today: 0, week: 0 })

  readonly property var characters: {
    var all = status.characters || []
    var out = []
    for (var i = 0; i < all.length; i++) {
      var name = String(all[i].name || "").toLowerCase()
      if (hiddenNames.indexOf(name) < 0) out.push(all[i])
    }
    return out
  }

  // The bar always follows the last played character. The panel shows that
  // one too until another is picked from the list.
  readonly property var main: characters.length > 0 ? characters[0] : null
  property string selectedId: ""
  readonly property var shown: {
    for (var i = 0; i < characters.length; i++)
      if (characters[i].id === selectedId) return characters[i]
    return main
  }
  readonly property var others: {
    var out = []
    for (var i = 0; i < characters.length; i++)
      if (!shown || characters[i].id !== shown.id) out.push(characters[i])
    return out
  }

  readonly property bool mainHasXp: main !== null && main.xpPercent !== null
    && main.xpPercent !== undefined

  property double nowMs: Date.now()
  readonly property int sessionSeconds: session
    ? Math.max(0, Math.floor(nowMs / 1000) - Number(session.start || 0)) : 0
  // The helper counted play time up to its last poll; add what has passed
  // since, so the totals move with the clock.
  readonly property int sinceStatus: session
    ? Math.max(0, Math.floor(nowMs / 1000) - Number(status.now || 0)) : 0

  Timer {
    interval: 5000
    running: root.session !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  function duration(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m"
  }

  function ago(timestamp) {
    var then = Number(timestamp) || 0
    if (then <= 0) return ""
    var seconds = Math.max(0, Math.floor(Date.now() / 1000) - then)
    if (seconds < 90) return "just now"
    if (seconds < 3600) return Math.floor(seconds / 60) + " minutes ago"
    if (seconds < 86400) return Math.floor(seconds / 3600) + " hours ago"
    return Math.floor(seconds / 86400) + " days ago"
  }

  function signed(value) {
    var n = Number(value) || 0
    return (n > 0 ? "+" : "") + n.toLocaleString(Qt.locale(), "f", 0)
  }

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      if (service) service.refresh()
    } else {
      selectedId = ""
    }
  }

  readonly property string tooltip: {
    if (error !== "") return "WoW Character Card: " + error
    if (!main) return "WoW Character Card"
    var text = main.name + " \u00b7 Level " + main.level
    if (session) text += " \u00b7 " + duration(sessionSeconds) + " this session"
    return text
  }

  // ---------------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // On a vertical bar there is no room for the face, so the glyph stands in.
    text: root.vertical ? root.glyph : ""
    labelVisible: root.vertical
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : face.implicitWidth + scaledHorizontalMargin * 2
    dimmed: root.main === null
    tooltipText: root.tooltip
    onPressed: root.toggle()

    Row {
      id: face
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.main !== null
        text: root.main ? String(root.main.level) : ""
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      XpBar {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.mainHasXp
        percent: root.mainHasXp ? Number(root.main.xpPercent) : 0
        restedPercent: root.mainHasXp ? Number(root.main.restedPercent || 0) : 0
        foreground: button.foreground
        fill: button.foreground
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.mainHasXp && root.showPercent
        text: root.mainHasXp ? root.main.xpPercent + "%" : ""
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.session !== null && root.showClock
        text: root.duration(root.sessionSeconds)
        color: button.foreground
        opacity: 0.7
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }
  }

  // -------------------------------------------------------------------- panel

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: !root.loaded
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(16)
          bottomPadding: Style.space(16)
          text: "Looking for WoW\u2026"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        SetupView {
          width: parent.width
          visible: root.loaded && root.shown === null
          setup: root.setup
          error: root.error
          installs: root.installs
          gameRunning: root.running !== null
          installing: root.service ? root.service.installing : false
          installResults: root.service ? root.service.installResults : []
          searching: root.service ? root.service.searching : false
          foreground: root.foreground
          fontFamily: root.fontFamily
          onInstallRequested: if (root.service) root.service.installAddon()
          onSearchRequested: if (root.service) root.service.search()
        }

        // ----------------------------------------------------- the card

        CharacterCard {
          width: parent.width
          visible: root.shown !== null
          character: root.shown
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // A newer plugin may read fields an older addon does not write.
        Item {
          width: parent.width
          height: updateButton.implicitHeight
          visible: root.shown !== null && root.helperSetup === "addon-outdated"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: updateButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "A newer addon is ready"
            elide: Text.ElideRight
            color: root.foreground
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Button {
            id: updateButton
            anchors.right: parent.right
            bordered: true
            enabled: !(root.service && root.service.installing)
            text: "Update addon"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.installAddon()
          }
        }

        // ------------------------------------------------- last session

        PanelSeparator {
          visible: lastSession.visible
          foreground: root.foreground
        }

        Column {
          id: lastSession
          width: parent.width
          spacing: Style.space(4)
          visible: root.shown !== null && root.shown.session !== null
            && root.shown.session !== undefined

          PanelSectionHeader {
            text: "LAST SESSION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          StatRow {
            label: "Levels"
            value: lastSession.visible && Number(root.shown.session.levelsGained || 0) > 0
              ? "+" + root.shown.session.levelsGained : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          StatRow {
            label: "XP"
            value: lastSession.visible ? root.signed(root.shown.session.xpGained) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          StatRow {
            label: "Gold"
            value: lastSession.visible
              ? (Number(root.shown.session.moneyDelta || 0) > 0 ? "+" : "")
                + String(root.shown.session.moneyText || "")
              : ""
            valueColor: lastSession.visible && Number(root.shown.session.moneyDelta || 0) < 0
              ? Color.urgent : root.foreground
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        // ---------------------------------------------------- play time

        PanelSeparator {
          visible: playTime.visible
          foreground: root.foreground
        }

        Column {
          id: playTime
          width: parent.width
          spacing: Style.space(4)
          visible: root.loaded && root.setup !== "error" && root.setup !== "no-install"

          PanelSectionHeader {
            text: "PLAY TIME"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          StatRow {
            label: root.running ? "This session \u00b7 " + String(root.running.label || "") : "This session"
            value: root.session ? root.duration(root.sessionSeconds) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          StatRow {
            label: "Today"
            value: root.duration(Number(root.playtime.today || 0) + root.sinceStatus)
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          StatRow {
            label: "This week"
            value: root.duration(Number(root.playtime.week || 0) + root.sinceStatus)
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        // --------------------------------------------------------- alts

        PanelSeparator {
          visible: alts.visible
          foreground: root.foreground
        }

        Column {
          id: alts
          width: parent.width
          spacing: Style.space(2)
          visible: root.others.length > 0

          PanelSectionHeader {
            text: "CHARACTERS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            // A long list would push the panel off the screen.
            model: root.others.slice(0, 8)

            AltRow {
              required property var modelData
              character: modelData
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.selectedId = modelData.id
            }
          }
        }

        // ------------------------------------------------------- footer

        Item {
          width: parent.width
          height: refreshButton.implicitHeight
          visible: root.loaded

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: refreshButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.shown && root.ago(root.shown.updatedAt) !== ""
              ? "Updated " + root.ago(root.shown.updatedAt) : ""
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelActionButton {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.refreshGlyph
            tooltipText: "Read the saved data again"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.refresh()
          }
        }
      }
    }
  }
}
