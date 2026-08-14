.pragma library

var strings = {
  en: {
    calendar: "Calendar",
    cachedData: "Cached data",
    invalidConfiguration: "Calendar configuration is invalid",
    updating: "Updating...",
    noCalendarsConfigured: "No calendars configured",
    updated: "Updated",
    refreshFailed: "A calendar could not be refreshed",
    noEvents: "No events",
    keyboardHelp: "󰁁 day   Ctrl󰁁 month   ⏎ today   r refresh   Esc close",
    monthYearFormat: "MMMM yyyy",
    selectedDateFormat: "dddd, d MMMM"
  },
  fr: {
    calendar: "Calendrier",
    cachedData: "Données en cache",
    invalidConfiguration: "La configuration du calendrier n'est pas valide",
    updating: "Mise à jour...",
    noCalendarsConfigured: "Aucun calendrier configuré",
    updated: "Mis à jour",
    refreshFailed: "Impossible d'actualiser un calendrier",
    noEvents: "Aucun événement",
    keyboardHelp: "󰁁 jour   Ctrl󰁁 mois   ⏎ aujourd'hui   r actualiser   Échap fermer",
    monthYearFormat: "MMMM yyyy",
    selectedDateFormat: "dddd, d MMMM"
  },
  es: {
    calendar: "Calendario",
    cachedData: "Datos en caché",
    invalidConfiguration: "La configuración del calendario no es válida",
    updating: "Actualizando...",
    noCalendarsConfigured: "No hay calendarios configurados",
    updated: "Actualizado",
    refreshFailed: "No se pudo actualizar un calendario",
    noEvents: "No hay eventos",
    keyboardHelp: "󰁁 día   Ctrl󰁁 mes   ⏎ hoy   r actualizar   Esc cerrar",
    monthYearFormat: "MMMM 'de' yyyy",
    selectedDateFormat: "dddd, d 'de' MMMM"
  }
}

function languageFor(locale) {
  var name = String(locale && locale.name || "")
  return name.split(/[-_]/)[0].toLowerCase()
}

function get(locale, key) {
  var language = languageFor(locale)
  var translation = strings[language] || strings.en
  return translation[key] || strings.en[key] || key
}
