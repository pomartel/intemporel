# Intemporel — Omarchy Quattro Clock/Calendar Plugin

Intemporel is a clockreplacement and read-only calendar for
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
the system locale by default; set `locale` on the bar entry to override it.

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

When Intemporel first loads, it copies `calendar.json.example` to
`~/.config/intemporel/calendar.json` without replacing an existing file. Edit
the local file to configure your calendars:

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

Each calendar entry supports:

- `name`: label used internally for the calendar source
- `url`: public, read-only ICS feed URL
- `color`: optional color for the event marker
- `excludeDeclined`: optional; defaults to `true`, hiding invitations you
  declined. Set it to `false` to show them.

The file uses JSONC: comments and trailing commas are allowed. It is watched
for changes and reloaded automatically.

### Feed cache

Intemporel keeps the last successful response for each feed in
`$XDG_CACHE_HOME/intemporel-calendar-cache.json` (or
`~/.cache/intemporel-calendar-cache.json`). Cached events appear immediately
when the calendar opens; feeds then refresh in the background. The cache is
local and may contain the same private calendar data as the configured ICS URLs.

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

1. `calendar.json` is valid JSONC.
2. Each feed URL is reachable without authentication.
3. `curl -fsSL "https://example.com/calendar.ics"` can fetch the feed.
4. The feed contains valid `VEVENT` entries.

## Updating

Update installed plugins with:

```bash
omarchy plugin update intemporel
```

## Removal

First remove the `intemporel` entry from `~/.config/omarchy/shell.json` and
restore the clock widget you want to use. Then remove the plugin:

```bash
omarchy plugin remove intemporel
```

The command disables and unloads the plugin before removing it. It preserves
your calendar configuration and cache. To discard those local files too, run:

```bash
rm -rf ~/.config/intemporel
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/intemporel-calendar-cache.json"
```

## Development

The plugin consists of:

- `BarWidget.qml`: clock label and calendar host, following the Omarchy clock structure
- `Model.js`: clock label formatting helpers
- `Calendar.qml`: calendar UI, keyboard handling, and shell integration
- `CalendarModel.js`: ICS parsing, recurrence expansion, and formatting
- `calendar.json.example`: starter calendar configuration
- `~/.config/intemporel/calendar.json`: local calendar configuration, outside
  the updatable plugin directory
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
