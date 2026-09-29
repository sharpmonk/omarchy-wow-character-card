import QtQuick
import Quickshell.Io

// The one place that talks to bin/wcc.
//
// Omarchy builds a bar per monitor, so a timer on the widget would poll once
// per screen and write the play-time log once per screen. This service is
// mounted once for the shell; every widget reads from it.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property string omarchyPath: ""

  // Pushed in by the widget from its settings.
  property string wowFolder: ""
  property bool demo: false

  // The last good answer from the helper. Kept when a later call fails, so a
  // hiccup does not blank the bar.
  property var status: ({})
  property bool loaded: false
  property string error: ""
  property bool installing: false
  property bool searching: false
  property var installResults: []
  // A refresh asked for while the helper was still running.
  property bool refreshQueued: false

  readonly property int pollMs: 15000

  // Asks the widget on one monitor to open its panel. A plain `open` reaches
  // only one bar, and not one the caller can choose.
  signal openRequested(string screen)

  readonly property string script:
    decodeURIComponent(Qt.resolvedUrl("bin/wcc").toString().replace(/^file:\/\//, ""))

  readonly property var helperEnvironment: ({
    "WCC_WOW_DIR": root.wowFolder,
    "WCC_DEMO": root.demo ? "1" : "0"
  })

  function helper(args) {
    return [root.script].concat(args)
  }

  function refresh() {
    if (tickProc.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    tickProc.command = root.helper(["tick"])
    tickProc.running = true
  }

  function installAddon() {
    if (installProc.running) return
    root.installResults = []
    root.installing = true
    installProc.command = root.helper(["install-addon"])
    installProc.running = true
  }

  function search() {
    if (searchProc.running) return
    root.searching = true
    searchProc.command = root.helper(["installs", "--rescan"])
    searchProc.running = true
  }

  function absorb(text) {
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return
    if (data.ok !== true) {
      root.error = String(data.message || data.error || "The helper failed")
      root.loaded = true
      return
    }
    root.error = ""
    root.status = data
    root.loaded = true
  }

  // Deferred, so the process has the new environment before it starts.
  onHelperEnvironmentChanged: Qt.callLater(root.refresh)

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: tickProc
    environment: root.helperEnvironment
    stdout: StdioCollector {
      onStreamFinished: root.absorb(text)
    }
    onExited: function(exitCode) {
      if (root.refreshQueued) Qt.callLater(root.refresh)
    }
  }

  Process {
    id: installProc
    environment: root.helperEnvironment
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.installResults = Array.isArray(data) ? data : []
        } catch (e) {
          root.installResults = []
        }
      }
    }
    onExited: function(exitCode) {
      root.installing = false
      root.refresh()
    }
  }

  Process {
    id: searchProc
    environment: root.helperEnvironment
    onExited: function(exitCode) {
      root.searching = false
      root.refresh()
    }
  }

  IpcHandler {
    target: "sharpmonk.wow-character-card.service"

    function refresh(): string {
      root.refresh()
      return "refreshing"
    }

    // Opens the panel on the named monitor, for example DP-2.
    function openOn(screen: string): string {
      root.openRequested(screen)
      return "asked " + screen
    }

    // Made-up characters, for taking screenshots.
    function demo(enabled: bool): string {
      root.demo = enabled
      return enabled ? "demo on" : "demo off"
    }

    function state(): string {
      var s = root.status || {}
      return JSON.stringify({
        loaded: root.loaded,
        error: root.error,
        demo: root.demo,
        setup: s.setup || "",
        running: s.running ? s.running.label : "",
        characters: s.characters ? s.characters.length : 0,
        installs: s.installs ? s.installs.length : 0
      })
    }
  }
}
