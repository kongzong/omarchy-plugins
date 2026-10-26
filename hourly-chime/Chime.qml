import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// 整点报时:栏上铃铛 + 弹出面板(开关 + 免打扰时段)。
// 结构照抄官方 agents 插件:Panel 管生命周期与 IPC,BarIconButton 是栏按钮,
// KeyboardPanel 是锚定按钮的弹出面板。
Panel {
  id: root
  moduleName: "com.github.kongzong.hourly-chime"
  ipcTarget: "com.github.kongzong.hourly-chime"

  // 栏按根元素的 implicit size 分配槽位,必须绑定到栏按钮
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)

  // ------------------------------------------------------------- state
  // chimeOn 而非 enabled:Item 自带 enabled 属性,不能遮蔽。
  property bool chimeOn: false
  property int dndStartMin: 23 * 60
  property int dndEndMin: 7 * 60

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/hourly-chime.json"

  function fmtTime(min) {
    var h = Math.floor(min / 60) % 24
    var m = min % 60
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
  }

  function parseTime(str, fallbackMin) {
    var m = String(str || "").match(/^(\d{1,2}):(\d{2})$/)
    if (!m) return fallbackMin
    var v = Number(m[1]) * 60 + Number(m[2])
    return (v >= 0 && v < 1440) ? v : fallbackMin
  }

  // 免打扰判断,支持跨午夜区间(如 23:00–07:00)
  function inDnd(minOfDay) {
    if (dndStartMin === dndEndMin) return false
    if (dndStartMin < dndEndMin) return minOfDay >= dndStartMin && minOfDay < dndEndMin
    return minOfDay >= dndStartMin || minOfDay < dndEndMin
  }

  function loadState(text) {
    var data = {}
    try { data = JSON.parse(text) } catch (e) { data = {} }
    chimeOn = data.enabled === true
    dndStartMin = parseTime(data.dndStart, 23 * 60)
    dndEndMin = parseTime(data.dndEnd, 7 * 60)
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      enabled: root.chimeOn,
      dndStart: fmtTime(root.dndStartMin),
      dndEnd: fmtTime(root.dndEndMin)
    }, null, 2) + "\n")
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("{}")
    onFileChanged: reload()
  }

  // ------------------------------------------------------- fire at :00
  readonly property string chimePath: Qt.resolvedUrl("chime.wav").toString().replace(/^file:\/\//, "")

  function fire() {
    if (!root.chimeOn) return
    var now = new Date()
    if (root.inDnd(now.getHours() * 60 + now.getMinutes())) return
    Quickshell.execDetached(["paplay", root.chimePath])
    Quickshell.execDetached(["notify-send", "-a", "hourly-chime", "整点报时", "现在 " + fmtTime(now.getHours() * 60)])
  }

  function msToNextHour() {
    var now = new Date()
    var next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0, 0, 0)
    return Math.max(1000, next.getTime() - now.getTime())
  }

  // 每次醒来都对齐下一个整点;若因休眠错过整点(minutes != 0)则静默重新对齐
  Timer {
    id: hourTimer
    repeat: true
    running: true
    triggeredOnStart: false
    interval: 60000
    onTriggered: {
      var now = new Date()
      if (now.getMinutes() === 0) root.fire()
      hourTimer.interval = root.msToNextHour()
    }
  }

  Component.onCompleted: hourTimer.interval = root.msToNextHour()

  // 面板打开时每 30 秒刷新一次"下次报时"预览
  // 注意:必须放根层级——KeyboardPanel 的默认属性 contentItem 只收 Item,
  // Timer 直接写在它下面会让整个组件加载失败(实测踩坑)。
  property double previewStamp: Date.now()
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.previewStamp = Date.now()
  }

  // 面板里的 −/+ 步进小按钮
  component StepButton: Text {
    property string glyph: "-"
    signal stepped()
    text: glyph
    color: mouse.containsMouse ? Commons.Color.accent : root.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold

    MouseArea {
      id: mouse
      anchors.fill: parent
      anchors.margins: -Style.space(6)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.stepped()
    }
  }

  // ------------------------------------------------------ bar button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // 开=闹钟+高亮色,关=被划掉的闹钟(md-alarm_off,码位从本机字体 cmap 实证)
    text: root.chimeOn ? "\uDB80\uDC20" : "\uDB80\uDC23"
    active: root.chimeOn
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  // ------------------------------------------------------ popup panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(300))

    readonly property string nextChime: {
      var next = new Date(root.previewStamp)
      next.setHours(next.getHours() + 1, 0, 0, 0)
      var now = new Date(root.previewStamp)
      var suffix = root.inDnd(now.getHours() * 60 + now.getMinutes()) ? "(免打扰中,将跳过)" : ""
      return "下次报时 " + root.fmtTime(next.getHours() * 60) + " " + suffix
    }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(14)

      // ---- 标题 + 开关 ----
      Item {
        width: parent.width
        height: Math.max(titleText.implicitHeight, switchControl.trackHeight)

        Text {
          id: titleText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "整点报时"
          color: root.foreground
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }

        ToggleSwitch {
          id: switchControl
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.chimeOn
          foreground: root.foreground
          onToggled: {
            root.chimeOn = !root.chimeOn  // ToggleSwitch 不自翻 checked,caller 负责
            root.saveState()
          }
        }
      }

      // 分隔线
      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
      }

      // ---- 免打扰 ----
      Text {
        text: "免打扰时段"
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: [
          { "label": "开始", "key": "start" },
          { "label": "结束", "key": "end" }
        ]

        delegate: Item {
          id: dndRow
          required property var modelData
          width: parent.width
          height: Style.space(28)

          readonly property int value: modelData.key === "start" ? root.dndStartMin : root.dndEndMin

          function shift(delta) {
            var v = ((value + delta) % 1440 + 1440) % 1440
            if (modelData.key === "start") root.dndStartMin = v
            else root.dndEndMin = v
            root.saveState()
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: dndRow.modelData.label
            color: root.foreground
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            StepButton {
              glyph: "-"
              anchors.verticalCenter: parent.verticalCenter
              onStepped: dndRow.shift(-15)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.fmtTime(dndRow.value)
              color: root.foreground
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
            StepButton {
              glyph: "+"
              anchors.verticalCenter: parent.verticalCenter
              onStepped: dndRow.shift(15)
            }
          }
        }
      }

      // ---- 预览 ----
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: panel.nextChime
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
