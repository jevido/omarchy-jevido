# omarchy-jevido

My [Omarchy](https://omarchy.org) shell plugins. Omarchy 4 replaced Waybar with
a single long-running [Quickshell](https://quickshell.org) process, and
everything on the bar is a plugin — so this is where mine live.

| Plugin | What it is |
|---|---|
| [`jevido.wiki`](plugins/jevido.wiki) | A daily digest of what your colleagues wrote on an [Outline](https://www.getoutline.com) wiki. Fullscreen each morning, a silent badge the rest of the day. |
| [`jevido.clock`](plugins/jevido.clock) | Clock with a calendar popup showing work and personal events, ISO week numbers, configurable formats. |
| [`jevido.media`](plugins/jevido.media) | MPRIS now-playing with a cover-art popup. |

## Installing

`omarchy plugin add` clones a repo and expects `manifest.json` at its root, so
it cannot install from a monorepo. Each plugin is therefore also published as a
thin repo (see [Makefile](Makefile)), and those are what you install:

```bash
omarchy plugin add https://github.com/jevido/omarchy-wiki-pulse --enable
omarchy plugin add https://github.com/jevido/omarchy-clock --enable
omarchy plugin add https://github.com/jevido/omarchy-media --enable
```

`jevido.wiki` has a pipeline behind it (systemd timers and a summariser), so it
needs one more step after installing:

```bash
~/.config/omarchy/plugins/jevido.wiki/bin/setup
```

> Plugins run as unsandboxed code inside your long-lived `omarchy-shell`
> process. Read them before you enable them — including these.

## Hacking

```bash
git clone https://github.com/jevido/omarchy-jevido && cd omarchy-jevido
make link              # symlinks every plugin into ~/.config/omarchy/plugins
omarchy-restart-shell
```

The plugin registry follows symlinks (`omarchy-plugin-catalog` walks with
`find -L`), so a linked working tree loads exactly like an installed one.

**Editing a file is not enough to see the change.** Omarchy's docs say saving
under `~/.config/omarchy/plugins/` hot-reloads plugin code, and the registry
does notice — but an already-instantiated `keepLoaded` overlay keeps its old
code, symlinked or not. `omarchy-shell shell rescanPlugins` does not help
either. Run `omarchy-restart-shell` after every edit.

Publishing, once the thin repos exist:

```bash
make check     # validates each plugin, refuses to publish internal references
make publish   # git subtree split → force-push each to its own repo
```

## Licence

MIT. `jevido.clock` and `jevido.media` began as `omarchy plugin clone` of
first-party plugins and still carry Omarchy code — see [NOTICE](NOTICE).
