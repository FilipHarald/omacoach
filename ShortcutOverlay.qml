import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "components"
import "ShortcutModel.js" as ShortcutModel

Item {
  id: root

  property bool opened: false
  property var manifest: null
  property string targetMonitor: ""
  property string currentModifierKey: "SUPER"
  property var bindingGroups: ({})
  property var currentBindings: []
  property var visibleBindings: []
  property var modifierBranches: []
  property int hiddenBindingCount: 0
  property var keycodeMap: ({})
  property var attemptStats: ({})
  property bool statsLoaded: false
  property bool measurementEnabled: true
  readonly property int revealDelayMs: 180
  readonly property int maximumBindings: 24
  readonly property var currentModifiers: ShortcutModel.normalizeModifiers(currentModifierKey)
  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string stateDir: stateHome + "/omacoach"
  readonly property string statsPath: stateDir + "/attempts.json"

  onPluginDirChanged: {
    if (pluginDir && !keymapProcess.running) {
      keymapProcess.command = [pluginDir + "/scripts/keymap"]
      keymapProcess.running = true
    }
  }

  function updateModel(modifiers) {
    currentModifierKey = ShortcutModel.modifierKey(modifiers) || "SUPER"
    currentBindings = ShortcutModel.bindingsFor(bindingGroups, currentModifierKey)
    modifierBranches = ShortcutModel.branchCounts(bindingGroups, currentModifierKey)
    var capped = ShortcutModel.cappedBindings(currentBindings, maximumBindings)
    visibleBindings = capped.visible
    hiddenBindingCount = capped.hiddenCount
  }

  function loadBindings(output) {
    var parsed = ShortcutModel.parseBindings(String(output || ""))
    bindingGroups = ShortcutModel.groupBindings(parsed)
    updateModel(currentModifierKey)
  }

  function loadKeymap(output) {
    var map = {}
    var lines = String(output || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length === 2 && fields[0] && fields[1]) map[String(fields[0])] = String(fields[1]).toUpperCase()
    }
    keycodeMap = map
  }

  function bindingSignature(binding) {
    return String(binding.modifierKey || "") + "\u001f" + String(binding.key || "").toUpperCase()
  }

  function attemptCount(binding) {
    var entry = attemptStats[bindingSignature(binding)]
    return entry && Number(entry.count) > 0 ? Number(entry.count) : 0
  }

  function loadStats(raw) {
    if (statsLoaded) return
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    measurementEnabled = !parsed || parsed.enabled !== false
    attemptStats = parsed && parsed.version === 1 && parsed.bindings && typeof parsed.bindings === "object"
      ? parsed.bindings : ({})
    statsLoaded = true
  }

  function saveStats() {
    if (!statsLoaded) return
    statsFile.setText(JSON.stringify({
      version: 1,
      enabled: measurementEnabled,
      bindings: attemptStats
    }, null, 2) + "\n")
  }

  function scheduleStatsSave() {
    if (statsLoaded) statsSaveTimer.restart()
  }

  function setMeasurementEnabled(enabled) {
    measurementEnabled = enabled === true
    scheduleStatsSave()
  }

  function resetStats() {
    attemptStats = ({})
    scheduleStatsSave()
  }

  function recordAttempt(modifiers, keycode) {
    if (!statsLoaded || !measurementEnabled) return false
    var key = keycodeMap[String(keycode)]
    if (!key) return false

    var candidates = ShortcutModel.bindingsFor(bindingGroups, modifiers)
    var matched = null
    for (var i = 0; i < candidates.length; i++) {
      if (String(candidates[i].key || "").toUpperCase() !== key) continue
      if (matched) return false
      matched = candidates[i]
    }
    if (!matched) return false

    var signature = bindingSignature(matched)
    var next = Object.assign({}, attemptStats)
    var previous = next[signature]
    next[signature] = { count: (previous ? Number(previous.count) : 0) + 1 }
    attemptStats = next
    scheduleStatsSave()
    return true
  }

  function observedBindingCount() {
    var count = 0
    for (var signature in attemptStats) {
      if (attemptStats[signature] && Number(attemptStats[signature].count) > 0) count++
    }
    return count
  }

  function totalAttemptCount() {
    var count = 0
    for (var signature in attemptStats) {
      if (attemptStats[signature]) count += Number(attemptStats[signature].count) || 0
    }
    return count
  }

  function armHints(modifiers, monitor) {
    targetMonitor = String(monitor || "")
    updateModel(modifiers)
    opened = false
    revealTimer.restart()
  }

  function updateHints(modifiers, monitor) {
    if (monitor) targetMonitor = String(monitor)
    updateModel(modifiers)
  }

  function hideHints() {
    revealTimer.stop()
    opened = false
  }

  function reloadBindings() {
    hideHints()
    if (!bindingProcess.running) bindingProcess.running = true
  }

  function columnCount(count) {
    if (count > 18) return 4
    if (count > 10) return 3
    if (count > 5) return 2
    return 1
  }

  Timer {
    id: revealTimer
    interval: root.revealDelayMs
    repeat: false
    onTriggered: root.opened = true
  }

  Process {
    id: bindingProcess
    command: ["omarchy-menu-keybindings", "--print"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadBindings(text)
    }
  }

  Process {
    id: keymapProcess
    command: root.pluginDir ? [root.pluginDir + "/scripts/keymap"] : []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadKeymap(text)
    }
  }

  Process {
    id: ensureStateDirProcess
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      if (exitCode === 0) statsFile.reload()
      else root.loadStats("")
    }
  }

  FileView {
    id: statsFile
    path: root.statsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadStats(text())
    onLoadFailed: root.loadStats("")
  }

  Timer {
    id: statsSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.saveStats()
  }

  IpcHandler {
    target: "omacoach"

    function arm(modifiers: string, monitor: string): string {
      root.armHints(modifiers, monitor)
      return "ok"
    }

    function update(modifiers: string, monitor: string): string {
      root.updateHints(modifiers, monitor)
      return "ok"
    }

    function hide(): string {
      root.hideHints()
      return "ok"
    }

    function attempt(modifiers: string, keycode: string): string {
      return root.recordAttempt(modifiers, Number(keycode)) ? "recorded" : "ignored"
    }

    function measurement(value: string): string {
      var normalized = String(value || "").toLowerCase()
      if (normalized === "on") root.setMeasurementEnabled(true)
      else if (normalized === "off") root.setMeasurementEnabled(false)
      return root.measurementEnabled ? "on" : "off"
    }

    function resetAttempts(): string {
      root.resetStats()
      return "ok"
    }

    function attempts(): string {
      return JSON.stringify({
        enabled: root.measurementEnabled,
        observedBindings: root.observedBindingCount(),
        totalAttempts: root.totalAttemptCount()
      })
    }

    function reload(): string {
      root.reloadBindings()
      return "ok"
    }

    function preview(modifiers: string, monitor: string): string {
      root.targetMonitor = String(monitor || "")
      root.updateModel(modifiers || "SUPER")
      revealTimer.stop()
      root.opened = true
      return "ok"
    }

    function state(): string {
      return root.opened ? root.currentModifierKey : "closed"
    }
  }

  Component.onCompleted: {
    if (!bindingProcess.running) bindingProcess.running = true
    if (root.pluginDir && !keymapProcess.running) keymapProcess.running = true
    if (!ensureStateDirProcess.running) ensureStateDirProcess.running = true
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      readonly property bool isTarget: String(modelData.name || "") === root.targetMonitor
      readonly property int columns: root.columnCount(root.visibleBindings.length)
      readonly property real desiredWidth: columns * Style.space(224)
        + Math.max(0, columns - 1) * Style.space(22)
        + Style.spacing.panelPadding * 2

      screen: modelData
      visible: isTarget && (root.opened || card.opacity > 0.01)
      anchors { top: true; right: true; bottom: true; left: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      WlrLayershell.namespace: "omacoach-shortcuts"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      BorderSurface {
        id: card

        width: Math.min(panel.width - Style.space(48), Math.max(Style.space(330), panel.desiredWidth))
        height: content.implicitHeight + Style.spacing.panelPadding * 2 + borderTop + borderBottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.opened ? Style.space(26) : Style.space(12)
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
        opacity: root.opened ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: root.opened ? 110 : 75; easing.type: Easing.OutCubic }
        }

        Behavior on anchors.bottomMargin {
          NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
          id: content
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.space(12)

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(7)

            Repeater {
              model: root.currentModifiers
              ModifierChip { required property string modelData; label: modelData }
            }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: panel.columns
            columnSpacing: Style.space(22)
            rowSpacing: Style.space(5)

            Repeater {
              model: root.visibleBindings
              BindingRow {
                required property var modelData
                binding: modelData
                attemptCount: root.attemptCount(modelData)
                Layout.fillWidth: true
              }
            }
          }

          Text {
            visible: root.currentBindings.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: "No described shortcuts for this combination"
            color: Util.alpha(Color.popups.text, 0.68)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.hiddenBindingCount > 0
            Layout.alignment: Qt.AlignHCenter
            text: "+ " + root.hiddenBindingCount + " more bindings"
            color: Util.alpha(Color.popups.text, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          RowLayout {
            visible: root.modifierBranches.length > 0
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(9)

            Text {
              text: "Hold another modifier"
              color: Util.alpha(Color.popups.text, 0.58)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.modifierBranches
              ModifierChip {
                required property var modelData
                label: String(modelData.modifier)
                count: Number(modelData.count)
                branch: true
              }
            }
          }


          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.measurementEnabled
              ? (root.totalAttemptCount() === 0
                ? "Learning attempted shortcuts locally"
                : root.observedBindingCount() + " bindings observed · " + root.totalAttemptCount() + " attempts")
              : "Shortcut measurement paused"
            color: Util.alpha(Color.popups.text, 0.48)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
