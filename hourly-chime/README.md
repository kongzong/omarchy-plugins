# hourly-chime — hourly chime for Omarchy 4

A single "beep" at the top of every hour (Casio watch style) plus a notification.
A do-not-disturb window is configurable from the panel.

![id](https://img.shields.io/badge/id-com.github.kongzong.hourly--chime-blue)

## Features

- Bell icon on the bar (solid = chime on, slashed = chime off), click to open the panel
- **Hourly chime**: one 2000 Hz square-wave beep (0.08 s) via `paplay` + a
  `notify-send` "It's HH:00"; toggleable in the panel
- **Do-not-disturb window**: −/+ steppers (15 min steps), default 23:00–07:00,
  supports ranges across midnight; the chime stays silent inside it
- If the laptop sleeps through the chime, it realigns silently on wake —
  no catch-up firing

## Install (Omarchy 4.x)

```bash
git clone https://github.com/kongzong/omarchy-plugins.git
cp -r omarchy-plugins/hourly-chime ~/.config/omarchy/plugins/
omarchy-shell shell rescanPlugins
omarchy plugin enable com.github.kongzong.hourly-chime
```

The bell appears on the bar once enabled; if not, restart `omarchy-shell`.

## Uninstall

```bash
omarchy plugin disable com.github.kongzong.hourly-chime
rm -rf ~/.config/omarchy/plugins/hourly-chime
rm -f ~/.local/state/hourly-chime.json
```

## Re-synthesizing the sound

The sound ships with the repo; to tweak it:

```bash
# Hourly beep: frequency / duration / volume
FREQ=2000 DUR=0.08 VOL=0.25 ./tools/make-chime.sh <plugin-dir>/chime.wav
# e.g. a crisper 4096 Hz blip
FREQ=4096 DUR=0.08 ./tools/make-chime.sh ~/.config/omarchy/plugins/hourly-chime/chime.wav
```

## Dependencies

Only components Omarchy 4.x ships: `quickshell` (omarchy-shell), `paplay`
(pipewire), `notify-send`. No extra dependencies, no network, all data local.

## Files

```
hourly-chime/
├── manifest.json          # plugin descriptor
├── Chime.qml              # bar icon + panel (chime / DND)
├── chime.wav              # 2000 Hz square-wave single beep
└── tools/make-chime.sh    # ffmpeg sound synthesizer (reproducible, tunable)
```

## History

1.x also shipped a one-shot reminder list (alarm rows with labels). It was
removed in 2.0.0 — the bar icon had to encode three states to reflect both
features, which made a single toggle hard to read. One-shot reminders are
covered by Omarchy's built-in reminders overlay (`omarchy.reminders`). Existing
state files keep working; the stale `alarms` key is dropped on the next save.
