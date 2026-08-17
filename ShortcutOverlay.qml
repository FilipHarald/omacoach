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
  property var appSearchStats: ({})
  property bool statsLoaded: false
  property bool measurementEnabled: true
  property bool pinned: false
  readonly property int revealDelayMs: 180
  readonly property int maximumBindings: 40
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
    currentBindings = ShortcutModel.groupForDisplay(ShortcutModel.bindingsFor(bindingGroups, currentModifierKey))
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
    if (binding.grouped === true) return 0
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
    appSearchStats = parsed && parsed.version === 1 && parsed.appSearches && typeof parsed.appSearches === "object"
      ? parsed.appSearches : ({})
    statsLoaded = true
  }

  function saveStats() {
    if (!statsLoaded) return
    statsFile.setText(JSON.stringify({
      version: 1,
      enabled: measurementEnabled,
      bindings: attemptStats,
      appSearches: appSearchStats
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
    appSearchStats = ({})
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

  function totalAppSelectionCount() {
    var count = 0
    for (var desktopId in appSearchStats) {
      if (appSearchStats[desktopId]) count += Number(appSearchStats[desktopId].count) || 0
    }
    return count
  }

  function recordSearchedApp(desktopId, name) {
    if (!statsLoaded || !measurementEnabled) return false
    var id = String(desktopId || "").trim()
    var label = String(name || "").trim()
    if (!id || !label) return false

    var next = Object.assign({}, appSearchStats)
    var previous = next[id]
    next[id] = {
      name: label,
      count: (previous ? Number(previous.count) : 0) + 1
    }
    appSearchStats = next
    scheduleStatsSave()
    return true
  }

  function searchedAppsSummary() {
    var apps = []
    for (var desktopId in appSearchStats) {
      var entry = appSearchStats[desktopId]
      if (!entry || Number(entry.count) <= 0) continue
      apps.push({ desktopId: desktopId, name: String(entry.name || desktopId), count: Number(entry.count) })
    }
    apps.sort(function(left, right) {
      if (left.count !== right.count) return right.count - left.count
      return left.name.localeCompare(right.name)
    })
    return apps
  }

  function armHints(modifiers, monitor) {
    if (pinned) return
    targetMonitor = String(monitor || "")
    updateModel(modifiers)
    opened = false
    revealTimer.restart()
  }

  function updateHints(modifiers, monitor) {
    if (pinned) return
    if (monitor) targetMonitor = String(monitor)
    updateModel(modifiers)
  }

  function hideHints() {
    revealTimer.stop()
    if (pinned) return
    opened = false
  }

  function togglePinned(monitor) {
    revealTimer.stop()
    if (pinned) {
      pinned = false
      opened = false
      return
    }
    targetMonitor = String(monitor || targetMonitor)
    updateModel("SUPER")
    pinned = true
    opened = true
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

    function searchedApp(desktopId: string, name: string): string {
      return root.recordSearchedApp(desktopId, name) ? "recorded" : "ignored"
    }

    function searchedApps(): string {
      return JSON.stringify(root.searchedAppsSummary())
    }

    function togglePinned(monitor: string): string {
      root.togglePinned(monitor)
      return root.pinned ? "open" : "closed"
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
      return root.pinned ? "pinned" : (root.opened ? root.currentModifierKey : "closed")
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
      readonly property real desiredWidth: columns * Style.space(270)
        + Math.max(0, columns - 1) * Style.space(22)
        + Style.spacing.panelPadding * 2

      screen: modelData
      visible: isTarget && (root.opened || card.opacity > 0.01)
      anchors { top: true; right: true; bottom: true; left: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {
        Region { item: root.pinned ? footerSections : null }
        Region { item: root.pinned ? topCloseControl : null }
      }

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
            visible: !root.pinned
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(8)

            Repeater {
              model: root.currentModifiers
              ModifierChip { required property string modelData; label: modelData }
            }

            Rectangle {
              visible: root.modifierBranches.length > 0
              Layout.preferredWidth: 1
              Layout.preferredHeight: Style.space(20)
              color: Util.alpha(Color.popups.border, 0.65)
            }

            Text {
              visible: root.modifierBranches.length > 0
              text: "Available"
              color: Util.alpha(Color.popups.text, 0.52)
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

          Rectangle {
            id: topCloseControl

            visible: root.pinned
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(28)
            radius: Style.space(6)
            color: topCloseMouse.containsMouse ? Util.alpha(Color.urgent, 0.1) : "transparent"

            Text {
              anchors.centerIn: parent
              text: "To exit: [SUPER CTRL K]"
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "x"
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.space(20)
              font.bold: true
            }

            MouseArea {
              id: topCloseMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePinned("")
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Util.alpha(Color.popups.border, 0.5)
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

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Util.alpha(Color.popups.border, 0.5)
          }

          RowLayout {
            id: footerSections
            Layout.fillWidth: true
            spacing: Style.space(18)

            ColumnLayout {
              id: coachPane
              readonly property var apps: root.searchedAppsSummary().slice(0, 3)
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.alignment: Qt.AlignTop
              spacing: Style.space(6)

              Text {
                text: "Coach"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                visible: coachPane.apps.length === 0
                text: "No apps selected after search yet"
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: coachPane.apps
                RowLayout {
                  required property var modelData
                  Layout.fillWidth: true

                  Text {
                    Layout.fillWidth: true
                    text: String(parent.modelData.name || parent.modelData.desktopId || "")
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "×" + Number(parent.modelData.count || 0)
                    color: Util.alpha(Color.accent, 0.82)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            Rectangle {
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              color: Util.alpha(Color.popups.border, 0.5)
            }

            ColumnLayout {
              id: dataPane
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              Layout.alignment: Qt.AlignTop
              spacing: Style.space(5)

              Text {
                text: "Data"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                text: root.observedBindingCount() + " bindings observed · " + root.totalAttemptCount() + " attempts"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                text: root.searchedAppsSummary().length + " searched apps · " + root.totalAppSelectionCount() + " selections"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Item {
                Layout.fillHeight: true
              }

              Rectangle {
                id: deleteStatsControl
                property bool hovered: false
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                radius: Math.min(Style.cornerRadius, Style.space(5))
                color: hovered ? Util.alpha(Color.urgent, 0.13) : "transparent"

                RowLayout {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(6)
                  spacing: Style.space(8)

                  Text {
                    text: "\uf1f8"
                    color: !root.pinned
                      ? Util.alpha(Color.popups.text, 0.45)
                      : (deleteStatsControl.hovered ? Color.urgent : Color.popups.text)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Delete data"
                    color: !root.pinned
                      ? Util.alpha(Color.popups.text, 0.45)
                      : (deleteStatsControl.hovered ? Color.urgent : Color.popups.text)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: root.pinned
                  hoverEnabled: true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onContainsMouseChanged: deleteStatsControl.hovered = containsMouse
                  onClicked: root.resetStats()
                }
              }
            }

            Rectangle {
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              color: Util.alpha(Color.popups.border, 0.5)
            }

            ColumnLayout {
              id: settingsPane
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              Layout.alignment: Qt.AlignTop
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "Settings"
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Keycap {
                  label: "SUPER CTRL K"
                }

                Text {
                  text: "to open settings"
                  color: Util.alpha(Color.popups.text, 0.62)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                spacing: Style.space(10)

                Text {
                  Layout.fillWidth: true
                  text: "Collect stats"
                  color: root.pinned ? Color.popups.text : Util.alpha(Color.popups.text, 0.45)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                ToggleSwitch {
                  checked: root.measurementEnabled
                  interactive: root.pinned
                  foreground: Color.popups.text
                  accent: Color.accent
                  trackHeight: Style.space(18)
                  onToggled: root.setMeasurementEnabled(!root.measurementEnabled)
                }
              }
            }
          }
        }
      }
    }
  }
}
