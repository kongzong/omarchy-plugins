# omarchy-plugins

A collection of Omarchy 4 plugins by kongzong. Every plugin is self-contained
(descriptor + QML + assets + its own README) — install only the ones you want.

## Plugins

| Plugin | Description | Install |
|--------|-------------|---------|
| [hourly-chime](./hourly-chime/) | Casio-style beep + notification at the top of every hour, configurable quiet hours | `cp -r hourly-chime ~/.config/omarchy/plugins/` |

## Generic install (Omarchy 4.x)

```bash
git clone https://github.com/kongzong/omarchy-plugins.git
cd omarchy-plugins
cp -r <plugin-dir> ~/.config/omarchy/plugins/
omarchy-shell shell rescanPlugins
omarchy plugin enable com.github.kongzong.<plugin-name>
```

The plugin icon appears on the bar once enabled; if not, restart `omarchy-shell`.

## Uninstall

```bash
omarchy plugin disable com.github.kongzong.<plugin-name>
rm -rf ~/.config/omarchy/plugins/<plugin-dir>
```

## Notes

- Plugin ids use the `com.github.kongzong.*` prefix (`omarchy.*` is reserved by the shell)
- All plugins are zero-dependency, make no network requests, and keep data local —
  they rely only on components Omarchy 4.x ships
- See each plugin's README for details and uninstall steps

## License

MIT
