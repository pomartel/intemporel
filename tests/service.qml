import QtQuick
import Quickshell
import "../service" as Service

Scope {
  id: test
  property string key: ""
  property int windowsReceived: 0
  property bool requested: false

  function start() {
    if (requested || Service.CalendarStore.calendars.length !== 1) return
    requested = true
    key = Service.CalendarStore.requestWindow(2026, 8, 1)
    // A second monitor must use the same window and coalesce its refresh.
    if (Service.CalendarStore.requestWindow(2026, 8, 1) !== key) throw new Error("Window identity differs")
    var before = Service.CalendarStore.generation
    Service.CalendarStore.configure(Service.CalendarStore.loadedConfigText)
    if (Service.CalendarStore.generation !== before) throw new Error("Metadata notification changed generation")
    Service.CalendarStore.refresh()
    Service.CalendarStore.refresh()
  }

  Connections {
    target: Service.CalendarStore
    function onCalendarsChanged() { Qt.callLater(test.start) }
    function onStateChanged() {
      if (Service.CalendarStore.state !== "updated") return
      var days = Service.CalendarStore.windows[test.key]
      if (!days || !days["2026-09-28"] || days["2026-09-28"][0].summary !== "Integration meeting") {
        console.error("SERVICE_TEST_FAILED: missing downloaded event")
        Qt.quit()
        return
      }
      // A late response from an earlier configuration must not enter the UI.
      Service.CalendarStore.receive(JSON.stringify({type: "window", generation: Service.CalendarStore.generation - 1, key: test.key, days: {}}))
      if (!Service.CalendarStore.windows[test.key]["2026-09-28"]) throw new Error("Accepted stale window")
      console.log("SERVICE_TEST_PASSED")
      Qt.quit()
    }
  }
  Component.onCompleted: Qt.callLater(test.start)
  Timer {
    interval: 20000
    running: true
    onTriggered: { console.error("SERVICE_TEST_FAILED: timeout", Service.CalendarStore.state); Qt.quit() }
  }
}
