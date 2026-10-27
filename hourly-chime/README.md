# hourly-chime — hourly chime & one-shot reminders for Omarchy 4

A single "beep" at the top of every hour (Casio watch style) plus a notification;
also set one-shot reminders that double-beep with a custom label when due.
A do-not-disturb window is configurable from the panel.

![id](https://img.shields.io/badge/id-com.github.kongzong.hourly--chime-blue)

## Features

- Bell icon on the bar (on = solid bell, off = slashed bell), click to open the panel
- **Hourly chime**: one 2000 Hz square-wave beep (0.08 s) via `paplay` + `notify-send`
  "It's HH:00"; toggleable in the panel
- **Reminders (one-shot)** (configured in the panel):
  - "＋ Add" to create, up to 5
  - Time is **directly editable** (click the time box: `7:30` / `0730` / `730`,
    invalid input reverts), or nudge with ± (5 min steps)
  - Each reminder can carry a **label**, shown in the notification
  - Fires a **double beep** (0.28 s) — clearly distinct from the hourly single beep
  - **Auto-disabled after firing**; the row stays as a template — flip the switch
    to arm it again
  - The DND window **never blocks reminders** — it only silences the hourly chime
- **Do-not-disturb window**: −/+ steppers (15 min steps), default 23:00–07:00,
  supports ranges across midnight
- If the laptop sleeps through a chime/reminder, it realigns silently on wake —
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

## Re-synthesizing the sounds

Sounds ship with the repo; to tweak them:

```bash
# Hourly beep: frequency / duration / volume
FREQ=2000 DUR=0.08 VOL=0.25 ./tools/make-chime.sh <plugin-dir>/chime.wav
# Reminder double beep (BEEPS=2, GAP controls the silence between beeps)
BEEPS=2 FREQ=2000 DUR=0.08 ./tools/make-chime.sh <plugin-dir>/alarm.wav
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
├── Chime.qml              # bar icon + panel (chime / DND / reminders)
├── chime.wav              # 2000 Hz square-wave single beep (hourly)
├── alarm.wav              # 2000 Hz square-wave double beep (reminder)
└── tools/make-chime.sh    # ffmpeg sound synthesizer (reproducible, tunable)
```

## License

MIT
