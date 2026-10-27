import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// 整点报时 + 闹钟提醒:栏上铃铛 + 弹出面板(报时开关 + 免打扰时段 + 闹钟列表)。
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

  // 闹钟列表:[{min: 当日分钟数, label: 提醒内容, on: bool}],每天重复触发
  property var alarms: []
  readonly property int maxAlarms: 5
  readonly property bool anyAlarmOn: root.alarms.some(function(a) { return a.on })

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

  // 免打扰判断,支持跨午夜区间(如 23:00–07:00);只拦报时,不拦闹钟
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
    var list = Array.isArray(data.alarms) ? data.alarms : []
    root.alarms = list.map(function(a) {
      return { min: parseTime(a.time, 8 * 60), label: String(a.label || ""), on: a.on === true }
    })
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      enabled: root.chimeOn,
      dndStart: fmtTime(root.dndStartMin),
      dndEnd: fmtTime(root.dndEndMin),
      alarms: root.alarms.map(function(a) {
        return { time: fmtTime(a.min), label: a.label, on: a.on }
      })
    }, null, 2) + "\n")
  }

  // ------------------------------------------------- alarm list helpers
  // 每次改动都整体重建数组(QML 数组属性需重新赋值才会触发绑定刷新)
  function addAlarm() {
    if (root.alarms.length >= root.maxAlarms) return
    var now = new Date()
    var min = Math.ceil((now.getHours() * 60 + now.getMinutes() + 1) / 5) * 5
    var copy = root.alarms.slice()
    copy.push({ min: min % 1440, label: "", on: true })
    root.alarms = copy
    root.saveState()
  }

  function removeAlarm(index) {
    var copy = root.alarms.slice()
    copy.splice(index, 1)
    root.alarms = copy
    root.saveState()
  }

  function toggleAlarm(index) {
    var copy = root.alarms.slice()
    copy[index].on = !copy[index].on
    root.alarms = copy
    root.saveState()
  }

  function shiftAlarm(index, delta) {
    var copy = root.alarms.slice()
    var a = copy[index]
    a.min = ((a.min + delta) % 1440 + 1440) % 1440
    root.alarms = copy
    root.saveState()
  }

  function setAlarmLabel(index, text) {
    var copy = root.alarms.slice()
    copy[index].label = String(text || "").trim()
    root.alarms = copy
    root.saveState()
  }

  // 宽松解析:"7:30"/"07:30"/"730"/"0730" → 当日分钟;非法返回 -1
  function parseAlarmInput(str) {
    var s = String(str || "").trim()
    var m = s.match(/^(\d{1,2}):(\d{1,2})$/)
    var h, mi
    if (m) {
      h = Number(m[1]); mi = Number(m[2])
    } else {
      var d = s.replace(/\D/g, "")
      if (d.length === 4) { h = Number(d.slice(0, 2)); mi = Number(d.slice(2)) }
      else if (d.length === 3) { h = Number(d.slice(0, 1)); mi = Number(d.slice(1)) }
      else return -1
    }
    if (!(h >= 0 && h <= 23 && mi >= 0 && mi <= 59)) return -1
    return h * 60 + mi
  }

  // 直接输入时间;非法返回 false,由调用方把输入框重置回当前值
  function setAlarmTime(index, str) {
    var v = parseAlarmInput(str)
    if (v < 0) return false
    var copy = root.alarms.slice()
    copy[index].min = v
    root.alarms = copy
    root.saveState()
    return true
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

  // ------------------------------------------------------- fire
  readonly property string chimePath: Qt.resolvedUrl("chime.wav").toString().replace(/^file:\/\//, "")
  readonly property string alarmPath: Qt.resolvedUrl("alarm.wav").toString().replace(/^file:\/\//, "")

  function fireChime(minOfDay) {
    if (!root.chimeOn) return
    if (root.inDnd(minOfDay)) return
    Quickshell.execDetached(["paplay", root.chimePath])
    Quickshell.execDetached(["notify-send", "-a", "hourly-chime", "整点报时", "现在 " + fmtTime(minOfDay)])
  }

  // 闹钟:双哔,免打扰不拦截,通知带提醒内容(触发由 tick 循环调用)
  function fireAlarm(a, minOfDay) {
    Quickshell.execDetached(["paplay", root.alarmPath])
    var msg = (a.label && a.label.length > 0) ? a.label : "现在 " + fmtTime(minOfDay)
    Quickshell.execDetached(["notify-send", "-a", "hourly-chime", "闹钟 " + fmtTime(minOfDay), msg + "\n(单次提醒,已自动关闭;要再响点开面板重开)"])
  }

  // 单次语义:响过的闹钟自动关掉开关(行保留,当模板复用)
  function autoDisableAlarms(indexes) {
    if (indexes.length === 0) return
    var copy = root.alarms.slice()
    for (var k = 0; k < indexes.length; k++) copy[indexes[k]].on = false
    root.alarms = copy
    root.saveState()
  }

  // ------------------------------------------------- minute tick
  function msToNextMinute() {
    var now = new Date()
    var next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours(), now.getMinutes() + 1, 0, 0)
    return Math.max(1000, next.getTime() - now.getTime())
  }

  // 每分钟醒来:整点走报时,任意分钟匹配启用的闹钟;
  // 若因休眠错过(醒来时分钟已过),静默重新对齐,不补响
  Timer {
    id: tickTimer
    repeat: true
    running: true
    triggeredOnStart: false
    interval: 60000
    onTriggered: {
      var now = new Date()
      var minOfDay = now.getHours() * 60 + now.getMinutes()
      if (now.getMinutes() === 0) root.fireChime(minOfDay)
      var fired = []
      for (var i = 0; i < root.alarms.length; i++) {
        var a = root.alarms[i]
        if (a.on && a.min === minOfDay) { root.fireAlarm(a, minOfDay); fired.push(i) }
      }
      // 单次提醒:全部触发完再统一自动关闭(避免边遍历边改数组)
      root.autoDisableAlarms(fired)
      tickTimer.interval = root.msToNextMinute()
    }
  }

  Component.onCompleted: tickTimer.interval = root.msToNextMinute()

  // 面板打开时每 30 秒刷新一次"下次触发"预览
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
    text: (root.chimeOn || root.anyAlarmOn) ? "\uDB80\uDC20" : "\uDB80\uDC23"
    active: root.chimeOn || root.anyAlarmOn
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    readonly property string previewText: {
      var now = new Date(root.previewStamp)
      var nowMin = now.getHours() * 60 + now.getMinutes()
      var parts = []
      // 下次报时
      parts.push("下次报时 " + root.fmtTime((nowMin - nowMin % 60) + 60))
      if (root.inDnd(nowMin)) parts[parts.length - 1] += "(免打扰中,将跳过)"
      // 下次闹钟(启用中的最早一个;过了今天时刻的算明天,不显示具体日期)
      var best = -1
      for (var i = 0; i < root.alarms.length; i++) {
        var a = root.alarms[i]
        if (!a.on) continue
        if (best < 0 || a.min < root.alarms[best].min) best = i
      }
      if (best >= 0) {
        var a2 = root.alarms[best]
        parts.push("下次提醒 " + root.fmtTime(a2.min) + (a2.label.length > 0 ? " " + a2.label : ""))
      }
      return parts.join(" · ")
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

      // ---- 免打扰(单行紧凑:起 – 止) ----
      Text {
        text: "免打扰时段(不拦闹钟)"
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      function shiftDndStart(delta) {
        root.dndStartMin = ((root.dndStartMin + delta) % 1440 + 1440) % 1440
        root.saveState()
      }

      function shiftDndEnd(delta) {
        root.dndEndMin = ((root.dndEndMin + delta) % 1440 + 1440) % 1440
        root.saveState()
      }

      Item {
        width: parent.width
        height: Style.space(28)

        // 左组:开始 [- 23:00 +]
        StepButton {
          id: dndMinusStart
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          glyph: "-"
          onStepped: root.shiftDndStart(-15)
        }
        Text {
          id: dndTimeStart
          anchors.left: dndMinusStart.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.fmtTime(root.dndStartMin)
          color: root.foreground
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
        StepButton {
          id: dndPlusStart
          anchors.left: dndTimeStart.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          glyph: "+"
          onStepped: root.shiftDndStart(15)
        }

        // 中间分隔
        Text {
          id: dndDash
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          text: "–"
          color: root.dim
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        // 右组:结束 [- 07:00 +],贴右对齐
        StepButton {
          id: dndMinusEnd
          anchors.right: dndTimeEnd.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          glyph: "-"
          onStepped: root.shiftDndEnd(-15)
        }
        Text {
          id: dndTimeEnd
          anchors.right: dndPlusEnd.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.fmtTime(root.dndEndMin)
          color: root.foreground
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
        StepButton {
          id: dndPlusEnd
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          glyph: "+"
          onStepped: root.shiftDndEnd(15)
        }
      }

      // 分隔线
      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
      }

      // ---- 定时提醒(单次,响后自动关闭) ----
      Item {
        width: parent.width
        height: alarmTitle.implicitHeight

        Text {
          id: alarmTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "定时提醒(单次)"
          color: root.dim
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.alarms.length >= root.maxAlarms ? "已达上限" : "＋ 添加"
          color: mouseAdd.containsMouse ? Commons.Color.accent : (root.alarms.length >= root.maxAlarms ? root.dim : root.foreground)
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold

          MouseArea {
            id: mouseAdd
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: root.alarms.length < root.maxAlarms
            onClicked: root.addAlarm()
          }
        }
      }

      Repeater {
        model: root.alarms

        delegate: Item {
          id: alarmRow
          required property var modelData
          required property int index
          width: parent.width
          height: Style.space(28)

          // 全锚点布局:左右两端定死,中间输入框自动填满,不依赖估算宽度
          StepButton {
            id: minusBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "-"
            onStepped: root.shiftAlarm(alarmRow.index, -5)
          }

          // 时间:可直接输入(7:30 / 0730 / 730),回车或失焦生效;非法自动还原
          Item {
            id: timeBox
            anchors.left: minusBtn.right
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(52)
            height: parent.height

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: timeInput.activeFocus
                     ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                     : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            }

            TextInput {
              id: timeInput
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              clip: true
              text: root.fmtTime(alarmRow.modelData.min)
              onEditingFinished: {
                if (!root.setAlarmTime(alarmRow.index, text))
                  timeInput.text = root.fmtTime(alarmRow.modelData.min)  // 非法输入还原
              }
            }
          }

          StepButton {
            id: plusBtn
            anchors.left: timeBox.right
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            glyph: "+"
            onStepped: root.shiftAlarm(alarmRow.index, 5)
          }

          StepButton {
            id: deleteBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "×"
            onStepped: root.removeAlarm(alarmRow.index)
          }

          ToggleSwitch {
            id: alarmToggle
            anchors.right: deleteBtn.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            checked: alarmRow.modelData.on
            foreground: root.foreground
            onToggled: root.toggleAlarm(alarmRow.index)
          }

          // 提醒内容:点击输入,失焦/回车保存
          Item {
            id: labelBox
            anchors.left: plusBtn.right
            anchors.leftMargin: Style.space(6)
            anchors.right: alarmToggle.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: labelInput.activeFocus
                     ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                     : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              visible: labelInput.text === "" && !labelInput.activeFocus
              text: "提醒内容…"
              color: root.dim
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            TextInput {
              id: labelInput
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              clip: true
              text: alarmRow.modelData.label
              onEditingFinished: root.setAlarmLabel(alarmRow.index, text)
            }
          }
        }
      }

      Text {
        visible: root.alarms.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "点右上「＋ 添加」设一个,到点双哔+通知,响完自动关"
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      // ---- 预览 ----
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: panel.previewText
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
