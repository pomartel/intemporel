function pad(value) {
  return (value < 10 ? "0" : "") + value
}

function dateKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function parseConfig(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    var calendars = Array.isArray(parsed.calendars) ? parsed.calendars : []
    var result = []
    for (var i = 0; i < calendars.length; i++) {
      var item = calendars[i]
      if (!item || !String(item.url || "").trim()) continue
      result.push({
        name: String(item.name || "Calendar"),
        url: String(item.url).trim(),
        color: String(item.color || ""),
        excludeDeclined: item.excludeDeclined !== false
      })
    }
    return result
  } catch (error) {
    return []
  }
}

function unfold(raw) {
  return String(raw || "").replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "").split(/\r?\n/)
}

function unescape(value) {
  return String(value || "")
    .replace(/\\n/gi, "\n")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\\\/g, "\\")
}

function propertyLine(line) {
  var split = String(line).split(":")
  if (split.length < 2) return null
  var value = split.slice(1).join(":")
  var left = split[0].split(";")
  var params = {}
  for (var i = 1; i < left.length; i++) {
    var pair = left[i].split("=")
    if (pair.length === 2) params[pair[0].toUpperCase()] = pair.slice(1).join("=")
  }
  return { name: left[0].toUpperCase(), params: params, value: value }
}

function parseDate(value, params) {
  var raw = String(value || "")
  var allDay = raw.length === 8 && raw.indexOf("T") < 0
  if (allDay) {
    return {
      date: new Date(Number(raw.slice(0, 4)), Number(raw.slice(4, 6)) - 1, Number(raw.slice(6, 8))),
      allDay: true
    }
  }
  var utc = raw.charAt(raw.length - 1) === "Z"
  if (utc) raw = raw.slice(0, -1)
  var y = Number(raw.slice(0, 4))
  var m = Number(raw.slice(4, 6)) - 1
  var d = Number(raw.slice(6, 8))
  var h = Number(raw.slice(9, 11) || 0)
  var min = Number(raw.slice(11, 13) || 0)
  var sec = Number(raw.slice(13, 15) || 0)
  return { date: utc ? new Date(Date.UTC(y, m, d, h, min, sec)) : new Date(y, m, d, h, min, sec), allDay: false }
}

function parseRule(value) {
  var rule = {}
  var parts = String(value || "").split(";")
  for (var i = 0; i < parts.length; i++) {
    var pair = parts[i].split("=")
    if (pair.length === 2) rule[pair[0].toUpperCase()] = pair[1]
  }
  return rule
}

function parseIcs(raw, calendar) {
  var lines = unfold(raw)
  var events = []
  var current = null
  for (var i = 0; i < lines.length; i++) {
    var prop = propertyLine(lines[i])
    if (!prop) continue
    if (prop.name === "BEGIN" && prop.value.toUpperCase() === "VEVENT") {
      current = { calendar: calendar.name, color: calendar.color, summary: "(untitled)", location: "", declined: false }
      continue
    }
    if (prop.name === "END" && prop.value.toUpperCase() === "VEVENT") {
      if (current && current.start && !(calendar.excludeDeclined && current.declined)) events.push(current)
      current = null
      continue
    }
    if (!current) continue
    if (prop.name === "SUMMARY") current.summary = unescape(prop.value)
    else if (prop.name === "LOCATION") current.location = unescape(prop.value)
    else if (prop.name === "ATTENDEE" && String(prop.params.PARTSTAT || "").toUpperCase() === "DECLINED") current.declined = true
    else if (prop.name === "DTSTART") current.start = parseDate(prop.value, prop.params)
    else if (prop.name === "DTEND") current.end = parseDate(prop.value, prop.params)
    else if (prop.name === "RRULE") current.rule = parseRule(prop.value)
  }
  return events
}

function daysInMonth(year, month) {
  return new Date(year, month + 1, 0).getDate()
}

function monthBounds(year, month) {
  return { start: new Date(year, month, 1), end: new Date(year, month, daysInMonth(year, month), 23, 59, 59) }
}

function addOccurrence(target, event, date) {
  var key = dateKey(date)
  if (!target[key]) target[key] = []
  var copy = {
    calendar: event.calendar,
    color: event.color,
    summary: event.summary,
    location: event.location,
    allDay: event.start.allDay,
    start: new Date(date.getTime()),
    end: event.end ? new Date(event.end.date.getTime()) : null
  }
  target[key].push(copy)
}

function overlapsMonth(event, year, month) {
  var bounds = monthBounds(year, month)
  return event.start.date <= bounds.end && (!event.end || event.end.date >= bounds.start)
}

function expandEvent(target, event, year, month) {
  if (!event.rule) {
    if (overlapsMonth(event, year, month)) addOccurrence(target, event, event.start.date)
    return
  }
  var freq = String(event.rule.FREQ || "").toUpperCase()
  if (["DAILY", "WEEKLY", "MONTHLY"].indexOf(freq) < 0) {
    if (overlapsMonth(event, year, month)) addOccurrence(target, event, event.start.date)
    return
  }
  var interval = Math.max(1, Number(event.rule.INTERVAL || 1))
  var count = Number(event.rule.COUNT || 0)
  var until = event.rule.UNTIL ? parseDate(event.rule.UNTIL, {}).date : null
  var cursor = new Date(event.start.date.getTime())
  for (var n = 0; n < 1000; n++) {
    if (count && n >= count) break
    if (until && cursor > until) break
    if (cursor > monthBounds(year, month).end) break
    if (cursor >= monthBounds(year, month).start) addOccurrence(target, event, cursor)
    if (freq === "DAILY") cursor.setDate(cursor.getDate() + interval)
    else if (freq === "WEEKLY") cursor.setDate(cursor.getDate() + 7 * interval)
    else cursor.setMonth(cursor.getMonth() + interval)
  }
}

function eventsForMonth(events, year, month) {
  var result = ({})
  for (var i = 0; i < events.length; i++) expandEvent(result, events[i], year, month)
  for (var key in result) {
    result[key].sort(function(a, b) { return a.start - b.start || a.summary.localeCompare(b.summary) })
  }
  return result
}

function formatTime(date, locale) {
  var pattern = locale.timeFormat(1)
  if (!/[aApP]{1,2}/.test(pattern)) return locale.toString(date, "H:mm")
  return locale.toString(date, pattern)
    .replace(/^0(?=\d)/, "")
    .replace(/\s+h\s*/i, ":")
    .replace(/\s*([AaPp])\.?\s*[Mm]\.?$/, function(_, meridiem) {
    return meridiem.toLowerCase() + "m"
  })
}

function formatEvent(event, locale, timeLocale) {
  var time = event.allDay ? "" : formatTime(event.start, timeLocale || locale)
  return { time: time, title: event.summary, location: event.location, calendar: event.calendar, color: event.color }
}
