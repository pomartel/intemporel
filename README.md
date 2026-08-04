# Intemporel — An Omarchy 4 Clock and Calendar Plugin

Intemporel is a clock replacement and read-only calendar for
[Omarchy](https://omarchy.org/). It displays a date/time label in the bar and
opens an event calendar from public iCalendar (ICS) feeds.

## Features

- Drop-in replacement for `omarchy.clock`: left-click opens the calendar,
  right-click cycles clock formats, and middle-click opens the timezone picker.
  The calendar opens inward from whichever screen edge holds the bar.
- Monthly calendar view with today and the selected day highlighted
- Read-only event display from one or more public ICS URLs
- Calendar-specific names and colors
- Keyboard navigation
- No calendar accounts, credentials, or write access required

## Installation

Install the plugin with the Omarchy plugin manager:

```bash
omarchy plugin add https://github.com/pomartel/intemporel.git
```

Then enable it if the installer did not enable it automatically:

```bash
omarchy plugin enable intemporel
```

The plugin is installed at:

```text
~/.config/omarchy/plugins/intemporel/
```

Replace the default clock in `~/.config/omarchy/shell.json`. Intemporel uses
Canadian French by default; set `locale` on the bar entry to override it.

```json
{
  "bar": {
    "centerAnchor": "intemporel",
    "layout": {
      "center": [{
        "id": "intemporel",
        "format": "dddd HH:mm",
        "formatAlt": "d MMMM 'W'ww yyyy",
        "locale": "fr_CA"
      }]
    }
  }
}
```

The calendar can also be opened through the Omarchy shell IPC interface:

```bash
omarchy-shell shell toggle intemporel
```

## Configuration

Copy `calendar.json.example` to `calendar.json` inside the plugin directory, then
edit the local file:

```json
{
  "calendars": [
    {
      "name": "Work",
      "url": "https://example.com/work.ics",
      "color": "#4285F4"
    },
    {
      "name": "Family",
      "url": "https://example.com/family.ics",
      "color": "#F59E0B"
    }
  ]
}
```

`calendar.json` is intentionally not tracked by Git, so personal calendar URLs
are preserved when the plugin updates. The example file is safe to replace or
extend with your own read-only ICS feeds.

Each calendar entry supports:

- `name`: label used internally for the calendar source
- `url`: public, read-only ICS feed URL
- `color`: optional color for the event marker
- `excludeDeclined`: optional; defaults to `true`, hiding invitations you
  declined. Set it to `false` to show them.

The file is watched for changes and is reloaded automatically.

### Feed cache

Intemporel keeps the last successful response for each feed in
`$XDG_CACHE_HOME/intemporel-calendar-cache.json` (or
`~/.cache/intemporel-calendar-cache.json`). Cached events appear immediately
when the calendar opens; feeds then refresh in the background. The cache is
local and may contain the same private calendar data as the configured ICS URLs.

## Clock and locale behavior

The bar label and calendar use Canadian French (`fr_CA`) by default. Set the
bar entry's `locale` field to use another Qt locale. Right-click the clock to
cycle label formats; the chosen format is written back to `shell.json`.

Open the calendar with the same command used by the clock action:

```bash
omarchy-shell shell toggle intemporel
```

The event time follows the selected locale's short-time convention. 12-hour
locales display times such as `9:30am`; 24-hour locales display times such as
`9:30`.

### Privacy and security

Only use feeds that are intended to be shared with the people who can access
your computer. Some calendar providers use hard-to-guess URLs as a form of
access control. Treat those URLs like passwords and do not commit them to a
public repository.

Intemporel only downloads and displays events. It does not create, edit, or
delete calendar data.

## Keyboard controls

| Key | Action |
| --- | --- |
| `↑` `↓` `←` `→` | Move the selected day |
| `Ctrl` + arrow keys | Change month |
| `Enter` or `Home` | Go to today |
| `r` | Refresh calendar feeds |
| `Esc` | Close the panel |

## Troubleshooting

### No calendars appear

Check that:

1. `calendar.json` is valid JSON.
2. Each feed URL is reachable without authentication.
3. `curl -fsSL "https://example.com/calendar.ics"` can fetch the feed.
4. The feed contains valid `VEVENT` entries.

### A feed stops updating

Use `r` while the panel is open to refresh immediately. Intemporel also
refreshes feeds periodically while open. Verify that the provider has not
revoked or changed the public feed URL.

## Updating

Update installed plugins with:

```bash
omarchy plugin update intemporel
```

## Development

The plugin consists of:

- `BarWidget.qml`: clock label and calendar host, following the Omarchy clock structure
- `Model.js`: clock label formatting helpers
- `Calendar.qml`: calendar UI, keyboard handling, and shell integration
- `CalendarModel.js`: ICS parsing, recurrence expansion, and formatting
- `calendar.json.example`: starter calendar configuration
- `calendar.json`: local, Git-ignored calendar configuration
- `manifest.json`: Omarchy plugin metadata and entry point

Validate the plugin before submitting changes:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell Calendar.qml
node --check CalendarModel.js
```

Pull requests and issue reports are welcome.

## License

Intemporel is released under the [MIT License](LICENSE).
