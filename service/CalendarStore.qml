pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../CalendarModel.js" as Model

QtObject {
  id: root

  property var calendars: []
  property string configError: ""
  property var loadedConfigText: null
  property int generation: 0
  property var windows: ({})
  property var requestedWindows: ({})
  property string state: "cachedData"
  property bool backendReady: false
  property bool refreshPending: false
  property bool externalConfigAvailable: false
  readonly property string externalConfigPath: Quickshell.env("HOME") + "/.config/intemporel/calendars.jsonc"
  readonly property string configPath: decodeURIComponent(Qt.resolvedUrl("../calendars.jsonc").toString().replace(/^file:\/\//, ""))
  readonly property string backendPath: decodeURIComponent(Qt.resolvedUrl("../backend.py").toString().replace(/^file:\/\//, ""))

  function send(message) {
    if (!backendReady) return
    message.generation = generation
    worker.write(JSON.stringify(message) + "\n")
  }

  function ensureStarted() {
    if (!worker.running) worker.running = true
  }

  function configure(text) {
    text = String(text || "")
    // yadm's automatic chmod also fires FileView notifications. Configuration
    // identity is its content, never its metadata or the panel's locale.
    if (text === loadedConfigText) return
    loadedConfigText = text
    var parsed = Model.parseConfigResult(text, "Calendar")
    configError = parsed.error
    calendars = parsed.calendars
    generation++
    windows = ({})
    sendConfiguration()
  }

  function sendConfiguration() {
    if (!backendReady) return
    send({ type: "configure", calendars: calendars })
    for (var key in requestedWindows) send(requestedWindows[key])
    if (refreshPending && !configError) {
      refreshPending = false
      send({ type: "refresh" })
    }
  }

  function requestWindow(year, month, firstDay) {
    var first = new Date(year, month, 1)
    var lead = (first.getDay() - firstDay + 7) % 7
    var start = new Date(year, month, 1 - lead)
    var stop = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 42)
    var key = Model.dateKey(start) + "/" + Model.dateKey(stop)
    var request = { type: "window", key: key, start: Model.dateKey(start), stop: Model.dateKey(stop) }
    var next = Object.assign({}, requestedWindows)
    next[key] = request
    var keys = Object.keys(next)
    while (keys.length > 6) delete next[keys.shift()]
    requestedWindows = next
    ensureStarted()
    if (!windows[key]) send(request)
    return key
  }

  function refresh() {
    if (configError) return
    ensureStarted()
    if (backendReady) send({ type: "refresh" })
    else refreshPending = true
  }

  function receive(line) {
    var message
    try { message = JSON.parse(line) } catch (error) { return }
    if (message.type === "ready") {
      backendReady = true
      sendConfiguration()
      return
    }
    if (message.generation !== generation) return
    if (message.type === "status") state = message.state
    else if (message.type === "window") {
      var next = Object.assign({}, windows)
      next[message.key] = message.days
      var keys = Object.keys(next)
      while (keys.length > 6) delete next[keys.shift()]
      windows = next
    }
  }

  property Process worker: Process {
    command: ["nice", "-n", "10", "uv", "run", "--quiet", "--locked", "--script", root.backendPath]
    environment: ({ PYTHONDONTWRITEBYTECODE: "1" })
    stdinEnabled: true
    running: true
    stdout: SplitParser { onRead: data => root.receive(data) }
    onExited: {
      root.backendReady = false
      root.state = "workerUnavailable"
    }
  }

  property FileView externalConfig: FileView {
    path: root.externalConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.externalConfigAvailable = true
      root.configure(text())
    }
    onLoadFailed: {
      root.externalConfigAvailable = false
      localConfig.reload()
    }
    onFileChanged: reload()
  }

  property FileView localConfig: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: if (!root.externalConfigAvailable) root.configure(text())
    onLoadFailed: if (!root.externalConfigAvailable) root.configure('{"calendars":[]}')
    onFileChanged: reload()
  }
}
