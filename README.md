# Intemporel — An Omarchy 4 QuickShell Calendar Plugin

Intemporel is a lightweight, read-only calendar panel for [Omarchy](https://omarchy.org/).
It displays events from public iCalendar (ICS) feeds in the same visual style as
the Omarchy shell's other panels.

## Features

- Monthly calendar view with today and the selected day highlighted
- Read-only event display from one or more public ICS URLs
- Calendar-specific names and colors
- Recurring daily, weekly, and monthly events
- 24-hour event times
- Keyboard navigation
- Automatic refresh while the panel is open
- Uses the shared Omarchy shell styling and font
- No calendar accounts, credentials, or write access required

## Requirements

- Omarchy 4
- A running Omarchy shell
- `curl`
- Public ICS feeds that can be fetched without authentication

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

After installing, add the panel to your preferred clock action or keybinding.
The panel can be opened through the Omarchy shell IPC interface:

```bash
omarchy-shell shell toggle intemporel
```

## Configuration

Edit `calendar.json` inside the plugin directory:

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

The file is watched for changes and is reloaded automatically.

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
| `h` `j` `k` `l` | Move the selected day |
| `Ctrl` + arrow keys | Change month while preserving the day when possible |
| `Ctrl` + `h` `j` `k` `l` | Change month |
| `Enter` | Go to today |
| `Home` | Go to today |
| `r` | Refresh calendar feeds |
| `Esc` | Close the panel |

## Event support

Intemporel reads standard ICS fields including:

- `SUMMARY`
- `DTSTART`
- `DTEND`
- `LOCATION` (parsed for compatibility but not displayed)
- `RRULE` for daily, weekly, and monthly recurrence

All-day events display without a time. Timed events display only their start
time in 24-hour format.

## Troubleshooting

### No calendars appear

Check that:

1. `calendar.json` is valid JSON.
2. Each feed URL is reachable without authentication.
3. `curl -fsSL "https://example.com/calendar.ics"` can fetch the feed.
4. The feed contains valid `VEVENT` entries.

After changing plugin code, rescan the plugins and restart the shell:

```bash
omarchy plugin rescan
omarchy restart shell
```

### A feed stops updating

Use `r` while the panel is open to refresh immediately. Intemporel also
refreshes feeds periodically while open. Verify that the provider has not
revoked or changed the public feed URL.

## Updating

Update installed plugins with:

```bash
omarchy plugin update intemporel
```

Review changes before accepting an update, especially if you keep personal
feed URLs in the plugin directory.

## Development

The plugin consists of:

- `Calendar.qml`: panel UI, keyboard handling, and shell integration
- `CalendarModel.js`: ICS parsing, recurrence expansion, and formatting
- `calendar.json`: local calendar configuration
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
