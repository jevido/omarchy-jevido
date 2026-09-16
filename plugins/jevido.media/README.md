# Media

MPRIS now-playing for the [Omarchy](https://omarchy.org) bar: a scrolling
track and artist label, with a cover-art popup.

Left click toggles play/pause, middle click skips, scroll moves through the
queue, right click opens the popup. Hides itself when nothing is playing.

```bash
omarchy plugin add https://github.com/jevido/omarchy-media --enable
```

Derived from the first-party `omarchy.media` plugin via `omarchy plugin clone`;
see NOTICE in the [monorepo](https://github.com/jevido/omarchy-jevido). MIT.
