function pad(value) {
  return (value < 10 ? "0" : "") + value
}

function dateKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function stripJsonComments(raw) {
  var input = String(raw || "{}")
  var output = ""
  var inString = false
  var escaped = false
  var lineComment = false
  var blockComment = false
  for (var i = 0; i < input.length; i++) {
    var character = input.charAt(i)
    var next = input.charAt(i + 1)
    if (lineComment) {
      if (character === "\n" || character === "\r") {
        lineComment = false
        output += character
      }
      continue
    }
    if (blockComment) {
      if (character === "*" && next === "/") {
        blockComment = false
        i++
      } else if (character === "\n" || character === "\r") output += character
      continue
    }
    if (inString) {
      output += character
      if (escaped) escaped = false
      else if (character === "\\") escaped = true
      else if (character === "\"") inString = false
      continue
    }
    if (character === "\"") {
      inString = true
      output += character
    } else if (character === "/" && next === "/") {
      lineComment = true
      i++
    } else if (character === "/" && next === "*") {
      blockComment = true
      i++
    } else output += character
  }
  return output
}

function stripTrailingCommas(raw) {
  var input = String(raw || "{}")
  var output = ""
  var inString = false
  var escaped = false
  for (var i = 0; i < input.length; i++) {
    var character = input.charAt(i)
    if (inString) {
      output += character
      if (escaped) escaped = false
      else if (character === "\\") escaped = true
      else if (character === "\"") inString = false
      continue
    }
    if (character === "\"") {
      inString = true
      output += character
      continue
    }
    if (character === ",") {
      var next = i + 1
      while (/\s/.test(input.charAt(next))) next++
      if (input.charAt(next) === "}" || input.charAt(next) === "]") continue
    }
    output += character
  }
  return output
}

function parseConfigResult(raw, defaultCalendarName) {
  try {
    var parsed = JSON.parse(stripTrailingCommas(stripJsonComments(raw)))
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.calendars))
      return { calendars: [], error: "The calendars field must be an array." }
    var calendars = parsed.calendars
    var result = []
    for (var i = 0; i < calendars.length; i++) {
      var item = calendars[i]
      if (!item || !String(item.url || "").trim()) continue
      var url = String(item.url).trim().replace(/^webcal:/i, "https:")
      if (!/^(https?|file):\/\//i.test(url)) return { calendars: [], error: "Calendar URLs must use HTTP, HTTPS or file." }
      if (result.some(function(calendar) { return calendar.url === url }))
        return { calendars: [], error: "Each calendar URL must be unique." }
      result.push({
        name: String(item.name || defaultCalendarName || "Calendar"),
        url: url,
        color: String(item.color || ""),
        excludeDeclined: item.excludeDeclined !== false,
        emails: (Array.isArray(item.emails) ? item.emails : (item.email ? [item.email] : []))
          .map(function(email) { return String(email).trim().toLowerCase() })
          .filter(function(email) { return email !== "" })
      })
    }
    return { calendars: result, error: "" }
  } catch (error) {
    return { calendars: [], error: "Invalid JSONC." }
  }
}

function parseConfig(raw, defaultCalendarName) {
  return parseConfigResult(raw, defaultCalendarName).calendars
}

function daysInMonth(year, month) {
  return new Date(year, month + 1, 0).getDate()
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
  var time = event.allDay ? "" : formatTime(new Date(event.start), timeLocale || locale)
  return { time: time, title: event.summary, location: event.location, calendar: event.calendar, color: event.color }
}
