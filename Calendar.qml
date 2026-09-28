import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "CalendarModel.js" as Model
import "Translations.js" as Translations
import "service" as Service

Item {
  id: root

  // BarWidget.qml owns this panel, as Omarchy's clock owns its calendar
  // popup. These are injected by the host so the calendar and its clock are
  // one plugin while this full-screen panel keeps its monitor-aware layout.
  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  property bool opened: false
  readonly property var calendars: Service.CalendarStore.calendars
  property string windowKey: ""
  readonly property var monthEvents: Service.CalendarStore.windows[windowKey] || ({})
  property var selectedDate: new Date()
  property var viewDate: new Date()
  property int preferredDay: selectedDate.getDate()
  readonly property string statusText: configError ? root.t("invalidConfiguration") : root.t(Service.CalendarStore.state)
  readonly property string configError: Service.CalendarStore.configError
  property bool keyboardHelpVisible: false
  property string requestedScreenName: ""
  property string explicitLocaleName: ""
  property string fontFamily: Style.font.menuFamily
  property color background: Color.popups.background
  property color foreground: Color.popups.text
  property color border: Color.popups.border
  property var borderSpec: Border.surfaceSpec("popups", "border", root.border, Math.max(1, Style.space(2)))
  readonly property var locale: root.explicitLocaleName ? Qt.locale(root.explicitLocaleName) : Qt.locale()
  // Match Omarchy's clock KeyboardPanel: its calendar is centered on the
  // bar edge, opening inward from top, bottom, left, or right.
  readonly property string barPosition: root.bar && root.bar.position ? root.bar.position : "top"
  readonly property bool verticalBar: root.barPosition === "left" || root.barPosition === "right"
  readonly property real barThickness: root.verticalBar ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int viewYear: viewDate.getFullYear()
  readonly property int viewMonth: viewDate.getMonth()
  readonly property string selectedKey: Model.dateKey(selectedDate)
  readonly property var selectedEvents: root.monthEvents[root.selectedKey] || []
  readonly property string monthTitle: root.capitalize(root.locale.toString(root.viewDate, root.t("monthYearFormat"))).toUpperCase()
  property var dayCells: []
  readonly property var weekdayNames: buildWeekdayNames()
  readonly property var targetScreen: findTargetScreen()

  function capitalize(value) {
    var text = String(value || "")
    return text ? text.charAt(0).toUpperCase() + text.slice(1) : text
  }

  function t(key) { return Translations.get(root.locale, key) }

  function selectedDateTitle(date) {
    return root.capitalize(root.locale.toString(date, root.t("selectedDateFormat")))
  }

  function open(payloadJson) {
    root.requestedScreenName = ""
    root.explicitLocaleName = ""
    root.keyboardHelpVisible = false
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
    root.rebuildMonth()
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }
  function toggle() { root.opened ? root.close() : root.open() }

  function openConfigEditor() {
    root.close()
    configEditorProcess.command = ["omarchy-launch-editor", Service.CalendarStore.externalConfigAvailable ? Service.CalendarStore.externalConfigPath : Service.CalendarStore.configPath]
    configEditorProcess.running = true
  }

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

  function cardX(cardWidth) {
    var margin = Style.gapsOut
    var x = root.verticalBar
      ? (root.barPosition === "left" ? root.barThickness + margin : panel.width - root.barThickness - cardWidth - margin)
      : (panel.width - cardWidth) / 2
    return Math.max(margin, Math.min(x, panel.width - cardWidth - margin))
  }

  function cardY(cardHeight) {
    var margin = Style.gapsOut
    var y = root.verticalBar
      ? (panel.height - cardHeight) / 2
      : (root.barPosition === "bottom" ? panel.height - root.barThickness - cardHeight - margin : root.barThickness + margin)
    return Math.max(margin, Math.min(y, panel.height - cardHeight - margin))
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
    var firstDay = Number(root.locale.firstDayOfWeek || 1) % 7
    root.windowKey = Service.CalendarStore.requestWindow(root.viewYear, root.viewMonth, firstDay)
    root.dayCells = buildDayCells()
  }

  function refresh() { Service.CalendarStore.refresh() }

  onMonthEventsChanged: root.dayCells = buildDayCells()
  onLocaleChanged: if (root.opened) root.rebuildMonth()

  Connections {
    target: Service.CalendarStore
    function onGenerationChanged() {
      if (root.opened) {
        root.rebuildMonth()
        // Run after the new configuration has been sent to the worker.
        Qt.callLater(root.refresh)
      }
    }
  }

  Process { id: configEditorProcess }

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
    WlrLayershell.namespace: "omarchy-intemporel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      z: 1
      width: Math.max(1, Math.min(Style.space(380), parent.width - (root.verticalBar ? root.barThickness + Style.gapsOut * 2 : Style.gapsOut * 2)))
      height: Math.min(
        parent.height - (root.verticalBar ? Style.gapsOut * 2 : root.barThickness + Style.gapsOut * 2),
        contentColumn.implicitHeight + card.contentTopInset + card.contentBottomInset)
      x: root.cardX(width)
      y: root.cardY(height)
      color: root.background
      borderSpec: root.borderSpec
      radius: Style.cornerRadius
      padding: Style.spacing.popupPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Flickable {
        id: contentScroll
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: contentScroll.width
          spacing: Style.spacing.panelGap

          Item {
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              anchors.fill: parent
              title: root.t("calendar")
              meta: root.statusText
              fontFamily: root.fontFamily

              iconComponent: Component {
                Text {
                  text: "󰃭"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              visible: root.statusText === root.t("noCalendarsConfigured")
                    || root.statusText === root.t("updating")
                    || root.statusText === root.t("updated")
                    || root.configError
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openConfigEditor()
            }
          }

          PanelSeparator { foreground: root.foreground }

          Text {
            text: root.monthTitle
            color: root.foreground
            font.family: root.fontFamily
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
                  font.family: root.fontFamily
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
                    color: modelData.selected ? root.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: modelData.today || modelData.selected
                  }

                  Rectangle {
                    visible: modelData.hasEvents
                    width: Style.space(5)
                    height: width
                    radius: width / 2
                    color: modelData.selected ? root.background : Color.accent
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

          Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.foreground; opacity: 0.14 }

          Column {
            width: parent.width
            spacing: Style.space(4)
            Text {
              text: root.selectedDateTitle(root.selectedDate)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              visible: root.selectedEvents.length === 0
              text: root.t("noEvents")
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            ListView {
              width: parent.width
              implicitHeight: Math.min(contentHeight, Style.space(240))
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              spacing: Style.space(4)
              model: root.selectedEvents
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
              delegate: Item {
                required property var modelData
                readonly property var display: Model.formatEvent(modelData, root.locale)
                width: ListView.view.width
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
                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: (display.time ? display.time + "  " : "") + display.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }

          Column {
            visible: root.keyboardHelpVisible
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: contentColumn.spacing

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Text {
              width: parent.width
              text: root.t("keyboardHelp")
              color: Util.alpha(root.foreground, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              fontSizeMode: Text.HorizontalFit
              minimumPixelSize: Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.NoWrap
            }
          }
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
        if (event.text === "?") { root.keyboardHelpVisible = !root.keyboardHelpVisible; event.accepted = true; return }
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

  Component.onCompleted: root.dayCells = buildDayCells()
}
