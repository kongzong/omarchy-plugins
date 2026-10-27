# hourly-chime — Omarchy 4 整点报时 + 闹钟提醒插件

每个整点播放一声卡西欧电子表风格的"哔"并弹出通知;还能设定每日闹钟,
到点双哔 + 带提醒内容的通知。免打扰时段可在面板里调整。

![id](https://img.shields.io/badge/id-com.github.kongzong.hourly--chime-blue)

## 功能

- 栏上铃铛图标(开 = 实心铃,关 = 斜杠铃),点击弹出面板
- **整点报时**:`paplay` 播放一声 2000Hz 方波哔(0.08s)+ `notify-send`「现在 HH:00」,面板内可开关
- **每日闹钟**(面板内设置):
  - 「＋ 添加」新增,时/分步进调整(5 分钟一档),最多 5 个
  - 每个闹钟可填**提醒内容**,到点通知显示「闹钟 HH:MM + 内容」
  - 到点播放**双哔**(0.28s,与单哔报时一听即辨)
  - **免打扰时段不拦闹钟**——闹钟必响,免打扰只管整点报时
  - 状态随闹钟列表一起持久化
- **免打扰时段可调**:面板内 −/+ 步进(15 分钟一档),默认 23:00–07:00,支持跨午夜区间
- 笔记本休眠错过整点/闹钟:醒来后静默重新对齐,不补响

## 安装(Omarchy 4.x)

```bash
git clone https://github.com/kongzong/omarchy-plugins.git
cp -r omarchy-plugins/hourly-chime ~/.config/omarchy/plugins/
omarchy-shell shell rescanPlugins
omarchy plugin enable com.github.kongzong.hourly-chime
```

启用后栏上即出现铃铛;若没出现,重启一次 `omarchy-shell`。

## 卸载

```bash
omarchy plugin disable com.github.kongzong.hourly-chime
rm -rf ~/.config/omarchy/plugins/hourly-chime
rm -f ~/.local/state/hourly-chime.json
```

## 重新合成提示音

提示音已随仓库附带,想调味道:

```bash
# 报时单哔:频率 / 时长 / 音量
FREQ=2000 DUR=0.08 VOL=0.25 ./tools/make-chime.sh <插件目录>/chime.wav
# 闹钟双哔(BEEPS=2,GAP 控制哔间静音)
BEEPS=2 FREQ=2000 DUR=0.08 ./tools/make-chime.sh <插件目录>/alarm.wav
# 例如:更清脆的 4096Hz 短哔
FREQ=4096 DUR=0.08 ./tools/make-chime.sh ~/.config/omarchy/plugins/hourly-chime/chime.wav
```

## 依赖

仅 Omarchy 4.x 自带组件:`quickshell`(omarchy-shell)、`paplay`(pipewire)、`notify-send`。
无额外依赖、无网络请求、数据全部本地。

## 文件

```
hourly-chime/
├── manifest.json          # 插件描述符
├── Chime.qml              # 栏图标 + 开关面板(报时/免打扰/闹钟)
├── chime.wav              # 2000Hz 方波单哔(报时)
├── alarm.wav              # 2000Hz 方波双哔(闹钟)
└── tools/make-chime.sh    # ffmpeg 合成提示音(可复现,参数可调)
```

## 许可

MIT
