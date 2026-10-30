import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Hourly chime: bar bell icon + popup panel (chime toggle + DND window).
// Structure copied from the official agents plugin: Panel owns lifecycle/IPC,
// BarIconButton is the bar button, KeyboardPanel is the anchored popup panel.
Panel {
  id: root
  moduleName: "com.github.kongzong.hourly-chime"
  ipcTarget: "com.github.kongzong.hourly-chime"

  // The bar sizes each slot from the root's implicit size — must bind to the button
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  // Resolved once at root. qs.Commons exports the singletons `Color` / `Style`
  // / `Border` / `Util` — there is no type named `Commons`, so `Commons.Color`
  // would throw ReferenceError the moment the binding is evaluated.
  readonly property color accent: Color.accent

  // ------------------------------------------------------------- state
  // chimeOn instead of enabled: Item already has `enabled`, do not shadow it
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

  // DND check, supports ranges across midnight (e.g. 23:00–07:00).
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
    // Older versions also stored a reminder list under "alarms"; it is simply
    // dropped here, so the file is rewritten clean on the first save.
    stateFile.setText(JSON.stringify({
      enabled: root.chimeOn,
      dndStart: fmtTime(root.dndStartMin),
      dndEnd: fmtTime(root.dndEndMin)
    }, null, 2) + "\n")
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

  function fireChime(minOfDay) {
    if (!root.chimeOn) return
    if (root.inDnd(minOfDay)) return
    Quickshell.execDetached(["paplay", root.chimePath])
    Quickshell.execDetached(["notify-send", "-a", "hourly-chime", "Hourly Chime", "It's " + fmtTime(minOfDay)])
  }

  // ------------------------------------------------------- minute tick
  function msToNextMinute() {
    var now = new Date()
    var next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours(), now.getMinutes() + 1, 0, 0)
    return Math.max(1000, next.getTime() - now.getTime())
  }

  // Wake every minute and fire at :00. If a tick was missed (e.g. after
  // sleep), realign silently — no catch-up.
  Timer {
    id: tickTimer
    repeat: true
    running: true
    triggeredOnStart: false
    interval: 60000
    onTriggered: {
      var now = new Date()
      if (now.getMinutes() === 0) root.fireChime(now.getHours() * 60 + now.getMinutes())
      tickTimer.interval = root.msToNextMinute()
    }
  }

  Component.onCompleted: tickTimer.interval = root.msToNextMinute()

  // Small −/+ stepper button used in the DND row
  component StepButton: Text {
    property string glyph: "-"
    signal stepped()
    text: glyph
    color: mouse.containsMouse ? root.accent : root.foreground
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
  // Wristwatch glyph (md-watch, U+F0589) reads as "a watch", not as an alarm.
  // MDI has no "off" variant for it, so the off state is the same glyph dimmed
  // instead of a slashed bell — the shape stays stable, only the weight changes.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uDB81\uDD89"
    opacity: root.chimeOn ? 1.0 : 0.42
    tooltipText: root.chimeOn
                 ? "Hourly chime on · quiet " + root.fmtTime(root.dndStartMin) + "–" + root.fmtTime(root.dndEndMin)
                 : "Hourly chime off"
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
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    Column {
      id: column
      width: parent.width
      spacing: Style.space(14)

      // ---- Chime toggle ----
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

      // ---- DND window, visually part of the chime section ----
      Item {
        width: parent.width
        height: Style.space(28)

        // Left: label + start group [- 23:00 +]
        Text {
          id: dndLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Do not disturb"
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

        // "to" between the two groups, centered in the gap
        Text {
          anchors.left: dndPlusStart.right
          anchors.right: dndMinusEnd.left
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: "to"
          color: root.dim
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
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
    }
  }
}
