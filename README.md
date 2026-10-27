# omarchy-plugins

kongzong 的 Omarchy 4 插件集合。每个插件自包含(描述符 + QML + 资源 + 独立 README),按需安装即可。

## 插件列表

| 插件 | 说明 | 安装命令 |
|------|------|----------|
| [hourly-chime](./hourly-chime/) | 整点报时 + 每日闹钟提醒(双哔+提醒内容),免打扰时段可调 | `cp -r hourly-chime ~/.config/omarchy/plugins/` |

## 通用安装方式(Omarchy 4.x)

```bash
git clone https://github.com/kongzong/omarchy-plugins.git
cd omarchy-plugins
cp -r <插件目录> ~/.config/omarchy/plugins/
omarchy-shell shell rescanPlugins
omarchy plugin enable com.github.kongzong.<插件名>
```

启用后栏上即出现对应图标;若没出现,重启一次 `omarchy-shell`。

## 卸载

```bash
omarchy plugin disable com.github.kongzong.<插件名>
rm -rf ~/.config/omarchy/plugins/<插件目录>
```

## 说明

- 插件 id 统一使用 `com.github.kongzong.*` 前缀(`omarchy.*` 为官方保留前缀)
- 全部插件零外部依赖、无网络请求、数据全部本地,只依赖 Omarchy 4.x 自带组件
- 各插件的详细功能与卸载方法见各自目录下的 README

## 许可

MIT
