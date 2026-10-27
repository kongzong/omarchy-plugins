import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Hourly chime + one-shot reminders: bar bell icon + popup panel
// (chime toggle + DND window + reminder list).
// Structure copied from the official agents plugin: Panel owns lifecycle/IPC,
// BarIconButton is the bar button, KeyboardPanel is the anchored popup panel.
Panel {
  id: root
  moduleName: "com.github.kongzong.hourly-chime"
  ipcTarget: "com.github.kongzong.hourly-chime"

  // The bar sizes each slot from the root's implicit size — must bind to the button
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)

  // ------------------------------------------------------------- state
  // chimeOn instead of enabled: Item already has `enabled`, do not shadow it
  property bool chimeOn: false
  property int dndStartMin: 23 * 60
  property int dndEndMin: 7 * 60

  // Reminder list: [{min: minute-of-day, label: text, on: bool}]
  // One-shot semantics: fired reminders auto-disable (row kept as a template)
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

  // DND check, supports ranges across midnight (e.g. 23:00–07:00).
  // Blocks the hourly chime only — reminders always fire.
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

  // ------------------------------------------------- reminder helpers
  // Every mutation rebuilds the array (a QML array property only refreshes
  // bindings when reassigned)
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

  // Lenient time input: "7:30" / "07:30" / "730" / "0730" → minute-of-day,
  // returns -1 when invalid
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

  // Direct time entry; returns false when invalid so the caller can reset the field
  function setAlarmTime(index, str) {
    var v = parseAlarmInput(str)
    if (v < 0) return false
    var copy = root.alarms.slice()
    copy[index].min = v
    root.alarms = copy
    root.saveState()
    return true
  }

  function shiftDndStart(delta) {
    root.dndStartMin = ((root.dndStartMin + delta) % 1440 + 1440) % 1440
    root.saveState()
  }

  function shiftDndEnd(delta) {
    root.dndEndMin = ((root.dndEndMin + delta) % 1440 + 1440) % 1440
    root.saveState()
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

  // ------------------------------------------------------------- fire
  readonly property string chimePath: Qt.resolvedUrl("chime.wav").toString().replace(/^file:\/\//, "")
  readonly property string alarmPath: Qt.resolvedUrl("alarm.wav").toString().replace(/^file:\/\//, "")

  function fireChime(minOfDay) {
    if (!root.chimeOn) return
    if (root.inDnd(minOfDay)) return
    Quickshell.execDetached(["paplay", root.chimePath])
    Quickshell.execDetached(["notify-send", "-a", "hourly-chime", "Hourly Chime", "It's " + fmtTime(minOfDay)])
  }

  // Reminder: double beep, ignores DND, notification carries the label
  function fireAlarm(a, minOfDay) {
    Quickshell.execDetached(["paplay", root.alarmPath])
    var msg = (a.label && a.label.length > 0) ? a.label : "It's " + fmtTime(minOfDay)
    Quickshell.execDetached(["notify-send", "-a", "hourly-chime", "Reminder " + fmtTime(minOfDay), msg + "\n(One-shot: auto-disabled, re-enable in panel)"])
  }

  // One-shot: auto-disable fired reminders (rows kept for one-tap re-arm)
  function autoDisableAlarms(indexes) {
    if (indexes.length === 0) return
    var copy = root.alarms.slice()
    for (var k = 0; k < indexes.length; k++) copy[indexes[k]].on = false
    root.alarms = copy
    root.saveState()
  }

  // ------------------------------------------------------- minute tick
  function msToNextMinute() {
    var now = new Date()
    var next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours(), now.getMinutes() + 1, 0, 0)
    return Math.max(1000, next.getTime() - now.getTime())
  }

  // Wake every minute: :00 triggers the chime, any minute may match a reminder.
  // If a tick was missed (e.g. after sleep), realign silently — no catch-up.
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
      // Disable all fired reminders after the loop (never mutate while iterating)
      root.autoDisableAlarms(fired)
      tickTimer.interval = root.msToNextMinute()
    }
  }

  Component.onCompleted: tickTimer.interval = root.msToNextMinute()

  // Refresh the "next reminder" preview every 30s while the panel is open.
  // Must live at root level — KeyboardPanel's default property (contentItem)
  // only accepts Items; a Timer directly inside it breaks the whole component.
  property double previewStamp: Date.now()
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.previewStamp = Date.now()
  }

  // Small −/+ stepper button used in the panel rows
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

  // --------------------------------------------------------- bar button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // On = alarm glyph highlighted, off = slashed alarm (md-alarm_off,
    // codepoint verified against the local font's cmap)
    text: (root.chimeOn || root.anyAlarmOn) ? "\uDB80\uDC20" : "\uDB80\uDC23"
    active: root.chimeOn || root.anyAlarmOn
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  // -------------------------------------------------------- popup panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    // Shown only when a reminder is enabled; earliest enabled one wins
    readonly property string previewText: {
      var best = -1
      for (var i = 0; i < root.alarms.length; i++) {
        var a = root.alarms[i]
        if (!a.on) continue
        if (best < 0 || a.min < root.alarms[best].min) best = i
      }
      if (best < 0) return ""
      var a2 = root.alarms[best]
      return "Next reminder " + root.fmtTime(a2.min) + (a2.label.length > 0 ? " " + a2.label : "")
    }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(14)

      // ---- Hourly Chime section: toggle + its DND window ----
      Item {
        width: parent.width
        height: Math.max(titleText.implicitHeight, switchControl.trackHeight)

        Text {
          id: titleText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Hourly Chime"
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
            root.chimeOn = !root.chimeOn  // ToggleSwitch does not flip itself; caller owns the value
            root.saveState()
          }
        }
      }

      // DND window, visually part of the Hourly Chime section (no extra caption
      // needed — it sits right under the chime toggle)
      Item {
        width: parent.width
        height: Style.space(28)

        // Left: "DND" label + start group [- 23:00 +]
        Text {
          id: dndLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "DND (chime only)"
          color: root.dim
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        StepButton {
          id: dndMinusStart
          anchors.left: dndLabel.right
          anchors.leftMargin: Style.space(10)
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

        // Right: end group [- 07:00 +], flush right
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

      // Separator
      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
      }

      // ---- Reminders section (one-shot, auto-off after firing) ----
      Item {
        width: parent.width
        height: alarmTitle.implicitHeight

        Text {
          id: alarmTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Reminders (one-shot)"
          color: root.dim
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.alarms.length >= root.maxAlarms ? "Max reached" : "＋ Add"
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

          // All anchors: left/right groups pinned to edges, the label box
          // stretches in between — no estimated widths, cannot overflow
          StepButton {
            id: minusBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "-"
            onStepped: root.shiftAlarm(alarmRow.index, -5)
          }

          // Time: directly editable ("7:30" / "0730" / "730"), commits on
          // Enter/focus loss, invalid input reverts
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
                  timeInput.text = root.fmtTime(alarmRow.modelData.min)  // revert invalid input
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

          // Label: click to type, commits on Enter/focus loss
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
              text: "Label…"
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
        elide: Text.ElideRight
        text: "＋ Add to set one — double beep, auto-off"
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      // ---- Preview (only when a reminder is enabled) ----
      Text {
        visible: root.anyAlarmOn
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: panel.previewText
        color: root.dim
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
