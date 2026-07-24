import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "CalendarModel.js" as Model

Item {
  id: root

  property bool opened: false
  property var calendars: []
  property var events: []
  property var monthEvents: ({})
  property var selectedDate: new Date()
  property var viewDate: new Date()
  property int preferredDay: selectedDate.getDate()
  property string statusText: ""
  property int fetchIndex: 0
  property string fetchRaw: ""
  property bool fetchInProgress: false
  property string requestedScreenName: ""
  property string explicitLocaleName: ""
  readonly property var locale: root.explicitLocaleName ? Qt.locale(root.explicitLocaleName) : Qt.locale()
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/intemporel/calendar.json"
  readonly property int viewYear: viewDate.getFullYear()
  readonly property int viewMonth: viewDate.getMonth()
  readonly property string selectedKey: Model.dateKey(selectedDate)
  readonly property var selectedEvents: {
    var list = root.monthEvents[root.selectedKey] || []
    var formatted = []
    for (var i = 0; i < list.length; i++) formatted.push(Model.formatEvent(list[i], root.locale, Qt.locale()))
    return formatted
  }
  readonly property string monthTitle: (root.capitalize(root.locale.toString(root.viewDate, "MMMM")) + " " + root.viewYear).toUpperCase()
  property var dayCells: []
  readonly property var weekdayNames: buildWeekdayNames()
  readonly property var targetScreen: findTargetScreen()

  function capitalize(value) {
    var text = String(value || "")
    return text ? text.charAt(0).toUpperCase() + text.slice(1) : text
  }

  function selectedDateTitle(date) {
    return root.capitalize(root.locale.toString(date, "dddd"))
      + ", " + root.locale.toString(date, "d")
      + " " + root.locale.toString(date, "MMMM")
  }

  function open(payloadJson) {
    root.requestedScreenName = ""
    root.explicitLocaleName = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && payload.screen) root.requestedScreenName = String(payload.screen)
      if (payload && payload.locale) root.explicitLocaleName = String(payload.locale)
    } catch (error) {
      root.requestedScreenName = ""
      root.explicitLocaleName = ""
    }
    root.opened = true
    root.selectedDate = new Date()
    root.preferredDay = root.selectedDate.getDate()
    root.viewDate = new Date()
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }
  function toggle() { root.opened ? root.close() : root.open() }

  function findTargetScreen() {
    var wanted = root.requestedScreenName
    if (wanted) {
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === wanted) return Quickshell.screens[i]
    }
    if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
      for (var j = 0; j < Quickshell.screens.length; j++)
        if (Quickshell.screens[j].name === Hyprland.focusedMonitor.name) return Quickshell.screens[j]
    return Quickshell.screens.length ? Quickshell.screens[0] : null
  }

  function setViewDate(year, month) {
    root.viewDate = new Date(year, month, 1)
    root.rebuildMonth()
  }

  function shiftMonth(amount) {
    root.viewDate = new Date(root.viewYear, root.viewMonth + amount, 1)
    var day = Math.min(root.preferredDay, Model.daysInMonth(root.viewDate.getFullYear(), root.viewDate.getMonth()))
    root.selectedDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth(), day)
    root.rebuildMonth()
  }

  function moveDay(dx, dy) {
    var next = new Date(root.selectedDate.getTime())
    next.setDate(next.getDate() + dx + dy * 7)
    root.selectedDate = next
    root.preferredDay = next.getDate()
    if (next.getMonth() !== root.viewMonth || next.getFullYear() !== root.viewYear)
      root.viewDate = new Date(next.getFullYear(), next.getMonth(), 1)
    root.rebuildMonth()
  }

  function goToday() {
    var today = new Date()
    root.selectedDate = today
    root.preferredDay = today.getDate()
    root.viewDate = new Date(today.getFullYear(), today.getMonth(), 1)
    root.rebuildMonth()
  }

  function buildDayCells() {
    var first = new Date(root.viewYear, root.viewMonth, 1)
    var firstDay = first.getDay()
    var localeFirst = Number(root.locale.firstDayOfWeek || 1) % 7
    var lead = (firstDay - localeFirst + 7) % 7
    var start = new Date(root.viewYear, root.viewMonth, 1 - lead)
    var cells = []
    for (var i = 0; i < 42; i++) {
      var date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
      var key = Model.dateKey(date)
      cells.push({
        date: date,
        key: key,
        day: date.getDate(),
        inMonth: date.getMonth() === root.viewMonth && date.getFullYear() === root.viewYear,
        today: key === Model.dateKey(new Date()),
        selected: key === root.selectedKey,
        hasEvents: (root.monthEvents[key] || []).length > 0
      })
    }
    return cells
  }

  function buildWeekdayNames() {
    var names = []
    var first = Number(root.locale.firstDayOfWeek || 1)
    for (var i = 0; i < 7; i++) {
      var day = (first - 1 + i) % 7
      var date = new Date(2024, 0, 1 + day)
      names.push(root.capitalize(root.locale.toString(date, "ddd")))
    }
    return names
  }

  function rebuildMonth() {
    root.monthEvents = Model.eventsForMonth(root.events, root.viewYear, root.viewMonth)
    root.dayCells = buildDayCells()
  }

  function refresh() {
    if (root.fetchInProgress) return
    root.fetchIndex = 0
    root.events = []
    root.monthEvents = ({})
    root.statusText = root.calendars.length ? "Refreshing calendars…" : "No calendars configured"
    root.fetchInProgress = root.calendars.length > 0
    if (root.fetchInProgress) root.fetchNext()
  }

  function fetchNext() {
    if (root.fetchIndex >= root.calendars.length) {
      root.fetchInProgress = false
      root.rebuildMonth()
      if (!root.statusText || root.statusText === "Refreshing calendars…") root.statusText = "Updated"
      return
    }
    var calendar = root.calendars[root.fetchIndex]
    root.fetchRaw = ""
    feedProcess.command = ["curl", "-fsSL", "--max-time", "15", calendar.url]
    feedProcess.running = true
  }

  function parseFetchedFeed() {
    var calendar = root.calendars[root.fetchIndex]
    var parsed = Model.parseIcs(root.fetchRaw, calendar)
    for (var i = 0; i < parsed.length; i++) root.events.push(parsed[i])
    root.fetchIndex++
    root.fetchNext()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.calendars = Model.parseConfig(text())
      if (root.opened) root.refresh()
    }
    onLoadFailed: {
      root.calendars = []
      root.rebuildMonth()
    }
    onFileChanged: reload()
  }

  Process {
    id: feedProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fetchRaw = String(text || "")
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.fetchRaw.trim()) root.parseFetchedFeed()
      else {
        root.statusText = "A calendar could not be refreshed"
        root.fetchIndex++
        root.fetchNext()
      }
    }
  }

  Timer {
    interval: 15 * 60 * 1000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "local-calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      z: 1
      width: Math.min(Style.space(380), parent.width - Style.gapsOut * 2)
      height: Math.min(
        parent.height - Style.bar.sizeHorizontal - Style.gapsOut * 2,
        contentColumn.implicitHeight + card.contentTopInset + card.contentBottomInset)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.bar.sizeHorizontal + Style.gapsOut
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: Style.spacing.popupPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        PanelHero {
          width: parent.width
          title: "Calendar"
          meta: root.statusText
          fontFamily: Style.fontFamily

          iconComponent: Component {
            Text {
              text: "󰃭"
              color: Color.foreground
              font.family: Style.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: Color.foreground }

        Text {
          text: root.monthTitle
          color: Color.foreground
          font.family: Style.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Column {
          width: parent.width
          spacing: Style.space(1)

          Grid {
            id: weekdayGrid
            width: parent.width
            columns: 7
            spacing: Style.space(2)
            Repeater {
              model: root.weekdayNames
              delegate: Text {
                required property string modelData
                width: (weekdayGrid.width - Style.space(12)) / 7
                height: Style.space(22)
                text: modelData.substring(0, 2)
                color: Color.accent
                font.family: Style.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          Grid {
            id: dayGrid
            width: parent.width
            columns: 7
            rows: 6
            spacing: Style.space(2)
            Repeater {
              model: root.dayCells
              delegate: Rectangle {
                required property var modelData
                width: (dayGrid.width - Style.space(12)) / 7
                height: Style.space(36)
                radius: Style.cornerRadius / 2
                color: modelData.selected ? Color.accent : (modelData.today ? Util.alpha(Color.accent, 0.22) : "transparent")
                opacity: modelData.inMonth ? 1 : 0.35

                Text {
                  anchors.centerIn: parent
                  text: modelData.day
                  color: modelData.selected ? Color.background : Color.foreground
                  font.family: Style.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: modelData.today || modelData.selected
                }

                Rectangle {
                  visible: modelData.hasEvents
                  width: Style.space(5)
                  height: width
                  radius: width / 2
                  color: modelData.selected ? Color.background : Color.accent
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.selectedDate = modelData.date
                    root.preferredDay = modelData.date.getDate()
                    root.viewDate = new Date(modelData.date.getFullYear(), modelData.date.getMonth(), 1)
                    root.rebuildMonth()
                  }
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Color.foreground; opacity: 0.14 }

        Column {
          width: parent.width
          spacing: Style.space(4)
          Text {
            text: root.selectedDateTitle(root.selectedDate)
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            visible: root.selectedEvents.length === 0
            text: "No events"
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.selectedEvents
            delegate: Item {
              required property var modelData
              width: parent.width
              height: eventRow.implicitHeight
              Row {
                id: eventRow
                anchors.fill: parent
                spacing: Style.space(8)
                Rectangle { width: Style.space(3); height: Style.space(30); color: modelData.color || Color.accent; radius: 2; anchors.verticalCenter: parent.verticalCenter }
                Column {
                  id: eventColumn
                  width: parent.width - Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  Text { text: (modelData.time ? modelData.time + "  " : "") + modelData.title; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
                }
              }
            }
          }
        }

        PanelSeparator { foreground: Color.foreground }

        Text {
          text: "󰁁 day   Ctrl󰁁 month   ⏎ today   r refresh   Esc close"
          anchors.left: parent.left
          anchors.right: parent.right
          color: Util.alpha(Color.foreground, 0.55)
          font.family: Style.fontFamily
          font.pixelSize: Style.font.caption
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: Style.space(8)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.NoWrap
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (!root.opened) return
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true; return }
        if (event.key === Qt.Key_Home) { root.goToday(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.goToday(); event.accepted = true; return }
        if (event.text === "r" || event.text === "R") { root.refresh(); event.accepted = true; return }

        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        if (event.key === Qt.Key_Left || event.key === Qt.Key_H
            || event.key === Qt.Key_Right || event.key === Qt.Key_L
            || event.key === Qt.Key_Up || event.key === Qt.Key_K
            || event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          var previous = event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Up || event.key === Qt.Key_K
          if (ctrl) root.shiftMonth(previous ? -1 : 1)
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) root.moveDay(-1, 0)
          else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) root.moveDay(1, 0)
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) root.moveDay(0, -1)
          else root.moveDay(0, 1)
          event.accepted = true
        }
      }
    }
  }

  Component.onCompleted: root.rebuildMonth()
}
