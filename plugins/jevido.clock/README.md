# Clock & Calendars

Date/time for the [Omarchy](https://omarchy.org) bar, with a calendar popup that
shows work and personal events side by side.

- Month grid with **ISO week numbers**, week starting Monday
- Events from `~/.config/omarchy/calendars.json` (populated by
  `omarchy-calendar-sync`), with a reminder field per day
- Configurable label formats, cycled from the settings panel
- A vertical stacked layout for left/right bars

Left click opens the calendar, right click opens settings, middle click opens
the timezone picker.

```bash
omarchy plugin add https://github.com/jevido/omarchy-clock --enable
```

Derived from the first-party `omarchy.clock` plugin via `omarchy plugin clone`;
see NOTICE in the [monorepo](https://github.com/jevido/omarchy-jevido). MIT.
