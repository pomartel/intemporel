// Clock-label helpers. Calendar-specific data handling stays in
// CalendarModel.js so the bar host follows Omarchy's clock structure.

var CLOCK_FORMATS = [
  "dddd HH:mm",
  "HH:mm",
  "ddd d MMM HH:mm",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

function isoWeekLiteral(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  var week = Math.ceil(((date.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
  return (week < 10 ? "0" : "") + week
}
